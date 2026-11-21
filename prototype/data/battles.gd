class_name Battles
extends RefCounted
## 战斗列表和开局，来自 Go 引擎（它读 data/tables/battles/<id>.json）。


static func ids() -> Array[String]:
	var out: Array[String] = []
	for b: Variant in (GoEngine.data().get("battles", []) as Array):
		out.append(str((b as Dictionary)["id"]))
	return out


static func title(id: String) -> String:
	for b: Variant in (GoEngine.data().get("battles", []) as Array):
		var d: Dictionary = b
		if d["id"] == id:
			return str(d["title"])
	return id


## picks：单位定义 -> 技能树节点 id；传空用表里的默认加点。失败返回 null（原因在 GoEngine.error）。
static func build(id: String, picks: Dictionary = {}, chiron_joined := false, reward := {}) -> BattleState:
	var reply: Dictionary = GoEngine.request({"op": "build", "battle": id, "picks": picks,"chiron_joined":chiron_joined,"reward":reward})
	if reply.has("fail"):
		return null
	var s := BattleState.new()
	s.sid = reply["sid"]
	s.apply(reply["state"])
	return s
