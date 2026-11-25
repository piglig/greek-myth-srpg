class_name BattleState
extends RefCounted
## 一场战斗的快照。真正的战斗在 Go 引擎里（会话 sid）；每次规则执行后引擎把新局面发回来，
## 这里原地刷新，所以界面手里拿着的 UnitState 对象一直有效。只读，不含规则。

var sid := 0  ## 引擎里的会话编号
var version := 0  ## 每次刷新加一
var grid: BattleGrid
var units := {}  ## id -> UnitState
var order: Array[String] = []
var round_number := 1
var phase: int = Defs.Phase.PLAYER
var marked_id := ""
var previous_mark := ""
var reward := {}
var move_undo := {}  ## 还能撤销移动的单位 id -> true
## 洞穴（没有则为空）：{boss, entrances: {id: {anchor, sealed}}, boulders: {id: {pos, seals, progress, placed}}}
var cave := {}
var village_exits: Array[Vector2i] = []
var village_result := ""
var escort_exits: Array[Vector2i] = []
var escort_result := ""
## The far bank (2-2): every living one of ours standing there wins. `swamp_rests` counts
## how many times one of ours was still in swamp when a round was settled.
var reach_exits: Array[Vector2i] = []
var reach_result := ""
var swamp_rests := 0
## How many enemies have been pushed into deep water and lost there.
var drowned := 0
## Forest that is alight: [x, y, rounds left] each, and the forest cells the fire will
## take at the next settling of a round.
var fires: Array = []
var fire_next: Array[Vector2i] = []
## Those the battle is fought to kill (2-4), how many still stand, and how many of them a
## fire on the ground has burnt.
var targets: Array = []
var targets_left := 0
var targets_scorched := 0
var target_result := ""
## What the engine says of the battle ("" while it goes on), and how often the head that
## grew back most has grown back (the hydra).
var outcome := ""
var most_regrown := 0
var record_orders := false
var orders: Array = []
var rescue_result := ""
var rescue_exits: Array[Vector2i] = []

var _cache := {}  ## 请求 -> 应答；局面一变就清空，悬停时反复问同一件事不用再走一趟


func apply(d: Dictionary) -> void:
	version += 1
	_cache.clear()
	if d.has("grid"):
		grid = BattleGrid.from_dict(d["grid"])
	if d.has("escort_exits"):
		escort_exits=GoEngine.cells(d.escort_exits)
		escort_result=d.escort_result
	if d.has("reach_exits"):
		reach_exits = GoEngine.cells(d.reach_exits)
		reach_result = d.reach_result
		swamp_rests = int(d.get("swamp_rests",0))
	drowned = int(d.get("drowned",drowned))
	outcome = str(d.get("outcome",outcome))
	most_regrown = int(d.get("most_regrown",most_regrown))
	if d.has("fires"):
		fires = d.fires
		fire_next = GoEngine.cells(d.fire_next)
	if d.has("targets"):
		targets = d.targets
		targets_left = int(d.targets_left)
		targets_scorched = int(d.targets_scorched)
		target_result = d.target_result
	if d.has("rescue_exits"):
		rescue_result = d.rescue_result
		rescue_exits = GoEngine.cells(d.rescue_exits)
	if d.has("village"):
		village_exits = GoEngine.cells(d["village"]["exits"])
		village_result = d["village"]["result"]
	round_number = d["round"]
	phase = d["phase"]
	marked_id = d["marked"]
	previous_mark = d.get("previous_mark","")
	reward = d.get("reward",{})
	move_undo.clear()
	var list: Array = d["units"]
	for e: Variant in list:
		var ud: Dictionary = e
		var uid: String = ud["id"]
		var u: UnitState = units.get(uid)
		if u == null:
			u = UnitState.new()
			units[uid] = u
			order.append(uid)
		u.apply(ud)
		if ud["can_undo"]:
			move_undo[uid] = true
	cave = {}
	if d["cave"] != null:
		var c: Dictionary = d["cave"]
		var entrances := {}
		for e: Variant in (c["entrances"] as Array):
			var ed: Dictionary = e
			entrances[ed["id"]] = {"anchor": GoEngine.cell(ed["anchor"]), "sealed": ed["sealed"]}
		var boulders := {}
		for b: Variant in (c["boulders"] as Array):
			var bd: Dictionary = b
			boulders[bd["id"]] = {"pos": GoEngine.cell(bd["pos"]), "seals": bd["seals"],
				"progress": bd["progress"], "placed": bd["placed"]}
		cave = {"boss": c["boss"], "trigger_hp": c["trigger_hp"], "emerge_actions": c["emerge_actions"],
			"last": c["last"], "entrances": entrances, "boulders": boulders}


## 向引擎查询这场战斗（不改变局面的请求）；同一个局面下相同的请求只问一次。
func query(req: Dictionary) -> Dictionary:
	req["sid"] = sid
	var key: String = JSON.stringify(GoEngine.encode(req))
	if not _cache.has(key):
		_cache[key] = GoEngine.request(req)
	return _cache[key]


## 让引擎执行会改变局面的请求，并用发回的新局面刷新自己。
func command(req: Dictionary) -> Dictionary:
	var order:=req.duplicate(true) if record_orders else {}
	req["sid"] = sid
	var reply: Dictionary = GoEngine.request(req)
	if reply.has("state"):
		apply(reply["state"])
		if record_orders and reply.get("ok",true): orders.append(order)
	return reply


func unit(id: String) -> UnitState:
	return units.get(id)


## 站在格子上的单位（倒下的和隐藏的不算）。
func unit_at(c: Vector2i) -> UnitState:
	for id in order:
		var u: UnitState = units[id]
		if u.alive and not u.hidden and u.occupies(c):
			return u
	return null


func living(team: int = -1) -> Array[UnitState]:
	var out: Array[UnitState] = []
	for id in order:
		var u: UnitState = units[id]
		if u.alive and (team == -1 or u.team == team):
			out.append(u)
	return out


## 占地的站立高度（脚下最高的一格）——摆放模型用。
func standing_height(anchor: Vector2i, size: int) -> int:
	var h := 0
	for dy in size:
		for dx in size:
			h = maxi(h, grid.height_at(anchor + Vector2i(dx, dy)))
	return h


func unit_height(u: UnitState) -> int:
	return u.height
