extends RefCounted
## The Corinth checkpoint also carries the resolved orders up to the last player decision.
## Where the save lives. A variable so the flow test can use a file of its own.
static var PATH := "user://chapter-one.cfg"
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
##
## A plain thing's price follows what it does: 18 to begin with, then for each point
## 生命 9, 力量 38, 防御 36, 意志 24, 神性 34, 移动 85, 跳跃 48; a point taken away gives back
## half its worth; 稀有 ×1.08 and 史诗 ×1.18; rounded to 5. Change a `mods` and the price
## should move with it.
const GOODS := {
	"olive": {"unique":true,"rarity":"common","slot":"hand","name":"橄榄枝","price":120,"group":"守御","effect":"防御时回复 4 点生命。","lore":"山麓的野橄榄枝，用一小段红线系在盾带上。","icon":0},
	"wrist": {"unique":true,"rarity":"rare","mods":{"move":-1},"slot":"hand","name":"牛皮腕带","price":120,"group":"攻势","effect":"击退距离 +1，移动 −1。","lore":"赶车人缝的双层牛皮。收紧铜扣，手腕就能稳稳抵住盾缘。","icon":1},
	"brooch": {"unique":true,"rarity":"rare","mods":{"wil":2,"move":-1},"slot":"body","name":"戈耳戈肩扣","price":90,"group":"守御","effect":"意志 +2，移动 −1。","lore":"守夜的士兵把这张青铜鬼面朝外别在披风上。","icon":3},
	"anklet": {"unique":true,"rarity":"common","mods":{"jump":1,"str":-2},"slot":"foot","name":"斥候踝带","price":80,"group":"行军","effect":"跳跃 +1，力量 −2。","lore":"山道信使缠在脚踝上的细带，银翼磨得只剩浅浅的羽纹。","icon":4},
	"stone": {"unique":true,"rarity":"rare","mods":{"move":1,"def":-2},"slot":"trinket","name":"路标石","price":150,"group":"行军","effect":"移动 +1，防御 −2。","lore":"石上的回纹被指尖磨平，仍能辨出通往科林斯的方向。","icon":2,"chapter":2},
	"glove_hide": {"slot":"hand","name":"皮手套","rarity":"common","price":55,"art":"art_glove","mods":{"def":1},"lore":"牧人冬天戴的羊皮手套，掌心磨得发亮。"},
	"fist_wrap": {"slot":"hand","name":"拳带","rarity":"common","price":55,"art":"art_knuckle","mods":{"str":1},"lore":"角力场上缠手用的牛皮条。"},
	"bracer_bronze": {"slot":"hand","name":"青铜护腕","rarity":"common","price":65,"art":"art_bracers","mods":{"def":2,"jump":-1},"lore":"一对沉手的青铜护腕，挡得住刀，也拖得慢人。"},
	"ring_oath": {"slot":"hand","name":"誓约指环","rarity":"rare","price":95,"art":"art_ring_hand","mods":{"wil":3},"lore":"内圈刻着一句誓词，字迹已经磨平了一半。"},
	"gauntlet": {"slot":"hand","name":"铁臂甲","rarity":"rare","price":115,"art":"art_gauntlet","mods":{"str":2,"def":1,"jump":-1},"lore":"头目们才用得起的整片臂甲。"},
	"red_thread": {"slot":"hand","name":"红线团","rarity":"epic","price":180,"art":"art_thread","mods":{"wil":2,"move":1},"lore":"克里特来的红线。握着它的人，据说不会迷路。","chapter":2},
	"tunic": {"slot":"body","name":"亚麻短衣","rarity":"common","price":45,"art":"art_tunic","mods":{"hp":3},"lore":"洗得发白的短衣，胜在合身。"},
	"belt_wide": {"slot":"body","name":"宽皮带","rarity":"common","price":75,"art":"art_belt","mods":{"hp":2,"str":1},"lore":"勒紧腰腹，发力时不泄气。"},
	"leather": {"slot":"body","name":"皮甲","rarity":"common","price":90,"art":"art_leather","mods":{"def":2},"lore":"几层硬牛皮缝成的胸甲。"},
	"cloak_travel": {"slot":"body","name":"旅人斗篷","rarity":"rare","price":100,"art":"art_cloak","mods":{"wil":2,"hp":3},"lore":"走过远路的人才有的厚斗篷，风雨都认得它。"},
	"scale": {"slot":"body","name":"鳞甲","rarity":"rare","price":130,"art":"art_scale","mods":{"def":4,"move":-1},"lore":"铜片一片压一片，走起来哗哗作响。"},
	"cuirass": {"slot":"body","name":"青铜胸甲","rarity":"epic","price":225,"art":"art_breastplate","mods":{"def":5,"hp":4,"move":-1},"lore":"整块青铜敲成的胸甲，照得出人影。","chapter":2},
	"wolf_cape": {"slot":"body","name":"狼皮披肩","rarity":"rare","price":100,"art":"art_pelt","mods":{"hp":4,"str":1},"lore":"整张狼皮连着头，披在肩上还带着林子的气味。","loot":true},
	"sandal": {"slot":"foot","name":"草鞋","rarity":"common","price":85,"art":"art_sandal","mods":{"move":1,"def":-1},"lore":"轻，快，不经踩。"},
	"boots": {"slot":"foot","name":"牧人皮靴","rarity":"common","price":65,"art":"art_boots","mods":{"jump":1},"lore":"山上放羊的人穿的高帮靴。"},
	"greaves": {"slot":"foot","name":"胫甲","rarity":"rare","price":95,"art":"art_greaves","mods":{"def":2},"lore":"扣在小腿上的青铜片，方阵里人人都有一对。"},
	"trail_wraps": {"slot":"foot","name":"山行绑腿","rarity":"rare","price":105,"art":"art_steps","mods":{"jump":2,"str":-1},"lore":"半人马的同伴们用的绑腿，翻山不费力。"},
	"wingfoot": {"slot":"foot","name":"飞翼凉鞋","rarity":"epic","price":180,"art":"art_wingfoot","mods":{"move":1,"jump":1},"lore":"鞋跟上钉着一对小翅膀。没人说得清它是真的还是仿的。","chapter":2},
	"feather": {"slot":"trinket","name":"鹰羽","rarity":"common","price":65,"art":"art_feather","mods":{"jump":1},"lore":"山鹰落下的一根长羽，别在发间。"},
	"fang_charm": {"slot":"trinket","name":"狼牙坠","rarity":"common","price":55,"art":"art_fang_charm","mods":{"str":1},"lore":"头狼的牙，穿了孔挂在颈上。"},
	"cup": {"slot":"trinket","name":"祭酒杯","rarity":"rare","price":75,"art":"art_cup","mods":{"hp":3,"wil":1},"lore":"祭酒用的小杯。出发前斟满，洒一半给大地。"},
	"necklace": {"slot":"trinket","name":"琥珀项链","rarity":"rare","price":70,"art":"art_necklace","mods":{"hp":5},"lore":"北方来的琥珀，握久了是温的。"},
	"pendant": {"slot":"trinket","name":"青金坠","rarity":"rare","price":95,"art":"art_pendant","mods":{"div":2},"lore":"一小块青金石，颜色像黄昏以后的天。"},
	"owl": {"slot":"trinket","name":"猫头鹰小像","rarity":"rare","price":110,"art":"art_owl","mods":{"wil":2,"div":1},"lore":"雅典娜的鸟。夜里守营的人喜欢带着它。"},
	"amulet": {"slot":"trinket","name":"祭司护符","rarity":"epic","price":200,"art":"art_amulet","mods":{"div":3,"wil":2},"lore":"神庙里流出来的东西，阿齐尔不肯说是怎么到手的。","chapter":2},
	"item_potion": {"slot":"item","name":"回复药","rarity":"common","price":40,"effect":"回复 12 点生命。给自己或身边的同伴。","lore":"蜂蜜、酒和几味草药熬成的浓浆，装在小陶瓶里。"},
	"item_antidote": {"slot":"item","name":"解毒药","rarity":"common","price":50,"effect":"解除灼烧、中毒、束缚中的两种，回复 4 点生命。","lore":"喀戎的方子，苦得让人忘了自己在怕什么。"},
	"item_stone": {"slot":"item","name":"投石","rarity":"common","price":20,"effect":"射程 2–3。0.6 倍物理伤害，额外破势 15。","lore":"河滩上捡的卵石，一袋三枚，这里按一枚算。"},
	"item_javelin": {"slot":"item","name":"标枪","rarity":"common","price":45,"effect":"射程 2–4。1.2 倍物理伤害。","lore":"轻木杆，铁尖头，扔出去就别指望捡回来。"},
	"item_firepot": {"slot":"item","name":"火油罐","rarity":"rare","price":90,"effect":"射程 2–3。0.7 倍神性伤害，点燃目标 2 回合。","lore":"封着松脂和橄榄油的陶罐，罐口塞着浸过油的麻布。"},
	"item_net": {"slot":"item","name":"捕网","rarity":"rare","price":80,"effect":"射程 1–3。0.3 倍物理伤害，目标 1 回合无法移动。","lore":"渔夫的手抛网，四角坠着铅块。"},
	"wolf_hide": {"slot":"material","name":"狼皮","rarity":"common","price":30,"art":"art_pelt","lore":"剥得不算整齐，皮匠照样收。"},
	"wolf_fang": {"slot":"material","name":"狼牙","rarity":"common","price":20,"art":"art_tooth","lore":"磨一磨能做箭头，也有人拿去当护身符。"},
	"bone": {"slot":"material","name":"兽骨","rarity":"common","price":12,"art":"art_bone","lore":"熬汤、做针、刻骰子，总有人要。"},
	"claw": {"slot":"material","name":"兽爪","rarity":"rare","price":60,"art":"art_claw","lore":"涅墨亚狮子的爪，割得开青铜。"},
	"boar_tusk": {"slot":"material","name":"野猪獠牙","rarity":"rare","price":50,"art":"art_tusk","lore":"弯得像新月，猎人把它钉在门楣上。"},
	"boar_hide": {"slot":"material","name":"野猪皮","rarity":"common","price":44,"art":"art_pelt","lore":"又厚又硬，做盾面正合适。"},
	"coin_pouch": {"slot":"material","name":"钱袋","rarity":"common","price":60,"art":"art_pouch","lore":"强盗腰上解下来的，里面是别人的钱。"},
	"bronze_scrap": {"slot":"material","name":"青铜碎片","rarity":"common","price":36,"art":"art_bronze","lore":"不知从哪副甲上掉下来的，回炉就是新的。"},
	"broken_shield": {"slot":"material","name":"破盾","rarity":"common","price":24,"art":"art_broken","lore":"盾面裂了，铜箍还是好的。"},
	"arrows": {"slot":"material","name":"箭束","rarity":"common","price":20,"art":"art_arrows","lore":"箭羽参差不齐，胜在数量。"},
	"rope": {"slot":"material","name":"麻绳","rarity":"common","price":14,"art":"art_rope","lore":"三股麻拧成，够结实。"},
	"wine_skin": {"slot":"material","name":"酒囊","rarity":"common","price":30,"art":"art_wine","lore":"还剩小半袋没掺水的酒。"},
	"horsehair": {"slot":"material","name":"马鬃","rarity":"common","price":28,"art":"art_horsehair","lore":"半人马的尾鬃，做弓弦比牛筋还韧。"},
	"lion_mane": {"slot":"material","name":"狮鬃","rarity":"epic","price":200,"art":"art_mane","lore":"涅墨亚狮子的鬃毛，刀割不断。"},
}
## Shown for a rarity where no hired fighter is involved.
const STAT_NAMES := {"hp":"生命","str":"力量","def":"防御","wil":"意志","div":"神性","move":"移动","jump":"跳跃"}
## What each kind of enemy leaves behind: [thing, chance]. A beaten enemy always leaves at
## least one material (the first listed, if the dice give none).
const LOOT := {
	"wolf": [["wolf_hide",0.6],["wolf_fang",0.5],["bone",0.3],["fang_charm",0.06],["wolf_cape",0.03]],
	"bandit": [["broken_shield",0.4],["coin_pouch",0.35],["rope",0.3],["fist_wrap",0.05],["leather",0.04],["item_stone",0.15]],
	"bandit_archer": [["arrows",0.6],["rope",0.3],["coin_pouch",0.25],["feather",0.06],["item_javelin",0.12]],
	"bandit_chief": [["coin_pouch",1.0],["bronze_scrap",0.6],["belt_wide",0.15],["gauntlet",0.12],["item_potion",0.3]],
	"boar": [["boar_hide",0.7],["boar_tusk",0.7],["bone",0.4]],
	"centaur": [["horsehair",0.6],["wine_skin",0.5],["bronze_scrap",0.3],["trail_wraps",0.06],["item_potion",0.1]],
	"lion": [["lion_mane",1.0],["claw",1.0]],
}

## How many things one member may carry into battle. The engine holds the same number
## (rules.KitSlots).
const KIT_SLOTS := 2

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
	return int(GOODS[id].price)/2

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
const RECRUITS := {
	"iphicles": {"fee":60,"look":"merc_sword","skill":"heavy_cut","def":"bandit","title":"忒拜的凡人","name":"伊菲克勒斯","rarity":"common","after":"","lore":"赫拉克勒斯的孪生兄弟。同一个母亲，同一夜出生，他身上却没有一滴神的血。"},
	"phalerus": {"fee":80,"look":"merc_archer","skill":"aimed_shot","def":"bandit_archer","title":"雅典的弓手","name":"法勒洛斯","rarity":"common","after":"1-1","lore":"小时候被蛇缠住，父亲一箭射死了蛇，没伤到他。从那天起他就没放下过弓。"},
	"ancaeus": {"fee":150,"look":"merc_captain","skill":"heavy_cut","def":"bandit_chief","title":"阿卡迪亚的斧手","name":"安开俄斯","rarity":"rare","after":"1-1","lore":"披熊皮，使双刃斧。有人预言他喝不到自己葡萄园的酒，他从来不信。"},
	"pholus": {"fee":160,"look":"merc_lancer","skill":"trample","def":"centaur","title":"福洛厄山的主人","name":"福洛斯","rarity":"rare","after":"1-3","lore":"酒宴就是在他的洞里办的。那坛酒是他开的，他想把这笔账算清。"},
	"idas": {"fee":240,"look":"idas","skill":"heavy_cut","def":"bandit_chief","title":"墨塞涅的力士","name":"伊达斯","rarity":"epic","after":"1-2","lore":"墨塞涅的伊达斯，自称世上最强壮的凡人。他在林道上劫过别人，也被别人劫过。"},
	"eurytion": {"fee":260,"look":"eurytion","skill":"trample","def":"centaur","title":"半人马首领","name":"欧律提翁","rarity":"epic","after":"1-3","lore":"酒宴上带头闹事的那个。酒醒之后，他想还清这笔账。"},
}
## Everyone starts with one plain attack and one technique. A hired hand's technique is the
## `skill` of their kind. A story companion's is the first node of their tree, held from the
## start at no cost; the hero's (盾击) is already part of the unit.
const STARTERS := {"atalanta":"vital_shot","chiron":"purify_arrow","medea":"frailty"}
## How many heroes march beside the protagonist, who always goes. The player picks them all.
const SEATS := 3
## Battles whose story needs someone there: they march whatever the player picked.
const REQUIRED := {"1-1":["atalanta"],"1-2":["atalanta"],"1-5":["atalanta"]}
## Heroes a battle's own file places on the field. Left behind, they are benched; taken
## along, they are not sent as extra party members.
const PLACED := ["atalanta"]

static func for_hire(kind: String, entry: Dictionary) -> bool:
	if not RECRUITS.has(kind): return false
	var gate: String = RECRUITS[kind].after
	return gate == "" or entry.get("outcomes",{}).get(gate,"") == "已通关" or entry.has("equipped_relic")

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
	"lion_pelt": {"icon":"art_pelt","name":"涅墨亚狮皮","held":"物理伤害在防御后再减 3；受背击的倍率降到 1.25。","called":"不坏之皮：1 回合内免疫物理伤害。冷却 4。"},
	"hydra_blood": {"icon":"relic_blood","name":"蛇血","held":"他的攻击附带中毒 1 回合。","called":"剧毒：3 格内一个敌人中毒 3 回合。冷却 3。"},
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
	2: {"boss":"许德拉","icon":"boss_hydra","pronoun":"它","relic":"hydra_blood","spared":{}},
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

## Whether a tier has been reached whose technique is not yet chosen.
static func owes_power(entry: Dictionary) -> bool:
	return (entry.get("powers",[]) as Array).size() < tier(entry)

## What a divine technique does, in words; "" for anything else.
static func power_words(id: String) -> String:
	for pair: Array in POWERS:
		for power: Array in pair:
			if power[0] == id: return str(power[2])
	return ""

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
