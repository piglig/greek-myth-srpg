package sim

import (
	"fmt"
	"time"

	"srpg/bots"
	"srpg/rules"
)

// 记录次数的机制事件。
var mechanics = []rules.EventType{rules.EvThrow, rules.EvMark, rules.EvIntercept,
	rules.EvLeap, rules.EvKnockback, rules.EvBroken, rules.EvAssist, rules.EvEdge, rules.EvCollision,
	rules.EvPush, rules.EvSealed, rules.EvRetreat, rules.EvEmerge}

var isMechanic = func() (set [64]bool) {
	for _, t := range mechanics {
		set[t] = true
	}
	return
}()

// Hook 在每批事件产生后被调用（跟踪、回放）。actor 是行动的单位，阶段切换时为 ""。
type Hook func(s *rules.BattleState, events []rules.Event, actor string)

// DefaultMaxRounds 是超时判负的回合上限。
const DefaultMaxRounds = 30

// RunBattle 用种子 seed 打完一场战斗，返回指标记录。
// picks 原样写进记录；为空时战斗用表里的默认加点。maxRounds <= 0 表示用默认上限。
func RunBattle(data *rules.Data, battleID string, picks map[string][]string, prof bots.Profile,
	seed int, maxRounds int, hook Hook) (*Row, error) {
	return new(Runner).RunBattle(data, battleID, picks, prof, seed, maxRounds, hook)
}

// Runner 连续打很多场战斗时复用搜索用的内存。一个 Runner 只能在一个 goroutine 里用。
type Runner struct {
	bot *bots.Bot
	// Muster 不为 nil 时，每场战斗都按它开局（带上队友、装备、物品、圣物），不再只看 picks。
	Muster *rules.Muster
	// Kit 是这套开局的名字，写进每一行记录。
	Kit string
}

// RunBattle 与包级的 RunBattle 相同，结果也完全相同。
func (r *Runner) RunBattle(data *rules.Data, battleID string, picks map[string][]string, prof bots.Profile,
	seed int, maxRounds int, hook Hook) (*Row, error) {
	t0 := time.Now()
	if maxRounds <= 0 {
		maxRounds = DefaultMaxRounds
	}
	var s *rules.BattleState
	var err error
	if r.Muster != nil {
		picks = r.Muster.Picks
		s, err = data.Muster(battleID, *r.Muster)
	} else {
		s, err = data.Build(battleID, picks)
	}
	if err != nil {
		return nil, err
	}
	rules.StartBattle(s)
	rng := rules.NewRNG(int64(seed))
	if r.bot == nil {
		r.bot = bots.New(prof)
	} else {
		r.bot.Reset(prof)
	}
	bot := r.bot
	c := newCollector(s, battleID, picks, prof, seed, hook)
	c.row.Kit = r.Kit

	result := ""
	for result == "" {
		for _, step := range bot.PlayTurn(s, rng) {
			c.collect(step.Events, step.Unit)
		}
		if result = outcome(s); result != "" {
			break
		}
		c.collect(rules.EndPhase(s), "")
		for _, e := range s.Living(rules.TeamEnemy) {
			for guard := 0; e.Alive && !e.HasActed && guard < 4; guard++ {
				p := rules.PlanFor(s, e)
				if p.HasMove {
					c.collect(rules.Perform(s, rules.Move(e.ID, p.MoveTo)).Events, e.ID)
				}
				o := rules.Perform(s, p.Action)
				if !o.OK {
					o = rules.Perform(s, rules.Wait(e.ID))
				}
				c.collect(o.Events, e.ID)
				if !rules.FinishActivation(s, e) {
					break
				}
			}
			if result = outcome(s); result != "" {
				break
			}
		}
		if result != "" {
			break
		}
		c.collect(rules.EndPhase(s), "")
		result = outcome(s)
		if result == "" && s.Round > maxRounds {
			result = "timeout"
		}
	}

	m := c.row
	m.Result = result
	m.Win = result == "win"
	m.Rounds = s.Round
	hp, maxHP := 0, 0
	for _, u := range s.Units {
		rec := m.Units[u.ID]
		rec.HP = 0
		if u.Alive {
			rec.HP = max(u.HP, 0)
		}
		rec.Alive = u.Alive
		if u.Team == rules.TeamPlayer {
			hp += rec.HP
			maxHP += u.MaxHP
		}
	}
	m.PartyHPLeft = GDFloat(float64(hp) / float64(maxHP))
	m.MS = time.Since(t0).Milliseconds()
	return m, nil
}

type collector struct {
	s    *rules.BattleState
	row  *Row
	hook Hook
}

func newCollector(s *rules.BattleState, battleID string, picks map[string][]string, prof bots.Profile,
	seed int, hook Hook) *collector {
	row := &Row{Battle: battleID, Bot: prof.Name, Seed: seed, Picks: map[string][]string{},
		BreakRounds: []int{}, Counts: map[string]int{}, DmgCells: map[string]int{},
		DmgToEnemy: map[string]int{}, DmgToPlayer: map[string]int{}, Falls: []Fall{}, Kills: []Kill{},
		Units: map[string]*UnitRecord{}}
	for def, nodes := range picks {
		row.Picks[def] = append([]string{}, nodes...)
	}
	for _, u := range s.Units {
		team := "enemy"
		if u.Team == rules.TeamPlayer {
			team = "player"
		}
		row.Units[u.ID] = &UnitRecord{Def: u.DefID, Team: team, MaxHP: u.MaxHP}
	}
	for _, t := range mechanics {
		row.Counts[t.String()] = 0
	}
	for _, k := range []string{"fall_enemy", "fall_enemy_levels", "fall_player", "ko_enemy", "ko_player"} {
		row.Counts[k] = 0
	}
	return &collector{s: s, row: row, hook: hook}
}

func xy(c rules.Cell) [2]int { return [2]int{c.X, c.Y} }

// countUse 记一笔我方用营地里带来的东西：物品、治疗、点火、圣物主动、神力招式。
func (c *collector) countUse(e *rules.Event) {
	m := c.row
	switch e.Type {
	case rules.EvIgnite:
		m.Counts["ignite"]++
		return
	case rules.EvStatus:
		// 给自己上的状态没有出手的事件，按状态名认。
		switch e.Status {
		case "impervious_hide":
			m.Counts["relic"]++
		case "thunder_body":
			m.Counts["power"]++
		}
		return
	case rules.EvSupport:
		m.Counts["support"]++
		return
	case rules.EvHeal, rules.EvAttack, rules.EvArea, rules.EvWard:
	default:
		return
	}
	u := c.s.Unit(e.Unit)
	if u == nil || u.Team != rules.TeamPlayer {
		return
	}
	if e.Type == rules.EvHeal {
		m.Counts["heal"]++
	}
	sk := u.Skill(e.Skill)
	switch {
	case len(e.Skill) > 5 && e.Skill[:5] == "item_":
		m.Counts["item"]++
	case sk != nil && sk.Relic:
		m.Counts["relic"]++
	case sk != nil && (sk.Blast > 0 || sk.Blink > 0 || sk.AreaShield > 0 || sk.ID == "thunder_bolt"):
		m.Counts["power"]++
	}
}

func (c *collector) collect(events []rules.Event, actor string) {
	s, m := c.s, c.row
	if c.hook != nil {
		c.hook(s, events, actor)
	}
	if len(events) == 0 {
		return
	}
	// 同一批事件里：坠落的起点是被击退前的位置
	var lastSource map[string]string
	var pushedFrom map[string]rules.Cell
	for i := range events {
		e := &events[i]
		switch e.Type {
		case rules.EvKnockback:
			if pushedFrom == nil {
				pushedFrom = map[string]rules.Cell{}
			}
			pushedFrom[e.Target] = e.From
		}
	}
	for i := range events {
		e := &events[i]
		if e.Type == rules.EvDamage {
			if lastSource == nil {
				lastSource = map[string]string{}
			}
			lastSource[e.Target] = e.Source
		}
		if isMechanic[e.Type] {
			m.Counts[e.Type.String()]++
		}
		if m.Kit != "" {
			// 带着出战配置时，另记我方用了几次药、点了几次火、用了几次圣物和神力。
			c.countUse(e)
		}
		switch e.Type {
		case rules.EvDamage:
			target := s.Unit(e.Target)
			src, amt := e.Source, e.Amount
			if target.Team == rules.TeamEnemy {
				m.DmgToEnemy[src] += amt
			} else {
				m.DmgToPlayer[src] += amt
			}
			m.Units[target.ID].Taken += amt
			if target.Team == rules.TeamPlayer {
				m.DmgCells[fmt.Sprintf("%d,%d", target.Pos.X, target.Pos.Y)] += amt
			}
			by := actor
			if by != "" && s.Unit(by).Team != target.Team {
				m.Units[by].Dealt += amt
			}
		case rules.EvBroken:
			m.BreakRounds = append(m.BreakRounds, s.Round)
		case rules.EvRetreat:
			if m.Phase2Round == 0 {
				m.Phase2Round = s.Round
			}
		case rules.EvFall:
			t := s.Unit(e.Target)
			if t.Team == rules.TeamEnemy {
				from, ok := pushedFrom[e.Target]
				if !ok {
					from = t.Pos
				}
				m.Falls = append(m.Falls, Fall{Def: t.DefID, Levels: e.Levels, Round: s.Round, From: xy(from), To: xy(t.Pos)})
				m.Counts["fall_enemy"]++
				m.Counts["fall_enemy_levels"] += e.Levels
			} else {
				m.Counts["fall_player"]++
			}
		case rules.EvKO:
			victim := s.Unit(e.Target)
			if victim.Team != rules.TeamEnemy {
				m.Counts["ko_player"]++
				break
			}
			m.Counts["ko_enemy"]++
			src, ok := lastSource[victim.ID]
			if !ok {
				src = "edge"
			}
			by := actor
			byDef := ""
			if by != "" {
				byDef = s.Unit(by).DefID
			}
			m.Kills = append(m.Kills, Kill{Def: victim.DefID, By: byDef, Source: src, Round: s.Round, Pos: xy(victim.Pos)})
		}
	}
}

func outcome(s *rules.BattleState) string {
	return s.Outcome()
}
