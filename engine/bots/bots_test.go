package bots

import (
	"reflect"
	"testing"

	"srpg/rules"
)

var testData = func() *rules.Data {
	d, err := rules.LoadData(rules.DataOptions{})
	if err != nil {
		panic(err)
	}
	return d
}()

func build(t *testing.T, id string) *rules.BattleState {
	t.Helper()
	s, err := testData.Build(id, nil)
	if err != nil {
		t.Fatal(err)
	}
	rules.StartBattle(s)
	return s
}

func profile(t *testing.T, name string) Profile {
	t.Helper()
	p, err := ProfileByName(name)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func TestProfiles(t *testing.T) {
	novice, skilled := profile(t, "novice"), profile(t, "skilled")
	if novice.Search != "greedy" || novice.Weights.Danger != 2 || novice.UseMark || novice.UseGrapple {
		t.Errorf("novice profile: %+v", novice)
	}
	if skilled.Search != "beam" || skilled.Beam != 6 || skilled.PerUnit != 8 || skilled.Weights != DefaultWeights() {
		t.Errorf("skilled profile: %+v", skilled)
	}
	if _, err := ProfileByName("nobody"); err == nil {
		t.Error("unknown profile must be an error")
	}
	for _, name := range ProfileNames() {
		profile(t, name)
	}
}

// 新手不标记也不擒抱；熟手两样都会考虑。
func TestPlansRespectTheProfile(t *testing.T) {
	count := func(name string) (marks, grapples, pushes, total int) {
		s := build(t, "1-5")
		// 把狮子挪到英雄旁边、阿塔兰忒的射程内
		s.Unit("lion").Pos = rules.Cell{X: 6, Y: 9}
		b := New(profile(t, name))
		for _, id := range []string{"hero", "atalanta", "heracles"} {
			for _, p := range b.Plans(s, s.Unit(id)) {
				total++
				if p.HasMark {
					marks++
				}
				switch p.Main.Type {
				case rules.ActGrapple:
					grapples++
				case rules.ActPushBoulder:
					pushes++
				}
			}
		}
		return
	}
	marks, grapples, _, total := count("novice")
	if marks != 0 || grapples != 0 || total == 0 {
		t.Errorf("novice: %d marks, %d grapples, %d plans", marks, grapples, total)
	}
	marks, grapples, _, _ = count("skilled")
	if marks == 0 || grapples == 0 {
		t.Errorf("skilled: %d marks, %d grapples", marks, grapples)
	}
}

// 生成候选方案时会临时挪动单位；结束后局面必须原样。
func TestPlansAndScoringLeaveTheStateUntouched(t *testing.T) {
	s := build(t, "1-4")
	before := string(s.AppendSignature(nil))
	b := New(profile(t, "skilled"))
	b.Eval.BeginTurn()
	for _, u := range s.Living(rules.TeamPlayer) {
		sc := b.scoredPlans(s, u)
		if len(sc) == 0 {
			t.Fatalf("%s has no plans", u.ID)
		}
		for i := 1; i < len(sc); i++ {
			if sc[i].score > sc[i-1].score {
				t.Fatalf("%s: plans not sorted best first", u.ID)
			}
		}
		for i := 0; i < min(len(sc), b.Prof.PerUnit); i++ {
			if sc[i].state == nil {
				t.Fatalf("%s: top plan %d has no resulting state", u.ID, i)
			}
		}
	}
	if string(s.AppendSignature(nil)) != before {
		t.Error("scoring plans changed the state")
	}
}

func TestPlayTurnIsDeterministicPerSeed(t *testing.T) {
	for _, name := range ProfileNames() {
		play := func(seed int64) ([]Step, string) {
			s := build(t, "1-4")
			steps := New(profile(t, name)).PlayTurn(s, rules.NewRNG(seed))
			return steps, string(s.AppendSignature(nil))
		}
		a, sigA := play(11)
		b, sigB := play(11)
		if !reflect.DeepEqual(a, b) || sigA != sigB {
			t.Errorf("%s: same seed must play the same turn", name)
		}
		if len(a) != 3 {
			t.Errorf("%s: every unit acts once, got %d steps", name, len(a))
		}
		s := build(t, "1-4")
		New(profile(t, name)).PlayTurn(s, rules.NewRNG(11))
		for _, u := range s.Living(rules.TeamPlayer) {
			if !u.HasActed {
				t.Errorf("%s: %s did not act", name, u.ID)
			}
		}
	}
}

// 评估：打伤敌人加分，自己人倒下扣分；位置分只在有敌人时才有。
func TestEvaluatorTerms(t *testing.T) {
	s := build(t, "1-4")
	ev := NewEvaluator(DefaultWeights())
	ev.BeginTurn()
	base := ev.Material(s)
	wolf := s.Unit("wolf_1")
	wolf.HP -= 8
	hurt := ev.Material(s)
	if hurt <= base {
		t.Errorf("hurting an enemy must raise material: %v -> %v", base, hurt)
	}
	wolf.HP, wolf.Alive = 0, false
	if ko := ev.Material(s); ko <= hurt {
		t.Errorf("a knock-out must raise material: %v -> %v", hurt, ko)
	}
	s.Unit("atalanta").Alive = false
	lost := ev.Material(s)
	s.Unit("hero").Alive = false
	if heroLost := ev.Material(s); !(heroLost < lost-50) {
		t.Errorf("losing the hero must cost far more: %v -> %v", lost, heroLost)
	}
	if ev.Score(s) != ev.Material(s)+ev.Positional(s) {
		t.Error("score = material + positional")
	}
	for _, u := range s.Units {
		if u.Team == rules.TeamEnemy {
			u.Alive = false
		}
	}
	if p := ev.Positional(s); p != 0 {
		t.Errorf("no enemies, no positional term: %v", p)
	}
}

// 站进敌人的威胁范围会增加危险度。
func TestDangerGrowsInsideThreatRange(t *testing.T) {
	s := build(t, "1-4")
	b := New(profile(t, "skilled"))
	b.Eval.BeginTurn()
	hero := s.Unit("hero")
	far := b.Eval.danger(s, []*rules.UnitState{hero}, s.Living(rules.TeamEnemy))
	wolf := s.Unit("wolf_4")
	wolf.Pos = rules.Cell{X: 5, Y: 10}
	near := b.Eval.danger(s, []*rules.UnitState{hero}, s.Living(rules.TeamEnemy))
	if !(near > far) {
		t.Errorf("danger next to a wolf (%v) must exceed danger far away (%v)", near, far)
	}
}

func TestSoftmaxPickFollowsTheWeights(t *testing.T) {
	sc := []scored{{score: 10}, {score: 9}, {score: -50}}
	rng := rules.NewRNG(5)
	counts := make([]int, len(sc))
	for i := 0; i < 2000; i++ {
		counts[softmaxPick(sc, 3.0, rng)]++
	}
	if !(counts[0] > counts[1] && counts[1] > 0 && counts[2] == 0) {
		t.Errorf("unexpected sampling: %v", counts)
	}
	for i := 0; i < 50; i++ {
		if softmaxPick(sc, 0, rng) != 0 {
			t.Fatal("zero temperature must always pick the best plan")
		}
	}
}
