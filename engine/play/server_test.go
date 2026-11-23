package play

import (
	"encoding/binary"
	"encoding/json"
	"io"
	"net"
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
	ok := ask(t, s, `{"op":"picks_check","def":"hero","nodes":["slam","iron_arm","shield_wall"]}`)
	if ok["error"] != "" || ok["cost"] != float64(4) {
		t.Errorf("picks: %v", ok)
	}
	over := ask(t, s, `{"op":"picks_check","def":"hero","nodes":["slam","iron_arm","shield_wall","intercept"]}`)
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

// 招募来的人按自己的单位定义学技能：加点以出战名单里的 id 为键。
func TestPartyLearnsItsOwnTree(t *testing.T) {
	s := newServer(t)
	plain := ask(t, s, `{"op":"build","battle":"1-4","party":[{"id":"r2","def":"bandit_chief","name":"伊达斯"}]}`)["state"].(map[string]any)
	trained := ask(t, s, `{"op":"build","battle":"1-4","party":[{"id":"r2","def":"bandit_chief","name":"伊达斯"}],"picks":{"r2":["idas_frame","idas_knee"]}}`)["state"].(map[string]any)
	before, after := unitOf(plain, "r2"), unitOf(trained, "r2")
	if after["max_hp"].(float64) != before["max_hp"].(float64)+8 {
		t.Errorf("厚实筋骨应该加 8 点生命上限: %v -> %v", before["max_hp"], after["max_hp"])
	}
	if len(after["skills"].([]any)) != len(before["skills"].([]any))+1 {
		t.Errorf("扫膝应该多出一个招式: %v -> %v", before["skills"], after["skills"])
	}
	check := ask(t, s, `{"op":"picks_check","def":"bandit_chief","nodes":["idas_knee"]}`)
	if check["error"] == "" {
		t.Errorf("没学前置就学扫膝应该不合法")
	}
}

// 出战招式：只带列出的那几个，超过四个不让开战；没列出的单位照旧带全部。
func TestLoadoutLimitsSkills(t *testing.T) {
	s := newServer(t)
	picks := `"picks":{"hero":["shield_wall","shield_drive","slam","heel_strike"]}`
	all := unitOf(ask(t, s, `{"op":"build","battle":"1-4",`+picks+`}`)["state"].(map[string]any), "hero")
	if len(all["skills"].([]any)) != 4 {
		t.Fatalf("主角应有 4 个招式: %v", all["skills"])
	}
	some := unitOf(ask(t, s, `{"op":"build","battle":"1-4",`+picks+`,"loadout":{"hero":["heel_strike","spear","breaker"]}}`)["state"].(map[string]any), "hero")
	if len(some["skills"].([]any)) != 2 {
		t.Errorf("只该带上扫膝和矛刺（碎阵重击没学）: %v", some["skills"])
	}
	var over map[string]any
	_ = json.Unmarshal(s.Handle([]byte(`{"op":"build","battle":"1-4",`+picks+`,"loadout":{"hero":["spear","shield_bash","shield_drive","heel_strike","breaker"]}}`)), &over)
	if over["fail"] == nil {
		t.Errorf("带五个招式应该被拒绝")
	}
}

// 招募来的人带着自己的起始招式进场。
func TestPartyBringsStarterSkill(t *testing.T) {
	s := newServer(t)
	st := ask(t, s, `{"op":"build","battle":"1-4","party":[{"id":"r1","def":"bandit","name":"吕科斯","skills":["heavy_cut"]}]}`)["state"].(map[string]any)
	if got := unitOf(st, "r1")["skills"].([]any); len(got) != 2 {
		t.Errorf("佣兵应有劈砍和重劈两招: %v", got)
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
