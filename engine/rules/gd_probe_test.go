package rules

import (
	"bufio"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"testing"
)

// 探针文件由 testdata/parity/probe/probe.gd 在 Godot 4.7.2 里生成。
const probeDir = "../testdata/parity/probe/"

func hexFloat(v float64) string {
	var b [8]byte
	binary.LittleEndian.PutUint64(b[:], math.Float64bits(v))
	return hex.EncodeToString(b[:])
}

func readLines(t *testing.T, name string) []string {
	t.Helper()
	f, err := os.Open(probeDir + name)
	if err != nil {
		t.Fatalf("缺少探针文件 %s: %v", name, err)
	}
	defer f.Close()
	var out []string
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		out = append(out, sc.Text())
	}
	return out
}

func TestRNGMatchesGodot(t *testing.T) {
	var rng *RNG
	i := 0
	draws := 0
	for n, line := range readLines(t, "rng.txt") {
		kind, want, _ := strings.Cut(line, " ")
		var got string
		switch kind {
		case "seed":
			seed, _ := strconv.ParseInt(want, 10, 64)
			rng = NewRNG(seed)
			i = 0
			continue
		case "randi":
			got = fmt.Sprint(rng.Randi())
		case "randf":
			got = hexFloat(rng.Randf())
		case "randf_range":
			got = hexFloat(rng.RandfRange(-0.3, 0.3))
		case "randi_range":
			got = fmt.Sprint(rng.RandiRange(-5, 17))
		case "mix":
			got = hexFloat(12.25 + rng.RandfRange(-0.3, 0.3))
		}
		if got != want {
			t.Fatalf("第 %d 行 %s（第 %d 次抽取）: Godot %s, Go %s", n+1, kind, i, want, got)
		}
		i++
		draws++
	}
	if draws < 10000 {
		t.Fatalf("探针样本太少: %d", draws)
	}
}

type probeLCG struct{ x int64 }

func (l *probeLCG) next() int64 {
	l.x = (l.x*1103515245 + 12345) % 2147483648
	return l.x
}

func TestSortMatchesGodot(t *testing.T) {
	type item struct {
		score float64
		i     int
	}
	lcg := &probeLCG{x: 12345}
	lines := readLines(t, "sort.txt")
	if len(lines) != 600 {
		t.Fatalf("sort.txt 行数 %d", len(lines))
	}
	for round, want := range lines {
		n := int(lcg.next() % 300)
		if round < 40 {
			n = round
		}
		spread := 1 + lcg.next()%40
		arr := make([]item, n)
		for i := range arr {
			arr[i] = item{float64(lcg.next()%spread) * 0.5, i}
		}
		SortCustom(arr, func(a, b item) bool { return a.score > b.score })
		ids := make([]string, n)
		for i, e := range arr {
			ids[i] = strconv.Itoa(e.i)
		}
		if got := strings.Join(ids, " "); got != want {
			t.Fatalf("第 %d 组 (n=%d): 顺序不同\nGodot %s\nGo    %s", round, n, want, got)
		}
	}
}
