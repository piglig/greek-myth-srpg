class_name UnitState
extends RefCounted
## 一个单位的快照。数据全部来自 Go 引擎，每次规则执行后原地刷新；这里不做任何规则判断。

var id := ""
var def_id := ""
var display_name := ""
var team: int = Defs.Team.PLAYER
var pos := Vector2i.ZERO  ## 占地的左上角
var size := 1
var facing: Vector2i = Defs.SOUTH

var max_hp := 1
var hp := 1
var strength := 0
var divinity := 0
var defense := 0
var will := 0
var move := 4
var jump := 1
var height := 0  ## 站立高度

var skills: Array[String] = []
var traits := {}  ## 特性名 -> 值
var statuses := {}  ## 状态名 -> 剩余回合（保持获得顺序）
var shield := 0
## Looks worn by particular units: unit id -> the folder under art/pixel that holds their
## sheets. A hired fighter fights as an enemy kind but is drawn in their own colours.
static var looks := {}
## The technique tree this unit learns from: its kind's, or a hired hero's own.
var tree := ""
var cooldowns := {}
var items := {}  ## things carried: id -> how many are left

var stagger := 0
var stagger_max := 0
var boss := false

var actions_per_turn := 1
var actions_left := 0
var has_moved := false
var has_acted := false
var assist_used := false
var mark_used := false
var intercept_used := false
var post_move := 0


var alive := true
var hidden := false


## 用引擎发来的数据刷新。
func apply(d: Dictionary) -> void:
	id = d["id"]
	def_id = d["def"]
	tree = str(d.get("tree",def_id))
	display_name = d["name"]
	team = d["team"]
	pos = GoEngine.cell(d["pos"])
	size = d["size"]
	facing = GoEngine.cell(d["facing"])
	max_hp = d["max_hp"]
	hp = d["hp"]
	strength = d["str"]
	divinity = d["div"]
	defense = d["defense"]
	will = d["wil"]
	move = d["move"]
	jump = d["jump"]
	height = d["height"]
	skills.assign(d["skills"] as Array)
	traits = GoEngine.pairs(d["traits"])
	statuses = GoEngine.pairs(d["statuses"])
	shield = d["shield"]
	cooldowns = GoEngine.pairs(d["cooldowns"])
	items = GoEngine.pairs(d.get("items",[]))
	stagger = d["stagger"]
	stagger_max = d["stagger_max"]
	boss = d["boss"]
	actions_per_turn = d["actions_per_turn"]
	actions_left = d["actions_left"]
	has_moved = d["has_moved"]
	has_acted = d["has_acted"]
	assist_used = d["assist_used"]
	mark_used = d["mark_used"]
	intercept_used = d["intercept_used"]
	post_move = d["post_move"]
	alive = d["alive"]
	hidden = d["hidden"]


## The folder of sprite sheets this unit is drawn from.
func look() -> String:
	return str(looks.get(id,def_id))


func is_boss() -> bool:
	return boss


func has_trait(key: String) -> bool:
	return traits.has(key)


func has_status(key: String) -> bool:
	return statuses.has(key)


func cooldown(skill_id: String) -> int:
	return int(cooldowns.get(skill_id, 0))


## 站在 anchor 时占的格子（画高亮用）。
func footprint(anchor: Vector2i = Defs.NO_POS) -> Array[Vector2i]:
	if anchor == Defs.NO_POS:
		anchor = pos
	var out: Array[Vector2i] = []
	for dy in size:
		for dx in size:
			out.append(anchor + Vector2i(dx, dy))
	return out


func occupies(c: Vector2i) -> bool:
	return c.x >= pos.x and c.y >= pos.y and c.x < pos.x + size and c.y < pos.y + size
