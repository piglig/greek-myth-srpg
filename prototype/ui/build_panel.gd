class_name BuildPanel
extends PanelContainer
## Pre-battle build screen: pick skill-tree nodes for each unit within SkillTree.points().

signal start_pressed(battle_id: String, picks: Dictionary)

var picks := {}
var battle_id := "1-4"
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
	_body.add_theme_constant_override("separation", int(14 * scale))
	add_child(_body)

	var title := Label.new()
	title.text = "战前编成　每人技能点 %d" % SkillTree.points()
	title.add_theme_font_size_override("font_size", int(30 * scale))
	_body.add_child(title)

	var battle_row := HBoxContainer.new()
	battle_row.add_child(_label("战斗：", scale))
	for id in Battles.ids():
		var b := _toggle(Battles.title(id), battle_id == id, scale)
		b.pressed.connect(func(): battle_id = id; _rebuild(scale))
		battle_row.add_child(b)
	_body.add_child(battle_row)

	for def_id in SkillTree.trees():
		var unit_name: String = UnitCatalog.unit_def(def_id)["name"]
		var used := SkillTree.cost(def_id, picks[def_id])
		var header := _label("%s　已用 %d / %d" % [unit_name, used, SkillTree.points()], scale)
		header.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
		_body.add_child(header)
		for branch in SkillTree.trees()[def_id]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", int(10 * scale))
			var bl := _label(branch["branch"], scale)
			bl.custom_minimum_size.x = 150 * scale
			row.add_child(bl)
			var nodes: Array = branch["nodes"]
			for i in nodes.size():
				var n: Dictionary = nodes[i]
				var on: bool = (picks[def_id] as Array).has(n["id"])
				var b := _toggle("%s（%d）" % [n["name"], n["cost"]], on, scale)
				b.custom_minimum_size.x = 210 * scale
				b.mouse_entered.connect(func(): _desc.text = "%s：%s" % [n["name"], n["desc"]])
				b.pressed.connect(func(): _toggle_node(def_id, nodes, i, scale))
				row.add_child(b)
			_body.add_child(row)

	_desc = _label("把鼠标移到技能上查看说明。容器分支需要圣物，第 1-5 场之后开放。", scale)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(940 * scale, 60 * scale)
	_desc.modulate = Color(0.85, 0.85, 0.85)
	_body.add_child(_desc)

	var start := Button.new()
	start.text = "开始战斗"
	start.custom_minimum_size = Vector2(240, 56) * scale
	start.size_flags_horizontal = Control.SIZE_SHRINK_END
	start.pressed.connect(func(): hide(); start_pressed.emit(battle_id, picks))
	_body.add_child(start)


## Picking a node also picks its prerequisite; dropping a node drops the nodes after it.
func _toggle_node(def_id: String, nodes: Array, index: int, scale: float) -> void:
	var list: Array = (picks[def_id] as Array).duplicate()
	var id: String = nodes[index]["id"]
	if list.has(id):
		for j in range(index, nodes.size()):
			list.erase(nodes[j]["id"])
	else:
		for j in range(0, index + 1):
			if not list.has(nodes[j]["id"]):
				list.append(nodes[j]["id"])
	if SkillTree.validate(def_id, list) == "":
		picks[def_id] = list
	else:
		_desc.text = "技能点不够。"
		return
	_rebuild(scale)


func _label(text: String, scale: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(20 * scale))
	return l


func _toggle(text: String, on: bool, scale: float) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 46 * scale
	return b
