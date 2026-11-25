package rules

// 天上的敌人和把它们弄下来的铜钹（第 3 章，19-battles、18-enemies-bosses）。
//
//	飞行   特性 flying：走路不看地形和高度；近战够不着（只有射击和从天上落下的招式打得到）；
//	       不会被击退、不会被摔、不会掉进水里。
//	落地   状态 grounded：还带着 flying，但这期间和地上的敌人一样。
//	对空   特性 anti_air：打还在天上的敌人，伤害 × AntiAirMult。
//	铜钹   地图上的机关。站在它上面或紧挨着它的我方单位用一次行动敲响：StrikeRadius 格内
//	       还在天上的敌人全部落地 GroundedRounds 回合。敲过之后要歇 CymbalRest 回合。
//
// 落地的回合数按"回合结算"算：我方敲响的那一回合里它一直在地上，敌方回合也在地上，
// 回合结算后飞起来。所以要先敲、再打。

const (
	AntiAirMult    = 1.5
	StrikeRadius   = 3
	GroundedRounds = 1
	CymbalRest     = 2
)

// Cymbal 是地图上的一面铜钹。
type Cymbal struct {
	Pos  Cell
	Rest int // 还要歇几回合才能再敲；0 是现在就能敲
}

// Aloft 表示这个单位现在在天上：会飞，而且没有被弄下来。
func (u *UnitState) Aloft() bool {
	return u.Traits.Flying && !u.HasStatus("grounded")
}

// ReachesSky 表示这一招打得到天上的敌人：射击，或者落点范围的招式（天火、天罚）。
func (sk *Skill) ReachesSky() bool {
	return sk.Ranged || sk.Blast > 0
}

// CymbalAt 返回这一格上的铜钹，没有就是 nil。
func (s *BattleState) CymbalAt(c Cell) *Cymbal {
	for i := range s.Cymbals {
		if s.Cymbals[i].Pos == c {
			return &s.Cymbals[i]
		}
	}
	return nil
}

// Strike 是敲响 target 那一格上的铜钹。
func Strike(unit string, target Cell) Action {
	return Action{Type: ActStrike, Unit: unit, Target: target}
}

func validateStrike(s *BattleState, u *UnitState, cell Cell) string {
	c := s.CymbalAt(cell)
	if c == nil {
		return "no cymbal there"
	}
	if u.Team != TeamPlayer {
		return "not yours to strike"
	}
	if CellDistance(u, cell) > 1 {
		return "not adjacent"
	}
	if c.Rest > 0 {
		return "still ringing"
	}
	return ""
}

// StrikeTargets 列出敲响这面铜钹会落地的敌人。
func StrikeTargets(s *BattleState, cell Cell) []*UnitState {
	var hit []*UnitState
	for _, o := range s.Units {
		if o.Alive && !o.Hidden && o.Team == TeamEnemy && o.Aloft() && CellDistance(o, cell) <= StrikeRadius {
			hit = append(hit, o)
		}
	}
	return hit
}

func doStrike(s *BattleState, u *UnitState, cell Cell, ev *[]Event) {
	c := s.CymbalAt(cell)
	c.Rest = CymbalRest
	u.HasActed = true
	u.undoOK = false
	if u.Pos != cell {
		u.Facing = facingToward(u.Pos, cell)
	}
	emit(ev, Event{Type: EvStrike, Unit: u.ID, To: cell})
	for _, o := range StrikeTargets(s, cell) {
		o.SetStatus("grounded", GroundedRounds)
		s.Felled++
		emit(ev, Event{Type: EvStatus, Target: o.ID, Status: "grounded", Rounds: GroundedRounds})
	}
}

// settleCymbals 在回合结算时让铜钹歇过一回合。
func (s *BattleState) settleCymbals() {
	for i := range s.Cymbals {
		if s.Cymbals[i].Rest > 0 {
			s.Cymbals[i].Rest--
		}
	}
}
