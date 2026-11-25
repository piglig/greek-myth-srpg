package rules

import "testing"

// 2-S：护送的是喀戎，不是美狄亚。
func TestWoundedCentaur(t *testing.T) {
	state, err := testData.Build("2-S", nil)
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(state)
	eq(t, state.EscortID(), "chiron", "this road is walked for Chiron")
	chiron := state.Unit("chiron")
	eq(t, state.Outcome(), "", "he has not reached the spring")
	for _, e := range state.Living(TeamEnemy) {
		e.Alive = false
	}
	eq(t, state.Outcome(), "", "clearing the marsh does not carry him there")
	chiron.Pos = state.EscortExits[0]
	eq(t, state.Outcome(), "win", "at the spring")
	chiron.Alive = false
	eq(t, state.Outcome(), "loss_escort", "if he falls the road was for nothing")
	old, _ := testData.Build("2-1", nil)
	eq(t, old.EscortID(), "medea", "the execution ground is still Medea's")
}
