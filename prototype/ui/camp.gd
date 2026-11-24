extends Control
## The camp: where the party stops between battles, and where every battle begins and ends.
##
## It keeps three kinds of business apart:
##   - the camp itself is a live scene. Three people stand in it, each with one job:
##     the trader sells charms, the drillmaster hires fighters, the pathfinder leads the march.
##   - the party is one screen, opened from anywhere: pick a member, then see their
##     standing, their techniques and what they wear.
##   - the system menu.

const Save := preload("res://core/campaign_checkpoint.gd")
const Routes := preload("res://data/chapter_routes.json")
const TITLE := "res://title.tscn"
const BATTLE := "res://main.tscn"
const NAMES := {"hero":"主角","atalanta":"阿塔兰忒","chiron":"喀戎","medea":"美狄亚"}
const ROLES := {"hero":"持盾先锋","atalanta":"卡吕冬猎手","chiron":"半人马贤者","medea":"科尔喀斯女巫"}
## Who the companions are, as the member sheet tells it. The hero's line says only what he
## knows of himself: the name of the game already tells the player the rest (20-narrative).
const LORE := {
	"hero": "阿卡迪亚山村的守村人。雷火烧掉村子的那一夜，只有他从火里走了出来。",
	"atalanta": "被父亲遗弃在山里，由母熊养大的猎手。她追着一头巨兽的踪迹来到这里，不相信任何归宿。",
	"chiron": "半人马贤者，教过阿喀琉斯、伊阿宋和阿斯克勒庇俄斯。被一支毒箭误伤，伤口永不愈合。",
	"medea": "科尔喀斯的女巫，赫利俄斯的孙女，赫卡忒的女祭司。帮伊阿宋取得金羊毛，又被他抛弃。",
}
const NUMERALS := ["一","二","三","四","五","六","七","八"]
## The people of the camp: who they are, the sprite that plays them, where they stand,
## and the screen they open.
const PEOPLE := [
	{"key":"trader","name":"阿齐尔","role":"行商","service":"买护符","icon":"shop","def":"refugee","look":"npc_trader","cell":Vector2(10.5,5.9),"turn":Vector2i(0,1)},
	{"key":"recruit","name":"达蒙","role":"教习","service":"招募","icon":"helmet","def":"bandit_chief","look":"npc_drill","cell":Vector2(3.4,5.6),"turn":Vector2i(1,0)},
	{"key":"march","name":"伊俄","role":"领路人","service":"出征","icon":"march","def":"bandit_archer","look":"npc_guide","cell":Vector2(11.4,8.2),"turn":Vector2i(-1,0)}]
const GREETINGS := {"trader":"坐。我这秤称过腓尼基的银子，也称过阿卡迪亚最后一袋麦子。",
	"recruit":"把盾放低些。你看得见我的肩，才看得见我什么时候出手。",
	"march":"过来搭把手，压住这张图。夜里起风，明早的路可不能让它吹走。"}
const FIRE := Vector2(7.0,6.8)
## Layout on the 960x540 canvas. Screens cover the left; the camp stays in view on the right.
const HEAD := Rect2(24,52,696,48)
const LIST := Rect2(24,108,214,412)
const DETAIL := Rect2(250,108,470,412)
const MEASURE := 430.0

var entry := {}
var persistent := true
var screen := "home"  ## home | party | trader | recruit | march
const CARRY := 4  ## techniques a member takes into battle; the engine enforces the same number (rules.LoadoutSlots)
var page := "info"  ## member sheet: "info" (numbers, gear, carried techniques) or "tree"
var open := ""  ## what the foot of the info page shows: "" (who they are), "gear" (a place) or "skill" (a carried slot)
var slot_at := 0  ## the carried slot open on the info page
var kit_at := 0  ## the pocket open on the info page (open == "kit")
var kit_pick := ""
var skill_pick := ""  ## the technique being considered for that slot
var member := "hero"
var technique := ""
var place := "hand"  ## the body place open on the gear page
var view := "members"  ## party screen: by person ("members") or by thing ("pack")
var pack_filter := ""  ## a place key, or "" for everything
var pack_spare := false  ## show only what nobody wears
var pack_item := ""
var shop_tab := "buy"  ## trader: "buy" from the shelf or "sell" from the bag
var shop_filter := ""
var candidate := ""  ## the thing being considered on the gear page
## Where each scrolling list was left, so redrawing a page does not jump it back to the top.
var scrolls := {}
var picked := {"trader":"","recruit":"","march":-1}
var chapter := 0
var note := ""
var asking := ""  ## "" | "boon" | "system"
var canvas: Control
var body := Control.new()
var signs := Control.new()
var scene: Diorama
var figures := {}
var seats := {}  ## where each party member stands in the camp
var sitters := {}  ## their figures, with the way each faces when left alone
var tabs_row: Array[Button] = []
var cheer := Control.new()  ## the report laid over everything when the party walks back in
var floats := Control.new()  ## short-lived words over the camp: what was just done, coins moving
var note_tone := Px.IVORY
var shown_coins := -1

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if not GoEngine.ensure():
		get_tree().change_scene_to_file.call_deferred(TITLE)
		return
	var shot := {}
	if get_tree().has_meta("shot"):
		shot = get_tree().get_meta("shot")
		get_tree().remove_meta("shot")
	if get_tree().has_meta("camp_entry"):
		entry = get_tree().get_meta("camp_entry")
		get_tree().remove_meta("camp_entry")
		persistent = entry.get("campaign",true)
	elif not shot.is_empty():
		entry = {"id":"1-4","stage":"camp","picks":SkillTree.default_picks(),"rescued":["a","b"],"chiron_joined":true,
			"outcomes":{"1-1":"已通关","1-2":"已通关","1-3":"已通关"},"choose_route":false,"roster":[{"id":"r1","kind":"iphicles","name":"伊菲克勒斯"},{"id":"r2","kind":"idas","name":"伊达斯"}],"deploy":["atalanta","chiron","r2"],
			"purse":{"coins":260,"bag":{"olive":1,"anklet":1,"leather":2,"wolf_hide":3,"wolf_fang":2,"coin_pouch":1},"worn":{"hero":{"hand":"olive"}},"paid":["1-1"]}}
		persistent = false
	else:
		entry = Save.read_entry()
	if entry.is_empty():
		get_tree().change_scene_to_file.call_deferred(TITLE)
		return
	_settle_roster()
	Soundscape.score("jar")
	chapter = _chapter_of(str(entry.get("id","1-1")))
	if not shot.is_empty():
		_open_for_shot(str(shot.page))
		UiShot.take(self,str(shot.path),2.6)
	_pitch_camp()
	canvas = Px.stage(self)
	for layer: Control in [signs,body,floats,cheer]:
		layer.size = Px.SIZE
		layer.mouse_filter = MOUSE_FILTER_IGNORE
		canvas.add_child(layer)
	cheer.hide()
	if entry.has("equipped_relic") and entry.get("boon","") == "":
		asking = "boon"
	_render()
	# News from the last battle is told once, then forgotten.
	if entry.has("news"):
		var news: Dictionary = entry.news
		entry.erase("news")
		var gains := _share_xp(int(news.get("xp",0)),news.get("fielded",[]))
		if persistent: Save.write_entry(entry)
		_report(news,gains)

func _open_for_shot(which: String) -> void:
	match which:
		"boon":
			entry.equipped_relic = "lion_pelt"
			entry.divinity = 3
			entry.boon = ""
		"system": asking = "system"
		"kit":
			screen = "party"
			entry.purse.bag["item_potion"] = 2
			entry.purse.bag["item_javelin"] = 1
			entry.purse.kit = {"hero":["item_potion"]}
			open = "kit"
			kit_at = 1
		"shop": screen = "trader"
		"sell":
			screen = "trader"
			shop_tab = "sell"
			picked.trader = "wolf_hide"
		"loot": entry.news = {"battle":"1-4","won":true,"result":"山谷已肃清","coins":60,"xp":100,"fielded":["hero","atalanta","chiron"],"fallen":[],"loot":{"wolf_hide":3,"wolf_fang":2,"bone":1,"boar_tusk":2,"boar_hide":1,"fang_charm":1}}
		"levelup": entry.news = {"battle":"1-3","won":true,"result":"酒宴结束，喀戎加入队伍","coins":60,"xp":180,"fielded":["hero","atalanta","chiron","r2"],"fallen":["r2"]}
		"won": entry.news = {"battle":"1-3","won":true,"result":"酒宴结束，喀戎加入队伍","fielded":["hero","atalanta"],"fallen":[]}
		"lost": entry.news = {"battle":"1-4","won":false,"result":"战斗失利，可整备后重试","fielded":["hero","atalanta","chiron"],"fallen":["hero","chiron"]}
		"toast":
			screen = "recruit"
			note = "福洛斯加入了营地。"
			note_tone = Color(str(Save.RARITY.rare.tint))
			shown_coins = 410
		"skills":
			screen = "party"
			page = "tree"
		"gear":
			screen = "party"
			open = "gear"
		"carry":
			screen = "party"
			entry.picks["hero"] = ["shield_wall","shield_drive","slam","heel_strike","breaker"]
			open = "skill"
			slot_at = 1
			skill_pick = "breaker"
		"swap":
			screen = "party"
			entry.purse.bag["wrist"] = 1
			open = "gear"
			candidate = "wrist"
		"pack":
			screen = "party"
			view = "pack"
			for id: String in Save.GOODS: entry.purse.bag[id] = 1+id.length()%3
			entry.purse.worn = {"hero":{"hand":"olive","body":"leather"},"atalanta":{"body":"leather","foot":"boots"},"chiron":{"foot":"anklet"}}
		"hired":
			screen = "party"
			member = "r2"
			page = "tree"
		"common":
			# A common hero's small tree.
			screen = "party"
			member = "r1"
			page = "tree"
		"depart":
			# Walk out of the camp into the next battle, to check the hand-over.
			screen = "march"
			_depart.call_deferred(_site(str(entry.id)))
		_:
			if which in ["party","trader","recruit","march"]: screen = which

# --- The camp scene -----------------------------------------------------------------

func _pitch_camp() -> void:
	scene = Diorama.new()
	add_child(scene)
	scene.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scene.lay(["22222222222222","11222222222211","11111111111111","00111111111100","00000000000000","00000000000000","00000000000000","00000000000000","00000000000000","00000000000000"],
		[Vector2i(1,6),Vector2i(12,3),Vector2i(2,9),Vector2i(8,9)])
	scene.fire(FIRE)
	scene.prop(preload("res://art/landmarks/cart.glb"),1.6,Vector2(11.4,3.2),-.5)
	_furnish()
	for person: Dictionary in PEOPLE:
		figures[person.key] = scene.unit(person.def,person.cell,person.turn,false,person.look)
	# The party rests round the fire, each turned toward it.
	var around := [Vector2(-1.5,.3),Vector2(1.4,.5),Vector2(-.9,-1.4),Vector2(1.0,-1.3),Vector2(-.2,1.6),Vector2(2.2,-.4)]
	var index := 0
	for who: String in _everyone():
		if index >= around.size(): break
		var seat: Vector2 = around[index]
		var toward := Vector2i(-signi(roundi(seat.x)),0) if absf(seat.x) > absf(seat.y) else Vector2i(0,-signi(roundi(seat.y)))
		sitters[who] = [scene.unit(_def(who),FIRE+seat,toward,false,_look(who) if _look(who) != _def(who) else ""),toward]
		seats[who] = FIRE+seat
		index += 1
	_turn_sitters()
	scene.look.call_deferred(_view_target(),0,_view_zoom())

## What makes the place a camp: somewhere to sleep, the trader's stall, the drillmaster's
## yard, the guide's post. Models from two CC0 kits (see art/thirdparty/CREDITS.md).
func _furnish() -> void:
	var props := "res://art/thirdparty/camp/props/%s.gltf"
	var survival := "res://art/thirdparty/camp/survival/%s.glb"
	# Tents on the open ground at the near left, bedrolls and logs by the fire.
	# Kept to the far left and behind the fire: nothing stands between the camera and
	# whoever sits by it when their sheet is open.
	scene.kit(survival % "tent-canvas",Vector2(.9,7.3),2.0,.55,true)
	scene.kit(survival % "tent-canvas",Vector2(1.5,9.2),2.0,.3,true)
	scene.kit(survival % "bedroll",Vector2(2.6,8.4),.22,.9,true)
	scene.kit(survival % "bedroll-packed",Vector2(2.3,7.2),.36,.3,true)
	scene.kit(survival % "tree-log",Vector2(8.9,5.4),.34,1.1,true)
	scene.kit(survival % "tree-log-small",Vector2(5.6,5.0),.3,-.3,true)
	scene.kit(props % "Bucket_Wooden_1",Vector2(8.1,5.6),.42)
	# The trader: a stall, and his wares round it.
	scene.kit(props % "Stall_Empty",Vector2(10.3,4.2),2.6,PI)
	scene.kit(props % "Crate_Wooden",Vector2(11.6,4.9),.66,.4)
	scene.kit(props % "Crate_Wooden",Vector2(12.0,4.3),.66,-.2)
	scene.kit(props % "Vase_4",Vector2(9.2,4.8),.62)
	scene.kit(props % "Bag",Vector2(9.5,5.4),.42,.6)
	scene.kit(props % "Barrel",Vector2(12.3,5.4),.85)
	# The drillmaster: weapons to hand and something to hit.
	scene.kit(props % "WeaponStand",Vector2(2.2,4.7),1.25,.5)
	scene.kit(props % "Dummy",Vector2(4.6,5.0),1.75,.3)
	scene.kit(props % "Shield_Wooden",Vector2(3.0,4.5),.8,.3)
	scene.kit(props % "Bench",Vector2(1.6,6.2),.45,1.3)
	# The guide: a post that points the way, a banner, his chest.
	scene.kit(survival % "signpost",Vector2(12.5,9.0),1.6,-.6,true)
	scene.kit(props % "Banner_1",Vector2(12.9,7.2),2.6,-.4)
	scene.kit(props % "Chest_Wood",Vector2(12.4,7.9),.5,-.9)
	scene.kit(props % "Stool",Vector2(10.5,8.6),.42)
	# What stood here before the camp did: an old shrine's columns, one still up, one down.
	var greek := "res://art/thirdparty/camp/greek/%s.glb"
	scene.kit(greek % "doric_column",Vector2(6.6,3.3),2.7,0.0,false,true)
	var fallen := scene.kit(greek % "doric_column",Vector2(8.4,13.2),2.4,0.0,false,true)
	fallen.rotation = Vector3(PI*.5,.9,0)
	fallen.position.y += .38

## With a screen open the camp slides right so whoever it concerns stays in view: the
## person being spoken to, or the member whose sheet is open. A member is shown close up,
## so the figure that fights stands in for a portrait.
func _view_target() -> Vector2:
	if screen == "home": return FIRE+Vector2(.4,.2)
	if screen == "party":
		if view == "members" and seats.has(member): return seats[member]+Vector2(-5.0,-.9)
		return FIRE+Vector2(-7.8,-.8)
	for person: Dictionary in PEOPLE:
		if person.key == screen: return person.cell+Vector2(-7.8,-.8)
	return FIRE

func _view_zoom() -> int:
	return 2 if screen == "party" and view == "members" else 1

## Whoever's sheet is open turns to face you; the rest go back to the fire.
func _turn_sitters() -> void:
	for who: String in sitters:
		var shown: bool = screen == "party" and view == "members" and who == member
		sitters[who][0].set_facing(Defs.SOUTH if shown else sitters[who][1])

func _reframe() -> void:
	_turn_sitters()
	scene.rig.zoom_index = _view_zoom()
	scene.rig.glide_to(scene.spot(_view_target())+Vector3.UP*.8)

func _process(_delta: float) -> void:
	# Name signs follow their people as the camera moves.
	for sign: Control in signs.get_children():
		var figure: Node3D = figures[sign.get_meta("key")]
		var at: Vector2 = scene.rig.camera.unproject_position(figure.global_position+Vector3.UP*2.3)/canvas.scale.x
		sign.position = (at-Vector2(sign.size.x*.5,40)).round()

# --- Progress ---------------------------------------------------------------------

func _story_party() -> Array:
	var party := ["hero","atalanta"]
	if entry.get("chiron_joined",false): party.append("chiron")
	if entry.get("medea_joined",false): party.append("medea")
	return party

## Saves from before hires had names of their own listed only the kind; give those a
## record.
func _settle_roster() -> void:
	var roster: Array = []
	for hand in entry.get("roster",[]):
		if hand is Dictionary:
			roster.append(hand)
		elif Save.RECRUITS.has(hand):
			roster.append({"id":str(hand),"kind":str(hand),"name":str(Save.RECRUITS[hand].name)})
	entry.roster = roster
	# Every companion holds their starting technique.
	if not entry.has("picks"): entry.picks = {}
	for who: String in Save.STARTERS:
		var held: Array = entry.picks.get(who,[])
		if not held.has(Save.STARTERS[who]): held.push_front(Save.STARTERS[who])
		entry.picks[who] = held
	_settle_xp()

func _xp(who: String) -> int:
	return int(entry.get("xp",{}).get(who,0))

func _level(who: String) -> int:
	return int(Save.standing(_xp(who)).level)

## Everyone has experience of their own. A save from before that starts everyone where the
## shared level stood. A companion who joins later starts level with the hero; a hired hand
## starts with half of what the hero has.
func _settle_xp() -> void:
	var known: Dictionary = entry.get("xp",{})
	var fresh := not entry.has("xp")
	if fresh: known["hero"] = Save.xp_total(SkillTree.campaign_level(entry))
	for who: String in _everyone():
		if known.has(who): continue
		known[who] = int(known.get("hero",0)) if fresh or _hand(who).is_empty() else int(known.get("hero",0))/2
	entry.xp = known

## Shares out what a battle paid: all of it to those who marched, half to the rest.
## Returns {who: [before, after]}.
func _share_xp(amount: int, fielded: Array) -> Dictionary:
	var gains := {}
	for who: String in _everyone():
		var before := _xp(who)
		var share := amount if fielded.has(who) else amount/2
		entry.xp[who] = before+share
		gains[who] = [before,before+share]
	return gains

## The record of a hired hand, or {} for a story companion.
func _hand(who: String) -> Dictionary:
	for hand: Dictionary in entry.get("roster",[]):
		if hand.id == who: return hand
	return {}

func _kind(who: String) -> Dictionary:
	var hand := _hand(who)
	return Save.RECRUITS[hand.kind] if not hand.is_empty() else {}

## Story companions first, then the hired.
func _everyone() -> Array:
	return _story_party()+entry.get("roster",[]).map(func(hand): return hand.id)

func _name(who: String) -> String:
	return NAMES.get(who,_hand(who).get("name",who))

func _role(who: String) -> String:
	return ROLES.get(who,_kind(who).get("title",""))

func _grade(rarity: String) -> Array:
	return [Save.RARITY[rarity].name,Color(str(Save.RARITY[rarity].tint))]

## [name, colour] of a hired fighter's rarity, or [] for a story companion.
func _rarity(who: String) -> Array:
	var kind := _kind(who)
	return _grade(kind.rarity) if not kind.is_empty() else []

## Points a member has to spend. The starting technique is held for free.
func _budget(who: String) -> int:
	var points := _level(who)
	if Save.STARTERS.has(who): points += SkillTree.cost(who,[Save.STARTERS[who]])
	return points

## The technique tree this member learns from, or "" if they have none: a story
## companion's goes by their own name, a hired hero's by the name they are hired under.
func _tree_of(who: String) -> String:
	var hand: Dictionary = _hand(who)
	var key := who if hand.is_empty() else str(hand.kind)
	return key if SkillTree.trees().has(key) else ""

## The folder of sprite sheets a member is drawn from: their own colours where they have them.
func _look(who: String) -> String:
	var kind := _kind(who)
	return str(kind.get("look",kind.def)) if not kind.is_empty() else who

func _def(who: String) -> String:
	var kind := _kind(who)
	return str(kind.def) if not kind.is_empty() else who

## Every hero in camp but the protagonist: any of them may be picked to march.
func _reserves() -> Array:
	var pool: Array = _story_party().filter(func(who): return who != "hero")
	pool.append_array(entry.get("roster",[]).map(func(hand): return hand.id))
	return pool

## Who the player has picked to march beside the protagonist, up to the seats.
func _marching() -> Array:
	var pool := _reserves()
	if not entry.has("deploy"):
		return pool.slice(0,Save.SEATS)
	return (entry.deploy as Array).filter(func(who): return pool.has(who)).slice(0,Save.SEATS)

## Who a battle's story needs there, of those in camp.
func _required(battle: String) -> Array:
	var pool := _reserves()
	return (Save.REQUIRED.get(battle,[]) as Array).filter(func(who): return pool.has(who))

## Who marches to a given battle: those it requires, then the player's picks.
func _marching_to(battle: String) -> Array:
	var going := _required(battle)
	for who: String in _marching():
		if not going.has(who): going.append(who)
	return going.slice(0,Save.SEATS)

func _coins() -> int:
	return int(entry.get("purse",{}).get("coins",Save.STARTING_COINS))

func _purse() -> Dictionary:
	var purse: Dictionary = entry.get("purse",{})
	Save.settle_purse(purse)
	entry.purse = purse
	return purse

## What a member has on, as {place: thing}.
func _worn(who: String) -> Dictionary:
	return _purse().worn.get(who,{})

## The colour of a thing's rarity.
func _tint(item: String) -> Color:
	return Color(str(Save.RARITY[Save.GOODS[item].get("rarity","common")].tint))

func _rarity_word(item: String) -> String:
	return str(Save.RARITY[Save.GOODS[item].get("rarity","common")].name)

## Sorts things by place, then the rarer first, then by name.
func _in_order(things: Array) -> Array:
	var places := Save.SLOTS.map(func(slot): return slot[0])+["item","material"]
	var grades := ["epic","rare","common"]
	var sorted := things.duplicate()
	sorted.sort_custom(func(a,b):
		var ga: Dictionary = Save.GOODS[a]
		var gb: Dictionary = Save.GOODS[b]
		if ga.slot != gb.slot: return places.find(ga.slot) < places.find(gb.slot)
		if ga.get("rarity","common") != gb.get("rarity","common"): return grades.find(ga.get("rarity","common")) < grades.find(gb.get("rarity","common"))
		return str(ga.name) < str(gb.name))
	return sorted

func _keep(next: Dictionary) -> bool:
	if persistent and Save.write_entry(next) != OK:
		note = "没能写入存档，请检查本机存储空间。"
		return false
	entry = next
	return true

func _chapter_of(id: String) -> int:
	return clampi(int(id.get_slice("-",0))-1,0,Routes.data.size()-1)

func _site(id: String) -> Dictionary:
	for region: Dictionary in Routes.data:
		for site: Dictionary in region.sites:
			if site.id == id: return site
	return {}

func _status(at: int, site: Dictionary) -> String:
	var outcomes: Dictionary = entry.get("outcomes",{})
	if at == 1 and site.id == "2-1" and entry.get("id") == "2-1":
		return str(outcomes[site.id]) if outcomes.has(site.id) else "可出发"
	if at != 0: return "尚未开放"
	if site.id == "1-5" and entry.has("equipped_relic"): return "已通关"
	if outcomes.has(site.id): return str(outcomes[site.id])
	if site.id == entry.get("id","1-1"): return "可出发"
	if site.id == "1-3":
		if entry.get("choose_route",false): return "可出发"
		if entry.get("id","") in ["1-4","1-5"]: return "未到访"
		return "支线待解锁"
	return "尚未抵达"

func _story(who: String) -> String:
	match who:
		"trader":
			if entry.get("rescued",[]).size() >= 2: return "林道上得救的人替我把货送到了。那只牛皮腕带，就是赶车的老人亲手缝的。"
			return "这枝橄榄是我女儿削的。举盾喘口气的时候，摸一摸，就记得为什么要活着回来。"
		"recruit":
			if str(entry.get("camp_summary","")).contains("失利"): return "先别急着重来。告诉我，敌人逼近时是谁站得太靠前了？下一次，让盾手先接敌。"
			if entry.get("chiron_joined",false): return "喀戎看了你的步子。他说弓手找的就是你抬盾时露出的空当。来，我们再走一遍。"
			return "记着狼扑过来的那一瞬。先稳后脚，再把盾送出去。光靠胳膊，你挡不住第二下。"
	if entry.get("choose_route",false): return "村民说山上还亮着酒宴的灯。往山里去能赶上宴席，向东走则直通涅墨亚。"
	if entry.get("id") == "2-1":
		if entry.get("outcomes",{}).has("2-1"): return "东门已经安全，美狄亚和我们一道走。今晚可以收起这张刑场图了。"
		return "科林斯的东门有条窄路。接到美狄亚就往那里撤，别为了追守卫把她落下。"
	return "我已把下一处落脚点圈在图上。先看路口，再看敌人能从哪边绕到你背后。"

# --- Drawing ------------------------------------------------------------------------

func _go(where: String) -> void:
	screen = where
	asking = ""
	_reframe()
	_render()

## Focus once the frame has settled; the control may already be gone if the page was redrawn.
func _focus(control: Control) -> void:
	(func():
		if is_instance_valid(control) and control.is_inside_tree(): control.grab_focus()).call_deferred()

func _set_asking(what: String) -> void:
	asking = what
	_render()

func _render() -> void:
	Px.clear(body)
	Px.clear(signs)
	tabs_row.clear()
	_top()
	match screen:
		"home": _home()
		"party": _party()
		"trader": _trader()
		"recruit": _recruit()
		"march": _march()
	_after()
	if asking == "boon": _ask_boon()
	elif asking == "system": _ask_system()

## A price: the coin stamp and the number, red when the purse cannot cover it. `at` is the
## left edge of the price, or its right edge when `flush`.
func _price(parent: Control, amount: int, at: Vector2, flush := false, tone := Px.OCHRE) -> void:
	if amount > _coins(): tone = Px.RED.lightened(.4)
	var words := str(amount)
	var x := at.x-(15+Px.width_of(words,Px.SMALL)) if flush else at.x
	var coin := Px.picture(parent,Px.icon("coins",12),Rect2(x,at.y-1,12,12))
	coin.modulate = tone
	coin.mouse_filter = MOUSE_FILTER_IGNORE
	Px.text(parent,words,Rect2(x+15,at.y,80,0),Px.SMALL,tone).mouse_filter = MOUSE_FILTER_IGNORE

## Gold dust for a level gained, thrown up from one spot.
func _dust(at: Vector2) -> CPUParticles2D:
	var dust := CPUParticles2D.new()
	dust.position = at
	dust.emitting = false
	dust.one_shot = true
	dust.amount = 36
	dust.lifetime = 1.1
	dust.explosiveness = .95
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(40,3)
	dust.direction = Vector2.UP
	dust.spread = 60.0
	dust.initial_velocity_min = 50.0
	dust.initial_velocity_max = 150.0
	dust.gravity = Vector2(0,200)
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 3.0
	var fade := Gradient.new()
	fade.set_color(0,Color("fff1c4"))
	fade.set_color(1,Color(Px.OCHRE,0))
	dust.color_ramp = fade
	cheer.add_child(dust)
	return dust

## The party walks back into camp. One panel: how the battle went and what it paid, then a
## cell for each member who marched, whose experience fills in front of you. `gains` is
## {who: [experience before, after]}.
func _report(news: Dictionary, gains: Dictionary) -> void:
	asking = "cheer"
	Px.clear(cheer)
	cheer.show()
	var won: bool = news.get("won",false)
	var earned := int(news.get("coins",0))
	var fielded: Array = (news.get("fielded",[]) as Array).filter(func(who): return _everyone().has(who))
	var fallen: Array = news.get("fallen",[])
	var trim := Px.OCHRE if won else Px.RED.lightened(.3)
	Px.block(cheer,Rect2(Vector2.ZERO,Px.SIZE),Color(Px.INK,.6)).mouse_filter = MOUSE_FILTER_STOP
	var across := maxi(4,fielded.size())
	var loot: Dictionary = news.get("loot",{})
	var more := 44.0 if not loot.is_empty() else 0.0
	var size := Vector2(across*108+24,258+more)
	var panel := Control.new()
	panel.size = size
	panel.position = ((Px.SIZE-size)*.5).round()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.modulate.a = 0.0
	cheer.add_child(panel)
	Px.sheet(panel,Rect2(Vector2.ZERO,size),.97)
	Px.block(panel,Rect2(0,0,size.x,2),trim)
	# How it went, and what it paid.
	Px.text(panel,"胜利" if won else "失利",Rect2(16,12,60,0),Px.TITLE,trim)
	var fought := _site(str(news.get("battle","")))
	if not fought.is_empty(): Px.text(panel,"%s %s" % [fought.id,fought.name],Rect2(74,12,260,0),Px.BODY,Px.IVORY)
	Px.text(panel,str(news.get("result","")).trim_suffix("，可整备后重试"),Rect2(74,28,300,0),Px.SMALL,Px.MUTED)
	if earned > 0:
		var gain := "+%d" % earned
		var left := size.x-16-15-Px.width_of(gain)
		Px.picture(panel,Px.icon("coins",12),Rect2(left,19,12,12)).modulate = Px.OCHRE
		Px.text(panel,gain,Rect2(left+15,18,80,0),Px.BODY,Px.OCHRE)
	Px.rule(panel,Vector2(16,48),size.x-32,Color(Px.OCHRE,.3))
	# A cell for each who marched (an empty one where nobody did).
	var bar_wide := 84.0
	var rose := false
	for i in across:
		var cell := Rect2(12+i*108,58,100,130)
		Px.block(panel,cell,Color(Px.IVORY,.05))
		if i >= fielded.size():
			Px.text(panel,"空位",Rect2(cell.position+Vector2(0,56),Vector2(100,0)),Px.SMALL,Px.FAINT,HORIZONTAL_ALIGNMENT_CENTER)
			continue
		var who: String = fielded[i]
		var down := fallen.has(who)
		var edge := Px.block(panel,Rect2(cell.position,Vector2(100,2)),Color(trim,0))
		var face := Px.picture(panel,Px.face(_look(who),48),Rect2(cell.position+Vector2(26,8),Vector2(48,48)))
		if down:
			face.modulate = Color(.45,.4,.4)
			Px.text(panel,"倒下",Rect2(cell.position+Vector2(0,40),Vector2(96,0)),Px.SMALL,Px.RED.lightened(.4),HORIZONTAL_ALIGNMENT_RIGHT)
		var grade := _rarity(who)
		Px.text(panel,_name(who),Rect2(cell.position+Vector2(0,60),Vector2(100,0)),Px.BODY,grade[1] if not grade.is_empty() else Px.IVORY,HORIZONTAL_ALIGNMENT_CENTER)
		var span: Array = gains.get(who,[_xp(who),_xp(who)])
		var from := Save.standing(int(span[0]))
		var to := Save.standing(int(span[1]))
		var rank := Px.text(panel,"等级 %d" % from.level,Rect2(cell.position+Vector2(0,78),Vector2(100,0)),Px.SMALL,Px.OCHRE,HORIZONTAL_ALIGNMENT_CENTER)
		rank.pivot_offset = Vector2(50,6)
		var track := Rect2(cell.position+Vector2(8,96),Vector2(bar_wide,6))
		Px.block(panel,track,Color(Px.IVORY,.12))
		var fill := Px.block(panel,Rect2(track.position,Vector2(roundf(bar_wide*from.into/from.need),6)),Px.OCHRE)
		var got := int(span[1])-int(span[0])
		var words := Px.text(panel,"+%d 经验" % got if got > 0 else "没有得到经验",Rect2(cell.position+Vector2(0,108),Vector2(100,0)),Px.SMALL,Px.MUTED if got > 0 else Px.FAINT,HORIZONTAL_ALIGNMENT_CENTER)
		if got <= 0: continue
		if to.level > from.level: rose = true
		# The bar fills; each time it tops out the level turns over and it starts again.
		var dust := _dust(panel.position+cell.position+Vector2(50,96)) if to.level > from.level else null
		var climb := panel.create_tween()
		climb.tween_interval(.35+i*.12)
		for level in range(from.level,to.level):
			climb.tween_property(fill,"size:x",bar_wide,.45).set_ease(Tween.EASE_OUT)
			climb.tween_callback(func():
				rank.text = "等级 %d" % (level+1)
				rank.scale = Vector2(1.6,1.6)
				fill.size.x = 0.0
				edge.color.a = 1.0
				words.text = "+%d 技能点" % (level+1-int(from.level))
				words.add_theme_color_override("font_color",Px.GREEN)
				dust.restart()
				Soundscape.cue("confirm"))
			climb.tween_property(rank,"scale",Vector2.ONE,.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		climb.tween_property(fill,"size:x",roundf(bar_wide*to.into/to.need),.4).set_ease(Tween.EASE_OUT)
	# What the beaten left behind.
	if not loot.is_empty():
		Px.text(panel,"战利品",Rect2(16,203,60,0),Px.SMALL,Px.OCHRE)
		var things := _in_order(loot.keys())
		var room := int((size.x-80)/46)
		for i in mini(things.size(),room):
			var thing: String = things[i]
			var spot := Vector2(64+i*46,194)
			Px.block(panel,Rect2(spot,Vector2(42,30)),Color(Px.IVORY,.05))
			Px.block(panel,Rect2(spot,Vector2(42,2)),Color(_tint(thing),.7))
			var stamp := Px.picture(panel,Px.icon(Save.art(thing),16),Rect2(spot+Vector2(4,8),Vector2(16,16)))
			stamp.modulate = _tint(thing)
			stamp.tooltip_text = Save.GOODS[thing].name
			Px.text(panel,"×%d" % int(loot[thing]),Rect2(spot+Vector2(20,11),Vector2(20,0)),Px.SMALL,Px.IVORY,HORIZONTAL_ALIGNMENT_RIGHT)
		if things.size() > room: Px.text(panel,"…",Rect2(size.x-22,203,16,0),Px.SMALL,Px.MUTED)
	# Those who stayed behind.
	var resting := _everyone().filter(func(who): return not fielded.has(who))
	var half := int(news.get("xp",0))/2
	if not resting.is_empty() and half > 0:
		Px.text(panel,"留守的 %d 人各得 %d 经验" % [resting.size(),half],Rect2(0,196+more,size.x,0),Px.SMALL,Px.FAINT,HORIZONTAL_ALIGNMENT_CENTER)
	var choices: Array[Button] = []
	if rose:
		choices.append(Px.primary(panel,"去分配技能点",Rect2(size.x*.5-140,218+more,136,28),_end_cheer.bind(true)))
		choices.append(Px.button(panel,"继续",Rect2(size.x*.5+4,218+more,136,28),_end_cheer.bind(false)))
	else:
		choices.append(Px.primary(panel,"继续" if won else "回营整备",Rect2(size.x*.5-68,218+more,136,28),_end_cheer.bind(false)))
	Px.chain(choices,false)
	_focus(choices[0])
	var arrive := panel.create_tween()
	arrive.tween_property(panel,"modulate:a",1.0,.18)
	arrive.parallel().tween_property(panel,"position:y",panel.position.y,.18).from(panel.position.y+10)

func _end_cheer(to_tree: bool) -> void:
	if asking != "cheer": return
	asking = "boon" if entry.has("equipped_relic") and entry.get("boon","") == "" else ""
	cheer.hide()
	Px.clear(cheer)
	if to_tree and asking == "":
		screen = "party"
		view = "members"
		if _tree_of(member) == "": member = "hero"
		page = "tree"
		_reframe()
	_render()

func _top() -> void:
	Px.sheet(body,Rect2(0,0,Px.SIZE.x,44),.84)
	Px.picture(body,Px.icon("campfire",24),Rect2(24,10,24,24)).modulate = Px.OCHRE
	Px.text(body,"营地",Rect2(56,8,120,0),Px.TITLE,Px.IVORY)
	var where := _chapter_of(str(entry.get("id","1-1")))
	Px.text(body,"第%s章 · %s" % [NUMERALS[where],Routes.data[where].name],Rect2(118,18,360,0),Px.SMALL,Px.MUTED)
	Px.picture(body,Px.icon("coins",16),Rect2(640,14,16,16)).modulate = Px.OCHRE
	Px.text(body,"%d 德拉克马" % _coins(),Rect2(662,15,100,0),Px.SMALL,Px.OCHRE)
	# The party is always one press away, wherever you are in the camp.
	var party := Px.button(body,"　　回营地" if screen == "party" else "　　队伍",Rect2(758,8,108,28),_go.bind("home" if screen == "party" else "party"))
	Px.picture(body,Px.icon("campfire" if screen == "party" else "party",16),Rect2(770,14,16,16)).modulate = Px.OCHRE
	var system := Px.button(body,"",Rect2(908,8,28,28),_set_asking.bind("system"))
	system.tooltip_text = "系统"
	Px.picture(body,Px.icon("system",16),Rect2(914,14,16,16)).modulate = Px.IVORY
	Px.chain([party,system],false)
	tabs_row.append(party)

## What follows every redraw: the purse says what it just lost or gained, and anything worth
## saying about the last action slips into the top bar for a moment.
func _after() -> void:
	if shown_coins >= 0 and _coins() != shown_coins:
		var change := _coins()-shown_coins
		var words := Px.text(floats,("+%d" if change > 0 else "%d") % change,Rect2(662,28,80,0),Px.BODY,Px.GREEN if change > 0 else Px.RED.lightened(.4))
		var drift := words.create_tween()
		drift.tween_property(words,"position:y",46.0,1.1).set_ease(Tween.EASE_OUT)
		drift.parallel().tween_property(words,"modulate:a",0.0,1.1).set_ease(Tween.EASE_IN)
		drift.tween_callback(words.queue_free)
	shown_coins = _coins()
	if note != "": _toast(note,note_tone)
	note = ""
	note_tone = Px.IVORY

func _toast(words: String, tone: Color) -> void:
	for old in floats.get_children():
		if old.has_meta("toast"): old.queue_free()
	var wide := Px.width_of(words)+40
	var slip := Control.new()
	slip.set_meta("toast",true)
	slip.mouse_filter = MOUSE_FILTER_IGNORE
	slip.size = Vector2(wide,26)
	slip.position = Vector2(roundf(460-wide*.5),-6)
	slip.modulate.a = 0.0
	floats.add_child(slip)
	Px.block(slip,Rect2(0,0,wide,26),Color(Px.CLAY_DARK,.96))
	Px.block(slip,Rect2(0,25,wide,1),tone)
	Px.block(slip,Rect2(0,0,2,26),tone)
	Px.text(slip,words,Rect2(0,7,wide,0),Px.BODY,tone,HORIZONTAL_ALIGNMENT_CENTER)
	var pass_by := slip.create_tween()
	pass_by.tween_property(slip,"position:y",9.0,.18).set_ease(Tween.EASE_OUT)
	pass_by.parallel().tween_property(slip,"modulate:a",1.0,.18)
	pass_by.tween_interval(2.2)
	pass_by.tween_property(slip,"modulate:a",0.0,.35)
	pass_by.tween_callback(slip.queue_free)

# --- The camp, with nothing open ----------------------------------------------------

func _home() -> void:
	var stops: Array[Button] = []
	for person: Dictionary in PEOPLE:
		# A sign over each head; pressing it, or the figure under it, opens their screen.
		var sign := Control.new()
		sign.size = Vector2(112,150)
		sign.mouse_filter = MOUSE_FILTER_IGNORE
		sign.set_meta("key",person.key)
		signs.add_child(sign)
		Px.block(sign,Rect2(0,0,112,34),Color(Px.INK,.82))
		Px.block(sign,Rect2(0,0,112,1),Color(Px.OCHRE,.6))
		Px.picture(sign,Px.icon(person.icon,16),Rect2(8,9,16,16)).modulate = Px.OCHRE
		Px.text(sign,person.service,Rect2(30,4,80,0),Px.BODY,Px.IVORY)
		var under := "%s · %s" % [person.name,person.role]
		if person.key == "march":
			# The guide's sign says where the road goes next.
			var ahead := _site(str(entry.get("id","1-1")))
			if not ahead.is_empty(): under = "%s %s" % [ahead.id,ahead.name]
		Px.text(sign,under,Rect2(30,20,80,0),Px.SMALL,Px.OCHRE if person.key == "march" else Px.MUTED)
		stops.append(Px.hotspot(sign,Rect2(0,0,112,150),_go.bind(person.key),person.service))
	Px.chain(stops,false)
	for stop in stops:
		stop.focus_neighbor_top = stop.get_path_to(tabs_row[0])
	tabs_row[0].focus_neighbor_bottom = tabs_row[0].get_path_to(stops[0])
	if asking == "": _focus(stops[PEOPLE.size()-1])

## The strip over a screen: who you are dealing with and what they say, and the way back.
func _head(title: String, over: String, words: String, face: Texture2D, sheets := true) -> void:
	Px.sheet(body,HEAD,.92)
	var x := HEAD.position.x+14
	if face != null:
		Px.picture(body,face,Rect2(x,HEAD.position.y+8,32,32))
		x += 42
	Px.text(body,title,Rect2(x,HEAD.position.y+7,100,0),Px.BODY,Px.IVORY)
	Px.text(body,over,Rect2(x,HEAD.position.y+25,100,0),Px.SMALL,Px.OCHRE)
	if words != "":
		Px.rule(body,Vector2(x+76,HEAD.position.y+10),28,Color(Px.OCHRE,.35),true)
		Px.text(body,words,Rect2(x+88,HEAD.position.y+8,HEAD.end.x-x-88-92,0),Px.SMALL,Px.MUTED)
	if screen != "party":
		tabs_row.append(Px.button(body,"回营地",Rect2(HEAD.end.x-78,HEAD.position.y+10,66,28),_go.bind("home")))
	if sheets:
		Px.sheet(body,LIST,.92)
		Px.sheet(body,DETAIL,.92)

func _person_head(key: String) -> void:
	for person: Dictionary in PEOPLE:
		if person.key == key:
			_head(person.name,person.role,_story(key),Px.face(person.look,32),key != "trader")

## A scrolling area of `height` content pixels. Returns the control to draw into.
func _scroll(key: String, rect: Rect2, height: float) -> Control:
	var inner := Px.scroll(body,rect,height)
	var area := inner.get_parent() as ScrollContainer
	area.scroll_vertical = int(scrolls.get(key,0))
	(func():
		if is_instance_valid(area): area.scroll_vertical = int(scrolls.get(key,0))).call_deferred()
	area.get_v_scroll_bar().value_changed.connect(func(value: float): scrolls[key] = value)
	return inner

## The left-hand list. `rows` are [key, title, subtitle, icon, tint]; `chosen` is the open key.
func _list(heading: String, rows: Array, chosen: Variant, pick: Callable, foot := 0.0) -> Array[Button]:
	Px.text(body,heading,Rect2(LIST.position+Vector2(14,10),Vector2(190,0)),Px.SMALL,Px.OCHRE)
	Px.rule(body,LIST.position+Vector2(14,26),LIST.size.x-28)
	var buttons: Array[Button] = []
	var inner := _scroll("list/"+screen+view,Rect2(LIST.position.x+2,LIST.position.y+32,LIST.size.x-4,LIST.size.y-38-foot),rows.size()*46.0)
	var y := 2.0
	for item: Array in rows:
		var open: bool = chosen == item[0]
		var button := Px.row(inner,"",Rect2(4,y,LIST.size.x-18,42),open,pick.bind(item[0]))
		if item[3] != null:
			Px.picture(inner,item[3],Rect2(14,y+5,32,32)).modulate = item[4]
		var ink: Color = item[5] if item.size() > 5 else Px.IVORY
		Px.text(inner,item[1],Rect2(54,y+5,146,0),Px.BODY,ink if open else ink.darkened(.25))
		Px.text(inner,item[2],Rect2(54,y+23,146,0),Px.SMALL,Px.OCHRE if open else Px.FAINT)
		if item.size() > 6 and int(item[6]) > 0: _price(inner,int(item[6]),Vector2(LIST.size.x-24,y+23),true)
		buttons.append(button)
		if open and asking == "": _focus(button)
		y += 46
	Px.chain(buttons)
	if not buttons.is_empty() and not tabs_row.is_empty():
		buttons[0].focus_neighbor_top = buttons[0].get_path_to(tabs_row[-1])
		tabs_row[-1].focus_neighbor_bottom = tabs_row[-1].get_path_to(buttons[0])
	return buttons

func _title(title: String, over: String, icon: Texture2D = null, tint := Color.WHITE) -> float:
	var x := DETAIL.position.x+20
	if icon != null:
		Px.picture(body,icon,Rect2(x,DETAIL.position.y+14,48,48)).modulate = tint
		x += 60
	Px.text(body,over,Rect2(x,DETAIL.position.y+14,380,0),Px.SMALL,Px.OCHRE)
	Px.text(body,title,Rect2(x,DETAIL.position.y+30,380,0),Px.TITLE,Px.IVORY)
	return DETAIL.position.y+76

func _link(rows: Array, target: Button, at: int) -> void:
	if target == null or rows.is_empty(): return
	for row: Button in rows: row.focus_neighbor_right = row.get_path_to(target)
	target.focus_neighbor_left = target.get_path_to(rows[clampi(at,0,rows.size()-1)])

func _stats(sheet: Dictionary, at: Vector2, with_divinity := true) -> void:
	var stats := [["heart","生命",sheet.get("max_hp",sheet.get("hp",0))],["strength","力量",sheet.get("str",0)],["armor","防御",sheet.get("def",0)],
		["will","意志",sheet.get("wil",0)],["boot","移动",sheet.get("move",0)],["jump","跳跃",sheet.get("jump",0)]]
	if with_divinity: stats.insert(4,["divinity","神性",sheet.get("div",0)])
	for i in stats.size():
		var spot := Vector2(at.x+(i%4)*108,at.y+(i/4)*30)
		Px.picture(body,Px.icon(stats[i][0],16),Rect2(spot,Vector2(16,16))).modulate = Px.OCHRE
		Px.text(body,stats[i][1],Rect2(spot+Vector2(22,1),Vector2(40,0)),Px.BODY,Px.MUTED)
		Px.text(body,str(stats[i][2]),Rect2(spot+Vector2(56,1),Vector2(40,0)),Px.BODY,Px.IVORY)

# --- 队伍：一个角色的全部 -----------------------------------------------------------

func _party() -> void:
	var everyone := _everyone()
	if not everyone.has(member): member = "hero"
	_head("队伍","%d 人在营" % everyone.size(),"",null,view != "pack")
	# Two ways in: by person, or by thing.
	var ways: Array[Button] = []
	for i in 2:
		var key: String = ["members","pack"][i]
		ways.append(Px.tab(body,["成员","行囊"][i],Rect2(HEAD.position.x+110+i*84,HEAD.position.y+12,76,26),view == key,_pick_view.bind(key)))
	Px.chain(ways,false)
	for way in ways: way.focus_neighbor_top = way.get_path_to(tabs_row[0])
	tabs_row[0].focus_neighbor_bottom = tabs_row[0].get_path_to(ways[0])
	tabs_row.append(ways[0 if view == "members" else 1])
	if view == "pack":
		_pack()
		return
	var going := _marching()
	var rows_data := []
	for who: String in everyone:
		var sub := "出战" if who == "hero" or going.has(who) else "留守"
		if _tree_of(who) != "":
			var spare := _budget(who)-SkillTree.cost(_tree_of(who),entry.get("picks",{}).get(who,[]))
			if spare > 0: sub += " · 余 %d 点" % spare
		var grade := _rarity(who)
		if grade.is_empty():
			rows_data.append([who,_name(who),sub,Px.face(_look(who),32),Color.WHITE])
		else:
			rows_data.append([who,_name(who),"%s · %s" % [grade[0],sub],Px.face(_look(who),32),Color.WHITE,grade[1]])
	var rows := _list("成员",rows_data,member,_pick_member)
	_sheet(rows)

func _pick_view(which: String) -> void:
	view = which
	_reframe()
	_render()

func _pick_member(who: String) -> void:
	member = who
	technique = ""
	candidate = ""
	skill_pick = ""
	_reframe()
	_render()

## What the things a member wears add up to, as {stat: change}. `trying` is a thing to
## count as worn in place of whatever sits in its place now.
func _worn_changes(who: String, trying := "") -> Dictionary:
	var wearing := _worn(who).duplicate()
	if trying != "": wearing[Save.GOODS[trying].slot] = trying
	var total := {}
	for where: String in wearing:
		var mods: Dictionary = Save.GOODS[wearing[where]].get("mods",{})
		for stat: String in mods: total[stat] = int(total.get(stat,0))+int(mods[stat])
	return total

## The lines a thing would change on a member's sheet, as [[stat name, now, then]].
func _would_change(who: String, item: String) -> Array:
	var base: Dictionary = UnitCatalog.unit_def(_def(who))
	var now := _worn_changes(who)
	var then := _worn_changes(who,item)
	var lines := []
	for stat: String in Save.STAT_NAMES:
		if int(now.get(stat,0)) == int(then.get(stat,0)): continue
		var plain := int(base.get("max_hp",base.get("hp",0))) if stat == "hp" else int(base.get(stat,0))
		lines.append([Save.STAT_NAMES[stat],plain+int(now.get(stat,0)),plain+int(then.get(stat,0))])
	return lines

## The plain attack every member has. It is always taken into battle.
func _basic(who: String) -> String:
	var innate: Array = UnitCatalog.unit_def(_def(who)).get("skills",[])
	return str(innate[0]) if not innate.is_empty() else ""

## What a member carries in their two pockets.
func _kit(who: String) -> Array:
	return _purse().kit.get(who,[])

## Every technique a member could choose to take into battle: those they came with beyond
## the plain attack, then those learnt.
func _known(who: String) -> Array:
	var known: Array = UnitCatalog.unit_def(_def(who)).get("skills",[]).slice(1)
	var own := str(_kind(who).get("skill",""))
	if own != "": known.append(own)
	var learned: Array = entry.get("picks",{}).get(who,[])
	for branch: Dictionary in SkillTree.trees().get(_tree_of(who),[]):
		for node: Dictionary in branch.nodes:
			var grants := str(node.get("skill",""))
			if learned.has(node.id) and grants != "" and not known.has(grants): known.append(grants)
	return known

## The techniques a member takes into battle, at most CARRY. Until the player chooses,
## it is the first ones they know.
func _carried(who: String) -> Array:
	var known := _known(who)
	var stored: Variant = entry.get("loadout",{}).get(who)
	if stored == null: return known.slice(0,CARRY)
	return (stored as Array).filter(func(id): return known.has(id)).slice(0,CARRY)

func _carry(list: Array) -> void:
	var next: Dictionary = entry.duplicate(true)
	if not next.has("loadout"): next.loadout = {}
	next.loadout[member] = list
	if _keep(next): note = _name(member)+"的出战招式已换好。"
	_render()

## The tree node that teaches a technique, or {} for one the member came with.
func _teacher(who: String, id: String) -> Dictionary:
	for branch: Dictionary in SkillTree.trees().get(_tree_of(who),[]):
		for node: Dictionary in branch.nodes:
			if str(node.get("skill","")) == id: return node
	return {}

func _skill_mark(who: String, id: String, size: int) -> Texture2D:
	var node := _teacher(who,id)
	return _mark(node if not node.is_empty() else {"id":id},size)

## Reach and cooldown in a few words.
func _skill_brief(id: String) -> String:
	var skill: Dictionary = SkillCatalog.get_skill(id)
	var near := int(skill.get("min_range",1))
	var far := int(skill.get("max_range",1))
	var words := "射程 %d" % near if near == far else "射程 %d–%d" % [near,far]
	if int(skill.get("cooldown",0)) > 0: words += " · 冷却 %d" % int(skill.cooldown)
	return words

func _skill_words(who: String, id: String) -> String:
	var node := _teacher(who,id)
	if not node.is_empty(): return str(node.desc)
	var skill: Dictionary = SkillCatalog.get_skill(id)
	var words := "%s 倍%s伤害" % [str(skill.get("mult",1)),"神性" if int(skill.get("type",0)) == Defs.DamageType.DIVINE else "物理"]
	if int(skill.get("knockback",0)) > 0: words += "，击退 %d 格" % int(skill.knockback)
	return words+"。随身的招式，不必修习。"

func _pick_page(which: String) -> void:
	page = which
	_render()

func _pick_pocket(index: int) -> void:
	kit_at = index
	open = "kit"
	kit_pick = ""
	_render()

func _pick_kit(item: String) -> void:
	kit_pick = item
	_render()

## Puts a thing in one of a member's pockets, or empties it when `item` is "".
func _pocket(who: String, index: int, item: String) -> void:
	if item != "" and Save.loose(_purse(),item) <= 0: return
	var next: Dictionary = entry.duplicate(true)
	var kit: Array = next.purse.kit.get(who,[])
	if index < kit.size():
		if item == "": kit.remove_at(index)
		else: kit[index] = item
	elif item != "" and kit.size() < Save.KIT_SLOTS:
		kit.append(item)
	next.purse.kit[who] = kit
	if _keep(next): note = "%s带上了%s。" % [_name(who),Save.GOODS[item].name] if item != "" else "已放回行囊。"
	_render()

func _pick_slot(index: int) -> void:
	slot_at = index
	open = "skill"
	skill_pick = ""
	_render()

func _pick_skill(id: String) -> void:
	skill_pick = id
	_render()

## One member: who they are, then two pages. "信息" holds their numbers, what they wear and
## the techniques they take into battle; "技能树" is where techniques are learnt.
func _sheet(rows: Array) -> void:
	var x := DETAIL.position.x+20
	var wide := DETAIL.size.x-40
	var y := DETAIL.position.y+12
	var grade := _rarity(member)
	Px.text(body,_name(member),Rect2(x,y,260,0),Px.TITLE,grade[1] if not grade.is_empty() else Px.IVORY)
	var after_name := x+Px.width_of(_name(member),Px.TITLE)+10
	Px.text(body,_role(member),Rect2(after_name,y+12,160,0),Px.SMALL,Px.OCHRE)
	if not grade.is_empty():
		Px.text(body,grade[0],Rect2(after_name+Px.width_of(_role(member),Px.SMALL)+10,y+12,60,0),Px.SMALL,grade[1])
	var marching := member == "hero" or _marching().has(member)
	Px.text(body,"出战" if marching else "留守营地",Rect2(x+wide-120,y+2,120,0),Px.SMALL,Px.GREEN if marching else Px.FAINT,HORIZONTAL_ALIGNMENT_RIGHT)
	# Their level, and how far along the next one they are.
	var rank := Save.standing(_xp(member))
	Px.text(body,"等级 %d" % rank.level,Rect2(x+wide-150,y+16,60,0),Px.SMALL,Px.OCHRE,HORIZONTAL_ALIGNMENT_RIGHT)
	Px.block(body,Rect2(x+wide-84,y+19,84,5),Color(Px.IVORY,.12))
	Px.block(body,Rect2(x+wide-84,y+19,roundf(84.0*rank.into/rank.need),5),Px.OCHRE)
	y += 30
	var root := _tree_of(member)
	if root == "": page = "info"
	var leaves: Array[Button] = []
	leaves.append(Px.tab(body,"信息",Rect2(x,y,64,24),page == "info",_pick_page.bind("info")))
	leaves.append(Px.tab(body,"技能树",Rect2(x+68,y,64,24),page == "tree",_pick_page.bind("tree")))
	Px.chain(leaves,false)
	if root == "":
		leaves[1].disabled = true
		leaves[1].tooltip_text = "只用随身的招式，没有可修习的分支。"
		Px.text(body,"没有可修习的分支",Rect2(x+140,y+8,160,0),Px.SMALL,Px.FAINT)
	else:
		var spare := _budget(member)-SkillTree.cost(root,entry.get("picks",{}).get(member,[]))
		Px.text(body,"余 %d 点" % spare,Rect2(x+wide-80,y+8,80,0),Px.SMALL,Px.GREEN if spare > 0 else Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	for row: Button in rows: row.focus_neighbor_right = row.get_path_to(leaves[0 if page == "info" else 1])
	for leaf in leaves: leaf.focus_neighbor_left = leaf.get_path_to(rows[_everyone().find(member)])
	y += 26
	Px.rule(body,Vector2(x,y),wide,Color(Px.OCHRE,.3))
	y += 8
	if page == "tree": _tree_page(rows,leaves,Vector2(x,y),wide)
	else: _info_page(rows,leaves,Vector2(x,y),wide)

func _info_page(rows: Array, leaves: Array, at: Vector2, wide: float) -> void:
	var purse := _purse()
	var base: Dictionary = UnitCatalog.unit_def(_def(member))
	var x := at.x
	var y := at.y
	var whose: Button = rows[_everyone().find(member)]
	# Their numbers, with what they wear counted in, and what the charm being weighed would do.
	var worn := _worn(member)
	# What could go in the open place: what is on now, then whatever lies free in the bag.
	var fitting: Array = _in_order(purse.bag.keys().filter(func(item):
		return Save.GOODS[item].slot == place and worn.get(place,"") != item and Save.loose(purse,item) > 0))
	if worn.has(place): fitting.push_front(worn[place])
	if open == "gear" and not fitting.has(candidate): candidate = "" if fitting.is_empty() else fitting[0]
	var now := _worn_changes(member)
	var weighing: bool = open == "gear" and candidate != "" and worn.get(place,"") != candidate
	var then := _worn_changes(member,candidate) if weighing else now
	var stats := [["heart","生命","hp"],["strength","力量","str"],["armor","防御","def"],["will","意志","wil"],["divinity","神性","div"],["boot","移动","move"],["jump","跳跃","jump"]]
	for i in stats.size():
		var key: String = stats[i][2]
		var plain := int(base.get("max_hp",base.get("hp",0))) if key == "hp" else int(base.get(key,0))
		var value: int = plain+int(now.get(key,0))
		var after: int = plain+int(then.get(key,0))
		var spot := Vector2(x+(i%4)*108,y+(i/4)*24)
		Px.picture(body,Px.icon(stats[i][0],16),Rect2(spot,Vector2(16,16))).modulate = Px.OCHRE
		Px.text(body,stats[i][1],Rect2(spot+Vector2(22,1),Vector2(40,0)),Px.BODY,Px.MUTED)
		var tone := Px.GREEN if value > plain else (Px.RED.lightened(.4) if value < plain else Px.IVORY)
		Px.text(body,str(value),Rect2(spot+Vector2(54,1),Vector2(24,0)),Px.BODY,tone)
		if after != value:
			Px.text(body,"→%d" % after,Rect2(spot+Vector2(54+Px.width_of(str(value))+2,1),Vector2(40,0)),Px.BODY,Px.GREEN if after > value else Px.RED.lightened(.4))
	y += 50
	Px.rule(body,Vector2(x,y),wide,Color(Px.OCHRE,.2))
	y += 6
	# What they wear, on the left.
	Px.text(body,"装备",Rect2(x,y,40,0),Px.SMALL,Px.OCHRE)
	var bag := Px.row(body,"",Rect2(x+92,y-4,52,18),false,_pick_view.bind("pack"),Px.SMALL)
	bag.tooltip_text = "按物品查看整个行囊"
	Px.text(body,"行囊 >",Rect2(x+92,y,48,0),Px.SMALL,Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	var places: Array[Button] = []
	for i in Save.SLOTS.size():
		var key: String = Save.SLOTS[i][0]
		var spot := Vector2(x-6,y+16+i*25)
		var button := Px.row(body,"",Rect2(spot,Vector2(150,23)),open == "gear" and place == key,_pick_place.bind(key))
		Px.text(body,Save.SLOTS[i][1],Rect2(spot+Vector2(8,6),Vector2(34,0)),Px.SMALL,Px.OCHRE)
		if worn.has(key):
			Px.picture(body,Px.icon(Save.art(worn[key]),16),Rect2(spot+Vector2(42,3),Vector2(16,16))).modulate = _tint(worn[key])
			Px.text(body,Save.GOODS[worn[key]].name,Rect2(spot+Vector2(62,5),Vector2(88,0)),Px.BODY,_tint(worn[key]))
		else:
			Px.text(body,"空",Rect2(spot+Vector2(42,5),Vector2(88,0)),Px.BODY,Px.FAINT)
		places.append(button)
	# Two pockets for things used up in battle.
	var kit := _kit(member)
	for i in Save.KIT_SLOTS:
		var spot := Vector2(x-6,y+16+(Save.SLOTS.size()+i)*25)
		var button := Px.row(body,"",Rect2(spot,Vector2(150,23)),open == "kit" and kit_at == i,_pick_pocket.bind(i))
		Px.text(body,"物品",Rect2(spot+Vector2(8,6),Vector2(34,0)),Px.SMALL,Px.OCHRE)
		if i < kit.size():
			Px.picture(body,Px.icon(Save.art(kit[i]),16),Rect2(spot+Vector2(42,3),Vector2(16,16))).modulate = _tint(kit[i])
			Px.text(body,Save.GOODS[kit[i]].name,Rect2(spot+Vector2(62,5),Vector2(88,0)),Px.BODY,_tint(kit[i]))
		else:
			Px.text(body,"空",Rect2(spot+Vector2(42,5),Vector2(88,0)),Px.BODY,Px.FAINT)
		places.append(button)
	Px.chain(places)
	places[0].focus_neighbor_top = places[0].get_path_to(leaves[0])
	leaves[0].focus_neighbor_bottom = leaves[0].get_path_to(places[0])
	leaves[1].focus_neighbor_bottom = leaves[1].get_path_to(places[0])
	for button in places: button.focus_neighbor_left = button.get_path_to(whose)
	Px.rule(body,Vector2(x+154,y),166,Color(Px.OCHRE,.2),true)
	# The techniques they take into battle, on the right.
	var left := x+166
	var known := _known(member)
	var carried := _carried(member)
	Px.text(body,"攻击与技能",Rect2(left,y,80,0),Px.SMALL,Px.OCHRE)
	# The plain attack: always there, not one of the four.
	var strike := _basic(member)
	if strike != "":
		var line := Vector2(left-6,y+16)
		Px.picture(body,_skill_mark(member,strike,16),Rect2(line+Vector2(8,3),Vector2(16,16))).modulate = Px.MUTED
		Px.text(body,"攻击",Rect2(line+Vector2(30,5),Vector2(40,0)),Px.BODY,Px.MUTED)
		Px.text(body,str(SkillCatalog.get_skill(strike).get("name",strike))+" · "+_skill_brief(strike),Rect2(line+Vector2(wide-160-166,7),Vector2(158,0)),Px.SMALL,Px.FAINT,HORIZONTAL_ALIGNMENT_RIGHT)
	var count := "技能 %d / %d" % [carried.size(),CARRY]
	if known.size() > carried.size(): count = "另会 %d 招 · " % (known.size()-carried.size())+count
	Px.text(body,count,Rect2(x+wide-140,y,140,0),Px.SMALL,Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	var slots: Array[Button] = []
	for i in CARRY:
		var spot := Vector2(left-6,y+16+(i+1)*25)
		var button := Px.row(body,"",Rect2(spot,Vector2(wide-160,23)),open == "skill" and slot_at == i,_pick_slot.bind(i))
		if i < carried.size():
			Px.picture(body,_skill_mark(member,carried[i],16),Rect2(spot+Vector2(8,3),Vector2(16,16))).modulate = Px.IVORY
			Px.text(body,str(SkillCatalog.get_skill(carried[i]).get("name",carried[i])),Rect2(spot+Vector2(30,5),Vector2(120,0)),Px.BODY,Px.IVORY)
			Px.text(body,_skill_brief(carried[i]),Rect2(spot+Vector2(wide-160-116,7),Vector2(108,0)),Px.SMALL,Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			Px.text(body,"空",Rect2(spot+Vector2(30,5),Vector2(80,0)),Px.BODY,Px.FAINT)
		slots.append(button)
	Px.chain(slots)
	for i in CARRY:
		slots[i].focus_neighbor_left = slots[i].get_path_to(places[i])
		places[i].focus_neighbor_right = places[i].get_path_to(slots[i])
	y += 170
	# What is always on: traits learnt, and what the hero carries from the gods.
	var always: Array = []
	var learned: Array = entry.get("picks",{}).get(member,[])
	for branch: Dictionary in SkillTree.trees().get(_tree_of(member),[]):
		for node: Dictionary in branch.nodes:
			if learned.has(node.id) and str(node.get("skill","")) == "": always.append(str(node.name))
	if member == "hero" and entry.has("equipped_relic"):
		always.append("圣物 涅墨亚狮皮")
		if entry.get("boon","") != "": always.append("神赐 "+str(Save.BOONS[entry.boon][1]))
	Px.text(body,"特性",Rect2(x,y,34,0),Px.SMALL,Px.OCHRE)
	Px.text(body,"、".join(always) if not always.is_empty() else "还没有",Rect2(x+34,y,wide-34,0),Px.SMALL,Px.IVORY if not always.is_empty() else Px.FAINT)
	y += 28
	Px.rule(body,Vector2(x,y),wide,Color(Px.OCHRE,.3))
	y += 6
	# The foot: whatever was pressed above, and the one thing to do about it.
	var act: Button
	var act_at := Rect2(DETAIL.end.x-20-136,DETAIL.end.y-40,136,28)
	if open == "skill":
		if known.is_empty():
			Px.text(body,"除了攻击，还没有别的技能。到「技能树」里学。",Rect2(x,y+4,wide,0),Px.SMALL,Px.FAINT)
			if asking == "": _focus(slots[slot_at])
			return
		if not known.has(skill_pick):
			var spare: Array = known.filter(func(id): return not carried.has(id))
			skill_pick = carried[slot_at] if slot_at < carried.size() else (spare[0] if not spare.is_empty() else known[0])
		Px.text(body,"第 %s 格 · 会 %d 招" % [NUMERALS[slot_at],known.size()],Rect2(x,y,200,0),Px.SMALL,Px.OCHRE)
		var inner := _scroll("carry/"+member,Rect2(x-6,y+16,206,DETAIL.end.y-y-26),known.size()*24.0)
		var choices: Array[Button] = []
		for i in known.size():
			var id: String = known[i]
			var choice := Px.row(inner,"",Rect2(0,i*24,198,22),skill_pick == id,_pick_skill.bind(id),Px.SMALL)
			Px.picture(inner,_skill_mark(member,id,16),Rect2(8,i*24+3,16,16)).modulate = Px.OCHRE if carried.has(id) else Px.IVORY
			Px.text(inner,str(SkillCatalog.get_skill(id).get("name",id)),Rect2(30,i*24+6,100,0),Px.SMALL,Px.IVORY)
			Px.text(inner,"出战中" if carried.has(id) else "",Rect2(118,i*24+6,74,0),Px.SMALL,Px.GREEN,HORIZONTAL_ALIGNMENT_RIGHT)
			choices.append(choice)
		Px.chain(choices)
		var side := x+212
		Px.text(body,_skill_brief(skill_pick),Rect2(side,y,wide-212,0),Px.SMALL,Px.OCHRE)
		Px.text(body,_skill_words(member,skill_pick),Rect2(side,y+16,wide-212,0),Px.SMALL,Px.IVORY)
		var next := carried.duplicate()
		if carried.has(skill_pick):
			next.erase(skill_pick)
			act = Px.button(body,"卸下",act_at,_carry.bind(next))
		elif carried.size() < CARRY:
			next.append(skill_pick)
			act = Px.primary(body,"装上",act_at,_carry.bind(next))
		else:
			var out: int = mini(slot_at,carried.size()-1)
			next[out] = skill_pick
			act = Px.primary(body,"换下"+str(SkillCatalog.get_skill(carried[out]).get("name",carried[out])),act_at,_carry.bind(next))
		for choice in choices: choice.focus_neighbor_right = choice.get_path_to(act)
		act.focus_neighbor_left = act.get_path_to(choices[known.find(skill_pick)])
		slots[-1].focus_neighbor_bottom = slots[-1].get_path_to(choices[0])
		if asking == "": _focus(choices[known.find(skill_pick)])
	elif open == "kit":
		# What could go in the open pocket: what is in it now, then whatever lies loose in the bag.
		var holding: String = kit[kit_at] if kit_at < kit.size() else ""
		var loose_things: Array = _in_order(purse.bag.keys().filter(func(item): return Save.GOODS[item].slot == "item" and Save.loose(purse,item) > 0))
		var offered: Array = ([holding] if holding != "" else [])+loose_things.filter(func(item): return item != holding)
		Px.text(body,"随身物品 · 每人 %d 件，用掉就没了" % Save.KIT_SLOTS,Rect2(x,y,260,0),Px.SMALL,Px.OCHRE)
		if offered.is_empty():
			Px.text(body,"行囊里没有能带的物品。阿齐尔那里有卖。",Rect2(x,y+22,wide,0),Px.SMALL,Px.FAINT)
			if asking == "": _focus(places[Save.SLOTS.size()+kit_at])
			return
		if not offered.has(kit_pick): kit_pick = offered[0]
		var inner := _scroll("kit/"+member,Rect2(x-6,y+16,206,DETAIL.end.y-y-26),offered.size()*24.0)
		var choices: Array[Button] = []
		for i in offered.size():
			var item: String = offered[i]
			var held: bool = item == holding
			var choice := Px.row(inner,"",Rect2(0,i*24,198,22),kit_pick == item,_pick_kit.bind(item),Px.SMALL)
			Px.picture(inner,Px.icon(Save.art(item),16),Rect2(8,i*24+3,16,16)).modulate = _tint(item)
			Px.text(inner,Save.GOODS[item].name,Rect2(30,i*24+6,100,0),Px.SMALL,_tint(item))
			Px.text(inner,"带着" if held else "×%d" % Save.loose(purse,item),Rect2(118,i*24+6,74,0),Px.SMALL,Px.GREEN if held else Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
			choices.append(choice)
		Px.chain(choices)
		Px.text(body,Save.effect_of(kit_pick),Rect2(x+212,y,wide-212,0),Px.SMALL,Px.IVORY)
		if kit_pick == holding:
			act = Px.button(body,"取下",act_at,_pocket.bind(member,kit_at,""))
		else:
			act = Px.primary(body,"带上" if holding == "" else "换上",act_at,_pocket.bind(member,kit_at,kit_pick))
		for choice in choices: choice.focus_neighbor_right = choice.get_path_to(act)
		act.focus_neighbor_left = act.get_path_to(choices[offered.find(kit_pick)])
		if asking == "": _focus(choices[offered.find(kit_pick)])
	elif open == "gear":
		Px.text(body,"%s · %d 件可用" % [Save.slot_name(place),fitting.size()],Rect2(x,y,200,0),Px.SMALL,Px.OCHRE)
		if fitting.is_empty():
			Px.text(body,"行囊里没有戴在这里的东西。阿齐尔那里也许有卖。",Rect2(x,y+22,wide,0),Px.SMALL,Px.FAINT)
			if asking == "": _focus(places[maxi(0,Save.SLOTS.find_custom(func(slot): return slot[0] == place))])
			return
		var inner := _scroll("gear/"+place,Rect2(x-6,y+16,206,DETAIL.end.y-y-26),fitting.size()*24.0)
		var choices: Array[Button] = []
		for i in fitting.size():
			var item: String = fitting[i]
			var on: bool = worn.get(place,"") == item
			var choice := Px.row(inner,"",Rect2(0,i*24,198,22),candidate == item,_pick_candidate.bind(item),Px.SMALL)
			Px.picture(inner,Px.icon(Save.art(item),16),Rect2(8,i*24+3,16,16)).modulate = _tint(item)
			Px.text(inner,Save.GOODS[item].name,Rect2(30,i*24+6,100,0),Px.SMALL,_tint(item))
			Px.text(inner,"佩戴中" if on else "×%d" % Save.loose(purse,item),Rect2(118,i*24+6,74,0),Px.SMALL,Px.GREEN if on else Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
			choices.append(choice)
		Px.chain(choices)
		places[-1].focus_neighbor_bottom = places[-1].get_path_to(choices[0])
		var current: String = worn.get(place,"")
		var mine := current == candidate
		var side := x+212
		Px.text(body,"现在" if mine else "得到",Rect2(side,y,34,0),Px.SMALL,Px.GREEN)
		Px.text(body,Save.effect_of(candidate),Rect2(side+34,y,wide-246,0),Px.SMALL,Px.IVORY)
		if not mine and current != "":
			Px.text(body,"失去",Rect2(side,y+22,34,0),Px.SMALL,Px.RED.lightened(.4))
			Px.text(body,Save.effect_of(current),Rect2(side+34,y+22,wide-246,0),Px.SMALL,Px.MUTED)
		if mine:
			act = Px.button(body,"卸下",act_at,_strip.bind(member,place))
		else:
			act = Px.primary(body,"戴上",act_at,_wear.bind(candidate,member))
		for choice in choices: choice.focus_neighbor_right = choice.get_path_to(act)
		act.focus_neighbor_left = act.get_path_to(choices[fitting.find(candidate)])
		if asking == "": _focus(choices[fitting.find(candidate)])
	else:
		# Nothing open: who this is.
		var kind := _kind(member)
		Px.text(body,"身世",Rect2(x,y,60,0),Px.SMALL,Px.OCHRE)
		Px.text(body,str(kind.lore) if not kind.is_empty() else str(LORE.get(member,"")),Rect2(x,y+18,wide,0),Px.BODY,Px.MUTED)
		Px.text(body,"点一个部位、一格技能或一个物品格来更换。",Rect2(x,DETAIL.end.y-28,wide,0),Px.SMALL,Px.FAINT)
		if asking == "": _focus(whose)

## Lays a branch out as a tree: tips spread left to right, each parent over the middle of
## its children. Fills `spots` with {id: Vector2(column, level)} and returns the column.
func _place(nodes: Array, id: String, level: int, spots: Dictionary, tips: Array) -> float:
	var kids: Array = nodes.filter(func(n): return n.parent == id)
	var column := 0.0
	if kids.is_empty():
		column = tips.size()
		tips.append(id)
	else:
		for kid: Dictionary in kids: column += _place(nodes,kid.id,level+1,spots,tips)
		column /= kids.size()
	spots[id] = Vector2(column,level)
	return column

func _tree_page(rows: Array, leaves: Array, at: Vector2, wide: float) -> void:
	var x := at.x
	var y := at.y
	var root := _tree_of(member)
	var budget := _budget(member)
	var learned: Array = entry.get("picks",{}).get(member,[])
	var remaining := budget-SkillTree.cost(root,learned)
	var branches: Array = SkillTree.trees()[root]
	var by_id := {}
	var branch_of := {}
	for branch: Dictionary in branches:
		for node: Dictionary in branch.nodes:
			by_id[node.id] = node
			branch_of[node.id] = branch.branch
	if not by_id.has(technique): technique = str(branches[0].nodes[0].id)
	var cells: Array[Button] = []
	var ids: Array = []
	var half := (wide-10)/branches.size()
	var box := Vector2(92,36)
	for arm in branches.size():
		var branch: Dictionary = branches[arm]
		var origin: float = x+arm*(half+10)
		Px.text(body,branch.branch,Rect2(origin,y,half,0),Px.SMALL,Px.OCHRE,HORIZONTAL_ALIGNMENT_CENTER)
		var spots := {}
		var tips: Array = []
		for node: Dictionary in branch.nodes:
			if node.parent == "": _place(branch.nodes,node.id,0,spots,tips)
		var corner := func(id: String) -> Vector2:
			return Vector2(roundf(origin+half*(spots[id].x+.5)/tips.size()-box.x*.5),y+18+spots[id].y*52)
		# The lines first, so the boxes sit on top of them.
		for node: Dictionary in branch.nodes:
			if node.parent == "": continue
			var from: Vector2 = corner.call(node.parent)+Vector2(box.x*.5,box.y)
			var to: Vector2 = corner.call(node.id)+Vector2(box.x*.5,0)
			var tone := Px.GREEN if learned.has(node.id) else (Color(Px.OCHRE,.7) if learned.has(node.parent) else Color(Px.FAINT,.6))
			Px.block(body,Rect2(from.x,from.y,1,8),tone)
			Px.block(body,Rect2(minf(from.x,to.x),from.y+8,absf(to.x-from.x)+1,1),tone)
			Px.block(body,Rect2(to.x,from.y+8,1,to.y-from.y-8),tone)
		for node: Dictionary in branch.nodes:
			var have := learned.has(node.id)
			var ready: bool = node.parent == "" or learned.has(node.parent)
			var tint := Px.GREEN if have else (Px.IVORY if ready else Px.FAINT)
			var rect := Rect2(corner.call(node.id),box)
			Px.block(body,rect,Color(Px.INK,.9))
			Px.block(body,rect,Color(Px.GREEN,.16) if have else Color(Px.IVORY,.07 if ready else .03))
			var cell := Px.row(body,"",rect,technique == node.id,_pick_technique.bind(node.id),Px.SMALL)
			Px.picture(body,_mark(node,16),Rect2(rect.position+Vector2(box.x*.5-8,3),Vector2(16,16))).modulate = tint
			Px.text(body,node.name,Rect2(rect.position+Vector2(0,22),Vector2(box.x,0)),Px.SMALL,tint,HORIZONTAL_ALIGNMENT_CENTER)
			Px.text(body,"✓" if have else str(node.cost),Rect2(rect.position+Vector2(box.x-20,4),Vector2(16,0)),Px.SMALL,Px.GREEN if have else Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
			cells.append(cell)
			ids.append(node.id)
	Px.chain(cells)
	cells[0].focus_neighbor_top = cells[0].get_path_to(leaves[1])
	leaves[0].focus_neighbor_bottom = leaves[0].get_path_to(cells[0])
	leaves[1].focus_neighbor_bottom = leaves[1].get_path_to(cells[0])
	for cell in cells: cell.focus_neighbor_left = cell.get_path_to(rows[_everyone().find(member)])
	y += 18+3*52-10
	Px.rule(body,Vector2(x,y),wide,Color(Px.OCHRE,.3))
	y += 8
	# The foot: the technique chosen, and learning or handing it back.
	var chosen: Dictionary = by_id[technique]
	var grants := str(chosen.get("skill",""))
	Px.picture(body,_mark(chosen,32),Rect2(x,y,32,32)).modulate = Px.OCHRE
	Px.text(body,"%s · %s" % [branch_of[technique],"招式" if grants != "" else "特性"],Rect2(x+42,y,200,0),Px.SMALL,Px.OCHRE)
	Px.text(body,chosen.name,Rect2(x+42,y+14,200,0),Px.BODY,Px.IVORY)
	var parent_name: String = by_id[chosen.parent].name if chosen.parent != "" else "无"
	Px.text(body,"一开始就会" if Save.STARTERS.get(member,"") == technique else "前置 %s　花费 %d 点" % [parent_name,chosen.cost],Rect2(x+wide-200,y+2,200,0),Px.SMALL,Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	Px.text(body,chosen.desc,Rect2(x,y+38,wide,0),Px.SMALL,Px.IVORY)
	var has := learned.has(technique)
	var state := "学会后一直生效，不占出战格。" if grants == "" else "学会后要放进出战招式才能用，每人带 %d 招。" % CARRY
	if has and grants != "":
		state = "出战中。" if _carried(member).has(grants) else "没有带上：出战招式已满，到「信息」页更换。"
	Px.text(body,state,Rect2(x,DETAIL.end.y-32,wide-150,0),Px.SMALL,Px.GREEN if has and (grants == "" or _carried(member).has(grants)) else Px.FAINT)
	var next := learned.duplicate()
	if has: next.erase(technique)
	else: next.append(technique)
	var legal := SkillTree.validate(root,next,budget) == ""
	var label := "退还 %d 点" % chosen.cost if has else "学习"
	if not legal:
		label = "先退还后面的" if has else ("先学「"+parent_name+"」" if chosen.parent != "" and not learned.has(chosen.parent) else "还差 %d 点" % (chosen.cost-remaining))
	var starter: bool = Save.STARTERS.get(member,"") == technique
	if starter: label = "起始招式"
	var act := Px.primary(body,label,Rect2(DETAIL.end.x-20-136,DETAIL.end.y-40,136,28),_train.bind(next))
	act.disabled = not legal or starter
	cells[-1].focus_neighbor_bottom = cells[-1].get_path_to(act)
	if asking == "": _focus(cells[ids.find(technique)])

func _pick_technique(id: String) -> void:
	technique = id
	_render()

## The stamp for a technique: its own drawing if it has one, else the one for what it grants.
func _mark(node: Dictionary, size: int) -> Texture2D:
	for key: String in [str(node.id),str(node.get("skill","")),str(node.get("trait",""))]:
		if key != "" and ResourceLoader.exists("res://art/thirdparty/game-icons/%s.svg" % key): return Px.icon(key,size)
	return Px.icon("skills",size)

func _train(next: Array) -> void:
	if SkillTree.validate(_tree_of(member),next,_budget(member)) != "": return
	if Save.STARTERS.has(member) and not next.has(Save.STARTERS[member]): return
	# A technique just learnt goes straight into battle if there is a free slot.
	var carried := _carried(member)
	var updated: Dictionary = entry.duplicate(true)
	if not updated.has("picks"): updated.picks = {}
	for id: String in next:
		if (entry.get("picks",{}).get(member,[]) as Array).has(id): continue
		var grants := ""
		for branch: Dictionary in SkillTree.trees().get(_tree_of(member),[]):
			for node: Dictionary in branch.nodes:
				if node.id == id: grants = str(node.get("skill",""))
		if grants != "" and carried.size() < CARRY and not carried.has(grants): carried.append(grants)
	updated.picks[member] = next.duplicate()
	if not updated.has("loadout"): updated.loadout = {}
	updated.loadout[member] = carried
	if _keep(updated): note = _name(member)+"的修习已记下。"
	_render()

func _pick_candidate(item: String) -> void:
	candidate = item
	_render()

## Everything owned, as a grid: filter by place, see who wears what, hand a thing to someone.
## A grid of things, as the bag and the trader both show them. `things` are ids; `mark`
## gives each cell its corner text and `cost` its price (0 for none). Returns the cells.
func _grid(key: String, area: Rect2, things: Array, chosen: String, pick: Callable, columns: int, mark: Callable, cost: Callable) -> Array[Button]:
	var cell := Vector2(floorf(area.size.x/columns),58)
	var inner := _scroll(key,area,ceili(things.size()/float(columns))*cell.y)
	var cells: Array[Button] = []
	for i in things.size():
		var item: String = things[i]
		var at := Vector2((i%columns)*cell.x,(i/columns)*cell.y)
		var open := chosen == item
		var button := Px.row(inner,"",Rect2(at,cell-Vector2(4,4)),open,pick.bind(item))
		button.tooltip_text = "%s · %s" % [Save.GOODS[item].name,Save.effect_of(item)]
		Px.block(inner,Rect2(at+Vector2(2,0),Vector2(cell.x-6,2)),Color(_tint(item),.9 if open else .55))
		Px.picture(inner,Px.icon(Save.art(item),32),Rect2(at+Vector2(roundf((cell.x-4)*.5)-16,5),Vector2(32,32))).modulate = _tint(item) if open else _tint(item).darkened(.2)
		var corner := str(mark.call(item))
		if corner != "": Px.text(inner,corner,Rect2(at+Vector2(0,4),Vector2(cell.x-8,0)),Px.SMALL,Px.IVORY,HORIZONTAL_ALIGNMENT_RIGHT)
		var price := int(cost.call(item))
		if price > 0: _price(inner,price,Vector2(at.x+roundf((cell.x-4)*.5)-(15+Px.width_of(str(price),Px.SMALL))*.5,at.y+41))
		cells.append(button)
	for i in cells.size():
		if i%columns > 0: cells[i].focus_neighbor_left = cells[i].get_path_to(cells[i-1])
		if i%columns < columns-1 and i+1 < cells.size(): cells[i].focus_neighbor_right = cells[i].get_path_to(cells[i+1])
		if i >= columns: cells[i].focus_neighbor_top = cells[i].get_path_to(cells[i-columns])
		if i+columns < cells.size(): cells[i].focus_neighbor_bottom = cells[i].get_path_to(cells[i+columns])
	return cells

## The row of place filters over a grid of things.
func _filters(at: Vector2, chosen: String, pick: Callable) -> Array[Button]:
	var filters: Array[Button] = []
	var names := [["","全部"]]+Save.SLOTS+[["item","物品"],["material","材料"]]
	for i in names.size():
		filters.append(Px.tab(body,names[i][1],Rect2(at.x+i*50,at.y,46,24),chosen == names[i][0],pick.bind(names[i][0])))
	return filters

## The head of the side panel for one thing: drawing, name, what it does. Returns the y below.
func _thing(item: String, side: Rect2) -> float:
	var goods: Dictionary = Save.GOODS[item]
	var x := side.position.x+16
	var wide := side.size.x-32
	Px.picture(body,Px.icon(Save.art(item),48),Rect2(x,side.position.y+14,48,48)).modulate = _tint(item)
	var kind: String = {"material":"材料","item":"物品"}.get(goods.slot,Save.slot_name(goods.slot))
	Px.text(body,"%s · %s" % [kind,_rarity_word(item)],Rect2(x+58,side.position.y+16,wide-58,0),Px.SMALL,Px.OCHRE)
	Px.text(body,goods.name,Rect2(x+58,side.position.y+32,wide-58,0),Px.BODY,_tint(item))
	var y := side.position.y+72
	Px.rule(body,Vector2(x,y),wide,Color(Px.OCHRE,.3))
	var does := Save.effect_of(item)
	Px.text(body,does,Rect2(x,y+10,wide,0),Px.SMALL,Px.GREEN if goods.slot != "material" else Px.MUTED)
	y += 16+Px.measure(does,Px.SMALL,wide)
	var lore := str(goods.get("lore",""))
	if lore != "":
		Px.text(body,lore,Rect2(x,y,wide,0),Px.SMALL,Px.MUTED)
		y += 10+Px.measure(lore,Px.SMALL,wide)
	return y

func _pack() -> void:
	var purse := _purse()
	var grid := Rect2(24,108,452,412)
	var side := Rect2(488,108,232,412)
	Px.sheet(body,grid,.92)
	Px.sheet(body,side,.92)
	var filters := _filters(grid.position+Vector2(12,8),pack_filter,_pick_filter)
	var spare := Px.tab(body,"只看空闲",Rect2(grid.end.x-78,grid.position.y+8,66,24),pack_spare,_toggle_spare)
	Px.chain(filters+[spare],false)
	Px.rule(body,Vector2(grid.position.x+12,grid.position.y+34),grid.size.x-24,Color(Px.OCHRE,.3))
	var shown: Array = _in_order(purse.bag.keys().filter(func(item):
		return int(purse.bag[item]) > 0 and (pack_filter == "" or Save.GOODS[item].slot == pack_filter) and (not pack_spare or Save.loose(purse,item) > 0)))
	var pieces := 0
	for item: String in purse.bag: pieces += int(purse.bag[item])
	Px.text(body,"%d 种，共 %d 件" % [purse.bag.size(),pieces],Rect2(grid.position.x+14,grid.end.y-22,300,0),Px.SMALL,Px.MUTED)
	if shown.is_empty():
		Px.text(body,"行囊是空的。打完仗会有战利品，阿齐尔那里也有卖。" if purse.bag.is_empty() else "没有符合条件的东西。",Rect2(grid.position.x+14,grid.position.y+60,400,0),Px.BODY,Px.FAINT)
		_focus(filters[0])
		return
	if not shown.has(pack_item): pack_item = shown[0]
	var cells := _grid("pack",Rect2(grid.position.x+10,grid.position.y+42,grid.size.x-16,grid.size.y-70),shown,pack_item,_pick_item,7,
		func(item): return "×%d" % int(purse.bag[item]) if int(purse.bag[item]) > 1 else "",
		func(_item): return 0)
	for filter in filters: filter.focus_neighbor_bottom = filter.get_path_to(cells[0])
	for i in mini(7,cells.size()): cells[i].focus_neighbor_top = cells[i].get_path_to(filters[0])
	# The open thing: what it does, how many there are, who has one on.
	var goods: Dictionary = Save.GOODS[pack_item]
	var x := side.position.x+16
	var wide := side.size.x-32
	var y := _thing(pack_item,side)
	var loose := Save.loose(purse,pack_item)
	Px.text(body,"共 %d 件，%d 件空闲" % [int(purse.bag[pack_item]),loose],Rect2(x,y,wide,0),Px.SMALL,Px.OCHRE)
	Px.text(body,"可卖",Rect2(x+wide-70,y,30,0),Px.SMALL,Px.MUTED)
	_price(body,Save.sell_price(pack_item),Vector2(x+wide,y),true)
	y += 18
	Px.rule(body,Vector2(x,y),wide,Color(Px.OCHRE,.2))
	if goods.slot in ["material","item"]:
		Px.text(body,"材料只能卖。去找阿齐尔。" if goods.slot == "material" else "随身物品在成员的「信息」页里分配，每人两件。",Rect2(x,y+10,wide,0),Px.SMALL,Px.FAINT)
		if asking == "": _focus(cells[shown.find(pack_item)])
		return
	Px.text(body,"交给谁",Rect2(x,y+8,wide,0),Px.SMALL,Px.OCHRE)
	var everyone := _everyone()
	var people := _scroll("pack/people",Rect2(x-6,y+26,wide+12,side.end.y-y-36),everyone.size()*26.0)
	var takers: Array[Button] = []
	for i in everyone.size():
		var who: String = everyone[i]
		var theirs: String = _worn(who).get(goods.slot,"")
		var has := theirs == pack_item
		var taker := Px.row(people,"",Rect2(0,i*26,wide+2,24),has,_strip.bind(who,goods.slot) if has else _wear.bind(pack_item,who))
		taker.disabled = not has and loose <= 0
		Px.picture(people,Px.face(_look(who),16),Rect2(8,i*26+4,16,16))
		Px.text(people,_name(who),Rect2(30,i*26+5,90,0),Px.SMALL,Px.IVORY)
		Px.text(people,"戴着 · 点一下卸下" if has else ("换下%s" % Save.GOODS[theirs].name if theirs != "" else ""),Rect2(wide-110,i*26+5,106,0),Px.SMALL,Px.GREEN if has else Px.FAINT,HORIZONTAL_ALIGNMENT_RIGHT)
		takers.append(taker)
	Px.chain(takers)
	for button in cells:
		if button.focus_neighbor_right.is_empty(): button.focus_neighbor_right = button.get_path_to(takers[0])
	for taker in takers: taker.focus_neighbor_left = taker.get_path_to(cells[shown.find(pack_item)])
	if asking == "": _focus(cells[shown.find(pack_item)])

func _pick_filter(key: String) -> void:
	pack_filter = key
	scrolls.erase("pack")
	_render()

func _toggle_spare() -> void:
	pack_spare = not pack_spare
	scrolls.erase("pack")
	_render()

func _pick_item(item: String) -> void:
	pack_item = item
	_render()

func _pick_place(key: String) -> void:
	place = key
	open = "gear"
	candidate = ""
	_render()

## Puts a free one of a thing on a member, in the place it belongs to.
func _wear(item: String, who: String) -> void:
	if Save.loose(_purse(),item) <= 0: return
	var next: Dictionary = entry.duplicate(true)
	var worn: Dictionary = next.purse.worn
	if not worn.has(who): worn[who] = {}
	worn[who][Save.GOODS[item].slot] = item
	if _keep(next): note = "%s戴上了%s。" % [_name(who),Save.GOODS[item].name]
	_render()

## Takes off whatever a member has in a place.
func _strip(who: String, where: String) -> void:
	var next: Dictionary = entry.duplicate(true)
	var worn: Dictionary = next.purse.worn
	if not worn.get(who,{}).has(where): return
	worn[who].erase(where)
	if _keep(next): note = "已收回行囊。"
	_render()

# --- 阿齐尔：买卖 ---------------------------------------------------------------------

## The trader: his shelf to buy from, your bag to sell from, both as grids by place.
func _trader() -> void:
	_person_head("trader")
	var purse := _purse()
	var grid := Rect2(24,108,452,412)
	var side := Rect2(488,108,232,412)
	Px.sheet(body,grid,.92)
	Px.sheet(body,side,.92)
	var selling := shop_tab == "sell"
	var ways: Array[Button] = [
		Px.tab(body,"买",Rect2(grid.position.x+12,grid.position.y+8,50,24),not selling,_pick_shop.bind("buy")),
		Px.tab(body,"卖",Rect2(grid.position.x+66,grid.position.y+8,50,24),selling,_pick_shop.bind("sell"))]
	Px.chain(ways,false)
	for way in ways: way.focus_neighbor_top = way.get_path_to(tabs_row[-1])
	tabs_row[-1].focus_neighbor_bottom = tabs_row[-1].get_path_to(ways[0])
	var filters := _filters(grid.position+Vector2(12,38),shop_filter,_pick_shop_filter)
	Px.chain(filters,false)
	for filter in filters: filter.focus_neighbor_top = filter.get_path_to(ways[1 if selling else 0])
	for way in ways: way.focus_neighbor_bottom = way.get_path_to(filters[0])
	Px.rule(body,Vector2(grid.position.x+12,grid.position.y+64),grid.size.x-24,Color(Px.OCHRE,.3))
	var shown: Array = []
	if selling:
		shown = purse.bag.keys().filter(func(item): return Save.loose(purse,item) > 0)
	else:
		for id: String in Save.GOODS:
			if Save.stocked(id,entry): shown.append(id)
	shown = _in_order(shown.filter(func(item): return shop_filter == "" or Save.GOODS[item].slot == shop_filter))
	# Along the foot: everything that is only good for selling, in one press.
	var scrap := 0
	for item: String in purse.bag:
		if Save.GOODS[item].slot == "material": scrap += Save.loose(purse,item)*Save.sell_price(item)
	var clear: Button
	if selling:
		clear = Px.button(body,"卖掉所有材料　　　　",Rect2(grid.position.x+12,grid.end.y-34,190,26),_sell_scrap)
		clear.disabled = scrap <= 0
		_price(body,scrap,Vector2(grid.position.x+140,grid.end.y-27),false,Px.IVORY)
	else:
		Px.text(body,"%d 样货。打下来的东西到「卖」里出手。" % shown.size(),Rect2(grid.position.x+14,grid.end.y-24,400,0),Px.SMALL,Px.MUTED)
	if shown.is_empty():
		var why := "这一类他没有货。"
		if selling: why = "没有能卖的。身上戴着的要先卸下。" if not purse.bag.is_empty() else "行囊是空的。打完仗会有战利品。"
		Px.text(body,why,Rect2(grid.position.x+14,grid.position.y+90,400,0),Px.BODY,Px.FAINT)
		_focus(filters[0])
		return
	if not shown.has(picked.trader): picked.trader = shown[0]
	var item: String = picked.trader
	var cells := _grid("shop/"+shop_tab,Rect2(grid.position.x+10,grid.position.y+72,grid.size.x-16,grid.size.y-112),shown,item,_pick.bind("trader"),7,
		func(thing):
			if selling: return "×%d" % Save.loose(purse,thing) if Save.loose(purse,thing) > 1 else ""
			return "有" if int(purse.bag.get(thing,0)) > 0 else "",
		func(thing): return Save.sell_price(thing) if selling else int(Save.GOODS[thing].price))
	for filter in filters: filter.focus_neighbor_bottom = filter.get_path_to(cells[0])
	for i in mini(7,cells.size()): cells[i].focus_neighbor_top = cells[i].get_path_to(filters[0])
	if clear != null: cells[-1].focus_neighbor_bottom = cells[-1].get_path_to(clear)
	# The open thing, and what it would do for whoever is being fitted.
	var goods: Dictionary = Save.GOODS[item]
	var x := side.position.x+16
	var wide := side.size.x-32
	var y := _thing(item,side)
	var have := int(purse.bag.get(item,0))
	Px.text(body,"你有 %d 件" % have if have > 0 else "你还没有",Rect2(x,y,wide,0),Px.SMALL,Px.OCHRE if have > 0 else Px.FAINT)
	y += 18
	var faces: Array[Button] = []
	if goods.slot not in ["material","item"] and not selling:
		Px.rule(body,Vector2(x,y),wide,Color(Px.OCHRE,.2))
		Px.text(body,"给谁试",Rect2(x,y+8,wide,0),Px.SMALL,Px.OCHRE)
		var everyone := _everyone()
		if not everyone.has(member): member = "hero"
		for i in everyone.size():
			var who: String = everyone[i]
			var face := Px.row(body,"",Rect2(x+44+i*26,y+3,24,22),member == who,_fit.bind(who))
			face.tooltip_text = _name(who)
			Px.picture(body,Px.face(_look(who),16),Rect2(x+48+i*26,y+6,16,16))
			faces.append(face)
		Px.chain(faces,false)
		y += 32
		var theirs: String = _worn(member).get(goods.slot,"")
		Px.text(body,"%s的%s：%s" % [_name(member),Save.slot_name(goods.slot),Save.GOODS[theirs].name if theirs != "" else "空"],Rect2(x,y,wide,0),Px.SMALL,Px.MUTED)
		y += 16
		var lines := _would_change(member,item) if theirs != item else []
		if theirs == item:
			Px.text(body,"已经戴着这一件。",Rect2(x,y,wide,0),Px.SMALL,Px.FAINT)
		elif lines.is_empty():
			Px.text(body,"换上后数值不变。",Rect2(x,y,wide,0),Px.SMALL,Px.FAINT)
		for i in lines.size():
			var line: Array = lines[i]
			Px.text(body,line[0],Rect2(x+(i%2)*100,y+(i/2)*16,40,0),Px.SMALL,Px.MUTED)
			Px.text(body,"%d→%d" % [line[1],line[2]],Rect2(x+34+(i%2)*100,y+(i/2)*16,60,0),Px.SMALL,Px.GREEN if line[2] > line[1] else Px.RED.lightened(.4))
	# What it costs or fetches, and the press that does it.
	var act: Button
	var act_at := Rect2(x,side.end.y-40,wide,28)
	if selling:
		var loose := Save.loose(purse,item)
		var each := Save.sell_price(item)
		if loose > 1:
			var whole := Px.button(body,"全部卖出 ×%d　　　　" % loose,Rect2(x,side.end.y-74,wide,28),_sell.bind(item,loose))
			_price(body,each*loose,Vector2(x+wide-52,side.end.y-66),false,Px.IVORY)
			act = Px.primary(body,"卖一件　　　　",act_at,_sell.bind(item,1))
			whole.focus_neighbor_bottom = whole.get_path_to(act)
			act.focus_neighbor_top = act.get_path_to(whole)
		else:
			act = Px.primary(body,"卖出　　　　",act_at,_sell.bind(item,1))
		_price(body,each,Vector2(x+wide-52,side.end.y-32),false,Px.IVORY)
	elif goods.get("unique",false) and have > 0:
		Px.text(body,"只此一件，已经在你手上。",Rect2(x,side.end.y-34,wide,0),Px.SMALL,Px.OCHRE)
	else:
		var short := int(goods.price)-_coins()
		act = Px.primary(body,"买下　　　　" if short <= 0 else "还差　　　　",act_at,_buy.bind(item))
		act.disabled = short > 0
		_price(body,int(goods.price) if short <= 0 else short,Vector2(x+wide-52,side.end.y-32),false,Px.IVORY if short <= 0 else Px.MUTED)
	var here := cells[shown.find(item)]
	for button in cells:
		if button.focus_neighbor_right.is_empty():
			button.focus_neighbor_right = button.get_path_to(faces[0] if not faces.is_empty() else (act if act != null else button))
	if act != null: act.focus_neighbor_left = act.get_path_to(here)
	for face in faces:
		face.focus_neighbor_left = face.get_path_to(here) if face == faces[0] else face.focus_neighbor_left
		if act != null: face.focus_neighbor_bottom = face.get_path_to(act)
	if asking == "": _focus(here)

func _pick(value: Variant, key: String) -> void:
	picked[key] = value
	_render()

func _pick_shop(which: String) -> void:
	shop_tab = which
	_render()

func _pick_shop_filter(key: String) -> void:
	shop_filter = key
	scrolls.erase("shop/buy")
	scrolls.erase("shop/sell")
	_render()

## Whose sheet a thing on the shelf is weighed against.
func _fit(who: String) -> void:
	member = who
	_render()

func _buy(item: String) -> void:
	var price := int(Save.GOODS[item].price)
	if _coins() < price: return
	var next: Dictionary = entry.duplicate(true)
	var purse: Dictionary = next.purse
	if Save.GOODS[item].get("unique",false) and int(purse.bag.get(item,0)) > 0: return
	purse.bag[item] = int(purse.bag.get(item,0))+1
	purse.coins = _coins()-price
	if _keep(next):
		note = "买下了%s。" % Save.GOODS[item].name
		note_tone = _tint(item)
	_render()

## Sells `count` free ones of a thing for half its price each.
func _sell(item: String, count: int) -> void:
	count = mini(count,Save.loose(_purse(),item))
	if count <= 0: return
	var next: Dictionary = entry.duplicate(true)
	var purse: Dictionary = next.purse
	purse.bag[item] = int(purse.bag[item])-count
	if int(purse.bag[item]) <= 0: purse.bag.erase(item)
	purse.coins = _coins()+Save.sell_price(item)*count
	if _keep(next): note = "卖掉了%s%s。" % [Save.GOODS[item].name," ×%d" % count if count > 1 else ""]
	_render()

func _sell_scrap() -> void:
	var next: Dictionary = entry.duplicate(true)
	var purse: Dictionary = next.purse
	var fetched := 0
	for item: String in purse.bag.keys():
		if Save.GOODS[item].slot != "material": continue
		fetched += Save.sell_price(item)*int(purse.bag[item])
		purse.bag.erase(item)
	if fetched <= 0: return
	purse.coins = _coins()+fetched
	if _keep(next): note = "材料都出手了。"
	_render()

# --- 达蒙：招募 -----------------------------------------------------------------------

func _recruit() -> void:
	_person_head("recruit")
	var offers := Save.offers(entry)
	if offers.filter(func(offer): return offer.id == picked.recruit).is_empty():
		picked.recruit = "" if offers.is_empty() else str(offers[0].id)
	var rows_data := []
	for offer: Dictionary in offers:
		var kind: Dictionary = Save.RECRUITS[offer.kind]
		var grade := _grade(kind.rarity)
		rows_data.append([offer.id,offer.name,grade[0],Px.face(str(kind.get("look",kind.def)),32),Color.WHITE,grade[1],int(offer.fee)])
	var rows := _list("愿意同行的英雄",rows_data,picked.recruit,_pick.bind("recruit"),40.0)
	var x := DETAIL.position.x+20
	if picked.recruit == "":
		_title("眼下没有人可招","招募")
		Px.text(body,"往前走，会有别的英雄听说你们。",Rect2(x,DETAIL.position.y+90,MEASURE,0),Px.BODY,Px.MUTED)
		return
	var offer: Dictionary = offers.filter(func(candidate): return candidate.id == picked.recruit)[0]
	var kind: Dictionary = Save.RECRUITS[offer.kind]
	var grade := _grade(kind.rarity)
	var y := _title("",kind.title,Px.face(str(kind.get("look",kind.def)),48))
	Px.text(body,offer.name,Rect2(x+60,DETAIL.position.y+30,380,0),Px.TITLE,grade[1])
	Px.text(body,grade[0],Rect2(x+60+Px.width_of(kind.title,Px.SMALL)+10,DETAIL.position.y+14,80,0),Px.SMALL,grade[1])
	# A band in the rarity's colour under the name.
	Px.block(body,Rect2(x,y-1,DETAIL.size.x-40,2),grade[1])
	y += 14
	var sheet: Dictionary = UnitCatalog.unit_def(kind.def)
	_stats(sheet,Vector2(x,y),false)
	y += 66
	var known: Array = []
	for skill: String in sheet.get("skills",[]):
		known.append(SkillCatalog.get_skill(skill).get("name",skill))
	if kind.has("skill"): known.append(SkillCatalog.get_skill(kind.skill).get("name",kind.skill))
	Px.text(body,"招式",Rect2(x,y,60,0),Px.SMALL,Px.OCHRE)
	Px.text(body,"、".join(known),Rect2(x+60,y,MEASURE-60,0),Px.SMALL,Px.IVORY)
	y += 22
	Px.text(body,"技艺",Rect2(x,y,60,0),Px.SMALL,Px.OCHRE)
	if SkillTree.trees().has(offer.kind):
		var arms: Array = SkillTree.trees().get(offer.kind,[]).map(func(branch): return "%s（%d 招）" % [branch.branch,branch.nodes.size()])
		Px.text(body,"专属　"+"、".join(arms),Rect2(x+60,y,MEASURE-60,0),Px.SMALL,grade[1])
	else:
		Px.text(body,"没有可修习的分支",Rect2(x+60,y,MEASURE-60,0),Px.SMALL,Px.FAINT)
	y += 28
	Px.text(body,kind.lore,Rect2(x,y,MEASURE,0),Px.BODY,Px.MUTED)
	var short := int(offer.fee)-_coins()
	Px.text(body,"雇金",Rect2(x,DETAIL.end.y-34,40,0),Px.SMALL,Px.OCHRE)
	_price(body,int(offer.fee),Vector2(x+34,DETAIL.end.y-34))
	var act := Px.primary(body,"招募　　　　" if short <= 0 else "还差　　　　",Rect2(DETAIL.end.x-20-136,DETAIL.end.y-42,136,30),_hire.bind(offer.id))
	act.disabled = short > 0
	_price(body,int(offer.fee) if short <= 0 else short,Vector2(DETAIL.end.x-20-64,DETAIL.end.y-33),false,Px.IVORY if short <= 0 else Px.MUTED)
	_link(rows,act,offers.find(offer))

func _hire(offer_id: String) -> void:
	var found: Array = Save.offers(entry).filter(func(candidate): return candidate.id == offer_id)
	if found.is_empty() or _coins() < int(found[0].fee): return
	var offer: Dictionary = found[0]
	var next: Dictionary = entry.duplicate(true)
	var roster: Array = next.get("roster",[])
	var serial := 1
	while roster.any(func(hand): return hand.id == "r%d" % serial): serial += 1
	var who := "r%d" % serial
	roster.append({"id":who,"kind":offer.kind,"name":offer.name})
	next.roster = roster
	if not next.has("xp"): next.xp = {}
	next.xp[who] = _xp("hero")/2
	var purse: Dictionary = next.get("purse",{})
	purse.coins = _coins()-int(offer.fee)
	next.purse = purse
	# A new hand marches at once if there is room.
	var going := _marching()
	if going.size() < Save.SEATS: going.append(who)
	next.deploy = going
	if _keep(next):
		note = "%s加入了营地。" % offer.name
		note_tone = _grade(Save.RECRUITS[offer.kind].rarity)[1]
	_render()

# --- 伊俄：出征 -----------------------------------------------------------------------

func _march() -> void:
	_person_head("march")
	var region: Dictionary = Routes.data[chapter]
	var sites: Array = region.sites
	if picked.march < 0 or picked.march >= sites.size():
		picked.march = 0
		for i in sites.size():
			if _status(chapter,sites[i]) == "可出发": picked.march = i
	var rows_data := []
	for i in sites.size():
		var state := _status(chapter,sites[i])
		var mark := "done" if state == "已通关" else ("here" if state == "可出发" else "lock")
		var tint := Px.GREEN if state == "已通关" else (Px.OCHRE if state == "可出发" else Px.FAINT)
		rows_data.append([i,"%s %s" % [sites[i].id,sites[i].name],state,Px.icon(mark,32),tint])
	var rows := _list("第%s章 · %s" % [NUMERALS[chapter],region.name],rows_data,picked.march,_pick.bind("march"),40.0)
	var earlier := Px.button(body,"上一章",Rect2(LIST.position.x+10,LIST.end.y-36,94,26),_turn_chapter.bind(-1))
	var later := Px.button(body,"下一章",Rect2(LIST.position.x+110,LIST.end.y-36,94,26),_turn_chapter.bind(1))
	earlier.disabled = chapter == 0
	later.disabled = chapter == Routes.data.size()-1
	Px.chain([earlier,later],false)
	var site: Dictionary = sites[picked.march]
	var state := _status(chapter,site)
	var y := _title(site.name,"%s · %s · %s" % [site.id,"支线" if site.optional else "主线",state])
	var x := DETAIL.position.x+20
	Px.rule(body,Vector2(x,y),DETAIL.size.x-40,Color(Px.OCHRE,.3))
	y += 12
	Px.text(body,"目标",Rect2(x,y,60,0),Px.SMALL,Px.OCHRE)
	Px.text(body,str(site.goal),Rect2(x+60,y,MEASURE-60,0),Px.BODY,Px.IVORY)
	y += 14+Px.measure(str(site.goal),Px.BODY,MEASURE-60)
	Px.rule(body,Vector2(x,y),DETAIL.size.x-40,Color(Px.OCHRE,.2))
	y += 10
	# Who goes: the protagonist, and up to three heroes of the player's choosing. A battle
	# whose story needs someone there takes one of the three for them.
	var needed := _required(str(site.id))
	var going := _marching_to(str(site.id))
	Px.text(body,"出战名单",Rect2(x,y,120,0),Px.SMALL,Px.OCHRE)
	Px.text(body,"另选 %d / %d 人" % [going.size(),Save.SEATS],Rect2(x+230,y,200,0),Px.SMALL,Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	y += 20
	Px.picture(body,Px.face("hero",32),Rect2(x,y,32,32))
	Px.text(body,_name("hero"),Rect2(x+40,y+2,120,0),Px.BODY,Px.IVORY)
	Px.text(body,"必定出战",Rect2(x+40,y+18,120,0),Px.SMALL,Px.FAINT)
	y += 42
	var toggles: Array[Button] = []
	var pool := _reserves()
	if pool.is_empty():
		Px.text(body,"营地里还没有别人。达蒙那里可以招募。",Rect2(x,y+4,MEASURE,0),Px.SMALL,Px.FAINT)
	for i in pool.size():
		var who: String = pool[i]
		var on := going.has(who)
		var at := Vector2(x+(i%2)*220,y+(i/2)*40)
		var toggle := Px.row(body,"",Rect2(at.x-10,at.y,214,36),on,_toggle_march.bind(who))
		var must := needed.has(who)
		toggle.disabled = must or (not on and going.size() >= Save.SEATS)
		Px.picture(body,Px.face(_look(who),32),Rect2(at.x,at.y+2,32,32)).modulate = Color.WHITE if on else Color(1,1,1,.45)
		var ink: Color = _rarity(who)[1] if not _rarity(who).is_empty() else Px.IVORY
		Px.text(body,_name(who),Rect2(at.x+40,at.y+3,120,0),Px.BODY,ink if on else ink.darkened(.3))
		Px.text(body,"这一战必须出战" if must else "出战 · 点一下留守" if on else ("名额已满" if toggle.disabled else "留守 · 点一下出战"),Rect2(at.x+40,at.y+19,160,0),Px.SMALL,Px.GREEN if on else Px.FAINT)
		toggles.append(toggle)
	Px.chain(toggles)
	var go: Button
	if state == "可出发":
		go = Px.primary(body,"出征",Rect2(DETAIL.end.x-20-160,DETAIL.end.y-42,160,30),_depart.bind(site))
	else:
		var why: String = {"尚未开放":"这一章还没有开放。","尚未抵达":"先打完前面的战斗。","支线待解锁":"在林道救出至少两名村民，这条路才会打开。","未到访":"这一趟已经错过了。","已通关":"这里已经打完了。"}.get(state,state)
		Px.text(body,why,Rect2(x,DETAIL.end.y-34,MEASURE,0),Px.SMALL,Px.MUTED)
	if not toggles.is_empty():
		for row in rows: row.focus_neighbor_right = row.get_path_to(toggles[0])
		for toggle in toggles: toggle.focus_neighbor_left = toggle.get_path_to(rows[picked.march])
		if go != null:
			toggles[-1].focus_neighbor_bottom = toggles[-1].get_path_to(go)
			go.focus_neighbor_top = go.get_path_to(toggles[-1])
	else:
		_link(rows,go,picked.march)
	if go != null and asking == "": _focus(go)

func _toggle_march(who: String) -> void:
	var going := _marching()
	if going.has(who): going.erase(who)
	elif going.size() < Save.SEATS: going.append(who)
	var next: Dictionary = entry.duplicate(true)
	next.deploy = going
	_keep(next)
	_render()

func _turn_chapter(step: int) -> void:
	chapter = clampi(chapter+step,0,Routes.data.size()-1)
	picked.march = -1
	_render()

func _depart(site: Dictionary) -> void:
	var next: Dictionary = entry.duplicate(true)
	next.id = site.id
	next.choose_route = false
	next.campaign = persistent
	next.erase("camp_summary")
	next.deploy = _marching_to(str(site.id))
	next.bench = Save.PLACED.filter(func(who): return not next.deploy.has(who))
	var party := []
	for who: String in next.deploy:
		if Save.PLACED.has(who): continue
		var own := str(_kind(who).get("skill",""))
		party.append({"id":who,"def":_def(who),"name":_name(who),"skills":[own] if own != "" else [],"look":_look(who) if _look(who) != _def(who) else "","tree":_tree_of(who)})
	next.party = party
	var loadout := {}
	for who: String in ["hero"]+next.deploy: loadout[who] = _carried(who)
	next.loadout = loadout
	get_tree().set_meta("battle_entry",next)
	get_tree().change_scene_to_file(BATTLE)

# --- Questions laid over the camp ---------------------------------------------------

func _modal(width: float, height: float) -> Rect2:
	Px.block(body,Rect2(Vector2.ZERO,Px.SIZE),Color(Px.INK,.6)).mouse_filter = MOUSE_FILTER_STOP
	var rect := Rect2((Px.SIZE-Vector2(width,height))*.5,Vector2(width,height)).abs()
	Px.sheet(body,rect,.96)
	return rect

func _ask_boon() -> void:
	var rect := _modal(520,280)
	var x := rect.position.x+28
	var y := rect.position.y+22
	Px.picture(body,Px.icon("relic",32),Rect2(x,y,32,32)).modulate = Px.OCHRE
	Px.text(body,"第一章 · 涅墨亚",Rect2(x+44,y,300,0),Px.SMALL,Px.OCHRE)
	Px.text(body,"涅墨亚狮子已败",Rect2(x+44,y+14,400,0),Px.TITLE,Px.IVORY)
	y += 56
	Px.text(body,"狮皮归主角：物理减伤 3，受背击倍率降至 1.25。\n不坏之皮：免疫物理伤害 1 回合，冷却 4 回合，使用时神性 +2。",Rect2(x,y,464,0),Px.SMALL,Px.MUTED)
	y += 44
	Px.rule(body,Vector2(x,y),464,Color(Px.OCHRE,.3))
	y += 12
	Px.text(body,"选一项神赐，此后一直带着",Rect2(x,y,400,0),Px.BODY,Px.IVORY)
	y += 26
	var choices: Array[Button] = []
	for id: String in Save.BOONS:
		var boon: Array = Save.BOONS[id]
		choices.append(Px.button(body,"%s · %s" % [boon[0],boon[1]],Rect2(x,y,200,28),_take_boon.bind(id)))
		Px.text(body,boon[2],Rect2(x+212,y+7,260,0),Px.SMALL,Px.MUTED)
		y += 36
	Px.chain(choices)
	_focus(choices[0])

func _take_boon(id: String) -> void:
	var next: Dictionary = entry.duplicate(true)
	next.boon = id
	next.id = "2-1"
	next.stage = "camp"
	next.choose_route = false
	next.camp_summary = "涅墨亚狮子已败。"
	if _keep(next):
		asking = ""
		chapter = _chapter_of("2-1")
		picked.march = -1
	_render()

func _ask_system() -> void:
	var rect := _modal(260,150)
	var x := rect.position.x+28
	Px.text(body,"系统",Rect2(x,rect.position.y+18,200,0),Px.TITLE,Px.IVORY)
	var choices: Array[Button] = [
		Px.row(body,"回到营地",Rect2(x-10,rect.position.y+60,224,24),false,_set_asking.bind("")),
		Px.row(body,"回到首页",Rect2(x-10,rect.position.y+86,224,24),false,get_tree().change_scene_to_file.bind(TITLE)),
		Px.row(body,"离开游戏",Rect2(x-10,rect.position.y+112,224,24),false,Soundscape.quit_game)]
	Px.chain(choices)
	_focus(choices[0])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if asking == "cheer":
			_end_cheer(false)
			return
		if asking == "boon": return
		if asking != "": _set_asking("")
		elif screen != "home": _go("home")
		else: _set_asking("system")
	elif asking == "" and event is InputEventKey and event.pressed and not event.echo:
		# Quick keys: Q for the party, then the three people of the camp.
		if event.keycode == KEY_TAB and screen == "party" and view == "members" and _tree_of(member) != "":
			get_viewport().set_input_as_handled()
			_pick_page("tree" if page == "info" else "info")
			return
		var where: String = {KEY_Q:"party",KEY_1:"trader",KEY_2:"recruit",KEY_3:"march"}.get(event.keycode,"")
		if where != "":
			get_viewport().set_input_as_handled()
			_go("home" if screen == where else where)
