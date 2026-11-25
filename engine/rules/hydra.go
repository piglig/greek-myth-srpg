package rules

// RegrowRounds 是断颈长回一个头要经过的回合结算次数。
const RegrowRounds = 2

// 许德拉的头：每个头是一个不会移动的敌人（特性 anchored），倒下后原地留一截断颈
// （特性 regrows）。断颈过 RegrowRounds 次回合结算就长回一个满血的头，除非这期间被火
// 烧到：带火的招式打中断颈，或者头是带着灼烧倒下的，就永远封住。全部封住才算打完。

// StumpAt 返回这一格上还会再生的断颈；没有就是 nil。
func (s *BattleState) StumpAt(c Cell) *UnitState {
	for _, u := range s.Units {
		if !u.Alive && u.Traits.Regrows && !u.Sealed && u.Regrow > 0 && u.Pos == c {
			return u
		}
	}
	return nil
}

// StumpsPending 表示还有没封住的断颈：敌人倒光了也不算赢。
func (s *BattleState) StumpsPending() bool {
	for _, u := range s.Units {
		if !u.Alive && u.Traits.Regrows && !u.Sealed && u.Regrow > 0 {
			return true
		}
	}
	return false
}

// MostRegrown 是再生次数最多的那个头长回来过几次（可选目标用）。
func (s *BattleState) MostRegrown() int {
	most := 0
	for _, u := range s.Units {
		most = max(most, u.Regrown)
	}
	return most
}

// behead 在一个会再生的单位倒下时调用：带着灼烧倒下的当场封住，否则留下断颈开始倒数。
func behead(s *BattleState, u *UnitState, ev *[]Event) {
	if !u.Traits.Regrows {
		return
	}
	if u.HasStatus("burning") {
		cauterize(u, ev)
		return
	}
	u.Regrow = RegrowRounds
}

// cauterize 把一截断颈烧封。
func cauterize(u *UnitState, ev *[]Event) {
	u.Sealed = true
	u.Regrow = 0
	emit(ev, Event{Type: EvCauterize, Target: u.ID})
}

// settleStumps 在回合结算时让每截断颈倒数一次；数到头就长回来。那一格上站着人就再等一回合。
func settleStumps(s *BattleState, ev *[]Event) {
	for _, u := range s.Units {
		if u.Alive || !u.Traits.Regrows || u.Sealed || u.Regrow <= 0 {
			continue
		}
		u.Regrow--
		if u.Regrow > 0 {
			continue
		}
		if s.UnitAt(u.Pos) != nil {
			u.Regrow = 1
			continue
		}
		u.Alive = true
		u.HP = u.MaxHP
		u.Statuses = u.Statuses[:0]
		u.Stagger = 0
		u.Regrown++
		emit(ev, Event{Type: EvRegrow, Target: u.ID})
	}
}
