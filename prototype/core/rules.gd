class_name Rules
extends RefCounted
## 行动的校验、执行、预览和阶段流程——全部转交给 Go 引擎（engine/rules），这里只收发。
##
## 行动是字典：
##   {"type": "move", "unit": id, "to": Vector2i}
##   {"type": "undo_move", "unit": id}
##   {"type": "skill", "unit": id, "skill": skill_id, "target": Vector2i, "to": Vector2i（跳跃技能的落点）}
##   {"type": "slam" | "grapple" | "mark" | "push_boulder", "unit": id, "target": Vector2i}
##   {"type": "reinforce" | "struggle" | "release" | "wait", "unit": id}
##   {"type": "face", "unit": id, "facing": Vector2i}
## perform() 返回 {"ok": bool, "error": String, "action": Dictionary, "events": Array}。


## 开始战斗：第 1 回合的我方阶段。
static func start_battle(state: BattleState) -> void:
	state.command({"op": "start"})


## "" 表示行动合法，否则是原因（英文短语，EventText.error_text 翻成中文）。
static func validate(state: BattleState, action: Dictionary) -> String:
	var reply: Dictionary = state.query({"op": "validate", "action": action})
	return str(reply.get("error", reply.get("fail", "")))


static func perform(state: BattleState, action: Dictionary) -> Dictionary:
	var reply: Dictionary = state.command({"op": "perform", "action": action})
	if reply.has("fail"):
		return {"ok": false, "error": str(reply["fail"]), "action": action, "events": []}
	return {"ok": reply["ok"], "error": reply["error"], "action": action, "events": events(reply["events"])}


## 预览：引擎在副本上执行同一段规则，所以看到的就是将要发生的。不改变局面。
static func preview(state: BattleState, action: Dictionary) -> Dictionary:
	var reply: Dictionary = state.query({"op": "preview", "action": action})
	if reply.has("fail"):
		return {"ok": false, "error": str(reply["fail"]), "action": action, "events": []}
	return {"ok": reply["ok"], "error": reply["error"], "action": action, "events": events(reply["events"])}


## 结束当前阶段，返回期间产生的事件（回合结算、眩晕跳过……）。
static func end_phase(state: BattleState) -> Array:
	var reply: Dictionary = state.command({"op": "end_phase"})
	return events(reply.get("events", []))


## 多次行动的单位（首领）用掉一次行动；返回它本阶段是否还能再动。
static func finish_activation(state: BattleState, u: UnitState) -> bool:
	var reply: Dictionary = state.command({"op": "finish", "unit": u.id})
	return bool(reply.get("again", false))


## 跳跃技能的落点是否可用（"" 表示可以）。
static func leap_landing_error(state: BattleState, u: UnitState, to: Vector2i, sk: Dictionary) -> String:
	var reply: Dictionary = state.query({"op": "leap_error", "unit": u.id, "cell": to, "skill": sk.get("id", "")})
	return str(reply.get("error", reply.get("fail", "")))


## 瞄准时界面要画的格子，一次问全：
##   {"landings": 跳跃技能可落脚的锚点, "in_range": 射程范围, "valid": 现在能指定的目标格}
## pending 是还没选目标的行动（要带 "unit"；跳跃技能选好落点后带 "to"）。
static func targeting(state: BattleState, pending: Dictionary) -> Dictionary:
	var reply: Dictionary = state.query({"op": "targeting", "action": pending})
	return {"landings": GoEngine.cells(reply.get("landings", [])), "in_range": GoEngine.cells(reply.get("in_range", [])),
		"valid": GoEngine.cells(reply.get("valid", []))}


## 引擎发来的事件 -> 界面用的事件字典（坐标换成 Vector2i）。
static func events(raw: Variant) -> Array:
	var out: Array = []
	var list: Array = raw
	for item: Variant in list:
		var e: Dictionary = (item as Dictionary).duplicate()
		for key: String in ["from", "to", "facing"]:
			if e.has(key):
				e[key] = GoEngine.cell(e[key])
		if e.has("path"):
			e["path"] = GoEngine.cells(e["path"])
		out.append(e)
	return out


## 引擎发来的行动 -> 行动字典。
static func action_from(raw: Dictionary) -> Dictionary:
	var a: Dictionary = raw.duplicate()
	for key: String in ["target", "to", "facing"]:
		if a.has(key):
			a[key] = GoEngine.cell(a[key])
	return a
