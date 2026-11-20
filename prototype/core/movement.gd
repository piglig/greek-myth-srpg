class_name Movement
extends RefCounted
## 可达范围，由 Go 引擎计算。


## 移动可以结束在哪些锚点（含起点）：{anchor: {"cost": 消耗}}。budget < 0 表示用单位自己的移动力。
static func destinations(state: BattleState, u: UnitState, budget: int = -1) -> Dictionary:
	var reply: Dictionary = state.query({"op": "destinations", "unit": u.id, "budget": budget})
	var out: Dictionary = {}
	var list: Array = reply.get("cells", [])
	for item: Variant in list:
		var c: Array = item
		out[Vector2i(int(c[0]), int(c[1]))] = {"cost": int(c[2]), "stop": true}
	return out
