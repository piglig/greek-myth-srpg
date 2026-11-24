package rules

import "testing"

// 每条分支的前两个节点（08-skills-hero-atalanta）和战前的技能点预算。

func heroWith(s *BattleState, pos Cell, picks []string, facing ...Cell) *UnitState {
	u := ally(s, "hero", "hero", pos, facing...)
	testData.ApplyPicks(u, picks)
	return u
}

func ataWith(s *BattleState, pos Cell, picks []string) *UnitState {
	u := ally(s, "atalanta", "ata", pos)
	testData.ApplyPicks(u, picks)
	return u
}

func TestBudgetAndPrerequisites(t *testing.T) {
	d := testData
	eq(t, d.ValidatePicks("hero", []string{"slam", "iron_arm", "shield_wall"}), "", "4 points ok")
	eq(t, d.ValidatePicks("hero", []string{"slam", "iron_arm", "shield_wall", "intercept"}), "over budget", "6 points")
	eq(t, d.ValidatePicks("hero", []string{"iron_arm"}), "missing prerequisite", "node 2 needs node 1")
	eq(t, d.ValidatePicks("atalanta", d.DefaultPicks()["atalanta"]), "", "default atalanta")
	eq(t, len(d.AllBuilds("hero")), 12, "hero builds within 4 points")
}

func TestShieldWallProtectsGuardedNeighbours(t *testing.T) {
	s := flat(8, 8)
	heroWith(s, c(2, 2), []string{"shield_wall"})
	ally(s, "atalanta", "ata", c(3, 2))
	foe(s, "wolf", "wolf", c(4, 2))
	StartBattle(s)
	Perform(s, Wait("hero"))
	EndPhase(s)
	o := Perform(s, UseSkill("wolf", "bite", c(3, 2)))
	// 狼 9 - 阿塔兰忒防御 3 = 6，x0.85 = 5.1 -> 5
	eq(t, sumDamage(o.Events, "bite"), 5, "shield wall")
}

func TestInterceptRedirectsOncePerRound(t *testing.T) {
	s := flat(8, 8)
	heroWith(s, c(2, 2), []string{"shield_wall", "intercept"})
	ally(s, "atalanta", "ata", c(3, 2))
	foe(s, "wolf", "w1", c(4, 2))
	foe(s, "wolf", "w2", c(3, 3), North)
	StartBattle(s)
	EndPhase(s)
	o := Perform(s, UseSkill("w1", "bite", c(3, 2)))
	check(t, hasEvent(o.Events, EvIntercept), "intercepted")
	eq(t, s.Unit("ata").HP, 30, "atalanta untouched")
	check(t, s.Unit("hero").HP < 40, "hero took it")
	o2 := Perform(s, UseSkill("w2", "bite", c(3, 2)))
	check(t, !hasEvent(o2.Events, EvIntercept), "only once per round")
	check(t, s.Unit("ata").HP < 30, "second bite lands")
}

func TestIronArmChokeAndDamageReduction(t *testing.T) {
	s := flat(8, 8)
	heroWith(s, c(2, 2), []string{"slam", "iron_arm"})
	foe(s, "bandit", "b", c(3, 2))
	StartBattle(s)
	Perform(s, Grapple("hero", c(3, 2)))
	EndPhase(s)
	o := Perform(s, UseSkill("b", "slash", c(2, 2)))
	// (10 - 6) = 4 x0.7 被擒抱 x0.8 铁臂 = 2.24 -> 2
	eq(t, sumDamage(o.Events, "slash"), 2, "reduced")
	ev := EndPhase(s)
	eq(t, sumDamage(ev, "choke"), 7, "4 + 3 choke")
}

func TestSlamThrowsOffALedge(t *testing.T) {
	s := mkState([]string{"2200", "2200"})
	heroWith(s, c(0, 0), []string{"slam"})
	foe(s, "wolf", "wolf", c(1, 0))
	StartBattle(s)
	Perform(s, Grapple("hero", c(1, 0)))
	EndPhase(s)
	EndPhase(s)
	o := Perform(s, Slam("hero", c(2, 0)))
	check(t, o.OK, o.Error)
	eq(t, s.Unit("wolf").Pos, c(2, 0), "thrown east")
	eq(t, sumDamage(o.Events, "fall"), 6, "2 levels")
	eq(t, s.Unit("hero").GrapplingID, "", "grapple over")
	s.Unit("hero").HasActed = false
	eq(t, Preview(s, Slam("hero", c(3, 0))).Error, "cannot slam", "needs a hold")
}

func TestPatienceRewardsStandingStill(t *testing.T) {
	s := flat(8, 8)
	ataWith(s, c(0, 2), []string{"vital_shot", "patience"})
	foe(s, "wolf", "wolf", c(3, 2))
	StartBattle(s)
	// (11 - 1) x1.25 = 12
	eq(t, sumDamage(Preview(s, UseSkill("ata", "shoot", c(3, 2))).Events, "shoot"), 12, "still")
	Perform(s, Move("ata", c(0, 3)))
	eq(t, sumDamage(Preview(s, UseSkill("ata", "shoot", c(3, 2))).Events, "shoot"), 10, "moved")
}

func TestVitalShotFlankOnMarkedBossAddsStagger(t *testing.T) {
	s := flat(10, 6)
	ataWith(s, c(0, 2), []string{"vital_shot"})
	foe(s, "lion", "lion", c(4, 2), East)
	StartBattle(s)
	Perform(s, Mark("ata", c(4, 2)))
	Perform(s, UseSkill("ata", "vital_shot", c(4, 2)))
	eq(t, s.Unit("lion").Stagger, 35, "back 20 + marked flank 15")
}

func TestSkirmishMovesAfterAttacking(t *testing.T) {
	s := flat(8, 8)
	ataWith(s, c(0, 2), []string{"skirmish"})
	foe(s, "wolf", "wolf", c(3, 2))
	StartBattle(s)
	Perform(s, UseSkill("ata", "shoot", c(3, 2)))
	eq(t, s.Unit("ata").PostMove, 2, "bonus granted")
	eq(t, Preview(s, Move("ata", c(0, 5))).Error, "unreachable", "3 is too far")
	check(t, Perform(s, Move("ata", c(0, 4))).OK, "2 tiles")
	eq(t, Preview(s, Move("ata", c(0, 3))).Error, "cannot move now", "spent")
}

func TestLeapShotLandsHighThenShoots(t *testing.T) {
	s := mkState([]string{"0300000", "0000000"})
	ataWith(s, c(0, 0), []string{"skirmish", "leap_shot"})
	foe(s, "wolf", "wolf", c(5, 0))
	StartBattle(s)
	eq(t, Preview(s, UseSkill("ata", "leap_shot", c(5, 0))).Error, "need landing", "landing required")
	act := LeapSkill("ata", "leap_shot", c(5, 0), c(1, 0))
	o := Perform(s, act)
	check(t, o.OK, o.Error)
	eq(t, s.Unit("ata").Pos, c(1, 0), "on the pillar")
	// floor(11 x0.8) = 8 - 1 = 7，x1.2 高处 = 8
	eq(t, sumDamage(o.Events, "leap_shot"), 8, "shot from height")
	s2 := mkState([]string{"0400000"})
	ataWith(s2, c(0, 0), []string{"skirmish", "leap_shot"})
	foe(s2, "wolf", "wolf", c(5, 0))
	StartBattle(s2)
	eq(t, Preview(s2, act).Error, "bad landing", "4 levels is too high")
}

func TestChironMedicineAndMentorship(t *testing.T) {
	s := flat(8, 8)
	u := ally(s, "chiron", "chiron", c(1, 2))
	ward := ally(s, "hero", "hero", c(3, 2))
	enemy := foe(s, "bandit_chief", "chief", c(1, 5))
	StartBattle(s)
	testData.ApplyPicks(u, []string{"purify_arrow", "field_medicine"})
	ward.HP = 10
	ward.SetStatus("poisoned", 2)
	ward.SetStatus("burning", 1)
	check(t, Validate(s, UseSkill(u.ID, "purify_arrow", enemy.Pos)) != "", "no enemy healing")
	o := Perform(s, UseSkill(u.ID, "purify_arrow", ward.Pos))
	check(t, o.OK && hasEvent(o.Events, EvHeal), "medicine resolves")
	eq(t, ward.HP, 22, "critical healing")
	check(t, !ward.HasStatus("burning") && ward.HasStatus("poisoned"), "exactly one condition cleansed")
	check(t, u.HasActed && u.Cooldown("purify_arrow") > 0, "medicine costs an action and cooldown")

	s = flat(8, 8)
	u = ally(s, "chiron", "chiron", c(1, 2))
	enemy = foe(s, "bandit_chief", "chief", c(1, 5))
	enemy.StaggerMax = 100
	StartBattle(s)
	testData.ApplyPicks(u, []string{"weak_point", "mentor_stagger"})
	enemy.Defense = 4
	plain := Compute(s, u, enemy, 0.8, Physical, true, NoPos).Amount
	hp := enemy.HP
	o = Perform(s, UseSkill(u.ID, "weak_point", enemy.Pos))
	check(t, o.OK && enemy.Stagger >= 20, "weak point staggers")
	check(t, len(enemy.Statuses) == 0, "and leaves no status behind")
	check(t, hp-enemy.HP > plain, "the shot finds the gap: armour does not count")

	s = flat(8, 8)
	u = ally(s, "chiron", "chiron", c(1, 2))
	enemy = foe(s, "bandit_chief", "chief", c(1, 5))
	enemy.Defense = 0
	StartBattle(s)
	testData.ApplyPicks(u, []string{"weak_point", "mentor_stagger", "keen_eye"})
	full := Compute(s, u, enemy, 1.0, Physical, true, NoPos).Amount
	hp = enemy.HP
	o = Perform(s, UseSkill(u.ID, "weak_point", enemy.Pos))
	check(t, o.OK && hp-enemy.HP == full, "keen eye: the shot lands at full strength")
}

func TestMedeaFireAndHex(t *testing.T) {
	s := flat(8, 8)
	u := ally(s, "medea", "medea", c(1, 2))
	enemy := foe(s, "bandit_chief", "chief", c(1, 5))
	StartBattle(s)
	testData.ApplyPicks(u, []string{"kindling", "solar_flame"})
	first := Compute(s, u, enemy, 1.5, Divine, true, NoPos)
	o := Perform(s, UseSkill(u.ID, "solar_flame", enemy.Pos))
	second := Compute(s, u, enemy, 1.5, Divine, true, NoPos)
	check(t, o.OK && enemy.HasStatus("burning") && !first.Notes.Has(NoteKindling) && second.Notes.Has(NoteKindling) && second.Amount > first.Amount, "fire enables next strike")
	s = flat(8, 8)
	u = ally(s, "medea", "medea", c(1, 2))
	enemy = foe(s, "bandit_chief", "chief", c(1, 5))
	StartBattle(s)
	testData.ApplyPicks(u, []string{"frailty", "lingering_hex"})
	o = Perform(s, UseSkill(u.ID, "frailty", enemy.Pos))
	duration, _ := enemy.Status("poisoned")
	check(t, o.OK && duration == 4, "the marrow hex poisons, and lingers a round longer")

	// 长夜咒：非首领眩晕一回合，首领不受。
	s = flat(8, 8)
	u = ally(s, "medea", "medea", c(1, 2))
	enemy = foe(s, "bandit", "raider", c(1, 5))
	StartBattle(s)
	testData.ApplyPicks(u, []string{"frailty", "bind_hex", "night_hex"})
	o = Perform(s, UseSkill(u.ID, "night_hex", enemy.Pos))
	check(t, o.OK && enemy.HasStatus("stunned") && u.Cooldown("night_hex") == 5, "the long night stuns")
}

// 游戏里只有四种异常状态；数据里出现别的就不该读得进来。
func TestOnlyFourAilments(t *testing.T) {
	for id, sk := range testData.skills {
		for _, given := range []string{sk.Status, sk.AreaStatus} {
			check(t, given == "" || IsAilment(given), id+" gives a status outside the four: "+given)
		}
	}
	for _, gone := range []string{"feared", "weakened", "exposed"} {
		check(t, !IsAilment(gone) && statusNames[gone] == "", gone+" is no longer a status")
	}
}

func TestBranchTraining(t *testing.T) {
	picks := []string{"weak_point", "repel_arrow", "centaur_volley"}
	eq(t, testData.ValidateTraining("chiron", picks, 7), "", "sibling node is optional")
	eq(t, testData.ValidateTraining("chiron", picks, 6), "over budget", "current level budget")
	eq(t, testData.ValidateTraining("chiron", []string{"weak_point", "centaur_volley"}, 9), "missing prerequisite", "cannot skip branch")
	s := flat(8, 8)
	u := ally(s, "chiron", "chiron", c(1, 2))
	testData.ApplyPicks(u, picks)
	check(t, u.HasSkill("centaur_volley") && !u.Traits.Has("mentor_stagger"), "learned leaf independent from other path")
}
