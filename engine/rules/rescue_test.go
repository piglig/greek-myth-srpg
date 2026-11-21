package rules

import "testing"

func TestWoodlandFirstRescue(t *testing.T) {
	s, err := testData.Build("1-2", nil)
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(s)
	blocked := s.Copy()
	EndPhase(blocked)
	eq(t, blocked.Unit("traveler_a").Pos, c(4, 5), "civilian stays while threatened")
	check(t, Validate(s, Move("traveler_a", c(3, 5))) != "", "civilians move automatically")
	check(t, Perform(s, Move("hero", c(3, 6))).OK, "hero can reach the intercept")
	strike := Perform(s, UseSkill("hero", "shield_bash", c(4, 6)))
	check(t, strike.OK && s.Unit("scout").Pos == c(5, 6), "bash clears the escape route")
	for _, e := range strike.Events {
		if e.Type == EvAssist && e.Unit == "traveler_a" {
			t.Fatal("unarmed civilian assisted")
		}
	}
	rescued := 0
	for _, e := range EndPhase(s) {
		if e.Type == EvRescued {
			rescued++
		}
	}
	eq(t, rescued, 1, "first evacuation")
	check(t, s.Unit("traveler_a").Hidden && s.UnitAt(c(0, 5)) == nil, "exit remains clear")
	EndPhase(s)
	for _, e := range EndPhase(s) {
		if e.Type == EvRescued && e.Unit == "traveler_a" {
			t.Fatal("rescued twice")
		}
	}
}

func TestWoodlandSecondRescue(t *testing.T) {
	for _, route := range []string{"archer", "guard", "unprotected"} {
		t.Run(route, func(t *testing.T) {
			s, err := testData.Build("1-2", nil)
			if err != nil {
				t.Fatal(err)
			}
			StartBattle(s)
			act := func(a Action) {
				t.Helper()
				if o := Perform(s, a); !o.OK {
					t.Fatalf("%v: %s", a, o.Error)
				}
			}
			enemyTurn := func() {
				EndPhase(s)
				for _, e := range s.Living(TeamEnemy) {
					for e.Alive && !e.HasActed && !e.Hidden {
						p := PlanFor(s, e)
						if p.HasMove {
							act(Move(e.ID, p.MoveTo))
						}
						act(p.Action)
						if !FinishActivation(s, e) {
							break
						}
					}
				}
				EndPhase(s)
			}
			act(Move("hero", c(3, 6)))
			act(UseSkill("hero", "shield_bash", c(4, 6)))
			enemyTurn()
			person := s.Unit("traveler_b")
			before := string(s.AppendSignature(nil))
			path, threats, exits := RescuePreview(s, person)
			if exits || len(path) == 0 || path[len(path)-1] != c(2, 5) || len(threats) != 1 || threats[0] != "bow" {
				t.Fatalf("unexpected second-turn forecast: %v %v %v", path, threats, exits)
			}
			eq(t, string(s.AppendSignature(nil)), before, "forecast leaves battle untouched")
			switch route {
			case "archer":
				act(Move("atalanta", c(7, 6)))
				act(UseSkill("atalanta", "vital_shot", s.Unit("bow").Pos))
			case "guard":
				act(Move("hero", c(2, 4)))
				act(Wait("hero"))
			}
			enemyTurn()
			EndPhase(s)
			eq(t, person.Alive && person.Hidden, route != "unprotected", "herbalist reaches exit")
		})
	}
}
