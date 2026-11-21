extends RefCounted
## The Corinth checkpoint also carries the resolved orders up to the last player decision.
const PATH := "user://chapter-one.cfg"
const BATTLES := ["1-1","1-2","1-3","1-4","1-5","2-1"]

const STARTING_COINS := 60
const GOODS := {
	"olive": {"name":"橄榄枝","price":120,"group":"守御","effect":"防御时回复 4 点生命。","lore":"山麓的野橄榄枝，用一小段红线系在盾带上。","icon":0},
	"wrist": {"name":"牛皮腕带","price":120,"group":"攻势","effect":"击退距离 +1，移动 −1。","lore":"赶车人缝的双层牛皮。收紧铜扣，手腕就能稳稳抵住盾缘。","icon":1},
	"brooch": {"name":"戈耳戈肩扣","price":90,"group":"守御","effect":"意志 +2，移动 −1。","lore":"守夜的士兵把这张青铜鬼面朝外别在披风上。","icon":3},
	"anklet": {"name":"斥候踝带","price":80,"group":"行军","effect":"跳跃 +1，力量 −2。","lore":"山道信使缠在脚踝上的细带，银翼磨得只剩浅浅的羽纹。","icon":4},
	"stone": {"name":"路标石","price":150,"group":"行军","effect":"移动 +1，防御 −2。","lore":"石上的回纹被指尖磨平，仍能辨出通往科林斯的方向。","icon":2,"chapter":2},
}

static func stocked(id: String, entry: Dictionary) -> bool:
	return GOODS.has(id) and int(GOODS[id].get("chapter",1))<=int(str(entry.get("id","1-1")).get_slice("-",0))

static func award(purse: Dictionary, battle: String) -> void:
	var paid: Array=purse.get("paid",[])
	if paid.has(battle): return
	paid.append(battle)
	purse.paid=paid
	purse.coins=int(purse.get("coins",STARTING_COINS))+(80 if battle.begins_with("2-") else 60)

const BOONS := {
	"moon_hunt": ["阿耳忒弥斯", "月下狩猎", "追猎标记可同时保留两个目标。"],
	"swift_boots": ["赫尔墨斯", "疾行之靴", "每场战斗的第一回合，全体我方单位移动力 +2。"],
}

static func chapter_reward(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	result["equipped_relic"] = "lion_pelt"
	result["divinity"] = 0
	result["boon"] = ""
	return result

static func read_entry() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return {}
	var entry: Variant = cfg.get_value("campaign","entry",{})
	if not entry is Dictionary or entry.get("id","") not in BATTLES:
		return {}
	if not entry.get("picks") is Dictionary or not entry.get("rescued") is Array or not entry.get("chiron_joined") is bool:
		return {}
	for nodes: Variant in entry.picks.values():
		if not nodes is Array:
			return {}
		for node: Variant in nodes:
			if not node is String:
				return {}
	if entry.has("equipped_relic"):
		if entry.id not in ["1-5","2-1"] or entry.equipped_relic != "lion_pelt" or int(entry.get("divinity",-1)) < 0:
			return {}
		if entry.get("boon") != "" and not BOONS.has(entry.get("boon")):
			return {}
	if entry.id=="2-1" and (not entry.has("equipped_relic") or not BOONS.has(entry.get("boon",""))):
		return {}
	return entry

static func write_entry(entry: Dictionary) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("campaign","entry",entry)
	var temporary := PATH + ".tmp"
	var error := cfg.save(temporary)
	if error != OK:
		return error
	return DirAccess.rename_absolute(temporary,PATH)
