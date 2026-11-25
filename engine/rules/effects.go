package rules

// 所有行动共用的底层状态变化：伤害、状态、破势、击退、摔出。每一步都往 ev 里追加事件。

// Deal 对 target 造成伤害，返回实际扣掉的生命。
func Deal(s *BattleState, target *UnitState, amount int, dmgType DamageType, source string,
	ev *[]Event, canDodge bool) int {
	if !target.Alive {
		return 0
	}
	if canDodge && amount > 0 && target.HasStatus("dodge") {
		target.EraseStatus("dodge")
		emit(ev, Event{Type: EvDodge, Target: target.ID, Source: source})
		return 0
	}
	dealt := amount
	if target.Shield > 0 && dealt > 0 {
		absorbed := min(target.Shield, dealt)
		target.Shield -= absorbed
		dealt -= absorbed
		emit(ev, Event{Type: EvShield, Target: target.ID, Absorbed: absorbed})
	}
	target.HP -= dealt
	emit(ev, Event{Type: EvDamage, Target: target.ID, Amount: dealt, DmgType: dmgType, Source: source, HP: target.HP})
	if target.DefID == "centaur" && target.HP*2 < target.MaxHP {
		target.Alive = false
		s.removeMark(target.ID)
		emit(ev, Event{Type: EvFlee, Unit: target.ID})
	} else if target.HP <= 0 {
		KnockOut(s, target, ev)
	}
	return dealt
}

func KnockOut(s *BattleState, u *UnitState, ev *[]Event) {
	if !u.Alive {
		return
	}
	u.HP = min(u.HP, 0)
	u.Alive = false
	s.removeMark(u.ID)
	emit(ev, Event{Type: EvKO, Target: u.ID})
}

// AddStatus 施加状态。首领无视控制状态，除非 bypassArmor 为真或正处于破势。
func AddStatus(s *BattleState, u *UnitState, status string, rounds int, ev *[]Event, bypassArmor bool) bool {
	if vessel(u) && IsAilment(status) && s.Tier() >= TierInhuman {
		emit(ev, Event{Type: EvResist, Target: u.ID, Status: status, Why: "divine"})
		return false
	}
	isControl := isControlStatus(status)
	if isControl && !bypassArmor {
		if u.IsBoss() && !u.HasStatus("staggered") {
			emit(ev, Event{Type: EvResist, Target: u.ID, Status: status, Why: "super_armor"})
			return false
		}
		if u.HasStatus("control_immune") {
			emit(ev, Event{Type: EvResist, Target: u.ID, Status: status, Why: "control_immune"})
			return false
		}
	}
	cur, _ := u.Status(status)
	u.SetStatus(status, max(cur, rounds))
	emit(ev, Event{Type: EvStatus, Target: u.ID, Status: status, Rounds: rounds})
	return true
}

func AddStagger(u *UnitState, amount int, ev *[]Event) {
	if !u.IsBoss() || !u.Alive || amount <= 0 || u.HasStatus("staggered") {
		return
	}
	u.Stagger += amount
	emit(ev, Event{Type: EvStagger, Target: u.ID, Amount: amount, Total: u.Stagger})
	if u.Stagger >= u.StaggerMax {
		u.Stagger = 0
		// 破势：眩晕到下一个敌方阶段结束，易伤持续到下一回合结束
		u.SetStatus("stunned", 1)
		u.SetStatus("staggered", 2)
		emit(ev, Event{Type: EvBroken, Target: u.ID})
	}
}

// Knockback 把 target 沿 dir 推 steps 格（07-combat-rules §5.1）。
func Knockback(s *BattleState, target *UnitState, dir Cell, steps int, source string, ev *[]Event) {
	if !target.Alive || steps <= 0 {
		return
	}
	start := target.Pos
	totalDrop := 0
	for i := 0; i < steps; i++ {
		nxt := target.Pos.Add(dir)
		curH := s.UnitHeight(target)
		if !s.FootprintInBounds(nxt, target.Size) || drowns(s, target, nxt) {
			sink(s, target, nxt, ev)
			break
		}
		if hit := s.firstBlocker(nxt, target.Size, target); hit != nil {
			emit(ev, Event{Type: EvCollision, Target: target.ID, With: hit.ID})
			Deal(s, target, CollisionDamage, True, "collision", ev, false)
			Deal(s, hit, CollisionDamage, True, "collision", ev, false)
			break
		}
		nxtH := s.StandingHeight(nxt, target.Size)
		if nxtH > curH || s.BoulderIn(nxt, target.Size) {
			emit(ev, Event{Type: EvCollision, Target: target.ID, With: "wall"})
			Deal(s, target, CollisionDamage, True, "collision", ev, false)
			break
		}
		totalDrop += curH - nxtH
		target.Pos = nxt
	}
	if !target.Alive {
		return
	}
	if target.Pos != start {
		emit(ev, Event{Type: EvKnockback, Target: target.ID, From: start, To: target.Pos})
	}
	AddStagger(target, StaggerKnockback, ev)
	if totalDrop > 0 {
		emit(ev, Event{Type: EvFall, Target: target.ID, Levels: totalDrop})
		Deal(s, target, totalDrop*FallDamagePerLevel, True, "fall", ev, false)
		AddStagger(target, totalDrop*StaggerFallPerLevel, ev)
	}
}

func drowns(s *BattleState, u *UnitState, anchor Cell) bool {
	if u.Traits.Flying {
		return false
	}
	for dy := 0; dy < u.Size; dy++ {
		for dx := 0; dx < u.Size; dx++ {
			if s.Grid.TerrainAt(Cell{anchor.X + dx, anchor.Y + dy}) == Deep {
				return true
			}
		}
	}
	return false
}

// sink 是被推出边缘或推进深水；敌人掉进深水淹没的，另记一笔（可选目标用）。
func sink(s *BattleState, u *UnitState, to Cell, ev *[]Event) {
	deep := s.FootprintInBounds(to, u.Size) && drowns(s, u, to)
	edge(s, u, ev)
	if deep && u.Team == TeamEnemy && !u.Alive {
		s.Drowned++
	}
}

func edge(s *BattleState, u *UnitState, ev *[]Event) {
	emit(ev, Event{Type: EvEdge, Target: u.ID})
	if u.Team == TeamEnemy && !u.IsBoss() {
		KnockOut(s, u, ev)
	} else {
		Deal(s, u, EdgeDamage, True, "edge", ev, false)
	}
}

// Throw 是过肩摔：thrower 把相邻的 target 从自己头顶摔到另一侧的相邻格，当场结算。
// 落点出界或是深水按坠出边缘算；落点有人或是更高的地形按撞击算，target 留在原地。
// 落差从 thrower 站的高度算起。
func Throw(s *BattleState, thrower, target *UnitState, source string, ev *[]Event) {
	if !target.Alive {
		return
	}
	start := target.Pos
	dir := Cell{thrower.Pos.X - start.X, thrower.Pos.Y - start.Y}
	dest := thrower.Pos.Add(dir)
	fromH := s.UnitHeight(thrower)
	emit(ev, Event{Type: EvThrow, Unit: thrower.ID, Target: target.ID})
	thrower.Facing = dir
	drop := 0
	if !s.FootprintInBounds(dest, target.Size) || drowns(s, target, dest) {
		sink(s, target, dest, ev)
	} else if hit := s.firstBlocker(dest, target.Size, target); hit != nil {
		emit(ev, Event{Type: EvCollision, Target: target.ID, With: hit.ID})
		Deal(s, target, CollisionDamage, True, "collision", ev, false)
		Deal(s, hit, CollisionDamage, True, "collision", ev, false)
	} else if destH := s.StandingHeight(dest, target.Size); destH > fromH || s.BoulderIn(dest, target.Size) {
		emit(ev, Event{Type: EvCollision, Target: target.ID, With: "wall"})
		Deal(s, target, CollisionDamage, True, "collision", ev, false)
	} else {
		drop = fromH - destH
		target.Pos = dest
		emit(ev, Event{Type: EvKnockback, Target: target.ID, From: start, To: dest})
	}
	if !target.Alive {
		return
	}
	stagger := StaggerKnockback
	if thrower.Traits.Has("stagger_fist") {
		stagger += StaggerFist
	}
	AddStagger(target, stagger, ev)
	if drop > 0 {
		emit(ev, Event{Type: EvFall, Target: target.ID, Levels: drop})
		Deal(s, target, drop*FallDamagePerLevel, True, "fall", ev, false)
		AddStagger(target, drop*StaggerFallPerLevel, ev)
	}
	if target.Alive && thrower.Traits.IronArm {
		Deal(s, target, IronArmThrow, True, source, ev, false)
	}
}
