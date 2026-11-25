extends Node
## Walks the whole game the way a player would and checks what is left on disk after every
## step: new game, the camp's pages, out to battle and back, through to the second chapter.
##
##     bash run_flow.sh
##
## It presses the real buttons wherever a button says what it is. Lists and grids whose rows
## carry no words of their own are chosen through the camp's own pick functions. Battles are
## not fought: once one has loaded and been checked, the field is declared won or lost and
## the game's own ending runs from there. The rules of combat are covered by the Go tests.
##
## The save used is a separate file, so a real save is never touched.

const Save := preload("res://core/campaign_checkpoint.gd")
const SAVE_PATH := "user://flow-test.cfg"

var passed := 0
var failures: Array[String] = []
var step := ""


func _ready() -> void:
	name = "CampaignFlow"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


# --- helpers ----------------------------------------------------------------------------------

func _say(words: String) -> void:
	print("[flow] ",words)

func _begin(what: String) -> void:
	step = what
	_say("== "+what)

func _check(what: String, ok: bool, detail: Variant = "") -> bool:
	if ok:
		passed += 1
	else:
		failures.append("%s: %s%s" % [step,what,"" if str(detail) == "" else "  ("+str(detail)+")"])
		_say("FAIL  %s  %s" % [what,detail])
	return ok

func _frames(count := 3) -> void:
	for i in count: await get_tree().process_frame

func _scene() -> Node:
	return get_tree().current_scene

## Waits until the running scene is the one named and has had a moment to set itself up.
func _arrive(file: String, seconds := 40.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		var now := _scene()
		if now != null and now.scene_file_path.ends_with(file) and now.is_node_ready():
			await _frames(4)
			return true
		await get_tree().process_frame
	return _check("arrive at "+file,false,"still at %s" % (_scene().scene_file_path if _scene() != null else "nothing"))

func _buttons(root: Node, into: Array) -> Array:
	for child in root.get_children():
		if child is Button and child.is_visible_in_tree() and not child.is_queued_for_deletion(): into.append(child)
		_buttons(child,into)
	return into

## The button a player would read as `label`: by the words on it, or by its hover text.
func _button(label: String) -> Button:
	for button: Button in _buttons(_scene(),[]):
		var words := button.text.replace("　","").strip_edges()
		if words.begins_with(label) or button.tooltip_text.begins_with(label): return button
	return null

func _press(label: String) -> bool:
	var button := _button(label)
	if not _check("button「%s」is there" % label,button != null): return false
	if not _check("button「%s」can be pressed" % label,not button.disabled): return false
	button.pressed.emit()
	await _frames(3)
	return true

func _disk() -> Dictionary:
	return Save.read_entry()

func _coins() -> int:
	return int(_disk().get("purse",{}).get("coins",-1))

func _bag() -> Dictionary:
	return _disk().get("purse",{}).get("bag",{})

func _level(who: String) -> int:
	return int(Save.standing(int(_disk().get("xp",{}).get(who,0))).level)

## Sets something up that the test needs and a player would have earned: written straight
## into the camp's entry and saved, then the camp redrawn.
func _grant_coins(amount: int) -> void:
	var camp := _scene()
	camp.entry.purse.coins = amount
	Save.write_entry(camp.entry)
	camp.shown_coins = amount
	camp._render()
	await _frames()


# --- the journey -----------------------------------------------------------------------------

func _run() -> void:
	Engine.time_scale = 4.0
	Save.PATH = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	get_tree().reload_current_scene()
	await _frames(4)
	if await _arrive("title.tscn"):
		await _new_game()
	if failures.is_empty() or _scene().scene_file_path.ends_with("camp.tscn"):
		await _old_save()
		await _call_for_help()
		await _side_road()
		await _verdicts()
	_finish()

func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_say("")
	_say("%d checks passed, %d failed" % [passed,failures.size()])
	for line in failures: _say("  ✗ "+line)
	get_tree().quit(1 if not failures.is_empty() else 0)

func _new_game() -> void:
	_begin("new game")
	if not await _press("踏上征程"): return
	if not await _arrive("camp.tscn"): return
	var camp := _scene()
	var saved := _disk()
	_check("save starts at 1-1",saved.get("id","") == "1-1",saved.get("id"))
	_check("purse starts with the opening coins",_coins() == Save.STARTING_COINS,_coins())
	_check("hero has learnt nothing yet",saved.picks.get("hero",[]).is_empty(),saved.picks.get("hero"))
	_check("atalanta holds her starting technique",saved.picks.get("atalanta",[]) == [Save.STARTERS.atalanta],saved.picks.get("atalanta"))
	# Heroes come with the seats for them: the first chapter has one seat, and nobody to hire.
	_check("nobody is for hire in the first chapter",Save.offers(saved).is_empty(),Save.offers(saved))
	_check("nobody is asking anything at the start",camp.asking == "",camp.asking)
	_check("everyone starts at level 1",_level("hero") == 1 and _level("atalanta") == 1)

	await _learn_first_technique()
	await _buy_and_wear()
	await _cannot_hire_when_poor()
	if not await _march_and_check_first_battle(): return
	if not await _end_battle(true): return
	await _first_report()
	await _sell_spoils()
	await _swap_carried()
	if not await _lose_a_battle(): return
	await _to_the_second_chapter()


func _learn_first_technique() -> void:
	_begin("learn a technique")
	var camp := _scene()
	if not await _press("队伍"): return
	_check("the party screen is open",camp.screen == "party",camp.screen)
	_check("one point to spend at level 1",camp._budget("hero") == 1,camp._budget("hero"))
	if not await _press("技能树"): return
	camp._pick_technique("shield_wall")
	await _frames()
	if not await _press("学习"): return
	_check("盾墙 is saved as learnt",_disk().picks.get("hero",[]) == ["shield_wall"],_disk().picks.get("hero"))
	camp._pick_technique("iron_arm")
	await _frames()
	var again := _button("还差")
	_check("a second technique is refused for lack of points",again != null and again.disabled)
	camp._pick_member("atalanta")
	await _frames()
	camp._pick_technique(Save.STARTERS.atalanta)
	await _frames()
	var starter := _button("起始招式")
	_check("a starting technique cannot be handed back",starter != null and starter.disabled)


func _buy_and_wear() -> void:
	_begin("buy and wear")
	var camp := _scene()
	camp._go("trader")
	await _frames()
	_check("the trader's shelf holds the first chapter's goods",_button("亚麻短衣") != null)
	camp._pick("tunic","trader")
	await _frames()
	var before := _coins()
	if not await _press("买下"): return
	_check("the price left the purse",_coins() == before-int(Save.GOODS.tunic.price),"%d -> %d" % [before,_coins()])
	_check("the tunic is in the bag",int(_bag().get("tunic",0)) == 1,_bag())
	camp._pick("leather","trader")
	await _frames()
	var short := _button("还差")
	_check("what cannot be afforded cannot be bought",short != null and short.disabled)
	# Put them on the hero from the member sheet.
	camp._go("party")
	await _frames()
	camp._pick_member("hero")
	await _press("信息")
	camp._pick_place("body")
	await _frames()
	_check("the tunic is offered for the body",camp.candidate == "tunic",camp.candidate)
	if not await _press("戴上"): return
	_check("the hero is saved as wearing them",_disk().purse.worn.get("hero",{}).get("body","") == "tunic",_disk().purse.get("worn"))
	_check("none are left loose",Save.loose(_disk().purse,"tunic") == 0)
	_check("the sheet counts them in",int(camp._worn_changes("hero").get("hp",0)) == 3,camp._worn_changes("hero"))


func _cannot_hire_when_poor() -> void:
	_begin("recruit without money")
	var camp := _scene()
	camp._go("recruit")
	await _frames()
	if Save.offers(camp.entry).is_empty():
		_check("with nobody to hire there is nothing to press",_button("招募") == null and _button("还差") == null)
		return
	var cheapest := 9999
	for offer: Dictionary in Save.offers(camp.entry): cheapest = mini(cheapest,int(offer.fee))
	if _coins() < cheapest:
		var hire := _button("还差")
		_check("hiring is refused when the purse is short",hire != null and hire.disabled)
	_check("nobody is sent for at a price",_button("换一批") == null)


func _march_and_check_first_battle() -> bool:
	_begin("march to 1-1")
	var camp := _scene()
	camp._go("march")
	await _frames()
	if not await _press("出征"): return false
	if not await _battle_ready(): return false
	var field := _scene()
	_check("the battle is 1-1",field._battle_id == "1-1",field._battle_id)
	var hero: UnitState = field.state.unit("hero")
	var sheet: Dictionary = UnitCatalog.unit_def("hero")
	var plain := int(sheet.get("max_hp",sheet.get("hp",0)))
	_check("the tunic reached the battlefield",hero.max_hp == plain+3,"%d, plain %d" % [hero.max_hp,plain])
	_check("the hero brings a plain attack, the shield bash and the throw",hero.skills == ["spear","shield_bash","shoulder_throw"],hero.skills)
	_check("盾墙 came along",hero.has_trait("shield_wall"),hero.traits)
	var atalanta: UnitState = field.state.unit("atalanta")
	_check("atalanta brings her shot and her starting technique",atalanta != null and atalanta.skills.size() == 2,atalanta.skills if atalanta != null else "absent")
	return true


## Waits for a battle to be loaded and waiting on the player.
func _battle_ready() -> bool:
	if not await _arrive("main.tscn"): return false
	var deadline := Time.get_ticks_msec()+40000
	while Time.get_ticks_msec() < deadline:
		var field := _scene()
		if field.get("state") != null and field._mode == field.Mode.IDLE:
			await _frames(6)
			return true
		await get_tree().process_frame
	return _check("the battle hands over to the player",false)


## Declares the field won or lost and lets the game's own ending take it back to camp.
func _end_battle(won: bool) -> bool:
	var field := _scene()
	var which: String = field._battle_id
	if won:
		for id: String in field.state.order:
			var unit: UnitState = field.state.unit(id)
			if unit != null and unit.team == Defs.Team.ENEMY: unit.alive = false
		if field.village != null: field.state.village_result = "win"
		if field.map_view.woodland:
			# The travellers all got away: that is what opens the side road afterwards.
			field.state.rescue_result = "win"
			for id: String in field.state.order:
				var traveller: UnitState = field.state.unit(id)
				if traveller != null and traveller.def_id == "refugee": traveller.hidden = true
		if not field.state.escort_exits.is_empty(): field.state.escort_result = "win"
		if not field.state.reach_exits.is_empty(): field.state.reach_result = "win"
		if not field.state.targets.is_empty(): field.state.target_result = "win"
		if which == "2-5": field.state.outcome = "win"
	else:
		field.state.unit("hero").alive = false
	field._check_end()
	await _frames(4)
	if _scene() == field and field._next_battle != "":
		_check("the battle is over",field._mode == field.Mode.OVER,field._mode)
		field._end_turn()
	if not await _arrive("camp.tscn"): return false
	_say("   %s %s -> camp at %s" % [which,"won" if won else "lost",_disk().get("id")])
	return true


func _first_report() -> void:
	_begin("back from 1-1")
	var camp := _scene()
	var saved := _disk()
	_check("the report is up",camp.asking == "cheer",camp.asking)
	_check("the report was not kept for next time",not saved.has("news"))
	_check("1-1 is saved as cleared",saved.outcomes.get("1-1","") == "已通关",saved.outcomes)
	_check("the save moved on to 1-2",saved.id == "1-2",saved.id)
	_check("the battle paid",_coins() == Save.STARTING_COINS-int(Save.GOODS.tunic.price)+60,_coins())
	_check("those who marched took the whole experience",int(saved.xp.get("hero",0)) == Save.xp_for("1-1"),saved.get("xp"))
	_check("the hero is level 2",_level("hero") == 2,_level("hero"))
	var spoils := 0
	for thing: String in _bag():
		if Save.GOODS[thing].slot == "material": spoils += int(_bag()[thing])
	_check("the beaten left materials in the bag",spoils > 0,_bag())
	_check("the tunic is still on",saved.purse.worn.get("hero",{}).get("body","") == "tunic")
	var open: Array = Save.offers(saved).map(func(offer): return offer.kind)
	_check("clearing 1-1 brings nobody yet: heroes come with the second chapter",open.is_empty(),open)
	if not await _press("去分配技能点"): return
	_check("the report is gone",camp.asking == "",camp.asking)
	_check("it opened the technique tree",camp.screen == "party" and camp.page == "tree","%s / %s" % [camp.screen,camp.page])
	_check("a second point has come",camp._budget("hero") == 2,camp._budget("hero"))
	camp._pick_member("hero")
	camp._pick_technique("iron_arm")
	await _frames()
	if await _press("学习"):
		_check("铁臂 is saved as learnt",_disk().picks.hero.has("iron_arm"),_disk().picks.hero)


func _sell_spoils() -> void:
	_begin("sell the spoils")
	var camp := _scene()
	camp._go("trader")
	await _frames()
	if not await _press("卖"): return
	_check("the sell page is open",camp.shop_tab == "sell",camp.shop_tab)
	_check("what is worn is not for sale",_button("亚麻短衣") == null)
	var worth := 0
	for thing: String in _bag():
		if Save.GOODS[thing].slot == "material": worth += Save.sell_price(thing)*int(_bag()[thing])
	var before := _coins()
	if not await _press("卖掉所有材料"): return
	_check("the materials fetched half their price",_coins() == before+worth,"%d + %d -> %d" % [before,worth,_coins()])
	var left := 0
	for thing: String in _bag():
		if Save.GOODS[thing].slot == "material": left += 1
	_check("no materials are left",left == 0,_bag())


func _hire() -> void:
	_begin("hire a fighter")
	var camp := _scene()
	camp._go("recruit")
	await _frames()
	var listed := Save.offers(camp.entry)
	var pick: Dictionary = listed[0]
	for offer: Dictionary in listed:
		if int(offer.fee) < int(pick.fee): pick = offer
	_check("each asks the fee set for them",int(pick.fee) == int(Save.RECRUITS[pick.kind].fee),pick)
	if _coins() < int(pick.fee):
		_say("   (setup: topping the purse up to cover the fee)")
		await _grant_coins(int(pick.fee)+50)
	camp._pick(pick.id,"recruit")
	await _frames()
	var before := _coins()
	if not await _press("招募"): return
	var saved := _disk()
	_check("the fee left the purse",_coins() == before-int(pick.fee),"%d -> %d" % [before,_coins()])
	_check("the hire is on the roster",saved.roster.size() == 1 and saved.roster[0].name == pick.name,saved.get("roster"))
	_check("the hire left the list",Save.offers(saved).size() == listed.size()-1 and not Save.offers(saved).any(func(offer): return offer.kind == pick.kind),Save.offers(saved))
	var who: String = saved.roster[0].id
	# The hired do not take the field: they come when the protagonist calls.
	_check("the hire takes no seat",not saved.get("deploy",[]).has(who) and not camp._reserves().has(who),saved.get("deploy"))
	_check("the first one hired is the one who comes",Save.support_of(saved) == str(pick.kind),saved.get("support"))
	_check("what he does is told in a sentence",Save.support_words(str(pick.kind)).contains("冷却"),Save.support_words(str(pick.kind)))


func _swap_carried() -> void:
	_begin("carried techniques")
	var camp := _scene()
	camp._go("party")
	await _frames()
	camp._pick_member("atalanta")
	await _press("信息")
	_check("the plain attack takes none of the four places",not camp._known("atalanta").has(camp._basic("atalanta")),camp._known("atalanta"))
	_check("atalanta carries the one technique she knows",camp._carried("atalanta") == [Save.STARTERS.atalanta],camp._carried("atalanta"))
	camp._pick_slot(0)
	await _frames()
	camp._pick_skill(Save.STARTERS.atalanta)
	await _frames()
	if not await _press("卸下"): return
	_check("the choice is saved",_disk().get("loadout",{}).get("atalanta",["?"]).is_empty(),_disk().get("loadout"))
	await _pack_pockets()


## Buys two things to carry and puts them in the hero's pockets.
func _pack_pockets() -> void:
	_begin("things to carry")
	var camp := _scene()
	await _grant_coins(300)
	camp._go("trader")
	await _frames()
	await _press("买")
	for thing: String in ["item_potion","item_javelin"]:
		camp._pick(thing,"trader")
		await _frames()
		await _press("买下")
	_check("both are in the bag",int(_bag().get("item_potion",0)) == 1 and int(_bag().get("item_javelin",0)) == 1,_bag())
	camp._go("party")
	await _frames()
	camp._pick_member("hero")
	await _press("信息")
	for pocket in 2:
		camp._pick_pocket(pocket)
		await _frames()
		camp._pick_kit(["item_potion","item_javelin"][pocket])
		await _frames()
		await _press("带上")
	var purse: Dictionary = _disk().purse
	_check("the hero's pockets are saved",purse.get("kit",{}).get("hero",[]) == ["item_potion","item_javelin"],purse.get("kit"))
	_check("neither is left loose to sell",Save.loose(purse,"item_potion") == 0 and Save.loose(purse,"item_javelin") == 0)
	camp._pick_pocket(0)
	await _frames()
	_check("a third thing has nowhere to go",camp._kit("hero").size() == Save.KIT_SLOTS)


func _lose_a_battle() -> bool:
	_begin("lose 1-2")
	var camp := _scene()
	camp._go("march")
	await _frames()
	if not await _press("出征"): return false
	if not await _battle_ready(): return false
	var field := _scene()
	_check("the battle is 1-2",field._battle_id == "1-2",field._battle_id)
	var who: String = _disk().roster[0].id if not _disk().get("roster",[]).is_empty() else ""
	var hire: UnitState = field.state.unit(who)
	# This battle needs Atalanta, and the chapter has the one seat: the hire is not here.
	_check("the hire stayed in camp",hire == null,who)
	var atalanta: UnitState = field.state.unit("atalanta")
	_check("atalanta brought only her plain attack",atalanta.skills.size() == 1,atalanta.skills)
	var hero: UnitState = field.state.unit("hero")
	_check("the hero's pockets came along",int(hero.items.get("item_potion",0)) == 1 and int(hero.items.get("item_javelin",0)) == 1,hero.items)
	_check("what is carried can be used like a technique",hero.skills.has("item_potion") and hero.skills.has("item_javelin"),hero.skills)
	var bar: Array = field._actions_for(hero)
	var groups := {}
	for command: Dictionary in bar: groups[command.group] = int(groups.get(command.group,0))+1
	_check("the bar sorts commands into move, attack, skill, item and wait",groups.get("move",0) == 1 and groups.get("attack",0) == 1 and groups.get("wait",0) == 1 and groups.get("item",0) == 2 and groups.get("skill",0) >= 1,groups)
	# The potion is drunk during the battle; the javelin is not thrown.
	hero.items = {"item_javelin":1}
	var before := _disk()
	if not await _end_battle(false): return false
	var saved := _disk()
	_check("what was used is gone from the bag",not saved.purse.bag.has("item_potion"),saved.purse.bag)
	_check("and from the hero's pockets",saved.purse.kit.get("hero",[]) == ["item_javelin"],saved.purse.get("kit"))
	_check("what was not used is kept",int(saved.purse.bag.get("item_javelin",0)) == 1,saved.purse.bag)
	before.purse.bag.erase("item_potion")
	camp = _scene()
	_check("the report is up",camp.asking == "cheer",camp.asking)
	_check("the report says it was lost",_button("回营整备") != null)
	_check("1-2 is not cleared",saved.outcomes.get("1-2","") != "已通关",saved.outcomes)
	_check("the save stays at 1-2",saved.id == "1-2",saved.id)
	_check("a lost battle pays nothing",int(saved.purse.coins) == int(before.purse.coins),"%s -> %s" % [before.purse.coins,saved.purse.coins])
	_check("a lost battle teaches nothing",saved.xp == before.xp,saved.xp)
	_check("a lost battle leaves no spoils",saved.purse.bag == before.purse.bag,saved.purse.bag)
	_check("the roster is kept",saved.get("roster",[]).size() == before.get("roster",[]).size())
	await _press("回营整备")
	return true


## Wins every battle from here until the second chapter's second battle is cleared.
func _to_the_second_chapter() -> void:
	var seen := {}
	for round in 12:
		var camp := _scene()
		var saved := _disk()
		if camp.asking == "cheer":
			await _press("继续") if _button("继续") != null else await _press("去分配技能点")
		if camp.asking == "boon":
			_begin("take a boon")
			var boon: String = Save.BOONS.keys()[0]
			camp._take_boon(boon)
			await _frames()
			saved = _disk()
			_check("the boon is saved",saved.get("boon","") == boon,saved.get("boon"))
			_check("the save moved on to the second chapter",saved.id == "2-1",saved.id)
			camp._go("trader")
			await _frames()
			_check("the second chapter's goods are on the shelf",_button("青铜胸甲") != null)
			# With the second seat come the first heroes for hire: the common and the rare.
			var kinds := Save.offers(_disk()).map(func(offer): return offer.kind)
			_check("four heroes have come, the two great ones not yet",kinds.size() == 4 and not kinds.has("idas") and not kinds.has("eurytion"),kinds)
			await _hire()
			camp = _scene()
		saved = _disk()
		var target: String = saved.id
		if saved.outcomes.get("2-5","") == "已通关": break
		var before := saved.duplicate(true)
		camp._go("march")
		await _frames()
		if saved.get("choose_route",false):
			# Two roads are open after the forest: take the side road, where Chiron is met.
			_begin("the fork after 1-2")
			var sites: Array = camp.Routes.data[camp.chapter].sites
			var side := -1
			for i in sites.size():
				if sites[i].id == "1-3": side = i
			var open := 0
			for site: Dictionary in sites:
				if camp._status(camp.chapter,site) == "可出发": open += 1
			_check("two roads are open",open == 2,open)
			if _check("the side road is one of them",side >= 0 and camp._status(camp.chapter,sites[side]) == "可出发"):
				camp._pick(side,"march")
				await _frames()
				target = "1-3"
		_begin("win "+target)
		if not await _press("出征"): return
		if not await _battle_ready(): return
		var fought: String = _scene()._battle_id
		_check("the battle is the one chosen",fought == target,"%s, wanted %s" % [fought,target])
		if seen.has(fought):
			_check("the journey moves on after %s" % fought,false,"came back to it")
			return
		seen[fought] = true
		if fought == "1-2":
			# Two travellers down: the side road is lost, the battle is not, and it says so.
			var field := _scene()
			var downed: Array[UnitState] = []
			for id: String in field.state.order:
				var person: UnitState = field.state.unit(id)
				if person.def_id == "refugee" and downed.size() < 2:
					person.alive = false
					downed.append(person)
			field._refresh()
			_check("losing two travellers is announced once",field._side_road_lost)
			_check("the goal says the battle goes on",field.hud._objective.tooltip_text.contains("可选目标已错过") and field.hud._objective.text.begins_with("歼灭所有敌人"),field.hud._objective.tooltip_text)
			_check("the battle is not over",field._mode != field.Mode.OVER,field._mode)
			for person in downed: person.alive = true
			field._refresh()
		var marched := 0
		for who: String in ["hero","atalanta"]+before.get("deploy",[]):
			if _scene().state.unit(who) != null: marched += 1
		_check("everyone chosen is on the field",marched == 2+before.get("deploy",[]).size(),"%d of %d" % [marched,2+before.get("deploy",[]).size()])
		if not await _end_battle(true): return
		saved = _disk()
		_check("%s is saved as cleared" % fought,saved.outcomes.get(fought,"") == "已通关",saved.outcomes)
		_check("it paid",int(saved.purse.coins) > int(before.purse.coins),"%s -> %s" % [before.purse.coins,saved.purse.coins])
		if fought == "2-2": _check("crossing dry paid as much again",str(saved.get("camp_summary","")).contains("酬金 +80"),saved.get("camp_summary"))
		if fought == "2-3": _check("nobody was pushed under, so no more than the pay",str(saved.get("camp_summary","")).contains("没有敌人被推进深水"),saved.get("camp_summary"))
		_check("it taught the hero",int(saved.xp.hero) == int(before.xp.hero)+Save.xp_for(fought),"%s -> %s" % [before.xp.hero,saved.xp.hero])
		for who: String in saved.xp:
			if not before.xp.has(who): continue
			var share := int(saved.xp[who])-int(before.xp[who])
			_check("%s got a share" % who,share == Save.xp_for(fought) or share == Save.xp_for(fought)/2,share)
	_begin("the second chapter")
	var last := _disk()
	_check("2-1 is cleared",last.outcomes.get("2-1","") == "已通关",last.outcomes)
	_check("2-2 is cleared",last.outcomes.get("2-2","") == "已通关",last.outcomes)
	_check("2-3 is cleared",last.outcomes.get("2-3","") == "已通关",last.outcomes)
	_check("2-4 is cleared",last.outcomes.get("2-4","") == "已通关",last.outcomes)
	_check("2-5 is cleared",last.outcomes.get("2-5","") == "已通关",last.outcomes)
	_check("the save rests at the hydra's lair",last.id == "2-5",last.id)
	_check("the hydra is to be judged",int(last.get("verdict",0)) == 2,last.get("verdict"))
	var roads: Array = _scene().Routes.data[1].sites
	for site: Dictionary in roads:
		if site.id == "2-S": _check("with Chiron already won at the feast, the side road is not needed",_scene()._status(1,site) == "无需前往",_scene()._status(1,site))
	_check("chiron is with the party",last.get("chiron_joined",false))
	_check("medea is with the party",last.get("medea_joined",false))
	var camp := _scene()
	if camp.asking == "cheer": await _press("继续") if _button("继续") != null else await _press("去分配技能点")
	_check("medea is listed in the camp",camp._everyone().has("medea"),camp._everyone())
	_check("medea holds her starting technique",_disk().picks.get("medea",[]).has(Save.STARTERS.medea) or camp.entry.picks.get("medea",[]).has(Save.STARTERS.medea),camp.entry.picks.get("medea"))


## Over a beaten boss the camp asks: take the relic, or spare them. Later chapters are not
## built, so the save is written by hand at the point where the question is owed.
func _verdicts() -> void:
	_begin("take a relic or spare a boss")
	var base := {"id":"2-1","stage":"camp","picks":{"hero":[],"atalanta":["vital_shot"]},"rescued":[],"chiron_joined":true,
		"outcomes":{},"choose_route":false,"equipped_relic":"lion_pelt","boon":"moon_hunt",
		"relics":["lion_pelt","hydra_blood","bronze_feather"],"divinity":3,"powers":["thunder_bolt"],"verdict":4}
	_check("the save can be written",Save.write_entry(base) == OK)
	get_tree().change_scene_to_file("res://camp.tscn")
	await _frames(4)
	if not await _arrive("camp.tscn"): return
	var camp := _scene()
	_check("the camp asks about the Minotaur before anything else",camp.asking == "verdict",camp.asking)
	_check("nothing can be settled before a side is leant toward",_button("夺走") == null and _button("放过他") == null)
	if not await _lean("take"): return
	_check("leaning is not yet deciding",_disk().get("verdict",0) == 4 and int(_disk().divinity) == 3,_disk().get("divinity"))
	if not await _press("夺走阿里阿德涅之线"): return
	_check("the taking plays out before anything is written",camp.settling and _disk().get("verdict",0) == 4)
	await _settled()
	var saved := _disk()
	_check("the thread is his",saved.relics == ["lion_pelt","hydra_blood","bronze_feather","ariadne_thread"],saved.get("relics"))
	_check("four relics make a demigod",int(saved.divinity) == 4 and Save.tier(saved) == 2,saved.get("divinity"))
	_check("the question is gone from the save",not saved.has("verdict"))
	_check("the new tier asks for its technique next",camp.asking == "power",camp.asking)
	if not await _press("天穹"): return
	_check("the technique is saved",_disk().powers == ["thunder_bolt","sky_dome"],_disk().get("powers"))
	_check("nothing more is owed",camp.asking == "",camp.asking)
	_check("he may carry it into battle",camp._known("hero").has("sky_dome"),camp._known("hero"))
	# The other road: spare Medusa.
	var mercy: Dictionary = _disk()
	mercy.verdict = 5
	_check("the save can be written",Save.write_entry(mercy) == OK)
	get_tree().change_scene_to_file("res://camp.tscn")
	await _frames(4)
	if not await _arrive("camp.tscn"): return
	camp = _scene()
	_check("the camp asks about Medusa",camp.asking == "verdict",camp.asking)
	if not await _lean("spare"): return
	if not await _press("放过她"): return
	await _settled()
	saved = _disk()
	_check("she is recorded as spared",saved.get("spared",[]) == [5],saved.get("spared"))
	_check("no relic was taken",int(saved.divinity) == 4 and saved.relics.size() == 4,saved.get("relics"))
	_check("sparing owes nothing further",camp.asking == "",camp.asking)


## Waits for a settled verdict to finish playing out.
func _settled() -> void:
	var deadline := Time.get_ticks_msec()+6000
	while _scene().settling and Time.get_ticks_msec() < deadline: await _frames(2)
	await _frames(3)


## Presses one of the two roads on the verdict screen: the cards are buttons all over.
func _lean(way: String) -> bool:
	for button: Button in _buttons(_scene(),[]):
		if button.get_meta("way","") == way:
			button.pressed.emit()
			await _frames(3)
			return true
	return _check("the road「%s」is there" % way,false)


## The second chapter for someone who did not win the feast: Chiron lies wounded off the
## road, and bringing him to the spring is how he joins.
## The index of the protagonist's command for calling his supporter, or -1.
func _call_index() -> int:
	var field := _scene()
	for i in field._actions.size():
		if SkillCatalog.get_skill(str(field._actions[i].get("action",{}).get("skill",""))).has("support"): return i
	return -1

## Ends the player's turn and waits until it is the player's again.
func _next_round() -> bool:
	var field := _scene()
	var was: int = field.state.round_number
	field._end_turn()
	var deadline := Time.get_ticks_msec()+40000
	while Time.get_ticks_msec() < deadline:
		if field.state != null and field.state.round_number > was and field.state.phase == Defs.Phase.PLAYER and field._mode == field.Mode.IDLE:
			await _frames(4)
			return true
		await get_tree().process_frame
	return _check("the turn comes back to the player",false)

## Opens 1-4 with this hired hero in support, the way the camp hands a battle over.
func _field_with(hero: String) -> bool:
	var entry := _disk()
	entry.id = "1-4"
	entry.choose_route = false
	entry.campaign = false
	entry.deploy = ["atalanta"]
	entry.bench = []
	entry.party = []
	entry.support = hero
	entry.support_picks = []
	get_tree().set_meta("battle_entry",entry)
	get_tree().change_scene_to_file("res://main.tscn")
	await _frames(4)
	if not await _battle_ready(): return false
	return _check("%s came along" % hero,_scene().state.unit("hero").skills.has(str(Save.RECRUITS[hero].support)),_scene().state.unit("hero").skills)

## Calling a hired hero in battle, through the same commands and clicks a player uses.
func _call_for_help() -> void:
	_begin("calling for help")
	# The old save's battle is still open, with Iphicles in support.
	var field := _scene()
	field._select("hero")
	await _frames()
	var at := _call_index()
	if not _check("the call is one of the protagonist's commands",at >= 0,field._actions.map(func(a): return a.get("label",""))): return
	_check("it is closed in the first round",not field._actions[at].enabled and str(field._actions[at].brief).contains("第二回合"),field._actions[at])
	if not await _next_round(): return
	# The protagonist spends his own action first; the call is still open to him.
	await field._perform({"type":"wait","unit":"hero"})
	await _frames()
	field._select("hero")
	await _frames()
	at = _call_index()
	_check("he has acted",field.state.unit("hero").has_acted)
	if not _check("and can still call",at >= 0 and field._actions[at].enabled,field._actions[at] if at >= 0 else "gone"): return
	field._on_action(at)
	await _frames()
	_check("the call asks for a target",field._mode == field.Mode.TARGET,field._mode)
	var friend: UnitState = field.state.unit("atalanta")
	field._click(friend.pos)
	await _frames(30)
	_check("Atalanta is shielded",field.state.unit("atalanta").shield > 0,field.state.unit("atalanta").shield)
	field._select("hero")
	await _frames()
	at = _call_index()
	_check("and he must rest before the next call",at >= 0 and not field._actions[at].enabled and int(field._actions[at].cooldown) > 0,field._actions[at] if at >= 0 else "gone")

	# Pholus carries: first where to set the companion down, then whom.
	if not await _field_with("pholus"): return
	if not await _next_round(): return
	field = _scene()
	field._select("hero")
	await _frames()
	at = _call_index()
	if not _check("Pholus can be called",at >= 0 and field._actions[at].enabled,field._actions[at] if at >= 0 else "gone"): return
	field._on_action(at)
	await _frames()
	_check("he asks where to first",field._needs_landing())
	var aim: Dictionary = Rules.targeting(field.state,field._pending.merged({"unit":"hero"}))
	if not _check("there are places to set someone down",not aim.landings.is_empty()): return
	var hero_at: Vector2i = field.state.unit("hero").pos
	var down: Vector2i = aim.landings[0]
	for cell: Vector2i in aim.landings:
		# The farthest he will carry, to see that she really travels.
		if absi(cell.x-hero_at.x)+absi(cell.y-hero_at.y) > absi(down.x-hero_at.x)+absi(down.y-hero_at.y): down = cell
	field._click(down)
	await _frames()
	_check("then he asks whom",field._mode == field.Mode.TARGET and not field._needs_landing() and field._pending.get("to") == down,field._pending)
	var rider: UnitState = field.state.unit("atalanta")
	field._click(rider.pos)
	await _frames(40)
	_check("Atalanta is set down where he was told",field.state.unit("atalanta").pos == down,[field.state.unit("atalanta").pos,down])
	_check("the protagonist has not spent his action",not field.state.unit("hero").has_acted)

	# Ancaeus splits armour, and the game has a name for what that leaves.
	if not await _field_with("ancaeus"): return
	field = _scene()
	var marks: Array = []
	for round in 5:
		if not await _next_round(): return
		field._select("hero")
		await _frames()
		at = _call_index()
		if at < 0 or not field._actions[at].enabled: continue
		var reach: Dictionary = Rules.targeting(field.state,{"type":"skill","unit":"hero","skill":str(Save.RECRUITS.ancaeus.support)})
		if reach.valid.is_empty(): continue
		field._on_action(at)
		await _frames()
		field._click(reach.valid[0])
		await _frames(40)
		marks = field.state.units.values().filter(func(u): return u.alive and u.has_status("sundered"))
		break
	if _check("the axe finds someone within five rounds, and leaves the armour split",not marks.is_empty()):
		_check("split armour has a name the player can read",str(EventText.STATUS_NAMES.get("sundered","")).contains("破甲"),EventText.STATUS_NAMES.get("sundered"))

func _side_road() -> void:
	_begin("the wounded centaur")
	var at := {"id":"2-2","stage":"camp","picks":{"hero":["iron_arm"],"atalanta":["vital_shot"]},"rescued":[],"chiron_joined":false,
		"medea_joined":true,"outcomes":{"1-1":"已通关","1-2":"已通关","1-4":"已通关","2-1":"已通关"},"choose_route":false,
		"equipped_relic":"lion_pelt","relics":["lion_pelt"],"divinity":1,"powers":[],"boon":"moon_hunt",
		"purse":{"coins":300,"paid":["1-1","1-2","1-4","1-5","2-1"]}}
	_check("the save can be written",Save.write_entry(at) == OK)
	get_tree().change_scene_to_file("res://camp.tscn")
	await _frames(4)
	if not await _arrive("camp.tscn"): return
	var camp := _scene()
	camp._go("march")
	await _frames()
	var sites: Array = camp.Routes.data[1].sites
	var side := -1
	for i in sites.size():
		if sites[i].id == "2-S": side = i
	_check("the side road is open",side >= 0 and camp._status(1,sites[side]) == "可出发",camp._status(1,sites[side]) if side >= 0 else "missing")
	_check("the map still opens on the main road",sites[camp.picked.march].id == "2-2",sites[camp.picked.march].id)
	camp._pick(side,"march")
	await _frames()
	if not await _press("出征"): return
	if not await _battle_ready(): return
	var field := _scene()
	_check("the battle is the side road",field._battle_id == "2-S",field._battle_id)
	_check("Chiron is there to be led",field.state.unit("chiron") != null and field.state.unit("chiron").team == Defs.Team.PLAYER)
	_check("the spring is marked",not field.state.escort_exits.is_empty())
	_check("the engine is still fighting",field.state.escort_result == "",field.state.escort_result)
	if not await _end_battle(true): return
	var saved := _disk()
	_check("the journey is back where it stood",saved.id == "2-2",saved.id)
	_check("the side road is done",saved.outcomes.get("2-S","") == "已通关",saved.outcomes)
	_check("Chiron has joined",saved.get("chiron_joined",false))
	_check("the main road was not touched",not saved.outcomes.has("2-2"),saved.outcomes)
	camp = _scene()
	_check("he is in camp to be chosen",camp._reserves().has("chiron"),camp._reserves())


## A save written before hires had names, things had counts and members had experience.
func _old_save() -> void:
	_begin("an old save")
	var old := {"id":"1-4","stage":"camp","picks":{"hero":["iron_arm"],"atalanta":["vital_shot"]},"rescued":[],"chiron_joined":true,
		"outcomes":{"1-1":"已通关","1-2":"已通关","1-3":"已通关"},"choose_route":false,"roster":["iphicles"],"deploy":["atalanta","chiron","iphicles"],
		"purse":{"coins":200,"owned":["olive","anklet"],"equipped":{"olive":"hero"},"paid":["1-1","1-2","1-3"]}}
	_check("the old save can be written",Save.write_entry(old) == OK)
	get_tree().change_scene_to_file("res://camp.tscn")
	await _frames(4)
	if not await _arrive("camp.tscn"): return
	var camp := _scene()
	_check("no report for a save that brings no news",camp.asking == "",camp.asking)
	_check("the hire has a record of their own",camp.entry.roster.size() == 1 and camp.entry.roster[0].name == "伊菲克勒斯",camp.entry.roster)
	_check("he has a tree of his own to learn from",camp._tree_of("iphicles") == "iphicles",camp._tree_of("iphicles"))
	var purse: Dictionary = camp._purse()
	_check("things are counted",int(purse.bag.get("olive",0)) == 1 and int(purse.bag.get("anklet",0)) == 1,purse.get("bag"))
	_check("the olive branch is still on the hero",purse.worn.get("hero",{}).get("hand","") == "olive",purse.get("worn"))
	_check("the old lists are gone",not purse.has("owned") and not purse.has("equipped"))
	_check("everyone has experience for the level they were",camp._level("hero") == 4 and camp._level("chiron") == 4,camp.entry.get("xp"))
	# The first chapter takes one beside the protagonist: of the three the old save sent, the first.
	_check("the party still marches, Atalanta now among the chosen",camp._marching() == ["atalanta"],camp._marching())
	# Only the protagonist is fixed: Atalanta may stay behind, unless the battle needs her.
	camp._toggle_march("atalanta")
	_check("Atalanta can be left in camp",not camp._marching_to("1-4").has("atalanta"),camp._marching_to("1-4"))
	_check("the lion hunt takes her along all the same",camp._marching_to("1-5")[0] == "atalanta",camp._marching_to("1-5"))
	_check("the hire is not among those who can march",not camp._reserves().has("iphicles"),camp._reserves())
	_check("he is the one who comes in support",Save.support_of(camp.entry) == "iphicles",camp.entry.get("support"))
	camp._toggle_march("atalanta")
	_check("one beside the protagonist in the first chapter",camp._marching() == ["atalanta"],camp._marching())
	_check("the party grows a seat a chapter, to four in all",Save.seats("2-2") == 2 and Save.seats("3-1") == 3 and Save.seats("7-4") == 3)
	camp._go("march")
	await _frames()
	if not await _press("出征"): return
	if not await _battle_ready(): return
	_check("the old save reaches its battle",_scene()._battle_id == "1-4",_scene()._battle_id)
	_check("the old hire stays off the field",_scene().state.unit("iphicles") == null)
	_check("and can be called: the protagonist has his move",_scene().state.unit("hero").skills.has("sup_iphicles"),_scene().state.unit("hero").skills)
	_check("not in the first round",Rules.validate(_scene().state,{"type":"skill","unit":"hero","skill":"sup_iphicles","target":_scene().state.unit("atalanta").pos}) != "")
	_check("Atalanta keeps her seat",_scene().state.unit("atalanta") != null)
