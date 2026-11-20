// Package studio 是战棋工坊（Balance Studio）的后端：变体、校验、差异、采用、动态日志、
// 模拟任务、分析数据和 HTTP 接口。磁盘格式和接口形状与原 Python 版一致。
//
// 基线是 prototype/data/tables 下的真实数据，从不原地修改。变体是目录
// balance/workspace/variants/<name>/tables/，只放和基线不同的文件；采用变体就是把它的文件覆盖到基线。
package studio

import (
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"srpg/balance"
	oj "srpg/balance/ordjson"
)

const Baseline = "baseline"

var (
	nameRE     = regexp.MustCompile(`^[A-Za-z0-9_\-一-鿿]{1,40}$`)
	battleIDRE = regexp.MustCompile(`^[A-Za-z0-9_\-]{1,24}$`)
	tableNames = []string{"units", "skills", "skill_tree"}
)

// Terrain 是地形代码的中文名（顺序即前端调色板的顺序）。
var Terrain = oj.Obj(".", "平地", "f", "森林", "w", "浅水", "D", "深水", "s", "沼泽", "b", "燃烧", "x", "冥河")

const walkable = ".fwsbx"

// Error 是给用户看的错误（名称不对、变体不存在、校验没过），接口返回 400。
type Error struct{ Msg string }

func (e *Error) Error() string { return e.Msg }

func userErr(format string, a ...any) error { return &Error{fmt.Sprintf(format, a...)} }

// RulesSource 是参与"规则哈希"的一个目录：其中扩展名为 Ext 的文件内容变了，旧的模拟结果就算过期。
type RulesSource struct {
	Dir string
	Ext string // ".gd" 或 ".go"（".go" 时不算 _test.go）
}

// Workspace 管理变体和动态日志。
type Workspace struct {
	P     balance.Paths
	Rules []RulesSource // 默认是 engine 下 rules、bots、sim 三个包的 *.go（不含测试）

	mu        sync.Mutex // 串行化所有改动
	logMu     sync.Mutex
	listeners []func(entry *oj.Object)
}

// NewWorkspace 用默认的规则哈希来源创建。
func NewWorkspace(p balance.Paths) *Workspace {
	var rules []RulesSource
	for _, d := range []string{"rules", "bots", "sim"} {
		rules = append(rules, RulesSource{Dir: filepath.Join(p.Project, "engine", d), Ext: ".go"})
	}
	return &Workspace{P: p, Rules: rules}
}

func (w *Workspace) variantsDir() string  { return filepath.Join(w.P.Workspace, "variants") }
func (w *Workspace) activityPath() string { return filepath.Join(w.P.Workspace, "activity.jsonl") }

// Now 是本地时间，精确到秒（datetime.now().isoformat(timespec="seconds")）。
func Now() string { return time.Now().Format("2006-01-02T15:04:05") }

func readJSON(path string) (any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	v, err := oj.Parse(data)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return v, nil
}

func readObject(path string) (*oj.Object, error) {
	v, err := readJSON(path)
	if err != nil {
		return nil, err
	}
	o, ok := v.(*oj.Object)
	if !ok {
		return nil, fmt.Errorf("%s: 需要 JSON 对象", path)
	}
	return o, nil
}

func writeJSON(path string, v any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(oj.Dump(v, oj.Indent2)+"\n"), 0o644)
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// --- 变体 ---------------------------------------------------------------------------------------

// IsBaseline：空串和 "baseline" 都指基线。
func IsBaseline(variant string) bool { return variant == "" || variant == Baseline }

func (w *Workspace) variantDir(variant string) (string, error) {
	if !nameRE.MatchString(variant) || variant == Baseline {
		return "", userErr("变体名称无效：%s（只能用字母、数字、中文、- 和 _）", oj.PyStrRepr(variant))
	}
	return filepath.Join(w.variantsDir(), variant), nil
}

// OverlayDir 是交给引擎的数据覆盖目录（基线返回空串）。
func (w *Workspace) OverlayDir(variant string) (string, error) {
	if IsBaseline(variant) {
		return "", nil
	}
	dir, err := w.variantDir(variant)
	if err != nil {
		return "", err
	}
	if !exists(dir) {
		return "", userErr("没有这个变体：%s", variant)
	}
	d := filepath.Join(dir, "tables")
	return d, os.MkdirAll(d, 0o755)
}

// ListVariants 列出全部变体（最近修改的在前），每个带 changed 文件列表。
func (w *Workspace) ListVariants() ([]*oj.Object, error) {
	entries, err := os.ReadDir(w.variantsDir())
	if err != nil {
		return []*oj.Object{}, nil
	}
	out := []*oj.Object{}
	for _, e := range entries {
		metaPath := filepath.Join(w.variantsDir(), e.Name(), "meta.json")
		if !exists(metaPath) {
			continue
		}
		meta, err := readObject(metaPath)
		if err != nil {
			return nil, err
		}
		changed, err := w.ChangedFiles(e.Name())
		if err != nil {
			return nil, err
		}
		meta.Set("changed", changed)
		out = append(out, meta)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Str("updated", "") > out[j].Str("updated", "") })
	return out, nil
}

// CreateVariant 新建变体；copyFrom 非空时复制另一个变体的文件。
func (w *Workspace) CreateVariant(name, note, actor, copyFrom string) (*oj.Object, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	d, err := w.variantDir(name)
	if err != nil {
		return nil, err
	}
	if exists(d) {
		return nil, userErr("变体 %s 已存在", name)
	}
	if copyFrom != "" && !IsBaseline(copyFrom) {
		src, err := w.variantDir(copyFrom)
		if err != nil {
			return nil, err
		}
		if !exists(filepath.Join(src, "tables")) {
			return nil, fmt.Errorf("找不到要复制的变体：%s", copyFrom)
		}
		if err := os.CopyFS(filepath.Join(d, "tables"), os.DirFS(filepath.Join(src, "tables"))); err != nil {
			return nil, err
		}
	}
	if err := os.MkdirAll(filepath.Join(d, "tables"), 0o755); err != nil {
		return nil, err
	}
	meta := oj.Obj("name", name, "note", note, "created", Now(), "updated", Now(), "by", actor)
	if err := writeJSON(filepath.Join(d, "meta.json"), meta); err != nil {
		return nil, err
	}
	text := fmt.Sprintf("新建变体「%s」", name)
	if note != "" {
		text += "：" + note
	}
	w.Log(actor, "variant", text, "variant", name)
	return meta, nil
}

// simVariantDirs 是 out/sim/*/variants/<name>。
func (w *Workspace) simVariantDirs(name string) []string {
	dirs, _ := filepath.Glob(filepath.Join(w.P.Out, "sim", "*", "variants"))
	var out []string
	for _, d := range dirs {
		if p := filepath.Join(d, name); exists(p) {
			out = append(out, p)
		}
	}
	return out
}

// DeleteVariant 删除变体及其模拟结果。
func (w *Workspace) DeleteVariant(name, actor string) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	d, err := w.variantDir(name)
	if err != nil {
		return err
	}
	if !exists(d) {
		return userErr("没有这个变体：%s", name)
	}
	if err := os.RemoveAll(d); err != nil {
		return err
	}
	for _, sims := range w.simVariantDirs(name) {
		os.RemoveAll(sims)
	}
	w.Log(actor, "variant", fmt.Sprintf("删除变体「%s」", name))
	return nil
}

func (w *Workspace) touch(variant, actor string) error {
	d, err := w.variantDir(variant)
	if err != nil {
		return err
	}
	metaPath := filepath.Join(d, "meta.json")
	meta, err := readObject(metaPath)
	if err != nil {
		return err
	}
	meta.Set("updated", Now()).Set("by", actor)
	return writeJSON(metaPath, meta)
}

// ChangedFiles 列出变体里的文件（不带 .json，如 "units"、"battles/1-4"）。
func (w *Workspace) ChangedFiles(variant string) ([]string, error) {
	dir, err := w.variantDir(variant)
	if err != nil {
		return nil, err
	}
	d := filepath.Join(dir, "tables")
	out := []string{}
	filepath.WalkDir(d, func(path string, e fs.DirEntry, err error) error {
		if err == nil && !e.IsDir() && strings.HasSuffix(e.Name(), ".json") {
			rel, _ := filepath.Rel(d, path)
			out = append(out, strings.TrimSuffix(filepath.ToSlash(rel), ".json"))
		}
		return nil
	})
	sort.Strings(out)
	return out, nil
}

// --- 数据 ---------------------------------------------------------------------------------------

// Data 是生效的数据表（基线叠上变体）。
type Data struct {
	Units, Skills, SkillTree *oj.Object
	Battles                  *oj.Object // 按 (order, id) 排序
}

// Table 按名字取表。
func (d *Data) Table(name string) *oj.Object {
	switch name {
	case "units":
		return d.Units
	case "skills":
		return d.Skills
	case "skill_tree":
		return d.SkillTree
	}
	return nil
}

func battleIDs(dir string) []string {
	files, _ := filepath.Glob(filepath.Join(dir, "*.json"))
	out := make([]string, len(files))
	for i, f := range files {
		out[i] = strings.TrimSuffix(filepath.Base(f), ".json")
	}
	return out
}

// Load 读生效的数据表。
func (w *Workspace) Load(variant string) (*Data, error) {
	over, err := w.OverlayDir(variant)
	if err != nil {
		return nil, err
	}
	pick := func(rel string) string {
		if over != "" {
			if p := filepath.Join(over, filepath.FromSlash(rel)); exists(p) {
				return p
			}
		}
		return filepath.Join(w.P.Tables, filepath.FromSlash(rel))
	}
	d := &Data{}
	for i, dst := range []**oj.Object{&d.Units, &d.Skills, &d.SkillTree} {
		if *dst, err = readObject(pick(tableNames[i] + ".json")); err != nil {
			return nil, err
		}
	}
	ids := battleIDs(filepath.Join(w.P.Tables, "battles"))
	if over != "" {
		ids = append(ids, battleIDs(filepath.Join(over, "battles"))...)
	}
	battles := map[string]*oj.Object{}
	for _, id := range ids {
		if battles[id] != nil {
			continue
		}
		if battles[id], err = readObject(pick("battles/" + id + ".json")); err != nil {
			return nil, err
		}
	}
	uniq := make([]string, 0, len(battles))
	for id := range battles {
		uniq = append(uniq, id)
	}
	sort.Slice(uniq, func(i, j int) bool {
		a, b := battles[uniq[i]].Float("order", 0), battles[uniq[j]].Float("order", 0)
		if a != b {
			return a < b
		}
		return uniq[i] < uniq[j]
	})
	d.Battles = oj.NewObject()
	for _, id := range uniq {
		d.Battles.Set(id, battles[id])
	}
	return d, nil
}

func canon(v any) string { return oj.Dump(v, oj.Canon) }

// RulesHash 是规则代码的哈希：规则变了，旧的模拟结果就过期。
func (w *Workspace) RulesHash() string {
	h := sha1.New()
	for _, src := range w.Rules {
		type file struct {
			path  string
			parts []string
		}
		var files []file
		filepath.WalkDir(src.Dir, func(path string, e fs.DirEntry, err error) error {
			if err != nil || e.IsDir() || !strings.HasSuffix(e.Name(), src.Ext) {
				return nil
			}
			if src.Ext == ".go" && strings.HasSuffix(e.Name(), "_test.go") {
				return nil
			}
			rel, _ := filepath.Rel(src.Dir, path)
			files = append(files, file{path, strings.Split(strings.ToLower(filepath.ToSlash(rel)), "/")})
			return nil
		})
		// 和 Python 的 sorted(Path.rglob()) 一样：逐段比较路径，Windows 上不分大小写
		sort.Slice(files, func(i, j int) bool {
			a, b := files[i].parts, files[j].parts
			for k := 0; k < len(a) && k < len(b); k++ {
				if a[k] != b[k] {
					return a[k] < b[k]
				}
			}
			return len(a) < len(b)
		})
		for _, f := range files {
			if data, err := os.ReadFile(f.path); err == nil {
				h.Write(data)
			}
		}
	}
	return hex.EncodeToString(h.Sum(nil))[:10]
}

// BattleHash 标识一场战斗的模拟所依赖的一切（数据 + 规则代码）。
func (w *Workspace) BattleHash(d *Data, battle string) string {
	b := oj.NewObject()
	src := d.Battles.Object(battle)
	for _, k := range src.Keys() {
		if k != "note" && k != "title" && k != "order" {
			b.Set(k, src.Get(k))
		}
	}
	payload := canon([]any{b, d.Units, d.Skills, d.SkillTree}) + w.RulesHash()
	sum := sha1.Sum([]byte(payload))
	return hex.EncodeToString(sum[:])[:12]
}

func (w *Workspace) schema(name string) (*oj.Object, error) { return w.P.Schema(name) }

// SaveBattle 把关卡存进变体（结构必须合法），返回校验问题。
func (w *Workspace) SaveBattle(variant, battleID string, battle *oj.Object, actor, summary string) ([]*oj.Object, error) {
	if IsBaseline(variant) {
		return nil, userErr("基线只读：请先新建变体，再编辑")
	}
	if !battleIDRE.MatchString(battleID) {
		return nil, userErr("关卡编号无效：%s", oj.PyStrRepr(battleID))
	}
	battle = battle.Clone().Set("id", battleID)
	sch, err := w.schema("battle")
	if err != nil {
		return nil, err
	}
	if e := bestError(battle, sch); e != nil {
		return nil, userErr("关卡数据结构不合法：%s", e.Message)
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	over, err := w.OverlayDir(variant)
	if err != nil {
		return nil, err
	}
	target := filepath.Join(over, "battles", battleID+".json")
	base := filepath.Join(w.P.Tables, "battles", battleID+".json")
	if summary == "" { // 给动态里写清楚这次改了什么
		data, err := w.Load(variant)
		if err != nil {
			return nil, err
		}
		before := data.Battles.Object(battleID)
		if before == nil {
			summary = "新建关卡 " + battleID
		} else {
			changes := battleDiff(before, battle)
			for _, kl := range [][2]string{{"title", "名称"}, {"note", "备注"}} {
				if before.Str(kl[0], "") != battle.Str(kl[0], "") {
					changes = append(changes, "改了"+kl[1])
				}
			}
			if len(changes) == 0 {
				return w.Validate(data)
			}
			more := ""
			if len(changes) > 4 {
				changes, more = changes[:4], "……"
			}
			summary = battleID + "：" + strings.Join(changes, "；") + more
		}
	}
	if old, err := readJSON(base); err == nil && canon(old) == canon(battle) {
		os.Remove(target)
	} else if err := writeJSON(target, battle); err != nil {
		return nil, err
	}
	if err := w.touch(variant, actor); err != nil {
		return nil, err
	}
	w.Log(actor, "edit", summary, "variant", variant, "battle", battleID)
	data, err := w.Load(variant)
	if err != nil {
		return nil, err
	}
	return w.Validate(data)
}

// DeleteBattle 删除只存在于变体里的关卡。
func (w *Workspace) DeleteBattle(variant, battleID, actor string) error {
	if strings.ContainsAny(battleID, `/\`) || strings.Contains(battleID, "..") {
		return userErr("关卡编号无效：%s", oj.PyStrRepr(battleID))
	}
	if exists(filepath.Join(w.P.Tables, "battles", battleID+".json")) {
		return userErr("基线里已有的关卡不能在变体中删除")
	}
	over, err := w.OverlayDir(variant)
	if err != nil {
		return err
	}
	if over == "" {
		return fmt.Errorf("基线里没有可以删除的变体关卡")
	}
	os.Remove(filepath.Join(over, "battles", battleID+".json"))
	w.Log(actor, "edit", "删除关卡 "+battleID, "variant", variant, "battle", battleID)
	return nil
}

// SaveTable 把整张数值表存进变体，返回校验问题。
func (w *Workspace) SaveTable(variant, table string, content *oj.Object, actor, summary string) ([]*oj.Object, error) {
	if IsBaseline(variant) {
		return nil, userErr("基线只读：请先新建变体，再编辑")
	}
	known := false
	for _, t := range tableNames {
		known = known || t == table
	}
	if !known {
		return nil, userErr("未知数据表：%s", table)
	}
	sch, err := w.schema(table)
	if err != nil {
		return nil, err
	}
	if e := bestError(content, sch); e != nil {
		return nil, userErr("%s 不合法（%s）：%s", table, e.PathString(), e.Message)
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	over, err := w.OverlayDir(variant)
	if err != nil {
		return nil, err
	}
	target := filepath.Join(over, table+".json")
	base, err := readJSON(filepath.Join(w.P.Tables, table+".json"))
	if err != nil {
		return nil, err
	}
	if canon(base) == canon(content) {
		os.Remove(target)
	} else if err := writeJSON(target, content); err != nil {
		return nil, err
	}
	if err := w.touch(variant, actor); err != nil {
		return nil, err
	}
	if summary == "" {
		summary = "修改数值表 " + table
	}
	w.Log(actor, "edit", summary, "variant", variant)
	data, err := w.Load(variant)
	if err != nil {
		return nil, err
	}
	return w.Validate(data)
}

func copyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	return os.WriteFile(dst, data, 0o644)
}

// Adopt 把变体的文件覆盖到基线，并把它仍然有效的模拟结果挪到基线的位置。
func (w *Workspace) Adopt(variant, actor string) ([]string, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	data, err := w.Load(variant)
	if err != nil {
		return nil, err
	}
	issues, err := w.Validate(data)
	if err != nil {
		return nil, err
	}
	var errs []string
	for _, i := range issues {
		if i.Str("level", "") == "error" {
			errs = append(errs, i.Str("message", ""))
		}
	}
	if len(errs) > 0 {
		return nil, userErr("变体还有未解决的错误，不能采用：%s", strings.Join(errs[:min(3, len(errs))], "；"))
	}
	over, err := w.OverlayDir(variant)
	if err != nil {
		return nil, err
	}
	if over == "" {
		return nil, userErr("变体名称无效：%s（只能用字母、数字、中文、- 和 _）", oj.PyStrRepr(variant))
	}
	files, err := w.ChangedFiles(variant)
	if err != nil {
		return nil, err
	}
	if len(files) == 0 {
		return nil, userErr("这个变体和基线没有差别")
	}
	diffs, err := w.Diff(variant)
	if err != nil {
		return nil, err
	}
	var lines []string
	for _, f := range diffs {
		for _, l := range f.Array("lines") {
			lines = append(lines, l.(string))
		}
	}
	for _, rel := range files {
		if err := copyFile(filepath.Join(over, filepath.FromSlash(rel)+".json"),
			filepath.Join(w.P.Tables, filepath.FromSlash(rel)+".json")); err != nil {
			return nil, err
		}
	}
	for _, sims := range w.simVariantDirs(variant) {
		battleDir := filepath.Dir(filepath.Dir(sims))
		battle := filepath.Base(battleDir)
		bots, _ := os.ReadDir(sims)
		for _, bot := range bots {
			botDir := filepath.Join(sims, bot.Name())
			meta, err := readObject(filepath.Join(botDir, "meta.json"))
			if err != nil || !data.Battles.Has(battle) || meta.Str("hash", "") != w.BattleHash(data, battle) {
				continue
			}
			dest := filepath.Join(battleDir, bot.Name())
			os.RemoveAll(dest)
			if err := os.Rename(botDir, dest); err != nil {
				return nil, err
			}
		}
		os.RemoveAll(sims)
	}
	dir, _ := w.variantDir(variant)
	if err := os.RemoveAll(dir); err != nil {
		return nil, err
	}
	more := ""
	if len(lines) > 6 {
		lines, more = lines[:6], "……"
	}
	w.Log(actor, "adopt", fmt.Sprintf("采用变体「%s」为新基线：%s%s", variant, strings.Join(lines, "；"), more))
	return files, nil
}

// --- 动态 ---------------------------------------------------------------------------------------

// OnActivity 注册动态监听（服务器用它把动态推给浏览器）。
func (w *Workspace) OnActivity(fn func(entry *oj.Object)) {
	w.logMu.Lock()
	defer w.logMu.Unlock()
	w.listeners = append(w.listeners, fn)
}

// Log 记一条动态；extra 是 k1, v1, k2, v2…
func (w *Workspace) Log(actor, kind, text string, extra ...any) *oj.Object {
	entry := oj.Obj("ts", Now(), "actor", actor, "kind", kind, "text", text)
	for i := 0; i+1 < len(extra); i += 2 {
		entry.Set(extra[i].(string), extra[i+1])
	}
	w.logMu.Lock()
	os.MkdirAll(w.P.Workspace, 0o755)
	if f, err := os.OpenFile(w.activityPath(), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644); err == nil {
		f.WriteString(oj.Dump(entry, oj.Default) + "\n")
		f.Close()
	}
	listeners := append([]func(*oj.Object){}, w.listeners...)
	w.logMu.Unlock()
	for _, fn := range listeners {
		fn(entry)
	}
	return entry
}

// Activity 返回最近 limit 条动态，最新的在前。
func (w *Workspace) Activity(limit int) ([]any, error) {
	data, err := os.ReadFile(w.activityPath())
	if err != nil {
		return []any{}, nil
	}
	var lines []string
	for _, l := range strings.Split(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n") {
		if l != "" {
			lines = append(lines, l)
		}
	}
	// 和 Python 的 lines[-limit:] 一样：limit 为 0 时是全部，为负时从头跳过 |limit| 条
	start := len(lines) - limit
	if limit <= 0 {
		start = -limit
	}
	start = max(0, min(start, len(lines)))
	lines = lines[start:]
	out := make([]any, 0, len(lines))
	for i := len(lines) - 1; i >= 0; i-- {
		v, err := oj.Parse([]byte(lines[i]))
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, nil
}
