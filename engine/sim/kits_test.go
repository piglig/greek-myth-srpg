package sim

import (
	"testing"

	"srpg/rules"
)

// 三档配置在每一关都摆得出来，加点花得起，带的人不超过三个。
func TestKitsMuster(t *testing.T) {
	data, err := rules.LoadData(rules.DataOptions{})
	if err != nil {
		t.Fatal(err)
	}
	kits, err := LoadKits("../../balance/kits.yaml")
	if err != nil {
		t.Fatal(err)
	}
	free := map[string]bool{"atalanta": true, "chiron": true, "medea": true}
	for _, tier := range kits.Names() {
		for _, battle := range []string{"1-1", "1-2", "1-3", "1-4", "1-5", "2-1", "2-2", "2-3", "2-4"} {
			m, err := kits.Muster(data, tier, battle)
			if err != nil {
				t.Fatalf("%s %s: %v", tier, battle, err)
			}
			st, err := data.Muster(battle, *m)
			if err != nil {
				t.Fatalf("%s %s: %v", tier, battle, err)
			}
			level, _ := kits.Level(data, tier, battle)
			trees := map[string]string{}
			for _, who := range m.Party {
				trees[who.ID] = who.Tree
				if st.Unit(who.ID) == nil {
					t.Errorf("%s %s: %s is not on the field", tier, battle, who.ID)
				}
			}
			for who, nodes := range m.Picks {
				tree := trees[who]
				if tree == "" {
					tree = who
				}
				points := level - 1
				if free[who] {
					points++
				}
				if cost := data.PicksCost(tree, nodes); cost > points {
					t.Errorf("%s %s: %s spends %d points and has %d at level %d", tier, battle, who, cost, points, level)
				}
				if msg := data.ValidateTraining(tree, nodes, 99); msg != "" {
					t.Errorf("%s %s: %s: %s", tier, battle, who, msg)
				}
			}
			// 主角之外最多三人：玩家带的，加上一直摆在关卡里的阿塔兰忒。剧情里临时出现的
			// 人（赫拉克勒斯、2-1 的美狄亚）不占名额。
			beside := len(m.Party)
			if st.Unit("atalanta") != nil {
				beside++
			}
			if beside > 3 {
				t.Errorf("%s %s: %d march beside the protagonist; three is the most", tier, battle, beside)
			}
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
	if kitted[0].Units["chiron"] == nil || kitted[0].Units["medea"] == nil || bare[0].Units["chiron"] != nil {
		t.Errorf("the typical party brings Chiron and Medea; the bare one does not")
	}
	if kitted[0].Units["hero"].MaxHP <= bare[0].Units["hero"].MaxHP {
		t.Errorf("his gear should show: %d against %d", kitted[0].Units["hero"].MaxHP, bare[0].Units["hero"].MaxHP)
	}
}
