package balance

import (
	"context"
	"encoding/json"

	"srpg/rules"
	"srpg/sim"
)

// 真正的战斗引擎（srpg/sim）。现在要加 -tags simengine 才编进来；
// 引擎稳定后：删掉 engine_adapter.go，再去掉本文件第一行的构建标签。

// EngineSimulator 是真正的战斗引擎。
type EngineSimulator struct{}

func (EngineSimulator) Run(ctx context.Context, o SimOptions) ([]RawRow, error) {
	var picks map[string][]string
	if len(o.Picks) > 0 {
		if err := json.Unmarshal(o.Picks, &picks); err != nil {
			return nil, err
		}
	}
	rows, err := sim.Run(ctx, sim.Options{Battle: o.Battle, Bot: o.Bot, SeedFrom: o.SeedFrom, Count: o.Count,
		DataDir: o.DataDir, Workers: o.Workers, Progress: o.Progress,
		TablesDir: o.TablesDir, Sets: o.Overrides, Picks: picks, MaxRounds: o.MaxRounds})
	if err != nil {
		return nil, err
	}
	out := make([]RawRow, len(rows))
	for i := range rows {
		if out[i], err = rows[i].JSON(); err != nil {
			return nil, err
		}
	}
	return out, nil
}

func (EngineSimulator) Replay(ctx context.Context, o ReplayOptions) (json.RawMessage, error) {
	rep, err := sim.ReplayWith(sim.ReplayOptions{Battle: o.Battle, Bot: o.Bot, Seed: o.Seed, DataDir: o.DataDir, TablesDir: o.TablesDir})
	if err != nil {
		return nil, err
	}
	return rep.JSON()
}

// ExportMetrics 导出静态伤害矩阵（实现 MetricsExporter）。
func (EngineSimulator) ExportMetrics(tablesDir string) ([]byte, error) {
	data, err := rules.LoadData(rules.DataOptions{Root: tablesDir})
	if err != nil {
		return nil, err
	}
	m, err := sim.ExportMetrics(data)
	if err != nil {
		return nil, err
	}
	return m.JSON()
}
