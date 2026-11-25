package sim

import (
	"fmt"
	"os"
	"slices"
	"sort"

	"gopkg.in/yaml.v3"

	"srpg/rules"
)

// Kits 是"玩家打到某一关时带着什么"的几套估计（balance/kits.yaml）。模拟器不知道营地里
// 发生过什么，这份文件替它记着：每一档按关卡先后写出一步一步的变化，打到哪一关就把那
// 一关之前的变化都叠上。
type Kits struct {
	Tiers map[string][]KitStep `yaml:"tiers"`
}

// KitStep 是进入 At 这一关之前发生的变化。Hire 和 Mods 是累加的；Party、Picks、Items、
// Relics 等写了就整个换掉之前的（Picks、Items 按人换）。
type KitStep struct {
	At    string `yaml:"at"`
	Level int    `yaml:"level"` // 这时大家大约几级；只用来核对加点花费
	Note  string `yaml:"note"`
	// Hire 是从这时起在营地里的人：招募来的，以及剧情里加入的喀戎、美狄亚。
	Hire []rules.PartyMember `yaml:"hire"`
	// Party 是跟主角出战的人（不含关卡文件里已经摆好的），按 Hire 里的 id 写。
	Party []string                  `yaml:"party"`
	Picks map[string][]string       `yaml:"picks"`
	Mods  map[string]map[string]int `yaml:"mods"`
	Items map[string][]string       `yaml:"items"`
	// Relics 是拿到的全部圣物；Worn 是带上的那几件，不写就按栏数从前往后带。
	Relics []string `yaml:"relics"`
	Worn   []string `yaml:"worn"`
	Boon   string   `yaml:"boon"`
	Powers []string `yaml:"powers"`
}

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

// Level 是这一档进入 battle 时大约的等级（没写过就是 1）。
func (k *Kits) Level(data *rules.Data, tier, battle string) (int, error) {
	level := 1
	err := k.walk(data, tier, battle, func(step *KitStep) {
		if step.Level > 0 {
			level = step.Level
		}
	})
	return level, err
}

// walk 按关卡先后把 battle 及之前的每一步交给 visit。
func (k *Kits) walk(data *rules.Data, tier, battle string, visit func(*KitStep)) error {
	steps, ok := k.Tiers[tier]
	if !ok {
		return fmt.Errorf("没有这一档出战配置: %s（有 %v）", tier, k.Names())
	}
	order, err := data.BattleIDs()
	if err != nil {
		return err
	}
	at := slices.Index(order, battle)
	if at < 0 {
		return fmt.Errorf("没有这场战斗: %s", battle)
	}
	for i := range steps {
		when := slices.Index(order, steps[i].At)
		if when < 0 {
			return fmt.Errorf("出战配置 %s 里写了不存在的战斗 %s", tier, steps[i].At)
		}
		if when <= at {
			visit(&steps[i])
		}
	}
	return nil
}

// Muster 算出这一档的玩家进入 battle 时的全部家当。
func (k *Kits) Muster(data *rules.Data, tier, battle string) (*rules.Muster, error) {
	camp := map[string]rules.PartyMember{}
	var going, relics, worn, powers []string
	boon := ""
	m := &rules.Muster{Picks: map[string][]string{}, Mods: map[string]map[string]int{}, Items: map[string][]string{}}
	err := k.walk(data, tier, battle, func(step *KitStep) {
		for _, who := range step.Hire {
			camp[who.ID] = who
		}
		if step.Party != nil {
			going = step.Party
		}
		for who, nodes := range step.Picks {
			m.Picks[who] = nodes
		}
		for who, changes := range step.Mods {
			if m.Mods[who] == nil {
				m.Mods[who] = map[string]int{}
			}
			for stat, by := range changes {
				m.Mods[who][stat] += by
			}
		}
		for who, things := range step.Items {
			m.Items[who] = things
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
	})
	if err != nil {
		return nil, err
	}
	def, err := data.Battle(battle)
	if err != nil {
		return nil, err
	}
	placed := map[string]bool{}
	for _, u := range def.Units {
		placed[u.ID] = true
	}
	for _, id := range going {
		who, ok := camp[id]
		if !ok {
			return nil, fmt.Errorf("出战配置 %s 在 %s 带了营地里没有的人: %s", tier, battle, id)
		}
		if !placed[id] {
			m.Party = append(m.Party, who)
		}
	}
	if len(relics) > 0 {
		if worn == nil {
			worn = relics[:min(len(relics), rules.RelicSlots(len(relics)))]
		}
		m.Reward = rules.ChapterReward{EquippedRelic: relics[0], Worn: worn, Boon: boon, Divinity: len(relics), Powers: powers}
	}
	return m, nil
}
