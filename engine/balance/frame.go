package balance

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"

	oj "srpg/balance/ordjson"
)

// Heavy 是逐格明细字段：统计时丢掉，工坊画热力图时才读原始行。
var Heavy = []string{"dmg_cells", "falls", "kills"}

// Run 是一局模拟结果展平后的样子（相当于 pandas.json_normalize 的一行）。
type Run struct {
	Bot, Result string
	Win         bool
	Num         map[string]float64 // 数值列："rounds"、"party_hp_left"、"counts.fall_enemy"、"units.hero.dealt"…
}

// Frame 是一组结果；Cols 记录出现过的列（某些行可能缺）。
type Frame struct {
	Rows []Run
	Cols map[string]bool
}

// ParseRun 解析 runs.jsonl 的一行。
func ParseRun(line []byte) (Run, error) {
	v, err := oj.ParseObject(line)
	if err != nil {
		return Run{}, err
	}
	return RunFromObject(v), nil
}

// RunFromObject 把一局的 JSON 对象展平。
func RunFromObject(o *oj.Object) Run {
	r := Run{Num: map[string]float64{}}
	r.Bot = o.Str("bot", "")
	r.Result = o.Str("result", "")
	r.Win, _ = o.Get("win").(bool)
	for _, k := range o.Keys() {
		heavy := false
		for _, h := range Heavy {
			heavy = heavy || k == h
		}
		if !heavy {
			flatten(k, o.Get(k), r.Num)
		}
	}
	return r
}

func flatten(prefix string, v any, out map[string]float64) {
	switch x := v.(type) {
	case *oj.Object:
		for _, k := range x.Keys() {
			flatten(prefix+"."+k, x.Get(k), out)
		}
	case bool:
		if x {
			out[prefix] = 1
		} else {
			out[prefix] = 0
		}
	default:
		if f, ok := oj.Float(v); ok {
			out[prefix] = f
		}
	}
}

// NewFrame 由若干行构造。
func NewFrame(rows []Run) Frame {
	f := Frame{Rows: rows, Cols: map[string]bool{}}
	for _, r := range rows {
		for k := range r.Num {
			f.Cols[k] = true
		}
	}
	return f
}

// ParseRuns 解析一整个 JSONL。
func ParseRuns(data []byte) ([]Run, error) {
	var rows []Run
	for _, line := range bytes.Split(data, []byte("\n")) {
		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}
		r, err := ParseRun(line)
		if err != nil {
			return nil, err
		}
		rows = append(rows, r)
	}
	return rows, nil
}

func (f Frame) Len() int { return len(f.Rows) }

func (f Frame) filter(keep func(Run) bool) Frame {
	out := Frame{Cols: f.Cols}
	for _, r := range f.Rows {
		if keep(r) {
			out.Rows = append(out.Rows, r)
		}
	}
	return out
}

// OfBot 只留某个机器人的行。
func (f Frame) OfBot(bot string) Frame { return f.filter(func(r Run) bool { return r.Bot == bot }) }

// Wins 只留胜局。
func (f Frame) Wins() Frame { return f.filter(func(r Run) bool { return r.Win }) }

// Bots 按首次出现的顺序列出机器人。
func (f Frame) Bots() []string {
	var out []string
	seen := map[string]bool{}
	for _, r := range f.Rows {
		if !seen[r.Bot] {
			seen[r.Bot] = true
			out = append(out, r.Bot)
		}
	}
	return out
}

// Col 取一列，缺的位置是 NaN。
func (f Frame) Col(name string) []float64 {
	out := make([]float64, len(f.Rows))
	for i, r := range f.Rows {
		if v, ok := r.Num[name]; ok {
			out[i] = v
		} else {
			out[i] = math.NaN()
		}
	}
	return out
}

// CountResult 数某种结局的局数。
func (f Frame) CountResult(result string) int {
	n := 0
	for _, r := range f.Rows {
		if r.Result == result {
			n++
		}
	}
	return n
}

// Positive 数某列大于 0 的行数（缺列、缺值都算 0）。
func (f Frame) Positive(col string) int {
	n := 0
	for _, r := range f.Rows {
		if r.Num[col] > 0 {
			n++
		}
	}
	return n
}

// ErrNoRuns 表示还没有模拟结果。
type ErrNoRuns struct{ Dir, Battle string }

func (e *ErrNoRuns) Error() string {
	return fmt.Sprintf("%s 下没有模拟结果；先运行 `srpg sim %s`", e.Dir, e.Battle)
}

// LoadRuns 读一个关卡（基线或某个变体）所有机器人的结果。
func (p Paths) LoadRuns(battle, variant string) (Frame, error) {
	base := p.SimDir(battle, variant)
	files, _ := filepath.Glob(filepath.Join(base, "*", "runs.jsonl"))
	sort.Strings(files)
	var rows []Run
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			return Frame{}, err
		}
		part, err := ParseRuns(data)
		if err != nil {
			return Frame{}, fmt.Errorf("%s: %w", f, err)
		}
		rows = append(rows, part...)
	}
	if len(rows) == 0 {
		return Frame{}, &ErrNoRuns{base, battle}
	}
	return NewFrame(rows), nil
}

// LoadBotRuns 读单个机器人的结果；文件不存在时返回空表。
func (p Paths) LoadBotRuns(battle, variant, bot string) (Frame, error) {
	data, err := os.ReadFile(filepath.Join(p.RunDir(battle, bot, variant), "runs.jsonl"))
	if err != nil {
		return Frame{}, err
	}
	rows, err := ParseRuns(data)
	return NewFrame(rows), err
}

// ReadRawRuns 读原始行（保留键顺序和逐格明细），文件不存在时返回 nil。
func ReadRawRuns(path string) ([]*oj.Object, error) {
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var out []*oj.Object
	for _, line := range bytes.Split(data, []byte("\n")) {
		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}
		o, err := oj.ParseObject(line)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		out = append(out, o)
	}
	return out, nil
}

// RawRow 是模拟器吐出的一局结果（一行 JSONL）。
type RawRow = json.RawMessage
