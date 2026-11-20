package studio

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	oj "srpg/balance/ordjson"
)

type change struct {
	path string
	a, b any
	hasA bool
	hasB bool
}

// walk 逐键比较两棵 JSON，记下不同的叶子。
func walk(a, b any, path string, out *[]change) {
	oa, okA := a.(*oj.Object)
	ob, okB := b.(*oj.Object)
	if okA && okB {
		keys := append([]string{}, oa.Keys()...)
		for _, k := range ob.Keys() {
			if !oa.Has(k) {
				keys = append(keys, k)
			}
		}
		for _, k := range keys {
			p := strings.TrimLeft(path+"."+k, ".")
			switch {
			case !oa.Has(k):
				*out = append(*out, change{path: p, b: ob.Get(k), hasB: true})
			case !ob.Has(k):
				*out = append(*out, change{path: p, a: oa.Get(k), hasA: true})
			default:
				walk(oa.Get(k), ob.Get(k), path+"."+k, out)
			}
		}
		return
	}
	if !oj.Equal(a, b) {
		*out = append(*out, change{strings.TrimLeft(path, "."), a, b, true, true})
	}
}

// short 把值写短：缺失是"无"，超过 40 个字截断。
func short(v any, present bool) string {
	if !present || v == nil {
		return "无"
	}
	s := []rune(oj.Dump(v, oj.Default))
	if len(s) <= 40 {
		return string(s)
	}
	return string(s[:37]) + "…"
}

func unitsByID(b *oj.Object) (map[string]*oj.Object, []string) {
	m := map[string]*oj.Object{}
	var ids []string
	for _, v := range b.Array("units") {
		if u, ok := v.(*oj.Object); ok {
			id := u.Str("id", "")
			if m[id] == nil {
				ids = append(ids, id)
			}
			m[id] = u
		}
	}
	sort.Strings(ids)
	return m, ids
}

// battleDiff 用人话描述两版关卡的差别。
func battleDiff(a, b *oj.Object) []string {
	var lines []string
	for _, kl := range [][2]string{{"heights", "高度"}, {"terrain", "地形"}} {
		ra, rb := a.Array(kl[0]), b.Array(kl[0])
		if oj.Equal(ra, rb) {
			continue
		}
		row := func(rows []any, i int) []rune { s, _ := rows[i].(string); return []rune(s) }
		w := func(rows []any) int {
			if len(rows) == 0 {
				return 0
			}
			return len(row(rows, 0))
		}
		if len(ra) != len(rb) || (len(ra) > 0 && len(rb) > 0 && w(ra) != w(rb)) {
			lines = append(lines, fmt.Sprintf("%s图尺寸 %d×%d → %d×%d", kl[1], w(ra), len(ra), w(rb), len(rb)))
			continue
		}
		n := 0
		for i := range ra {
			x, y := row(ra, i), row(rb, i)
			for j := 0; j < len(x) && j < len(y); j++ {
				if x[j] != y[j] {
					n++
				}
			}
		}
		lines = append(lines, fmt.Sprintf("%s改了 %d 格", kl[1], n))
	}
	ua, idsA := unitsByID(a)
	ub, idsB := unitsByID(b)
	for _, i := range idsB {
		if ua[i] == nil {
			lines = append(lines, fmt.Sprintf("新增单位 %s（%s）于 %s", i, ub[i].Str("def", ""), oj.PyTuple(ub[i].Array("pos"))))
		}
	}
	for _, i := range idsA {
		if ub[i] == nil {
			lines = append(lines, "移除单位 "+i)
		}
	}
	for _, i := range idsA {
		if ub[i] == nil {
			continue
		}
		if !oj.Equal(ua[i].Get("pos"), ub[i].Get("pos")) {
			lines = append(lines, fmt.Sprintf("%s 从 %s 移到 %s", i, oj.PyTuple(ua[i].Array("pos")), oj.PyTuple(ub[i].Array("pos"))))
		}
		if ua[i].Str("def", "") != ub[i].Str("def", "") {
			lines = append(lines, fmt.Sprintf("%s 类型 %s → %s", i, ua[i].Str("def", ""), ub[i].Str("def", "")))
		}
		if fa, fb := ua[i].Str("facing", "S"), ub[i].Str("facing", "S"); fa != fb {
			lines = append(lines, fmt.Sprintf("%s 朝向 %s → %s", i, fa, fb))
		}
	}
	if !oj.Equal(a.Get("cave"), b.Get("cave")) {
		lines = append(lines, "改了洞穴设置（入口、巨石或触发生命）")
	}
	return lines
}

// Diff 返回 [{file, lines: [文字]}]，描述变体和基线的差别。
func (w *Workspace) Diff(variant string) ([]*oj.Object, error) {
	out := []*oj.Object{}
	if IsBaseline(variant) {
		return out, nil
	}
	over, err := w.OverlayDir(variant)
	if err != nil {
		return nil, err
	}
	files, err := w.ChangedFiles(variant)
	if err != nil {
		return nil, err
	}
	for _, rel := range files {
		newObj, err := readObject(filepath.Join(over, filepath.FromSlash(rel)+".json"))
		if err != nil {
			return nil, err
		}
		basePath := filepath.Join(w.P.Tables, filepath.FromSlash(rel)+".json")
		if !exists(basePath) {
			out = append(out, oj.Obj("file", rel, "lines", []any{fmt.Sprintf("新关卡「%s」", newObj.Str("title", rel))}))
			continue
		}
		old, err := readObject(basePath)
		if err != nil {
			return nil, err
		}
		var lines []string
		if strings.HasPrefix(rel, "battles/") {
			lines = battleDiff(old, newObj)
		} else {
			var changes []change
			walk(old, newObj, "", &changes)
			for _, c := range changes {
				lines = append(lines, fmt.Sprintf("%s：%s → %s", c.path, short(c.a, c.hasA), short(c.b, c.hasB)))
			}
		}
		if len(lines) > 0 {
			out = append(out, oj.Obj("file", rel, "lines", toAny(lines)))
		}
	}
	return out, nil
}

func toAny(s []string) []any {
	out := make([]any, len(s))
	for i, x := range s {
		out[i] = x
	}
	return out
}
