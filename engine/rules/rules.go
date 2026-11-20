package rules

import "math"

// 行动的校验、执行、预览和阶段流程（07-combat-rules §2、§7.1）。

// ActionType 是行动种类。
type ActionType uint8

const (
	ActUnknown     ActionType = iota
	ActMove                   // Unit, To
	ActUndoMove               // Unit
	ActSkill                  // Unit, Skill, Target；跳跃技能另带落点 To（HasTo）
	ActSlam                   // Unit, Target（被擒抱者旁边的一格：摔出的方向）
	ActGrapple                // Unit, Target
	ActReinforce              // Unit
	ActStruggle               // Unit
	ActRelease                // Unit
	ActWait                   // Unit
	ActFace                   // Unit, Facing
	ActMark                   // Unit, Target
	ActPushBoulder            // Unit, Target（巨石所在的格子）
	ActRetreat                // Unit
	ActEmerge                 // Unit, Entrance
)

var actionNames = [...]string{"", "move", "undo_move", "skill", "slam", "grapple", "reinforce", "struggle",
	"release", "wait", "face", "mark", "push_boulder", "retreat", "emerge"}

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
func Grapple(unit string, target Cell) Action {
	return Action{Type: ActGrapple, Unit: unit, Target: target}
}
func Slam(unit string, target Cell) Action { return Action{Type: ActSlam, Unit: unit, Target: target} }
func Mark(unit string, target Cell) Action { return Action{Type: ActMark, Unit: unit, Target: target} }
func Face(unit string, facing Cell) Action { return Action{Type: ActFace, Unit: unit, Facing: facing} }
func PushBoulder(unit string, target Cell) Action {
	return Action{Type: ActPushBoulder, Unit: unit, Target: target}
}
func Emerge(unit, entrance string) Action {
	return Action{Type: ActEmerge, Unit: unit, Entrance: entrance}
}

// Simple 创建只需要单位的行动（undo_move、reinforce、struggle、release、wait、retreat）。
func Simple(t ActionType, unit string) Action { return Action{Type: t, Unit: unit} }

// Outcome 是执行一个行动的结果。
type Outcome struct {
	OK     bool
	Error  string
	Action Action
	Events []Event
}

func isFree(t ActionType) bool {
	return t == ActFace || t == ActMark || t == ActRelease || t == ActUndoMove
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
		u.Pos = u.undoPos
		u.Facing = u.undoFacing
		u.HasMoved = false
		u.undoOK = false
	case ActSkill:
		doSkill(s, u, a, ev)
	case ActSlam:
		doSlam(s, u, a.Target, ev)
	case ActGrapple:
		doGrapple(u, s.UnitAt(a.Target), ev)
	case ActReinforce:
		t := s.Unit(u.GrapplingID)
		t.Escape = min(t.Escape+1, EscapeCap(t))
		u.HasActed = true
		emit(ev, Event{Type: EvReinforce, Unit: u.ID, Escape: t.Escape})
	case ActStruggle:
		// 首领挣脱快一倍：按住它只耗掉它一次行动，而不是整个回合
		if u.IsBoss() {
			u.Escape -= BossStruggle
		} else {
			u.Escape--
		}
		u.HasActed = true
		emit(ev, Event{Type: EvStruggle, Unit: u.ID, Escape: u.Escape})
		if u.Escape <= 0 {
			EndGrapple(s, s.Unit(u.GrappledByID), ev, "escaped")
		}
	case ActRelease:
		EndGrapple(s, u, ev, "released")
	case ActWait:
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
		s.MarkedID = t.ID
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
	if !isUnitsPhase(s, u) {
		return "not this unit's phase"
	}
	t := a.Type
	needsMain := !isFree(t) && t != ActMove
	if needsMain && u.HasActed {
		return "already acted"
	}
	if u.GrappledByID != "" && t != ActStruggle && t != ActSkill && t != ActWait {
		return "grappled"
	}
	if u.GrapplingID != "" && t != ActReinforce && t != ActRelease && t != ActWait && t != ActSkill && t != ActSlam {
		return "grappling"
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
	case ActSlam:
		if !u.Traits.Slam || u.GrapplingID == "" {
			return "cannot slam"
		}
		held := s.Unit(u.GrapplingID)
		if !s.Grid.InBounds(a.Target) || CellDistance(held, a.Target) != 1 {
			return "bad slam direction"
		}
	case ActGrapple:
		return validateGrapple(s, u, a.Target)
	case ActReinforce:
		if u.GrapplingID == "" {
			return "not grappling"
		}
	case ActStruggle:
		if u.GrappledByID == "" {
			return "not grappled"
		}
	case ActRelease:
		if u.GrapplingID == "" {
			return "not grappling"
		}
	case ActFace:
		if u.GrappledByID != "" {
			return "facing locked"
		}
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
	if u.HasStatus("feared") {
		return "feared"
	}
	if u.GrapplingID != "" {
		return "grappling"
	}
	if sk.IsArea() {
		if u.GrappledByID != "" {
			return "grappled"
		}
		if !anyAreaTarget(s, u, sk) {
			return "no one in range"
		}
		return ""
	}
	if sk.HasLeap {
		if u.GrappledByID != "" {
			return "grappled"
		}
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
	if target == nil || target.Team == u.Team {
		return "no enemy there"
	}
	ranged := sk.Ranged
	if u.GrappledByID != "" && (target.ID != u.GrappledByID || ranged) {
		return "grappled: can only strike the grappler"
	}
	dist := Distance(u, target)
	minR, maxR := sk.MinRange, sk.MaxRange
	if ranged {
		if s.UnitHeight(u)-s.UnitHeight(target) >= HighGroundRangeLevel {
			maxR++
		}
		if u.Traits.HunterMark && s.MarkedID == target.ID {
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

func validateGrapple(s *BattleState, u *UnitState, cell Cell) string {
	if !u.Traits.HasGrapple {
		return "cannot grapple"
	}
	var t *UnitState
	if s.Grid.InBounds(cell) {
		t = s.UnitAt(cell)
	}
	if t == nil || t.Team == u.Team {
		return "no enemy there"
	}
	if Distance(u, t) != 1 {
		return "not adjacent"
	}
	if t.Traits.Flying || t.HasStatus("petrified") || t.Size >= 3 {
		return "cannot grapple that"
	}
	if t.GrappledByID != "" {
		return "already grappled"
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
	u.Pos = to
	u.HasMoved = true
}

func doSkill(s *BattleState, u *UnitState, a Action, ev *[]Event) {
	sk := u.Skill(a.Skill)
	if sk.IsArea() {
		u.HasActed = true
		if sk.Cooldown > 0 {
			u.SetCooldown(sk.ID, sk.Cooldown)
		}
		emit(ev, Event{Type: EvArea, Unit: u.ID, Skill: sk.ID})
		for _, o := range AreaTargets(s, u, sk) {
			AddStatus(s, o, sk.AreaStatus, sk.Rounds, ev, false)
		}
		return
	}
	if sk.HasLeap {
		emit(ev, Event{Type: EvLeap, Unit: u.ID, From: u.Pos, To: a.To})
		u.Pos = a.To
		u.HasMoved = true
	}
	target := interceptor(s, u, s.UnitAt(a.Target), ev)
	ranged := sk.Ranged
	u.Facing = dirToward(u, target)
	u.HasActed = true
	if sk.Cooldown > 0 {
		u.SetCooldown(sk.ID, sk.Cooldown)
	}

	hit := Compute(s, u, target, sk.Mult, sk.Type, ranged, NoPos)
	emit(ev, Event{Type: EvAttack, Unit: u.ID, Target: target.ID, Skill: sk.ID, Relation: hit.Relation, Notes: hit.Notes})
	dodged := target.HasStatus("dodge")
	Deal(s, target, hit.Amount, sk.Type, sk.ID, ev, true)
	if !dodged {
		stagger := StaggerFromRelation(hit.Relation) + sk.StaggerBonus
		if s.MarkedID == target.ID && hit.Relation != Front {
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
		Knockback(s, target, dirToward(u, target), sk.Knockback, sk.ID, ev)
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

// 力气大的单位（赫拉克勒斯）一推到位；其他人要推两次。
func doPush(s *BattleState, u *UnitState, id string, ev *[]Event) {
	b := s.Cave.Boulder(id)
	if u.Traits.Strong {
		b.Progress += 2
	} else {
		b.Progress++
	}
	u.HasActed = true
	emit(ev, Event{Type: EvPush, Unit: u.ID, Boulder: id, Progress: b.Progress})
	if b.Progress >= 2 {
		b.Placed = true
		s.Cave.Entrance(b.Seals).Sealed = true
		emit(ev, Event{Type: EvSealed, Entrance: b.Seals, Boulder: id})
	}
}

func doRetreat(s *BattleState, u *UnitState, ev *[]Event) {
	u.Hidden = true
	u.HasMoved = true
	u.HasActed = true
	u.ActionsLeft = 1 // 回合到此结束
	s.Cave.Last = "retreat"
	if s.MarkedID == u.ID {
		s.MarkedID = ""
	}
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
		if ally.GrapplingID != "" || ally.GrappledByID != "" || ally.HasStatus("stunned") {
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

func doSlam(s *BattleState, u *UnitState, cell Cell, ev *[]Event) {
	held := s.Unit(u.GrapplingID)
	hx, hy := held.Center()
	dx, dy := float64(cell.X)+0.5-hx, float64(cell.Y)+0.5-hy
	var dir Cell
	if math.Abs(dx) >= math.Abs(dy) {
		dir = West
		if dx > 0 {
			dir = East
		}
	} else {
		dir = North
		if dy > 0 {
			dir = South
		}
	}
	u.HasActed = true
	emit(ev, Event{Type: EvSlam, Unit: u.ID, Target: held.ID})
	EndGrapple(s, u, ev, "slam")
	Knockback(s, held, dir, 1, "slam", ev)
}

// 一个相邻的同伴（按单位顺序的第一个）追加 30% 的援护攻击，每人每回合一次。
func assist(s *BattleState, attacker, target *UnitState, ev *[]Event) {
	for _, ally := range s.Units {
		if !ally.Alive || ally.Team != attacker.Team {
			continue
		}
		if ally == attacker || ally.AssistUsed || ally.HasStatus("stunned") {
			continue
		}
		if ally.GrapplingID != "" || ally.GrappledByID != "" {
			continue
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

func doGrapple(u, t *UnitState, ev *[]Event) {
	u.HasActed = true
	u.GrapplingID = t.ID
	t.GrappledByID = u.ID
	t.Escape = EscapeValue(u, t)
	t.Facing = dirToward(t, u)
	u.Facing = dirToward(u, t)
	emit(ev, Event{Type: EvGrappleStart, Grappler: u.ID, Target: t.ID, Escape: t.Escape})
}

// --- 阶段流程 ----------------------------------------------------------------------

// StartBattle 开始战斗：第 1 回合的我方阶段。
func StartBattle(s *BattleState) {
	s.ClearMoveCache()
	s.Round = 1
	beginPhase(s, PhasePlayer, nil)
}

// EndPhase 结束当前阶段。敌方阶段结束后先做回合结算，再进入新回合。
// 返回期间产生的事件（结算、眩晕跳过……）。
func EndPhase(s *BattleState) []Event {
	events := []Event{}
	if s.Phase == PhasePlayer {
		beginPhase(s, PhaseEnemy, &events)
	} else {
		SettleRound(s, &events)
		s.Round++
		beginPhase(s, PhasePlayer, &events)
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
		u.undoOK = false
		if !u.Alive {
			continue
		}
		if phase == PhasePlayer {
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

// SettleRound 做回合结算，顺序：擒抱（窒息、破势、挣脱倒计时）→ 地形和持续伤害 → 状态倒计时 → 冷却。
func SettleRound(s *BattleState, ev *[]Event) {
	for _, g := range s.Living(TeamAny) {
		if g.GrapplingID == "" {
			continue
		}
		t := s.Unit(g.GrapplingID)
		choke := g.Traits.Grapple
		if g.Traits.IronArm {
			choke += IronArmChoke
		}
		emit(ev, Event{Type: EvChoke, Grappler: g.ID, Target: t.ID, Amount: choke})
		Deal(s, t, choke, True, "choke", ev, false)
		if !t.Alive {
			continue
		}
		AddStagger(t, StaggerGrappleTick, ev)
		t.Escape--
		emit(ev, Event{Type: EvEscapeTick, Target: t.ID, Escape: t.Escape})
		if t.Escape <= 0 {
			EndGrapple(s, g, ev, "escaped")
		}
	}

	for _, u := range s.Living(TeamAny) {
		switch terrain := s.Grid.TerrainAt(u.Pos); {
		case terrain == Burning:
			AddStatus(s, u, "burning", 2, ev, false)
		case terrain == Swamp:
			AddStatus(s, u, "poisoned", 3, ev, false)
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
				if st == "feared" || st == "rooted" {
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
