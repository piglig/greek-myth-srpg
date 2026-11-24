package balance

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	oj "srpg/balance/ordjson"
	"srpg/balance/schema"
)

// --- 目标判定（tests/test_stats.py）-------------------------------------------------------------

func runsOf(bot string, wins, n int) Frame {
	rows := make([]Run, n)
	for i := range rows {
		r := Run{Bot: bot, Win: i < wins, Result: "loss_hero",
			Num: map[string]float64{"rounds": 8, "party_hp_left": 0.5, "counts.fall_enemy": 1, "counts.throw": 1}}
		if r.Win {
			r.Result = "win"
		}
		rows[i] = r
	}
	return NewFrame(rows)
}

func specOf(t *testing.T, yaml string) *Spec {
	t.Helper()
	v, err := YAMLToValue([]byte(yaml))
	if err != nil {
		t.Fatal(err)
	}
	s, err := SpecFromObject(v.(*oj.Object))
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestVerdictsUseTheInterval(t *testing.T) {
	spec := specOf(t, "runs_min: 100\nbots: {skilled: {win_rate: [0.70, 0.90]}}")
	for wins, want := range map[int]string{320: "PASS", 100: "FAIL", 283: "INCONCLUSIVE"} {
		vs, err := Evaluate(runsOf("skilled", wins, 400), spec, 0)
		if err != nil || vs[0].Status != want {
			t.Errorf("%d 胜：%v %+v，期望 %s", wins, err, vs, want)
		}
	}
}

func TestTooFewRunsIsInconclusive(t *testing.T) {
	spec := specOf(t, "runs_min: 200\nbots: {skilled: {win_rate: [0.70, 0.90]}}")
	vs, _ := Evaluate(runsOf("skilled", 80, 100), spec, 0)
	if vs[0].Status != "INCONCLUSIVE" || vs[0].Note != "样本 100 < 200" {
		t.Fatalf("%+v", vs[0])
	}
}

func TestKnownIssueReportsKnownInsteadOfFail(t *testing.T) {
	spec := specOf(t, "runs_min: 100\nbots: {skilled: {win_rate: {range: [0.7, 0.9], known_issue: x}}}")
	vs, _ := Evaluate(runsOf("skilled", 50, 400), spec, 0)
	if vs[0].Status != "KNOWN" || vs[0].Note != "x" {
		t.Fatalf("%+v", vs[0])
	}
}

func TestNoDataAndUnknownMetric(t *testing.T) {
	spec := specOf(t, "bots: {novice: {win_rate: [0.3, 0.6]}}")
	vs, _ := Evaluate(runsOf("skilled", 50, 400), spec, 0)
	if vs[0].Status != "NO_DATA" || vs[0].Note != "没有 novice 的模拟结果" || spec.RunsMin != 100 {
		t.Fatalf("%+v", vs[0])
	}
	if _, err := Evaluate(runsOf("novice", 1, 2), specOf(t, "bots: {novice: {nope: [0, 1]}}"), 0); err == nil {
		t.Fatal("未知指标应当报错")
	}
}

func TestTargetFilesLoadAndDumpLikePyYAML(t *testing.T) {
	root, err := FindProject()
	if err != nil {
		t.Skip(err)
	}
	spec, err := LoadSpec(NewPaths(root).TargetsPath("1-4"))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(spec.BotNames(), []string{"skilled", "novice"}) || spec.RunsMin != 50 || spec.Raw.Str("battle", "") != "1-4" {
		t.Fatalf("1-4.yaml 读成了 %+v", spec)
	}
	body := oj.Obj("battle", "1-4", "runs_min", 50, "bots", oj.Obj("skilled", oj.Obj(
		"win_rate", []any{0.7, 0.95}, "rounds_p50", oj.Obj("range", []any{6, 10}, "known_issue", "已知：偏快 #1"))))
	want := "battle: 1-4\nruns_min: 50\nbots:\n  skilled:\n    win_rate:\n    - 0.7\n    - 0.95\n    rounds_p50:\n      range:\n      - 6\n      - 10\n      known_issue: '已知：偏快 #1'\n"
	if got := DumpYAML(body); got != want {
		t.Fatalf("DumpYAML =\n%s期望\n%s", got, want)
	}
	// 参考输出来自 yaml.safe_dump(…, allow_unicode=True, sort_keys=False)
	odd := oj.Obj("battle", "12", "a b", "x: y", "n", nil, "t", true, "f", 1e-7, "big", 1e16, "s", "yes", "e", "",
		"d", "2026-11-20", "l", []any{}, "neg", "-5", "dash", "- x", "empty", oj.NewObject())
	wantOdd := `battle: '12'
a b: 'x: y'
n: null
t: true
f: 1.0e-07
big: 1.0e+16
s: 'yes'
e: ''
d: '2026-11-20'
l: []
neg: '-5'
dash: '- x'
empty: {}
`
	if got := DumpYAML(odd); got != wantOdd {
		t.Fatalf("DumpYAML =\n%s期望\n%s", got, wantOdd)
	}
	back, err := YAMLToValue([]byte(DumpYAML(body)))
	if err != nil || oj.Dump(back, oj.Compact) != oj.Dump(body, oj.Compact) {
		t.Fatalf("读回来不一样：%v %s", err, oj.Dump(back, oj.Compact))
	}
}

// --- 模拟落盘、序贯停止、逐轮减半、参数影响 -----------------------------------------------------

func TestKeepsCompleteRecordsAndDropsHalfWrittenTail(t *testing.T) {
	part := filepath.Join(t.TempDir(), "part-00-a0.jsonl")
	os.WriteFile(part, []byte("{\"seed\": 0}\n{\"seed\": 1}\n{\"seed\": 2, \"res"), 0o644)
	if n, err := KeepCompleteLines(part); n != 2 || err != nil {
		t.Fatalf("n = %d, err = %v", n, err)
	}
	if data, _ := os.ReadFile(part); string(data) != "{\"seed\": 0}\n{\"seed\": 1}\n" {
		t.Fatalf("文件内容 = %q", data)
	}
}

func TestMissingPartCountsAsZero(t *testing.T) {
	if n, err := KeepCompleteLines(filepath.Join(t.TempDir(), "nope.jsonl")); n != 0 || err != nil {
		t.Fatalf("n = %d, err = %v", n, err)
	}
}

func TestLooksFor(t *testing.T) {
	for max, want := range map[int][]int{400: {50, 100, 200, 400}, 120: {50, 100, 120}, 50: {50}, 30: {30}, 1000: {50, 100, 200, 400, 1000}} {
		if got := LooksFor(max); !reflect.DeepEqual(got, want) {
			t.Errorf("LooksFor(%d) = %v，期望 %v", max, got, want)
		}
	}
}

func tempRunner(t *testing.T, sim Simulator, targets string) *Runner {
	p := NewPaths(t.TempDir())
	if targets != "" {
		os.MkdirAll(p.Targets, 0o755)
		os.WriteFile(p.TargetsPath("1-4"), []byte(targets), 0o644)
	}
	return &Runner{Paths: p, Sim: sim}
}

func TestSimulateWritesAndAppendsRuns(t *testing.T) {
	fake := &FakeSimulator{}
	r := tempRunner(t, fake, "")
	ctx := context.Background()
	total := 0
	path, err := r.Simulate(ctx, SimRequest{Battle: "1-4", Bot: "skilled", Runs: 30, OnProgress: func(n int) { total += n }})
	if err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(filepath.Dir(path), "meta.json"), []byte("{}"), 0o644)
	if _, err := r.Simulate(ctx, SimRequest{Battle: "1-4", Bot: "skilled", Runs: 20, Seed: 30, Append: true}); err != nil {
		t.Fatal(err)
	}
	df, err := r.Paths.LoadRuns("1-4", "")
	if err != nil || df.Len() != 50 || total != 30 {
		t.Fatalf("行数 %d，进度 %d，err %v", df.Len(), total, err)
	}
	for i, row := range df.Rows {
		if int(row.Num["seed"]) != i {
			t.Fatalf("第 %d 行的种子是 %v", i, row.Num["seed"])
		}
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(path), "meta.json")); err == nil {
		t.Error("重新模拟后旧的 meta.json 应当被删除")
	}
	if calls := fake.Calls(); calls[1].SeedFrom != 30 || calls[1].Count != 20 || calls[0].MaxRounds != 30 || calls[0].TablesDir != r.Paths.Tables {
		t.Errorf("传给模拟器的参数不对：%+v", calls)
	}
	// 不追加时覆盖
	r.Simulate(ctx, SimRequest{Battle: "1-4", Bot: "skilled", Runs: 5})
	if df, _ := r.Paths.LoadRuns("1-4", ""); df.Len() != 5 {
		t.Errorf("覆盖后行数 = %d", df.Len())
	}
	if _, err := r.Paths.LoadRuns("9-9", ""); err == nil {
		t.Error("没有结果时应当报错")
	}
}

func TestFileSimulatorReplaysExistingRuns(t *testing.T) {
	src := tempRunner(t, &FakeSimulator{}, "")
	if _, err := src.Simulate(context.Background(), SimRequest{Battle: "1-4", Bot: "novice", Runs: 40}); err != nil {
		t.Fatal(err)
	}
	r := tempRunner(t, FileSimulator{Dir: filepath.Join(src.Paths.Out, "sim")}, "")
	if _, err := r.Simulate(context.Background(), SimRequest{Battle: "1-4", Bot: "novice", Runs: 10, Seed: 25}); err != nil {
		t.Fatal(err)
	}
	a, _ := os.ReadFile(filepath.Join(src.Paths.RunDir("1-4", "novice", ""), "runs.jsonl"))
	b, _ := os.ReadFile(filepath.Join(r.Paths.RunDir("1-4", "novice", ""), "runs.jsonl"))
	if want := strings.Join(strings.SplitAfter(string(a), "\n")[25:35], ""); string(b) != want {
		t.Error("文件模拟器应当原样返回种子 25–34 的行")
	}
	if _, err := r.Simulate(context.Background(), SimRequest{Battle: "1-4", Bot: "novice", Runs: 10, Seed: 35}); err == nil {
		t.Error("种子超出已有结果时应当报错")
	}
}

func TestRunUntilDecidedStopsEarly(t *testing.T) {
	targets := "battle: \"1-4\"\nruns_min: 50\nbots:\n  skilled:\n    win_rate: [0.60, 0.99]\n  novice:\n    win_rate: [0.40, 0.60]\n"
	fake := &FakeSimulator{WinRate: func(o SimOptions) float64 {
		if o.Bot == "novice" {
			return 0.60 // 正好在上限：到 400 局也定不下来
		}
		return 0.85
	}}
	r := tempRunner(t, fake, targets)
	progress := 0
	used, err := r.RunUntilDecided(context.Background(), DecideRequest{Battle: "1-4", Bots: []string{"skilled", "novice", "other"},
		MaxRuns: 400, OnProgress: func(n int) { progress += n }})
	if err != nil {
		t.Fatal(err)
	}
	if used["skilled"] != 50 || used["novice"] != 400 || used["other"] != 400 {
		t.Fatalf("used = %v", used)
	}
	if progress != 1200 {
		t.Errorf("进度合计 %d，应为 1200（跳过的局也要算进去）", progress)
	}
	if got := PredictedRunsSaved(used, 400); got < 0.29 || got > 0.30 {
		t.Errorf("省下 %v", got)
	}
	var counts []int
	for _, c := range fake.Calls() {
		if c.Bot == "novice" {
			counts = append(counts, c.Count)
		}
	}
	if !reflect.DeepEqual(counts, []int{50, 50, 100, 200}) {
		t.Errorf("新手的批次 = %v", counts)
	}
	// 取消：不再开新的批次
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	used, _ = tempRunner(t, fake, targets).RunUntilDecided(ctx, DecideRequest{Battle: "1-4", Bots: []string{"skilled"}})
	if used["skilled"] != 0 {
		t.Errorf("取消后 used = %v", used)
	}
}

func TestLoss(t *testing.T) {
	vs := []Verdict{
		{Lo: 0.7, Hi: 0.9, Estimate: Estimate{Value: 0.95, N: 10}}, // 偏出 0.05 / 0.2
		{Lo: 6, Hi: 10, Estimate: Estimate{Value: 8, N: 10}},       // 正中
		{Lo: 0, Hi: 1, Estimate: Estimate{N: 0}},                   // 没有样本：算 1
	}
	if got := Loss(vs); got != [2]float64{1.25, 0.75} {
		t.Fatalf("Loss = %v", got)
	}
}

func overrideValue(o SimOptions, key string) float64 {
	for _, s := range o.Overrides {
		if k, v, _ := strings.Cut(s, "="); k == key {
			return map[string]float64{"14": 14, "16": 16, "18": 18, "20": 20}[v]
		}
	}
	return 0
}

func TestRaceAndEffects(t *testing.T) {
	targets := "battle: \"1-4\"\nruns_min: 50\nbots:\n  skilled:\n    win_rate: [0.70, 0.90]\n"
	// 力量越高胜率越高：14 → 50%，16 → 65%，18 → 80%，20 → 95%
	fake := &FakeSimulator{WinRate: func(o SimOptions) float64 { return 0.5 + (overrideValue(o, "units:heracles.str")-14)*0.075 }}
	r := tempRunner(t, fake, targets)
	axis, err := ParseAxis("units:heracles.str=14, 16,18,20")
	if err != nil || !reflect.DeepEqual(axis.Values, []string{"14", "16", "18", "20"}) {
		t.Fatalf("ParseAxis: %+v %v", axis, err)
	}
	if _, err := ParseAxis("units:heracles.str"); err == nil {
		t.Fatal("没有取值应当报错")
	}
	var logs []string
	rows, err := r.Race(context.Background(), "1-4", []Axis{axis}, []string{"skilled"}, 400, 40, 0, func(s string) { logs = append(logs, s) })
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 4 || rows[0].Label != "heracles.str=18" || rows[0].Variant != "units.heracles.str=18" || rows[0].EliminatedAt != 0 {
		t.Fatalf("最好的应当是 18：%+v", rows[0])
	}
	if rows[1].EliminatedAt != 0 || rows[2].EliminatedAt != 40 || rows[3].EliminatedAt != 40 || rows[2].Runs != 40 {
		t.Errorf("淘汰轮次不对：%d %d %d", rows[1].EliminatedAt, rows[2].EliminatedAt, rows[3].EliminatedAt)
	}
	if rows[0].Runs < 50 || len(rows[0].Verdicts) != 1 || len(logs) != 2 || !strings.HasPrefix(logs[0], "40 局后：") {
		t.Errorf("决赛局数 %d，日志 %v", rows[0].Runs, logs)
	}
	df, _ := r.Paths.LoadRuns("1-4", rows[0].Variant)
	if df.Len() != rows[0].Runs {
		t.Errorf("磁盘上 %d 局，记录 %d 局", df.Len(), rows[0].Runs)
	}
	eff, err := r.Effects("1-4", rows, []Axis{axis, {Key: "units:wolf.str", Values: []string{"9"}}, {Key: "units:x.kind", Values: []string{"a", "b"}}})
	if err != nil || len(eff) != 2 {
		t.Fatalf("Effects: %v %+v", err, eff)
	}
	if e := eff[0]; e.Outcome != "win_rate" || e.Parameter != "units:heracles.str" || e.Effect < 0.04 || e.Effect > 0.11 || !(e.Lo < e.Effect && e.Effect < e.Hi) {
		t.Errorf("胜率影响应当在每点 +7.5 个百分点左右：%+v", e)
	}
	if eff[1].Outcome != "rounds" {
		t.Errorf("%+v", eff[1])
	}
}

// 参考值：scipy.stats.t.ppf(0.975, df)
func TestStudentTPPF(t *testing.T) {
	for df, want := range map[float64]float64{1: 12.706204736174694, 5: 2.5705818356363146, 30: 2.0422724563012378, 397: 1.965957427966824} {
		approx(t, "t.ppf", StudentTPPF(0.975, df), want, 1e-9)
	}
}

// --- 数据表和静态规格（tests/test_data_tables.py、tests/test_static_specs.py）--------------------

func TestDataTablesAndStaticSpecs(t *testing.T) {
	root, err := FindProject()
	if err != nil {
		t.Skip(err)
	}
	p := NewPaths(root)
	cases, err := CheckTables(p)
	if err != nil {
		t.Fatal(err)
	}
	if len(cases) < 8 {
		t.Fatalf("只有 %d 项数据表检查", len(cases))
	}
	metrics, err := LoadMetrics(filepath.Join(p.Out, "metrics.json"))
	if err != nil {
		t.Logf("跳过静态规格：%v", err)
	} else {
		hits := HitsFrame(metrics)
		specs, err := CheckSpecs(p, hits)
		if err != nil {
			t.Fatal(err)
		}
		cases = append(cases, specs...)
		if h, err := Lookup(hits, "hero", "spear", "hero", "front"); err != nil || h.Damage != 6 || h.HitsToKill != 7 || h.HPFraction != 0.15 {
			t.Errorf("hero:spear -> hero = %+v %v", h, err)
		}
		if _, err := Lookup(hits, "hero", "nope", "hero", "front"); err == nil {
			t.Error("查不到应当报错")
		}
		// 行的顺序跟着导出时单位表的顺序走，所以只认表头和主角那一行在不在。
		if csv := HitsCSV(hits); !strings.HasPrefix(csv, "\xef\xbb\xbfattacker,damage,immune,relation,scenario,skill,target,target_hp,target_max_hp,hits_to_kill,hp_fraction\n") ||
			!strings.Contains(csv, "\nhero,6,False,0,front,spear,hero,40,40,7.0,0.15\n") {
			t.Errorf("hits.csv 不对：%q", csv[:160])
		}
	}
	xfail := 0
	for _, c := range cases {
		if c.Failed() {
			t.Errorf("%s: %s", c.Name, c.Err)
		}
		if c.XFail != "" {
			xfail++
		}
	}
	t.Logf("%d 项检查，其中 %d 项是已知问题", len(cases), xfail)
	out := filepath.Join(t.TempDir(), "junit.xml")
	if err := WriteJUnit(out, cases, 0); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(out); !strings.Contains(string(data), `<testcase classname="tests.test_data_tables" name="test_table_matches_schema[units-units]"`) {
		t.Error("JUnit 文件里没有预期的用例")
	}
}

// 报错文字要和 Python jsonschema 一样（参考值由 jsonschema 4.26 生成）。
func TestSchemaMessagesMatchJsonschema(t *testing.T) {
	sch, _ := oj.ParseObject([]byte(`{"type":"object","required":["id","n"],"additionalProperties":false,"properties":{
		"id":{"type":"string","pattern":"^[a-z]+$","minLength":2},"n":{"type":"integer","minimum":1,"maximum":3},
		"m":{"type":"number","exclusiveMinimum":0},"team":{"enum":["player","enemy"]},"k":{"const":"x"},
		"pos":{"type":"array","items":{"type":"integer","minimum":0},"minItems":2,"maxItems":2,"uniqueItems":true},
		"node":{"type":"object","oneOf":[{"required":["trait"]},{"required":["skill"]}]},
		"names":{"type":"object","minProperties":1,"propertyNames":{"pattern":"^[a-z]+$"},"additionalProperties":{"type":"string"}}}}`))
	inst, _ := oj.Parse([]byte(`{"id":"A","n":7,"m":0,"team":"x","k":1.5,"pos":[1,1,-2,"a"],"node":{"other":true},
		"names":{"Bad":1},"zzz":null,"aaa":[]}`))
	want := []string{
		"|Additional properties are not allowed ('aaa', 'zzz' were unexpected)",
		"id|'A' does not match '^[a-z]+$'",
		"id|'A' is too short",
		"n|7 is greater than the maximum of 3",
		"m|0 is less than or equal to the minimum of 0",
		"team|'x' is not one of ['player', 'enemy']",
		"k|'x' was expected",
		"pos.2|-2 is less than the minimum of 0",
		"pos.3|'a' is not of type 'integer'",
		"pos|[1, 1, -2, 'a'] is too long",
		"pos|[1, 1, -2, 'a'] has non-unique elements",
		"node|{'other': True} is not valid under any of the given schemas",
		"names|'Bad' does not match '^[a-z]+$'",
		"names.Bad|1 is not of type 'string'",
	}
	var got []string
	for _, e := range schema.Validate(inst, sch) {
		got = append(got, e.PathString()+"|"+e.Message)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("iter_errors 不一致：\n得到 %s\n期望 %s", strings.Join(got, "\n     "), strings.Join(want, "\n     "))
	}
	if best := schema.Best(inst, sch); best == nil || best.Message != "Additional properties are not allowed ('aaa', 'zzz' were unexpected)" {
		t.Errorf("best_match = %+v", best)
	}
	if e := schema.Best(oj.Obj("n", 2), sch); e == nil || e.Message != "'id' is a required property" {
		t.Errorf("best_match = %+v", e)
	}
	if e := schema.Validate(oj.Obj("id", "ab", "n", 2, "pos", []any{}, "names", oj.NewObject()), sch); len(e) != 2 ||
		e[0].Message != "[] is too short" || e[1].Message != "{} should be non-empty" {
		t.Errorf("得到 %+v", e)
	}
}

func TestReportHTML(t *testing.T) {
	p := NewPaths(filepath.Join("testdata", "project"))
	df, err := p.LoadRuns("1-4", "")
	if err != nil {
		t.Fatal(err)
	}
	spec, _ := LoadSpec(p.TargetsPath("1-4"))
	vs, _ := Evaluate(df, spec, 0)
	p.Out = t.TempDir()
	path, err := p.BuildReport("1-4", df, vs)
	if err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	html := string(data)
	for _, want := range []string{"<h1>平衡报告：1-4</h1>", "skilled 50 局", "<td>胜率</td><td>70%–95%</td><td>84%（71%–92%）</td>",
		"战斗结果", "胜局回合数分布", "对敌伤害来源（每局平均）", "我方各单位造成伤害（每局）"} {
		if !strings.Contains(html, want) {
			t.Errorf("报告里没有 %q", want)
		}
	}
	if strings.Count(html, "<svg") != 6 || strings.Contains(html, "<script") {
		t.Errorf("应当有 6 张内嵌 SVG 图且没有脚本，实际 %d 张", strings.Count(html, "<svg"))
	}
}
