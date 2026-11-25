package rules

import "testing"

func TestHeraAltar(t *testing.T) {
	state, err := testData.Build("2-4", nil)
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(state)
	hero := state.Unit("hero")
	first, second := state.Unit("priestess_1"), state.Unit("priestess_2")

	// 女祭司给受伤的同伴治疗，自己不上前。
	crab := state.Unit("crab_1")
	crab.Pos, crab.HP = c(8, 3), crab.MaxHP-10
	state.Phase = PhaseEnemy
	plan := PlanFor(state, first)
	check(t, plan.Action.Skill == "hera_blessing" && plan.Action.Target == crab.Pos, "a hurt ally in reach is healed: "+plan.Action.Skill)
	if plan.HasMove {
		check(t, Perform(state, Move(first.ID, plan.MoveTo)).OK, "she steps to where she can reach")
	}
	mend := Perform(state, plan.Action)
	check(t, mend.OK && crab.HP == crab.MaxHP-2, "eight points back: "+mend.Error)
	state.Phase = PhasePlayer
	first.Pos, crab.Pos = c(9, 3), c(13, 9)

	// 带火的招式打在空的林地上，把它点着；不带火的不行，平地也不行。
	medea, err := testData.MakeUnit("medea", "medea", TeamPlayer, c(6, 5), East)
	if err != nil {
		t.Fatal(err)
	}
	state.AddUnit(medea)
	eq(t, state.Grid.TerrainAt(c(9, 4)), Forest, "the grove is where the test expects it")
	check(t, Validate(state, UseSkill(hero.ID, "spear", c(9, 4))) != "", "a spear cannot be thrown at empty trees")
	check(t, Validate(state, UseSkill(medea.ID, "witch_fire", c(8, 5))) != "", "fire needs something to burn")
	lit := Perform(state, UseSkill(medea.ID, "witch_fire", c(9, 4)))
	check(t, lit.OK && state.Grid.TerrainAt(c(9, 4)) == Burning && len(state.Fires) == 1, "the witch's fire takes in the trees: "+lit.Error)
	eq(t, len(state.FireNext()), 3, "the three cells of grove beside it are next")

	// 回合结算：火向相邻的林地各扩一格，站在火里的人被灼烧并记下。
	var ev []Event
	SettleRound(state, &ev)
	check(t, state.Grid.TerrainAt(c(9, 3)) == Burning && state.Grid.TerrainAt(c(10, 4)) == Burning && state.Grid.TerrainAt(c(9, 5)) == Burning, "it spreads one cell each way through the grove")
	eq(t, state.Grid.TerrainAt(c(8, 4)), Plain, "and not across open ground")
	eq(t, state.TargetsScorched(), 0, "nobody was standing in it when it arrived")
	SettleRound(state, &ev)
	check(t, first.HasStatus("burning") && first.Scorched, "a priestess who stays where the fire came is burnt by it")
	eq(t, state.Grid.TerrainAt(c(9, 4)), Plain, "after two rounds the first cell is ash")
	eq(t, state.TargetsScorched(), 1, "one so far")
	SettleRound(state, &ev)
	check(t, second.Scorched, "a round later it has reached the second one too")
	eq(t, state.TargetsScorched(), 3, "all three who stayed in the grove, for the goal aside")
	for i := 0; i < 8; i++ {
		SettleRound(state, &ev)
	}
	eq(t, len(state.Fires), 0, "a grove burns through and goes out")

	// 三名女祭司倒下就赢，别的敌人还在也算。
	eq(t, state.Outcome(), "", "not while one of them stands")
	for _, id := range state.Targets {
		state.Unit(id).Alive = false
	}
	check(t, len(state.Living(TeamEnemy)) > 0, "the guards are still there")
	eq(t, state.Outcome(), "win", "the three priestesses are what the battle is for")
}
