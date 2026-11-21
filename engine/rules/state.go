package rules

import "encoding/binary"

// Entrance 是洞穴的一个入口。
type Entrance struct {
	ID     string
	Anchor Cell
	Sealed bool
}

// Boulder 是入口旁的巨石；推到位（Placed）后封住 Seals 指向的入口。
type Boulder struct {
	ID       string
	Pos      Cell
	Seals    string
	Progress int
	Placed   bool
}

// Cave 是首领巢穴的状态（09-chapter-1 的 1-5）。没有洞穴的战斗里 BattleState.Cave 为 nil。
type Cave struct {
	Boss          string
	TriggerHP     int
	EmergeActions int
	Last          string // "" | "retreat" | "emerge"
	Entrances     []Entrance
	Boulders      []Boulder
}

func (c *Cave) Entrance(id string) *Entrance {
	for i := range c.Entrances {
		if c.Entrances[i].ID == id {
			return &c.Entrances[i]
		}
	}
	return nil
}

func (c *Cave) Boulder(id string) *Boulder {
	for i := range c.Boulders {
		if c.Boulders[i].ID == id {
			return &c.Boulders[i]
		}
	}
	return nil
}

func (c *Cave) copy() *Cave {
	if c == nil {
		return nil
	}
	n := *c
	n.Entrances = append([]Entrance(nil), c.Entrances...)
	n.Boulders = append([]Boulder(nil), c.Boulders...)
	return &n
}

// BattleState 是整场战斗的状态。规则修改它；表现层只读。
type BattleState struct {
	Grid         *Grid
	Units        []*UnitState // 加入顺序，也是所有平局判定的顺序
	Round        int
	Phase        Phase
	MarkedID     string
	PreviousMark string
	Reward       ChapterReward
	EscortExits  []Cell
	RescueExits  []Cell   // Immutable evacuation zone.
	Village      *Village // Read-only scenario data.
	Cave         *Cave

	mc *moveCache // 移动范围缓存，同一场战斗的副本共用

	// CopyInto 复用的内存：单位本体和状态 / 冷却表
	slab []UnitState
	kvs  []KV
}

func NewBattleState(g *Grid) *BattleState {
	return &BattleState{Grid: g, Round: 1, Phase: PhasePlayer}
}

// AddUnit 把单位加入战斗；id 不能重复。
func (s *BattleState) AddUnit(u *UnitState) *UnitState {
	if s.Unit(u.ID) != nil {
		panic("duplicate unit id " + u.ID)
	}
	u.index = len(s.Units)
	s.Units = append(s.Units, u)
	return u
}

func (s *BattleState) Unit(id string) *UnitState {
	for _, u := range s.Units {
		if u.ID == id {
			return u
		}
	}
	return nil
}

// UnitAt 返回站在格子上的单位（倒下的和隐藏的不算）。
func (s *BattleState) UnitAt(c Cell) *UnitState {
	for _, u := range s.Units {
		if u.Alive && !u.Hidden && u.Occupies(c) {
			return u
		}
	}
	return nil
}

// Living 返回还活着的单位（team 传 TeamAny 表示不限阵营）。返回的是当时的快照。
func (s *BattleState) Living(team Team) []*UnitState {
	out := make([]*UnitState, 0, len(s.Units))
	for _, u := range s.Units {
		if u.Alive && (team == TeamAny || u.Team == team) {
			out = append(out, u)
		}
	}
	return out
}

// BoulderAt 返回立在格子上的巨石 id（没有则为 ""）。巨石像墙一样挡路。
func (s *BattleState) BoulderAt(c Cell) string {
	if s.Cave == nil {
		return ""
	}
	for i := range s.Cave.Boulders {
		b := &s.Cave.Boulders[i]
		if !b.Placed && b.Pos == c {
			return b.ID
		}
	}
	return ""
}

func (s *BattleState) BoulderIn(anchor Cell, size int) bool {
	if s.Cave == nil {
		return false
	}
	for i := range s.Cave.Boulders {
		b := &s.Cave.Boulders[i]
		if !b.Placed && b.Pos.X >= anchor.X && b.Pos.Y >= anchor.Y &&
			b.Pos.X < anchor.X+size && b.Pos.Y < anchor.Y+size {
			return true
		}
	}
	return false
}

// OpenEntrances 列出还没封住的入口 id。
func (s *BattleState) OpenEntrances() []string {
	var out []string
	if s.Cave != nil {
		for i := range s.Cave.Entrances {
			if !s.Cave.Entrances[i].Sealed {
				out = append(out, s.Cave.Entrances[i].ID)
			}
		}
	}
	return out
}

func (s *BattleState) openEntranceCount() int {
	n := 0
	if s.Cave != nil {
		for i := range s.Cave.Entrances {
			if !s.Cave.Entrances[i].Sealed {
				n++
			}
		}
	}
	return n
}

func (s *BattleState) entranceOpen(id string) bool {
	if s.Cave == nil {
		return false
	}
	e := s.Cave.Entrance(id)
	return e != nil && !e.Sealed
}

// StandingHeight 是占地的站立高度：脚下最高的那一格。
func (s *BattleState) StandingHeight(anchor Cell, size int) int {
	g := s.Grid
	if size == 1 {
		return int(g.heights[anchor.Y*g.Width+anchor.X])
	}
	h := 0
	for dy := 0; dy < size; dy++ {
		row := (anchor.Y+dy)*g.Width + anchor.X
		for dx := 0; dx < size; dx++ {
			if v := int(g.heights[row+dx]); v > h {
				h = v
			}
		}
	}
	return h
}

func (s *BattleState) UnitHeight(u *UnitState) int {
	return s.StandingHeight(u.Pos, u.Size)
}

func (s *BattleState) FootprintInBounds(anchor Cell, size int) bool {
	return anchor.X >= 0 && anchor.Y >= 0 && anchor.X+size <= s.Grid.Width && anchor.Y+size <= s.Grid.Depth
}

// Blockers 返回与占地重叠的其他在场单位（按格子先行后列的发现顺序）。
func (s *BattleState) Blockers(anchor Cell, size int, ignore *UnitState) []*UnitState {
	var out []*UnitState
	for dy := 0; dy < size; dy++ {
		for dx := 0; dx < size; dx++ {
			other := s.UnitAt(Cell{anchor.X + dx, anchor.Y + dy})
			if other == nil || other == ignore {
				continue
			}
			seen := false
			for _, o := range out {
				if o == other {
					seen = true
					break
				}
			}
			if !seen {
				out = append(out, other)
			}
		}
	}
	return out
}

// firstBlocker 等于 Blockers(...)[0]（没有则为 nil），不分配内存。
func (s *BattleState) firstBlocker(anchor Cell, size int, ignore *UnitState) *UnitState {
	for dy := 0; dy < size; dy++ {
		for dx := 0; dx < size; dx++ {
			other := s.UnitAt(Cell{anchor.X + dx, anchor.Y + dy})
			if other != nil && other != ignore {
				return other
			}
		}
	}
	return nil
}

// AppendSignature 把“区分同一场战斗两个局面的全部信息”编码追加到 buf。
// 两个搜索分支的签名相同，就是同一个局面（机器人用它合并重复的搜索）。
// 状态和冷却按顺序编码：顺序不同算不同局面，与原版 str(字典) 的比较方式一致。
func (s *BattleState) AppendSignature(buf []byte) []byte {
	buf = append(buf, byte(s.Phase))
	buf = binary.AppendVarint(buf, int64(s.Round))
	buf = appendStr(buf, s.MarkedID)
	buf = appendStr(buf, s.PreviousMark)
	buf = appendStr(buf, s.Reward.Boon)
	buf = appendStr(buf, s.Reward.EquippedRelic)
	buf = binary.AppendVarint(buf, int64(s.Reward.Divinity))
	for _, u := range s.Units {
		if u.DefID == "centaur" {
			buf = append(buf, byte(u.chargeDir.X+1), byte(u.chargeDir.Y+1))
		}
		if s.Village != nil || len(s.RescueExits) > 0 {
			buf = binary.AppendVarint(buf, int64(u.Arrival))
		}
		buf = binary.AppendVarint(buf, int64(u.Pos.X))
		buf = binary.AppendVarint(buf, int64(u.Pos.Y))
		buf = binary.AppendVarint(buf, int64(u.HP))
		buf = append(buf, flags(u.Alive, u.Hidden, u.HasMoved, u.HasActed, u.MarkUsed, u.AssistUsed, u.InterceptUsed),
			byte(u.Facing.X+1), byte(u.Facing.Y+1))
		buf = binary.AppendVarint(buf, int64(u.ActionsLeft))
		buf = binary.AppendVarint(buf, int64(u.Stagger))
		buf = binary.AppendVarint(buf, int64(u.Escape))
		buf = appendStr(buf, u.GrapplingID)
		buf = appendStr(buf, u.GrappledByID)
		buf = binary.AppendVarint(buf, int64(u.Shield))
		buf = binary.AppendVarint(buf, int64(u.PostMove))
		buf = appendKVs(buf, u.Statuses)
		buf = appendKVs(buf, u.Cooldowns)
	}
	if c := s.Cave; c != nil {
		buf = appendStr(buf, c.Last)
		for i := range c.Entrances {
			buf = append(buf, flags(c.Entrances[i].Sealed))
		}
		for i := range c.Boulders {
			buf = append(buf, flags(c.Boulders[i].Placed))
			buf = binary.AppendVarint(buf, int64(c.Boulders[i].Progress))
		}
	}
	return buf
}

func flags(bs ...bool) byte {
	var f byte
	for i, b := range bs {
		if b {
			f |= 1 << i
		}
	}
	return f
}

func appendStr(buf []byte, s string) []byte {
	buf = binary.AppendUvarint(buf, uint64(len(s)))
	return append(buf, s...)
}

func appendKVs(buf []byte, list []KV) []byte {
	buf = append(buf, byte(len(list)))
	for _, kv := range list {
		buf = appendStr(buf, kv.Key)
		buf = binary.AppendVarint(buf, int64(kv.Val))
	}
	return buf
}

// Copy 复制单位和洞穴状态；地图共用，因为规则在战斗中不会改它。
// 要改地形（例如桥的状态切换）必须把 Grid 换成改过的副本。
func (s *BattleState) Copy() *BattleState {
	return s.CopyInto(nil)
}

// CopyInto 把 s 复制进 dst 并返回 dst，尽量复用 dst 已有的内存（搜索时反复复制局面用）。
// dst 原来的内容全部作废；dst 为 nil 时新建一个。
func (s *BattleState) CopyInto(dst *BattleState) *BattleState {
	n := len(s.Units)
	if dst == nil {
		dst = &BattleState{}
	}
	dst.Reward, dst.PreviousMark = s.Reward, s.PreviousMark
	dst.Village = s.Village
	dst.RescueExits = s.RescueExits
	dst.EscortExits = s.EscortExits
	dst.Grid, dst.Round, dst.Phase, dst.MarkedID, dst.mc = s.Grid, s.Round, s.Phase, s.MarkedID, s.mc
	if cap(dst.slab) < n {
		dst.slab = make([]UnitState, n)
		dst.Units = make([]*UnitState, n)
		for i := range dst.slab {
			dst.Units[i] = &dst.slab[i]
		}
	}
	dst.slab = dst.slab[:n]
	dst.Units = dst.Units[:n]
	total := 0
	for _, u := range s.Units {
		total += len(u.Statuses) + len(u.Cooldowns)
	}
	if cap(dst.kvs) < total {
		dst.kvs = make([]KV, total)
	}
	kvs := dst.kvs[:total]
	for i, u := range s.Units {
		c := &dst.slab[i]
		*c = *u
		c.Skills = u.Skills[:len(u.Skills):len(u.Skills)]
		// 容量卡死在长度上：副本追加状态时会另行分配，互不影响
		ns := copy(kvs, u.Statuses)
		c.Statuses = kvs[:ns:ns]
		kvs = kvs[ns:]
		nc := copy(kvs, u.Cooldowns)
		c.Cooldowns = kvs[:nc:nc]
		kvs = kvs[nc:]
	}
	if s.Cave == nil {
		dst.Cave = nil
	} else {
		if dst.Cave == nil {
			dst.Cave = &Cave{}
		}
		entrances, boulders := dst.Cave.Entrances[:0], dst.Cave.Boulders[:0]
		*dst.Cave = *s.Cave
		dst.Cave.Entrances = append(entrances, s.Cave.Entrances...)
		dst.Cave.Boulders = append(boulders, s.Cave.Boulders...)
	}
	return dst
}
