package rules

// Civilians depart after the player has had a chance to clear an adjacent raider.
func (s *BattleState) evacuate(events *[]Event) {
	if len(s.RescueExits) == 0 {
		return
	}
	for _, u := range s.Units {
		if u.DefID != "refugee" || !u.Alive || u.Hidden {
			continue
		}
		pinned := false
		for _, e := range s.Living(TeamEnemy) {
			if !e.Hidden && CellDistance(e, u.Pos) == 1 {
				pinned = true
				break
			}
		}
		if pinned {
			continue
		}
		full := Reachable(s, u, s.Grid.Width*s.Grid.Depth*4)
		exit := NoPos
		for _, c := range s.RescueExits {
			if full.CanStop(c) && (exit == NoPos || full.Cost(c) < full.Cost(exit)) {
				exit = c
			}
		}
		if exit == NoPos {
			continue
		}
		reach := Reachable(s, u, u.Move)
		to := u.Pos
		for _, step := range full.PathTo(exit) {
			if reach.CanStop(step) {
				to = step
			}
		}
		if to != u.Pos {
			doMove(s, u, to, events)
			u.undoOK = false
		}
		if to == exit {
			u.Hidden = true
			emit(events, Event{Type: EvRescued, Unit: u.ID})
		}
		s.ClearMoveCache()
	}
}

// RescuePreview follows the same civilian order, occupancy and evacuation events as EndPhase.
func RescuePreview(s *BattleState, u *UnitState) (path []Cell, threats []string, escapes bool) {
	next := s.Copy()
	events := EndPhase(next)
	for _, e := range events {
		if e.Unit == u.ID && e.Type == EvMove {
			path = e.Path
		}
	}
	traveler := next.Unit(u.ID)
	threats = []string{}
	if traveler.Hidden {
		return path, threats, true
	}
	for _, e := range next.Living(TeamEnemy) {
		if e.Hidden || e.HasActed {
			continue
		}
		original := e.Pos
		for _, c := range Reachable(next, e, -1).Dests() {
			e.Pos = c
			canHit := false
			for _, sk := range e.Skills {
				if Validate(next, UseSkill(e.ID, sk.ID, traveler.Pos)) == "" {
					canHit = true
					break
				}
			}
			if canHit {
				threats = append(threats, e.ID)
				break
			}
		}
		e.Pos = original
	}
	return path, threats, false
}
