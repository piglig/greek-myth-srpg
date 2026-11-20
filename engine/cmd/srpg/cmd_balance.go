package main

// 平衡分析相关的子命令（原 Python 的 `balance` 命令行）：
//
//	check    数据表 schema + 交叉引用 + 静态规格，然后打印"几下打死"表
//	ttk      只打印"几下打死"表
//	sim      用机器人模拟一场战斗，结果写到 balance/out/sim/<战斗>/<机器人>/runs.jsonl
//	report   用 targets/<战斗>.yaml 判定模拟结果，写 HTML 报告
//	run      把目标文件里的每个机器人模拟到定论，然后 report
//	sweep    参数扫描：逐轮减半找最符合目标的组合
//	studio   战棋工坊：关卡编辑 + 模拟 + 分析 + 回放（浏览器）
//
// 公共参数：--project <仓库根目录>、--simulator engine|fake|file:<目录>、--workers <并行数>。

import (
	"context"
	"fmt"
	"math"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"srpg/balance"
	"srpg/studio"
)

func init() {
	register("check", "校验数据表和静态规格，有问题时退出码非 0（--no-junit 不写 JUnit 文件）", balCheck)
	register("ttk", "打印主要攻击对第 1 章敌人几下打死（--scenario front|side|back|broken_side，--no-export）", balTTK)
	register("sim", "模拟战斗并存入 balance/out/sim（<战斗> --bot -n/--runs --seed --max-rounds --workers）", balSim)
	register("report", "按设计目标判定模拟结果并写 HTML 报告，有 FAIL 时退出码 1（<战斗>）", balReport)
	register("run", "把目标里的每个机器人模拟到定论再出报告（<战斗> -n/--runs --seed --full）", balRun)
	register("sweep", "参数扫描：逐轮减半找最符合目标的组合（<战斗> --set 表:键=v1,v2 … --bots -n/--runs --first --seed）", balSweep)
	register("studio", "启动战棋工坊（--port 8765 --no-open --rules <目录,目录> --rules-ext .go）", balStudio)
}

// balArgs 是解析后的命令行：位置参数和 --名字 值（可重复）。
type balArgs struct {
	pos  []string
	vals map[string][]string
}

// balParse 接受 --name=value、--name value、-n value、--flag、--no-flag，位置参数可以出现在任意位置。
func balParse(args []string, valued, flags []string) (*balArgs, error) {
	valued = append(valued, "project", "simulator", "workers")
	kind := map[string]byte{}
	for _, v := range valued {
		kind[v] = 'v'
	}
	for _, f := range flags {
		kind[f] = 'f'
	}
	out := &balArgs{vals: map[string][]string{}}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if !strings.HasPrefix(a, "-") || a == "-" {
			out.pos = append(out.pos, a)
			continue
		}
		name, value, hasValue := strings.Cut(strings.TrimLeft(a, "-"), "=")
		if name == "n" {
			name = "runs"
		}
		switch {
		case kind[name] == 'v':
			if !hasValue {
				if i+1 >= len(args) {
					return nil, fmt.Errorf("%s 需要一个值", a)
				}
				i++
				value = args[i]
			}
			out.vals[name] = append(out.vals[name], value)
		case kind[name] == 'f':
			out.vals[name] = []string{"true"}
		case strings.HasPrefix(name, "no-") && kind[name[3:]] == 'f':
			out.vals[name[3:]] = []string{"false"}
		default:
			return nil, fmt.Errorf("不认识的参数 %s", a)
		}
	}
	return out, nil
}

func (a *balArgs) str(name, def string) string {
	if v := a.vals[name]; len(v) > 0 {
		return v[len(v)-1]
	}
	return def
}

func (a *balArgs) num(name string, def int) (int, error) {
	s := a.str(name, "")
	if s == "" {
		return def, nil
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0, fmt.Errorf("--%s 需要整数，得到 %q", name, s)
	}
	return n, nil
}

func (a *balArgs) flag(name string, def bool) bool {
	if v := a.vals[name]; len(v) > 0 {
		return v[0] == "true"
	}
	return def
}

func (a *balArgs) battle() (string, error) {
	if len(a.pos) != 1 {
		return "", fmt.Errorf("需要一个战斗 id，例如 1-4")
	}
	return a.pos[0], nil
}

func (a *balArgs) paths() (balance.Paths, error) {
	root := a.str("project", "")
	if root == "" {
		var err error
		if root, err = balance.FindProject(); err != nil {
			return balance.Paths{}, err
		}
	}
	root, err := filepath.Abs(root)
	return balance.NewPaths(root), err
}

// simulator 按 --simulator（或环境变量 SRPG_SIMULATOR）选模拟器：engine（默认）、fake、file:<目录>。
func (a *balArgs) simulator() (balance.Simulator, error) {
	spec := a.str("simulator", os.Getenv("SRPG_SIMULATOR"))
	switch {
	case spec == "" || spec == "engine":
		return balance.EngineSimulator{}, nil
	case spec == "fake":
		return &balance.FakeSimulator{}, nil
	case strings.HasPrefix(spec, "file:"):
		return balance.FileSimulator{Dir: strings.TrimPrefix(spec, "file:")}, nil
	}
	return nil, fmt.Errorf("--simulator 应为 engine、fake 或 file:<目录>，得到 %q", spec)
}

func (a *balArgs) runner() (*balance.Runner, error) {
	p, err := a.paths()
	if err != nil {
		return nil, err
	}
	sim, err := a.simulator()
	if err != nil {
		return nil, err
	}
	workers, err := a.num("workers", 0)
	return &balance.Runner{Paths: p, Sim: sim, Workers: workers}, err
}

// balProgress 在终端同一行显示进度。
func balProgress(label string, total int) func(n int) {
	done := 0
	st, err := os.Stderr.Stat()
	tty := err == nil && st.Mode()&os.ModeCharDevice != 0 // 输出被重定向时不刷进度
	return func(n int) {
		done += n
		if !tty {
			return
		}
		fmt.Fprintf(os.Stderr, "\r%s %d/%d", label, done, total)
		if done >= total {
			fmt.Fprint(os.Stderr, "\r"+strings.Repeat(" ", len(label)+24)+"\r")
		}
	}
}

// balTable 打印带边框的表格；单元格里可以有换行，中文按两格宽对齐。
func balTable(title string, header []string, rows [][]string) {
	all := append([][]string{header}, rows...)
	width := make([]int, len(header))
	for _, row := range all {
		for i, cell := range row {
			for _, line := range strings.Split(cell, "\n") {
				width[i] = max(width[i], balance.DisplayWidth(line))
			}
		}
	}
	rule := func(l, m, r string) {
		parts := make([]string, len(width))
		for i, w := range width {
			parts[i] = strings.Repeat("─", w+2)
		}
		fmt.Println(l + strings.Join(parts, m) + r)
	}
	fmt.Println(title)
	rule("┌", "┬", "┐")
	for n, row := range all {
		height := 1
		for _, cell := range row {
			height = max(height, strings.Count(cell, "\n")+1)
		}
		for h := 0; h < height; h++ {
			line := "│"
			for i := range width {
				text := ""
				if i < len(row) {
					if lines := strings.Split(row[i], "\n"); h < len(lines) {
						text = lines[h]
					}
				}
				line += " " + text + strings.Repeat(" ", width[i]-balance.DisplayWidth(text)) + " │"
			}
			fmt.Println(line)
		}
		if n == 0 {
			rule("├", "┼", "┤")
		}
	}
	rule("└", "┴", "┘")
}

var (
	balPlayers = []string{"hero:spear", "hero:shield_bash", "atalanta:shoot", "atalanta:vital_shot", "heracles:club", "heracles:heracles_bow"}
	balEnemies = []string{"wolf", "bandit", "bandit_archer", "bandit_chief", "boar", "lion"}
)

// balHits 读（或先让引擎导出）静态伤害矩阵。
func balHits(a *balArgs, p balance.Paths, export bool) ([]balance.Hit, error) {
	path := filepath.Join(p.Out, "metrics.json")
	if export {
		sim, err := a.simulator()
		if err != nil {
			return nil, err
		}
		if exp, ok := sim.(balance.MetricsExporter); ok {
			data, err := exp.ExportMetrics(p.Tables)
			if err != nil {
				return nil, err
			}
			if err := os.MkdirAll(p.Out, 0o755); err != nil {
				return nil, err
			}
			if err := os.WriteFile(path, data, 0o644); err != nil {
				return nil, err
			}
		} else {
			fmt.Fprintln(os.Stderr, "提示：当前模拟器不能导出伤害矩阵，用已有的 "+path)
		}
	}
	metrics, err := balance.LoadMetrics(path)
	if err != nil {
		return nil, err
	}
	return balance.HitsFrame(metrics), nil
}

func balPrintTTK(p balance.Paths, hits []balance.Hit, scenario string) error {
	var rows [][]string
	for _, key := range balPlayers {
		unit, skill, _ := strings.Cut(key, ":")
		row := []string{key}
		for _, e := range balEnemies {
			h, err := balance.Lookup(hits, unit, skill, e, scenario)
			switch {
			case err != nil:
				row = append(row, "-")
			case math.IsInf(h.HitsToKill, 1):
				row = append(row, "免疫")
			default:
				row = append(row, fmt.Sprintf("%d 下（%d）", int(h.HitsToKill), int(h.Damage)))
			}
		}
		rows = append(rows, row)
	}
	balTable(fmt.Sprintf("几下打死（%s，平地单次命中）", scenario), append([]string{"攻击"}, balEnemies...), rows)
	csv := balance.HitsCSV(hits)
	if runtime.GOOS == "windows" { // pandas 在 Windows 上写 CRLF
		csv = strings.ReplaceAll(csv, "\n", "\r\n")
	}
	return os.WriteFile(filepath.Join(p.Out, "hits.csv"), []byte(csv), 0o644)
}

func balTTK(args []string) error {
	a, err := balParse(args, []string{"scenario"}, []string{"export"})
	if err != nil {
		return err
	}
	p, err := a.paths()
	if err != nil {
		return err
	}
	hits, err := balHits(a, p, a.flag("export", true))
	if err != nil {
		return err
	}
	return balPrintTTK(p, hits, a.str("scenario", "front"))
}

func balCheck(args []string) error {
	a, err := balParse(args, nil, []string{"junit"})
	if err != nil {
		return err
	}
	p, err := a.paths()
	if err != nil {
		return err
	}
	t0 := time.Now()
	cases, err := balance.CheckTables(p)
	if err != nil {
		return err
	}
	hits, err := balHits(a, p, true)
	if err != nil {
		return err
	}
	specs, err := balance.CheckSpecs(p, hits)
	if err != nil {
		return err
	}
	cases = append(cases, specs...)
	failed, xfailed := 0, 0
	for _, c := range cases {
		switch {
		case c.XFail != "":
			xfailed++
		case c.Failed():
			failed++
			fmt.Printf("FAILED %s::%s\n    %s\n", c.Class, c.Name, c.Err)
		}
	}
	fmt.Printf("%d 项通过，%d 项未通过，%d 项已知问题（%.2f 秒）\n", len(cases)-failed-xfailed, failed, xfailed, time.Since(t0).Seconds())
	if a.flag("junit", true) {
		if err := balance.WriteJUnit(filepath.Join(p.Out, "junit-balance.xml"), cases, time.Since(t0)); err != nil {
			return err
		}
	}
	if err := balPrintTTK(p, hits, "front"); err != nil {
		return err
	}
	if failed > 0 {
		os.Exit(1)
	}
	return nil
}

func balSim(args []string) error {
	a, err := balParse(args, []string{"bot", "runs", "seed", "max-rounds"}, nil)
	if err != nil {
		return err
	}
	battle, err := a.battle()
	if err != nil {
		return err
	}
	r, err := a.runner()
	if err != nil {
		return err
	}
	runs, err1 := a.num("runs", 400)
	seed, err2 := a.num("seed", 0)
	maxRounds, err3 := a.num("max-rounds", 30)
	for _, e := range []error{err1, err2, err3} {
		if e != nil {
			return e
		}
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	bot := a.str("bot", "skilled")
	out, err := r.Simulate(ctx, balance.SimRequest{Battle: battle, Bot: bot, Runs: runs, Seed: seed, MaxRounds: maxRounds,
		OnProgress: balProgress(battle+" / "+bot, runs)})
	if err != nil {
		return err
	}
	fmt.Printf("%d 局已写入 %s\n", runs, out)
	return nil
}

// balDoReport 打印判定表并写报告；返回是否有 FAIL。
func balDoReport(p balance.Paths, battle string) (bool, error) {
	df, err := p.LoadRuns(battle, "")
	if err != nil {
		return false, err
	}
	spec, err := balance.LoadSpec(p.TargetsPath(battle))
	if err != nil {
		return false, err
	}
	verdicts, err := balance.Evaluate(df, spec, 0)
	if err != nil {
		return false, err
	}
	var rows [][]string
	failed := false
	for _, v := range verdicts {
		rows = append(rows, []string{v.Bot, v.Label, v.FmtTarget(), v.Estimate.Fmt(v.Pct), v.Status, v.Note})
		failed = failed || v.Status == "FAIL"
	}
	balTable("设计目标："+battle, []string{"机器人", "指标", "目标", "实测（95% 区间）", "结论", "说明"}, rows)
	path, err := p.BuildReport(battle, df, verdicts)
	if err != nil {
		return false, err
	}
	fmt.Println("报告：" + path)
	fmt.Printf("提示：要把胜率的 95%% 区间收窄到 ±5%%，每个机器人约需 %d 局。\n", balance.RunsForMargin(0.05, 0.5, 0.95))
	return failed, nil
}

func balReport(args []string) error {
	a, err := balParse(args, nil, nil)
	if err != nil {
		return err
	}
	battle, err := a.battle()
	if err != nil {
		return err
	}
	p, err := a.paths()
	if err != nil {
		return err
	}
	failed, err := balDoReport(p, battle)
	if err != nil {
		return err
	}
	if failed {
		os.Exit(1)
	}
	return nil
}

func balRun(args []string) error {
	a, err := balParse(args, []string{"runs", "seed"}, []string{"full"})
	if err != nil {
		return err
	}
	battle, err := a.battle()
	if err != nil {
		return err
	}
	r, err := a.runner()
	if err != nil {
		return err
	}
	runs, err1 := a.num("runs", 400)
	seed, err2 := a.num("seed", 0)
	if err1 != nil || err2 != nil {
		return fmt.Errorf("%v %v", err1, err2)
	}
	spec, err := balance.LoadSpec(r.Paths.TargetsPath(battle))
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	bots := spec.BotNames()
	if a.flag("full", false) {
		for _, bot := range bots {
			if _, err := r.Simulate(ctx, balance.SimRequest{Battle: battle, Bot: bot, Runs: runs, Seed: seed,
				OnProgress: balProgress(battle+" / "+bot, runs)}); err != nil {
				return err
			}
		}
	} else {
		used, err := r.RunUntilDecided(ctx, balance.DecideRequest{Battle: battle, Bots: bots, MaxRuns: runs, Seed: seed, Spec: spec,
			OnProgress: balProgress(battle, runs*len(bots))})
		if err != nil {
			return err
		}
		parts := make([]string, len(bots))
		for i, b := range bots {
			parts[i] = fmt.Sprintf("%s %d 局", b, used[b])
		}
		fmt.Printf("用了 %s（上限各 %d 局，省下 %s）\n", strings.Join(parts, "、"), runs,
			balance.Pct0(balance.PredictedRunsSaved(used, runs)))
	}
	failed, err := balDoReport(r.Paths, battle)
	if err != nil {
		return err
	}
	if failed {
		os.Exit(1)
	}
	return nil
}

func balSweep(args []string) error {
	a, err := balParse(args, []string{"set", "bots", "runs", "first", "seed"}, nil)
	if err != nil {
		return err
	}
	battle, err := a.battle()
	if err != nil {
		return err
	}
	if len(a.vals["set"]) == 0 {
		return fmt.Errorf("至少要有一个 --set 表:键.路径=v1,v2,…  例如 --set units:heracles.str=16,18")
	}
	var axes []balance.Axis
	for _, g := range a.vals["set"] {
		axis, err := balance.ParseAxis(g)
		if err != nil {
			return err
		}
		axes = append(axes, axis)
	}
	r, err := a.runner()
	if err != nil {
		return err
	}
	runs, err1 := a.num("runs", 400)
	first, err2 := a.num("first", 40)
	seed, err3 := a.num("seed", 0)
	for _, e := range []error{err1, err2, err3} {
		if e != nil {
			return e
		}
	}
	spec, err := balance.LoadSpec(r.Paths.TargetsPath(battle))
	if err != nil {
		return err
	}
	var bots []string
	for _, b := range strings.Split(a.str("bots", ""), ",") {
		if b != "" {
			bots = append(bots, b)
		}
	}
	if len(bots) == 0 {
		bots = spec.BotNames()
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	rows, err := r.Race(ctx, battle, axes, bots, runs, first, seed, func(s string) { fmt.Println(s) })
	if err != nil {
		return err
	}
	header := []string{"组合", "局数"}
	for _, v := range rows[0].Verdicts {
		header = append(header, v.Bot+"\n"+v.Label+"\n"+v.FmtTarget())
	}
	header = append(header, "偏离目标")
	var table [][]string
	total := 0
	for _, row := range rows {
		note := ""
		if row.EliminatedAt != 0 {
			note = fmt.Sprintf("（%d 局后淘汰）", row.EliminatedAt)
		}
		line := []string{row.Label, strconv.Itoa(row.Runs) + note}
		for _, v := range row.Verdicts {
			line = append(line, v.Estimate.Fmt(v.Pct)+" "+v.Status)
		}
		table = append(table, append(line, fmt.Sprintf("%.2f", row.Loss[0])))
		total += row.Runs
	}
	balTable(fmt.Sprintf("参数扫描：%s（最好的在最上面）", battle), header, table)
	fmt.Printf("共模拟 %d 局；全部跑满需要 %d 局。被淘汰的组合样本少，区间宽，只用于排除。\n",
		total*len(bots), len(rows)*runs*len(bots))

	eff, err := r.Effects(battle, rows, axes)
	if err != nil {
		return err
	}
	if len(eff) > 0 {
		var lines [][]string
		for _, e := range eff {
			f := func(x float64) string { return fmt.Sprintf("%+.2f 回合", x) }
			name := "胜局回合数"
			if e.Outcome == "win_rate" {
				f = func(x float64) string { return fmt.Sprintf("%+.1f 个百分点", x*100) }
				name = "胜率"
			}
			_, param, _ := strings.Cut(e.Parameter, ":")
			lines = append(lines, []string{e.Bot, name, param, f(e.Effect), f(e.Lo) + " 至 " + f(e.Hi)})
		}
		balTable("每个参数的影响（合并所有组合的数据估计）", []string{"机器人", "指标", "参数 +1", "变化", "95% 区间"}, lines)
	}
	return nil
}

func balStudio(args []string) error {
	a, err := balParse(args, []string{"port", "rules", "rules-ext"}, []string{"open"})
	if err != nil {
		return err
	}
	r, err := a.runner()
	if err != nil {
		return err
	}
	port, err := a.num("port", 8765)
	if err != nil {
		return err
	}
	cfg := studio.Config{Paths: r.Paths, Sim: r.Sim, Workers: r.Workers}
	// 规则哈希的来源：默认是 engine/rules、engine/bots、engine/sim；--rules 可以换成别的目录
	if dirs := a.str("rules", os.Getenv("SRPG_RULES")); dirs != "" {
		ext := a.str("rules-ext", ".go")
		for _, d := range strings.Split(dirs, ",") {
			if d = strings.TrimSpace(d); d == "" {
				continue
			}
			if !filepath.IsAbs(d) {
				d = filepath.Join(r.Paths.Project, d)
			}
			if _, err := os.Stat(d); err != nil {
				return fmt.Errorf("--rules 里的目录不存在：%s", d)
			}
			cfg.Rules = append(cfg.Rules, studio.RulesSource{Dir: d, Ext: ext})
		}
	}
	if _, err := os.Stat(r.Paths.WebDist); err != nil {
		fmt.Println("网页还没有构建：在 balance/web 下运行 `npm install && npm run build`")
	}
	url := fmt.Sprintf("http://127.0.0.1:%d", port)
	fmt.Println("Balance Studio：" + url)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	if a.flag("open", true) {
		time.AfterFunc(time.Second, func() { balOpenBrowser(url) })
	}
	return studio.New(cfg).Serve(ctx, fmt.Sprintf("127.0.0.1:%d", port))
}

func balOpenBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	case "darwin":
		cmd = exec.Command("open", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	cmd.Start()
}
