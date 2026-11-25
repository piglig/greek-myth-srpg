package studio

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	oj "srpg/balance/ordjson"
)

// 难度总表：跑一关、存盘、读回、改目标后重新定论。用真的引擎，局数很少。
func TestDifficultyRunStoreAndRetarget(t *testing.T) {
	p := sandbox(t)
	real := p.Balance
	p.Balance = filepath.Join(t.TempDir(), "balance") // 目标文件会被改写，不能碰真的那份
	os.MkdirAll(p.Balance, 0o755)
	for _, f := range []string{"difficulty.yaml", "kits.yaml"} {
		if err := copyFile(filepath.Join(real, f), filepath.Join(p.Balance, f)); err != nil {
			t.Fatal(err)
		}
	}
	s := New(Config{Paths: p})
	ts := newHTTP(t, s)

	code, v, raw := call(t, ts, "GET", "/api/difficulty", "")
	if code != 200 {
		t.Fatal(raw)
	}
	view := v.(*oj.Object)
	if view.Get("report") != nil || len(view.Array("battles")) < 10 || len(view.Array("columns")) < 2 {
		t.Fatalf("空的总表不对：%s", raw[:min(300, len(raw))])
	}

	if code, _, raw := call(t, ts, "POST", "/api/difficulty/run", `{"scope":"9-9"}`); code == 200 {
		t.Fatalf("不存在的关卡应该被拒绝：%s", raw)
	}
	code, _, raw = call(t, ts, "POST", "/api/difficulty/run", `{"scope":"1-1","runs":12}`, "X-Actor", "ai")
	if code != 200 {
		t.Fatal(raw)
	}
	deadline := time.Now().Add(60 * time.Second)
	for {
		_, v, _ = call(t, ts, "GET", "/api/difficulty", "")
		if run := v.(*oj.Object).Object("run"); run.Get("running") != true {
			if msg := run.Str("error", ""); msg != "" {
				t.Fatal(msg)
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("难度判定一直没有结束")
		}
		time.Sleep(50 * time.Millisecond)
	}
	rep := v.(*oj.Object).Object("report")
	if rep == nil {
		t.Fatal("跑完没有存下结果")
	}
	var primary *oj.Object
	for _, c := range rep.Array("cells") {
		if o := c.(*oj.Object); o.Get("primary") == true {
			primary = o
		}
	}
	if primary == nil || primary.Str("battle", "") != "1-1" || primary.Str("verdict", "") != "ok" {
		t.Fatalf("1-1 的主要验收格不对：%v", oj.Dump(primary, oj.Compact))
	}
	if rep.Object("hashes").Str("1-1", "") == "" {
		t.Error("没有记下数据指纹")
	}

	// 把教学关的目标改成一个它达不到的区间：胜率不变，判定变成偏易；文件里的注释还在。
	code, _, raw = call(t, ts, "PUT", "/api/difficulty/bands", `{"kind":"teaching","kit":"typical","bot":"casual","lo":0.2,"hi":0.5}`)
	if code != 200 {
		t.Fatal(raw)
	}
	text := string(must(os.ReadFile(filepath.Join(p.Balance, "difficulty.yaml"))))
	if !strings.Contains(text, "# 难度目标") || !strings.Contains(text, "0.20, 0.50") {
		t.Errorf("目标文件没有按预期改写：\n%s", text)
	}
	_, v, _ = call(t, ts, "GET", "/api/difficulty", "")
	for _, c := range v.(*oj.Object).Object("report").Array("cells") {
		if o := c.(*oj.Object); o.Get("primary") == true && o.Str("verdict", "") != "easy" {
			t.Errorf("改了目标之后应当重新定论为偏易：%s", oj.Dump(o, oj.Compact))
		}
	}
	if code, _, _ := call(t, ts, "PUT", "/api/difficulty/bands", `{"kind":"teaching","kit":"typical","bot":"casual","lo":0.9,"hi":0.5}`); code == 200 {
		t.Error("下限高于上限应该被拒绝")
	}
}
