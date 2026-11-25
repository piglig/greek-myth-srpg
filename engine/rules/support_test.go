package rules

import "testing"

// 支援英雄：不上场，主角多一手"召援"。不占他的行动，有冷却，第一回合用不了，范围从他算起。
func musterWith(t *testing.T, battle, who string) (*BattleState, *UnitState, *Skill) {
	t.Helper()
	state, err := testData.Muster(battle, Muster{Support: who})
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(state)
	hero := state.Unit("hero")
	var move *Skill
	for _, sk := range hero.Skills {
		if sk.Support != "" {
			move = sk
		}
	}
	if move == nil {
		t.Fatalf("带了 %s，主角却没有召援的招式", who)
	}
	return state, hero, move
}

func nextRound(s *BattleState) {
	EndPhase(s)
	EndPhase(s)
}

func TestSupportIsFreeAndOnCooldown(t *testing.T) {
	state, hero, shot := musterWith(t, "1-4", "phalerus")
	check(t, state.Support == "phalerus", "the battle remembers who came")
	for _, u := range state.Units {
		check(t, u.ID != "phalerus", "the supporter does not take the field")
	}
	foe := state.Unit("wolf_1")
	foe.Pos = c(hero.Pos.X, hero.Pos.Y-3)
	call := UseSkill(hero.ID, shot.ID, foe.Pos)
	check(t, Validate(state, call) != "", "no support in the first round")
	nextRound(state)
	foe.Pos = c(hero.Pos.X, hero.Pos.Y-3)
	before := foe.HP
	out := Perform(state, call)
	check(t, out.OK, "round two: he answers the call: "+out.Error)
	check(t, foe.HP == before-supportHit(foe, shot.Power, false), "a fixed blow, less armour")
	check(t, !hero.HasActed && !hero.HasMoved, "calling him costs the hero nothing")
	check(t, out.Events[0].Type == EvSupport && out.Events[0].Source == "phalerus", "the view is told who arrived")
	check(t, Validate(state, call) == "on cooldown", "once called, he needs his rounds")
	check(t, Validate(state, UseSkill(hero.ID, "spear", foe.Pos)) != "already acted", "the hero still has his own action")
	for i := 0; i < shot.Cooldown; i++ {
		check(t, Validate(state, call) != "", "still resting")
		nextRound(state)
		foe.Pos = c(hero.Pos.X, hero.Pos.Y-3)
	}
	check(t, Validate(state, call) == "", "and back after his cooldown")

	far := state.Unit("wolf_2")
	far.Pos = c(hero.Pos.X, hero.Pos.Y-shot.MaxRange-1)
	check(t, Validate(state, UseSkill(hero.ID, shot.ID, far.Pos)) == "out of range", "reach is counted from the hero")
	hero.HasActed = true
	check(t, Validate(state, call) != "", "he must be called before the hero strikes")
}

func TestSupportMoves(t *testing.T) {
	// 并肩：护盾；劈盾：不计防御；碎阵：破势。
	state, hero, guard := musterWith(t, "1-5", "iphicles")
	nextRound(state)
	ally := state.Unit("atalanta")
	ally.Pos = c(hero.Pos.X+1, hero.Pos.Y)
	out := Perform(state, UseSkill(hero.ID, guard.ID, ally.Pos))
	check(t, out.OK && ally.Shield == guard.Power, "a shield for the one beside him: "+out.Error)
	lion := state.Unit("lion")
	check(t, Validate(state, UseSkill(hero.ID, guard.ID, lion.Pos)) != "", "not for the enemy")

	state, hero, sunder := musterWith(t, "1-4", "ancaeus")
	nextRound(state)
	boar := state.Unit("boar_w")
	boar.Pos = c(hero.Pos.X, hero.Pos.Y-2)
	before := boar.HP
	check(t, Perform(state, UseSkill(hero.ID, sunder.ID, boar.Pos)).OK && boar.HP == before-sunder.Power && boar.Defense > 4,
		"the axe ignores a boar's hide")

	state, hero, breaker := musterWith(t, "1-5", "idas")
	nextRound(state)
	lion = state.Unit("lion")
	lion.Pos = c(hero.Pos.X, hero.Pos.Y-3)
	was := lion.Stagger
	check(t, Perform(state, UseSkill(hero.ID, breaker.ID, lion.Pos)).OK && lion.Stagger == was+breaker.StaggerBonus,
		"the strongest mortal shakes a boss")
}

func TestSupportAidAndCharge(t *testing.T) {
	state, hero, aid := musterWith(t, "1-4", "pholus")
	nextRound(state)
	ally := state.Unit("atalanta")
	ally.Pos = c(hero.Pos.X+1, hero.Pos.Y)
	check(t, Validate(state, UseSkill(hero.ID, aid.ID, ally.Pos)) != "", "nothing to help with")
	ally.HP -= 15
	ally.SetStatus("poisoned", 2)
	ally.HasMoved = true
	hp := ally.HP
	out := Perform(state, UseSkill(hero.ID, aid.ID, ally.Pos))
	check(t, out.OK && ally.HP == hp+aid.Power && !ally.HasStatus("poisoned") && !ally.HasMoved,
		"wine, a clean wound, and a ride: "+out.Error)

	state, hero, charge := musterWith(t, "1-4", "eurytion")
	nextRound(state)
	hero.Pos = c(5, 9)
	a, b := state.Unit("wolf_1"), state.Unit("wolf_2")
	a.Pos, b.Pos = c(5, 8), c(5, 6)
	for _, u := range state.Units {
		if u != hero && u != a && u != b && u.Pos.X == 5 && u.Pos.Y < 9 {
			u.Pos = c(11, 13)
		}
	}
	ah, bh := a.HP, b.HP
	check(t, Validate(state, UseSkill(hero.ID, charge.ID, c(5, 7))) != "", "he needs a direction, not a cell")
	check(t, Validate(state, UseSkill(hero.ID, charge.ID, c(6, 9))) != "", "and someone in the lane")
	out = Perform(state, UseSkill(hero.ID, charge.ID, c(5, 8)))
	check(t, out.OK && a.HP < ah && b.HP < bh, "everyone in the lane is ridden down: "+out.Error)
	check(t, a.Pos == c(5, 7) && b.Pos == c(5, 5), "and thrown back a step")
}
