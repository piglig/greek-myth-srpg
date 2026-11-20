package rules

import "testing"

// 伤害公式的算例，出自 07-combat-rules §4 和 09-chapter-1 §4。

func TestSpearVsWolfFrontIs11(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(2, 2))
	foe(s, "wolf", "wolf", c(3, 2))
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "spear", c(3, 2)))
	check(t, o.OK, o.Error)
	eq(t, sumDamage(o.Events, "spear"), 11, "12 str - 1 def")
}

func TestSpearVsBanditFront9Back13(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(2, 2))
	foe(s, "bandit", "front", c(3, 2), West)
	foe(s, "bandit", "back", c(2, 3), South)
	StartBattle(s)
	eq(t, sumDamage(Preview(s, UseSkill("hero", "spear", c(3, 2))).Events, "spear"), 9, "front")
	eq(t, sumDamage(Preview(s, UseSkill("hero", "spear", c(2, 3))).Events, "spear"), 13, "back 9 x1.5")
}

func TestSpearReachesTwoTilesInALineOnly(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(2, 2))
	foe(s, "wolf", "line", c(4, 2))
	foe(s, "wolf", "diag", c(3, 3))
	StartBattle(s)
	check(t, Preview(s, UseSkill("hero", "spear", c(4, 2))).OK, "two tiles in line")
	eq(t, Preview(s, UseSkill("hero", "spear", c(3, 3))).Error, "not in line", "diagonal")
}

func TestHighGroundBonus(t *testing.T) {
	s := mkState([]string{"0000", "0100", "0000"})
	ally(s, "hero", "hero", c(1, 1))
	foe(s, "wolf", "wolf", c(2, 1))
	StartBattle(s)
	eq(t, sumDamage(Preview(s, UseSkill("hero", "spear", c(2, 1))).Events, "spear"), 13, "11 x1.2")
}

func TestChiefBlocksFrontNotBack(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(2, 2))
	foe(s, "bandit_chief", "chief", c(3, 2), West)
	StartBattle(s)
	eq(t, sumDamage(Preview(s, UseSkill("hero", "spear", c(3, 2))).Events, "spear"), 4, "8 x0.5")
	s.Unit("chief").Facing = East
	eq(t, sumDamage(Preview(s, UseSkill("hero", "spear", c(3, 2))).Events, "spear"), 12, "8 x1.5")
}

func TestLionImmuneButBackHitBuildsStagger(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 2))
	foe(s, "lion", "lion", c(2, 2), East)
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "spear", c(2, 2)))
	eq(t, sumDamage(o.Events, "spear"), 0, "physical immune")
	eq(t, s.Unit("lion").HP, 60, "lion hp unchanged")
	eq(t, s.Unit("lion").Stagger, 20, "back hit stagger")
}

func TestBrokenLionTakesBoostedPhysicalDamage(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 2))
	lion := foe(s, "lion", "lion", c(2, 2), West)
	StartBattle(s)
	lion.SetStatus("staggered", 2)
	eq(t, sumDamage(Preview(s, UseSkill("hero", "spear", c(2, 2))).Events, "spear"), 10, "(12-4) x1.25")
}

func TestForestCoverReducesRanged(t *testing.T) {
	s := mkState([]string{"000000", "000000", "000000"}, "......", "...f..", "......")
	ally(s, "atalanta", "ata", c(0, 1))
	foe(s, "bandit", "bandit", c(3, 1))
	StartBattle(s)
	eq(t, sumDamage(Preview(s, UseSkill("ata", "shoot", c(3, 1))).Events, "shoot"), 6, "8 x0.75")
}

func TestMarkBoostsDamage(t *testing.T) {
	s := flat(8, 8)
	ally(s, "atalanta", "ata", c(0, 2))
	foe(s, "wolf", "wolf", c(3, 2))
	StartBattle(s)
	check(t, Perform(s, Mark("ata", c(3, 2))).OK, "mark")
	eq(t, sumDamage(Preview(s, UseSkill("ata", "shoot", c(3, 2))).Events, "shoot"), 11, "10 x1.15")
	eq(t, Perform(s, Mark("ata", c(3, 2))).Error, "cannot mark", "once per round")
}

func TestAtalantaCannotShootAdjacent(t *testing.T) {
	s := flat(8, 8)
	ally(s, "atalanta", "ata", c(2, 2))
	foe(s, "wolf", "wolf", c(3, 2))
	StartBattle(s)
	eq(t, Preview(s, UseSkill("ata", "shoot", c(3, 2))).Error, "out of range", "adjacent")
}

func TestFlankAndAssist(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(2, 2))
	ally(s, "heracles", "her", c(4, 2), West)
	foe(s, "wolf", "wolf", c(3, 2), West)
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "spear", c(3, 2)))
	eq(t, sumDamage(o.Events, "spear"), 12, "front 11 x1.1 flank")
	// 赫拉克勒斯从背后援护：floor(20*0.3)=6 - 1 = 5，x1.5 背面 x1.1 包夹 = 8
	eq(t, sumDamage(o.Events, "assist"), 8, "assist")
	check(t, s.Unit("her").AssistUsed, "assist consumed")
}

func TestLowBumpDoesNotBlockLineOfSight(t *testing.T) {
	s := mkState([]string{"010000", "000000"})
	ally(s, "atalanta", "ata", c(0, 0))
	foe(s, "wolf", "wolf", c(3, 0))
	StartBattle(s)
	check(t, Preview(s, UseSkill("ata", "shoot", c(3, 0))).OK, "one-level bump")
	s.Grid.SetHeight(c(1, 0), 2)
	eq(t, Preview(s, UseSkill("ata", "shoot", c(3, 0))).Error, "no line of sight", "two-level wall")
}
