package studio

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"srpg/balance"
	oj "srpg/balance/ordjson"
)

// 后台模拟任务：一次只跑一个，带实时进度和取消。

type job struct {
	id                    int
	battle, variant       string
	bots                  []string
	runs, seed            int
	actor, status, errMsg string
	done, total           int
	created               string
	startedAt             time.Time
	elapsed               float64
	hash                  string
	used                  *oj.Object
	cancel                context.CancelFunc
	ctx                   context.Context
}

// snapshot 是任务的 JSON 形状（调用方持有 Jobs.mu）。
func (j *job) snapshot() *oj.Object {
	o := oj.Obj("id", j.id, "battle", j.battle, "variant", j.variant, "bots", toAny(j.bots), "runs", j.runs,
		"seed", j.seed, "actor", j.actor, "status", j.status, "done", j.done, "total", j.total, "error", j.errMsg,
		"created", j.created)
	if j.startedAt.IsZero() {
		o.Set("started_at", nil).Set("elapsed", 0)
	} else {
		o.Set("started_at", float64(j.startedAt.UnixNano())/1e9).Set("elapsed", j.elapsed)
	}
	return o.Set("hash", j.hash).Set("used", j.used.Clone())
}

// Jobs 是任务队列。
type Jobs struct {
	ws      *Workspace
	runner  *balance.Runner
	publish func(kind string, payload any) // 推给已连接的浏览器

	mu      sync.Mutex
	jobs    map[int]*job
	nextID  int
	queue   []int
	running bool
	idle    chan struct{} // 队列跑空时关闭（测试用来等待）
}

// NewJobs 创建任务队列。
func NewJobs(ws *Workspace, runner *balance.Runner, publish func(kind string, payload any)) *Jobs {
	if publish == nil {
		publish = func(string, any) {}
	}
	return &Jobs{ws: ws, runner: runner, publish: publish, jobs: map[int]*job{}, nextID: 1}
}

// List 返回最近 20 个任务，新的在前。
func (s *Jobs) List() []any {
	s.mu.Lock()
	defer s.mu.Unlock()
	ids := make([]int, 0, len(s.jobs))
	for id := range s.jobs {
		ids = append(ids, id)
	}
	sort.Sort(sort.Reverse(sort.IntSlice(ids)))
	out := []any{}
	for _, id := range ids[:min(20, len(ids))] {
		out = append(out, s.jobs[id].snapshot())
	}
	return out
}

// Wait 等到队列里的任务全部结束。
func (s *Jobs) Wait() {
	s.mu.Lock()
	ch := s.idle
	running := s.running
	s.mu.Unlock()
	if running && ch != nil {
		<-ch
	}
}

// Start 排一个模拟任务：runs 是每个机器人的上限，目标都定论后会提前停。
func (s *Jobs) Start(battle, variant string, bots []string, runs, seed int, actor string) (*oj.Object, error) {
	data, err := s.ws.Load(variant)
	if err != nil {
		return nil, err
	}
	if !data.Battles.Has(battle) {
		return nil, userErr("没有这个关卡：%s", battle)
	}
	issues, err := s.ws.Validate(data)
	if err != nil {
		return nil, err
	}
	var errs []string
	for _, i := range issues {
		switch i.Str("where", "") {
		case "units", "skills", "skill_tree", "battles/" + battle:
			if i.Str("level", "") == "error" {
				errs = append(errs, i.Str("message", ""))
			}
		}
	}
	if len(errs) > 0 {
		return nil, userErr("先修正错误再模拟：%s", strings.Join(errs[:min(3, len(errs))], "；"))
	}
	valid := len(bots) > 0
	for _, b := range bots {
		valid = valid && Bots.Has(b)
	}
	if !valid {
		return nil, userErr("机器人无效：%s", oj.PyRepr(toAny(bots)))
	}
	if runs < 1 || runs > 5000 {
		return nil, userErr("局数必须在 1 到 5000 之间")
	}
	if variant == "" {
		variant = Baseline
	}
	ctx, cancel := context.WithCancel(context.Background())
	s.mu.Lock()
	j := &job{id: s.nextID, battle: battle, variant: variant, bots: bots, runs: runs, seed: seed, actor: actor,
		status: "queued", total: runs * len(bots), created: Now(), hash: s.ws.BattleHash(data, battle),
		used: oj.NewObject(), ctx: ctx, cancel: cancel}
	s.nextID++
	s.jobs[j.id] = j
	s.queue = append(s.queue, j.id)
	if !s.running {
		s.running = true
		s.idle = make(chan struct{})
		go s.loop()
	}
	snap := j.snapshot()
	s.mu.Unlock()
	labels := make([]string, len(bots))
	for i, b := range bots {
		labels[i] = botLabel(b)
	}
	s.ws.Log(actor, "sim", fmt.Sprintf("开始模拟 %s（%s，各最多 %d 局）", battle, strings.Join(labels, "、"), runs),
		"variant", variant, "battle", battle)
	s.publish("job", snap)
	return snap, nil
}

// Cancel 取消排队中或正在跑的任务。
func (s *Jobs) Cancel(id int, actor string) (*oj.Object, error) {
	s.mu.Lock()
	j := s.jobs[id]
	if j == nil {
		s.mu.Unlock()
		return nil, userErr("没有这个模拟任务")
	}
	if j.status == "queued" || j.status == "running" {
		j.status = "cancelled"
		for i, q := range s.queue {
			if q == id {
				s.queue = append(s.queue[:i], s.queue[i+1:]...)
				break
			}
		}
		j.cancel()
	}
	snap := j.snapshot()
	s.mu.Unlock()
	s.ws.Log(actor, "sim", "取消模拟 "+j.battle, "variant", j.variant, "battle", j.battle)
	s.publish("job", snap)
	return snap, nil
}

func (s *Jobs) loop() {
	for {
		s.mu.Lock()
		if len(s.queue) == 0 {
			s.running = false
			close(s.idle)
			s.mu.Unlock()
			return
		}
		j := s.jobs[s.queue[0]]
		s.queue = s.queue[1:]
		j.status = "running"
		j.startedAt = time.Now()
		s.mu.Unlock()
		s.run(j)
	}
}

func (s *Jobs) run(j *job) {
	var lastPush time.Time
	progress := func(n int) {
		s.mu.Lock()
		j.done += n
		j.elapsed = time.Since(j.startedAt).Seconds()
		var snap *oj.Object
		if time.Since(lastPush) > 400*time.Millisecond {
			lastPush = time.Now()
			snap = j.snapshot()
		}
		s.mu.Unlock()
		if snap != nil {
			s.publish("job", snap)
		}
	}
	cancelled := func() bool {
		s.mu.Lock()
		defer s.mu.Unlock()
		return j.status == "cancelled"
	}
	variant := j.variant
	if IsBaseline(variant) {
		variant = ""
	}
	used := map[string]int{}
	err := func() error {
		for _, bot := range j.bots {
			if cancelled() {
				break
			}
			dataDir, err := s.ws.OverlayDir(variant)
			if err != nil {
				return err
			}
			// runs 是上限：这个机器人的目标都定论后提前停
			u, err := s.runner.RunUntilDecided(j.ctx, balance.DecideRequest{Battle: j.battle, Bots: []string{bot},
				Variant: variant, DataDir: dataDir, MaxRuns: j.runs, Seed: j.seed, OnProgress: progress})
			if err != nil {
				return err
			}
			used[bot] = u[bot]
			s.mu.Lock()
			j.used.Set(bot, u[bot])
			s.mu.Unlock()
			if !cancelled() {
				if err := s.ws.WriteMeta(j.battle, variant, bot, oj.Obj("hash", j.hash, "runs", u[bot], "max_runs", j.runs,
					"seed", j.seed, "finished", Now(), "by", j.actor)); err != nil {
					return err
				}
			}
		}
		return nil
	}()
	switch {
	case cancelled():
	case err != nil:
		msg := []rune(err.Error())
		if len(msg) > 1500 {
			msg = msg[len(msg)-1500:]
		}
		s.mu.Lock()
		j.status, j.errMsg = "failed", string(msg)
		s.mu.Unlock()
		s.ws.Log(j.actor, "sim", fmt.Sprintf("模拟 %s 失败", j.battle), "variant", j.variant, "battle", j.battle)
	default:
		s.mu.Lock()
		j.status, j.done = "done", j.total
		s.mu.Unlock()
		s.ws.Log(j.actor, "sim", s.ws.headline(j.battle, j.variant, j.bots, used), "variant", j.variant, "battle", j.battle)
	}
	s.mu.Lock()
	j.elapsed = time.Since(j.startedAt).Seconds()
	snap := j.snapshot()
	s.mu.Unlock()
	s.publish("job", snap)
}
