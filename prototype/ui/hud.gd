class_name Hud
extends Control
## Native-resolution HUD: phase bar, unit panel, action bar, info / preview panel, battle log.

signal action_pressed(index: int)
signal next_unit_pressed
signal menu_pressed
signal end_turn_pressed
signal threat_changed(on: bool)
signal tactical_changed(on: bool)
signal cancel_pressed
signal order_inspected(unit_id: String)
const MARKS := preload("res://art/original/interface/ceramic_marks.svg")
const ACTION_MARK := {"spear":0,"slash":0,"shield_bash":1,"grapple":2,"wait":3,"facing":4,
	"move":18,"leap":18,"face":4,"undo_move":5,"shoot":6,"leap_shot":6,"heracles_bow":6,"bandit_bow":6,"vital_shot":7,
	"mark":7,"club":13,"slam":13,"release":14,"struggle":14,"reinforce":2,"push_boulder":17}
var enemy_numbers := {}
var _round_numbers := {}
var _queue_round := -1
var _queue_state: BattleState
var acting_enemy := ""
var inspected_enemy := ""
var _order_panel: PanelContainer
var _leading_chip: Button
var _order_row: GridContainer
var _order_scroll: ScrollContainer
var _order_toggle: Button
var _order_summary := ""

const Metrics := preload("res://ui/interface_metrics.gd")
const HELP := "左键 选择/移动/确认　右键 取消　Q/E 旋转　滚轮 缩放　WASD 平移\nT 威胁范围　Tab 战术视图　P 像素化开关　Z 撤销移动　空格 结束回合　R 重开"

var overlay: BattleOverlay
var ui_scale := 1.0

var _mission: PanelContainer
var _mission_title: Button
var _objective: Label
var _tools: HBoxContainer
var _threat: Button
var _tactical: Button
var _action_title: Label
var _cancel: Button
var _forecast: Label
var _journal: Button
var _help: Button
var _seal: Control
var _portrait: TextureRect
var _unit_name: Button
var wheel := preload("res://ui/action_wheel.gd").new()
var _condition: Label
var _vitals: Label
var _health: ProgressBar
var _selected_id := ""
var _phase_label: Label
var _help_label: Label
var _unit_panel: PanelContainer
var _details := VBoxContainer.new()
var _shown_unit: UnitState
var _shown_height := 0
var _hover_dossier := false
var _action_panel: PanelContainer
var _action_box: HFlowContainer
var _info_panel: PanelContainer
var _info_text: RichTextLabel
var _log_panel: PanelContainer
const CombatRecord := preload("res://ui/combat_record.gd")
var _top: PanelContainer
var _bottom: PanelContainer
var _commands: HBoxContainer
var _feed: VBoxContainer
var _scroll: ScrollContainer
var _context: VBoxContainer
var _last_record: Dictionary = {}
var _battle_visible := false
var _ready_units: Button
var menu_button: Button
var _end_button: Button
var _phase_banner := preload("res://ui/phase_banner.gd").new()
var _banner: Label
var _banner_tween: Tween



func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()

	overlay = BattleOverlay.new()
	add_child(overlay)

	_mission = _panel()
	var mission_body := VBoxContainer.new()
	_mission.add_child(mission_body)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",16)
	mission_body.add_child(heading)
	_mission_title = _toggle_button("","展开或收起作战目标")
	_mission_title.button_pressed = false
	heading.add_child(_mission_title)
	_phase_label = Label.new()
	_phase_label.modulate = Color("#d8c499")
	heading.add_child(_phase_label)
	_objective = Label.new()
	mission_body.add_child(_objective)
	_mission_title.toggled.connect(func(on: bool): _objective.visible = on and not _objective.text.is_empty())

	_order_panel = _panel()
	_order_toggle = _toggle_button("","展开或收起敌方行动顺序")
	_order_toggle.clip_text = true
	_order_panel.add_child(_order_toggle)
	_order_toggle.toggled.connect(func(_on: bool): wheel.hide(); _layout_order())
	_order_scroll = ScrollContainer.new()
	_order_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_order_scroll.hide()
	_order_row = GridContainer.new()
	_order_scroll.add_child(_order_row)

	_tools = HBoxContainer.new()
	add_child(_tools)
	_journal = _toggle_button("战报","查看最近的战斗记录")
	_help = _toggle_button("操作","查看键鼠操作")
	_threat = _toggle_button("威胁范围","显示敌方威胁范围（T）")
	_tactical = _toggle_button("地形","切换战术地形视图（Tab）")
	_threat.toggled.connect(func(on: bool): threat_changed.emit(on))
	_tactical.toggled.connect(func(on: bool): tactical_changed.emit(on))
	var tool_marks := { _threat:8, _tactical:9, _journal:10, _help:11 }
	for button: Button in tool_marks:
		button.icon = _mark(tool_marks[button])
		button.text = "操作" if button == _help else ("战报" if button == _journal else "")
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT if button == _help or button == _journal else HORIZONTAL_ALIGNMENT_CENTER
		button.accessibility_name = button.tooltip_text
	_tools.add_child(_threat)
	_tools.add_child(_tactical)
	_tools.add_child(_journal)
	_tools.add_child(_help)
	menu_button = Button.new()
	menu_button.text = "≡"
	menu_button.tooltip_text = "战斗菜单（Esc）"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.pressed.connect(func(): menu_pressed.emit())
	_tools.add_child(menu_button)
	_help_label = Label.new()
	_help_label.add_theme_stylebox_override("normal",theme.get_stylebox("panel","PanelContainer"))
	add_child(_help_label)
	_help_label.hide()
	_help.toggled.connect(func(on: bool):
		wheel.hide()
		_help_label.visible = on
		_info_panel.visible = not on and (not _info_text.text.is_empty() or not _last_record.is_empty() or _context.get_child_count()>0)
	)

	_unit_panel = _panel()
	var unit_body := VBoxContainer.new()
	_unit_panel.add_child(unit_body)
	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation",12)
	unit_body.add_child(summary)
	_seal = Control.new()
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary.add_child(_seal)
	_seal.draw.connect(_draw_seal)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_seal.add_child(_portrait)
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mask := Shader.new()
	mask.code = "shader_type canvas_item; varying vec2 pt; void vertex(){pt=VERTEX;} uniform float diameter; void fragment(){COLOR.a *= 1.0-smoothstep(.41,.43,length(pt/diameter-vec2(.5)));}"
	var ink := ShaderMaterial.new()
	ink.shader = mask
	_portrait.material = ink
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(identity)
	_unit_name = _toggle_button("","展开或收起角色属性")
	identity.add_child(_unit_name)
	_vitals = Label.new()
	identity.add_child(_vitals)
	_health = ProgressBar.new()
	_health.show_percentage = false
	_health.add_theme_stylebox_override("fill",_fill(Color("#d3bc83")))
	_health.add_theme_stylebox_override("background",_fill(Color("#34443e")))
	identity.add_child(_health)
	_condition = Label.new()
	_condition.modulate = Color("#dec39e")
	identity.add_child(_condition)
	_unit_name.toggled.connect(func(_on: bool): _update_details())

	_action_panel = _panel()
	var commands := VBoxContainer.new()
	_action_panel.add_child(commands)
	var context := HBoxContainer.new()
	commands.add_child(context)
	_action_title = Label.new()
	_action_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_title.modulate = Color("#dbccaf")
	context.add_child(_action_title)
	_cancel = Button.new()
	_cancel.text = "取消"
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.flat = true
	_cancel.pressed.connect(func(): cancel_pressed.emit())
	context.add_child(_cancel)
	_action_box = HFlowContainer.new()
	commands.add_child(_action_box)
	_info_panel = _panel()
	_info_text = _rich()
	var inspector := ScrollContainer.new()
	inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_info_panel.add_child(inspector)
	var assessment := VBoxContainer.new()
	assessment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_child(assessment)
	assessment.minimum_size_changed.connect(func():
		inspector.custom_minimum_size.y = minf(assessment.get_combined_minimum_size().y,210*ui_scale)
	)
	_forecast = Label.new()
	_forecast.modulate = Color("#f2c597")
	assessment.add_child(_forecast)
	assessment.add_child(_info_text)
	_log_panel = _panel()
	var journal_body := VBoxContainer.new()
	_log_panel.add_child(journal_body)
	var journal_head := HBoxContainer.new()
	journal_body.add_child(journal_head)
	var journal_title := Label.new()
	journal_title.text = "战斗记录"
	journal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_head.add_child(journal_title)
	var back := Button.new()
	back.text = "返回战场"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): _journal.button_pressed = false)
	journal_head.add_child(back)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	journal_body.add_child(_scroll)
	_feed = VBoxContainer.new()
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_feed)
	_feed.minimum_size_changed.connect(_fit_journal)
	var empty := Label.new()
	empty.text = "本场尚无行动记录"
	_feed.add_child(empty)
	_journal.toggled.connect(func(on: bool):
		wheel.hide()
		_log_panel.visible = on
		_commands.visible = not on
		_update_details()
		_bottom.visible = on or _has_context()
		_place_workspace.call_deferred()
	)

	_ready_units = Button.new()
	_ready_units.flat = true
	_ready_units.focus_mode = Control.FOCUS_NONE
	_ready_units.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ready_units.pressed.connect(func(): next_unit_pressed.emit())
	add_child(_ready_units)
	_end_button = Button.new()
	_end_button.text = "结束回合"
	_end_button.icon = _mark(12)
	_end_button.focus_mode = Control.FOCUS_NONE
	_end_button.add_theme_stylebox_override("normal",Px.big_box("button_primary",Vector2(14,6)))
	_end_button.pressed.connect(func(): end_turn_pressed.emit())
	add_child(_end_button)
	_phase_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_banner.hide()
	add_child(_phase_banner)
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0
	add_child(_banner)

	_top = _panel()
	var strip := HBoxContainer.new()
	var header := VBoxContainer.new()
	_top.add_child(header)
	header.add_child(strip)
	header.add_child(_order_scroll)
	_top.minimum_size_changed.connect(func(): _top.set_deferred("offset_bottom",_top.offset_top+_top.get_combined_minimum_size().y))
	for node in [_mission,_order_panel,_tools,_ready_units,_end_button]:
		node.reparent(strip,false)
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(space)
	strip.move_child(space,_order_panel.get_index()+1)
	_mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_order_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_end_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bottom = _panel()
	_bottom.minimum_size_changed.connect(func(): _place_workspace.call_deferred())
	var body := VBoxContainer.new()
	_bottom.add_child(body)
	_commands = HBoxContainer.new()
	body.add_child(_commands)
	body.add_child(_details)
	_details.hide()
	for node in [_unit_panel,_action_panel,_info_panel]:
		node.reparent(_commands,false)
	_action_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_panel.reparent(body,false)
	_context = VBoxContainer.new()
	assessment.add_child(_context)
	add_child(wheel)
	wheel.chosen.connect(func(index: int): action_pressed.emit(index))
	for section: PanelContainer in [_mission,_order_panel,_unit_panel,_action_panel,_info_panel,_log_panel]:
		section.add_theme_stylebox_override("panel",StyleBoxEmpty.new())


func _place_workspace() -> void:
	if not _bottom.visible:
		return
	var margin := Metrics.MARGIN*ui_scale
	var extent := get_viewport_rect().size
	var needed := _bottom.get_combined_minimum_size()
	var width := extent.x-2*margin
	if journal_open():
		width = minf(width,maxf(needed.x,850*ui_scale))
	elif _hover_dossier and not _unit_panel.visible:
		width = minf(width,maxf(needed.x,760*ui_scale))
	elif _details.visible:
		width = minf(width,maxf(needed.x,1300*ui_scale))
	_bottom.size = Vector2(width,needed.y)
	_bottom.position = Vector2(margin,extent.y-margin-_bottom.size.y)


func _fit_journal() -> void:
	_scroll.custom_minimum_size.y = minf(_feed.get_combined_minimum_size().y,236*ui_scale)
	if _bottom != null:
		_place_workspace.call_deferred()


func _has_context() -> bool:
	return _battle_visible and (_unit_panel.visible or _action_panel.visible or _info_panel.visible)


func apply_scale(window: Vector2) -> void:
	ui_scale = clampf(minf(window.y / 980.0,window.x / 1536.0), 0.58, 1.8)
	var s := ui_scale
	var m := Metrics.MARGIN*s
	Px.fit(_condition,roundi(Metrics.CAPTION*s))
	theme.default_font_size = 24
	Px.fit(_help_label,roundi(Metrics.CAPTION*s))
	Px.fit(_phase_label,roundi(Metrics.CAPTION*s))
	Px.fit(_mission_title,roundi(Metrics.TITLE*s))
	Px.fit(_unit_name,roundi(Metrics.TITLE*s))
	Px.fit(_forecast,roundi(Metrics.TITLE*s))
	Px.fit(_action_title,roundi(Metrics.CAPTION*s))
	Px.fit(_vitals,roundi(Metrics.CAPTION*s))
	Px.fit(_objective,roundi(Metrics.CAPTION*s))
	Px.fit(_banner,int(40*s))
	for panel in [_top,_bottom]:
		panel.get_theme_stylebox("panel").set_content_margin_all(Metrics.PADDING*s)
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.offset_left = m
	_top.offset_right = -m
	_top.offset_top = m
	_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom.offset_left = m
	_bottom.offset_right = -m
	_bottom.offset_bottom = -m
	_commands.add_theme_constant_override("separation",roundi(Metrics.CAPTION*s))
	_fit_journal()
	for button: Button in _tools.get_children():
		button.add_theme_constant_override("icon_max_width",roundi(30*s))
		button.custom_minimum_size = Vector2(Metrics.CONTROL,Metrics.CONTROL)*s
	_end_button.add_theme_constant_override("icon_max_width",roundi(28*s))
	for control: Control in [_ready_units,_order_toggle,_mission_title,_end_button]:
		control.custom_minimum_size.y = Metrics.CONTROL*s
	Px.fit(_order_toggle,roundi(Metrics.BODY*s))
	_order_toggle.custom_minimum_size.x = 420*s
	var gap := roundi(Metrics.GAP*s)
	for container in ["HBoxContainer","VBoxContainer"]:
		theme.set_constant("separation",container,gap)
	for container in ["GridContainer","HFlowContainer"]:
		theme.set_constant("h_separation",container,gap)
		theme.set_constant("v_separation",container,gap)
	for key in ["normal","hover","pressed","disabled"]:
		var button_box := theme.get_stylebox(key,"Button")
		button_box.content_margin_left = Metrics.PADDING*s
		button_box.content_margin_right = Metrics.PADDING*s
		button_box.content_margin_top = 4*s
		button_box.content_margin_bottom = 4*s
	_layout_order()
	_dock(_help_label,Control.PRESET_TOP_RIGHT,Control.GROW_DIRECTION_BEGIN,Control.GROW_DIRECTION_END,Vector2(-m,128*s))
	_seal.custom_minimum_size = Vector2(98,98)*s
	_seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(_portrait.material as ShaderMaterial).set_shader_parameter("diameter",98*s)
	_health.custom_minimum_size.y = 5*s
	_unit_panel.custom_minimum_size.x = 215*s
	_action_box.custom_minimum_size.x = minf(700*s,window.x*.46)
	_info_panel.custom_minimum_size.x = 340*s
	_info_text.custom_minimum_size.x = 310*s
	_end_button.custom_minimum_size = Vector2(152,Metrics.CONTROL)*s
	_phase_banner.fit(window, s)
	_banner.size = Vector2(window.x, 120 * s)
	_banner.position = Vector2(0, window.y * 0.3)


## Anchors `c` to a corner preset with zero size; it then grows from that corner by its minimum size.
func _dock(c: Control, preset: int, grow_h: int, grow_v: int, offset: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.grow_horizontal = grow_h
	c.grow_vertical = grow_v
	c.offset_left = offset.x
	c.offset_right = offset.x
	c.offset_top = offset.y
	c.offset_bottom = offset.y


func _draw_seal() -> void:
	var center := _seal.size*.5
	var r := minf(center.x,center.y)-2*ui_scale
	_seal.draw_circle(center,r,Color("#ad7554"),true,-1,true)
	_seal.draw_circle(center,r-2*ui_scale,Color("#322521"),true,-1,true)
	_seal.draw_circle(center,r*.85,Color("#874c38"),true,-1,true)
	for side: int in [-1,1]:
		for i in 7:
			var angle := PI*.48+i*.19*side
			var tip := Vector2.from_angle(angle)
			var leaf := center+tip*r*.92
			_seal.draw_line(leaf,leaf+tip.rotated(.8*side)*ui_scale*3.4,Color("#e4be85"),2*ui_scale,true)


static func _mark(index: int) -> AtlasTexture:
	var tile := AtlasTexture.new()
	tile.atlas = MARKS
	tile.region = Rect2(index%9*48,index/9*48,48,48)
	return tile


func set_enemy_order(state: BattleState, active: String, finished: bool) -> void:
	_leading_chip = null
	acting_enemy = active
	enemy_numbers.clear()
	inspected_enemy = ""
	for child in _order_row.get_children():
		_order_row.remove_child(child)
		child.queue_free()
	var enemy_phase := state.phase == Defs.Phase.ENEMY
	var lead_name := ""
	if state != _queue_state or state.round_number != _queue_round:
		_round_numbers.clear()
		_queue_state = state
		_queue_round = state.round_number
	var found_next := false
	for unit in state.living(Defs.Team.ENEMY):
		if unit.hidden or (enemy_phase and unit.actions_left <= 0) or (not enemy_phase and unit.has_status("stunned")):
			continue
		if not _round_numbers.has(unit.id):
			_round_numbers[unit.id] = _round_numbers.size()+1
		var index: int = _round_numbers[unit.id]
		enemy_numbers[unit.id] = index
		var chip := Button.new()
		chip.focus_mode = Control.FOCUS_NONE
		chip.toggle_mode = true
		chip.set_pressed_no_signal(unit.id == active)
		chip.text = CombatRecord.participant(state,unit.id).name
		var unit_name := chip.text
		chip.text = "%02d   %s" % [index,unit_name]
		chip.clip_text = true
		chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
		chip.custom_minimum_size = Vector2(Metrics.CARD_WIDTH,Metrics.CONTROL)*ui_scale
		Px.fit(chip,roundi(Metrics.CAPTION*ui_scale))
		var count := unit.actions_left if enemy_phase else unit.actions_per_turn
		if count > 1:
			chip.text += " · %d动" % count
		chip.icon = _mark(15 if unit.def_id == "wolf" else 16)
		if unit.def_id != "wolf":
			var portrait := AtlasTexture.new()
			portrait.atlas = load("res://art/original/actors/%s.png" % unit.def_id)
			portrait.region = Rect2(50,26,220,210)
			chip.icon = portrait
		chip.add_theme_constant_override("icon_max_width",roundi(30*ui_scale))
		var leading := unit.id == active if not active.is_empty() else not found_next
		if leading:
			found_next = true
			lead_name = unit_name
			chip.text += "　行动中" if not active.is_empty() else "　下一位"
			chip.add_theme_stylebox_override("normal",Px.big_box("card_chosen",Vector2(14,6)))
		chip.tooltip_text = "第 %d 位 · %s" % [index,unit_name]
		if count > 1:
			chip.tooltip_text += " · 本回合 %d 次行动" % count
		chip.mouse_entered.connect(_inspect_enemy.bind(unit.id))
		chip.mouse_exited.connect(_inspect_enemy.bind(""))
		chip.pressed.connect(func():
			chip.set_pressed_no_signal(unit.id == acting_enemy)
			_inspect_enemy(unit.id)
		)
		_order_row.add_child(chip)
		if leading:
			_leading_chip = chip
			_reveal_leading_chip.call_deferred()
	_order_panel.visible = not enemy_numbers.is_empty() and not finished
	_order_summary = "本回合敌方 %d" % enemy_numbers.size()
	if not lead_name.is_empty():
		_order_summary += (" · 行动中 " if not active.is_empty() else " · 下一位 ") + lead_name
	else:
		_order_summary += "　·　行动顺序"
	_layout_order()


func _layout_order() -> void:
	var open := _order_toggle.button_pressed and _order_panel.visible
	_order_toggle.text = _order_summary + ("　▴" if open else "　▾")
	_order_scroll.visible = open
	if not open:
		return
	var available := get_viewport_rect().size.x/ui_scale-2*(Metrics.MARGIN+Metrics.PADDING)-24
	_order_row.columns = maxi(1,floori((available+Metrics.GAP)/(Metrics.CARD_WIDTH+Metrics.GAP)))
	var rows := mini(3,ceili(float(_order_row.get_child_count())/_order_row.columns))
	_order_scroll.custom_minimum_size.y = rows*ceilf(Metrics.CONTROL*ui_scale)+maxi(0,rows-1)*roundi(Metrics.GAP*ui_scale)+2
	_reveal_leading_chip.call_deferred()


func close_order() -> bool:
	if not _order_scroll.is_visible_in_tree():
		return false
	_order_toggle.button_pressed = false
	_inspect_enemy("")
	return true


func _reveal_leading_chip() -> void:
	if _order_scroll.is_visible_in_tree() and is_instance_valid(_leading_chip):
		_order_scroll.ensure_control_visible(_leading_chip)


func _inspect_enemy(id: String) -> void:
	inspected_enemy = id
	order_inspected.emit(id)


func set_mission(title: String, phase: String, objective: String) -> void:
	_mission_title.flat = true
	_mission_title.text = title
	_mission_title.disabled = objective.is_empty()
	_phase_label.text = phase
	_mission_title.tooltip_text = objective
	_objective.text = objective
	_objective.visible = _mission_title.button_pressed and not objective.is_empty()


func set_help_visible(on: bool, painted := false) -> void:
	_help.visible = on
	_help_label.text = ("数字键 1–9 选择行动\n"+HELP).replace("P 像素化开关　","") if painted else "数字键 1–9 选择行动\n"+HELP
	_help_label.visible = on and _help.button_pressed


func set_unit(u: UnitState, height: int, resolving: bool) -> void:
	overlay.resolving = resolving
	_shown_unit = u
	_shown_height = height
	_unit_panel.visible = u != null
	if u == null:
		_selected_id = ""
		_details.hide()
		return
	if _selected_id != u.id:
		_selected_id = u.id
		_unit_name.set_pressed_no_signal(false)
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://art/original/actors/%s.png" % u.def_id)
		var top: int = {"hero":64,"atalanta":48,"heracles":82}.get(u.def_id,32)
		atlas.region = Rect2(133,top+4,62,62)
		_portrait.texture = atlas
	_unit_name.flat = true
	_unit_name.text = u.display_name + "  ▾"
	_vitals.text = "生命  %d / %d" % [maxi(u.hp,0),u.max_hp]
	_health.max_value = u.max_hp
	_health.value = u.hp
	var availability := "已行动" if u.has_acted else "可行动"
	if u.has_acted and u.post_move > 0:
		availability = "可再移动"
	var conditions := PackedStringArray()
	if not u.grappled_by_id.is_empty():
		conditions.append("被擒抱")
	for status in u.statuses:
		conditions.append(EventText.STATUS_NAMES.get(status,status))
	_condition.text = "行动中" if resolving else ("已移动" if u.has_moved else "可移动")+" · "+availability
	if not conditions.is_empty():
		_condition.text += " · "+conditions[0]
		if conditions.size() > 1:
			_condition.text += " +%d" % (conditions.size()-1)
	_condition.tooltip_text = "、".join(conditions)
	_update_details()


func _update_details() -> void:
	_details.visible = _shown_unit != null and _unit_name.button_pressed and not journal_open()
	if _shown_unit == null:
		return
	_unit_name.text = _shown_unit.display_name + ("  ▴" if _details.visible else "  ▾")
	if _details.visible:
		for child in _details.get_children():
			_details.remove_child(child)
			child.queue_free()
		_add_attributes(_details,_shown_unit,_shown_height,false)
	_place_workspace.call_deferred()


func _badge(text_value: String, accent: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	var backing := _fill(Color("#392d27"))
	backing.border_width_left = maxi(2,roundi(3*ui_scale))
	backing.border_color = accent
	backing.set_content_margin_all(4*ui_scale)
	backing.content_margin_left = 10*ui_scale
	backing.content_margin_right = 10*ui_scale
	label.add_theme_stylebox_override("normal",backing)
	Px.fit(label,roundi(Metrics.CAPTION*ui_scale))
	return label


func _stat_group(parent: Container, title: String, items: Array) -> void:
	var panel := PanelContainer.new()
	var style := _fill(Color("#382c26"))
	style.set_content_margin_all(8*ui_scale)
	style.border_width_top = maxi(1,roundi(2*ui_scale))
	style.border_color = Color("#a57951")
	panel.add_theme_stylebox_override("panel",style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var group := VBoxContainer.new()
	panel.add_child(group)
	var heading := Label.new()
	heading.text = title
	heading.modulate = Color("#d9b790")
	Px.fit(heading,roundi(Metrics.CAPTION*ui_scale))
	group.add_child(heading)
	var row := HBoxContainer.new()
	group.add_child(row)
	for item: Array in items:
		var field := VBoxContainer.new()
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.add_theme_constant_override("separation",0)
		row.add_child(field)
		var measure := HBoxContainer.new()
		measure.add_theme_constant_override("separation",roundi(4*ui_scale))
		field.add_child(measure)
		var icon := TextureRect.new()
		icon.texture = _mark(item[1])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2.ONE*23*ui_scale
		measure.add_child(icon)
		var number := Label.new()
		number.text = str(item[2])
		Px.fit(number,roundi(Metrics.TITLE*ui_scale))
		measure.add_child(number)
		var label := Label.new()
		label.text = item[0]
		label.modulate = Color("#d7c6af")
		Px.fit(label,roundi(Metrics.CAPTION*ui_scale))
		field.add_child(label)


func _add_attributes(parent: VBoxContainer, u: UnitState, height: int, compact: bool) -> void:
	var groups: BoxContainer = VBoxContainer.new() if compact else HBoxContainer.new()
	parent.add_child(groups)
	var facing: String = {Defs.NORTH:"北",Defs.EAST:"东",Defs.SOUTH:"南",Defs.WEST:"西"}.get(u.facing,"—")
	_stat_group(groups,"战斗属性",[["力量",0,u.strength],["防御",1,u.defense],["意志",19,u.will]])
	_stat_group(groups,"机动与站位",[["移动",18,u.move],["跳跃",20,u.jump],["高度",9,height],["朝向",21,facing]])
	var tags := HFlowContainer.new()
	parent.add_child(tags)
	if u.team == Defs.Team.PLAYER and u.post_move > 0 and not overlay.resolving:
		tags.add_child(_badge("可再移动 %d 格" % u.post_move,Color("#8eae9d")))
	if u.is_boss():
		tags.add_child(_badge("破势 %d/%d" % [u.stagger,u.stagger_max],Color("#bc8258")))
	for status in u.statuses:
		tags.add_child(_badge("%s · %d" % [EventText.STATUS_NAMES.get(status,status),u.statuses[status]],Color("#c7896b")))
	var traits := {"physical_immune":"物理免疫","block":"正面格挡","cannot_attack_adjacent":"不能攻击相邻","forest_stride":"林地疾行","guest":"倒下后撤离"}
	for key in traits:
		if u.has_trait(key):
			tags.add_child(_badge(traits[key],Color("#b69a6e")))
	tags.visible = tags.get_child_count() > 0


func show_unit_inspection(u: UnitState, height: int, intent: String) -> void:
	_clear_context()
	_hover_dossier = true
	_place_workspace.call_deferred()
	_info_text.hide()
	_forecast.hide()
	var header := HFlowContainer.new()
	_context.add_child(header)
	header.add_child(_person_chip({"kind":u.def_id,"name":u.display_name}))
	header.add_child(_badge("我方" if u.team == Defs.Team.PLAYER else "敌方",Color("#86ac97") if u.team == Defs.Team.PLAYER else Color("#c97b5d")))
	var vital := VBoxContainer.new()
	vital.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vital.add_theme_constant_override("separation",roundi(2*ui_scale))
	header.add_child(vital)
	var hp := Label.new()
	hp.text = "生命  %d / %d" % [maxi(0,u.hp),u.max_hp]
	Px.fit(hp,roundi(Metrics.CAPTION*ui_scale))
	vital.add_child(hp)
	var meter := ProgressBar.new()
	meter.show_percentage = false
	meter.max_value = u.max_hp
	meter.value = u.hp
	meter.custom_minimum_size = Vector2(104,5)*ui_scale
	for state_name in ["fill","background"]:
		var bar_style := _fill(Color("#cfb482") if state_name=="fill" else Color("#53433b"))
		bar_style.set_content_margin_all(0)
		meter.add_theme_stylebox_override(state_name,bar_style)
	vital.add_child(meter)
	if u.team == Defs.Team.PLAYER:
		header.add_child(_badge("已移动" if u.has_moved else "可移动",Color("#8eae9d")))
		header.add_child(_badge("可再移动" if u.post_move>0 else ("已行动" if u.has_acted else "可行动"),Color("#b69a6e")))
	if intent:
		header.add_child(_badge(intent,Color("#b69a6e")))
	_add_attributes(_context,u,height,_unit_panel.visible)
	_info_panel.visible = not _help.button_pressed
	_bottom.visible = journal_open() or _has_context()


func set_view_options(threat: bool,tactical: bool) -> void:
	_threat.set_pressed_no_signal(threat)
	_tactical.set_pressed_no_signal(tactical)


func set_action_context(title: String, can_cancel: bool) -> void:
	_action_title.text = title
	_cancel.visible = can_cancel
	_end_button.flat = can_cancel


func set_info_text(bbcode: String,forecast := "") -> void:
	_clear_context()
	_forecast.text = forecast
	_forecast.visible = not forecast.is_empty()
	_info_text.text = bbcode
	_info_text.visible = not bbcode.is_empty()
	if bbcode.is_empty() and not _last_record.is_empty():
		_show_record(_last_record,"最近行动")
	_info_panel.visible = not _help.button_pressed and (_context.get_child_count()>0 or not bbcode.is_empty())
	_bottom.visible = _journal.button_pressed or _has_context()


func _clear_context() -> void:
	if _hover_dossier:
		_hover_dossier = false
		_place_workspace.call_deferred()
	overlay.forecasts.clear()
	for child in _context.get_children():
		_context.remove_child(child)
		child.queue_free()


func _show_record(row: Dictionary, caption: String) -> void:
	_forecast.text = caption
	_forecast.show()
	_context.add_child(_record_line(row,false))


func preview_records(state: BattleState,events: Array,caption := "行动预览　·　左键确认", on_map := false) -> void:
	var rows := CombatRecord.collect(state,events)
	if rows.is_empty():
		return
	_clear_context()
	_info_text.hide()
	_forecast.text = caption
	_forecast.show()
	for row in rows:
		if on_map and not row.target_id.is_empty() and (row.after >= 0 or not row.outcome.is_empty()):
			overlay.set_health_forecast(row)
		_context.add_child(_record_line(row,false))
	_info_panel.show()
	_bottom.show()


func open_wheel(actions: Array, unit_anchor: Callable) -> void:
	var entries := [{},{},{},{}]
	var skill_count := 0
	for i in actions.size():
		var item: Dictionary = actions[i]
		var command: Dictionary = item.get("action",{})
		var key: String = command.get("skill",command.get("type",""))
		var slot := -1
		if command.has("skill"):
			if skill_count < 2:
				slot = skill_count
			skill_count += 1
		elif key == "wait":
			slot = 2
		elif key in ["grapple","mark","struggle","slam","release"] and entries[3].is_empty():
			slot = 3
		if slot >= 0:
			entries[slot] = {"index":i,"label":item.label,"icon":_mark(ACTION_MARK.get(key,16)),
				"enabled":item.get("enabled",true),"cooldown":item.get("cooldown",0)}
	var area := get_viewport_rect().grow(-8*ui_scale)
	var bottom := _bottom.position.y if _bottom.visible else area.end.y
	area.position.y = _top.get_global_rect().end.y+8*ui_scale
	area.size.y = bottom-area.position.y-8*ui_scale
	wheel.open(entries,unit_anchor,area,ui_scale)


## actions: [{label, enabled, active}]
func set_actions(actions: Array) -> void:
	for c in _action_box.get_children():
		_action_box.remove_child(c)
		c.queue_free()
	_action_panel.visible = not actions.is_empty()
	_action_box.custom_minimum_size.x = minf(700.0,actions.size()*104.0)*ui_scale
	for i in actions.size():
		var a: Dictionary = actions[i]
		var b := Button.new()
		b.accessibility_name = a["label"]
		b.tooltip_text = a["label"]
		var command: Dictionary = a.get("action",{})
		var kind: String = command.get("skill",command.get("type",a["kind"]))
		var utility := kind in ["wait","facing","undo_move"]
		b.flat = utility and not a.get("active",false)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = _mark(ACTION_MARK.get(kind,16))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		b.add_child(icon)
		icon.offset_left = -16*ui_scale
		icon.offset_right = 16*ui_scale
		icon.offset_top = 9*ui_scale
		icon.offset_bottom = 41*ui_scale
		var caption := Label.new()
		caption.text = a["label"]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		Px.fit(caption,roundi(Metrics.CAPTION*ui_scale))
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(caption)
		caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		caption.offset_left = 3*ui_scale
		caption.offset_right = -3*ui_scale
		caption.offset_top = -30*ui_scale
		caption.offset_bottom = -4*ui_scale
		if not a.get("enabled",true):
			icon.modulate = Color("#a59b90")
			caption.modulate = icon.modulate
		var cooldown: int = a.get("cooldown",0)
		if cooldown > 0:
			var timer := Label.new()
			timer.text = str(cooldown)
			timer.modulate = Color("#e5a580")
			timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			Px.fit(timer,roundi(13*ui_scale))
			b.add_child(timer)
			timer.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			timer.offset_left = -23*ui_scale
			timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.tooltip_text += " · 冷却 %d 回合" % cooldown
		if i < 9:
			var shortcut := Label.new()
			shortcut.text = str(i+1)
			shortcut.position = Vector2(5,1)*ui_scale
			shortcut.modulate = Color("#cfad89")
			Px.fit(shortcut,roundi(13*ui_scale))
			shortcut.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(shortcut)
		b.disabled = not a.get("enabled", true)
		b.toggle_mode = true
		b.button_pressed = a.get("active", false)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(96,Metrics.ACTION) * ui_scale
		b.pressed.connect(func(): action_pressed.emit(i))
		_action_box.add_child(b)


func journal_open() -> bool:
	return _journal.button_pressed


func close_journal() -> void:
	_journal.button_pressed = false


func set_available_units(count: int, movers: int, available: bool) -> void:
	_ready_units.visible = available
	_ready_units.disabled = count+movers == 0
	_ready_units.text = "%d 可行动" % count
	if movers:
		_ready_units.text += " · %d 可再移动" % movers
	_ready_units.tooltip_text = "选择并定位下一名可行动或可再移动的角色"


func set_turn_command(on: bool, next_battle: String) -> void:
	_end_button.text = {"camp":"返回营地","1-2":"前往林间","1-5":"前往洞穴","reward":"领取狮皮","corinth_map":"返回行军图"}.get(next_battle,"结束回合")
	_end_button.disabled = not on


## Hides battle-only controls (used while the build panel is open).
func set_battle_controls_visible(on: bool) -> void:
	_battle_visible = on
	_top.visible = on
	_bottom.visible = on and (_journal.button_pressed or _has_context())
	_end_button.visible = on
	_mission.visible = on
	_tools.visible = on


func record_events(state: BattleState,events: Array,from_round := -1) -> void:
	var exchange: VBoxContainer
	for row in CombatRecord.collect(state,events,from_round):
		if exchange != null and row.linked:
			exchange.add_child(_record_line(row,true))
			_last_record = row
			continue
		if _last_record.is_empty():
			_feed.get_child(0).free()
		_last_record = row
		var entry := _record_line(row,true)
		exchange = entry
		entry.set_meta("round",row.round)
		var heading := Label.new()
		heading.text = "第 %d 回合" % row.round
		heading.modulate = Color("#dfbc89")
		entry.add_child(heading)
		entry.move_child(heading,0)
		if _feed.get_child_count() and _feed.get_child(0).get_meta("round") == row.round:
			_feed.get_child(0).get_child(0).hide()
		_feed.add_child(entry)
		_feed.move_child(entry,0)
		if _feed.get_child_count()>60:
			_feed.get_child(-1).free()


func _person_chip(person: Dictionary) -> HBoxContainer:
	var chip := HBoxContainer.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://art/original/actors/%s.png" % person.kind)
	var crop := Rect2(125,42,82,86)
	match person.kind:
		"hero": crop = Rect2(133,68,62,62)
		"wolf": crop = Rect2(69,102,95,95)
		"heracles": crop = Rect2(131,84,70,70)
		"lion","boar": crop = Rect2(65,70,120,120)
	atlas.region = crop
	var image := TextureRect.new()
	image.texture = atlas
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(38,40)*ui_scale
	chip.add_child(image)
	var name_label := Label.new()
	name_label.text = person.name
	chip.add_child(name_label)
	return chip


func _record_line(row: Dictionary, history: bool) -> VBoxContainer:
	var card := VBoxContainer.new()
	var line: Container
	if history:
		line = HBoxContainer.new()
		line.add_theme_constant_override("separation",roundi(10*ui_scale))
		var backing := PanelContainer.new()
		var style := _fill(Color("#352a25"))
		style.border_color = Color("#b87750") if row.after >= 0 else Color("#7e765e")
		style.border_width_left = 3
		style.content_margin_left = 14*ui_scale
		backing.add_theme_stylebox_override("panel",style)
		card.add_child(backing)
		backing.add_child(line)
	else:
		line = HFlowContainer.new()
		card.add_child(line)
	if not row.actor.is_empty():
		var actor_chip := _person_chip(row.actor)
		line.add_child(actor_chip)
	elif history:
		var environment := Label.new()
		environment.text = "战场"
		environment.modulate = Color("#dfbc89")
		line.add_child(environment)
	var move := Button.new()
	move.icon = _mark(ACTION_MARK.get(row.cause,15 if row.cause=="bite" else 4))
	move.add_theme_constant_override("icon_max_width",int(24*ui_scale))
	move.text = row.title
	move.flat = true
	move.focus_mode = Control.FOCUS_NONE
	move.tooltip_text = "\n".join(row.details)
	move.add_theme_constant_override("h_separation",roundi(5*ui_scale))
	line.add_child(move)
	if not row.target.is_empty():
		var arrow := Label.new()
		arrow.text = "›"
		line.add_child(arrow)
		var target_chip := _person_chip(row.target)
		line.add_child(target_chip)
	var result := Label.new()
	result.text = "　".join(PackedStringArray([row.direction,row.outcome])).strip_edges()
	if history and row.cause == "move":
		result.hide()
	result.modulate = Color("#f5b18a")
	line.add_child(result)
	if row.after >= 0:
		var hp_line := HBoxContainer.new()
		if history:
			line.add_child(hp_line)
		else:
			card.add_child(hp_line)
		var hp := ProgressBar.new()
		hp.custom_minimum_size = Vector2(92,7)*ui_scale
		hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hp.show_percentage = false
		hp.max_value = row.target.get("max_hp",row.before)
		hp.value = row.after
		hp.add_theme_stylebox_override("fill",_fill(Color("#cd8b63")))
		hp.add_theme_stylebox_override("background",_fill(Color("#4b3831")))
		hp_line.add_child(hp)
		var numbers := Label.new()
		numbers.text = "生命  %d → %d" % [row.before,row.after]
		hp_line.add_child(numbers)
	if not row.details.is_empty():
		var details := Label.new()
		details.text = "\n".join(row.details)
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.hide()
		card.add_child(details)
		move.text += "  ▾"
		move.pressed.connect(func(): details.visible = not details.visible)
	else:
		move.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return card


func announce_phase(number: int, player_turn: bool) -> void:
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0
	_phase_banner.present(number, player_turn, _mark(1 if player_turn else 8))
	_phase_banner.show()
	_phase_banner.modulate.a = 0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_phase_banner, "modulate:a", 1.0, 0.12)
	_banner_tween.tween_interval(1.15)
	_banner_tween.tween_property(_phase_banner, "modulate:a", 0.0, 0.25)
	_banner_tween.tween_callback(_phase_banner.hide)


func banner(text: String, hold: float = 0.9) -> void:
	_phase_banner.hide()
	_banner.text = text
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.15)
	if hold > 0.0:
		_banner_tween.tween_interval(hold)
		_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.3)


func is_over_panel(screen: Vector2) -> bool:
	for c: Control in [_top,_bottom,_help_label]:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(screen):
			return true
	return false


func show_rescue_result(state: BattleState, retry: Callable, travel: Callable, campaign := false) -> void:
	var card := _panel()
	card.show()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var body := VBoxContainer.new()
	card.custom_minimum_size.x = 360 * ui_scale
	var margins := MarginContainer.new()
	for edge in ["top", "bottom", "left", "right"]:
		margins.add_theme_constant_override("margin_" + edge, roundi(18 * ui_scale))
	card.add_child(margins)
	margins.add_child(body)
	body.add_theme_constant_override("separation", roundi(9 * ui_scale))
	var title := Label.new()
	title.text = "林道已肃清"
	Px.fit(title,roundi(34*ui_scale))
	body.add_child(title)
	var travelers: Array[UnitState] = []
	var safe := 0
	for id in state.order:
		var person := state.unit(id)
		if person.def_id == "refugee":
			travelers.append(person)
			if person.hidden and person.alive:
				safe += 1
	var success := safe >= 2
	body.add_child(_badge("%s　%d / %d 人撤离" % ["护送达成" if success else "护送不足",safe,travelers.size()],Color("#83beaa") if success else Color("#d79368")))
	for person in travelers:
		var row := HBoxContainer.new()
		body.add_child(row)
		var chip := _person_chip({"kind":person.def_id,"name":person.display_name})
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(chip)
		var status := Label.new()
		status.text = "已撤离" if person.hidden else ("仍在林道" if person.alive else "遇难")
		row.add_child(status)
	if campaign:
		_travel_button(body,"在地图上选择路线","1-4",travel)
	else:
		if success:
			_travel_button(body,"跟随村民前往福洛厄山","1-3",travel)
		_travel_button(body,"前往涅墨亚山谷","1-4",travel)
	var restart := Button.new()
	restart.text = "重打本关"
	restart.pressed.connect(retry)
	body.add_child(restart)


func show_feast_result(saved: bool, travel: Callable) -> void:
	var card := _panel()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",roundi(10*ui_scale))
	var padding := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		padding.add_theme_constant_override("margin_"+side,roundi(16*ui_scale))
	card.add_child(padding)
	padding.add_child(body)
	body.custom_minimum_size.x = roundi(300*ui_scale)
	body.add_child(_person_chip({"kind":"chiron","name":"喀戎"}))
	body.add_child(_badge("喀戎加入队伍" if saved else "喀戎负伤离开",Color("#9dd5ba") if saved else Color("#d79368")))
	_travel_button(body,"前往涅墨亚山谷","1-4",travel)
	_travel_button(body,"重打宴地","1-3",travel)
	card.show()


func _travel_button(body: VBoxContainer, caption: String, battle: String, travel: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(travel.bind(battle))
	body.add_child(button)


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", theme.get_stylebox("panel", "PanelContainer").duplicate())
	p.draw.connect(func():
		if p != _top and p != _bottom:
			return
		var u := maxf(1.0,ui_scale*1.6)
		var x := p.size.x-8*u
		var y := p.size.y-3*u
		for j in 3:
			p.draw_polyline(PackedVector2Array([Vector2(x,y),Vector2(x-5*u,y),Vector2(x-5*u,y-3*u),
				Vector2(x-2*u,y-3*u),Vector2(x-2*u,y-u)]),Color("#b78354"),u)
			x -= 7*u
	)
	p.visible = false
	add_child(p)
	return p


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _toggle_button(caption: String, tip: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.tooltip_text = tip
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	return button


static func _fill(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(6)
	return box


static func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = Px.font(24)
	t.default_font_size = 24
	t.set_stylebox("panel", "PanelContainer", Px.big_box("panel",Vector2(14,12)))
	for state in ["normal","hover","pressed","disabled"]:
		t.set_stylebox(state, "Button", Px.big_box("button" if state == "normal" else "button_"+state,Vector2(14,6)))
	t.set_stylebox("focus", "Button", Px.big_box("focus",Vector2(14,6)))
	t.set_color("font_color", "Button", Px.IVORY)
	t.set_color("font_hover_color", "Button", Px.IVORY)
	t.set_color("font_color", "Label", Px.IVORY)
	t.set_stylebox("hover_pressed", "Button", t.get_stylebox("pressed", "Button"))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.48, 0.44))
	t.set_color("font_pressed_color", "Button", Color(1, 0.95, 0.8))
	return t
