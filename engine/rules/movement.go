package rules

import (
	"encoding/binary"
	"slices"
)

// 可达范围与路径（07-combat-rules §5.1）。消耗 = 地形消耗 + 每爬一层 1 点。

// Reach 是一个单位本回合能经过的全部锚点。
// “能经过”不等于“能停下”：同伴所在的格子可以穿过，不能共用。
// Reach 会被缓存并共用，只读。
type Reach struct {
	w, d  int
	start Cell
	cells []reachCell // 按格子下标
	dests []Cell      // 能停下的锚点，先行后列
}

type reachCell struct {
	cost int16 // 到这个锚点的消耗，-1 表示到不了
	from uint8 // 最短路上的前一个锚点在哪个方向（Dirs 的下标）；起点为 fromStart
	stop bool  // 能否停在这里
}

const fromStart = 4

func (r *Reach) idx(c Cell) int {
	if c.X < 0 || c.Y < 0 || c.X >= r.w || c.Y >= r.d {
		return -1
	}
	return c.Y*r.w + c.X
}

// Has 判断锚点是否在可经过的范围内。
func (r *Reach) Has(c Cell) bool {
	i := r.idx(c)
	return i >= 0 && r.cells[i].cost >= 0
}

// CanStop 判断移动能否以这个锚点结束（包含起点）。
func (r *Reach) CanStop(c Cell) bool {
	i := r.idx(c)
	return i >= 0 && r.cells[i].cost >= 0 && r.cells[i].stop
}

// Cost 返回走到锚点的消耗（到不了为 -1）。
func (r *Reach) Cost(c Cell) int {
	i := r.idx(c)
	if i < 0 {
		return -1
	}
	return int(r.cells[i].cost)
}

// Dests 返回所有能停下的锚点，先行后列。不要修改返回的切片。
func (r *Reach) Dests() []Cell { return r.dests }

// Cells 返回所有能经过的锚点，先行后列。
func (r *Reach) Cells() []Cell {
	var out []Cell
	for i := range r.cells {
		if r.cells[i].cost >= 0 {
			out = append(out, Cell{i % r.w, i / r.w})
		}
	}
	return out
}

// 最短路上 c 的前一个锚点。
func (r *Reach) prev(c Cell) Cell {
	return c.Sub(Dirs[r.cells[c.Y*r.w+c.X].from])
}

// PathTo 返回从起点走到 dest 的每一步（不含起点）；到不了则为空。
func (r *Reach) PathTo(dest Cell) []Cell {
	if !r.Has(dest) {
		return nil
	}
	n := 0
	for cur := dest; cur != r.start; cur = r.prev(cur) {
		n++
	}
	path := make([]Cell, n)
	for cur := dest; cur != r.start; cur = r.prev(cur) {
		n--
		path[n] = cur
	}
	return path
}

// LastStep 返回走到 dest 的最后一步的方向；dest 就是起点或到不了时 ok 为假。
func (r *Reach) LastStep(dest Cell) (dir Cell, ok bool) {
	if !r.Has(dest) || dest == r.start {
		return Cell{}, false
	}
	return Dirs[r.cells[r.idx(dest)].from], true
}

// moveCache 记住算过的可达范围。结果只取决于地图、谁站在哪、巨石和移动者自身，
// 机器人会从同一个局面评估上百个候选方案，不缓存就要反复重算。
type moveCache struct {
	grid    *Grid
	version int
	m       map[string]*Reach
	key     []byte
	occ     []int8
	buckets [][]int32
}

const moveCacheLimit = 8192

func (s *BattleState) moveCache() *moveCache {
	if s.mc == nil {
		s.mc = &moveCache{m: map[string]*Reach{}}
	}
	mc := s.mc
	if mc.grid != s.Grid || mc.version != s.Grid.version {
		clear(mc.m)
		mc.grid, mc.version = s.Grid, s.Grid.version
	}
	return mc
}

// ClearMoveCache 丢弃移动缓存（开战时调用）。
func (s *BattleState) ClearMoveCache() {
	s.mc = nil
}

func isLocked(u *UnitState) bool {
	return u.HasStatus("rooted")
}

// Reachable 计算 u 用 budget 点移动力能经过的锚点；budget < 0 表示用单位自己的移动力。
func Reachable(s *BattleState, u *UnitState, budget int) *Reach {
	if budget < 0 {
		budget = u.Move
	}
	mc := s.moveCache()
	key := mc.key[:0]
	key = binary.AppendVarint(key, int64(budget))
	key = append(key, byte(u.index), flags(isLocked(u)))
	key = binary.AppendVarint(key, int64(u.Pos.X))
	key = binary.AppendVarint(key, int64(u.Pos.Y))
	key = binary.AppendVarint(key, int64(u.Move))
	key = binary.AppendVarint(key, int64(u.Jump))
	for _, o := range s.Units {
		if o.Alive && !o.Hidden {
			key = binary.AppendVarint(key, int64(o.Pos.X))
			key = binary.AppendVarint(key, int64(o.Pos.Y))
		} else {
			key = append(key, 0x7f, 0x7f) // 相当于坐标 (-64, -64)，场上的单位不会站在那里
		}
	}
	if s.Cave != nil {
		for i := range s.Cave.Boulders {
			key = append(key, flags(s.Cave.Boulders[i].Placed))
		}
	}
	mc.key = key
	if r, ok := mc.m[string(key)]; ok {
		return r
	}
	if len(mc.m) > moveCacheLimit {
		clear(mc.m)
	}
	r := computeReach(s, u, budget, mc)
	mc.m[string(key)] = r
	return r
}

// StepCost 返回 u 从锚点 a 走到相邻锚点 b 的消耗，走不了返回 -1。
func StepCost(s *BattleState, u *UnitState, a, b Cell) int {
	return stepCost(s, u, a, b, nil)
}

// occ 是可选的占位表（格子下标 → 单位下标 + 1），循环里调用时传入可以省掉逐格查单位。
func stepCost(s *BattleState, u *UnitState, a, b Cell, occ []int8) int {
	if !s.FootprintInBounds(b, u.Size) || s.BoulderIn(b, u.Size) {
		return -1
	}
	g := s.Grid
	flying := u.Aloft()
	cost := 0
	for dy := 0; dy < u.Size; dy++ {
		for dx := 0; dx < u.Size; dx++ {
			c := Cell{b.X + dx, b.Y + dy}
			ci := c.Y*g.Width + c.X
			tc := terrainCost(g.terrain[ci], u.Traits.ForestStride, u.Traits.MarshStride)
			if tc < 0 && !flying {
				return -1
			}
			if flying {
				tc = 1
			}
			cost = max(cost, tc)
			var other *UnitState
			if occ != nil {
				if o := occ[ci]; o > 0 {
					other = s.Units[o-1]
				}
			} else {
				other = s.UnitAt(c)
			}
			if other != nil && other != u && other.Team != u.Team {
				return -1
			}
		}
	}
	if flying {
		return cost
	}
	rise := s.StandingHeight(b, u.Size) - s.StandingHeight(a, u.Size)
	if rise > u.Jump || -rise > MaxDrop {
		return -1
	}
	return cost + max(rise, 0)
}

func computeReach(s *BattleState, u *UnitState, budget int, mc *moveCache) *Reach {
	g := s.Grid
	n := g.Width * g.Depth
	r := &Reach{w: g.Width, d: g.Depth, start: u.Pos, cells: make([]reachCell, n)}
	cells := r.cells
	for i := range cells {
		cells[i].cost = -1
	}
	startIdx := int32(g.index(u.Pos))
	cells[startIdx] = reachCell{cost: 0, from: fromStart, stop: true}
	if isLocked(u) {
		r.dests = []Cell{u.Pos}
		return r
	}

	// 占位表：后加入的单位覆盖先加入的（与原版用字典逐个写入的结果一致）
	if cap(mc.occ) < n {
		mc.occ = make([]int8, n)
	}
	occ := mc.occ[:n]
	clear(occ)
	for i, o := range s.Units {
		if !o.Alive || o.Hidden {
			continue
		}
		for dy := 0; dy < o.Size; dy++ {
			for dx := 0; dx < o.Size; dx++ {
				occ[(o.Pos.Y+dy)*g.Width+o.Pos.X+dx] = int8(i + 1)
			}
		}
	}

	// 桶队列：步进消耗都是小的正整数。每个桶按先行后列处理，消耗相同的路径就有确定的选择；
	// 过期的条目直接跳过。
	buckets := mc.buckets[:0]
	push := func(cost int, idx int32) {
		for len(buckets) <= cost {
			if len(buckets) < cap(buckets) {
				buckets = buckets[:len(buckets)+1]
				buckets[len(buckets)-1] = buckets[len(buckets)-1][:0]
			} else {
				buckets = append(buckets, nil)
			}
		}
		buckets[cost] = append(buckets[cost], idx)
	}
	push(0, startIdx)
	maxCost := min(budget, 999)
	for cost := 0; cost <= maxCost && cost < len(buckets); cost++ {
		bucket := buckets[cost]
		if len(bucket) == 0 {
			continue
		}
		slices.Sort(bucket)
		for _, ci := range bucket {
			if int(cells[ci].cost) != cost {
				continue
			}
			cur := Cell{int(ci) % g.Width, int(ci) / g.Width}
			for di, dir := range Dirs {
				nxt := cur.Add(dir)
				sc := stepCost(s, u, cur, nxt, occ)
				if sc < 0 {
					continue
				}
				nc := cost + sc
				if nc > budget {
					continue
				}
				ni := int32(nxt.Y*g.Width + nxt.X)
				if cells[ni].cost < 0 || nc < int(cells[ni].cost) {
					cells[ni].cost = int16(nc)
					cells[ni].from = uint8(di)
					push(nc, ni)
				}
			}
		}
	}
	mc.buckets = buckets

	count := 0
	for i := range cells {
		if cells[i].cost < 0 {
			continue
		}
		anchor := Cell{i % g.Width, i / g.Width}
		free := true
		if anchor != u.Pos {
		scan:
			for dy := 0; dy < u.Size; dy++ {
				for dx := 0; dx < u.Size; dx++ {
					if o := occ[(anchor.Y+dy)*g.Width+anchor.X+dx]; o != 0 && s.Units[o-1] != u {
						free = false
						break scan
					}
				}
			}
		}
		cells[i].stop = free
		if free {
			count++
		}
	}
	r.dests = make([]Cell, 0, count)
	for i := range cells {
		if cells[i].cost >= 0 && cells[i].stop {
			r.dests = append(r.dests, Cell{i % g.Width, i / g.Width})
		}
	}
	return r
}
