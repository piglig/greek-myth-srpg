package rules

import "testing"

func TestReedMarsh(t *testing.T) {
	state, err := testData.Build("2-2", nil)
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(state)
	hero, snake := state.Unit("hero"), state.Unit("snake_1")

	// 沼泽 3、浅水 2；沼蛇都按 1 算。
	swamp, dry := c(4, 4), c(5, 4)
	eq(t, state.Grid.TerrainAt(swamp), Swamp, "the map has swamp where the test expects it")
	hero.Pos, snake.Pos = c(3, 4), c(13, 9)
	walk := Reachable(state, hero, -1)
	check(t, walk.Cost(swamp) == 3 && walk.Cost(dry) == 4, "swamp costs a walker three, and one dry step beyond is the limit of four")
	snake.Pos, hero.Pos = c(3, 4), c(0, 9)
	eq(t, Reachable(state, snake, -1).Cost(swamp), 1, "the snake crosses swamp at one a cell")

	// 咬中使人中毒；在沼泽里过回合的人中毒并被记一笔，沼蛇不会。
	hero.Pos, snake.Pos = c(5, 4), swamp
	snake.Facing = East
	state.Phase = PhaseEnemy
	bite := Perform(state, UseSkill(snake.ID, "venom_bite", hero.Pos))
	check(t, bite.OK && hero.HasStatus("poisoned"), "the bite poisons: "+bite.Error)
	state.Phase = PhasePlayer
	hero.EraseStatus("poisoned")
	var ev []Event
	SettleRound(state, &ev)
	check(t, !snake.HasStatus("poisoned") && state.SwampRests == 0, "a snake resting in swamp is at home")
	hero.Pos, snake.Pos = swamp, c(13, 9)
	hp := hero.HP
	SettleRound(state, &ev)
	check(t, hero.HasStatus("poisoned") && hero.HP == hp-PoisonDamage, "a walker resting in swamp is poisoned at once")
	eq(t, state.SwampRests, 1, "and it is counted against the optional goal")

	// 活着的人全部站上对岸才算赢；杀光也算。
	eq(t, state.Outcome(), "", "nobody has crossed yet")
	at := 0
	for _, u := range state.Living(TeamPlayer) {
		u.Pos = state.ReachExits[at]
		at++
	}
	eq(t, state.Outcome(), "win", "everyone living stands on the far bank")
	state.Unit("atalanta").Pos = c(0, 0)
	eq(t, state.Outcome(), "", "one left behind keeps the battle going")
	state.Unit("atalanta").Alive = false
	eq(t, state.Outcome(), "win", "the fallen do not hold the rest back")
	hero.Pos = c(0, 0)
	for _, e := range state.Living(TeamEnemy) {
		e.Alive = false
	}
	eq(t, state.Outcome(), "win", "clearing the marsh also ends it")
}
