package rules

// A run-up must stay in one direction, including the final attack.
func straightRun(from Cell, path []Cell) Cell {
	if len(path) < 3 {
		return Cell{}
	}
	dir := path[0].Sub(from)
	for _, step := range path {
		if step.Sub(from) != dir {
			return Cell{}
		}
		from = step
	}
	return dir
}

// When the wounded archer is in a straight lane, the first defender in it
// intercepts the rider. Occupied or obstructed lanes fall back to ordinary AI.
func feastLane(s *BattleState, rider *UnitState) (Plan, bool) {
	ally := s.Unit("wounded_chiron")
	if ally == nil || !ally.Alive || rider.HasMoved {
		return Plan{}, false
	}
	delta := ally.Pos.Sub(rider.Pos)
	if delta.X != 0 && delta.Y != 0 {
		return Plan{}, false
	}
	distance := CellDistance(rider, ally.Pos)
	if distance == 0 {
		return Plan{}, false
	}
	dir := Cell{delta.X / distance, delta.Y / distance}
	reach := Reachable(s, rider, -1)
	origin := rider.Pos
	stop := origin
	for i := 0; i < distance; i++ {
		step := stop.Add(dir)
		if target := s.UnitAt(step); target != nil {
			if target.Team == rider.Team {
				break
			}
			rider.Pos = stop
			action := UseSkill(rider.ID, "spear", step)
			ok := Validate(s, action) == ""
			rider.Pos = origin
			if ok {
				return Plan{HasMove: i > 0, MoveTo: stop, Action: action}, true
			}
			break
		}
		if !reach.CanStop(step) || len(reach.PathTo(step)) != i+1 {
			break
		}
		stop = step
	}
	return Plan{}, false
}

func chironVolley(s *BattleState, ev *[]Event) {
	u := s.Unit("wounded_chiron")
	if u == nil || !u.Alive || u.HasActed || u.HasStatus("stunned") {
		return
	}
	var nearest *UnitState
	for _, enemy := range s.Living(TeamEnemy) {
		if validateSkill(s, u, "shoot", enemy.Pos, NoPos) != "" {
			continue
		}
		if nearest == nil || CellDistance(u, enemy.Pos) < CellDistance(u, nearest.Pos) {
			nearest = enemy
		}
	}
	if nearest != nil {
		doSkill(s, u, UseSkill(u.ID, "shoot", nearest.Pos), ev)
	}
}
