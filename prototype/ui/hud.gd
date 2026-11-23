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
## The stamp for each command, from the same set the camp uses. A technique with a drawing
## of its own (the tree's) uses that; these cover the rest.
const ACTION_ART := {"spear":"act_spear","slash":"act_slash","club":"act_slash","heavy_cut":"act_slash","shield_bash":"act_shield",
	"grapple":"act_grapple","reinforce":"act_guard","release":"act_release","struggle":"act_release","wait":"act_wait",
	"facing":"act_facing","face":"act_facing","undo_move":"act_undo","move":"boot","leap":"jump","mark":"act_mark",
	"shoot":"act_shoot","heracles_bow":"act_shoot","bandit_bow":"act_shoot","aimed_shot":"act_shoot","witch_fire":"act_fire",
	"push_boulder":"act_push","trample":"heel_strike","hoof_stomp":"heel_strike","brute_shove":"shield_drive","lance_charge":"phalanx_thrust"}
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
var _bottom: Control  ## holds the three things along the foot of the screen, and the journal
var _card: PanelContainer  ## lower left: who is selected
var _bar: PanelContainer  ## lower middle: what they can do
var _side: PanelContainer  ## lower right: what is about to happen
var _log: PanelContainer
var _figures: HBoxContainer  ## the numbers on the card
## The five things anyone can do, always in the same places: [group, word, drawing].
const GROUPS := [["move","移动","act_move"],["attack","攻击","act_slash"],["skill","技能","skills"],["item","物品","act_item"],["wait","待机","act_wait"]]
var _diamond: DiamondBar  ## the commands, as a diamond that grows facets
var _menu: PanelContainer  ## the card that says what the facet under the mouse does
var _menu_rows: VBoxContainer
var _shown_actions: Array = []
var _detail := -1  ## which command the card describes
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
	_mission_title.toggle_mode = false
	_mission_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.modulate = Color("#d8c499")

	_order_panel = _panel()
	_order_toggle = _toggle_button("","展开或收起敌方行动顺序")
	_order_toggle.clip_text = true
	_order_panel.add_child(_order_toggle)
	_order_toggle.hide()
	_order_scroll = ScrollContainer.new()
	_order_scroll.hide()
	# The enemy's order of play stands in the bar as a row of faces, always in view.
	_order_row = GridContainer.new()
	_order_row.columns = 12
	_order_panel.add_child(_order_row)

	_tools = HBoxContainer.new()
	add_child(_tools)
	_journal = _toggle_button("战报","查看最近的战斗记录")
	_help = _toggle_button("操作","查看键鼠操作")
	_threat = _toggle_button("威胁","显示敌方威胁范围（T）")
	_tactical = _toggle_button("地形","切换战术地形视图（Tab）")
	_threat.toggled.connect(func(on: bool): threat_changed.emit(on))
	_tactical.toggled.connect(func(on: bool): tactical_changed.emit(on))
	menu_button = Button.new()
	menu_button.text = "菜单"
	menu_button.tooltip_text = "战斗菜单（Esc）"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.pressed.connect(func(): menu_pressed.emit())
	# Every tool carries its stamp and its word.
	var tool_art := { _threat:"ui_threat", _tactical:"ui_terrain", _journal:"ui_log", _help:"ui_keys", menu_button:"ui_menu" }
	for button: Button in tool_art:
		button.icon = Px.icon(tool_art[button],32)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_color_override("icon_normal_color",Px.OCHRE)
		button.add_theme_color_override("icon_hover_color",Px.IVORY)
		button.add_theme_color_override("icon_pressed_color",Px.IVORY)
		button.accessibility_name = button.tooltip_text
		_tools.add_child(button)
	_help_label = Label.new()
	_help_label.add_theme_stylebox_override("normal",theme.get_stylebox("panel","PanelContainer"))
	add_child(_help_label)
	_help_label.hide()
	_help.toggled.connect(func(on: bool):
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
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	_figures = HBoxContainer.new()
	identity.add_child(_figures)
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
	_action_box.hide()
	_info_panel = _panel()
	_info_text = _rich()
	var inspector := ScrollContainer.new()
	inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_info_panel.add_child(inspector)
	var assessment := VBoxContainer.new()
	assessment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_child(assessment)
	assessment.minimum_size_changed.connect(func():
		inspector.custom_minimum_size.y = minf(assessment.get_combined_minimum_size().y,get_viewport_rect().size.y*.46)
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
		_log_panel.visible = on
		_update_details()
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
	_end_button.icon = Px.icon("march",32)
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
	# Along the foot of the screen, three separate things with the battlefield between them:
	# who is selected, what they can do, and what is about to happen.
	_bottom = Control.new()
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom)
	_bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = _panel()
	var card_body := VBoxContainer.new()
	_card.add_child(card_body)
	_bar = _panel()
	_side = _panel()
	_log = _panel()
	for box: PanelContainer in [_card,_bar,_side,_log]:
		box.reparent(_bottom,false)
		box.minimum_size_changed.connect(func(): _place_workspace.call_deferred())
	_unit_panel.reparent(card_body,false)
	card_body.add_child(_details)
	_details.hide()
	_action_panel.reparent(_bar,false)
	_info_panel.reparent(_side,false)
	_log_panel.reparent(_log,false)
	for content: Control in [_unit_panel,_action_panel,_info_panel,_log_panel]:
		content.visibility_changed.connect(func(): _place_workspace.call_deferred())
	_context = VBoxContainer.new()
	assessment.add_child(_context)
	_menu = _panel()
	_menu.reparent(_bottom,false)
	_menu_rows = VBoxContainer.new()
	_menu.add_child(_menu_rows)
	_menu.hide()
	_menu.minimum_size_changed.connect(func(): _place_workspace.call_deferred())
	_diamond = DiamondBar.new()
	_bottom.add_child(_diamond)
	_diamond.chosen.connect(func(index: int): action_pressed.emit(index))
	_diamond.cancelled.connect(func(): cancel_pressed.emit())
	_diamond.pointed.connect(_show_detail)
	for section: PanelContainer in [_mission,_order_panel,_unit_panel,_action_panel,_info_panel,_log_panel]:
		section.add_theme_stylebox_override("panel",StyleBoxEmpty.new())


## Shows each of the foot's panels when it has something in it, and sets them in their
## corners: the card at the left, the commands in the middle, the forecast at the right.
func _place_workspace() -> void:
	if _bottom == null or _card == null:
		return
	var reading := journal_open()
	_card.visible = _battle_visible and _unit_panel.visible and not reading
	_diamond.visible = _battle_visible and _action_panel.visible and not reading
	_bar.visible = _diamond.visible and _action_title.get_parent().visible
	_side.visible = _battle_visible and _info_panel.visible and not reading
	_log.visible = _battle_visible and reading
	var margin := Metrics.MARGIN*ui_scale
	var extent := get_viewport_rect().size
	for box: PanelContainer in [_card,_bar,_side,_log]:
		box.size = box.get_combined_minimum_size()
	_card.position = Vector2(margin,extent.y-margin-_card.size.y)
	_side.position = Vector2(extent.x-margin-_side.size.x,extent.y-margin-_side.size.y)
	# The commands are a diamond at the middle of the foot. What the facet under the mouse
	# does, and the line that says what the next click will do, stand to its right.
	_diamond.fit(extent,ui_scale,margin)
	var cluster := _diamond.bounds()
	_menu.visible = _diamond.visible and _detail >= 0
	_menu.size = _menu.get_combined_minimum_size()
	var beside := cluster.end.x+margin
	_bar.position = Vector2(beside,extent.y-margin-_bar.size.y)
	_menu.position = Vector2(beside,extent.y-margin-_menu.size.y)
	for note: PanelContainer in [_bar,_menu]:
		# Where the forecast already stands at the right, sit on top of it.
		if _side.visible and note.position.x+note.size.x > _side.position.x-margin:
			note.position = Vector2(minf(note.position.x,extent.x-margin-note.size.x),_side.position.y-note.size.y-margin*.5)
	_log.size.x = minf(extent.x-2*margin,maxf(_log.size.x,850*ui_scale))
	_log.position = Vector2((extent.x-_log.size.x)*.5,extent.y-margin-_log.size.y)


func _fit_journal() -> void:
	_scroll.custom_minimum_size.y = minf(_feed.get_combined_minimum_size().y,236*ui_scale)
	if _bottom != null:
		_place_workspace.call_deferred()


func _has_context() -> bool:
	return _battle_visible and (_unit_panel.visible or _action_panel.visible or _info_panel.visible)


## The drawing for a command, tinted by whoever draws it.
static func _art(kind: String, size := 32) -> Texture2D:
	var name: String = ACTION_ART.get(kind,kind)
	if not ResourceLoader.exists("res://art/thirdparty/game-icons/%s.svg" % name): name = "skills"
	return Px.icon(name,size)


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
	_top.get_theme_stylebox("panel").set_content_margin_all(Metrics.PADDING*s)
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.offset_left = m
	_top.offset_right = -m
	_top.offset_top = m
	_fit_journal()
	for button: Button in _tools.get_children():
		button.add_theme_constant_override("icon_max_width",roundi(22*s))
		button.custom_minimum_size = Vector2(Metrics.CONTROL,Metrics.CONTROL)*s
		Px.fit(button,roundi(Metrics.CAPTION*s))
	_end_button.add_theme_constant_override("icon_max_width",roundi(28*s))
	for control: Control in [_ready_units,_order_toggle,_mission_title,_end_button]:
		control.custom_minimum_size.y = Metrics.CONTROL*s
	Px.fit(_order_toggle,roundi(Metrics.BODY*s))
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
	_seal.custom_minimum_size = Vector2(84,84)*s
	_seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT,Control.PRESET_MODE_MINSIZE,roundi(5*s))
	_health.custom_minimum_size = Vector2(190,6)*s
	_unit_panel.custom_minimum_size.x = 300*s
	_info_panel.custom_minimum_size.x = 340*s
	_place_workspace.call_deferred()
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


## The frame the selected unit's face sits in.
func _draw_seal() -> void:
	var frame := Rect2(Vector2.ZERO,_seal.size).grow(-1*ui_scale)
	_seal.draw_rect(frame,Px.INK)
	_seal.draw_rect(frame,Px.OCHRE,false,maxf(1.0,2*ui_scale))


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
		var unit_name: String = CombatRecord.participant(state,unit.id).name
		chip.custom_minimum_size = Vector2(Metrics.CONTROL,Metrics.CONTROL)*ui_scale
		var count := unit.actions_left if enemy_phase else unit.actions_per_turn
		var face := TextureRect.new()
		face.texture = Px.face(unit.def_id,32)
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT,Control.PRESET_MODE_MINSIZE,roundi(4*ui_scale))
		var order := Label.new()
		order.text = str(index)
		order.mouse_filter = Control.MOUSE_FILTER_IGNORE
		order.add_theme_color_override("font_outline_color",Px.INK)
		order.add_theme_constant_override("outline_size",roundi(6*ui_scale))
		Px.fit(order,roundi(13*ui_scale))
		chip.add_child(order)
		order.position = Vector2(4,0)*ui_scale
		var leading := unit.id == active if not active.is_empty() else not found_next
		if leading:
			found_next = true
			lead_name = unit_name
			chip.add_theme_stylebox_override("normal",Px.big_box("card_chosen",Vector2(14,6)))
		chip.tooltip_text = "第 %d 位 · %s%s" % [index,unit_name,("　行动中" if not active.is_empty() else "　下一位") if leading else ""]
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
	_order_panel.tooltip_text = _order_summary
	if true:
		return
	var open := false
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
	# The bar carries the goal in one line; the rest is a hover away.
	_objective.text = objective.get_slice("。",0).get_slice("
",0)
	_objective.tooltip_text = objective
	_objective.mouse_filter = Control.MOUSE_FILTER_STOP
	_objective.visible = not objective.is_empty()


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
		_diamond.open_group = ""
		_unit_name.set_pressed_no_signal(false)
		_portrait.texture = Px.face(u.def_id,64)
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
	# The numbers a player reads before every decision, always on the card.
	for child in _figures.get_children():
		_figures.remove_child(child)
		child.queue_free()
	_fill_figures(_figures,u,-1)
	_update_details()


## A unit's numbers as a row of stamps: strength, defence, will, move, jump, and the height
## it stands at when `height` is given.
func _fill_figures(row: HBoxContainer, u: UnitState, height: int) -> void:
	row.add_theme_constant_override("separation",roundi(10*ui_scale))
	var items := [["strength","力量",u.strength],["armor","防御",u.defense],["will","意志",u.will],["boot","移动",u.move],["jump","跳跃",u.jump]]
	if height >= 0: items.append(["ui_terrain","站立高度",height])
	for item: Array in items:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation",roundi(3*ui_scale))
		pair.tooltip_text = item[1]
		pair.mouse_filter = Control.MOUSE_FILTER_STOP
		var stamp := TextureRect.new()
		stamp.texture = Px.icon(item[0],16)
		stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stamp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		stamp.custom_minimum_size = Vector2.ONE*18*ui_scale
		stamp.modulate = Px.OCHRE
		pair.add_child(stamp)
		var number := Label.new()
		number.text = str(item[2])
		Px.fit(number,roundi(Metrics.CAPTION*ui_scale))
		pair.add_child(number)
		row.add_child(pair)


## What is on a unit beyond its numbers: lasting conditions and the traits worth knowing.
func _add_tags(parent: Container, u: UnitState) -> void:
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
	_add_tags(parent,u)


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
	var figures := HBoxContainer.new()
	_context.add_child(figures)
	_fill_figures(figures,u,height)
	# What they are about to do, on a line of its own so it is never cut short.
	var notes := HFlowContainer.new()
	_context.add_child(notes)
	if u.team == Defs.Team.PLAYER:
		notes.add_child(_badge("已移动" if u.has_moved else "可移动",Color("#8eae9d")))
		notes.add_child(_badge("可再移动" if u.post_move>0 else ("已行动" if u.has_acted else "可行动"),Color("#b69a6e")))
	if intent:
		notes.add_child(_badge(intent,Color("#b69a6e")))
	notes.visible = notes.get_child_count() > 0
	_add_tags(_context,u)
	_info_panel.visible = not _help.button_pressed


func set_view_options(threat: bool,tactical: bool) -> void:
	_threat.set_pressed_no_signal(threat)
	_tactical.set_pressed_no_signal(tactical)


## `mode` tells the diamond what is going on: "" | "aim" | "facing".
var _bar_mode := ""

func set_action_context(title: String, can_cancel: bool, mode := "") -> void:
	_bar_mode = mode
	_action_title.text = title
	# The bar needs no heading. A line appears over it only while a target or a facing is
	# being chosen, to say what the next click will do.
	_action_title.get_parent().visible = can_cancel
	# The way back is the diamond's bottom facet, not a word at the end of this line.
	_cancel.visible = false
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


## The commands of whoever is selected, each naming its `group`: move, attack, skill, item,
## wait. They are drawn as a diamond: see DiamondBar.
func set_actions(actions: Array) -> void:
	_shown_actions = actions
	_action_panel.visible = not actions.is_empty()
	_diamond.show_commands(actions,_bar_mode)
	_show_detail(-1)


func _toggle_group(key: String) -> void:
	_diamond.toggle(key)


## Closes the open group of commands. True if there was one to close.
func close_menu() -> bool:
	return _diamond.close()


## A number key: with a group open it picks from the group, otherwise from the four.
func press_key(number: int) -> void:
	_diamond.press_key(number)


## The card beside the diamond: what the command under the mouse does, what it reaches,
## what it waits on.
func _show_detail(index: int) -> void:
	_detail = index if index >= 0 and index < _shown_actions.size() else -1
	for child in _menu_rows.get_children():
		_menu_rows.remove_child(child)
		child.queue_free()
	if _detail < 0:
		_place_workspace.call_deferred()
		return
	var a: Dictionary = _shown_actions[_detail]
	var usable: bool = a.get("enabled",true)
	var waiting := int(a.get("cooldown",0))
	_menu_rows.add_theme_constant_override("separation",roundi(4*ui_scale))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation",roundi(10*ui_scale))
	_menu_rows.add_child(head)
	var icon := TextureRect.new()
	icon.texture = _art(str(a.get("art","")),32)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2.ONE*40*ui_scale
	icon.modulate = Px.OCHRE
	head.add_child(icon)
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation",0)
	head.add_child(title)
	var name_label := Label.new()
	name_label.text = str(a.get("title",a.label))
	Px.fit(name_label,roundi(Metrics.BODY*ui_scale))
	title.add_child(name_label)
	var facts := PackedStringArray()
	if str(a.get("brief","")) != "": facts.append(str(a.brief))
	if int(a.get("recharge",0)) > 0: facts.append("冷却 %d 回合" % int(a.recharge))
	var line := Label.new()
	line.text = "　·　".join(facts)
	line.modulate = Color("#d8c9b0")
	Px.fit(line,roundi(Metrics.CAPTION*ui_scale))
	line.visible = not line.text.is_empty()
	title.add_child(line)
	var words := str(a.get("words",""))
	if words != "":
		var does := Label.new()
		does.text = words
		does.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		does.custom_minimum_size.x = 300*ui_scale
		does.modulate = Color("#bfae98")
		Px.fit(does,roundi(Metrics.CAPTION*ui_scale))
		_menu_rows.add_child(does)
	if waiting > 0 or not usable:
		var state := Label.new()
		state.text = "冷却中，还要 %d 回合" % waiting if waiting > 0 else "现在不能用"
		state.modulate = Color("#e5a580") if waiting > 0 else Color("#8a8076")
		Px.fit(state,roundi(Metrics.CAPTION*ui_scale))
		_menu_rows.add_child(state)
	_place_workspace.call_deferred()


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


## Draws the eye to the end-turn button: everyone has done what they can.
func nudge_end_turn() -> void:
	if _end_button.disabled: return
	_end_button.pivot_offset = _end_button.size*.5
	var pulse := _end_button.create_tween()
	for beat in 2:
		pulse.tween_property(_end_button,"scale",Vector2(1.08,1.08),.16).set_trans(Tween.TRANS_SINE)
		pulse.parallel().tween_property(_end_button,"modulate",Color(1.35,1.25,1.1),.16)
		pulse.tween_property(_end_button,"scale",Vector2.ONE,.2).set_trans(Tween.TRANS_SINE)
		pulse.parallel().tween_property(_end_button,"modulate",Color.WHITE,.2)


func set_turn_command(on: bool, next_battle: String) -> void:
	_end_button.text = {"camp":"返回营地","1-2":"前往林间","1-5":"前往洞穴","reward":"领取狮皮","corinth_map":"返回行军图"}.get(next_battle,"结束回合")
	_end_button.disabled = not on


## Hides battle-only controls (used while the build panel is open).
func set_battle_controls_visible(on: bool) -> void:
	_battle_visible = on
	_top.visible = on
	_bottom.visible = on
	_place_workspace.call_deferred()
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
	var image := TextureRect.new()
	image.texture = Px.face(person.kind,32)
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	if _diamond.covers(screen):
		return true
	for c: Control in [_top,_card,_bar,_side,_log,_help_label]:
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
