package studio

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"srpg/balance"
	oj "srpg/balance/ordjson"
)

// 战棋工坊的 HTTP 接口 + 构建好的网页。
//
// 界面上的每个操作都是这里的一个接口，所以浏览器里的人和调用接口的 AI 操作的是同一批变体，
// 并且能看到对方的改动（通过 /api/events 推送）。请求头 X-Actor: ai（默认 human）决定动态里显示是谁做的。

// DefaultGodot 是原型用的 Godot（只有"实机预览截图"还需要它）。
const DefaultGodot = `D:\golang\cloudbound-isles\.tools\godot\Godot_v4.7.2-stable_win64_console.exe`

// Config 是服务器的配置。
type Config struct {
	Paths   balance.Paths
	Sim     balance.Simulator
	Workers int
	Rules   []RulesSource // 空 = 默认（engine 下的规则源码）
	// Preview 把关卡渲染成 PNG 存到 out；nil 时调用 Godot（$GODOT 或 DefaultGodot）。
	Preview func(battle, out, dataDir string) error
}

// Server 是工坊后端。
type Server struct {
	WS   *Workspace
	Jobs *Jobs
	cfg  Config
	bus  *bus
	mux  *http.ServeMux
	diff *difficultyRun
	// KeepAlive 是事件流的保活间隔。
	KeepAlive time.Duration
}

// --- 实时事件 -----------------------------------------------------------------------------------

type bus struct {
	mu   sync.Mutex
	subs map[chan string]bool
}

func (b *bus) publish(kind string, payload any) {
	msg := oj.Dump(oj.Obj("kind", kind, "data", payload), oj.Default)
	b.mu.Lock()
	defer b.mu.Unlock()
	for ch := range b.subs {
		select {
		case ch <- msg:
		default: // 订阅者太慢：丢掉这条，不阻塞模拟
		}
	}
}

func (b *bus) subscribe() chan string {
	ch := make(chan string, 1024)
	b.mu.Lock()
	b.subs[ch] = true
	b.mu.Unlock()
	return ch
}

func (b *bus) unsubscribe(ch chan string) {
	b.mu.Lock()
	delete(b.subs, ch)
	b.mu.Unlock()
}

// New 创建服务器。
func New(cfg Config) *Server {
	ws := NewWorkspace(cfg.Paths)
	if len(cfg.Rules) > 0 {
		ws.Rules = cfg.Rules
	}
	s := &Server{WS: ws, cfg: cfg, bus: &bus{subs: map[chan string]bool{}}, KeepAlive: 15 * time.Second, diff: &difficultyRun{}}
	runner := &balance.Runner{Paths: cfg.Paths, Sim: cfg.Sim, Workers: cfg.Workers}
	s.Jobs = NewJobs(ws, runner, s.bus.publish)
	ws.OnActivity(func(entry *oj.Object) { s.bus.publish("activity", entry) })
	s.routes()
	return s
}

// Handler 返回 HTTP 处理器。
func (s *Server) Handler() http.Handler { return s.mux }

// Serve 监听 addr 直到 ctx 取消。
func (s *Server) Serve(ctx context.Context, addr string) error {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}
	srv := &http.Server{Handler: s.mux}
	go func() {
		<-ctx.Done()
		srv.Close()
	}()
	if err := srv.Serve(ln); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

// --- 请求/响应工具 ------------------------------------------------------------------------------

func writeJSONResp(w http.ResponseWriter, status int, v any) {
	body := oj.Dump(v, oj.Compact)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	io.WriteString(w, body)
}

// invalid 是请求参数不对（FastAPI 的 422）。
type invalid struct {
	loc []any
	msg string
}

func (e *invalid) Error() string { return e.msg }

func missing(loc ...any) error { return &invalid{loc, "Field required"} }
func badType(msg string, loc ...any) error {
	return &invalid{loc, msg}
}

func writeErr(w http.ResponseWriter, err error) {
	var ue *Error
	var inv *invalid
	switch {
	case errors.As(err, &ue):
		writeJSONResp(w, 400, oj.Obj("error", ue.Msg))
	case errors.As(err, &inv):
		kind := "value_error"
		if inv.msg == "Field required" {
			kind = "missing"
		}
		writeJSONResp(w, 422, oj.Obj("detail", []any{oj.Obj("type", kind, "loc", inv.loc, "msg", inv.msg)}))
	default:
		msg := []rune("内部错误：" + err.Error())
		if len(msg) > 800 {
			msg = msg[:800]
		}
		writeJSONResp(w, 500, oj.Obj("error", string(msg)))
	}
}

func actor(r *http.Request) string {
	if strings.EqualFold(r.Header.Get("X-Actor"), "ai") {
		return "ai"
	}
	return "human"
}

func body(r *http.Request) (*oj.Object, error) {
	data, err := io.ReadAll(http.MaxBytesReader(nil, r.Body, 32<<20))
	if err != nil {
		return nil, err
	}
	if len(strings.TrimSpace(string(data))) == 0 {
		return nil, missing("body")
	}
	v, err := oj.Parse(data)
	if err != nil {
		return nil, badType("JSON decode error", "body")
	}
	o, ok := v.(*oj.Object)
	if !ok {
		return nil, badType("Input should be a valid dictionary", "body")
	}
	return o, nil
}

func strField(o *oj.Object, key, def string, required bool) (string, error) {
	if !o.Has(key) {
		if required {
			return "", missing("body", key)
		}
		return def, nil
	}
	s, ok := o.Get(key).(string)
	if !ok {
		return "", badType("Input should be a valid string", "body", key)
	}
	return s, nil
}

func intField(o *oj.Object, key string, def int) (int, error) {
	if !o.Has(key) {
		return def, nil
	}
	f, ok := oj.Float(o.Get(key))
	if s, isStr := o.Get(key).(string); isStr {
		n, err := strconv.Atoi(strings.TrimSpace(s))
		f, ok = float64(n), err == nil
	}
	if !ok || f != float64(int(f)) {
		return 0, badType("Input should be a valid integer", "body", key)
	}
	return int(f), nil
}

func objField(o *oj.Object, key string) (*oj.Object, error) {
	if !o.Has(key) {
		return nil, missing("body", key)
	}
	v, ok := o.Get(key).(*oj.Object)
	if !ok {
		return nil, badType("Input should be a valid dictionary", "body", key)
	}
	return v, nil
}

func queryInt(r *http.Request, key string, def int) (int, error) {
	if !r.URL.Query().Has(key) {
		return def, nil
	}
	n, err := strconv.Atoi(r.URL.Query().Get(key))
	if err != nil {
		return 0, badType("Input should be a valid integer, unable to parse string as an integer", "query", key)
	}
	return n, nil
}

func queryRequired(r *http.Request, key string) (string, error) {
	if !r.URL.Query().Has(key) {
		return "", missing("query", key)
	}
	return r.URL.Query().Get(key), nil
}

type handler func(r *http.Request) (any, error)

func (s *Server) handle(pattern string, h handler) {
	s.mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if p := recover(); p != nil {
				writeErr(w, fmt.Errorf("%v", p))
			}
		}()
		v, err := h(r)
		if err != nil {
			writeErr(w, err)
			return
		}
		writeJSONResp(w, 200, v)
	})
}

var safeName = regexp.MustCompile(`^[A-Za-z0-9_\-]{1,40}$`)

// --- 路由 ---------------------------------------------------------------------------------------

func (s *Server) routes() {
	s.mux = http.NewServeMux()
	ws := s.WS
	ok := oj.Obj("ok", true)
	variantOf := func(r *http.Request) string { return r.URL.Query().Get("variant") }
	orBaseline := func(v string) string {
		if v == "" {
			return Baseline
		}
		return v
	}

	s.mux.HandleFunc("GET /api/events", s.events)
	s.difficultyRoutes()

	// 静态词汇：地形代码、机器人、指标、结局
	s.handle("GET /api/meta", func(r *http.Request) (any, error) {
		return oj.Obj("terrain", Terrain, "bots", Bots, "metrics", MetricCatalog(), "results", Results, "baseline", Baseline), nil
	})

	s.handle("GET /api/variants", func(r *http.Request) (any, error) {
		vs, err := ws.ListVariants()
		out := make([]any, len(vs))
		for i, v := range vs {
			out[i] = v
		}
		return out, err
	})

	s.handle("POST /api/variants", func(r *http.Request) (any, error) {
		b, err := body(r)
		if err != nil {
			return nil, err
		}
		name, err := strField(b, "name", "", true)
		if err != nil {
			return nil, err
		}
		note, err := strField(b, "note", "", false)
		if err != nil {
			return nil, err
		}
		copyFrom := ""
		if b.Get("copy_from") != nil {
			if copyFrom, err = strField(b, "copy_from", "", false); err != nil {
				return nil, err
			}
		}
		meta, err := ws.CreateVariant(name, note, actor(r), copyFrom)
		if err != nil {
			return nil, err
		}
		s.bus.publish("data", oj.Obj("variant", name))
		return meta, nil
	})

	s.handle("DELETE /api/variants/{variant}", func(r *http.Request) (any, error) {
		v := r.PathValue("variant")
		if err := ws.DeleteVariant(v, actor(r)); err != nil {
			return nil, err
		}
		s.bus.publish("data", oj.Obj("variant", v, "deleted", true))
		return ok, nil
	})

	// 某个变体（或基线）生效的数据表，加上校验问题和差异
	s.handle("GET /api/data", func(r *http.Request) (any, error) {
		variant := variantOf(r)
		d, err := ws.Load(variant)
		if err != nil {
			return nil, err
		}
		issues, err := ws.Validate(d)
		if err != nil {
			return nil, err
		}
		diff, err := ws.Diff(variant)
		if err != nil {
			return nil, err
		}
		hashes := oj.NewObject()
		for _, b := range d.Battles.Keys() {
			hashes.Set(b, ws.BattleHash(d, b))
		}
		return oj.Obj("variant", orBaseline(variant), "units", d.Units, "skills", d.Skills, "skill_tree", d.SkillTree,
			"battles", d.Battles, "issues", objList(issues), "diff", objList(diff), "hashes", hashes), nil
	})

	s.handle("PUT /api/variants/{variant}/battles/{battle_id}", func(r *http.Request) (any, error) {
		b, err := body(r)
		if err != nil {
			return nil, err
		}
		battle, err := objField(b, "battle")
		if err != nil {
			return nil, err
		}
		summary, err := strField(b, "summary", "", false)
		if err != nil {
			return nil, err
		}
		variant, id := r.PathValue("variant"), r.PathValue("battle_id")
		issues, err := ws.SaveBattle(variant, id, battle, actor(r), summary)
		if err != nil {
			return nil, err
		}
		s.bus.publish("data", oj.Obj("variant", variant, "battle", id, "actor", actor(r)))
		return oj.Obj("issues", objList(issues)), nil
	})

	s.handle("DELETE /api/variants/{variant}/battles/{battle_id}", func(r *http.Request) (any, error) {
		variant := r.PathValue("variant")
		if err := ws.DeleteBattle(variant, r.PathValue("battle_id"), actor(r)); err != nil {
			return nil, err
		}
		s.bus.publish("data", oj.Obj("variant", variant))
		return ok, nil
	})

	s.handle("PUT /api/variants/{variant}/tables/{table}", func(r *http.Request) (any, error) {
		b, err := body(r)
		if err != nil {
			return nil, err
		}
		content, err := objField(b, "content")
		if err != nil {
			return nil, err
		}
		summary, err := strField(b, "summary", "", false)
		if err != nil {
			return nil, err
		}
		variant, table := r.PathValue("variant"), r.PathValue("table")
		issues, err := ws.SaveTable(variant, table, content, actor(r), summary)
		if err != nil {
			return nil, err
		}
		s.bus.publish("data", oj.Obj("variant", variant, "table", table, "actor", actor(r)))
		return oj.Obj("issues", objList(issues)), nil
	})

	s.handle("POST /api/variants/{variant}/adopt", func(r *http.Request) (any, error) {
		variant := r.PathValue("variant")
		files, err := ws.Adopt(variant, actor(r))
		if err != nil {
			return nil, err
		}
		s.bus.publish("data", oj.Obj("variant", variant, "adopted", true))
		return oj.Obj("files", toAny(files)), nil
	})

	// --- 模拟 ---

	s.handle("POST /api/sims", func(r *http.Request) (any, error) {
		b, err := body(r)
		if err != nil {
			return nil, err
		}
		battle, err := strField(b, "battle", "", true)
		if err != nil {
			return nil, err
		}
		variant := ""
		if b.Get("variant") != nil {
			if variant, err = strField(b, "variant", "", false); err != nil {
				return nil, err
			}
		}
		bots := []string{"skilled", "novice"}
		if b.Has("bots") {
			arr, isList := b.Get("bots").([]any)
			if !isList {
				return nil, badType("Input should be a valid list", "body", "bots")
			}
			bots = []string{}
			for i, x := range arr {
				name, isStr := x.(string)
				if !isStr {
					return nil, badType("Input should be a valid string", "body", "bots", i)
				}
				bots = append(bots, name)
			}
		}
		runs, err := intField(b, "runs", 400)
		if err != nil {
			return nil, err
		}
		seed, err := intField(b, "seed", 0)
		if err != nil {
			return nil, err
		}
		return s.Jobs.Start(battle, variant, bots, runs, seed, actor(r))
	})

	s.handle("GET /api/jobs", func(r *http.Request) (any, error) { return s.Jobs.List(), nil })

	s.handle("POST /api/jobs/{job_id}/cancel", func(r *http.Request) (any, error) {
		id, err := strconv.Atoi(r.PathValue("job_id"))
		if err != nil {
			return nil, badType("Input should be a valid integer, unable to parse string as an integer", "path", "job_id")
		}
		return s.Jobs.Cancel(id, actor(r))
	})

	s.handle("GET /api/results", func(r *http.Request) (any, error) {
		battle, err := queryRequired(r, "battle")
		if err != nil {
			return nil, err
		}
		return ws.Results(battle, variantOf(r))
	})

	// 多个变体的判定并排；variants 用逗号分隔，默认是基线加全部变体
	s.handle("GET /api/compare", func(r *http.Request) (any, error) {
		battle, err := queryRequired(r, "battle")
		if err != nil {
			return nil, err
		}
		var names []string
		for _, v := range strings.Split(r.URL.Query().Get("variants"), ",") {
			if v != "" {
				names = append(names, v)
			}
		}
		if len(names) == 0 {
			names = []string{Baseline}
			vs, err := ws.ListVariants()
			if err != nil {
				return nil, err
			}
			for _, v := range vs {
				names = append(names, v.Str("name", ""))
			}
		}
		out := []any{}
		for _, name := range names {
			sum, err := ws.Summary(battle, name)
			var ue *Error
			if errors.As(err, &ue) {
				continue
			}
			if err != nil {
				return nil, err
			}
			out = append(out, sum)
		}
		return out, nil
	})

	s.handle("GET /api/targets/{battle}", func(r *http.Request) (any, error) {
		battle := r.PathValue("battle")
		spec, err := ws.LoadTargets(battle)
		if err != nil {
			return nil, err
		}
		if spec == nil || spec.Raw.Len() == 0 {
			return oj.Obj("battle", battle, "runs_min", 200, "bots", oj.NewObject()), nil
		}
		return spec.Raw, nil
	})

	s.handle("PUT /api/targets/{battle}", func(r *http.Request) (any, error) {
		spec, err := body(r)
		if err != nil {
			return nil, err
		}
		battle := r.PathValue("battle")
		if err := ws.SaveTargets(battle, spec); err != nil {
			return nil, err
		}
		ws.Log(actor(r), "targets", fmt.Sprintf("修改 %s 的设计目标", battle), "battle", battle)
		s.bus.publish("data", oj.Obj("battle", battle, "targets", true))
		return ok, nil
	})

	// --- 回放与预览 ---

	// 某个种子的一局的逐步记录（确定性的，所以按需重放并缓存）
	s.handle("GET /api/replay", func(r *http.Request) (any, error) {
		battle, err := queryRequired(r, "battle")
		if err != nil {
			return nil, err
		}
		bot := "skilled"
		if r.URL.Query().Has("bot") {
			bot = r.URL.Query().Get("bot")
		}
		seed, err := queryInt(r, "seed", 0)
		if err != nil {
			return nil, err
		}
		variant := variantOf(r)
		d, err := ws.Load(variant)
		if err != nil {
			return nil, err
		}
		if !d.Battles.Has(battle) {
			return nil, userErr("没有这个关卡：%s", battle)
		}
		if !safeName.MatchString(bot) {
			return nil, userErr("机器人无效：%s", oj.PyStrRepr(bot))
		}
		out := filepath.Join(s.cacheDir(), "replay", fmt.Sprintf("%s-%s-%s-%d.json", battle, ws.BattleHash(d, battle), bot, seed))
		if !exists(out) {
			over, err := ws.OverlayDir(variant)
			if err != nil {
				return nil, err
			}
			if s.cfg.Sim == nil {
				return nil, balance.ErrEngineNotWired
			}
			rep, err := s.cfg.Sim.Replay(r.Context(), balance.ReplayOptions{Battle: battle, Bot: bot, Seed: seed, DataDir: over,
				TablesDir: s.cfg.Paths.Tables})
			if err != nil {
				return nil, err
			}
			if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
				return nil, err
			}
			if err := os.WriteFile(out, rep, 0o644); err != nil {
				return nil, err
			}
		}
		return readJSON(out)
	})

	// 用真实的游戏画面渲染关卡，返回图片地址
	s.handle("POST /api/preview", func(r *http.Request) (any, error) {
		battle, err := queryRequired(r, "battle")
		if err != nil {
			return nil, err
		}
		variant := variantOf(r)
		d, err := ws.Load(variant)
		if err != nil {
			return nil, err
		}
		if !d.Battles.Has(battle) {
			return nil, userErr("没有这个关卡：%s", battle)
		}
		name := fmt.Sprintf("%s-%s.png", battle, ws.BattleHash(d, battle))
		out := filepath.Join(s.cacheDir(), "preview", name)
		if !exists(out) {
			over, err := ws.OverlayDir(variant)
			if err != nil {
				return nil, err
			}
			render := s.cfg.Preview
			if render == nil {
				render = s.godotCapture
			}
			if err := render(battle, out, over); err != nil {
				return nil, err
			}
		}
		return oj.Obj("url", "/api/preview/"+name), nil
	})

	s.mux.HandleFunc("GET /api/preview/{name}", func(w http.ResponseWriter, r *http.Request) {
		path := filepath.Join(s.cacheDir(), "preview", filepath.Base(r.PathValue("name")))
		if st, err := os.Stat(path); err != nil || st.IsDir() {
			writeErr(w, fmt.Errorf("File at path %s does not exist.", path))
			return
		}
		w.Header().Set("Content-Type", "image/png")
		http.ServeFile(w, r, path)
	})

	s.handle("GET /api/activity", func(r *http.Request) (any, error) {
		limit, err := queryInt(r, "limit", 80)
		if err != nil {
			return nil, err
		}
		return ws.Activity(limit)
	})

	// --- 网页 ---

	dist := s.cfg.Paths.WebDist
	hasDist := exists(dist)
	if hasDist {
		s.mux.Handle("GET /assets/", http.StripPrefix("/assets/", http.FileServer(http.Dir(filepath.Join(dist, "assets")))))
	}
	s.mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		switch {
		case !hasDist:
			writeJSONResp(w, 404, oj.Obj("detail", "Not Found"))
		case r.Method != http.MethodGet && r.Method != http.MethodHead:
			writeJSONResp(w, 405, oj.Obj("detail", "Method Not Allowed"))
		default:
			// 单页应用：是文件就给文件，否则一律给 index.html（只在 dist 目录内找）
			rel := filepath.FromSlash(strings.TrimPrefix(r.URL.Path, "/"))
			file := filepath.Join(dist, "index.html")
			if rel != "" && filepath.IsLocal(rel) {
				if st, err := os.Stat(filepath.Join(dist, rel)); err == nil && !st.IsDir() {
					file = filepath.Join(dist, rel)
				}
			}
			serveFile(w, r, file)
		}
	})
}

// serveFile 直接给文件内容（http.ServeFile 会把 /index.html 重定向到 /，这里不要）。
func serveFile(w http.ResponseWriter, r *http.Request, path string) {
	f, err := os.Open(path)
	if err != nil {
		writeErr(w, err)
		return
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		writeErr(w, err)
		return
	}
	http.ServeContent(w, r, filepath.Base(path), st.ModTime(), f)
}

func objList(list []*oj.Object) []any {
	out := make([]any, len(list))
	for i, o := range list {
		out[i] = o
	}
	return out
}

func (s *Server) cacheDir() string { return filepath.Join(s.cfg.Paths.Out, "studio") }

// events 是 SSE 事件流：每条是 data: {"kind": "job"|"activity"|"data", "data": …}。
func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeErr(w, fmt.Errorf("不支持流式响应"))
		return
	}
	ch := s.bus.subscribe()
	defer s.bus.unsubscribe(ch)
	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(200)
	io.WriteString(w, "retry: 1500\n\n")
	flusher.Flush()
	tick := time.NewTicker(s.KeepAlive)
	defer tick.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case msg := <-ch:
			io.WriteString(w, "data: "+msg+"\n\n")
			tick.Reset(s.KeepAlive)
		case <-tick.C:
			io.WriteString(w, ": keepalive\n\n")
		}
		flusher.Flush()
	}
}

// godotCapture 用 Godot 原型把关卡渲染成 PNG（需要显示器，不能无头）。
func (s *Server) godotCapture(battle, out, dataDir string) error {
	godot := os.Getenv("GODOT")
	if godot == "" {
		godot = DefaultGodot
	}
	if !exists(godot) {
		return fmt.Errorf("Godot not found at %s; set the GODOT environment variable", godot)
	}
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}
	args := []string{"--path", s.cfg.Paths.Prototype, "--", "--battle=" + battle, "--capture=" + out, "--demo=idle"}
	if dataDir != "" {
		args = append(args, "--data-dir="+dataDir)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, godot, args...).CombinedOutput()
	if !exists(out) {
		tail := []rune(string(output))
		if len(tail) > 2000 {
			tail = tail[len(tail)-2000:]
		}
		return fmt.Errorf("Godot capture failed (%v):\n%s", err, string(tail))
	}
	return nil
}
