package sim

import (
	"bytes"
	"encoding/json"
	"testing"

	"srpg/bots"
	"srpg/rules"
)

// 模拟框架：可复现性和记录的完整性（11-balance-testing）。

var testData = func() *rules.Data {
	d, err := rules.LoadData(rules.DataOptions{})
	if err != nil {
		panic(err)
	}
	return d
}()

func run(t *testing.T, battle, bot string, seed int) *Row {
	t.Helper()
	prof, err := bots.ProfileByName(bot)
	if err != nil {
		t.Fatal(err)
	}
	row, err := RunBattle(testData, battle, nil, prof, seed, 30, nil)
	if err != nil {
		t.Fatal(err)
	}
	row.MS = 0
	return row
}

func rowJSON(t *testing.T, r *Row) []byte {
	t.Helper()
	b, err := r.JSON()
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestSameSeedSameBattle(t *testing.T) {
	a := rowJSON(t, run(t, "test", "novice", 42))
	b := rowJSON(t, run(t, "test", "novice", 42))
	if !bytes.Equal(a, b) {
		t.Error("identical records for the same seed")
	}
}

func TestDifferentSeedsCanDiffer(t *testing.T) {
	seen := map[string]bool{}
	for seed := 0; seed < 6; seed++ {
		units, _ := json.Marshal(run(t, "test", "novice", seed).Units)
		seen[string(units)] = true
	}
	if len(seen) <= 1 {
		t.Error("novice noise produces different battles")
	}
}

func TestRecordAccountsForAllEnemyDamage(t *testing.T) {
	r := run(t, "test", "novice", 7)
	bySource := 0
	for _, v := range r.DmgToEnemy {
		bySource += v
	}
	taken := 0
	for _, u := range r.Units {
		if u.Team == "enemy" {
			taken += u.Taken
		}
	}
	if bySource != taken {
		t.Errorf("damage by source equals damage taken by enemies: expected %d, got %d", taken, bySource)
	}
	switch r.Result {
	case "win", "loss_hero", "loss_wipe", "timeout":
	default:
		t.Errorf("valid result, got %q", r.Result)
	}
}

func TestBossFightReachesAnOutcome(t *testing.T) {
	r := run(t, "1-5", "novice", 3)
	if r.Result == "timeout" {
		t.Errorf("1-5 ends within 30 rounds (%s in %d)", r.Result, r.Rounds)
	}
}

// 记录读回来再写出去不变（平衡工具会读这些行）。
func TestRowRoundTrips(t *testing.T) {
	a := rowJSON(t, run(t, "1-5", "skilled", 5))
	var back Row
	if err := json.Unmarshal(a, &back); err != nil {
		t.Fatal(err)
	}
	if b := rowJSON(t, &back); !bytes.Equal(a, b) {
		t.Errorf("round trip changed the row\n%s\n%s", a, b)
	}
}

func TestReplayFramesFollowTheBattle(t *testing.T) {
	rep, err := Replay("1-5", "skilled", 2, "")
	if err != nil {
		t.Fatal(err)
	}
	row := run(t, "1-5", "skilled", 2)
	if rep.Result != row.Result || rep.Rounds != row.Rounds {
		t.Errorf("replay %s/%d, simulation %s/%d", rep.Result, rep.Rounds, row.Result, row.Rounds)
	}
	if len(rep.Frames) < 2 || len(rep.Frames[0].Lines) != 0 || rep.Frames[0].Round != 1 {
		t.Fatalf("frames[0] must be the starting position (%d frames)", len(rep.Frames))
	}
	for i, f := range rep.Frames[1:] {
		if len(f.Lines) == 0 || len(f.Units) != len(rep.Frames[0].Units) {
			t.Fatalf("frame %d is malformed", i+1)
		}
	}
	if rep.Frames[0].Cave.Entrances == nil {
		t.Error("1-5 has a cave")
	}
}
