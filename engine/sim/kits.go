package sim

import (
	"fmt"
	"os"
	"slices"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"

	"srpg/rules"
)

// Kits 是"玩家打到某一关时带着什么"的几套估计（balance/kits.yaml）。模拟器不知道营地里
// 发生过什么，这份文件替它记着：每一档写出这种玩家怎么挣钱，再按关卡先后写出他在营地里
// 做的每一件事——买了什么、卖了什么、招了谁、谁穿什么、学了什么。打到哪一关，就把那一关
// 之前的事都算上。
//
// 原则：模拟一关，就用玩家打到那一关时能有的东西。Resolve 逐条核对：买的东西那时行商
// 有没有货，招的人那时来了没有，花的钱有没有超过那时挣到的，等级够不够学那些招式，
// 出战的人有没有超过名额，圣物是不是来早了。有一条对不上就报错，不让模拟跑下去。
type Kits struct {
	Tiers map[string]*Tier `yaml:"tiers"`
}

// Tier 是一种玩家。
type Tier struct {
	Earns Earns     `yaml:"earns"`
	Steps []KitStep `yaml:"steps"`
}

// Earns 说这种玩家怎么挣钱和经验。
type Earns struct {
	Asides   float64 `yaml:"asides"`   // 每场做到可选目标的机会（0 到 1）
	Spoils   string  `yaml:"spoils"`   // 卖战利品："none" 不卖，"materials" 只卖材料，"all" 全卖
	Optional bool    `yaml:"optional"` // 打不打可选的战斗
}

// KitStep 是进入 At 这一关之前在营地里做的事。
type KitStep struct {
	At   string `yaml:"at"`
	Note string `yaml:"note"`
	// Joins 是剧情里加入的人（不花钱）；Hire 是招募的英雄（recruits.json 里的名字）。
	Joins []string `yaml:"joins"`
	Hire  []string `yaml:"hire"`
	Buy   []string `yaml:"buy"`  // 从行商那里买的东西，可以重复
	Sell  []string `yaml:"sell"` // 卖掉的东西
	// Party 是跟主角出战的人，不含关卡文件里已经摆好的。写了就换掉之前的。
	Party []string `yaml:"party"`
	// Picks、Wear、Items 都按人写，写了就换掉那个人之前的。Wear 写这个人身上的全部装备。
	Picks  map[string][]string `yaml:"picks"`
	Wear   map[string][]string `yaml:"wear"`
	Items  map[string][]string `yaml:"items"`
	Relics []string            `yaml:"relics"`
	Worn   []string            `yaml:"worn"`
	Boon   string              `yaml:"boon"`
	Powers []string            `yaml:"powers"`
}

// Ledger 是算到某一关时这一档玩家的账。
type Ledger struct {
	Level  int
	Earned int // 进入这一关之前累计挣到的钱（含起始的）
	Spent  int // 累计花掉的钱（买和招，减去卖回的）
}

// 剧情里加入的人：id 就是单位定义。
var storyCompanions = map[string]bool{"chiron": true, "medea": true}

// LoadKits 读入 kits.yaml。
func LoadKits(path string) (*Kits, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var k Kits
	if err := yaml.Unmarshal(raw, &k); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if len(k.Tiers) == 0 {
		return nil, fmt.Errorf("%s: 没有任何一档配置", path)
	}
	return &k, nil
}

// Names 按字母顺序列出有哪几档。
func (k *Kits) Names() []string {
	names := make([]string, 0, len(k.Tiers))
	for name := range k.Tiers {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// CampaignOrder 是战役里的关卡，按先后。测试图和工坊变体不算。
func CampaignOrder(data *rules.Data) ([]string, error) {
	all, err := data.BattleIDs()
	if err != nil {
		return nil, err
	}
	var out []string
	for _, id := range all {
		if rules.Chapter(id) > 0 && strings.Contains(id, "-") && !strings.ContainsAny(id, "xX_") {
			out = append(out, id)
		}
	}
	return out, nil
}

// Muster 算出这一档的玩家进入 battle 时的全部家当；配置有任何一条不合时宜就报错。
func (k *Kits) Muster(data *rules.Data, tier, battle string) (*rules.Muster, error) {
	m, _, problems, err := k.Resolve(data, tier, battle)
	if err != nil {
		return nil, err
	}
	if len(problems) > 0 {
		return nil, fmt.Errorf("出战配置 %s 在 %s 不合时宜：%s", tier, battle, strings.Join(problems, "；"))
	}
	return m, nil
}

// Resolve 把这一档玩家从头走到 battle 之前，返回开局、账目，以及发现的每一条问题。
func (k *Kits) Resolve(data *rules.Data, tier, battle string) (*rules.Muster, *Ledger, []string, error) {
	t, ok := k.Tiers[tier]
	if !ok {
		return nil, nil, nil, fmt.Errorf("没有这一档出战配置: %s（有 %v）", tier, k.Names())
	}
	market, err := data.Market()
	if err != nil {
		return nil, nil, nil, err
	}
	order, err := CampaignOrder(data)
	if err != nil {
		return nil, nil, nil, err
	}
	if !slices.Contains(order, battle) {
		return nil, nil, nil, fmt.Errorf("没有这场战斗: %s", battle)
	}
	for i := range t.Steps {
		if !slices.Contains(order, t.Steps[i].At) {
			return nil, nil, nil, fmt.Errorf("出战配置 %s 里写了不存在的战斗 %s", tier, t.Steps[i].At)
		}
	}

	var problems []string
	bad := func(at, format string, args ...any) {
		problems = append(problems, at+" "+fmt.Sprintf(format, args...))
	}
	camp := map[string]rules.PartyMember{}
	owned := map[string]int{}
	wear := map[string][]string{}
	picks := map[string][]string{}
	items := map[string][]string{}
	var going, relics, worn, powers []string
	boon := ""
	ledger := &Ledger{Level: 1, Earned: market.StartingCoins}
	xp := 0

	for _, at := range order {
		ledger.Level = market.LevelAt(xp)
		for i := range t.Steps {
			step := &t.Steps[i]
			if step.At != at {
				continue
			}
			for _, who := range step.Joins {
				if !storyCompanions[who] {
					bad(at, "%s 不是剧情里会加入的人", who)
					continue
				}
				camp[who] = rules.PartyMember{ID: who, Def: who}
			}
			for _, kind := range step.Hire {
				r := market.Recruits[kind]
				switch {
				case r == nil:
					bad(at, "没有 %s 这位英雄", kind)
				case r.Opens > rules.Chapter(at):
					bad(at, "%s 要到第 %d 章才来投", r.Name, r.Opens)
				default:
					camp[kind] = rules.PartyMember{ID: kind, Def: r.Def, Name: r.Name, Skills: []string{r.Skill}, Tree: kind}
					ledger.Spent += r.Fee
				}
			}
			for _, id := range step.Buy {
				g := market.Goods[id]
				switch {
				case g == nil:
					bad(at, "没有 %s 这件东西", id)
				case !market.Stocked(id, at):
					bad(at, "行商这时不卖 %s（第 %d 章起才有，或只能从敌人身上得到）", id, g.Chapter)
				default:
					owned[id]++
					ledger.Spent += g.Price
				}
			}
			for _, id := range step.Sell {
				if owned[id] <= 0 {
					bad(at, "卖了没有的东西 %s", id)
					continue
				}
				owned[id]--
				ledger.Spent -= market.SellPrice(id)
			}
			if step.Party != nil {
				going = step.Party
			}
			for who, nodes := range step.Picks {
				picks[who] = nodes
			}
			for who, things := range step.Wear {
				wear[who] = things
			}
			for who, things := range step.Items {
				items[who] = things
			}
			if step.Relics != nil {
				relics, worn = step.Relics, step.Worn
			} else if step.Worn != nil {
				worn = step.Worn
			}
			if step.Boon != "" {
				boon = step.Boon
			}
			if step.Powers != nil {
				powers = step.Powers
			}
			if ledger.Spent > ledger.Earned {
				bad(at, "到这时累计花了 %d，而这一档玩家那时一共只挣到 %d", ledger.Spent, ledger.Earned)
			}
		}
		if at == battle {
			break
		}
		// 打完这一关的收入和经验（这一档不打的可选关跳过）。
		if market.OptionalBattles[at] && (!t.Earns.Optional || market.OnlyIfSkipped[at] != "") {
			// 不打可选战的玩家跳过；只在没打另一场时才出现的（2-S），打可选战的玩家也碰不到。
			continue
		}
		pay := market.PayFor(at)
		income := float64(pay) + t.Earns.Asides*float64(pay*(market.AsidePays-1))
		if def, err := data.Battle(at); err == nil && t.Earns.Spoils != "none" && t.Earns.Spoils != "" {
			for _, u := range def.Units {
				if u.Team != rules.TeamEnemy {
					continue
				}
				materials, rest := market.Spoils(u.Def)
				income += materials
				if t.Earns.Spoils == "all" {
					income += rest
				}
			}
		}
		ledger.Earned += int(income)
		xp += market.XPFor(at)
	}

	// 身上和包里的东西对得上手里有的。
	used := map[string]int{}
	m := &rules.Muster{Picks: picks, Mods: map[string]map[string]int{}, Items: map[string][]string{}}
	charms := map[string]string{}
	for _, who := range sortedKeys(wear) {
		slots := map[string]string{}
		for _, id := range wear[who] {
			g := market.Goods[id]
			if g == nil {
				bad(battle, "%s 穿了不存在的 %s", who, id)
				continue
			}
			if g.Slot == "item" || g.Slot == "material" {
				bad(battle, "%s 不是能穿的东西", id)
				continue
			}
			if other, taken := slots[g.Slot]; taken {
				bad(battle, "%s 的同一个部位穿了 %s 和 %s", who, other, id)
				continue
			}
			slots[g.Slot] = id
			used[id]++
			if g.Unique {
				charms[id] = who
				continue
			}
			if m.Mods[who] == nil {
				m.Mods[who] = map[string]int{}
			}
			for stat, by := range g.Mods {
				m.Mods[who][stat] += by
			}
		}
	}
	for _, who := range sortedKeys(items) {
		if len(items[who]) > market.KitSlots {
			bad(battle, "%s 带了 %d 件物品，最多 %d 件", who, len(items[who]), market.KitSlots)
		}
		for _, id := range items[who] {
			if g := market.Goods[id]; g == nil || g.Slot != "item" {
				bad(battle, "%s 不是随身物品", id)
				continue
			}
			used[id]++
		}
		m.Items[who] = items[who]
	}
	for _, id := range sortedKeys(used) {
		if used[id] > owned[id] {
			bad(battle, "用了 %d 件 %s，手里只有 %d 件", used[id], id, owned[id])
		}
	}

	// 出战名单和名额。
	def, err := data.Battle(battle)
	if err != nil {
		return nil, nil, nil, err
	}
	placed := map[string]bool{}
	for _, u := range def.Units {
		placed[u.ID] = true
	}
	beside := 0
	if placed["atalanta"] {
		beside++
	}
	for _, id := range going {
		who, ok := camp[id]
		if !ok {
			bad(battle, "带了营地里没有的人 %s", id)
			continue
		}
		if !placed[id] {
			m.Party = append(m.Party, who)
			beside++
		}
	}
	if seats := market.SeatsFor(battle); beside > seats {
		bad(battle, "主角之外带了 %d 人，这一章最多 %d 人", beside, seats)
	}

	// 等级够不够学这些招式。只核对剧情里的人；招募来的人入队时的经验另算。
	for _, who := range sortedKeys(picks) {
		tree := who
		if member, ok := camp[who]; ok && member.Tree != "" {
			tree = member.Tree
		}
		if msg := data.ValidateTraining(tree, picks[who], 99); msg != "" {
			bad(battle, "%s 的加点不成立：%s", who, msg)
			continue
		}
		if _, hired := market.Recruits[who]; hired {
			continue
		}
		points := ledger.Level - 1
		if market.FreeFirst[who] != "" {
			points++
		}
		spent := data.PicksCost(tree, picks[who])
		if spent > points {
			bad(battle, "%s 花了 %d 点，这时 %d 级只有 %d 点", who, spent, ledger.Level, points)
		}
		if (who == "hero" || who == "atalanta") && spent < points-1 {
			bad(battle, "%s 有 %d 点只花了 %d 点，配置停在了更早的状态", who, points, spent)
		}
	}

	// 圣物：第 n 件要打完第 n 章才有；第二章起一定带着狮皮。
	chapter := rules.Chapter(battle)
	if len(relics) > chapter-1 {
		bad(battle, "第 %d 章就有了 %d 件圣物", chapter, len(relics))
	}
	if chapter >= 2 && len(relics) == 0 {
		bad(battle, "第 %d 章还没有狮皮", chapter)
	}
	if len(relics) > 0 {
		if worn == nil {
			worn = relics[:min(len(relics), rules.RelicSlots(len(relics)))]
		}
		m.Reward = rules.ChapterReward{EquippedRelic: relics[0], Worn: worn, Boon: boon, Divinity: len(relics), Powers: powers}
	}
	if len(charms) > 0 {
		m.Reward.Charms = charms
	}
	return m, ledger, problems, nil
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
