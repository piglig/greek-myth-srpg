extends RefCounted
## Snapshot each exchange at resolution time. The journal must survive later HP and round changes.

const NAMES := {"rescued":"安全撤离","assist":"援护","move":"移动","undo_move":"撤销移动","leap":"跃进","arrival":"增援",
	"knockback":"击退","fall":"坠落","dodge":"闪避","shield":"护盾","ko":"倒下","stagger":"破势累积",
	"broken":"破势","choke":"窒息","status":"状态变化","status_end":"状态结束","resist":"抵抗",
	"grapple_start":"擒抱","grapple_end":"解除擒抱","slam":"摔投","mark":"标记","face":"转向",
	"intercept":"截击","retreat":"撤退","emerge":"入场","sealed":"封锁入口","push":"推石",
	"struggle":"挣扎","reinforce":"加固","escape_tick":"挣脱","collision":"撞击","edge":"坠出边缘","stun_skip":"跳过行动"}
const CONSEQUENCES := ["damage","ko","knockback","fall","dodge","shield","stagger","broken","resist","status","edge","collision"]

static func participant(state: BattleState,id: String) -> Dictionary:
	var u := state.unit(id)
	if u == null:
		return {}
	var caption := u.display_name
	if u.id.begins_with(u.def_id+"_") and u.id.get_slice("_",1).is_valid_int():
		caption += " "+u.id.get_slice("_",1)
	return {"id":id,"name":caption,"kind":u.def_id,"max_hp":u.max_hp}


static func collect(state: BattleState, events: Array, from_round := -1) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var round_number := state.round_number if from_round < 0 else from_round
	var area := {}
	for event: Dictionary in events:
		var kind: String = event["type"]
		if kind in ["arrival","stun_skip"]:
			round_number = state.round_number
		var source: String = event.get("source","")
		var target: String = event.get("target",event.get("protected",""))
		var actor: String = event.get("unit",event.get("grappler",""))
		var row: Dictionary = rows.back() if not rows.is_empty() else {}
		if kind == "area":
			area = event
		elif kind not in ["resist","status","status_end"]:
			area = {}
		var attach: bool = kind in CONSEQUENCES and not target.is_empty() and row.get("target_id","") == target
		if kind == "damage" and source != row.get("cause",""):
			attach = false
		if not attach:
			var cause: String = event.get("skill",source if kind == "damage" else kind)
			var title: String = NAMES.get(kind,EventText.SOURCE_NAMES.get(cause,EventText.skill_name(cause)))
			if kind == "attack" or kind == "area":
				title = EventText.skill_name(cause)
			if not area.is_empty() and kind != "area":
				actor = area.unit
				cause = area.skill
				title = EventText.skill_name(cause)
			row = {"linked":kind == "assist" or (not area.is_empty() and kind != "area"),"actor":participant(state,actor),"target":participant(state,target),"target_id":target,
				"title":title,"cause":cause,"round":round_number,"details":[],"outcome":"","direction":"","before":-1,"after":-1}
			rows.append(row)
		var line := EventText._line(state,event).strip_edges()
		if kind == "move":
			line = "移动 %d 格" % _steps(event)
		if kind == "undo_move":
			line = "返回移动前的位置"
		if not line.is_empty():
			row.details.append(line)
		match kind:
			"damage":
				if row.before < 0:
					row.before = maxi(0,event.hp+event.amount)
				row.after = maxi(0,event.hp)
				row.outcome = "−%d 生命" % (row.before-row.after)
			"ko": row.outcome = ("−%d · 倒下" % (row.before-row.after)) if row.after >= 0 else "倒下"
			"knockback": row.outcome += " 击退"
			"move","leap": row.outcome = "%s %d 格" % ["跃出" if kind == "leap" else "移动",_steps(event)]
			"undo_move": row.outcome = "退回原位"
			"attack","assist": row.direction = EventText.RELATION_NAMES[event.relation]
			"resist": row.outcome = "抵抗"
			"dodge": row.outcome = "闪避"
			"shield": row.outcome = "吸收 %d" % event.absorbed
			"status","status_end":
				if row.after < 0:
					row.outcome = EventText.STATUS_NAMES.get(event.status,event.status)
	return rows


## How far a move went, in cells. A player reads the path on the field, not coordinates.
static func _steps(event: Dictionary) -> int:
	if event.has("path") and event.path is Array and event.path.size() > 1: return event.path.size()-1
	var from: Vector2i = event.from
	var to: Vector2i = event.to
	return absi(to.x-from.x)+absi(to.y-from.y)
