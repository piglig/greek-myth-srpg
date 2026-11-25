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
	register("supports", "逐关对比带不同的支援英雄胜率差多少（[章号 | 关卡] -n/--runs --seed --kit --bot；默认用难度表的主要验收格）", balSupports)
}

func balSupports(args []string) error {
	a, err := balParse(args, []string{"runs", "seed", "kit", "bot"}, nil)
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
	market, err := data.Market()
	if err != nil {
		return err
	}
	opts := sim.SupportOptions{Runs: runs, Seed: seed, Workers: workers, KitsPath: p.Kits(), Kit: a.str("kit", ""), Bot: a.str("bot", "")}
	if len(a.pos) == 1 && strings.Contains(a.pos[0], "-") {
		opts.Battle = a.pos[0]
	} else if len(a.pos) == 1 {
		fmt.Sscanf(a.pos[0], "%d", &opts.Chapter)
	} else if len(a.pos) > 1 {
		return fmt.Errorf("最多给一个章号（2）或一关（2-3）；不给就是全部")
	}
	fmt.Printf("支援对比（每格 %d 局）。* 是出战配置里这一关带的那一位；括号里是每场召了几次。\n", runs)
	battle := ""
	opts.OnCell = func(c sim.SupportCell, _, _ int) {
		if c.Battle != battle {
			battle = c.Battle
			kind := spec.KindOf(c.Battle)
			kit, bot := spec.PrimaryOf(c.Battle)
			if opts.Kit != "" {
				kit = opts.Kit
			}
			if opts.Bot != "" {
				bot = opts.Bot
			}
			band := spec.Bands[kind][kit][bot]
			fmt.Printf("\n%-5s %s·%s 目标 %.0f%%–%.0f%%\n", c.Battle, kitNames[kit], botNames[bot], band[0]*100, band[1]*100)
		}
		name, mark := "不带", " "
		if r := market.Recruits[c.Support]; r != nil {
			name = r.Name
		}
		if c.Usual {
			mark = "*"
		}
		fmt.Printf("  %s %-6s %3.0f%%  %.1f 回合", mark, name, c.Win*100, c.Rounds)
		if c.Support != "none" {
			fmt.Printf("（召 %.1f 次）", c.Calls)
		}
		fmt.Println()
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	_, err = sim.CompareSupports(ctx, data, spec, opts)
	return err
}
