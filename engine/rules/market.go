package rules

import (
	"fmt"
	"strconv"
)

// Market 是营地这一侧的数据：能买什么、敌人掉什么、能招谁，以及战役的几个基本数。
// 战斗规则用不到它；模拟器靠它核对"打到这一关时玩家可能有什么"。
// 来源是 goods.json、loot.json、recruits.json、campaign.json，游戏读的是同一份文件。
type Market struct {
	Goods    map[string]*Good
	Recruits map[string]*Recruit
	Loot     map[string][]Drop

	StartingCoins   int
	Pay, XP, Seats  map[int]int // 按章
	AsidePays       int         // 做到可选目标时酬金是几倍
	SellFor         float64     // 卖出价是买价的几成
	XPFirst, XPStep int         // 升到 2 级要的经验，之后每级多要多少
	KitSlots        int
	OptionalBattles map[string]bool
	// OnlyIfSkipped：这场可选战只在没打另一场时才出现（2-S 对 1-3）。
	OnlyIfSkipped map[string]string
	// FreeFirst：第一招不花点数的人和那一招。
	FreeFirst map[string]string
	goodOrder []string
}

// Good 是一件东西。Slot 是穿戴的部位，或 "item"（消耗品）、"material"（只能卖）。
type Good struct {
	ID, Slot string
	Price    int
	Chapter  int // 哪一章起行商有货
	Mods     map[string]int
	Loot     bool // 只能从敌人身上得到，行商不卖
	Unique   bool // 规则按名字认的护符，效果不只是属性
}

// Recruit 是一位可以招募的英雄。
type Recruit struct {
	ID, Def, Skill, Name string
	Fee, Opens           int // 雇金；哪一章起来投
}

// Drop 是掉落表里的一行。
type Drop struct {
	Thing  string
	Chance float64
}

// Market 读入营地这一侧的数据表。
func (d *Data) Market() (*Market, error) {
	m := &Market{Goods: map[string]*Good{}, Recruits: map[string]*Recruit{}, Loot: map[string][]Drop{},
		Pay: map[int]int{}, XP: map[int]int{}, Seats: map[int]int{}, OptionalBattles: map[string]bool{}}
	goods, err := d.table("goods")
	if err != nil {
		return nil, err
	}
	for _, id := range goods.keys {
		raw, _ := goods.m[id].(*jobj)
		if raw == nil {
			return nil, fmt.Errorf("goods.json 的 %s 不是对象", id)
		}
		if err := raw.need("物品 "+id, "slot", "price"); err != nil {
			return nil, err
		}
		g := &Good{ID: id, Slot: raw.str("slot", ""), Price: raw.int("price", 0), Chapter: raw.int("chapter", 1), Mods: map[string]int{}}
		g.Loot, _ = raw.m["loot"].(bool)
		g.Unique, _ = raw.m["unique"].(bool)
		if mods, ok := raw.m["mods"].(*jobj); ok {
			for stat, v := range mods.m {
				g.Mods[stat] = asInt(v)
			}
		}
		m.Goods[id] = g
		m.goodOrder = append(m.goodOrder, id)
	}
	recruits, err := d.table("recruits")
	if err != nil {
		return nil, err
	}
	for _, id := range recruits.keys {
		raw, _ := recruits.m[id].(*jobj)
		if raw == nil {
			return nil, fmt.Errorf("recruits.json 的 %s 不是对象", id)
		}
		if err := raw.need("英雄 "+id, "fee", "def", "skill", "name"); err != nil {
			return nil, err
		}
		r := &Recruit{ID: id, Def: raw.str("def", ""), Skill: raw.str("skill", ""), Name: raw.str("name", ""),
			Fee: raw.int("fee", 0), Opens: raw.int("opens", 2)}
		if d.units[r.Def] == nil {
			return nil, fmt.Errorf("英雄 %s 用到了不存在的单位 %s", id, r.Def)
		}
		if d.Skill(r.Skill) == nil {
			return nil, fmt.Errorf("英雄 %s 带了不存在的招式 %s", id, r.Skill)
		}
		m.Recruits[id] = r
	}
	loot, err := d.table("loot")
	if err != nil {
		return nil, err
	}
	for _, kind := range loot.keys {
		rows, _ := loot.m[kind].([]any)
		for _, row := range rows {
			pair, _ := row.([]any)
			if len(pair) != 2 {
				return nil, fmt.Errorf("loot.json 的 %s 有一行不是 [物品, 概率]", kind)
			}
			thing, _ := pair[0].(string)
			chance, _ := pair[1].(float64)
			if m.Goods[thing] == nil {
				return nil, fmt.Errorf("%s 掉落了不存在的物品 %s", kind, thing)
			}
			m.Loot[kind] = append(m.Loot[kind], Drop{Thing: thing, Chance: chance})
		}
	}
	c, err := d.table("campaign")
	if err != nil {
		return nil, err
	}
	if err := c.need("campaign.json", "starting_coins", "pay", "xp", "seats", "xp_need", "sell_for", "aside_pays", "kit_slots"); err != nil {
		return nil, err
	}
	m.StartingCoins, m.AsidePays, m.KitSlots = c.int("starting_coins", 0), c.int("aside_pays", 1), c.int("kit_slots", 2)
	m.SellFor, _ = c.m["sell_for"].(float64)
	for key, into := range map[string]map[int]int{"pay": m.Pay, "xp": m.XP, "seats": m.Seats} {
		tbl, _ := c.m[key].(*jobj)
		if tbl == nil {
			return nil, fmt.Errorf("campaign.json 的 %s 不是按章的表", key)
		}
		for chapter, v := range tbl.m {
			n, err := strconv.Atoi(chapter)
			if err != nil {
				return nil, fmt.Errorf("campaign.json 的 %s 里 %q 不是章号", key, chapter)
			}
			into[n] = asInt(v)
		}
	}
	if need, ok := c.m["xp_need"].(*jobj); ok {
		m.XPFirst, m.XPStep = need.int("first", 100), need.int("more_each_level", 20)
	}
	for _, id := range stringsOf(c.m["optional_battles"]) {
		m.OptionalBattles[id] = true
	}
	m.OnlyIfSkipped, m.FreeFirst = map[string]string{}, map[string]string{}
	for key, into := range map[string]map[string]string{"only_if_skipped": m.OnlyIfSkipped, "free_first_technique": m.FreeFirst} {
		if tbl, ok := c.m[key].(*jobj); ok {
			for k, v := range tbl.m {
				into[k], _ = v.(string)
			}
		}
	}
	return m, nil
}

// Chapter 是关卡 id（"2-3"）里的章号。
func Chapter(battle string) int {
	n := 0
	for _, ch := range battle {
		if ch < '0' || ch > '9' {
			break
		}
		n = n*10 + int(ch-'0')
	}
	return n
}

// byChapter 取这一章的数；表里没写到的章沿用写了的最后一章。
func byChapter(table map[int]int, chapter int) int {
	best, at := 0, -1
	for c, v := range table {
		if c <= chapter && c > at {
			best, at = v, c
		}
	}
	return best
}

func (m *Market) PayFor(battle string) int   { return byChapter(m.Pay, Chapter(battle)) }
func (m *Market) XPFor(battle string) int    { return byChapter(m.XP, Chapter(battle)) }
func (m *Market) SeatsFor(battle string) int { return byChapter(m.Seats, Chapter(battle)) }

// SellPrice 是卖掉一件东西得到的钱。
func (m *Market) SellPrice(id string) int {
	return int(float64(m.Goods[id].Price) * m.SellFor)
}

// LevelAt 是攒到这么多经验时的等级。
func (m *Market) LevelAt(xp int) int {
	level := 1
	for need := m.XPFirst; xp >= need; need = m.XPFirst + m.XPStep*(level-1) {
		xp -= need
		level++
	}
	return level
}

// Stocked 表示行商在这一关所在的章里卖这件东西。
func (m *Market) Stocked(id, battle string) bool {
	g := m.Goods[id]
	return g != nil && g.Slot != "material" && !g.Loot && g.Chapter <= Chapter(battle)
}

// Spoils 是打倒一个这种敌人平均能卖出的钱：材料一份，掉的装备和物品另一份。
// 每个敌人至少留下一件材料（骰子没给就给表里的第一种）。
func (m *Market) Spoils(kind string) (materials, rest float64) {
	none, first := 1.0, ""
	for _, drop := range m.Loot[kind] {
		worth := drop.Chance * float64(m.SellPrice(drop.Thing))
		if m.Goods[drop.Thing].Slot == "material" {
			materials += worth
			none *= 1 - drop.Chance
			if first == "" {
				first = drop.Thing
			}
		} else {
			rest += worth
		}
	}
	if first != "" {
		materials += none * float64(m.SellPrice(first))
	}
	return materials, rest
}
