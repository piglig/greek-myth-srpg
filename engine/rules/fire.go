package rules

// Fire 是一格正在烧的林地：Left 是它还能烧几次回合结算。
type Fire struct {
	Cell Cell
	Left int
}

// FireRounds 是一格林地从点着到烧成焦土经过的回合结算次数。
const FireRounds = 2

// Kindles 表示这个招式带火：打在林地上（不管那格有没有人）会把那一格点着。
func Kindles(sk *Skill) bool {
	if sk.Status == "burning" {
		return true
	}
	switch sk.ID {
	case "witch_fire", "solar_flame", "cinder_lance":
		return true
	}
	return false
}

// setTerrain 改一格地形。地图在同一场战斗的各个副本之间共用，所以先换成自己的一份。
func (s *BattleState) setTerrain(c Cell, t Terrain) {
	g := *s.Grid
	g.terrain = append([]Terrain(nil), g.terrain...)
	g.SetTerrain(c, t)
	s.Grid = &g
	s.ClearMoveCache()
}

// kindle 把一格林地点着；不是林地就什么也不做。
func (s *BattleState) kindle(c Cell, ev *[]Event) bool {
	if !s.Grid.InBounds(c) || s.Grid.TerrainAt(c) != Forest {
		return false
	}
	s.setTerrain(c, Burning)
	s.Fires = append(s.Fires, Fire{Cell: c, Left: FireRounds})
	s.FireEver = true
	emit(ev, Event{Type: EvIgnite, To: c})
	return true
}

// FireNext 是下一次回合结算时会被烧到的林地格：与火相邻的每一格林地，必定点着。
func (s *BattleState) FireNext() []Cell {
	var out []Cell
	seen := map[Cell]bool{}
	for _, f := range s.Fires {
		for _, d := range Dirs {
			c := f.Cell.Add(d)
			if s.Grid.InBounds(c) && s.Grid.TerrainAt(c) == Forest && !seen[c] {
				seen[c] = true
				out = append(out, c)
			}
		}
	}
	return out
}

// settleFires 在回合结算时让火走一步：先向相邻的林地蔓延，再让原有的火各烧掉一回合，
// 烧完的变成平地（焦土），不会再烧第二次。这一步新点着的火下一回合才开始算。
func settleFires(s *BattleState, ev *[]Event) {
	if len(s.Fires) == 0 {
		return
	}
	old := len(s.Fires)
	for _, c := range s.FireNext() {
		s.kindle(c, ev)
	}
	kept := s.Fires[:0:0]
	for i, f := range s.Fires {
		if i < old {
			f.Left--
			if f.Left <= 0 {
				s.setTerrain(f.Cell, Plain)
				emit(ev, Event{Type: EvBurnOut, To: f.Cell})
				continue
			}
		}
		kept = append(kept, f)
	}
	s.Fires = kept
}

// IsTarget 表示这个单位是这场战斗指定要击杀的目标。
func (s *BattleState) IsTarget(id string) bool {
	for _, t := range s.Targets {
		if t == id {
			return true
		}
	}
	return false
}

// TargetsLeft 是还活着的指定目标数。
func (s *BattleState) TargetsLeft() int {
	n := 0
	for _, id := range s.Targets {
		if u := s.Unit(id); u != nil && u.Alive {
			n++
		}
	}
	return n
}

// TargetsScorched 是有多少个指定目标被地上的火烧到过（可选目标用）。
func (s *BattleState) TargetsScorched() int {
	n := 0
	for _, id := range s.Targets {
		if u := s.Unit(id); u != nil && u.Scorched {
			n++
		}
	}
	return n
}
