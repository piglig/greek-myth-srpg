package rules

import "testing"

// 过肩摔；击退、坠落、碰撞和边缘（07-combat-rules §5.1）。

func TestShoulderThrowLandsOnTheFarSide(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(2, 2))
	foe(s, "wolf", "wolf", c(3, 2))
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "shoulder_throw", c(3, 2)))
	check(t, o.OK, o.Error)
	check(t, hasEvent(o.Events, EvThrow), "throw event")
	eq(t, s.Unit("wolf").Pos, c(1, 2), "over the hero to the west")
	eq(t, s.Unit("hero").Facing, West, "the hero turns with the throw")
	eq(t, sumDamage(o.Events, "fall"), 0, "level ground")
	check(t, s.Unit("hero").HasActed, "one action, settled at once")
}

func TestShoulderThrowOffALedge(t *testing.T) {
	// 主角站在 2 层台地边上，背后是谷底
	s := mkState([]string{"0220", "0220"})
	ally(s, "hero", "hero", c(1, 0))
	foe(s, "wolf", "wolf", c(2, 0))
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "shoulder_throw", c(2, 0)))
	check(t, o.OK, o.Error)
	eq(t, s.Unit("wolf").Pos, c(0, 0), "thrown down behind the hero")
	eq(t, sumDamage(o.Events, "fall"), 6, "2 levels x3")
}

func TestShoulderThrowIntoSomeoneHurtsBoth(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(2, 2))
	foe(s, "wolf", "w1", c(3, 2))
	foe(s, "wolf", "w2", c(1, 2))
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "shoulder_throw", c(3, 2)))
	check(t, o.OK, o.Error)
	eq(t, s.Unit("w1").Pos, c(3, 2), "nowhere to land: stays put")
	eq(t, sumDamage(o.Events, "collision"), 6, "both take the collision")
}

func TestShoulderThrowOverTheEdgeKills(t *testing.T) {
	s := flat(4, 4)
	ally(s, "hero", "hero", c(0, 1))
	foe(s, "wolf", "wolf", c(1, 1))
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "shoulder_throw", c(1, 1)))
	check(t, hasEvent(o.Events, EvEdge), "edge event")
	check(t, !s.Unit("wolf").Alive, "wolf gone")
}

func TestBigTargetsCannotBeThrown(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 2))
	foe(s, "lion", "lion", c(2, 2))
	StartBattle(s)
	eq(t, Preview(s, UseSkill("hero", "shoulder_throw", c(2, 2))).Error, "cannot throw that", "2x2")
}

func TestBoarPushedOffThreeLevelCliffTakes9(t *testing.T) {
	// 野猪（2x2）站在 3 层台地上；第 3 列起是谷底
	s := mkState([]string{"333000", "333000", "000000"})
	ally(s, "heracles", "her", c(0, 0))
	foe(s, "boar", "boar", c(1, 0), East)
	StartBattle(s)
	o := Perform(s, UseSkill("her", "club", c(1, 0)))
	check(t, o.OK, o.Error)
	eq(t, s.Unit("boar").Pos, c(3, 0), "pushed 2 tiles")
	eq(t, sumDamage(o.Events, "fall"), 9, "3 levels x3")
}

func TestEdgeKillsNormalEnemy(t *testing.T) {
	s := flat(4, 4)
	ally(s, "hero", "hero", c(2, 1))
	foe(s, "wolf", "wolf", c(3, 1))
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "shield_bash", c(3, 1)))
	check(t, hasEvent(o.Events, EvEdge), "edge event")
	check(t, !s.Unit("wolf").Alive, "wolf gone")
}

func TestEdgeHurtsPlayersInsteadOfKilling(t *testing.T) {
	s := flat(4, 4)
	foe(s, "bandit", "b", c(1, 1))
	s.AddUnit(mk("hero", "hero", TeamPlayer, c(0, 1), South))
	s.Unit("b").AddSkill(testData.Skill("gore"))
	StartBattle(s)
	EndPhase(s)
	o := Perform(s, UseSkill("b", "gore", c(0, 1)))
	check(t, o.OK, o.Error)
	check(t, s.Unit("hero").Alive, "hero survives")
	eq(t, sumDamage(o.Events, "edge"), 10, "edge damage")
}

func TestCollisionHurtsBoth(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 1))
	foe(s, "wolf", "a", c(2, 1))
	foe(s, "wolf", "b", c(3, 1))
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "shield_bash", c(2, 1)))
	eq(t, sumDamage(o.Events, "collision"), 6, "3 each")
	eq(t, s.Unit("a").Pos, c(2, 1), "did not move")
}

func TestWallStopsKnockback(t *testing.T) {
	s := mkState([]string{"0020"})
	ally(s, "hero", "hero", c(0, 0))
	foe(s, "wolf", "wolf", c(1, 0))
	StartBattle(s)
	o := Perform(s, UseSkill("hero", "shield_bash", c(1, 0)))
	eq(t, s.Unit("wolf").Pos, c(1, 0), "blocked by higher cell")
	eq(t, sumDamage(o.Events, "collision"), 3, "wall bump")
}

func TestBossKnockbackAndFallBuildStagger(t *testing.T) {
	s := mkState([]string{"33300", "33300", "00000"})
	ally(s, "heracles", "her", c(0, 0))
	foe(s, "lion", "lion", c(1, 0), West)
	StartBattle(s)
	Perform(s, UseSkill("her", "club", c(1, 0)))
	// 正面命中：破势 0；击退 +15；坠落 3 层 +15
	eq(t, s.Unit("lion").Stagger, 30, "knockback + fall stagger")
	eq(t, s.Unit("lion").HP, 51, "fall damage is true damage")
}
