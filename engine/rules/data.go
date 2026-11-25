package rules

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

// 数据表：prototype/data/tables 下的 JSON 是调参数字的唯一来源。
//
// 覆盖层（关卡编辑器的变体）整文件替换：<覆盖目录>/<表>.json 优先于根目录里的同名文件，
// 只存在于覆盖目录的战斗也会列出来。
// 改写（参数扫描、A/B）不动文件：  <表>:<点分键路径>=<json 值>   例如 units:heracles.str=16

// DataOptions 指定从哪里读表。
type DataOptions struct {
	Root    string   // 表的根目录；留空则用 DefaultTablesDir()
	Overlay string   // 可选的覆盖目录
	Sets    []string // 可选的改写，只能改已有的键
}

// Skill 是技能定义（skills.json）。
type Skill struct {
	ID, Name string

	HasMult bool // 范围控制技能（咆哮）不造成伤害，没有 mult 和 type
	Mult    float64
	Type    DamageType

	MinRange, MaxRange       int
	HasMinRange, HasMaxRange bool
	Line                     bool // shape == "line"
	Ranged                   bool
	Knockback, Cooldown      int
	StaggerBonus             int
	MarkedFlankStagger       int

	HasLeap        bool
	Leap, LeapRise int

	// 物品：带进战斗的消耗品，用一次少一件（UnitState.Charges），没有冷却。
	Item bool
	// Heal > 0 或 Cleanse > 0 表示对己方使用：回复生命、解除若干种负面状态。
	Heal, Cleanse int
	// Status 非空表示命中后给目标加上这个状态，持续 Rounds 回合。
	Status string

	SelfStatus string
	AreaStatus string // 非空表示以自身为中心、给范围内敌人加状态的技能
	// AreaKnockback 大于 0 表示以自身为中心、把范围内敌人各震退这么多格的技能。
	AreaKnockback int
	Radius        int
	HasRadius     bool
	Rounds        int
	// Pierce 表示这一击不计算目标的物理防御。
	Pierce bool
	// Throw 表示过肩摔：命中后把目标摔到自己另一侧的相邻格（见 effects.go 的 Throw）。
	Throw bool
	// Relic 表示圣物的主动技能：阶位的好处只对它们生效。
	Relic bool
	// Blast 大于 0 表示指定一格、打到那一格周围 Blast 格内所有敌人的招式；Square 为真时
	// 范围是方形，否则是十字。FriendlyFire 为真时连同伴和自己都打。
	Blast        int
	Square       bool
	FriendlyFire bool
	// Blink 大于 0 表示瞬移到这么多格内的任意一格，不看地形和高度。
	Blink int
	// AreaShield 大于 0 表示给自己和 Radius 格内的同伴各加这么多护盾。
	AreaShield int
}

func (sk *Skill) IsArea() bool {
	return sk.AreaStatus != "" || sk.AreaKnockback > 0 || sk.AreaShield > 0
}

// 游戏里只有这四种异常状态。招式和物品能给别人加上的状态必须在其中。
var ailments = map[string]bool{"burning": true, "poisoned": true, "rooted": true, "stunned": true}

// IsAilment 表示这个状态是四种异常状态之一。
func IsAilment(status string) bool { return ailments[status] }

// Mends 表示这个招式或物品是用在己方身上的（回复或解除状态）。
func (sk *Skill) Mends() bool { return sk.Heal > 0 || sk.Cleanse > 0 }

// TraitValue 是单位定义里的一个特性（保持表里的顺序）。
type TraitValue struct {
	Key   string
	Value int // 数值型特性的值；布尔型为 1 / 0
}

// UnitDef 是单位定义（units.json）。
type UnitDef struct {
	ID, Name                                  string
	HP, MaxHP, Str, Div, Def, Wil, Move, Jump int
	Size, Actions, StaggerMax                 int
	Skills                                    []string
	Traits                                    []TraitValue
}

// TreeNode 是技能树的一个节点：给特性或给技能。
type TreeNode struct {
	ID, Name, Trait, Skill, Desc, Parent string
	Cost                                 int
}

type TreeBranch struct {
	Name  string
	Nodes []TreeNode
}

// BattleUnit 是战斗表里的一个出场单位。
type BattleUnit struct {
	Def, ID, Name string
	Arrival       int
	Team          Team
	Pos           Cell
	Facing        Cell
}

// BattleDef 是一场战斗的布置（battles/<id>.json）。
type BattleDef struct {
	ID, Title   string
	Order       int
	Heights     []string
	Terrain     []string
	EscortExits []Cell
	ReachExits  []Cell
	Targets     []string
	RescueExits []Cell
	Village     *Village
	Units       []BattleUnit
	Cave        *Cave
}

// Data 是加载好的全部数据表。加载后只读，可以在多个 goroutine 间共用。
type Data struct {
	opts DataOptions

	UnitIDs  []string // units.json 里的顺序
	units    map[string]*UnitDef
	SkillIDs []string
	skills   map[string]*Skill

	Points       int
	TreeDefs     []string // skill_tree.json 里有技能树的单位，按表里的顺序
	trees        map[string][]TreeBranch
	defaultPicks map[string][]string

	mu      sync.Mutex
	battles map[string]*BattleDef
}

// DefaultTablesDir 找到 prototype/data/tables：先看环境变量 SRPG_TABLES，
// 再从当前目录和可执行文件所在目录逐级向上找。
func DefaultTablesDir() (string, error) {
	if dir := os.Getenv("SRPG_TABLES"); dir != "" {
		return dir, nil
	}
	var starts []string
	if wd, err := os.Getwd(); err == nil {
		starts = append(starts, wd)
	}
	if exe, err := os.Executable(); err == nil {
		starts = append(starts, filepath.Dir(exe))
	}
	for _, dir := range starts {
		for {
			cand := filepath.Join(dir, "prototype", "data", "tables")
			if st, err := os.Stat(filepath.Join(cand, "units.json")); err == nil && !st.IsDir() {
				return cand, nil
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return "", fmt.Errorf("找不到 prototype/data/tables（可用环境变量 SRPG_TABLES 指定）")
}

// LoadData 读入 units、skills、skill_tree 三张表；战斗表在用到时再读。
func LoadData(opts DataOptions) (*Data, error) {
	if opts.Root == "" {
		root, err := DefaultTablesDir()
		if err != nil {
			return nil, err
		}
		opts.Root = root
	}
	d := &Data{opts: opts, units: map[string]*UnitDef{}, skills: map[string]*Skill{},
		trees: map[string][]TreeBranch{}, defaultPicks: map[string][]string{}, battles: map[string]*BattleDef{}}
	for _, set := range opts.Sets {
		if _, _, _, err := parseSet(set); err != nil {
			return nil, err
		}
	}
	if err := d.loadSkills(); err != nil {
		return nil, err
	}
	if err := d.loadUnits(); err != nil {
		return nil, err
	}
	if err := d.loadTree(); err != nil {
		return nil, err
	}
	return d, nil
}

// --- 有序 JSON ---------------------------------------------------------------------

// jobj 是保持键顺序的 JSON 对象。
type jobj struct {
	keys []string
	m    map[string]any
}

func (o *jobj) has(k string) bool { _, ok := o.m[k]; return ok }

func (o *jobj) set(k string, v any) {
	if _, ok := o.m[k]; !ok {
		o.keys = append(o.keys, k)
	}
	o.m[k] = v
}

func parseJSON(text []byte) (any, error) {
	dec := json.NewDecoder(bytes.NewReader(text))
	v, err := parseValue(dec)
	if err != nil {
		return nil, err
	}
	if _, err := dec.Token(); err == nil {
		return nil, fmt.Errorf("JSON 末尾有多余内容")
	}
	return v, nil
}

func parseValue(dec *json.Decoder) (any, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	switch t := tok.(type) {
	case json.Delim:
		switch t {
		case '{':
			o := &jobj{m: map[string]any{}}
			for dec.More() {
				kt, err := dec.Token()
				if err != nil {
					return nil, err
				}
				v, err := parseValue(dec)
				if err != nil {
					return nil, err
				}
				o.set(kt.(string), v)
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
		return nil, fmt.Errorf("意外的 %v", t)
	default:
		return tok, nil // string, float64, bool, nil
	}
}

// 读一张表：覆盖目录里有就用覆盖的，再套用改写。
func (d *Data) table(name string) (*jobj, error) {
	path := filepath.Join(d.opts.Root, filepath.FromSlash(name)+".json")
	if d.opts.Overlay != "" {
		over := filepath.Join(d.opts.Overlay, filepath.FromSlash(name)+".json")
		if st, err := os.Stat(over); err == nil && !st.IsDir() {
			path = over
		}
	}
	text, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("缺少数据表 %s: %w", path, err)
	}
	text = bytes.TrimPrefix(text, []byte("\xef\xbb\xbf"))
	v, err := parseJSON(text)
	if err != nil {
		return nil, fmt.Errorf("数据表 %s 格式错误: %w", path, err)
	}
	obj, ok := v.(*jobj)
	if !ok {
		return nil, fmt.Errorf("数据表 %s 不是 JSON 对象", path)
	}
	for _, set := range d.opts.Sets {
		table, keyPath, value, _ := parseSet(set)
		if table != name {
			continue
		}
		node := obj
		for _, k := range keyPath[:len(keyPath)-1] {
			next, ok := node.m[k].(*jobj)
			if !ok {
				return nil, fmt.Errorf("改写路径 %s 在 %s 里不存在", strings.Join(keyPath, "."), name)
			}
			node = next
		}
		last := keyPath[len(keyPath)-1]
		if !node.has(last) {
			return nil, fmt.Errorf("改写的键 %s 在 %s 里不存在（改写只能改已有的值）", strings.Join(keyPath, "."), name)
		}
		node.m[last] = value
	}
	return obj, nil
}

// 解析 "<表>:<点分路径>=<json 值>"。值不是合法 JSON 时按字符串处理。
func parseSet(spec string) (table string, path []string, value any, err error) {
	spec = strings.TrimPrefix(spec, "--set=")
	colon := strings.Index(spec, ":")
	eq := strings.Index(spec, "=")
	if colon <= 0 || eq <= colon {
		return "", nil, nil, fmt.Errorf("改写格式错误 %q（应为 表:键.路径=值）", spec)
	}
	raw := spec[eq+1:]
	value, perr := parseJSON([]byte(raw))
	if perr != nil || value == nil {
		value = raw
	}
	return spec[:colon], strings.Split(spec[colon+1:eq], "."), value, nil
}

// --- 取值小工具 ----------------------------------------------------------------------

func asInt(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case bool:
		if n {
			return 1
		}
	case string:
		var i int
		fmt.Sscanf(n, "%d", &i)
		return i
	}
	return 0
}

func (o *jobj) int(k string, def int) int {
	if v, ok := o.m[k]; ok {
		return asInt(v)
	}
	return def
}

func (o *jobj) str(k, def string) string {
	if v, ok := o.m[k].(string); ok {
		return v
	}
	return def
}

func (o *jobj) need(table string, keys ...string) error {
	for _, k := range keys {
		if !o.has(k) {
			return fmt.Errorf("%s 缺少字段 %q", table, k)
		}
	}
	return nil
}

func cellOf(v any) (Cell, error) {
	arr, ok := v.([]any)
	if !ok || len(arr) < 2 {
		return Cell{}, fmt.Errorf("坐标应为 [x, y]")
	}
	return Cell{asInt(arr[0]), asInt(arr[1])}, nil
}

func stringsOf(v any) []string {
	arr, _ := v.([]any)
	out := make([]string, 0, len(arr))
	for _, e := range arr {
		s, _ := e.(string)
		out = append(out, s)
	}
	return out
}

// --- 技能 ------------------------------------------------------------------------

var typeNames = map[string]DamageType{"physical": Physical, "divine": Divine, "true": True}

func (d *Data) loadSkills() error {
	tbl, err := d.table("skills")
	if err != nil {
		return err
	}
	for _, id := range tbl.keys {
		raw, ok := tbl.m[id].(*jobj)
		if !ok || len(raw.keys) == 0 {
			return fmt.Errorf("技能 %s 的定义为空", id)
		}
		sk := &Skill{ID: id, Name: raw.str("name", id)}
		if raw.has("mult") {
			sk.HasMult = true
			sk.Mult, _ = raw.m["mult"].(float64)
		}
		if raw.has("type") {
			t, ok := typeNames[raw.str("type", "")]
			if !ok {
				return fmt.Errorf("技能 %s 的 type 无效", id)
			}
			sk.Type = t
		}
		sk.HasMinRange, sk.MinRange = raw.has("min_range"), raw.int("min_range", 0)
		sk.HasMaxRange, sk.MaxRange = raw.has("max_range"), raw.int("max_range", 0)
		sk.Line = raw.str("shape", "single") == "line"
		sk.Ranged, _ = raw.m["ranged"].(bool)
		sk.Knockback = raw.int("knockback", 0)
		sk.Cooldown = raw.int("cooldown", 0)
		sk.StaggerBonus = raw.int("stagger_bonus", 0)
		sk.MarkedFlankStagger = raw.int("marked_flank_stagger", 0)
		sk.HasLeap, sk.Leap = raw.has("leap"), raw.int("leap", 0)
		sk.LeapRise = raw.int("leap_rise", 0)
		sk.Item, _ = raw.m["item"].(bool)
		sk.Heal = raw.int("heal", 0)
		sk.Cleanse = raw.int("cleanse", 0)
		sk.Status = raw.str("status", "")
		sk.SelfStatus = raw.str("self_status", "")
		sk.AreaStatus = raw.str("area_status", "")
		sk.AreaKnockback = raw.int("area_knockback", 0)
		sk.Pierce, _ = raw.m["pierce"].(bool)
		sk.Throw, _ = raw.m["throw"].(bool)
		sk.Relic, _ = raw.m["relic"].(bool)
		sk.Blast = raw.int("blast", 0)
		sk.Square, _ = raw.m["square"].(bool)
		sk.FriendlyFire, _ = raw.m["friendly_fire"].(bool)
		sk.Blink = raw.int("blink", 0)
		sk.AreaShield = raw.int("area_shield", 0)
		for _, given := range []string{sk.Status, sk.AreaStatus} {
			if given != "" && !IsAilment(given) {
				return fmt.Errorf("招式 %s 的状态 %s 不是四种异常状态（灼烧、中毒、束缚、眩晕）之一", id, given)
			}
		}
		sk.HasRadius, sk.Radius = raw.has("radius"), raw.int("radius", 0)
		sk.Rounds = raw.int("rounds", 1)
		if sk.IsArea() {
			if !sk.HasRadius {
				return fmt.Errorf("范围技能 %s 缺少 radius", id)
			}
		} else if sk.Mends() {
			if err := raw.need("物品 "+id, "min_range", "max_range"); err != nil {
				return err
			}
		} else if sk.SelfStatus == "" {
			if err := raw.need("技能 "+id, "mult", "type", "min_range", "max_range"); err != nil {
				return err
			}
		}
		d.SkillIDs = append(d.SkillIDs, id)
		d.skills[id] = sk
	}
	return nil
}

// Skill 返回技能定义；没有则为 nil。
func (d *Data) Skill(id string) *Skill { return d.skills[id] }

// --- 单位 ------------------------------------------------------------------------

func (d *Data) loadUnits() error {
	tbl, err := d.table("units")
	if err != nil {
		return err
	}
	for _, id := range tbl.keys {
		raw, ok := tbl.m[id].(*jobj)
		if !ok {
			return fmt.Errorf("单位 %s 的定义不是对象", id)
		}
		if err := raw.need("单位 "+id, "name", "hp", "str", "def", "wil", "move", "jump", "skills"); err != nil {
			return err
		}
		u := &UnitDef{ID: id, Name: raw.str("name", id), HP: raw.int("hp", 0), Str: raw.int("str", 0),
			Div: raw.int("div", 0), Def: raw.int("def", 0), Wil: raw.int("wil", 0), Move: raw.int("move", 0),
			Jump: raw.int("jump", 0), Size: raw.int("size", 1), Actions: raw.int("actions", 1),
			StaggerMax: raw.int("stagger_max", 0), Skills: stringsOf(raw.m["skills"])}
		u.MaxHP = raw.int("max_hp", u.HP)
		for _, sk := range u.Skills {
			if d.skills[sk] == nil {
				return fmt.Errorf("单位 %s 用到了不存在的技能 %s", id, sk)
			}
		}
		if traits, ok := raw.m["traits"].(*jobj); ok {
			for _, k := range traits.keys {
				u.Traits = append(u.Traits, TraitValue{k, asInt(traits.m[k])})
			}
		}
		d.UnitIDs = append(d.UnitIDs, id)
		d.units[id] = u
	}
	return nil
}

// UnitDef 返回单位定义；没有则为 nil。
func (d *Data) UnitDef(id string) *UnitDef { return d.units[id] }

// MakeUnit 按定义创建一个单位。
func (d *Data) MakeUnit(defID, id string, team Team, pos, facing Cell) (*UnitState, error) {
	def := d.units[defID]
	if def == nil {
		return nil, fmt.Errorf("没有这个单位定义: %s", defID)
	}
	u := NewUnit()
	u.ID, u.DefID, u.Name = id, defID, def.Name
	u.Team, u.Pos, u.Facing = team, pos, facing
	u.Size = def.Size
	u.MaxHP, u.HP = def.MaxHP, def.HP
	u.Strength, u.Divinity, u.Defense, u.Will = def.Str, def.Div, def.Def, def.Wil
	u.Move, u.Jump = def.Move, def.Jump
	for _, sk := range def.Skills {
		u.Skills = append(u.Skills, d.skills[sk])
	}
	for _, t := range def.Traits {
		u.Traits.Set(t.Key, t.Value)
	}
	u.ActionsPerTurn = def.Actions
	u.ActionsLeft = u.ActionsPerTurn
	u.StaggerMax = def.StaggerMax
	return u, nil
}

// --- 技能树（战前选择的节点，08-skills-hero-atalanta） ------------------------------------

func (d *Data) loadTree() error {
	tbl, err := d.table("skill_tree")
	if err != nil {
		return err
	}
	d.Points = tbl.int("points", 0)
	if trees, ok := tbl.m["trees"].(*jobj); ok {
		for _, def := range trees.keys {
			d.TreeDefs = append(d.TreeDefs, def)
			branches, _ := trees.m[def].([]any)
			for _, b := range branches {
				bo, ok := b.(*jobj)
				if !ok {
					continue
				}
				br := TreeBranch{Name: bo.str("branch", "")}
				nodes, _ := bo.m["nodes"].([]any)
				for _, n := range nodes {
					no, ok := n.(*jobj)
					if !ok {
						continue
					}
					node := TreeNode{ID: no.str("id", ""), Name: no.str("name", ""), Trait: no.str("trait", ""),
						Skill: no.str("skill", ""), Desc: no.str("desc", ""), Parent: no.str("parent", ""), Cost: no.int("cost", 0)}
					if node.Skill != "" && d.skills[node.Skill] == nil {
						return fmt.Errorf("技能树节点 %s 用到了不存在的技能 %s", node.ID, node.Skill)
					}
					br.Nodes = append(br.Nodes, node)
				}
				d.trees[def] = append(d.trees[def], br)
			}
		}
	}
	if picks, ok := tbl.m["default_picks"].(*jobj); ok {
		for _, def := range picks.keys {
			d.defaultPicks[def] = stringsOf(picks.m[def])
		}
	}
	return nil
}

// Trees 返回一棵技能树的分支。名字是单位定义（主角、剧情同伴）或招募英雄自己的名字。
func (d *Data) Trees(defID string) []TreeBranch { return d.trees[defID] }

// DefaultPicks 返回表里的默认加点（副本，可以随意改）。
func (d *Data) DefaultPicks() map[string][]string {
	out := make(map[string][]string, len(d.defaultPicks))
	for k, v := range d.defaultPicks {
		out[k] = append([]string{}, v...)
	}
	return out
}

// TreeNode 找到节点；没有则返回 nil。
func (d *Data) TreeNode(defID, nodeID string) *TreeNode {
	for bi := range d.trees[defID] {
		nodes := d.trees[defID][bi].Nodes
		for ni := range nodes {
			if nodes[ni].ID == nodeID {
				return &nodes[ni]
			}
		}
	}
	return nil
}

func (d *Data) PicksCost(defID string, picks []string) int {
	total := 0
	for _, id := range picks {
		if n := d.TreeNode(defID, id); n != nil {
			total += n.Cost
		}
	}
	return total
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

// ValidatePicks 返回 "" 表示加点合法：不超预算，且每个后续节点都点了它前面的节点。
func (d *Data) ValidatePicks(defID string, picks []string) string {
	return d.ValidateTraining(defID, picks, d.Points)
}

func (d *Data) ValidateTraining(defID string, picks []string, budget int) string {
	seen := map[string]bool{}
	for _, id := range picks {
		n := d.TreeNode(defID, id)
		if n == nil || seen[id] {
			return "unknown node"
		}
		seen[id] = true
		if n.Parent != "" && !contains(picks, n.Parent) {
			return "missing prerequisite"
		}
	}
	if d.PicksCost(defID, picks) > budget {
		return "over budget"
	}
	return ""
}

// AllBuilds 枚举一个单位所有合法的加点（平衡测试用）。
func (d *Data) AllBuilds(defID string) [][]string {
	var ids []string
	for _, br := range d.trees[defID] {
		for _, n := range br.Nodes {
			ids = append(ids, n.ID)
		}
	}
	var out [][]string
	for mask := 0; mask < 1<<len(ids); mask++ {
		picks := []string{}
		for i, id := range ids {
			if mask&(1<<i) != 0 {
				picks = append(picks, id)
			}
		}
		if d.ValidatePicks(defID, picks) == "" {
			out = append(out, picks)
		}
	}
	return out
}

// ApplyPicks 把加点落到单位身上。
func (d *Data) ApplyPicks(u *UnitState, picks []string) {
	for _, id := range picks {
		n := d.TreeNode(u.TreeKey(), id)
		if n == nil {
			continue
		}
		if n.Trait != "" {
			u.Traits.Set(n.Trait, 1)
			switch n.Trait {
			case "bulwark":
				u.Defense += 3
			case "wrestler":
				u.MaxHP += 8
				u.HP += 8
			case "fleet":
				u.Move++
			case "high_jump":
				u.Jump += 2
			case "solar_blood":
				u.Divinity += 3
			case "hex_ward":
				u.Will += 4
			}
		}
		if n.Skill != "" {
			u.AddSkill(d.skills[n.Skill])
		}
	}
}

// --- 战斗 ------------------------------------------------------------------------

var teamNames = map[string]Team{"player": TeamPlayer, "enemy": TeamEnemy, "neutral": TeamNeutral}
var facingNames = map[string]Cell{"N": North, "E": East, "S": South, "W": West}

// Battle 读入一场战斗的布置（读过的会记住）。
func (d *Data) Battle(id string) (*BattleDef, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if b, ok := d.battles[id]; ok {
		return b, nil
	}
	tbl, err := d.table("battles/" + id)
	if err != nil {
		return nil, err
	}
	if err := tbl.need("战斗 "+id, "heights", "units"); err != nil {
		return nil, err
	}
	b := &BattleDef{ID: id, Title: tbl.str("title", id), Order: tbl.int("order", 0),
		Heights: stringsOf(tbl.m["heights"]), Terrain: stringsOf(tbl.m["terrain"])}
	units, _ := tbl.m["units"].([]any)
	for _, e := range units {
		eo, ok := e.(*jobj)
		if !ok {
			return nil, fmt.Errorf("战斗 %s 的单位条目不是对象", id)
		}
		if err := eo.need("战斗 "+id+" 的单位", "def", "id", "team", "pos"); err != nil {
			return nil, err
		}
		bu := BattleUnit{Name: eo.str("name", ""), Def: eo.str("def", ""), ID: eo.str("id", ""), Arrival: eo.int("round", 1)}
		if bu.Pos, err = cellOf(eo.m["pos"]); err != nil {
			return nil, fmt.Errorf("战斗 %s 单位 %s: %w", id, bu.ID, err)
		}
		team, ok := teamNames[eo.str("team", "")]
		if !ok {
			return nil, fmt.Errorf("战斗 %s 单位 %s 的 team 无效", id, bu.ID)
		}
		bu.Team = team
		facing, ok := facingNames[eo.str("facing", "S")]
		if !ok {
			return nil, fmt.Errorf("战斗 %s 单位 %s 的 facing 无效", id, bu.ID)
		}
		bu.Facing = facing
		if d.units[bu.Def] == nil {
			return nil, fmt.Errorf("战斗 %s 用到了不存在的单位 %s", id, bu.Def)
		}
		b.Units = append(b.Units, bu)
	}
	if exits, ok := tbl.m["escort_exits"].([]any); ok {
		for _, raw := range exits {
			cell, err := cellOf(raw)
			if err != nil || cell.Y < 0 || cell.Y >= len(b.Heights) || cell.X < 0 || cell.X >= len(b.Heights[cell.Y]) {
				return nil, fmt.Errorf("%s: invalid escort exit", id)
			}
			b.EscortExits = append(b.EscortExits, cell)
		}
	}
	for _, id := range stringsOf(tbl.m["targets"]) {
		found := false
		for _, bu := range b.Units {
			found = found || (bu.ID == id && bu.Team == TeamEnemy)
		}
		if !found {
			return nil, fmt.Errorf("%s: target %s is not an enemy in this battle", id, id)
		}
		b.Targets = append(b.Targets, id)
	}
	if exits, ok := tbl.m["reach_exits"].([]any); ok {
		for _, raw := range exits {
			cell, err := cellOf(raw)
			if err != nil || cell.Y < 0 || cell.Y >= len(b.Heights) || cell.X < 0 || cell.X >= len(b.Heights[cell.Y]) {
				return nil, fmt.Errorf("%s: invalid reach exit", id)
			}
			b.ReachExits = append(b.ReachExits, cell)
		}
	}
	if exits, ok := tbl.m["rescue_exits"].([]any); ok {
		for _, raw := range exits {
			cell, err := cellOf(raw)
			if err != nil || cell.Y < 0 || cell.Y >= len(b.Heights) || cell.X < 0 || cell.X >= len(b.Heights[cell.Y]) {
				return nil, fmt.Errorf("%s: invalid rescue exit", id)
			}
			b.RescueExits = append(b.RescueExits, cell)
		}
	}
	if v, ok := tbl.m["village"].(*jobj); ok {
		setting := &Village{Ignition: stringsOf(v.m["ignition"])}
		if len(setting.Ignition) != len(b.Heights) || len(b.Heights) == 0 {
			return nil, fmt.Errorf("%s: invalid fire rows", id)
		}
		for _, row := range setting.Ignition {
			if len(row) != len(b.Heights[0]) {
				return nil, fmt.Errorf("%s: invalid fire width", id)
			}
			for _, ch := range row {
				if ch != '.' && (ch < '1' || ch > '9') {
					return nil, fmt.Errorf("%s: invalid fire round", id)
				}
			}
		}
		exits, _ := v.m["exits"].([]any)
		for _, raw := range exits {
			c, err := cellOf(raw)
			if err != nil || c.X < 0 || c.Y < 0 || c.Y >= len(b.Heights) || c.X >= len(b.Heights[c.Y]) {
				return nil, fmt.Errorf("%s: invalid exit", id)
			}
			setting.Exits = append(setting.Exits, c)
		}
		if len(setting.Exits) < 2 {
			return nil, fmt.Errorf("%s: two exit cells required", id)
		}
		b.Village = setting
	}
	if c, ok := tbl.m["cave"].(*jobj); ok {
		if err := c.need("战斗 "+id+" 的 cave", "boss", "trigger_hp", "entrances"); err != nil {
			return nil, err
		}
		cave := &Cave{Boss: c.str("boss", ""), TriggerHP: c.int("trigger_hp", 0), EmergeActions: c.int("emerge_actions", 1)}
		entrances, _ := c.m["entrances"].([]any)
		for _, e := range entrances {
			eo, ok := e.(*jobj)
			if !ok {
				continue
			}
			anchor, err := cellOf(eo.m["anchor"])
			if err != nil {
				return nil, fmt.Errorf("战斗 %s 的入口: %w", id, err)
			}
			if old := cave.Entrance(eo.str("id", "")); old != nil {
				old.Anchor, old.Sealed = anchor, false
				continue
			}
			cave.Entrances = append(cave.Entrances, Entrance{ID: eo.str("id", ""), Anchor: anchor})
		}
		boulders, _ := c.m["boulders"].([]any)
		for _, e := range boulders {
			bo, ok := e.(*jobj)
			if !ok {
				continue
			}
			pos, err := cellOf(bo.m["pos"])
			if err != nil {
				return nil, fmt.Errorf("战斗 %s 的巨石: %w", id, err)
			}
			nb := Boulder{ID: bo.str("id", ""), Pos: pos, Seals: bo.str("seals", "")}
			if cave.Entrance(nb.Seals) == nil {
				return nil, fmt.Errorf("战斗 %s 的巨石 %s 指向不存在的入口 %s", id, nb.ID, nb.Seals)
			}
			if old := cave.Boulder(nb.ID); old != nil {
				*old = nb
				continue
			}
			cave.Boulders = append(cave.Boulders, nb)
		}
		b.Cave = cave
	}
	d.battles[id] = b
	return b, nil
}

// BattleIDs 列出所有战斗 id（根目录和覆盖目录的并集），按 order 字段排序。
func (d *Data) BattleIDs() ([]string, error) {
	seen := map[string]bool{}
	dirs := []string{filepath.Join(d.opts.Root, "battles")}
	if d.opts.Overlay != "" {
		dirs = append(dirs, filepath.Join(d.opts.Overlay, "battles"))
	}
	for i, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			if i == 0 {
				return nil, err
			}
			continue
		}
		for _, e := range entries {
			if !e.IsDir() && strings.HasSuffix(e.Name(), ".json") {
				seen[strings.TrimSuffix(e.Name(), ".json")] = true
			}
		}
	}
	type entry struct {
		order int
		id    string
	}
	var list []entry
	for id := range seen {
		b, err := d.Battle(id)
		if err != nil {
			return nil, err
		}
		list = append(list, entry{b.Order, id})
	}
	sort.Slice(list, func(i, j int) bool {
		if list[i].order != list[j].order {
			return list[i].order < list[j].order
		}
		return list[i].id < list[j].id
	})
	ids := make([]string, len(list))
	for i, e := range list {
		ids[i] = e.id
	}
	return ids, nil
}

// BattleTitle 返回战斗的标题。
func (d *Data) BattleTitle(id string) string {
	if b, err := d.Battle(id); err == nil {
		return b.Title
	}
	return id
}

// Build 按战斗表摆好一场战斗。picks 是 单位定义 → 技能树节点；传空则用表里的默认加点。
func (d *Data) Build(id string, picks map[string][]string) (*BattleState, error) {
	b, err := d.Battle(id)
	if err != nil {
		return nil, err
	}
	grid, err := GridFromRows(b.Heights, b.Terrain)
	if err != nil {
		return nil, fmt.Errorf("战斗 %s: %w", id, err)
	}
	s := NewBattleState(grid)
	s.Village = b.Village
	s.RescueExits = b.RescueExits
	s.EscortExits = b.EscortExits
	s.ReachExits = b.ReachExits
	s.Targets = b.Targets
	for _, e := range b.Units {
		u, err := d.MakeUnit(e.Def, e.ID, e.Team, e.Pos, e.Facing)
		if err != nil {
			return nil, err
		}
		if s.Unit(u.ID) != nil {
			return nil, fmt.Errorf("战斗 %s 里单位 id %s 重复", id, u.ID)
		}
		if !s.FootprintInBounds(u.Pos, u.Size) {
			return nil, fmt.Errorf("战斗 %s 里单位 %s 站在地图外", id, u.ID)
		}
		if u.ID == "wounded_chiron" {
			u.Move = 0
		}
		if e.Name != "" {
			u.Name = e.Name
		}
		if e.Arrival > 1 {
			u.Arrival = e.Arrival
			u.Alive = false
		}
		s.AddUnit(u)
	}
	s.Cave = b.Cave.copy()
	if len(picks) == 0 {
		picks = d.defaultPicks
	}
	for _, u := range s.Units {
		if u.Team == TeamPlayer {
			d.ApplyPicks(u, picks[u.DefID])
		}
	}
	return s, nil
}
