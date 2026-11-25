package rules

import (
	"reflect"
	"slices"
	"testing"
)

// 回合流程、移动、冷却、破势、预览不改状态。

func TestMoveThenUndoRestores(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 1), South)
	StartBattle(s)
	check(t, Perform(s, Move("hero", c(3, 2))).OK, "move")
	eq(t, s.Unit("hero").Pos, c(3, 2), "moved")
	check(t, Perform(s, Simple(ActUndoMove, "hero")).OK, "undo")
	eq(t, s.Unit("hero").Pos, c(1, 1), "restored pos")
	eq(t, s.Unit("hero").Facing, South, "restored facing")
}

func TestCannotUndoAfterActingOrActTwice(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 1))
	foe(s, "wolf", "wolf", c(3, 2))
	StartBattle(s)
	Perform(s, Move("hero", c(2, 2)))
	check(t, Perform(s, UseSkill("hero", "spear", c(3, 2))).OK, "attack")
	eq(t, Perform(s, Simple(ActUndoMove, "hero")).Error, "nothing to undo", "undo")
	eq(t, Perform(s, UseSkill("hero", "spear", c(3, 2))).Error, "already acted", "twice")
}

func TestPreviewDoesNotMutate(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(2, 2))
	foe(s, "wolf", "wolf", c(3, 2))
	StartBattle(s)
	p := Preview(s, UseSkill("hero", "spear", c(3, 2)))
	eq(t, s.Unit("wolf").HP, 16, "untouched")
	check(t, !s.Unit("hero").HasActed, "hero not spent")
	o := Perform(s, UseSkill("hero", "spear", c(3, 2)))
	eq(t, sumDamage(o.Events, ""), sumDamage(p.Events, ""), "preview == perform")
}

func TestClimbAndDropLimits(t *testing.T) {
	s := mkState([]string{"02300", "00000", "00000"})
	hero := ally(s, "hero", "hero", c(0, 0))
	StartBattle(s)
	reach := Reachable(s, hero, -1)
	check(t, reach.CanStop(c(1, 0)), "climb 2 with jump 2")
	eq(t, reach.Cost(c(1, 0)), 3, "1 + 2 levels")
	check(t, !reach.CanStop(c(2, 0)), "height 3 needs 5 move (3 + 1 + 1)")
	high := mkState([]string{"30"})
	h2 := ally(high, "hero", "h2", c(0, 0))
	check(t, !Reachable(high, h2, -1).CanStop(c(1, 0)), "drop of 3 blocked")
}

func TestForestCostAndAtalantaStride(t *testing.T) {
	s := mkState([]string{"0000"}, ".ff.")
	hero := ally(s, "hero", "hero", c(0, 0))
	ata := ally(s, "atalanta", "ata", c(0, 0))
	eq(t, Reachable(s, hero, -1).Cost(c(2, 0)), 4, "hero 2+2")
	eq(t, Reachable(s, ata, -1).Cost(c(2, 0)), 2, "atalanta 1+1")
}

func TestEnemiesBlockAlliesPassThrough(t *testing.T) {
	s := mkState([]string{"00000"})
	hero := ally(s, "hero", "hero", c(0, 0))
	ally(s, "atalanta", "ata", c(1, 0))
	reach := Reachable(s, hero, -1)
	check(t, reach.CanStop(c(2, 0)), "through ally")
	check(t, !reach.CanStop(c(1, 0)), "cannot stop on ally")
	foe(s, "wolf", "wolf", c(3, 0))
	check(t, !Reachable(s, hero, -1).CanStop(c(4, 0)), "enemy blocks")
}

func TestCooldownCountsDownAtRoundEnd(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(2, 2))
	foe(s, "bandit", "b", c(3, 2))
	StartBattle(s)
	Perform(s, UseSkill("hero", "shield_bash", c(3, 2)))
	eq(t, s.Unit("hero").Cooldown("shield_bash"), 2, "set")
	EndPhase(s)
	EndPhase(s)
	eq(t, s.Unit("hero").Cooldown("shield_bash"), 1, "after round 1")
	eq(t, Preview(s, UseSkill("hero", "shield_bash", c(4, 2))).Error, "on cooldown", "still")
}

func TestBossHasTwoActivations(t *testing.T) {
	s := flat(8, 8)
	foe(s, "lion", "lion", c(2, 2))
	StartBattle(s)
	EndPhase(s)
	lion := s.Unit("lion")
	check(t, Perform(s, Wait("lion")).OK, "first")
	check(t, FinishActivation(s, lion), "has a second")
	check(t, Perform(s, Move("lion", c(3, 2))).OK, "second move")
	check(t, !FinishActivation(s, lion), "spent")
}

func TestStaggerBreakStunsAndStripsImmunity(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 2))
	lion := foe(s, "lion", "lion", c(2, 2), East)
	StartBattle(s)
	lion.Stagger = 85
	o := Perform(s, UseSkill("hero", "spear", c(2, 2))) // 背面命中 +20
	check(t, hasEvent(o.Events, EvBroken), "broken")
	check(t, lion.HasStatus("staggered") && lion.HasStatus("stunned"), "statuses")
	ev := EndPhase(s)
	check(t, hasEvent(ev, EvStunSkip), "lion skips enemy phase")
	check(t, lion.HasActed, "spent")
	EndPhase(s) // 第 1 回合结算；进入第 2 回合我方阶段
	check(t, lion.HasStatus("staggered"), "still broken during round 2 player phase")
	hit := Compute(s, s.Unit("hero"), lion, 1.0, Physical, false, NoPos)
	eq(t, hit.Amount, 15, "(12-4) x1.5 back x1.25 broken")
	EndPhase(s)
	EndPhase(s)
	check(t, !lion.HasStatus("staggered"), "window closed after round 2")
}

func TestBossResistsControlUnlessBroken(t *testing.T) {
	s := flat(8, 8)
	lion := foe(s, "lion", "lion", c(2, 2))
	var ev []Event
	check(t, !AddStatus(s, lion, "rooted", 1, &ev, false), "super armor")
	lion.SetStatus("staggered", 1)
	check(t, AddStatus(s, lion, "rooted", 1, &ev, false), "broken boss can be rooted")
}

func TestPathThroughAllyReconstructs(t *testing.T) {
	s := mkState([]string{"00000"})
	ally(s, "hero", "hero", c(0, 0))
	ally(s, "atalanta", "ata", c(1, 0))
	StartBattle(s)
	o := Perform(s, Move("hero", c(2, 0)))
	check(t, o.OK, o.Error)
	check(t, slices.Equal(o.Events[0].Path, []Cell{c(1, 0), c(2, 0)}), "path through ally")
}

func TestRootedUnitCanOnlyStay(t *testing.T) {
	s := flat(8, 8)
	hero := ally(s, "hero", "hero", c(2, 2))
	hero.SetStatus("rooted", 1)
	check(t, slices.Equal(Reachable(s, hero, -1).Dests(), []Cell{c(2, 2)}), "only its own cell")
}

func TestStateCopyIsIndependent(t *testing.T) {
	s := flat(8, 8)
	hero := ally(s, "hero", "hero", c(1, 1))
	hero.SetStatus("guard", 1)
	hero.SetCooldown("shield_bash", 2)
	cp := s.Copy()
	ch := cp.Unit("hero")
	ch.HP -= 5
	ch.Pos = c(3, 3)
	ch.SetStatus("burning", 2)
	ch.SetCooldown("shield_bash", 0)
	ch.AddSkill(&Skill{ID: "x"})
	eq(t, hero.HP, 40, "hp")
	eq(t, hero.Pos, c(1, 1), "pos")
	check(t, !hero.HasStatus("burning"), "statuses")
	eq(t, hero.Cooldown("shield_bash"), 2, "cooldowns")
	check(t, !hero.HasSkill("x"), "skills")
	// 每个字段都必须被复制：防止以后加了字段却忘了复制
	check(t, reflect.DeepEqual(*s.Copy().Unit("hero"), *hero), "every field copied")
	check(t, reflect.DeepEqual(*hero.Copy(), *hero), "unit copy")
}

func TestSignatureTracksStateAndOrder(t *testing.T) {
	s := flat(8, 8)
	hero := ally(s, "hero", "hero", c(1, 1))
	foe(s, "wolf", "wolf", c(5, 5))
	StartBattle(s)
	sig := func(st *BattleState) string { return string(st.AppendSignature(nil)) }
	base := sig(s)
	eq(t, sig(s.Copy()), base, "a copy is the same position")
	hero.SetStatus("guard", 1)
	hero.SetStatus("burning", 2)
	a := sig(s)
	check(t, a != base, "statuses are part of the position")
	hero.Statuses = nil
	hero.SetStatus("burning", 2)
	hero.SetStatus("guard", 1)
	check(t, sig(s) != a, "status order matters, as in the original")
}

// 覆盖目录：同名文件整个替换，只在覆盖目录里有的战斗也会列出来；改写只能动已有的键。
func TestOverlayAndOverrides(t *testing.T) {
	ids, err := testData.BattleIDs()
	if err != nil {
		t.Fatal(err)
	}
	check(t, slices.Equal(ids, []string{"1-1", "1-2", "1-3", "1-4", "1-5", "2-1", "2-2", "test"}), "battles sorted by their order field")

	over, err := LoadData(DataOptions{Overlay: "../testdata/parity/overlay", Sets: []string{"units:wolf.str=11", "skills:spear.max_range=3"}})
	if err != nil {
		t.Fatal(err)
	}
	ids, err = over.BattleIDs()
	if err != nil {
		t.Fatal(err)
	}
	check(t, slices.Equal(ids, []string{"1-1", "1-2", "1-3", "1-4", "1-5", "2-1", "2-2", "1-4x", "test"}), "overlay-only battles are listed too")
	eq(t, over.UnitDef("heracles").Str, 15, "overlay units.json wins")
	eq(t, over.UnitDef("wolf").HP, 18, "overlay units.json wins")
	eq(t, over.UnitDef("wolf").Str, 11, "override applied on top of the overlay")
	eq(t, over.Skill("spear").MaxRange, 3, "override on a table without an overlay file")
	eq(t, testData.UnitDef("wolf").HP, 16, "the base tables are untouched")
	s, err := over.Build("1-4x", nil)
	if err != nil {
		t.Fatal(err)
	}
	check(t, s.Unit("chief") != nil && s.Unit("archer") != nil, "overlay battle has its own units")
	check(t, s.Unit("hero").Traits.IronArm && s.Unit("atalanta").HasSkill("vital_shot"), "default picks applied")

	_, err = LoadData(DataOptions{Sets: []string{"units:wolf.speed=3"}})
	check(t, err != nil, "overrides may only change existing keys")
	_, err = LoadData(DataOptions{Sets: []string{"nonsense"}})
	check(t, err != nil, "malformed override")
}

func TestGuardFacingAfterApproach(t *testing.T) {
	s := flat(8, 8)
	hero := ally(s, "hero", "hero", c(4, 4), West)
	wolf := foe(s, "wolf", "wolf", c(1, 1), North)
	StartBattle(s)
	check(t, Perform(s, Wait(hero.ID)).OK, "player guards")
	eq(t, hero.Facing, West, "player retains chosen facing")
	EndPhase(s)
	check(t, Perform(s, Move(wolf.ID, c(4, 1))).OK, "wolf approaches from west")
	eq(t, wolf.Facing, East, "travel facing")
	p := Preview(s, Wait(wolf.ID))
	check(t, p.OK && hasEvent(p.Events, EvFace), "preview includes guard turn")
	eq(t, wolf.Facing, East, "preview does not rotate wolf")
	Perform(s, Wait(wolf.ID))
	eq(t, wolf.Facing, South, "wolf guards toward hero")
}
