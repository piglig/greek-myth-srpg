class_name SkillTree
extends RefCounted
## 战前选择的技能树节点。树的内容来自 Go 引擎读到的 skill_tree.json；点数和前置的校验也在引擎里做。

static var _trees: Dictionary = {}


static func points() -> int:
	return int(GoEngine.data().get("points", 0))


## def_id -> [{branch, nodes: [{id, name, cost, trait|skill, desc}]}]
static func campaign_level(entry: Dictionary) -> int:
	var victories:=0
	for outcome in entry.get("outcomes",{}).values():
		if outcome=="已通关": victories+=1
	return mini(30,1+victories)

static func budget(entry: Dictionary) -> int:
	return points()+campaign_level(entry)-1

static func trees() -> Dictionary:
	if _trees.is_empty():
		_trees = GoEngine.pairs(GoEngine.data().get("trees", []))
	return _trees


static func default_picks() -> Dictionary:
	var src: Dictionary = GoEngine.data().get("default_picks", {})
	return src.duplicate(true)


static func cost(def_id: String, picks: Array) -> int:
	return int(_check(def_id, picks).get("cost", 0))


## "" 表示加点合法（不超预算，且每个后续节点都点了它前面的节点）。
static func validate(def_id: String, picks: Array, allowance:=0) -> String:
	var reply: Dictionary = _check(def_id, picks, allowance)
	return str(reply.get("error", reply.get("fail", "")))


static func _check(def_id: String, picks: Array, allowance:=0) -> Dictionary:
	return GoEngine.request({"op": "picks_check", "def": def_id, "nodes": picks,"budget":allowance})
