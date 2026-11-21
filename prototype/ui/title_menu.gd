extends Control

const Checkpoint := preload("res://core/campaign_checkpoint.gd")
var saved_entry := {}
var reward_entry := {}
var record_reward := true
const BATTLE := "res://main.tscn"
const TITLE := "res://title.tscn"
const COVER := "res://art/original/interface/pandora-cover.webp"
const MARKS := preload("res://art/original/interface/ceramic_marks.svg")
const IVORY := Color("#f5e5c9")
const COPPER := Color("#d8a46c")

var in_battle := false
var battle_map_entry := {}
var inspecting_map := false
var page := ""
var frame := Control.new()
var body := VBoxContainer.new()
var footer := Label.new()
var serif := SystemFont.new()
var focus_button: Button
var marker := Polygon2D.new()
var marker_y := 0.0
var entrance: Tween
var cover := TextureRect.new()
var camp: Control
var scenery: ShaderMaterial
var look_offset := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not in_battle and not get_tree().has_meta("battle_entered"):
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--battle=") or arg.begins_with("--demo=") or arg.begins_with("--capture="):
				get_tree().change_scene_to_file.call_deferred(BATTLE)
				return
	if not in_battle:
		saved_entry = Checkpoint.read_entry()
		Soundscape.score("jar")
	serif.font_names = PackedStringArray(["Songti SC", "STSong", "SimSun", "Noto Serif CJK SC", "Georgia"])
	cover.texture = load(COVER)
	if not in_battle:
		scenery = ShaderMaterial.new()
		scenery.shader = preload("res://ui/pandora_ember.gdshader")
		cover.material = scenery
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(_draw_trim)
	frame.add_child(marker)
	marker.color = COPPER
	marker.polygon = PackedVector2Array([Vector2(-5,0), Vector2(0,-6), Vector2(5,0), Vector2(0,6)])
	marker.visible = not in_battle
	frame.add_child(body)
	body.position = Vector2(100, 121)
	body.custom_minimum_size.x = 414
	body.add_theme_constant_override("separation", 9)
	frame.add_child(footer)
	footer.position = Vector2(100, 709)
	footer.add_theme_font_size_override("font_size", 15)
	footer.modulate = Color("#c8b59b")
	resized.connect(_layout)
	_layout()
	if get_tree().has_meta("return_to_camp"):
		get_tree().remove_meta("return_to_camp")
		_show("camp")
	elif get_tree().has_meta("chapter_reward_screen"):
		var result: Dictionary = get_tree().get_meta("chapter_reward_screen")
		get_tree().remove_meta("chapter_reward_screen")
		reward_entry = result.entry
		record_reward = result.campaign
		_show("reward")
	else:
		_show("root")

func _layout() -> void:
	var factor := minf(size.x / 1366.0, size.y / 768.0)
	frame.scale = Vector2.ONE * factor
	frame.size = Vector2(1366, 768)
	frame.position = (size - frame.size * factor) * 0.5

func _draw_trim() -> void:
	if page=="camp":return
	for y in [83, 691]:
		frame.draw_line(Vector2(100,y), Vector2(514,y), Color("#8b6444"), 1.0)
		frame.draw_colored_polygon(PackedVector2Array([Vector2(100,y-4),Vector2(104,y),Vector2(100,y+4),Vector2(96,y)]), COPPER)

func _label(value: String, points: int, color: Color, title_font := false) -> Label:
	var line := Label.new()
	line.text = value
	line.add_theme_font_size_override("font_size", points)
	line.add_theme_color_override("font_color", color)
	if title_font:
		line.add_theme_font_override("font", serif)
	body.add_child(line)
	return line

func _space(height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	body.add_child(spacer)

func _style(fill: Color, edge: Color, focus := false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.border_width_left = 3
	box.content_margin_left = 19
	box.content_margin_right = 18
	if focus:
		box.draw_center = false
		box.set_border_width_all(1)
	return box

func _button(caption: String, mark: int, handler: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 54
	var icon := AtlasTexture.new()
	icon.atlas = MARKS
	icon.region = Rect2((mark % 9) * 48, floori(mark / 9.0) * 48, 48, 48)
	button.icon = icon
	button.add_theme_constant_override("icon_max_width", 29)
	button.add_theme_constant_override("h_separation", 18)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", IVORY)
	button.add_theme_stylebox_override("normal", _style(Color("#211d19d9"), Color("#886342")))
	button.add_theme_stylebox_override("hover", _style(Color("#633d29"), COPPER))
	button.add_theme_stylebox_override("pressed", _style(Color("#74442c"), IVORY))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, COPPER, true))
	body.add_child(button)
	button.pressed.connect(Soundscape.cue.bind("confirm"))
	button.pressed.connect(handler)
	if not in_battle:
		button.mouse_entered.connect(button.grab_focus)
	return button

func _show(which: String, selected := 0) -> void:
	var opening := page.is_empty()
	var changing := which != page
	page = which
	frame.queue_redraw()
	if not in_battle:
		cover.visible=which!="camp"
	if is_instance_valid(camp):
		frame.remove_child(camp)
		camp.queue_free()
		camp=null
	body.visible=which!="camp"
	footer.visible=which!="camp"
	marker.visible=false
	if which=="camp":
		camp=preload("res://ui/camp_people.gd").new()
		frame.add_child(camp)
		camp.prepare.connect(_prepare)
		camp.depart.connect(_depart_camp)
		camp.leave.connect(_show.bind("root"))
		camp.setup(self)
		return
	for node in body.get_children():
		body.remove_child(node)
		node.queue_free()
	footer.text = "↑ ↓  选择　　　 Enter  确认"
	if which != "root" or in_battle:
		footer.text += "　　　 Esc  返回"
	match which:
		"root":
			_label("H E I R   O F   P A N D O R A", 19, COPPER, true)
			_label("战斗暂停" if in_battle else "潘多拉之裔", 67, IVORY, true)
			_space(35)
			if not in_battle and not saved_entry.is_empty():
				var caption := "查看征程地图" if saved_entry.has("equipped_relic") else "继续征程　%s" % saved_entry.id
				if saved_entry.get("choose_route",false): caption = "继续征程　林道岔路"
				if saved_entry.get("stage")=="camp": caption="继续征程　营地"
				elif saved_entry.id=="2-1": caption="继续征程　科林斯"
				_button(caption,12,_resume)
				_button("开始新征程", 12, _show.bind("new_campaign"))
			else:
				_button("继续战斗" if in_battle else "开始征程", 12, _begin)
			if in_battle and not battle_map_entry.is_empty():
				_button("查看征程地图",7,_inspect_map)
			_button("游戏设置", 7, _show.bind("settings"))
			_button("操作指南", 10, _show.bind("controls"))
			_button("返回首页" if in_battle else "退出游戏", 5, _show.bind("leave"))
		"settings":
			_heading("游戏设置")
			_button("显示模式　　　%s" % ("全屏" if DisplayPrefs.fullscreen else "窗口"), 7, _setting.bind(0))
			_button("垂直同步　　　%s" % ("开启" if DisplayPrefs.vsync else "关闭"), 3, _setting.bind(1))
			var limit := "不限" if DisplayPrefs.frame_cap == 0 else "%d FPS" % DisplayPrefs.frame_cap
			_button("帧率上限　　　%s" % limit, 21, _setting.bind(2))
			_button("声音设置", 10, _show.bind("audio"))
			_button("返回", 5, _back)
		"audio":
			_heading("声音设置")
			_button("音乐音量　　　%d%%" % Soundscape.levels[Soundscape.MUSIC], 10, _volume.bind(Soundscape.MUSIC, 0))
			_button("音效音量　　　%d%%" % Soundscape.levels[Soundscape.EFFECTS], 7, _volume.bind(Soundscape.EFFECTS, 1))
			_button("返回", 5, _back)
		"controls":
			_heading("操作指南")
			for entry in ["左键　　　　　选择、移动或确认", "右键　　　　　取消当前指令", "W A S D　　　平移镜头", "Q / E　　　　 旋转镜头", "鼠标滚轮　　　缩放战场", "T / Tab　　　 威胁范围 / 战术视图", "空格　　　　　结束回合"]:
				_label(entry, 19, IVORY)
			_button("返回", 5, _back)
		"reward":
			_chapter_reward_page()
		"new_campaign":
			_heading("开始新征程？")
			_label("进入新战斗时将替换现有关卡存档。", 21, IVORY)
			_button("返回", 5, _back)
			_button("前往编成", 12, _begin)
		"leave":
			_heading("返回首页？" if in_battle else "退出游戏？")
			if in_battle:
				_label("已保存最近一次我方操作。" if battle_map_entry.get("id")=="2-1" else "当前战斗进度将丢失。", 21, IVORY)
			_space(12)
			_button("取消", 5, _back)
			_button("返回首页" if in_battle else "退出游戏", 12, _leave)
	var buttons := body.find_children("*","Button",false,false)
	if buttons[selected].disabled:
		for i in buttons.size():
			if not buttons[i].disabled:
				selected=i
				break
	focus_button = buttons[selected]
	focus_button.grab_focus()
	for b in buttons:
		b.focus_entered.connect(Soundscape.cue.bind("focus"))
	if changing and not in_battle:
		if entrance:
			entrance.kill()
		body.modulate.a = 0.35
		entrance = create_tween()
		entrance.tween_property(body, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
		if opening:
			for i in body.get_child_count():
				var item := body.get_child(i) as Control
				item.modulate.a = 0.0
				entrance.parallel().tween_property(item, "modulate:a", 1.0, 0.38).set_delay(i * 0.055)
		marker_y = 0.0
	# Keep arrow-key navigation inside this page, including at either end.
	for i in buttons.size():
		var b := buttons[i] as Button
		b.focus_neighbor_top = b.get_path_to(buttons[posmod(i-1,buttons.size())])
		b.focus_neighbor_bottom = b.get_path_to(buttons[(i+1)%buttons.size()])

func _process(delta: float) -> void:
	if in_battle or not marker.is_inside_tree():
		return
	var pointer := (get_local_mouse_position() / size.max(Vector2.ONE) * 2.0 - Vector2.ONE).clamp(-Vector2.ONE, Vector2.ONE)
	look_offset = look_offset.lerp(pointer * Vector2(0.007, 0.005), 1.0 - exp(-3.0 * delta))
	scenery.set_shader_parameter("look_offset", look_offset)
	var active := get_viewport().gui_get_focus_owner() as Button
	if active == null or active.get_parent() != body:
		marker.hide()
		return
	marker.show()
	var target := body.position.y + active.position.y + active.size.y * 0.5
	marker_y = target if marker_y == 0.0 else lerpf(marker_y, target, 1.0 - exp(-18.0 * delta))
	marker.position = Vector2(body.position.x - 14.0, marker_y)

func _heading(caption: String) -> void:
	_label("潘 多 拉 之 裔", 18, COPPER, true)
	_label(caption, 48, IVORY, true)
	_space(18)

func _volume(bus: StringName, index: int) -> void:
	var result := Soundscape.cycle_volume(bus)
	_show("audio", index)
	if result != OK:
		footer.text = "音量已应用，写入本机失败。"

func _setting(index: int) -> void:
	match index:
		0: DisplayPrefs.fullscreen = not DisplayPrefs.fullscreen
		1: DisplayPrefs.vsync = not DisplayPrefs.vsync
		2:
			var caps := DisplayPrefs.CAPS
			DisplayPrefs.frame_cap = caps[(caps.find(DisplayPrefs.frame_cap)+1) % caps.size()]
	var result := DisplayPrefs.commit()
	_show("settings", index)
	if result != OK:
		footer.text = "设置已应用，写入本机失败。"

func _review_reward() -> void:
	reward_entry = saved_entry.duplicate(true)
	record_reward = true
	_show("reward")

func _chapter_reward_page() -> void:
	var choosing: bool = reward_entry.boon == ""
	_label("第一章　／　涅墨亚",19,COPPER,true)
	_label("涅墨亚狮子已败" if choosing else "第一章已完成",42,IVORY,true)
	var hero := HBoxContainer.new()
	body.add_child(hero)
	var portrait := AtlasTexture.new()
	portrait.atlas = preload("res://art/original/actors/hero.png")
	portrait.region = Rect2(50,26,220,210)
	var face := TextureRect.new()
	face.texture = portrait
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.custom_minimum_size = Vector2(58,58)
	hero.add_child(face)
	var equipment := VBoxContainer.new()
	hero.add_child(equipment)
	var relic := Label.new()
	relic.text = "持盾主角　／　狮皮已装备"
	relic.add_theme_color_override("font_color",IVORY)
	equipment.add_child(relic)
	var divinity := ProgressBar.new()
	divinity.max_value = 20
	divinity.value = reward_entry.divinity
	divinity.show_percentage = false
	divinity.custom_minimum_size = Vector2(190,6)
	equipment.add_child(divinity)
	var value := Label.new()
	value.text = "神性 %d　·　凡人" % int(reward_entry.divinity)
	equipment.add_child(value)
	_label("物理减伤 3，受背击倍率降至 1.25。",17,IVORY)
	_label("不坏之皮　免疫物理伤害 1 回合，冷却 4 回合；使用时神性 +2。",16,COPPER)
	_space(6)
	if choosing:
		_label("选择一项永久神赐",22,IVORY,true)
		for id in Checkpoint.BOONS:
			var boon: Array = Checkpoint.BOONS[id]
			_button("%s · %s" % [boon[0],boon[1]],11 if id == "moon_hunt" else 12,_choose_boon.bind(id))
			_label(boon[2],16,IVORY)
	else:
		var chosen: Array = Checkpoint.BOONS[reward_entry.boon]
		_label("神赐　%s · %s" % [chosen[0],chosen[1]],22,COPPER,true)
		_label(chosen[2],17,IVORY)
		if record_reward:
			_button("前往营地整备",5,_enter_camp)
		else:
			_button("返回首页",5,_show.bind("root"))

func _choose_boon(id: String) -> void:
	if reward_entry.boon != "" or not Checkpoint.BOONS.has(id):
		return
	var next := reward_entry.duplicate(true)
	next.boon = id
	if record_reward:
		if Checkpoint.write_entry(next) != OK:
			footer.text = "神赐保存失败，请检查存储空间后重新选择。"
			return
		saved_entry = next
	reward_entry = next
	_show("reward")



func _coins() -> int:
	return int(saved_entry.get("purse",{}).get("coins",Checkpoint.STARTING_COINS))

func _party() -> Dictionary:
	var party:={"hero":"主角","atalanta":"阿塔兰忒"}
	if saved_entry.chiron_joined: party.chiron="喀戎"
	if saved_entry.get("medea_joined",false): party.medea="美狄亚"
	return party

func _buy(id: String) -> bool:
	if not Checkpoint.stocked(id,saved_entry):return false
	var next:=saved_entry.duplicate(true)
	var purse: Dictionary=next.get("purse",{})
	var owned: Array=purse.get("owned",[])
	if not owned.has(id):
		var price:=int(Checkpoint.GOODS[id].price)
		if _coins()<price:return false
		owned.append(id)
		purse.owned=owned
		purse.coins=_coins()-price
		next.purse=purse
		return _persist(next)
	return true

func _assign_charm(item: String,who: String) -> bool:
	if not saved_entry.get("purse",{}).get("owned",[]).has(item) or (who!="" and not _party().has(who)):return false
	var next:=saved_entry.duplicate(true)
	var slots: Dictionary=next.purse.get("equipped",{})
	if who!="":
		for id in slots.keys():
			if slots[id]==who: slots.erase(id)
		slots[item]=who
	else: slots.erase(item)
	next.purse.equipped=slots
	return _persist(next)

func _resume():
	if saved_entry.get("stage")=="camp": _show("camp")
	elif saved_entry.id=="1-5" and saved_entry.has("equipped_relic"): _review_reward()
	else: _open_map(saved_entry)

func _persist(next: Dictionary) -> bool:
	if Checkpoint.write_entry(next)!=OK:
		footer.text="保存失败，请重试。"
		return false
	saved_entry=next
	return true

func _enter_camp():
	var next:=reward_entry.duplicate(true)
	next.camp_summary="涅墨亚狮子已败。全队升至 %d 级，各得 1 技能点。"%SkillTree.campaign_level(next)
	next.id="2-1"
	next.stage="camp"
	next.choose_route=false
	if _persist(next): _show("camp")

func _prepare():
	var panel:=preload("res://ui/training_ground.gd").new()
	camp.hide()
	frame.add_child(panel)
	panel.dismissed.connect(func():
		panel.queue_free()
		camp.show()
		camp.yard())
	panel.ask_teacher.connect(func():
		panel.queue_free()
		camp.show()
		camp.talk(1,true))
	panel.setup(self)

func _depart_camp():
	var next:=saved_entry.duplicate(true)
	next.stage="map"
	if _persist(next): _open_map(next)
	else:
		camp._panel("story","行程未保存，请再试一次。")
		camp._choice("展开行军图",_depart_camp)
		camp._choice("留在营地",camp.yard)

func _inspect_map() -> void:
	var map = preload("res://journey.tscn").instantiate()
	map.inspecting = true
	map.entry = battle_map_entry
	inspecting_map = true
	frame.hide()
	map.closed.connect(func():
		inspecting_map = false
		frame.show()
		_show("root",1))
	add_child(map)

func _open_map(progress: Dictionary) -> void:
	get_tree().set_meta("journey_entry",progress.duplicate(true))
	get_tree().change_scene_to_file("res://journey.tscn")

func _begin() -> void:
	if in_battle:
		get_tree().paused = false
		queue_free()
	else:
		_open_map({})

func _leave() -> void:
	if in_battle:
		get_tree().paused = false
		get_tree().change_scene_to_file(TITLE)
	else:
		Soundscape.quit_game()

func _back() -> void:
	var extra := int(not in_battle and not saved_entry.is_empty() or in_battle and not battle_map_entry.is_empty())
	match page:
		"root":
			if in_battle:
				_begin()
		"reward","camp": _show("root")
		"new_campaign": _show("root", 1)
		"settings": _show("root", 1+extra)
		"audio": _show("settings", 3)
		"controls": _show("root", 2+extra)
		"leave": _show("root", 3+extra)

func _input(event: InputEvent) -> void:
	if is_instance_valid(camp) and camp.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		camp.back()
		return
	if inspecting_map or not body.visible: return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()
