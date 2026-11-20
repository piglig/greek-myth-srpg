class_name EnemyAI
extends RefCounted
## 敌方 AI，由 Go 引擎决策（engine/rules/enemy_ai.go）。
## 计划：{"move_to": Vector2i（可选）, "action": 行动字典}。


static func plan(state: BattleState, u: UnitState) -> Dictionary:
	var reply: Dictionary = state.query({"op": "plan", "unit": u.id})
	if not reply.has("plan"):
		return {"action": {"type": "wait", "unit": u.id}}
	return _plan(reply["plan"])


## 在副本上走一遍计划，返回 {"plan", "events"}——意图预览用。不改变局面。
static func simulate(state: BattleState, u: UnitState) -> Dictionary:
	var reply: Dictionary = state.query({"op": "simulate", "unit": u.id})
	if not reply.has("plan"):
		return {"plan": {"action": {"type": "wait", "unit": u.id}}, "events": []}
	return {"plan": _plan(reply["plan"]), "events": Rules.events(reply["events"])}


## 这个单位下次行动（移动 + 任意技能）可能打到的格子。
static func threat_cells(state: BattleState, u: UnitState) -> Array[Vector2i]:
	var reply: Dictionary = state.query({"op": "threat", "unit": u.id})
	return GoEngine.cells(reply.get("cells", []))


## 洞穴首领下次要用的入口。
static func cave_entrance(state: BattleState, u: UnitState) -> String:
	var reply: Dictionary = state.query({"op": "cave_entrance", "unit": u.id})
	return str(reply.get("entrance", ""))


static func _plan(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {"action": Rules.action_from(raw["action"])}
	if raw.has("move_to"):
		out["move_to"] = GoEngine.cell(raw["move_to"])
	return out
