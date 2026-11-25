package bots

import (
	"testing"

	"srpg/rules"
)

func has(plans []Plan, skill string, target rules.Cell) bool {
	for _, p := range plans {
		if p.Main.Type == rules.ActSkill && p.Main.Skill == skill && p.Main.Target == target {
			return true
		}
	}
	return false
}

// 机器人认得营地里带来的东西：药、带火的招式打空林地、给自己上的状态、指定目标。
func TestBotUsesWhatThePartyBrings(t *testing.T) {
	data, err := rules.LoadData(rules.DataOptions{})
	if err != nil {
		t.Fatal(err)
	}
	reward := rules.ChapterReward{EquippedRelic: "lion_pelt", Divinity: 2, Worn: []string{"lion_pelt", "hydra_blood"}}
	s, err := data.Muster("2-4", rules.Muster{
		Party:  []rules.PartyMember{{ID: "medea", Def: "medea"}, {ID: "chiron", Def: "chiron"}},
		Picks:  map[string][]string{"chiron": {"purify_arrow"}, "medea": {"frailty"}},
		Items:  map[string][]string{"hero": {"item_potion"}},
		Reward: reward,
	})
	if err != nil {
		t.Fatal(err)
	}
	rules.StartBattle(s)
	prof, _ := ProfileByName("skilled")
	bot := New(prof)
	hero, medea, chiron := s.Unit("hero"), s.Unit("medea"), s.Unit("chiron")
	atalanta := s.Unit("atalanta")

	atalanta.HP = atalanta.MaxHP - 14
	if !has(bot.Plans(s, hero), "item_potion", atalanta.Pos) && !hasAny(bot.Plans(s, hero), "item_potion") {
		t.Error("he does not think of the potion for a hurt companion")
	}
	if !hasAny(bot.Plans(s, chiron), "purify_arrow") {
		t.Error("Chiron does not think of healing")
	}
	if !hasAny(bot.Plans(s, hero), "impervious_hide") {
		t.Error("he does not think of the pelt")
	}
	if !hasAny(bot.Plans(s, hero), "hydra_venom") && rules.Distance(hero, s.Unit("crab_1")) <= 7 {
		t.Error("he does not think of the venom")
	}
	// 女祭司站在林地里：她身边的空林地是点火的好地方。
	medea.Pos = rules.Cell{X: 7, Y: 3}
	lit := false
	for _, p := range bot.Plans(s, medea) {
		if p.Main.Skill == "witch_fire" && s.UnitAt(p.Main.Target) == nil {
			lit = true
		}
	}
	if !lit {
		t.Error("Medea does not think of lighting the grove beside a priestess")
	}

	// 评分：指定目标比同样的敌人值钱；敌人身上的毒算数；站在沼泽里要付代价。
	ev := NewEvaluator(DefaultWeights())
	base := ev.Material(s)
	nun, crab := s.Unit("priestess_1"), s.Unit("crab_1")
	nun.HP -= 6
	gainNun := ev.Material(s) - base
	nun.HP += 6
	crab.HP -= 6
	gainCrab := ev.Material(s) - base
	crab.HP += 6
	if gainNun <= gainCrab {
		t.Errorf("six points off a priestess (%.2f) should be worth more than off a crab (%.2f)", gainNun, gainCrab)
	}
	crab.SetStatus("poisoned", 3)
	if ev.Material(s) <= base {
		t.Error("poison on an enemy is worth nothing to it")
	}
	crab.EraseStatus("poisoned")

	marsh, err := data.Build("2-2", nil)
	if err != nil {
		t.Fatal(err)
	}
	rules.StartBattle(marsh)
	walker := marsh.Unit("hero")
	walker.Pos = rules.Cell{X: 3, Y: 4}
	dry := ev.Positional(marsh)
	walker.Pos = rules.Cell{X: 4, Y: 4}
	if marsh.Grid.TerrainAt(walker.Pos) != rules.Swamp {
		t.Fatal("the test expects swamp there")
	}
	// 往前一格离敌人更近，危险也不同，所以只比较"同一格是不是沼泽"：把他标成不怕沼泽再算一次。
	wet := ev.Positional(marsh)
	walker.Traits.MarshStride = true
	ev.BeginTurn()
	immune := ev.Positional(marsh)
	if wet >= immune {
		t.Errorf("standing in swamp (%.2f) should score below the same cell for one who does not mind it (%.2f); dry was %.2f", wet, immune, dry)
	}
}

func hasAny(plans []Plan, skill string) bool {
	for _, p := range plans {
		if p.Main.Type == rules.ActSkill && p.Main.Skill == skill {
			return true
		}
	}
	return false
}
