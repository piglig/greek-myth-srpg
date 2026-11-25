package studio

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"gopkg.in/yaml.v3"

	oj "srpg/balance/ordjson"
	"srpg/rules"
	"srpg/sim"
)

// 难度总表：每一关在每种"配置 × 水平"下的胜率，对着 balance/difficulty.yaml 的目标区间判定。
// 和命令行的 srpg difficulty 是同一份逻辑（sim.Judge）；这里多了三件事：结果按变体存盘、
// 跑的时候一格一格推给浏览器、目标区间可以在界面上（或由 AI 通过接口）改。

// difficultyReport 是一个变体存下来的判定结果。
type difficultyReport struct {
	Variant  string               `json:"variant"`
	Finished string               `json:"finished"`
	By       string               `json:"by"`
	Cells    []sim.DifficultyCell `json:"cells"`
	// Hashes 是每一关模拟时的数据指纹；和现在的对不上，这一关的结果就过期了。
	Hashes map[string]string `json:"hashes"`
}

// difficultyRun 是正在跑的那一次判定（同一时间只有一个）。
type difficultyRun struct {
	mu      sync.Mutex
	running bool
	variant string
	scope   string
	actor   string
	done    int
	total   int
	errMsg  string
	cells   []sim.DifficultyCell
	cancel  context.CancelFunc
}

func (s *Server) difficultyPath() string {
	return filepath.Join(s.cfg.Paths.Balance, "difficulty.yaml")
}

func (s *Server) difficultyReportPath(variant string) string {
	if IsBaseline(variant) {
		variant = Baseline
	}
	return filepath.Join(s.cfg.Paths.Out, "difficulty", variant+".json")
}

// viaJSON 把普通的 Go 值转成响应用的有序 JSON。
func viaJSON(v any) (any, error) {
	raw, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	return oj.Parse(raw)
}

func (s *Server) loadDifficultyReport(variant string) (*difficultyReport, error) {
	raw, err := os.ReadFile(s.difficultyReportPath(variant))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var rep difficultyReport
	if err := json.Unmarshal(raw, &rep); err != nil {
		return nil, nil // 存坏了就当没有，重新跑一遍会覆盖
	}
	return &rep, nil
}

func (r *difficultyRun) snapshot() map[string]any {
	return map[string]any{"running": r.running, "variant": r.variant, "scope": r.scope, "actor": r.actor,
		"done": r.done, "total": r.total, "error": r.errMsg, "cells": append([]sim.DifficultyCell{}, r.cells...)}
}

// difficultyView 是界面要的全部：目标、列、战役顺序、存下来的结果、正在跑的进度。
func (s *Server) difficultyView(variant string) (any, error) {
	spec, err := sim.LoadDifficulty(s.difficultyPath())
	if err != nil {
		return nil, userErr("读不了难度目标：%v", err)
	}
	d, err := s.WS.Load(variant)
	if err != nil {
		return nil, err
	}
	overlay, err := s.WS.OverlayDir(variant)
	if err != nil {
		return nil, err
	}
	data, err := rules.LoadData(rules.DataOptions{Root: s.cfg.Paths.Tables, Overlay: overlay})
	if err != nil {
		return nil, userErr("数据表有错，先修正：%v", err)
	}
	order, err := sim.CampaignOrder(data)
	if err != nil {
		return nil, err
	}
	type battleRow struct {
		ID      string   `json:"id"`
		Title   string   `json:"title"`
		Chapter int      `json:"chapter"`
		Kind    string   `json:"kind"`
		Primary []string `json:"primary"`
		Hash    string   `json:"hash"`
	}
	var battles []battleRow
	for _, id := range order {
		kit, bot := spec.PrimaryOf(id)
		title := ""
		if b := d.Battles.Object(id); b != nil {
			title = b.Str("title", "")
		}
		battles = append(battles, battleRow{ID: id, Title: title, Chapter: rules.Chapter(id), Kind: spec.KindOf(id),
			Primary: []string{kit, bot}, Hash: s.WS.BattleHash(d, id)})
	}
	rep, err := s.loadDifficultyReport(variant)
	if err != nil {
		return nil, err
	}
	s.diff.mu.Lock()
	run := s.diff.snapshot()
	s.diff.mu.Unlock()
	return viaJSON(map[string]any{"variant": orBaselineName(variant), "spec": spec, "columns": spec.Columns(),
		"battles": battles, "report": rep, "run": run})
}

func orBaselineName(v string) string {
	if v == "" {
		return Baseline
	}
	return v
}

// startDifficulty 开始一次判定。scope 是 ""（全部）、章号（"2"）或一关（"2-3"）。
func (s *Server) startDifficulty(variant, scope string, runs int, actor string) (any, error) {
	spec, err := sim.LoadDifficulty(s.difficultyPath())
	if err != nil {
		return nil, userErr("读不了难度目标：%v", err)
	}
	if runs < 0 || runs > 5000 {
		return nil, userErr("局数必须在 1 到 5000 之间")
	}
	d, err := s.WS.Load(variant)
	if err != nil {
		return nil, err
	}
	overlay, err := s.WS.OverlayDir(variant)
	if err != nil {
		return nil, err
	}
	data, err := rules.LoadData(rules.DataOptions{Root: s.cfg.Paths.Tables, Overlay: overlay})
	if err != nil {
		return nil, userErr("数据表有错，先修正再判定：%v", err)
	}
	opts := sim.JudgeOptions{Runs: runs, Workers: s.cfg.Workers, KitsPath: s.cfg.Paths.Kits()}
	label := "全部关卡"
	switch {
	case scope == "":
	case strings.Contains(scope, "-"):
		if !d.Battles.Has(scope) {
			return nil, userErr("没有这个关卡：%s", scope)
		}
		opts.Battle, label = scope, scope
	default:
		n, err := strconv.Atoi(scope)
		if err != nil || n < 1 {
			return nil, userErr("范围要么留空，要么是章号（2），要么是一关（2-3）")
		}
		opts.Chapter, label = n, fmt.Sprintf("第 %d 章", n)
	}

	s.diff.mu.Lock()
	if s.diff.running {
		s.diff.mu.Unlock()
		return nil, userErr("已经有一次难度判定在跑，等它结束或先取消")
	}
	ctx, cancel := context.WithCancel(context.Background())
	r := s.diff
	r.running, r.variant, r.scope, r.actor, r.cancel = true, orBaselineName(variant), scope, actor, cancel
	r.done, r.total, r.errMsg, r.cells = 0, 0, "", nil
	snap := s.diff.snapshot()
	s.diff.mu.Unlock()
	s.WS.Log(actor, "sim", "开始难度判定："+label, "variant", orBaselineName(variant))
	s.bus.publish("difficulty", mustJSON(snap))

	hashes := map[string]string{}
	opts.OnCell = func(c sim.DifficultyCell, done, total int) {
		hashes[c.Battle] = s.WS.BattleHash(d, c.Battle)
		s.diff.mu.Lock()
		s.diff.cells = append(s.diff.cells, c)
		s.diff.done, s.diff.total = done, total
		snap := s.diff.snapshot()
		s.diff.mu.Unlock()
		s.bus.publish("difficulty", mustJSON(snap))
	}
	go func() {
		cells, err := sim.Judge(ctx, data, spec, opts)
		cancelled := ctx.Err() != nil
		cancel()
		msg := ""
		if err != nil && !cancelled {
			msg = err.Error()
		}
		// 跑完的格子都留下，哪怕中途取消：并进这个变体存着的结果里，同一关的旧格子被换掉。
		if len(cells) > 0 {
			if saveErr := s.mergeDifficulty(variant, actor, cells, hashes); saveErr != nil && msg == "" {
				msg = saveErr.Error()
			}
		}
		s.diff.mu.Lock()
		s.diff.running, s.diff.errMsg = false, msg
		snap := s.diff.snapshot()
		s.diff.mu.Unlock()
		switch {
		case msg != "":
			s.WS.Log(actor, "sim", "难度判定失败："+label, "variant", orBaselineName(variant))
		case cancelled:
			s.WS.Log(actor, "sim", "取消难度判定："+label, "variant", orBaselineName(variant))
		default:
			s.WS.Log(actor, "sim", difficultyHeadline(label, cells), "variant", orBaselineName(variant))
		}
		s.bus.publish("difficulty", mustJSON(snap))
	}()
	return viaJSON(snap)
}

func mustJSON(v any) any {
	out, err := viaJSON(v)
	if err != nil {
		return oj.Obj("error", err.Error())
	}
	return out
}

func difficultyHeadline(label string, cells []sim.DifficultyCell) string {
	total, ok := 0, 0
	var off []string
	for _, c := range cells {
		if !c.Primary {
			continue
		}
		total++
		if c.Verdict == "ok" {
			ok++
		} else {
			word := "偏易"
			if c.Verdict == "hard" {
				word = "偏难"
			}
			off = append(off, fmt.Sprintf("%s %s（%.0f%%）", c.Battle, word, c.Win*100))
		}
	}
	text := fmt.Sprintf("难度判定（%s）：%d 关里 %d 关达标", label, total, ok)
	if len(off) > 0 {
		text += "；" + strings.Join(off[:min(4, len(off))], "、")
		if len(off) > 4 {
			text += " 等"
		}
	}
	return text
}

func (s *Server) mergeDifficulty(variant, actor string, cells []sim.DifficultyCell, hashes map[string]string) error {
	rep, err := s.loadDifficultyReport(variant)
	if err != nil {
		return err
	}
	if rep == nil {
		rep = &difficultyReport{Hashes: map[string]string{}}
	}
	if rep.Hashes == nil {
		rep.Hashes = map[string]string{}
	}
	// 只换掉重新跑完整了的关；被取消时半截的那一关（没有主要验收格之后的格子）也照样替换它跑过的格。
	fresh := map[[3]string]bool{}
	for _, c := range cells {
		fresh[[3]string{c.Battle, c.Kit, c.Bot}] = true
	}
	kept := rep.Cells[:0]
	for _, c := range rep.Cells {
		if !fresh[[3]string{c.Battle, c.Kit, c.Bot}] {
			kept = append(kept, c)
		}
	}
	rep.Cells = append(kept, cells...)
	for b, h := range hashes {
		rep.Hashes[b] = h
	}
	rep.Variant, rep.Finished, rep.By = orBaselineName(variant), time.Now().Format("2006-01-02T15:04:05"), actor
	raw, err := json.MarshalIndent(rep, "", " ")
	if err != nil {
		return err
	}
	path := s.difficultyReportPath(variant)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, append(raw, '\n'), 0o644)
}

func (s *Server) cancelDifficulty() (any, error) {
	s.diff.mu.Lock()
	if s.diff.running && s.diff.cancel != nil {
		s.diff.cancel()
	}
	snap := s.diff.snapshot()
	s.diff.mu.Unlock()
	return viaJSON(snap)
}

// setDifficultyBand 改一格目标区间，保留文件里的注释和排版。
func (s *Server) setDifficultyBand(kind, kit, bot string, lo, hi float64, actor string) error {
	if !(lo >= 0 && hi <= 1 && lo <= hi) {
		return userErr("区间要在 0%% 到 100%% 之间，下限不能高于上限")
	}
	raw, err := os.ReadFile(s.difficultyPath())
	if err != nil {
		return err
	}
	var doc yaml.Node
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		return userErr("difficulty.yaml 读不了：%v", err)
	}
	child := func(n *yaml.Node, key string) *yaml.Node {
		if n == nil || n.Kind != yaml.MappingNode {
			return nil
		}
		for i := 0; i+1 < len(n.Content); i += 2 {
			if n.Content[i].Value == key {
				return n.Content[i+1]
			}
		}
		return nil
	}
	if len(doc.Content) == 0 {
		return userErr("difficulty.yaml 是空的")
	}
	band := child(child(child(child(doc.Content[0], "bands"), kind), kit), bot)
	if band == nil || band.Kind != yaml.SequenceNode || len(band.Content) != 2 {
		return userErr("目标表里没有这一格：%s / %s / %s", kind, kit, bot)
	}
	band.Content[0].Value = strconv.FormatFloat(lo, 'f', 2, 64)
	band.Content[1].Value = strconv.FormatFloat(hi, 'f', 2, 64)
	var out strings.Builder
	enc := yaml.NewEncoder(&out)
	enc.SetIndent(2)
	if err := enc.Encode(&doc); err != nil {
		return err
	}
	enc.Close()
	if err := os.WriteFile(s.difficultyPath(), []byte(out.String()), 0o644); err != nil {
		return err
	}
	s.WS.Log(actor, "edit", fmt.Sprintf("难度目标 %s / %s / %s 改为 %.0f%%–%.0f%%", kind, kit, bot, lo*100, hi*100))
	// 目标变了，已有的胜率不变，判定要重算：把存着的每份结果按新区间重新定论。
	spec, err := sim.LoadDifficulty(s.difficultyPath())
	if err != nil {
		return err
	}
	files, _ := filepath.Glob(filepath.Join(s.cfg.Paths.Out, "difficulty", "*.json"))
	for _, f := range files {
		variant := strings.TrimSuffix(filepath.Base(f), ".json")
		rep, err := s.loadDifficultyReport(variant)
		if err != nil || rep == nil {
			continue
		}
		for i := range rep.Cells {
			c := &rep.Cells[i]
			b, ok := spec.Bands[spec.KindOf(c.Battle)][c.Kit][c.Bot]
			if !ok {
				continue
			}
			c.Kind, c.Lo, c.Hi, c.Verdict = spec.KindOf(c.Battle), b[0], b[1], "ok"
			if c.Win > c.Hi+1e-9 {
				c.Verdict = "easy"
			} else if c.Win < c.Lo-1e-9 {
				c.Verdict = "hard"
			}
		}
		if raw, err := json.MarshalIndent(rep, "", " "); err == nil {
			os.WriteFile(f, append(raw, '\n'), 0o644)
		}
	}
	s.bus.publish("difficulty", oj.Obj("targets", true))
	return nil
}

func (s *Server) difficultyRoutes() {
	s.handle("GET /api/difficulty", func(r *http.Request) (any, error) {
		return s.difficultyView(r.URL.Query().Get("variant"))
	})
	s.handle("POST /api/difficulty/run", func(r *http.Request) (any, error) {
		b, err := body(r)
		if err != nil {
			return nil, err
		}
		variant, scope := "", ""
		if b.Get("variant") != nil {
			if variant, err = strField(b, "variant", "", false); err != nil {
				return nil, err
			}
		}
		if b.Get("scope") != nil {
			if scope, err = strField(b, "scope", "", false); err != nil {
				return nil, err
			}
		}
		runs, err := intField(b, "runs", 0)
		if err != nil {
			return nil, err
		}
		return s.startDifficulty(variant, scope, runs, actor(r))
	})
	s.handle("POST /api/difficulty/cancel", func(r *http.Request) (any, error) { return s.cancelDifficulty() })
	s.handle("PUT /api/difficulty/bands", func(r *http.Request) (any, error) {
		b, err := body(r)
		if err != nil {
			return nil, err
		}
		var f [3]string
		for i, key := range []string{"kind", "kit", "bot"} {
			if f[i], err = strField(b, key, "", true); err != nil {
				return nil, err
			}
		}
		lo, okLo := oj.Float(b.Get("lo"))
		hi, okHi := oj.Float(b.Get("hi"))
		if !okLo || !okHi {
			return nil, badType("Input should be a valid number", "body", "lo")
		}
		if err := s.setDifficultyBand(f[0], f[1], f[2], lo, hi, actor(r)); err != nil {
			return nil, err
		}
		return oj.Obj("ok", true), nil
	})
}
