package balance

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
)

// 只在能改变结论的地方花对局数。
//
// RunUntilDecided：分组序贯模拟。按递增的批次模拟，每批之后检查目标（一次"查看"）。一个机器人的
//   所有目标都已定论（区间整个在目标范围内或外）就停。反复查看会抬高误判率，所以每次查看用更严的
//   区间（Bonferroni：总共 5% 平分给各次查看）。
// Race：参数扫描的逐轮减半。每个组合先在相同种子上跑一小批，淘汰较差的一半，剩下的加倍，直到剩一两个，
//   再把它们跑到定论。
// Effects：把一次扫描的全部对局合在一起，每个机器人做一次回归，估计每个参数 +1 的影响。

// Looks 是查看结果的局数节点，Alpha 是总的误判率。
var Looks = []int{50, 100, 200, 400}

const Alpha = 0.05

// LooksFor 给出上限为 maxRuns 时的查看节点。
func LooksFor(maxRuns int) []int {
	var out []int
	for _, n := range Looks {
		if Looks[0] <= n && n < maxRuns {
			out = append(out, n)
		}
	}
	return append(out, maxRuns)
}

// Undecided 返回 bot 在序贯置信水平下还没有定论的指标。
func Undecided(df Frame, spec *Spec, bot string, nLooks int) ([]string, error) {
	if _, ok := spec.Bot(bot); !ok {
		return nil, nil
	}
	verdicts, err := Evaluate(df, spec.only([]string{bot}, 0), 1-Alpha/float64(nLooks))
	if err != nil {
		return nil, err
	}
	var out []string
	for _, v := range verdicts {
		if v.Status != "PASS" && v.Status != "FAIL" && v.Status != "KNOWN" {
			out = append(out, v.Metric)
		}
	}
	return out, nil
}

// DecideRequest 对应 Python 的 run_until_decided(...) 参数。
type DecideRequest struct {
	Battle     string
	Bots       []string
	Variant    string
	DataDir    string
	MaxRuns    int // 每个机器人的上限（默认 400）
	Seed       int
	Overrides  []string
	OnProgress func(n int)
	Spec       *Spec          // nil 时读 targets/<battle>.yaml（没有文件则每个机器人跑满）
	Start      map[string]int // 各机器人磁盘上已有的局数（扫描从上一轮接着跑）
}

// RunUntilDecided 让每个机器人一直模拟到所有目标定论或达到上限，返回各自用掉的局数。
// ctx 取消时在批次之间停下。
func (r *Runner) RunUntilDecided(ctx context.Context, req DecideRequest) (map[string]int, error) {
	if req.MaxRuns == 0 {
		req.MaxRuns = 400
	}
	spec := req.Spec
	if spec == nil {
		var err error
		if spec, err = r.Paths.LoadTargets(req.Battle); err != nil {
			return nil, err
		}
	}
	used := map[string]int{}
	nLooks := len(LooksFor(req.MaxRuns))
	for _, bot := range req.Bots {
		done := req.Start[bot]
		rules, _ := spec.Bot(bot)
		hasTargets := len(rules) > 0
		plan := []int{req.MaxRuns}
		if hasTargets {
			plan = LooksFor(req.MaxRuns)
		}
		var todo []int
		for _, n := range plan {
			if n > done {
				todo = append(todo, n)
			}
		}
		if len(todo) == 0 {
			todo = []int{done}
		}
		for _, n := range todo {
			if ctx.Err() != nil {
				break
			}
			if n > done {
				_, err := r.Simulate(ctx, SimRequest{Battle: req.Battle, Bot: bot, Runs: n - done, Seed: req.Seed + done,
					Variant: req.Variant, DataDir: req.DataDir, Overrides: req.Overrides, OnProgress: req.OnProgress,
					Append: done > 0})
				if err != nil {
					return used, err
				}
				done = n
			}
			if hasTargets {
				df, err := r.Paths.LoadBotRuns(req.Battle, req.Variant, bot)
				if err != nil {
					return used, err
				}
				open, err := Undecided(df, spec, bot, nLooks)
				if err != nil {
					return used, err
				}
				if len(open) == 0 {
					break
				}
			}
		}
		used[bot] = done
		if req.OnProgress != nil && done < req.MaxRuns {
			req.OnProgress(req.MaxRuns - done) // 跳过的局数：让进度条如实走完
		}
	}
	return used, nil
}

// PredictedRunsSaved 是相对于全部跑满省下的比例。
func PredictedRunsSaved(used map[string]int, maxRuns int) float64 {
	total := maxRuns * len(used)
	if total == 0 {
		return 0
	}
	sum := 0
	for _, n := range used {
		sum += n
	}
	return 1 - float64(sum)/float64(total)
}

// --- 逐轮减半 -----------------------------------------------------------------------------------

// Loss 返回（偏出目标多远，离目标中心多远），越小越好。每条偏差以目标范围的宽度为单位，
// 这样百分比和回合数可以相加；第二个数只用来给都没偏出的组合排先后。
func Loss(verdicts []Verdict) [2]float64 {
	miss, off := 0.0, 0.0
	for _, v := range verdicts {
		if v.Estimate.N == 0 || math.IsNaN(v.Estimate.Value) {
			miss++
			continue
		}
		width := v.Hi - v.Lo
		if width == 0 {
			width = 1
		}
		miss += math.Max(math.Max(v.Lo-v.Estimate.Value, v.Estimate.Value-v.Hi), 0) / width
		off += math.Abs(v.Estimate.Value-(v.Lo+v.Hi)/2) / width
	}
	return [2]float64{roundTo(miss, 6), roundTo(off, 6)}
}

func lossLess(a, b [2]float64) bool {
	if a[0] != b[0] {
		return a[0] < b[0]
	}
	return a[1] < b[1]
}

// Axis 是扫描的一个维度："units:heracles.str" 取若干值。
type Axis struct {
	Key    string
	Values []string
}

// ParseAxis 解析 "units:heracles.str=16,18"。
func ParseAxis(s string) (Axis, error) {
	key, vals, ok := strings.Cut(s, "=")
	if !ok || vals == "" {
		return Axis{}, fmt.Errorf("--set 需要取值：%s", s)
	}
	a := Axis{Key: key}
	for _, v := range strings.Split(vals, ",") {
		a.Values = append(a.Values, strings.TrimSpace(v))
	}
	return a, nil
}

// RaceRow 是一个参数组合的结果。
type RaceRow struct {
	Label        string
	Variant      string
	Overrides    []string
	Runs         int
	Verdicts     []Verdict
	Loss         [2]float64
	EliminatedAt int // 0 表示进了决赛
}

// Race 对 axes 的全部组合做逐轮减半，返回每个组合一行，最好的在最前。
func (r *Runner) Race(ctx context.Context, battle string, axes []Axis, bots []string, maxRuns, first, seed int,
	log func(string)) ([]*RaceRow, error) {
	spec, err := LoadSpec(r.Paths.TargetsPath(battle))
	if err != nil {
		return nil, err
	}
	specBots := spec.only(bots, 0)
	var rows []*RaceRow
	combo := make([]string, len(axes))
	var build func(i int)
	build = func(i int) {
		if i == len(axes) {
			row := &RaceRow{Loss: [2]float64{math.Inf(1), math.Inf(1)}}
			var labels, parts []string
			for j, a := range axes {
				o := a.Key + "=" + combo[j]
				row.Overrides = append(row.Overrides, o)
				_, short, _ := strings.Cut(a.Key, ":")
				labels = append(labels, short+"="+combo[j])
				parts = append(parts, strings.ReplaceAll(o, ":", "."))
			}
			row.Label, row.Variant = strings.Join(labels, " "), strings.Join(parts, "__")
			rows = append(rows, row)
			return
		}
		for _, v := range axes[i].Values {
			combo[i] = v
			build(i + 1)
		}
	}
	build(0)
	evaluate := func(row *RaceRow) error {
		df, err := r.Paths.LoadRuns(battle, row.Variant)
		if err != nil {
			return err
		}
		if row.Verdicts, err = Evaluate(df, specBots, 0); err != nil {
			return err
		}
		row.Loss = Loss(row.Verdicts)
		return nil
	}
	alive := append([]*RaceRow(nil), rows...)
	n := min(first, maxRuns)
	for {
		for _, row := range alive {
			for _, bot := range bots {
				if _, err := r.Simulate(ctx, SimRequest{Battle: battle, Bot: bot, Runs: n - row.Runs, Seed: seed + row.Runs,
					Variant: row.Variant, Overrides: row.Overrides, Append: row.Runs > 0}); err != nil {
					return nil, err
				}
			}
			row.Runs = n
			if err := evaluate(row); err != nil {
				return nil, err
			}
		}
		sort.SliceStable(alive, func(i, j int) bool { return lossLess(alive[i].Loss, alive[j].Loss) })
		if log != nil {
			parts := make([]string, len(alive))
			for i, row := range alive {
				parts[i] = fmt.Sprintf("%s（偏离 %.2f）", row.Label, row.Loss[0])
			}
			log(strconv.Itoa(n) + " 局后：" + strings.Join(parts, "；"))
		}
		if len(alive) <= 2 || n*2 > maxRuns/2 {
			break
		}
		keep := max(2, (len(alive)+1)/2)
		for _, row := range alive[keep:] {
			row.EliminatedAt = n
		}
		alive = alive[:keep]
		n *= 2
	}
	for i, row := range alive {
		if i >= 2 {
			row.EliminatedAt = n
			continue
		}
		start := map[string]int{}
		for _, b := range bots {
			start[b] = row.Runs
		}
		used, err := r.RunUntilDecided(ctx, DecideRequest{Battle: battle, Bots: bots, Variant: row.Variant,
			Overrides: row.Overrides, MaxRuns: maxRuns, Seed: seed, Spec: spec, Start: start})
		if err != nil {
			return nil, err
		}
		row.Runs = 0
		for _, u := range used {
			row.Runs = max(row.Runs, u)
		}
		if err := evaluate(row); err != nil {
			return nil, err
		}
	}
	sort.SliceStable(rows, func(i, j int) bool {
		a, b := rows[i], rows[j]
		if (a.EliminatedAt != 0) != (b.EliminatedAt != 0) {
			return a.EliminatedAt == 0
		}
		if a.EliminatedAt != b.EliminatedAt {
			return a.EliminatedAt > b.EliminatedAt
		}
		return lossLess(a.Loss, b.Loss)
	})
	return rows, nil
}

// --- 合并估计参数影响 ---------------------------------------------------------------------------

// Effect 是某个参数 +1 对一项结果的平均影响及其 95% 区间。
type Effect struct {
	Bot, Outcome, Parameter string // Outcome: "win_rate"（Logit 平均边际效应）或 "rounds"（胜局上的最小二乘）
	Effect, Lo, Hi          float64
}

// Effects 用扫描的全部对局估计每个数值参数 +1 的平均影响。取值不是数字或只有一个水平的参数跳过。
func (r *Runner) Effects(battle string, rows []*RaceRow, axes []Axis) ([]Effect, error) {
	var names []string
	for _, a := range axes {
		levels := map[float64]bool{}
		ok := true
		for _, v := range a.Values {
			f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
			if err != nil {
				ok = false
				break
			}
			levels[f] = true
		}
		if ok && len(levels) > 1 {
			names = append(names, a.Key)
		}
	}
	if len(names) == 0 {
		return nil, nil
	}
	type obs struct {
		x      []float64
		win    bool
		rounds float64
	}
	byBot := map[string][]obs{}
	for _, row := range rows {
		df, err := r.Paths.LoadRuns(battle, row.Variant)
		if err != nil {
			if _, none := err.(*ErrNoRuns); none {
				continue
			}
			return nil, err
		}
		x := make([]float64, len(names))
		for i := range x {
			x[i] = math.NaN()
		}
		for _, o := range row.Overrides {
			key, value, _ := strings.Cut(o, "=")
			for i, name := range names {
				if name == key {
					x[i], _ = strconv.ParseFloat(value, 64)
				}
			}
		}
		for _, run := range df.Rows {
			rounds, ok := run.Num["rounds"]
			if !ok {
				rounds = math.NaN()
			}
			byBot[run.Bot] = append(byBot[run.Bot], obs{x, run.Win, rounds})
		}
	}
	bots := make([]string, 0, len(byBot))
	for b := range byBot {
		bots = append(bots, b)
	}
	sort.Strings(bots)
	var out []Effect
	design := func(d []obs) [][]float64 {
		X := make([][]float64, len(d))
		for i, o := range d {
			X[i] = append([]float64{1}, o.x...)
		}
		return X
	}
	for _, bot := range bots {
		d := byBot[bot]
		y := make([]float64, len(d))
		wins := []obs{}
		sum := 0.0
		for i, o := range d {
			if o.win {
				y[i] = 1
				wins = append(wins, o)
			}
			sum += y[i]
		}
		if mean := sum / float64(len(d)); mean > 0 && mean < 1 {
			if eff, lo, hi, ok := logitMargins(design(d), y); ok {
				for j, name := range names {
					out = append(out, Effect{bot, "win_rate", name, eff[j+1], lo[j+1], hi[j+1]})
				}
			}
		}
		if len(wins) > len(names)+2 {
			yr := make([]float64, len(wins))
			for i, o := range wins {
				yr[i] = o.rounds
			}
			if beta, lo, hi, ok := olsFit(design(wins), yr); ok {
				for j, name := range names {
					out = append(out, Effect{bot, "rounds", name, beta[j+1], lo[j+1], hi[j+1]})
				}
			}
		}
	}
	return out, nil
}
