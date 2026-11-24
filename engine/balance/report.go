package balance

import (
	"fmt"
	"html"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// 单个关卡的自包含 HTML 平衡报告：目标判定表 + 六张图（内嵌 SVG，不依赖任何外部脚本）。

// StatusStyle 是判定状态的中文名和颜色。
var StatusStyle = map[string][2]string{
	"PASS": {"通过", "#2e7d32"}, "FAIL": {"未通过", "#c62828"}, "INCONCLUSIVE": {"待定", "#ef8f00"},
	"KNOWN": {"已知问题", "#6d4c8d"}, "NO_DATA": {"无数据", "#757575"},
}

var sourceNames = map[string]string{"fall": "坠落", "collision": "撞击", "edge": "坠出边缘", "assist": "援护"}

var mechanicNames = [][2]string{
	{"counts.throw", "过肩摔"}, {"counts.mark", "标记"}, {"counts.intercept", "截击"},
	{"counts.leap", "跃射"}, {"counts.fall_enemy", "敌人坠落"}, {"counts.broken", "破势"}, {"counts.assist", "援护"},
	{"counts.knockback", "击退"},
}

var palette = []string{"#636efa", "#ef553b", "#00cc96", "#ab63fa", "#ffa15a", "#19d3f3", "#ff6692", "#b6e880", "#ff97ff", "#fecb52"}

const reportHead = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><title>平衡报告 %s</title>
<style>
 body{font-family:"Microsoft YaHei UI","PingFang SC",sans-serif;margin:32px auto;max-width:1180px;color:#222;background:#fafaf7}
 h1{margin-bottom:4px} .meta{color:#666;margin-bottom:24px}
 table{border-collapse:collapse;width:100%%;margin:12px 0 28px;background:#fff}
 th,td{border:1px solid #ddd;padding:6px 10px;text-align:left;font-size:14px} th{background:#f0ede6}
 .tag{display:inline-block;padding:1px 8px;border-radius:3px;color:#fff;font-size:13px}
 .grid{display:grid;grid-template-columns:1fr 1fr;gap:16px} .card{background:#fff;border:1px solid #ddd;padding:8px}
 .summary span{margin-right:18px;font-size:15px}
 svg text{font-family:inherit}
</style></head><body>
`

// ReportHTML 生成报告内容。
func ReportHTML(battle string, df Frame, verdicts []Verdict, now time.Time) string {
	esc := html.EscapeString
	var b strings.Builder
	fmt.Fprintf(&b, reportHead, esc(battle))
	bots := df.Bots()
	fmt.Fprintf(&b, "<h1>平衡报告：%s</h1>\n<div class=\"meta\">生成于 %s　·　样本：", esc(battle), now.Format("2006-01-02 15:04"))
	for _, bot := range bots {
		fmt.Fprintf(&b, "%s %d 局　", esc(bot), df.OfBot(bot).Len())
	}
	b.WriteString("　·　区间为 95% 置信区间</div>\n<div class=\"summary\">")
	tag := func(status string) string {
		st, ok := StatusStyle[status]
		if !ok {
			st = [2]string{status, "#757575"}
		}
		return fmt.Sprintf(`<span class="tag" style="background:%s">%s</span>`, st[1], st[0])
	}
	var order []string
	tally := map[string]int{}
	for _, v := range verdicts {
		if tally[v.Status] == 0 {
			order = append(order, v.Status)
		}
		tally[v.Status]++
	}
	for _, k := range order {
		fmt.Fprintf(&b, "<span>%s %d</span>", tag(k), tally[k])
	}
	b.WriteString("</div>\n<h2>设计目标</h2>\n<table><tr><th>机器人</th><th>指标</th><th>目标</th><th>实测</th><th>结论</th><th>说明</th></tr>\n")
	for _, v := range verdicts {
		fmt.Fprintf(&b, "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td>\n<td>%s</td><td>%s</td></tr>",
			esc(v.Bot), esc(v.Label), v.FmtTarget(), v.Estimate.Fmt(v.Pct), tag(v.Status), esc(v.Note))
	}
	b.WriteString("\n</table>\n<h2>结果分布</h2>\n<div class=\"grid\">")
	for _, fig := range reportFigures(df, bots) {
		b.WriteString(`<div class="card">` + fig + `</div>`)
	}
	b.WriteString("</div>\n</body></html>")
	return b.String()
}

// BuildReport 写 out/report/<battle>.html 并返回路径。
func (p Paths) BuildReport(battle string, df Frame, verdicts []Verdict) (string, error) {
	out := filepath.Join(p.Out, "report", battle+".html")
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return "", err
	}
	return out, os.WriteFile(out, []byte(ReportHTML(battle, df, verdicts, time.Now())), 0o644)
}

func nanToZero(v float64) float64 {
	if math.IsNaN(v) {
		return 0
	}
	return v
}

func colMean(f Frame, col string) float64 {
	if f.Len() == 0 {
		return math.NaN()
	}
	s := 0.0
	for _, r := range f.Rows {
		s += r.Num[col]
	}
	return s / float64(f.Len())
}

func reportFigures(df Frame, bots []string) []string {
	var figs []string
	perBot := make([]Frame, len(bots))
	for i, b := range bots {
		perBot[i] = df.OfBot(b)
	}

	// 1. 各机器人的结局分布（Wilson 区间）
	var s1 []barSeries
	for _, r := range [][3]string{{"win", "胜利", "#2e7d32"}, {"loss_hero", "主角倒下", "#c62828"},
		{"loss_wipe", "全灭", "#8e24aa"}, {"timeout", "超时", "#757575"}} {
		s := barSeries{Name: r[1], Color: r[2]}
		for _, d := range perBot {
			e := Proportion(d.CountResult(r[0]), d.Len(), 0)
			s.Vals = append(s.Vals, e.Value)
			s.Lo = append(s.Lo, e.Lo)
			s.Hi = append(s.Hi, e.Hi)
		}
		s1 = append(s1, s)
	}
	figs = append(figs, barChart("战斗结果", "", bots, s1, false, true))

	// 2. 胜局回合数分布
	roundSet := map[int]bool{}
	counts := make([]map[int]int, len(bots))
	for i, d := range perBot {
		counts[i] = map[int]int{}
		for _, v := range d.Wins().Col("rounds") {
			if !math.IsNaN(v) {
				roundSet[int(v)] = true
				counts[i][int(v)]++
			}
		}
	}
	var rounds []int
	for r := range roundSet {
		rounds = append(rounds, r)
	}
	sort.Ints(rounds)
	cats := make([]string, len(rounds))
	for i, r := range rounds {
		cats[i] = fmt.Sprint(r)
	}
	var s2 []barSeries
	for i, b := range bots {
		s := barSeries{Name: b, Color: palette[i%len(palette)]}
		for _, r := range rounds {
			s.Vals = append(s.Vals, float64(counts[i][r]))
		}
		s2 = append(s2, s)
	}
	figs = append(figs, barChart("胜局回合数分布", "回合", cats, s2, false, false))

	// 3. 胜局我方剩余生命
	s3 := []boxSeries{{Name: "", Color: ""}}
	for _, d := range perBot {
		s3[0].Groups = append(s3[0].Groups, d.Wins().Col("party_hp_left"))
	}
	figs = append(figs, boxChart("胜局我方剩余生命比例", bots, s3, true))

	// 4. 对敌伤害来源（每局平均）
	var srcCols []string
	for c := range df.Cols {
		if strings.HasPrefix(c, "dmg_to_enemy.") {
			srcCols = append(srcCols, c)
		}
	}
	sort.Strings(srcCols)
	sort.SliceStable(srcCols, func(i, j int) bool { return colMean(df, srcCols[i]) > colMean(df, srcCols[j]) })
	var s4 []barSeries
	for i, c := range srcCols {
		src := strings.TrimPrefix(c, "dmg_to_enemy.")
		name := src
		if n, ok := sourceNames[src]; ok {
			name = n
		}
		s := barSeries{Name: name, Color: palette[i%len(palette)]}
		for _, d := range perBot {
			s.Vals = append(s.Vals, nanToZero(colMean(d, c)))
		}
		s4 = append(s4, s)
	}
	figs = append(figs, barChart("对敌伤害来源（每局平均）", "", bots, s4, true, false))

	// 5. 用到各机制的战斗比例
	var mcats, mcols []string
	for _, m := range mechanicNames {
		if df.Cols[m[0]] {
			mcols = append(mcols, m[0])
			mcats = append(mcats, m[1])
		}
	}
	var s5 []barSeries
	for i, d := range perBot {
		s := barSeries{Name: bots[i], Color: palette[i%len(palette)]}
		for _, c := range mcols {
			share := 0.0
			if d.Len() > 0 {
				share = float64(d.Positive(c)) / float64(d.Len())
			}
			s.Vals = append(s.Vals, share)
		}
		s5 = append(s5, s)
	}
	figs = append(figs, barChart("用到各机制的战斗比例", "", mcats, s5, false, true))

	// 6. 我方各单位每局造成的伤害
	var s6 []boxSeries
	for i, u := range []string{"hero", "atalanta", "heracles"} {
		col := "units." + u + ".dealt"
		if !df.Cols[col] {
			continue
		}
		s := boxSeries{Name: u, Color: palette[i]}
		for _, d := range perBot {
			var vals []float64
			for _, v := range d.Col(col) {
				if !math.IsNaN(v) {
					vals = append(vals, v)
				}
			}
			s.Groups = append(s.Groups, vals)
		}
		s6 = append(s6, s)
	}
	figs = append(figs, boxChart("我方各单位造成伤害（每局）", bots, s6, false))
	return figs
}

// --- 极简 SVG 图 --------------------------------------------------------------------------------

type barSeries struct {
	Name, Color string
	Vals        []float64
	Lo, Hi      []float64 // 可选：误差线的两端
}

type boxSeries struct {
	Name, Color string
	Groups      [][]float64 // 每个分类一组样本
}

const (
	chartW, chartH         = 560.0, 360.0
	padL, padR, padT, padB = 54.0, 12.0, 58.0, 44.0
	plotW, plotH           = chartW - padL - padR, chartH - padT - padB
)

// niceMax 把纵轴上限取整到好读的刻度。
func niceMax(v float64) (maxV, step float64) {
	if !(v > 0) {
		return 1, 0.2
	}
	mag := math.Pow(10, math.Floor(math.Log10(v)))
	for _, m := range []float64{1, 2, 2.5, 5, 10} {
		if v <= m*mag*1.0000001 {
			return m * mag, m * mag / 5
		}
	}
	return 10 * mag, 2 * mag
}

func tickLabel(v float64, pct bool) string {
	if pct {
		return Pct0(v)
	}
	return FmtG(roundTo(v, 6))
}

func chartFrame(b *strings.Builder, title, xTitle string, legend []barSeries, maxV, step float64, pct bool) {
	fmt.Fprintf(b, `<svg viewBox="0 0 %g %g" width="100%%" xmlns="http://www.w3.org/2000/svg" role="img">`, chartW, chartH)
	fmt.Fprintf(b, `<text x="%g" y="20" font-size="15" font-weight="600" fill="#222">%s</text>`, padL, html.EscapeString(title))
	x := padL
	for _, s := range legend {
		if s.Name == "" {
			continue
		}
		fmt.Fprintf(b, `<rect x="%g" y="30" width="10" height="10" fill="%s"/><text x="%g" y="39" font-size="11" fill="#444">%s</text>`,
			x, s.Color, x+13, html.EscapeString(s.Name))
		x += 22 + 7*float64(displayWidth(s.Name))
	}
	for v := 0.0; v <= maxV*1.0000001; v += step {
		y := padT + plotH - v/maxV*plotH
		fmt.Fprintf(b, `<line x1="%g" y1="%.1f" x2="%g" y2="%.1f" stroke="#e6e6e6"/><text x="%g" y="%.1f" font-size="11" fill="#666" text-anchor="end">%s</text>`,
			padL, y, chartW-padR, y, padL-6, y+4, tickLabel(v, pct))
	}
	fmt.Fprintf(b, `<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="#888"/>`, padL, padT+plotH, chartW-padR, padT+plotH)
	if xTitle != "" {
		fmt.Fprintf(b, `<text x="%g" y="%g" font-size="12" fill="#444" text-anchor="middle">%s</text>`,
			padL+plotW/2, chartH-6, html.EscapeString(xTitle))
	}
}

func catLabel(b *strings.Builder, i, n int, label string) {
	slot := plotW / float64(max(n, 1))
	fmt.Fprintf(b, `<text x="%.1f" y="%g" font-size="11" fill="#444" text-anchor="middle">%s</text>`,
		padL+slot*(float64(i)+0.5), padT+plotH+16, html.EscapeString(label))
}

func barChart(title, xTitle string, cats []string, series []barSeries, stacked, pct bool) string {
	top := 0.0
	for i := range cats {
		sum := 0.0
		for _, s := range series {
			v := nanToZero(s.Vals[i])
			if s.Hi != nil {
				v = math.Max(v, nanToZero(s.Hi[i]))
			}
			sum += v
			if !stacked {
				top = math.Max(top, v)
			}
		}
		if stacked {
			top = math.Max(top, sum)
		}
	}
	maxV, step := niceMax(top)
	if pct {
		maxV, step = 1, 0.2
	}
	var b strings.Builder
	chartFrame(&b, title, xTitle, series, maxV, step, pct)
	slot := plotW / float64(max(len(cats), 1))
	y := func(v float64) float64 { return padT + plotH - v/maxV*plotH }
	for i, c := range cats {
		catLabel(&b, i, len(cats), c)
		x0 := padL + slot*float64(i) + slot*0.12
		w := slot * 0.76
		base := 0.0
		for j, s := range series {
			v := nanToZero(s.Vals[i])
			tip := fmt.Sprintf("%s · %s：%s", c, s.Name, tickLabel(v, pct))
			if stacked {
				fmt.Fprintf(&b, `<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"><title>%s</title></rect>`,
					x0, y(base+v), w, y(base)-y(base+v), s.Color, html.EscapeString(tip))
				base += v
				continue
			}
			bw := w / float64(len(series))
			bx := x0 + bw*float64(j)
			fmt.Fprintf(&b, `<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"><title>%s</title></rect>`,
				bx, y(v), bw*0.92, y(0)-y(v), s.Color, html.EscapeString(tip))
			if s.Lo != nil && !math.IsNaN(s.Vals[i]) {
				cx := bx + bw*0.46
				fmt.Fprintf(&b, `<path d="M%.1f %.1fV%.1fM%.1f %.1fh6M%.1f %.1fh6" stroke="#333" fill="none"/>`,
					cx, y(s.Hi[i]), y(s.Lo[i]), cx-3, y(s.Hi[i]), cx-3, y(s.Lo[i]))
			}
		}
	}
	b.WriteString("</svg>")
	return b.String()
}

func boxChart(title string, cats []string, series []boxSeries, pct bool) string {
	top := 0.0
	for _, s := range series {
		for _, g := range s.Groups {
			for _, v := range g {
				top = math.Max(top, v)
			}
		}
	}
	maxV, step := niceMax(top)
	if pct {
		maxV, step = 1, 0.2
	}
	legend := make([]barSeries, len(series))
	for i, s := range series {
		legend[i] = barSeries{Name: s.Name, Color: s.Color}
	}
	var b strings.Builder
	chartFrame(&b, title, "", legend, maxV, step, pct)
	slot := plotW / float64(max(len(cats), 1))
	y := func(v float64) float64 { return padT + plotH - v/maxV*plotH }
	for i, c := range cats {
		catLabel(&b, i, len(cats), c)
		w := slot * 0.7 / float64(max(len(series), 1))
		for j, s := range series {
			vals := append([]float64(nil), s.Groups[i]...)
			if len(vals) == 0 {
				continue
			}
			sort.Float64s(vals)
			q := func(p float64) float64 { return percentileSorted(vals, p) }
			color := s.Color
			if color == "" {
				color = palette[i%len(palette)]
			}
			x := padL + slot*float64(i) + slot*0.15 + w*float64(j)
			cx, bw := x+w*0.46, w*0.92
			tip := fmt.Sprintf("%s %s：中位数 %s，四分位 %s–%s，范围 %s–%s，均值 %s（%d 局）", c, s.Name, tickLabel(q(50), pct),
				tickLabel(q(25), pct), tickLabel(q(75), pct), tickLabel(vals[0], pct), tickLabel(vals[len(vals)-1], pct),
				tickLabel(meanOf(vals), pct), len(vals))
			fmt.Fprintf(&b, `<g stroke="%s" fill="%s" fill-opacity="0.35"><title>%s</title>`, color, color, html.EscapeString(tip))
			fmt.Fprintf(&b, `<path d="M%.1f %.1fV%.1fM%.1f %.1fV%.1f" fill="none"/>`, cx, y(vals[len(vals)-1]), y(q(75)), cx, y(q(25)), y(vals[0]))
			fmt.Fprintf(&b, `<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f"/>`, x, y(q(75)), bw, math.Max(y(q(25))-y(q(75)), 0.5))
			fmt.Fprintf(&b, `<path d="M%.1f %.1fh%.1f" stroke-width="2"/>`, x, y(q(50)), bw)
			fmt.Fprintf(&b, `<path d="M%.1f %.1fh%.1f" stroke-dasharray="3 2"/></g>`, x, y(meanOf(vals)), bw)
		}
	}
	b.WriteString("</svg>")
	return b.String()
}

// displayWidth 是终端/图例里的显示宽度（中日韩字符算 2）。
func displayWidth(s string) int {
	w := 0
	for _, r := range s {
		if r >= 0x1100 && (r <= 0x115f || (r >= 0x2e80 && r <= 0xa4cf) || (r >= 0xac00 && r <= 0xd7a3) ||
			(r >= 0xf900 && r <= 0xfaff) || (r >= 0xfe30 && r <= 0xfe6f) || (r >= 0xff00 && r <= 0xff60) || (r >= 0xffe0 && r <= 0xffe6)) {
			w += 2
		} else {
			w++
		}
	}
	return w
}

// DisplayWidth 导出给命令行排表用。
func DisplayWidth(s string) int { return displayWidth(s) }
