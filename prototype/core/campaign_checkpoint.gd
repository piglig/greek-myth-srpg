extends RefCounted
## The Corinth checkpoint also carries the resolved orders up to the last player decision.
const PATH := "user://chapter-one.cfg"
const BATTLES := ["1-1","1-2","1-3","1-4","1-5","2-1"]

const STARTING_COINS := 60
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
const GOODS := {
	"olive": {"unique":true,"rarity":"common","slot":"hand","name":"橄榄枝","price":120,"group":"守御","effect":"防御时回复 4 点生命。","lore":"山麓的野橄榄枝，用一小段红线系在盾带上。","icon":0},
	"wrist": {"unique":true,"rarity":"rare","mods":{"move":-1},"slot":"hand","name":"牛皮腕带","price":120,"group":"攻势","effect":"击退距离 +1，移动 −1。","lore":"赶车人缝的双层牛皮。收紧铜扣，手腕就能稳稳抵住盾缘。","icon":1},
	"brooch": {"unique":true,"rarity":"rare","mods":{"wil":2,"move":-1},"slot":"body","name":"戈耳戈肩扣","price":90,"group":"守御","effect":"意志 +2，移动 −1。","lore":"守夜的士兵把这张青铜鬼面朝外别在披风上。","icon":3},
	"anklet": {"unique":true,"rarity":"common","mods":{"jump":1,"str":-2},"slot":"foot","name":"斥候踝带","price":80,"group":"行军","effect":"跳跃 +1，力量 −2。","lore":"山道信使缠在脚踝上的细带，银翼磨得只剩浅浅的羽纹。","icon":4},
	"stone": {"unique":true,"rarity":"rare","mods":{"move":1,"def":-2},"slot":"trinket","name":"路标石","price":150,"group":"行军","effect":"移动 +1，防御 −2。","lore":"石上的回纹被指尖磨平，仍能辨出通往科林斯的方向。","icon":2,"chapter":2},
	"glove_hide": {"slot":"hand","name":"皮手套","rarity":"common","price":60,"art":"art_glove","mods":{"def":1},"lore":"牧人冬天戴的羊皮手套，掌心磨得发亮。"},
	"fist_wrap": {"slot":"hand","name":"拳带","rarity":"common","price":70,"art":"art_knuckle","mods":{"str":1},"lore":"角力场上缠手用的牛皮条。"},
	"bracer_bronze": {"slot":"hand","name":"青铜护腕","rarity":"common","price":90,"art":"art_bracers","mods":{"def":2,"jump":-1},"lore":"一对沉手的青铜护腕，挡得住刀，也拖得慢人。"},
	"ring_oath": {"slot":"hand","name":"誓约指环","rarity":"rare","price":150,"art":"art_ring_hand","mods":{"wil":3},"lore":"内圈刻着一句誓词，字迹已经磨平了一半。"},
	"gauntlet": {"slot":"hand","name":"铁臂甲","rarity":"rare","price":160,"art":"art_gauntlet","mods":{"str":2,"def":1,"jump":-1},"lore":"头目们才用得起的整片臂甲。"},
	"red_thread": {"slot":"hand","name":"红线团","rarity":"epic","price":320,"art":"art_thread","mods":{"wil":2,"move":1},"lore":"克里特来的红线。握着它的人，据说不会迷路。","chapter":2},
	"tunic": {"slot":"body","name":"亚麻短衣","rarity":"common","price":50,"art":"art_tunic","mods":{"hp":3},"lore":"洗得发白的短衣，胜在合身。"},
	"belt_wide": {"slot":"body","name":"宽皮带","rarity":"common","price":70,"art":"art_belt","mods":{"hp":2,"str":1},"lore":"勒紧腰腹，发力时不泄气。"},
	"leather": {"slot":"body","name":"皮甲","rarity":"common","price":90,"art":"art_leather","mods":{"def":2},"lore":"几层硬牛皮缝成的胸甲。"},
	"cloak_travel": {"slot":"body","name":"旅人斗篷","rarity":"rare","price":140,"art":"art_cloak","mods":{"wil":2,"hp":3},"lore":"走过远路的人才有的厚斗篷，风雨都认得它。"},
	"scale": {"slot":"body","name":"鳞甲","rarity":"rare","price":190,"art":"art_scale","mods":{"def":4,"move":-1},"lore":"铜片一片压一片，走起来哗哗作响。"},
	"cuirass": {"slot":"body","name":"青铜胸甲","rarity":"epic","price":340,"art":"art_breastplate","mods":{"def":5,"hp":4,"move":-1},"lore":"整块青铜敲成的胸甲，照得出人影。","chapter":2},
	"wolf_cape": {"slot":"body","name":"狼皮披肩","rarity":"rare","price":150,"art":"art_pelt","mods":{"hp":4,"str":1},"lore":"整张狼皮连着头，披在肩上还带着林子的气味。","loot":true},
	"sandal": {"slot":"foot","name":"草鞋","rarity":"common","price":50,"art":"art_sandal","mods":{"move":1,"def":-1},"lore":"轻，快，不经踩。"},
	"boots": {"slot":"foot","name":"牧人皮靴","rarity":"common","price":80,"art":"art_boots","mods":{"jump":1},"lore":"山上放羊的人穿的高帮靴。"},
	"greaves": {"slot":"foot","name":"胫甲","rarity":"rare","price":150,"art":"art_greaves","mods":{"def":2},"lore":"扣在小腿上的青铜片，方阵里人人都有一对。"},
	"trail_wraps": {"slot":"foot","name":"山行绑腿","rarity":"rare","price":160,"art":"art_steps","mods":{"jump":2,"str":-1},"lore":"半人马的同伴们用的绑腿，翻山不费力。"},
	"wingfoot": {"slot":"foot","name":"飞翼凉鞋","rarity":"epic","price":360,"art":"art_wingfoot","mods":{"move":1,"jump":1},"lore":"鞋跟上钉着一对小翅膀。没人说得清它是真的还是仿的。","chapter":2},
	"feather": {"slot":"trinket","name":"鹰羽","rarity":"common","price":60,"art":"art_feather","mods":{"jump":1},"lore":"山鹰落下的一根长羽，别在发间。"},
	"fang_charm": {"slot":"trinket","name":"狼牙坠","rarity":"common","price":70,"art":"art_fang_charm","mods":{"str":1},"lore":"头狼的牙，穿了孔挂在颈上。"},
	"cup": {"slot":"trinket","name":"祭酒杯","rarity":"rare","price":140,"art":"art_cup","mods":{"hp":3,"wil":1},"lore":"祭酒用的小杯。出发前斟满，洒一半给大地。"},
	"necklace": {"slot":"trinket","name":"琥珀项链","rarity":"rare","price":150,"art":"art_necklace","mods":{"hp":5},"lore":"北方来的琥珀，握久了是温的。"},
	"pendant": {"slot":"trinket","name":"青金坠","rarity":"rare","price":160,"art":"art_pendant","mods":{"div":2},"lore":"一小块青金石，颜色像黄昏以后的天。"},
	"owl": {"slot":"trinket","name":"猫头鹰小像","rarity":"rare","price":170,"art":"art_owl","mods":{"wil":2,"div":1},"lore":"雅典娜的鸟。夜里守营的人喜欢带着它。"},
	"amulet": {"slot":"trinket","name":"祭司护符","rarity":"epic","price":330,"art":"art_amulet","mods":{"div":3,"wil":2},"lore":"神庙里流出来的东西，阿齐尔不肯说是怎么到手的。","chapter":2},
	"wolf_hide": {"slot":"material","name":"狼皮","rarity":"common","price":30,"art":"art_pelt","lore":"剥得不算整齐，皮匠照样收。"},
	"wolf_fang": {"slot":"material","name":"狼牙","rarity":"common","price":20,"art":"art_tooth"},
	"bone": {"slot":"material","name":"兽骨","rarity":"common","price":12,"art":"art_bone"},
	"claw": {"slot":"material","name":"兽爪","rarity":"rare","price":60,"art":"art_claw"},
	"boar_tusk": {"slot":"material","name":"野猪獠牙","rarity":"rare","price":50,"art":"art_tusk"},
	"boar_hide": {"slot":"material","name":"野猪皮","rarity":"common","price":44,"art":"art_pelt"},
	"coin_pouch": {"slot":"material","name":"钱袋","rarity":"common","price":60,"art":"art_pouch","lore":"强盗腰上解下来的，里面是别人的钱。"},
	"bronze_scrap": {"slot":"material","name":"青铜碎片","rarity":"common","price":36,"art":"art_bronze"},
	"broken_shield": {"slot":"material","name":"破盾","rarity":"common","price":24,"art":"art_broken"},
	"arrows": {"slot":"material","name":"箭束","rarity":"common","price":20,"art":"art_arrows"},
	"rope": {"slot":"material","name":"麻绳","rarity":"common","price":14,"art":"art_rope"},
	"wine_skin": {"slot":"material","name":"酒囊","rarity":"common","price":30,"art":"art_wine","lore":"还剩小半袋没掺水的酒。"},
	"horsehair": {"slot":"material","name":"马鬃","rarity":"common","price":28,"art":"art_horsehair"},
	"lion_mane": {"slot":"material","name":"狮鬃","rarity":"epic","price":200,"art":"art_mane","lore":"涅墨亚狮子的鬃毛，刀割不断。"},
}
## Shown for a rarity where no hired fighter is involved.
const STAT_NAMES := {"hp":"生命","str":"力量","def":"防御","wil":"意志","div":"神性","move":"移动","jump":"跳跃"}
## What each kind of enemy leaves behind: [thing, chance]. A beaten enemy always leaves at
## least one material (the first listed, if the dice give none).
const LOOT := {
	"wolf": [["wolf_hide",0.6],["wolf_fang",0.5],["bone",0.3],["fang_charm",0.06],["wolf_cape",0.03]],
	"bandit": [["broken_shield",0.4],["coin_pouch",0.35],["rope",0.3],["fist_wrap",0.05],["leather",0.04]],
	"bandit_archer": [["arrows",0.6],["rope",0.3],["coin_pouch",0.25],["feather",0.06]],
	"bandit_chief": [["coin_pouch",1.0],["bronze_scrap",0.6],["belt_wide",0.15],["gauntlet",0.12]],
	"boar": [["boar_hide",0.7],["boar_tusk",0.7],["bone",0.4]],
	"centaur": [["horsehair",0.6],["wine_skin",0.5],["bronze_scrap",0.3],["trail_wraps",0.06]],
	"lion": [["lion_mane",1.0],["claw",1.0]],
}

## The drawing for a thing.
static func art(id: String) -> String:
	return str(GOODS[id].get("art",id))

## What a thing does, in words.
static func effect_of(id: String) -> String:
	var goods: Dictionary = GOODS[id]
	if goods.has("effect"): return goods.effect
	if goods.slot == "material": return "战利品。可以卖给行商。"
	var parts: Array = []
	for stat: String in goods.get("mods",{}):
		var change := int(goods.mods[stat])
		parts.append("%s %s%d" % [STAT_NAMES[stat],"+" if change > 0 else "−",absi(change)])
	return "，".join(parts)+"。"

static func sell_price(id: String) -> int:
	return int(GOODS[id].price)/2

## A purse holds coins, `bag` ({thing: how many are owned, worn or not}) and `worn`
## ({who: {place: thing}}). Older saves listed one of each thing and one wearer per thing.
static func settle_purse(purse: Dictionary) -> void:
	if not purse.has("coins"): purse.coins = STARTING_COINS
	if not purse.has("bag"): purse.bag = {}
	if not purse.has("worn"): purse.worn = {}
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

## How rare a hired fighter is: its name and colour, how often it turns up among the
## drillmaster's offers (weights), and the range its fee is drawn from.
const RARITY := {
	"common": {"name":"普通","tint":"#cfc4b0","odds":62,"fee":[60,100]},
	"rare": {"name":"稀有","tint":"#b78cf0","odds":30,"fee":[130,180]},
	"epic": {"name":"史诗","tint":"#f2b84b","odds":8,"fee":[220,280]},
}
## The kinds of fighter that can be hired. `def` is the unit they fight as. `after` is the
## battle that must be cleared before the kind turns up. A kind with a `name` is one person
## and can be hired once; the others are a trade, and each hire is given a name of their own.
## Only kinds marked `tree` have techniques to learn (the tree belongs to their `def`).
const RECRUITS := {
	"sword": {"skill":"heavy_cut","def":"bandit","title":"佣兵剑士","rarity":"common","after":"","lore":"从烧毁的村子里逃出来的护院，只剩一把短剑和一身力气。"},
	"archer": {"skill":"aimed_shot","def":"bandit_archer","title":"佣兵弓手","rarity":"common","after":"1-1","lore":"山里的猎户，箭术平平，胜在肯跟着走远路。"},
	"captain": {"skill":"heavy_cut","def":"bandit_chief","title":"佣兵队长","rarity":"rare","after":"1-1","lore":"带过十几个人的老兵。队伍散了，手艺还在。"},
	"lancer": {"skill":"trample","def":"centaur","title":"半人马枪手","rarity":"rare","after":"1-3","lore":"酒宴上少数没喝醉的半人马。他欠喀戎一个人情。"},
	"idas": {"skill":"heavy_cut","def":"bandit_chief","title":"墨塞涅的力士","name":"伊达斯","rarity":"epic","after":"1-2","tree":true,"lore":"墨塞涅的伊达斯，自称世上最强壮的凡人。他在林道上劫过别人，也被别人劫过。"},
	"eurytion": {"skill":"trample","def":"centaur","title":"半人马首领","name":"欧律提翁","rarity":"epic","after":"1-3","tree":true,"lore":"酒宴上带头闹事的那个。酒醒之后，他想还清这笔账。"},
}
## Everyone starts with one plain attack and one technique. A hired hand's technique is the
## `skill` of their kind. A story companion's is the first node of their tree, held from the
## start at no cost; the hero's (盾击) is already part of the unit.
const STARTERS := {"atalanta":"vital_shot","chiron":"purify_arrow","medea":"frailty"}
## Given names for hired hands who have none of their own.
const HAND_NAMES := ["吕科斯","克勒翁","狄翁","墨农","阿革诺耳","忒隆","欧迈俄斯","菲洛","卡里阿斯","尼卡诺耳","安提丰","西蒙","堤丢斯","厄喀翁"]
## How many fighters may march besides those the battle itself brings.
const EXTRA_SLOTS := 2
## How many the drillmaster has on offer at a time, and what it costs to see others.
const OFFERS := 3
const REROLL_FEE := 15

static func for_hire(kind: String, entry: Dictionary) -> bool:
	if not RECRUITS.has(kind): return false
	var gate: String = RECRUITS[kind].after
	return gate == "" or entry.get("outcomes",{}).get(gate,"") == "已通关" or entry.has("equipped_relic")

## Draws the drillmaster's offers: each is {id, kind, name, fee}. Rarity is rolled by its
## odds among the kinds open at this point of the journey; a named person is offered only
## while not yet hired, and never twice in one draw.
static func draw_offers(entry: Dictionary, rng: RandomNumberGenerator) -> Array:
	var taken := {}
	var names := {}
	for hand: Dictionary in entry.get("roster",[]):
		taken[hand.kind] = true
		names[hand.name] = true
	var offers := []
	for slot in OFFERS:
		var open := {}
		for kind: String in RECRUITS:
			if not for_hire(kind,entry): continue
			if RECRUITS[kind].has("name") and taken.has(kind): continue
			var grade: String = RECRUITS[kind].rarity
			if not open.has(grade): open[grade] = []
			open[grade].append(kind)
		if open.is_empty(): break
		var total := 0
		for grade: String in open: total += int(RARITY[grade].odds)
		var roll := rng.randi_range(1,total)
		var chosen := ""
		for grade: String in open:
			roll -= int(RARITY[grade].odds)
			if roll <= 0:
				chosen = grade
				break
		var kind: String = open[chosen][rng.randi_range(0,open[chosen].size()-1)]
		var name := str(RECRUITS[kind].get("name",""))
		if name == "":
			var free := HAND_NAMES.filter(func(candidate): return not names.has(candidate))
			name = free[rng.randi_range(0,free.size()-1)] if not free.is_empty() else "无名氏"
		else:
			taken[kind] = true
		names[name] = true
		var fee: Array = RARITY[chosen].fee
		offers.append({"id":"o%d" % rng.randi(),"kind":kind,"name":name,"fee":int(rng.randi_range(int(fee[0]),int(fee[1]))/5)*5})
	return offers

## Whether the trader has a thing on the shelf at this point of the journey.
static func stocked(id: String, entry: Dictionary) -> bool:
	if not GOODS.has(id) or GOODS[id].slot == "material" or GOODS[id].get("loot",false): return false
	return int(GOODS[id].get("chapter",1))<=int(str(entry.get("id","1-1")).get_slice("-",0))

## Experience. Each member has their own, kept in the entry as {who: total}. Winning a battle
## for the first time pays `xp_for` to everyone who marched and half of it to those who
## stayed in camp. A level is worth one technique point.
static func xp_for(battle: String) -> int:
	return 140 if battle.begins_with("2-") else 100

## Experience needed to go from `level` to the next.
static func xp_need(level: int) -> int:
	return 100+20*(level-1)

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
