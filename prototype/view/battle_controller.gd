extends Node
## Greybox battle: builds the low-res world, HUD and input flow on top of the rules core.
## 规则全部在 Go 引擎里（engine/，由 GoEngine 拉起 `srpg play`）；这里只做表现和输入。
## Starts on the pre-battle build panel (skill picks + battle choice).
##
## Command line (after `--`):
##   --battle=<id>     1-4 | 1-5 | test (default 1-4); skips the build panel with default picks
##   --data-dir=<dir>  覆盖数据目录，原样交给规则引擎
##   --capture=<png>   save a screenshot after the scripted demo and quit
##   --demo=<name>     build | idle | move | target | threat | rotate | enemy  (scripted captures)

const LOW_RES := Vector2(640, 360)

enum Mode { IDLE, TARGET, FACING, BUSY, OVER }

var state: BattleState
var map_view: MapView
var highlights: HighlightLayer
var cam_rig: CameraRig
var hud: Hud
var unit_views := {}
var boulder_views := {}  ## boulder id -> MeshInstance3D
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
var _drag_from := Vector2.INF
var _capture_path := ""
var _demo := ""
var _battle_id := ""
var _build_panel: BuildPanel


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--demo="):
			_demo = arg.trim_prefix("--demo=")
		elif arg.begins_with("--battle="):
			_battle_id = arg.trim_prefix("--battle=")
	if not GoEngine.ensure():
		_engine_missing()
		return
	_build_scene()
	get_window().size_changed.connect(_on_resize)
	_on_resize()
	if _demo == "build" or (_battle_id == "" and _capture_path == ""):
		_build_panel = BuildPanel.new()
		hud.add_child(_build_panel)
		_build_panel.start_pressed.connect(_start_battle)
		_build_panel.open(ui_scale)
		hud.set_battle_controls_visible(false)
	else:
		_start_battle(_battle_id if _battle_id != "" else "1-4", SkillTree.default_picks())
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
	label.add_theme_font_size_override("font_size", 28)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(label)
	if _capture_path != "" or DisplayServer.get_name() == "headless":
		get_tree().quit(1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GoEngine.shutdown()


func _start_battle(battle_id: String, picks: Dictionary) -> void:
	hud.set_battle_controls_visible(true)
	state = Battles.build(battle_id, picks)
	if state == null:
		hud.banner("无法开始战斗：%s" % GoEngine.error, 0.0)
		return
	Rules.start_battle(state)
	map_view.build(state.grid)
	for id in state.order:
		var v := UnitView.new()
		_units_root.add_child(v)
		v.setup(state.units[id])
		unit_views[id] = v
	if not state.cave.is_empty():
		for id in state.cave["boulders"]:
			var rock := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.42
			mesh.height = 0.7
			mesh.radial_segments = 10
			mesh.rings = 5
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.56, 0.55, 0.58)
			mat.roughness = 1.0
			mesh.material = mat
			rock.mesh = mesh
			_units_root.add_child(rock)
			boulder_views[id] = rock
	_sync_views()
	cam_rig.bounds = AABB(Vector3.ZERO, Vector3(state.grid.width, 0, state.grid.depth))
	cam_rig.focus(Vector3(state.grid.width * 0.5, 0.5, state.grid.depth * 0.5))
	hud.set_help_visible(true)
	_refresh()
	hud.banner("%s　第 1 回合" % Battles.title(battle_id))


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
	env.background_color = Color(0.55, 0.68, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.88)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
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
	world.add_child(cam_rig)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.overlay.controller = self
	hud.action_pressed.connect(_on_action)
	hud.end_turn_pressed.connect(_end_turn)


func _on_resize() -> void:
	var size := Vector2(get_window().size)
	shrink = maxi(1, mini(floori(size.x / LOW_RES.x), floori(size.y / LOW_RES.y)))
	_container.stretch_shrink = shrink
	_container.position = Vector2.ZERO
	_container.size = size
	hud.apply_scale(size)
	ui_scale = hud.ui_scale


func world_to_screen(p: Vector3) -> Vector2:
	return cam_rig.camera.unproject_position(p) * shrink


# --- Input -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == null:
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
			tactical = not tactical
			map_view.set_tactical(tactical)
		KEY_P:
			var mat := cam_rig.post.material_override as ShaderMaterial
			cam_rig.set_post_enabled(not mat.get_shader_parameter("enabled"))
		KEY_Z:
			if _selected != "" and _mode != Mode.BUSY:
				_perform({"type": "undo_move", "unit": _selected})
		KEY_SPACE, KEY_ENTER:
			_end_turn()
		KEY_ESCAPE:
			_cancel()
		KEY_R:
			get_tree().reload_current_scene()
		KEY_F11:
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


## Unit sprites take priority over the tile under the cursor (sprites stand in front of tiles).
func _pick(screen: Vector2) -> Vector2i:
	if hud.is_over_panel(screen):
		return Defs.NO_POS
	var best_depth := INF
	var best := Defs.NO_POS
	for id in state.order:
		var u: UnitState = state.units[id]
		if not u.alive:
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
	var sub := screen / shrink
	return map_view.pick(cam_rig.camera.project_ray_origin(sub), cam_rig.camera.project_ray_normal(sub))


func _click(cell: Vector2i) -> void:
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
				else:
					_set_mode(Mode.IDLE)
				return
			var act := _pending.duplicate()
			act["unit"] = _selected
			act["target"] = cell
			if Rules.validate(state, act) == "":
				_perform(act)
			else:
				_set_mode(Mode.IDLE)
		Mode.FACING:
			var u := state.unit(_selected)
			var d := cell - u.pos
			if d != Vector2i.ZERO:
				var f := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
				_perform({"type": "face", "unit": _selected, "facing": f})
			_set_mode(Mode.IDLE)
		_:
			if at != null and at.team == Defs.Team.PLAYER:
				_select(at.id)
			elif _selected != "":
				var mv := {"type": "move", "unit": _selected, "to": cell}
				if Rules.validate(state, mv) == "":
					_perform(mv)
				elif at == null:
					_select("")


func _cancel() -> void:
	if _mode == Mode.TARGET or _mode == Mode.FACING:
		_set_mode(Mode.IDLE)
	elif _mode == Mode.IDLE:
		_select("")


func _select(id: String) -> void:
	if _selected != "" and unit_views.has(_selected):
		(unit_views[_selected] as UnitView).set_selected(false)
	_selected = id
	if id != "":
		(unit_views[id] as UnitView).set_selected(true)
	_set_mode(Mode.IDLE)


func _set_mode(m: int) -> void:
	_mode = m
	if m != Mode.TARGET:
		_pending = {}
	_refresh()


func _on_action(index: int) -> void:
	if _mode == Mode.BUSY or index >= _actions.size():
		return
	var a: Dictionary = _actions[index]
	match a["kind"]:
		"target":
			if _is_pending(a["action"]):
				_set_mode(Mode.IDLE)
			else:
				_pending = (a["action"] as Dictionary).duplicate()
				_mode = Mode.TARGET
				_refresh()
		"facing":
			_set_mode(Mode.FACING if _mode != Mode.FACING else Mode.IDLE)
		"do":
			var act: Dictionary = (a["action"] as Dictionary).duplicate()
			act["unit"] = _selected
			_perform(act)


# --- Actions & animation ---------------------------------------------------------

func _perform(action: Dictionary) -> void:
	var o := Rules.perform(state, action)
	if not o["ok"]:
		hud.log_lines(["[color=#e88]无法执行：%s[/color]" % EventText.error_text(o["error"])])
		return
	_set_mode(Mode.BUSY)
	await _play(o["events"])
	if _check_end():
		return
	_set_mode(Mode.IDLE)


func _play(events: Array) -> void:
	hud.log_lines(EventText.describe(state, events))
	for e in events:
		match e["type"]:
			"move":
				await _animate_path(e["unit"], e["path"])
			"undo_move":
				_sync_views()
			"leap":
				var lu := state.unit(e["unit"])
				var lv: UnitView = unit_views[lu.id]
				var to := map_view.anchor_world(state, e["to"], lu.size)
				var top := Vector3((lv.position.x + to.x) * 0.5, maxf(lv.position.y, to.y) + 0.8, (lv.position.z + to.z) * 0.5)
				var ltw := create_tween()
				ltw.tween_property(lv, "position", top, 0.14)
				ltw.tween_property(lv, "position", to, 0.14)
				await ltw.finished
			"intercept":
				_popup(e["unit"], "截击", Color(0.6, 0.85, 1.0))
			"slam":
				_popup(e["target"], "摔投", Color(1, 0.85, 0.5))
			"knockback":
				var u := state.unit(e["target"])
				var tw := create_tween()
				tw.tween_property(unit_views[u.id], "position", map_view.anchor_world(state, e["to"], u.size), 0.16)
				await tw.finished
			"attack":
				await _bump(e["unit"], e["target"])
			"damage":
				var col := Color(1, 0.35, 0.3) if e["dmg_type"] != Defs.DamageType.TRUE else Color(1, 1, 1)
				_popup(e["target"], "-%d" % e["amount"] if e["amount"] > 0 else "0", col)
				await get_tree().create_timer(0.08).timeout
			"ko":
				(unit_views[e["target"]] as UnitView).fade_out()
			"broken":
				_popup(e["target"], "破势！", Color(1, 0.85, 0.2))
			"stagger":
				_popup(e["target"], "破势 +%d" % e["amount"], Color(0.95, 0.6, 0.2))
			"dodge":
				_popup(e["target"], "闪避", Color(0.7, 0.9, 1))
			"grapple_start":
				_popup(e["target"], "擒抱", Color(1, 0.85, 0.5))
			"grapple_end":
				if e["target"] != "":
					_popup(e["target"], EventText.END_REASONS.get(e["why"], ""), Color(0.85, 0.85, 0.85))
			"status":
				_popup(e["target"], EventText.STATUS_NAMES.get(e["status"], e["status"]), Color(0.8, 0.9, 1))
			"stun_skip":
				_popup(e["unit"], "眩晕", Color(1, 0.85, 0.2))
			"area":
				_popup(e["unit"], EventText.skill_name(e["skill"]), Color(1, 0.6, 0.3))
				await get_tree().create_timer(0.25).timeout
			"push":
				_popup(e["unit"], "推巨石 %d/2" % mini(int(e["progress"]), 2), Color(0.85, 0.85, 0.9))
			"sealed":
				hud.banner("%s入口已封住" % EventText.ENTRANCE_NAMES.get(e["entrance"], e["entrance"]), 0.8)
				_sync_views()
			"retreat":
				_popup(e["unit"], "退回洞内", Color(1, 0.85, 0.2))
				await get_tree().create_timer(0.35).timeout
				_sync_views()
			"emerge":
				_sync_views()
				_popup(e["unit"], "冲出！", Color(1, 0.4, 0.3))
				await get_tree().create_timer(0.3).timeout
	_sync_views()


func _animate_path(id: String, path: Array) -> void:
	var u := state.unit(id)
	var v: UnitView = unit_views[id]
	var tw := create_tween()
	var prev: Vector3 = v.position
	for cell in path:
		var to := map_view.anchor_world(state, cell, u.size)
		if absf(to.y - prev.y) > 0.01:
			var mid := Vector3((prev.x + to.x) * 0.5, maxf(prev.y, to.y) + 0.25, (prev.z + to.z) * 0.5)
			tw.tween_property(v, "position", mid, 0.06)
			tw.tween_property(v, "position", to, 0.06)
		else:
			tw.tween_property(v, "position", to, 0.1)
		prev = to
	if path.is_empty():
		return
	await tw.finished


func _bump(attacker_id: String, target_id: String) -> void:
	var v: UnitView = unit_views[attacker_id]
	var t: UnitView = unit_views[target_id]
	var home := v.position
	var toward := (t.position - home)
	toward.y = 0
	var tw := create_tween()
	tw.tween_property(v, "position", home + toward.normalized() * 0.25, 0.07)
	tw.tween_property(v, "position", home, 0.09)
	await tw.finished


func _popup(id: String, text: String, col: Color) -> void:
	var v: UnitView = unit_views[id]
	hud.overlay.add_popup(v.position + Vector3(0, v.sprite_height + 0.35, 0), text, col)


func _sync_views() -> void:
	for id in state.order:
		var u: UnitState = state.units[id]
		var v: UnitView = unit_views[id]
		if u.alive:
			v.position = map_view.anchor_world(state, u.pos, u.size)
			v.visible = not u.hidden
		v.set_facing(u.facing)
	for id in boulder_views:
		var b: Dictionary = state.cave["boulders"][id]
		var rock: MeshInstance3D = boulder_views[id]
		rock.visible = not b["placed"]
		rock.position = Vector3(b["pos"].x + 0.5, map_view.cell_top(b["pos"]) + 0.3, b["pos"].y + 0.5)


# --- Turn flow -------------------------------------------------------------------

func _end_turn() -> void:
	if _mode == Mode.BUSY or _mode == Mode.OVER or state.phase != Defs.Phase.PLAYER:
		return
	_select("")
	_set_mode(Mode.BUSY)
	await _play(Rules.end_phase(state))
	hud.banner("敌方回合", 0.5)
	_refresh()
	await get_tree().create_timer(0.5).timeout
	for e in state.living(Defs.Team.ENEMY):
		while e.alive and not e.has_acted:
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
		await get_tree().create_timer(0.12).timeout
	await _play(Rules.end_phase(state))
	if _check_end():
		return
	hud.banner("第 %d 回合 · 我方回合" % state.round_number)
	_set_mode(Mode.IDLE)


func _check_end() -> bool:
	var hero := state.unit("hero")
	if hero == null or not hero.alive or state.living(Defs.Team.PLAYER).is_empty():
		hud.banner("战斗失败　按 R 重开", 0.0)
		_mode = Mode.OVER
		_refresh()
		return true
	if state.living(Defs.Team.ENEMY).is_empty():
		hud.banner("胜利！　按 R 重开", 0.0)
		_mode = Mode.OVER
		_refresh()
		return true
	return false


# --- Presentation refresh --------------------------------------------------------

func _refresh() -> void:
	if state == null:
		return
	var phase_text := "我方回合" if state.phase == Defs.Phase.PLAYER else "敌方回合"
	hud.set_phase("第 %d 回合 · %s" % [state.round_number, phase_text])
	hud.set_end_enabled(_mode != Mode.BUSY and _mode != Mode.OVER and state.phase == Defs.Phase.PLAYER)

	highlights.clear_all()
	if _show_threat:
		var cells := {}
		for e in state.living(Defs.Team.ENEMY):
			for c in EnemyAI.threat_cells(state, e):
				cells[c] = true
		highlights.show_cells("threat", cells.keys(), Color(0.95, 0.45, 0.15), 0, 1)

	if not state.cave.is_empty():
		var boss := state.unit(state.cave["boss"])
		for id in state.cave["entrances"]:
			var ent: Dictionary = state.cave["entrances"][id]
			var cells: Array = [ent["anchor"], ent["anchor"] + Vector2i(1, 0), ent["anchor"] + Vector2i(0, 1), ent["anchor"] + Vector2i(1, 1)]
			if ent["sealed"]:
				highlights.show_cells("lair_" + id, cells, Color(0.45, 0.45, 0.5), 0, 1)
			elif boss != null and boss.alive and boss.hidden and EnemyAI.cave_entrance(state, boss) == id:
				highlights.show_frame("lair_" + id, cells, Color(1.0, 0.3, 0.2), 14)  # intent: it comes out here
			else:
				highlights.show_frame("lair_" + id, cells, Color(0.95, 0.75, 0.3), 9)

	var u := state.unit(_selected) if _selected != "" else null
	if u != null and not u.alive:
		_selected = ""
		u = null
	_actions = []
	if u != null and _mode != Mode.OVER:
		if _mode == Mode.TARGET:
			_show_targets(u)
		elif _mode != Mode.BUSY and ((not u.has_moved and not u.has_acted) or (u.has_acted and u.post_move > 0)):
			var reach := Movement.destinations(state, u, u.post_move if u.has_acted else -1)
			var cells: Array = []
			for a in reach:
				if a != u.pos:
					cells.append_array(u.footprint(a))
			highlights.show_cells("move", cells, Color(0.3, 0.6, 1.0), 1, 0)
		_actions = _actions_for(u)
	hud.set_actions(_actions if _mode != Mode.BUSY else [])
	hud.set_unit_text(_unit_text(u) if u != null else "")
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
	if _pending["type"] == "slam" or _needs_landing():
		var cells: Array[Vector2i] = t["valid"] if _pending["type"] == "slam" else t["landings"]
		var col := Color(1.0, 0.85, 0.3) if _pending["type"] == "skill" else Color(1.0, 0.5, 0.2)
		highlights.show_cells("valid", cells, col, 2, 0)
		return
	if _pending.has("to"):
		highlights.show_frame("landing_pick", u.footprint(_pending["to"]), Color(1.0, 0.85, 0.3), 12)
	highlights.show_cells("range", t["in_range"], Color(0.9, 0.3, 0.25), 1, 0)
	highlights.show_cells("valid", t["valid"], Color(1.0, 0.25, 0.2), 2, 2, 0.12)


func _actions_for(u: UnitState) -> Array:
	var out: Array = []
	var my_phase := state.phase == Defs.Phase.PLAYER
	var can_act := my_phase and not u.has_acted
	for sk in u.skills:
		var cd := u.cooldown(sk)
		var label: String = SkillCatalog.get_skill(sk)["name"] + ("（%d）" % cd if cd > 0 else "")
		var act := {"type": "skill", "skill": sk}
		out.append({"label": label, "kind": "target", "action": act,
			"enabled": can_act and cd == 0 and u.grappling_id == "",
			"active": _is_pending(act)})
	if u.has_trait("grapple"):
		if u.grappling_id == "":
			var act := {"type": "grapple"}
			out.append({"label": "擒抱", "kind": "target", "action": act, "enabled": can_act,
				"active": _is_pending(act)})
		else:
			if u.has_trait("slam"):
				var act := {"type": "slam"}
				out.append({"label": "摔投", "kind": "target", "action": act, "enabled": can_act,
					"active": _is_pending(act)})
			out.append({"label": "加固", "kind": "do", "action": {"type": "reinforce"}, "enabled": can_act})
			out.append({"label": "松开", "kind": "do", "action": {"type": "release"}, "enabled": my_phase})
	if u.grappled_by_id != "":
		out.append({"label": "挣扎", "kind": "do", "action": {"type": "struggle"}, "enabled": can_act})
	if u.has_trait("hunter_mark"):
		var act := {"type": "mark"}
		out.append({"label": "标记", "kind": "target", "action": act, "enabled": my_phase and not u.mark_used,
			"active": _is_pending(act)})
	if not state.cave.is_empty():
		for id in state.cave["boulders"]:
			var push := {"type": "push_boulder", "unit": u.id, "target": state.cave["boulders"][id]["pos"]}
			var err := Rules.validate(state, push)
			if err == "" or err == "cannot seal the last entrance":
				out.append({"label": "推巨石", "kind": "do", "action": {"type": "push_boulder", "target": push["target"]},
					"enabled": can_act and err == ""})
	out.append({"label": "待机", "kind": "do", "action": {"type": "wait"}, "enabled": can_act})
	out.append({"label": "朝向", "kind": "facing", "enabled": my_phase and u.grappled_by_id == "",
		"active": _mode == Mode.FACING})
	if state.move_undo.has(u.id):
		out.append({"label": "撤销移动", "kind": "do", "action": {"type": "undo_move"}, "enabled": true})
	return out


func _unit_text(u: UnitState) -> String:
	var lines: Array[String] = []
	var team := "[color=#7fb2ff]我方[/color]" if u.team == Defs.Team.PLAYER else "[color=#ff8c7a]敌方[/color]"
	lines.append("[b]%s[/b]　%s" % [u.display_name, team])
	lines.append("生命 %d/%d　力量 %d　防御 %d　意志 %d" % [maxi(u.hp, 0), u.max_hp, u.strength, u.defense, u.will])
	lines.append("移动 %d　跳跃 %d　高度 %d　朝向 %s" % [u.move, u.jump, state.unit_height(u), _facing_name(u.facing)])
	if u.is_boss():
		lines.append("破势 %d/%d" % [u.stagger, u.stagger_max])
	var st: Array[String] = []
	for s in u.statuses:
		st.append("%s %d" % [EventText.STATUS_NAMES.get(s, s), u.statuses[s]])
	if not st.is_empty():
		lines.append("状态：" + "、".join(st))
	var traits: Array[String] = []
	if u.has_trait("physical_immune"):
		traits.append("物理免疫")
	if u.has_trait("block"):
		traits.append("正面格挡")
	if u.has_trait("cannot_attack_adjacent"):
		traits.append("不能攻击相邻")
	if u.has_trait("forest_stride"):
		traits.append("林地疾行")
	if not traits.is_empty():
		lines.append("[color=#c8b48a]" + "、".join(traits) + "[/color]")
	var learned: Array[String] = []
	for branch in SkillTree.trees().get(u.def_id, []):
		for n in branch["nodes"]:
			if u.has_trait(n.get("trait", "-")) or u.skills.has(n.get("skill", "-")):
				learned.append(n["name"])
	if not learned.is_empty():
		lines.append("[color=#9fd3a0]已学：" + "、".join(learned) + "[/color]")
	if u.has_trait("guest"):
		lines.append("[color=#9a9a9a]客串：倒下后撤离，不会阵亡[/color]")
	if u.post_move > 0:
		lines.append("[color=#9fd3a0]游击：还能移动 %d 格[/color]" % u.post_move)
	if u.team == Defs.Team.PLAYER:
		var done := "已移动" if u.has_moved else "可移动"
		done += "　" + ("已行动" if u.has_acted else "可行动")
		lines.append("[color=#9a9a9a]%s[/color]" % done)
	return "\n".join(lines)


func _facing_name(f: Vector2i) -> String:
	return {Defs.NORTH: "北", Defs.EAST: "东", Defs.SOUTH: "南", Defs.WEST: "西"}.get(f, "?")


func _on_hover() -> void:
	highlights.clear("hover")
	highlights.clear("landing")
	highlights.clear("intent")
	hud.overlay.intent_from = Vector3.INF
	if state == null or _hovered == Defs.NO_POS:
		hud.set_info_text("")
		return
	highlights.show_frame("hover", [_hovered], Color(1, 1, 0.85))
	var at := state.unit_at(_hovered)
	var info: Array[String] = []
	var terrain_names := ["平地", "林地", "浅水", "深水", "沼泽", "燃烧", "冥河"]
	info.append("[color=#c8b48a]格子 (%d, %d)　高度 %d　%s[/color]" % [_hovered.x, _hovered.y,
		state.grid.height_at(_hovered), terrain_names[state.grid.terrain_at(_hovered)]])

	if _mode == Mode.TARGET and _needs_landing():
		info.append("[b]选择落点[/b]（3 格内，最多高 3 层）")
	elif _mode == Mode.TARGET and (at != null or _pending.get("type", "") == "slam"):
		var act := _pending.duplicate()
		act["unit"] = _selected
		act["target"] = _hovered
		var err := Rules.validate(state, act)
		if err == "":
			var p := Rules.preview(state, act)
			info.append("[b]预览[/b]")
			info.append_array(EventText.describe(state, p["events"]))
			for e in p["events"]:
				if e["type"] == "knockback":
					highlights.show_frame("landing", state.unit(e["target"]).footprint(e["to"]), Color(1, 1, 1), 11)
		else:
			info.append("[color=#e88]不能对其使用：%s[/color]" % EventText.error_text(err))
	elif at != null and at.team == Defs.Team.ENEMY and _mode != Mode.BUSY:
		info.append(_unit_text(at))
		var sim := EnemyAI.simulate(state, at)
		info.append("[b]意图（若现在轮到它）[/b]")
		var lines := EventText.describe(state, sim["events"])
		info.append_array(lines if not lines.is_empty() else ["  待机"] as Array[String])
		highlights.show_cells("intent", EnemyAI.threat_cells(state, at), Color(0.95, 0.55, 0.2), 0, 1)
		var act: Dictionary = sim["plan"]["action"]
		if act.get("type", "") == "skill":
			var from: Vector2i = sim["plan"].get("move_to", at.pos)
			hud.overlay.intent_from = map_view.anchor_world(state, from, at.size) + Vector3(0, 0.3, 0)
			var tgt := state.unit_at(act["target"])
			hud.overlay.intent_to = (unit_views[tgt.id] as UnitView).position + Vector3(0, 0.3, 0)
	elif at != null and at.id != _selected:
		info.append(_unit_text(at))
	hud.set_info_text("\n".join(info))


# --- Scripted captures (for automated screenshots) -------------------------------

func _run_capture() -> void:
	await get_tree().process_frame
	match _demo:
		"build":
			pass
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
			tactical = true
			map_view.set_tactical(true)
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
		get_viewport().get_texture().get_image().save_png(_capture_path)
		print("captured ", _capture_path)
	GoEngine.shutdown()
	get_tree().quit()
