package rules

import "testing"

// 擒抱与挣脱（07-combat-rules §7.1）；击退、坠落、碰撞和边缘（§5.1）。

func TestEscapeValuesFromDocs(t *testing.T) {
	hero := mk("hero", "h", TeamPlayer, Cell{}, South)
	heracles := mk("heracles", "x", TeamPlayer, Cell{}, South)
	lion := mk("lion", "l", TeamEnemy, Cell{}, South)
	wolf := mk("wolf", "w", TeamEnemy, Cell{}, South)
	eq(t, EscapeValue(hero, lion), 1, "hero vs lion")
	eq(t, EscapeValue(heracles, lion), 3, "heracles vs lion")
	eq(t, EscapeValue(hero, wolf), 3, "hero vs wolf")
}

func TestHeroHoldsLionForOneSettlement(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 2))
	foe(s, "lion", "lion", c(2, 2), South)
	StartBattle(s)
	o := Perform(s, Grapple("hero", c(2, 2)))
	check(t, o.OK, o.Error)
	lion := s.Unit("lion")
	eq(t, lion.Escape, 1, "escape")
	eq(t, lion.Facing, West, "facing locked toward grappler")
	EndPhase(s)       // 进入敌方阶段；狮子选择不挣扎
	ev := EndPhase(s) // 回合结算
	eq(t, sumDamage(ev, "choke"), 4, "choke is true damage through immunity")
	eq(t, lion.HP, 56, "lion hp")
	eq(t, lion.Stagger, 15, "grapple tick stagger")
	eq(t, lion.GrappledByID, "", "escaped after countdown")
	eq(t, s.Unit("hero").GrapplingID, "", "grappler released")
}

func TestStruggleSpendsAnActionAndEscapes(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 2))
	foe(s, "lion", "lion", c(2, 2))
	StartBattle(s)
	Perform(s, Grapple("hero", c(2, 2)))
	EndPhase(s)
	o := Perform(s, Simple(ActStruggle, "lion"))
	check(t, o.OK, o.Error)
	eq(t, s.Unit("lion").GrappledByID, "", "free")
	check(t, FinishActivation(s, s.Unit("lion")), "lion still has its second action")
	ev := EndPhase(s)
	eq(t, sumDamage(ev, "choke"), 0, "no choke after escape")
}

func TestGrappledUnitOnlyHitsGrapplerAt70Percent(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(2, 2))
	ally(s, "atalanta", "ata", c(3, 3))
	foe(s, "wolf", "wolf", c(3, 2))
	StartBattle(s)
	Perform(s, Grapple("hero", c(3, 2)))
	EndPhase(s)
	eq(t, Preview(s, UseSkill("wolf", "bite", c(3, 3))).Error, "grappled: can only strike the grappler", "other target")
	o := Perform(s, UseSkill("wolf", "bite", c(2, 2)))
	check(t, o.OK, o.Error)
	eq(t, sumDamage(o.Events, "bite"), 2, "(9-6) x0.7")
	eq(t, Preview(s, Move("wolf", c(4, 2))).Error, "grappled", "cannot move")
}

func TestReinforceRaisesEscapeUpToCap(t *testing.T) {
	s := flat(8, 8)
	ally(s, "heracles", "her", c(1, 2))
	foe(s, "lion", "lion", c(2, 2))
	StartBattle(s)
	Perform(s, Grapple("her", c(2, 2)))
	eq(t, s.Unit("lion").Escape, 3, "start at boss cap")
	EndPhase(s)
	EndPhase(s) // 结算：3 -> 2
	eq(t, s.Unit("lion").Escape, 2, "after one settlement")
	check(t, Perform(s, Simple(ActReinforce, "her")).OK, "reinforce")
	eq(t, s.Unit("lion").Escape, 3, "back to cap")
}

func TestKnockbackBreaksGrapple(t *testing.T) {
	s := flat(8, 8)
	ally(s, "heracles", "her", c(3, 1))
	ally(s, "hero", "hero", c(2, 2))
	foe(s, "wolf", "wolf", c(3, 2), West)
	StartBattle(s)
	Perform(s, Grapple("her", c(3, 2)))
	o := Perform(s, UseSkill("hero", "shield_bash", c(3, 2)))
	check(t, o.OK, o.Error)
	eq(t, s.Unit("wolf").Pos, c(4, 2), "pushed east")
	eq(t, s.Unit("her").GrapplingID, "", "grapple ended")
	check(t, hasEvent(o.Events, EvGrappleEnd), "grapple_end event")
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
