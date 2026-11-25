package studio

import (
	"strings"
	"testing"
	"time"

	oj "srpg/balance/ordjson"
)

// 支援对比：一关、几位英雄各带一遍，结果存下来能读回。
func TestSupportComparisonRunsAndStores(t *testing.T) {
	p := sandbox(t)
	s := New(Config{Paths: p})
	ts := newHTTP(t, s)
	code, v, raw := call(t, ts, "GET", "/api/supports", "")
	if code != 200 {
		t.Fatal(raw)
	}
	view := v.(*oj.Object)
	if len(view.Array("heroes")) != 6 || view.Get("report") != nil {
		t.Fatalf("空的对比表不对：%.300s", raw)
	}
	for _, b := range view.Array("battles") {
		if strings.HasPrefix(b.(*oj.Object).Str("id", ""), "1-") {
			t.Errorf("第一章没有英雄可雇，不该列出来：%v", b)
		}
	}
	if code, _, raw = call(t, ts, "POST", "/api/supports/run", `{"scope":"2-1","runs":10}`, "X-Actor", "ai"); code != 200 {
		t.Fatal(raw)
	}
	deadline := time.Now().Add(90 * time.Second)
	for {
		_, v, _ = call(t, ts, "GET", "/api/supports", "")
		if run := v.(*oj.Object).Object("run"); run.Get("running") != true {
			if msg := run.Str("error", ""); msg != "" {
				t.Fatal(msg)
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("支援对比一直没有结束")
		}
		time.Sleep(50 * time.Millisecond)
	}
	rep := v.(*oj.Object).Object("report")
	if rep == nil {
		t.Fatal("跑完没有存下结果")
	}
	seen, usual := map[string]bool{}, ""
	for _, c := range rep.Array("cells") {
		o := c.(*oj.Object)
		seen[o.Str("support", "")] = true
		if o.Get("usual") == true {
			usual = o.Str("support", "")
		}
	}
	// 第二章来得了四位，加上不带。
	if len(seen) != 5 || !seen["none"] || !seen["iphicles"] || seen["idas"] {
		t.Errorf("2-1 应该是不带加四位第二章的英雄：%v", seen)
	}
	if usual != "phalerus" {
		t.Errorf("出战配置里一般玩家带的是法勒洛斯，标成了 %q", usual)
	}
}
