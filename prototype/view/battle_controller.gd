extends Node
## Greybox battle: builds the low-res world, HUD and input flow on top of the rules core.
## 规则全部在 Go 引擎里（engine/，由 GoEngine 拉起 `srpg play`）；这里只做表现和输入。
## Starts on the pre-battle build panel (skill picks + battle choice).
##
## Command line (after `--`):
##   --battle=<id>     1-4 | 1-5 | test (default 1-4); skips the build panel with default picks
##   --data-dir=<dir>  覆盖数据目录，原样交给规则引擎
##   --capture=<png>   save a screenshot after the scripted demo and quit
##   --kit=<a,b>       things for the protagonist to carry (e.g. item_firepot)
##   --rounds=<n>      how many rounds the "fire" demo lets pass
##   --wide            one zoom step out, centred on the map (for looking at a whole field)
##   --demo=<name>     build | idle | move | target | threat | rotate | enemy  (scripted captures)

const DUST := preload("res://art/thirdparty/pixelfx/dust.png")
## A small scuff for ordinary footfalls. DUST is a hard landing with rings and pebbles.
const STEP_DUST := preload("res://art/original/fx/dust.png")
const IMPACT := preload("res://art/thirdparty/pixelfx/hit.png")
const SLASH := preload("res://art/thirdparty/pixelfx/slash.png")
## What a thing carried does where it lands, and what comes over whoever takes a status.
const BURST := preload("res://art/thirdparty/pixelfx/burst.png")
## The second chapter's own drawings (art/originals/fx): a burning thicket and what it
## leaves, a neck sealed and a head grown back, the hydra's venom and the priestess's blessing.
const BRUSHFIRE := preload("res://art/original/fx/brushfire.png")
const CHARRED := preload("res://art/original/fx/charred.png")
const CAUTERIZE := preload("res://art/original/fx/cauterize.png")
const REGROW := preload("res://art/original/fx/regrow.png")
const VENOM_SPIT := preload("res://art/original/fx/venom_spit.png")
const HERA_BLESSING := preload("res://art/original/fx/hera_blessing.png")
const HYDRA_VENOM := preload("res://art/original/fx/hydra_venom.png")
## A blow that has its own drawing where it lands, instead of the common impact.
const SKILL_HIT := {"hydra_spit":VENOM_SPIT}
const THUD := preload("res://art/thirdparty/pixelfx/thud.png")
const BLESS := preload("res://art/thirdparty/pixelfx/bless.png")
## The four ailments show on the body for as long as they last. With each, how high on the
## body it sits (0 the feet, 1 the crown). A badge by the health bar says the same; this is what lets
## the player see it across the field without reading badges.
const LIGHTNING := preload("res://art/original/fx/lightning.png")
const SKYFIRE := preload("res://art/original/fx/skyfire.png")
const THUNDERSTEP := preload("res://art/original/fx/thunderstep.png")
const DOME := preload("res://art/original/fx/dome.png")
const THUNDERBODY := preload("res://art/original/fx/thunderbody.png")
const CAST_NET := preload("res://art/original/fx/net.png")
const NET_PIXEL_SIZE := .022
## The combat result is already applied while its throwing animation is playing.
var pending_net_binds := {}
const AURAS := {
	"thunder_body": [THUNDERBODY,.48,1.20],
	"burning": [preload("res://art/thirdparty/pixelfx/burning.png"),.30],
	"poisoned": [preload("res://art/thirdparty/pixelfx/poisoned.png"),.04],
	"stunned": [preload("res://art/thirdparty/pixelfx/stunned.png"),1.02],
	# Drawn for the game by art/tools/draw_status_fx.py: no kit had a fitting one.
	"rooted": [preload("res://art/original/fx/rooted.png"),.06],
}
var _auras := {}  ## "unit/status" -> the effect playing on them
const ARROW := preload("res://art/original/fx/arrow.png")
const ROAR := preload("res://art/original/fx/roar.png")
const LOW_RES := Vector2(640, 360)

enum Mode { IDLE, TARGET, FACING, BUSY, OVER }

var state: BattleState
var map_view: MapView
var highlights: HighlightLayer
var cam_rig: CameraRig
var village: VillageDisplay
var fire_round := 0
var hud: Hud
var unit_views := {}
const CaveMouth := preload("res://view/cave_mouth.gd")
var cave_mouths := {}
var boulder_vertices := PackedVector3Array()
var boulder_views := {}  ## boulder id -> Node3D
var ui_scale := 1.0
var tactical := false
var shrink := 3

var _container: SubViewportContainer
var _viewport: SubViewport
var _units_root: Node3D
var _mode := Mode.IDLE
var _selected := ""
var _pending := {}  ## action template while targeting: {"type": ..., "skill": ...}
var _hovered := Defs.NO_POS
var _show_threat := false
var _actions: Array = []
var _reachable := {}
var _mission_name := ""
var _available_units: Array[String] = []
var _active_enemy := ""
var _drag_from := Vector2.INF
var _capture_path := ""
var _demo := ""
var _wide := false
var _fire_rounds := 1  ## how many rounds the "fire" demo lets pass: --rounds=N
var _battle_id := ""
var _skill_picks := {}
const Checkpoint := preload("res://core/campaign_checkpoint.gd")
var _next_battle := ""
var _campaign := false
var _rescued: Array = []
var _outcomes := {}
var _campaign_reward := {}
var _purse := {}
var _camp_stop := {}
var _saved_orders: Array = []
## Where the journey stood when a side battle was set out for: the camp returns there.
var _resume := ""
var rescued_count := 0
var _side_road_lost := false  ## said once, when too few travellers are left to open the side road
var _chiron_joined := false
## Carried through from the camp so a battle never loses them: who has been hired, who was
## picked to march, and the marching list in the form the engine takes (null = not chosen).
var _roster: Array = []
var _deploy: Array = []
## Heroes the battle file places who stay in camp this time.
var _bench: Array = []
var _party: Variant = null
var _xp: Variant = null  ## each member's experience, carried through untouched
var _haul := {}  ## spoils so far this battle: thing -> how many
var _looted := {}  ## enemies whose spoils have been rolled
var _loadout: Variant = null  ## techniques each member carries, chosen at the camp
var _build_panel: BuildPanel


func _ready() -> void:
	get_tree().set_meta("battle_entered", true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--demo="):
			_demo = arg.trim_prefix("--demo=")
		elif arg.begins_with("--relics="):
			# For trying a tier of divinity: so many relics, and (with --powers) what grew.
			_campaign_reward["equipped_relic"] = "lion_pelt"
			_campaign_reward["boon"] = ""
			_campaign_reward["divinity"] = int(arg.trim_prefix("--relics="))
		elif arg.begins_with("--powers="):
			_campaign_reward["powers"] = Array(arg.trim_prefix("--powers=").split(","))
		elif arg.begins_with("--bench="):
			# Leave heroes the battle places in camp, to see the field without them.
			_bench = Array(arg.trim_prefix("--bench=").split(","))
		elif arg.begins_with("--battle="):
			_battle_id = arg.trim_prefix("--battle=")
		elif arg.begins_with("--support="):
			# A hired hero to call on in a single battle: --support=phalerus
			_campaign_reward["support"] = arg.trim_prefix("--support=")
		elif arg.begins_with("--worn="):
			# Which relics he wears in a single battle: --worn=lion_pelt,hydra_blood
			_campaign_reward["relics_worn"] = Array(arg.trim_prefix("--worn=").split(","))
		elif arg.begins_with("--kit="):
			# Things for the protagonist to carry into a single battle: --kit=item_firepot,item_potion
			_purse["kit"] = {"hero":Array(arg.trim_prefix("--kit=").split(","))}
		elif arg.begins_with("--rounds="):
			_fire_rounds = int(arg.trim_prefix("--rounds="))
		elif arg == "--wide":
			# For looking at a whole field: one zoom step out, centred on the map.
			_wide = true
	if not GoEngine.ensure():
		_engine_missing()
		return
	_build_scene()
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	if get_tree().has_meta("battle_entry"):
		var entry: Dictionary = get_tree().get_meta("battle_entry")
		get_tree().remove_meta("battle_entry")
		_campaign = entry.get("campaign", false)
		_purse=entry.get("purse",{}).duplicate(true)
		_outcomes = entry.get("outcomes",{})
		_rescued = entry.get("rescued", [])
		if entry.has("equipped_relic"):
			for key in ["equipped_relic","boon","divinity","powers","relics_worn"]:
				if entry.has(key): _campaign_reward[key]=entry[key]
		if str(entry.get("support","")) not in ["","none"]:
			_campaign_reward["support"] = str(entry.support)
			_campaign_reward["support_picks"] = entry.get("support_picks",[])
		_saved_orders=entry.get("orders",[])
		_resume=str(entry.get("resume",""))
		_chiron_joined = entry.get("chiron_joined",false)
		_roster = entry.get("roster",[])
		_deploy = entry.get("deploy",[])
		_bench = entry.get("bench",[])
		_party = entry.get("party")
		_loadout = entry.get("loadout")
		_xp = entry.get("xp")
		_start_battle(entry.id,entry.picks)
	elif _demo == "build" or (_battle_id == "" and _capture_path == ""):
		Soundscape.score("jar")
		_build_panel = BuildPanel.new()
		_build_panel.campaign_start = get_tree().has_meta("campaign_build")
		if _build_panel.campaign_start: get_tree().remove_meta("campaign_build")
		hud.add_child(_build_panel)
		_campaign = _demo.is_empty() and _capture_path.is_empty()
		_build_panel.start_pressed.connect(_start_battle)
		_build_panel.open(ui_scale)
		hud.set_battle_controls_visible(false)
	else:
		var picks := SkillTree.default_picks()
		_start_battle(_battle_id if _battle_id != "" else "1-4", picks)
	if _capture_path != "":
		_run_capture.call_deferred()


## 规则引擎没起来：说明原因，不进入战斗。
func _engine_missing() -> void:
	printerr(GoEngine.error)
	var label := Label.new()
	label.text = "无法启动规则引擎\n\n" + GoEngine.error
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Px.fit(label,28)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(label)
	if _capture_path != "" or DisplayServer.get_name() == "headless":
		get_tree().quit(1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GoEngine.shutdown()


func _start_battle(battle_id: String, picks: Dictionary) -> void:
	_battle_id = battle_id
	_skill_picks = picks.duplicate(true)
	_mission_name = Battles.title(battle_id)
	hud.set_battle_controls_visible(true)
	var gear:=_campaign_reward.duplicate()
	Checkpoint.settle_purse(_purse)
	gear["charms"]=Checkpoint.charms(_purse)
	state = Battles.build(battle_id, picks, _chiron_joined,gear,_party,_loadout,Checkpoint.gear_mods(_purse),_purse.get("kit",{}),_bench)
	# Who is drawn in colours of their own: the hired, by the look the camp gave them.
	UnitState.looks.clear()
	if _party is Array:
		for member: Dictionary in _party:
			if str(member.get("look","")) != "": UnitState.looks[member.id] = member.look
	if state == null:
		hud.banner("无法开始战斗：%s" % GoEngine.error, 0.0)
		return
	UnitState.looks["hero"] = Checkpoint.hero_look(state.reward)
	Rules.start_battle(state)
	if battle_id=="2-1":
		for order: Dictionary in _saved_orders:
			var reply:=state.command(order.duplicate(true))
			if not reply.has("state") or not reply.get("ok",true):
				hud.banner("护送进度读取失败，可按 R 从刑场入口重新开始。",0.)
				_mode=Mode.OVER
				return
		state.orders=_saved_orders.duplicate(true)
		state.record_orders=_campaign
	Soundscape.score("ridge")
	if battle_id in ["1-1","1-2","1-3","1-4","1-5","2-1","2-2","2-3","2-4","2-5","2-S","3-1"]:
		map_view.nemea = true
		map_view.wetland = MapView.Wetland.LERNA if battle_id in ["2-2","2-3","2-4","2-5","2-S"] else (MapView.Wetland.STYMPHALUS if battle_id.begins_with("3-") else MapView.Wetland.NONE)
		map_view.shrine = battle_id=="2-2"
		map_view.scale = Vector3(MapView.CHAPTER_CELL_PITCH,1.,MapView.CHAPTER_CELL_PITCH)
		highlights.scale = map_view.scale
		cam_rig.painted = true
		cam_rig.post.hide()
		cam_rig.set_quadrant(0)
		_on_resize()
	map_view.woodland = not state.rescue_exits.is_empty()
	map_view.village_sites = not state.village_exits.is_empty()
	map_view.build(state.grid)
	if battle_id=="2-1":
		var yard:=preload("res://view/corinth_yard.gd").new()
		_units_root.add_child(yard)
		yard.scale=map_view.scale
		yard.setup(map_view.field)
		for prop in [[preload("res://art/landmarks/gate.glb"),Vector2i(11,2),1.9],[preload("res://art/landmarks/ruin.glb"),Vector2i(1,5),2.0],[preload("res://art/landmarks/cart.glb"),Vector2i(0,7),1.5]]:
			var landmark:=NemeaField.landmark(prop[0],prop[2])
			var cell: Vector2i=prop[1]
			landmark.position=map_view.to_global(Vector3(cell.x+.5,map_view.cell_top(cell),cell.y+.5))
			_units_root.add_child(landmark)
	if battle_id=="1-3":
		var feast := preload("res://view/feast_display.gd").new()
		_units_root.add_child(feast)
		feast.scale = map_view.scale
		feast.setup(map_view.field)
	if not state.village_exits.is_empty():
		village = VillageDisplay.new()
		_units_root.add_child(village)
		village.scale = map_view.scale
		village.setup(map_view)
	for id in state.order:
		var u := state.unit(id)
		var v := PixelUnit.new()
		_units_root.add_child(v)
		v.setup(u,null,null)
		v.visible = state.units[id].alive
		unit_views[id] = v
	if not state.cave.is_empty():
		for id in state.cave["entrances"]:
			var anchor: Vector2i = state.cave["entrances"][id]["anchor"]
			var entrance := CaveMouth.new()
			cave_mouths[id] = entrance
			entrance.position = map_view.to_global(Vector3(anchor.x + 1, map_view.cell_top(anchor), anchor.y + 0.5))
			_units_root.add_child(entrance)
		for id in state.cave["boulders"]:
			var rock := NemeaField.landmark(preload("res://art/landmarks/boulder.glb"), 2.12)
			_units_root.add_child(rock)
			boulder_views[id] = rock
			if boulder_vertices.is_empty():
				var parts := rock.find_children("*","MeshInstance3D",true,false)
				var surface := parts[0] as MeshInstance3D
				boulder_vertices = surface.mesh.get_faces()
	_raise_cymbals()
	_sync_views()
	cam_rig.bounds = AABB(Vector3.ZERO, Vector3(state.grid.width, 0, state.grid.depth)*map_view.scale)
	cam_rig.focus(map_view.to_global(Vector3(state.grid.width * 0.5, 1.45 if village != null else 0.83, state.grid.depth * 0.5)))
	if battle_id=="1-3":
		cam_rig.focus(map_view.to_global(Vector3(6.0,1.25,5.1)))
	if map_view.woodland:
		cam_rig.focus(map_view.to_global(Vector3(4.5,1.28,5.7)))
		var cart := NemeaField.landmark(preload("res://art/landmarks/cart.glb"),1.55)
		cart.position = map_view.to_global(Vector3(-.55,map_view.cell_top(state.rescue_exits[0]),4.45))
		cart.rotation.y = -.48
		_units_root.add_child(cart)
	if cam_rig.painted and _demo in ["","idle"]:
		# Open with both sides between the top bar and the command panel. Pull back one
		# zoom step when the map is too deep for that; failing that, favour the party.
		var party: Array[Vector3] = []
		var everyone: Array[Vector3] = []
		for id in state.order:
			var member := state.unit(id)
			if not member.alive:
				continue
			var feet: Vector3 = unit_views[id].global_position
			everyone.append_array([feet,feet+Vector3.UP*1.9])
			if member.team == Defs.Team.PLAYER:
				party.append_array([feet,feet+Vector3.UP*1.9])
		if not cam_rig.spans(everyone,.12,.82) and cam_rig.zoom_index > 0:
			cam_rig.zoom_step(-1)
			cam_rig.focus(cam_rig.pivot)
		cam_rig.keep_in_view(everyone if cam_rig.spans(everyone,.12,.82) else party,.12,.82)
	if _wide:
		cam_rig.zoom_step(-1)
		var middle := Vector2i(state.grid.width/2,state.grid.depth/2)
		cam_rig.focus(map_view.to_global(Vector3(middle.x+.5,map_view.cell_top(middle),middle.y+.5)))
	hud.set_help_visible(true, cam_rig.painted)
	_refresh()
	hud.announce_phase(state.round_number, state.phase == Defs.Phase.PLAYER)
	_take_next()
	_save_checkpoint(battle_id)
	if battle_id=="2-1" and _saved_orders.is_empty():
		hud.banner("美狄亚加入队伍　·　护送她抵达东门",3.5)
	if battle_id=="2-2":
		hud.banner("穿过芦苇荡，抵达对岸　·　沼泽里过夜会中毒",3.5)
	if battle_id=="2-3":
		hud.banner("巨蟹正面只受一半伤害　·　绕到背后，或把它推进深水",3.5)
	if battle_id=="2-4":
		hud.banner("击倒三名女祭司　·　带火的招式能点着林地，火每回合蔓延一格",4.)
	if battle_id=="2-5":
		hud.banner("许德拉　·　砍下的头两回合后再生，用火烧封断颈",4.)
	if battle_id=="2-S":
		hud.banner("护送负伤的喀戎到泉边",3.5)
	if battle_id=="3-1":
		hud.banner("鸟在天上，近战够不着　·　站到铜钹旁敲响它，近处的鸟落地一回合",4.5)


# --- Scene construction --------------------------------------------------------

func _build_scene() -> void:
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	_viewport.positional_shadow_atlas_size = 1024
	_container.add_child(_viewport)

	var world := Node3D.new()
	world.name = "World"
	_viewport.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1b3f6e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.88)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(-Vector3(-0.25,0.75,0.60).normalized(),Vector3.UP)
	sun.directional_shadow_max_distance = 70.0
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.72
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	world.add_child(sun)

	map_view = MapView.new()
	world.add_child(map_view)
	highlights = HighlightLayer.new()
	highlights.map_view = map_view
	world.add_child(highlights)
	_units_root = Node3D.new()
	world.add_child(_units_root)
	cam_rig = CameraRig.new()
	cam_rig.sun = sun
	world.add_child(cam_rig)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.overlay.controller = self
	hud.menu_pressed.connect(_open_menu)
	hud.action_pressed.connect(_on_action)
	hud.next_unit_pressed.connect(_next_unit)
	hud.cancel_pressed.connect(_cancel)
	hud.order_inspected.connect(_inspect_enemy_order)
	hud.threat_changed.connect(func(on: bool):
		_show_threat = on
		_refresh()
	)
	hud.tactical_changed.connect(_set_tactical)
	hud.end_turn_pressed.connect(_end_turn)


func _on_resize() -> void:
	var size := get_viewport().get_visible_rect().size
	shrink = maxi(1, mini(floori(size.x / LOW_RES.x), floori(size.y / LOW_RES.y)))
	if cam_rig.painted:
		shrink = 1
	_container.stretch_shrink = shrink
	_container.size = size if cam_rig.painted else LOW_RES * shrink
	_container.position = ((size - _container.size) * 0.5).floor()
	hud.apply_scale(size)
	ui_scale = hud.ui_scale
	if state != null and not unit_views.is_empty():
		_refresh()
	elif is_instance_valid(_build_panel) and _build_panel.visible:
		_build_panel.open(ui_scale)


func world_to_screen(p: Vector3) -> Vector2:
	return _container.position + cam_rig.camera.unproject_position(p) * shrink


# --- Input -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		if event.is_action_pressed("ui_cancel"):
			get_tree().change_scene_to_file("res://title.tscn")
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event as InputEventKey)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_rig.zoom_step(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_rig.zoom_step(-1)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_from = mb.position if mb.pressed else Vector2.INF
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_click(_pick(mb.position))
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cancel()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_from != Vector2.INF:
			cam_rig.pan_pixels(mm.relative / shrink)
		var c := _pick(mm.position)
		if c != _hovered:
			_hovered = c
			_on_hover()


func _on_key(k: InputEventKey) -> void:
	if hud.journal_open():
		if k.keycode == KEY_ESCAPE:
			hud.close_journal()
		return
	if k.keycode == KEY_ESCAPE and hud.close_order():
		return
	if k.keycode >= KEY_1 and k.keycode <= KEY_9:
		hud.press_key(int(k.keycode-KEY_1))
		return
	match k.keycode:
		KEY_Q:
			cam_rig.rotate_step(-1)
		KEY_E:
			cam_rig.rotate_step(1)
		KEY_EQUAL, KEY_KP_ADD:
			cam_rig.zoom_step(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			cam_rig.zoom_step(-1)
		KEY_T:
			_show_threat = not _show_threat
			_refresh()
		KEY_TAB:
			_set_tactical(not tactical)
		KEY_P:
			if cam_rig.painted:
				return
			var mat := cam_rig.post.material_override as ShaderMaterial
			cam_rig.set_post_enabled(not mat.get_shader_parameter("enabled"))
		KEY_Z:
			if _selected != "" and _mode != Mode.BUSY:
				_perform({"type": "undo_move", "unit": _selected})
		KEY_SPACE, KEY_ENTER:
			_end_turn()
		KEY_ESCAPE:
			if (_mode == Mode.IDLE and _selected == "") or _mode == Mode.OVER:
				_open_menu()
			else:
				_cancel()
		KEY_R:
			if _next_battle=="camp": return
			_load_battle(_battle_id)
		KEY_F11:
			DisplayPrefs.fullscreen = not DisplayPrefs.fullscreen
			DisplayPrefs.commit()


func _entry(id: String) -> Dictionary:
	var entry: Dictionary={"purse":_purse.duplicate(true),"id":id,"picks":_skill_picks,"chiron_joined":_chiron_joined,"rescued":_rescued,"outcomes":_outcomes.duplicate(),"roster":_roster,"deploy":_deploy,"bench":_bench}
	if _party != null: entry.party = _party
	# What was used in this battle is gone from the bag and from whoever carried it.
	if state != null and entry.purse.has("kit"):
		for who: String in entry.purse.kit:
			var carrier := state.unit(who)
			if carrier == null: continue
			var left: Dictionary = carrier.items.duplicate()
			var kept := []
			for thing: String in entry.purse.kit[who]:
				if int(left.get(thing,0)) > 0:
					left[thing] = int(left[thing])-1
					kept.append(thing)
				else:
					entry.purse.bag[thing] = int(entry.purse.bag.get(thing,1))-1
					if int(entry.purse.bag[thing]) <= 0: entry.purse.bag.erase(thing)
			entry.purse.kit[who] = kept
	if _loadout != null: entry.loadout = _loadout
	if _xp != null: entry.xp = _xp
	if id=="2-1":
		entry.merge(_campaign_reward)
		entry.stage="battle"
		entry.medea_joined=true
		entry.orders=state.orders.duplicate(true)
	elif id.begins_with("2-"):
		# The second chapter is reached with the lion's pelt and Medea: keep both.
		entry.merge(_campaign_reward)
		entry.medea_joined=true
	return entry

func _save_checkpoint(id: String, choose_route := false) -> void:
	if not _campaign or id not in Checkpoint.BATTLES:
		return
	var entry := _entry(id)
	entry.choose_route = choose_route
	if Checkpoint.write_entry(entry) != OK:
		hud.banner("关卡进度保存失败，请检查本机存储空间。",4.)

func _load_battle(id: String) -> void:
	if id != "":
		var entry := _entry(id)
		entry.campaign = _campaign
		if id == "1-3": entry.chiron_joined = false
		if id == "1-2": entry.rescued = []
		if _campaign and id != _battle_id:
			entry.choose_route = _battle_id=="1-2" and _rescued.size()>=2
			get_tree().set_meta("camp_entry",entry)
			get_tree().change_scene_to_file("res://camp.tscn")
			return
		if id == _battle_id:
			entry.outcomes.erase(id)
			entry.erase("orders")
		get_tree().set_meta("battle_entry",entry)
	get_tree().reload_current_scene()


func _open_menu() -> void:
	if _mode == Mode.BUSY or get_tree().paused:
		return
	var menu := preload("res://ui/title_menu.gd").new()
	menu.in_battle = true
	if _campaign: menu.battle_map_entry = _entry(_battle_id)
	hud.get_parent().add_child(menu)
	get_tree().paused = true


## Unit sprites take priority over the tile under the cursor (sprites stand in front of tiles).
func _pick(screen: Vector2) -> Vector2i:
	if hud.is_over_panel(screen):
		return Defs.NO_POS
	if _mode in [Mode.IDLE,Mode.TARGET] and not _needs_landing():
		for id in hud.overlay.marker_hits:
			var rect: Rect2 = hud.overlay.marker_hits[id]
			var unit := state.unit(id)
			if rect.has_point(screen) and unit.alive and not unit.hidden:
				return unit.pos
	var best_depth := INF
	var best := Defs.NO_POS
	for id in state.order:
		var u: UnitState = state.units[id]
		if not u.alive or u.hidden:
			continue
		var v: UnitView = unit_views[id]
		var foot := world_to_screen(v.position)
		var head := world_to_screen(v.position + Vector3(0, v.sprite_height, 0))
		var half_w := (head.y - foot.y) * -0.35 * (1.3 if u.size > 1 else 1.0)
		var r := Rect2(Vector2(foot.x - half_w, head.y), Vector2(half_w * 2, foot.y - head.y))
		if r.has_point(screen):
			var depth := cam_rig.camera.global_position.distance_to(v.position)
			if depth < best_depth:
				best_depth = depth
				best = u.pos
	if best != Defs.NO_POS:
		return best
	var sub := (screen - _container.position) / shrink
	return map_view.pick(cam_rig.camera.project_ray_origin(sub), cam_rig.camera.project_ray_normal(sub))


func _click(cell: Vector2i) -> void:
	if hud.journal_open():
		return
	if _mode == Mode.BUSY or _mode == Mode.OVER or cell == Defs.NO_POS:
		return
	var at := state.unit_at(cell)
	match _mode:
		Mode.TARGET:
			if _needs_landing():
				var sk := SkillCatalog.get_skill(_pending["skill"])
				if Rules.leap_landing_error(state, state.unit(_selected), cell, sk) == "":
					_pending["to"] = cell
					_refresh()
				return
			var act := _pending.duplicate()
			act["unit"] = _selected
			act["target"] = cell
			if Rules.validate(state, act) == "":
				_perform(act)
		Mode.FACING:
			# Turn toward the cell clicked, then wait there.
			var u := state.unit(_selected)
			var who := _selected
			var d := cell - u.pos
			if d != Vector2i.ZERO:
				var f := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
				if f != u.facing:
					await _perform({"type": "face", "unit": who, "facing": f})
			if _selected == who and _mode not in [Mode.BUSY,Mode.OVER]:
				_perform({"type":"wait","unit":who})
		_:
			if at != null and at.team == Defs.Team.PLAYER and at.def_id != "refugee" and at.id != "wounded_chiron":
				if at.id != _selected: _select(at.id)
			elif _selected != "":
				var mv := {"type": "move", "unit": _selected, "to": cell}
				if Rules.validate(state, mv) == "":
					_perform(mv)
				elif at == null:
					_select("")


func _cancel() -> void:
	if hud.close_menu():
		return
	if _mode == Mode.TARGET or _mode == Mode.FACING:
		_set_mode(Mode.IDLE)
	elif _mode == Mode.IDLE:
		# Stepping back once more: a move just made is taken back before anyone is let go of.
		if _selected != "" and state.phase == Defs.Phase.PLAYER and state.move_undo.has(_selected):
			_perform({"type":"undo_move","unit":_selected})
		else:
			_select("")


func _select(id: String) -> void:
	if id != "" and id != _selected:
		Soundscape.cue("focus")
	if _selected != "" and unit_views.has(_selected):
		(unit_views[_selected] as UnitView).set_selected(false)
	_selected = id
	if id != "":
		(unit_views[id] as UnitView).set_selected(true)
	_set_mode(Mode.IDLE)


## Hands the turn to whoever should act next, so the player is never left with nobody
## selected: the hero when a turn begins, afterwards whoever stands nearest the one who has
## just finished. With nobody left, the end-turn button asks for attention; the turn is not
## ended for the player. Clicking anyone else at any time still works.
func _take_next(after := "") -> void:
	if state == null or state.phase != Defs.Phase.PLAYER or _mode in [Mode.BUSY,Mode.OVER] or not _demo in ["","idle","menu","facing","moved"]:
		return
	_refresh()
	var fresh: Array = _available_units.filter(func(id): return not state.unit(id).has_acted)
	var pool: Array = fresh if not fresh.is_empty() else _available_units.filter(func(id): return id != after)
	if pool.is_empty():
		_select("")
		hud.nudge_end_turn()
		return
	var next: String = pool[0]
	var from := state.unit(after) if after != "" else null
	if from == null:
		if pool.has("hero"): next = "hero"
	else:
		var nearest := 1 << 20
		for id: String in pool:
			var there := state.unit(id).pos
			var away := absi(there.x-from.pos.x)+absi(there.y-from.pos.y)
			if away < nearest:
				nearest = away
				next = id
	_select(next)
	_reveal_unit(next)


func _next_unit() -> void:
	if _available_units.is_empty() or _mode in [Mode.BUSY,Mode.OVER]:
		return
	var index := (_available_units.find(_selected)+1) % _available_units.size()
	var id := _available_units[index]
	hud.close_journal()
	_select(id)
	_reveal_unit(id)


func _reveal_unit(id: String) -> void:
	var view: UnitView = unit_views[id]
	var point := view.position+Vector3.UP*view.sprite_height*.5
	var screen := world_to_screen(point)
	var bounds := get_viewport().get_visible_rect().grow(-48*ui_scale)
	if not bounds.has_point(screen) or hud.is_over_panel(screen):
		cam_rig.glide_to(point)


func _set_mode(m: int) -> void:
	_mode = m
	if m != Mode.TARGET:
		_pending = {}
	_refresh()


func _on_action(index: int) -> void:
	if _mode in [Mode.BUSY,Mode.OVER] or index >= _actions.size() or not _actions[index].get("enabled",true):
		return
	Soundscape.cue("confirm")
	var a: Dictionary = _actions[index]
	match a["kind"]:
		"target":
			if _is_pending(a["action"]):
				_set_mode(Mode.IDLE)
			else:
				_pending = (a["action"] as Dictionary).duplicate()
				_mode = Mode.TARGET
				_refresh()
		"move":
			_set_mode(Mode.IDLE)
		"wait":
			# Waiting ends with choosing which way to face. Pressing 待机 again keeps the
			# facing as it is.
			if _mode == Mode.FACING:
				_perform({"type":"wait","unit":_selected})
			else:
				_set_mode(Mode.FACING)
		"do":
			var act: Dictionary = (a["action"] as Dictionary).duplicate()
			act["unit"] = _selected
			_perform(act)


# --- Actions & animation ---------------------------------------------------------

func _perform(action: Dictionary) -> void:
	var o := Rules.perform(state, action)
	if not o["ok"]:
		hud.banner(EventText.error_text(o["error"]))
		return
	_set_mode(Mode.BUSY)
	await _play(o["events"])
	if _check_end():
		return
	_set_mode(Mode.IDLE)
	if _battle_id=="2-1": _save_checkpoint(_battle_id)
	if action.unit == _selected:
		var actor := state.unit(_selected)
		if actor == null or not actor.alive or (actor.has_acted and actor.post_move <= 0):
			# Nothing left for this one to do: on to the next.
			_take_next(action.unit)
		elif action.type == "move":
			_reveal_unit(_selected)
		elif action.type == "skill" and actor.post_move > 0:
			_reveal_unit(_selected)
			unit_views[_selected].signal_post_move()


func _advance_phase() -> void:
	var from_round := state.round_number
	var events := Rules.end_phase(state)
	_refresh()
	await _play(events,from_round)


func _play(events: Array, from_round := -1) -> void:
	var recovery: Tween
	var attacker: UnitView
	var attack_source := ""
	var thrown_target := ""
	var defender: PixelUnit
	var ward: UnitView
	var guard_home := Vector3.ZERO
	for event in events:
		if event.type=="attack" and event.skill=="item_net" and not _auras.has("%s/rooted" % event.target):
			pending_net_binds[event.target] = true
		if event.type == "damage" and not hud.overlay.playback_hp.has(event.target):
			hud.overlay.playback_hp[event.target] = event.hp + event.amount
	for index in events.size():
		var e: Dictionary=events[index]
		var evade_slash := false
		if e.type in ["attack","assist"] and index+1<events.size():
			var result: Dictionary=events[index+1]
			if result.type=="dodge" and result.target==e.target:
				evade_slash=e.type=="attack" and e.skill=="slash" and state.unit(e.unit).def_id in ["bandit","bandit_chief"]
				if not evade_slash:
					(unit_views[e.target] as PixelUnit).begin_evade(unit_views[e.unit])
		match e["type"]:
			"move":
				await _animate_path(e["unit"], e["path"])
			"flee":
				var rider := unit_views[e.unit] as PixelUnit
				if rider.falling:
					await rider.finish_fall()
					continue
				_popup(e.unit,"退离宴地",Color.WHEAT)
				var direction := Vector2i.RIGHT
				rider.set_facing(direction)
				rider.walking = true
				var retreat := create_tween()
				retreat.tween_property(rider,"position:x",rider.position.x+1.4,.45)
				await retreat.finished
				rider.walking = false
				rider.hide()
			"rescued":
				var traveler: UnitView = unit_views[e.unit]
				var gone := create_tween()
				traveler.set_facing(Vector2i.LEFT)
				traveler.walking = true
				gone.tween_property(traveler,"position",traveler.position+Vector3.LEFT*.9,.34)
				await gone.finished
				traveler.walking = false
				traveler.hide()
				rescued_count += 1
				hud.overlay.add_popup(traveler.position+Vector3.UP*1.45,"安全撤离",Color("#9ae0c6"))
				_refresh()
			"cauterize":
				_popup(e.target,"烧封",Color("#ffb060"))
				Soundscape.cue("hit")
				BattleFX.spawn(_units_root,CAUTERIZE,map_view.anchor_world(state,state.unit(e.target).pos,1)+Vector3.UP*.5,.5)
				await get_tree().create_timer(.5).timeout
			"regrow":
				# A new head on the old neck: a fresh figure where the fallen one lay.
				var grown := state.unit(e.target)
				await BattleFX.spawn(_units_root,REGROW,map_view.anchor_world(state,grown.pos,1)+Vector3.UP*.9,.67).finished
				if unit_views.has(e.target): unit_views[e.target].queue_free()
				var fresh := PixelUnit.new()
				_units_root.add_child(fresh)
				fresh.setup(grown,null,null)
				fresh.position = map_view.anchor_world(state,grown.pos,grown.size)
				fresh.set_facing(grown.facing)
				unit_views[e.target] = fresh
				_popup(e.target,"再生",Color("#e0453a"))
				Soundscape.cue("warning")
				await get_tree().create_timer(.35).timeout
			"arrival":
				var newcomer := state.unit(e["unit"])
				var view: UnitView = unit_views[newcomer.id]
				view.position = map_view.anchor_world(state,newcomer.pos,newcomer.size)
				view.set_facing(newcomer.facing)
				view.show()
				if newcomer.team == Defs.Team.PLAYER:
					_reveal_unit(newcomer.id)
				_popup(newcomer.id, "山脊支援" if newcomer.team == Defs.Team.PLAYER else (newcomer.display_name + "入场" if map_view.woodland else "狼群增援"), Color.WHEAT)
				await get_tree().create_timer(0.18).timeout
			"face":
				var turning: UnitView = unit_views[e.unit]
				turning.set_facing(e.facing)
				if state.unit(e.unit).team == Defs.Team.ENEMY:
					await get_tree().create_timer(.14).timeout
			"undo_move":
				_sync_views()
			"leap":
				var lu := state.unit(e["unit"])
				var lv: UnitView = unit_views[lu.id]
				var to := map_view.anchor_world(state, e["to"], lu.size)
				if index+1<events.size() and events[index+1].get("skill","")=="thunder_step":
					_divine_flash(THUNDERSTEP,lv.position,.29,.77)
					await get_tree().create_timer(.13).timeout
					lv.position = to
				else:
					await _leap(lv, to, lu.def_id == "lion")
			"intercept":
				defender=unit_views[e.unit] as PixelUnit
				ward=unit_views[e.protected]
				guard_home=defender.position
			"throw":
				# Over the shoulder: the thrown one flies in an arc to wherever the knockback
				# that follows says they land. With nowhere to land they stay, and the
				# collision or the edge that follows tells why.
				_popup(e["target"], "过肩摔", Color(1, 0.85, 0.5))
				var thrower := unit_views[e.unit] as PixelUnit
				var flung := unit_views[e.target] as PixelUnit
				for follow in events:
					if follow.type == "knockback" and follow.target == e.target:
						thrown_target = e.target
						recovery = await _animate_throw(thrower,flung,map_view.anchor_world(state,follow.to,flung.size),state.unit(e.target).alive)
						break
			"knockback":
				if e.target != thrown_target:
					await _knockback(e)
			"assist":
				attacker = unit_views[e["unit"]]
				attack_source = "assist"
			"attack":
				if not _active_enemy.is_empty():
					_reveal_unit(e.target)
					hud.overlay.hit_target = e.target
				attacker = unit_views[e["unit"]]
				attack_source = e["skill"]
				var covered_spear: bool = defender!=null and e.skill=="spear" and state.unit(e.unit).def_id=="centaur"
				if defender!=null:
					hud.overlay.hit_target=ward.unit_id
					if not covered_spear:
						await attacker.turn_to_strike(ward.position)
						await _cover_step(defender,ward,attacker).finished
				if e.skill=="thunder_bolt":
					await _divine(e,events)
				elif covered_spear:
					recovery=await _centaur_strike(attacker as PixelUnit,ward,defender)
				elif (attacker as PixelUnit).epic_attack_sheet and e.skill in ["slash","heavy_cut","spear","trample","felling_blow","axe_sweep","shield_split","spear_breaker"]:
					recovery=await _epic_strike(attacker as PixelUnit,unit_views[e.target],state.unit(e.unit).look())
				elif e["skill"] == "spear" and state.unit(e["unit"]).def_id == "hero":
					recovery = await _spear_strike(unit_views[e["unit"]],unit_views[e["target"]])
				elif e.skill == "spear" and state.unit(e.unit).def_id == "centaur":
					recovery = await _centaur_strike(attacker as PixelUnit,unit_views[e.target])
				elif e.skill in ["witch_fire","solar_flame","frailty","cinder_lance","bind_hex","night_hex"]:
					var victim: UnitView=unit_views[e.target]
					await attacker.turn_to_strike(victim.position)
					attacker.set_pose(2,.28)
					await get_tree().create_timer(.29).timeout
					var spark:=MeshInstance3D.new()
					var orb:=SphereMesh.new()
					orb.radius=.17 if e.skill=="solar_flame" else .11
					orb.height=orb.radius*2
					spark.mesh=orb
					var glow:=StandardMaterial3D.new()
					glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
					glow.albedo_color=Color("#b972df") if e.skill in ["frailty","bind_hex","night_hex"] else Color("#ffac41")
					spark.material_override=glow
					_units_root.add_child(spark)
					var origin:=attacker.medea_release_point() if state.unit(e.unit).def_id=="medea" else attacker.position+Vector3.UP*1.3
					var aim:=_effect_origin(victim)
					spark.global_position=origin
					var shot:=create_tween()
					shot.tween_method(func(t: float): spark.global_position=origin.lerp(aim,t)+Vector3.UP*(1.6*t*(1.-t)),0.,1.,clampf(origin.distance_to(aim)/10.,.22,.48))
					await shot.finished
					spark.queue_free()
					attacker.set_pose(-1,.34)
				elif SkillCatalog.get_skill(e.skill).get("item",false):
					if e.skill=="item_net":
						var binds := events.any(func(ev): return ev.type=="status" and ev.target==e.target and ev.status=="rooted")
						await _throw_net(attacker,unit_views[e.target],binds)
						pending_net_binds.erase(e.target)
					else:
						await _throw_thing(attacker,unit_views[e.target],e.skill)
				elif e["skill"] == "heracles_bow":
					recovery = await _bow_shot(attacker,unit_views[e.target])
				elif e.skill == "bandit_bow" or (state.unit(e.unit).look()=="merc_archer" and SkillCatalog.get_skill(e.skill).get("ranged",false)):
					recovery = await _bandit_shot(attacker,unit_views[e.target])
				elif state.unit(e["unit"]).def_id == "chiron":
					recovery = await _chiron_shot(attacker as PixelUnit,unit_views[e.target])
				elif state.unit(e["unit"]).def_id == "atalanta" and SkillCatalog.get_skill(e["skill"]).get("ranged",false):
					recovery = await _bow_shot(attacker,unit_views[e["target"]])
				elif e["skill"] == "pounce":
					var lion: UnitView = unit_views[e["unit"]]
					recovery = lion.create_tween()
					recovery.tween_interval(.13)
					recovery.tween_callback(lion.set_pose.bind(-1,.24))
					recovery.tween_interval(.24)
					lion.face_point(unit_views[e["target"]].position)
				else:
					recovery = await _bump(e["unit"], e["target"],e["skill"],evade_slash)
			"damage":
				var intercepted: bool = defender!=null and e.target==defender.unit_id
				Soundscape.cue("shield_hit" if intercepted else _impact_sound(e.source, e.amount))
				hud.overlay.playback_hp[e.target] = maxi(0,e.hp)
				var victim: UnitView = unit_views[e.target]
				var force := Vector3.ZERO
				if attacker != null and e.source == attack_source:
					force = (victim.position-attacker.position).slide(Vector3.UP)
				var severity := float(e.amount)/state.unit(e.target).max_hp
				var painted := victim as PixelUnit
				if e.hp <= 0 and painted.fall_sheet != null:
					painted.start_fall(34. if e.target == thrown_target else 0.)
				elif e.target != thrown_target and not intercepted and not (
					painted.kind in ["bandit_chief","lion"] and index+2<events.size() and
					events[index+1].type=="stagger" and events[index+2].type=="broken" and events[index+2].target==e.target):
					painted.receive_impact(force,severity,e.source,e.amount==0)
				if intercepted:
					hud.overlay.hit_target=defender.unit_id
					_popup(e.target,"截击",Color("#a5dfd7"))
					BattleFX.contact(_units_root,"spear",defender.shield_contact()+cam_rig.camera.global_basis.z*.06,force)
				elif e.amount>0:
					if attack_source == e["source"] and attacker != null and state.unit(attacker.unit_id).def_id in ["atalanta","chiron","heracles","bandit_archer"] and SkillCatalog.get_skill(attack_source).get("ranged",false):
						BattleFX.contact(_units_root,"arrow",_effect_origin(victim),force)
					elif attack_source == e["source"] and attacker != null and SKILL_HIT.has(attack_source):
						var spit := BattleFX._sprite(_units_root,SKILL_HIT[attack_source])
						spit.position = _effect_origin(victim)
						# Drawn flying left to right: turn it when the blow comes from the right.
						spit.flip_h = (victim.position-attacker.position).dot(cam_rig.camera.global_basis.x) < 0.
						var flight := spit.create_tween()
						flight.tween_property(spit,"frame",spit.hframes-1,.5)
						flight.tween_callback(spit.queue_free)
					elif attack_source == e["source"] and attack_source in ["spear","shield_bash","bite"]:
						BattleFX.contact(_units_root,attack_source,_effect_origin(victim)-force.normalized()*.13,force)
					elif e.source != "fall":
						BattleFX.spawn(_units_root, IMPACT, _effect_origin(victim), 0.24)
				var col := Color("#ffc49e") if e["dmg_type"] != Defs.DamageType.TRUE else Color(1, 1, 1)
				var damage_text := "−%d" % e.amount if e.amount > 0 else "0"
				if e.source == "fall":
					damage_text = "坠落 " + damage_text
				_popup(e.target,damage_text,col,attacker)
				if intercepted:
					if e.hp>0:
						await _recover_cover(defender,guard_home,true)
					else:
						defender.release_intercept()
					defender=null
				await get_tree().create_timer(0.08).timeout
			"ko":
				if e.target == thrown_target:
					(unit_views[e.target] as PixelUnit).start_fall(34.)
				await (unit_views[e.target] as PixelUnit).finish_fall()
				_drop_spoils(e.target)
			"broken":
				Soundscape.cue("break_guard")
				_popup(e["target"], "破势！", Color(1, 0.85, 0.2))
				var broken := unit_views[e.target] as PixelUnit
				if broken.kind in ["bandit_chief","lion"] and not broken.falling:
					await broken.lose_balance()
			"stagger":
				_popup(e["target"], "破势 +%d" % e["amount"], Color(0.95, 0.6, 0.2))
			"dodge":
				_popup(e["target"], "闪避", Color(0.7, 0.9, 1))
				var hunter := unit_views[e.target] as PixelUnit
				if hunter.kind=="atalanta" and not hunter.falling:
					if hunter.balance_motion==null:
						hunter.begin_evade(attacker)
					await hunter.finish_evade()
				if defender!=null and e.target==defender.unit_id:
					await _recover_cover(defender,guard_home,false)
					defender=null
			"heal":
				if e.skill == "hera_blessing":
					BattleFX.spawn(_units_root,HERA_BLESSING,unit_views[e.target].position+Vector3.UP*.45,.67)
					_popup(e.target,"%s　+%d" % [SkillCatalog.get_skill(e.skill).name,e.amount],Color("#98e3ae"))
					await get_tree().create_timer(.4).timeout
				elif SkillCatalog.get_skill(e.skill).get("item",false):
					await _take_tonic(unit_views[e.unit],unit_views[e.target],e.skill)
					_popup(e.target,"%s　+%d" % [SkillCatalog.get_skill(e.skill).name,e.amount],Color("#98e3ae"))
				else:
					recovery=await _chiron_shot(unit_views[e.unit] as PixelUnit,unit_views[e.target])
					_popup(e.target,"净化箭　+%d"%e.amount,Color("#98e3ae"))
			"status":
				if e.status=="thunder_body":
					Soundscape.cue("warning")
					_divine_flash(THUNDERBODY,unit_views[e.target].position,.45)
					_popup(e.target,"雷躯",_divine_tint())
					await get_tree().create_timer(.44).timeout
					continue
				if e.status == "blighted":
					BattleFX.spawn(_units_root,HYDRA_VENOM,unit_views[e.target].position+Vector3.UP*.7,.67)
				_popup(e["target"], EventText.STATUS_NAMES.get(e["status"], e["status"]), Color(0.8, 0.9, 1))
			"stun_skip":
				_popup(e["unit"], "眩晕", Color(1, 0.85, 0.2))
			"ward":
				_popup(e.target,"护盾 +%d" % int(e.amount),Color("#8fd0ff"))
				if not events.any(func(ev): return ev.get("skill","")=="sky_dome"):
					BattleFX.spawn(_units_root,BLESS,unit_views[e.target].position+Vector3.UP*.08,.3)
			"strike":
				# The cymbal rings: a flash over it, and whatever was aloft nearby comes down.
				var spot := Vector2i(int(e.to[0]),int(e.to[1]))
				Soundscape.cue("hit")
				_popup(e.unit,"铜钹",Color("#e8b95a"))
				BattleFX.spawn(_units_root,ROAR,map_view.anchor_world(state,spot,1)+Vector3.UP*.9,.5)
				_sync_cymbals()
				await get_tree().create_timer(.35).timeout
			"support":
				await _support_arrives(e)
			"area":
				if Checkpoint.power_words(e.skill) != "":
					await _divine(e,events)
					continue
				if e.skill == "roar" and state.unit(e.unit).def_id == "lion":
					var caller: UnitView = unit_views[e.unit]
					var inhale := caller.create_tween()
					inhale.tween_method(caller.set_roar_lift,0.,-.26,.18).set_trans(Tween.TRANS_SINE)
					inhale.tween_method(caller.set_roar_lift,-.26,1.,.17).set_trans(Tween.TRANS_SINE)
					await inhale.finished
					recovery = caller.create_tween()
					recovery.tween_method(caller.set_roar_lift,1.,.83,.18)
					recovery.tween_method(caller.set_roar_lift,.83,0.,.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				Soundscape.cue("warning")
				var rows := Hud.CombatRecord.collect(state,events)
				for row in rows:
					if row.linked and not row.target_id.is_empty() and not row.outcome.is_empty():
						hud.overlay.set_health_forecast(row)
				BattleFX.spawn(_units_root, ROAR, _effect_origin(unit_views[e["unit"]]), 0.38)
				_popup(e["unit"], EventText.skill_name(e["skill"]), Color(1, 0.6, 0.3))
				await get_tree().create_timer(0.25).timeout
			"push":
				await _push_boulder(e.unit,e.boulder,e.progress)
			"sealed":
				var anchor: Vector2i = state.cave.entrances[e.entrance].anchor
				var end := _plug_position(anchor)
				Soundscape.cue("hit")
				cave_mouths[e.entrance].shed_stones()
				BattleFX.spawn(_units_root, DUST, end + Vector3.UP * 0.25, 0.3)
				hud.overlay.add_popup(end + Vector3.UP * 1.55, "%s已封住" % EventText.ENTRANCE_NAMES.get(e.entrance,e.entrance), Color.WHEAT)
				_sync_views()
			"retreat":
				_popup(e["unit"], "退回洞内", Color(1, 0.85, 0.2))
				await get_tree().create_timer(0.35).timeout
				_sync_views()
			"emerge":
				var mouth: Node3D = cave_mouths[e.entrance]
				var lion: UnitView = unit_views[e.unit]
				var exit := map_view.anchor_world(state,e.to,lion.size)
				mouth.set_warning(false)
				mouth.shed_stones()
				cam_rig.glide_to(mouth.position + Vector3.UP*.65)
				await get_tree().create_timer(.36).timeout
				lion.position = mouth.position + Vector3(0,-.32,-.61)
				lion.face_point(exit)
				lion.set_pose(3,.12)
				lion.show()
				var charge := lion.create_tween()
				charge.tween_callback(lion.set_pose.bind(2,.18))
				charge.tween_property(lion,"position",exit,.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				await charge.finished
				Soundscape.cue("paw")
				BattleFX.spawn(_units_root,DUST,exit,.26)
				lion.set_pose(-1,.16)
				await get_tree().create_timer(.16).timeout
	if recovery != null and recovery.is_running():
		await recovery.finished
	hud.overlay.hit_target = ""
	hud.overlay.forecasts.clear()
	hud.overlay.playback_hp.clear()
	hud.record_events(state,events,from_round)
	_sync_views()


func _animate_throw(holder: PixelUnit, held: PixelUnit, landing: Vector3, survives: bool) -> Tween:
	var raider := holder.kind=="hero" and held.kind=="bandit" and holder.raider_throw_sheet != null
	var home := holder.position
	var origin := held.position
	var facing := (origin-home).slide(Vector3.UP).normalized()
	holder.face_point(origin)
	var load := holder.create_tween()
	load.tween_property(holder,"position",home+facing*.13,.22).set_trans(Tween.TRANS_SINE)
	if raider:
		load.parallel().tween_method(held.set_raider_throw,12.,24.,.22)
		load.parallel().tween_method(holder.set_raider_throw,12.,24.,.22)
	await load.finished
	var flight := held.create_tween()
	flight.tween_method(func(t: float):
		held.position=origin.lerp(landing,t)
		# High enough to clear the thrower's head on the way over.
		held.position.y+=3.1*t*(1.-t)
		if raider: held.set_raider_throw(lerpf(24.,40.,t)),0.,1.,.40)
	flight.parallel().tween_property(holder,"position",home,.32)
	if raider:
		flight.parallel().tween_method(holder.set_raider_throw,24.,40.,.40)
	await flight.finished
	held.position=landing
	BattleFX.spawn(_units_root,DUST,landing+Vector3.UP*.08,.26)
	Soundscape.cue("hit")
	if not raider:
		return null
	var recover := holder.create_tween()
	recover.tween_method(holder.set_raider_throw,40.,55.,.23)
	recover.tween_callback(holder.set_raider_throw.bind(-1.))
	if not survives:
		return null
	var rise := held.create_tween()
	rise.tween_interval(.16)
	rise.tween_method(held.set_raider_throw,40.,55.,.69).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	rise.tween_callback(held.set_raider_throw.bind(-1.))
	return rise


func _knockback(event: Dictionary) -> void:
	var victim: UnitView = unit_views[event.target]
	var start := victim.position
	var end := map_view.anchor_world(state,event.to,victim.size)
	var drop := start.y-end.y
	var motion := create_tween()
	if drop > .01:
		# Clear the lip before gravity pulls the feet down to the lower terrace.
		var lip := start.lerp(end,.44)
		lip.y = start.y+.10
		motion.tween_property(victim,"position",lip,.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		motion.tween_method(func(t: float):
			var at := lip.lerp(end,t)
			at.y = lerpf(lip.y,end.y,t*t)
			victim.position = at,
			0.,1.,clampf(.20*sqrt(drop),.17,.39))
	else:
		motion.tween_property(victim,"position",end,.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await motion.finished
	if drop > .01:
		BattleFX.spawn(_units_root,DUST,end+Vector3.UP*.06,.23)


func _impact_sound(source: String, amount: int) -> String:
	if amount <= 0:
		return "guard"
	match source:
		"spear": return "spear_hit"
		"shield_bash": return "shield_hit"
		"bite": return "bite"
	if SkillCatalog.get_skill(source).get("ranged", false):
		return "arrow_hit"
	return "hit"


func _animate_path(id: String, path: Array) -> void:
	var u := state.unit(id)
	var v: UnitView = unit_views[id]
	if u.def_id in ["heracles","wolf","boar"]:
		await _walk_planted(v,path,u.def_id)
		return
	var step_seconds := .36 if u.def_id == "lion" else .26
	var tw := create_tween()
	var prev: Vector3 = v.position
	if path.is_empty():
		tw.kill()
		return
	v.walking = true
	for cell in path:
		var to := map_view.anchor_world(state, cell, u.size)
		var heading := Vector2i(roundi(to.x-prev.x), roundi(to.z-prev.z))
		if heading != Vector2i.ZERO:
			tw.tween_callback(v.set_facing.bind(heading))
		if map_view.field != null and u.size == 1:
			tw.tween_method(_follow_slope.bind(v,prev,to),0.0,1.0,step_seconds)
		elif absf(to.y - prev.y) > 0.01:
			var mid := Vector3((prev.x + to.x) * 0.5, maxf(prev.y, to.y) + 0.12, (prev.z + to.z) * 0.5)
			tw.tween_property(v, "position", mid, step_seconds*.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(v, "position", to, step_seconds*.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		else:
			tw.tween_property(v, "position", to, step_seconds)
		var wet := state.grid.terrain_at(cell) in [Defs.Terrain.SHALLOW, Defs.Terrain.DEEP, Defs.Terrain.SWAMP, Defs.Terrain.STYX]
		var footfall := "paw" if u.def_id in ["wolf","lion"] else "step"
		tw.tween_callback(Soundscape.cue.bind("splash" if wet else footfall))
		tw.tween_callback(BattleFX.spawn.bind(_units_root, STEP_DUST, to + Vector3.UP * 0.12, 0.18))
		prev = to
	await tw.finished
	v.walking = false


# Finish a planted step before changing heading. Straight runs keep their momentum.
func _walk_planted(view: UnitView, path: Array, kind: String) -> void:
	var step_seconds := .24 if kind == "wolf" else (.32 if kind == "boar" else .36)
	var plant_seconds := .10 if kind == "wolf" else .13
	var footfall := "paw" if kind == "wolf" else "step"
	var index := 0
	while index < path.size():
		var start := view.position
		var local_start := map_view.to_local(start)
		var cell := Vector2i(roundi(local_start.x-view.size*.5),roundi(local_start.z-view.size*.5))
		var heading: Vector2i = path[index]-cell
		if heading == Vector2i.ZERO:
			index += 1
			continue
		var count := 1
		while index+count < path.size() and path[index+count]-path[index+count-1] == heading:
			count += 1
		await view.plant_and_turn(heading)
		view.walking = true
		var run := create_tween()
		var origin := cell
		var advance := func(distance: float):
			var whole := mini(floori(distance),count-1)
			var tile := origin+heading*whole
			var a := map_view.anchor_world(state,tile,view.size)
			var b := map_view.anchor_world(state,tile+heading,view.size)
			if view.size == 1:
				_follow_slope(distance-whole,view,a,b)
			else:
				view.position = a.lerp(b,distance-whole)
				view.position.y = lerpf(a.y,b.y,smoothstep(0.,1.,distance-whole))
		run.tween_method(advance,0.,.18,plant_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		run.tween_method(advance,.18,count-.18,(count-.36)*step_seconds)
		run.tween_method(advance,count-.18,float(count),plant_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# The contact drawings take weight just after each half-step starts.
		var steps := create_tween()
		for n in count:
			var tile := cell+heading*(n+1)
			var wet := state.grid.terrain_at(tile) in [Defs.Terrain.SHALLOW,Defs.Terrain.DEEP,Defs.Terrain.SWAMP,Defs.Terrain.STYX]
			steps.tween_interval(plant_seconds+.06 if n == 0 else step_seconds)
			steps.tween_callback(Soundscape.cue.bind("splash" if wet else footfall))
			if kind != "heracles":
				steps.tween_callback(func(): BattleFX.spawn(_units_root,STEP_DUST,view.position+Vector3.UP*.12,.18))
		await run.finished
		view.walking = false
		index += count


func _set_tactical(on: bool) -> void:
	tactical = on
	cam_rig.tactical = on
	map_view.set_tactical(on)
	if village != null:
		village.visible = not on
		if not on:
			village.sync_fire(state.grid)
	_refresh()


func _follow_slope(t: float, view: UnitView, start: Vector3, finish: Vector3) -> void:
	var point := start.lerp(finish,t)
	if map_view.field != null:
		var ground := map_view.to_local(point)
		point.y = map_view.field.elevation(ground.x,ground.z)
	view.position = point


## Rolls what a beaten enemy leaves and adds it to the battle's haul. Shown over where they
## fell, one line a thing, unless `shown` is false. Each enemy is counted once.
func _drop_spoils(id: String, shown := true) -> void:
	var fallen := state.unit(id)
	if fallen == null or fallen.team != Defs.Team.ENEMY or _looted.has(id) or not (_campaign or _demo == "spoils"):
		return
	_looted[id] = true
	var dice := RandomNumberGenerator.new()
	dice.randomize()
	var left := Checkpoint.roll_loot([fallen.def_id],dice)
	var view: UnitView = unit_views.get(id)
	var row := 0
	for thing: String in left:
		_haul[thing] = int(_haul.get(thing,0))+int(left[thing])
		if shown and view != null:
			var rare: String = Checkpoint.GOODS[thing].get("rarity","common")
			var words: String = Checkpoint.GOODS[thing].name+(" ×%d" % int(left[thing]) if int(left[thing]) > 1 else "")
			hud.overlay.add_popup(view.position+Vector3.UP*.9,words,Color(str(Checkpoint.RARITY[rare].tint)),Px.icon(Checkpoint.art(thing),32),row)
			row += 1
	if shown and not left.is_empty(): Soundscape.cue("confirm")


## A small card of a thing's drawing, standing in the world: what is thrown or drunk.
func _thing_card(thing: String, at: Vector3, tint: Color) -> Sprite3D:
	var card := Sprite3D.new()
	card.texture = Px.icon(Checkpoint.art(thing) if Checkpoint.GOODS.has(thing) else thing,32)
	card.pixel_size = .014
	card.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	card.shaded = false
	card.no_depth_test = true
	card.modulate = tint
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_units_root.add_child(card)
	card.position = at
	return card


## Something carried is thrown: it leaves the thrower's hand, arcs over, and lands on the target.
func _throw_thing(thrower: UnitView, target: UnitView, thing: String) -> void:
	await thrower.turn_to_strike(target.position)
	var hand := thrower.position+Vector3.UP*thrower.sprite_height*.72
	var mark := _effect_origin(target)
	var fiery := thing == "item_firepot"
	# The kit stamp shows the loaded sling. Only its stone leaves the hand.
	var projectile := "sling_stone" if thing == "item_stone" else thing
	var card := _thing_card(projectile,hand,Color("#ffb066") if fiery else Color("#f1e3c4"))
	var flight := clampf(hand.distance_to(mark)/9.0,.26,.5)
	var lift := 1.1+hand.distance_to(mark)*.12
	Soundscape.cue("swing")
	var arc := create_tween()
	arc.tween_method(func(t: float):
		card.position = hand.lerp(mark,t)+Vector3.UP*lift*4.0*t*(1.0-t)
		card.rotation.z = -t*TAU*(2.0 if thing in ["item_stone","item_firepot"] else .0),0.0,1.0,flight)
	await arc.finished
	card.queue_free()
	if thing in ["item_stone","item_javelin"]:
		BattleFX.spawn(_units_root,THUD,mark,.3)
	if fiery:
		BattleFX.spawn(_units_root,BURST,target.position+Vector3.UP*.08,.3)
		# Three tongues of flame where it breaks.
		for n in 3:
			var flame := _thing_card("kindling",mark+cam_rig.camera.global_basis.x*(n-1)*.22,Color("#ff8a3a"))
			flame.scale = Vector3.ONE*.5
			var rise := create_tween()
			rise.tween_property(flame,"scale",Vector3.ONE*(1.5+n*.2),.22).set_delay(n*.05)
			rise.parallel().tween_property(flame,"position:y",flame.position.y+.55,.5).set_delay(n*.05)
			rise.parallel().tween_property(flame,"modulate:a",0.0,.3).set_delay(.25+n*.05)
			rise.tween_callback(flame.queue_free)


## Both the final cast frame and the first binding frame use this same ankle-space anchor.
func _ankles(view: UnitView) -> Vector3:
	var axes := cam_rig.camera.global_basis
	return axes.y*view.sprite_height*.135 + axes.z*.22

func _net_size(view: UnitView) -> float:
	return NET_PIXEL_SIZE*(1.30 if view.size>1 else 1.0)

func _throw_net(thrower: UnitView, target: UnitView, binds: bool) -> void:
	await thrower.turn_to_strike(target.position)
	var axes := cam_rig.camera.global_basis
	var side := signf((target.position-thrower.position).dot(axes.x))
	var hand := thrower.position+axes.y*thrower.sprite_height*.56+axes.x*.22*side+axes.z*.18
	var net := BattleFX._sprite(_units_root,CAST_NET)
	net.pixel_size = _net_size(target)
	net.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	net.render_priority = 2
	net.position = hand
	var feet := target.position+_ankles(target)
	var landing := feet if binds else feet+axes.x*side*.56
	var spread := landing+axes.y*target.sprite_height*.38
	var flight := clampf(hand.distance_to(landing)/7.,.40,.64)
	Soundscape.cue("swing")
	var toss := net.create_tween()
	toss.tween_method(func(t: float):
		net.position = hand.lerp(spread,t)+Vector3.UP*(.9+flight)*4.*t*(1.-t)
		net.frame = mini(4,floori(t*5.))
		net.rotation.z = .24*side*sin(PI*t),0.,1.,flight)
	toss.tween_interval(.055)
	toss.tween_method(func(t: float):
		net.position = spread.lerp(landing,t)
		net.frame = 4+mini(3,floori(t*4.)) if binds else 4
		if not binds: net.modulate.a=1.-t,0.,1.,.30)
	await toss.finished
	net.queue_free()


## Something carried is drunk or handed over: it rises over whoever takes it and fades, with
## a ring of green opening at their feet.
func _take_tonic(giver: UnitView, taker: UnitView, thing: String) -> void:
	if giver != taker:
		await giver.turn_to_strike(taker.position)
	var over := taker.position+Vector3.UP*(taker.sprite_height*.55)
	var card := _thing_card(thing,over,Color("#b9f0c4"))
	card.scale = Vector3.ONE*.7
	Soundscape.cue("confirm")
	BattleFX.spawn(_units_root,BLESS,taker.position+Vector3.UP*.08,.3)
	var sip := create_tween()
	sip.tween_property(card,"scale",Vector3.ONE*1.5,.16).set_ease(Tween.EASE_OUT)
	sip.tween_property(card,"position:y",over.y+.8,.42).set_ease(Tween.EASE_OUT)
	sip.parallel().tween_property(card,"modulate:a",0.0,.3).set_delay(.14)
	sip.tween_callback(card.queue_free)
	for n in 5:
		var mote := _thing_card("heart",taker.position+Vector3(randf_range(-.35,.35),.15+randf_range(0,.3),randf_range(-.2,.2)),Color("#8fe6a6"))
		mote.scale = Vector3.ONE*.35
		var drift := create_tween()
		drift.tween_property(mote,"position:y",mote.position.y+1.2,.7).set_delay(n*.06)
		drift.parallel().tween_property(mote,"modulate:a",0.0,.35).set_delay(.35+n*.06)
		drift.tween_callback(mote.queue_free)
	await get_tree().create_timer(.45).timeout


## Keeps the effects worn on bodies in step with the statuses the rules say they have:
## one appears the moment a status does and goes when it ends, or when its wearer falls.
func _process(_delta: float) -> void:
	if state == null: return
	var due := {}
	for id: String in unit_views:
		var wearer := state.unit(id)
		if wearer == null or not wearer.alive or wearer.hidden or not is_instance_valid(unit_views[id]): continue
		for status: String in AURAS:
			if status=="rooted" and pending_net_binds.has(id): continue
			if wearer.has_status(status): due["%s/%s" % [id,status]] = [id,status]
	for key: String in _auras.keys():
		if not due.has(key) or not is_instance_valid(_auras[key]):
			if is_instance_valid(_auras[key]): _auras[key].queue_free()
			_auras.erase(key)
	for key: String in due:
		var view: UnitView = unit_views[due[key][0]]
		if _auras.has(key):
			if due[key][1]=="rooted": _auras[key].position = _ankles(view)
			continue
		var look: Array = AURAS[due[key][1]]
		# A hair toward the camera, so the card is drawn over its wearer and not through them.
		_auras[key] = BattleFX.aura(view,look[0],Vector3.UP*view.sprite_height*float(look[1])+Vector3(0,0,.05),float(look[2]) if look.size() > 2 else 1.0)
		if due[key][1]=="rooted":
			_auras[key].modulate.a = 1.0
			_auras[key].pixel_size = _net_size(view)
			_auras[key].position = _ankles(view)
			_auras[key].alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		elif due[key][1]=="thunder_body":
			_auras[key].modulate = _divine_tint()
			_auras[key].alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED


func _divine_tint() -> Color:
	return Color(str(Checkpoint.TIERS[Checkpoint.tier(state.reward)].tint))


func _divine_flash(texture: Texture2D, ground: Vector3, seconds: float, size := 1.0) -> void:
	var fx := BattleFX._sprite(_units_root,texture)
	fx.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	fx.pixel_size = .033*size
	fx.offset.y = 36.
	fx.modulate = _divine_tint()
	fx.global_position = ground + cam_rig.camera.global_basis.z*.24
	fx.render_priority = 2
	var anim := fx.create_tween()
	anim.tween_property(fx,"frame",fx.hframes-1,seconds)
	anim.tween_callback(fx.queue_free)


## A divine technique lands: its name in the tier's colour, and light on every cell it
## reaches. The colour is the tier's, so the same technique looks less human as he rises.
func _divine(e: Dictionary, events: Array) -> void:
	var def: Dictionary = SkillCatalog.get_skill(e.skill)
	var tier := Checkpoint.tier_of(int(state.reward.get("divinity",0)))
	var tint := _divine_tint()
	var caster: UnitView = unit_views[e.unit]
	var cells: Array[Vector2i] = []
	if def.has("blast"):
		var reach := int(def.blast)
		for dy in range(-reach,reach+1):
			for dx in range(-reach,reach+1):
				if def.get("square",false) or absi(dx)+absi(dy) <= reach:
					var cell: Vector2i = e.to+Vector2i(dx,dy)
					if state.grid.in_bounds(cell): cells.append(cell)
		caster.face_point(map_view.anchor_world(state,e.to,1))
	_popup(e.unit,str(def.name),tint)
	Soundscape.cue("warning")
	var rows := Hud.CombatRecord.collect(state,events)
	for row in rows:
		if row.linked and not row.target_id.is_empty() and not row.outcome.is_empty():
			hud.overlay.set_health_forecast(row)
	match e.skill:
		"thunder_bolt":
			var target: UnitView = unit_views[e.target]
			await caster.turn_to_strike(target.position)
			_divine_flash(LIGHTNING,target.position,.50,1.18)
		"sky_fire","sky_wrath":
			var center: Vector2i = e.to
			var texture := SKYFIRE if e.skill=="sky_fire" else LIGHTNING
			_divine_flash(texture,map_view.anchor_world(state,center,1),.63,1.14)
			await get_tree().create_timer(.11).timeout
			for cell in cells:
				if cell!=center:
					_divine_flash(texture,map_view.anchor_world(state,cell,1),.50,.71)
		"thunder_step":
			_divine_flash(THUNDERSTEP,caster.position,.47)
		"sky_dome":
			for event in events:
				if event.type=="ward":
					_divine_flash(DOME,unit_views[event.target].position,.77,1.20)
	if tier >= 3:
		# The ground itself answers: a few quick shoves of the view that sum to nothing.
		var shake := create_tween()
		for push: Vector2 in [Vector2(5,0),Vector2(-9,3),Vector2(6,-5),Vector2(-2,2)]:
			shake.tween_callback(cam_rig.pan_pixels.bind(push))
			shake.tween_interval(.04)
	await get_tree().create_timer(.3).timeout


func _effect_origin(unit: UnitView) -> Vector3:
	return unit.position + Vector3.UP * unit.sprite_height * 0.55 + cam_rig.camera.global_basis.z * 0.28


func _leap(view: UnitView, landing: Vector3, heavy: bool) -> void:
	var start := view.position
	view.face_point(landing)
	var height := (1.05 if heavy else .8) + absf(landing.y-start.y)*.32
	var leap := view.create_tween()
	if heavy:
		view.set_pose(3,.19)
		view.signal_pounce()
		leap.tween_interval(.24)
		leap.tween_callback(view.set_pose.bind(2,.15))
	var duration := clampf(.34+start.distance_to(landing)*.056,.43,.69) if heavy else .34
	leap.tween_method(func(progress: float):
		view.position = start.lerp(landing,progress)
		var lift := 4.*height*progress*(1.-progress)
		if heavy:
			view.lift_body(lift)
		else:
			view.position.y += lift,
		0.,1.,duration)
	if heavy:
		# Reach with the forepaws during descent, before contact starts the recovery.
		leap.parallel().tween_callback(view.set_pose.bind(4,.17)).set_delay(duration-.14)
	await leap.finished
	if heavy:
		Soundscape.cue("paw")
	BattleFX.spawn(_units_root,DUST if heavy else STEP_DUST,landing + Vector3.UP*0.12,0.32)


func _cover_step(hero: PixelUnit, ally: UnitView, source: UnitView) -> Tween:
	var incoming := (source.position-ally.position).slide(Vector3.UP).normalized()
	var cover := ally.position+incoming*.48
	var step := (cover-hero.position).limit_length(.86)
	hud.overlay.hit_target=hero.unit_id
	hero.face_point(source.position)
	hero.intercept_side=step.normalized().dot(cam_rig.camera.global_basis.x)
	hero.intercept_pose=0.
	var enter := hero.create_tween().set_parallel()
	enter.tween_property(hero,"position",hero.position+step,.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	enter.tween_property(hero,"intercept_pose",1.,.24)
	enter.tween_callback(Soundscape.cue.bind("step")).set_delay(.20)
	return enter


func _recover_cover(hero: PixelUnit, home: Vector3, contact: bool) -> void:
	if contact:
		hero.intercept_contact=true
		hero.intercept_pose=0.
		var absorb := hero.create_tween()
		absorb.tween_property(hero,"intercept_pose",1.,.41)
		await absorb.finished
	hero.intercept_contact=false
	hero.intercept_pose=1.
	hero.intercept_side=-hero.intercept_side
	var recover := hero.create_tween().set_parallel()
	recover.tween_property(hero,"position",home,.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	recover.tween_property(hero,"intercept_pose",0.,.38)
	await recover.finished
	hero.release_intercept()


## The bronze cymbals of the lake shore: a disc hung on a post at each one's cell. A stand-in
## until the painted one is made (28-art-backlog).
var _cymbal_views := {}

func _raise_cymbals() -> void:
	for view: Node3D in _cymbal_views.values(): view.queue_free()
	_cymbal_views.clear()
	if state == null: return
	for cymbal: Dictionary in state.cymbals:
		var stand := Node3D.new()
		var post := MeshInstance3D.new()
		var shaft := CylinderMesh.new()
		shaft.top_radius = .035
		shaft.bottom_radius = .05
		shaft.height = 1.0
		post.mesh = shaft
		post.position.y = .5
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("#5a4630")
		post.material_override = wood
		stand.add_child(post)
		var disc := MeshInstance3D.new()
		var plate := CylinderMesh.new()
		plate.top_radius = .3
		plate.bottom_radius = .3
		plate.height = .035
		disc.mesh = plate
		disc.rotation_degrees = Vector3(90,0,25)
		disc.position.y = .92
		var bronze := StandardMaterial3D.new()
		bronze.albedo_color = Color("#c98a3c")
		bronze.metallic = .7
		bronze.roughness = .35
		disc.material_override = bronze
		disc.name = "disc"
		stand.add_child(disc)
		stand.position = map_view.anchor_world(state,cymbal.pos,1)+Vector3(.28,0,-.28)
		_units_root.add_child(stand)
		_cymbal_views[cymbal.pos] = stand
	_sync_cymbals()

## A cymbal that has just rung hangs dull until it can ring again; and every flying unit is
## told whether it is on the ground.
func _sync_cymbals() -> void:
	if state == null: return
	for cymbal: Dictionary in state.cymbals:
		var stand: Node3D = _cymbal_views.get(cymbal.pos)
		if stand == null: continue
		var disc := stand.get_node("disc") as MeshInstance3D
		(disc.material_override as StandardMaterial3D).albedo_color = Color("#c98a3c") if int(cymbal.rest) == 0 else Color("#6b5a44")
	for id in state.order:
		var u := state.unit(id)
		if u.has_trait("flying") and unit_views.has(id) and unit_views[id] is PixelUnit:
			(unit_views[id] as PixelUnit).grounded = u.has_status("grounded")

## A hired hero answers the call: he steps in beside the protagonist, on the side nearest
## where he is needed, strikes once and is gone. He is a figure only: the rules never had
## him on the field. Drawn from the sheets he already has until his own arrival is painted
## (28-art-backlog §0.4).
func _support_arrives(e: Dictionary) -> void:
	var kind := str(e.source)
	var record: Dictionary = Checkpoint.RECRUITS.get(kind,{})
	var aim := Vector2i(int(e.to[0]),int(e.to[1]))
	Soundscape.cue("warning")
	hud.banner("%s · %s" % [str(record.get("name","援军")),EventText.skill_name(e.skill)])
	var hero := state.unit(str(e.unit))
	if record.is_empty() or hero == null:
		await get_tree().create_timer(.3).timeout
		return
	# The free cell beside the protagonist nearest the aim; his own cell if he is hemmed in.
	var stand := hero.pos
	var nearest := 9999
	for step: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
		var cell := hero.pos+step
		if not state.grid.in_bounds(cell) or state.unit_at(cell) != null or cell == aim: continue
		var far := absi(cell.x-aim.x)+absi(cell.y-aim.y)
		if far < nearest:
			nearest = far
			stand = cell
	var ghost := UnitState.new()
	ghost.id = "support:"+kind
	ghost.def_id = str(record.def)
	ghost.display_name = str(record.name)
	ghost.pos = stand
	UnitState.looks[ghost.id] = str(record.get("look",record.def))
	var figure := PixelUnit.new()
	_units_root.add_child(figure)
	figure.setup(ghost,null,null)
	figure.position = map_view.anchor_world(state,stand,1)
	var mark := map_view.anchor_world(state,aim,1)
	figure.face_point(mark)
	figure.scale = Vector3.ONE*.6
	var entrance := figure.create_tween()
	entrance.tween_property(figure,"scale",Vector3.ONE,.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await entrance.finished
	figure.play_attack()
	await get_tree().create_timer(.22).timeout
	BattleFX.spawn(_units_root,ROAR,mark+Vector3.UP*.3,.3)
	await get_tree().create_timer(.3).timeout
	if _demo == "support_hold": return  # for a capture: leave him standing where he struck
	var leaving := figure.create_tween()
	leaving.tween_property(figure,"scale",Vector3.ONE*.01,.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await leaving.finished
	figure.queue_free()
	UnitState.looks.erase(ghost.id)

func _epic_strike(actor: PixelUnit, target: UnitView, look: String) -> Tween:
	await actor.turn_to_strike(target.position)
	var axe:=look in ["idas","merc_captain"]
	var sweep:=look=="merc_captain"
	var planted:=look=="merc_lancer"
	var home:=actor.position
	var forward:=(target.position-home).slide(Vector3.UP).normalized()
	actor._sprite.material_override.set_shader_parameter("painted_action_sheet",actor.epic_attack_sheet)
	var strike:=actor.create_tween()
	var lateral:=Vector3(-forward.z,0,forward.x)*(.13 if sweep else 0.)
	var reach:=.16 if planted else .23 if sweep else .25 if axe else .40
	var drive_time:=.19 if sweep else .17 if planted else .15 if axe else .12
	var load_time:=.25 if sweep else .33 if planted else .38 if axe else .26
	strike.tween_method(actor.set_painted_action_frame,0.,16.,load_time)
	strike.parallel().tween_property(actor,"position",home-forward*(.035 if planted else .10)-lateral,load_time).set_trans(Tween.TRANS_SINE)
	strike.tween_interval(.03 if sweep else .09 if axe else .04)
	strike.tween_callback(Soundscape.cue.bind("swing" if axe else "step"))
	strike.tween_method(actor.set_painted_action_frame,16.,21.,drive_time)
	strike.parallel().tween_property(actor,"position",home+forward*reach+lateral,drive_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await strike.finished
	var settle:=actor.create_tween()
	settle.tween_method(actor.set_painted_action_frame,21.,26.,.20 if planted else .12)
	if not axe:settle.tween_callback(Soundscape.cue.bind("step"))
	settle.tween_method(actor.set_painted_action_frame,26.,55.,.46)
	settle.parallel().tween_property(actor,"position",home,.46).set_trans(Tween.TRANS_SINE)
	settle.tween_callback(actor.set_painted_action_frame.bind(-1.))
	return settle


func _centaur_strike(rider: PixelUnit, target: UnitView, defender: PixelUnit=null) -> Tween:
	await rider.turn_to_strike(target.position)
	var pose := rider.set_painted_action_frame if defender==null else rider.aim_covered_spear.bind(defender)
	var thrust := rider.create_tween()
	var home := rider.position
	var line := (target.position-home).slide(Vector3.UP).normalized()
	if defender!=null:
		# Let the original line of attack read before the defender crosses it.
		thrust.tween_method(pose,0.,8.,.24)
		thrust.parallel().tween_property(rider,"position",home-line*.42,.24).set_trans(Tween.TRANS_SINE)
		thrust.tween_callback(_cover_step.bind(defender,target,rider))
		thrust.tween_method(pose,8.,16.,.23)
	else:
		thrust.tween_method(pose,0.,16.,16./60.)
	thrust.tween_callback(Soundscape.cue.bind("swing"))
	thrust.tween_method(pose,16.,21.,5./60.)
	if defender!=null:
		thrust.parallel().tween_property(rider,"position",home-line*.26,5./60.)
	await thrust.finished
	var settle := rider.create_tween()
	settle.tween_method(pose,21.,26.,5./60.)
	settle.tween_callback(Soundscape.cue.bind("step"))
	settle.tween_method(pose,26.,55.,29./60.)
	if defender!=null:
		settle.parallel().tween_property(rider,"position",home,.32)
		settle.tween_callback(rider._sprite.material_override.set_shader_parameter.bind("parry_warp",Vector4.ZERO))
	settle.tween_callback(rider.set_painted_action_frame.bind(-1.))
	return settle


func _spear_strike(view: UnitView, target: UnitView) -> Tween:
	var home := view.position
	await view.turn_to_strike(target.position)
	var direction := (target.position-home) * Vector3(1,0,1)
	direction = direction.normalized()
	view.attack_key(0,.07)
	var strike := view.create_tween()
	strike.tween_property(view,"position",home-direction*0.14,.175).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	strike.parallel().tween_callback(view.attack_key.bind(1,.09)).set_delay(.075)
	strike.tween_callback(Soundscape.cue.bind("swing"))
	strike.tween_callback(view.attack_key.bind(2,.12))
	strike.tween_property(view,"position",home+direction*0.32,.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await strike.finished
	var recovery := view.create_tween()
	recovery.tween_callback(view.attack_key.bind(3,.12))
	recovery.tween_property(view,"position",home,.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	recovery.parallel().tween_callback(view.set_pose.bind(-1,.12)).set_delay(.13)
	return recovery


func _bandit_shot(archer: UnitView, target: UnitView) -> Tween:
	await archer.turn_to_strike(target.position)
	archer.set_pose(2,.23)
	Soundscape.cue("bow_draw")
	await get_tree().create_timer(.31).timeout
	var aim := _effect_origin(target)
	var grip := archer.bow_grip(1.)
	var arrow := BattleFX.nock(_units_root,ARROW)
	if (archer as PixelUnit).painted_look == "merc_archer":
		arrow.pixel_size = archer._sprite.pixel_size*.80
	arrow.align_to_grip(grip,aim)
	archer.set_pose(3,.05)
	Soundscape.cue("arrow")
	var release := archer.create_tween()
	release.tween_interval(.14)
	release.tween_callback(archer.set_pose.bind(-1,.29))
	release.tween_interval(.29)
	await arrow.fly_to(aim,clampf(grip.distance_to(aim)/13.,.14,.36)).finished
	return release


func _chiron_shot(archer: PixelUnit, target: UnitView) -> Tween:
	await archer.turn_to_strike(target.position)
	while archer.hit_phase < 1.:
		await get_tree().process_frame
	var draw := archer.create_tween()
	draw.tween_method(archer.set_painted_action_frame,0.,12.,.26)
	draw.tween_callback(Soundscape.cue.bind("bow_draw"))
	draw.tween_method(archer.set_painted_action_frame,12.,26.,.36)
	draw.tween_interval(.12)
	await draw.finished
	var grip := archer.bow_grip(1.)
	var finish := _effect_origin(target)
	var shaft := BattleFX.nock(_units_root,ARROW)
	shaft.pixel_size = archer._sprite.pixel_size*.55
	shaft.align_to_grip(grip,finish)
	archer.set_painted_action_frame(31.)
	Soundscape.cue("arrow")
	var recovery := archer.create_tween()
	recovery.tween_method(archer.set_painted_action_frame,31.,39.,.17)
	recovery.tween_method(archer.set_painted_action_frame,39.,51.,.32)
	recovery.tween_method(archer.set_painted_action_frame,51.,55.,.13)
	recovery.tween_callback(archer.set_painted_action_frame.bind(-1.))
	await shaft.fly_to(finish,clampf(grip.distance_to(finish)/14.,.12,.36)).finished
	return recovery


func _bow_shot(archer: PixelUnit, target: UnitView) -> Tween:
	var finish := _effect_origin(target)
	var strongman := archer.kind=="heracles"
	await archer.turn_to_strike(target.position)
	if strongman:
		archer.bow_draw=0.
		await get_tree().create_timer(.42).timeout
	else:
		await archer.raise_bow(target)
	archer.show_live_arrow()
	Soundscape.cue("bow_draw")
	var shaft := BattleFX.nock(_units_root,ARROW)
	var place_arrow := func(weight: float):
		archer.set_bow_tension(weight)
		var grip := archer.bow_grip(weight)
		if strongman:
			grip=archer.position+Vector3.UP*archer.sprite_height*.57+archer.position.direction_to(target.position)*.25
		shaft.align_to_grip(grip,finish)
	var draw := create_tween()
	draw.tween_method(place_arrow,0.,1.,.55 if strongman else .30).set_trans(Tween.TRANS_SINE)
	await draw.finished
	Soundscape.cue("arrow")
	var travel := clampf(shaft.global_position.distance_to(finish)/13.5,.13,.36)
	var flight := shaft.fly_to(finish,travel)
	var recovery := archer.create_tween()
	recovery.tween_method(archer.set_bow_tension,1.,0.,.40 if strongman else .26)
	recovery.tween_callback(archer.lower_bow)
	await flight.finished
	return recovery


func _bump(attacker_id: String, target_id: String, skill: String, evade_slash := false) -> Tween:
	var v: UnitView = unit_views[attacker_id]
	var t: UnitView = unit_views[target_id]
	await v.turn_to_strike(t.position)
	if state.unit(attacker_id).look()=="merc_sword" and skill in ["slash","heavy_cut","spear_breaker"]:
		var home := v.position
		var forward := (t.position-home).slide(Vector3.UP).normalized()
		var cut := v.create_tween()
		cut.tween_property(v,"position",home-forward*.045,.09)
		if evade_slash:
			cut.parallel().tween_callback((t as PixelUnit).begin_evade.bind(v))
		cut.tween_callback(v.set_pose.bind(2,.095))
		cut.tween_callback(Soundscape.cue.bind("swing"))
		cut.tween_property(v,"position",home+forward*.29,.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await cut.finished
		BattleFX.spawn(_units_root,SLASH,_effect_origin(t),.13)
		var recovery := v.create_tween()
		recovery.tween_interval(.055)
		recovery.tween_callback(v.set_pose.bind(-1,.19))
		recovery.tween_property(v,"position",home,.21).set_trans(Tween.TRANS_SINE)
		return recovery
	if skill=="slash" and state.unit(attacker_id).def_id in ["bandit","bandit_chief"]:
		return await _raider_slash(v,t,state.unit(attacker_id).def_id=="bandit_chief",evade_slash)
	if skill=="shield_bash":
		(v as PixelUnit).bash_clock=0.
	if skill == "bite" and state.unit(attacker_id).def_id == "lion":
		var home := v.position
		var forward := (t.position-home).slide(Vector3.UP).normalized()
		v.set_pose(3,.17)
		var bite := v.create_tween()
		bite.tween_interval(.18)
		bite.tween_callback(v.set_pose.bind(2,.13))
		bite.tween_property(v,"position",home+forward*.33,.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await bite.finished
		var settle := v.create_tween()
		settle.tween_callback(v.set_pose.bind(4,.14))
		settle.tween_interval(.09)
		settle.tween_property(v,"position",home,.21).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		settle.parallel().tween_callback(v.set_pose.bind(-1,.20)).set_delay(.05)
		settle.tween_interval(.05)
		return settle
	if skill in ["club","gore","bite"]:
		return await _painted_melee(v,t,skill)
	v.play_attack()
	var home := v.position
	var toward := (t.position - home)
	toward.y = 0
	var tw := create_tween()
	if skill == "shield_bash":
		tw.tween_property(v,"position",home-toward.normalized()*.09,.10)
		tw.tween_property(v,"position",home+toward.normalized()*.34,.085).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		tw.tween_property(v,"position",home+toward.normalized()*.25,.22)
	await tw.finished
	var recovery := v.create_tween()
	recovery.tween_property(v, "position", home, 0.22)
	if skill != "shield_bash":
		BattleFX.spawn(_units_root, SLASH, _effect_origin(t), 0.22)
	return recovery


func _raider_slash(attacker: UnitView, target: UnitView, heavy: bool, evade_slash: bool) -> Tween:
	var home := attacker.position
	var forward := (target.position-home).slide(Vector3.UP).normalized()
	var raise_time := .32 if heavy else .14
	attacker.set_pose(2,raise_time)
	var swing := attacker.create_tween()
	swing.tween_property(attacker,"position",home-forward*(.14 if heavy else .045),raise_time).set_trans(Tween.TRANS_SINE)
	if evade_slash:
		swing.parallel().tween_callback((target as PixelUnit).begin_evade.bind(attacker)).set_delay(raise_time-.14)
	if heavy:
		swing.tween_interval(.10)
	swing.tween_callback(Soundscape.cue.bind("swing"))
	swing.tween_callback(attacker.set_pose.bind(-1,.17 if heavy else .12))
	swing.tween_property(attacker,"position",home+forward*(.38 if heavy else .21),.13 if heavy else .095).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await swing.finished
	BattleFX.spawn(_units_root,SLASH,_effect_origin(target),.20 if heavy else .13)
	var settle := attacker.create_tween()
	settle.tween_interval(.15 if heavy else .025)
	settle.tween_property(attacker,"position",home,.32 if heavy else .16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return settle


func _painted_melee(view: UnitView,target: UnitView,skill: String) -> Tween:
	var home := view.position
	var forward := (target.position-home).slide(Vector3.UP).normalized()
	var wolf := skill=="bite"
	var club := skill=="club"
	var reach := clampf((target.position-home).slide(Vector3.UP).length()-(.95 if skill=="gore" else .65),.23,.70)
	var impact := view.create_tween()
	if wolf: view.attack_key(0)
	else: view.set_pose(1,.12)
	impact.tween_property(view,"position",home-forward*(.08 if wolf else .14),.12 if wolf else .26).set_trans(Tween.TRANS_SINE)
	if wolf: impact.tween_callback(view.attack_key.bind(1,.06))
	impact.tween_callback(Soundscape.cue.bind("swing"))
	if wolf: impact.tween_callback(view.attack_key.bind(2,.09))
	else: impact.tween_callback(view.set_pose.bind(2,.10))
	impact.tween_property(view,"position",home+forward*(.35 if club else reach),.10 if wolf else .16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await impact.finished
	var recover := view.create_tween()
	if wolf: recover.tween_callback(view.attack_key.bind(3,.12))
	recover.tween_property(view,"position",home,.20 if wolf else .34).set_trans(Tween.TRANS_SINE)
	recover.tween_callback(view.set_pose.bind(-1,.14))
	return recover


func _popup(id: String, text: String, col: Color, attacker: UnitView = null) -> void:
	var v: UnitView = unit_views[id]
	var origin := v.position+Vector3.UP*(v.sprite_height+.35)
	if attacker != null:
		var right := cam_rig.camera.global_basis.x
		var side := 1.0 if (v.position-attacker.position).dot(right)>=0.0 else -1.0
		origin += right*side*.42
	hud.overlay.add_popup(origin,text,col)


func _sync_views() -> void:
	_sync_cymbals()
	if village != null and fire_round != state.round_number:
		map_view.grid = state.grid
		if tactical:
			map_view.build(state.grid)
		village.sync_fire(state.grid)
		fire_round = state.round_number
	for id in state.order:
		var u: UnitState = state.units[id]
		var v: UnitView = unit_views[id]
		if u.alive:
			v.position = map_view.anchor_world(state, u.pos, u.size)
			v.visible = not u.hidden
		v.set_facing(u.facing)
		var painted := v as PixelUnit
		painted.guarding=u.has_status("guard")
		if u.def_id=="lion" and not painted.falling:
			painted.set_lion_exposed(u.alive and not u.hidden and u.has_status("stunned") and u.has_status("staggered"))
	for id in boulder_views:
		var b: Dictionary = state.cave.boulders[id]
		_place_boulder(id,1.0 if b.placed else (.10 if b.progress > 0 else 0.0))

	if not boulder_views.is_empty():
		for view: UnitView in unit_views.values():
			var nearest := Vector2.ZERO
			for rock: Node3D in boulder_views.values():
				var offset := Vector2(rock.position.x-view.position.x,rock.position.z-view.position.z)
				if offset.length() <= 1.22*map_view.scale.x and (nearest == Vector2.ZERO or offset.length_squared() < nearest.length_squared()):
					nearest = offset
			view.set_nearby_stone(nearest)
	# A hydra's neck is taller than anything else on the field and stands against the raised
	# ground in the middle of the marsh. A camera-facing sprite leans back into that ground,
	# so its upper part is tested as if it stood upright, as beside a boulder.
	for id in state.order:
		var neck: UnitState = state.units[id]
		if neck.def_id != "hydra_head" or not neck.alive: continue
		var here := map_view.anchor_world(state,neck.pos,1)
		var lean := Vector2.ZERO
		for step: Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			var next := neck.pos+step
			if state.grid.in_bounds(next) and state.grid.height_at(next) > state.grid.height_at(neck.pos):
				var there := map_view.anchor_world(state,next,1)
				lean += Vector2(there.x-here.x,there.z-here.z)
		unit_views[id].set_nearby_stone(lean)


# Rotate about the rolling axis and rest the lowest actual facet on the ground.
func _place_boulder(id: String, travel: float) -> void:
	var data: Dictionary = state.cave.boulders[id]
	var cell: Vector2i = data.pos
	var start := map_view.to_global(Vector3(cell.x+.5,map_view.cell_top(cell),cell.y+.5))
	var finish := _plug_position(state.cave.entrances[data.seals].anchor)
	var path := (finish-start).slide(Vector3.UP)
	var rock: Node3D = boulder_views[id]
	var rolling := Basis(Vector3.UP.cross(path).normalized(),path.length()*travel/.69).scaled(Vector3.ONE*2.12)
	var bottom := INF
	for vertex in boulder_vertices:
		bottom = minf(bottom,(rolling*vertex).y)
	var at := start.lerp(finish,travel)
	if map_view.field != null and not tactical:
		var ground := map_view.to_local(at)
		at.y = map_view.field.elevation(ground.x,ground.z)
	at.y -= bottom*.90
	rock.transform = Transform3D(rolling,at)


func _push_boulder(unit_id: String, id: String, progress: int) -> void:
	var actor: UnitView = unit_views[unit_id]
	var rock: Node3D = boulder_views[id]
	var home := actor.position
	var direction := (rock.position-home).slide(Vector3.UP).normalized()
	# The first of two ordinary pushes leaves the boulder slightly dislodged.
	var data: Dictionary = state.cave.boulders[id]
	var cell: Vector2i = data.pos
	var center := map_view.anchor_world(state,cell,1)
	var start := Vector2(center.x,center.z)
	var end := _plug_position(state.cave.entrances[data.seals].anchor)
	var path := Vector2(end.x,end.z)-start
	var initial := clampf((Vector2(rock.position.x,rock.position.z)-start).dot(path)/path.length_squared(),0.,1.)
	var released := initial + (.20 if progress >= 2 else .10)
	await actor.turn_to_strike(rock.position)
	var contact := home + direction*(.18 + map_view.scale.x-1.)
	var follow := contact + direction*.09
	var shove := actor.create_tween()
	shove.tween_method(func(w: float): actor.brace_against(direction,w),0.,.62,.30).set_trans(Tween.TRANS_SINE)
	shove.parallel().tween_property(actor,"position",contact,.30).set_trans(Tween.TRANS_SINE)
	shove.tween_method(func(w: float): actor.brace_against(direction,w),.62,1.,.23).set_trans(Tween.TRANS_SINE)
	shove.tween_callback(Soundscape.cue.bind("step"))
	shove.tween_callback(BattleFX.spawn.bind(_units_root,DUST,rock.position+Vector3.UP*.1,.26))
	await shove.finished
	var drive := actor.create_tween()
	drive.tween_method(func(t: float): _place_boulder(id,lerpf(initial,released,t)),0.,1.,.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drive.parallel().tween_property(actor,"position",follow,.32).set_trans(Tween.TRANS_SINE)
	await drive.finished
	var release := actor.create_tween().set_parallel()
	release.tween_method(func(w: float): actor.brace_against(direction,w),1.,0.,.42).set_trans(Tween.TRANS_SINE)
	release.tween_property(actor,"position",home,.48).set_trans(Tween.TRANS_SINE)
	if progress >= 2:
		release.tween_method(func(t: float): _place_boulder(id,lerpf(released,1.,t)),0.,1.,.78).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_popup(unit_id,"推巨石 1/2",Color.WHEAT)
	await release.finished


func _plug_position(anchor: Vector2i) -> Vector3:
	return map_view.to_global(Vector3(anchor.x + 1, map_view.cell_top(anchor) + 0.04, anchor.y + .54))


# --- Turn flow -------------------------------------------------------------------

## What the camp reports when the party walks back in: how the battle went, what it paid,
## and whether the party went up a level. Compared against the save from before the battle.
func _news(after: Dictionary, summary: String) -> Dictionary:
	var before: Dictionary = Checkpoint.read_entry()
	var won: bool = _outcomes.get(_battle_id,"")=="已通关"
	var news := {"battle":_battle_id,"won":won,"result":summary}
	var earned: int = int(_purse.get("coins",0))-int(before.get("purse",{}).get("coins",_purse.get("coins",0)))
	if earned > 0: news.coins = earned
	if won and before.get("outcomes",{}).get(_battle_id,"")!="已通关": news.xp = Checkpoint.xp_for(_battle_id)
	if won:
		# What the beaten leave behind goes into the bag (both the one being saved and ours).
		# Most of it fell as each enemy did; anyone not yet counted is counted now.
		# Those on the field and not beaten, where the battle was won another way, are paid
		# for at half: reaching the far bank should not earn less than staying to kill.
		var standing := []
		for id: String in state.order:
			var foe := state.unit(id)
			if foe == null or foe.team != Defs.Team.ENEMY: continue
			if not foe.alive: _drop_spoils(id,false)
			elif not foe.hidden: standing.append(foe.def_id)
		var dice := RandomNumberGenerator.new()
		dice.randomize()
		var spared := Checkpoint.left_standing(standing,dice) if _campaign else 0
		if spared > 0:
			news.coins = int(news.get("coins",0))+spared
			news.spared = standing.size()
		var haul := _haul
		for purse: Dictionary in [_purse,after.get("purse",{})]:
			Checkpoint.settle_purse(purse)
			purse.coins = int(purse.get("coins",0))+spared
			for thing: String in haul: purse.bag[thing] = int(purse.bag.get(thing,0))+int(haul[thing])
		if not haul.is_empty(): news.loot = haul
	# Who marched, and who was down when it ended. The camp shares out the experience.
	var fielded := []
	var fallen := []
	for id: String in ["hero","atalanta"]+_deploy:
		var fighter := state.unit(id)
		if fighter == null or fielded.has(id): continue
		fielded.append(id)
		if not fighter.alive: fallen.append(id)
	news.fielded = fielded
	news.fallen = fallen
	return news

func _settle_at_camp(destination: String, summary: String, fork := false):
	# A side battle is not a place the journey rests at: back to where it stood.
	if destination == "2-S": destination = _resume if _resume != "" else "2-2"
	_camp_stop=_entry(destination)
	_camp_stop.stage="camp"
	_camp_stop.choose_route=fork
	_camp_stop.news=_news(_camp_stop,summary)
	_camp_stop.camp_summary=summary  # the drillmaster reads this to know how the last battle went
	_camp_stop.erase("orders")
	if _battle_id=="2-1" and state.escort_result=="win":
		_camp_stop.divinity=state.reward.divinity
	if _battle_id=="2-5" and _outcomes.get("2-5","")=="已通关" and not _camp_stop.get("relics",[]).has("hydra_blood") and not _camp_stop.get("spared",[]).has(2):
		# The hydra is down: the camp asks what becomes of it.
		_camp_stop.verdict=2
	_next_battle="camp"
	_mode=Mode.OVER
	var saved:=Checkpoint.write_entry(_camp_stop)==OK
	hud.banner(summary+"　·　返回营地" if saved else "保存失败，请点击返回营地重试",0.)
	_refresh()

func _end_turn() -> void:
	hud.close_journal()
	if _next_battle=="camp":
		if Checkpoint.write_entry(_camp_stop)!=OK:
			hud.banner("保存失败，请重试。",0.)
			return
		get_tree().change_scene_to_file("res://camp.tscn")
		return
	if _next_battle=="corinth_map":
		var next:=_finish_escort()
		if _campaign and Checkpoint.write_entry(next)!=OK:
			hud.banner("护送结果保存失败，请重试。",0.)
			return
		next.campaign = _campaign
		get_tree().set_meta("camp_entry",next)
		get_tree().change_scene_to_file("res://camp.tscn")
		return
	if _next_battle == "reward":
		_open_chapter_reward()
		_refresh()
		return
	if not _next_battle.is_empty():
		var destination := _next_battle
		_next_battle = ""
		_load_battle(destination)
		return
	if _mode == Mode.BUSY or _mode == Mode.OVER or state.phase != Defs.Phase.PLAYER:
		return
	_select("")
	_set_mode(Mode.BUSY)
	await _advance_phase()
	if _battle_id == "1-3" and _check_end():
		return
	hud.announce_phase(state.round_number, state.phase == Defs.Phase.PLAYER)
	_refresh()
	await get_tree().create_timer(0.5).timeout
	for e in state.living(Defs.Team.ENEMY):
		while e.alive and not e.has_acted:
			_active_enemy = e.id
			hud.set_enemy_order(state,_active_enemy,false)
			if not e.hidden:
				_reveal_unit(e.id)
			var p := EnemyAI.plan(state, e)
			if p.has("move_to"):
				await _play(Rules.perform(state, {"type": "move", "unit": e.id, "to": p["move_to"]})["events"])
			var o := Rules.perform(state, p["action"])
			if not o["ok"]:
				o = Rules.perform(state, {"type": "wait", "unit": e.id})
			await _play(o["events"])
			if _check_end():
				return
			if not Rules.finish_activation(state, e):
				break
		_active_enemy = ""
		hud.set_enemy_order(state,"",false)
		await get_tree().create_timer(0.12).timeout
	await _advance_phase()
	if _check_end():
		return
	hud.announce_phase(state.round_number, state.phase == Defs.Phase.PLAYER)
	_set_mode(Mode.IDLE)
	_take_next()
	if _battle_id=="2-1": _save_checkpoint(_battle_id)

## A flame on every cell of forest that is alight, and what grew there taken away.
var _flames := {}
var _flame_paint: ShaderMaterial

func _sync_fires() -> void:
	var alight := {}
	for fire: Array in state.fires:
		alight[Vector2i(int(fire[0]),int(fire[1]))] = true
	for cell: Vector2i in _flames.keys():
		if not alight.has(cell):
			_flames[cell].queue_free()
			_flames.erase(cell)
			# Burnt out: a charred stump smoulders there for the rest of the fight.
			var embers := BattleFX._sprite(_units_root,CHARRED)
			embers.pixel_size = .016
			embers.offset.y = CHARRED.get_height()*.5-8
			embers.global_position = map_view.to_global(Vector3(cell.x+.5,map_view.cell_top(cell),cell.y+.5))
			embers.create_tween().set_loops().tween_property(embers,"frame",embers.hframes-1,1.0).from(0)
	for cell: Vector2i in alight:
		if _flames.has(cell): continue
		if _flame_paint == null:
			_flame_paint = ShaderMaterial.new()
			_flame_paint.shader = preload("res://view/pixel_flame.gdshader")
			_flame_paint.set_shader_parameter("atlas",BRUSHFIRE)
			_flame_paint.set_shader_parameter("frames",8.0)
			_flame_paint.set_shader_parameter("fps",10.0)
		var flame := MeshInstance3D.new()
		var card := QuadMesh.new()
		card.size = Vector2.ONE*1.7
		flame.mesh = card
		flame.material_override = _flame_paint
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_units_root.add_child(flame)
		flame.global_position = map_view.to_global(Vector3(cell.x+.5,map_view.cell_top(cell),cell.y+.5))+Vector3.UP*.7
		_flames[cell] = flame
		if map_view.field != null and map_view.field.has_method("scorch"): map_view.field.scorch(cell)

## What is left where a hydra's head has fallen: a raw stump while it can grow back, a
## burnt one once it is sealed. Gone again when a new head stands there.
const STUMP := preload("res://art/pixel/hydra_head/stump.png")
var _stumps := {}

func _sync_stumps() -> void:
	var down := {}
	for id: String in state.order:
		var neck := state.unit(id)
		if neck.def_id == "hydra_head" and not neck.alive: down[id] = neck
	for id: String in _stumps.keys():
		if not down.has(id):
			_stumps[id].queue_free()
			_stumps.erase(id)
	for id: String in down:
		var neck: UnitState = down[id]
		if not _stumps.has(id):
			var stump := Sprite3D.new()
			stump.texture = STUMP
			stump.hframes = 2
			stump.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			stump.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			stump.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			stump.pixel_size = .018
			stump.offset.y = STUMP.get_height()*.5
			_units_root.add_child(stump)
			stump.position = map_view.anchor_world(state,neck.pos,1)
			_stumps[id] = stump
		(_stumps[id] as Sprite3D).frame = 1 if neck.sealed else 0

func _finish_escort() -> Dictionary:
	var next:=_entry("2-1")
	next.stage="done"
	next.divinity=state.reward.divinity
	next.erase("orders")
	return next

func _open_chapter_reward() -> void:
	var entry := Checkpoint.chapter_reward(_entry("1-5"))
	entry.news = _news(entry,"涅墨亚狮子已败")
	if _campaign and Checkpoint.write_entry(entry) != OK:
		hud.banner("章末进度保存失败，点击「领取狮皮」重试。",0.)
		_next_battle = "reward"
		return
	entry.campaign = _campaign
	get_tree().set_meta("camp_entry",entry)
	get_tree().change_scene_to_file.call_deferred("res://camp.tscn")

func _check_end() -> bool:
	if _next_battle=="camp" and _mode==Mode.OVER:return true
	var hero := state.unit("hero")
	if hero == null or not hero.alive or state.living(Defs.Team.PLAYER).is_empty():
		Soundscape.score("")
		Soundscape.cue("defeat")
		if _campaign:
			_settle_at_camp(_battle_id,"战斗失利，可整备后重试")
			return true
		hud.banner("战斗失败　按 R 重开", 0.0)
		_mode = Mode.OVER
		_refresh()
		return true
	if _battle_id=="1-3" and not state.unit("wounded_chiron").alive:
		_mode = Mode.OVER
		_chiron_joined = false
		_outcomes[_battle_id]="喀戎负伤离开"
		Soundscape.score("")
		if _campaign:
			_settle_at_camp("1-4","喀戎负伤离开")
			return true
		hud.show_feast_result(false,_load_battle)
		_save_checkpoint("1-4")
		_refresh()
		return true
	if _battle_id=="2-S":
		# The wounded centaur brought to the spring: he joins. If he falls, try again.
		if state.escort_result=="": return false
		_mode=Mode.OVER
		var reached := state.escort_result=="win"
		Soundscape.score("")
		Soundscape.cue("victory" if reached else "defeat")
		if reached:
			_outcomes["2-S"]="已通关"
			_chiron_joined=true
		if _campaign:
			if reached: Checkpoint.award(_purse,_battle_id)
			_settle_at_camp(_battle_id,"喀戎到了泉边，伤口洗净，加入队伍" if reached else "喀戎倒在了半路，可整备后重试")
			return true
		hud.banner("喀戎到了泉边　按 R 重开" if reached else "喀戎倒下了　按 R 重试",0.)
		_refresh()
		return true
	if not state.escort_exits.is_empty():
		if state.escort_result=="":return false
		_mode=Mode.OVER
		if state.escort_result=="win":
			_outcomes["2-1"]="已通关"
			if _campaign:
				Checkpoint.award(_purse,_battle_id)
				Soundscape.cue("victory")
				_settle_at_camp("2-2","护送成功，美狄亚已随队撤离")
				return true
			_next_battle="corinth_map"
			var saved:=not _campaign or Checkpoint.write_entry(_finish_escort())==OK
			hud.banner("护送成功　美狄亚已随队撤离" if saved else "保存失败，点击返回行军图重试",0.)
			Soundscape.cue("victory")
		else:
			if _campaign:
				_settle_at_camp("2-1","护送失败，可整备后重试")
				return true
			hud.banner("美狄亚倒下了　按 R 重试",0.)
			Soundscape.cue("defeat")
		_refresh()
		return true
	if not state.reach_exits.is_empty() and state.reach_result=="win":
		# Across the reeds. Nobody left standing in swamp at a round's end is the goal aside.
		var dry := state.swamp_rests == 0
		Soundscape.score("")
		Soundscape.cue("victory")
		_outcomes[_battle_id]="已通关"
		var summary := "已抵达对岸" if state.living(Defs.Team.ENEMY).size() > 0 else "芦苇荡已肃清"
		summary += "，没有人在沼泽里过夜（酬金 +%d）" % (Checkpoint.pay_for(_battle_id,true)-Checkpoint.pay_for(_battle_id)) if dry else "，有人在沼泽里过了夜"
		if _campaign:
			Checkpoint.award(_purse,_battle_id,dry)
			_settle_at_camp("2-3",summary)
			return true
		hud.banner(summary+"　按 R 重开",0.0)
		_mode = Mode.OVER
		_refresh()
		return true
	if _battle_id=="3-1" and state.living(Defs.Team.ENEMY).is_empty():
		# The lake shore. Three birds brought down with the cymbal is the goal aside.
		var rung := state.felled >= 3
		Soundscape.score("")
		Soundscape.cue("victory")
		_outcomes[_battle_id]="已通关"
		var summary := "湖岸已肃清"
		summary += "，铜钹敲下了 %d 只鸟（酬金 +%d）" % [state.felled,Checkpoint.pay_for(_battle_id,true)-Checkpoint.pay_for(_battle_id)] if rung else "，铜钹只敲下了 %d 只鸟" % state.felled
		if _campaign:
			Checkpoint.award(_purse,_battle_id,rung)
			_settle_at_camp("3-1",summary)
			return true
		hud.banner(summary+"　按 R 重开",0.0)
		_mode = Mode.OVER
		_refresh()
		return true
	if _battle_id=="2-5" and state.outcome=="win":
		# The hydra: every neck sealed. No head grown back more than once is the goal aside.
		var clean := state.most_regrown <= 1
		Soundscape.score("")
		Soundscape.cue("victory")
		_outcomes[_battle_id]="已通关"
		var summary := "许德拉的头全部封住了"
		summary += "，没有一个头再生超过一次（酬金 +%d）" % (Checkpoint.pay_for(_battle_id,true)-Checkpoint.pay_for(_battle_id)) if clean else "，有的头长回来了 %d 次" % state.most_regrown
		if _campaign:
			Checkpoint.award(_purse,_battle_id,clean)
			_settle_at_camp(_battle_id,summary)
			return true
		hud.banner(summary+"　按 R 重开",0.0)
		_mode = Mode.OVER
		_refresh()
		return true
	if not state.targets.is_empty() and state.target_result=="win":
		# The altar. Two of the three caught by fire on the ground is the goal aside.
		var burnt := state.targets_scorched >= 2
		Soundscape.score("")
		Soundscape.cue("victory")
		_outcomes[_battle_id]="已通关"
		var summary := "三名女祭司已倒下"
		summary += "，其中 %d 人被林火烧到（酬金 +%d）" % [state.targets_scorched,Checkpoint.pay_for(_battle_id,true)-Checkpoint.pay_for(_battle_id)] if burnt else "，林火烧到的不足两人"
		if _campaign:
			Checkpoint.award(_purse,_battle_id,burnt)
			_settle_at_camp("2-5",summary)
			return true
		hud.banner(summary+"　按 R 重开",0.0)
		_mode = Mode.OVER
		_refresh()
		return true
	if _battle_id=="2-3" and state.living(Defs.Team.ENEMY).is_empty():
		# The crab beach. One of them pushed under is the goal aside.
		var sunk := state.drowned > 0
		Soundscape.score("")
		Soundscape.cue("victory")
		_outcomes[_battle_id]="已通关"
		var summary := "巨蟹滩已肃清"
		summary += "，%d 个敌人被推进了深水（酬金 +%d）" % [state.drowned,Checkpoint.pay_for(_battle_id,true)-Checkpoint.pay_for(_battle_id)] if sunk else "，没有敌人被推进深水"
		if _campaign:
			Checkpoint.award(_purse,_battle_id,sunk)
			_settle_at_camp("2-4",summary)
			return true
		hud.banner(summary+"　按 R 重开",0.0)
		_mode = Mode.OVER
		_refresh()
		return true
	if state.village_result == "win" or state.rescue_result == "win" or (village == null and not map_view.woodland and _battle_id != "2-5" and state.living(Defs.Team.ENEMY).is_empty()):
		Soundscape.score("")
		Soundscape.cue("victory")
		_outcomes[_battle_id]="已通关"
		if _campaign: Checkpoint.award(_purse,_battle_id)
		if map_view.woodland:
			_rescued.clear()
			for id in state.order:
				var traveler := state.unit(id)
				if traveler.def_id == "refugee" and traveler.hidden and traveler.alive:
					_rescued.append(id)
			if _campaign:
				_settle_at_camp("1-4","林道已肃清，%d 名村民获救"%_rescued.size(),_rescued.size()>=2)
				return true
			hud.show_rescue_result(state,_load_battle.bind("1-2"),_load_battle,_campaign)
			_save_checkpoint("1-4",_rescued.size() >= 2)
		elif _battle_id=="1-3":
			_chiron_joined = true
			if _campaign:
				_settle_at_camp("1-4","酒宴结束，喀戎加入队伍")
				return true
			hud.show_feast_result(true,_load_battle)
			_save_checkpoint("1-4")
		elif _battle_id == "1-5":
			_open_chapter_reward()
		elif _battle_id in ["1-1","1-4"]:
			_next_battle = "1-2" if _battle_id=="1-1" else "1-5"
			if _campaign:
				_settle_at_camp(_next_battle,"村口已安全" if _battle_id=="1-1" else "山谷已肃清")
				return true
			hud.banner("村口已安全　前往林间山道" if _battle_id=="1-1" else "山谷已肃清　前往双口洞穴",0.0)
			_save_checkpoint(_next_battle)
		else:
			hud.banner("胜利！　按 R 重开",0.0)
		_mode = Mode.OVER
		_refresh()
		return true
	return false


# --- Presentation refresh --------------------------------------------------------

func _refresh() -> void:
	if state == null:
		return
	var phase_text := "我方回合" if state.phase == Defs.Phase.PLAYER else "敌方回合"
	var heading := "第 %d 回合 · %s" % [state.round_number, phase_text]
	var objective := ""
	if village != null:
		objective = "两人抵达北门，或歼灭三批狼群"
		if state.round_number < 3:
			objective += "\n阿塔兰忒将在第 3 回合从北面山脊支援"
	if map_view.woodland:
		# Saving two of the three travellers is the goal aside: it opens the side road to
		# the feast. The battle is won by clearing the road either way, and says so.
		var fallen := 0
		for id in state.order:
			var traveler := state.unit(id)
			if traveler.def_id == "refugee" and not traveler.alive: fallen += 1
		heading += "　·　村民已撤离 %d/3" % rescued_count
		if fallen > 0: heading += "，倒下 %d" % fallen
		var aside := "可选：救出至少两名村民，打开上山赴宴的路（已救 %d 人）。" % rescued_count
		if rescued_count >= 2: aside = "可选目标已达成：两名村民获救，上山赴宴的路打开了。"
		elif fallen >= 2: aside = "可选目标已错过：倒下的村民太多，上山赴宴的路不会打开。战斗继续。"
		objective = "歼灭所有敌人即可过关。%s\n指向村民可查看撤离路线和威胁。第 4 回合南北夹击，第 6 回合头目从东侧入场。" % aside
		if fallen >= 2 and rescued_count < 2 and not _side_road_lost:
			_side_road_lost = true
			hud.banner("两名村民倒下了，上山赴宴的路已经错过　·　战斗继续，歼灭敌人即可过关",4.5)
	if _battle_id=="2-1":
		objective="美狄亚已入队。护送她抵达东门的青绿色出口；主角和美狄亚必须存活。"
	if _battle_id=="2-S":
		objective="护送喀戎抵达东边泉眼的青绿色格子；主角和喀戎必须存活。敌人不必清完。"
	if _battle_id=="2-5":
		var stumps := []
		var soonest := 9
		for id in state.order:
			var neck := state.unit(id)
			if neck.def_id == "hydra_head" and not neck.alive and not neck.sealed and neck.regrow > 0:
				stumps.append(neck.pos)
				soonest = mini(soonest,neck.regrow)
		var standing := 0
		var sealed := 0
		for id in state.order:
			var neck := state.unit(id)
			if neck.def_id != "hydra_head": continue
			if neck.alive: standing += 1
			elif neck.sealed: sealed += 1
		heading += "　·　头 %d　封住 %d/5" % [standing,sealed]
		if not stumps.is_empty(): heading += "　断颈 %d（%d 回合后再生）" % [stumps.size(),soonest]
		objective="把五个头全部封住。头不会移动，也推不动。砍下的头留下断颈（红框），两回合后长回一个满血的头；这期间用带火的招式（巫火、火油罐）打中断颈，或者让头带着灼烧倒下，就永远封住。\n可选：没有一个头再生超过一次（目前最多 %d 次）。" % state.most_regrown
	if not state.targets.is_empty():
		heading += "　·　女祭司 %d/%d" % [state.targets_left,state.targets.size()]
		objective="击倒三名女祭司即可过关，其余敌人不必清完。女祭司每回合会治疗一个同伴。带火的招式（巫火、火油罐）打中林地里的人或直接打一格林地，那一格就起火；火每回合向相邻的林地蔓延一格，橙色框是下一回合会烧到的地方，烧两回合后成为焦土。火不分敌我。\n可选：让地上的火烧到至少两名女祭司（已烧到 %d 人）。" % state.targets_scorched
	if _battle_id=="3-1":
		var aloft := 0
		for id in state.order:
			var bird := state.unit(id)
			if bird.alive and not bird.hidden and bird.team == Defs.Team.ENEMY and bird.has_trait("flying") and not bird.has_status("grounded"): aloft += 1
		heading += "　·　天上 %d 只" % aloft
		objective="歼灭所有铜羽鸟。鸟在天上时近战够不着，只有射击和神力打得到；它们的铜羽不看防御。站到铜钹旁（或站在它上面）敲响，3 格内的鸟落地到这一回合结束，这期间谁都打得到。铜钹敲过后要歇 2 回合。\n可选：用铜钹让 3 只鸟落地（现在 %d 只）。" % state.felled
	if _battle_id=="2-3":
		objective="歼灭所有敌人。巨蟹正面受到的伤害减半，钳住的人下一回合不能移动；深蓝色是深水，被推进去的敌人直接出局。\n可选：把至少一个敌人推进深水（%s）。" % ("已做到，%d 个" % state.drowned if state.drowned > 0 else "还没有")
	if not state.reach_exits.is_empty():
		objective="所有人抵达对岸的青绿色区域，或肃清沼蛇。沼泽移动消耗 3，回合结束时还站在沼泽里会中毒。\n可选：没有人在沼泽里结束回合（%s）。" % ("目前做到了" if state.swamp_rests == 0 else "已有 %d 人次" % state.swamp_rests)
	hud.overlay.charge_lanes.clear()
	if _battle_id=="1-3":
		objective = "护住负伤的喀戎，击退五名半人马。喀戎会在我方回合结束时放箭。"
		if state.phase==Defs.Phase.PLAYER and _mode==Mode.IDLE:
			for rider in state.living(Defs.Team.ENEMY):
				var sim := EnemyAI.simulate(state,rider)
				var path: Array = [rider.pos]
				for event in sim.events:
					if event.type=="move": path.append_array(event.path)
					if event.type=="attack" and event.notes.has("charge"):
						path.append(state.unit(event.target).pos)
						hud.overlay.charge_lanes.append(path)
	hud.set_enemy_order(state,_active_enemy,_mode == Mode.OVER)
	hud.set_mission(_mission_name,heading,objective)
	hud.set_view_options(_show_threat,tactical)
	_available_units.clear()
	var movers := 0
	for ally in state.living(Defs.Team.PLAYER):
		if ally.id == "wounded_chiron" or ally.def_id == "refugee" or ally.hidden or (ally.has_acted and ally.post_move <= 0):
			continue
		_available_units.append(ally.id)
		if ally.has_acted:
			movers += 1
	hud.set_available_units(_available_units.size()-movers,movers,state.phase == Defs.Phase.PLAYER and _mode not in [Mode.BUSY,Mode.OVER])
	hud.menu_button.disabled = _mode == Mode.BUSY
	hud.set_turn_command(not _next_battle.is_empty() or (_mode != Mode.BUSY and _mode != Mode.OVER and state.phase == Defs.Phase.PLAYER),_next_battle)

	highlights.clear_all()
	if not state.escort_exits.is_empty(): highlights.show_frame("east_gate",state.escort_exits,Color("#48ddbb"),8)
	if not state.reach_exits.is_empty(): highlights.show_frame("far_bank",state.reach_exits,Color("#48ddbb"),8)
	if not state.fire_next.is_empty(): highlights.show_frame("fire_next",state.fire_next,Color("#ff9440"),8)
	var necks: Array[Vector2i] = []
	for id in state.order:
		var neck := state.unit(id)
		if not neck.alive and not neck.sealed and neck.regrow > 0: necks.append(neck.pos)
	if not necks.is_empty(): highlights.show_frame("stumps",necks,Color("#e0453a"),9)
	_sync_fires()
	_sync_stumps()
	if map_view.woodland:
		highlights.show_frame("rescue_gate",state.rescue_exits,Color("#64bcad"),8)
	if village != null:
		highlights.show_frame("gate",state.village_exits,Color("#6bbaac"),8)
	if _show_threat:
		var cells := {}
		for e in state.living(Defs.Team.ENEMY):
			if e.hidden:
				continue
			for c in EnemyAI.threat_cells(state, e):
				cells[c] = true
		highlights.show_threat("threat",cells.keys())

	if not state.cave.is_empty():
		var boss := state.unit(state.cave["boss"])
		var next_exit := EnemyAI.cave_entrance(state,boss) if boss != null and boss.alive and boss.hidden else ""
		for id in state.cave["entrances"]:
			cave_mouths[id].set_warning(id == next_exit)
			var ent: Dictionary = state.cave["entrances"][id]
			var cells: Array = [ent["anchor"], ent["anchor"] + Vector2i(1, 0), ent["anchor"] + Vector2i(0, 1), ent["anchor"] + Vector2i(1, 1)]
			if ent["sealed"]:
				highlights.show_cells("lair_" + id, cells, Color(0.45, 0.45, 0.5), 0, 1)
			elif next_exit == id:
				highlights.show_frame("lair_" + id, cells, Color(1.0, 0.3, 0.2), 14)  # intent: it comes out here
			elif tactical:
				highlights.show_frame("lair_" + id, cells, Color(0.95, 0.75, 0.3), 9)

	var u := state.unit(_selected) if _selected != "" else null
	if u != null and not u.alive:
		_selected = ""
		u = null
	_actions = []
	_reachable.clear()
	if u != null and _mode != Mode.OVER:
		if _mode == Mode.TARGET:
			_show_targets(u)
		elif _mode != Mode.BUSY and ((not u.has_moved and not u.has_acted) or (u.has_acted and u.post_move > 0)):
			_reachable = Movement.destinations(state, u, u.post_move if u.has_acted else -1)
			var cells: Array = []
			for a in _reachable:
				if a != u.pos:
					cells.append_array(u.footprint(a))
			highlights.show_cells("move", cells, Color("#5b9995"), 1, 0)
		_actions = _actions_for(u)
	var prompt := "选择行动"
	if _mode == Mode.TARGET:
		prompt = "选择落点" if _needs_landing() else "选择目标"
		if SkillCatalog.get_skill(str(_pending.get("skill",""))).has("carry"):
			prompt = "选择把同伴送到哪里" if _needs_landing() else "选择要送过去的同伴"
		for action in _actions:
			if action.get("active",false):
				prompt = "%s　·　%s" % [action["label"],prompt]
				break
	elif _mode == Mode.FACING:
		prompt = "点亮起的格子选朝向"
	hud.set_action_context(prompt,_mode in [Mode.TARGET,Mode.FACING],"aim" if _mode == Mode.TARGET else ("facing" if _mode == Mode.FACING else ""))
	# Choosing a facing: the four cells around them light up to be clicked.
	highlights.clear("facing")
	if _mode == Mode.FACING and u != null:
		var around: Array = []
		for step: Vector2i in [Defs.NORTH,Defs.EAST,Defs.SOUTH,Defs.WEST]:
			if state.grid.in_bounds(u.pos+step): around.append(u.pos+step)
		highlights.show_cells("facing",around,Color("#f0cf8a"),3,2,.16)
		highlights.show_frame("facing_now",[u.pos+u.facing] if state.grid.in_bounds(u.pos+u.facing) else [],Color("#fff3d0"),13)
	else:
		highlights.clear("facing_now")
	hud.set_actions(_actions if _mode != Mode.BUSY else [])
	hud.set_unit(u,state.unit_height(u) if u != null else 0,_mode == Mode.BUSY)
	_on_hover()


func _needs_landing() -> bool:
	return _pending.get("type", "") == "skill" and SkillCatalog.get_skill(_pending["skill"]).has("leap") \
		and not _pending.has("to")


func _is_pending(act: Dictionary) -> bool:
	return _mode == Mode.TARGET and _pending.get("type", "") == act.get("type", "") \
		and _pending.get("skill", "") == act.get("skill", "")


## 瞄准时的高亮。哪些格子在射程内、哪些目标可选都由规则引擎一次算好（Rules.targeting）。
func _show_targets(u: UnitState) -> void:
	var pending := _pending.duplicate()
	pending["unit"] = u.id
	var t := Rules.targeting(state, pending)
	if _needs_landing():
		var cells: Array[Vector2i] = t["landings"]
		highlights.show_cells("valid", cells, Color(1.0, 0.85, 0.3), 2, 0)
		return
	if _pending.has("to"):
		highlights.show_frame("landing_pick", u.footprint(_pending["to"]), Color(1.0, 0.85, 0.3), 12)
	highlights.show_cells("range", t["in_range"], Color(0.9, 0.3, 0.25), 1, 0)
	if _pending.get("skill","")=="purify_arrow":
		highlights.show_cells("valid",t["valid"],Color("#8fe6ae"),2,2,.12)
		return
	highlights.show_cells("valid", t["valid"], Color(1.0, 0.25, 0.2), 2, 2, 0.12)


## What a technique or a carried thing does, in a sentence: the tree's own words where it
## was learnt from the tree, the trader's for a thing, else its numbers.
func _words_for(u: UnitState, id: String, def: Dictionary) -> String:
	if Checkpoint.GOODS.has(id): return Checkpoint.effect_of(id)
	if Checkpoint.power_words(id) != "": return Checkpoint.power_words(id)
	if def.has("support"): return Checkpoint.support_words(id)
	for branch: Dictionary in SkillTree.trees().get(u.tree,[]):
		for node: Dictionary in branch.nodes:
			if str(node.get("skill","")) == id: return str(node.desc)
	if int(def.get("area_knockback",0)) > 0: return "周围 %d 格内的敌人各被震退 %d 格。" % [int(def.get("radius",1)),int(def.area_knockback)]
	if def.has("self_status") or def.has("area_status"): return ""
	var words := "%s 倍%s伤害" % [str(def.get("mult",1)),"神性" if int(def.get("type",0)) == Defs.DamageType.DIVINE else "物理"]
	if int(def.get("knockback",0)) > 0: words += "，击退 %d 格" % int(def.knockback)
	if def.get("throw",false): words += "，把对方从头顶摔到自己另一侧的格子；落差、撞击照常结算，摔不动大体型"
	if int(def.get("stagger_bonus",0)) > 0: words += "，额外破势 %d" % int(def.stagger_bonus)
	return words+"。"


## Reach and waiting time of a technique or a thing, in a few words.
func _brief(sk: Dictionary) -> String:
	if sk.has("blink"): return "%d 格内" % int(sk.blink)
	if sk.has("self_status") or sk.has("area_status") or sk.has("area_knockback") or sk.has("area_shield"): return "自身"
	var near := int(sk.get("min_range",1))
	var far := int(sk.get("max_range",1))
	return "射程 %d" % near if near == far else "射程 %d–%d" % [near,far]


## Everything the selected unit can do, each command naming the group it belongs to on the
## bar: move, attack (the plain attack every unit has), skill, item, wait.
func _actions_for(u: UnitState) -> Array:
	var out: Array = []
	var my_phase := state.phase == Defs.Phase.PLAYER
	var can_act := my_phase and not u.has_acted
	if state.move_undo.has(u.id):
		out.append({"group":"move","label":"撤销移动","art":"act_undo","kind":"do","action":{"type":"undo_move"},"enabled":true,"words":"回到移动前的位置，可以重新走。"})
	else:
		var can_move := my_phase and _reachable.size() > 1
		out.append({"group":"move","label":"移动","art":"act_move","kind":"move","enabled":can_move,"active":can_move and _mode == Mode.IDLE})
	for i in u.skills.size():
		var sk: String = u.skills[i]
		var def: Dictionary = SkillCatalog.get_skill(sk)
		var cd := u.cooldown(sk)
		var act := {"type": "skill", "skill": sk}
		var carried: bool = def.get("item",false)
		var entry := {"group":"item" if carried else ("attack" if i == 0 else "skill"),"label":"攻击" if i == 0 and not carried else str(def["name"]),
			"title":str(def["name"]),"art":sk,"cooldown":cd,"brief":_brief(def),"kind":"target","action":act,
			"enabled":can_act and cd == 0,"active":_is_pending(act)}
		entry.words = _words_for(u,sk,def)
		entry.recharge = int(def.get("cooldown",0))
		if carried:
			entry.count = int(u.items.get(sk,0))
			entry.brief += "　·　剩 %d 件" % entry.count
		if def.has("support"):
			# Calling a hired hero is not the protagonist's own action: it stays open after
			# he has struck, from the second round on.
			entry.enabled = my_phase and cd == 0 and state.round_number >= 2
			if state.round_number < 2: entry.brief += "　·　第二回合起"
		if def.has("self_status") or def.has("area_shield"):
			entry.kind = "do"
			entry.enabled = can_act and cd == 0
			entry.erase("active")
		out.append(entry)
	if u.has_trait("hunter_mark"):
		var act := {"type": "mark"}
		out.append({"group":"skill","label":"标记","art":"mark","brief":"视野内","words":"标记一个敌人，对它的射击更远更准。不耗行动。","kind":"target","action":act,"enabled":my_phase and not u.mark_used,"active":_is_pending(act)})
	for cymbal: Dictionary in state.cymbals:
		# Offered whenever he could reach it; says why not when it cannot be rung just now.
		var strike := {"type":"strike","unit":u.id,"target":cymbal.pos}
		var why := Rules.validate(state,strike)
		if why in ["","still ringing"]:
			var falls := 0
			for id in state.order:
				var bird := state.unit(id)
				if bird.alive and bird.team == Defs.Team.ENEMY and bird.has_trait("flying") and not bird.has_status("grounded") and absi(bird.pos.x-cymbal.pos.x)+absi(bird.pos.y-cymbal.pos.y) <= 3: falls += 1
			out.append({"group":"skill","label":"敲铜钹","art":"act_push","brief":"相邻" if why == "" else "还要歇 %d 回合" % int(cymbal.rest),
				"words":"敲响铜钹：3 格内还在天上的敌人落地，到这一回合结束前谁都打得到。现在会落下 %d 只。敲过后铜钹要歇 2 回合。" % falls,
				"kind":"do","action":{"type":"strike","target":cymbal.pos},"enabled":can_act and why == ""})
	if not state.cave.is_empty():
		for id in state.cave["boulders"]:
			var push := {"type": "push_boulder", "unit": u.id, "target": state.cave["boulders"][id]["pos"]}
			var err := Rules.validate(state, push)
			if err == "" or err == "cannot seal the last entrance":
				out.append({"group":"skill","label":"推巨石","art":"push_boulder","brief":"相邻","words":"把巨石推进洞口，封住一个出口。","kind":"do","action":{"type":"push_boulder","target":push["target"]},"enabled":can_act and err == ""})
	out.append({"group":"wait","label":"待机","art":"act_wait","kind":"wait","enabled":can_act,"active":_mode == Mode.FACING,
		"words":"结束这个人的行动，进入防御姿态。点了之后选朝向。"})
	return out


## Draws an enemy's plan on the field: footsteps to where it means to stand, and an arrow
## from there to whoever it means to strike.
func _draw_intent(at: UnitState, sim: Dictionary) -> void:
	var plan: Dictionary = sim["plan"]
	var from: Vector2i = plan.get("move_to", at.pos)
	if from != at.pos:
		hud.overlay.intent_walk.assign([(unit_views[at.id] as UnitView).position+Vector3(0,.08,0),map_view.anchor_world(state,from,at.size)+Vector3(0,.08,0)])
	var act: Dictionary = plan["action"]
	if act.get("type", "") == "skill":
		var tgt := state.unit_at(act["target"])
		if tgt != null:
			hud.overlay.intent_from = map_view.anchor_world(state, from, at.size) + Vector3(0, 0.3, 0)
			hud.overlay.intent_to = (unit_views[tgt.id] as UnitView).position + Vector3(0, 0.3, 0)


func _inspect_enemy_order(id: String) -> void:
	if state == null:
		return
	if id.is_empty():
		_on_hover()
		return
	var u := state.unit(id)
	if _mode == Mode.BUSY or u == null:
		return
	var sim := EnemyAI.simulate(state,u)
	var caption := "%d · %s　当前局面推演" % [hud.enemy_numbers[id],u.display_name]
	hud.overlay.intent_from = Vector3.INF
	hud.overlay.intent_walk.clear()
	if sim["events"].is_empty():
		hud.set_info_text("待机",caption)
	else:
		hud.preview_records(state,sim["events"],caption,true)
		_draw_intent(u,sim)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and hud != null and hud.overlay != null and hud.is_over_panel(event.position):
		if hud.overlay.rescue_route.is_empty() and hud.overlay.fall_preview.is_empty():
			return
		_hovered = Defs.NO_POS
		_on_hover()


func _on_hover() -> void:
	hud.overlay.fall_preview.clear()
	hud.overlay.rescue_route.clear()
	hud.overlay.rescue_threats.clear()
	highlights.clear("route")
	highlights.clear("hover")
	highlights.clear("landing")
	highlights.clear("intent")
	hud.overlay.intent_from = Vector3.INF
	hud.overlay.intent_walk.clear()
	if state == null or _hovered == Defs.NO_POS:
		hud.set_info_text("")
		return
	highlights.show_frame("hover", [_hovered], Color(1, 1, 0.85))
	var at := state.unit_at(_hovered)
	var info: Array[String] = []
	var forecast := ""
	var inspected: UnitState
	var inspected_intent := ""
	var preview_events: Array = []
	var preview_caption := "行动预览　·　左键确认"
	var terrain_names := ["平地", "林地", "浅水", "深水", "沼泽", "燃烧", "冥河"]
	info.append("[color=#c8b48a]格子 (%d, %d)　高度 %d　%s[/color]" % [_hovered.x, _hovered.y,
		state.grid.height_at(_hovered), terrain_names[state.grid.terrain_at(_hovered)]])

	if map_view.woodland and _mode == Mode.IDLE and state.phase == Defs.Phase.PLAYER and at != null and at.def_id == "refugee":
		var plan := state.query({"op":"rescue_preview","unit":at.id})
		hud.overlay.rescue_route.append(at.pos)
		hud.overlay.rescue_route.append_array(GoEngine.cells(plan.path))
		hud.overlay.rescue_threats.assign(plan.threats)
		var intent := "本回合抵达西口" if plan.escapes else ("本回合原地等待" if plan.path.is_empty() else "本回合向西撤离")
		if not plan.threats.is_empty():
			intent += "　·　%d 名敌人可攻击停留格" % plan.threats.size()
		hud.show_unit_inspection(at,state.unit_height(at),intent)
		return

	if _mode == Mode.IDLE and at == null and _reachable.has(_hovered):
		var preview := Rules.preview(state,{"type":"move","unit":_selected,"to":_hovered})
		for event in preview["events"]:
			if event["type"] == "move":
				highlights.show_frame("route",event["path"],Color("#afe1ca"),9)
				break
		info.append("移动消耗  %d　·　左键前往" % _reachable[_hovered]["cost"])

	if _mode == Mode.TARGET and _needs_landing():
		info.append("[b]选择落点[/b]（3 格内，最多高 3 层）")
	elif _mode == Mode.TARGET and at != null:
		var act := _pending.duplicate()
		act["unit"] = _selected
		act["target"] = _hovered
		var err := Rules.validate(state, act)
		if err == "":
			var p := Rules.preview(state, act)
			info.append("[b]行动预览[/b]　·　左键确认")
			preview_events = p["events"]
			var landed := {}
			for e in p["events"]:
				if e["type"] in ["damage","heal"] and at != null and e["target"] == at.id:
					forecast = "%s　生命 %d → %d" % [at.display_name,at.hp,maxi(0,e["hp"])]
				if e["type"] == "knockback":
					landed[e.target] = map_view.anchor_world(state,e.to,state.unit(e.target).size)
					highlights.show_frame("landing", state.unit(e.target).footprint(e.to), Color("#ffcb8c"), 11)
				if e.type == "fall" and landed.has(e.target):
					hud.overlay.fall_preview = {"world":landed[e.target],"levels":e.levels}
				if e.type == "damage" and e.source == "fall" and not hud.overlay.fall_preview.is_empty():
					hud.overlay.fall_preview.damage = e.amount
		else:
			info.append("[color=#e88]不能对其使用：%s[/color]" % EventText.error_text(err))
	elif at != null and at.team == Defs.Team.ENEMY and _mode != Mode.BUSY and hud.enemy_numbers.has(at.id):
		inspected = at
		var sim := EnemyAI.simulate(state, at)
		info.append("[b]意图（若现在轮到它）[/b]")
		preview_events = sim["events"]
		preview_caption = "%s　·　预计行动" % at.display_name
		if preview_events.is_empty():
			inspected_intent = "待机"
		highlights.show_threat("intent",EnemyAI.threat_cells(state,at))
		_draw_intent(at,sim)
	elif at != null and at.id != _selected:
		inspected = at
	if not preview_events.is_empty():
		hud.preview_records(state,preview_events,preview_caption,_mode == Mode.TARGET or (inspected != null and inspected.team == Defs.Team.ENEMY))
	elif inspected != null:
		hud.show_unit_inspection(inspected,state.unit_height(inspected),inspected_intent)
	else:
		hud.set_info_text("\n".join(info),forecast)


# --- Scripted captures (for automated screenshots) -------------------------------

func _run_capture() -> void:
	await get_tree().process_frame
	match _demo:
		"build":
			pass
		"motion", "material", "material_side", "material_close", "material_far":
			cam_rig.focus(map_view.to_global(Vector3(2.7,1.05,5.7)))
			if _demo == "material_side":
				cam_rig.set_quadrant(1)
			if _demo in ["material_close","motion"]:
				cam_rig.zoom_step(1)
			if _demo == "material_far":
				cam_rig.zoom_step(-1)
			if _demo == "motion":
				_select("hero")
			await get_tree().create_timer(0.55).timeout
			await _perform({"type":"move","unit":"hero","to":Vector2i(3,5)})
			if _demo == "motion":
				_pending = {"type":"skill","skill":"spear"}
				_mode = Mode.TARGET
				_hovered = Vector2i(3,6)
				_refresh()
				_on_hover()
				await get_tree().create_timer(0.65).timeout
				_hovered = Defs.NO_POS
			await _perform({"type":"skill","unit":"hero","skill":"spear","target":Vector2i(3,6)})
			await _end_turn()
			if _demo == "motion":
				await get_tree().create_timer(0.8).timeout
		"menu":
			# The bar with the technique list open over it.
			await get_tree().create_timer(.4).timeout
			hud._toggle_group("skill")
			await get_tree().create_timer(.5).timeout
			for i in _actions.size():
				if _actions[i].group == "skill":
					hud._show_detail(i)
					break
			await get_tree().create_timer(.2).timeout
		"facing":
			# Waiting: the prompt to choose which way to face.
			await get_tree().create_timer(.4).timeout
			for i in _actions.size():
				if _actions[i].group == "wait": _on_action(i)
			await get_tree().create_timer(.3).timeout
		"moved":
			# After a move: the small diamond at the middle that takes it back.
			await get_tree().create_timer(.4).timeout
			for cell: Vector2i in _reachable:
				if cell != state.unit("hero").pos:
					await _perform({"type":"move","unit":"hero","to":cell})
					break
			for i in _actions.size():
				if _actions[i].group == "move": hud._show_detail(i)
			await get_tree().create_timer(.4).timeout
		"spoils":
			# What a beaten enemy leaves, shown over where they fell.
			await get_tree().create_timer(.4).timeout
			for id: String in state.order:
				var foe := state.unit(id)
				if foe.team == Defs.Team.ENEMY and not foe.hidden:
					cam_rig.focus(unit_views[id].position)
					await get_tree().create_timer(.4).timeout
					_drop_spoils(id)
					_drop_spoils(state.order[state.order.find(id)+1])
					break
			await get_tree().create_timer(.12).timeout
		"badges":
			# Every condition at once on one of ours and one of theirs, to see the badges.
			await get_tree().create_timer(.4).timeout
			for id: String in state.order:
				var foe := state.unit(id)
				if foe.team == Defs.Team.ENEMY and not foe.hidden:
					foe.statuses = {"burning":2,"rooted":1,"stunned":1}
					cam_rig.focus(unit_views[id].position.lerp(unit_views["hero"].position,.5))
					break
			state.unit("hero").statuses = {"guard":1,"poisoned":2}
			await get_tree().create_timer(.6).timeout
		"fx":
			# The effects of things carried and of statuses, one on each of whoever is about.
			await get_tree().create_timer(.4).timeout
			var shown := ["burning","poisoned","stunned"]
			var seen := 0
			for id: String in state.order:
				if state.unit(id).hidden or not unit_views.has(id): continue
				if seen < shown.size(): state.unit(id).statuses[shown[seen]] = 2
				elif seen == shown.size(): BattleFX.spawn(_units_root,BLESS,unit_views[id].position+Vector3.UP*.08,.3)
				elif seen == shown.size()+1: BattleFX.spawn(_units_root,BURST,unit_views[id].position+Vector3.UP*.08,.3)
				seen += 1
			cam_rig.focus(unit_views["hero"].position)
			await get_tree().create_timer(.75).timeout
		"reel":
			# Everything a thing carried or a status puts on screen, one after another, for a
			# recording: the hero throws each thing at the nearest enemy, drinks, then the
			# enemy takes each status in turn.
			var foe_id := ""
			for id: String in state.order:
				var other := state.unit(id)
				if other.team != Defs.Team.ENEMY or other.hidden or not unit_views.has(id): continue
				if foe_id == "" or unit_views[id].position.distance_to(unit_views["hero"].position) < unit_views[foe_id].position.distance_to(unit_views["hero"].position):
					foe_id = id
			var me: UnitView = unit_views["hero"]
			var foe: UnitView = unit_views[foe_id]
			cam_rig.focus(me.position.lerp(foe.position,.5))
			await get_tree().create_timer(1.0).timeout
			for thrown: Array in [["item_firepot","火油罐"],["item_stone","石块"],["item_javelin","标枪"],["item_net","捕网"]]:
				_popup("hero",thrown[1],Color("#f1e3c4"))
				if thrown[0]=="item_net":
					await _throw_net(me,foe,true)
				else:
					await _throw_thing(me,foe,thrown[0])
				await get_tree().create_timer(1.6).timeout
			_popup("hero","药剂",Color("#b9f0c4"))
			await _take_tonic(me,me,"item_potion")
			await get_tree().create_timer(1.8).timeout
			# Statuses stay on the body while they last: one alone, then all three together,
			# then gone.
			for status: String in ["burning","poisoned","rooted","stunned"]:
				_popup(foe_id,EventText.STATUS_NAMES.get(status,status),Color(.8,.9,1))
				state.unit(foe_id).statuses = {status:2}
				await get_tree().create_timer(2.6).timeout
			state.unit(foe_id).statuses = {"burning":2,"poisoned":2,"rooted":1,"stunned":1}
			state.unit("hero").statuses = {"rooted":2,"poisoned":2}
			await get_tree().create_timer(3.5).timeout
			state.unit(foe_id).statuses = {}
			state.unit("hero").statuses = {}
			await get_tree().create_timer(1.0).timeout
		"powers":
			# The protagonist uses whatever divinity grew on him, one technique a turn, on
			# the first thing each can reach. For a recording.
			for turn in 5:
				var u := state.unit("hero")
				if u == null or not u.alive: break
				cam_rig.focus(unit_views["hero"].position)
				await get_tree().create_timer(.6).timeout
				for sk: String in u.skills:
					if Checkpoint.power_words(sk) == "" or u.cooldown(sk) > 0: continue
					var def: Dictionary = SkillCatalog.get_skill(sk)
					var act := {"type":"skill","unit":"hero","skill":sk}
					if not (def.has("self_status") or def.has("area_shield")):
						var aim := Rules.targeting(state,act)
						if aim.valid.is_empty(): continue
						# Step toward the enemy rather than away: the reachable cell nearest any of them.
						var pick: Vector2i = aim.valid[0]
						if def.has("blink"):
							var score := 999
							for cell: Vector2i in aim.valid:
								for other_id: String in state.order:
									var other := state.unit(other_id)
									if other.team != Defs.Team.ENEMY or not other.alive or other.hidden: continue
									var gap: int = abs(cell.x-other.pos.x)+abs(cell.y-other.pos.y)
									if gap < score:
										score = gap
										pick = cell
						act.target = pick
					await _perform(act)
					await get_tree().create_timer(1.6).timeout
					break
				_end_turn()
				await get_tree().create_timer(1.0).timeout
				while state != null and state.phase != Defs.Phase.PLAYER: await get_tree().create_timer(.5).timeout
				await get_tree().create_timer(.6).timeout
		"support", "support_hold", "support_late":
			# Round two: the protagonist calls whoever came with him on the first target offered.
			# Run with --support=phalerus.
			_end_turn()
			await get_tree().create_timer(1.0).timeout
			while state != null and state.phase != Defs.Phase.PLAYER: await get_tree().create_timer(.5).timeout
			var move := str(Checkpoint.RECRUITS[str(_campaign_reward.get("support",""))].support)
			if _demo == "support_late":
				# After the protagonist has spent his own action.
				await _perform({"type":"wait","unit":"hero"})
			var call := {"type":"skill","unit":"hero","skill":move}
			var calls: Dictionary = Rules.targeting(state,call)
			if not calls.landings.is_empty():
				# A carry: first where to set the companion down, then whom.
				call["to"] = calls.landings[0]
				calls = Rules.targeting(state,call)
			if not calls.valid.is_empty():
				call["target"] = calls.valid[0]
				await _perform(call)
			_select("hero")
		"stumps":
			# 2-5 for a capture only: one head just cut down, one sealed, as the view draws them.
			for pair: Array in [["head_1",false],["head_4",true]]:
				var neck := state.unit(pair[0])
				neck.alive = false
				neck.sealed = pair[1]
				unit_views[neck.id].hide()
			_refresh()
		"fire":
			# A fire pot thrown at empty forest, then two rounds for it to spread and burn out.
			# Run with --kit=item_firepot.
			for turn in 3:
				var aim := Rules.targeting(state,{"type":"skill","unit":"hero","skill":"item_firepot"})
				var empty: Array = aim.valid.filter(func(cell): return state.unit_at(cell) == null)
				if turn == 0 and not empty.is_empty():
					await _perform({"type":"skill","unit":"hero","skill":"item_firepot","target":empty[0]})
					await get_tree().create_timer(.6).timeout
				if turn < _fire_rounds:
					_end_turn()
					await get_tree().create_timer(1.0).timeout
					while state != null and state.phase != Defs.Phase.PLAYER: await get_tree().create_timer(.5).timeout
					await get_tree().create_timer(.4).timeout
				_refresh()
		"throw":
			# The protagonist closes on the nearest enemy and throws them over his shoulder.
			for turn in 6:
				var u := state.unit("hero")
				cam_rig.focus(unit_views["hero"].position)
				var aim := Rules.targeting(state,{"type":"skill","unit":"hero","skill":"shoulder_throw"})
				if aim.valid.is_empty() and not u.has_moved:
					var best := u.pos
					var score := 999
					for cell: Vector2i in Movement.destinations(state,u,-1):
						for other_id: String in state.order:
							var other := state.unit(other_id)
							if other.team != Defs.Team.ENEMY or not other.alive or other.hidden or other.size > 1: continue
							var gap: int = abs(cell.x-other.pos.x)+abs(cell.y-other.pos.y)
							if gap >= 1 and gap < score:
								score = gap
								best = cell
					if best != u.pos:
						await _perform({"type":"move","unit":"hero","to":best})
						await get_tree().create_timer(.4).timeout
					aim = Rules.targeting(state,{"type":"skill","unit":"hero","skill":"shoulder_throw"})
				if not aim.valid.is_empty():
					await get_tree().create_timer(.6).timeout
					await _perform({"type":"skill","unit":"hero","skill":"shoulder_throw","target":aim.valid[0]})
					await get_tree().create_timer(2.0).timeout
					break
				_end_turn()
				await get_tree().create_timer(1.0).timeout
				while state != null and state.phase != Defs.Phase.PLAYER: await get_tree().create_timer(.5).timeout
				await get_tree().create_timer(.6).timeout
		"guard":
			# Two of ours brace: how the stance shows on the field.
			await get_tree().create_timer(.4).timeout
			await _perform({"type":"wait","unit":"hero"})
			await _perform({"type":"wait","unit":"atalanta"})
			await get_tree().create_timer(1.4).timeout
		"intent":
			# Point at the first enemy: its plan drawn on the field and summed up in the card.
			await get_tree().create_timer(.5).timeout
			for id: String in state.order:
				var foe := state.unit(id)
				if foe.alive and not foe.hidden and foe.team == Defs.Team.ENEMY:
					cam_rig.focus(unit_views[id].position)
					await get_tree().create_timer(.4).timeout
					_hovered = foe.pos
					_on_hover()
					break
			await get_tree().create_timer(.4).timeout
		"inspect":
			# Point at someone who is not ours to command: a traveller if there is one,
			# else the first enemy. A still shows the card that comes up for them.
			var subject: UnitState = null
			for id: String in state.order:
				var other := state.unit(id)
				if other.alive and not other.hidden and (other.def_id == "refugee" or (subject == null and other.team == Defs.Team.ENEMY)): subject = other
			cam_rig.focus(unit_views[subject.id].position)
			await get_tree().create_timer(.5).timeout
			_hovered = subject.pos
			_on_hover()
			await get_tree().create_timer(.4).timeout
		"edge":
			# Selection overlays where the ground steps: the hero's reach, and a hover frame
			# on each cell around him, so a still shows how they sit at a ledge.
			_select("hero")
			cam_rig.zoom_step(1)
			cam_rig.focus(unit_views["hero"].position+Vector3(0,.6,-1.5))
			var around: Array = []
			for dz in range(-2,3):
				for dx in range(-2,3):
					if (dx+dz)%2 == 0: around.append(state.unit("hero").pos+Vector2i(dx,dz))
			highlights.show_frame("edge_demo",around.filter(func(c): return state.grid.in_bounds(c)),Color(1,1,0.85))
			await get_tree().create_timer(1.2).timeout
		"fx":
			# The three one-shot effects side by side, slowed so a still catches them mid-play.
			var centre: Vector3 = unit_views["hero"].position
			var side := cam_rig.camera.global_basis.x
			BattleFX.spawn(_units_root,SLASH,centre+Vector3.UP*.9-side*2.6,6.0)
			BattleFX.spawn(_units_root,IMPACT,centre+Vector3.UP*.9+side*2.2,9.0)
			BattleFX.spawn(_units_root,DUST,centre+Vector3.UP*.08-side*.2+cam_rig.camera.global_basis.y*2.6,5.0)
			await get_tree().create_timer(.25).timeout
		"field_wind":
			cam_rig.focus(map_view.to_global(Vector3(1.4,.8,5.8)))
			await get_tree().create_timer(6.5).timeout
		"workshop_entry":
			cam_rig.focus(map_view.to_global(Vector3(11.0,.8,5.8)))
			cam_rig.set_quadrant(1)
			cam_rig.zoom_step(1)
		"workshop", "village_ruin":
			var workshop := _demo == "workshop"
			cam_rig.focus(map_view.to_global(Vector3(-2.1,.45,5.1) if workshop else Vector3(-2.15,.60,6.65)))
			cam_rig.set_quadrant(0 if workshop else 2)
			cam_rig.zoom_step(1)
		"art_side":
			cam_rig.set_quadrant(1)
		"escape", "escape_far":
			if _demo == "escape_far":
				cam_rig.zoom_step(-1)
			_select("hero")
			await get_tree().create_timer(.95).timeout
			await _perform({"type":"move","unit":"hero","to":Vector2i(3,5)})
			await _perform({"type":"skill","unit":"hero","skill":"spear","target":Vector2i(3,6)})
			await _end_turn()
			if _demo == "escape_far":
				cam_rig.rotate_step(1)
			_select("hero")
			await get_tree().create_timer(.48).timeout
			await _perform({"type":"move","unit":"hero","to":Vector2i(6,4)})
			await _end_turn()
			if _demo == "escape_far":
				cam_rig.rotate_step(1)
			_select("hero")
			await get_tree().create_timer(.48).timeout
			await _perform({"type":"move","unit":"hero","to":Vector2i(8,2)})
			_select("atalanta")
			await get_tree().create_timer(.48).timeout
			await _perform({"type":"move","unit":"atalanta","to":Vector2i(9,0)})
			await _end_turn()
			_select("hero")
			await get_tree().create_timer(.48).timeout
			await _perform({"type":"move","unit":"hero","to":Vector2i(8,0)})
			print("village escape: ",state.village_result)
			await get_tree().create_timer(0.75).timeout
		"pounce":
			# A fixed legal exchange from the ordinary 1-5 starting state.
			await _perform({"type":"move","unit":"hero","to":Vector2i(6,8)})
			cam_rig.focus(map_view.to_global(Vector3(6,0.85,7.8)))
			cam_rig.zoom_step(1)
			await _advance_phase()
			_refresh()
			await get_tree().create_timer(0.45).timeout
			await _perform({"type":"skill","unit":"lion","skill":"pounce","target":Vector2i(6,8),"to":Vector2i(5,6)})
			await _advance_phase()
			_refresh()
			await get_tree().create_timer(0.4).timeout
			await _perform({"type":"skill","unit":"hero","skill":"spear","target":Vector2i(5,6)})
			await get_tree().create_timer(0.55).timeout
		"skirmish":
			# Advance a legal opening move and let the battle AI answer.
			_select("hero")
			await get_tree().create_timer(0.5).timeout
			await _perform({"type":"move", "unit":"hero", "to":Vector2i(6, 8)})
			await _end_turn()
			await get_tree().create_timer(0.5).timeout
		"move":
			_select("hero")
			_hovered = Vector2i(3, 6)
		"target":
			_perform({"type": "move", "unit": "atalanta", "to": Vector2i(2, 6)})
			await get_tree().create_timer(1.0).timeout
			_select("atalanta")
			_perform({"type": "mark", "unit": "atalanta", "target": Vector2i(6, 4)})
			await get_tree().create_timer(0.3).timeout
			_pending = {"type": "skill", "skill": "shoot"}
			_mode = Mode.TARGET
			_refresh()
			_hovered = Vector2i(6, 4)
		"threat":
			_show_threat = true
			_set_tactical(true)
			_hovered = Vector2i(9, 5)
			_refresh()
		"leap":
			_select("atalanta")
			_pending = {"type": "skill", "skill": "leap_shot"}
			_mode = Mode.TARGET
			_refresh()
			await get_tree().create_timer(0.3).timeout
			_click(Vector2i(9, 13))
			_hovered = Vector2i(7, 9)
		"rotate":
			cam_rig.rotate_step(1)
			cam_rig.zoom_step(1)
			_select("hero")
			await get_tree().create_timer(0.6).timeout
			_hovered = Vector2i(2, 5)
		"enemy":
			_end_turn()
			await get_tree().create_timer(6.0).timeout
	_on_hover()
	for i in 20:
		await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		# 无头模式没有画面可存：只把演示流程走完（自动检查用）
		if state != null:
			print("demo finished (headless, no image): round %d, phase %d" % [state.round_number, state.phase])
		else:
			print("demo finished (headless, no image): build panel")
	else:
		await RenderingServer.frame_post_draw
		var source := _viewport if _demo in ["art", "art_side","workshop","village_ruin","workshop_entry"] or _demo.begins_with("material") else get_viewport()
		source.get_texture().get_image().save_png(_capture_path)
		print("captured ", _capture_path)
	GoEngine.shutdown()
	get_tree().quit()
