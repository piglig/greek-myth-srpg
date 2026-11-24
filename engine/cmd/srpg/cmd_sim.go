package main

// 战斗模拟相关的子命令：simulate（批量模拟）、replay（回放）、bench（测速）、
// profile-battle（一场战斗的耗时去向）、export-metrics（伤害矩阵）。

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"runtime/pprof"
	"time"

	"srpg/bots"
	"srpg/rules"
	"srpg/sim"
)

func init() {
	register("simulate", "批量模拟战斗，每场写一行 JSON（-battle -bot -runs -seed -out -workers -data-dir）", cmdSimulate)
	register("replay", "重放一场带种子的战斗，写出逐步回放 JSON（-battle -bot -seed -out）", cmdReplay)
	register("bench", "测模拟速度：单线程和全部线程各跑一遍（-battle -bot -runs）", cmdBench)
	register("profile-battle", "打一场战斗，看时间花在哪：我方搜索 / 敌方 AI / 阶段切换（-battle -bot -seed）", cmdProfileBattle)
	register("export-metrics", "导出静态伤害矩阵 JSON（-out）", cmdExportMetrics)
}

// 多次出现的 -set 参数。
type setFlags []string

func (s *setFlags) String() string     { return fmt.Sprint(*s) }
func (s *setFlags) Set(v string) error { *s = append(*s, v); return nil }

// 各子命令共用的数据来源参数。
type dataFlags struct {
	dataDir, tables string
	sets            setFlags
}

func (d *dataFlags) register(fs *flag.FlagSet) {
	fs.StringVar(&d.dataDir, "data-dir", "", "覆盖数据目录：里面的 <表>.json 优先于默认数据表")
	fs.StringVar(&d.tables, "tables", "", "数据表根目录（默认自动寻找 prototype/data/tables，或用环境变量 SRPG_TABLES）")
	fs.Var(&d.sets, "set", "数值改写，可多次给出：<表>:<点分键路径>=<json 值>，例如 units:heracles.str=16")
}

func (d *dataFlags) load() (*rules.Data, error) {
	return rules.LoadData(rules.DataOptions{Root: d.tables, Overlay: d.dataDir, Sets: d.sets})
}

func parsePicks(text string) (map[string][]string, error) {
	if text == "" {
		return nil, nil
	}
	var picks map[string][]string
	if err := json.Unmarshal([]byte(text), &picks); err != nil {
		return nil, fmt.Errorf("-picks 不是合法的 JSON（应为 {\"hero\": [...], ...}）: %w", err)
	}
	return picks, nil
}

func writeFile(path string, data []byte) error {
	if dir := filepath.Dir(path); dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	return os.WriteFile(path, data, 0o644)
}

func cmdSimulate(args []string) error {
	fs := flag.NewFlagSet("simulate", flag.ContinueOnError)
	battle := fs.String("battle", "1-4", "战斗 id")
	bot := fs.String("bot", "skilled", "机器人：novice | skilled")
	runs := fs.Int("runs", 10, "场数；第 i 场用种子 seed+i")
	seed := fs.Int("seed", 0, "起始种子")
	out := fs.String("out", "", "输出的 JSONL 文件（留空写到标准输出）")
	workers := fs.Int("workers", 0, "并行数（默认全部 CPU）")
	picksJSON := fs.String("picks", "", "技能树加点 JSON，例如 {\"hero\":[\"iron_arm\"]}；默认用表里的默认加点")
	maxRounds := fs.Int("max-rounds", sim.DefaultMaxRounds, "回合上限，超过判 timeout")
	trace := fs.Bool("trace", false, "打印可读的事件日志（单线程；用来看机器人某个种子到底做了什么）")
	quiet := fs.Bool("quiet", false, "不打印每场的结果")
	var df dataFlags
	df.register(fs)
	if err := fs.Parse(args); err != nil {
		return err
	}
	picks, err := parsePicks(*picksJSON)
	if err != nil {
		return err
	}
	data, err := df.load()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	t0 := time.Now()
	var rows []sim.Row
	if *trace {
		prof, err := bots.ProfileByName(*bot)
		if err != nil {
			return err
		}
		if picks == nil {
			picks = data.DefaultPicks()
		}
		hook := func(s *rules.BattleState, events []rules.Event, _ string) {
			for _, line := range rules.Describe(s, events) {
				fmt.Fprintf(os.Stderr, "    [R%d] %s\n", s.Round, line)
			}
		}
		for i := 0; i < *runs; i++ {
			row, err := sim.RunBattle(data, *battle, picks, prof, *seed+i, *maxRounds, hook)
			if err != nil {
				return err
			}
			fmt.Fprintf(os.Stderr, "run %d/%d seed %d: %s in %d rounds (%d ms)\n", i+1, *runs, row.Seed, row.Result, row.Rounds, row.MS)
			rows = append(rows, *row)
		}
	} else {
		rows, err = sim.RunWith(ctx, data, sim.Options{Battle: *battle, Bot: *bot, SeedFrom: *seed, Count: *runs,
			Workers: *workers, Picks: picks, MaxRounds: *maxRounds})
		if err != nil {
			return err
		}
	}

	w := bufio.NewWriter(os.Stdout)
	if *out != "" {
		if dir := filepath.Dir(*out); dir != "." {
			if err := os.MkdirAll(dir, 0o755); err != nil {
				return err
			}
		}
		f, err := os.Create(*out)
		if err != nil {
			return err
		}
		defer f.Close()
		w = bufio.NewWriter(f)
	}
	wins := 0
	for i := range rows {
		line, err := rows[i].JSON()
		if err != nil {
			return err
		}
		w.Write(line)
		w.WriteByte('\n')
		if rows[i].Win {
			wins++
		}
		if !*quiet && !*trace {
			fmt.Fprintf(os.Stderr, "run %d/%d seed %d: %s in %d rounds (%d ms)\n", i+1, len(rows), rows[i].Seed,
				rows[i].Result, rows[i].Rounds, rows[i].MS)
		}
	}
	if err := w.Flush(); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "%s %s：%d 场，胜 %d 场，用时 %.2f 秒\n", *battle, *bot, len(rows), wins, time.Since(t0).Seconds())
	return nil
}

func cmdReplay(args []string) error {
	fs := flag.NewFlagSet("replay", flag.ContinueOnError)
	battle := fs.String("battle", "1-4", "战斗 id")
	bot := fs.String("bot", "skilled", "机器人：novice | skilled")
	seed := fs.Int("seed", 0, "种子")
	out := fs.String("out", "", "输出的 JSON 文件（留空写到标准输出）")
	maxRounds := fs.Int("max-rounds", sim.DefaultMaxRounds, "回合上限")
	var df dataFlags
	df.register(fs)
	if err := fs.Parse(args); err != nil {
		return err
	}
	rep, err := sim.ReplayWith(sim.ReplayOptions{Battle: *battle, Bot: *bot, Seed: *seed, DataDir: df.dataDir,
		TablesDir: df.tables, Sets: df.sets, MaxRounds: *maxRounds})
	if err != nil {
		return err
	}
	text, err := rep.JSON()
	if err != nil {
		return err
	}
	if *out == "" {
		_, err = os.Stdout.Write(append(text, '\n'))
		return err
	}
	if err := writeFile(*out, text); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "回放已写入 %s：%d 帧，%s，%d 回合\n", *out, len(rep.Frames), rep.Result, rep.Rounds)
	return nil
}

func cmdBench(args []string) error {
	fs := flag.NewFlagSet("bench", flag.ContinueOnError)
	battle := fs.String("battle", "1-4", "战斗 id")
	bot := fs.String("bot", "skilled", "机器人：novice | skilled")
	runs := fs.Int("runs", 400, "场数")
	seed := fs.Int("seed", 0, "起始种子")
	workers := fs.Int("workers", 0, "多线程那一遍的并行数（默认全部 CPU）")
	cpuProfile := fs.String("cpuprofile", "", "把单线程那一遍的 CPU profile 写到这个文件")
	var df dataFlags
	df.register(fs)
	if err := fs.Parse(args); err != nil {
		return err
	}
	data, err := df.load()
	if err != nil {
		return err
	}
	if *workers <= 0 {
		*workers = runtime.NumCPU()
	}
	run := func(w int) (time.Duration, int, error) {
		t0 := time.Now()
		rows, err := sim.RunWith(context.Background(), data, sim.Options{Battle: *battle, Bot: *bot,
			SeedFrom: *seed, Count: *runs, Workers: w})
		wins := 0
		for i := range rows {
			if rows[i].Win {
				wins++
			}
		}
		return time.Since(t0), wins, err
	}
	if *cpuProfile != "" {
		f, err := os.Create(*cpuProfile)
		if err != nil {
			return err
		}
		defer f.Close()
		if err := pprof.StartCPUProfile(f); err != nil {
			return err
		}
	}
	single, wins, err := run(1)
	pprof.StopCPUProfile()
	if err != nil {
		return err
	}
	fmt.Printf("%s %s，%d 场（种子 %d 起），胜 %d 场\n", *battle, *bot, *runs, *seed, wins)
	fmt.Printf("  1 线程：%8.2f 秒  每场 %7.2f 毫秒\n", single.Seconds(), single.Seconds()*1000/float64(*runs))
	if *workers > 1 {
		multi, _, err := run(*workers)
		if err != nil {
			return err
		}
		fmt.Printf("%3d 线程：%8.2f 秒  每场 %7.2f 毫秒（加速 %.1f 倍）\n", *workers, multi.Seconds(),
			multi.Seconds()*1000/float64(*runs), single.Seconds()/multi.Seconds())
	}
	return nil
}

func cmdExportMetrics(args []string) error {
	fs := flag.NewFlagSet("export-metrics", flag.ContinueOnError)
	out := fs.String("out", "", "输出的 JSON 文件（留空写到标准输出）")
	var df dataFlags
	df.register(fs)
	if err := fs.Parse(args); err != nil {
		return err
	}
	data, err := df.load()
	if err != nil {
		return err
	}
	m, err := sim.ExportMetrics(data)
	if err != nil {
		return err
	}
	text, err := m.JSON()
	if err != nil {
		return err
	}
	if *out == "" {
		_, err = os.Stdout.Write(append(text, '\n'))
		return err
	}
	if err := writeFile(*out, text); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "已导出 %d 条命中到 %s\n", len(m.Hits), *out)
	return nil
}

func cmdProfileBattle(args []string) error {
	fs := flag.NewFlagSet("profile-battle", flag.ContinueOnError)
	battle := fs.String("battle", "1-4", "战斗 id")
	bot := fs.String("bot", "skilled", "机器人：novice | skilled")
	seed := fs.Int("seed", 0, "种子")
	var df dataFlags
	df.register(fs)
	if err := fs.Parse(args); err != nil {
		return err
	}
	data, err := df.load()
	if err != nil {
		return err
	}
	p, err := sim.ProfileBattle(data, *battle, *bot, *seed)
	if err != nil {
		return err
	}
	ms := func(d time.Duration) float64 { return float64(d.Microseconds()) / 1000 }
	turns := float64(max(p.Turns, 1))
	fmt.Printf("%s %s 种子 %d：%s，%d 个我方回合\n", p.Battle, p.Bot, p.Seed, p.Result, p.Turns)
	fmt.Printf("我方搜索 %8.2f 毫秒（每回合 %.2f）\n", ms(p.Player), ms(p.Player)/turns)
	fmt.Printf("敌方 AI  %8.2f 毫秒（每回合 %.2f）\n", ms(p.Enemy), ms(p.Enemy)/turns)
	fmt.Printf("阶段切换 %8.2f 毫秒\n", ms(p.Phases))
	fmt.Printf("  评估方案的调用 %d 次，其中命中缓存 %d 次；生成方案 %d 个，实际执行 %d 个\n",
		p.Stats.ScoredCalls, p.Stats.MemoHits, p.Stats.Plans, p.Stats.Applied)
	return nil
}
