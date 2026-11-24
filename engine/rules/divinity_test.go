package rules

import "testing"

// 神性四阶和神力招式（15-relics-boons §2）。

func divine(t *testing.T, s *BattleState, relics int, powers ...string) *UnitState {
	t.Helper()
	reward := ChapterReward{EquippedRelic: "lion_pelt", Divinity: relics, Powers: powers}
	if err := s.GrantDivinity(testData, reward); err != nil {
		t.Fatal(err)
	}
	s.EquipReward(testData, reward)
	return s.Unit("hero")
}

func TestTiersFollowTheRelicCount(t *testing.T) {
	for relics, tier := range []int{0, 0, 1, 1, 2, 2, 3, 3} {
		eq(t, TierOf(relics), tier, "tier")
	}
	eq(t, ValidatePowers(1, []string{"thunder_bolt"}), "more powers than tiers", "a mortal has none")
	eq(t, ValidatePowers(2, []string{"sky_wrath"}), "power does not belong to its tier", "wrong tier")
	eq(t, ValidatePowers(6, []string{"sky_fire", "sky_dome", "thunder_body"}), "", "one of each pair")
	eq(t, ValidatePowers(6, []string{"sky_fire"}), "", "a choice may still be owed")
}

func TestEachTierRaisesDivinity(t *testing.T) {
	s := flat(8, 8)
	h := heroWith(s, c(2, 2), nil)
	base := h.Divinity
	divine(t, s, 4, "thunder_bolt", "sky_dome")
	eq(t, h.Divinity, base+2*TierDivinity, "two tiers")
	check(t, h.HasSkill("thunder_bolt") && h.HasSkill("sky_dome"), "the chosen powers arrive")
}

func TestTouchedFirstRelicUseHasNoCooldown(t *testing.T) {
	s := flat(8, 8)
	h := heroWith(s, c(2, 2), nil)
	divine(t, s, 2)
	StartBattle(s)
	check(t, Perform(s, UseSkill("hero", "impervious_hide", NoPos)).OK, "first use")
	eq(t, h.Cooldown("impervious_hide"), 0, "the first use of the battle is free of its wait")
	check(t, h.HasActed, "it still takes the action at this tier")
	EndPhase(s)
	EndPhase(s)
	check(t, Perform(s, UseSkill("hero", "impervious_hide", NoPos)).OK, "second use")
	eq(t, h.Cooldown("impervious_hide"), 4, "the second waits as usual")
}

func TestDemigodUsesARelicFreelyAndFightsAlone(t *testing.T) {
	s := flat(8, 8)
	h := heroWith(s, c(2, 2), nil)
	ally(s, "atalanta", "ata", c(4, 3))
	ally(s, "heracles", "her", c(3, 3))
	w := foe(s, "wolf", "wolf", c(3, 2))
	w.MaxHP, w.HP = 90, 90
	divine(t, s, 4)
	StartBattle(s)
	check(t, Perform(s, UseSkill("hero", "impervious_hide", NoPos)).OK, "relic")
	check(t, !h.HasActed, "once a turn a relic costs no action")
	o := Perform(s, UseSkill("hero", "spear", c(3, 2)))
	check(t, o.OK, o.Error)
	check(t, !hasEvent(o.Events, EvAssist), "no one assists a demigod")
	check(t, w.Alive, "the wolf lives")
	o = Perform(s, UseSkill("ata", "shoot", c(3, 2)))
	check(t, o.OK, o.Error)
	check(t, hasEvent(o.Events, EvAssist), "the heroes still assist each other")
}

func TestInhumanShrugsOffAilmentsAndCannotBeHealed(t *testing.T) {
	s := flat(8, 8)
	h := heroWith(s, c(2, 2), nil)
	ch := ally(s, "chiron", "chiron", c(4, 2))
	ch.AddSkill(testData.Skill("purify_arrow"))
	divine(t, s, 6)
	StartBattle(s)
	var ev []Event
	check(t, !AddStatus(s, h, "burning", 2, &ev, false), "no burning")
	check(t, !AddStatus(s, h, "stunned", 1, &ev, false), "no stun")
	h.HP = 10
	eq(t, Preview(s, UseSkill(ch.ID, "purify_arrow", c(2, 2))).Error, "cannot be healed", "beyond mending")
}

func TestThunderBoltStunsAndReaches(t *testing.T) {
	s := flat(8, 8)
	heroWith(s, c(1, 2), nil)
	w := foe(s, "wolf", "wolf", c(5, 2))
	divine(t, s, 2, "thunder_bolt")
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "thunder_bolt", c(5, 2)))
	check(t, o.OK, o.Error)
	check(t, w.HasStatus("stunned"), "stunned")
	// 神性 4 + 3 = 7，x1.2 = 8，减狼的意志
	eq(t, sumDamage(o.Events, "thunder_bolt"), max(1, 8-w.Will), "divine damage")
}

func TestSkyFireBurnsACross(t *testing.T) {
	s := flat(8, 8)
	heroWith(s, c(1, 2), nil)
	a := foe(s, "wolf", "a", c(4, 2))
	b := foe(s, "wolf", "b", c(4, 3))
	far := foe(s, "wolf", "far", c(5, 3))
	friend := ally(s, "atalanta", "ata", c(4, 1))
	divine(t, s, 2, "sky_fire")
	StartBattle(s)
	eq(t, Preview(s, UseSkill("hero", "sky_fire", c(7, 7))).Error, "out of range", "too far")
	o := Perform(s, UseSkill("hero", "sky_fire", c(4, 2)))
	check(t, o.OK, o.Error)
	check(t, a.HasStatus("burning") && b.HasStatus("burning"), "the cell and its neighbours burn")
	check(t, !far.HasStatus("burning"), "the diagonal is spared")
	eq(t, friend.HP, friend.MaxHP, "sky fire spares our own")
}

func TestThunderStepIgnoresHeight(t *testing.T) {
	s := mkState([]string{"00030", "00030", "00030"})
	h := heroWith(s, c(0, 1), nil)
	w := foe(s, "wolf", "wolf", c(4, 1))
	divine(t, s, 4, "sky_fire", "thunder_step")
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "thunder_step", c(3, 1)))
	check(t, o.OK, o.Error)
	eq(t, h.Pos, c(3, 1), "up three levels at once")
	check(t, !h.HasMoved, "it is not his move")
	check(t, !w.Alive || w.Pos != c(4, 1), "whoever stood beside the landing is thrown back")
	eq(t, Preview(s, UseSkill("hero", "thunder_step", c(3, 1))).Error, "already acted", "one action")
}

func TestSkyDomeShieldsThoseNear(t *testing.T) {
	s := flat(8, 8)
	h := heroWith(s, c(2, 2), nil)
	near := ally(s, "atalanta", "ata", c(3, 3))
	far := ally(s, "heracles", "her", c(6, 6))
	foe(s, "wolf", "wolf", c(7, 0))
	divine(t, s, 4, "sky_fire", "sky_dome")
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "sky_dome", NoPos))
	check(t, o.OK, o.Error)
	eq(t, h.Shield, 6, "himself")
	eq(t, near.Shield, 6, "within two")
	eq(t, far.Shield, 0, "too far")
}

func TestSkyWrathSparesNoOne(t *testing.T) {
	s := flat(8, 8)
	heroWith(s, c(1, 1), nil)
	w := foe(s, "wolf", "wolf", c(4, 4))
	friend := ally(s, "atalanta", "ata", c(5, 5))
	divine(t, s, 6, "sky_fire", "sky_dome", "sky_wrath")
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "sky_wrath", c(4, 4)))
	check(t, o.OK, o.Error)
	check(t, !w.Alive || w.HasStatus("burning"), "the enemy is caught")
	check(t, friend.HP < friend.MaxHP && friend.HasStatus("burning"), "so is the friend on the corner")
}

func TestThunderBodyHurtsEveryoneBesideHim(t *testing.T) {
	s := flat(8, 8)
	h := heroWith(s, c(2, 2), nil)
	friend := ally(s, "heracles", "her", c(2, 3))
	lion := foe(s, "lion", "lion", c(3, 2))
	divine(t, s, 6, "sky_fire", "sky_dome", "thunder_body")
	StartBattle(s)
	check(t, Perform(s, UseSkill("hero", "thunder_body", NoPos)).OK, "thunder body")
	EndPhase(s)
	lionHP, friendHP, heroHP := lion.HP, friend.HP, h.HP
	Perform(s, Wait("lion"))
	Perform(s, Wait("lion"))
	ev := EndPhase(s)
	eq(t, sumDamage(ev, "thunder_body"), 2*ThunderBodyDamage, "both neighbours")
	eq(t, lion.HP, lionHP-ThunderBodyDamage, "divine damage passes the hide")
	eq(t, friend.HP, friendHP-ThunderBodyDamage, "a friend is not spared")
	eq(t, h.HP, heroHP, "he is unharmed by it")
}
