package rules

import "fmt"

// 神性四阶（15-relics-boons §2）。阶位只由主角拿了几件圣物决定，记在
// ChapterReward.Divinity 里；每一阶给一个好处、一个代价，并让主角长出一个神力招式。
const (
	TierMortal  = iota // 0–1 件
	TierTouched        // 2–3 件：每场第一次用圣物主动不进冷却
	TierDemigod        // 4–5 件：每回合第一次用圣物主动不占行动；同伴不再为主角援护
	TierInhuman        // 6–7 件：主角免疫四种异常状态；主角不能被治疗
)

// TierDivinity 是每升一阶主角神性属性的增量。
const TierDivinity = 3

// ThunderBodyDamage 是雷躯每次回合结算对相邻单位造成的神性伤害。
const ThunderBodyDamage = 6

// PowerPairs 是每一阶二选一的神力招式，下标 0 对应沾染阶。
var PowerPairs = [3][2]string{
	{"thunder_bolt", "sky_fire"},
	{"thunder_step", "sky_dome"},
	{"sky_wrath", "thunder_body"},
}

// TierOf 由圣物件数得出阶位。
func TierOf(relics int) int {
	switch {
	case relics >= 6:
		return TierInhuman
	case relics >= 4:
		return TierDemigod
	case relics >= 2:
		return TierTouched
	}
	return TierMortal
}

// Tier 是这场战斗里主角的阶位。
func (s *BattleState) Tier() int { return TierOf(s.Reward.Divinity) }

// vessel 判断 u 是不是承载神性的那个人。
func vessel(u *UnitState) bool { return u != nil && u.ID == "hero" }

// ValidatePowers 检查选过的神力：按升阶的先后排列，第 i 个必须是第 i 阶那一对里的一个，
// 个数不能超过已经到达的阶位。
func ValidatePowers(relics int, powers []string) string {
	if len(powers) > TierOf(relics) {
		return "more powers than tiers"
	}
	for i, id := range powers {
		if id != PowerPairs[i][0] && id != PowerPairs[i][1] {
			return "power does not belong to its tier"
		}
	}
	return ""
}

// GrantDivinity 把阶位带来的东西加到主角身上：神性属性和选过的神力招式。
// 要在按出战招式栏筛选（Carry）之前调用，神力和别的招式一样占格子。
func (s *BattleState) GrantDivinity(d *Data, reward ChapterReward) error {
	if err := ValidatePowers(reward.Divinity, reward.Powers); err != "" {
		return fmt.Errorf("神力不合法: %s", err)
	}
	hero := s.Unit("hero")
	if hero == nil {
		return nil
	}
	hero.Divinity += TierDivinity * TierOf(reward.Divinity)
	for _, id := range reward.Powers {
		sk := d.Skill(id)
		if sk == nil {
			return fmt.Errorf("没有这个神力招式: %s", id)
		}
		hero.AddSkill(sk)
	}
	return nil
}

// relicUse 结算阶位对圣物主动的好处，在招式照常结算完之后调用。
func relicUse(s *BattleState, u *UnitState, sk *Skill) {
	if !sk.Relic || !vessel(u) {
		return
	}
	tier := s.Tier()
	if tier >= TierTouched && !u.RelicFreeUsed {
		u.RelicFreeUsed = true
		u.SetCooldown(sk.ID, 0)
	}
	if tier >= TierDemigod && !u.RelicSwiftUsed {
		u.RelicSwiftUsed = true
		u.HasActed = false
	}
}

// blastCells 列出以 center 为中心的落点范围：十字（曼哈顿距离）或方形。
func blastHits(center, c Cell, sk *Skill) bool {
	dx, dy := abs(c.X-center.X), abs(c.Y-center.Y)
	if sk.Square {
		return dx <= sk.Blast && dy <= sk.Blast
	}
	return dx+dy <= sk.Blast
}

// BlastTargets 列出落在 center 的范围招式会打到谁。不分敌我的招式连同伴和自己都算。
func BlastTargets(s *BattleState, u *UnitState, sk *Skill, center Cell) []*UnitState {
	var out []*UnitState
	for _, o := range s.Units {
		if !o.Alive || o.Hidden || o.Team == TeamNeutral {
			continue
		}
		if o.Team == u.Team && !sk.FriendlyFire {
			continue
		}
		for _, f := range o.Footprint(o.Pos) {
			if blastHits(center, f, sk) {
				out = append(out, o)
				break
			}
		}
	}
	return out
}

func validateBlast(s *BattleState, u *UnitState, sk *Skill, center Cell) string {
	if !s.Grid.InBounds(center) {
		return "out of range"
	}
	if d := CellDistance(u, center); d < sk.MinRange || d > sk.MaxRange {
		return "out of range"
	}
	for _, o := range BlastTargets(s, u, sk, center) {
		if o.Team != u.Team {
			return ""
		}
	}
	return "no enemy there"
}

func doBlast(s *BattleState, u *UnitState, sk *Skill, center Cell, ev *[]Event) {
	if u.Pos != center {
		u.Facing = facingToward(u.Pos, center)
	}
	u.HasActed = true
	if sk.Cooldown > 0 {
		u.SetCooldown(sk.ID, sk.Cooldown)
	}
	emit(ev, Event{Type: EvArea, Unit: u.ID, Skill: sk.ID, To: center})
	for _, o := range BlastTargets(s, u, sk, center) {
		hit := Compute(s, u, o, sk.Mult, sk.Type, true, NoPos)
		dodged := o.HasStatus("dodge")
		Deal(s, o, hit.Amount, sk.Type, sk.ID, ev, true)
		if !dodged && o.Alive {
			if sk.Status != "" {
				AddStatus(s, o, sk.Status, sk.Rounds, ev, false)
			}
			AddStagger(o, sk.StaggerBonus, ev)
		}
	}
}

func facingToward(from, to Cell) Cell {
	dx, dy := to.X-from.X, to.Y-from.Y
	if abs(dx) >= abs(dy) {
		if dx > 0 {
			return East
		}
		return West
	}
	if dy > 0 {
		return South
	}
	return North
}

// BlinkLandingError 检查瞬移的落点：blink 格以内、能站得下。不看地形消耗和高度。
func BlinkLandingError(s *BattleState, u *UnitState, to Cell, sk *Skill) string {
	if !s.FootprintInBounds(to, u.Size) {
		return "bad landing"
	}
	if d := abs(to.X-u.Pos.X) + abs(to.Y-u.Pos.Y); d < 1 || d > sk.Blink {
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
	return ""
}

func doBlink(s *BattleState, u *UnitState, sk *Skill, to Cell, ev *[]Event) {
	u.HasActed = true
	if sk.Cooldown > 0 {
		u.SetCooldown(sk.ID, sk.Cooldown)
	}
	emit(ev, Event{Type: EvLeap, Unit: u.ID, From: u.Pos, To: to})
	u.Pos = to
	emit(ev, Event{Type: EvArea, Unit: u.ID, Skill: sk.ID, To: to})
	if sk.AreaKnockback <= 0 {
		return
	}
	for _, o := range AreaTargets(s, u, sk) {
		if o.Alive {
			Knockback(s, o, dirToward(u, o), sk.AreaKnockback, sk.ID, ev)
		}
	}
}

// 天穹：自己和半径内的同伴各得一层护盾。
func doWard(s *BattleState, u *UnitState, sk *Skill, ev *[]Event) {
	u.HasActed = true
	if sk.Cooldown > 0 {
		u.SetCooldown(sk.ID, sk.Cooldown)
	}
	emit(ev, Event{Type: EvArea, Unit: u.ID, Skill: sk.ID, To: u.Pos})
	for _, o := range s.Units {
		if !o.Alive || o.Hidden || o.Team != u.Team || Distance(u, o) > sk.Radius {
			continue
		}
		o.Shield += sk.AreaShield
		emit(ev, Event{Type: EvWard, Target: o.ID, Amount: sk.AreaShield})
	}
}

// 雷躯：回合结算时，带着它的单位让相邻的所有人（不分敌我）受神性伤害。
func settleThunderBody(s *BattleState, ev *[]Event) {
	for _, u := range s.Living(TeamAny) {
		if !u.HasStatus("thunder_body") {
			continue
		}
		for _, o := range s.Living(TeamAny) {
			if o == u || o.Hidden || o.Team == TeamNeutral || Distance(u, o) != 1 {
				continue
			}
			Deal(s, o, ThunderBodyDamage, Divine, "thunder_body", ev, false)
		}
	}
}
