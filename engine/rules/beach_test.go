package rules

import "testing"

func TestCrabBeach(t *testing.T) {
	state, err := testData.Build("2-3", nil)
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(state)
	hero, crab := state.Unit("hero"), state.Unit("crab_1")

	// 正面减半，背后不减。
	hero.Pos, crab.Pos = c(2, 3), c(3, 3)
	hero.Facing, crab.Facing = East, West
	hp := crab.HP
	front := Perform(state, UseSkill(hero.ID, "spear", crab.Pos))
	check(t, front.OK, "the spear lands: "+front.Error)
	taken := hp - crab.HP
	crab.HP, crab.Facing = hp, East
	hero.HasActed, hero.ActionsLeft = false, 1
	back := Perform(state, UseSkill(hero.ID, "spear", crab.Pos))
	check(t, back.OK, "the spear lands again: "+back.Error)
	check(t, hp-crab.HP > 2*taken, "its shell halves what comes from the front, and nothing from behind")

	// 钳住的人被束缚。
	crab.HP, crab.Facing = hp, West
	state.Phase = PhaseEnemy
	grip := Perform(state, UseSkill(crab.ID, "claw_grip", hero.Pos))
	check(t, grip.OK && hero.HasStatus("rooted"), "the claw holds: "+grip.Error)
	state.Phase = PhasePlayer

	// 推进深水直接出局，并记一笔；推出地图边缘不记。
	eq(t, state.Grid.TerrainAt(c(5, 4)), Deep, "the tide pool is where the test expects it")
	crab.Pos = c(4, 4)
	var ev []Event
	Knockback(state, crab, East, 1, "test", &ev)
	check(t, !crab.Alive && state.Drowned == 1, "pushed into the pool, it is gone and counted")
	other := state.Unit("crab_2")
	other.Pos = c(13, 3)
	Knockback(state, other, East, 1, "test", &ev)
	check(t, !other.Alive && state.Drowned == 1, "off the edge of the map is not drowning")
}
