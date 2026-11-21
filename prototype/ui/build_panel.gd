class_name BuildPanel
extends PanelContainer
## Pre-battle build screen: pick skill-tree nodes for each unit within SkillTree.points().

const Metrics := preload("res://ui/interface_metrics.gd")

signal start_pressed(battle_id: String, picks: Dictionary)

signal canceled
var camp_mode := false
var picks := {}
var campaign_start := false
var battle_id := "1-1"
var _body: VBoxContainer
var _desc: Label


func _init() -> void:
	var defaults := SkillTree.default_picks()
	for def_id in defaults:
		picks[def_id] = (defaults[def_id] as Array).duplicate()


func open(scale: float) -> void:
	custom_minimum_size = Vector2(980, 0) * scale
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_rebuild(scale)
	show()


func _rebuild(scale: float) -> void:
	for c in get_children():
		c.queue_free()
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", roundi(Metrics.PADDING * scale))
	add_child(_body)

	var title := Label.new()
	title.text = ("营地整备　每人技能点 %d" if camp_mode else "战前编成　每人技能点 %d") % SkillTree.points()
	title.add_theme_font_size_override("font_size", roundi(Metrics.TITLE * scale))
	_body.add_child(title)

	var battle_row := HBoxContainer.new()
	battle_row.add_child(_label("战斗：", scale))
	for id in Battles.ids():
		if (campaign_start and id != battle_id) or id=="1-3":
			continue # Enter the banquet through the woodland rescue.
		var b := _toggle(Battles.title(id), battle_id == id, scale)
		b.pressed.connect(func(): battle_id = id; _rebuild(scale))
		battle_row.add_child(b)
	_body.add_child(battle_row)
	battle_row.visible=not camp_mode

	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=300*scale
	_body.add_child(scroll)
	var list_box:=VBoxContainer.new()
	scroll.add_child(list_box)
	for def_id in SkillTree.trees():
		if def_id in ["chiron","medea"] and (campaign_start or battle_id!="2-1"):continue
		if not picks.has(def_id):picks[def_id]=[]
		var unit_name: String = UnitCatalog.unit_def(def_id)["name"]
		var used := SkillTree.cost(def_id, picks[def_id])
		var header := _label("%s　已用 %d / %d" % [unit_name, used, SkillTree.points()], scale)
		header.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
		list_box.add_child(header)
		for branch in SkillTree.trees()[def_id]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", roundi(Metrics.GAP * scale))
			var bl := _label(branch["branch"], scale)
			bl.custom_minimum_size.x = 110 * scale
			row.add_child(bl)
			var nodes: Array = branch["nodes"]
			for i in nodes.size():
				var n: Dictionary = nodes[i]
				var on: bool = (picks[def_id] as Array).has(n["id"])
				var b := _toggle("%s（%d）" % [n["name"], n["cost"]], on, scale)
				b.custom_minimum_size.x = 128 * scale
				b.mouse_entered.connect(func(): _desc.text = "%s：%s" % [n["name"], n["desc"]])
				b.pressed.connect(func(): _toggle_node(def_id, nodes, i, scale))
				row.add_child(b)
			list_box.add_child(row)

	_desc = _label("指向技能查看说明，保存后将在下一战生效。" if camp_mode else "指向招式查看说明。出发后可到营地找达蒙进修。", scale)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(940 * scale, 60 * scale)
	_desc.modulate = Color(0.85, 0.85, 0.85)
	_body.add_child(_desc)

	var start := Button.new()
	start.text = "保存整备" if camp_mode else "开始战斗"
	start.custom_minimum_size = Vector2(240, Metrics.CONTROL) * scale
	start.size_flags_horizontal = Control.SIZE_SHRINK_END
	start.pressed.connect(func(): hide(); start_pressed.emit(battle_id, picks))
	var navigation := HBoxContainer.new()
	_body.add_child(navigation)
	var back := Button.new()
	back.text = "取消调整" if camp_mode else "返回地图" if campaign_start else "返回首页"
	if camp_mode: back.pressed.connect(canceled.emit)
	else: back.pressed.connect(func(): get_tree().change_scene_to_file("res://journey.tscn" if campaign_start else "res://title.tscn"))
	navigation.add_child(back)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(gap)
	navigation.add_child(start)


## Picking a node also picks its prerequisite; dropping a node drops the nodes after it.
func _toggle_node(def_id: String, nodes: Array, index: int, scale: float) -> void:
	var list: Array = (picks[def_id] as Array).duplicate()
	var id: String = nodes[index]["id"]
	if list.has(id):
		list.erase(id)
		for node: Dictionary in nodes:
			if node.parent!="" and not list.has(node.parent):list.erase(node.id)
	else:
		var current:=id
		while current!="" and not list.has(current):
			list.append(current)
			for node: Dictionary in nodes:
				if node.id==current:
					current=node.parent
					break
	if SkillTree.validate(def_id, list) == "":
		picks[def_id] = list
	else:
		_desc.text = "技能点不够。"
		return
	_rebuild(scale)


func _unhandled_key_input(event: InputEvent) -> void:
	if camp_mode and is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		canceled.emit()


func _label(text: String, scale: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", roundi(Metrics.BODY * scale))
	return l


func _toggle(text: String, on: bool, scale: float) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = Metrics.CONTROL * scale
	return b
