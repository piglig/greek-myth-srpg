package sim

import (
	"encoding/json"
	"fmt"

	"srpg/rules"
)

// 静态伤害矩阵：用真实规则（rules.Compute）算出每个 攻击者 × 技能 × 目标 × 情形 的一击伤害，
// 供平衡规格检查使用。不模拟战斗：一击、平地、没有标记和包夹。

// Metrics 是导出的伤害矩阵。
type Metrics struct {
	Hits  []MetricHit           `json:"hits"`
	Units map[string]MetricUnit `json:"units"`
}

type MetricHit struct {
	Attacker string `json:"attacker"`
	Damage   int    `json:"damage"`
	Immune   bool   `json:"immune"`
	Relation int    `json:"relation"`
	Scenario string `json:"scenario"`
	Skill    string `json:"skill"`
	Target   string `json:"target"`
}

type MetricUnit struct {
	HP    int `json:"hp"`
	MaxHP int `json:"max_hp"`
	Size  int `json:"size"`
}

// JSON 返回带缩进的 JSON。
func (m *Metrics) JSON() ([]byte, error) { return json.MarshalIndent(m, "", "  ") }

// 情形：攻击者站在目标正西，目标的朝向决定正面 / 侧面 / 背面；broken_side 是侧面加破势。
var scenarios = []struct {
	name   string
	facing rules.Cell
	broken bool
}{
	{"front", rules.Cell{X: -1, Y: 0}, false},
	{"side", rules.Cell{X: 0, Y: -1}, false},
	{"back", rules.Cell{X: 1, Y: 0}, false},
	{"broken_side", rules.Cell{X: 0, Y: -1}, true},
}

// ExportMetrics 计算伤害矩阵。
func ExportMetrics(data *rules.Data) (*Metrics, error) {
	out := &Metrics{Hits: []MetricHit{}, Units: map[string]MetricUnit{}}
	for _, atk := range data.UnitIDs {
		for _, sk := range usableSkills(data, atk) {
			for _, tgt := range data.UnitIDs {
				for _, scen := range scenarios {
					// 目标锚在 (4, 1)；攻击者紧贴它的西侧，无论体型多大
					s := rules.NewBattleState(rules.NewGrid(8, 5, 0))
					a, err := data.MakeUnit(atk, "a", rules.TeamPlayer, rules.Cell{}, rules.East)
					if err != nil {
						return nil, err
					}
					a.Pos = rules.Cell{X: 4 - a.Size, Y: 1}
					s.AddUnit(a)
					t, err := data.MakeUnit(tgt, "t", rules.TeamEnemy, rules.Cell{X: 4, Y: 1}, scen.facing)
					if err != nil {
						return nil, err
					}
					s.AddUnit(t)
					if rules.Distance(a, t) != 1 {
						return nil, fmt.Errorf("伤害矩阵的两个单位必须相邻（%s 对 %s）", atk, tgt)
					}
					if scen.broken {
						t.SetStatus("staggered", 2)
					}
					hit := rules.Compute(s, a, t, sk.Mult, sk.Type, sk.Ranged, rules.NoPos)
					out.Hits = append(out.Hits, MetricHit{Attacker: atk, Skill: sk.ID, Target: tgt, Scenario: scen.name,
						Damage: hit.Amount, Immune: hit.Immune, Relation: int(hit.Relation)})
				}
			}
		}
	}
	for _, id := range data.UnitIDs {
		def := data.UnitDef(id)
		out.Units[id] = MetricUnit{HP: def.HP, MaxHP: def.MaxHP, Size: def.Size}
	}
	return out, nil
}

// 基础技能，加上这个单位能从技能树学到的每个技能；不造成伤害的范围控制技能（咆哮）不列。
func usableSkills(data *rules.Data, defID string) []*rules.Skill {
	var out []*rules.Skill
	add := func(id string) {
		sk := data.Skill(id)
		if sk == nil || !sk.HasMult {
			return
		}
		for _, o := range out {
			if o == sk {
				return
			}
		}
		out = append(out, sk)
	}
	for _, id := range data.UnitDef(defID).Skills {
		add(id)
	}
	for _, br := range data.Trees(defID) {
		for _, n := range br.Nodes {
			if n.Skill != "" {
				add(n.Skill)
			}
		}
	}
	return out
}
