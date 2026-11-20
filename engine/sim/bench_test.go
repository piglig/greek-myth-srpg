package sim

import (
	"testing"

	"srpg/bots"
)

func benchBattle(b *testing.B, battle, bot string) {
	prof, err := bots.ProfileByName(bot)
	if err != nil {
		b.Fatal(err)
	}
	picks := testData.DefaultPicks()
	b.ReportAllocs()
	runner := new(Runner)
	for i := 0; i < b.N; i++ {
		if _, err := runner.RunBattle(testData, battle, picks, prof, i, 30, nil); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkValleySkilled(b *testing.B) { benchBattle(b, "1-4", "skilled") }
func BenchmarkCaveSkilled(b *testing.B)   { benchBattle(b, "1-5", "skilled") }
func BenchmarkValleyNovice(b *testing.B)  { benchBattle(b, "1-4", "novice") }
