// Package rules 是战棋战斗规则的唯一实现：状态、地形、移动、伤害、效果、行动校验与执行、
// 回合流程、敌方 AI、洞穴机制和数据表加载。数值与流程遵循 07-combat-rules.md。
//
// 与原 GDScript 引擎逐位对齐：同一场战斗、同一个种子，结果完全相同（见 testdata/parity）。
// 包内没有全局可变状态；一场战斗的 BattleState（及其副本）只能在一个 goroutine 里使用，
// Data 加载后只读，可以被多个 goroutine 共享。
package rules

import "math"

// Cell 是格子坐标（x 向东，y 向南）。
type Cell struct{ X, Y int }

func (c Cell) Add(o Cell) Cell { return Cell{c.X + o.X, c.Y + o.Y} }
func (c Cell) Sub(o Cell) Cell { return Cell{c.X - o.X, c.Y - o.Y} }

type Team int8

const (
	TeamPlayer Team = iota
	TeamEnemy
	TeamNeutral
	TeamAny Team = -1 // Living 的“不限阵营”
)

type Terrain uint8

const (
	Plain Terrain = iota
	Forest
	Shallow
	Deep
	Swamp
	Burning
	Styx
)

type DamageType int8

const (
	Physical DamageType = iota
	Divine
	True
)

type Relation int

const (
	Front Relation = iota
	Side
	Back
)

type Phase int8

const (
	PhasePlayer Phase = iota
	PhaseEnemy
)

var (
	North = Cell{0, -1}
	East  = Cell{1, 0}
	South = Cell{0, 1}
	West  = Cell{-1, 0}
	Dirs  = [4]Cell{North, East, South, West}
	// NoPos 表示“没有坐标”（例如技能没有指定落点）。
	NoPos = Cell{-99999, -99999}
)

const (
	MaxHeight      = 5
	MaxDrop        = 2
	LOSBlockLevels = 2 // 比射手和目标都高出这么多层的格子才挡视线

	SideMult             = 1.25
	BackMult             = 1.5
	HighGroundMult       = 1.2
	HighGroundRangeLevel = 2
	CoverMult            = 0.75
	BlockMult            = 0.5
	GuardMult            = 0.7
	MarkMult             = 1.15
	MarkRangeBonus       = 2
	FlankMult            = 1.1
	BrokenMult           = 1.25
	AssistMult           = 0.3
	PatienceMult         = 1.25
	IronArmThrow         = 3 // 铁臂：过肩摔落地时追加的真实伤害
	ShieldWallMult       = 0.85
	SkirmishMove         = 2

	FallDamagePerLevel = 3
	CollisionDamage    = 3
	EdgeDamage         = 10
	BurnDamage         = 2
	PoisonDamage       = 2
	StyxDamage         = 3

	StaggerBack         = 20
	StaggerSide         = 10
	StaggerKnockback    = 15
	StaggerFallPerLevel = 5
	StaggerFist         = 8 // 破势之拳：击退或摔出时追加的破势

	Epsilon = 0.000001
)

// 首领“霸体”无视的控制状态（破势期间除外）。
func isControlStatus(s string) bool {
	return s == "stunned" || s == "rooted"
}

func terrainCost(t Terrain, forestStride bool) int {
	switch t {
	case Forest:
		if forestStride {
			return 1
		}
		return 2
	case Shallow:
		return 2
	case Swamp:
		return 3
	case Deep:
		return -1
	}
	return 1
}

// FloorInt 向下取整，带一个极小的容差（与原版 Defs.floor_int 相同）。
func FloorInt(v float64) int {
	return int(math.Floor(v + Epsilon))
}

func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
