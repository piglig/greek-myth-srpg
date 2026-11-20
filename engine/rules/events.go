package rules

// EventType 是规则事件的种类。名字（String）与原版事件字典的 "type" 相同。
type EventType uint8

const (
	EvNone EventType = iota
	EvDodge
	EvShield
	EvDamage
	EvKO
	EvResist
	EvStatus
	EvStagger
	EvBroken
	EvCollision
	EvKnockback
	EvFall
	EvEdge
	EvGrappleStart
	EvGrappleEnd
	EvReinforce
	EvStruggle
	EvFace
	EvMark
	EvMove
	EvUndoMove
	EvArea
	EvLeap
	EvAttack
	EvPush
	EvSealed
	EvRetreat
	EvEmerge
	EvIntercept
	EvSlam
	EvAssist
	EvStunSkip
	EvChoke
	EvEscapeTick
	EvStatusEnd
)

var eventNames = [...]string{
	EvNone: "", EvDodge: "dodge", EvShield: "shield", EvDamage: "damage", EvKO: "ko", EvResist: "resist",
	EvStatus: "status", EvStagger: "stagger", EvBroken: "broken", EvCollision: "collision",
	EvKnockback: "knockback", EvFall: "fall", EvEdge: "edge", EvGrappleStart: "grapple_start",
	EvGrappleEnd: "grapple_end", EvReinforce: "reinforce", EvStruggle: "struggle", EvFace: "face",
	EvMark: "mark", EvMove: "move", EvUndoMove: "undo_move", EvArea: "area", EvLeap: "leap",
	EvAttack: "attack", EvPush: "push", EvSealed: "sealed", EvRetreat: "retreat", EvEmerge: "emerge",
	EvIntercept: "intercept", EvSlam: "slam", EvAssist: "assist", EvStunSkip: "stun_skip",
	EvChoke: "choke", EvEscapeTick: "escape_tick", EvStatusEnd: "status_end",
}

func (t EventType) String() string { return eventNames[t] }

// Notes 是一次命中里生效的修正，按位记录；位的顺序就是原版 notes 数组的顺序。
type Notes uint16

const (
	NoteBlock Notes = 1 << iota
	NoteHighGround
	NoteCover
	NoteMarked
	NoteFlanked
	NotePatience
	NoteIronArm
	NoteShieldWall
	NoteGuard
	NoteBroken
	NoteGrappled
	NotePhysicalImmune
)

var noteNames = [...]string{"block", "high_ground", "cover", "marked", "flanked", "patience",
	"iron_arm", "shield_wall", "guard", "broken", "grappled", "physical_immune"}

// Names 按原版顺序列出修正名。
func (n Notes) Names() []string {
	var out []string
	for i, name := range noteNames {
		if n&(1<<i) != 0 {
			out = append(out, name)
		}
	}
	return out
}

func (n Notes) Has(o Notes) bool { return n&o != 0 }

// Event 是规则执行时产生的一条事件。各种事件用到的字段：
//
//	damage: Target Amount DmgType Source HP      shield: Target Absorbed      dodge: Target Source
//	ko / broken / edge: Target                   status: Target Status Rounds
//	resist: Target Status Why                    status_end: Target Status
//	stagger: Target Amount Total                 collision: Target With（单位 id 或 "wall"）
//	knockback: Target From To                    fall: Target Levels
//	grapple_start: Grappler Target Escape        grapple_end: Grappler Target Why
//	choke: Grappler Target Amount                escape_tick: Target Escape
//	reinforce / struggle: Unit Escape            face: Unit Facing
//	mark / slam: Unit Target                     move: Unit From To Path
//	undo_move / leap: Unit From To               area: Unit Skill
//	attack: Unit Target Skill Relation Notes     assist: Unit Target Relation
//	push: Unit Boulder Progress                  sealed: Entrance Boulder
//	retreat / stun_skip: Unit                    emerge: Unit Entrance To
//	intercept: Unit Protected
type Event struct {
	Type                              EventType
	Unit, Target, Grappler, Protected string
	Source, Skill, Status, Why, With  string
	Entrance, Boulder                 string
	Amount, HP, Levels, Total, Escape int
	Rounds, Absorbed, Progress        int
	DmgType                           DamageType
	Relation                          Relation
	Notes                             Notes
	From, To, Facing                  Cell
	Path                              []Cell
}

// emit 追加一条事件；ev 为 nil 表示不记录（机器人搜索时用，省掉事件的开销）。
func emit(ev *[]Event, e Event) {
	if ev != nil {
		*ev = append(*ev, e)
	}
}
