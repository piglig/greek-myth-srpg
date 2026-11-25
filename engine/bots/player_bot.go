package bots

import (
	"fmt"
	"math"

	"srpg/rules"
)

// Profile 是机器人的水平设定。
//
//	novice  —— 按出场顺序一次只看一个单位，对方案分数做高温 softmax 抽样；不会标记
//	casual  —— 同样一次只看一个单位，但多半挑得出最好的那个方案，也会标记：打过几关、
//	           不做全盘推演的普通玩家
//	skilled —— 对整个我方回合做束搜索（行动顺序和每个单位的方案），带一点随种子变化的噪声
type Profile struct {
	Name        string
	Search      string  // "greedy" | "beam"
	Temperature float64 // greedy：softmax 温度
	Beam        int     // beam：束宽
	PerUnit     int     // 每个单位精确评估的方案数
	Noise       float64 // beam：分数噪声幅度
	UseMark     bool
	Foresee     bool // beam：最后几种走法各推演一遍对面的回合再选
	Weights     Weights
}

// ProfileNames 列出所有机器人。
func ProfileNames() []string { return []string{"novice", "casual", "skilled"} }

// ProfileByName 返回指定名字的机器人设定。
func ProfileByName(name string) (Profile, error) {
	w := DefaultWeights()
	switch name {
	case "novice":
		w.Danger = 2.0
		return Profile{Name: name, Search: "greedy", Temperature: 3.0, PerUnit: 6, Weights: w}, nil
	case "casual":
		return Profile{Name: name, Search: "greedy", Temperature: 0.8, PerUnit: 6, UseMark: true, Weights: w}, nil
	case "skilled":
		return Profile{Name: name, Search: "beam", Beam: 6, PerUnit: 8, Noise: 0.3, UseMark: true, Foresee: true,
			Weights: w}, nil
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

	live  bool                 // 正在真正落子（不是搜索里的试走）
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
		b.live = true
		b.ApplyPlan(s, u.ID, sc[pick].plan, &step.Events)
		b.live = false
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
	// 留到最后的几种走法，各自让对面走完它的回合再比：人在落子前会想一步"我这样走完，
	// 它们会怎么打"——谁会被围、要保护的人撑不撑得住、是不是该先杀掉那个够得着的。
	best := 0
	if b.Prof.Foresee && len(beams) > 1 {
		top := math.Inf(-1)
		for i := range beams {
			if beams[i].state == nil {
				continue
			}
			after := b.afterReply(beams[i].state)
			if after > top {
				top, best = after, i
			}
		}
	}
	var steps []*planStep
	for st := beams[best].last; st != nil; st = st.prev {
		steps = append(steps, st)
	}
	played := []Step{}
	for i := len(steps) - 1; i >= 0; i-- {
		st := steps[i]
		step := Step{Unit: st.unit, Events: []rules.Event{}}
		b.live = true
		b.ApplyPlan(s, st.unit, st.plan, &step.Events)
		b.live = false
		played = append(played, step)
	}
	return played
}

// afterReply 是对面按它的规则走完一个回合之后的局面分数。不改 s。
func (b *Bot) afterReply(s *rules.BattleState) float64 {
	c := b.copyState(s)
	defer func() { b.pool = append(b.pool, c) }()
	if c.Outcome() != "" {
		return b.Eval.Score(c)
	}
	rules.EndPhase(c)
	for _, e := range c.Living(rules.TeamEnemy) {
		for guard := 0; e.Alive && !e.HasActed && guard < 4; guard++ {
			p := rules.PlanFor(c, e)
			if p.HasMove {
				rules.Perform(c, rules.Move(e.ID, p.MoveTo))
			}
			if o := rules.Perform(c, p.Action); !o.OK {
				rules.Perform(c, rules.Wait(e.ID))
			}
			if !rules.FinishActivation(c, e) {
				break
			}
		}
		if c.Outcome() != "" {
			break
		}
	}
	return b.Eval.Score(c)
}

func hasSupport(skills []*rules.Skill) bool {
	for _, sk := range skills {
		if sk.Support != "" {
			return true
		}
	}
	return false
}

// callSupport 在主角走完、出手之前看一眼要不要召援：把够得着的每个目标各试一遍，哪一手
// 让局面好得最多就用哪一手；都不值就留着。只在真正落子时做，搜索打分时不做。
func (b *Bot) callSupport(s *rules.BattleState, u *rules.UnitState, ev *[]rules.Event) {
	if u.ID != "hero" || !u.Alive {
		return
	}
	for _, sk := range u.Skills {
		if sk.Support == "" || u.Cooldown(sk.ID) > 0 {
			continue
		}
		var cells []rules.Cell
		if sk.Support == "charge" {
			for _, dir := range rules.Dirs {
				cells = append(cells, u.Pos.Add(dir))
			}
		} else {
			for _, o := range s.Units {
				if o.Alive && !o.Hidden {
					cells = append(cells, o.Pos)
				}
			}
		}
		best, gain := rules.NoPos, 1.0 // 至少要好出这么多才值得用掉
		base := b.Eval.Score(s)
		pick := rules.Action{}
		try := func(act rules.Action) {
			if rules.Validate(s, act) != "" {
				return
			}
			trial := b.copyState(s)
			rules.Do(trial, act, nil)
			if d := b.Eval.Score(trial) - base; d > gain {
				best, gain, pick = act.Target, d, act
			}
			b.pool = append(b.pool, trial)
		}
		for _, c := range cells {
			if sk.Carry == 0 {
				try(rules.UseSkill(u.ID, sk.ID, c))
				continue
			}
			// 驮行：这个同伴可以放到主角周围的每一块空地，各试一遍。
			if o := s.UnitAt(c); o == nil || o.Team != u.Team {
				continue
			}
			for dy := -sk.Carry; dy <= sk.Carry; dy++ {
				for dx := -sk.Carry; dx <= sk.Carry; dx++ {
					to := rules.Cell{X: u.Pos.X + dx, Y: u.Pos.Y + dy}
					if rules.CarryLandingError(s, u, to, sk) == "" {
						try(rules.LeapSkill(u.ID, sk.ID, c, to))
					}
				}
			}
		}
		if best != rules.NoPos {
			rules.Do(s, pick, ev)
		}
	}
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
	// 召援不是这个人自己的出手（不占行动，另有时机，见 callSupport）：列方案时先拿开。
	if all := u.Skills; hasSupport(all) {
		plain := make([]*rules.Skill, 0, len(all))
		for _, sk := range all {
			if sk.Support == "" {
				plain = append(plain, sk)
			}
		}
		u.Skills = plain
		defer func() { u.Skills = all }()
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
	// 治疗和解毒的对象；给自己或身边上状态的招式；带火的招式能点的空林地（紧挨着站在林地里
	// 的敌人的那些，火下一回合就烧到他们脚下）。
	var allies []*rules.UnitState
	for _, p := range s.Units {
		if p.Alive && p.Team == rules.TeamPlayer && !p.Hidden {
			allies = append(allies, p)
		}
	}
	var mends, selfCast, kindlers []*rules.Skill
	for _, sk := range u.Skills {
		switch {
		case sk.HasLeap || sk.Blink > 0 || sk.Blast > 0:
		case sk.SelfStatus != "":
			if !u.HasStatus(sk.SelfStatus) {
				selfCast = append(selfCast, sk)
			}
		case sk.IsArea():
			selfCast = append(selfCast, sk)
		case sk.Mends() || sk.ID == "purify_arrow":
			mends = append(mends, sk)
		case rules.Kindles(sk) && sk.HasMaxRange:
			kindlers = append(kindlers, sk)
		}
	}
	var tinder []rules.Cell
	if len(kindlers) > 0 {
		for _, o := range s.Units {
			if s.StumpAt(o.Pos) == o {
				tinder = append(tinder, o.Pos)
			}
		}
		seen := map[rules.Cell]bool{}
		for _, e := range enemies {
			if s.Grid.TerrainAt(e.Pos) != rules.Forest {
				continue
			}
			for _, dir := range rules.Dirs {
				c := e.Pos.Add(dir)
				if s.Grid.InBounds(c) && s.Grid.TerrainAt(c) == rules.Forest && s.UnitAt(c) == nil && !seen[c] {
					seen[c] = true
					tinder = append(tinder, c)
				}
			}
		}
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
		for _, sk := range mends {
			for _, p := range allies {
				act := rules.UseSkill(uid, sk.ID, p.Pos)
				if rules.Validate(s, act) == "" {
					out = append(out, plan(nil, act))
				}
			}
		}
		for _, sk := range selfCast {
			act := rules.UseSkill(uid, sk.ID, d)
			if rules.Validate(s, act) == "" {
				out = append(out, plan(nil, act))
			}
		}
		for _, sk := range kindlers {
			for _, c := range tinder {
				if gap := rules.CellDistance(u, c); gap < sk.MinRange || gap > sk.MaxRange {
					continue
				}
				act := rules.UseSkill(uid, sk.ID, c)
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
		// 铜钹：站到它旁边敲响，只在真有东西会掉下来的时候。
		for i := range s.Cymbals {
			at := s.Cymbals[i].Pos
			if strike := rules.Strike(uid, at); rules.Validate(s, strike) == "" && len(rules.StrikeTargets(s, at)) > 0 {
				out = append(out, plan(nil, strike))
			}
		}
		out = append(out, plan(nil, rules.Wait(uid)))
	}
	u.Pos = start
	u.HasMoved = wasMoved
	b.Stats.Plans += len(out)

	// 瞬移的招式：只从当前位置考虑，落点挑敌人身边的格子。
	for _, sk := range u.Skills {
		if sk.Blink == 0 || u.Cooldown(sk.ID) > 0 {
			continue
		}
		tried := map[rules.Cell]bool{}
		for _, e := range enemies {
			for _, dir := range rules.Dirs {
				to := e.Pos.Add(dir)
				if tried[to] {
					continue
				}
				tried[to] = true
				act := rules.UseSkill(uid, sk.ID, to)
				if rules.Validate(s, act) == "" {
					out = append(out, Plan{Main: act})
				}
			}
		}
	}

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
	if b.live {
		b.callSupport(s, u, ev)
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
	if u.Alive {
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
