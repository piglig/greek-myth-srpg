package bots

import (
	"fmt"
	"math"

	"srpg/rules"
)

// Profile 是机器人的水平设定。
//
//	novice  —— 按出场顺序一次只看一个单位，对方案分数做高温 softmax 抽样；不会标记，也不会擒抱
//	skilled —— 对整个我方回合做束搜索（行动顺序和每个单位的方案），带一点随种子变化的噪声
type Profile struct {
	Name        string
	Search      string  // "greedy" | "beam"
	Temperature float64 // greedy：softmax 温度
	Beam        int     // beam：束宽
	PerUnit     int     // 每个单位精确评估的方案数
	Noise       float64 // beam：分数噪声幅度
	UseMark     bool
	UseGrapple  bool
	Weights     Weights
}

// ProfileNames 列出所有机器人。
func ProfileNames() []string { return []string{"novice", "skilled"} }

// ProfileByName 返回指定名字的机器人设定。
func ProfileByName(name string) (Profile, error) {
	w := DefaultWeights()
	switch name {
	case "novice":
		w.Danger = 2.0
		return Profile{Name: name, Search: "greedy", Temperature: 3.0, PerUnit: 6, Weights: w}, nil
	case "skilled":
		return Profile{Name: name, Search: "beam", Beam: 6, PerUnit: 8, Noise: 0.3, UseMark: true,
			UseGrapple: true, Weights: w}, nil
	}
	return Profile{}, fmt.Errorf("没有这个机器人: %s（可选 %v）", name, ProfileNames())
}

// Plan 是一个单位的方案：可选的移动、可选的标记，再加一个主行动。
// 执行时还会替它做两个顺手的决定：游击的奖励移动（评估最好的落点）和转身面向最近的敌人。
type Plan struct {
	HasMove bool
	Move    rules.Cell
	HasMark bool
	Mark    rules.Cell
	Main    rules.Action
}

// Step 是机器人实际执行的一步。
type Step struct {
	Unit   string
	Events []rules.Event
}

// Stats 是搜索计数（性能分析用）。
type Stats struct {
	ScoredCalls, MemoHits, Plans, Applied int
}

type scored struct {
	plan  Plan
	state *rules.BattleState // 执行方案之后的副本；粗评的原地等待方案没有
	score float64
}

// 束搜索里的一步；沿 prev 往回走就是这个分支到目前为止的全部步骤。
type planStep struct {
	unit string
	plan Plan
	prev *planStep
}

type beamNode struct {
	state *rules.BattleState
	last  *planStep
	score float64
}

// Bot 是一场战斗里的我方机器人。
type Bot struct {
	Prof  Profile
	Eval  *Evaluator
	Stats Stats

	memo map[string][]scored // 局面签名 + 单位 id -> 评过分的方案，只在一个我方回合内有效
	key  []byte

	pool  []*rules.BattleState // 用完的局面副本，留着复用内存
	rough []scored
	plans []Plan
}

// 取一份 s 的副本（优先复用回收的）。
func (b *Bot) copyState(s *rules.BattleState) *rules.BattleState {
	if n := len(b.pool); n > 0 {
		dst := b.pool[n-1]
		b.pool = b.pool[:n-1]
		return s.CopyInto(dst)
	}
	return s.Copy()
}

// 归还一批不再被任何地方引用的副本。
func (b *Bot) release(list []scored) {
	for i := range list {
		if list[i].state != nil {
			b.pool = append(b.pool, list[i].state)
			list[i].state = nil
		}
	}
}

func New(prof Profile) *Bot {
	return &Bot{Prof: prof, Eval: NewEvaluator(prof.Weights), memo: map[string][]scored{}}
}

// Reset 让这个 Bot 可以去打下一场战斗（换不换设定都行），留下已经分配的内存继续用。
func (b *Bot) Reset(prof Profile) {
	for _, sc := range b.memo {
		b.release(sc)
	}
	clear(b.memo)
	b.Prof = prof
	b.Eval.W = prof.Weights
	b.Eval.BeginTurn()
	b.Stats = Stats{}
}

// PlayTurn 在 s 上打完整个我方阶段，按顺序返回每一步的事件。
func (b *Bot) PlayTurn(s *rules.BattleState, rng *rules.RNG) []Step {
	b.Eval.BeginTurn()
	for _, sc := range b.memo {
		b.release(sc) // 上一回合搜索留下的副本已经没人用了
	}
	clear(b.memo)
	if b.Prof.Search == "beam" {
		return b.playBeam(s, rng)
	}
	return b.playGreedy(s, rng)
}

// --- 搜索 ------------------------------------------------------------------------

func (b *Bot) playGreedy(s *rules.BattleState, rng *rules.RNG) []Step {
	played := []Step{}
	for _, u := range s.Living(rules.TeamPlayer) {
		if !u.Alive || u.HasActed || u.Hidden || (u.DefID == "refugee" || u.ID == "wounded_chiron") {
			continue
		}
		sc := b.scoredPlans(s, u)
		if len(sc) == 0 {
			continue
		}
		pick := softmaxPick(sc, b.Prof.Temperature, rng)
		step := Step{Unit: u.ID, Events: []rules.Event{}}
		b.ApplyPlan(s, u.ID, sc[pick].plan, &step.Events)
		played = append(played, step)
		b.release(sc)
	}
	return played
}

func (b *Bot) playBeam(s *rules.BattleState, rng *rules.RNG) []Step {
	beams := []beamNode{{state: s.Copy(), score: b.Eval.Score(s)}}
	width, perUnit, noise := b.Prof.Beam, b.Prof.PerUnit, b.Prof.Noise
	var children, spare []beamNode
	for {
		children = children[:0]
		for ni := range beams {
			node := &beams[ni]
			st := node.state
			// 不同的行动顺序常常走到同一个局面：每个局面只展开一次
			b.key = st.AppendSignature(b.key[:0])
			sigLen := len(b.key)
			for _, u := range st.Units {
				if !u.Alive || u.Team != rules.TeamPlayer || u.HasActed || u.Hidden || (u.DefID == "refugee" || u.ID == "wounded_chiron") {
					continue
				}
				b.key = append(b.key[:sigLen], u.ID...)
				b.Stats.ScoredCalls++
				sc, ok := b.memo[string(b.key)]
				if ok {
					b.Stats.MemoHits++
				} else {
					k := string(b.key)
					sc = b.scoredPlans(st, u)
					b.memo[k] = sc
				}
				for i := 0; i < min(perUnit, len(sc)); i++ {
					children = append(children, beamNode{state: sc[i].state,
						last:  &planStep{unit: u.ID, plan: sc[i].plan, prev: node.last},
						score: sc[i].score + rng.RandfRange(-noise, noise)})
				}
			}
		}
		if len(children) == 0 {
			break
		}
		rules.SortCustom(children, func(x, y beamNode) bool { return x.score > y.score })
		// 留下最好的 width 个；两块缓冲轮换着用
		spare = append(spare[:0], children[:min(width, len(children))]...)
		beams, spare = spare, beams
	}
	var steps []*planStep
	for st := beams[0].last; st != nil; st = st.prev {
		steps = append(steps, st)
	}
	played := []Step{}
	for i := len(steps) - 1; i >= 0; i-- {
		st := steps[i]
		step := Step{Unit: st.unit, Events: []rules.Event{}}
		b.ApplyPlan(s, st.unit, st.plan, &step.Events)
		played = append(played, step)
	}
	return played
}

// 返回按分数从高到低排好的方案；state 是执行方案之后的副本。
// “移动后等待”的方案先原地粗评（临时把单位挪过去，不复制状态、不跑规则）；
// 只有最好的 PerUnit 个候选才真正在副本上执行并精确重评。
func (b *Bot) scoredPlans(s *rules.BattleState, u *rules.UnitState) []scored {
	material := b.Eval.Material(s) // 不随 u 站在哪里而变
	plans := b.appendPlans(b.plans[:0], s, u)
	b.plans = plans
	rough := b.rough[:0]
	for _, plan := range plans {
		if plan.Main.Type == rules.ActWait && !plan.HasMark {
			at := u.Pos
			if plan.HasMove {
				at = plan.Move
			}
			rough = append(rough, scored{plan: plan, score: material + b.positionScore(s, u, at)})
		} else {
			c := b.copyState(s)
			b.ApplyPlan(c, u.ID, plan, nil)
			b.Stats.Applied++
			rough = append(rough, scored{plan: plan, state: c, score: b.Eval.Score(c)})
		}
	}
	b.rough = rough
	desc := func(x, y scored) bool { return x.score > y.score }
	rules.SortCustom(rough, desc)
	keep := b.Prof.PerUnit
	if keep <= 0 {
		keep = len(rough)
	}
	keep = min(keep, len(rough))
	b.release(rough[keep:]) // 落选方案的副本不会再用到
	size := keep
	if b.Prof.Search == "greedy" {
		size = len(rough)
	}
	out := make([]scored, 0, size)
	for i := 0; i < keep; i++ {
		e := rough[i]
		if e.state == nil {
			c := b.copyState(s)
			b.ApplyPlan(c, u.ID, e.plan, nil)
			e = scored{plan: e.plan, state: c, score: b.Eval.Score(c)}
		}
		out = append(out, e)
	}
	if b.Prof.Search == "greedy" {
		// 贪心抽样需要每个候选的分数，而不只是前 K 个
		for i := keep; i < len(rough); i++ {
			out = append(out, rough[i])
		}
	}
	rules.SortCustom(out, desc)
	return out
}

// u 站在 at 时的位置分，不复制状态也不跑任何规则。
// 加上 Material 才是完整的分数；只比较同一个单位的不同落点时这一项就够了。
func (b *Bot) positionScore(s *rules.BattleState, u *rules.UnitState, at rules.Cell) float64 {
	home := u.Pos
	u.Pos = at
	sc := b.Eval.Positional(s)
	u.Pos = home
	return sc
}

func softmaxPick(sc []scored, temperature float64, rng *rules.RNG) int {
	top := sc[0].score
	weights := make([]float64, len(sc))
	total := 0.0
	for i := range sc {
		w := math.Exp((sc[i].score - top) / max(temperature, 0.001))
		weights[i] = w
		total += w
	}
	r := float64(rng.Randf() * total)
	for i, w := range weights {
		r -= w
		if r <= 0 {
			return i
		}
	}
	return len(weights) - 1
}

// --- 候选方案 ----------------------------------------------------------------------

type skillReach struct {
	sk       *rules.Skill
	min, max int
}

// Plans 列出单位 u 在局面 s 下的全部候选方案。
func (b *Bot) Plans(s *rules.BattleState, u *rules.UnitState) []Plan {
	return b.appendPlans(nil, s, u)
}

func (b *Bot) appendPlans(out []Plan, s *rules.BattleState, u *rules.UnitState) []Plan {
	uid := u.ID
	if u.GrappledByID != "" {
		out = append(out, Plan{Main: rules.Simple(rules.ActStruggle, uid)})
		for _, sk := range u.Skills {
			act := rules.UseSkill(uid, sk.ID, s.Unit(u.GrappledByID).Pos)
			if rules.Validate(s, act) == "" {
				out = append(out, Plan{Main: act})
			}
		}
		return out
	}
	if u.GrapplingID != "" {
		out = append(out, Plan{Main: rules.Simple(rules.ActReinforce, uid)}, Plan{Main: rules.Wait(uid)})
		if u.Traits.Slam {
			held := s.Unit(u.GrapplingID)
			for _, c := range ring(s, held) {
				act := rules.Slam(uid, c)
				if rules.Validate(s, act) == "" {
					out = append(out, Plan{Main: act})
				}
			}
		}
		return out
	}

	var enemies []*rules.UnitState
	for _, e := range s.Units {
		if e.Alive && e.Team == rules.TeamEnemy && !e.Hidden {
			enemies = append(enemies, e)
		}
	}
	start := u.Pos
	wasMoved := u.HasMoved
	dests := []rules.Cell{start}
	if !u.HasMoved {
		dests = rules.Reachable(s, u, -1).Dests()
	}
	canMark := b.Prof.UseMark && u.Traits.HunterMark && !u.MarkUsed
	// 每个技能的距离上下界：绝大多数（格子，敌人）组合都够不着，先用几次整数运算筛掉，
	// 再做完整校验。上界把所有加成都算进去（高处 +1、猎人标记），不会漏掉合法的方案。
	var reach []skillReach
	for _, sk := range u.Skills {
		if sk.HasLeap || !sk.HasMaxRange {
			continue
		}
		extra := 0
		if sk.Ranged {
			extra = 1 + rules.MarkRangeBonus
		}
		reach = append(reach, skillReach{sk, sk.MinRange, sk.MaxRange + extra})
	}
	dist := make([]int, len(enemies))
	for _, d := range dests {
		u.Pos = d
		u.HasMoved = wasMoved || d != start
		hasMove := d != start
		plan := func(mark *rules.Cell, main rules.Action) Plan {
			p := Plan{Main: main}
			if hasMove {
				p.HasMove, p.Move = true, d
			}
			if mark != nil {
				p.HasMark, p.Mark = true, *mark
			}
			return p
		}
		for i, e := range enemies {
			dist[i] = rules.Distance(u, e)
		}
		for _, r := range reach {
			for i, e := range enemies {
				if dist[i] < r.min || dist[i] > r.max {
					continue
				}
				act := rules.UseSkill(uid, r.sk.ID, e.Pos)
				if rules.Validate(s, act) != "" {
					continue
				}
				out = append(out, plan(nil, act))
				if canMark && !s.IsMarked(e.ID) {
					pos := e.Pos
					out = append(out, plan(&pos, act))
				}
			}
		}
		if b.Prof.UseGrapple && u.Traits.HasGrapple {
			for i, e := range enemies {
				if dist[i] != 1 {
					continue
				}
				act := rules.Grapple(uid, e.Pos)
				if rules.Validate(s, act) == "" {
					out = append(out, plan(nil, act))
				}
			}
		}
		if s.Cave != nil {
			for i := range s.Cave.Boulders {
				push := rules.PushBoulder(uid, s.Cave.Boulders[i].Pos)
				if rules.Validate(s, push) == "" {
					out = append(out, plan(nil, push))
				}
			}
		}
		out = append(out, plan(nil, rules.Wait(uid)))
	}
	u.Pos = start
	u.HasMoved = wasMoved
	b.Stats.Plans += len(out)

	// 跳跃技能：只从当前位置考虑（跳跃本身就是移动）
	if !u.HasMoved {
		for _, sk := range u.Skills {
			if !sk.HasLeap || u.Cooldown(sk.ID) > 0 {
				continue
			}
			for dy := -sk.Leap; dy <= sk.Leap; dy++ {
				for dx := -sk.Leap; dx <= sk.Leap; dx++ {
					to := rules.Cell{X: start.X + dx, Y: start.Y + dy}
					if rules.LeapLandingError(s, u, to, sk) != "" {
						continue
					}
					for _, e := range enemies {
						act := rules.LeapSkill(uid, sk.ID, e.Pos, to)
						if rules.Validate(s, act) == "" {
							out = append(out, Plan{Main: act})
						}
					}
				}
			}
		}
	}
	return out
}

// 紧贴 t 占地外圈的格子（按占地格子、再按北东南西的顺序，去重）。
func ring(s *rules.BattleState, t *rules.UnitState) []rules.Cell {
	var out []rules.Cell
	for _, f := range t.Footprint(t.Pos) {
		for _, d := range rules.Dirs {
			c := f.Add(d)
			if !s.Grid.InBounds(c) || t.Occupies(c) {
				continue
			}
			dup := false
			for _, o := range out {
				if o == c {
					dup = true
					break
				}
			}
			if !dup {
				out = append(out, c)
			}
		}
	}
	return out
}

// --- 执行方案 ----------------------------------------------------------------------

// ApplyPlan 在 s 上执行方案，事件追加到 ev（传 nil 不记录）。主行动失效时改为等待。
// 之后的两个顺手动作：最好的游击移动，然后转身面向最近的敌人。
func (b *Bot) ApplyPlan(s *rules.BattleState, uid string, plan Plan, ev *[]rules.Event) {
	u := s.Unit(uid)
	if plan.HasMove {
		rules.Do(s, rules.Move(uid, plan.Move), ev)
	}
	if plan.HasMark {
		rules.Do(s, rules.Mark(uid, plan.Mark), ev)
	}
	if rules.Do(s, plan.Main, ev) != "" {
		rules.Do(s, rules.Wait(uid), ev)
	}
	if u.Alive && u.PostMove > 0 {
		best := u.Pos
		bestScore := math.Inf(-1)
		for _, d := range rules.Reachable(s, u, u.PostMove).Dests() {
			if sc := b.positionScore(s, u, d); sc > bestScore {
				bestScore = sc
				best = d
			}
		}
		if best != u.Pos {
			rules.Do(s, rules.Move(uid, best), ev)
		}
	}
	if u.Alive && u.GrappledByID == "" && u.GrapplingID == "" {
		f := faceNearest(s, u)
		if f != u.Facing && f != (rules.Cell{}) {
			rules.Do(s, rules.Face(uid, f), ev)
		}
	}
}

func faceNearest(s *rules.BattleState, u *rules.UnitState) rules.Cell {
	var best *rules.UnitState
	bestD := 1 << 30
	for _, e := range s.Units {
		if !e.Alive || e.Team != rules.TeamEnemy {
			continue
		}
		if d := rules.Distance(u, e); d < bestD {
			bestD = d
			best = e
		}
	}
	if best == nil {
		return rules.Cell{}
	}
	bx, by := best.Center()
	ux, uy := u.Center()
	vx, vy := bx-ux, by-uy
	if math.Abs(vx) >= math.Abs(vy) {
		if vx >= 0 {
			return rules.East
		}
		return rules.West
	}
	if vy >= 0 {
		return rules.South
	}
	return rules.North
}
