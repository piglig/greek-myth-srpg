package balance

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// ErrEngineNotWired 表示 Go 战斗引擎还没有接进来（默认构建里 EngineSimulator 是占位）。
var ErrEngineNotWired = errors.New("战斗引擎尚未接入：用 -tags simengine 构建（见 engine/balance/engine_adapter.go），或用 --simulator file:<目录> / fake")

// MetricsExporter 是模拟器可选实现的接口：导出静态伤害矩阵（metrics.json 的内容），给 `srpg ttk --export` 用。
type MetricsExporter interface {
	ExportMetrics(tablesDir string) ([]byte, error)
}

// SimOptions 是交给战斗引擎的一批对局：种子 SeedFrom … SeedFrom+Count-1。
type SimOptions struct {
	Battle, Bot string
	SeedFrom    int
	Count       int
	// DataDir 是数据表覆盖目录（工坊变体）：里面有的 <表>.json、battles/<id>.json 整个替换基线里的同名文件，
	// 没有的回落到基线；空串表示纯基线。
	DataDir   string
	TablesDir string          // 基线数据表目录（prototype/data/tables）
	Overrides []string        // 参数扫描的数值改写："units:heracles.str=16"，只能改已有的键
	Workers   int             // 并行数；0 由引擎自己定
	MaxRounds int             // 超过这么多回合算超时（默认 30）
	Picks     json.RawMessage // 可选：指定技能树选点，{"hero": ["iron_arm", …]}
	// Progress 汇报累计完成数；可以从任意协程调用。
	Progress func(done, total int)
}

// ReplayOptions 指定要回放的一局。
type ReplayOptions struct {
	Battle, Bot string
	Seed        int
	DataDir     string // 覆盖目录，含义同 SimOptions.DataDir
	TablesDir   string // 基线数据表目录
}

// Simulator 是和战斗引擎之间唯一的接缝（实现见 engine_adapter.go）。
type Simulator interface {
	// Run 跑完一批对局，按种子顺序返回每局一行 JSON（和 runs.jsonl 的一行相同）。ctx 取消时尽快返回错误。
	Run(ctx context.Context, opts SimOptions) ([]RawRow, error)
	// Replay 返回一局的逐步回放（/api/replay 原样转给前端）。
	Replay(ctx context.Context, o ReplayOptions) (json.RawMessage, error)
}

// Runner 把模拟结果落到 balance/out/sim 下，文件布局和 Python 版相同。
type Runner struct {
	Paths   Paths
	Sim     Simulator
	Workers int
	Log     func(string) // 进度文字（可为 nil）
}

// SimRequest 对应 Python 的 sim.simulate(...) 参数。
type SimRequest struct {
	Battle, Bot string
	Runs, Seed  int
	Variant     string   // 结果放在 out/sim/<battle>/variants/<variant>/ 下；空 = 基线
	DataDir     string   // 工坊变体的覆盖目录
	Overrides   []string // "units:heracles.str=16"
	MaxRounds   int
	Picks       json.RawMessage
	Append      bool        // 保留 runs.jsonl 里已有的局，再追加这些
	OnProgress  func(n int) // 每完成 n 局调用一次
}

// Simulate 跑 Runs 局并写入 runs.jsonl，返回文件路径。
func (r *Runner) Simulate(ctx context.Context, req SimRequest) (string, error) {
	if r.Sim == nil {
		return "", fmt.Errorf("没有配置模拟器")
	}
	out := r.Paths.RunDir(req.Battle, req.Bot, req.Variant)
	if err := os.MkdirAll(out, 0o755); err != nil {
		return "", err
	}
	maxRounds := req.MaxRounds
	if maxRounds == 0 {
		maxRounds = 30
	}
	var mu sync.Mutex
	last := 0
	opts := SimOptions{Battle: req.Battle, Bot: req.Bot, SeedFrom: req.Seed, Count: req.Runs, DataDir: req.DataDir,
		TablesDir: r.Paths.Tables, Overrides: req.Overrides, Workers: r.Workers, MaxRounds: maxRounds, Picks: req.Picks}
	if req.OnProgress != nil {
		opts.Progress = func(done, total int) {
			mu.Lock()
			delta := done - last
			if delta > 0 {
				last = done
			}
			mu.Unlock()
			if delta > 0 {
				req.OnProgress(delta)
			}
		}
	}
	rows, err := r.Sim.Run(ctx, opts)
	if err != nil {
		return "", err
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	if len(rows) != req.Runs {
		return "", fmt.Errorf("模拟器返回了 %d 局，应为 %d 局", len(rows), req.Runs)
	}
	if opts.Progress != nil {
		opts.Progress(req.Runs, req.Runs)
	}
	os.Remove(filepath.Join(out, "meta.json")) // 结果要变了，旧的元数据作废（模拟成功后才删，失败时旧结果和元数据都原样保留）
	merged := filepath.Join(out, "runs.jsonl")
	var buf bytes.Buffer
	if req.Append {
		if earlier, err := os.ReadFile(merged); err == nil {
			buf.Write(earlier)
		}
	}
	for _, row := range rows {
		if err := json.Compact(&buf, row); err != nil {
			return "", fmt.Errorf("模拟器返回的行不是合法 JSON：%w", err)
		}
		buf.WriteByte('\n')
	}
	return merged, os.WriteFile(merged, buf.Bytes(), 0o644)
}

// KeepCompleteLines 去掉崩溃的进程留下的半行记录，返回完整行数。
func KeepCompleteLines(part string) (int, error) {
	data, err := os.ReadFile(part)
	if os.IsNotExist(err) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	var good []string
	for _, line := range strings.Split(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n") {
		if !json.Valid([]byte(line)) {
			break
		}
		good = append(good, line)
	}
	var b strings.Builder
	for _, g := range good {
		b.WriteString(g + "\n")
	}
	return len(good), os.WriteFile(part, []byte(b.String()), 0o644)
}
