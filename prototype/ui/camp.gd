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
const LEVEL_UP := preload("res://art/original/fx/levelup.png")
var leveled_members: Array[String] = []
const NUMERALS := ["一","二","三","四","五","六","七","八"]
## The people of the camp: who they are, the sprite that plays them, where they stand,
## and the screen they open.
const PEOPLE := [
	{"key":"trader","name":"阿齐尔","role":"行商","service":"买护符","icon":"shop","def":"refugee","look":"npc_trader","cell":Vector2(10.85,6.15),"turn":Vector2i(0,1)},
	{"key":"recruit","name":"达蒙","role":"教习","service":"招募 · 操练","icon":"talk","def":"bandit_chief","look":"npc_drill","cell":Vector2(3.4,5.6),"turn":Vector2i(1,0)},
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
var drill_open := false
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
var asking := ""  ## "" | "verdict" | "boon" | "power" | "system" | "cheer"
## Which way the player leans over a beaten boss ("take" | "spare"), before saying so.
var leaning := ""
## Set when the lean has just changed, so the screen answers once and not on every redraw.
var lean_fresh := false
## True while a settled verdict plays out, before it is written down.
var settling := false
## Where things stand on the verdict screen, for what is played over it.
var verdict_spots := {}
## How far the scales on the verdict screen were last seen tipped, in degrees (left pan
## down is positive), so a new lean swings them from there instead of jumping.
var verdict_tilt := 0.0
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
		UiShot.take(self,str(shot.path),9.0 if str(shot.page).begins_with("verdictplay") else 2.6)
	_pitch_camp()
	canvas = Px.stage(self)
	for layer: Control in [signs,body,floats,cheer]:
		layer.size = Px.SIZE
		layer.mouse_filter = MOUSE_FILTER_IGNORE
		canvas.add_child(layer)
	cheer.hide()
	asking = _owed()
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
			entry.divinity = 1
			entry.boon = ""
			asking = "boon"
		"verdictplay", "verdictplay2":
			# The verdict played through for a recording: lean one way, then the other,
			# then settle.
			entry.equipped_relic = "lion_pelt"
			entry.boon = "moon_hunt"
			entry.relics = ["lion_pelt","hydra_blood","bronze_feather"]
			entry.divinity = 3
			entry.powers = ["thunder_bolt"]
			entry.verdict = 4
			asking = "verdict"
			var settle_on := "take" if which == "verdictplay" else "spare"
			var other := "spare" if settle_on == "take" else "take"
			get_tree().create_timer(1.4).timeout.connect(_lean.bind(other))
			get_tree().create_timer(3.0).timeout.connect(_lean.bind(settle_on))
			get_tree().create_timer(4.8).timeout.connect(_settle_verdict)
		"verdict", "verdict2":
			# Over a beaten boss: the Minotaur with three relics held (taking his makes a
			# demigod), or the Hydra with one.
			entry.equipped_relic = "lion_pelt"
			entry.boon = "moon_hunt"
			entry.relics = ["lion_pelt","hydra_blood","bronze_feather"] if which == "verdict" else ["lion_pelt"]
			entry.divinity = entry.relics.size()
			entry.powers = ["thunder_bolt"] if which == "verdict" else []
			entry.verdict = 4 if which == "verdict" else 2
			leaning = "take" if which == "verdict" else ""
			asking = "verdict"
		"verdict3":
			# Leaning toward sparing the Minotaur, the Hydra spared before him.
			entry.equipped_relic = "lion_pelt"
			entry.boon = "moon_hunt"
			entry.relics = ["lion_pelt","bronze_feather"]
			entry.divinity = 2
			entry.powers = ["thunder_bolt"]
			entry.spared = [2]
			entry.verdict = 4
			leaning = "spare"
			asking = "verdict"
		"power", "power2", "power3":
			# Standing at a tier whose technique is not yet chosen.
			entry.equipped_relic = "lion_pelt"
			entry.boon = "moon_hunt"
			entry.divinity = {"power":2,"power2":4,"power3":6}[which]
			entry.powers = {"power":[],"power2":["thunder_bolt"],"power3":["thunder_bolt","sky_dome"]}[which]
			asking = "power"
		"divine":
			# The protagonist's sheet as a demigod.
			entry.equipped_relic = "lion_pelt"
			entry.boon = "moon_hunt"
			entry.divinity = 4
			entry.powers = ["sky_fire","thunder_step"]
			screen = "party"
			member = "hero"
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
			entry.picks["hero"] = ["shield_wall","shield_drive","iron_arm","heel_strike","breaker"]
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
	scene.map_view.grid_lines = false
	scene.lay(["22222222222222","11111111111111","00000000000000","00000000000000","00000000000000","00000000000000","00000000000000","00000000000000","00000000000000","00000000000000"],
		[Vector2i(1,6),Vector2i(12,3),Vector2i(2,9),Vector2i(8,9)])
	scene.fire(FIRE,.46)
	scene.prop(preload("res://art/landmarks/olive.glb"),2.65,Vector2(.15,2.68),.3)
	scene.prop(preload("res://art/landmarks/cypress.glb"),1.75,Vector2(13.55,3.05),-.7)
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

const CAMP_MODELS := {
	"ridge-tent": preload("res://art/camp/ridge-tent.glb"),
	"lean-to": preload("res://art/camp/lean-to.glb"),
	"amphora": preload("res://art/camp/amphora.glb"),
	"hydria": preload("res://art/camp/hydria.glb"),
	"tripod": preload("res://art/camp/tripod.glb"),
	"altar": preload("res://art/camp/altar.glb"),
	"spear-rack": preload("res://art/camp/spear-rack.glb"),
	"aspis": preload("res://art/camp/aspis.glb"),
	"wolf-hide": preload("res://art/camp/wolf-hide.glb"),
	"brazier": preload("res://art/camp/brazier.glb"),
}
const VISITOR_SPOTS := {"trader":Vector2(9.92,6.93),"recruit":Vector2(4.35,6.25),"march":Vector2(10.59,8.75)}
var furnishings: Array[AABB] = []
var visit_walk: Tween
var destination := ""

func _place_prop(model: String, cell: Vector2, turn := 0., size := 1.) -> void:
	var prop_node := scene.camp_prop(CAMP_MODELS[model],cell,turn,size,1. if model=="ridge-tent" else .40)
	for mesh: MeshInstance3D in prop_node.find_children("*","MeshInstance3D",true,false):
		furnishings.append((mesh.global_transform*mesh.get_aabb()).grow(.15))

func _furnish() -> void:
	# Trading tent, decorated water jar and amphorae on timber stands.
	_place_prop("ridge-tent",Vector2(10.15,2.63),.40)
	_place_prop("amphora",Vector2(11.96,5.16),.30,.89)
	_place_prop("amphora",Vector2(12.52,4.67),-.32,.76)
	_place_prop("hydria",Vector2(9.15,5.18),.56,1.13)
	_place_prop("hydria",Vector2(8.70,4.80),-1.03,.76)
	# The drill yard faces the path. The shield rests against the rack.
	_place_prop("spear-rack",Vector2(2.55,4.15),-.21)
	_place_prop("aspis",Vector2(2.92,4.48),-.27)
	_place_prop("wolf-hide",Vector2(1.23,4.75),.12)
	_place_prop("lean-to",Vector2(1.65,7.20),.85)
	# A second tent and the shrine stand behind the fire.
	_place_prop("ridge-tent",Vector2(2.70,2.04),.30,.86)
	_place_prop("altar",Vector2(6.59,3.14),-.15,1.15)
	_place_prop("tripod",Vector2(7.52,3.52),.32)
	_place_prop("brazier",FIRE)
	_place_prop("lean-to",Vector2(12.43,7.43),-.54,.82)
	_place_prop("amphora",Vector2(12.18,8.50),-.38,.77)

## With a screen open the camp slides right so whoever it concerns stays in view: the
## person being spoken to, or the member whose sheet is open. A member is shown close up,
## so the figure that fights stands in for a portrait.
func _view_target() -> Vector2:
	if screen == "home": return Vector2(7.12,5.35)
	if screen == "party":
		if view == "members" and seats.has(member): return seats[member]+Vector2(-5.0,-.9)
		return FIRE+Vector2(-7.8,-.8)
	for person: Dictionary in PEOPLE:
		if person.key == screen: return (person.cell as Vector2).lerp(VISITOR_SPOTS[person.key],.5)+Vector2(-4.50,-.87)
	return FIRE

func _view_zoom() -> int:
	return 2 if VISITOR_SPOTS.has(screen) or (screen == "party" and view == "members") else 1

## Whoever's sheet is open turns to face you; the rest go back to the fire.
func _turn_sitters() -> void:
	for who: String in sitters:
		var shown: bool = screen == "party" and view == "members" and who == member
		if who=="hero" and VISITOR_SPOTS.has(screen): continue
		sitters[who][0].set_facing(Defs.SOUTH if shown else sitters[who][1])

func _reframe() -> void:
	_turn_sitters()
	scene.rig.ease_zoom(_view_zoom(),.40)
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
	if who == "hero": return Save.hero_look(entry)
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
	var changes_hero := Save.tier(next)!=Save.tier(entry) and sitters.has("hero")
	entry = next
	if changes_hero:
		var toward: Vector2i = sitters.hero[1]
		sitters.hero[0].queue_free()
		sitters.hero[0] = scene.unit("hero",seats.hero,toward,false,_look("hero"))
		_turn_sitters()
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
	if at == 1 and str(entry.get("id","")).begins_with("2-"):
		if outcomes.has(site.id): return str(outcomes[site.id])
		if site.id == entry.id: return "可出发"
		return "尚未抵达" if Save.BATTLES.has(site.id) else "尚未开放"
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
		return "科林斯的东门有条窄路。接到美狄亚就往那里撤，别为了追守卫把她落下。"
	if entry.get("id") == "2-2":
		return "芦苇荡里看着是地的，一半是泥。踩着干的土墩走，别在泥里过夜；蛇在泥里比你快。"
	if entry.get("id") == "2-3":
		if entry.get("outcomes",{}).has("2-3"): return "滩上清净了。再往里是赫拉的祭坛，路我还在探，今晚先把湿衣服烤干。"
		return "巨蟹的壳正面砍不动。绕到它背后，或者干脆把它顶进深水里，它自己爬不上来。"
	return "我已把下一处落脚点圈在图上。先看路口，再看敌人能从哪边绕到你背后。"

# --- Drawing ------------------------------------------------------------------------

func _stop_walk() -> void:
	if visit_walk:
		visit_walk.kill()
		visit_walk = null
	destination = ""
	if sitters.has("hero"): sitters.hero[0].walking = false
	signs.show()

## Quarter-cell steps are only for finding a passage. The feet move continuously on the terrain.
func _camp_route(hero: PixelUnit, goal: Vector2) -> PackedVector2Array:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0,0,57,41)
	grid.cell_size = Vector2.ONE*.25
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var people: Array = figures.values()
	for who: String in sitters:
		if who != "hero": people.append(sitters[who][0])
	for z in grid.region.size.y:
		for x in grid.region.size.x:
			var id := Vector2i(x,z)
			var foot := scene.spot(Vector2(id)*.25)
			var occupied := false
			for box in furnishings:
				if Rect2(box.position.x,box.position.z,box.size.x,box.size.z).has_point(Vector2(foot.x,foot.z)):
					occupied = true
					break
			if not occupied:
				for person: Node3D in people:
					if (foot-person.position).slide(Vector3.UP).length_squared()<.32:
						occupied = true
						break
			if occupied: grid.set_point_solid(id)
	var start3 := scene.map_view.to_local(hero.position)
	var start := Vector2i((Vector2(start3.x,start3.z)*4).round())
	var end := Vector2i((goal*4).round())
	grid.set_point_solid(start,false)
	grid.set_point_solid(end,false)
	var steps := grid.get_id_path(start,end)
	var route := PackedVector2Array()
	for i in range(1,steps.size()-1):
		if steps[i]-steps[i-1]!=steps[i+1]-steps[i]: route.append(Vector2(steps[i])*.25)
	if not steps.is_empty(): route.append(goal)
	return route

func _walk_to(where: String) -> void:
	_stop_walk()
	var hero: PixelUnit = sitters.hero[0]
	var home := where=="home"
	var goal: Vector2 = seats.hero if home else VISITOR_SPOTS[where]
	var route := _camp_route(hero,goal)
	if route.is_empty():
		if home: hero.position=scene.spot(goal)
		else: _go(where)
		return
	destination = where
	if not home: signs.hide()
	var current := scene.map_view.to_local(hero.position)
	var start := Vector2(current.x,current.z)
	visit_walk = create_tween()
	hero.walking = true
	for point in route:
		var end := scene.spot(point)
		visit_walk.tween_callback(hero.face_point.bind(end))
		visit_walk.tween_method(func(cell: Vector2): hero.position=scene.spot(cell),start,point,maxf(.04,scene.spot(start).distance_to(end)/3.6))
		start = point
	if not home:
		visit_walk.tween_callback(func():
			hero.walking = false
			hero.face_point(figures[where].position)
			figures[where].face_point(hero.position)
			var meeting: Vector3 = hero.position.lerp(figures[where].position,.55)
			scene.rig.ease_zoom(2,.55)
			scene.rig.glide_to(meeting+Vector3.UP*.90))
		visit_walk.tween_interval(1.10)
	visit_walk.tween_callback(func():
		visit_walk = null
		destination = ""
		hero.walking = false
		if home:
			hero.set_facing(sitters.hero[1])
		else:
			_go(where))

func _visit(where: String) -> void:
	if screen=="home" and VISITOR_SPOTS.has(where) and sitters.has("hero"):
		_walk_to(where)
	else:
		_go(where)

func _go(where: String) -> void:
	drill_open = false
	_stop_walk()
	screen = where
	asking = ""
	if sitters.has("hero"):
		var hero: PixelUnit = sitters.hero[0]
		if VISITOR_SPOTS.has(where):
			hero.position = scene.spot(VISITOR_SPOTS[where])
			hero.face_point(figures[where].position)
			figures[where].face_point(hero.position)
		elif where=="home" and hero.position.distance_to(scene.spot(seats.hero))>.1:
			_walk_to("home")
		else:
			hero.position = scene.spot(seats.hero)
	_reframe()
	_render()

## Focus once the frame has settled; the control may already be gone if the page was redrawn.
func _focus(control: Control) -> void:
	(func():
		if is_instance_valid(control) and control.is_inside_tree(): control.grab_focus()).call_deferred()

func _set_asking(what: String) -> void:
	_stop_walk()
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
	elif asking == "verdict": _ask_verdict()
	elif asking == "power": _ask_power()
	elif asking == "system": _ask_system()

## What the camp must settle before anything else: what to do with a beaten boss, the boon
## after a chapter's boss, then any divine technique a new tier has brought.
func _owed() -> String:
	if Save.VERDICTS.has(int(entry.get("verdict",0))): return "verdict"
	if entry.has("equipped_relic") and entry.get("boon","") == "": return "boon"
	if Save.owes_power(entry): return "power"
	return ""

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

## The laurel ring passes behind the portrait and leaves the facial features visible.
func _rank_ring(face: Control) -> void:
	var ring := Sprite2D.new()
	ring.texture = LEVEL_UP
	ring.hframes = 10
	ring.scale = Vector2.ONE*.80
	ring.position = face.position+face.size*.5
	face.get_parent().add_child(ring)
	face.get_parent().move_child(ring,face.get_index())
	var anim := ring.create_tween()
	anim.tween_property(ring,"frame",9,.78)
	anim.tween_callback(ring.queue_free)

func _celebrate_levels() -> void:
	for who in leveled_members:
		if not sitters.has(who): continue
		var wearer: PixelUnit = sitters[who][0]
		var ring := BattleFX._sprite(wearer,LEVEL_UP)
		ring.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		ring.pixel_size = wearer.sprite_height/65.
		ring.offset.y = 35.
		ring.position = -scene.rig.camera.global_basis.z*.065
		ring.render_priority = -1
		var anim := ring.create_tween()
		anim.tween_property(ring,"frame",9,.88)
		anim.tween_callback(ring.queue_free)
	leveled_members.clear()

## The party walks back into camp. One panel: how the battle went and what it paid, then a
## cell for each member who marched, whose experience fills in front of you. `gains` is
## {who: [experience before, after]}.
func _report(news: Dictionary, gains: Dictionary) -> void:
	asking = "cheer"
	leveled_members.clear()
	for who: String in gains:
		var progress: Array = gains[who]
		if Save.standing(progress[1]).level > Save.standing(progress[0]).level:
			leveled_members.append(who)
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
				_rank_ring(face)
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
	asking = _owed()
	cheer.hide()
	_celebrate_levels()
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
	# The key pattern runs under the bar, as round the neck of a pot, on a dark band of
	# its own so it reads over bright ground as well as dark.
	Px.block(body,Rect2(0,44,Px.SIZE.x,9),Color(Px.INK,.84))
	Vase.frieze(body,Rect2(0,45,Px.SIZE.x,7),Color(Px.OCHRE,.5))
	Px.block(body,Rect2(0,53,Px.SIZE.x,1),Color(Px.OCHRE,.3))
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
		var hot := Px.hotspot(sign,Rect2(0,0,112,150),_visit.bind(person.key),person.service)
		for state in ["hover","pressed","focus"]:
			hot.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		hot.draw.connect(func():
			if hot.has_focus() or hot.is_hovered(): hot.draw_rect(Rect2(0,0,112,34),Px.OCHRE,false,1.))
		stops.append(hot)
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
		var controls_width := 170 if screen == "recruit" else 92
		Px.text(body,words,Rect2(x+88,HEAD.position.y+8,HEAD.end.x-x-88-controls_width,0),Px.SMALL,Px.MUTED)
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
	_head("队伍","%d 人在营" % _everyone().size(),"",null,view != "pack")
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
	_member_list()

func _member_list() -> void:
	var everyone := _everyone()
	if not everyone.has(member): member = "hero"
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
	# What divinity grew on him takes a place like anything else.
	if who == "hero": known.append_array(entry.get("powers",[]))
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
	return Hud._art(id,size) if node.is_empty() else _mark(node,size)

## Reach and cooldown in a few words.
func _skill_brief(id: String) -> String:
	var skill: Dictionary = SkillCatalog.get_skill(id)
	var near := int(skill.get("min_range",1))
	var far := int(skill.get("max_range",1))
	var words := "射程 %d" % near if near == far else "射程 %d–%d" % [near,far]
	if skill.has("blink"): words = "%d 格内" % int(skill.blink)
	elif skill.has("self_status") or skill.has("area_shield"): words = "自身"
	if int(skill.get("cooldown",0)) > 0: words += " · 冷却 %d" % int(skill.cooldown)
	return words

func _skill_words(who: String, id: String) -> String:
	if Save.power_words(id) != "": return Save.power_words(id)
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
	if page == "tree":
		var sources := {"随身":UnitCatalog.unit_def(_def(member)).get("skills",[])}
		var recruit := _kind(member)
		if not recruit.is_empty():
			sources["随身"] = [_basic(member),recruit.skill]
		if member == "hero" and entry.get("equipped_relic","") == "lion_pelt":
			sources["狮皮"] = ["impervious_hide"]
		var offset := x+140
		for source: String in sources:
			Px.text(body,source,Rect2(offset,y+7,26,0),Px.SMALL,Px.MUTED)
			offset += 26
			for id: String in sources[source]:
				var icon := Px.picture(body,_skill_mark(member,id,24),Rect2(offset,y,24,24))
				icon.modulate = Px.IVORY
				icon.mouse_filter = MOUSE_FILTER_PASS
				icon.tooltip_text = str(SkillCatalog.get_skill(id).name)
				offset += 26
			offset += 6
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
		if member == "hero" and key == "div": plain += Save.TIER_DIVINITY*Save.tier(entry)
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
		always.append("%s（圣物 %d 件）" % [Save.TIERS[Save.tier(entry)].name,int(entry.get("divinity",0))])
		for relic: String in entry.get("relics",["lion_pelt"]):
			always.append("圣物 "+str(Save.RELICS[relic].name))
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
		# Each technique is a medallion on a branch: filled once learnt, ringed when it
		# can be, faint while out of reach. The branches are drawn with a brush.
		var hub := func(id: String) -> Vector2:
			return corner.call(id)+Vector2(box.x*.5,15)
		var limbs := Control.new()
		limbs.size = Px.SIZE
		limbs.mouse_filter = MOUSE_FILTER_IGNORE
		body.add_child(limbs)
		limbs.draw.connect(func():
			for node: Dictionary in branch.nodes:
				if node.parent == "": continue
				var from: Vector2 = hub.call(node.parent)
				var to: Vector2 = hub.call(node.id)
				var tone := Px.GREEN if learned.has(node.id) else (Color(Px.OCHRE,.7) if learned.has(node.parent) else Color(Px.FAINT,.6))
				limbs.draw_polyline(Vase.stroke(from,to,1.2,hash(node.id)),tone,2.0 if learned.has(node.id) else 1.0)
			for node: Dictionary in branch.nodes:
				var have := learned.has(node.id)
				var ready: bool = node.parent == "" or learned.has(node.parent)
				var spot: Vector2 = hub.call(node.id)
				var open: bool = technique == node.id
				if open: Vase.roundel(limbs,spot,18,Vase.GLAZE,Px.OCHRE,1.5)
				Vase.roundel(limbs,spot,14,Px.GREEN if have else Vase.GLAZE,Px.IVORY if have or ready else Px.FAINT,1.5 if ready else 1.0))
		for node: Dictionary in branch.nodes:
			var have := learned.has(node.id)
			var ready: bool = node.parent == "" or learned.has(node.parent)
			var tint := Px.GREEN if have else (Px.IVORY if ready else Px.FAINT)
			var rect := Rect2(corner.call(node.id),Vector2(box.x,42))
			var cell := Px._control(body,"",rect,_pick_technique.bind(node.id),Px.SMALL)
			var none := StyleBoxEmpty.new()
			Px._paint(cell,none,none,none,Color.TRANSPARENT,Color.TRANSPARENT)
			var spot: Vector2 = hub.call(node.id)
			Px.picture(body,_mark(node,24),Rect2(spot-Vector2(12,12),Vector2(24,24))).modulate = Vase.GLAZE if have else tint
			Px.text(body,node.name,Rect2(rect.position+Vector2(0,31),Vector2(box.x,0)),Px.SMALL,Px.IVORY if technique == node.id else tint,HORIZONTAL_ALIGNMENT_CENTER)
			# What it costs, on a bead at the medallion's shoulder; a tick once learnt.
			if have: Px.picture(body,Px.icon("done",8),Rect2(spot+Vector2(10,-16),Vector2(8,8))).modulate = Px.GREEN
			else: Px.text(body,str(node.cost),Rect2(spot+Vector2(11,-17),Vector2(12,0)),Px.SMALL,Px.MUTED if ready else Px.FAINT)
			cells.append(cell)
			ids.append(node.id)
	Px.chain(cells)
	cells[0].focus_neighbor_top = cells[0].get_path_to(leaves[1])
	leaves[0].focus_neighbor_bottom = leaves[0].get_path_to(cells[0])
	leaves[1].focus_neighbor_bottom = leaves[1].get_path_to(cells[0])
	for cell in cells: cell.focus_neighbor_left = cell.get_path_to(rows[_everyone().find(member)])
	y += 18+3*52+2
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
	for key: String in [Px.technique_stamp(node.id),str(node.get("skill","")),str(node.get("trait",""))]:
		if key != "" and ResourceLoader.exists(Px.icon_path(key)): return Px.icon(key,size)
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
	var cell := Vector2(floorf(area.size.x/columns),62)
	var inner := _scroll(key,area,ceili(things.size()/float(columns))*cell.y)
	var cells: Array[Button] = []
	for i in things.size():
		var item: String = things[i]
		var at := Vector2((i%columns)*cell.x,(i/columns)*cell.y)
		var open := chosen == item
		# Each thing lies on a round plate ringed in the colour of its rarity; the open one
		# has a second ring. The plate is the button, and lights when pointed at.
		var hub := at+Vector2(roundf((cell.x-4)*.5),21)
		var tint := _tint(item)
		var button := Px._control(inner,"",Rect2(hub-Vector2(20,20),Vector2(40,40)),pick.bind(item),Px.SMALL)
		var plain := Px.rounded(Px.flat(Color(Vase.GLAZE,.9),Color(tint,1.0 if open else .55),[2,2,2,2] if open else [1,1,1,1]),20)
		var lit := Px.rounded(Px.flat(Color(tint.darkened(.7),.95),Px.IVORY,[2,2,2,2]),20)
		Px._paint(button,plain,lit,plain,Px.IVORY,Px.IVORY)
		button.tooltip_text = "%s · %s" % [Save.GOODS[item].name,Save.effect_of(item)]
		if open:
			var halo := Px.rounded(Px.flat(Color.TRANSPARENT,Color(Px.OCHRE,.8),[1,1,1,1]),24)
			var ring := Panel.new()
			ring.add_theme_stylebox_override("panel",halo)
			ring.position = hub-Vector2(24,24)
			ring.size = Vector2(48,48)
			ring.mouse_filter = MOUSE_FILTER_IGNORE
			inner.add_child(ring)
		Px.picture(inner,Px.icon(Save.art(item),24),Rect2(hub-Vector2(12,12),Vector2(24,24))).modulate = Px.IVORY
		var corner := str(mark.call(item))
		if corner != "": Px.text(inner,corner,Rect2(at+Vector2(0,0),Vector2(cell.x-6,0)),Px.SMALL,Px.IVORY,HORIZONTAL_ALIGNMENT_RIGHT)
		var price := int(cost.call(item))
		if price > 0: _price(inner,price,Vector2(at.x+roundf((cell.x-4)*.5)-(15+Px.width_of(str(price),Px.SMALL))*.5,at.y+46))
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
	Px.picture(body,Px.icon(Save.art(item),48),Rect2(x,side.position.y+14,48,48)).modulate = Px.IVORY
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

func _toggle_drill() -> void:
	drill_open = not drill_open
	if drill_open:
		page = "tree"
		technique = ""
	_render()

func _recruit() -> void:
	_person_head("recruit")
	var service := Px.button(body,"招募名册" if drill_open else "操练",Rect2(HEAD.end.x-156,HEAD.position.y+10,70,28),_toggle_drill)
	tabs_row.append(service)
	if drill_open:
		_member_list()
		return
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
	Px.picture(body,Px.face(_look("hero"),32),Rect2(x,y,32,32))
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

## `stamp` names a drawing to set in a medallion across the panel's upper left corner, in
## `tone`; the heading then starts to the right of it, at x+56.
func _modal(width: float, height: float, stamp := "", tone := Px.OCHRE) -> Rect2:
	Px.block(body,Rect2(Vector2.ZERO,Px.SIZE),Color(Px.INK,.6)).mouse_filter = MOUSE_FILTER_STOP
	var rect := Rect2((Px.SIZE-Vector2(width,height))*.5,Vector2(width,height)).abs()
	Px.sheet(body,rect,.96)
	if stamp == "": return rect
	var hub := rect.position+Vector2(44,16)
	var seal := Control.new()
	seal.size = Px.SIZE
	seal.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(seal)
	seal.draw.connect(func():
		Vase.roundel(seal,hub,30,Vase.GLAZE,tone,2)
		Vase.roundel(seal,hub,26,tone,Vase.GLAZE,1))
	Px.picture(body,Px.icon(stamp,32),Rect2(hub-Vector2(16,16),Vector2(32,32))).modulate = Vase.GLAZE
	# The key pattern under the heading, where a plain rule would be.
	Vase.frieze(body,Rect2(rect.position.x+28,rect.position.y+62,width-56,7),Color(tone,.45))
	return rect

func _ask_boon() -> void:
	var rect := _modal(520,296,"boon")
	var x := rect.position.x+28
	var y := rect.position.y+22
	Px.text(body,"第一章 · 涅墨亚",Rect2(x+56,y-6,300,0),Px.SMALL,Px.OCHRE)
	Px.text(body,"涅墨亚狮子已败",Rect2(x+56,y+8,400,0),Px.TITLE,Px.IVORY)
	y += 62
	Px.text(body,"狮皮归主角：物理减伤 3，受背击倍率降至 1.25。\n不坏之皮：免疫物理伤害 1 回合，冷却 4 回合。",Rect2(x,y,464,0),Px.SMALL,Px.MUTED)
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
		asking = _owed()
		chapter = _chapter_of("2-1")
		picked.march = -1
	_render()

## Over a beaten boss: take the relic, or spare them. Laid out plainly: who fell, the road
## of seven relics, the two roads as cards, the one button that settles it. What keeps it
## from being a form is borrowed from painted pots: medallions that sit across the edge of
## what they belong to, corners cut as a potter trims a tag, the key pattern for a rule,
## and lines drawn as a brush draws them. Pressing a card only leans toward it.
func _ask_verdict() -> void:
	var chapter_no := int(entry.verdict)
	var case: Dictionary = Save.VERDICTS[chapter_no]
	var relic: Dictionary = Save.RELICS[case.relic]
	var held: Array = entry.get("relics",["lion_pelt"])
	var kept: Array = entry.get("spared",[])
	var now := Save.tier_of(held.size())
	var then := Save.tier_of(held.size()+1)
	var rank: Dictionary = Save.TIERS[then]
	var divine := Color(str(rank.tint)) if then > 0 else Px.OCHRE
	var mortal := Px.GREEN
	var guest: Dictionary = case.spared
	Px.block(body,Rect2(Vector2.ZERO,Px.SIZE),Color(Px.INK,.93)).mouse_filter = MOUSE_FILTER_STOP
	var mid := Px.SIZE.x*.5
	var card := Vector2(396,250)
	var card_top := 196.0
	var cut := 14.0
	var foot := card.y-112
	var take_at := Rect2(mid-14-card.x,card_top,card.x,card.y)
	var spare_at := Rect2(mid+14,card_top,card.x,card.y)
	# The scales, as a thing of bronze: the one who fell is the boss the beam turns on, the
	# beam runs out to either side of the name, and a pan hangs at each end beside it.
	# Relics lie in the left pan, the spared in the right; the fuller pan sinks.
	var pivot := Vector2(mid,40)
	var arm := 196.0
	var drop := 54.0
	var heavy := held.size()+(1 if leaning == "take" else 0)
	var light := kept.size()+(1 if leaning == "spare" else 0)
	var tilt := clampf((heavy-light)*1.5,-6.0,6.0)
	var yet := maxi(0,6-(held.size()-1)-kept.size()-1)   # bosses still to come after this one
	# Everything painted rather than laid out.
	var art := Control.new()
	art.size = Px.SIZE
	art.mouse_filter = MOUSE_FILTER_IGNORE
	art.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(art)
	art.draw.connect(func():
		# The two cards.
		for side: Array in [[take_at,"take",divine],[spare_at,"spare",mortal]]:
			var rect: Rect2 = side[0]
			var tone: Color = side[2]
			var chosen: bool = leaning == side[1]
			var back: bool = leaning != "" and not chosen
			var shade := Color(.5,.5,.5) if back else Color.WHITE
			var p := rect.position
			var outline := PackedVector2Array([p,p+Vector2(card.x-cut,0),p+Vector2(card.x,cut),p+card,p+Vector2(cut,card.y),p+Vector2(0,card.y-cut)])
			var uvs := PackedVector2Array()
			for point in outline: uvs.append(point/128.0)
			art.draw_colored_polygon(outline,shade,uvs,Vase.glaze())
			# The lower part, where the price is told, is washed in the road's colour; its
			# upper edge is a brush stroke.
			var brow := Vase.stroke(p+Vector2(0,foot),p+Vector2(card.x,foot),1.8,chapter_no*11+(1 if side[1] == "take" else 2))
			var wash := PackedVector2Array(brow)
			wash.append_array([p+card,p+Vector2(cut,card.y),p+Vector2(0,card.y-cut)])
			art.draw_colored_polygon(wash,Color(tone.darkened(.78),.5 if back else .95))
			art.draw_polyline(brow,Color(tone,.25 if back else .7),1.5)
			outline.append(p)
			art.draw_polyline(outline,Color(tone,.2 if back else (1.0 if chosen else .5)),2.0 if chosen else 1.0)
			if chosen:
				# A second line just inside, as on the lip of a cup.
				var inner := PackedVector2Array()
				for point in [Vector2(4,4),Vector2(card.x-cut-2,4),Vector2(card.x-4,cut+2),Vector2(card.x-4,card.y-4),Vector2(cut+2,card.y-4),Vector2(4,card.y-cut-2),Vector2(4,4)]:
					inner.append(p+point)
				art.draw_polyline(inner,Color(tone,.35),1.0)
			# The medallion sits across the card's upper edge.
			var hub := p+Vector2(40,12)
			var size := 30.0 if chosen else 27.0
			Vase.roundel(art,hub,size,Vase.GLAZE,Color(tone,.3 if back else 1.0),2)
			Vase.roundel(art,hub,size-4,Color(tone.darkened(.5 if back else 0.0),1),Vase.GLAZE,1))
	Px.text(body,"第 %d 章" % chapter_no,Rect2(0,70,Px.SIZE.x,0),Px.SMALL,Px.OCHRE,HORIZONTAL_ALIGNMENT_CENTER)
	Px.text(body,"%s倒下了" % case.boss,Rect2(0,82,Px.SIZE.x,0),Px.TITLE,Px.IVORY,HORIZONTAL_ALIGNMENT_CENTER)
	var rig := Control.new()
	rig.size = Px.SIZE
	rig.mouse_filter = MOUSE_FILTER_IGNORE
	rig.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(rig)
	var shown := {"tilt":verdict_tilt}
	var bronze := Px.OCHRE
	var shadow := Px.OCHRE.darkened(.42)
	# Where a thing sits in a pan when the beam is tipped `degrees`: `side` -1 left, +1 right.
	var seat := func(side: float, place: int, count: int, degrees: float) -> Vector2:
		# The pan hangs plumb from the foot of the ring the beam ends in.
		var end := pivot+Vector2(side*(arm+6)*cos(deg_to_rad(degrees)),-side*(arm+6)*sin(deg_to_rad(degrees)))+Vector2(0,10)
		var step := minf(19.0,80.0/maxf(1.0,count-1.0))
		return end+Vector2((place-(count-1)*.5)*step,drop-7)
	rig.draw.connect(func():
		var degrees: float = shown.tilt
		var lean := Vector2(cos(deg_to_rad(degrees)),-sin(deg_to_rad(degrees)))
		var across := Vector2(-lean.y,lean.x)
		for side in [-1.0,1.0]:
			# The chains start from one link under the ring at the beam's end, so they fall
			# straight from it and spread, instead of gathering at its side.
			var ring: Vector2 = pivot+lean*(arm+6)*side
			var end := ring+Vector2(0,10)
			rig.draw_line(ring+Vector2(0,6),end,bronze,2.0)
			var rim := end+Vector2(0,drop)
			var mine: bool = leaning == ("take" if side < 0 else "spare")
			var tone: Color = divine if side < 0 else mortal
			# Chains of beads from the beam's end out to the rim.
			for hold in [-46.0,0.0,46.0]:
				var grip := rim+Vector2(hold,0)
				var links := 9
				for link in links:
					rig.draw_circle(end.lerp(grip,(link+1.0)/(links+1.0)),1.7,bronze if link % 2 == 0 else shadow)
			# The far rim of the pan, seen from a little above.
			rig.draw_line(rim+Vector2(-50,-1),rim+Vector2(50,-1),shadow,2.0)
			# What lies in it.
			var count := heavy if side < 0 else light
			for n in count:
				var fresh := n >= (held.size() if side < 0 else kept.size())
				var at: Vector2 = seat.call(side,n,count,degrees)
				var fill := tone if fresh or side > 0 else Color(str(Save.TIERS[Save.tier_of(n+1)].tint))
				Vase.roundel(rig,at,10 if fresh else 8,fill,Px.IVORY,1.5 if fresh else 1.0)
				var stamp: Texture2D
				if side < 0: stamp = Px.icon(str(relic.icon) if fresh else str(Save.RELICS[held[n]].icon),10)
				else: stamp = Px.icon(str(case.icon) if fresh else str(Save.VERDICTS[int(kept[n])].icon),10)
				rig.draw_texture_rect(stamp,Rect2(at-Vector2(5,5),Vector2(10,10)),false,Vase.GLAZE)
			# The pan itself: a shallow bowl of beaten bronze, darker beneath, bright on the lip.
			var bowl := PackedVector2Array()
			for i in 17:
				var t := -1.0+i/8.0
				bowl.append(rim+Vector2(54*t,12*(1.0-t*t)))
			rig.draw_colored_polygon(bowl,bronze)
			# The underside in shadow: a crescent along the bottom of the bowl.
			var belly := PackedVector2Array()
			for i in 15:
				var t := -.86+i*.86/7.0
				belly.append(rim+Vector2(54*t,12*(1.0-t*t)))
			for i in 13:
				var t := .74-i*.74/6.0
				belly.append(rim+Vector2(54*t,12*(1.0-t*t)-5.5*(1.0-t*t/.55)))
			rig.draw_colored_polygon(belly,shadow)
			rig.draw_line(rim+Vector2(-54,0),rim+Vector2(54,0),tone if mine else Px.IVORY,2.0 if mine else 1.0)
			# A row of dots punched round the bowl, and a knob under it.
			for dot in 7: rig.draw_circle(rim+Vector2((dot-3)*12,4.5-absf(dot-3)*.5),1.0,Vase.GLAZE)
			rig.draw_circle(rim+Vector2(0,13.5),2.5,bronze)
		# The beam: thick at the boss, tapering to a curl at each end.
		for side in [-1.0,1.0]:
			var end: Vector2 = pivot+lean*arm*side
			var root: Vector2 = pivot+lean*22*side
			rig.draw_colored_polygon(PackedVector2Array([root-across*5,end-across*2.5,end+across*2.5,root+across*5]),bronze)
			rig.draw_line(root+across*3,end+across*1.5,shadow,2.0)
			# Collars along it, as a turned bar has.
			for mark in [.34,.38,.72]:
				var at: Vector2 = root.lerp(end,mark)
				rig.draw_line(at-across*6.5,at+across*6.5,bronze,3.0)
			# The volute it ends in.
			var eye: Vector2 = end+lean*side*6
			rig.draw_arc(eye,6.0,0,TAU,20,bronze,3.0)
			rig.draw_circle(eye,2.0,bronze)
		# The boss: who is being weighed. A ring to hang it by; under it, a bead for each
		# of those still to come.
		rig.draw_arc(pivot+Vector2(0,-30),4.0,0,TAU,16,bronze,2.0)
		rig.draw_line(pivot+Vector2(0,-26),pivot+Vector2(0,-22),bronze,3.0)
		Vase.roundel(rig,pivot,25,bronze,Px.IVORY,1.5)
		Vase.roundel(rig,pivot,21,bronze,Vase.GLAZE,1)
		rig.draw_texture_rect(Px.icon(str(case.icon),30),Rect2(pivot-Vector2(15,15),Vector2(30,30)),false,Vase.GLAZE)
		for n in yet:
			rig.draw_arc(Vector2(mid+(n-(yet-1)*.5)*11,118),3.0,0,TAU,12,Color(bronze,.75),1.5))
	# The beam swings to where the lean puts it, a little past, and back.
	if absf(verdict_tilt-tilt) > .01:
		var swing := rig.create_tween()
		swing.tween_method(func(value: float):
			shown.tilt = value
			rig.queue_redraw(),verdict_tilt,tilt,.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		verdict_tilt = tilt
	# What the pans add up to, said plainly under each.
	var rank_now: Dictionary = Save.TIERS[then if leaning == "take" else now]
	Px.text(body,"圣物 %d 件 · %s" % [heavy,rank_now.name],Rect2(mid-arm-90,152,180,0),Px.SMALL,Color(str(rank_now.tint)),HORIZONTAL_ALIGNMENT_CENTER)
	Px.text(body,"放过 %d 位" % light if light > 0 else "还没有放过谁",Rect2(mid+arm-90,152,180,0),Px.SMALL,mortal if light > 0 else Px.FAINT,HORIZONTAL_ALIGNMENT_CENTER)
	var reach := 7-light
	if yet > 0 or reach < 6:
		Px.text(body,("还有 %d 位首领" % yet if yet > 0 else "这是最后一位")+("，最多到%s" % Save.TIERS[Save.tier_of(reach)].name if reach < 6 else ""),Rect2(mid-120,128,240,0),Px.SMALL,Px.FAINT,HORIZONTAL_ALIGNMENT_CENTER)
	# What is written on the cards.
	var taking := _verdict_card(take_at,"take",divine,str(relic.icon),"夺圣物",str(relic.name),"")
	var sparing := _verdict_card(spare_at,"spare",mortal,str(case.icon),"放过%s" % case.pronoun,
		str(guest.name) if not guest.is_empty() else "一位与%s有渊源的人" % case.pronoun,str(guest.get("title","")))
	var pane: Control = taking.get_meta("pane")
	var y := 86.0
	y = _verdict_line(pane,"带着",str(relic.held),y,Px.OCHRE)
	y = _verdict_line(pane,"使用",str(relic.called),y,Px.OCHRE)
	Px.text(pane,"圣物共 %d 件" % (held.size()+1),Rect2(18,foot+12,160,0),Px.BODY,Px.IVORY)
	if then > now:
		Px.picture(pane,Px.icon("divinity",16),Rect2(card.x-18-16,foot+11,16,16)).modulate = divine
		Px.text(pane,"升为 %s" % rank.name,Rect2(card.x-18-22-140,foot+12,140,0),Px.BODY,divine,HORIZONTAL_ALIGNMENT_RIGHT)
		var fy := _verdict_line(pane,"得到","%s神性 +%d。" % [rank.gain,Save.TIER_DIVINITY],foot+36,divine)
		fy = _verdict_line(pane,"神力","「%s」或「%s」，取其一。" % [Save.POWERS[then-1][0][1],Save.POWERS[then-1][1][1]],fy,divine)
		if rank.cost != "": _verdict_line(pane,"失去",str(rank.cost),fy,Px.RED.lightened(.45))
	else:
		Px.text(pane,"仍是 %s" % rank.name,Rect2(card.x-18-160,foot+12,160,0),Px.BODY,Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
		if then+1 < Save.TIERS.size():
			_verdict_line(pane,"还差","再有 %d 件，就是%s。" % [int(Save.TIERS[then+1].from)-(held.size()+1),Save.TIERS[then+1].name],foot+36,Px.MUTED)
	pane = sparing.get_meta("pane")
	_verdict_line(pane,"加入",str(guest.words) if not guest.is_empty() else "会有人因此来到营地。是谁，还没有写到这一章。",86.0,mortal)
	Px.text(pane,"圣物仍是 %d 件" % held.size(),Rect2(18,foot+12,160,0),Px.BODY,Px.IVORY)
	Px.text(pane,"仍是 %s" % Save.TIERS[now].name,Rect2(card.x-18-160,foot+12,160,0),Px.BODY,Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	var sy := _verdict_line(pane,"得到","营地多一位英雄，出战时可以带上。",foot+36,mortal)
	_verdict_line(pane,"失去","%s，此后再也拿不到。" % relic.name,sy,Px.RED.lightened(.45))
	# The foot: a rounded tag that says what pressing it does, a brushed line to either side.
	var words := "先选一边"
	if leaning == "take": words = "夺走%s" % relic.name
	elif leaning == "spare": words = "放过%s" % case.pronoun
	var tag := Rect2(mid-116,card_top+card.y+20,232,32)
	var settle := Px._control(body,words,tag,_settle_verdict,Px.BODY)
	var fill := Px.RED if leaning != "" else Color(Px.INK,.7)
	var rest := Px.flat(fill,Px.OCHRE if leaning != "" else Px.FAINT,[1,1,1,1])
	var lit := Px.flat(Px.RED.lightened(.14),Px.IVORY,[1,1,1,1])
	for style: StyleBoxFlat in [rest,lit]:
		style.set_corner_radius_all(16)
		style.anti_aliasing = false
	Px._paint(settle,rest,lit,rest,Px.IVORY,Px.IVORY)
	settle.disabled = leaning == ""
	var flank := Control.new()
	flank.size = Px.SIZE
	flank.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(flank)
	flank.draw.connect(func():
		for side in [-1.0,1.0]:
			var from := Vector2(mid+side*(tag.size.x*.5+12),tag.get_center().y)
			flank.draw_polyline(Vase.stroke(from,from+Vector2(side*70,0),1.2,chapter_no+int(side)*5),Color(Px.OCHRE,.5),1.5)
			flank.draw_circle(from+Vector2(side*77,0),2.0,Color(Px.OCHRE,.7)))
	Px.text(body,"两条路都不能回头。",Rect2(0,tag.end.y+8,Px.SIZE.x,0),Px.SMALL,Px.MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	taking.focus_neighbor_right = taking.get_path_to(sparing)
	sparing.focus_neighbor_left = sparing.get_path_to(taking)
	for side: Button in [taking,sparing]:
		side.focus_neighbor_bottom = side.get_path_to(settle)
	settle.focus_neighbor_top = settle.get_path_to(sparing if leaning == "spare" else taking)
	if leaning != "": _focus(settle)
	verdict_spots = {"take":take_at,"spare":spare_at,"socket":seat.call(-1.0,held.size(),held.size()+1,tilt),
		"haven":seat.call(1.0,kept.size(),kept.size()+1,tilt),"saved":str(case.icon),
		"divine":divine,"mortal":mortal,"cut":cut,"rises":then > now,"icon":str(relic.icon),"tag":tag}
	if lean_fresh and leaning != "":
		lean_fresh = false
		_answer_lean(taking.get_meta("pane") if leaning == "take" else sparing.get_meta("pane"))

## The screen's answer to leaning one way: the card's edge flares and settles, its writing
## rises into place, a ring spreads from its medallion, and (when taking) from the socket
## the relic would fill.
func _answer_lean(pane: Control) -> void:
	var rect: Rect2 = verdict_spots[leaning]
	var tone: Color = verdict_spots.divine if leaning == "take" else verdict_spots.mortal
	var rest := pane.position
	pane.position = rest+Vector2(0,7)
	pane.modulate.a = 0.0
	var rise := pane.create_tween().set_parallel()
	rise.tween_property(pane,"position",rest,.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rise.tween_property(pane,"modulate:a",1.0,.22)
	_flare(rect,tone,.42)
	_burst(rect.position+Vector2(40,12),30,tone,.45)
	_burst(verdict_spots.socket if leaning == "take" else verdict_spots.haven,11,tone,.45,.05)
	_burst(Vector2(verdict_spots.tag.get_center()),19,Color(Px.RED.lightened(.3),.7),.35,.1,Vector2(5.2,.82))

## The outline of a verdict card, bright for a moment and then gone.
func _flare(rect: Rect2, tone: Color, seconds: float) -> void:
	var cut: float = verdict_spots.cut
	var glow := Control.new()
	glow.position = rect.position
	glow.mouse_filter = MOUSE_FILTER_IGNORE
	floats.add_child(glow)
	glow.draw.connect(func():
		var size := rect.size
		var outline := PackedVector2Array([Vector2.ZERO,Vector2(size.x-cut,0),Vector2(size.x,cut),size,Vector2(cut,size.y),Vector2(0,size.y-cut),Vector2.ZERO])
		glow.draw_polyline(outline,Color(tone.lightened(.4),1),4.0)
		glow.draw_colored_polygon(outline,Color(tone,.10)))
	var fade := glow.create_tween()
	fade.tween_property(glow,"modulate:a",0.0,seconds).set_ease(Tween.EASE_OUT)
	fade.tween_callback(glow.queue_free)

## A ring that spreads from a point and thins to nothing. `squash` flattens it (for a ring
## round something wide).
func _burst(at: Vector2, radius: float, tone: Color, seconds := .45, wait := 0.0, squash := Vector2.ONE) -> void:
	var ring := Control.new()
	ring.position = at
	ring.mouse_filter = MOUSE_FILTER_IGNORE
	ring.scale = squash*.8
	ring.modulate.a = 0.0
	floats.add_child(ring)
	ring.draw.connect(func(): ring.draw_arc(Vector2.ZERO,radius,0,TAU,48,tone,2.0))
	var spread := ring.create_tween()
	if wait > 0: spread.tween_interval(wait)
	spread.tween_property(ring,"modulate:a",1.0,.01)
	spread.tween_property(ring,"scale",squash*1.45,seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	spread.parallel().tween_property(ring,"modulate:a",0.0,seconds).set_ease(Tween.EASE_IN)
	spread.tween_callback(ring.queue_free)

## The whole screen washed in one colour for a moment.
func _wash(tone: Color, peak: float, seconds: float, wait := 0.0) -> void:
	var sheet := Px.block(floats,Rect2(Vector2.ZERO,Px.SIZE),tone)
	sheet.modulate.a = 0.0
	var pulse := sheet.create_tween()
	if wait > 0: pulse.tween_interval(wait)
	pulse.tween_property(sheet,"modulate:a",peak,seconds*.25)
	pulse.tween_property(sheet,"modulate:a",0.0,seconds*.75).set_ease(Tween.EASE_OUT)
	pulse.tween_callback(sheet.queue_free)

## Taking, played out: the relic leaves its card for its place on the road; where it lands
## rings spread and the screen takes its colour. If that makes a new tier of him, fire
## comes down on the spot from the sky. Returns how long it runs.
func _play_taking() -> float:
	var tone: Color = verdict_spots.divine
	var from: Vector2 = (verdict_spots.take as Rect2).position+Vector2(40,12)
	var to: Vector2 = verdict_spots.socket
	var coin := Control.new()
	coin.position = from
	coin.mouse_filter = MOUSE_FILTER_IGNORE
	floats.add_child(coin)
	coin.draw.connect(func():
		Vase.roundel(coin,Vector2.ZERO,10,tone,Px.IVORY,1.5))
	Px.picture(coin,Px.icon(str(verdict_spots.icon),10),Rect2(-5,-5,10,10)).modulate = Vase.GLAZE
	coin.scale = Vector2.ONE*2.6
	var flight := coin.create_tween()
	# Up and over, not straight across.
	flight.tween_method(func(t: float):
		coin.position = from.lerp(to,t)+Vector2(0,-70*sin(t*PI))
		coin.scale = Vector2.ONE*lerpf(2.6,1.0,t),0.0,1.0,.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flight.tween_interval(.5)
	flight.tween_property(coin,"modulate:a",0.0,.2)
	flight.tween_callback(coin.queue_free)
	_flare(verdict_spots.take,tone,.5)
	_burst(to,15,tone,.45,.5)
	_burst(to,15,Color(Px.IVORY,.8),.6,.58)
	_wash(tone,.22,.6,.5)
	if not verdict_spots.rises: return 1.15
	# A new tier: the sky answers.
	var bolt := Sprite2D.new()
	bolt.texture = preload("res://art/original/fx/lightning.png")
	bolt.hframes = 10
	bolt.position = to - Vector2(0,72)
	bolt.scale = Vector2.ONE*2.0
	bolt.modulate = tone
	bolt.hide()
	floats.add_child(bolt)
	var strike := bolt.create_tween()
	strike.tween_interval(.62)
	strike.tween_callback(bolt.show)
	strike.tween_property(bolt,"frame",9,.52)
	strike.tween_callback(bolt.queue_free)
	_wash(Px.IVORY,.45,.5,.62)
	_burst(to,15,Px.IVORY,.7,.66,Vector2(1.7,1.7))
	return 1.6

## Sparing, played out: the other road goes dark, rings spread slowly from the one who
## lives, and they go to take their place at the far end of the road.
func _play_sparing() -> float:
	var tone: Color = verdict_spots.mortal
	var rect: Rect2 = verdict_spots.spare
	var hub := rect.position+Vector2(40,12)
	var shade := Px.block(floats,verdict_spots.take,Color(Px.INK,1))
	shade.modulate.a = 0.0
	var close := shade.create_tween()
	close.tween_property(shade,"modulate:a",.75,.5)
	close.tween_interval(.5)
	close.tween_property(shade,"modulate:a",0.0,.2)
	close.tween_callback(shade.queue_free)
	_flare(rect,tone,.6)
	for n in 2: _burst(hub,30,Color(tone,1.0-n*.35),.8,n*.2)
	_wash(tone,.12,.9,.1)
	# The one who lives takes a place at the far end of the road.
	var to: Vector2 = verdict_spots.haven
	var coin := Control.new()
	coin.position = hub
	coin.mouse_filter = MOUSE_FILTER_IGNORE
	floats.add_child(coin)
	coin.draw.connect(func(): Vase.roundel(coin,Vector2.ZERO,10,tone,Px.IVORY,1.5))
	Px.picture(coin,Px.icon(str(verdict_spots.saved),10),Rect2(-5,-5,10,10)).modulate = Vase.GLAZE
	coin.scale = Vector2.ONE*2.6
	var walk := coin.create_tween()
	walk.tween_interval(.15)
	# Slower and lower than a relic seized: walked there, not thrown.
	walk.tween_method(func(t: float):
		coin.position = hub.lerp(to,t)+Vector2(0,-34*sin(t*PI))
		coin.scale = Vector2.ONE*lerpf(2.6,1.0,t),0.0,1.0,.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	walk.tween_interval(.3)
	walk.tween_property(coin,"modulate:a",0.0,.2)
	walk.tween_callback(coin.queue_free)
	_burst(to,15,tone,.6,.85)
	return 1.3

## The writing on one of the two cards, over a button the size of the card. The card not
## leant toward falls back. Returns the button; its "pane" is where more lines go.
func _verdict_card(rect: Rect2, way: String, tone: Color, stamp: String, kind: String, title: String, sub: String) -> Button:
	var press := Px._control(body,"",rect,_lean.bind(way),Px.BODY)
	var none := StyleBoxEmpty.new()
	Px._paint(press,none,none,none,Color.TRANSPARENT,Color.TRANSPARENT)
	press.set_meta("way",way)
	# Reaching a card with the keys leans toward it, as pointing and pressing does.
	# Merely passing the pointer over a card must not: the kit gives focus on hover.
	press.focus_entered.connect(func():
		if leaning != way and not press.is_hovered(): _lean.call_deferred(way))
	var pane := Control.new()
	pane.position = rect.position
	pane.size = rect.size
	pane.mouse_filter = MOUSE_FILTER_IGNORE
	if leaning != "" and leaning != way: pane.modulate = Color(1,1,1,.4)
	body.add_child(pane)
	press.set_meta("pane",pane)
	var chosen := leaning == way
	var size := 34 if chosen else 30
	Px.picture(pane,Px.icon(stamp,size),Rect2(40-size*.5,12-size*.5,size,size)).modulate = Vase.GLAZE
	Px.text(pane,kind,Rect2(80,14,120,0),Px.SMALL,tone)
	Px.text(pane,title,Rect2(80,26,rect.size.x-98,0),Px.TITLE if Px.width_of(title,Px.TITLE) <= rect.size.x-98 else Px.BODY,Px.IVORY)
	if sub != "": Px.text(pane,sub,Rect2(rect.size.x-34-140,14,140,0),Px.SMALL,Px.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	# The key pattern for a rule under the name, fading out toward the cut corner.
	Vase.frieze(pane,Rect2(18,64,rect.size.x-36,7),Color(tone,.45))
	return press

## A labelled line on a verdict card; returns where the next one goes.
func _verdict_line(pane: Control, label: String, words: String, y: float, tone: Color) -> float:
	var room := pane.size.x-70
	var length := Px.width_of(words,Px.BODY)
	# A last line of one mark alone looks like a slip: break a little sooner.
	if length > room and fmod(length,room) < 18: room -= 26
	Px.block(pane,Rect2(18,y+6,3,3),tone)
	Px.text(pane,label,Rect2(26,y+1,30,0),Px.SMALL,tone)
	Px.text(pane,words,Rect2(58,y,room,0),Px.BODY,Px.IVORY)
	return y+maxi(1,ceili(length/room))*16+6

func _lean(way: String) -> void:
	if settling: return
	lean_fresh = leaning != way
	leaning = way
	_render()

func _settle_verdict() -> void:
	if leaning == "" or settling: return
	# What was chosen is shown happening before it is written down.
	settling = true
	Soundscape.cue("warning" if leaning == "take" and verdict_spots.get("rises",false) else "confirm")
	await get_tree().create_timer(_play_taking() if leaning == "take" else _play_sparing()).timeout
	settling = false
	if not is_inside_tree() or not Save.VERDICTS.has(int(entry.get("verdict",0))): return
	var chapter_no := int(entry.verdict)
	var case: Dictionary = Save.VERDICTS[chapter_no]
	var next: Dictionary = entry.duplicate(true)
	next.erase("verdict")
	if leaning == "take":
		var relics: Array = next.get("relics",["lion_pelt"])
		relics.append(case.relic)
		next.relics = relics
		next.divinity = relics.size()
	else:
		var spared: Array = next.get("spared",[])
		spared.append(chapter_no)
		next.spared = spared
	if _keep(next):
		note = "%s归他了。" % str(Save.RELICS[case.relic].name) if leaning == "take" else "%s活了下来。" % case.boss
		note_tone = Px.OCHRE if leaning == "take" else Px.GREEN
		leaning = ""
		asking = _owed()
	_render()

## A new tier of divinity: what it gives and takes, and the one technique of two that
## grows on him with it. The choice is for good.
func _ask_power() -> void:
	var at := (entry.get("powers",[]) as Array).size()
	var rank: Dictionary = Save.TIERS[at+1]
	var tone := Color(str(rank.tint))
	var rect := _modal(748,344,"divinity",tone)
	var x := rect.position.x+28
	var y := rect.position.y+22
	Px.text(body,"圣物 %d 件 · 神性升阶" % int(entry.get("divinity",0)),Rect2(x+56,y-6,400,0),Px.SMALL,Px.OCHRE)
	Px.text(body,rank.name,Rect2(x+56,y+8,400,0),Px.TITLE,tone)
	# A matching painted bust accompanies the rank that is being chosen.
	Px.picture(body,load("res://art/original/portraits/hero-tier%d.png" % (at+1)),Rect2(x-8,y+74,168,210))
	x += 184
	y += 62
	Px.text(body,"得到",Rect2(x,y,40,0),Px.SMALL,Px.OCHRE)
	Px.text(body,"%s神性 +%d。" % [rank.gain,Save.TIER_DIVINITY],Rect2(x+40,y,464,0),Px.SMALL,Px.IVORY)
	y += 20
	if rank.cost != "":
		Px.text(body,"失去",Rect2(x,y,40,0),Px.SMALL,Px.RED.lightened(.4))
		Px.text(body,rank.cost,Rect2(x+40,y,464,0),Px.SMALL,Px.IVORY)
		y += 20
	y += 6
	Px.rule(body,Vector2(x,y),504,Color(Px.OCHRE,.3))
	y += 12
	Px.text(body,"身上长出了凡人没有的东西。两样里取一样，取了不能改；它和别的招式一样占出战的格子。",Rect2(x,y,504,0),Px.SMALL,Px.MUTED)
	y += 40
	var choices: Array[Button] = []
	for power: Array in Save.POWERS[at]:
		var choice := Px.button(body,power[1],Rect2(x,y,96,34),_take_power.bind(power[0]))
		choice.icon = Px.icon(power[0],24)
		choice.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.add_theme_color_override("icon_normal_color",tone)
		choices.append(choice)
		Px.text(body,power[2],Rect2(x+108,y+2,396,0),Px.SMALL,Px.IVORY)
		y += 48
	Px.chain(choices)
	_focus(choices[0])

func _take_power(id: String) -> void:
	var next: Dictionary = entry.duplicate(true)
	var powers: Array = next.get("powers",[])
	powers.append(id)
	next.powers = powers
	if _keep(next):
		asking = _owed()
		note = "%s 留在了他身上。" % str(SkillCatalog.get_skill(id).name)
		note_tone = Color(str(Save.TIERS[Save.tier(next)].tint))
	_render()

func _ask_system() -> void:
	var rect := _modal(260,172,"system")
	var x := rect.position.x+28
	Px.text(body,"系统",Rect2(x+56,rect.position.y+22,200,0),Px.TITLE,Px.IVORY)
	var choices: Array[Button] = [
		Px.row(body,"回到营地",Rect2(x-10,rect.position.y+80,224,24),false,_set_asking.bind("")),
		Px.row(body,"回到首页",Rect2(x-10,rect.position.y+106,224,24),false,get_tree().change_scene_to_file.bind(TITLE)),
		Px.row(body,"离开游戏",Rect2(x-10,rect.position.y+132,224,24),false,Soundscape.quit_game)]
	Px.chain(choices)
	_focus(choices[0])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if destination!="" and destination!="home":
			_go("home")
			return
		if asking == "cheer":
			_end_cheer(false)
			return
		if asking in ["boon","power","verdict"]: return
		if asking != "": _set_asking("")
		elif drill_open: _toggle_drill()
		elif screen != "home": _go("home")
		else: _set_asking("system")
	elif asking == "" and event is InputEventKey and event.pressed and not event.echo:
		# Quick keys: Q for the party, then the three people of the camp.
		if event.keycode == KEY_TAB and (drill_open or (screen == "party" and view == "members")) and _tree_of(member) != "":
			get_viewport().set_input_as_handled()
			_pick_page("tree" if page == "info" else "info")
			return
		var where: String = {KEY_Q:"party",KEY_1:"trader",KEY_2:"recruit",KEY_3:"march"}.get(event.keycode,"")
		if where != "":
			get_viewport().set_input_as_handled()
			_visit("home" if screen == where else where)
