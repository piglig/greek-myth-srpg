package rules

import (
	"math"
	"sort"
)

// 行动的校验、执行、预览和阶段流程（07-combat-rules §2、§7.1）。

// ActionType 是行动种类。
type ActionType uint8

const (
	ActUnknown     ActionType = iota
	ActMove                   // Unit, To
	ActUndoMove               // Unit
	ActSkill                  // Unit, Skill, Target；跳跃技能另带落点 To（HasTo）
	ActWait                   // Unit
	ActFace                   // Unit, Facing
	ActMark                   // Unit, Target
	ActPushBoulder            // Unit, Target（巨石所在的格子）
	ActRetreat                // Unit
	ActEmerge                 // Unit, Entrance
)

var actionNames = [...]string{"", "move", "undo_move", "skill", "wait", "face", "mark", "push_boulder",
	"retreat", "emerge"}

func (t ActionType) String() string { return actionNames[t] }

// Action 是一个行动。用下面的构造函数创建。
type Action struct {
	Type     ActionType
	Unit     string
	Skill    string
	Target   Cell
	To       Cell
	HasTo    bool // 技能是否带落点
	Facing   Cell
	Entrance string
}

func Move(unit string, to Cell) Action { return Action{Type: ActMove, Unit: unit, To: to} }
func Wait(unit string) Action          { return Action{Type: ActWait, Unit: unit} }
func UseSkill(unit, skill string, target Cell) Action {
	return Action{Type: ActSkill, Unit: unit, Skill: skill, Target: target}
}
func LeapSkill(unit, skill string, target, to Cell) Action {
	return Action{Type: ActSkill, Unit: unit, Skill: skill, Target: target, To: to, HasTo: true}
}
func Mark(unit string, target Cell) Action { return Action{Type: ActMark, Unit: unit, Target: target} }
func Face(unit string, facing Cell) Action { return Action{Type: ActFace, Unit: unit, Facing: facing} }
func PushBoulder(unit string, target Cell) Action {
	return Action{Type: ActPushBoulder, Unit: unit, Target: target}
}
func Emerge(unit, entrance string) Action {
	return Action{Type: ActEmerge, Unit: unit, Entrance: entrance}
}

// Simple 创建只需要单位的行动（undo_move、wait、retreat）。
func Simple(t ActionType, unit string) Action { return Action{Type: t, Unit: unit} }

// Outcome 是执行一个行动的结果。
type Outcome struct {
	OK     bool
	Error  string
	Action Action
	Events []Event
}

func isFree(t ActionType) bool {
	return t == ActFace || t == ActMark || t == ActUndoMove
}

// Preview 在副本上执行同一段代码，所以界面上预览到的就是将要发生的。
func Preview(s *BattleState, a Action) Outcome {
	return Perform(s.Copy(), a)
}

// Perform 校验并执行行动，返回产生的事件。
func Perform(s *BattleState, a Action) Outcome {
	o := Outcome{Action: a, Events: []Event{}}
	o.Error = Do(s, a, &o.Events)
	o.OK = o.Error == ""
	return o
}

// Do 校验并执行行动，事件追加到 ev（传 nil 则不记录事件）。返回 "" 表示成功，否则是出错原因。
func Do(s *BattleState, a Action, ev *[]Event) string {
	if err := Validate(s, a); err != "" {
		return err
	}
	u := s.Unit(a.Unit)
	switch a.Type {
	case ActMove:
		doMove(s, u, a.To, ev)
	case ActUndoMove:
		emit(ev, Event{Type: EvUndoMove, Unit: u.ID, From: u.Pos, To: u.undoPos})
		u.chargeDir = Cell{}
		u.Pos = u.undoPos
		u.Facing = u.undoFacing
		u.HasMoved = false
		u.undoOK = false
	case ActSkill:
		doSkill(s, u, a, ev)
	case ActWait:
		if u.Team == TeamEnemy && u.Traits.Has("turn_on_guard") && !u.Hidden {
			facing := guardFacing(s, u)
			if u.Facing != facing {
				u.Facing = facing
				emit(ev, Event{Type: EvFace, Unit: u.ID, Facing: facing})
			}
		}
		if s.Reward.Charms["olive"] == u.ID {
			u.HP = min(u.MaxHP, u.HP+4)
		}
		u.SetStatus("guard", 1)
		u.HasActed = true
		emit(ev, Event{Type: EvStatus, Target: u.ID, Status: "guard", Rounds: 1})
	case ActFace:
		u.Facing = a.Facing
		emit(ev, Event{Type: EvFace, Unit: u.ID, Facing: u.Facing})
	case ActPushBoulder:
		doPush(s, u, s.BoulderAt(a.Target), ev)
	case ActRetreat:
		doRetreat(s, u, ev)
	case ActEmerge:
		doEmerge(s, u, a.Entrance, ev)
	case ActMark:
		t := s.UnitAt(a.Target)
		s.setMark(t.ID)
		u.MarkUsed = true
		emit(ev, Event{Type: EvMark, Unit: u.ID, Target: t.ID})
	}
	if !isFree(a.Type) && a.Type != ActMove {
		u.undoOK = false
	}
	return ""
}

// --- 校验 ------------------------------------------------------------------------

// Validate 返回 "" 表示行动合法，否则是原因（英文短语，界面再翻译）。
func Validate(s *BattleState, a Action) string {
	u := s.Unit(a.Unit)
	if u == nil || !u.Alive {
		return "no such unit"
	}
	if u.ID == "wounded_chiron" {
		return "wounded ally"
	}
	if u.DefID == "refugee" {
		return "civilian follows escape route"
	}
	if !isUnitsPhase(s, u) {
		return "not this unit's phase"
	}
	t := a.Type
	needsMain := !isFree(t) && t != ActMove
	if needsMain && u.HasActed {
		return "already acted"
	}
	switch t {
	case ActMove:
		budget := u.Move
		if u.HasActed {
			if u.PostMove <= 0 {
				return "cannot move now"
			}
			budget = u.PostMove
		} else if u.HasMoved {
			return "cannot move now"
		}
		if !Reachable(s, u, budget).CanStop(a.To) {
			return "unreachable"
		}
	case ActUndoMove:
		if !u.undoOK || u.HasActed {
			return "nothing to undo"
		}
	case ActSkill:
		to := NoPos
		if a.HasTo {
			to = a.To
		}
		return validateSkill(s, u, a.Skill, a.Target, to)
	case ActFace:
		if a.Facing != North && a.Facing != East && a.Facing != South && a.Facing != West {
			return "bad facing"
		}
	case ActMark:
		if !u.Traits.HunterMark || u.MarkUsed {
			return "cannot mark"
		}
		m := s.UnitAt(a.Target)
		if m == nil || m.Team == u.Team {
			return "no enemy there"
		}
	case ActPushBoulder:
		return validatePush(s, u, a.Target)
	case ActRetreat:
		if s.Cave == nil || s.Cave.Boss != u.ID || u.Hidden {
			return "cannot retreat"
		}
		if s.openEntranceCount() == 0 {
			return "no open entrance"
		}
	case ActEmerge:
		if !u.Hidden || !s.entranceOpen(a.Entrance) {
			return "cannot emerge"
		}
	case ActWait:
	default:
		return "unknown action"
	}
	return ""
}

func validateSkill(s *BattleState, u *UnitState, skillID string, cell, to Cell) string {
	sk := u.Skill(skillID)
	if sk == nil {
		return "unknown skill"
	}
	if u.Cooldown(skillID) > 0 {
		return "on cooldown"
	}
	if sk.Item && u.Charge(skillID) <= 0 {
		return "none left"
	}
	if sk.SelfStatus != "" {
		return ""
	}
	if sk.Blink > 0 {
		return BlinkLandingError(s, u, cell, sk)
	}
	if sk.AreaShield > 0 {
		return ""
	}
	if sk.Blast > 0 {
		return validateBlast(s, u, sk, cell)
	}
	if sk.IsArea() {
		if !anyAreaTarget(s, u, sk) {
			return "no one in range"
		}
		return ""
	}
	if sk.HasLeap {
		if to == NoPos {
			return "need landing"
		}
		if err := LeapLandingError(s, u, to, sk); err != "" {
			return err
		}
		// 假设已经落在 to 上再校验这一击（原版在副本上做，这里临时挪过去再挪回来，结果相同）
		home := u.Pos
		u.Pos = to
		err := validateShot(s, u, sk, cell)
		u.Pos = home
		return err
	}
	return validateShot(s, u, sk, cell)
}

func areaHits(u, o *UnitState, sk *Skill) bool {
	return o.Alive && o.Team != u.Team && o.Team != TeamNeutral && !o.Hidden && Distance(u, o) <= sk.Radius
}

func anyAreaTarget(s *BattleState, u *UnitState, sk *Skill) bool {
	for _, o := range s.Units {
		if areaHits(u, o, sk) {
			return true
		}
	}
	return false
}

// AreaTargets 返回以使用者为中心的范围技能（如狮子的咆哮）波及的对手。
func AreaTargets(s *BattleState, u *UnitState, sk *Skill) []*UnitState {
	var out []*UnitState
	for _, o := range s.Units {
		if areaHits(u, o, sk) {
			out = append(out, o)
		}
	}
	return out
}

// LeapLandingError 检查跳跃技能的落点：leap 格以内、最多高 leap_rise 层、能站得下。
func LeapLandingError(s *BattleState, u *UnitState, to Cell, sk *Skill) string {
	if !s.FootprintInBounds(to, u.Size) {
		return "bad landing"
	}
	d := abs(to.X-u.Pos.X) + abs(to.Y-u.Pos.Y)
	if d < 1 || d > sk.Leap {
		return "bad landing"
	}
	for dy := 0; dy < u.Size; dy++ {
		for dx := 0; dx < u.Size; dx++ {
			if s.Grid.TerrainAt(Cell{to.X + dx, to.Y + dy}) == Deep {
				return "bad landing"
			}
		}
	}
	if s.firstBlocker(to, u.Size, u) != nil || s.BoulderIn(to, u.Size) {
		return "bad landing"
	}
	rise := s.StandingHeight(to, u.Size) - s.UnitHeight(u)
	if rise > sk.LeapRise || -rise > MaxDrop {
		return "bad landing"
	}
	return ""
}

func validateShot(s *BattleState, u *UnitState, sk *Skill, cell Cell) string {
	var target *UnitState
	if s.Grid.InBounds(cell) {
		target = s.UnitAt(cell)
	}
	if sk.ID == "purify_arrow" || sk.Mends() {
		if target == nil || target.Team != u.Team || (sk.ID == "purify_arrow" && target.DefID == "chiron") {
			return "need healable ally"
		}
		if vessel(target) && s.Tier() >= TierInhuman {
			return "cannot be healed"
		}
		if target.HasStatus("blighted") && sk.Heal > 0 {
			return "blighted"
		}
		if (sk.Heal == 0 && sk.ID != "purify_arrow" || target.HP == target.MaxHP) && cleanseTarget(target) == "" {
			return "unhurt ally"
		}
	} else if target == nil && Kindles(sk) && s.Grid.InBounds(cell) && s.Grid.TerrainAt(cell) == Forest {
		// 带火的招式可以直接打一格空的林地，把它点着。
		dist := CellDistance(u, cell)
		minR := sk.MinRange
		if sk.Ranged && u.Traits.CannotAttackAdjacent {
			minR = max(minR, 2)
		}
		if dist < minR || dist > sk.MaxRange {
			return "out of range"
		}
		return ""
	} else if target == nil || target.Team == u.Team {
		return "no enemy there"
	}
	ranged := sk.Ranged
	if sk.Throw && (u.Size != 1 || target.Size != 1 || target.Traits.Flying) {
		return "cannot throw that"
	}
	dist := Distance(u, target)
	minR, maxR := sk.MinRange, sk.MaxRange
	if ranged {
		if s.UnitHeight(u)-s.UnitHeight(target) >= HighGroundRangeLevel {
			maxR++
		}
		if u.Traits.HunterMark && s.IsMarked(target.ID) {
			maxR += MarkRangeBonus
		}
		if u.Traits.CannotAttackAdjacent {
			minR = max(minR, 2)
		}
	}
	if dist < minR || dist > maxR {
		return "out of range"
	}
	if sk.Line && !inLine(u, target) {
		return "not in line"
	}
	if ranged && !LineOfSight(s, u, target) {
		return "no line of sight"
	}
	return ""
}

// --- 执行 ------------------------------------------------------------------------

func doMove(s *BattleState, u *UnitState, to Cell, ev *[]Event) {
	postMove := u.HasActed // 行动后的游击移动：用掉奖励步数，不能撤销
	budget := -1
	if postMove {
		budget = u.PostMove
	}
	reach := Reachable(s, u, budget)
	if postMove {
		u.PostMove = 0
	} else {
		u.undoOK, u.undoPos, u.undoFacing = true, u.Pos, u.Facing
	}
	// 沿路每一步都转向前进的方向，所以走完后面向最后一步的方向
	if dir, ok := reach.LastStep(to); ok {
		u.Facing = dir
	}
	if ev != nil {
		emit(ev, Event{Type: EvMove, Unit: u.ID, From: u.Pos, To: to, Path: reach.PathTo(to)})
	}
	if u.DefID == "centaur" {
		u.chargeDir = straightRun(u.Pos, reach.PathTo(to))
	}
	u.Pos = to
	u.HasMoved = true
}

func cleanseTarget(target *UnitState) string {
	for _, status := range []string{"burning", "poisoned", "rooted"} {
		if target.HasStatus(status) {
			return status
		}
	}
	return ""
}

func doSkill(s *BattleState, u *UnitState, a Action, ev *[]Event) {
	sk := u.Skill(a.Skill)
	if sk.Item {
		// 用一件少一件；用完就不再出现在可用的招式里。
		left := u.Charge(sk.ID) - 1
		u.Charges = kvSet(u.Charges, sk.ID, left)
		if left <= 0 {
			defer u.dropSkill(sk.ID)
		}
	}
	defer relicUse(s, u, sk)
	if sk.SelfStatus != "" {
		u.HasActed = true
		u.SetCooldown(sk.ID, sk.Cooldown)
		u.SetStatus(sk.SelfStatus, sk.Rounds)
		emit(ev, Event{Type: EvStatus, Target: u.ID, Status: sk.SelfStatus, Rounds: sk.Rounds})
		return
	}
	if sk.Blink > 0 {
		doBlink(s, u, sk, a.Target, ev)
		return
	}
	if sk.AreaShield > 0 {
		doWard(s, u, sk, ev)
		return
	}
	if sk.Blast > 0 {
		doBlast(s, u, sk, a.Target, ev)
		return
	}
	if sk.IsArea() {
		u.HasActed = true
		if sk.Cooldown > 0 {
			u.SetCooldown(sk.ID, sk.Cooldown)
		}
		emit(ev, Event{Type: EvArea, Unit: u.ID, Skill: sk.ID})
		caught := AreaTargets(s, u, sk)
		if sk.AreaKnockback > 0 {
			// 先推远处的，近处的才有地方退。
			sort.SliceStable(caught, func(i, j int) bool { return Distance(u, caught[i]) > Distance(u, caught[j]) })
		}
		for _, o := range caught {
			if sk.AreaStatus != "" {
				AddStatus(s, o, sk.AreaStatus, sk.Rounds, ev, false)
			}
			if sk.AreaKnockback > 0 && o.Alive {
				Knockback(s, o, dirToward(u, o), sk.AreaKnockback, sk.ID, ev)
			}
		}
		return
	}
	if sk.HasLeap {
		emit(ev, Event{Type: EvLeap, Unit: u.ID, From: u.Pos, To: a.To})
		u.Pos = a.To
		u.HasMoved = true
	}
	target := s.UnitAt(a.Target)
	if sk.ID == "hydra_venom" {
		u.Facing = dirToward(u, target)
		u.HasActed = true
		u.SetCooldown(sk.ID, sk.Cooldown)
		emit(ev, Event{Type: EvAttack, Unit: u.ID, Target: target.ID, Skill: sk.ID, Relation: ComputeHit(s, u, target, 0, True, true, NoPos, false).Relation})
		if AddStatus(s, target, "poisoned", sk.Rounds, ev, false) {
			target.SetStatus("blighted", sk.Rounds)
			emit(ev, Event{Type: EvStatus, Target: target.ID, Status: "blighted", Rounds: sk.Rounds})
		}
		return
	}
	if target == nil && Kindles(sk) {
		// 打在空的林地上：只点火。
		if dx, dy := a.Target.X-u.Pos.X, a.Target.Y-u.Pos.Y; dx*dx >= dy*dy {
			u.Facing = Cell{sign(dx), 0}
			if dx == 0 {
				u.Facing = East
			}
		} else {
			u.Facing = Cell{0, sign(dy)}
		}
		u.HasActed = true
		if sk.Cooldown > 0 {
			u.SetCooldown(sk.ID, sk.Cooldown)
		}
		emit(ev, Event{Type: EvArea, Unit: u.ID, Skill: sk.ID, To: a.Target})
		s.kindle(a.Target, ev)
		return
	}
	if sk.ID == "purify_arrow" {
		u.Facing = dirToward(u, target)
		u.HasActed = true
		u.SetCooldown(sk.ID, sk.Cooldown)
		gain := 8
		if u.Traits.Has("field_medicine") && target.HP*2 < target.MaxHP {
			gain = 12
		}
		if u.Traits.Has("herb_pouch") {
			gain += 3
		}
		gain = min(gain, target.MaxHP-target.HP)
		target.HP += gain
		emit(ev, Event{Type: EvHeal, Unit: u.ID, Target: target.ID, Skill: sk.ID, Amount: gain, HP: target.HP})
		if u.Traits.Has("triage") {
			target.Shield += 4
		}
		cleanses := 1
		if u.Traits.Has("antidote") {
			cleanses++
		}
		for i := 0; i < cleanses; i++ {
			status := cleanseTarget(target)
			if status == "" {
				break
			}
			target.EraseStatus(status)
			emit(ev, Event{Type: EvStatusEnd, Target: target.ID, Status: status})
		}
		return
	}
	if sk.Mends() {
		if target != u {
			u.Facing = dirToward(u, target)
		}
		u.HasActed = true
		gain := min(sk.Heal, target.MaxHP-target.HP)
		target.HP += gain
		emit(ev, Event{Type: EvHeal, Unit: u.ID, Target: target.ID, Skill: sk.ID, Amount: gain, HP: target.HP})
		for i := 0; i < sk.Cleanse; i++ {
			status := cleanseTarget(target)
			if status == "" {
				break
			}
			target.EraseStatus(status)
			emit(ev, Event{Type: EvStatusEnd, Target: target.ID, Status: status})
		}
		return
	}
	target = interceptor(s, u, target, ev)
	ranged := sk.Ranged
	u.Facing = dirToward(u, target)
	u.HasActed = true
	if sk.Cooldown > 0 {
		u.SetCooldown(sk.ID, sk.Cooldown)
	}

	mult := sk.Mult
	if sk.ID == "weak_point" && u.Traits.Has("keen_eye") {
		mult = 1.0
	}
	hit := ComputeHit(s, u, target, mult, sk.Type, ranged, NoPos, sk.Pierce)
	emit(ev, Event{Type: EvAttack, Unit: u.ID, Target: target.ID, Skill: sk.ID, Relation: hit.Relation, Notes: hit.Notes})
	dodged := target.HasStatus("dodge")
	Deal(s, target, hit.Amount, sk.Type, sk.ID, ev, true)
	if !dodged && Kindles(sk) {
		// 目标脚下是林地就烧起来。
		for _, c := range target.Footprint(target.Pos) {
			s.kindle(c, ev)
		}
	}
	if !dodged && target.Alive {
		switch sk.ID {
		case "witch_fire", "solar_flame", "cinder_lance":
			rounds := 2
			if u.Traits.Has("long_flame") {
				rounds++
			}
			AddStatus(s, target, "burning", rounds, ev, false)
		case "pin_shot", "bind_hex":
			AddStatus(s, target, "rooted", 1, ev, false)
		}
		if sk.Status != "" {
			rounds := sk.Rounds
			if sk.ID == "frailty" && u.Traits.Has("lingering_hex") {
				rounds++
			}
			AddStatus(s, target, sk.Status, rounds, ev, false)
		}
		if vessel(u) && s.Reward.Wears("hydra_blood") && hit.Amount > 0 {
			// 蛇血：他的每一击都带毒。
			AddStatus(s, target, "poisoned", 1, ev, false)
		}
	}
	if !dodged {
		stagger := StaggerFromRelation(hit.Relation) + sk.StaggerBonus
		if sk.ID == "weak_point" && u.Traits.Has("mentor_stagger") {
			stagger += 20
		}
		if s.IsMarked(target.ID) && hit.Relation != Front {
			stagger += sk.MarkedFlankStagger
		}
		AddStagger(target, stagger, ev)
	}
	if u.Traits.Skirmish {
		u.PostMove = SkirmishMove
	}

	if target.Alive && u.Team == TeamPlayer {
		assist(s, u, target, ev)
	}
	if sk.Knockback > 0 && target.Alive && !dodged {
		distance := sk.Knockback
		if s.Reward.Charms["wrist"] == u.ID {
			distance++
		}
		Knockback(s, target, dirToward(u, target), distance, sk.ID, ev)
		if u.Traits.Has("stagger_fist") {
			AddStagger(target, StaggerFist, ev)
		}
	}
	if sk.Throw && target.Alive && !dodged {
		Throw(s, u, target, sk.ID, ev)
	}
}

// --- 洞穴与巨石（09-chapter-1 的 1-5） ------------------------------------------------

func validatePush(s *BattleState, u *UnitState, cell Cell) string {
	id := s.BoulderAt(cell)
	if id == "" {
		return "no boulder there"
	}
	if CellDistance(u, cell) != 1 {
		return "not adjacent"
	}
	b := s.Cave.Boulder(id)
	if !s.entranceOpen(b.Seals) {
		return "already sealed"
	}
	if s.openEntranceCount() <= 1 {
		return "cannot seal the last entrance"
	}
	return ""
}

// 谁推都是一次到位：一个动作按下就结算完，没有"推到一半"。
func doPush(s *BattleState, u *UnitState, id string, ev *[]Event) {
	b := s.Cave.Boulder(id)
	b.Progress = 2
	b.Placed = true
	u.HasActed = true
	emit(ev, Event{Type: EvPush, Unit: u.ID, Boulder: id, Progress: b.Progress})
	s.Cave.Entrance(b.Seals).Sealed = true
	emit(ev, Event{Type: EvSealed, Entrance: b.Seals, Boulder: id})
}

func doRetreat(s *BattleState, u *UnitState, ev *[]Event) {
	u.Hidden = true
	u.HasMoved = true
	u.HasActed = true
	u.ActionsLeft = 1 // 回合到此结束
	s.Cave.Last = "retreat"
	s.removeMark(u.ID)
	emit(ev, Event{Type: EvRetreat, Unit: u.ID})
}

// 从入口旁冲出（离入口最近的空位），扑击就绪，还剩 emerge_actions 次行动。
func doEmerge(s *BattleState, u *UnitState, entrance string, ev *[]Event) {
	want := s.Cave.Entrance(entrance).Anchor
	best := want
	bestD := 1 << 30
	for y := 0; y < s.Grid.Depth; y++ {
		for x := 0; x < s.Grid.Width; x++ {
			a := Cell{x, y}
			d := abs(a.X-want.X) + abs(a.Y-want.Y)
			if d >= bestD || !s.FootprintInBounds(a, u.Size) || s.BoulderIn(a, u.Size) {
				continue
			}
			if s.firstBlocker(a, u.Size, u) != nil {
				continue
			}
			best = a
			bestD = d
		}
	}
	u.Hidden = false
	u.Pos = best
	u.HasMoved = false
	u.HasActed = true
	u.ActionsLeft = s.Cave.EmergeActions + 1
	for _, sk := range u.Skills {
		if sk.HasLeap {
			u.Cooldowns = kvErase(u.Cooldowns, sk.ID)
		}
	}
	s.Cave.Last = "emerge"
	emit(ev, Event{Type: EvEmerge, Unit: u.ID, Entrance: entrance, To: best})
}

// 截击：目标身边带 intercept 的同伴替它挨这一下（每回合一次）。
func interceptor(s *BattleState, attacker, target *UnitState, ev *[]Event) *UnitState {
	if attacker.Team == target.Team {
		return target
	}
	for _, ally := range s.Units {
		if !ally.Alive || ally.Team != target.Team {
			continue
		}
		if ally == target || !ally.Traits.Intercept || ally.InterceptUsed {
			continue
		}
		if ally.HasStatus("stunned") {
			continue
		}
		if Distance(ally, target) != 1 {
			continue
		}
		ally.InterceptUsed = true
		emit(ev, Event{Type: EvIntercept, Unit: ally.ID, Protected: target.ID})
		return ally
	}
	return target
}

// 一个相邻的同伴（按单位顺序的第一个）追加 30% 的援护攻击，每人每回合一次。
func assist(s *BattleState, attacker, target *UnitState, ev *[]Event) {
	for _, ally := range s.Units {
		if !ally.Alive || ally.Hidden || ally.DefID == "refugee" || ally.ID == "wounded_chiron" || ally.Team != attacker.Team {
			continue
		}
		if ally == attacker || ally.AssistUsed || ally.HasStatus("stunned") {
			continue
		}
		// 半神：同伴不再为他援护。
		if vessel(attacker) && s.Tier() >= TierDemigod {
			return
		}
		if Distance(ally, target) != 1 {
			continue
		}
		ally.AssistUsed = true
		hit := Compute(s, ally, target, AssistMult, Physical, false, NoPos)
		emit(ev, Event{Type: EvAssist, Unit: ally.ID, Target: target.ID, Relation: hit.Relation})
		dodged := target.HasStatus("dodge")
		Deal(s, target, hit.Amount, Physical, "assist", ev, true)
		if !dodged {
			AddStagger(target, StaggerFromRelation(hit.Relation), ev)
		}
		return
	}
}

// --- 阶段流程 ----------------------------------------------------------------------

// StartBattle 开始战斗：第 1 回合的我方阶段。
func StartBattle(s *BattleState) {
	s.ClearMoveCache()
	s.Round = 1
	s.ignite()
	beginPhase(s, PhasePlayer, nil)
}

// EndPhase 结束当前阶段。敌方阶段结束后先做回合结算，再进入新回合。
// 返回期间产生的事件（结算、眩晕跳过……）。
func EndPhase(s *BattleState) []Event {
	events := []Event{}
	if s.Phase == PhasePlayer {
		chironVolley(s, &events)
		s.evacuate(&events)
		beginPhase(s, PhaseEnemy, &events)
	} else {
		SettleRound(s, &events)
		if s.Round == 1 && s.Reward.Boon == "swift_boots" {
			for _, u := range s.Units {
				if u.Team == TeamPlayer {
					u.Move -= 2
				}
			}
		}
		s.Round++
		s.ignite()
		archer := s.arrivals(&events)
		beginPhase(s, PhasePlayer, &events)
		if archer != nil {
			s.ridgeShot(archer, &events)
		}
	}
	return events
}

// FinishActivation 用于多次行动的单位（首领）：用掉一次行动，还有剩余就刷新移动和行动。
// 返回它本阶段是否还能再动。
func FinishActivation(s *BattleState, u *UnitState) bool {
	u.ActionsLeft--
	u.undoOK = false
	if u.ActionsLeft > 0 && u.Alive {
		u.HasMoved = false
		u.HasActed = false
		return true
	}
	u.HasMoved = true
	u.HasActed = true
	return false
}

func beginPhase(s *BattleState, phase Phase, ev *[]Event) {
	s.Phase = phase
	team := TeamEnemy
	if phase == PhasePlayer {
		team = TeamPlayer
	}
	for _, u := range s.Units {
		u.chargeDir = Cell{}
		u.undoOK = false
		if !u.Alive {
			continue
		}
		if phase == PhasePlayer {
			u.RelicSwiftUsed = false
			u.AssistUsed = false
			u.MarkUsed = false
			u.InterceptUsed = false
		}
		if u.Team != team {
			continue
		}
		u.EraseStatus("guard")
		u.EraseStatus("dodge")
		u.PostMove = 0
		u.HasMoved = false
		u.HasActed = false
		u.ActionsLeft = u.ActionsPerTurn
		if u.HasStatus("stunned") {
			u.EraseStatus("stunned")
			u.HasMoved = true
			u.HasActed = true
			u.ActionsLeft = 0
			emit(ev, Event{Type: EvStunSkip, Unit: u.ID})
		}
	}
}

// SettleRound 做回合结算，顺序：雷躯 → 地形和持续伤害 → 状态倒计时 → 冷却。
func SettleRound(s *BattleState, ev *[]Event) {
	settleThunderBody(s, ev)
	for _, u := range s.Living(TeamAny) {
		switch terrain := s.Grid.TerrainAt(u.Pos); {
		case terrain == Burning:
			AddStatus(s, u, "burning", 2, ev, false)
			u.Scorched = true
		case terrain == Swamp && !u.Traits.MarshStride:
			// 沼泽里长大的不怕沼泽。
			AddStatus(s, u, "poisoned", 3, ev, false)
			if u.Team == TeamPlayer {
				s.SwampRests++
			}
		case terrain == Styx && !u.Traits.Undead:
			Deal(s, u, StyxDamage, True, "styx", ev, false)
		}
		if u.Alive && u.HasStatus("burning") {
			Deal(s, u, BurnDamage, True, "burning", ev, false)
		}
		if u.Alive && u.HasStatus("poisoned") {
			Deal(s, u, PoisonDamage, True, "poisoned", ev, false)
		}
	}
	settleFires(s, ev)

	var keys []string
	for _, u := range s.Living(TeamAny) {
		keys = keys[:0]
		for _, kv := range u.Statuses {
			keys = append(keys, kv.Key)
		}
		for _, st := range keys {
			if st == "guard" || st == "dodge" || st == "stunned" {
				continue // 在持有者下一个阶段开始时清除
			}
			cur, _ := u.Status(st)
			left := cur - 1
			if left <= 0 {
				u.EraseStatus(st)
				emit(ev, Event{Type: EvStatusEnd, Target: u.ID, Status: st})
				if st == "rooted" {
					u.SetStatus("control_immune", 1)
				}
			} else {
				u.SetStatus(st, left)
			}
		}
		for i := range u.Cooldowns {
			u.Cooldowns[i].Val = max(0, u.Cooldowns[i].Val-1)
		}
	}
}

// --- 几何 ------------------------------------------------------------------------

func gap(a0, an, b0, bn int) int {
	if d := a0 - (b0 + bn - 1); d > 0 {
		return d
	}
	if d := b0 - (a0 + an - 1); d > 0 {
		return d
	}
	return 0
}

// CellDistance 是单位占地到一个格子的曼哈顿距离。
func CellDistance(u *UnitState, c Cell) int {
	return gap(u.Pos.X, u.Size, c.X, 1) + gap(u.Pos.Y, u.Size, c.Y, 1)
}

// Distance 是两个占地之间最近两格的曼哈顿距离。
func Distance(a, b *UnitState) int {
	return gap(a.Pos.X, a.Size, b.Pos.X, b.Size) + gap(a.Pos.Y, a.Size, b.Pos.Y, b.Size)
}

// FootprintDistance 是 u 假如站在 anchor 时到 t 的距离。
func FootprintDistance(u *UnitState, anchor Cell, t *UnitState) int {
	return gap(anchor.X, u.Size, t.Pos.X, t.Size) + gap(anchor.Y, u.Size, t.Pos.Y, t.Size)
}

func LineOfSight(s *BattleState, a, b *UnitState) bool {
	from, to := a.Pos, b.Pos
	limit := max(s.UnitHeight(a), s.UnitHeight(b)) + LOSBlockLevels - 1
	steps := max(abs(to.X-from.X), abs(to.Y-from.Y))
	for i := 1; i < steps; i++ {
		t := float64(i) / float64(steps)
		c := Cell{
			int(math.Round(float64(from.X) + float64(float64(to.X-from.X)*t))),
			int(math.Round(float64(from.Y) + float64(float64(to.Y-from.Y)*t))),
		}
		if a.Occupies(c) || b.Occupies(c) {
			continue
		}
		if s.Grid.HeightAt(c) > limit {
			return false
		}
	}
	return true
}

func inLine(a, b *UnitState) bool {
	return gap(a.Pos.X, a.Size, b.Pos.X, b.Size) == 0 || gap(a.Pos.Y, a.Size, b.Pos.Y, b.Size) == 0
}

// 从 a 指向 b 的正方向（取两个中心之间占优的那条轴）。
func dirToward(a, b *UnitState) Cell {
	ax, ay := a.Center()
	bx, by := b.Center()
	dx, dy := bx-ax, by-ay
	if math.Abs(dx) >= math.Abs(dy) {
		if dx >= 0 {
			return East
		}
		return West
	}
	if dy >= 0 {
		return South
	}
	return North
}

func isUnitsPhase(s *BattleState, u *UnitState) bool {
	if s.Phase == PhasePlayer {
		return u.Team == TeamPlayer
	}
	return u.Team == TeamEnemy
}

// ActionTypeByName 把行动名（"move"、"skill"……）转成 ActionType；不认识的返回 ActUnknown。
func ActionTypeByName(name string) ActionType {
	for i, n := range actionNames {
		if i > 0 && n == name {
			return ActionType(i)
		}
	}
	return ActUnknown
}

func sign(v int) int {
	if v > 0 {
		return 1
	}
	if v < 0 {
		return -1
	}
	return 0
}
