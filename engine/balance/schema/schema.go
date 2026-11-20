// Package schema 是一个小型 JSON Schema（draft 2020-12）校验器，只实现数据表用到的关键字，
// 报错文字和排序规则照搬 Python jsonschema 4.x，保证工坊里看到的提示不变。
package schema

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"

	oj "srpg/balance/ordjson"
)

// Error 对应 jsonschema.ValidationError。
type Error struct {
	Message   string
	Path      []any // 实例内的绝对路径（字符串键或整数下标）
	Validator string
	Schema    *oj.Object
	Instance  any
	Context   []*Error // oneOf 各分支的错误
	base      int      // 父错误的路径长度，用来算相对路径
}

// PathString 等价于 ".".join(str(x) for x in err.absolute_path)。
func (e *Error) PathString() string {
	parts := make([]string, len(e.Path))
	for i, p := range e.Path {
		parts[i] = fmt.Sprint(p)
	}
	return strings.Join(parts, ".")
}

// Validate 等价于 Draft202012Validator(schema).iter_errors(instance)。
func Validate(instance, schema any) []*Error {
	return descend(instance, schema, nil)
}

// Best 等价于 jsonschema.validate() 抛出的那个错误（best_match）；没有错误时返回 nil。
func Best(instance, schema any) *Error {
	errs := Validate(instance, schema)
	if len(errs) == 0 {
		return nil
	}
	best := errs[0]
	for _, e := range errs[1:] {
		if cmpKey(e, best) > 0 {
			best = e
		}
	}
	for len(best.Context) > 0 {
		ctx := append([]*Error(nil), best.Context...)
		sort.SliceStable(ctx, func(i, j int) bool { return cmpKey(ctx[i], ctx[j]) < 0 })
		if len(ctx) >= 2 && cmpKey(ctx[0], ctx[1]) == 0 {
			return best
		}
		best = ctx[0]
	}
	return best
}

// cmpKey 比较 by_relevance 的排序键：(-len(path), path, 非弱关键字, 强关键字, 类型不匹配)。
func cmpKey(a, b *Error) int {
	pa, pb := a.Path[a.base:], b.Path[b.base:]
	if len(pa) != len(pb) {
		if len(pa) < len(pb) {
			return 1
		}
		return -1
	}
	for i := range pa {
		if c := cmpElem(pa[i], pb[i]); c != 0 {
			return c
		}
	}
	if c := cmpBool(!weak(a), !weak(b)); c != 0 {
		return c
	}
	return cmpBool(!a.matchesType(), !b.matchesType())
}

func weak(e *Error) bool { return e.Validator == "anyOf" || e.Validator == "oneOf" }

func cmpBool(a, b bool) int {
	switch {
	case a == b:
		return 0
	case a:
		return 1
	}
	return -1
}

func cmpElem(a, b any) int {
	switch x := a.(type) {
	case int:
		if y, ok := b.(int); ok {
			return x - y
		}
	case string:
		if y, ok := b.(string); ok {
			return strings.Compare(x, y)
		}
	}
	return 0
}

func (e *Error) matchesType() bool {
	switch t := e.Schema.Get("type").(type) {
	case string:
		return isType(e.Instance, t)
	case []any:
		for _, x := range t {
			if s, ok := x.(string); ok && isType(e.Instance, s) {
				return true
			}
		}
	}
	return false
}

func isType(v any, t string) bool {
	switch t {
	case "object":
		_, ok := v.(*oj.Object)
		return ok
	case "array":
		_, ok := v.([]any)
		return ok
	case "string":
		_, ok := v.(string)
		return ok
	case "boolean":
		_, ok := v.(bool)
		return ok
	case "null":
		return v == nil
	case "number":
		_, ok := oj.Float(v)
		return ok
	case "integer":
		f, ok := oj.Float(v)
		return ok && f == float64(int64(f))
	}
	return false
}

func extend(path []any, elem any) []any {
	out := make([]any, len(path)+1)
	copy(out, path)
	out[len(path)] = elem
	return out
}

func descend(inst, schema any, path []any) []*Error {
	var s *oj.Object
	switch x := schema.(type) {
	case bool:
		if x {
			return nil
		}
		return []*Error{{Message: "False schema does not allow " + oj.PyRepr(inst), Path: path, Instance: inst}}
	case *oj.Object:
		s = x
	default:
		return nil
	}
	var out []*Error
	fail := func(kw, format string, args ...any) {
		out = append(out, &Error{Message: fmt.Sprintf(format, args...), Path: path, Validator: kw, Schema: s, Instance: inst})
	}
	obj, isObj := inst.(*oj.Object)
	arr, isArr := inst.([]any)
	str, isStr := inst.(string)
	num, isNum := oj.Float(inst)
	r := oj.PyRepr
	for _, kw := range s.Keys() {
		v := s.Get(kw)
		switch kw {
		case "type":
			var types []string
			switch t := v.(type) {
			case string:
				types = []string{t}
			case []any:
				for _, x := range t {
					types = append(types, fmt.Sprint(x))
				}
			}
			ok := false
			reprs := make([]string, len(types))
			for i, t := range types {
				ok = ok || isType(inst, t)
				reprs[i] = oj.PyStrRepr(t)
			}
			if !ok {
				fail(kw, "%s is not of type %s", r(inst), strings.Join(reprs, ", "))
			}
		case "required":
			if isObj {
				for _, p := range v.([]any) {
					if name, _ := p.(string); !obj.Has(name) {
						fail(kw, "%s is a required property", r(p))
					}
				}
			}
		case "properties":
			if props, ok := v.(*oj.Object); ok && isObj {
				for _, p := range props.Keys() {
					if obj.Has(p) {
						out = append(out, descend(obj.Get(p), props.Get(p), extend(path, p))...)
					}
				}
			}
		case "additionalProperties":
			if !isObj {
				break
			}
			props := s.Object("properties")
			var extras []string
			for _, k := range obj.Keys() {
				if !props.Has(k) {
					extras = append(extras, k)
				}
			}
			if sub, ok := v.(*oj.Object); ok {
				for _, k := range extras {
					out = append(out, descend(obj.Get(k), sub, extend(path, k))...)
				}
			} else if b, ok := v.(bool); ok && !b && len(extras) > 0 {
				sort.Strings(extras)
				reprs := make([]string, len(extras))
				for i, e := range extras {
					reprs[i] = oj.PyStrRepr(e)
				}
				verb := "were"
				if len(extras) == 1 {
					verb = "was"
				}
				fail(kw, "Additional properties are not allowed (%s %s unexpected)", strings.Join(reprs, ", "), verb)
			}
		case "propertyNames":
			if isObj {
				for _, k := range obj.Keys() {
					out = append(out, descend(k, v, path)...)
				}
			}
		case "minProperties":
			if n, _ := oj.Float(v); isObj && float64(obj.Len()) < n {
				msg := "does not have enough properties"
				if n == 1 {
					msg = "should be non-empty"
				}
				fail(kw, "%s %s", r(inst), msg)
			}
		case "items":
			if isArr {
				for i, e := range arr {
					out = append(out, descend(e, v, extend(path, i))...)
				}
			}
		case "minItems":
			if n, _ := oj.Float(v); isArr && float64(len(arr)) < n {
				msg := "is too short"
				if n == 1 {
					msg = "should be non-empty"
				}
				fail(kw, "%s %s", r(inst), msg)
			}
		case "maxItems":
			if n, _ := oj.Float(v); isArr && float64(len(arr)) > n {
				msg := "is too long"
				if n == 0 {
					msg = "is expected to be empty"
				}
				fail(kw, "%s %s", r(inst), msg)
			}
		case "uniqueItems":
			if b, _ := v.(bool); b && isArr && !unique(arr) {
				fail(kw, "%s has non-unique elements", r(inst))
			}
		case "minLength":
			if n, _ := oj.Float(v); isStr && float64(utf8.RuneCountInString(str)) < n {
				msg := "is too short"
				if n == 1 {
					msg = "should be non-empty"
				}
				fail(kw, "%s %s", r(inst), msg)
			}
		case "maxLength":
			if n, _ := oj.Float(v); isStr && float64(utf8.RuneCountInString(str)) > n {
				msg := "is too long"
				if n == 0 {
					msg = "is expected to be empty"
				}
				fail(kw, "%s %s", r(inst), msg)
			}
		case "pattern":
			if p, _ := v.(string); isStr {
				if re, err := regexp.Compile(p); err == nil && !re.MatchString(str) {
					fail(kw, "%s does not match %s", r(inst), oj.PyStrRepr(p))
				}
			}
		case "minimum":
			if n, ok := oj.Float(v); ok && isNum && num < n {
				fail(kw, "%s is less than the minimum of %s", r(inst), r(v))
			}
		case "maximum":
			if n, ok := oj.Float(v); ok && isNum && num > n {
				fail(kw, "%s is greater than the maximum of %s", r(inst), r(v))
			}
		case "exclusiveMinimum":
			if n, ok := oj.Float(v); ok && isNum && num <= n {
				fail(kw, "%s is less than or equal to the minimum of %s", r(inst), r(v))
			}
		case "exclusiveMaximum":
			if n, ok := oj.Float(v); ok && isNum && num >= n {
				fail(kw, "%s is greater than or equal to the maximum of %s", r(inst), r(v))
			}
		case "enum":
			found := false
			for _, e := range v.([]any) {
				found = found || oj.Equal(inst, e)
			}
			if !found {
				fail(kw, "%s is not one of %s", r(inst), r(v))
			}
		case "const":
			if !oj.Equal(inst, v) {
				fail(kw, "%s was expected", r(v))
			}
		case "oneOf":
			subs, _ := v.([]any)
			var all []*Error
			first := -1
			for i, sub := range subs {
				errs := descend(inst, sub, path)
				if len(errs) == 0 {
					first = i
					break
				}
				all = append(all, errs...)
			}
			if first < 0 {
				for _, e := range all {
					e.base = len(path)
				}
				fail(kw, "%s is not valid under any of the given schemas", r(inst))
				out[len(out)-1].Context = all
				break
			}
			var more []string
			for _, sub := range subs[first+1:] {
				if len(descend(inst, sub, path)) == 0 {
					more = append(more, r(sub))
				}
			}
			if len(more) > 0 {
				more = append(more, r(subs[first]))
				fail(kw, "%s is valid under each of %s", r(inst), strings.Join(more, ", "))
			}
		case "anyOf":
			subs, _ := v.([]any)
			var all []*Error
			ok := false
			for _, sub := range subs {
				errs := descend(inst, sub, path)
				if len(errs) == 0 {
					ok = true
					break
				}
				all = append(all, errs...)
			}
			if !ok {
				for _, e := range all {
					e.base = len(path)
				}
				fail(kw, "%s is not valid under any of the given schemas", r(inst))
				out[len(out)-1].Context = all
			}
		case "allOf":
			for _, sub := range v.([]any) {
				out = append(out, descend(inst, sub, path)...)
			}
		}
	}
	return out
}

func unique(arr []any) bool {
	for i := range arr {
		for j := i + 1; j < len(arr); j++ {
			if oj.Equal(arr[i], arr[j]) {
				return false
			}
		}
	}
	return true
}
