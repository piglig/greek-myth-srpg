package studio

import (
	"bufio"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"srpg/balance"
	oj "srpg/balance/ordjson"
)

// sandbox 复制一份数据表到临时目录，配一个空的工作区，测试不会碰真实数据。
func sandbox(t *testing.T) balance.Paths {
	t.Helper()
	root, err := balance.FindProject()
	if err != nil {
		t.Skip(err)
	}
	real := balance.NewPaths(root)
	tmp := t.TempDir()
	p := real
	p.Tables = filepath.Join(tmp, "tables")
	p.Out = filepath.Join(tmp, "out")
	p.Workspace = filepath.Join(tmp, "workspace")
	p.Targets = filepath.Join(tmp, "targets")
	p.WebDist = filepath.Join(tmp, "dist")
	if err := os.CopyFS(p.Tables, os.DirFS(real.Tables)); err != nil {
		t.Fatal(err)
	}
	return p
}

func must[T any](v T, err error) T {
	if err != nil {
		panic(err)
	}
	return v
}

func isUserErr(err error) bool {
	_, ok := err.(*Error)
	return ok
}

func battleOf(t *testing.T, ws *Workspace, variant, id string) *oj.Object {
	t.Helper()
	return oj.DeepCopy(must(ws.Load(variant)).Battles.Object(id)).(*oj.Object)
}

func unit(b *oj.Object, id string) *oj.Object {
	for _, v := range b.Array("units") {
		if u := v.(*oj.Object); u.Str("id", "") == id {
			return u
		}
	}
	return nil
}

func messages(issues []*oj.Object) map[string]*oj.Object {
	out := map[string]*oj.Object{}
	for _, i := range issues {
		out[i.Str("message", "")] = i
	}
	return out
}

func TestBaselineIsValidAndReadOnly(t *testing.T) {
	ws := NewWorkspace(sandbox(t))
	data := must(ws.Load(""))
	for _, i := range must(ws.Validate(data)) {
		if i.Str("level", "") == "error" {
			t.Errorf("基线有错误：%s", oj.Dump(i, oj.Default))
		}
	}
	if _, err := ws.SaveBattle("baseline", "1-4", data.Battles.Object("1-4"), "human", ""); !isUserErr(err) {
		t.Fatalf("基线应当只读，得到 %v", err)
	}
}

func TestVariantOverlaysOnlyWhatChanged(t *testing.T) {
	ws := NewWorkspace(sandbox(t))
	must(ws.CreateVariant("v1", "", "human", ""))
	battle := battleOf(t, ws, "v1", "1-4")
	baseHash := ws.BattleHash(must(ws.Load("")), "1-4")
	battle.Array("units")[0].(*oj.Object).Set("pos", []any{6, 12})
	if issues := must(ws.SaveBattle("v1", "1-4", battle, "ai", "")); len(issues) != 0 {
		t.Fatalf("不应有问题：%v", messages(issues))
	}
	if got := must(ws.ChangedFiles("v1")); !reflect.DeepEqual(got, []string{"battles/1-4"}) {
		t.Fatalf("changed = %v", got)
	}
	if pos := oj.PyRepr(must(ws.Load("")).Battles.Object("1-4").Array("units")[0].(*oj.Object).Get("pos")); pos != "[5, 12]" {
		t.Fatalf("基线被改了：%s", pos)
	}
	if ws.BattleHash(must(ws.Load("v1")), "1-4") == baseHash {
		t.Fatal("旧布局的模拟结果应当过期")
	}
	if got := oj.Dump(objList(must(ws.Diff("v1"))), oj.Default); got != `[{"file": "battles/1-4", "lines": ["hero 从 (5, 12) 移到 (6, 12)"]}]` {
		t.Fatalf("diff = %s", got)
	}
	if act := must(ws.Activity(80)); act[0].(*oj.Object).Str("actor", "") != "ai" {
		t.Fatalf("最新动态应当是 ai 的：%s", oj.Dump(act[0], oj.Default))
	}
	// 把基线内容存回去，覆盖文件就又没了
	must(ws.SaveBattle("v1", "1-4", must(ws.Load("")).Battles.Object("1-4"), "human", ""))
	if got := must(ws.ChangedFiles("v1")); len(got) != 0 {
		t.Fatalf("changed = %v", got)
	}
}

func TestValidationReportsOverlapAndOutOfBoundsWithCells(t *testing.T) {
	ws := NewWorkspace(sandbox(t))
	must(ws.CreateVariant("v1", "", "human", ""))
	battle := battleOf(t, ws, "", "1-4")
	unit(battle, "wolf_1").Set("pos", []any{5, 12}) // 踩在主角身上
	unit(battle, "boar_w").Set("pos", []any{11, 2}) // 2×2 伸出东边
	msgs := messages(must(ws.SaveBattle("v1", "1-4", battle, "human", "")))
	if got := oj.Dump(msgs["wolf_1 与 hero 重叠"].Get("cells"), oj.Default); got != "[[5, 12]]" {
		t.Fatalf("重叠格 = %s（全部问题：%v）", got, msgs)
	}
	if msgs["boar_w 超出地图范围"] == nil {
		t.Fatalf("缺少越界问题：%v", msgs)
	}
	if _, err := ws.Adopt("v1", "human"); !isUserErr(err) {
		t.Fatalf("有错误的变体不能采用，得到 %v", err)
	}
}

func TestStatEditAndAdopt(t *testing.T) {
	ws := NewWorkspace(sandbox(t))
	must(ws.CreateVariant("v1", "", "human", ""))
	units := oj.DeepCopy(must(ws.Load("")).Units).(*oj.Object)
	units.Object("wolf").Set("hp", 15)
	must(ws.SaveTable("v1", "units", units, "human", ""))
	if got := oj.Dump(must(ws.Diff("v1"))[0].Get("lines"), oj.Default); got != `["wolf.hp：16 → 15"]` {
		t.Fatalf("diff = %s", got)
	}
	if got := must(ws.Adopt("v1", "human")); !reflect.DeepEqual(got, []string{"units"}) {
		t.Fatalf("adopt = %v", got)
	}
	if hp := must(ws.Load("")).Units.Object("wolf").Int("hp", 0); hp != 15 {
		t.Fatalf("基线 wolf.hp = %d", hp)
	}
	if vs := must(ws.ListVariants()); len(vs) != 0 {
		t.Fatalf("变体应当已删除：%v", vs)
	}
}

func newBattle() *oj.Object {
	return oj.Obj("id", "9-9", "title", "新关卡", "heights", []any{"000", "000", "000"}, "units", []any{
		oj.Obj("def", "hero", "id", "hero", "team", "player", "pos", []any{1, 2}),
		oj.Obj("def", "wolf", "id", "wolf_1", "team", "enemy", "pos", []any{1, 0})})
}

func TestNewBattleExistsOnlyInTheVariant(t *testing.T) {
	ws := NewWorkspace(sandbox(t))
	must(ws.CreateVariant("v1", "", "human", ""))
	if issues := must(ws.SaveBattle("v1", "9-9", newBattle(), "human", "")); len(issues) != 0 {
		t.Fatalf("不应有问题：%v", messages(issues))
	}
	if !must(ws.Load("v1")).Battles.Has("9-9") || must(ws.Load("")).Battles.Has("9-9") {
		t.Fatal("新关卡应当只在变体里")
	}
	// 不符合 schema 的表被拒绝
	_, err := ws.SaveTable("v1", "units", oj.Obj("wolf", oj.Obj("name", "x")), "human", "")
	if !isUserErr(err) {
		t.Fatalf("应当拒绝，得到 %v", err)
	}
	if !strings.HasPrefix(err.Error(), "units 不合法（wolf）：'") || !strings.HasSuffix(err.Error(), "' is a required property") {
		t.Errorf("报错文字应与 jsonschema 一致：%s", err)
	}
}

func TestBadNamesAndActivityLimit(t *testing.T) {
	ws := NewWorkspace(sandbox(t))
	if _, err := ws.CreateVariant("../x", "", "human", ""); err == nil || err.Error() != "变体名称无效：'../x'（只能用字母、数字、中文、- 和 _）" {
		t.Fatalf("得到 %v", err)
	}
	must(ws.CreateVariant("试验_1", "备注", "ai", ""))
	if _, err := ws.CreateVariant("试验_1", "", "human", ""); !isUserErr(err) {
		t.Fatalf("重名应当报错，得到 %v", err)
	}
	line := strings.TrimSpace(string(must(os.ReadFile(ws.activityPath()))))
	if !strings.HasSuffix(line, `"actor": "ai", "kind": "variant", "text": "新建变体「试验_1」：备注", "variant": "试验_1"}`) {
		t.Errorf("动态日志的格式应与 Python 的 json.dumps 一致：%s", line)
	}
	meta := string(must(os.ReadFile(filepath.Join(ws.variantsDir(), "试验_1", "meta.json"))))
	if !strings.HasPrefix(meta, "{\n  \"name\": \"试验_1\",\n  \"note\": \"备注\",\n  \"created\": \"") || !strings.HasSuffix(meta, "\"by\": \"ai\"\n}\n") {
		t.Errorf("meta.json 的格式应与 Python 的 indent=2 一致：%q", meta)
	}
	if err := ws.DeleteVariant("试验_1", "human"); err != nil {
		t.Fatal(err)
	}
	if n := len(must(ws.Activity(1))); n != 1 {
		t.Errorf("limit=1 得到 %d 条", n)
	}
	if n := len(must(ws.Activity(80))); n != 2 {
		t.Errorf("得到 %d 条", n)
	}
}

// --- 任务、分析和 HTTP 接口（用假模拟器）--------------------------------------------------------

func newServer(t *testing.T, sim balance.Simulator) (*Server, *httptest.Server) {
	p := sandbox(t)
	os.MkdirAll(filepath.Join(p.WebDist, "assets"), 0o755)
	os.WriteFile(filepath.Join(p.WebDist, "index.html"), []byte("<html>studio</html>"), 0o644)
	os.WriteFile(filepath.Join(p.WebDist, "assets", "app.js"), []byte("console.log(1)"), 0o644)
	s := New(Config{Paths: p, Sim: sim, Preview: func(battle, out, dataDir string) error {
		os.MkdirAll(filepath.Dir(out), 0o755)
		return os.WriteFile(out, []byte("PNG"), 0o644)
	}})
	return s, newHTTP(t, s)
}

func newHTTP(t *testing.T, s *Server) *httptest.Server {
	ts := httptest.NewServer(s.Handler())
	t.Cleanup(ts.Close)
	return ts
}

func call(t *testing.T, ts *httptest.Server, method, path, body string, headers ...string) (int, any, string) {
	t.Helper()
	var rd io.Reader
	if body != "" {
		rd = strings.NewReader(body)
	}
	req := must(http.NewRequest(method, ts.URL+path, rd))
	req.Header.Set("Content-Type", "application/json")
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	res := must(http.DefaultClient.Do(req))
	defer res.Body.Close()
	raw := string(must(io.ReadAll(res.Body)))
	v, _ := oj.Parse([]byte(raw))
	return res.StatusCode, v, raw
}

func TestHTTPDataAndEditing(t *testing.T) {
	_, ts := newServer(t, &balance.FakeSimulator{})

	code, v, raw := call(t, ts, "GET", "/api/meta", "")
	if code != 200 || !strings.HasPrefix(raw, `{"terrain":{".":"平地","f":"森林"`) || v.(*oj.Object).Str("baseline", "") != "baseline" {
		t.Fatalf("/api/meta: %d %s", code, raw)
	}
	if got := v.(*oj.Object).Array("metrics")[0]; oj.Dump(got, oj.Compact) != `{"key":"win_rate","label":"胜率","pct":true}` {
		t.Errorf("metrics[0] = %s", oj.Dump(got, oj.Compact))
	}

	code, v, _ = call(t, ts, "GET", "/api/data", "")
	d := v.(*oj.Object)
	if code != 200 || strings.Join(d.Keys(), ",") != "variant,units,skills,skill_tree,battles,issues,diff,hashes" || d.Str("variant", "") != "baseline" {
		t.Fatalf("/api/data: %d keys=%v", code, d.Keys())
	}
	if len(d.Object("hashes").Str("1-4", "")) != 12 {
		t.Errorf("hash = %q", d.Object("hashes").Str("1-4", ""))
	}

	code, v, raw = call(t, ts, "POST", "/api/variants", `{"name":"v1","note":"n"}`, "X-Actor", "AI")
	if code != 200 || strings.Join(v.(*oj.Object).Keys(), ",") != "name,note,created,updated,by" || v.(*oj.Object).Str("by", "") != "ai" {
		t.Fatalf("POST /api/variants: %d %s", code, raw)
	}
	if code, _, raw = call(t, ts, "POST", "/api/variants", `{"name":"v1"}`); code != 400 || raw != `{"error":"变体 v1 已存在"}` {
		t.Fatalf("重名：%d %s", code, raw)
	}
	if code, _, raw = call(t, ts, "POST", "/api/variants", `{"note":"x"}`); code != 422 || !strings.Contains(raw, `"detail"`) {
		t.Fatalf("缺字段：%d %s", code, raw)
	}

	battle := oj.Dump(newBattle(), oj.Compact)
	code, _, raw = call(t, ts, "PUT", "/api/variants/v1/battles/9-9", `{"battle":`+battle+`,"summary":""}`)
	if code != 200 || raw != `{"issues":[]}` {
		t.Fatalf("PUT battle: %d %s", code, raw)
	}
	code, v, _ = call(t, ts, "GET", "/api/variants", "")
	if list := v.([]any); code != 200 || len(list) != 1 || oj.Dump(list[0].(*oj.Object).Get("changed"), oj.Compact) != `["battles/9-9"]` {
		t.Fatalf("GET /api/variants: %s", oj.Dump(v, oj.Compact))
	}
	code, v, _ = call(t, ts, "GET", "/api/data?variant=v1", "")
	if diff := oj.Dump(v.(*oj.Object).Get("diff"), oj.Compact); diff != `[{"file":"battles/9-9","lines":["新关卡「新关卡」"]}]` {
		t.Fatalf("diff = %s", diff)
	}
	if code, _, raw = call(t, ts, "PUT", "/api/variants/baseline/tables/units", `{"content":{}}`); code != 400 || raw != `{"error":"基线只读：请先新建变体，再编辑"}` {
		t.Fatalf("基线只读：%d %s", code, raw)
	}
	if code, _, raw = call(t, ts, "DELETE", "/api/variants/v1/battles/9-9", ""); code != 200 || raw != `{"ok":true}` {
		t.Fatalf("DELETE battle: %d %s", code, raw)
	}
	if code, _, raw = call(t, ts, "POST", "/api/variants/v1/adopt", ""); code != 400 || raw != `{"error":"这个变体和基线没有差别"}` {
		t.Fatalf("adopt: %d %s", code, raw)
	}

	// 目标：写入后读回，文件是 PyYAML 的块状格式
	spec := `{"battle":"1-4","runs_min":50,"bots":{"skilled":{"win_rate":[0.7,0.95],"rounds_p50":{"range":[6,10],"known_issue":"已知：偏快"}}}}`
	if code, _, raw = call(t, ts, "PUT", "/api/targets/1-4", spec); code != 200 || raw != `{"ok":true}` {
		t.Fatalf("PUT targets: %d %s", code, raw)
	}
	if _, _, raw = call(t, ts, "GET", "/api/targets/1-4", ""); raw != spec {
		t.Fatalf("GET targets = %s", raw)
	}
	if code, _, raw = call(t, ts, "PUT", "/api/targets/1-4", `{"bots":{"skilled":{"win_rate":[0.9,0.1]}}}`); code != 400 || raw != `{"error":"skilled.win_rate 的范围无效：[0.9, 0.1]"}` {
		t.Fatalf("坏范围：%d %s", code, raw)
	}
	if _, _, raw = call(t, ts, "GET", "/api/targets/none", ""); raw != `{"battle":"none","runs_min":200,"bots":{}}` {
		t.Fatalf("默认目标 = %s", raw)
	}

	// 预览、回放、动态、网页
	code, v, raw = call(t, ts, "POST", "/api/preview?battle=1-4", "")
	if code != 200 || !strings.HasPrefix(v.(*oj.Object).Str("url", ""), "/api/preview/1-4-") {
		t.Fatalf("preview: %d %s", code, raw)
	}
	if code, _, raw = call(t, ts, "GET", v.(*oj.Object).Str("url", ""), ""); code != 200 || raw != "PNG" {
		t.Fatalf("preview file: %d %s", code, raw)
	}
	if code, v, raw = call(t, ts, "GET", "/api/replay?battle=1-4&bot=novice&seed=3", ""); code != 200 || v.(*oj.Object).Int("seed", -1) != 3 {
		t.Fatalf("replay: %d %s", code, raw)
	}
	if code, _, raw = call(t, ts, "GET", "/api/replay?battle=zz", ""); code != 400 || raw != `{"error":"没有这个关卡：zz"}` {
		t.Fatalf("replay 未知关卡：%d %s", code, raw)
	}
	if code, _, raw = call(t, ts, "GET", "/api/results", ""); code != 422 {
		t.Fatalf("缺 battle：%d %s", code, raw)
	}
	code, v, _ = call(t, ts, "GET", "/api/activity?limit=2", "")
	if list := v.([]any); code != 200 || len(list) != 2 || list[0].(*oj.Object).Str("kind", "") != "targets" {
		t.Fatalf("activity = %s", oj.Dump(v, oj.Compact))
	}
	for _, path := range []string{"/", "/some/page", "/index.html"} {
		if code, _, raw = call(t, ts, "GET", path, ""); code != 200 || raw != "<html>studio</html>" {
			t.Fatalf("GET %s: %d %s", path, code, raw)
		}
	}
	if code, _, raw = call(t, ts, "GET", "/assets/app.js", ""); code != 200 || raw != "console.log(1)" {
		t.Fatalf("assets: %d %s", code, raw)
	}
	if code, _, raw = call(t, ts, "POST", "/nope", ""); code != 405 || raw != `{"detail":"Method Not Allowed"}` {
		t.Fatalf("POST /nope: %d %s", code, raw)
	}
}

func TestSimulationJobResultsAndEvents(t *testing.T) {
	fake := &balance.FakeSimulator{WinRate: func(o balance.SimOptions) float64 {
		if o.Bot == "novice" {
			return 0.45
		}
		return 0.85
	}}
	s, ts := newServer(t, fake)
	os.MkdirAll(s.WS.P.Targets, 0o755)
	os.WriteFile(s.WS.P.TargetsPath("1-4"), []byte("battle: \"1-4\"\nruns_min: 50\nbots:\n  skilled:\n    win_rate: [0.60, 0.99]\n    rounds_p50: [1, 30]\n"), 0o644)

	// 订阅事件流
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	req := must(http.NewRequestWithContext(ctx, "GET", ts.URL+"/api/events", nil))
	res := must(http.DefaultClient.Do(req))
	defer res.Body.Close()
	if ct := res.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
		t.Fatalf("Content-Type = %s", ct)
	}
	events := make(chan string, 256)
	go func() {
		sc := bufio.NewScanner(res.Body)
		sc.Buffer(make([]byte, 1<<20), 1<<20)
		for sc.Scan() {
			events <- sc.Text()
		}
		close(events)
	}()
	if first := <-events; first != "retry: 1500" {
		t.Fatalf("事件流开头 = %q", first)
	}

	code, v, raw := call(t, ts, "POST", "/api/sims", `{"battle":"1-4","variant":null,"bots":["skilled","novice"],"runs":120,"seed":0}`)
	job := v.(*oj.Object)
	if code != 200 || strings.Join(job.Keys(), ",") != "id,battle,variant,bots,runs,seed,actor,status,done,total,error,created,started_at,elapsed,hash,used" {
		t.Fatalf("POST /api/sims: %d %s", code, raw)
	}
	if job.Int("total", 0) != 240 || job.Str("variant", "") != "baseline" || job.Str("status", "") != "queued" {
		t.Fatalf("job = %s", raw)
	}
	s.Jobs.Wait()

	_, v, raw = call(t, ts, "GET", "/api/jobs", "")
	done := v.([]any)[0].(*oj.Object)
	if done.Str("status", "") != "done" || done.Int("done", 0) != 240 {
		t.Fatalf("任务没有完成：%s", raw)
	}
	// 熟练机器人有目标：50 局时就定论，提前停；新手没有目标：跑满
	if used := oj.Dump(done.Get("used"), oj.Compact); used != `{"skilled":50,"novice":120}` {
		t.Fatalf("used = %s", used)
	}
	meta := string(must(os.ReadFile(filepath.Join(s.WS.P.RunDir("1-4", "skilled", ""), "meta.json"))))
	if !strings.HasPrefix(meta, `{"hash": "`+done.Str("hash", "")+`", "runs": 50, "max_runs": 120, "seed": 0, "finished": "`) || !strings.HasSuffix(meta, `", "by": "human"}`) {
		t.Fatalf("meta.json = %s", meta)
	}

	code, v, raw = call(t, ts, "GET", "/api/results?battle=1-4", "")
	r := v.(*oj.Object)
	if code != 200 || strings.Join(r.Keys(), ",") != "battle,variant,hash,bots,verdicts,targets,runs_min" || r.Int("runs_min", 0) != 50 {
		t.Fatalf("/api/results: %d %.300s", code, raw)
	}
	sk := r.Object("bots").Object("skilled")
	if strings.Join(sk.Keys(), ",") != "label,status,meta,runs,outcomes,rounds,hp,damage,sources,mechanics,heat,table" ||
		sk.Str("status", "") != "fresh" || sk.Int("runs", 0) != 50 {
		t.Fatalf("bots.skilled = %.300s", oj.Dump(sk, oj.Compact))
	}
	vs := r.Array("verdicts")
	if len(vs) != 2*len(balance.Metrics) {
		t.Fatalf("判定行数 = %d", len(vs))
	}
	win := vs[0].(*oj.Object)
	if strings.Join(win.Keys(), ",") != "bot,metric,label,pct,target,value,lo,hi,n,status,note" ||
		win.Str("status", "") != "PASS" || oj.Dump(win.Get("target"), oj.Compact) != "[0.6,0.99]" {
		t.Fatalf("verdicts[0] = %s", oj.Dump(win, oj.Compact))
	}
	if nv := vs[len(balance.Metrics)].(*oj.Object); nv.Str("bot", "") != "novice" || nv.Str("status", "") != "NO_TARGET" || nv.Get("target") != nil {
		t.Fatalf("新手的行 = %s", oj.Dump(nv, oj.Compact))
	}

	_, v, raw = call(t, ts, "GET", "/api/compare?battle=1-4", "")
	if rows := v.([]any); len(rows) != 1 || oj.Dump(rows[0].(*oj.Object).Get("bots"), oj.Compact) != `{"skilled":{"status":"fresh","runs":50},"novice":{"status":"fresh","runs":120}}` {
		t.Fatalf("/api/compare = %.300s", raw)
	}

	// 改了数据，结果就过期
	must(s.WS.CreateVariant("v1", "", "human", ""))
	units := oj.DeepCopy(must(s.WS.Load("")).Units).(*oj.Object)
	units.Object("wolf").Set("hp", 15)
	must(s.WS.SaveTable("v1", "units", units, "human", ""))
	must(s.WS.Adopt("v1", "human"))
	_, v, _ = call(t, ts, "GET", "/api/results?battle=1-4", "")
	if st := v.(*oj.Object).Object("bots").Object("skilled").Str("status", ""); st != "stale" {
		t.Fatalf("改数据后状态 = %s", st)
	}

	// 事件流里应当有三种事件，最后一条任务事件是 done，动态里有完成的一句话
	cancel()
	kinds := map[string]int{}
	lastJob, headline := "", ""
	timeout := time.After(5 * time.Second)
loop:
	for {
		select {
		case line, ok := <-events:
			if !ok {
				break loop
			}
			if !strings.HasPrefix(line, "data: ") {
				continue
			}
			e := must(oj.ParseObject([]byte(strings.TrimPrefix(line, "data: "))))
			kinds[e.Str("kind", "")]++
			switch e.Str("kind", "") {
			case "job":
				lastJob = e.Object("data").Str("status", "")
			case "activity":
				if text := e.Object("data").Str("text", ""); strings.HasPrefix(text, "模拟完成") {
					headline = text
				}
			}
		case <-timeout:
			break loop
		}
	}
	if kinds["job"] < 2 || kinds["activity"] < 2 {
		t.Errorf("事件种类 = %v", kinds)
	}
	if lastJob != "done" {
		t.Errorf("最后的任务状态 = %q", lastJob)
	}
	if !strings.HasPrefix(headline, "模拟完成 1-4（熟练机器人 50 局、新手机器人 120 局）：熟练机器人胜率 ") || !strings.HasSuffix(headline, "，目标通过 2/2") {
		t.Errorf("完成动态 = %q", headline)
	}
}

func TestJobValidationAndCancel(t *testing.T) {
	fake := &balance.FakeSimulator{Delay: 5 * time.Millisecond}
	s, ts := newServer(t, fake)
	for body, want := range map[string]string{
		`{"battle":"zz"}`:                     `{"error":"没有这个关卡：zz"}`,
		`{"battle":"1-4","bots":["x"]}`:       `{"error":"机器人无效：['x']"}`,
		`{"battle":"1-4","runs":0}`:           `{"error":"局数必须在 1 到 5000 之间"}`,
		`{"battle":"1-4","variant":"nobody"}`: `{"error":"没有这个变体：nobody"}`,
	} {
		if code, _, raw := call(t, ts, "POST", "/api/sims", body); code != 400 || raw != want {
			t.Errorf("%s → %d %s", body, code, raw)
		}
	}
	_, v, _ := call(t, ts, "POST", "/api/sims", `{"battle":"1-4","bots":["skilled"],"runs":2000}`)
	id := v.(*oj.Object).Int("id", 0)
	time.Sleep(60 * time.Millisecond)
	code, v, raw := call(t, ts, "POST", "/api/jobs/"+oj.PyRepr(id)+"/cancel", "", "X-Actor", "ai")
	if code != 200 || v.(*oj.Object).Str("status", "") != "cancelled" {
		t.Fatalf("cancel: %d %s", code, raw)
	}
	s.Jobs.Wait()
	_, v, _ = call(t, ts, "GET", "/api/jobs", "")
	if j := v.([]any)[0].(*oj.Object); j.Str("status", "") != "cancelled" || j.Int("done", 0) >= 2000 {
		t.Fatalf("取消后的任务 = %s", oj.Dump(j, oj.Compact))
	}
	if exists(filepath.Join(s.WS.P.RunDir("1-4", "skilled", ""), "runs.jsonl")) {
		t.Error("取消的模拟不应留下结果文件")
	}
	if code, _, raw = call(t, ts, "POST", "/api/jobs/999/cancel", ""); code != 400 || raw != `{"error":"没有这个模拟任务"}` {
		t.Fatalf("取消不存在的任务：%d %s", code, raw)
	}
}

// 和 Python 版的接口输出逐字节对比（设置了环境变量才运行）：
// STUDIO_PY_REF 是 Python 各接口响应的目录，STUDIO_PY_PROJECT 是同一份数据的仓库根目录。
func TestLiveAPIAgainstPython(t *testing.T) {
	ref, root := os.Getenv("STUDIO_PY_REF"), os.Getenv("STUDIO_PY_PROJECT")
	if ref == "" || root == "" {
		t.Skip("未设置 STUDIO_PY_REF / STUDIO_PY_PROJECT")
	}
	s := New(Config{Paths: balance.NewPaths(root), Sim: balance.EngineSimulator{}})
	ts := httptest.NewServer(s.Handler())
	defer ts.Close()
	t.Logf("规则哈希 %s", s.WS.RulesHash())
	for name, path := range map[string]string{
		"meta": "/api/meta", "variants": "/api/variants", "data": "/api/data", "results_1-4": "/api/results?battle=1-4",
		"results_1-5": "/api/results?battle=1-5", "compare_1-4": "/api/compare?battle=1-4", "targets_1-4": "/api/targets/1-4",
		"targets_1-5": "/api/targets/1-5", "targets_zz": "/api/targets/zz", "activity": "/api/activity", "activity5": "/api/activity?limit=5",
	} {
		want := string(must(os.ReadFile(filepath.Join(ref, name))))
		code, _, got := call(t, ts, "GET", path, "")
		if code != 200 || got != want {
			i := 0
			for i < len(got) && i < len(want) && got[i] == want[i] {
				i++
			}
			t.Errorf("%s: 状态 %d，第 %d 字节起不同：\n  Go     …%.200s\n  Python …%.200s", name, code, i, got[max(0, i-60):], want[max(0, i-60):])
		} else {
			t.Logf("%s：%d 字节完全一致", name, len(got))
		}
	}
}
