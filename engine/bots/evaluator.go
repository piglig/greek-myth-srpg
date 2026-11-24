// Package bots 是平衡模拟用的我方机器人（11-balance-testing §4）：局面评估和回合搜索。
//
// 与原 GDScript 版逐位对齐：评估的先后顺序、缓存何时填充、排序的平局次序都照搬，
// 因为威胁范围缓存是“谁先问就按谁的局面算”，顺序一变结果就会变。
// 一个 Bot 只服务一场战斗，不能跨 goroutine 共用。
package bots

import (
	"srpg/rules"
)

// Weights 是局面评估各项的权重。
type Weights struct {
	EnemyHP  float64 // 敌人损失的生命（按敌人的强度缩放）
	EnemyKO  float64 // 击倒敌人
	Stagger  float64 // 首领破势进度
	PlayerHP float64 // 我方保住的生命
	PlayerKO float64 // 我方单位倒下
	HeroKO   float64 // 主角倒下（代价大得多）
	Danger   float64 // 危险度：威胁范围罩住我方的敌人的预期伤害
	Distance float64 // 向最近的敌人靠拢的一点引力，免得机器人不接战
	Seal     float64 // 封住洞穴入口
}

// DefaultWeights 返回默认权重。
func DefaultWeights() Weights {
	return Weights{EnemyHP: 10, EnemyKO: 8, Stagger: 6, PlayerHP: 6, PlayerKO: 25,
		HeroKO: 100, Danger: 5, Distance: 0.15, Seal: 4}
}

// Evaluator 从我方角度给局面打分，越高越好。
// 局面的价值 = Material + Positional：
//
//	Material   —— 谁受伤、倒下、破势：只有执行规则时才会变
//	Positional —— 危险度和接近距离：我方单位换个位置站时唯一会变的部分，
//	              所以比较候选落点时不必重算其余部分
type Evaluator struct {
	W Weights

	// threat[敌人下标][格子下标]：敌人站在那里时下回合能打到的格子（位图）。每个我方回合开始时清空。
	threat [][][]uint64
	filled []threatSlot // 这个回合填过的位置，清空时只动它们
	masks  [][]uint64   // 用过的位图，留着复用
	// 敌人对我方单位最强一击的预期伤害（-1 表示还没算）。属性在一个回合内不会变。
	hit [][]float64

	players, enemies []*rules.UnitState
	incoming         []float64
	reachable        []int
}

type threatSlot struct{ unit, cell int }

func NewEvaluator(w Weights) *Evaluator {
	return &Evaluator{W: w}
}

// BeginTurn 清空缓存；每个我方回合开始时调用。
func (ev *Evaluator) BeginTurn() {
	for _, f := range ev.filled {
		ev.masks = append(ev.masks, ev.threat[f.unit][f.cell])
		ev.threat[f.unit][f.cell] = nil
	}
	ev.filled = ev.filled[:0]
	for i := range ev.hit {
		for j := range ev.hit[i] {
			ev.hit[i][j] = -1
		}
	}
}

func (ev *Evaluator) Score(s *rules.BattleState) float64 {
	m := ev.Material(s)
	return m + ev.Positional(s)
}

func (ev *Evaluator) Material(s *rules.BattleState) float64 {
	w := &ev.W
	v := 0.0
	for _, u := range s.Units {
		switch u.Team {
		case rules.TeamEnemy:
			toughness := float64(u.MaxHP) / 20.0
			v += w.EnemyHP * toughness * float64(u.MaxHP-max(u.HP, 0)) / float64(u.MaxHP)
			if !u.Alive {
				v += float64(w.EnemyKO * toughness)
				continue
			}
			if u.IsBoss() {
				progress := 1.0
				if !u.HasStatus("staggered") {
					progress = float64(u.Stagger) / float64(u.StaggerMax)
				}
				v += float64(w.Stagger * progress)
			}
		case rules.TeamPlayer:
			if !u.Alive {
				if u.ID == "hero" {
					v -= w.HeroKO
				} else {
					v -= w.PlayerKO
				}
				continue
			}
			v += w.PlayerHP * float64(u.HP) / float64(u.MaxHP)
		}
	}
	// 封住一个入口会让首领的行动可以预判：本身就值一点分
	if s.Cave != nil {
		for i := range s.Cave.Boulders {
			b := &s.Cave.Boulders[i]
			part := 1.0
			if !b.Placed {
				part = float64(0.4 * float64(b.Progress))
			}
			v += float64(w.Seal * part)
		}
	}
	return v
}

func (ev *Evaluator) Positional(s *rules.BattleState) float64 {
	players, enemies := ev.players[:0], ev.enemies[:0]
	for _, u := range s.Units {
		if !u.Alive || u.Hidden {
			continue
		}
		if u.Team == rules.TeamPlayer {
			players = append(players, u)
		} else if u.Team == rules.TeamEnemy {
			enemies = append(enemies, u)
		}
	}
	ev.players, ev.enemies = players, enemies
	if len(enemies) == 0 {
		return 0
	}
	v := 0.0
	for _, p := range players {
		near := 99
		for _, e := range enemies {
			near = min(near, rules.Distance(p, e))
		}
		v -= float64(ev.W.Distance * float64(min(near, 12)))
	}
	return v - float64(ev.W.Danger*ev.danger(s, players, enemies))
}

// 我方每个单位的（预期承受伤害 / 当前生命）之和，每个单位封顶。
// 每个敌人把威胁平均摊给它下回合够得着的单位。
func (ev *Evaluator) danger(s *rules.BattleState, players, enemies []*rules.UnitState) float64 {
	incoming := ev.incoming[:0]
	for range players {
		incoming = append(incoming, 0)
	}
	ev.incoming = incoming
	w := s.Grid.Width
	for _, e := range enemies {
		if e.HasStatus("stunned") {
			continue
		}
		cells := ev.threatOf(s, e)
		reachable := ev.reachable[:0]
		for i, p := range players {
			covered := false
			for dy := 0; dy < p.Size && !covered; dy++ {
				for dx := 0; dx < p.Size; dx++ {
					ci := (p.Pos.Y+dy)*w + p.Pos.X + dx
					if cells[ci>>6]&(1<<(ci&63)) != 0 {
						covered = true
						break
					}
				}
			}
			if covered {
				reachable = append(reachable, i)
			}
		}
		ev.reachable = reachable
		for _, i := range reachable {
			incoming[i] += float64(ev.expectedHit(s, e, players[i])*float64(e.ActionsPerTurn)) / float64(len(reachable))
		}
	}
	total := 0.0
	for i, p := range players {
		total += min(incoming[i]/float64(max(p.HP, 1)), 1.5)
	}
	return total
}

func (ev *Evaluator) expectedHit(s *rules.BattleState, e, p *rules.UnitState) float64 {
	n := len(s.Units)
	if len(ev.hit) != n {
		ev.hit = make([][]float64, n)
		for i := range ev.hit {
			row := make([]float64, n)
			for j := range row {
				row[j] = -1
			}
			ev.hit[i] = row
		}
	}
	hit := ev.hit[e.Index()][p.Index()]
	if hit < 0 {
		best := 0.0
		for _, sk := range e.Skills {
			if !sk.HasMult {
				continue
			}
			raw := rules.FloorInt(float64(float64(e.Strength) * sk.Mult))
			dmg := raw
			if sk.Type == rules.Physical {
				dmg = max(1, raw-p.Defense)
			} else if sk.Type == rules.Divine {
				dmg = max(1, rules.FloorInt(float64(float64(e.Divinity)*sk.Mult))-p.Will)
			}
			best = max(best, float64(dmg))
		}
		hit = best
		ev.hit[e.Index()][p.Index()] = hit
	}
	return hit
}

func (ev *Evaluator) threatOf(s *rules.BattleState, e *rules.UnitState) []uint64 {
	n := s.Grid.Width * s.Grid.Depth
	if len(ev.threat) != len(s.Units) || len(ev.threat[0]) != n {
		ev.threat = make([][][]uint64, len(s.Units))
		for i := range ev.threat {
			ev.threat[i] = make([][]uint64, n)
		}
		ev.filled, ev.masks = ev.filled[:0], nil
	}
	ci := e.Pos.Y*s.Grid.Width + e.Pos.X
	cells := ev.threat[e.Index()][ci]
	if cells == nil {
		var buf []uint64
		if k := len(ev.masks); k > 0 {
			buf, ev.masks = ev.masks[k-1], ev.masks[:k-1]
		}
		cells = rules.ThreatMask(s, e, buf)
		ev.threat[e.Index()][ci] = cells
		ev.filled = append(ev.filled, threatSlot{e.Index(), ci})
	}
	return cells
}
