package sim

import (
	"context"
	"fmt"
	"sort"

	"srpg/rules"
)

// 支援对比：同一关、同一种玩家，换着带每一位雇得到的英雄（和不带），看胜率差多少。
// 难度是按出战配置里写的那一位调的；这张表回答"换一位会怎样"和"哪位在哪一关最好用"。

// SupportCell 是一关带一位英雄的结果。
type SupportCell struct {
	Battle  string  `json:"battle"`
	Support string  `json:"support"` // 英雄的名字；"none" 是不带
	Usual   bool    `json:"usual"`   // 出战配置里这一关带的就是他
	Runs    int     `json:"runs"`
	Win     float64 `json:"win"`
	Rounds  float64 `json:"rounds"`
	Calls   float64 `json:"calls"` // 每场召了几次
}

// SupportOptions 是一次对比的范围。
type SupportOptions struct {
	Chapter  int
	Battle   string
	Kit, Bot string // 留空用难度表的主要验收格
	Runs     int
	Seed     int
	Workers  int
	KitsPath string
	OnCell   func(cell SupportCell, done, total int)
}

// startingSteps 是一位刚雇来的英雄学得起的节点：他有主角一半的经验，按技能树的顺序学到
// 花满 budget 点为止。对比时每位英雄都按这个算，免得"学了几步"成了差别的来源。
func startingSteps(data *rules.Data, who string, budget int) []string {
	var picks []string
	for _, br := range data.Trees(who) {
		for _, n := range br.Nodes {
			if n.Cost > budget {
				return picks
			}
			budget -= n.Cost
			picks = append(picks, n.ID)
		}
	}
	return picks
}

// CompareSupports 逐关把每位来得了的英雄各带一遍。只算有英雄可雇的章节。
func CompareSupports(ctx context.Context, data *rules.Data, spec *Difficulty, o SupportOptions) ([]SupportCell, error) {
	order, err := CampaignOrder(data)
	if err != nil {
		return nil, err
	}
	market, err := data.Market()
	if err != nil {
		return nil, err
	}
	kits, err := LoadKits(o.KitsPath)
	if err != nil {
		return nil, err
	}
	runs := o.Runs
	if runs <= 0 {
		runs = spec.Runs
	}
	var heroes []string
	for id := range market.Recruits {
		heroes = append(heroes, id)
	}
	sort.Slice(heroes, func(i, j int) bool {
		a, b := market.Recruits[heroes[i]], market.Recruits[heroes[j]]
		if a.Opens != b.Opens {
			return a.Opens < b.Opens
		}
		return a.Fee < b.Fee
	})
	type slot struct {
		battle, kit, bot, support string
		usual                     bool
	}
	var todo []slot
	for _, battle := range order {
		chapter := rules.Chapter(battle)
		if (o.Chapter > 0 && chapter != o.Chapter) || (o.Battle != "" && battle != o.Battle) {
			continue
		}
		kit, bot := spec.PrimaryOf(battle)
		if o.Kit != "" {
			kit = o.Kit
		}
		if o.Bot != "" {
			bot = o.Bot
		}
		usual := "none"
		if m, err := kits.Muster(data, kit, battle); err != nil {
			return nil, err
		} else if m.Support != "" {
			usual = m.Support
		}
		var open []string
		for _, h := range heroes {
			if market.Recruits[h].Opens <= chapter {
				open = append(open, h)
			}
		}
		if len(open) == 0 {
			continue
		}
		todo = append(todo, slot{battle, kit, bot, "none", usual == "none"})
		for _, h := range open {
			todo = append(todo, slot{battle, kit, bot, h, usual == h})
		}
	}
	out := make([]SupportCell, 0, len(todo))
	for i, t := range todo {
		if err := ctx.Err(); err != nil {
			return out, err
		}
		rows, err := RunWith(ctx, data, Options{Battle: t.battle, Bot: t.bot, SeedFrom: o.Seed, Count: runs, Workers: o.Workers,
			Kit: t.kit, KitsPath: o.KitsPath, Support: t.support, SupportPicks: startingSteps(data, t.support, 3)})
		if err != nil {
			return out, fmt.Errorf("%s 带 %s: %w", t.battle, t.support, err)
		}
		if len(rows) == 0 {
			return out, ctx.Err()
		}
		cell := SupportCell{Battle: t.battle, Support: t.support, Usual: t.usual, Runs: len(rows)}
		n := float64(len(rows))
		for j := range rows {
			if rows[j].Win {
				cell.Win++
			}
			cell.Rounds += float64(rows[j].Rounds)
			cell.Calls += float64(rows[j].Counts["support"])
		}
		cell.Win, cell.Rounds, cell.Calls = cell.Win/n, cell.Rounds/n, cell.Calls/n
		out = append(out, cell)
		if o.OnCell != nil {
			o.OnCell(cell, i+1, len(todo))
		}
	}
	return out, nil
}
