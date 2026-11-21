package rules

import "testing"

func TestCorinthEscort(t *testing.T) {
	state, err := testData.Build("2-1", nil)
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(state)
	medea := state.Unit("medea")
	guard := state.Unit("watchman")
	medea.Pos = c(5, 5)
	strike := Perform(state, UseSkill(medea.ID, "witch_fire", guard.Pos))
	if !strike.OK || !guard.HasStatus("burning") {
		t.Fatal("Medea's opening spell should burn its target")
	}
	for _, enemy := range state.Living(TeamEnemy) {
		enemy.Alive = false
	}
	eq(t, state.Outcome(), "", "clearing the yard does not evacuate Medea")
	arrived := state.Copy()
	arrived.Unit("medea").Pos = arrived.EscortExits[0]
	eq(t, arrived.Outcome(), "win", "living escort at the eastern gate")
	arrived.Unit("medea").Alive = false
	eq(t, arrived.Outcome(), "loss_escort", "fallen escort cannot escape")
}
