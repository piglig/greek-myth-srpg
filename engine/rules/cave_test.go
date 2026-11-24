package rules

import (
	"slices"
	"testing"
)

// 首领巢穴规则（09-chapter-1 的 1-5）：扑击、咆哮、巨石、退回洞穴和冲出。

// 12x8 的平地加一个洞穴：入口在西 (1,3) 和东 (9,3)，各有一块巨石。
func lair() *BattleState {
	s := flat(12, 8)
	s.Cave = &Cave{Boss: "lion", TriggerHP: 30, EmergeActions: 1,
		Entrances: []Entrance{{ID: "west", Anchor: c(1, 3)}, {ID: "east", Anchor: c(9, 3)}},
		Boulders:  []Boulder{{ID: "bw", Pos: c(0, 6), Seals: "west"}, {ID: "be", Pos: c(11, 6), Seals: "east"}}}
	return s
}

func enemyTurn(t *testing.T, s *BattleState) []Event {
	return aiTurn(t, s, TeamEnemy, false)
}

func TestPounceMustLandNextToItsTarget(t *testing.T) {
	s := flat(12, 8)
	ally(s, "hero", "hero", c(8, 3), West)
	foe(s, "lion", "lion", c(1, 3), East)
	StartBattle(s)
	EndPhase(s)
	eq(t, Validate(s, LeapSkill("lion", "pounce", c(8, 3), c(5, 3))),
		"out of range", "landing at columns 5-6 leaves the hero at 8 two tiles away")
	eq(t, Validate(s, LeapSkill("lion", "pounce", c(8, 3), c(7, 3))), "bad landing", "more than 4 tiles")
}

func TestPounceAdjacentTargetTakesDamageAndIsPushed(t *testing.T) {
	s := flat(12, 8)
	ally(s, "hero", "hero", c(7, 3), West)
	foe(s, "lion", "lion", c(1, 3), East)
	StartBattle(s)
	EndPhase(s)
	o := Perform(s, LeapSkill("lion", "pounce", c(7, 3), c(5, 3)))
	check(t, o.OK, o.Error)
	eq(t, sumDamage(o.Events, "pounce"), 6, "floor(16 x 0.8) - 6")
	eq(t, s.Unit("hero").Pos, c(8, 3), "knocked back one tile")
	eq(t, s.Unit("lion").Cooldown("pounce"), 2, "cooldown")
	eq(t, Validate(s, LeapSkill("lion", "pounce", c(8, 3), c(11, 3))), "already acted", "one action per activation")
}

func TestRoarHurlsBackPlayersInTwoTilesOnly(t *testing.T) {
	s := flat(12, 8)
	ally(s, "hero", "hero", c(5, 3))
	ally(s, "atalanta", "ata", c(9, 3))
	foe(s, "lion", "lion", c(2, 3))
	StartBattle(s)
	EndPhase(s)
	o := Perform(s, UseSkill("lion", "roar", c(2, 3)))
	check(t, o.OK, o.Error)
	eq(t, s.Unit("hero").Pos, c(6, 3), "hero (2 tiles from the 2x2 lion) is hurled back a tile")
	eq(t, s.Unit("ata").Pos, c(9, 3), "atalanta is out of range")
	check(t, len(s.Unit("hero").Statuses) == 0, "and the roar leaves no status on anyone")
}

func TestBoulderBlocksAndSeals(t *testing.T) {
	s := lair()
	ally(s, "hero", "hero", c(1, 6))
	ally(s, "heracles", "her", c(10, 6))
	foe(s, "lion", "lion", c(5, 1))
	StartBattle(s)
	check(t, !Reachable(s, s.Unit("hero"), -1).CanStop(c(0, 6)), "a boulder cannot be walked onto")
	eq(t, Validate(s, PushBoulder("hero", c(5, 5))), "no boulder there", "empty cell")
	o := Perform(s, PushBoulder("hero", c(0, 6)))
	check(t, o.OK, o.Error)
	check(t, !s.Cave.Entrance("west").Sealed, "an ordinary unit needs two pushes")
	EndPhase(s)
	Perform(s, Wait("lion"))
	EndPhase(s)
	o = Perform(s, PushBoulder("hero", c(0, 6)))
	check(t, hasEvent(o.Events, EvSealed), "second push seals the west entrance")
	check(t, slices.Equal(s.OpenEntrances(), []string{"east"}), "one entrance left")
	check(t, len(Reachable(s, s.Unit("her"), -1).Dests()) > 0, "movement still works")
	eq(t, Validate(s, PushBoulder("her", c(11, 6))), "cannot seal the last entrance", "the lair always keeps one way out")
}

func TestStrongUnitSealsInOnePush(t *testing.T) {
	s := lair()
	ally(s, "hero", "hero", c(5, 6))
	ally(s, "heracles", "her", c(10, 6))
	foe(s, "lion", "lion", c(5, 1))
	StartBattle(s)
	o := Perform(s, PushBoulder("her", c(11, 6)))
	check(t, hasEvent(o.Events, EvSealed), "Heracles rolls it home at once")
	check(t, s.BoulderAt(c(11, 6)) == "", "the boulder left its cell")
}

func TestWoundedLionRetreatsThenBurstsOutNearTheSoftestPlayer(t *testing.T) {
	s := lair()
	ally(s, "hero", "hero", c(2, 6))
	ally(s, "atalanta", "ata", c(9, 6))
	lion := foe(s, "lion", "lion", c(5, 0))
	lion.HP = 30
	StartBattle(s)
	EndPhase(s)
	ev := enemyTurn(t, s)
	check(t, hasEvent(ev, EvRetreat), "at half health it goes to ground")
	check(t, lion.Hidden, "hidden")
	EndPhase(s)
	eq(t, Validate(s, UseSkill("hero", "spear", c(5, 0))), "no enemy there", "a hidden boss cannot be targeted")
	check(t, s.UnitAt(c(5, 0)) == nil, "and blocks nothing")
	eq(t, CaveEntrance(s, lion), "east", "intent: the entrance nearest Atalanta (lowest defence)")
	EndPhase(s)
	ev = enemyTurn(t, s)
	check(t, hasEvent(ev, EvEmerge), "bursts out next enemy phase")
	check(t, !lion.Hidden, "visible again")
	for _, e := range ev {
		if e.Type == EvEmerge {
			eq(t, e.To, c(9, 3), "at the east entrance")
		}
	}
	check(t, hasEvent(ev, EvAttack) || hasEvent(ev, EvLeap), "and attacks in the same phase")
	EndPhase(s)
	EndPhase(s)
	ev = enemyTurn(t, s)
	check(t, hasEvent(ev, EvRetreat), "having been out for a player phase, it goes back in")
}

func TestSealedEntranceForcesTheOtherOne(t *testing.T) {
	s := lair()
	ally(s, "hero", "hero", c(2, 6))
	ally(s, "atalanta", "ata", c(9, 6))
	lion := foe(s, "lion", "lion", c(5, 0))
	s.Cave.Entrance("east").Sealed = true
	lion.Hidden = true
	eq(t, CaveEntrance(s, lion), "west", "only the west entrance is open")
}

func TestHeldLionCannotRetreatAndBreaksFreeWithOneAction(t *testing.T) {
	s := lair()
	ally(s, "heracles", "her", c(4, 2))
	ally(s, "hero", "hero", c(2, 6))
	lion := foe(s, "lion", "lion", c(5, 2))
	lion.HP = 20
	StartBattle(s)
	check(t, Perform(s, Grapple("her", c(5, 2))).OK, "grapple")
	eq(t, lion.Escape, 3, "reference Heracles holds the lion at the boss cap")
	EndPhase(s)
	ev := enemyTurn(t, s)
	check(t, !hasEvent(ev, EvRetreat), "a held lion cannot slip back into the cave")
	check(t, hasEvent(ev, EvStruggle), "it struggles instead")
	eq(t, lion.GrappledByID, "", "two boss struggles (2 points each) break a hold of 3")
	check(t, !lion.Hidden, "still outside")
}
