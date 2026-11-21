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
	if len(data["battles"].([]any)) < 3 || len(data["skills"].([]any)) == 0 || len(data["trees"].([]any)) != 4 {
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
