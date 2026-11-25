package rules

import "fmt"

// PartyMember 是出战名单里的一个人：关卡文件没摆、由玩家带上场的。
type PartyMember struct {
	ID   string `json:"id"`
	Def  string `json:"def"`
	Name string `json:"name"`
	// Tree 是这个人自己的技能树的名字；空着就用单位定义的那棵。
	Tree string `json:"tree"`
	// Skills 是这个人自带、单位定义里没有的招式（招募来的人的起始技能）。
	Skills []string `json:"skills"`
}

// Muster 是一场战斗开打前从营地带来的一切：谁上场、谁留守、各人学了什么、带哪几招、
// 穿戴加了多少属性、随身带什么物品，以及主角的圣物、神赐和神性。游戏和模拟器都用它。
type Muster struct {
	Party   []PartyMember
	Bench   []string // 关卡文件里摆了、这一场留在营地的我方单位
	Picks   map[string][]string
	Loadout map[string][]string       // 按单位 id：带进战斗的招式；没列出的带上全部
	Mods    map[string]map[string]int // 按单位 id：装备带来的属性增减
	Items   map[string][]string       // 按单位 id：随身物品
	Reward  ChapterReward
	Support string // 来支援的英雄；空着就是没带。他学了的节点写在 Picks[Support] 里
}

// Muster 按关卡文件布阵，再把 m 里的东西都安排上。顺序固定：留守、出战名单、神性、
// 携带的招式、装备、物品、圣物与神赐。
func (d *Data) Muster(battle string, m Muster) (*BattleState, error) {
	st, err := d.Build(battle, m.Picks)
	if err != nil {
		return nil, err
	}
	for _, id := range m.Bench {
		if err := bench(st, id); err != nil {
			return nil, err
		}
	}
	if err := d.deploy(st, m.Party, m.Picks); err != nil {
		return nil, err
	}
	if err := st.GrantDivinity(d, m.Reward); err != nil {
		return nil, err
	}
	for id, carried := range m.Loadout {
		if u := st.Unit(id); u != nil {
			if err := u.Carry(carried); err != nil {
				return nil, err
			}
		}
	}
	for id, changes := range m.Mods {
		if u := st.Unit(id); u != nil {
			if err := u.Adjust(changes); err != nil {
				return nil, err
			}
		}
	}
	for id, kit := range m.Items {
		u := st.Unit(id)
		if u == nil {
			continue
		}
		for _, item := range kit {
			sk := d.Skill(item)
			if sk == nil {
				return nil, fmt.Errorf("没有这种物品: %s", item)
			}
			if err := u.Pack(sk); err != nil {
				return nil, err
			}
		}
	}
	st.EquipReward(d, m.Reward)
	if err := st.GrantSupport(d, m.Support, m.Picks[m.Support]); err != nil {
		return nil, err
	}
	return st, nil
}

// deploy 把额外出战的人放到主角身边：从主角所在格向外一圈圈找，站到最近的空地上。
// 只用和主角高差不超过 1、不是深水也不在燃烧的格子，免得开场就被困住。
// bench 把关卡文件里的一名我方单位留在营地：这一场没有他。
func bench(st *BattleState, id string) error {
	for i, u := range st.Units {
		if u.ID != id {
			continue
		}
		if id == "hero" || u.Team != TeamPlayer {
			return fmt.Errorf("%s 不能留守", id)
		}
		st.Units = append(st.Units[:i], st.Units[i+1:]...)
		return nil
	}
	return nil
}

func (d *Data) deploy(st *BattleState, party []PartyMember, picks map[string][]string) error {
	hero := st.Unit("hero")
	if hero == nil || len(party) == 0 {
		return nil
	}
	seen := map[Cell]bool{hero.Pos: true}
	ring := []Cell{hero.Pos}
	next := 0
	for len(ring) > 0 && next < len(party) {
		var outer []Cell
		for _, from := range ring {
			for _, dir := range Dirs {
				c := from.Add(dir)
				if seen[c] || !st.Grid.InBounds(c) {
					continue
				}
				seen[c] = true
				drop := st.Grid.HeightAt(c) - st.Grid.HeightAt(hero.Pos)
				terrain := st.Grid.TerrainAt(c)
				if drop > 1 || drop < -1 || terrain == Deep || terrain == Burning {
					continue
				}
				outer = append(outer, c)
				if st.UnitAt(c) != nil || next >= len(party) {
					continue
				}
				member := party[next]
				if st.Unit(member.ID) != nil {
					return fmt.Errorf("出战名单里的 %s 已经在场上", member.ID)
				}
				u, err := d.MakeUnit(member.Def, member.ID, TeamPlayer, c, hero.Facing)
				if err != nil {
					return err
				}
				if member.Name != "" {
					u.Name = member.Name
				}
				for _, id := range member.Skills {
					sk := d.Skill(id)
					if sk == nil {
						return fmt.Errorf("出战名单里的 %s 带了不存在的招式 %s", member.ID, id)
					}
					u.AddSkill(sk)
				}
				if member.Tree != "" && d.Trees(member.Tree) == nil {
					return fmt.Errorf("出战名单里的 %s 要学不存在的技能树 %s", member.ID, member.Tree)
				}
				u.Tree = member.Tree
				d.ApplyPicks(u, picks[member.ID])
				u.HP = u.MaxHP
				st.AddUnit(u)
				next++
			}
		}
		ring = outer
	}
	if next < len(party) {
		return fmt.Errorf("主角身边没有足够的空地放下 %d 名出战者", len(party))
	}
	return nil
}
