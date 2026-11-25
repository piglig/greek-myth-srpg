package rules

import "testing"

func TestHydra(t *testing.T) {
	state, err := testData.Build("2-5", nil)
	if err != nil {
		t.Fatal(err)
	}
	medea, err := testData.MakeUnit("medea", "medea", TeamPlayer, c(2, 4), East)
	if err != nil {
		t.Fatal(err)
	}
	state.AddUnit(medea)
	StartBattle(state)
	hero, head := state.Unit("hero"), state.Unit("head_1")

	// 头不会动，推不动，摔不动。
	eq(t, len(Reachable(state, head, -1).Dests()), 1, "a head stays where it grows")
	hero.Pos = c(4, 4)
	hero.Facing = East
	at := head.Pos
	bash := Perform(state, UseSkill(hero.ID, "shield_bash", head.Pos))
	check(t, bash.OK && head.Pos == at, "a shield does not move it: "+bash.Error)
	check(t, Validate(state, UseSkill(hero.ID, "shoulder_throw", head.Pos)) != "", "nor can it be thrown")

	// 砸掉的头留下断颈，两次回合结算后长回来。
	var ev []Event
	KnockOut(state, head, &ev)
	check(t, !head.Alive && head.Regrow == RegrowRounds && state.StumpAt(at) == head, "a severed head leaves a stump")
	for _, id := range []string{"head_2", "head_3", "head_4", "head_5"} {
		other := state.Unit(id)
		other.SetStatus("burning", 2)
		KnockOut(state, other, &ev)
		check(t, other.Sealed && other.Regrow == 0, "a head that falls burning is sealed at once")
	}
	eq(t, state.Outcome(), "", "one stump unsealed: not over")
	hero.Pos = c(1, 5)
	SettleRound(state, &ev)
	check(t, !head.Alive && head.Regrow == 1, "one round: still a stump")
	SettleRound(state, &ev)
	check(t, head.Alive && head.HP == head.MaxHP && head.Regrown == 1, "two rounds: a new head, whole")
	eq(t, state.MostRegrown(), 1, "and it is counted")

	// 再砸一次，这次用火封住断颈。
	KnockOut(state, head, &ev)
	check(t, Validate(state, UseSkill(hero.ID, "spear", at)) != "", "a spear does nothing to a stump")
	medea.Pos = c(2, 4)
	seal := Perform(state, UseSkill(medea.ID, "witch_fire", at))
	check(t, seal.OK && head.Sealed && state.StumpAt(at) == nil, "fire on the stump seals it: "+seal.Error)
	SettleRound(state, &ev)
	SettleRound(state, &ev)
	check(t, !head.Alive, "sealed, it stays down")
	// 沼泽里还会游来一条蛇（第三回合到）；它也得倒下。
	for _, u := range state.Units {
		if u.Team == TeamEnemy && !u.Traits.Has("regrows") {
			u.Arrival, u.Hidden = 0, false
			KnockOut(state, u, &ev)
		}
	}
	eq(t, state.Outcome(), "win", "every neck sealed")
}
