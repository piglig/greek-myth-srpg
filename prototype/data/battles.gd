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
## `party` lists the extra fighters chosen at the camp, as [{id, def, name}]. Leave it null
## for the old behaviour, where only Chiron tags along once he has joined.
static func build(id: String, picks: Dictionary = {}, chiron_joined := false, reward := {}, party: Variant = null, loadout: Variant = null, mods: Variant = null, items: Variant = null, bench: Array = []) -> BattleState:
	var ask := {"op": "build", "battle": id, "picks": picks,"chiron_joined":chiron_joined,"reward":reward}
	if party != null: ask["party"] = party
	if loadout != null: ask["loadout"] = loadout
	if mods != null: ask["mods"] = mods
	if items != null: ask["items"] = items
	if not bench.is_empty(): ask["bench"] = bench
	# Who comes in support rides along with the rest of what the camp sends.
	if str(reward.get("support","")) != "":
		ask["support"] = str(reward.support)
		# What he has learnt goes under his own name, beside the fighters' picks.
		var all: Dictionary = picks.duplicate()
		all[str(reward.support)] = reward.get("support_picks",[])
		ask["picks"] = all
	var reply: Dictionary = GoEngine.request(ask)
	if reply.has("fail"):
		return null
	var s := BattleState.new()
	s.sid = reply["sid"]
	s.apply(reply["state"])
	return s
