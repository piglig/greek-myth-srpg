package rules

import "testing"

// 营地这一侧的表读得进来，而且互相对得上：掉落的东西都存在，英雄用的单位和招式都存在。
func TestMarketTables(t *testing.T) {
	m, err := testData.Market()
	if err != nil {
		t.Fatal(err)
	}
	check(t, len(m.Goods) > 50 && len(m.Recruits) == 6 && len(m.Loot) >= 10, "the tables are there")
	eq(t, m.Goods["leather"].Mods["def"], 2, "leather armour is worth two defence")
	eq(t, m.SellPrice("leather"), 45, "things sell for half")
	check(t, m.Stocked("leather", "1-2") && !m.Stocked("cuirass", "1-5") && m.Stocked("cuirass", "2-1"), "the shelf follows the chapter")
	check(t, !m.Stocked("wolf_hide", "2-1") && !m.Stocked("wolf_cape", "2-1"), "spoils are not sold")
	eq(t, m.PayFor("1-4"), 60, "first chapter pay")
	eq(t, m.PayFor("2-3"), 80, "second chapter pay")
	eq(t, m.PayFor("3-1"), 100, "third chapter pay")
	eq(t, m.PayFor("5-1"), 100, "a chapter not yet written takes the last one that is")
	eq(t, m.SeatsFor("1-1"), 1, "two in all in the first chapter")
	eq(t, m.SeatsFor("2-1"), 2, "three in the second")
	eq(t, m.SeatsFor("6-2"), 3, "four from the third on")
	eq(t, m.LevelAt(0), 1, "level one with nothing")
	eq(t, m.LevelAt(100), 2, "a hundred makes two")
	eq(t, m.LevelAt(219), 2, "one short of three")
	eq(t, m.LevelAt(220), 3, "a hundred and twenty more makes three")
	eq(t, m.Recruits["idas"].Opens, 3, "the great ones come with the third seat")
	materials, rest := m.Spoils("wolf")
	check(t, materials > 15 && materials < 25 && rest > 0, "a wolf is worth about eighteen in hide, fang and bone")
	check(t, m.OptionalBattles["1-3"] && m.OnlyIfSkipped["2-S"] == "1-3" && m.FreeFirst["chiron"] == "purify_arrow", "the side roads and the free techniques are told")
}
