package rules

import "fmt"

// 支援：招募来的英雄不上场，不占出战名额。带上一位，主角就多一个"召援"的招式——
// 英雄登场、出手一次、离场。它不占用主角的行动（用完主角照常移动和出手），但要在主角
// 这回合出手之前用；每位英雄各有冷却，开战第一回合用不了。（2026-11-25 定）
//
// 招式表里 support 字段写的是哪一种：
//
//	guard   并肩：把 max_range 格内一名同伴的护盾补到 power 点（不叠加）
//	shot    远射：max_range 格内的一个敌人受 power 点物理伤害，不看掩护和视线
//	sunder  劈盾：max_range 格内的一个敌人受 power 点伤害，不计算防御
//	aid     驮行：max_range 格内的一名同伴回复 power 点生命、解一种异常，还没出手的话可以再走一次
//	break   碎阵：max_range 格内的一个敌人受 power 点物理伤害，外加 stagger_bonus 点破势
//	charge  冲锋：从主角身边起沿直线冲 max_range 格，路上每个敌人受 power 点物理伤害并被击退 knockback 格
//
// 范围都从主角算起：支援是冲着他来的，他站在哪里决定了支援够得着哪里。

// SupportFirstRound 是开战后要等到第几回合才能第一次召援。
const SupportFirstRound = 2

// SupportMove 是这位英雄学了 picks 这些节点之后的那一手：表里的招式加上各节点给的数值。
func (d *Data) SupportMove(who string, picks []string) (*Skill, error) {
	market, err := d.Market()
	if err != nil {
		return nil, err
	}
	hire := market.Recruits[who]
	if hire == nil || hire.Support == "" {
		return nil, fmt.Errorf("%s 不是能来支援的英雄", who)
	}
	if msg := d.ValidateTraining(who, picks, 99); msg != "" {
		return nil, fmt.Errorf("%s 的加点不成立：%s", who, msg)
	}
	move := *d.Skill(hire.Support)
	for _, br := range d.Trees(who) {
		for _, n := range br.Nodes {
			learnt := false
			for _, id := range picks {
				learnt = learnt || id == n.ID
			}
			if !learnt {
				continue
			}
			for _, kv := range n.Support {
				switch kv.Key {
				case "power":
					move.Power += kv.Val
				case "max_range":
					move.MaxRange += kv.Val
				case "cooldown":
					move.Cooldown = max(1, move.Cooldown+kv.Val)
				case "stagger_bonus":
					move.StaggerBonus += kv.Val
				case "knockback":
					move.Knockback += kv.Val
				}
			}
		}
	}
	return &move, nil
}

// GrantSupport 让主角带上一位支援英雄；picks 是这位英雄学了的节点。
func (s *BattleState) GrantSupport(d *Data, who string, picks []string) error {
	if who == "" {
		return nil
	}
	sk, err := d.SupportMove(who, picks)
	if err != nil {
		return err
	}
	hero := s.Unit("hero")
	if hero == nil {
		return nil
	}
	hero.AddSkill(sk)
	hero.SetCooldown(sk.ID, SupportFirstRound-1)
	s.Support = who
	return nil
}

// supportHit 是支援的一击落到目标身上的伤害：固定的 power，照常被防御抵掉，照常有保底。
func supportHit(target *UnitState, power int, pierce bool) int {
	if target.Traits.PhysicalImmune && !target.HasStatus("staggered") || target.HasStatus("impervious_hide") {
		return 0
	}
	if pierce {
		return power
	}
	return max(1, power-target.Defense, FloorInt(float64(power)*MinDamageShare))
}

// chargeLane 列出冲锋经过的格子：从 u 身边沿 dir 方向数 n 格，出了地图或撞上高墙、深水就停。
func chargeLane(s *BattleState, u *UnitState, dir Cell, n int) []Cell {
	var lane []Cell
	at := u.Pos
	for i := 0; i < n; i++ {
		next := at.Add(dir)
		if !s.Grid.InBounds(next) || s.Grid.TerrainAt(next) == Deep || abs(s.Grid.HeightAt(next)-s.Grid.HeightAt(at)) > 1 {
			break
		}
		lane = append(lane, next)
		at = next
	}
	return lane
}

// SupportTargets 列出这一手会落到谁身上（预览和机器人打分用）。
func SupportTargets(s *BattleState, u *UnitState, sk *Skill, cell Cell) []*UnitState {
	if sk.Support != "charge" {
		if t := s.UnitAt(cell); t != nil {
			return []*UnitState{t}
		}
		return nil
	}
	var hit []*UnitState
	seen := map[*UnitState]bool{}
	for _, c := range chargeLane(s, u, cell.Sub(u.Pos), sk.MaxRange) {
		if t := s.UnitAt(c); t != nil && t.Alive && !t.Hidden && t.Team == TeamEnemy && !seen[t] {
			seen[t] = true
			hit = append(hit, t)
		}
	}
	return hit
}

func validateSupport(s *BattleState, u *UnitState, sk *Skill, cell Cell) string {
	if s.Round < SupportFirstRound {
		return "support not here yet"
	}
	if !s.Grid.InBounds(cell) {
		return "out of range"
	}
	if sk.Support == "charge" {
		d := cell.Sub(u.Pos)
		if abs(d.X)+abs(d.Y) != 1 {
			return "pick a direction"
		}
		if len(SupportTargets(s, u, sk, cell)) == 0 {
			return "no enemy in the lane"
		}
		return ""
	}
	target := s.UnitAt(cell)
	if target == nil || !target.Alive || target.Hidden {
		return "no one there"
	}
	if CellDistance(u, target.Pos) > sk.MaxRange {
		return "out of range"
	}
	switch sk.Support {
	case "guard":
		if target.Team != u.Team {
			return "need an ally"
		}
		if target.Shield >= sk.Power {
			return "already shielded"
		}
	case "aid":
		if target.Team != u.Team || target == u {
			return "need an ally"
		}
		if target.ID == "wounded_chiron" || target.DefID == "refugee" {
			return "cannot be helped"
		}
		heals := target.HP < target.MaxHP && !target.HasStatus("blighted") && !(vessel(target) && s.Tier() >= TierInhuman)
		if !heals && cleanseTarget(target) == "" && !(target.HasMoved && !target.HasActed) {
			return "nothing to help"
		}
	default:
		if target.Team != TeamEnemy {
			return "no enemy there"
		}
	}
	return ""
}

func doSupport(s *BattleState, u *UnitState, sk *Skill, cell Cell, ev *[]Event) {
	// 不占主角的行动：HasActed、HasMoved 都不动。
	u.SetCooldown(sk.ID, sk.Cooldown)
	u.undoOK = false
	emit(ev, Event{Type: EvSupport, Unit: u.ID, Skill: sk.ID, To: cell, Source: s.Support})
	switch sk.Support {
	case "guard":
		t := s.UnitAt(cell)
		// 护盾不叠：把他身上的补到 power 点。不然每隔几回合叠一层，越打越厚。
		gain := max(0, sk.Power-t.Shield)
		t.Shield += gain
		emit(ev, Event{Type: EvWard, Target: t.ID, Amount: gain})
	case "aid":
		t := s.UnitAt(cell)
		if t.HP < t.MaxHP && !t.HasStatus("blighted") && !(vessel(t) && s.Tier() >= TierInhuman) {
			gain := min(sk.Power, t.MaxHP-t.HP)
			t.HP += gain
			emit(ev, Event{Type: EvHeal, Target: t.ID, Amount: gain, HP: t.HP})
		}
		if st := cleanseTarget(t); st != "" {
			t.EraseStatus(st)
			emit(ev, Event{Type: EvStatusEnd, Target: t.ID, Status: st})
		}
		if !t.HasActed {
			t.HasMoved = false
			t.undoOK = false
		}
	case "charge":
		dir := cell.Sub(u.Pos)
		hit := SupportTargets(s, u, sk, cell)
		// 先打远处的：近处的被击退时才有地方退。
		for i := len(hit) - 1; i >= 0; i-- {
			t := hit[i]
			Deal(s, t, supportHit(t, sk.Power, false), Physical, sk.ID, ev, false)
			if t.Alive && sk.Knockback > 0 {
				Knockback(s, t, dir, sk.Knockback, sk.ID, ev)
			}
		}
	default: // shot、sunder、break
		t := s.UnitAt(cell)
		Deal(s, t, supportHit(t, sk.Power, sk.Support == "sunder"), Physical, sk.ID, ev, false)
		if t.Alive && sk.StaggerBonus > 0 {
			AddStagger(t, sk.StaggerBonus, ev)
		}
	}
}
