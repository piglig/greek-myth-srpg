package rules

import "testing"

// 第三章的基础规则：天上的敌人近战够不着；铜钹把它们弄下来一回合；阿塔兰忒对空更准。
func TestSkyAndCymbal(t *testing.T) {
	state, err := testData.Build("3-1", nil)
	if err != nil {
		t.Fatal(err)
	}
	StartBattle(state)
	hero, hunter, bird := state.Unit("hero"), state.Unit("atalanta"), state.Unit("bird_1")
	check(t, bird.Aloft(), "a bird starts in the air")
	check(t, len(state.Cymbals) == 1, "the shore has its cymbal")
	spot := state.Cymbals[0].Pos

	// 近战够不着，射击够得着；还在天上的推不动、摔不动。
	hero.Pos, bird.Pos = c(spot.X-1, spot.Y), c(spot.X+1, spot.Y)
	check(t, Validate(state, UseSkill(hero.ID, "spear", bird.Pos)) == "out of reach in the sky", "a spear does not reach the sky")
	hunter.Pos = c(spot.X-2, spot.Y)
	check(t, Validate(state, UseSkill(hunter.ID, "shoot", bird.Pos)) == "", "an arrow does")
	at := bird.Pos
	var ev []Event
	Knockback(state, bird, East, 2, "test", &ev)
	check(t, bird.Pos == at, "nothing pushes what is in the air")

	// 对空：同一箭打天上的比打地上的重一半。
	aloft := Compute(state, hunter, bird, 1.0, Physical, true, NoPos).Amount
	bird.SetStatus("grounded", 1)
	down := Compute(state, hunter, bird, 1.0, Physical, true, NoPos).Amount
	bird.EraseStatus("grounded")
	check(t, aloft > down && aloft == FloorInt(float64(down)*AntiAirMult), "the huntress is surer against the sky")

	// 敲铜钹：要紧挨着；三格内的落地，远处的不动；敲的人用掉了这回合的出手。
	far := state.Unit("bird_2")
	far.Pos = c(spot.X+StrikeRadius+1, spot.Y)
	hunter.Pos = c(0, 0)
	check(t, Validate(state, Strike(hunter.ID, spot)) == "not adjacent", "only from beside it")
	out := Perform(state, Strike(hero.ID, spot))
	check(t, out.OK && out.Events[0].Type == EvStrike, "the cymbal rings: "+out.Error)
	check(t, !bird.Aloft() && far.Aloft() && state.Felled == 1, "the near one comes down, the far one does not")
	check(t, hero.HasActed, "ringing it is his action for the round")
	check(t, Validate(state, Strike(hunter.ID, spot)) != "", "and it cannot ring again at once")

	// 落地的这一回合里，矛够得着，也推得动。
	hero.HasActed = false
	check(t, Validate(state, UseSkill(hero.ID, "spear", bird.Pos)) == "", "on the ground a spear reaches it")
	Knockback(state, bird, East, 1, "test", &ev)
	check(t, bird.Pos == c(at.X+1, at.Y), "and it can be shoved")

	// 回合结算后飞回天上；铜钹再歇一回合才能敲。
	EndPhase(state)
	check(t, !bird.Aloft(), "still down through the enemy's turn")
	EndPhase(state)
	check(t, bird.Aloft(), "up again when the round is out")
	hero.Pos = c(spot.X-1, spot.Y)
	check(t, Validate(state, Strike(hero.ID, spot)) == "still ringing", "the cymbal rests a round more")
	EndPhase(state)
	EndPhase(state)
	check(t, Validate(state, Strike(hero.ID, spot)) == "", "then it can be rung again")

	// 铜羽不看防御。
	hero.Defense = 30
	hit := Compute(state, bird, hero, 1.0, Physical, true, NoPos)
	_ = hit
	feather := bird.Skill("feather_shot")
	check(t, feather != nil && feather.Pierce && feather.Ranged, "bronze feathers go through armour")
}
