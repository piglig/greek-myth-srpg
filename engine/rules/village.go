package rules

// Village defines the two-person escape zone and the first round each cell burns.
type Village struct {
	Exits    []Cell
	Ignition []string
}

func (s *BattleState) ignite() {
	if s.Village == nil || s.Round > 9 {
		return
	}
	var changed *Grid
	for y, row := range s.Village.Ignition {
		for x, ch := range row {
			if int(ch-'0') != s.Round {
				continue
			}
			if changed == nil {
				g := *s.Grid
				g.terrain = append([]Terrain(nil), g.terrain...)
				changed = &g
			}
			changed.SetTerrain(Cell{x, y}, Burning)
		}
	}
	if changed != nil {
		s.Grid = changed
		s.ClearMoveCache()
	}
}

func (s *BattleState) arrivals(ev *[]Event) *UnitState {
	var archer *UnitState
	for _, u := range s.Units {
		if u.Arrival == 0 || u.Arrival > s.Round {
			continue
		}
		// An occupied entry point shifts to the closest open cell of the same elevation.
		start := u.Pos
		best := s.Grid.Width + s.Grid.Depth + 1
		var pos Cell
		for y := 0; y < s.Grid.Depth; y++ {
			for x := 0; x < s.Grid.Width; x++ {
				c := Cell{x, y}
				distance := abs(x-start.X) + abs(y-start.Y)
				if distance < best && s.Grid.HeightAt(c) == s.Grid.HeightAt(start) && s.UnitAt(c) == nil {
					best = distance
					pos = c
				}
			}
		}
		if best > s.Grid.Width+s.Grid.Depth {
			continue
		}
		u.Pos = pos
		u.Alive = true
		u.Arrival = 0
		emit(ev, Event{Type: EvArrival, Unit: u.ID})
		if u.ID == "atalanta" {
			archer = u
		}
	}
	return archer
}

func (s *BattleState) ridgeShot(u *UnitState, ev *[]Event) {
	var target *UnitState
	for _, e := range s.Living(TeamEnemy) {
		if Validate(s, UseSkill(u.ID, "shoot", e.Pos)) != "" {
			continue
		}
		if target == nil || s.UnitHeight(e) < s.UnitHeight(target) {
			target = e
		}
	}
	if target != nil {
		doSkill(s, u, UseSkill(u.ID, "shoot", target.Pos), ev)
		u.HasActed = false // The introductory shot is a scripted reaction.
		u.PostMove = 0
	}
}

func (s *BattleState) atVillageGate() bool {
	if s.Village == nil {
		return false
	}
	for _, id := range []string{"hero", "atalanta"} {
		u := s.Unit(id)
		if u == nil || !u.Alive {
			return false
		}
		atExit := false
		for _, c := range s.Village.Exits {
			if u.Pos == c {
				atExit = true
				break
			}
		}
		if !atExit {
			return false
		}
	}
	return true
}

// Outcome is empty while the battle continues.
func (s *BattleState) Outcome() string {
	hero := s.Unit("hero")
	if hero == nil || !hero.Alive {
		return "loss_hero"
	}
	if ally := s.Unit("wounded_chiron"); ally != nil && !ally.Alive {
		return "loss_chiron"
	}
	if len(s.EscortExits) > 0 {
		ally := s.Unit("medea")
		if ally == nil || !ally.Alive {
			return "loss_escort"
		}
		for _, exit := range s.EscortExits {
			if ally.Pos == exit {
				return "win"
			}
		}
		return ""
	}
	players, enemies := false, false
	for _, u := range s.Units {
		if u.Arrival > 0 && u.Team == TeamEnemy {
			enemies = true
		}
		if u.Alive {
			players = players || u.Team == TeamPlayer
			enemies = enemies || u.Team == TeamEnemy
		}
	}
	if !players {
		return "loss_wipe"
	}
	if !enemies || s.atVillageGate() {
		return "win"
	}
	return ""
}
