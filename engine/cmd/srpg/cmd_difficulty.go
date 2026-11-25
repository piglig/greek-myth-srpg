package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"

	"srpg/rules"
	"srpg/sim"
)

func init() {
	register("difficulty", "按 balance/difficulty.yaml 把一章的每一关跑一遍，逐格判定难度（[章号 | 关卡] -n/--runs --seed；有主要验收格不达标时退出码 1）", balDifficulty)
}

// difficultySpec 是 balance/difficulty.yaml。
type difficultySpec struct {
	Runs    int      `yaml:"runs"`
	Primary []string `yaml:"primary"`
	// PrimaryFor 让个别关卡换一格做主要验收（只有某类玩家才会遇到的关）。
	PrimaryFor map[string][]string                         `yaml:"primary_for"`
	Kinds      map[string][]string                         `yaml:"kinds"`
	Bands      map[string]map[string]map[string][2]float64 `yaml:"bands"`
}

func (s *difficultySpec) kindOf(battle string) string {
	for kind, ids := range s.Kinds {
		for _, id := range ids {
			if id == battle {
				return kind
			}
		}
	}
	return "normal"
}

var kindNames = map[string]string{"teaching": "教学", "intro": "引入", "normal": "普通", "boss": "首领", "side": "支线", "late_side": "支线"}
var kitNames = map[string]string{"frugal": "节俭", "typical": "一般", "rich": "富裕"}
var botNames = map[string]string{"novice": "新手", "casual": "普通", "skilled": "熟练"}

func balDifficulty(args []string) error {
	a, err := balParse(args, []string{"runs", "seed"}, nil)
	if err != nil {
		return err
	}
	p, err := a.paths()
	if err != nil {
		return err
	}
	raw, err := os.ReadFile(filepath.Join(p.Balance, "difficulty.yaml"))
	if err != nil {
		return err
	}
	var spec difficultySpec
	if err := yaml.Unmarshal(raw, &spec); err != nil {
		return fmt.Errorf("difficulty.yaml: %w", err)
	}
	runs, err1 := a.num("runs", spec.Runs)
	seed, err2 := a.num("seed", 0)
	workers, err3 := a.num("workers", 0)
	for _, e := range []error{err1, err2, err3} {
		if e != nil {
			return e
		}
	}
	if runs <= 0 {
		runs = 200
	}
	data, err := rules.LoadData(rules.DataOptions{Root: p.Tables})
	if err != nil {
		return err
	}
	order, err := sim.CampaignOrder(data)
	if err != nil {
		return err
	}
	chapter, only := 0, ""
	if len(a.pos) == 1 && strings.Contains(a.pos[0], "-") {
		only = a.pos[0]
	} else if len(a.pos) == 1 {
		fmt.Sscanf(a.pos[0], "%d", &chapter)
	} else if len(a.pos) > 1 {
		return fmt.Errorf("最多给一个章号（2）或一关（2-3）；不给就是全部")
	}

	// 表头：按配置、再按水平排好的每一格。
	type cell struct{ kit, bot string }
	seen := map[cell]bool{}
	var cells []cell
	for _, kits := range spec.Bands {
		for kit, bots := range kits {
			for bot := range bots {
				if !seen[cell{kit, bot}] {
					seen[cell{kit, bot}] = true
					cells = append(cells, cell{kit, bot})
				}
			}
		}
	}
	rank := map[string]int{"typical": 0, "frugal": 1, "rich": 2, "casual": 0, "novice": 1, "skilled": 2}
	sort.Slice(cells, func(i, j int) bool {
		if cells[i].kit != cells[j].kit {
			return rank[cells[i].kit] < rank[cells[j].kit]
		}
		return rank[cells[i].bot] < rank[cells[j].bot]
	})
	primary := cell{"typical", "casual"}
	if len(spec.Primary) == 2 {
		primary = cell{spec.Primary[0], spec.Primary[1]}
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	fmt.Printf("难度判定（每格 %d 局）。每格：胜率 判定；主要验收格另附 平均回合 / 剩余生命。\n", runs)
	fmt.Printf("%-6s %-4s", "关", "类")
	for _, c := range cells {
		label := kitNames[c.kit] + "·" + botNames[c.bot]
		if c == primary {
			label += "*"
		}
		fmt.Printf("  %-22s", label)
	}
	fmt.Println()
	off, total := 0, 0
	var notes []string
	for _, battle := range order {
		if (chapter > 0 && rules.Chapter(battle) != chapter) || (only != "" && battle != only) {
			continue
		}
		kind := spec.kindOf(battle)
		primary := primary
		if own := spec.PrimaryFor[battle]; len(own) == 2 {
			primary = cell{own[0], own[1]}
		}
		fmt.Printf("%-6s %-4s", battle, kindNames[kind])
		for _, c := range cells {
			band, ok := spec.Bands[kind][c.kit][c.bot]
			if !ok {
				fmt.Printf("  %-22s", "—")
				continue
			}
			rows, err := sim.RunWith(ctx, data, sim.Options{Battle: battle, Bot: c.bot, SeedFrom: seed, Count: runs,
				Workers: workers, Kit: c.kit, KitsPath: p.Kits()})
			if err != nil {
				return fmt.Errorf("%s %s·%s: %w", battle, c.kit, c.bot, err)
			}
			wins, rounds, hp := 0, 0, 0.0
			for i := range rows {
				if rows[i].Win {
					wins++
				}
				rounds += rows[i].Rounds
				hp += float64(rows[i].PartyHPLeft)
			}
			rate := float64(wins) / float64(len(rows))
			verdict := "达标"
			switch {
			case rate > band[1]+1e-9:
				verdict = "偏易"
			case rate < band[0]-1e-9:
				verdict = "偏难"
			}
			text := fmt.Sprintf("%3.0f%% %s [%.0f–%.0f]", rate*100, verdict, band[0]*100, band[1]*100)
			if c == primary {
				text += fmt.Sprintf(" %.1f回 %.0f%%", float64(rounds)/float64(len(rows)), hp/float64(len(rows))*100)
				total++
				if verdict != "达标" {
					off++
					notes = append(notes, fmt.Sprintf("%s（%s关）%s：%.0f%%，目标 %.0f%%–%.0f%%", battle, kindNames[kind], verdict, rate*100, band[0]*100, band[1]*100))
				}
			}
			fmt.Printf("  %-22s", text)
		}
		fmt.Println()
	}
	fmt.Printf("\n主要验收格（%s·%s）：%d 关里 %d 关达标。\n", kitNames[primary.kit], botNames[primary.bot], total, total-off) // 个别关卡另有指定，见 primary_for
	if len(notes) > 0 {
		fmt.Println("不达标的：\n  " + strings.Join(notes, "\n  "))
		return fmt.Errorf("有 %d 关的主要验收格不达标", off)
	}
	return nil
}
