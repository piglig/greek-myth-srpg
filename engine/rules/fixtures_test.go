package rules

import (
	"strings"
	"testing"
)

// 小型测试战斗的搭建工具。
//
// 规则测试不能依赖调参：这里造出来的单位用下面的参考数值（07–09 号文档里的算例），
// 不管 units.json 现在写的是什么。平衡数值由平衡工具另行检查。

var testData = func() *Data {
	d, err := LoadData(DataOptions{})
	if err != nil {
		panic(err)
	}
	return d
}()

var reference = map[string]struct{ hp, maxHP, str, def int }{
	"hero":          {40, 40, 12, 6},
	"atalanta":      {30, 30, 11, 3},
	"heracles":      {60, 80, 20, 9},
	"wolf":          {16, 16, 9, 1},
	"bandit":        {20, 20, 10, 3},
	"bandit_archer": {16, 16, 9, 2},
	"bandit_chief":  {30, 30, 12, 4},
	"boar":          {36, 36, 13, 8},
	"lion":          {60, 60, 16, 4},
}

func c(x, y int) Cell { return Cell{x, y} }

func mk(defID, id string, team Team, pos, facing Cell) *UnitState {
	u, err := testData.MakeUnit(defID, id, team, pos, facing)
	if err != nil {
		panic(err)
	}
	if ref, ok := reference[defID]; ok {
		u.HP, u.MaxHP, u.Strength, u.Defense = ref.hp, ref.maxHP, ref.str, ref.def
	}
	return u
}

func mkState(heightRows []string, terrainRows ...string) *BattleState {
	g, err := GridFromRows(heightRows, terrainRows)
	if err != nil {
		panic(err)
	}
	return NewBattleState(g)
}

func flat(w, d int) *BattleState {
	rows := make([]string, d)
	for i := range rows {
		rows[i] = strings.Repeat("0", w)
	}
	return mkState(rows)
}

func facingOr(def Cell, facing []Cell) Cell {
	if len(facing) > 0 {
		return facing[0]
	}
	return def
}

// 我方单位，默认朝东。
func ally(s *BattleState, defID, id string, pos Cell, facing ...Cell) *UnitState {
	return s.AddUnit(mk(defID, id, TeamPlayer, pos, facingOr(East, facing)))
}

// 敌方单位，默认朝西。
func foe(s *BattleState, defID, id string, pos Cell, facing ...Cell) *UnitState {
	return s.AddUnit(mk(defID, id, TeamEnemy, pos, facingOr(West, facing)))
}

func build(t *testing.T, id string) *BattleState {
	t.Helper()
	s, err := testData.Build(id, nil)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// 某个来源（"" 表示任意来源）的伤害事件总和。
func sumDamage(events []Event, source string) int {
	total := 0
	for _, e := range events {
		if e.Type == EvDamage && (source == "" || e.Source == source) {
			total += e.Amount
		}
	}
	return total
}

func hasEvent(events []Event, typ EventType) bool {
	for _, e := range events {
		if e.Type == typ {
			return true
		}
	}
	return false
}

func check(t *testing.T, cond bool, msg string) {
	t.Helper()
	if !cond {
		t.Error(msg)
	}
}

func checkf(t *testing.T, cond bool, format string, args ...any) {
	t.Helper()
	if !cond {
		t.Errorf(format, args...)
	}
}

func eq[T comparable](t *testing.T, actual, expected T, msg string) {
	t.Helper()
	if actual != expected {
		t.Errorf("%s: expected %v, got %v", msg, expected, actual)
	}
}

// 让一方的单位都按敌方 AI 行动一轮，返回产生的事件。
func aiTurn(t *testing.T, s *BattleState, team Team, strict bool) []Event {
	t.Helper()
	var events []Event
	for _, u := range s.Living(team) {
		for guard := 0; u.Alive && !u.HasActed && guard < 4; guard++ {
			p := PlanFor(s, u)
			if p.HasMove {
				mv := Perform(s, Move(u.ID, p.MoveTo))
				if strict {
					checkf(t, mv.OK, "%s move: %s", u.ID, mv.Error)
				}
				events = append(events, mv.Events...)
			}
			o := Perform(s, p.Action)
			if !o.OK {
				o = Perform(s, Wait(u.ID))
			}
			events = append(events, o.Events...)
			if !FinishActivation(s, u) {
				break
			}
		}
	}
	return events
}
