package rules

import "math"

// 确定性的敌方 AI（07-combat-rules §9.3）。
//
// 一次行动 = 可选的移动 + 一个动作。评分权重从高到低：
//   击倒（+1000）> 造成的伤害（×10，包括击退带来的坠落 / 碰撞）
//   > 目标落单（+15）> 目标防御低（每点 −2）> 少走路（每步 −0.1）。
// 够不着任何人时，沿真实最短路走向最值得打的目标（会绕悬崖和坡道），而不是直线最近的那个。
// 平分时保留先遇到的候选：锚点先行后列，然后是技能顺序和单位顺序。

const (
	aiKOScore          = 1000.0
	aiDamageWeight     = 10.0
	aiIsolatedBonus    = 15.0
	aiDefenseWeight    = 2.0
	aiStepCost         = 0.1
	aiApproachIsolated = 4.0  // 选择走向谁时，落单目标的路程折扣
	aiFearScore        = 14.0 // 范围控制技能（咆哮）每罩住一个对手的得分
)

// Plan 是敌方一次行动的计划：可选的移动加一个动作。
type Plan struct {
	HasMove bool
	MoveTo  Cell
	Action  Action
}

// PlanFor 为单位 u 规划一次行动。不修改 s。
func PlanFor(s *BattleState, u *UnitState) Plan {
	sim := asActing(s, u)
	su := sim.Unit(u.ID)

	if su.DefID == "centaur" {
		if p, ok := feastLane(sim, su); ok {
			return p
		}
	}
	if lair, ok := CaveAction(sim, su); ok {
		return Plan{Action: lair}
	}
	if su.Hidden {
		return Plan{Action: Wait(su.ID)}
	}

	var reach *Reach
	anchors := []Cell{su.Pos}
	if !su.HasMoved {
		reach = Reachable(sim, su, -1)
		anchors = reach.Dests()
	}
	costOf := func(anchor Cell) float64 {
		if reach == nil {
			return 0
		}
		return float64(reach.Cost(anchor))
	}

	var best Plan
	found := false
	bestScore := math.Inf(-1)
	home := su.Pos
	wasMoved := su.HasMoved
	for _, anchor := range anchors {
		// 原地校验；只有确实打得到的攻击才复制状态去试
		su.Pos = anchor
		if su.DefID == "centaur" && reach != nil {
			su.chargeDir = straightRun(home, reach.PathTo(anchor))
		}
		su.HasMoved = true
		for _, sk := range su.Skills {
			if sk.IsArea() {
				roar := UseSkill(su.ID, sk.ID, anchor)
				if Validate(sim, roar) == "" {
					caught := 0
					for _, t := range AreaTargets(sim, su, sk) {
						if sk.AreaStatus == "" || (!t.HasStatus("control_immune") && !t.HasStatus(sk.AreaStatus)) {
							caught++
						}
					}
					fear := float64(float64(caught)*aiFearScore) - float64(costOf(anchor)*aiStepCost)
					if caught > 0 && fear > bestScore {
						bestScore = fear
						best, found = Plan{HasMove: true, MoveTo: anchor, Action: roar}, true
					}
				}
				continue
			}
			if sk.HasLeap {
				continue // 跳跃本身就是移动：只从起点考虑，见下面
			}
			for _, t := range sim.Units {
				if !isOpponent(su, t) {
					continue
				}
				act := UseSkill(su.ID, sk.ID, t.Pos)
				if Validate(sim, act) != "" {
					continue
				}
				o := Preview(sim, act)
				score := ScoreAttack(sim, o.Events, t) - float64(costOf(anchor)*aiStepCost)
				if score > bestScore {
					bestScore = score
					best, found = Plan{HasMove: true, MoveTo: anchor, Action: act}, true
				}
			}
		}
	}
	su.Pos = home
	su.HasMoved = wasMoved
	if !wasMoved {
		for _, sk := range su.Skills {
			if !sk.HasLeap || su.Cooldown(sk.ID) > 0 {
				continue
			}
			span := sk.Leap
			for dy := -span; dy <= span; dy++ {
				for dx := -span; dx <= span; dx++ {
					to := Cell{home.X + dx, home.Y + dy}
					if LeapLandingError(sim, su, to, sk) != "" {
						continue
					}
					for _, t := range sim.Units {
						if !isOpponent(su, t) {
							continue
						}
						if FootprintDistance(su, to, t) > sk.MaxRange {
							continue
						}
						act := LeapSkill(su.ID, sk.ID, t.Pos, to)
						if Validate(sim, act) != "" {
							continue
						}
						score := ScoreAttack(sim, Preview(sim, act).Events, t) + 0.5 // 能扑就扑，不走过去
						if score > bestScore {
							bestScore = score
							best, found = Plan{HasMove: true, MoveTo: home, Action: act}, true
						}
					}
				}
			}
		}
	}
	if found {
		if best.MoveTo == su.Pos {
			best.HasMove = false
		}
		return best
	}

	out := Plan{Action: Wait(su.ID)}
	if !su.HasMoved {
		if goal := ApproachStep(sim, su); goal != su.Pos {
			out.HasMove, out.MoveTo = true, goal
		}
	}
	return out
}

// CaveAction 是洞穴首领的巢穴行为（09-chapter-1 的 1-5 第二阶段）。没有可做的返回 false。
//
//	躲在洞里        -> 从离最软的我方单位最近的开放入口冲出
//	生命 <= 触发线  -> 自己的阶段一开始，如果这回合没有冲出来过，就退回洞里
func CaveAction(s *BattleState, u *UnitState) (Action, bool) {
	if s.Cave == nil || s.Cave.Boss != u.ID {
		return Action{}, false
	}
	if u.Hidden {
		entrance := CaveEntrance(s, u)
		if entrance == "" {
			return Action{}, false
		}
		return Emerge(u.ID, entrance), true
	}
	if u.HP > s.Cave.TriggerHP || u.HasActed || u.HasMoved {
		return Action{}, false
	}
	if u.ActionsLeft != u.ActionsPerTurn || s.openEntranceCount() == 0 {
		return Action{}, false
	}
	return Simple(ActRetreat, u.ID), true
}

// CaveEntrance 是首领下次要用的入口：离防御最低的我方单位最近的开放入口（平局按入口顺序）。
func CaveEntrance(s *BattleState, u *UnitState) string {
	var prey *UnitState
	for _, t := range s.Units {
		if isOpponent(u, t) && (prey == nil || t.Defense < prey.Defense) {
			prey = t
		}
	}
	best := ""
	bestD := 1 << 30
	for i := range s.Cave.Entrances {
		e := &s.Cave.Entrances[i]
		if e.Sealed {
			continue
		}
		d := 0
		if prey != nil {
			d = abs(e.Anchor.X-prey.Pos.X) + abs(e.Anchor.Y-prey.Pos.Y)
		}
		if d < bestD {
			bestD = d
			best = e.ID
		}
	}
	return best
}

// ScoreAttack 给一次攻击的结果打分。伤害算上目标因此损失的一切（命中、撞击、坠落），
// 所以把人推下悬崖的分数很高。
func ScoreAttack(s *BattleState, events []Event, t *UnitState) float64 {
	dmg := 0
	ko := false
	for i := range events {
		e := &events[i]
		if e.Type == EvDamage && e.Target == t.ID {
			dmg += e.Amount
		} else if e.Type == EvKO && e.Target == t.ID {
			ko = true
		}
	}
	score := float64(float64(dmg)*aiDamageWeight) - float64(float64(t.Defense)*aiDefenseWeight)
	if ko {
		score += aiKOScore
	}
	if IsIsolated(s, t) {
		score += aiIsolatedBonus
	}
	return score
}

// ApproachStep 是沿真实最短路走向最值得接战的对手时，这回合能停到的最远一格。
func ApproachStep(s *BattleState, u *UnitState) Cell {
	full := Reachable(s, u, 999)
	goal := NoPos
	goalVal := math.Inf(1)
	for _, anchor := range full.Dests() {
		for _, t := range s.Units {
			if !isOpponent(u, t) || FootprintDistance(u, anchor, t) != 1 {
				continue
			}
			val := float64(full.Cost(anchor)) + float64(float64(t.Defense)*0.5)
			if IsIsolated(s, t) {
				val -= aiApproachIsolated
			}
			if val < goalVal {
				goalVal = val
				goal = anchor
			}
		}
	}
	if goal == NoPos {
		return u.Pos
	}
	dests := Reachable(s, u, -1)
	step := u.Pos
	for _, cell := range full.PathTo(goal) {
		if dests.CanStop(cell) {
			step = cell
		}
	}
	return step
}

func IsIsolated(s *BattleState, t *UnitState) bool {
	for _, ally := range s.Units {
		if ally.Alive && ally.Team == t.Team && ally != t && Distance(ally, t) == 1 {
			return false
		}
	}
	return true
}

// Simulate 在副本上执行一次计划，返回计划和事件（用于意图预览）。
func Simulate(s *BattleState, u *UnitState) (Plan, []Event) {
	sim := asActing(s, u)
	p := PlanFor(sim, sim.Unit(u.ID))
	events := []Event{}
	if p.HasMove {
		Do(sim, Move(u.ID, p.MoveTo), &events)
	}
	Do(sim, p.Action, &events)
	return p, events
}

// ThreatMask 标出这个单位下次行动（移动 + 任意技能）可能打到的格子，不考虑视线。
// mask 按格子下标（y*宽+x）置位，长度不够会重新分配；返回填好的 mask。
func ThreatMask(s *BattleState, u *UnitState, mask []uint64) []uint64 {
	g := s.Grid
	words := (g.Width*g.Depth + 63) / 64
	if cap(mask) < words {
		mask = make([]uint64, words)
	}
	mask = mask[:words]
	clear(mask)
	// 可达范围与“是否已经移动过”、当前是谁的阶段都无关，所以不用像原版那样先复制状态
	for _, anchor := range Reachable(s, u, -1).Dests() {
		for _, sk := range u.Skills {
			minR := 0
			if sk.HasMinRange {
				minR = sk.MinRange
			}
			maxR := 1
			if sk.HasMaxRange {
				maxR = sk.MaxRange
			} else if sk.HasRadius {
				maxR = sk.Radius
			}
			maxR += sk.Leap
			for fy := 0; fy < u.Size; fy++ {
				for fx := 0; fx < u.Size; fx++ {
					for dy := -maxR; dy <= maxR; dy++ {
						y := anchor.Y + fy + dy
						if y < 0 || y >= g.Depth {
							continue
						}
						for dx := -maxR; dx <= maxR; dx++ {
							dist := abs(dx) + abs(dy)
							if dist < minR || dist > maxR || (sk.Line && dx != 0 && dy != 0) {
								continue
							}
							x := anchor.X + fx + dx
							if x < 0 || x >= g.Width {
								continue
							}
							i := y*g.Width + x
							mask[i>>6] |= 1 << (i & 63)
						}
					}
				}
			}
		}
	}
	return mask
}

// ThreatCells 以格子列表的形式返回 ThreatMask（先行后列）。
func ThreatCells(s *BattleState, u *UnitState) []Cell {
	mask := ThreatMask(s, u, nil)
	var out []Cell
	for i := 0; i < s.Grid.Width*s.Grid.Depth; i++ {
		if mask[i>>6]&(1<<(i&63)) != 0 {
			out = append(out, Cell{i % s.Grid.Width, i / s.Grid.Width})
		}
	}
	return out
}

// 返回一个副本，其中 u 现在可以行动（轮到它的阶段；不是它的回合就重置行动标记）。
func asActing(s *BattleState, u *UnitState) *BattleState {
	sim := s.Copy()
	own := PhasePlayer
	if u.Team == TeamEnemy {
		own = PhaseEnemy
	}
	if sim.Phase != own {
		sim.Phase = own
		su := sim.Unit(u.ID)
		su.HasMoved = false
		su.HasActed = false
	}
	return sim
}

func kills(o Outcome, targetID string) bool {
	for i := range o.Events {
		if o.Events[i].Type == EvKO && o.Events[i].Target == targetID {
			return true
		}
	}
	return false
}

// At the end of its activation a guarding enemy watches the nearest opponent.
func guardFacing(s *BattleState, u *UnitState) Cell {
	facing := u.Facing
	best := math.MaxInt
	for _, target := range s.Units {
		if !isOpponent(u, target) {
			continue
		}
		distance := FootprintDistance(u, u.Pos, target)
		direction := dirToward(u, target)
		if distance < best || (distance == best && direction == u.Facing) {
			best, facing = distance, direction
		}
	}
	return facing
}

func isOpponent(u, o *UnitState) bool {
	return o.Alive && o.Team != u.Team && o.Team != TeamNeutral && !o.Hidden
}
