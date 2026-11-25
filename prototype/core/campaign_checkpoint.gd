extends RefCounted
## The Corinth checkpoint also carries the resolved orders up to the last player decision.
## Where the save lives. A variable so the flow test can use a file of its own.
static var PATH := "user://chapter-one.cfg"
const BATTLES := ["1-1","1-2","1-3","1-4","1-5","2-1","2-2","2-3","2-4","2-5","3-1"]

## The numbers the campaign runs on, and the tables of things, spoils and heroes, are
## data/tables/*.json: the rules engine reads the same files, so that what a simulated
## player owns at each battle can be checked against what could be bought by then.
static var RULES: Dictionary = _table("campaign")
static var STARTING_COINS: int = int(RULES.starting_coins)

static func _table(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/tables/%s.json" % name))
	if not parsed is Dictionary:
		push_error("data/tables/%s.json is missing or is not a table" % name)
		return {}
	return _whole(parsed)

## JSON has one kind of number; a price of 55 comes back as 55.0. Whole numbers are made
## whole again, all the way down.
static func _whole(value: Variant) -> Variant:
	if value is float and value == floorf(value): return int(value)
	if value is Dictionary:
		for key: Variant in value: value[key] = _whole(value[key])
	elif value is Array:
		for i in value.size(): value[i] = _whole(value[i])
	return value

## What a chapter's table says for a battle of that chapter; chapters past the last one
## written take the last.
static func _by_chapter(table: Dictionary, battle: String) -> int:
	var chapter := int(battle.get_slice("-",0))
	var best := 0
	for key: String in table:
		if int(key) <= chapter: best = int(table[key])
	return best
## Where things are worn. A member wears one thing per place; every charm names its place.
const SLOTS := [["hand","手部"],["body","身体"],["foot","足部"],["trinket","饰物"]]

static func slot_name(key: String) -> String:
	for slot: Array in SLOTS:
		if slot[0] == key: return slot[1]
	return key
## Everything that can be owned. `slot` is a body place, or "material" for spoils that are
## only good for selling. `mods` changes numbers on the member sheet.
##
## The first five are `unique`: one of each exists, and the engine knows them by name
## because they do more than change numbers (engine/rules/chapter_reward.go, EquipReward).
## Their `mods` mirror what the engine applies; if one changes, change the other.
## Everything after them is plain: any number may be owned, the trader sells them unless
## marked `loot`, and their `mods` are sent to the engine as they are.
##
## A plain thing's price follows what it does: 18 to begin with, then for each point
## 生命 9, 力量 38, 防御 36, 意志 24, 神性 34, 移动 85, 跳跃 48; a point taken away gives back
## half its worth; 稀有 ×1.08 and 史诗 ×1.18; rounded to 5. Change a `mods` and the price
## should move with it.
static var GOODS: Dictionary = _table("goods")
## Shown for a rarity where no hired fighter is involved.
const STAT_NAMES := {"hp":"生命","str":"力量","def":"防御","wil":"意志","div":"神性","move":"移动","jump":"跳跃"}
## What each kind of enemy leaves behind: [thing, chance]. A beaten enemy always leaves at
## least one material (the first listed, if the dice give none).
static var LOOT: Dictionary = _table("loot")

## How many things one member may carry into battle. The engine holds the same number
## (rules.KitSlots).
static var KIT_SLOTS: int = int(RULES.kit_slots)

## The drawing for a thing.
static func art(id: String) -> String:
	return str(GOODS[id].get("art",id))

## What a thing does, in words.
static func effect_of(id: String) -> String:
	var goods: Dictionary = GOODS[id]
	if goods.has("effect"): return goods.effect
	if goods.slot == "material": return "战利品。可以卖给行商。"
	if goods.slot == "item": return "消耗品。"
	var parts: Array = []
	for stat: String in goods.get("mods",{}):
		var change := int(goods.mods[stat])
		parts.append("%s %s%d" % [STAT_NAMES[stat],"+" if change > 0 else "−",absi(change)])
	return "，".join(parts)+"。"

static func sell_price(id: String) -> int:
	return int(int(GOODS[id].price)*float(RULES.sell_for))

## A purse holds coins, `bag` ({thing: how many are owned, worn or not}), `worn`
## ({who: {place: thing}}) and `kit` ({who: [things carried into battle, one entry each]}). Older saves listed one of each thing and one wearer per thing.
static func settle_purse(purse: Dictionary) -> void:
	if not purse.has("coins"): purse.coins = STARTING_COINS
	if not purse.has("bag"): purse.bag = {}
	if not purse.has("worn"): purse.worn = {}
	if not purse.has("kit"): purse.kit = {}
	for id in purse.get("owned",[]):
		if GOODS.has(id): purse.bag[id] = maxi(1,int(purse.bag.get(id,0)))
	for id in purse.get("equipped",{}):
		if not GOODS.has(id): continue
		var who := str(purse.equipped[id])
		if not purse.worn.has(who): purse.worn[who] = {}
		purse.worn[who][GOODS[id].slot] = id
	purse.erase("owned")
	purse.erase("equipped")

## How many of a thing are being worn.
static func in_use(purse: Dictionary, id: String) -> int:
	var count := 0
	for who in purse.get("worn",{}):
		for place in purse.worn[who]:
			if purse.worn[who][place] == id: count += 1
	for who in purse.get("kit",{}):
		for thing in purse.kit[who]:
			if thing == id: count += 1
	return count

## How many of a thing are lying in the bag, free to wear or sell.
static func loose(purse: Dictionary, id: String) -> int:
	return int(purse.get("bag",{}).get(id,0))-in_use(purse,id)

## For the engine: the unique charms as {thing: wearer}.
static func charms(purse: Dictionary) -> Dictionary:
	var out := {}
	for who in purse.get("worn",{}):
		for place in purse.worn[who]:
			var id: String = purse.worn[who][place]
			if GOODS.has(id) and GOODS[id].get("unique",false): out[id] = who
	return out

## For the engine: what plain gear adds up to, as {wearer: {stat: change}}.
static func gear_mods(purse: Dictionary) -> Dictionary:
	var out := {}
	for who in purse.get("worn",{}):
		var total := {}
		for place in purse.worn[who]:
			var id: String = purse.worn[who][place]
			if not GOODS.has(id) or GOODS[id].get("unique",false): continue
			for stat: String in GOODS[id].get("mods",{}):
				total[stat] = int(total.get(stat,0))+int(GOODS[id].mods[stat])
		if not total.is_empty(): out[who] = total
	return out

## What a field of beaten enemies leaves behind, as {thing: how many}.
static func roll_loot(beaten: Array, rng: RandomNumberGenerator) -> Dictionary:
	var haul := {}
	for kind in beaten:
		var table: Array = LOOT.get(kind,[])
		var found_material := false
		for drop: Array in table:
			if rng.randf() >= float(drop[1]): continue
			haul[drop[0]] = int(haul.get(drop[0],0))+1
			if GOODS[drop[0]].slot == "material": found_material = true
		if not found_material:
			for drop: Array in table:
				if GOODS[drop[0]].slot == "material":
					haul[drop[0]] = int(haul.get(drop[0],0))+1
					break
	return haul

## What those still standing are worth when a battle is won without beating them: half
## of what their spoils would have sold for, in coin. Winning by the goal should not cost
## the purse.
static func left_standing(kinds: Array, rng: RandomNumberGenerator) -> int:
	var worth := 0
	var haul := roll_loot(kinds,rng)
	for thing: String in haul: worth += sell_price(thing)*int(haul[thing])
	return worth/2

## How rare a hired hero is: its name and colour.
const RARITY := {
	"common": {"name":"普通","tint":"#cfc4b0"},
	"rare": {"name":"稀有","tint":"#b78cf0"},
	"epic": {"name":"史诗","tint":"#f2b84b"},
}
## The heroes who can be hired at the camp. Each is one person of the old stories, hired
## once. `def` is the unit they fight as, `look` the sheets they are drawn from, `skill` the
## technique they come with, `fee` what they ask, and `after` the battle that must be
## cleared before they turn up. Each has a technique tree of their own under their key in skill_tree.json: a small
## one for the common, a middling one for the rare, a full one for the epic.
static var RECRUITS: Dictionary = _table("recruits")
## Everyone starts with one plain attack and one technique. A hired hand's technique is the
## `skill` of their kind. A story companion's is the first node of their tree, held from the
## start at no cost; the hero's (盾击) is already part of the unit.
static var STARTERS: Dictionary = RULES.free_first_technique
## How many heroes march beside the protagonist, who always goes. The player picks them all.
## One in the first chapter, two in the second, three from the third: with him that is a
## party of two, then three, then four, and each chapter's battles are set out for a party
## of that size (2026-11-25).
## The wounded centaur of the side road takes no seat: he is who the battle is about.
static func seats(battle: String) -> int:
	return _by_chapter(RULES.seats,battle)
## Battles whose story needs someone there: they march whatever the player picked.
const REQUIRED := {"1-1":["atalanta"],"1-2":["atalanta"],"1-5":["atalanta"]}
## Heroes a battle's own file places on the field. Left behind, they are benched; taken
## along, they are not sent as extra party members.
const PLACED := ["atalanta"]

## Heroes turn up as there come to be seats for them (2026-11-25): nobody in the first
## chapter, where the one seat beside the protagonist is nearly always Atalanta's; the
## common and the rare with the second chapter and its second seat; the epic with the
## third. `opens` is that chapter. `after`, the battle each was first heard of in, is kept
## for the telling and no longer gates anything.
static func for_hire(kind: String, entry: Dictionary) -> bool:
	if not RECRUITS.has(kind): return false
	return int(str(entry.get("id","1-1")).get_slice("-",0)) >= int(RECRUITS[kind].get("opens",2))

## What a hired hero does when called, in a sentence. `id` is his move in skills.json or
## his own name in recruits.json.
static func support_words(id: String, learnt: Array = []) -> String:
	var move := str(RECRUITS[id].get("support","")) if RECRUITS.has(id) else id
	var sk: Dictionary = SkillCatalog.get_skill(move).duplicate()
	# Each step of his tree adds to the move's numbers.
	if RECRUITS.has(id):
		for branch: Dictionary in SkillTree.trees().get(id,[]):
			for node: Dictionary in branch.nodes:
				if not learnt.has(node.id): continue
				var adds: Dictionary = node.get("support",{})
				for key: String in adds: sk[key] = int(sk.get(key,0))+int(adds[key])
		sk["cooldown"] = maxi(1,int(sk.get("cooldown",1)))
	var far := int(sk.get("max_range",1))
	var much := int(sk.get("power",0))
	var words := ""
	match str(sk.get("support","")):
		"guard": words = "主角 %d 格内的一名同伴得到 %d 点护盾。" % [far,much]
		"shot": words = "主角 %d 格内的一个敌人受 %d 点物理伤害，不看掩护和视线。" % [far,much]
		"sunder": words = "主角 %d 格内的一个敌人受 %d 点伤害，不计算防御；之后 %d 回合它的防御 −4。" % [far,much,int(sk.get("rounds",2))]
		"aid": words = "把主角自己或他 %d 格内的一名同伴带到主角 %d 格内的一块空地。带的是同伴时回复 %d 点生命、解一种异常。" % [far,int(sk.get("carry",0)),much]
		"break": words = "主角 %d 格内的一个敌人受 %d 点物理伤害，破势 +%d。" % [far,much,int(sk.get("stagger_bonus",0))]
		"charge": words = "从主角身边沿直线冲 %d 格，路上每个敌人受 %d 点物理伤害并被击退 %d 格。" % [far,much,int(sk.get("knockback",0))]
		_: return ""
	return words+"冷却 %d 回合，不占用主角的行动，他出手前后都能召。" % int(sk.get("cooldown",0))

## The hired heroes in camp, by their names in recruits.json.
static func hired(entry: Dictionary) -> Array:
	var out := []
	for hand: Dictionary in entry.get("roster",[]):
		if RECRUITS.has(str(hand.get("kind",""))) and not out.has(str(hand.kind)): out.append(str(hand.kind))
	return out

## Who comes in support of the next battle: the one picked, else the first hired, else "".
static func support_of(entry: Dictionary) -> String:
	var have := hired(entry)
	var picked := str(entry.get("support",""))
	if picked == "none": return ""
	return picked if have.has(picked) else ("" if have.is_empty() else str(have[0]))

## The chapter in which the first heroes can be hired.
const HIRING_OPENS := 2

## Who the drillmaster has to offer: every hero open at this point of the journey and not
## yet hired, each as {id, kind, name, fee}. Nothing is drawn by chance.
static func offers(entry: Dictionary) -> Array:
	var taken := {}
	for hand: Dictionary in entry.get("roster",[]): taken[hand.kind] = true
	var open := []
	for kind: String in RECRUITS:
		if for_hire(kind,entry) and not taken.has(kind):
			open.append({"id":kind,"kind":kind,"name":str(RECRUITS[kind].name),"fee":int(RECRUITS[kind].fee)})
	return open

## Whether the trader has a thing on the shelf at this point of the journey.
static func stocked(id: String, entry: Dictionary) -> bool:
	if not GOODS.has(id) or GOODS[id].slot == "material" or GOODS[id].get("loot",false): return false
	return int(GOODS[id].get("chapter",1))<=int(str(entry.get("id","1-1")).get_slice("-",0))

## Experience. Each member has their own, kept in the entry as {who: total}. Winning a battle
## for the first time pays `xp_for` to everyone who marched and half of it to those who
## stayed in camp. A level is worth one technique point.
static func xp_for(battle: String) -> int:
	return _by_chapter(RULES.xp,battle)

## Experience needed to go from `level` to the next.
static func xp_need(level: int) -> int:
	return int(RULES.xp_need.first)+int(RULES.xp_need.more_each_level)*(level-1)

## Total experience at which `level` is reached.
static func xp_total(level: int) -> int:
	var total := 0
	for step in range(1,level): total += xp_need(step)
	return total

## Where a total stands: {level, into (experience into this level), need}.
static func standing(total: int) -> Dictionary:
	var level := 1
	while total >= xp_need(level):
		total -= xp_need(level)
		level += 1
	return {"level":level,"into":total,"need":xp_need(level)}

## `aside` says the battle's optional goal was met: as much again.
static func award(purse: Dictionary, battle: String, aside := false) -> void:
	var paid: Array=purse.get("paid",[])
	if paid.has(battle): return
	paid.append(battle)
	purse.paid=paid
	purse.coins=int(purse.get("coins",STARTING_COINS))+pay_for(battle,aside)

static func pay_for(battle: String, aside := false) -> int:
	var pay := _by_chapter(RULES.pay,battle)
	return pay*int(RULES.aside_pays) if aside else pay

const BOONS := {
	"moon_hunt": ["阿耳忒弥斯", "月下狩猎", "追猎标记可同时保留两个目标。"],
	"swift_boots": ["赫尔墨斯", "疾行之靴", "每场战斗的第一回合，全体我方单位移动力 +2。"],
}

## The four tiers of divinity. The tier follows how many relics the protagonist has taken
## (entry.divinity) and nothing else: `gain` is what it gives, `cost` what it takes.
const TIERS := [
	{"name":"凡人","from":0,"tint":"#cfc4b0","gain":"","cost":""},
	{"name":"受火","from":2,"tint":"#7fc4ff","gain":"每场战斗第一次使用圣物主动，不进入冷却。","cost":""},
	{"name":"半神","from":4,"tint":"#ffd76a","gain":"每回合第一次使用圣物主动，不占行动。","cost":"他出手时，身边的英雄不再为他援护。"},
	{"name":"僭神","from":6,"tint":"#fff6da","gain":"免疫灼烧、中毒、束缚、眩晕。","cost":"治疗的招式和药对他不再起作用。"},
]
## Each tier raises his divinity by this much.
const TIER_DIVINITY := 3
## The divine techniques: on reaching a tier he takes one of its two, for good. The engine
## holds the same pairs (rules.PowerPairs).
const POWERS := [
	[["thunder_bolt","雷矢","射程 2–5。打一个，1.2 倍神性伤害，眩晕 1 回合；首领改为破势 +20。冷却 3。"],
	 ["sky_fire","天火","射程 2–4。指定一格，那一格和相邻四格各受 0.8 倍神性伤害，灼烧 2 回合。冷却 3。"]],
	[["thunder_step","雷行","瞬间出现在 4 格内任意一格，不看地形和高度；落点相邻的敌人各被震退 1 格。不算移动。冷却 3。"],
	 ["sky_dome","天穹","自己和 2 格内的同伴各得 6 点护盾。冷却 4。"]],
	[["sky_wrath","天罚","射程 2–6。任选一片 3×3，1.5 倍神性伤害，灼烧 2 回合。不分敌我。冷却 4。"],
	 ["thunder_body","雷躯","2 回合内，每次回合结算时与他相邻的所有人受 6 点神性伤害。不分敌我。冷却 5。"]],
]

## The relics, by id: what each is called, what it does while held, and what it does when
## called on. Only the lion's pelt works in battle so far; the rest are words until their
## chapters are built.
const RELICS := {
	"lion_pelt": {"icon":"art_pelt","name":"涅墨亚狮皮","held":"物理伤害在防御后再减 3；受背击的倍率降到 1.25。","called":"不坏之皮：1 回合内免疫物理伤害。冷却 4。","skill":"impervious_hide"},
	"hydra_blood": {"icon":"relic_blood","name":"蛇血","held":"他的攻击附带中毒 1 回合。","called":"剧毒：3 格内一个敌人中毒 3 回合，期间无法被治疗。冷却 3。","skill":"hydra_venom"},
	"bronze_feather": {"icon":"art_feather","name":"铜羽","held":"受到的远程伤害减 3，并把三成还给射手。","called":"羽刃：直线 4 格，贯穿，0.8 倍物理伤害。冷却 3。"},
	"ariadne_thread": {"icon":"art_thread","name":"阿里阿德涅之线","held":"每场 1 次，不耗行动与任意一位同伴交换位置。","called":"归路：把一位同伴拉到他身边，并解开束缚。冷却 4。"},
	"gorgon_head": {"icon":"brooch","name":"蛇发之首","held":"从正面近身打他的敌人被束缚 1 回合，每回合 1 次。","called":"凝视：面前扇形 3 格内朝着他的敌人眩晕 1 回合；首领改为破势 +30。冷却 5。"},
	"styx_water": {"icon":"relic_styx","name":"冥河之水","held":"每场 1 次，致命的一击改为留下 1 点生命。","called":"浸礼：2 回合内免疫异常状态和真实伤害。冷却 5。"},
	"titan_might": {"icon":"relic_titan","name":"泰坦之力","held":"击退对 2×2、3×3 的敌人同样有效，距离加 1；过肩摔能摔 2×2。","called":"撼地：身边所有敌人受 1.2 倍物理伤害并被击退 2 格。冷却 4。"},
}
## What each chapter's boss leaves to be decided once beaten: take the relic, or spare them
## and gain a hero. The lion of the first chapter is not here; its pelt is simply taken.
## `spared` is who joins: empty where that person is not yet designed.
const VERDICTS := {
	2: {"boss":"许德拉","icon":"boss_hydra","pronoun":"它","relic":"hydra_blood","spared":{"name":"伊俄拉俄斯","title":"举火的人","words":"带着火把的辅助：让身边人的攻击带火，能烧封伤口。（人已定，招式和数值还没做，现在选了只会记下来。）"}},
	3: {"boss":"铜羽鸟","icon":"boss_bird","pronoun":"它","relic":"bronze_feather","spared":{}},
	4: {"boss":"米诺陶洛斯","icon":"boss_minotaur","pronoun":"他","relic":"ariadne_thread","spared":{"name":"阿斯忒里俄斯","title":"迷宫里的人","words":"2×2 的前排，生命 86、力量 19。能撞开挡路的东西；走不了窄路，意志低。"}},
	5: {"boss":"美杜莎","icon":"brooch","pronoun":"她","relic":"gorgon_head","spared":{"name":"美杜莎","title":"戈尔贡","words":"完整的凝视：把人变成石像，不分敌我。神性 16，走得慢。"}},
	6: {"boss":"刻耳柏洛斯","icon":"boss_cerberus","pronoun":"它","relic":"styx_water","spared":{}},
	7: {"boss":"泰坦","icon":"boss_titan","pronoun":"他","relic":"titan_might","spared":{}},
}

static func tier_of(relics: int) -> int:
	var tier := 0
	for i in TIERS.size():
		if relics >= int(TIERS[i].from): tier = i
	return tier

static func tier(entry: Dictionary) -> int:
	return tier_of(int(entry.get("divinity",0)))

static func hero_look(entry: Dictionary) -> String:
	var rank := tier(entry)
	return "hero-tier%d" % rank if rank > 0 else "hero"


## Whether a tier has been reached whose technique is not yet chosen.
static func owes_power(entry: Dictionary) -> bool:
	return (entry.get("powers",[]) as Array).size() < tier(entry)

## What a divine technique does, in words; "" for anything else.
static func power_words(id: String) -> String:
	for pair: Array in POWERS:
		for power: Array in pair:
			if power[0] == id: return str(power[2])
	return ""

## How many relics he may take into a battle: one to begin with, and one more with the
## second, fourth and sixth relic taken. The engine holds the same rule (rules.RelicSlots).
static func relic_slots(entry: Dictionary) -> int:
	return mini(int(RULES.relic_slots.most),int(RULES.relic_slots.first)+(entry.get("relics",[]) as Array).size()/int(RULES.relic_slots.one_more_every))

## The relics he takes into battle: those picked, or failing that the first he took, as
## many as there are slots. Only relics the rules know how to use can be worn.
static func worn(entry: Dictionary) -> Array:
	if not entry.has("equipped_relic"): return []
	var held: Array = entry.get("relics",["lion_pelt"])
	var usable := held.filter(func(id): return RELICS.has(id) and RELICS[id].has("skill"))
	var picked: Array = entry.get("relics_worn",usable)
	return picked.filter(func(id): return usable.has(id)).slice(0,relic_slots(entry))

static func chapter_reward(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	result["equipped_relic"] = "lion_pelt"
	result["relics"] = ["lion_pelt"]
	result["divinity"] = 1
	result["powers"] = []
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
		if entry.id != "1-5" and not entry.id.begins_with("2-") or entry.equipped_relic != "lion_pelt" or int(entry.get("divinity",-1)) < 0:
			return {}
		if entry.get("boon") != "" and not BOONS.has(entry.get("boon")):
			return {}
	if entry.id.begins_with("2-") and (not entry.has("equipped_relic") or not BOONS.has(entry.get("boon",""))):
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
