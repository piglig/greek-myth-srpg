package sim

import (
	"bufio"
	"bytes"
	"context"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
	"testing"

	"srpg/rules"
)

// 对拍测试：testdata/parity 下的基准文件由原 GDScript 引擎在 Godot 4.7.2 里生成
// （gen_reference.sh / gen_variant.sh / probe.gd）。Go 引擎必须逐字节重现它们，只有耗时 ms 例外。
//
// 规则有意改动之后，受影响的战斗不可能再和原引擎一致。这些用例标了 rebased：它们的基准
// 改由 Go 引擎自己生成，只用来发现无意的改动。重新生成：
//
//	SRPG_REBASE=1 go test ./sim -run TestRowsMatchGodot
//
// 2026-11-24：1-5 的六个用例改为 rebased。涅墨亚狮子的咆哮从「恐惧」改成了「震退 1 格」
// （游戏只保留灼烧、中毒、束缚、眩晕四种异常状态，见 06-decisions）。

const parityDir = "../testdata/parity/"

var picksVariant = map[string][]string{
	"hero":     {"shield_wall", "intercept", "slam"},
	"atalanta": {"skirmish", "leap_shot", "vital_shot"},
}

var goldenCases = []struct {
	file    string
	opts    Options
	rebased bool
}{
	{"godot_1-4_novice", Options{Battle: "1-4", Bot: "novice"}, false},
	{"godot_1-4_skilled", Options{Battle: "1-4", Bot: "skilled"}, false},
	{"godot_1-5_novice", Options{Battle: "1-5", Bot: "novice"}, true},
	{"godot_1-5_skilled", Options{Battle: "1-5", Bot: "skilled"}, true},
	{"godot_test_novice", Options{Battle: "test", Bot: "novice"}, false},
	{"godot_test_skilled", Options{Battle: "test", Bot: "skilled"}, false},
	{"godot_overlay_1-4x_novice", Options{Battle: "1-4x", Bot: "novice", DataDir: parityDir + "overlay"}, false},
	{"godot_overlay_1-4x_skilled", Options{Battle: "1-4x", Bot: "skilled", DataDir: parityDir + "overlay"}, false},
	{"godot_overlay_1-5_skilled", Options{Battle: "1-5", Bot: "skilled", DataDir: parityDir + "overlay"}, true},
	{"godot_set_1-4_skilled", Options{Battle: "1-4", Bot: "skilled", Sets: []string{"units:wolf.str=9", "units:heracles.max_hp=70"}}, false},
	{"godot_picks_1-4_skilled", Options{Battle: "1-4", Bot: "skilled", Picks: picksVariant}, false},
	{"godot_picks_1-5_skilled", Options{Battle: "1-5", Bot: "skilled", Picks: picksVariant}, true},
	{"godot_picks_1-5_novice", Options{Battle: "1-5", Bot: "novice", Picks: picksVariant}, true},
	{"godot_maxrounds_1-5_novice", Options{Battle: "1-5", Bot: "novice", MaxRounds: 3}, true},
}

var msField = regexp.MustCompile(`"ms":\d+`)

func readLines(t *testing.T, path string) [][]byte {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("缺少基准文件: %v", err)
	}
	defer f.Close()
	var out [][]byte
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<22), 1<<22)
	for sc.Scan() {
		if len(bytes.TrimSpace(sc.Bytes())) > 0 {
			out = append(out, append([]byte(nil), sc.Bytes()...))
		}
	}
	return out
}

func TestRowsMatchGodot(t *testing.T) {
	total := 0
	for _, gc := range goldenCases {
		t.Run(gc.file, func(t *testing.T) {
			golden := readLines(t, parityDir+gc.file+".jsonl")
			opts := gc.opts
			if opts.DataDir == "" {
				opts.DataDir = parityDir + "base"
			} // Original roster used for the Godot captures.
			opts.Count = len(golden)
			rows, err := Run(context.Background(), opts)
			if err != nil {
				t.Fatal(err)
			}
			if gc.rebased && os.Getenv("SRPG_REBASE") != "" {
				var fresh bytes.Buffer
				for i := range rows {
					line, err := rows[i].JSON()
					if err != nil {
						t.Fatal(err)
					}
					fresh.Write(msField.ReplaceAll(line, []byte(`"ms":0`)))
					fresh.WriteByte(10)
				}
				if err := os.WriteFile(parityDir+gc.file+".jsonl", fresh.Bytes(), 0o644); err != nil {
					t.Fatal(err)
				}
				return
			}
			bad := 0
			for i := range rows {
				got, err := rows[i].JSON()
				if err != nil {
					t.Fatal(err)
				}
				got = msField.ReplaceAll(got, []byte(`"ms":0`))
				want := msField.ReplaceAll(golden[i], []byte(`"ms":0`))
				if !bytes.Equal(got, want) {
					if bad++; bad <= 3 {
						t.Errorf("种子 %d 与 Godot 不一致\nGodot: %s\nGo:    %s", i, firstDiff(want, got), firstDiff(got, want))
					}
				}
			}
			if bad > 0 {
				t.Errorf("%s: %d / %d 行不一致", gc.file, bad, len(rows))
			}
			total += len(rows)
		})
	}
	t.Logf("对拍 %d 场战斗", total)
}

// 第一处不同的位置附近的片段。
func firstDiff(a, b []byte) string {
	i := 0
	for i < len(a) && i < len(b) && a[i] == b[i] {
		i++
	}
	return string(a[max(0, i-80):min(len(a), i+120)])
}

// 并行数不影响结果。
func TestWorkersDoNotChangeResults(t *testing.T) {
	strip := func(rows []Row) []Row {
		for i := range rows {
			rows[i].MS = 0
		}
		return rows
	}
	one, err := Run(context.Background(), Options{Battle: "1-5", Bot: "skilled", Count: 24, SeedFrom: 100, Workers: 1})
	if err != nil {
		t.Fatal(err)
	}
	calls := 0
	many, err := Run(context.Background(), Options{Battle: "1-5", Bot: "skilled", Count: 24, SeedFrom: 100, Workers: 8,
		Progress: func(done, total int) {
			calls++
			if done != calls || total != 24 {
				t.Errorf("progress(%d, %d) at call %d", done, total, calls)
			}
		}})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(strip(one), strip(many)) {
		t.Error("1 个和 8 个 worker 的结果不同")
	}
	if calls != 24 {
		t.Errorf("progress 被调用 %d 次", calls)
	}
}

func TestRunRejectsBadInput(t *testing.T) {
	if _, err := Run(context.Background(), Options{Battle: "1-4", Bot: "nobody", Count: 1}); err == nil {
		t.Error("未知的机器人应该报错")
	}
	if _, err := Run(context.Background(), Options{Battle: "no-such", Bot: "novice", Count: 1}); err == nil {
		t.Error("未知的战斗应该报错")
	}
	if _, err := Run(context.Background(), Options{Battle: "1-4", Bot: "novice", Count: 1, Sets: []string{"units:nobody.str=1"}}); err == nil {
		t.Error("改写不存在的键应该报错")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := Run(ctx, Options{Battle: "1-4", Bot: "skilled", Count: 50, Workers: 2}); err == nil {
		t.Error("取消后应该返回错误")
	}
}

func TestReplayMatchesGodot(t *testing.T) {
	cases := []struct {
		file, battle, bot string
		seed              int
	}{
		{"godot_replay_1-4_skilled_0", "1-4", "skilled", 0},
		{"godot_replay_1-5_skilled_3", "1-5", "skilled", 3},
		{"godot_replay_1-5_novice_1", "1-5", "novice", 1},
	}
	for _, rc := range cases {
		want, err := os.ReadFile(parityDir + rc.file + ".json")
		if err != nil {
			t.Fatal(err)
		}
		rep, err := Replay(rc.battle, rc.bot, rc.seed, parityDir+"base")
		if err != nil {
			t.Fatal(err)
		}
		got, err := rep.JSON()
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(got, bytes.TrimSpace(want)) {
			t.Errorf("%s 与 Godot 的回放不一致\nGodot: %s\nGo:    %s", rc.file, firstDiff(want, got), firstDiff(got, want))
		}
	}
}

func TestMetricsMatchGodot(t *testing.T) {
	want, err := os.ReadFile(parityDir + "godot_metrics.json")
	if err != nil {
		t.Fatal(err)
	}
	data, err := rules.LoadData(rules.DataOptions{})
	if err != nil {
		t.Fatal(err)
	}
	m, err := ExportMetrics(data)
	if err != nil {
		t.Fatal(err)
	}
	// Compare the original Godot roster; newer units still appear in the live matrix.
	var fixture Metrics
	if err := json.Unmarshal(want, &fixture); err != nil {
		t.Fatal(err)
	}
	if _, ok := m.Units["refugee"]; !ok {
		t.Fatal("missing civilian damage target")
	}
	// Newly learned attacks have no reference value in the archived game.
	originalSkills := map[string]bool{}
	for _, hit := range fixture.Hits {
		originalSkills[hit.Skill] = true
	}
	original := m.Hits[:0]
	for _, hit := range m.Hits {
		_, atk := fixture.Units[hit.Attacker]
		_, tgt := fixture.Units[hit.Target]
		if atk && tgt && originalSkills[hit.Skill] {
			original = append(original, hit)
		}
	}
	m.Hits = original
	for id := range m.Units {
		if _, ok := fixture.Units[id]; !ok {
			delete(m.Units, id)
		}
	}
	text, err := m.JSON()
	if err != nil {
		t.Fatal(err)
	}
	var a, b any
	if err := json.Unmarshal(want, &a); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(text, &b); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(a, b) {
		t.Error("伤害矩阵与 Godot 导出的不一致")
	}
	if len(m.Hits) != 504 {
		t.Errorf("命中条数 %d", len(m.Hits))
	}
}

func TestFloatFormatMatchesGodot(t *testing.T) {
	lines := readLines(t, filepath.Join(parityDir, "probe", "floats.txt"))
	if len(lines) < 3000 {
		t.Fatalf("探针样本太少: %d", len(lines))
	}
	for _, line := range lines {
		hx, want, _ := strings.Cut(string(line), " ")
		raw, err := hex.DecodeString(hx)
		if err != nil {
			t.Fatal(err)
		}
		v := math.Float64frombits(binary.LittleEndian.Uint64(raw))
		if got := formatGDFloat(v); got != want {
			t.Fatalf("%v: Godot %s, Go %s", v, want, got)
		}
	}
}
