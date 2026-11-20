package studio

import (
	"fmt"
	"sort"
	"strings"

	oj "srpg/balance/ordjson"
	"srpg/balance/schema"
)

func bestError(v any, sch *oj.Object) *schema.Error { return schema.Best(v, sch) }

func issue(level, where, message string, extra ...any) *oj.Object {
	o := oj.Obj("level", level, "where", where, "message", message)
	for i := 0; i+1 < len(extra); i += 2 {
		o.Set(extra[i].(string), extra[i+1])
	}
	return o
}

// Validate 做 schema、交叉引用和布局检查。where 是 "units"、"skills" 或 "battles/<id>"。
func (w *Workspace) Validate(d *Data) ([]*oj.Object, error) {
	issues := []*oj.Object{}
	for _, table := range tableNames {
		sch, err := w.schema(table)
		if err != nil {
			return nil, err
		}
		for _, e := range schema.Validate(d.Table(table), sch) {
			path := e.PathString()
			issues = append(issues, issue("error", table, path+"："+e.Message, "path", path))
		}
	}
	for _, uid := range d.Units.Keys() {
		u := d.Units.Object(uid)
		for _, s := range u.Array("skills") {
			if name, ok := s.(string); !ok || !d.Skills.Has(name) {
				issues = append(issues, issue("error", "units",
					fmt.Sprintf("%s 引用了不存在的技能 %v", u.Str("name", uid), s), "path", uid+".skills"))
			}
		}
	}
	for _, sid := range d.Skills.Keys() {
		s := d.Skills.Object(sid)
		if s.Float("min_range", 0) > s.Float("max_range", 0) {
			issues = append(issues, issue("error", "skills", s.Str("name", sid)+" 的最小射程大于最大射程", "path", sid+".min_range"))
		}
	}
	battleSchema, err := w.schema("battle")
	if err != nil {
		return nil, err
	}
	for _, bid := range d.Battles.Keys() {
		issues = append(issues, validateBattle(bid, d.Battles.Object(bid), d.Units, battleSchema)...)
	}
	return issues, nil
}

func intAt(arr []any, i int) int {
	if i >= len(arr) {
		return 0
	}
	f, _ := oj.Float(arr[i])
	return int(f)
}

func cellList(cells [][2]int) []any {
	out := make([]any, len(cells))
	for i, c := range cells {
		out[i] = []any{c[0], c[1]}
	}
	return out
}

func validateBattle(bid string, b, units, sch *oj.Object) []*oj.Object {
	where := "battles/" + bid
	var out []*oj.Object
	for _, e := range schema.Validate(b, sch) {
		out = append(out, issue("error", where, e.PathString()+"："+e.Message))
	}
	if len(out) > 0 {
		return out
	}
	str := func(rows []any, i int) string { s, _ := rows[i].(string); return s }
	heights, terrain := b.Array("heights"), b.Array("terrain")
	width, depth := len(str(heights, 0)), len(heights)
	for i := range heights {
		if len(str(heights, i)) != width {
			return []*oj.Object{issue("error", where, "高度图每一行的宽度必须相同")}
		}
	}
	if len(terrain) > 0 {
		bad := len(terrain) != depth
		for i := range terrain {
			bad = bad || len(str(terrain, i)) != width
		}
		if bad {
			return []*oj.Object{issue("error", where, "地形图的尺寸必须和高度图一致")}
		}
	}
	var unitList []*oj.Object
	count := map[string]int{}
	for _, v := range b.Array("units") {
		u := v.(*oj.Object)
		unitList = append(unitList, u)
		count[u.Str("id", "")]++
	}
	var dups []string
	for id, n := range count {
		if n > 1 {
			dups = append(dups, id)
		}
	}
	sort.Strings(dups)
	for _, dup := range dups {
		out = append(out, issue("error", where, "单位编号重复："+dup, "unit", dup))
	}
	hero, enemy := false, false
	for _, u := range unitList {
		hero = hero || (u.Str("id", "") == "hero" && u.Str("team", "") == "player")
		enemy = enemy || u.Str("team", "") == "enemy"
	}
	if !hero {
		out = append(out, issue("error", where, "必须有编号为 hero 的我方主角"))
	}
	if !enemy {
		out = append(out, issue("error", where, "至少要有一个敌人"))
	}
	cave := b.Object("cave")
	occupied := map[[2]int]string{}
	for _, u := range unitList {
		id, def := u.Str("id", ""), u.Str("def", "")
		if !units.Has(def) {
			out = append(out, issue("error", where, fmt.Sprintf("%s 使用了不存在的单位类型 %s", id, def), "unit", id))
			continue
		}
		size := units.Object(def).Int("size", 1)
		x0, y0 := intAt(u.Array("pos"), 0), intAt(u.Array("pos"), 1)
		var cells [][2]int
		inside := true
		for dy := 0; dy < size; dy++ {
			for dx := 0; dx < size; dx++ {
				c := [2]int{x0 + dx, y0 + dy}
				cells = append(cells, c)
				inside = inside && c[0] >= 0 && c[0] < width && c[1] >= 0 && c[1] < depth
			}
		}
		if !inside {
			out = append(out, issue("error", where, id+" 超出地图范围", "unit", id, "cells", cellList(cells)))
			continue
		}
		levels := map[byte]bool{}
		for _, c := range cells {
			if other, ok := occupied[c]; ok {
				out = append(out, issue("error", where, fmt.Sprintf("%s 与 %s 重叠", id, other), "unit", id, "cells", cellList([][2]int{c})))
			}
			occupied[c] = id
			if len(terrain) > 0 && !strings.ContainsRune(walkable, rune(str(terrain, c[1])[c[0]])) {
				out = append(out, issue("error", where, id+" 站在不可通行的地形上", "unit", id, "cells", cellList([][2]int{c})))
			}
			levels[str(heights, c[1])[c[0]]] = true
		}
		if size > 1 && len(levels) > 1 && !(cave != nil && cave.Str("boss", "") == id) {
			out = append(out, issue("warning", where, fmt.Sprintf("%s（%d×%d）的起始格高度不一致，按最高格站立", id, size, size),
				"unit", id, "cells", cellList(cells)))
		}
	}
	if cave.Len() > 0 {
		boss := cave.Str("boss", "")
		found := false
		for _, u := range unitList {
			found = found || (u.Str("id", "") == boss && u.Str("team", "") == "enemy")
		}
		if !found {
			out = append(out, issue("error", where, fmt.Sprintf("洞穴的 Boss「%s」不是场上的敌方单位", boss)))
		}
		entranceIDs := map[string]bool{}
		for _, v := range cave.Array("entrances") {
			e := v.(*oj.Object)
			entranceIDs[e.Str("id", "")] = true
			x, y := intAt(e.Array("anchor"), 0), intAt(e.Array("anchor"), 1)
			if !(x >= 0 && x < width-1 && y >= 0 && y < depth-1) {
				out = append(out, issue("error", where, fmt.Sprintf("洞穴入口 %s 超出地图范围", e.Str("id", "")), "cells", cellList([][2]int{{x, y}})))
			}
		}
		for _, v := range cave.Array("boulders") {
			bo := v.(*oj.Object)
			id := bo.Str("id", "")
			x, y := intAt(bo.Array("pos"), 0), intAt(bo.Array("pos"), 1)
			if !(x >= 0 && x < width && y >= 0 && y < depth) {
				out = append(out, issue("error", where, fmt.Sprintf("巨石 %s 超出地图范围", id)))
			} else if other, ok := occupied[[2]int{x, y}]; ok {
				out = append(out, issue("error", where, fmt.Sprintf("巨石 %s 和 %s 重叠", id, other), "cells", cellList([][2]int{{x, y}})))
			}
			if seals := bo.Str("seals", ""); !entranceIDs[seals] {
				out = append(out, issue("error", where, fmt.Sprintf("巨石 %s 要封的入口 %s 不存在", id, seals), "cells", cellList([][2]int{{x, y}})))
			}
		}
	}
	return out
}
