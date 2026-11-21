package rules

import "math"

// 伤害公式（07-combat-rules §4）。完全确定，没有任何随机。

// Hit 是一次命中的计算结果。
type Hit struct {
	Amount   int
	Relation Relation
	Immune   bool
	Base     int
	Mult     float64
	Notes    Notes
}

// RelationOf 判断从 (fx, fy) 打向 target 时是正面、侧面还是背面。
func RelationOf(fx, fy float64, target *UnitState) Relation {
	cx, cy := target.Center()
	dx, dy := fx-cx, fy-cy
	tx, ty := float64(target.Facing.X), float64(target.Facing.Y)
	along := dx*tx + dy*ty
	across := math.Abs(dx*ty - dy*tx)
	if along > 0 && along > across {
		return Front
	}
	if along < 0 && -along > across {
		return Back
	}
	return Side
}

func relationMult(rel Relation) float64 {
	switch rel {
	case Back:
		return BackMult
	case Side:
		return SideMult
	}
	return 1.0
}

// IsFlanked 判断 target 是否被 team 的单位从相对的两侧夹住。
func IsFlanked(s *BattleState, target *UnitState, team Team) bool {
	sz := target.Size
	p := target.Pos
	var left, right, top, bottom bool
	for i := 0; i < sz; i++ {
		left = left || isTeam(s, Cell{p.X - 1, p.Y + i}, team)
		right = right || isTeam(s, Cell{p.X + sz, p.Y + i}, team)
		top = top || isTeam(s, Cell{p.X + i, p.Y - 1}, team)
		bottom = bottom || isTeam(s, Cell{p.X + i, p.Y + sz}, team)
	}
	return (left && right) || (top && bottom)
}

func isTeam(s *BattleState, c Cell, team Team) bool {
	if !s.Grid.InBounds(c) {
		return false
	}
	u := s.UnitAt(c)
	return u != nil && u.Team == team
}

// Compute 计算一次命中。fromAnchor 传 NoPos 表示从攻击者当前位置出手，
// 否则按“假如站在 fromAnchor”来算。
func Compute(s *BattleState, attacker, target *UnitState, skillMult float64, dmgType DamageType,
	ranged bool, fromAnchor Cell) Hit {
	if fromAnchor == NoPos {
		fromAnchor = attacker.Pos
	}
	fx, fy := attacker.CenterAt(fromAnchor)
	rel := RelationOf(fx, fy, target)
	broken := target.HasStatus("staggered")
	if dmgType == Physical && (target.Traits.PhysicalImmune && !broken || target.HasStatus("impervious_hide")) {
		return Hit{Amount: 0, Relation: rel, Immune: true, Notes: NotePhysicalImmune}
	}

	stat := attacker.Strength
	if attacker.HasStatus("weakened") {
		stat = max(0, stat-3)
	}
	if dmgType == Divine {
		stat = attacker.Divinity
	}
	raw := FloorInt(float64(float64(stat) * skillMult))
	mitigation := 0
	if dmgType == Physical {
		mitigation = target.Defense
		if target.HasStatus("exposed") {
			mitigation = max(0, mitigation-3)
		}
	} else if dmgType == Divine {
		mitigation = target.Will
	}
	base := max(1, raw-mitigation)

	var notes Notes
	m := relationMult(rel)
	if attacker.Traits.Has("beast_hunter") && target.Size > 1 {
		m *= 1.2
	}
	if dmgType == Divine && attacker.Traits.Has("kindling") && target.HasStatus("burning") {
		m *= 1.25
		notes |= NoteKindling
	}
	if target.ID == "hero" && s.Reward.EquippedRelic == "lion_pelt" {
		if dmgType == Physical {
			base = max(1, base-3)
		}
		if rel == Back {
			m = 1.25
		}
	}
	if attacker.DefID == "centaur" && attacker.chargeDir != (Cell{}) && target.Pos.Sub(fromAnchor) == attacker.chargeDir {
		m *= 1.5
		notes |= NoteCharge
	}
	if rel == Front && target.Traits.Block {
		m *= BlockMult
		notes |= NoteBlock
	}
	hAtt := s.StandingHeight(fromAnchor, attacker.Size)
	hTgt := s.UnitHeight(target)
	if hAtt >= hTgt+1 {
		m *= HighGroundMult
		notes |= NoteHighGround
	}
	if ranged && s.Grid.TerrainAt(target.Pos) == Forest {
		m *= CoverMult
		notes |= NoteCover
	}
	if s.IsMarked(target.ID) && attacker.Team == TeamPlayer {
		m *= MarkMult
		notes |= NoteMarked
	}
	if IsFlanked(s, target, attacker.Team) {
		m *= FlankMult
		notes |= NoteFlanked
	}
	if attacker.Traits.Patience && !attacker.HasMoved {
		m *= PatienceMult
		notes |= NotePatience
	}
	if target.Traits.IronArm && target.GrapplingID != "" {
		m *= IronArmMult
		notes |= NoteIronArm
	}
	if shieldWallCovers(s, target) {
		m *= ShieldWallMult
		notes |= NoteShieldWall
	}
	if target.HasStatus("guard") {
		m *= GuardMult
		notes |= NoteGuard
	}
	if broken {
		m *= BrokenMult
		notes |= NoteBroken
	}
	if attacker.GrappledByID != "" && attacker.GrappledByID == target.ID {
		m *= GrappledAttackMult
		notes |= NoteGrappled
	}
	return Hit{Amount: FloorInt(float64(float64(base) * m)), Relation: rel, Base: base, Mult: m, Notes: notes}
}

// StaggerFromRelation 是首领因受击方向获得的破势值（即使伤害为 0 也算）。
func StaggerFromRelation(rel Relation) int {
	switch rel {
	case Back:
		return StaggerBack
	case Side:
		return StaggerSide
	}
	return 0
}

// 目标身边有处于防御姿态、带“盾墙”的同伴时减伤。
func shieldWallCovers(s *BattleState, target *UnitState) bool {
	for _, ally := range s.Units {
		if ally.Alive && ally.Team == target.Team && ally != target && ally.Traits.ShieldWall &&
			ally.HasStatus("guard") && Distance(ally, target) == 1 {
			return true
		}
	}
	return false
}
