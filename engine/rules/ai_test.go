package rules

import "testing"

// 敌方 AI：计划是确定的、优先击杀、威胁范围。

func TestWolfMovesInAndBites(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 1))
	foe(s, "wolf", "wolf", c(5, 1))
	StartBattle(s)
	EndPhase(s)
	p := PlanFor(s, s.Unit("wolf"))
	check(t, p.HasMove, "moves")
	eq(t, p.Action.Type, ActSkill, "attacks")
	eq(t, p.Action.Target, c(1, 1), "targets hero")
}

func TestPlansAreDeterministic(t *testing.T) {
	s := build(t, "test")
	StartBattle(s)
	EndPhase(s)
	for _, e := range s.Living(TeamEnemy) {
		eq(t, PlanFor(s, e), PlanFor(s, e), "same plan twice for "+e.ID)
	}
}

func TestPrefersTheKill(t *testing.T) {
	s := flat(8, 8)
	ally(s, "hero", "hero", c(1, 1))
	ata := ally(s, "atalanta", "ata", c(3, 1))
	ata.HP = 5
	foe(s, "wolf", "wolf", c(2, 2))
	StartBattle(s)
	EndPhase(s)
	eq(t, PlanFor(s, s.Unit("wolf")).Action.Target, c(3, 1), "finishes atalanta")
}

func TestIntentPreviewDuringPlayerPhaseDoesNotMutate(t *testing.T) {
	s := build(t, "test")
	StartBattle(s)
	wolf := s.Unit("wolf_a")
	before := wolf.Pos
	_, events := Simulate(s, wolf)
	check(t, len(events) > 0, "has events")
	eq(t, wolf.Pos, before, "real wolf untouched")
	eq(t, s.Phase, PhasePlayer, "phase untouched")
	check(t, len(ThreatCells(s, wolf)) > 10, "threat area")
}

func TestBoarTakesTheRampInsteadOfWaitingAtTheCliff(t *testing.T) {
	// 左边是 3 层台地；唯一的下坡路是第 3-4 行的单级坡道
	s := mkState([]string{
		"3330000",
		"3330000",
		"3330000",
		"3321000",
		"3321000",
	})
	foe(s, "boar", "boar", c(1, 0), South)
	ally(s, "hero", "hero", c(5, 0))
	StartBattle(s)
	EndPhase(s)
	p := PlanFor(s, s.Unit("boar"))
	check(t, p.HasMove, "moves")
	checkf(t, s.StandingHeight(p.MoveTo, 2) < 3, "comes down off the plateau (got %v)", p.MoveTo)
}

func TestPrefersIsolatedTarget(t *testing.T) {
	s := flat(10, 6)
	ally(s, "hero", "hero", c(1, 1))
	ally(s, "heracles", "her", c(1, 2))
	ally(s, "atalanta", "ata", c(7, 1))
	foe(s, "bandit", "b", c(4, 1))
	StartBattle(s)
	EndPhase(s)
	eq(t, PlanFor(s, s.Unit("b")).Action.Target, c(7, 1), "goes for the lone archer")
}

func TestValleyBattleReachesAnOutcome(t *testing.T) {
	s := build(t, "1-4")
	StartBattle(s)
	rounds, falls := 0, 0
	for rounds < 40 && len(s.Living(TeamPlayer)) > 0 && len(s.Living(TeamEnemy)) > 0 && s.Unit("hero").Alive {
		for _, team := range []Team{TeamPlayer, TeamEnemy} {
			for _, e := range aiTurn(t, s, team, false) {
				if e.Type == EvFall {
					falls++
				}
			}
			EndPhase(s)
		}
		rounds++
	}
	checkf(t, rounds < 40, "ends within 40 rounds (took %d)", rounds)
	t.Logf("1-4 autoplay: %d rounds, players %d, enemies %d, falls %d", rounds,
		len(s.Living(TeamPlayer)), len(s.Living(TeamEnemy)), falls)
}

// 冒烟测试：双方都由敌方 AI 驱动，把测试战斗打到结束。
func TestTestBattleReachesAnOutcome(t *testing.T) {
	s := build(t, "test")
	StartBattle(s)
	rounds := 0
	for rounds < 30 && len(s.Living(TeamPlayer)) > 0 && len(s.Living(TeamEnemy)) > 0 {
		aiTurn(t, s, TeamPlayer, true)
		EndPhase(s)
		aiTurn(t, s, TeamEnemy, true)
		EndPhase(s)
		rounds++
	}
	checkf(t, rounds < 30, "battle ends within 30 rounds (took %d)", rounds)
	check(t, len(s.Living(TeamPlayer)) == 0 || len(s.Living(TeamEnemy)) == 0, "one side wiped")
	t.Logf("autoplay: %d rounds, players left %d, enemies left %d", rounds,
		len(s.Living(TeamPlayer)), len(s.Living(TeamEnemy)))
}
