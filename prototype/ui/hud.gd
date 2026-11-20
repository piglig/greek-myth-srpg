class_name Hud
extends Control
## Native-resolution HUD: phase bar, unit panel, action bar, info / preview panel, battle log.

signal action_pressed(index: int)
signal end_turn_pressed

const BASE_FONT := 20
const HELP := "左键 选择/移动/确认　右键 取消　Q/E 旋转　滚轮 缩放　WASD 平移\nT 威胁范围　Tab 战术视图　P 像素化开关　Z 撤销移动　空格 结束回合　R 重开"

var overlay: BattleOverlay
var ui_scale := 1.0

var _phase_label: Label
var _help_label: Label
var _unit_panel: PanelContainer
var _unit_text: RichTextLabel
var _action_panel: PanelContainer
var _action_box: HBoxContainer
var _info_panel: PanelContainer
var _info_text: RichTextLabel
var _log_panel: PanelContainer
var _log_text: RichTextLabel
var _end_button: Button
var _banner: Label
var _banner_tween: Tween
var _log_lines: Array[String] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()

	overlay = BattleOverlay.new()
	add_child(overlay)

	_phase_label = Label.new()
	add_child(_phase_label)
	_help_label = Label.new()
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help_label.modulate = Color(1, 1, 1, 0.8)
	add_child(_help_label)

	_unit_panel = _panel()
	_unit_text = _rich()
	_unit_panel.add_child(_unit_text)

	_action_panel = _panel()
	_action_box = HBoxContainer.new()
	_action_panel.add_child(_action_box)

	_info_panel = _panel()
	_info_text = _rich()
	_info_panel.add_child(_info_text)

	_log_panel = _panel()
	_log_text = _rich()
	_log_panel.add_child(_log_text)

	_end_button = Button.new()
	_end_button.text = "结束回合"
	_end_button.pressed.connect(func(): end_turn_pressed.emit())
	add_child(_end_button)

	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	add_child(_banner)


func apply_scale(window: Vector2) -> void:
	ui_scale = clampf(window.y / 1080.0, 0.6, 2.0)
	var s := ui_scale
	var m := 16.0 * s
	theme.default_font_size = int(BASE_FONT * s)
	_help_label.add_theme_font_size_override("font_size", int(15 * s))
	_phase_label.add_theme_font_size_override("font_size", int(26 * s))
	_banner.add_theme_font_size_override("font_size", int(54 * s))
	for p: PanelContainer in [_unit_panel, _info_panel, _log_panel, _action_panel]:
		(p.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(12 * s)

	_phase_label.position = Vector2(m, m * 0.6)
	_help_label.size = Vector2(window.x * 0.6, 50 * s)
	_help_label.position = Vector2(window.x - _help_label.size.x - m, m * 0.6)

	# Panels are anchored to a corner and grow away from it, so content changes resize them in place.
	_unit_text.custom_minimum_size.x = 360 * s
	_dock(_unit_panel, Control.PRESET_BOTTOM_LEFT, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN,
		Vector2(m, -m))
	_info_text.custom_minimum_size.x = 420 * s
	_dock(_info_panel, Control.PRESET_TOP_RIGHT, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END,
		Vector2(-m, 84 * s))
	_log_text.custom_minimum_size = Vector2(420 * s, 200 * s)
	_dock(_log_panel, Control.PRESET_BOTTOM_RIGHT, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN,
		Vector2(-m, -m - 70 * s))
	_end_button.custom_minimum_size = Vector2(200 * s, 54 * s)
	_dock(_end_button, Control.PRESET_BOTTOM_RIGHT, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN,
		Vector2(-m, -m))
	_dock(_action_panel, Control.PRESET_CENTER_BOTTOM, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN,
		Vector2(0, -m))

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


func set_phase(text: String) -> void:
	_phase_label.text = text


func set_help_visible(on: bool) -> void:
	_help_label.text = HELP if on else ""


func set_unit_text(bbcode: String) -> void:
	_unit_panel.visible = bbcode != ""
	_unit_text.text = bbcode


func set_info_text(bbcode: String) -> void:
	_info_panel.visible = bbcode != ""
	_info_text.text = bbcode


## actions: [{label, enabled, active}]
func set_actions(actions: Array) -> void:
	for c in _action_box.get_children():
		c.queue_free()
	_action_panel.visible = not actions.is_empty()
	for i in actions.size():
		var a: Dictionary = actions[i]
		var b := Button.new()
		b.text = a["label"]
		b.disabled = not a.get("enabled", true)
		b.toggle_mode = true
		b.button_pressed = a.get("active", false)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46 * ui_scale)
		b.pressed.connect(func(): action_pressed.emit(i))
		_action_box.add_child(b)


func set_end_enabled(on: bool) -> void:
	_end_button.disabled = not on


## Hides battle-only controls (used while the build panel is open).
func set_battle_controls_visible(on: bool) -> void:
	_end_button.visible = on
	_phase_label.visible = on


func log_lines(lines: Array[String]) -> void:
	_log_lines.append_array(lines)
	if _log_lines.size() > 60:
		_log_lines = _log_lines.slice(_log_lines.size() - 60)
	_log_panel.visible = not _log_lines.is_empty()
	_log_text.text = "\n".join(_log_lines.slice(maxi(0, _log_lines.size() - 8)))


func banner(text: String, hold: float = 0.9) -> void:
	_banner.text = text
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.15)
	if hold > 0.0:
		_banner_tween.tween_interval(hold)
		_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.3)


func is_over_panel(screen: Vector2) -> bool:
	for c: Control in [_unit_panel, _action_panel, _info_panel, _log_panel, _end_button]:
		if c.visible and c.get_global_rect().has_point(screen):
			return true
	return false


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", (theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate())
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


static func _make_theme() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
		"Noto Sans CJK SC", "Noto Sans SC", "Source Han Sans SC"])
	t.default_font = font
	t.default_font_size = BASE_FONT
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.08, 0.07, 0.88)
	panel.border_color = Color(0.72, 0.58, 0.34)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(3)
	panel.set_content_margin_all(12)
	t.set_stylebox("panel", "PanelContainer", panel)
	var states := {
		"normal": Color(0.2, 0.17, 0.13), "hover": Color(0.3, 0.25, 0.17),
		"pressed": Color(0.5, 0.38, 0.18), "disabled": Color(0.13, 0.12, 0.11),
	}
	for st in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[st]
		sb.border_color = Color(0.72, 0.58, 0.34) if st != "disabled" else Color(0.3, 0.27, 0.22)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		t.set_stylebox(st, "Button", sb)
	t.set_stylebox("hover_pressed", "Button", t.get_stylebox("pressed", "Button"))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.48, 0.44))
	t.set_color("font_pressed_color", "Button", Color(1, 0.95, 0.8))
	return t
