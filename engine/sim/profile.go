package sim

import (
	"time"

	"srpg/bots"
	"srpg/rules"
)

// Profile 是一场模拟战斗的时间去向：我方搜索、敌方 AI、阶段切换，外加搜索计数。
type Profile struct {
	Battle, Bot string
	Seed        int
	Turns       int // 我方回合数
	Result      string
	Player      time.Duration // 我方机器人搜索
	Enemy       time.Duration // 敌方 AI
	Phases      time.Duration // 阶段切换和回合结算
	Stats       bots.Stats
}

// ProfileBattle 打一场战斗并统计各部分耗时（开发时看模拟慢在哪里）。
func ProfileBattle(data *rules.Data, battleID, botName string, seed int) (*Profile, error) {
	prof, err := bots.ProfileByName(botName)
	if err != nil {
		return nil, err
	}
	s, err := data.Build(battleID, data.DefaultPicks())
	if err != nil {
		return nil, err
	}
	rules.StartBattle(s)
	bot := bots.New(prof)
	rng := rules.NewRNG(int64(seed))
	p := &Profile{Battle: battleID, Bot: botName, Seed: seed}
	for s.Round <= DefaultMaxRounds {
		a := time.Now()
		bot.PlayTurn(s, rng)
		b := time.Now()
		p.Player += b.Sub(a)
		p.Turns++
		if p.Result = outcome(s); p.Result != "" {
			break
		}
		rules.EndPhase(s)
		c := time.Now()
		p.Phases += c.Sub(b)
		for _, e := range s.Living(rules.TeamEnemy) {
			for guard := 0; e.Alive && !e.HasActed && guard < 4; guard++ {
				plan := rules.PlanFor(s, e)
				if plan.HasMove {
					rules.Do(s, rules.Move(e.ID, plan.MoveTo), nil)
				}
				if rules.Do(s, plan.Action, nil) != "" {
					rules.Do(s, rules.Wait(e.ID), nil)
				}
				if !rules.FinishActivation(s, e) {
					break
				}
			}
		}
		d := time.Now()
		p.Enemy += d.Sub(c)
		if p.Result = outcome(s); p.Result != "" {
			break
		}
		rules.EndPhase(s)
		p.Phases += time.Since(d)
	}
	if p.Result == "" {
		p.Result = "timeout"
	}
	p.Stats = bot.Stats
	return p, nil
}
