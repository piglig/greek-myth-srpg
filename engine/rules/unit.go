package rules

// KV 是有序小表的一项（状态 → 剩余回合，技能 → 冷却）。保持插入顺序，和原版字典一致。
type KV struct {
	Key string
	Val int
}

// Traits 是单位的特性。规则会查询的特性拆成字段；其余只记名字。
type Traits struct {
	PhysicalImmune, Block, ForestStride, Flying, CannotAttackAdjacent, HunterMark bool
	Slam, IronArm, ShieldWall, Intercept, Patience, Skirmish, Strong, Undead      bool
	HasGrapple                                                                    bool
	Grapple                                                                       int      // 擒抱的窒息伤害
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
	case "flying":
		return &t.Flying
	case "cannot_attack_adjacent":
		return &t.CannotAttackAdjacent
	case "hunter_mark":
		return &t.HunterMark
	case "slam":
		return &t.Slam
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
	case "strong":
		return &t.Strong
	case "undead":
		return &t.Undead
	case "grapple":
		return &t.HasGrapple
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

// Set 加上一个特性；value 只对 grapple 有意义（窒息伤害）。
func (t *Traits) Set(key string, value int) {
	if p := t.flag(key); p != nil {
		*p = true
		if key == "grapple" {
			t.Grapple = value
		}
		return
	}
	if !t.Has(key) {
		t.Other = append(t.Other[:len(t.Other):len(t.Other)], key)
	}
}

// UnitState 是一个单位的运行时状态。纯数据；规则在 rules.go 等文件里。
type UnitState struct {
	ID, DefID, Name string
	Team            Team
	Pos             Cell // 占地的左上角
	Size            int
	Facing          Cell

	MaxHP, HP, Strength, Divinity, Defense, Will, Move, Jump int

	Skills    []*Skill
	Traits    Traits
	Statuses  []KV // 状态 → 剩余回合；staggered / stunned 由破势系统设置
	Shield    int
	Cooldowns []KV

	Stagger    int
	StaggerMax int // > 0 表示带破势条的首领

	ActionsPerTurn, ActionsLeft                             int
	HasMoved, HasActed, AssistUsed, MarkUsed, InterceptUsed bool
	PostMove                                                int // 行动后还能走的步数（游击）

	GrapplingID, GrappledByID string
	Escape                    int

	Alive  bool
	Hidden bool // 不在场上（狮子在洞里）：不能被选中，也不挡路

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
		"hunter_mark", "slam", "iron_arm", "shield_wall", "intercept", "patience", "skirmish", "strong", "undead", "grapple"} {
		if t.Has(k) {
			out = append(out, k)
		}
	}
	return append(out, t.Other...)
}

// CanUndoMove 表示这个单位本回合的移动还能撤销。
func (u *UnitState) CanUndoMove() bool { return u.undoOK }
