package studio

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"

	"srpg/balance"
	oj "srpg/balance/ordjson"
)

// 把模拟结果变成工坊要画的 JSON：判定、分布、热力图。

var (
	// Bots 是工坊认识的机器人。
	Bots = oj.Obj("skilled", "熟练机器人", "novice", "新手机器人")
	// Results 是结局的中文名。
	Results = oj.Obj("win", "胜利", "loss_hero", "主角倒下", "loss_wipe", "全灭", "timeout", "超时")
	sources = map[string]string{"fall": "坠落", "choke": "窒息", "collision": "撞击", "edge": "坠出边缘", "assist": "援护"}
	// mechanics 的顺序就是图表里的顺序
	mechanics = [][2]string{{"grapple_start", "擒抱"}, {"fall_enemy", "敌人坠落"}, {"knockback", "击退"}, {"mark", "标记"},
		{"assist", "援护"}, {"collision", "撞击"}, {"slam", "摔投"}, {"intercept", "截击"}, {"leap", "跃射"},
		{"broken", "破势"}, {"struggle", "敌人挣扎"}, {"edge", "坠出边缘"}, {"push", "推巨石"}, {"sealed", "封住入口"},
		{"retreat", "Boss 退入洞内"}, {"emerge", "Boss 冲出"}}
)

func botLabel(bot string) string { return Bots.Str(bot, bot) }

func (w *Workspace) botDir(battle, variant, bot string) string {
	if IsBaseline(variant) {
		variant = ""
	}
	return w.P.RunDir(battle, bot, variant)
}

// ReadMeta 读某个机器人结果旁边的 meta.json（没有则为 nil）。
func (w *Workspace) ReadMeta(battle, variant, bot string) *oj.Object {
	meta, err := readObject(filepath.Join(w.botDir(battle, variant, bot), "meta.json"))
	if err != nil {
		return nil
	}
	return meta
}

// WriteMeta 写 meta.json。
func (w *Workspace) WriteMeta(battle, variant, bot string, meta *oj.Object) error {
	return os.WriteFile(filepath.Join(w.botDir(battle, variant, bot), "meta.json"), []byte(oj.Dump(meta, oj.Default)), 0o644)
}

// LoadTargets 读目标文件的原样内容（没有则为 nil）。
func (w *Workspace) LoadTargets(battle string) (*balance.Spec, error) {
	if !battleIDRE.MatchString(battle) {
		return nil, nil
	}
	return w.P.LoadTargets(battle)
}

// SaveTargets 校验并写回 targets/<battle>.yaml。
func (w *Workspace) SaveTargets(battle string, spec *oj.Object) error {
	if !battleIDRE.MatchString(battle) {
		return userErr("关卡编号无效：%s", oj.PyStrRepr(battle))
	}
	bots := spec.Object("bots")
	for _, bot := range bots.Keys() {
		rules := bots.Object(bot)
		for _, metric := range rules.Keys() {
			if _, ok := balance.MetricByKey(metric); !ok {
				return userErr("未知指标：%s", metric)
			}
			rule := rules.Get(metric)
			if d, ok := rule.(*oj.Object); ok {
				rule = d.Get("range")
			}
			rng, _ := rule.([]any)
			lo, ok1 := oj.Float(at(rng, 0))
			hi, ok2 := oj.Float(at(rng, 1))
			if len(rng) != 2 || !ok1 || !ok2 || lo > hi {
				return userErr("%s.%s 的范围无效：%s", bot, metric, oj.PyRepr(rule))
			}
		}
	}
	if bots == nil {
		bots = oj.NewObject()
	}
	body := oj.Obj("battle", battle, "runs_min", spec.Int("runs_min", 200), "bots", bots)
	path := w.P.TargetsPath(battle)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte("# 设计目标（由 Balance Studio 写入）。每个指标：[下限, 上限]。\n"+balance.DumpYAML(body)), 0o644)
}

func at(arr []any, i int) any {
	if i < len(arr) {
		return arr[i]
	}
	return nil
}

// MetricCatalog 列出可设目标的指标。
func MetricCatalog() []any {
	out := make([]any, len(balance.Metrics))
	for i, m := range balance.Metrics {
		out[i] = oj.Obj("key", m.Key, "label", m.Label, "pct", m.Pct)
	}
	return out
}

// verdicts 给每个指标一行：有目标的带判定，没有的只给估计值。
func verdicts(df balance.Frame, spec *balance.Spec) ([]any, error) {
	type key struct{ bot, metric string }
	judged := map[key]balance.Verdict{}
	if spec != nil {
		vs, err := balance.Evaluate(df, spec, 0)
		if err != nil {
			return nil, err
		}
		for _, v := range vs {
			judged[key{v.Bot, v.Metric}] = v
		}
	}
	bots := spec.BotNames()
	seen := map[string]bool{}
	for _, b := range bots {
		seen[b] = true
	}
	for _, b := range df.Bots() {
		if !seen[b] {
			seen[b] = true
			bots = append(bots, b)
		}
	}
	out := []any{}
	for _, bot := range bots {
		d := df.OfBot(bot)
		for _, m := range balance.Metrics {
			var est balance.Estimate
			var target any
			status, note := "NO_TARGET", ""
			if v, ok := judged[key{bot, m.Key}]; ok {
				est, status, note = v.Estimate, v.Status, v.Note
				target = v.Target
				if v.Target == nil {
					target = []any{v.Lo, v.Hi}
				}
			} else if d.Len() == 0 {
				continue
			} else {
				est = m.Fn(d, 0)
			}
			row := oj.Obj("bot", bot, "metric", m.Key, "label", m.Label, "pct", m.Pct, "target", target)
			if est.N > 0 && !math.IsNaN(est.Value) {
				row.Set("value", est.Value).Set("lo", est.Lo).Set("hi", est.Hi)
			} else {
				row.Set("value", nil).Set("lo", nil).Set("hi", nil)
			}
			out = append(out, row.Set("n", est.N).Set("status", status).Set("note", note))
		}
	}
	return out, nil
}

// tally 是保留首次出现顺序的计数器（相当于 Python 的 dict 累加）。
type tally struct {
	keys []string
	sum  map[string]float64
}

func newTally() *tally { return &tally{sum: map[string]float64{}} }

func (t *tally) add(k string, v float64) {
	if _, ok := t.sum[k]; !ok {
		t.keys = append(t.keys, k)
	}
	t.sum[k] += v
}

// byValueDesc 按值从大到小排（稳定）。
func (t *tally) byValueDesc() []string {
	keys := append([]string{}, t.keys...)
	sort.SliceStable(keys, func(i, j int) bool { return t.sum[keys[i]] > t.sum[keys[j]] })
	return keys
}

func (t *tally) total() float64 {
	s := 0.0
	for _, v := range t.sum {
		s += v
	}
	return s
}

func cellKey(v any) (string, bool) {
	arr, ok := v.([]any)
	if !ok || len(arr) < 2 {
		return "", false
	}
	return oj.PyRepr(arr[0]) + "," + oj.PyRepr(arr[1]), true
}

func botDetail(runs []*oj.Object, d *Data) *oj.Object {
	n := len(runs)
	fn := float64(n)
	name := func(table *oj.Object, k string) string { return table.Object(k).Str("name", k) }
	outcomes := []any{}
	for _, key := range Results.Keys() {
		k := 0
		for _, r := range runs {
			if r.Str("result", "") == key {
				k++
			}
		}
		e := balance.Proportion(k, n, 0)
		outcomes = append(outcomes, oj.Obj("key", key, "label", Results.Get(key), "count", k, "share", e.Value, "lo", e.Lo, "hi", e.Hi))
	}
	type slot struct{ win, loss int }
	rounds := map[int]*slot{}
	hp := make([]int, 10)
	dealt, taken, src := newTally(), newTally(), newTally()
	heatKills, heatFalls, heatDmg := newTally(), newTally(), newTally()
	table := []any{}
	for _, r := range runs {
		win, _ := r.Get("win").(bool)
		rd := r.Int("rounds", 0)
		if rounds[rd] == nil {
			rounds[rd] = &slot{}
		}
		if win {
			rounds[rd].win++
			hp[min(9, int(r.Float("party_hp_left", 0)*10))]++
		} else {
			rounds[rd].loss++
		}
		units := r.Object("units")
		for _, id := range units.Keys() {
			u := units.Object(id)
			if u.Str("team", "") == "player" {
				dealt.add(u.Str("def", ""), u.Float("dealt", 0))
				taken.add(u.Str("def", ""), u.Float("taken", 0))
			}
		}
		dmg := r.Object("dmg_to_enemy")
		for _, s := range dmg.Keys() {
			src.add(s, dmg.Float(s, 0))
		}
		for _, k := range r.Array("kills") {
			if o, ok := k.(*oj.Object); ok {
				if c, ok := cellKey(o.Get("pos")); ok {
					heatKills.add(c, 1)
				}
			}
		}
		for _, f := range r.Array("falls") {
			if o, ok := f.(*oj.Object); ok {
				if c, ok := cellKey(o.Get("from")); ok {
					heatFalls.add(c, 1)
				}
			}
		}
		cells := r.Object("dmg_cells")
		for _, c := range cells.Keys() {
			heatDmg.add(c, cells.Float(c, 0))
		}
		var hpLeft any = r.Get("party_hp_left")
		if !oj.IsInt(hpLeft) {
			hpLeft = balance.RoundTo(r.Float("party_hp_left", 0), 3)
		}
		table = append(table, oj.Obj("seed", r.Get("seed"), "result", r.Get("result"), "rounds", r.Get("rounds"),
			"hp", hpLeft, "falls", len(r.Array("falls"))))
	}
	roundKeys := make([]int, 0, len(rounds))
	for k := range rounds {
		roundKeys = append(roundKeys, k)
	}
	sort.Ints(roundKeys)
	roundList := []any{}
	for _, k := range roundKeys {
		roundList = append(roundList, oj.Obj("rounds", k, "win", rounds[k].win, "loss", rounds[k].loss))
	}
	hpBins := []any{}
	for i, c := range hp {
		hpBins = append(hpBins, oj.Obj("from", float64(i)/10, "to", float64(i+1)/10, "count", c))
	}
	total := dealt.total()
	if total == 0 {
		total = 1
	}
	damage := []any{}
	for _, def := range dealt.byValueDesc() {
		v := dealt.sum[def]
		damage = append(damage, oj.Obj("def", def, "name", name(d.Units, def), "dealt", v/fn, "taken", taken.sum[def]/fn, "share", v/total))
	}
	stotal := src.total()
	if stotal == 0 {
		stotal = 1
	}
	srcList := []any{}
	for _, s := range src.byValueDesc() {
		label, ok := sources[s]
		if !ok {
			label = name(d.Skills, s)
		}
		srcList = append(srcList, oj.Obj("key", s, "label", label, "per_battle", src.sum[s]/fn, "share", src.sum[s]/stotal))
	}
	mech := []any{}
	for _, m := range mechanics {
		used, sum := 0, 0.0
		for _, r := range runs {
			c := r.Object("counts").Float(m[0], 0)
			sum += c
			if c > 0 {
				used++
			}
		}
		mech = append(mech, oj.Obj("key", m[0], "label", m[1], "battles", float64(used)/fn, "per_battle", sum/fn))
	}
	counts := func(t *tally) *oj.Object {
		o := oj.NewObject()
		for _, k := range t.keys {
			o.Set(k, int(t.sum[k]))
		}
		return o
	}
	dmgHeat := oj.NewObject()
	for _, k := range heatDmg.keys {
		dmgHeat.Set(k, balance.RoundTo(heatDmg.sum[k]/fn, 2))
	}
	heat := oj.Obj("kills", counts(heatKills), "falls", counts(heatFalls), "dmg", dmgHeat)
	return oj.Obj("runs", n, "outcomes", outcomes, "rounds", roundList, "hp", hpBins, "damage", damage,
		"sources", srcList, "mechanics", mech, "heat", heat, "table", table)
}

// Results 是分析页需要的一切：一个关卡在一个变体下的结果。
func (w *Workspace) Results(battle, variant string) (*oj.Object, error) {
	d, err := w.Load(variant)
	if err != nil {
		return nil, err
	}
	if !d.Battles.Has(battle) {
		return nil, userErr("没有这个关卡：%s", battle)
	}
	current := w.BattleHash(d, battle)
	spec, err := w.LoadTargets(battle)
	if err != nil {
		return nil, err
	}
	names := spec.BotNames()
	for _, b := range Bots.Keys() {
		dup := false
		for _, n := range names {
			dup = dup || n == b
		}
		if !dup {
			names = append(names, b)
		}
	}
	bots := oj.NewObject()
	var rows []balance.Run
	have := false
	for _, bot := range names {
		runs, err := balance.ReadRawRuns(filepath.Join(w.botDir(battle, variant, bot), "runs.jsonl"))
		if err != nil {
			return nil, err
		}
		if len(runs) == 0 {
			bots.Set(bot, oj.Obj("label", botLabel(bot), "status", "none"))
			continue
		}
		have = true
		meta := w.ReadMeta(battle, variant, bot)
		status := "unknown"
		entry := oj.Obj("label", botLabel(bot))
		if meta != nil {
			status = "stale"
			if meta.Str("hash", "") == current {
				status = "fresh"
			}
			entry.Set("status", status).Set("meta", meta)
		} else {
			entry.Set("status", status).Set("meta", nil)
		}
		detail := botDetail(runs, d)
		for _, k := range detail.Keys() {
			entry.Set(k, detail.Get(k))
		}
		bots.Set(bot, entry)
		for _, r := range runs {
			rows = append(rows, balance.RunFromObject(r))
		}
	}
	vs := []any{}
	if have || spec != nil {
		if vs, err = verdicts(balance.NewFrame(rows), spec); err != nil {
			return nil, err
		}
	}
	out := oj.Obj("battle", battle, "variant", variant, "hash", current, "bots", bots, "verdicts", vs)
	if variant == "" {
		out.Set("variant", Baseline)
	}
	if spec != nil {
		runsMin := 200
		if spec.HasRunsMin {
			runsMin = spec.RunsMin
		}
		return out.Set("targets", spec.Raw).Set("runs_min", runsMin), nil
	}
	return out.Set("targets", nil).Set("runs_min", 200), nil
}

// Summary 是对比表用的精简结果。
func (w *Workspace) Summary(battle, variant string) (*oj.Object, error) {
	r, err := w.Results(battle, variant)
	if err != nil {
		return nil, err
	}
	bots := oj.NewObject()
	src := r.Object("bots")
	for _, b := range src.Keys() {
		v := src.Object(b)
		bots.Set(b, oj.Obj("status", v.Get("status"), "runs", v.Int("runs", 0)))
	}
	return oj.Obj("variant", r.Get("variant"), "verdicts", r.Get("verdicts"), "bots", bots), nil
}

// headline 是模拟完成后写进动态的一句话。
func (w *Workspace) headline(battle, variant string, bots []string, used map[string]int) string {
	r, err := w.Results(battle, variant)
	if err != nil || len(bots) == 0 {
		return "模拟完成 " + battle
	}
	judged, passed := 0, 0
	var win *oj.Object
	for _, x := range r.Array("verdicts") {
		v := x.(*oj.Object)
		if v.Get("target") != nil {
			judged++
			if v.Str("status", "") == "PASS" {
				passed++
			}
		}
		if win == nil && v.Str("bot", "") == bots[0] && v.Str("metric", "") == "win_rate" {
			win = v
		}
	}
	text := "模拟完成 " + battle + "（"
	i := 0
	for _, b := range bots {
		if n, ok := used[b]; ok {
			if i > 0 {
				text += "、"
			}
			text += fmt.Sprintf("%s %d 局", botLabel(b), n)
			i++
		}
	}
	text += "）："
	if win != nil && win.Get("value") != nil {
		text += botLabel(bots[0]) + "胜率 " + balance.Pct0(win.Float("value", 0))
	}
	if judged > 0 {
		text += fmt.Sprintf("，目标通过 %d/%d", passed, judged)
	}
	return text
}
