package sim

import (
	"context"
	"fmt"
	"runtime"
	"sync"

	"srpg/bots"
	"srpg/rules"
)

// Options 描述一批模拟。第 i 场用种子 SeedFrom + i，所以把种子区间拆开跑结果也一样。
type Options struct {
	Battle   string // 战斗 id，例如 "1-4"
	Bot      string // 机器人："novice" | "skilled"
	SeedFrom int
	Count    int
	DataDir  string // 可选的覆盖数据目录（里面的 <表>.json 优先于默认表）
	Workers  int    // 并行的 goroutine 数；<= 0 表示用全部 CPU
	// Progress 在每场战斗打完后被调用（同一时刻只会有一个调用）。可以为 nil。
	Progress func(done, total int)

	TablesDir string              // 数据表根目录；留空自动寻找 prototype/data/tables
	Sets      []string            // 可选的数值改写："<表>:<点分键路径>=<json 值>"
	Picks     map[string][]string // 技能树加点；nil 表示用表里的默认加点
	MaxRounds int                 // 回合上限；<= 0 表示 DefaultMaxRounds
	// Kit 不为空时按这一档出战配置开局（见 kits.go）；KitsPath 是配置文件的位置。
	Kit      string
	KitsPath string
}

// LoadData 按选项读入数据表。
func (o *Options) LoadData() (*rules.Data, error) {
	return rules.LoadData(rules.DataOptions{Root: o.TablesDir, Overlay: o.DataDir, Sets: o.Sets})
}

// Run 并行地模拟 Count 场战斗，返回按种子顺序排好的记录。
// 每场战斗的结果只取决于战斗、机器人、种子和数据，与 Workers 无关。
func Run(ctx context.Context, opts Options) ([]Row, error) {
	data, err := opts.LoadData()
	if err != nil {
		return nil, err
	}
	return RunWith(ctx, data, opts)
}

// RunWith 与 Run 相同，但使用已经读好的数据表（忽略选项里的 DataDir / TablesDir / Sets）。
func RunWith(ctx context.Context, data *rules.Data, opts Options) ([]Row, error) {
	prof, err := bots.ProfileByName(opts.Bot)
	if err != nil {
		return nil, err
	}
	if _, err := data.Battle(opts.Battle); err != nil {
		return nil, err
	}
	if opts.Count < 0 {
		return nil, fmt.Errorf("场数不能为负: %d", opts.Count)
	}
	picks := opts.Picks
	if picks == nil {
		picks = data.DefaultPicks()
	}
	var muster *rules.Muster
	if opts.Kit != "" {
		kits, err := LoadKits(opts.KitsPath)
		if err != nil {
			return nil, err
		}
		if muster, err = kits.Muster(data, opts.Kit, opts.Battle); err != nil {
			return nil, err
		}
	}
	workers := opts.Workers
	if workers <= 0 {
		workers = runtime.NumCPU()
	}
	workers = min(workers, max(opts.Count, 1))

	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	rows := make([]Row, opts.Count)
	jobs := make(chan int)
	var (
		wg       sync.WaitGroup
		mu       sync.Mutex
		done     int
		firstErr error
	)
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			runner := &Runner{Muster: muster, Kit: opts.Kit}
			for i := range jobs {
				row, err := runOne(runner, data, opts.Battle, picks, prof, opts.SeedFrom+i, opts.MaxRounds)
				mu.Lock()
				if err != nil {
					if firstErr == nil {
						firstErr = err
						cancel()
					}
				} else {
					rows[i] = *row
					done++
					if opts.Progress != nil {
						opts.Progress(done, opts.Count)
					}
				}
				mu.Unlock()
			}
		}()
	}
feed:
	for i := 0; i < opts.Count; i++ {
		select {
		case jobs <- i:
		case <-ctx.Done():
			break feed
		}
	}
	close(jobs)
	wg.Wait()
	if firstErr != nil {
		return nil, firstErr
	}
	if err := ctx.Err(); err != nil && done < opts.Count {
		return nil, err
	}
	return rows, nil
}

// 一场战斗里的 panic 不该拖垮整批：转成带种子的错误。
func runOne(runner *Runner, data *rules.Data, battle string, picks map[string][]string, prof bots.Profile,
	seed, maxRounds int) (row *Row, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("战斗 %s 种子 %d 出错: %v", battle, seed, r)
		}
	}()
	return runner.RunBattle(data, battle, picks, prof, seed, maxRounds, nil)
}
