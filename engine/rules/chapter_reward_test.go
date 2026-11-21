package rules

import "testing"

func TestChapterOneRewards(t *testing.T) {
	s := flat(8, 8)
	h := heroWith(s, c(2, 2), nil)
	a := ataWith(s, c(3, 2), nil)
	w := foe(s, "wolf", "wolf", c(2, 3))
	before := Compute(s, w, h, 1, Physical, false, NoPos)
	move := a.Move
	s.EquipReward(testData, ChapterReward{EquippedRelic: "lion_pelt", Boon: "swift_boots"})
	StartBattle(s)
	eq(t, a.Move, move+2, "opening movement")
	hit := Compute(s, w, h, 1, Physical, false, NoPos)
	eq(t, hit.Base, max(1, before.Base-3), "pelt mitigation")
	o := Perform(s, UseSkill("hero", "impervious_hide", NoPos))
	eq(t, o.OK, true, "activate pelt")
	eq(t, s.Reward.Divinity, 2, "active divinity")
	eq(t, h.Cooldown("impervious_hide"), 4, "relic cooldown")
	eq(t, Compute(s, w, h, 1, Physical, false, NoPos).Immune, true, "physical immunity")
	eq(t, Compute(s, w, h, 1, Divine, false, NoPos).Immune, false, "divine passes")
	EndPhase(s)
	EndPhase(s)
	eq(t, a.Move, move, "second round movement")
	eq(t, h.HasStatus("impervious_hide"), false, "hide expires")
}
func TestMoonHuntKeepsTwoTargets(t *testing.T) {
	s := flat(8, 8)
	s.EquipReward(testData, ChapterReward{Boon: "moon_hunt"})
	s.setMark("a")
	s.setMark("b")
	s.setMark("c")
	eq(t, s.IsMarked("a"), false, "oldest expires")
	s = s.Copy()
	eq(t, s.IsMarked("b") && s.IsMarked("c"), true, "preview keeps both")
	s.removeMark("c")
	eq(t, s.IsMarked("b") && !s.IsMarked("c"), true, "surviving mark")
}

func TestMerchantCharms(t *testing.T) {
	s := flat(8, 8)
	h := heroWith(s, c(2, 2), nil)
	a := ataWith(s, c(3, 2), nil)
	oldMove, oldDefense := a.Move, a.Defense
	s.EquipReward(testData, ChapterReward{Charms: map[string]string{"olive": h.ID, "stone": a.ID}})
	StartBattle(s)
	eq(t, a.Move, oldMove+1, "waystone movement")
	eq(t, a.Defense, oldDefense-2, "waystone price")
	h.HP -= 6
	check(t, Perform(s, Wait(h.ID)).OK, "guard")
	eq(t, h.HP, h.MaxHP-2, "olive branch heals its owner on guard")
}
