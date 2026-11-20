// Package ordjson 是保留键顺序的 JSON 值，输出格式与 Python 的 json.dumps 逐字节一致。
//
// 值的类型：nil、bool、string、json.Number、[]any、*Object；
// 编码时另外接受 int、int64、float64、[]string、map[string]any（按键排序）。
package ordjson

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"sort"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

// Object 是保留插入顺序的 JSON 对象。
type Object struct {
	keys []string
	m    map[string]any
}

func NewObject() *Object { return &Object{m: map[string]any{}} }

// Obj 用 k1, v1, k2, v2… 构造对象。
func Obj(kv ...any) *Object {
	o := NewObject()
	for i := 0; i+1 < len(kv); i += 2 {
		o.Set(kv[i].(string), kv[i+1])
	}
	return o
}

func (o *Object) Set(k string, v any) *Object {
	if _, ok := o.m[k]; !ok {
		o.keys = append(o.keys, k)
	}
	o.m[k] = v
	return o
}

func (o *Object) Get(k string) any {
	if o == nil {
		return nil
	}
	return o.m[k]
}

func (o *Object) Has(k string) bool {
	if o == nil {
		return false
	}
	_, ok := o.m[k]
	return ok
}

func (o *Object) Delete(k string) {
	if _, ok := o.m[k]; !ok {
		return
	}
	delete(o.m, k)
	for i, x := range o.keys {
		if x == k {
			o.keys = append(o.keys[:i:i], o.keys[i+1:]...)
			break
		}
	}
}

func (o *Object) Keys() []string {
	if o == nil {
		return nil
	}
	return o.keys
}

func (o *Object) Len() int {
	if o == nil {
		return 0
	}
	return len(o.keys)
}

// Clone 浅拷贝（只复制顶层键）。
func (o *Object) Clone() *Object {
	c := NewObject()
	for _, k := range o.Keys() {
		c.Set(k, o.m[k])
	}
	return c
}

// Str 取字符串字段，缺失或类型不符时返回 def。
func (o *Object) Str(k, def string) string {
	if s, ok := o.Get(k).(string); ok {
		return s
	}
	return def
}

func (o *Object) Object(k string) *Object {
	v, _ := o.Get(k).(*Object)
	return v
}

func (o *Object) Array(k string) []any {
	v, _ := o.Get(k).([]any)
	return v
}

// Float 取数值字段。
func (o *Object) Float(k string, def float64) float64 {
	if f, ok := Float(o.Get(k)); ok {
		return f
	}
	return def
}

func (o *Object) Int(k string, def int) int {
	if f, ok := Float(o.Get(k)); ok {
		return int(f)
	}
	return def
}

// Float 把数值类型的值转成 float64。
func Float(v any) (float64, bool) {
	switch x := v.(type) {
	case json.Number:
		f, err := x.Float64()
		return f, err == nil
	case float64:
		return x, true
	case int:
		return float64(x), true
	case int64:
		return float64(x), true
	}
	return 0, false
}

// IsInt 判断值是否是 Python 意义上的 int（JSON 字面量不含小数点和指数）。
func IsInt(v any) bool {
	switch x := v.(type) {
	case json.Number:
		return !strings.ContainsAny(string(x), ".eE")
	case int, int64:
		return true
	}
	return false
}

// DeepCopy 递归复制。
func DeepCopy(v any) any {
	switch x := v.(type) {
	case []any:
		out := make([]any, len(x))
		for i, e := range x {
			out[i] = DeepCopy(e)
		}
		return out
	case *Object:
		c := NewObject()
		for _, k := range x.Keys() {
			c.Set(k, DeepCopy(x.m[k]))
		}
		return c
	}
	return v
}

// --- 解析 ---------------------------------------------------------------------------------------

func Parse(data []byte) (any, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	v, err := parseValue(dec)
	if err != nil {
		return nil, err
	}
	if _, err := dec.Token(); err != io.EOF {
		return nil, fmt.Errorf("JSON 之后还有多余内容")
	}
	return v, nil
}

func ParseObject(data []byte) (*Object, error) {
	v, err := Parse(data)
	if err != nil {
		return nil, err
	}
	o, ok := v.(*Object)
	if !ok {
		return nil, fmt.Errorf("需要 JSON 对象")
	}
	return o, nil
}

func parseValue(dec *json.Decoder) (any, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	d, ok := tok.(json.Delim)
	if !ok {
		return tok, nil
	}
	switch d {
	case '{':
		o := NewObject()
		for dec.More() {
			kt, err := dec.Token()
			if err != nil {
				return nil, err
			}
			v, err := parseValue(dec)
			if err != nil {
				return nil, err
			}
			o.Set(kt.(string), v)
		}
		_, err := dec.Token()
		return o, err
	case '[':
		arr := []any{}
		for dec.More() {
			v, err := parseValue(dec)
			if err != nil {
				return nil, err
			}
			arr = append(arr, v)
		}
		_, err := dec.Token()
		return arr, err
	}
	return nil, fmt.Errorf("意外的 %v", d)
}

// --- 编码 ---------------------------------------------------------------------------------------

// Style 对应 json.dumps 的 separators / indent / sort_keys（一律 ensure_ascii=False）。
type Style struct {
	ItemSep, KeySep string
	Indent          int
	Sort            bool
}

var (
	Default = Style{ItemSep: ", ", KeySep: ": "}           // json.dumps(x)
	Compact = Style{ItemSep: ",", KeySep: ":"}             // separators=(",", ":")
	Indent2 = Style{ItemSep: ",", KeySep: ": ", Indent: 2} // indent=2
	Canon   = Style{ItemSep: ",", KeySep: ":", Sort: true} // sort_keys=True，紧凑
)

func Dump(v any, st Style) string {
	var b strings.Builder
	write(&b, v, st, 0)
	return b.String()
}

func nl(b *strings.Builder, st Style, depth int) {
	if st.Indent > 0 {
		b.WriteByte('\n')
		b.WriteString(strings.Repeat(" ", st.Indent*depth))
	}
}

func write(b *strings.Builder, v any, st Style, depth int) {
	switch x := v.(type) {
	case nil:
		b.WriteString("null")
	case bool:
		b.WriteString(strconv.FormatBool(x))
	case string:
		writeString(b, x)
	case json.Number:
		b.WriteString(PyNumber(x))
	case int:
		b.WriteString(strconv.Itoa(x))
	case int64:
		b.WriteString(strconv.FormatInt(x, 10))
	case float64:
		b.WriteString(jsonFloat(x))
	case []string:
		arr := make([]any, len(x))
		for i, s := range x {
			arr[i] = s
		}
		write(b, arr, st, depth)
	case []any:
		if len(x) == 0 {
			b.WriteString("[]")
			return
		}
		b.WriteByte('[')
		for i, e := range x {
			if i > 0 {
				b.WriteString(st.ItemSep)
			}
			nl(b, st, depth+1)
			write(b, e, st, depth+1)
		}
		nl(b, st, depth)
		b.WriteByte(']')
	case *Object:
		if x == nil {
			b.WriteString("null")
			return
		}
		keys := x.keys
		if st.Sort {
			keys = append([]string(nil), keys...)
			sort.Strings(keys)
		}
		writeMap(b, keys, x.m, st, depth)
	case map[string]any:
		keys := make([]string, 0, len(x))
		for k := range x {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		writeMap(b, keys, x, st, depth)
	case json.RawMessage:
		p, err := Parse(x)
		if err != nil {
			b.WriteString("null")
			return
		}
		write(b, p, st, depth)
	default:
		panic(fmt.Sprintf("ordjson: 不支持的类型 %T", v))
	}
}

func writeMap(b *strings.Builder, keys []string, m map[string]any, st Style, depth int) {
	if len(keys) == 0 {
		b.WriteString("{}")
		return
	}
	b.WriteByte('{')
	for i, k := range keys {
		if i > 0 {
			b.WriteString(st.ItemSep)
		}
		nl(b, st, depth+1)
		writeString(b, k)
		b.WriteString(st.KeySep)
		write(b, m[k], st, depth+1)
	}
	nl(b, st, depth)
	b.WriteByte('}')
}

// writeString 按 Python json（ensure_ascii=False）的规则转义。
func writeString(b *strings.Builder, s string) {
	b.WriteByte('"')
	for _, r := range s {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		case '\b':
			b.WriteString(`\b`)
		case '\f':
			b.WriteString(`\f`)
		default:
			if r < 0x20 {
				fmt.Fprintf(b, `\u%04x`, r)
			} else {
				b.WriteRune(r)
			}
		}
	}
	b.WriteByte('"')
}

func jsonFloat(f float64) string {
	switch {
	case math.IsNaN(f):
		return "NaN"
	case math.IsInf(f, 1):
		return "Infinity"
	case math.IsInf(f, -1):
		return "-Infinity"
	}
	return PyFloat(f)
}

// PyFloat 等价于 Python 的 repr(float)。
func PyFloat(f float64) string {
	switch {
	case math.IsNaN(f):
		return "nan"
	case math.IsInf(f, 1):
		return "inf"
	case math.IsInf(f, -1):
		return "-inf"
	}
	e := strconv.FormatFloat(f, 'e', -1, 64)
	exp, _ := strconv.Atoi(e[strings.IndexByte(e, 'e')+1:])
	if exp < -4 || exp >= 16 {
		return e
	}
	s := strconv.FormatFloat(f, 'f', -1, 64)
	if !strings.Contains(s, ".") {
		s += ".0"
	}
	return s
}

// PyNumber 把 JSON 数字字面量规范成 Python 读入再写出的样子（整数原样，其余按 float 的 repr）。
func PyNumber(n json.Number) string {
	s := string(n)
	if !strings.ContainsAny(s, ".eE") {
		if s == "-0" {
			return "0"
		}
		return s
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return s
	}
	return jsonFloat(f)
}

// --- 比较与 repr --------------------------------------------------------------------------------

// Equal 按 Python 的 == 比较两个 JSON 值（数字按数值，对象不看键顺序）。
func Equal(a, b any) bool {
	if fa, ok := Float(a); ok {
		fb, ok := Float(b)
		return ok && fa == fb
	}
	switch x := a.(type) {
	case nil:
		return b == nil
	case bool:
		y, ok := b.(bool)
		return ok && x == y
	case string:
		y, ok := b.(string)
		return ok && x == y
	case []any:
		y, ok := b.([]any)
		if !ok || len(x) != len(y) {
			return false
		}
		for i := range x {
			if !Equal(x[i], y[i]) {
				return false
			}
		}
		return true
	case *Object:
		y, ok := b.(*Object)
		if !ok || x.Len() != y.Len() {
			return false
		}
		for _, k := range x.Keys() {
			if !y.Has(k) || !Equal(x.m[k], y.m[k]) {
				return false
			}
		}
		return true
	}
	return false
}

// PyRepr 等价于 Python 的 repr()（用于和 jsonschema 一致的报错文字）。
func PyRepr(v any) string {
	switch x := v.(type) {
	case nil:
		return "None"
	case bool:
		if x {
			return "True"
		}
		return "False"
	case string:
		return PyStrRepr(x)
	case json.Number:
		s := PyNumber(x)
		switch s {
		case "NaN":
			return "nan"
		case "Infinity":
			return "inf"
		case "-Infinity":
			return "-inf"
		}
		return s
	case int:
		return strconv.Itoa(x)
	case int64:
		return strconv.FormatInt(x, 10)
	case float64:
		return PyFloat(x)
	case []any:
		parts := make([]string, len(x))
		for i, e := range x {
			parts[i] = PyRepr(e)
		}
		return "[" + strings.Join(parts, ", ") + "]"
	case *Object:
		parts := make([]string, 0, x.Len())
		for _, k := range x.Keys() {
			parts = append(parts, PyStrRepr(k)+": "+PyRepr(x.m[k]))
		}
		return "{" + strings.Join(parts, ", ") + "}"
	}
	return fmt.Sprint(v)
}

// PyStrRepr 等价于 repr(str)。
func PyStrRepr(s string) string {
	q := '\''
	if strings.Contains(s, "'") && !strings.Contains(s, `"`) {
		q = '"'
	}
	var b strings.Builder
	b.WriteRune(q)
	for len(s) > 0 {
		r, size := utf8.DecodeRuneInString(s)
		s = s[size:]
		switch {
		case r == q || r == '\\':
			b.WriteByte('\\')
			b.WriteRune(r)
		case r == '\n':
			b.WriteString(`\n`)
		case r == '\r':
			b.WriteString(`\r`)
		case r == '\t':
			b.WriteString(`\t`)
		case r < 0x20 || r == 0x7f:
			fmt.Fprintf(&b, `\x%02x`, r)
		case !unicode.IsPrint(r):
			if r < 0x100 {
				fmt.Fprintf(&b, `\x%02x`, r)
			} else if r < 0x10000 {
				fmt.Fprintf(&b, `\u%04x`, r)
			} else {
				fmt.Fprintf(&b, `\U%08x`, r)
			}
		default:
			b.WriteRune(r)
		}
	}
	b.WriteRune(q)
	return b.String()
}

// PyTuple 等价于 repr(tuple(list))，例如 "(5, 12)"。
func PyTuple(arr []any) string {
	parts := make([]string, len(arr))
	for i, e := range arr {
		parts[i] = PyRepr(e)
	}
	if len(parts) == 1 {
		return "(" + parts[0] + ",)"
	}
	return "(" + strings.Join(parts, ", ") + ")"
}
