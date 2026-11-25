package studio

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"srpg/rules"
	"srpg/sim"
)

// 支援对比：每一关换着带每一位雇得到的英雄，看胜率差多少。和命令行的 srpg supports 是
// 同一份逻辑（sim.CompareSupports）；这里把结果按变体存盘，跑的时候一格一格推给浏览器。

type supportReport struct {
	Variant  string            `json:"variant"`
	Finished string            `json:"finished"`
	By       string            `json:"by"`
	Cells    []sim.SupportCell `json:"cells"`
	Hashes   map[string]string `json:"hashes"`
}

type supportRun struct {
	mu      sync.Mutex
	running bool
	variant string
	scope   string
	actor   string
	done    int
	total   int
	errMsg  string
	cells   []sim.SupportCell
	cancel  context.CancelFunc
}

func (r *supportRun) snapshot() map[string]any {
	return map[string]any{"running": r.running, "variant": r.variant, "scope": r.scope, "actor": r.actor,
		"done": r.done, "total": r.total, "error": r.errMsg, "cells": append([]sim.SupportCell{}, r.cells...)}
}

func (s *Server) supportReportPath(variant string) string {
	return filepath.Join(s.cfg.Paths.Out, "supports", orBaselineName(variant)+".json")
}

func (s *Server) loadSupportReport(variant string) *supportReport {
	raw, err := os.ReadFile(s.supportReportPath(variant))
	if err != nil {
		return nil
	}
	var rep supportReport
	if json.Unmarshal(raw, &rep) != nil {
		return nil
	}
	return &rep
}

// variantData 读入一个变体的数据表（基线传空串）。
func (s *Server) variantData(variant string) (*Data, *rules.Data, error) {
	d, err := s.WS.Load(variant)
	if err != nil {
		return nil, nil, err
	}
	overlay, err := s.WS.OverlayDir(variant)
	if err != nil {
		return nil, nil, err
	}
	data, err := rules.LoadData(rules.DataOptions{Root: s.cfg.Paths.Tables, Overlay: overlay})
	if err != nil {
		return nil, nil, userErr("数据表有错，先修正：%v", err)
	}
	return d, data, nil
}

func (s *Server) supportView(variant string) (any, error) {
	spec, err := sim.LoadDifficulty(s.difficultyPath())
	if err != nil {
		return nil, userErr("读不了难度目标：%v", err)
	}
	d, data, err := s.variantData(variant)
	if err != nil {
		return nil, err
	}
	market, err := data.Market()
	if err != nil {
		return nil, err
	}
	order, err := sim.CampaignOrder(data)
	if err != nil {
		return nil, err
	}
	type hero struct {
		ID       string `json:"id"`
		Name     string `json:"name"`
		Fee      int    `json:"fee"`
		Opens    int    `json:"opens"`
		Move     string `json:"move"`
		Kind     string `json:"kind"`
		Power    int    `json:"power"`
		Range    int    `json:"range"`
		Cooldown int    `json:"cooldown"`
	}
	var heroes []hero
	first := 99
	for id, r := range market.Recruits {
		h := hero{ID: id, Name: r.Name, Fee: r.Fee, Opens: r.Opens}
		if sk := data.Skill(r.Support); sk != nil {
			h.Move, h.Kind, h.Power, h.Range, h.Cooldown = sk.Name, sk.Support, sk.Power, sk.MaxRange, sk.Cooldown
		}
		heroes = append(heroes, h)
		first = min(first, r.Opens)
	}
	sort.Slice(heroes, func(i, j int) bool {
		if heroes[i].Opens != heroes[j].Opens {
			return heroes[i].Opens < heroes[j].Opens
		}
		return heroes[i].Fee < heroes[j].Fee
	})
	type battleRow struct {
		ID      string     `json:"id"`
		Title   string     `json:"title"`
		Chapter int        `json:"chapter"`
		Kind    string     `json:"kind"`
		Primary []string   `json:"primary"`
		Band    [2]float64 `json:"band"`
		Hash    string     `json:"hash"`
	}
	var battles []battleRow
	for _, id := range order {
		if rules.Chapter(id) < first {
			continue
		}
		kit, bot := spec.PrimaryOf(id)
		kind := spec.KindOf(id)
		title := ""
		if b := d.Battles.Object(id); b != nil {
			title = b.Str("title", "")
		}
		battles = append(battles, battleRow{ID: id, Title: title, Chapter: rules.Chapter(id), Kind: kind,
			Primary: []string{kit, bot}, Band: spec.Bands[kind][kit][bot], Hash: s.WS.BattleHash(d, id)})
	}
	s.sup.mu.Lock()
	run := s.sup.snapshot()
	s.sup.mu.Unlock()
	return viaJSON(map[string]any{"variant": orBaselineName(variant), "runs": spec.Runs, "heroes": heroes, "battles": battles,
		"report": s.loadSupportReport(variant), "run": run})
}

func (s *Server) startSupports(variant, scope string, runs int, actor string) (any, error) {
	spec, err := sim.LoadDifficulty(s.difficultyPath())
	if err != nil {
		return nil, userErr("读不了难度目标：%v", err)
	}
	if runs < 0 || runs > 5000 {
		return nil, userErr("局数必须在 1 到 5000 之间")
	}
	d, data, err := s.variantData(variant)
	if err != nil {
		return nil, err
	}
	opts := sim.SupportOptions{Runs: runs, Workers: s.cfg.Workers, KitsPath: s.cfg.Paths.Kits()}
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
	s.sup.mu.Lock()
	if s.sup.running {
		s.sup.mu.Unlock()
		return nil, userErr("已经有一次支援对比在跑，等它结束或先取消")
	}
	ctx, cancel := context.WithCancel(context.Background())
	r := s.sup
	r.running, r.variant, r.scope, r.actor, r.cancel = true, orBaselineName(variant), scope, actor, cancel
	r.done, r.total, r.errMsg, r.cells = 0, 0, "", nil
	snap := r.snapshot()
	s.sup.mu.Unlock()
	s.WS.Log(actor, "sim", "开始支援对比："+label, "variant", orBaselineName(variant))
	s.bus.publish("supports", mustJSON(snap))

	hashes := map[string]string{}
	opts.OnCell = func(c sim.SupportCell, done, total int) {
		hashes[c.Battle] = s.WS.BattleHash(d, c.Battle)
		s.sup.mu.Lock()
		s.sup.cells = append(s.sup.cells, c)
		s.sup.done, s.sup.total = done, total
		snap := s.sup.snapshot()
		s.sup.mu.Unlock()
		s.bus.publish("supports", mustJSON(snap))
	}
	go func() {
		cells, err := sim.CompareSupports(ctx, data, spec, opts)
		cancelled := ctx.Err() != nil
		cancel()
		msg := ""
		if err != nil && !cancelled {
			msg = err.Error()
		}
		if len(cells) > 0 {
			if saveErr := s.mergeSupports(variant, actor, cells, hashes); saveErr != nil && msg == "" {
				msg = saveErr.Error()
			}
		}
		s.sup.mu.Lock()
		s.sup.running, s.sup.errMsg = false, msg
		snap := s.sup.snapshot()
		s.sup.mu.Unlock()
		switch {
		case msg != "":
			s.WS.Log(actor, "sim", "支援对比失败："+label, "variant", orBaselineName(variant))
		case cancelled:
			s.WS.Log(actor, "sim", "取消支援对比："+label, "variant", orBaselineName(variant))
		default:
			s.WS.Log(actor, "sim", supportHeadline(label, data, cells), "variant", orBaselineName(variant))
		}
		s.bus.publish("supports", mustJSON(snap))
	}()
	return viaJSON(snap)
}

// supportHeadline 说出差得最多的那一关：带谁最好、带谁最差、差多少。
func supportHeadline(label string, data *rules.Data, cells []sim.SupportCell) string {
	market, _ := data.Market()
	name := func(id string) string {
		if market != nil {
			if r := market.Recruits[id]; r != nil {
				return r.Name
			}
		}
		return "不带"
	}
	type span struct {
		best, worst sim.SupportCell
		seen        bool
	}
	by := map[string]*span{}
	for _, c := range cells {
		if c.Support == "none" {
			continue
		}
		sp := by[c.Battle]
		if sp == nil {
			sp = &span{}
			by[c.Battle] = sp
		}
		if !sp.seen || c.Win > sp.best.Win {
			sp.best = c
		}
		if !sp.seen || c.Win < sp.worst.Win {
			sp.worst = c
		}
		sp.seen = true
	}
	widest, gap := "", -1.0
	for b, sp := range by {
		if g := sp.best.Win - sp.worst.Win; g > gap {
			widest, gap = b, g
		}
	}
	if widest == "" {
		return "支援对比（" + label + "）跑完了"
	}
	sp := by[widest]
	return fmt.Sprintf("支援对比（%s）：差得最多的是 %s，带%s %.0f%%、带%s %.0f%%", label, widest,
		name(sp.best.Support), sp.best.Win*100, name(sp.worst.Support), sp.worst.Win*100)
}

func (s *Server) mergeSupports(variant, actor string, cells []sim.SupportCell, hashes map[string]string) error {
	rep := s.loadSupportReport(variant)
	if rep == nil {
		rep = &supportReport{}
	}
	if rep.Hashes == nil {
		rep.Hashes = map[string]string{}
	}
	fresh := map[[2]string]bool{}
	for _, c := range cells {
		fresh[[2]string{c.Battle, c.Support}] = true
	}
	kept := rep.Cells[:0]
	for _, c := range rep.Cells {
		if !fresh[[2]string{c.Battle, c.Support}] {
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
	path := s.supportReportPath(variant)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, append(raw, '\n'), 0o644)
}

func (s *Server) supportRoutes() {
	s.handle("GET /api/supports", func(r *http.Request) (any, error) {
		return s.supportView(r.URL.Query().Get("variant"))
	})
	s.handle("POST /api/supports/run", func(r *http.Request) (any, error) {
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
		return s.startSupports(variant, scope, runs, actor(r))
	})
	s.handle("POST /api/supports/cancel", func(r *http.Request) (any, error) {
		s.sup.mu.Lock()
		if s.sup.running && s.sup.cancel != nil {
			s.sup.cancel()
		}
		snap := s.sup.snapshot()
		s.sup.mu.Unlock()
		return viaJSON(snap)
	})
}
