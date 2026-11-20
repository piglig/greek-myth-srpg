package balance

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"
)

// 和 Python 版逐项对数。参考文件由 Python 实现生成：
//   - testdata/pyref.json：对 testdata/sim 里固定的一份真实结果（随仓库走，永远运行）
//   - $BALANCE_PY_REF：对 balance/out/sim 里当前的全部结果（设置了才运行）

type refVerdict struct {
	Bot, Metric, Status, Note, Fmt string
	N                              int
	Value, Lo, Hi                  *float64
}

type refFile struct {
	Cases []struct {
		Battle, Variant string
		Rows            int
		V95, Vseq       []refVerdict
		Loss            []float64
		Undecided       map[string][]string
	}
	Effects []struct {
		Battle string
		Axes   [][]any
		Rows   []struct {
			Bot, Outcome, Parameter string
			Effect, Lo, Hi          float64
		}
	}
}

func refNum(p *float64) float64 {
	if p == nil {
		return math.NaN()
	}
	return *p
}

func compareVerdicts(t *testing.T, where string, got []Verdict, want []refVerdict) int {
	t.Helper()
	if len(got) != len(want) {
		t.Errorf("%s: %d 条判定，Python 是 %d 条", where, len(got), len(want))
		return 0
	}
	for i, w := range want {
		g := got[i]
		id := where + " " + w.Bot + "." + w.Metric
		if g.Bot != w.Bot || g.Metric != w.Metric || g.Status != w.Status || g.Note != w.Note || g.Estimate.N != w.N {
			t.Errorf("%s: 得到 %s/%s/%q/n=%d，Python 是 %s/%s/%q/n=%d", id, g.Metric, g.Status, g.Note, g.Estimate.N,
				w.Metric, w.Status, w.Note, w.N)
		}
		approx(t, id+" value", g.Estimate.Value, refNum(w.Value), 1e-9)
		if w.Status != "NO_DATA" {
			approx(t, id+" lo", g.Estimate.Lo, refNum(w.Lo), 1e-9)
			approx(t, id+" hi", g.Estimate.Hi, refNum(w.Hi), 1e-9)
		}
		if f := g.Estimate.Fmt(g.Pct); f != w.Fmt {
			t.Errorf("%s: 显示为 %q，Python 是 %q", id, f, w.Fmt)
		}
	}
	return len(want)
}

func crossCheck(t *testing.T, p Paths, refPath string) {
	data, err := os.ReadFile(refPath)
	if err != nil {
		t.Fatal(err)
	}
	var ref refFile
	if err := json.Unmarshal(data, &ref); err != nil {
		t.Fatal(err)
	}
	r := &Runner{Paths: p}
	nVerdicts, nEffects := 0, 0
	for _, c := range ref.Cases {
		where := c.Battle + "/" + c.Variant
		spec, err := LoadSpec(p.TargetsPath(c.Battle))
		if err != nil {
			t.Fatal(err)
		}
		df, err := p.LoadRuns(c.Battle, c.Variant)
		if err != nil {
			t.Fatal(err)
		}
		if df.Len() != c.Rows {
			t.Fatalf("%s: %d 行，参考文件是 %d 行（结果变了？重新生成参考文件）", where, df.Len(), c.Rows)
		}
		v95, err := Evaluate(df, spec, 0)
		if err != nil {
			t.Fatal(err)
		}
		nVerdicts += compareVerdicts(t, where+" 95%", v95, c.V95)
		vseq, err := Evaluate(df, spec.only(spec.BotNames(), 0), 1-Alpha/4)
		if err != nil {
			t.Fatal(err)
		}
		nVerdicts += compareVerdicts(t, where+" 序贯", vseq, c.Vseq)
		loss := Loss(v95)
		approx(t, where+" loss[0]", loss[0], c.Loss[0], 1e-9)
		approx(t, where+" loss[1]", loss[1], c.Loss[1], 1e-9)
		for bot, want := range c.Undecided {
			got, err := Undecided(df, spec, bot, 4)
			if err != nil {
				t.Fatal(err)
			}
			if len(got) != len(want) {
				t.Errorf("%s %s: 未定论 %v，Python 是 %v", where, bot, got, want)
				continue
			}
			for i := range want {
				if got[i] != want[i] {
					t.Errorf("%s %s: 未定论 %v，Python 是 %v", where, bot, got, want)
				}
			}
		}
	}
	for _, e := range ref.Effects {
		var axes []Axis
		for _, a := range e.Axes {
			ax := Axis{Key: a[0].(string)}
			for _, v := range a[1].([]any) {
				ax.Values = append(ax.Values, v.(string))
			}
			axes = append(axes, ax)
		}
		var rows []*RaceRow
		var build func(i int, ov []string)
		build = func(i int, ov []string) {
			if i == len(axes) {
				row := &RaceRow{Overrides: append([]string(nil), ov...)}
				for j, o := range ov {
					if j > 0 {
						row.Variant += "__"
					}
					row.Variant += replaceColon(o)
				}
				rows = append(rows, row)
				return
			}
			for _, v := range axes[i].Values {
				build(i+1, append(ov, axes[i].Key+"="+v))
			}
		}
		build(0, nil)
		got, err := r.Effects(e.Battle, rows, axes)
		if err != nil {
			t.Fatal(err)
		}
		if len(got) != len(e.Rows) {
			t.Errorf("%s: %d 行参数影响，Python 是 %d 行", e.Battle, len(got), len(e.Rows))
			continue
		}
		for i, w := range e.Rows {
			g := got[i]
			id := e.Battle + " " + w.Bot + " " + w.Outcome + " " + w.Parameter
			if g.Bot != w.Bot || g.Outcome != w.Outcome || g.Parameter != w.Parameter {
				t.Errorf("%s: 得到 %s %s %s", id, g.Bot, g.Outcome, g.Parameter)
			}
			tol := 1e-6
			if w.Outcome == "win_rate" && w.Hi-w.Lo > 2 {
				// 准分离（几乎全败）时 Logit 不收敛，statsmodels 照样给出一个病态的区间；点估计能对上，区间只能对到百分之几
				tol = 0.05 * math.Abs(w.Hi)
			}
			approx(t, id+" effect", g.Effect, w.Effect, 1e-6)
			approx(t, id+" lo", g.Lo, w.Lo, tol)
			approx(t, id+" hi", g.Hi, w.Hi, tol)
			nEffects++
		}
	}
	t.Logf("对上 Python：%d 个结果集，%d 条判定，%d 行参数影响", len(ref.Cases), nVerdicts, nEffects)
}

func replaceColon(s string) string {
	out := []byte(s)
	for i, c := range out {
		if c == ':' {
			out[i] = '.'
		}
	}
	return string(out)
}

// 固定样本：testdata 里是 2026-11-20 的 1-4 基线结果（熟练、新手各 50 局）和当时的目标文件。
func TestGoldenAgainstPython(t *testing.T) {
	p := NewPaths(filepath.Join("testdata", "project"))
	crossCheck(t, p, filepath.Join("testdata", "pyref.json"))
}

// 全量：BALANCE_PY_REF 指向 Python 对当前 balance/out/sim 生成的参考文件。
func TestLiveAgainstPython(t *testing.T) {
	ref := os.Getenv("BALANCE_PY_REF")
	if ref == "" {
		t.Skip("未设置 BALANCE_PY_REF")
	}
	root, err := FindProject()
	if err != nil {
		t.Skip(err)
	}
	crossCheck(t, NewPaths(root), ref)
}
