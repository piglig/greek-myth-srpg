package sim

import (
	"context"
	"fmt"
	"os"
	"sort"

	"gopkg.in/yaml.v3"

	"srpg/rules"
)

// 难度判定：按 balance/difficulty.yaml 把每一关在每种"配置 × 水平"下跑一遍，对着目标区间说
// 达标、偏易还是偏难。命令行（srpg difficulty）和平衡工坊用的是这里的同一份逻辑。

// Difficulty 是 balance/difficulty.yaml。
type Difficulty struct {
	Runs    int      `yaml:"runs" json:"runs"`
	Primary []string `yaml:"primary" json:"primary"`
	// PrimaryFor 让个别关卡换一格做主要验收（只有某类玩家才会遇到的关）。
	PrimaryFor map[string][]string                         `yaml:"primary_for" json:"primary_for"`
	Kinds      map[string][]string                         `yaml:"kinds" json:"kinds"`
	Bands      map[string]map[string]map[string][2]float64 `yaml:"bands" json:"bands"`
}

// LoadDifficulty 读入难度目标。
func LoadDifficulty(path string) (*Difficulty, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var spec Difficulty
	if err := yaml.Unmarshal(raw, &spec); err != nil {
		return nil, fmt.Errorf("difficulty.yaml: %w", err)
	}
	if spec.Runs <= 0 {
		spec.Runs = 200
	}
	return &spec, nil
}

// KindOf 是这一关的类型；没有列出来的都是 normal。
func (d *Difficulty) KindOf(battle string) string {
	for kind, ids := range d.Kinds {
		for _, id := range ids {
			if id == battle {
				return kind
			}
		}
	}
	return "normal"
}

// PrimaryOf 是这一关主要验收的那一格（配置、水平）。
func (d *Difficulty) PrimaryOf(battle string) (kit, bot string) {
	kit, bot = "typical", "casual"
	if len(d.Primary) == 2 {
		kit, bot = d.Primary[0], d.Primary[1]
	}
	if own := d.PrimaryFor[battle]; len(own) == 2 {
		kit, bot = own[0], own[1]
	}
	return
}

// Columns 是目标表里出现过的每一格，按配置、再按水平排好。
func (d *Difficulty) Columns() [][2]string {
	seen := map[[2]string]bool{}
	var cols [][2]string
	for _, kits := range d.Bands {
		for kit, bots := range kits {
			for bot := range bots {
				if c := [2]string{kit, bot}; !seen[c] {
					seen[c] = true
					cols = append(cols, c)
				}
			}
		}
	}
	rank := map[string]int{"typical": 0, "frugal": 1, "rich": 2, "casual": 0, "novice": 1, "skilled": 2}
	sort.Slice(cols, func(i, j int) bool {
		if cols[i][0] != cols[j][0] {
			return rank[cols[i][0]] < rank[cols[j][0]]
		}
		return rank[cols[i][1]] < rank[cols[j][1]]
	})
	return cols
}

// DifficultyCell 是一关在一格里的结果。
type DifficultyCell struct {
	Battle  string  `json:"battle"`
	Kind    string  `json:"kind"`
	Kit     string  `json:"kit"`
	Bot     string  `json:"bot"`
	Primary bool    `json:"primary"`
	Lo      float64 `json:"lo"`
	Hi      float64 `json:"hi"`
	Runs    int     `json:"runs"`
	Win     float64 `json:"win"`
	Rounds  float64 `json:"rounds"`   // 平均回合
	HPLeft  float64 `json:"hp_left"`  // 平均剩余生命（输的局算 0）
	Verdict string  `json:"verdict"`  // ok | easy | hard
	Timeout float64 `json:"timeouts"` // 打到回合上限的比例
}

// JudgeOptions 是一次判定的范围。
type JudgeOptions struct {
	Chapter  int    // > 0 时只跑这一章
	Battle   string // 不为空时只跑这一关
	Runs     int    // <= 0 用目标表里的局数
	Seed     int
	Workers  int
	KitsPath string
	// OnCell 在每一格跑完后被调用；done / total 是格数。可以为 nil。
	OnCell func(cell DifficultyCell, done, total int)
}

// Judge 按目标表逐关逐格模拟并判定。返回的格子按战役顺序、再按 Columns 的顺序排。
func Judge(ctx context.Context, data *rules.Data, spec *Difficulty, o JudgeOptions) ([]DifficultyCell, error) {
	order, err := CampaignOrder(data)
	if err != nil {
		return nil, err
	}
	runs := o.Runs
	if runs <= 0 {
		runs = spec.Runs
	}
	type slot struct {
		battle, kind, kit, bot string
		band                   [2]float64
	}
	var todo []slot
	for _, battle := range order {
		if (o.Chapter > 0 && rules.Chapter(battle) != o.Chapter) || (o.Battle != "" && battle != o.Battle) {
			continue
		}
		kind := spec.KindOf(battle)
		for _, c := range spec.Columns() {
			if band, ok := spec.Bands[kind][c[0]][c[1]]; ok {
				todo = append(todo, slot{battle, kind, c[0], c[1], band})
			}
		}
	}
	out := make([]DifficultyCell, 0, len(todo))
	for i, t := range todo {
		if err := ctx.Err(); err != nil {
			return out, err
		}
		rows, err := RunWith(ctx, data, Options{Battle: t.battle, Bot: t.bot, SeedFrom: o.Seed, Count: runs,
			Workers: o.Workers, Kit: t.kit, KitsPath: o.KitsPath})
		if err != nil {
			return out, fmt.Errorf("%s %s·%s: %w", t.battle, t.kit, t.bot, err)
		}
		if len(rows) == 0 {
			return out, ctx.Err()
		}
		pk, pb := spec.PrimaryOf(t.battle)
		cell := DifficultyCell{Battle: t.battle, Kind: t.kind, Kit: t.kit, Bot: t.bot, Lo: t.band[0], Hi: t.band[1],
			Runs: len(rows), Primary: t.kit == pk && t.bot == pb, Verdict: "ok"}
		n := float64(len(rows))
		for j := range rows {
			if rows[j].Win {
				cell.Win++
			}
			if rows[j].Result == "timeout" {
				cell.Timeout++
			}
			cell.Rounds += float64(rows[j].Rounds)
			cell.HPLeft += float64(rows[j].PartyHPLeft)
		}
		cell.Win, cell.Timeout, cell.Rounds, cell.HPLeft = cell.Win/n, cell.Timeout/n, cell.Rounds/n, cell.HPLeft/n
		switch {
		case cell.Win > cell.Hi+1e-9:
			cell.Verdict = "easy"
		case cell.Win < cell.Lo-1e-9:
			cell.Verdict = "hard"
		}
		out = append(out, cell)
		if o.OnCell != nil {
			o.OnCell(cell, i+1, len(todo))
		}
	}
	return out, nil
}
