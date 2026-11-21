package rules

import "testing"

func TestVillageRoundsAndRidgeShot(t *testing.T) {
	s, err := testData.Build("1-1", nil)
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(s)
	eq(t, len(s.Living(TeamPlayer)), 1, "hero starts alone")
	eq(t, len(s.Living(TeamEnemy)), 2, "first wave")
	branch := s.Copy()
	EndPhase(branch)
	EndPhase(branch)
	eq(t, len(branch.Living(TeamEnemy)), 4, "second wave")
	eq(t, s.Grid.TerrainAt(c(1, 7)), Plain, "forecast must not modify the original map")
	eq(t, branch.Grid.TerrainAt(c(1, 7)), Burning, "fire advances one ring")
	EndPhase(branch)
	events := EndPhase(branch)
	arrived := map[string]bool{}
	var shot bool
	for _, e := range events {
		if e.Type == EvArrival {
			arrived[e.Unit] = true
		}
		if e.Type == EvAttack && e.Unit == "atalanta" && e.Skill == "shoot" {
			shot = true
		}
	}
	check(t, arrived["wolf_5"] && arrived["wolf_6"], "both third-wave wolves entered")
	for _, u := range branch.Units {
		eq(t, u.Arrival, 0, "no reinforcements remain queued")
	}
	check(t, shot, "archer fires from the ridge")
	check(t, branch.Unit("atalanta").Alive && !branch.Unit("atalanta").HasActed, "archer is selectable after introductory shot")
}

func TestVillageVictoryConditions(t *testing.T) {
	s, err := testData.Build("1-1", nil)
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(s)
	for _, u := range s.Living(TeamEnemy) {
		u.Alive = false
	}
	eq(t, s.Outcome(), "", "pending wolves keep the level open")
	s.Unit("hero").Pos = c(8, 0)
	eq(t, s.Outcome(), "", "one survivor at the gate does not finish the level")
	for i := 0; i < 4; i++ {
		EndPhase(s)
	}
	s.Unit("atalanta").Pos = c(9, 0)
	eq(t, s.Outcome(), "win", "both heroes at gate")
	s.Unit("atalanta").Pos = c(5, 1)
	for _, u := range s.Living(TeamEnemy) {
		u.Alive = false
	}
	eq(t, s.Outcome(), "win", "eliminating all waves also wins")
	s.Unit("hero").Alive = false
	eq(t, s.Outcome(), "loss_hero", "hero death takes priority")
}
