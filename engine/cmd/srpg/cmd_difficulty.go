package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strings"

	"srpg/rules"
	"srpg/sim"
)

func init() {
	register("difficulty", "按 balance/difficulty.yaml 逐关逐格判定难度（[章号 | 关卡] -n/--runs --seed；有主要验收格不达标时退出码 1）", balDifficulty)
}

var kindNames = map[string]string{"teaching": "教学", "intro": "引入", "normal": "普通", "boss": "首领", "side": "支线", "late_side": "支线"}
var kitNames = map[string]string{"frugal": "节俭", "typical": "一般", "rich": "富裕"}
var botNames = map[string]string{"novice": "新手", "casual": "普通", "skilled": "熟练"}
var verdictNames = map[string]string{"ok": "达标", "easy": "偏易", "hard": "偏难"}

func balDifficulty(args []string) error {
	a, err := balParse(args, []string{"runs", "seed"}, nil)
	if err != nil {
		return err
	}
	p, err := a.paths()
	if err != nil {
		return err
	}
	spec, err := sim.LoadDifficulty(filepath.Join(p.Balance, "difficulty.yaml"))
	if err != nil {
		return err
	}
	runs, err1 := a.num("runs", spec.Runs)
	seed, err2 := a.num("seed", 0)
	workers, err3 := a.num("workers", 0)
	for _, e := range []error{err1, err2, err3} {
		if e != nil {
			return e
		}
	}
	data, err := rules.LoadData(rules.DataOptions{Root: p.Tables})
	if err != nil {
		return err
	}
	opts := sim.JudgeOptions{Runs: runs, Seed: seed, Workers: workers, KitsPath: p.Kits()}
	if len(a.pos) == 1 && strings.Contains(a.pos[0], "-") {
		opts.Battle = a.pos[0]
	} else if len(a.pos) == 1 {
		fmt.Sscanf(a.pos[0], "%d", &opts.Chapter)
	} else if len(a.pos) > 1 {
		return fmt.Errorf("最多给一个章号（2）或一关（2-3）；不给就是全部")
	}

	cols := spec.Columns()
	fmt.Printf("难度判定（每格 %d 局）。每格：胜率 判定；主要验收格另附 平均回合 / 剩余生命。\n", runs)
	fmt.Printf("%-6s %-4s", "关", "类")
	for _, c := range cols {
		label := kitNames[c[0]] + "·" + botNames[c[1]]
		if len(spec.Primary) == 2 && c[0] == spec.Primary[0] && c[1] == spec.Primary[1] {
			label += "*"
		}
		fmt.Printf("  %-22s", label)
	}
	// 一格一格地出：每跑完一格就把它和它前面空着的格子打出来。
	col, battle := 0, ""
	off, total := 0, 0
	var notes []string
	opts.OnCell = func(c sim.DifficultyCell, _, _ int) {
		if c.Battle != battle {
			battle, col = c.Battle, 0
			fmt.Printf("\n%-6s %-4s", c.Battle, kindNames[c.Kind])
		}
		for ; col < len(cols) && (cols[col][0] != c.Kit || cols[col][1] != c.Bot); col++ {
			fmt.Printf("  %-22s", "—")
		}
		col++
		text := fmt.Sprintf("%3.0f%% %s [%.0f–%.0f]", c.Win*100, verdictNames[c.Verdict], c.Lo*100, c.Hi*100)
		if c.Primary {
			text += fmt.Sprintf(" %.1f回 %.0f%%", c.Rounds, c.HPLeft*100)
			total++
			if c.Verdict != "ok" {
				off++
				notes = append(notes, fmt.Sprintf("%s（%s关）%s：%.0f%%，目标 %.0f%%–%.0f%%", c.Battle, kindNames[c.Kind],
					verdictNames[c.Verdict], c.Win*100, c.Lo*100, c.Hi*100))
			}
		}
		fmt.Printf("  %-22s", text)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	if _, err := sim.Judge(ctx, data, spec, opts); err != nil {
		fmt.Println()
		return err
	}
	fmt.Printf("\n\n主要验收格（标 * 的一列；个别关卡另有指定）：%d 关里 %d 关达标。\n", total, total-off)
	if len(notes) > 0 {
		fmt.Println("不达标的：\n  " + strings.Join(notes, "\n  "))
		return fmt.Errorf("有 %d 关的主要验收格不达标", off)
	}
	return nil
}
