package balance

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"

	oj "srpg/balance/ordjson"
)

// 设计目标（balance/targets/<battle>.yaml）对照模拟结果的判定。用区间而不是点估计：
//   PASS          整个区间落在目标范围内
//   FAIL          整个区间落在目标范围外
//   INCONCLUSIVE  区间跨过边界（或样本太少）：需要更多局
// 带 known_issue 的规则把 FAIL 报成 KNOWN。

// Metric 是一个可设目标的指标。
type Metric struct {
	Key, Label string
	Pct        bool
	Fn         func(d Frame, level float64) Estimate
}

func winShare(col string) func(Frame, float64) Estimate {
	return func(d Frame, level float64) Estimate {
		w := d.Wins()
		return Proportion(w.Positive(col), w.Len(), level)
	}
}

// Metrics 的顺序就是工坊里显示的顺序。
var Metrics = []Metric{
	{"win_rate", "胜率", true, func(d Frame, l float64) Estimate { return Proportion(d.Wins().Len(), d.Len(), l) }},
	{"hero_ko_rate", "主角倒下率", true, func(d Frame, l float64) Estimate { return Proportion(d.CountResult("loss_hero"), d.Len(), l) }},
	{"timeout_rate", "超时率", true, func(d Frame, l float64) Estimate { return Proportion(d.CountResult("timeout"), d.Len(), l) }},
	{"rounds_p50", "胜局回合数中位数", false, func(d Frame, l float64) Estimate { return Median(d.Wins().Col("rounds"), l) }},
	{"rounds_mean", "胜局平均回合数", false, func(d Frame, l float64) Estimate { return Mean(d.Wins().Col("rounds"), l) }},
	{"party_hp_left_p50", "胜局剩余生命中位数", true, func(d Frame, l float64) Estimate { return Median(d.Wins().Col("party_hp_left"), l) }},
	{"battles_with_fall", "胜局中有敌人坠落的比例", true, winShare("counts.fall_enemy")},
	{"battles_with_grapple", "胜局中用过擒抱的比例", true, winShare("counts.grapple_start")},
	{"battles_with_break", "胜局中打出过破势的比例", true, winShare("counts.broken")},
	{"phase2_reached", "胜局中 Boss 进入第二阶段的比例", true, winShare("phase2_round")},
	{"battles_with_seal", "胜局中封住过入口的比例", true, winShare("counts.sealed")},
}

// MetricByKey 查指标。
func MetricByKey(key string) (Metric, bool) {
	for _, m := range Metrics {
		if m.Key == key {
			return m, true
		}
	}
	return Metric{}, false
}

// Rule 是一条目标：指标落在 [Lo, Hi]。
type Rule struct {
	Metric     string
	Lo, Hi     float64
	KnownIssue string
	Raw        []any // 文件里写的 [下限, 上限] 原值（保留整数/小数写法）
}

// BotRules 是一个机器人的全部目标，保持文件里的顺序。
type BotRules struct {
	Bot   string
	Rules []Rule
}

// Spec 是一个关卡的目标文件。
type Spec struct {
	RunsMin    int  // 少于这么多局一律 INCONCLUSIVE
	HasRunsMin bool // 文件里是否写了 runs_min（命令行默认 100，工坊默认 200）
	Bots       []BotRules
	Raw        *oj.Object // 原样内容（保留顺序，/api/targets 直接返回它）
}

// Bot 取某个机器人的规则。
func (s *Spec) Bot(bot string) ([]Rule, bool) {
	if s == nil {
		return nil, false
	}
	for _, b := range s.Bots {
		if b.Bot == bot {
			return b.Rules, true
		}
	}
	return nil, false
}

// BotNames 按文件顺序列出机器人。
func (s *Spec) BotNames() []string {
	if s == nil {
		return nil
	}
	out := make([]string, len(s.Bots))
	for i, b := range s.Bots {
		out[i] = b.Bot
	}
	return out
}

// only 返回只含指定机器人、runs_min 改写后的副本。
func (s *Spec) only(bots []string, runsMin int) *Spec {
	c := &Spec{RunsMin: runsMin, HasRunsMin: true, Raw: s.Raw}
	for _, name := range bots {
		if rules, ok := s.Bot(name); ok {
			c.Bots = append(c.Bots, BotRules{name, rules})
		}
	}
	return c
}

// SpecFromObject 由 JSON/YAML 内容解析目标。
func SpecFromObject(raw *oj.Object) (*Spec, error) {
	s := &Spec{RunsMin: 100, Raw: raw}
	if raw.Has("runs_min") {
		f, ok := oj.Float(raw.Get("runs_min"))
		if !ok {
			return nil, fmt.Errorf("runs_min 必须是数字")
		}
		s.RunsMin, s.HasRunsMin = int(f), true
	}
	bots := raw.Object("bots")
	if bots == nil && raw.Get("bots") != nil {
		return nil, fmt.Errorf("bots 必须是映射")
	}
	for _, bot := range bots.Keys() {
		rules := bots.Object(bot)
		br := BotRules{Bot: bot}
		for _, metric := range rules.Keys() {
			rule := Rule{Metric: metric}
			v := rules.Get(metric)
			if d, ok := v.(*oj.Object); ok {
				rule.KnownIssue = d.Str("known_issue", "")
				v = d.Get("range")
			}
			rng, ok := v.([]any)
			if !ok || len(rng) != 2 {
				return nil, fmt.Errorf("%s.%s 的范围必须是 [下限, 上限]", bot, metric)
			}
			lo, ok1 := oj.Float(rng[0])
			hi, ok2 := oj.Float(rng[1])
			if !ok1 || !ok2 {
				return nil, fmt.Errorf("%s.%s 的范围必须是数字", bot, metric)
			}
			rule.Lo, rule.Hi, rule.Raw = lo, hi, rng
			br.Rules = append(br.Rules, rule)
		}
		s.Bots = append(s.Bots, br)
	}
	return s, nil
}

// LoadSpec 读目标文件。
func LoadSpec(path string) (*Spec, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("没有目标文件 %s", path)
		}
		return nil, err
	}
	v, err := YAMLToValue(data)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	raw, ok := v.(*oj.Object)
	if !ok {
		return nil, fmt.Errorf("%s: 顶层必须是映射", path)
	}
	return SpecFromObject(raw)
}

// LoadTargets 读某关卡的目标；文件不存在时返回 (nil, nil)。
func (p Paths) LoadTargets(battle string) (*Spec, error) {
	if _, err := os.Stat(p.TargetsPath(battle)); err != nil {
		return nil, nil
	}
	return LoadSpec(p.TargetsPath(battle))
}

// YAMLToValue 把 YAML 解析成保留顺序的 JSON 值（相当于 yaml.safe_load）。
func YAMLToValue(data []byte) (any, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return nil, err
	}
	if doc.Kind == 0 {
		return nil, nil
	}
	return nodeValue(&doc)
}

func nodeValue(n *yaml.Node) (any, error) {
	switch n.Kind {
	case yaml.DocumentNode:
		if len(n.Content) == 0 {
			return nil, nil
		}
		return nodeValue(n.Content[0])
	case yaml.AliasNode:
		return nodeValue(n.Alias)
	case yaml.MappingNode:
		o := oj.NewObject()
		for i := 0; i+1 < len(n.Content); i += 2 {
			v, err := nodeValue(n.Content[i+1])
			if err != nil {
				return nil, err
			}
			o.Set(n.Content[i].Value, v)
		}
		return o, nil
	case yaml.SequenceNode:
		arr := []any{}
		for _, c := range n.Content {
			v, err := nodeValue(c)
			if err != nil {
				return nil, err
			}
			arr = append(arr, v)
		}
		return arr, nil
	}
	switch n.ShortTag() {
	case "!!null":
		return nil, nil
	case "!!bool":
		var b bool
		err := n.Decode(&b)
		return b, err
	case "!!int":
		var i int64
		if err := n.Decode(&i); err != nil {
			return nil, err
		}
		return json.Number(strconv.FormatInt(i, 10)), nil
	case "!!float":
		var f float64
		if err := n.Decode(&f); err != nil {
			return nil, err
		}
		if math.IsNaN(f) || math.IsInf(f, 0) {
			return f, nil
		}
		return json.Number(oj.PyFloat(f)), nil
	}
	return n.Value, nil
}

// Verdict 是一条目标的判定结果。
type Verdict struct {
	Bot, Metric, Label string
	Pct                bool
	Lo, Hi             float64 // 目标范围
	Estimate           Estimate
	Target             []any  // 目标范围的原值；nil 时用 Lo、Hi
	Status             string // PASS | FAIL | INCONCLUSIVE | KNOWN | NO_DATA
	Note               string
}

// FmtTarget 输出 "70%–95%" 或 "6–10"。
func (v Verdict) FmtTarget() string {
	if v.Pct {
		return Pct0(v.Lo) + "–" + Pct0(v.Hi)
	}
	return FmtG(v.Lo) + "–" + FmtG(v.Hi)
}

// Evaluate 逐条判定；level 传 0 表示 95%。
func Evaluate(df Frame, spec *Spec, level float64) ([]Verdict, error) {
	var out []Verdict
	for _, b := range spec.Bots {
		d := df.OfBot(b.Bot)
		for _, rule := range b.Rules {
			m, ok := MetricByKey(rule.Metric)
			if !ok {
				return nil, fmt.Errorf("未知指标：%s", rule.Metric)
			}
			v := Verdict{Bot: b.Bot, Metric: m.Key, Label: m.Label, Pct: m.Pct, Lo: rule.Lo, Hi: rule.Hi, Target: rule.Raw}
			if d.Len() == 0 {
				v.Estimate = Estimate{math.NaN(), 0, 0, 0}
				v.Status, v.Note = "NO_DATA", fmt.Sprintf("没有 %s 的模拟结果", b.Bot)
				out = append(out, v)
				continue
			}
			est := m.Fn(d, level)
			v.Estimate = est
			switch {
			case est.N == 0:
				v.Status, v.Note = "INCONCLUSIVE", "没有可用样本（例如没有胜局）"
			case d.Len() < spec.RunsMin:
				v.Status, v.Note = "INCONCLUSIVE", fmt.Sprintf("样本 %d < %d", d.Len(), spec.RunsMin)
			case rule.Lo <= est.Lo && est.Hi <= rule.Hi:
				v.Status = "PASS"
			case est.Hi < rule.Lo || est.Lo > rule.Hi:
				v.Status = "FAIL"
			default:
				v.Status, v.Note = "INCONCLUSIVE", "置信区间跨越目标边界，需要更多样本"
			}
			if v.Status == "FAIL" && rule.KnownIssue != "" {
				v.Status, v.Note = "KNOWN", rule.KnownIssue
			}
			out = append(out, v)
		}
	}
	return out, nil
}

// --- 写 YAML（与 yaml.safe_dump(allow_unicode=True, sort_keys=False) 同样的块状格式）-------------

// DumpYAML 把 JSON 值写成 PyYAML 默认的块状 YAML。
func DumpYAML(v any) string {
	var b strings.Builder
	dumpYAML(&b, v, 0)
	return b.String()
}

func dumpYAML(b *strings.Builder, v any, indent int) {
	pad := strings.Repeat("  ", indent)
	switch x := v.(type) {
	case *oj.Object:
		for _, k := range x.Keys() {
			b.WriteString(pad + yamlScalar(k) + ":")
			yamlChild(b, x.Get(k), indent, false)
		}
	case []any:
		for _, e := range x {
			b.WriteString(pad + "-")
			yamlChild(b, e, indent, true)
		}
	}
}

// yamlChild 写键或 "-" 之后的部分。PyYAML 的序列和上层的键对齐，不再缩进。
func yamlChild(b *strings.Builder, v any, indent int, inSeq bool) {
	switch x := v.(type) {
	case *oj.Object:
		if x.Len() == 0 {
			b.WriteString(" {}\n")
			return
		}
		if inSeq { // "- key: value" 写在同一行
			var sub strings.Builder
			dumpYAML(&sub, x, indent+1)
			b.WriteString(" " + strings.TrimPrefix(sub.String(), strings.Repeat("  ", indent+1)))
			return
		}
		b.WriteString("\n")
		dumpYAML(b, x, indent+1)
	case []any:
		if len(x) == 0 {
			b.WriteString(" []\n")
			return
		}
		if inSeq {
			var sub strings.Builder
			dumpYAML(&sub, x, indent+1)
			b.WriteString(" " + strings.TrimPrefix(sub.String(), strings.Repeat("  ", indent+1)))
			return
		}
		b.WriteString("\n")
		dumpYAML(b, x, indent)
	default:
		b.WriteString(" " + yamlAtom(v) + "\n")
	}
}

func yamlAtom(v any) string {
	switch x := v.(type) {
	case nil:
		return "null"
	case bool:
		return strconv.FormatBool(x)
	case string:
		return yamlScalar(x)
	case json.Number:
		return yamlNumber(oj.PyNumber(x))
	case int:
		return strconv.Itoa(x)
	case float64:
		return yamlNumber(oj.PyFloat(x))
	}
	return yamlScalar(fmt.Sprint(v))
}

// yamlNumber：PyYAML 给没有小数点的指数形式补上 ".0"（1e+16 → 1.0e+16）。
func yamlNumber(s string) string {
	if i := strings.IndexByte(s, 'e'); i >= 0 && !strings.Contains(s, ".") {
		return s[:i] + ".0" + s[i:]
	}
	switch s {
	case "NaN", "nan":
		return ".nan"
	case "Infinity", "inf":
		return ".inf"
	case "-Infinity", "-inf":
		return "-.inf"
	}
	return s
}

// yamlScalar 能不加引号就不加；否则用单引号，含换行等控制字符时用双引号。
func yamlScalar(s string) string {
	if plainOK(s) {
		return s
	}
	for _, r := range s {
		if r < 0x20 || r == 0x7f {
			return oj.Dump(s, oj.Compact) // JSON 字符串也是合法的 YAML 双引号标量
		}
	}
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}

func plainOK(s string) bool {
	if s == "" || strings.TrimSpace(s) != s {
		return false
	}
	if strings.ContainsAny(s[:1], "-?:,[]{}#&*!|>'\"%@`") && !(s[0] == '-' && len(s) > 1 && s[1] != ' ') {
		return false
	}
	if strings.Contains(s, ": ") || strings.Contains(s, " #") || strings.HasSuffix(s, ":") {
		return false
	}
	// 交给解析器确认：不加引号读回来必须还是同一个字符串（排除数字、布尔、null、日期等）
	var n yaml.Node
	if err := yaml.Unmarshal([]byte(s), &n); err != nil || len(n.Content) != 1 {
		return false
	}
	c := n.Content[0]
	if c.Kind != yaml.ScalarNode || c.ShortTag() != "!!str" || c.Value != s {
		return false
	}
	switch strings.ToLower(s) { // YAML 1.1（PyYAML）还把这些当布尔
	case "yes", "no", "on", "off", "true", "false", "null", "~":
		return false
	}
	return true
}
