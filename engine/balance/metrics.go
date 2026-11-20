package balance

import (
	"fmt"
	"math"
	"os"
	"strings"

	oj "srpg/balance/ordjson"
)

// 静态平衡指标：由引擎导出的伤害矩阵（balance/out/metrics.json）推出"几下打死"。

// Hit 是（攻击者, 技能, 目标, 场景）的一次命中。
type Hit struct {
	Attacker, Skill, Target, Scenario string
	Damage                            float64
	TargetHP, TargetMaxHP             float64
	HitsToKill                        float64 // 伤害为 0 时是 +Inf
	HPFraction                        float64
	Raw                               *oj.Object
}

// HitsFrame 由 metrics.json 的内容生成命中表。
func HitsFrame(metrics *oj.Object) []Hit {
	units := metrics.Object("units")
	var out []Hit
	for _, v := range metrics.Array("hits") {
		o, ok := v.(*oj.Object)
		if !ok {
			continue
		}
		h := Hit{Attacker: o.Str("attacker", ""), Skill: o.Str("skill", ""), Target: o.Str("target", ""),
			Scenario: o.Str("scenario", ""), Damage: o.Float("damage", 0), Raw: o}
		u := units.Object(h.Target)
		h.TargetHP, h.TargetMaxHP = u.Float("hp", math.NaN()), u.Float("max_hp", math.NaN())
		h.HitsToKill = math.Inf(1)
		if h.Damage > 0 {
			h.HitsToKill = math.Ceil(h.TargetHP / h.Damage)
		}
		h.HPFraction = h.Damage / h.TargetMaxHP
		out = append(out, h)
	}
	return out
}

// LoadMetrics 读 metrics.json。
func LoadMetrics(path string) (*oj.Object, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("读不到 %s（静态伤害矩阵，需要由引擎导出）：%w", path, err)
	}
	return oj.ParseObject(data)
}

// Lookup 找一条命中记录。
func Lookup(hits []Hit, attacker, skill, target, scenario string) (Hit, error) {
	for _, h := range hits {
		if h.Attacker == attacker && h.Skill == skill && h.Target == target && h.Scenario == scenario {
			return h, nil
		}
	}
	return Hit{}, fmt.Errorf("no metric for %s:%s -> %s (%s)", attacker, skill, target, scenario)
}

// BestHit 是攻击者对目标在某场景下的最高单次伤害（没有记录时为 0）。
func BestHit(hits []Hit, attacker, target, scenario string) int {
	best := 0.0
	for _, h := range hits {
		if h.Attacker == attacker && h.Target == target && h.Scenario == scenario {
			best = math.Max(best, h.Damage)
		}
	}
	return int(best)
}

// TTKTable 是"几下打死"矩阵：行是 "攻击者:技能"，列是目标。attackers 里可以写 "单位" 或 "单位:技能"。
func TTKTable(hits []Hit, attackers, targets []string, scenario string) (rows []string, table map[string]map[string]float64) {
	in := func(list []string, s string) bool {
		for _, x := range list {
			if x == s {
				return true
			}
		}
		return false
	}
	table = map[string]map[string]float64{}
	for _, h := range hits {
		key := h.Attacker + ":" + h.Skill
		if h.Scenario != scenario || !in(targets, h.Target) || !(in(attackers, key) || in(attackers, h.Attacker)) {
			continue
		}
		if table[key] == nil {
			table[key] = map[string]float64{}
			rows = append(rows, key)
		}
		if _, ok := table[key][h.Target]; !ok {
			table[key][h.Target] = h.HitsToKill
		}
	}
	return rows, table
}

// HitsCSV 输出和 pandas 的 to_csv 相同列的 CSV（带 BOM，供表格软件打开）。
func HitsCSV(hits []Hit) string {
	var b strings.Builder
	b.Write([]byte{0xef, 0xbb, 0xbf}) // UTF-8 BOM
	var cols []string
	if len(hits) > 0 {
		cols = hits[0].Raw.Keys()
	}
	b.WriteString(strings.Join(append(append([]string{}, cols...), "target_hp", "target_max_hp", "hits_to_kill", "hp_fraction"), ",") + "\n")
	for _, h := range hits {
		cells := make([]string, 0, len(cols)+4)
		for _, c := range cols {
			switch v := h.Raw.Get(c).(type) {
			case string:
				cells = append(cells, v)
			default:
				cells = append(cells, oj.PyRepr(v))
			}
		}
		cells = append(cells, csvNum(h.TargetHP), csvNum(h.TargetMaxHP), oj.PyFloat(h.HitsToKill), oj.PyFloat(h.HPFraction))
		b.WriteString(strings.Join(cells, ",") + "\n")
	}
	return b.String()
}

func csvNum(f float64) string {
	if f == math.Trunc(f) && !math.IsInf(f, 0) {
		return fmt.Sprintf("%d", int64(f))
	}
	return oj.PyFloat(f)
}
