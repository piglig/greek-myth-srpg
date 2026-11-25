package sim

import (
	"strings"
	"testing"

	"srpg/rules"
)

// 三档配置在战役的每一关都合时宜：东西买得到、钱够、等级够、人数不超、圣物不早到，
// 并且真的摆得出来。
func TestKitsFitTheirMoment(t *testing.T) {
	data, err := rules.LoadData(rules.DataOptions{})
	if err != nil {
		t.Fatal(err)
	}
	kits, err := LoadKits("../../balance/kits.yaml")
	if err != nil {
		t.Fatal(err)
	}
	order, err := CampaignOrder(data)
	if err != nil {
		t.Fatal(err)
	}
	if len(order) < 10 {
		t.Fatalf("the campaign should have at least ten battles: %v", order)
	}
	for _, tier := range kits.Names() {
		for _, battle := range order {
			m, ledger, problems, err := kits.Resolve(data, tier, battle)
			if err != nil {
				t.Fatalf("%s %s: %v", tier, battle, err)
			}
			for _, p := range problems {
				t.Errorf("%s: %s", tier, p)
			}
			if len(problems) > 0 {
				continue
			}
			st, err := data.Muster(battle, *m)
			if err != nil {
				t.Errorf("%s %s cannot be mustered: %v", tier, battle, err)
				continue
			}
			for _, who := range m.Party {
				if st.Unit(who.ID) == nil {
					t.Errorf("%s %s: %s is not on the field", tier, battle, who.ID)
				}
			}
			t.Logf("%-8s %-4s level %d  earned %4d  spent %4d", tier, battle, ledger.Level, ledger.Earned, ledger.Spent)
		}
	}
}

// 不合时宜的配置会被逐条指出来，而不是悄悄跑出一个不可信的数字。
func TestKitsRefuseWhatCouldNotBe(t *testing.T) {
	data, err := rules.LoadData(rules.DataOptions{})
	if err != nil {
		t.Fatal(err)
	}
	picks := map[string][]string{"hero": {}, "atalanta": {"vital_shot"}}
	cases := []struct {
		name string
		step KitStep
		want string
	}{
		{"gear from a later chapter", KitStep{At: "1-1", Buy: []string{"cuirass"}, Picks: picks}, "行商这时不卖 cuirass"},
		{"more than the purse holds", KitStep{At: "1-1", Buy: []string{"scale", "scale"}, Picks: picks}, "只挣到"},
		{"a hero who has not come yet", KitStep{At: "1-1", Hire: []string{"iphicles"}, Picks: picks}, "才来投"},
		{"wearing what was never bought", KitStep{At: "1-1", Wear: map[string][]string{"hero": {"leather"}}, Picks: picks}, "手里只有 0 件"},
		{"two things in one place", KitStep{At: "1-1", Buy: []string{"tunic"}, Wear: map[string][]string{"hero": {"tunic", "tunic"}}, Picks: picks}, "同一个部位"},
		{"techniques beyond the level", KitStep{At: "1-1", Picks: map[string][]string{"hero": {"iron_arm", "stagger_fist"}, "atalanta": {"vital_shot"}}}, "只有 0 点"},
		{"a relic before its chapter is won", KitStep{At: "1-1", Relics: []string{"lion_pelt"}, Picks: picks}, "件圣物"},
		{"selling what is not owned", KitStep{At: "1-1", Sell: []string{"tunic"}, Picks: picks}, "卖了没有的东西"},
	}
	for _, c := range cases {
		kits := &Kits{Tiers: map[string]*Tier{"x": {Earns: Earns{Spoils: "none"}, Steps: []KitStep{c.step}}}}
		_, _, problems, err := kits.Resolve(data, "x", "1-1")
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		if !strings.Contains(strings.Join(problems, "\n"), c.want) {
			t.Errorf("%s: expected a problem mentioning %q, got %v", c.name, c.want, problems)
		}
		if _, err := kits.Muster(data, "x", "1-1"); err == nil {
			t.Errorf("%s: a kit with problems must not be mustered", c.name)
		}
	}
}

// 带着配置开局和裸装开局是两回事：人多了，属性变了，记录里写着档名。
func TestKitChangesTheBattle(t *testing.T) {
	bare, err := Run(t.Context(), Options{Battle: "2-3", Bot: "skilled", Count: 1})
	if err != nil {
		t.Fatal(err)
	}
	kitted, err := Run(t.Context(), Options{Battle: "2-3", Bot: "skilled", Count: 1, Kit: "typical", KitsPath: "../../balance/kits.yaml"})
	if err != nil {
		t.Fatal(err)
	}
	if bare[0].Kit != "" || kitted[0].Kit != "typical" {
		t.Errorf("kit names: %q and %q", bare[0].Kit, kitted[0].Kit)
	}
	if kitted[0].Units["medea"] == nil || bare[0].Units["medea"] != nil {
		t.Errorf("the typical party brings Medea; the bare one does not")
	}
	if kitted[0].Units["hero"].MaxHP <= bare[0].Units["hero"].MaxHP {
		t.Errorf("his gear should show: %d against %d", kitted[0].Units["hero"].MaxHP, bare[0].Units["hero"].MaxHP)
	}
}
