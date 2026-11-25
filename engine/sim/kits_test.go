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
			seats := 3 // 连主角：第一章 2 人，第二章 3 人，之后 4 人（campaign_checkpoint.gd 的 seats）
			switch battle[0] {
			case '1':
				seats = 1
			case '2':
				seats = 2
			}
			if beside > seats {
				t.Errorf("%s %s: %d march beside the protagonist; %d is the most in this chapter", tier, battle, beside, seats)
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
	if kitted[0].Units["medea"] == nil || bare[0].Units["medea"] != nil {
		t.Errorf("the typical party brings Medea; the bare one does not")
	}
	if kitted[0].Units["hero"].MaxHP <= bare[0].Units["hero"].MaxHP {
		t.Errorf("his gear should show: %d against %d", kitted[0].Units["hero"].MaxHP, bare[0].Units["hero"].MaxHP)
	}
}

// 每一关都要用"那时玩家能有的东西"来模拟：等级跟得上经验，点数基本花掉，圣物不早到。
// 经验规则抄自 prototype/core/campaign_checkpoint.gd（xp_for、xp_need），那边改了这里跟着改。
func TestKitsFitTheirMoment(t *testing.T) {
	data, err := rules.LoadData(rules.DataOptions{})
	if err != nil {
		t.Fatal(err)
	}
	kits, err := LoadKits("../../balance/kits.yaml")
	if err != nil {
		t.Fatal(err)
	}
	battles := []string{"1-1", "1-2", "1-3", "1-4", "1-5", "2-1", "2-2", "2-3", "2-4"}
	optional := map[string]bool{"1-3": true}
	levelAt := func(xp int) int {
		level := 1
		for xp >= 100+20*(level-1) {
			xp -= 100 + 20*(level-1)
			level++
		}
		return level
	}
	free := map[string]bool{"atalanta": true}
	for _, tier := range kits.Names() {
		most, least := 0, 0 // 进入这一关之前攒下的经验：每关都打 / 不打可选关
		for _, battle := range battles {
			level, _ := kits.Level(data, tier, battle)
			if hi, lo := levelAt(most), levelAt(least); level > hi || level < lo {
				t.Errorf("%s %s: level %d, but by then it is %d to %d", tier, battle, level, lo, hi)
			}
			m, err := kits.Muster(data, tier, battle)
			if err != nil {
				t.Fatal(err)
			}
			for _, who := range []string{"hero", "atalanta"} {
				points := level - 1
				if free[who] {
					points++
				}
				if spent := data.PicksCost(who, m.Picks[who]); spent < points-1 {
					t.Errorf("%s %s: %s has %d points and has spent only %d; the kit is behind its moment", tier, battle, who, points, spent)
				}
			}
			chapter := int(battle[0] - '0')
			if n := m.Reward.Divinity; n > chapter-1 {
				t.Errorf("%s %s: %d relics in chapter %d; the n-th is only won at the end of chapter n", tier, battle, n, chapter)
			}
			if chapter >= 2 && m.Reward.Divinity == 0 {
				t.Errorf("%s %s: no relic in chapter %d; the lion's pelt is always taken", tier, battle, chapter)
			}
			gain := 100
			if chapter >= 2 {
				gain = 140
			}
			most += gain
			if !optional[battle] {
				least += gain
			}
		}
	}
}
