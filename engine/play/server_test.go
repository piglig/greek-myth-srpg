package play

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"strings"
	"testing"

	"srpg/rules"
)

func newServer(t *testing.T) *Server {
	t.Helper()
	data, err := rules.LoadData(rules.DataOptions{})
	if err != nil {
		t.Fatal(err)
	}
	return NewServer(data)
}

func ask(t *testing.T, s *Server, req string) map[string]any {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal(s.Handle([]byte(req)), &out); err != nil {
		t.Fatal(err)
	}
	if f, bad := out["fail"]; bad {
		t.Fatalf("%s -> fail: %v", req, f)
	}
	return out
}

func unitOf(state map[string]any, id string) map[string]any {
	for _, u := range state["units"].([]any) {
		if m := u.(map[string]any); m["id"] == id {
			return m
		}
	}
	return nil
}

// 一场战斗走一遍：建局、移动、攻击、预览不改局面、结束回合、敌方行动。
func TestBattleRoundTrip(t *testing.T) {
	s := newServer(t)
	if p := ask(t, s, `{"op":"hello"}`)["protocol"]; p != float64(Protocol) {
		t.Fatalf("protocol %v", p)
	}
	data := ask(t, s, `{"op":"data"}`)
	if len(data["battles"].([]any)) < 3 || len(data["skills"].([]any)) == 0 || len(data["trees"].([]any)) < 4 {
		t.Fatalf("data tables incomplete")
	}
	b := ask(t, s, `{"op":"build","battle":"test","picks":{}}`)
	if b["sid"] != float64(1) || b["state"].(map[string]any)["grid"] == nil {
		t.Fatalf("build: %v", b["sid"])
	}
	ask(t, s, `{"op":"start","sid":1}`)

	dests := ask(t, s, `{"op":"destinations","sid":1,"unit":"hero"}`)["cells"].([]any)
	if len(dests) < 5 {
		t.Fatalf("hero should have somewhere to go: %v", dests)
	}
	if e := ask(t, s, `{"op":"validate","sid":1,"action":{"type":"move","unit":"hero","to":[1,6]}}`)["error"]; e != "" {
		t.Fatalf("move should be valid: %v", e)
	}
	mv := ask(t, s, `{"op":"perform","sid":1,"action":{"type":"move","unit":"hero","to":[1,6]}}`)
	if mv["ok"] != true {
		t.Fatalf("move failed: %v", mv["error"])
	}
	ev := mv["events"].([]any)[0].(map[string]any)
	if ev["type"] != "move" || len(ev["path"].([]any)) != 2 {
		t.Errorf("move event: %v", ev)
	}
	hero := unitOf(mv["state"].(map[string]any), "hero")
	if pos := hero["pos"].([]any); pos[0] != float64(1) || pos[1] != float64(6) || hero["can_undo"] != true {
		t.Errorf("hero after move: %v", hero)
	}
	bad := ask(t, s, `{"op":"perform","sid":1,"action":{"type":"move","unit":"hero","to":[1,5]}}`)
	if bad["ok"] != false || bad["error"] != "cannot move now" {
		t.Errorf("second move: %v", bad["error"])
	}

	// 预览不改变局面；目标批量查询给出射程和可选目标
	tg := ask(t, s, `{"op":"targeting","sid":1,"action":{"type":"skill","unit":"atalanta","skill":"shoot"}}`)
	if len(tg["in_range"].([]any)) == 0 {
		t.Errorf("shoot must have a range band")
	}
	wait := ask(t, s, `{"op":"preview","sid":1,"action":{"type":"wait","unit":"atalanta"}}`)
	if wait["ok"] != true || len(wait["events"].([]any)) != 1 {
		t.Errorf("preview: %v", wait)
	}
	if e := ask(t, s, `{"op":"validate","sid":1,"action":{"type":"wait","unit":"atalanta"}}`)["error"]; e != "" {
		t.Errorf("preview must not spend the action: %v", e)
	}

	end := ask(t, s, `{"op":"end_phase","sid":1}`)
	if end["state"].(map[string]any)["phase"] != float64(rules.PhaseEnemy) {
		t.Fatalf("phase after end_phase: %v", end["state"].(map[string]any)["phase"])
	}
	plan := ask(t, s, `{"op":"plan","sid":1,"unit":"wolf_a"}`)["plan"].(map[string]any)
	if plan["action"].(map[string]any)["unit"] != "wolf_a" {
		t.Errorf("plan: %v", plan)
	}
	if ask(t, s, `{"op":"finish","sid":1,"unit":"wolf_a"}`)["again"] != false {
		t.Errorf("a wolf has one activation")
	}
	sim := ask(t, s, `{"op":"simulate","sid":1,"unit":"wolf_b"}`)
	if len(sim["threat"].([]any)) < 10 || sim["plan"] == nil {
		t.Errorf("simulate: %v", sim["plan"])
	}
	back := ask(t, s, `{"op":"end_phase","sid":1}`)["state"].(map[string]any)
	if back["round"] != float64(2) || back["phase"] != float64(rules.PhasePlayer) {
		t.Errorf("round 2 player phase expected: %v %v", back["round"], back["phase"])
	}
}

func TestCaveAndPicks(t *testing.T) {
	s := newServer(t)
	st := ask(t, s, `{"op":"build","battle":"1-5"}`)["state"].(map[string]any)
	cave := st["cave"].(map[string]any)
	if len(cave["entrances"].([]any)) != 2 || len(cave["boulders"].([]any)) != 2 {
		t.Fatalf("cave: %v", cave)
	}
	if lion := unitOf(st, "lion"); lion["boss"] != true || lion["size"] != float64(2) {
		t.Errorf("lion: %v", lion)
	}
	ask(t, s, `{"op":"start","sid":1}`)
	if e := ask(t, s, `{"op":"cave_entrance","sid":1,"unit":"lion"}`)["entrance"]; e != "west" && e != "east" {
		t.Errorf("entrance: %v", e)
	}
	lp := ask(t, s, `{"op":"targeting","sid":1,"action":{"type":"skill","unit":"atalanta","skill":"vital_shot"}}`)
	if len(lp["landings"].([]any)) != 0 {
		t.Errorf("vital_shot is not a leap")
	}
	ok := ask(t, s, `{"op":"picks_check","def":"hero","nodes":["iron_arm","stagger_fist","shield_wall"]}`)
	if ok["error"] != "" || ok["cost"] != float64(4) {
		t.Errorf("picks: %v", ok)
	}
	over := ask(t, s, `{"op":"picks_check","def":"hero","nodes":["iron_arm","stagger_fist","shield_wall","intercept"]}`)
	if over["error"] != "over budget" {
		t.Errorf("picks: %v", over)
	}
}

func TestProtocolErrors(t *testing.T) {
	s := newServer(t)
	for _, req := range []string{`not json`, `{"op":"nope","sid":1}`, `{"op":"start","sid":99}`, `{"op":"build","battle":"no-such"}`} {
		var out map[string]any
		json.Unmarshal(s.Handle([]byte(req)), &out)
		if out["fail"] == nil {
			t.Errorf("%s should fail, got %v", req, out)
		}
	}
	// 旧会话按先后淘汰
	for i := 0; i < maxSessions+2; i++ {
		ask(t, s, `{"op":"build","battle":"test"}`)
	}
	if len(s.sessions) != maxSessions || s.sessions[1] != nil {
		t.Errorf("sessions kept: %d", len(s.sessions))
	}
}

// 帧格式：4 字节小端长度 + JSON；对方断开后 Serve 正常返回。
func TestFraming(t *testing.T) {
	s := newServer(t)
	client, server := net.Pipe()
	done := make(chan error, 1)
	go func() { done <- s.Serve(server) }()
	send := func(msg string) map[string]any {
		head := make([]byte, 4)
		binary.LittleEndian.PutUint32(head, uint32(len(msg)))
		if _, err := client.Write(append(head, msg...)); err != nil {
			t.Fatal(err)
		}
		if _, err := io.ReadFull(client, head); err != nil {
			t.Fatal(err)
		}
		body := make([]byte, binary.LittleEndian.Uint32(head))
		if _, err := io.ReadFull(client, body); err != nil {
			t.Fatal(err)
		}
		var out map[string]any
		if err := json.Unmarshal(body, &out); err != nil {
			t.Fatal(err)
		}
		return out
	}
	if send(`{"op":"hello"}`)["protocol"] != float64(Protocol) {
		t.Error("hello over the wire")
	}
	if send(`{"op":"build","battle":"1-4"}`)["sid"] != float64(1) {
		t.Error("build over the wire")
	}
	client.Close()
	if err := <-done; err != nil {
		t.Errorf("Serve after disconnect: %v", err)
	}
}

func TestPartyDeploys(t *testing.T) {
	s := newServer(t)
	st := ask(t, s, `{"op":"build","battle":"1-4","party":[{"id":"chiron","def":"chiron"},{"id":"r1","def":"bandit","name":"佣兵剑士"}]}`)["state"].(map[string]any)
	hero := unitOf(st, "hero")
	for _, id := range []string{"chiron", "r1"} {
		u := unitOf(st, id)
		if u == nil {
			t.Fatalf("%s 没有上场", id)
		}
		if u["team"] != hero["team"] {
			t.Errorf("%s 不在我方: %v", id, u["team"])
		}
	}
	if name := unitOf(st, "r1")["name"]; name != "佣兵剑士" {
		t.Errorf("招募者的名字没有带上: %v", name)
	}
	// 给了空名单就没有额外的人，即使旧的开关还开着。
	st = ask(t, s, `{"op":"build","battle":"1-4","party":[],"chiron_joined":true}`)["state"].(map[string]any)
	if unitOf(st, "chiron") != nil {
		t.Errorf("空名单不应该带上喀戎")
	}
	var dup map[string]any
	json.Unmarshal(s.Handle([]byte(`{"op":"build","battle":"1-4","party":[{"id":"hero","def":"bandit"}]}`)), &dup)
	if dup["fail"] == nil {
		t.Errorf("和场上单位重名应该报错")
	}
}

// 关卡文件里固定出场的英雄可以留在营地；主角和敌人不行。
func TestBenchLeavesHeroesBehind(t *testing.T) {
	s := newServer(t)
	st := ask(t, s, `{"op":"build","battle":"1-4","bench":["atalanta"],"party":[{"id":"chiron","def":"chiron"}]}`)["state"].(map[string]any)
	if unitOf(st, "atalanta") != nil {
		t.Errorf("留守的阿塔兰忒还在场上")
	}
	if unitOf(st, "hero") == nil || unitOf(st, "chiron") == nil {
		t.Errorf("其余的人应该照常出战")
	}
	var bad map[string]any
	json.Unmarshal(s.Handle([]byte(`{"op":"build","battle":"1-4","bench":["hero"]}`)), &bad)
	if bad["fail"] == nil {
		t.Errorf("主角不能留守")
	}
}

// 招募来的英雄来支援：不上场，主角多一个招式；他学了的节点写在 picks 里他自己的名字下面。
func TestSupportComesOverTheWire(t *testing.T) {
	s := newServer(t)
	st := ask(t, s, `{"op":"build","battle":"1-4","support":"idas","picks":{"idas":["idas_might"]}}`)["state"].(map[string]any)
	if unitOf(st, "idas") != nil {
		t.Errorf("支援的英雄不该上场")
	}
	if skills := fmt.Sprint(unitOf(st, "hero")["skills"]); !strings.Contains(skills, "sup_idas") {
		t.Errorf("主角应该多出召援的招式: %v", skills)
	}
	var bad map[string]any
	json.Unmarshal(s.Handle([]byte(`{"op":"build","battle":"1-4","support":"nobody"}`)), &bad)
	if bad["fail"] == nil {
		t.Errorf("不存在的英雄应该报错")
	}
	bad = nil
	json.Unmarshal(s.Handle([]byte(`{"op":"build","battle":"1-4","support":"idas","picks":{"idas":["idas_quake"]}}`)), &bad)
	if bad["fail"] == nil {
		t.Errorf("没学前置就学的节点应该报错")
	}
	check := ask(t, s, `{"op":"picks_check","def":"idas","nodes":["idas_quake"]}`)
	if check["error"] == "" {
		t.Errorf("没学前置就学扫膝应该不合法")
	}
}

// 出战招式：只带列出的那几个，超过四个不让开战；没列出的单位照旧带全部。
func TestLoadoutLimitsSkills(t *testing.T) {
	s := newServer(t)
	picks := `"picks":{"hero":["shield_wall","shield_drive","iron_arm","heel_strike"]}`
	all := unitOf(ask(t, s, `{"op":"build","battle":"1-4",`+picks+`}`)["state"].(map[string]any), "hero")
	if len(all["skills"].([]any)) != 5 {
		t.Fatalf("主角应有 5 个招式（矛刺、盾击、过肩摔，加学到的两招）: %v", all["skills"])
	}
	some := unitOf(ask(t, s, `{"op":"build","battle":"1-4",`+picks+`,"loadout":{"hero":["heel_strike","breaker"]}}`)["state"].(map[string]any), "hero")
	if got := some["skills"].([]any); len(got) != 2 || got[0] != "spear" {
		t.Errorf("基础攻击总在，再加上扫膝（碎阵重击没学）: %v", some["skills"])
	}
	none := unitOf(ask(t, s, `{"op":"build","battle":"1-4",`+picks+`,"loadout":{"hero":[]}}`)["state"].(map[string]any), "hero")
	if got := none["skills"].([]any); len(got) != 1 || got[0] != "spear" {
		t.Errorf("什么技能都不带时只剩基础攻击: %v", none["skills"])
	}
	var over map[string]any
	_ = json.Unmarshal(s.Handle([]byte(`{"op":"build","battle":"1-4",`+picks+`,"picks":{"hero":["shield_wall","shield_drive","phalanx_thrust","iron_arm","heel_strike","breaker"]},"loadout":{"hero":["shield_bash","shield_drive","phalanx_thrust","heel_strike","breaker"]}}`)), &over)
	if over["fail"] == nil {
		t.Errorf("基础攻击之外带五个技能应该被拒绝")
	}
}

// 出战名单里的人可以带上单位定义之外的招式。
func TestPartyBringsStarterSkill(t *testing.T) {
	s := newServer(t)
	st := ask(t, s, `{"op":"build","battle":"1-4","party":[{"id":"r1","def":"bandit","name":"吕科斯","skills":["shield_bash"]}]}`)["state"].(map[string]any)
	if got := unitOf(st, "r1")["skills"].([]any); len(got) != 2 {
		t.Errorf("应有劈砍和带来的盾击两招: %v", got)
	}
}

// 装备的属性增减照数加到单位身上；不认识的属性不让开战。
func TestGearModsApply(t *testing.T) {
	s := newServer(t)
	plain := unitOf(ask(t, s, `{"op":"build","battle":"1-4"}`)["state"].(map[string]any), "hero")
	geared := unitOf(ask(t, s, `{"op":"build","battle":"1-4","mods":{"hero":{"hp":5,"def":2,"move":-1}}}`)["state"].(map[string]any), "hero")
	if geared["max_hp"].(float64) != plain["max_hp"].(float64)+5 || geared["hp"].(float64) != geared["max_hp"].(float64) {
		t.Errorf("生命上限应 +5 且满血: %v -> %v / %v", plain["max_hp"], geared["max_hp"], geared["hp"])
	}
	if geared["move"].(float64) != plain["move"].(float64)-1 {
		t.Errorf("移动应 −1: %v -> %v", plain["move"], geared["move"])
	}
	var bad map[string]any
	_ = json.Unmarshal(s.Handle([]byte(`{"op":"build","battle":"1-4","mods":{"hero":{"luck":1}}}`)), &bad)
	if bad["fail"] == nil {
		t.Errorf("不认识的属性应该被拒绝")
	}
}

// 随身物品：用一件少一件，用完就没有了；最多带两件；回复药只能用在受伤的己方身上。
func TestItemsAreUsedUp(t *testing.T) {
	s := newServer(t)
	b := ask(t, s, `{"op":"build","battle":"1-4","items":{"hero":["item_potion","item_stone"]}}`)
	sid := int(b["sid"].(float64))
	hero := unitOf(b["state"].(map[string]any), "hero")
	if len(hero["items"].([]any)) != 2 {
		t.Fatalf("主角应带着两件物品: %v", hero["items"])
	}
	ask(t, s, fmt.Sprintf(`{"op":"start","sid":%d}`, sid))
	pos := hero["pos"].([]any)
	here := fmt.Sprintf(`[%v,%v]`, pos[0], pos[1])
	full := ask(t, s, fmt.Sprintf(`{"op":"validate","sid":%d,"action":{"type":"skill","unit":"hero","skill":"item_potion","target":%s}}`, sid, here))
	if full["error"] == "" {
		t.Errorf("满血时不该能喝回复药")
	}
	var over map[string]any
	_ = json.Unmarshal(s.Handle([]byte(`{"op":"build","battle":"1-4","items":{"hero":["item_potion","item_potion","item_stone"]}}`)), &over)
	if over["fail"] == nil {
		t.Errorf("带三件物品应该被拒绝")
	}
}

// 物品的效果：回复药回血并用掉，火油罐点燃目标。
func TestItemEffects(t *testing.T) {
	d, err := rules.LoadData(rules.DataOptions{})
	if err != nil {
		t.Fatal(err)
	}
	st, err := d.Build("1-4", nil)
	if err != nil {
		t.Fatal(err)
	}
	hero := st.Unit("hero")
	for _, id := range []string{"item_potion", "item_firepot"} {
		if err := hero.Pack(d.Skill(id)); err != nil {
			t.Fatal(err)
		}
	}
	rules.StartBattle(st)
	hero.HP = 10
	if o := rules.Perform(st, rules.UseSkill("hero", "item_potion", hero.Pos)); !o.OK {
		t.Fatalf("喝回复药: %s", o.Error)
	}
	if hero.HP != 22 || hero.Charge("item_potion") != 0 || hero.Skill("item_potion") != nil {
		t.Errorf("回复药应回 12 点并用掉: hp %d, 剩 %d", hero.HP, hero.Charge("item_potion"))
	}
	if !hero.HasActed {
		t.Errorf("用物品应算一次行动")
	}
}
