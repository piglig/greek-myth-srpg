package balance

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"os"
	"path/filepath"
	"sync"
	"time"

	oj "srpg/balance/ordjson"
)

// FileSimulator 不跑战斗，而是从已有的 runs.jsonl 里按种子取结果：
// <Dir>/<battle>/<bot>/runs.jsonl（即 balance/out/sim 的布局）。用于在引擎接入前验证整条流程。
type FileSimulator struct {
	Dir string
}

func (f FileSimulator) Run(ctx context.Context, o SimOptions) ([]RawRow, error) {
	path := filepath.Join(f.Dir, o.Battle, o.Bot, "runs.jsonl")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("文件模拟器读不到 %s：%w", path, err)
	}
	bySeed := map[int]RawRow{}
	for _, line := range bytes.Split(data, []byte("\n")) {
		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}
		var head struct {
			Seed *int `json:"seed"`
		}
		if err := json.Unmarshal(line, &head); err != nil || head.Seed == nil {
			return nil, fmt.Errorf("%s 里有无法识别的行", path)
		}
		bySeed[*head.Seed] = RawRow(append([]byte(nil), line...))
	}
	out := make([]RawRow, 0, o.Count)
	for i := 0; i < o.Count; i++ {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		row, ok := bySeed[o.SeedFrom+i]
		if !ok {
			return nil, fmt.Errorf("%s 里没有种子 %d 的结果", path, o.SeedFrom+i)
		}
		out = append(out, row)
		if o.Progress != nil {
			o.Progress(i+1, o.Count)
		}
	}
	return out, nil
}

func (f FileSimulator) Replay(ctx context.Context, o ReplayOptions) (json.RawMessage, error) {
	return nil, fmt.Errorf("文件模拟器不能生成回放")
}

// FakeSimulator 用种子决定的假对局代替战斗（测试用）：结果只取决于 (battle, bot, seed) 和 WinRate。
type FakeSimulator struct {
	// WinRate 给出这一批对局的胜率；nil 时为 0.8。
	WinRate func(o SimOptions) float64
	Delay   time.Duration // 每局耗时，用来测试取消和进度

	mu    sync.Mutex
	calls []SimOptions
}

// Calls 返回至今收到的所有请求。
func (f *FakeSimulator) Calls() []SimOptions {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]SimOptions(nil), f.calls...)
}

func (f *FakeSimulator) Run(ctx context.Context, o SimOptions) ([]RawRow, error) {
	f.mu.Lock()
	f.calls = append(f.calls, o)
	f.mu.Unlock()
	rate := 0.8
	if f.WinRate != nil {
		rate = f.WinRate(o)
	}
	out := make([]RawRow, 0, o.Count)
	for i := 0; i < o.Count; i++ {
		if f.Delay > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(f.Delay):
			}
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		out = append(out, FakeRow(o.Battle, o.Bot, o.SeedFrom+i, rate))
		if o.Progress != nil {
			o.Progress(i+1, o.Count)
		}
	}
	return out, nil
}

func (f *FakeSimulator) Replay(ctx context.Context, o ReplayOptions) (json.RawMessage, error) {
	rep := oj.Obj("battle", o.Battle, "bot", o.Bot, "seed", o.Seed, "result", "win", "rounds", 1, "frames", []any{})
	return json.RawMessage(oj.Dump(rep, oj.Compact)), nil
}

// FakeRow 生成一行和真实 runs.jsonl 同样字段的假结果。
func FakeRow(battle, bot string, seed int, winRate float64) RawRow {
	h := fnv.New64a()
	fmt.Fprintf(h, "%s/%s", battle, bot)
	z := h.Sum64() + uint64(seed+1)*0x9e3779b97f4a7c15 // splitmix64：相邻种子也要互不相关
	z = (z ^ z>>30) * 0xbf58476d1ce4e5b9
	z = (z ^ z>>27) * 0x94d049bb133111eb
	rng := NewPCG64(z ^ z>>31)
	u := func() float64 { return float64(rng.Uint64()>>11) / (1 << 53) }
	win := u() < winRate
	result := "win"
	if !win {
		result = []string{"loss_hero", "loss_wipe", "timeout"}[rng.Below(3)]
	}
	rounds := 5 + int(rng.Below(6))
	hp := 0.0
	if win {
		hp = roundTo(0.2+0.6*u(), 4)
	}
	fall, throw := int(rng.Below(3)), int(rng.Below(2))
	x, y := int(rng.Below(8)), int(rng.Below(8))
	cell := fmt.Sprintf("%d,%d", x, y)
	dealt := 20 + int(rng.Below(40))
	row := oj.Obj(
		"battle", battle, "bot", bot,
		"counts", oj.Obj("broken", 0, "fall_enemy", fall, "throw", throw, "knockback", fall, "mark", 1),
		"dmg_cells", oj.Obj(cell, dealt),
		"dmg_to_enemy", oj.Obj("spear", dealt, "fall", 3*fall),
		"dmg_to_player", oj.Obj("bite", 7),
		"falls", []any{},
		"kills", []any{oj.Obj("by", "hero", "def", "wolf", "pos", []any{x, y}, "round", 1, "source", "spear")},
		"ms", 1, "party_hp_left", hp, "result", result, "rounds", rounds, "seed", seed,
		"units", oj.Obj(
			"hero", oj.Obj("alive", win, "dealt", dealt, "def", "hero", "hp", 10, "max_hp", 40, "taken", 7, "team", "player"),
			"wolf_1", oj.Obj("alive", !win, "dealt", 7, "def", "wolf", "hp", 0, "max_hp", 16, "taken", dealt, "team", "enemy")),
		"win", win)
	if fall > 0 {
		row.Set("falls", []any{oj.Obj("def", "wolf", "from", []any{x, y}, "levels", 1, "round", 2, "to", []any{x, y})})
	}
	return RawRow(oj.Dump(row, oj.Compact))
}
