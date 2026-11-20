package balance

import (
	"encoding/xml"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	oj "srpg/balance/ordjson"
	"srpg/balance/schema"
)

// `srpg check` 做的事：数据表的 schema 和交叉引用检查 + 静态规格（specs/*.yaml）对照伤害矩阵。
// 每一项对应原来 pytest 里的一个用例，名字保持不变。

// Case 是一项检查的结果。
type Case struct {
	Class, Name string
	Err         string // 空 = 通过
	XFail       string // 非空 = 已知问题，按预期失败（算跳过）
}

// Failed 表示这项检查没过。
func (c Case) Failed() bool { return c.Err != "" && c.XFail == "" }

func readObj(path string) (*oj.Object, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	o, err := oj.ParseObject(data)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return o, nil
}

// Tables 是基线数据表。
type Tables struct {
	Units, Skills, SkillTree *oj.Object
	Battles                  map[string]*oj.Object
	BattleIDs                []string // 按文件名排序
}

// LoadTables 读基线数据表。
func (p Paths) LoadTables() (*Tables, error) {
	t := &Tables{Battles: map[string]*oj.Object{}}
	var err error
	if t.Units, err = readObj(filepath.Join(p.Tables, "units.json")); err != nil {
		return nil, err
	}
	if t.Skills, err = readObj(filepath.Join(p.Tables, "skills.json")); err != nil {
		return nil, err
	}
	if t.SkillTree, err = readObj(filepath.Join(p.Tables, "skill_tree.json")); err != nil {
		return nil, err
	}
	files, _ := filepath.Glob(filepath.Join(p.Tables, "battles", "*.json"))
	sort.Strings(files)
	for _, f := range files {
		id := strings.TrimSuffix(filepath.Base(f), ".json")
		if t.Battles[id], err = readObj(f); err != nil {
			return nil, err
		}
		t.BattleIDs = append(t.BattleIDs, id)
	}
	return t, nil
}

// Schema 读 schemas/<name>.schema.json。
func (p Paths) Schema(name string) (*oj.Object, error) {
	return readObj(filepath.Join(p.Schemas, name+".schema.json"))
}

func first(errs []string) string {
	if len(errs) == 0 {
		return ""
	}
	return errs[0]
}

// CheckTables 对应 tests/test_data_tables.py。
func CheckTables(p Paths) ([]Case, error) {
	t, err := p.LoadTables()
	if err != nil {
		return nil, err
	}
	const class = "tests.test_data_tables"
	var out []Case
	add := func(name, err string) { out = append(out, Case{Class: class, Name: name, Err: err}) }
	validate := func(v any, name string) string {
		s, err := p.Schema(name)
		if err != nil {
			return err.Error()
		}
		if e := schema.Best(v, s); e != nil {
			return e.Message
		}
		return ""
	}
	add("test_table_matches_schema[units-units]", validate(t.Units, "units"))
	add("test_table_matches_schema[skills-skills]", validate(t.Skills, "skills"))
	add("test_table_matches_schema[skill_tree-skill_tree]", validate(t.SkillTree, "skill_tree"))

	var errs []string
	for _, id := range t.BattleIDs {
		b := t.Battles[id]
		if e := validate(b, "battle"); e != "" {
			errs = append(errs, e)
		} else if b.Str("id", "") != id {
			errs = append(errs, fmt.Sprintf("battles/%s.json declares id %s", id, oj.PyRepr(b.Get("id"))))
		}
	}
	add("test_battles_match_schema", first(errs))

	errs = nil
	for _, u := range t.Units.Keys() {
		for _, s := range t.Units.Object(u).Array("skills") {
			if name, _ := s.(string); !t.Skills.Has(name) {
				errs = append(errs, fmt.Sprintf("(%s, %s)", u, name))
			}
		}
	}
	if len(errs) > 0 {
		errs = []string{"units reference unknown skills: " + strings.Join(errs, ", ")}
	}
	add("test_unit_skills_exist", first(errs))

	errs = nil
	for _, k := range t.Skills.Keys() {
		s := t.Skills.Object(k)
		if s.Has("max_range") && s.Float("min_range", 0) > s.Float("max_range", 0) {
			errs = append(errs, k)
		}
	}
	if len(errs) > 0 {
		errs = []string{"min_range > max_range: " + strings.Join(errs, ", ")}
	}
	add("test_skill_ranges_are_ordered", first(errs))
	add("test_skill_tree_references_and_defaults", first(checkSkillTree(t)))
	for _, id := range t.BattleIDs {
		add(fmt.Sprintf("test_battle_layout[%s]", id), first(checkLayout(t, t.Battles[id])))
	}
	return out, nil
}

func checkSkillTree(t *Tables) (errs []string) {
	trees := t.SkillTree.Object("trees")
	nodesOf := func(def string) (ids []string, byID map[string]*oj.Object, branches [][]string) {
		byID = map[string]*oj.Object{}
		for _, b := range trees.Array(def) {
			var branch []string
			for _, n := range b.(*oj.Object).Array("nodes") {
				node := n.(*oj.Object)
				id := node.Str("id", "")
				ids = append(ids, id)
				byID[id] = node
				branch = append(branch, id)
			}
			branches = append(branches, branch)
		}
		return
	}
	for _, def := range trees.Keys() {
		if !t.Units.Has(def) {
			errs = append(errs, "skill tree for unknown unit "+def)
		}
		ids, byID, _ := nodesOf(def)
		if len(byID) != len(ids) {
			errs = append(errs, "duplicate node ids in "+def)
		}
		for _, id := range ids {
			if n := byID[id]; n.Has("skill") && !t.Skills.Has(n.Str("skill", "")) {
				errs = append(errs, fmt.Sprintf("%s/%s: unknown skill %s", def, id, n.Str("skill", "")))
			}
		}
	}
	points := t.SkillTree.Float("points", 0)
	picksAll := t.SkillTree.Object("default_picks")
	for _, def := range picksAll.Keys() {
		_, byID, branches := nodesOf(def)
		picked := map[string]bool{}
		cost := 0.0
		for _, p := range picksAll.Array(def) {
			id, _ := p.(string)
			if byID[id] == nil {
				errs = append(errs, fmt.Sprintf("default picks for %s name unknown nodes", def))
				continue
			}
			picked[id] = true
			cost += byID[id].Float("cost", 0)
		}
		if cost > points {
			errs = append(errs, fmt.Sprintf("default picks for %s over budget", def))
		}
		for _, ids := range branches {
			for i := 1; i < len(ids); i++ {
				if picked[ids[i]] && !picked[ids[i-1]] {
					errs = append(errs, fmt.Sprintf("%s: %s needs %s", def, ids[i], ids[i-1]))
				}
			}
		}
	}
	return errs
}

func checkLayout(t *Tables, b *oj.Object) (errs []string) {
	fail := func(format string, a ...any) { errs = append(errs, fmt.Sprintf(format, a...)) }
	heights, terrain := b.Array("heights"), b.Array("terrain")
	if len(heights) == 0 {
		return []string{"heights missing"}
	}
	row := func(rows []any, i int) string { s, _ := rows[i].(string); return s }
	width, depth := len(row(heights, 0)), len(heights)
	for i := range heights {
		if len(row(heights, i)) != width {
			fail("height rows must have equal width")
		}
	}
	if len(terrain) > 0 {
		ok := len(terrain) == depth
		for i := range terrain {
			ok = ok && len(row(terrain, i)) == width
		}
		if !ok {
			return append(errs, "terrain must match heights")
		}
	}
	seen := map[string]bool{}
	hero := false
	occupied := map[[2]int]string{}
	for _, v := range b.Array("units") {
		u := v.(*oj.Object)
		id := u.Str("id", "")
		if seen[id] {
			fail("unit ids must be unique")
		}
		seen[id] = true
		hero = hero || (id == "hero" && u.Str("team", "") == "player")
		def := t.Units.Object(u.Str("def", ""))
		if def == nil {
			fail("unknown unit def %s", u.Str("def", ""))
			continue
		}
		size := def.Int("size", 1)
		pos := u.Array("pos")
		x0f, _ := oj.Float(pos[0])
		y0f, _ := oj.Float(pos[1])
		for dy := 0; dy < size; dy++ {
			for dx := 0; dx < size; dx++ {
				x, y := int(x0f)+dx, int(y0f)+dy
				if x < 0 || x >= width || y < 0 || y >= depth {
					fail("%s out of bounds at (%d, %d)", id, x, y)
					continue
				}
				if other, ok := occupied[[2]int{x, y}]; ok {
					fail("%s overlaps %s at (%d, %d)", id, other, x, y)
				}
				occupied[[2]int{x, y}] = id
				if len(terrain) > 0 && !strings.ContainsRune(".fwsbx", rune(row(terrain, y)[x])) {
					fail("%s starts on impassable terrain at (%d, %d)", id, x, y)
				}
			}
		}
	}
	if !hero {
		fail("the hero must be present")
	}
	return errs
}

// CheckSpecs 对应 tests/test_static_specs.py：每条规则展开成逐对的用例。
func CheckSpecs(p Paths, hits []Hit) ([]Case, error) {
	files, _ := filepath.Glob(filepath.Join(p.Specs, "*.yaml"))
	sort.Strings(files)
	var out []Case
	strs := func(v []any) []string {
		s := make([]string, len(v))
		for i, x := range v {
			s[i] = fmt.Sprint(x)
		}
		return s
	}
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			return nil, err
		}
		doc, err := YAMLToValue(data)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", f, err)
		}
		root, _ := doc.(*oj.Object)
		for _, rv := range root.Array("rules") {
			rule := rv.(*oj.Object)
			id, kind := rule.Str("id", ""), rule.Str("kind", "")
			scenario := rule.Str("scenario", "front")
			where := fmt.Sprintf("%s:%s (%s)", filepath.Base(f), id, rule.Str("source", ""))
			add := func(name, msg string) {
				c := Case{Class: "tests.test_static_specs", Name: "test_spec[" + name + "]", Err: msg}
				if known := rule.Str("known_issue", ""); known != "" {
					if msg == "" { // 严格的预期失败：一旦通过就报错，提醒去掉标记
						c.Err = "[XPASS(strict)] " + known
					} else {
						c.XFail = known
					}
				}
				out = append(out, c)
			}
			rng := rule.Array("range")
			bound := func(i int) float64 { f, _ := oj.Float(rng[i]); return f }
			switch kind {
			case "hits_to_kill":
				for _, atk := range strs(rule.Array("attackers")) {
					for _, tgt := range strs(rule.Array("targets")) {
						unit, skill, _ := strings.Cut(atk, ":")
						msg := ""
						if h, err := Lookup(hits, unit, skill, tgt, scenario); err != nil {
							msg = err.Error()
						} else if !(bound(0) <= h.HitsToKill && h.HitsToKill <= bound(1)) {
							msg = fmt.Sprintf("%s kills %s in %v hits (%v dmg vs %v HP, %s); want %s–%s. %s", atk, tgt,
								h.HitsToKill, h.Damage, h.TargetHP, scenario, FmtG(bound(0)), FmtG(bound(1)), where)
						}
						add(fmt.Sprintf("%s[%s->%s]", id, atk, tgt), msg)
					}
				}
			case "max_hit_fraction":
				limit := rule.Float("max", 0)
				for _, atk := range strs(rule.Array("attackers")) {
					for _, tgt := range strs(rule.Array("targets")) {
						var worst *Hit
						for i, h := range hits {
							if h.Attacker == atk && h.Target == tgt && h.Scenario == scenario &&
								(worst == nil || h.HPFraction > worst.HPFraction) {
								worst = &hits[i]
							}
						}
						msg := ""
						if worst == nil {
							msg = fmt.Sprintf("no metric for %s -> %s (%s)", atk, tgt, scenario)
						} else if worst.HPFraction > limit {
							msg = fmt.Sprintf("%s:%s takes %v/%v (%s) of %s in one hit; max %s. %s", atk, worst.Skill,
								worst.Damage, worst.TargetMaxHP, Pct0(worst.HPFraction), tgt, Pct0(limit), where)
						}
						add(fmt.Sprintf("%s[%s->%s]", id, atk, tgt), msg)
					}
				}
			case "party_burst":
				target := rule.Str("target", "")
				total := 0
				var detail []string
				for _, m := range strs(rule.Array("party")) {
					best := BestHit(hits, m, target, scenario)
					total += best
					detail = append(detail, fmt.Sprintf("%s %d", m, best))
				}
				msg := "no metric for target " + target
				for _, h := range hits {
					if h.Target == target {
						hp := float64(int(h.TargetHP))
						frac := float64(total) / hp
						msg = ""
						if !(bound(0) <= frac && frac <= bound(1)) {
							msg = fmt.Sprintf("party burst vs %s (%s) = %d/%v = %s [%s]; want %s–%s. %s", target, scenario,
								total, hp, Pct0(frac), strings.Join(detail, ", "), Pct0(bound(0)), Pct0(bound(1)), where)
						}
						break
					}
				}
				add(id, msg)
			default:
				return nil, fmt.Errorf("unknown spec kind %q in %s", kind, filepath.Base(f))
			}
		}
	}
	return out, nil
}

// WriteJUnit 把检查结果写成 CI 认识的 JUnit XML。
func WriteJUnit(path string, cases []Case, elapsed time.Duration) error {
	type skipped struct {
		Type    string `xml:"type,attr"`
		Message string `xml:"message,attr"`
	}
	type failure struct {
		Message string `xml:"message,attr"`
		Text    string `xml:",chardata"`
	}
	type testcase struct {
		Class   string   `xml:"classname,attr"`
		Name    string   `xml:"name,attr"`
		Time    string   `xml:"time,attr"`
		Failure *failure `xml:"failure,omitempty"`
		Skipped *skipped `xml:"skipped,omitempty"`
	}
	type testsuite struct {
		XMLName   xml.Name   `xml:"testsuite"`
		Name      string     `xml:"name,attr"`
		Errors    int        `xml:"errors,attr"`
		Failures  int        `xml:"failures,attr"`
		Skipped   int        `xml:"skipped,attr"`
		Tests     int        `xml:"tests,attr"`
		Time      string     `xml:"time,attr"`
		Timestamp string     `xml:"timestamp,attr"`
		Cases     []testcase `xml:"testcase"`
	}
	type testsuites struct {
		XMLName xml.Name  `xml:"testsuites"`
		Name    string    `xml:"name,attr"`
		Suite   testsuite `xml:"testsuite"`
	}
	s := testsuite{Name: "srpg check", Tests: len(cases), Time: fmt.Sprintf("%.3f", elapsed.Seconds()),
		Timestamp: time.Now().Format(time.RFC3339)}
	for _, c := range cases {
		tc := testcase{Class: c.Class, Name: c.Name, Time: "0.000"}
		switch {
		case c.XFail != "":
			s.Skipped++
			tc.Skipped = &skipped{Type: "pytest.xfail", Message: c.XFail}
		case c.Err != "":
			s.Failures++
			tc.Failure = &failure{Message: c.Err, Text: c.Err}
		}
		s.Cases = append(s.Cases, tc)
	}
	data, err := xml.Marshal(testsuites{Name: "srpg check", Suite: s})
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, append([]byte(`<?xml version="1.0" encoding="utf-8"?>`), data...), 0o644)
}
