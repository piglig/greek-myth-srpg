package rules

import "testing"

func TestRelicSlotsAndHydraBlood(t *testing.T) {
	eq(t, RelicSlots(1), 1, "one slot with the pelt alone")
	eq(t, RelicSlots(2), 2, "the second relic brings its own slot")
	eq(t, RelicSlots(3), 2, "the third must share")
	eq(t, RelicSlots(4), 3, "the fourth brings one")
	eq(t, RelicSlots(7), 4, "four at most")
	check(t, ValidateRelics(ChapterReward{Divinity: 1, Worn: []string{"lion_pelt", "hydra_blood"}}) != "", "two relics do not fit one slot")
	check(t, ValidateRelics(ChapterReward{Divinity: 2, Worn: []string{"lion_pelt", "hydra_blood"}}) == "", "they fit two")
	check(t, ValidateRelics(ChapterReward{Divinity: 2, Worn: []string{"moon"}}) != "", "an unknown relic is refused")

	old := ChapterReward{EquippedRelic: "lion_pelt"}
	check(t, old.Wears("lion_pelt") && !old.Wears("hydra_blood"), "with nothing chosen, the pelt is worn as before")
	bare := ChapterReward{EquippedRelic: "lion_pelt", Worn: []string{"hydra_blood"}}
	check(t, !bare.Wears("lion_pelt") && bare.Wears("hydra_blood"), "what is chosen is what is worn")

	state, err := testData.Build("2-4", nil)
	if err != nil {
		t.Fatal(err)
	}
	reward := ChapterReward{EquippedRelic: "lion_pelt", Divinity: 2, Worn: []string{"hydra_blood"}}
	state.EquipReward(testData, reward)
	if err := state.GrantDivinity(testData, reward); err != nil {
		t.Fatal(err)
	}
	StartBattle(state)
	hero, crab, nun := state.Unit("hero"), state.Unit("crab_1"), state.Unit("priestess_1")
	check(t, hero.Skill("hydra_venom") != nil && hero.Skill("impervious_hide") == nil, "he carries the blood's technique and not the pelt's")

	// 被动：他的每一击都带一回合的毒。
	hero.Pos, crab.Pos = c(6, 4), c(7, 4)
	hero.Facing = East
	strike := Perform(state, UseSkill(hero.ID, "spear", crab.Pos))
	check(t, strike.OK && crab.HasStatus("poisoned"), "his spear poisons: "+strike.Error)

	// 主动：三格内一个敌人中毒三回合，期间治不了。
	hero.HasActed, hero.ActionsLeft = false, 1
	crab.EraseStatus("poisoned")
	crab.Pos, crab.HP = c(8, 4), crab.MaxHP-10
	hp := crab.HP
	venom := Perform(state, UseSkill(hero.ID, "hydra_venom", crab.Pos))
	check(t, venom.OK && crab.HP == hp, "the venom is cast and deals no blow: "+venom.Error)
	rounds, _ := crab.Status("poisoned")
	check(t, rounds == 3 && crab.HasStatus("blighted"), "three rounds of poison, and blighted")
	nun.Pos = c(9, 4)
	state.Phase = PhaseEnemy
	check(t, Validate(state, UseSkill(nun.ID, "hera_blessing", crab.Pos)) != "", "the priestess cannot heal what the hydra's blood has touched")
	plan := PlanFor(state, nun)
	check(t, plan.Action.Skill != "hera_blessing" || plan.Action.Target != crab.Pos, "and does not try")
}
