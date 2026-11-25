package rules

import "fmt"

// KV 是有序小表的一项（状态 → 剩余回合，技能 → 冷却）。保持插入顺序，和原版字典一致。
type KV struct {
	Key string
	Val int
}

// Traits 是单位的特性。规则会查询的特性拆成字段；其余只记名字。
type Traits struct {
	PhysicalImmune, Block, ForestStride, Flying, CannotAttackAdjacent, HunterMark bool
	IronArm, ShieldWall, Intercept, Patience, Skirmish, Undead, MarshStride       bool
	Other                                                                         []string // 规则不关心的特性（guest、anti_air……）
}

func (t *Traits) flag(key string) *bool {
	switch key {
	case "physical_immune":
		return &t.PhysicalImmune
	case "block":
		return &t.Block
	case "forest_stride":
		return &t.ForestStride
	case "marsh_stride":
		return &t.MarshStride
	case "flying":
		return &t.Flying
	case "cannot_attack_adjacent":
		return &t.CannotAttackAdjacent
	case "hunter_mark":
		return &t.HunterMark
	case "iron_arm":
		return &t.IronArm
	case "shield_wall":
		return &t.ShieldWall
	case "intercept":
		return &t.Intercept
	case "patience":
		return &t.Patience
	case "skirmish":
		return &t.Skirmish
	case "undead":
		return &t.Undead
	}
	return nil
}

// Has 判断是否带有某个特性（只看键是否存在，与原版 has_trait 相同）。
func (t *Traits) Has(key string) bool {
	if p := t.flag(key); p != nil {
		return *p
	}
	for _, k := range t.Other {
		if k == key {
			return true
		}
	}
	return false
}

// Set 加上一个特性。value 目前没有特性用到，留着是因为表里的特性可以带数值。
func (t *Traits) Set(key string, value int) {
	if p := t.flag(key); p != nil {
		*p = true
		return
	}
	if !t.Has(key) {
		t.Other = append(t.Other[:len(t.Other):len(t.Other)], key)
	}
}

// UnitState 是一个单位的运行时状态。纯数据；规则在 rules.go 等文件里。
type UnitState struct {
	chargeDir       Cell
	ID, DefID, Name string
	Team            Team
	Pos             Cell // 占地的左上角
	Size            int
	Facing          Cell

	MaxHP, HP, Strength, Divinity, Defense, Will, Move, Jump int

	// Tree 是这个人学的技能树的名字；空着就用单位定义的名字（主角和剧情同伴）。
	// 招募来的英雄借用别的单位定义出战，但各有各的技能树。
	Tree string

	Skills    []*Skill
	Traits    Traits
	Statuses  []KV // 状态 → 剩余回合；staggered / stunned 由破势系统设置
	Shield    int
	Cooldowns []KV
	// Charges 是随身物品还剩几件（物品 id -> 件数）。
	Charges []KV

	Stagger    int
	StaggerMax int // > 0 表示带破势条的首领

	ActionsPerTurn, ActionsLeft                             int
	HasMoved, HasActed, AssistUsed, MarkUsed, InterceptUsed bool
	PostMove                                                int // 行动后还能走的步数（游击）
	// 阶位对圣物主动的好处用过没有：前一个每场一次，后一个每回合一次（见 divinity.go）。
	RelicFreeUsed, RelicSwiftUsed bool

	Arrival int // Scheduled round, zero after arrival.
	Alive   bool
	Hidden  bool // 不在场上（狮子在洞里）：不能被选中，也不挡路

	// 移动撤销用的快照
	undoOK              bool
	undoPos, undoFacing Cell

	index int // 在 BattleState.Units 里的下标
}

// NewUnit 返回带默认值的单位。
func NewUnit() *UnitState {
	return &UnitState{Size: 1, Facing: South, MaxHP: 1, HP: 1, Move: 4, Jump: 1,
		ActionsPerTurn: 1, Alive: true}
}

func (u *UnitState) IsBoss() bool { return u.StaggerMax > 0 }

func (u *UnitState) HasTrait(key string) bool { return u.Traits.Has(key) }

func (u *UnitState) HasStatus(key string) bool {
	for i := range u.Statuses {
		if u.Statuses[i].Key == key {
			return true
		}
	}
	return false
}

// Status 返回状态的剩余回合。
func (u *UnitState) Status(key string) (int, bool) {
	for i := range u.Statuses {
		if u.Statuses[i].Key == key {
			return u.Statuses[i].Val, true
		}
	}
	return 0, false
}

// SetStatus 设置状态；已有则原位更新，没有则排到最后。
func (u *UnitState) SetStatus(key string, rounds int) {
	u.Statuses = kvSet(u.Statuses, key, rounds)
}

func (u *UnitState) EraseStatus(key string) {
	u.Statuses = kvErase(u.Statuses, key)
}

func (u *UnitState) Cooldown(skillID string) int {
	for i := range u.Cooldowns {
		if u.Cooldowns[i].Key == skillID {
			return u.Cooldowns[i].Val
		}
	}
	return 0
}

func (u *UnitState) SetCooldown(skillID string, rounds int) {
	u.Cooldowns = kvSet(u.Cooldowns, skillID, rounds)
}

// StatusNames 按获得顺序列出状态名。
func (u *UnitState) StatusNames() []string {
	out := make([]string, len(u.Statuses))
	for i, kv := range u.Statuses {
		out[i] = kv.Key
	}
	return out
}

// Skill 返回单位掌握的技能定义，没有则为 nil。
func (u *UnitState) Skill(id string) *Skill {
	for _, sk := range u.Skills {
		if sk.ID == id {
			return sk
		}
	}
	return nil
}

func (u *UnitState) HasSkill(id string) bool { return u.Skill(id) != nil }

// AddSkill 学会一个技能（已有则不重复）。
func (u *UnitState) AddSkill(sk *Skill) {
	if !u.HasSkill(sk.ID) {
		u.Skills = append(u.Skills[:len(u.Skills):len(u.Skills)], sk)
	}
}

// Adjust 把装备带来的属性增减加到单位身上。生命、移动、跳跃不会被减到 1 以下。
func (u *UnitState) Adjust(changes map[string]int) error {
	for stat, by := range changes {
		switch stat {
		case "hp":
			u.MaxHP = max(1, u.MaxHP+by)
			u.HP = u.MaxHP
		case "str":
			u.Strength += by
		case "def":
			u.Defense += by
		case "wil":
			u.Will += by
		case "div":
			u.Divinity += by
		case "move":
			u.Move = max(1, u.Move+by)
		case "jump":
			u.Jump = max(1, u.Jump+by)
		default:
			return fmt.Errorf("%s 的装备改了不认识的属性 %s", u.ID, stat)
		}
	}
	return nil
}

// LoadoutSlots 是一个单位能带进战斗的技能数。基础攻击（定义里的第一个招式）不占格，特性也不占。
const LoadoutSlots = 4

// KitSlots 是一个单位能随身带的物品件数。
const KitSlots = 2

// Carry 只留下基础攻击和 ids 里列出的技能，按 ids 的顺序。没学会的 id 略过；
// 除基础攻击外超过 LoadoutSlots 个算错。
func (u *UnitState) Carry(ids []string) error {
	if len(u.Skills) == 0 {
		return nil
	}
	basic := u.Skills[0]
	kept := []*Skill{basic}
	seen := map[string]bool{basic.ID: true}
	for _, id := range ids {
		for _, sk := range u.Skills {
			if sk.ID == id && !seen[id] {
				kept = append(kept, sk)
				seen[id] = true
			}
		}
	}
	if len(kept)-1 > LoadoutSlots {
		return fmt.Errorf("%s 带了 %d 个技能，最多 %d 个", u.ID, len(kept)-1, LoadoutSlots)
	}
	u.Skills = kept
	return nil
}

// Charge 返回某种物品还剩几件。
func (u *UnitState) Charge(id string) int {
	for i := range u.Charges {
		if u.Charges[i].Key == id {
			return u.Charges[i].Val
		}
	}
	return 0
}

// Pack 把一件物品放到身上：会用了（进招式表），件数加一。
func (u *UnitState) Pack(item *Skill) error {
	total := 0
	for _, kv := range u.Charges {
		total += kv.Val
	}
	if total >= KitSlots {
		return fmt.Errorf("%s 随身物品超过 %d 件", u.ID, KitSlots)
	}
	if !item.Item {
		return fmt.Errorf("%s 不是物品", item.ID)
	}
	u.AddSkill(item)
	u.Charges = kvSet(u.Charges, item.ID, u.Charge(item.ID)+1)
	return nil
}

// Footprint 列出站在 anchor 时占的格子（先行后列）。
func (u *UnitState) Footprint(anchor Cell) []Cell {
	cells := make([]Cell, 0, u.Size*u.Size)
	for dy := 0; dy < u.Size; dy++ {
		for dx := 0; dx < u.Size; dx++ {
			cells = append(cells, Cell{anchor.X + dx, anchor.Y + dy})
		}
	}
	return cells
}

func (u *UnitState) Occupies(c Cell) bool {
	return c.X >= u.Pos.X && c.Y >= u.Pos.Y && c.X < u.Pos.X+u.Size && c.Y < u.Pos.Y+u.Size
}

// Center 返回占地中心（站在当前位置）。
func (u *UnitState) Center() (x, y float64) { return u.CenterAt(u.Pos) }

func (u *UnitState) CenterAt(anchor Cell) (x, y float64) {
	half := float64(u.Size) * 0.5
	return float64(anchor.X) + half, float64(anchor.Y) + half
}

// Copy 返回独立的副本。
func (u *UnitState) Copy() *UnitState {
	n := *u
	n.Skills = u.Skills[:len(u.Skills):len(u.Skills)]
	n.Statuses = append([]KV(nil), u.Statuses...)
	n.Cooldowns = append([]KV(nil), u.Cooldowns...)
	n.Charges = append([]KV(nil), u.Charges...)
	return &n
}

func kvSet(list []KV, key string, val int) []KV {
	for i := range list {
		if list[i].Key == key {
			list[i].Val = val
			return list
		}
	}
	return append(list, KV{key, val})
}

func kvErase(list []KV, key string) []KV {
	for i := range list {
		if list[i].Key == key {
			copy(list[i:], list[i+1:])
			return list[:len(list)-1]
		}
	}
	return list
}

// Index 是单位在 BattleState.Units 里的下标（副本之间保持一致，可用作缓存键）。
func (u *UnitState) Index() int { return u.index }

// Names 按固定顺序列出单位带有的全部特性名。
func (t *Traits) Names() []string {
	var out []string
	for _, k := range [...]string{"physical_immune", "block", "forest_stride", "flying", "cannot_attack_adjacent",
		"hunter_mark", "iron_arm", "shield_wall", "intercept", "patience", "skirmish", "undead", "marsh_stride"} {
		if t.Has(k) {
			out = append(out, k)
		}
	}
	return append(out, t.Other...)
}

// CanUndoMove 表示这个单位本回合的移动还能撤销。
func (u *UnitState) CanUndoMove() bool { return u.undoOK }

// dropSkill 把一个招式（用完的物品）从招式表里拿掉。
func (u *UnitState) dropSkill(id string) {
	kept := make([]*Skill, 0, len(u.Skills))
	for _, sk := range u.Skills {
		if sk.ID != id {
			kept = append(kept, sk)
		}
	}
	u.Skills = kept
}

// TreeKey 返回这个单位的技能树在 skill_tree.json 里的名字。
func (u *UnitState) TreeKey() string {
	if u.Tree != "" {
		return u.Tree
	}
	return u.DefID
}
