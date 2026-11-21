package rules

import "testing"

func TestBanquetChargeAndInterception(t *testing.T) {
	s, err := testData.Build("1-3", nil)
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(s)
	rider := s.Unit("rider_1")
	ally := s.Unit("wounded_chiron")
	eq(t, ally.Move, 0, "wounded archer is stationary")
	p, events := Simulate(s, rider)
	eq(t, p.Action.Target, ally.Pos, "open charge lane")
	checkCharge := func(events []Event) {
		t.Helper()
		for _, e := range events {
			if e.Type == EvAttack && e.Notes.Has(NoteCharge) {
				return
			}
		}
		t.Fatal("missing charge damage")
	}
	checkCharge(events)
	check(t, Perform(s, Move("hero", c(5, 5))).OK, "hero enters lane")
	before := string(s.AppendSignature(nil))
	p, events = Simulate(s, rider)
	eq(t, p.Action.Target, c(5, 5), "hero is first contact")
	checkCharge(events)
	eq(t, string(s.AppendSignature(nil)), before, "forecast leaves battle unchanged")
	eq(t, straightRun(c(1, 1), []Cell{c(1, 2), c(2, 2), c(3, 2)}), Cell{}, "turn prevents charge")
	// The wounded archer gets one automatic shot; a half-health rider remains.
	rider.Pos = c(6, 5)
	rider.HP = 13
	Deal(s, rider, 0, Physical, "test", nil, false)
	check(t, rider.Alive, "exactly half health holds")
	ev := EndPhase(s)
	check(t, hasEvent(ev, EvFlee) && !rider.Alive, "volley drives rider away")
	ally.Alive = false
	eq(t, s.Outcome(), "loss_chiron", "fallen ward ends defense")
}
