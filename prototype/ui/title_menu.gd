extends Control
## The front page, and the pause menu when opened from a battle (`in_battle`).
## The front page is a live piece of battlefield with the game's name and four choices;
## everything else in the game happens in the camp.

const Checkpoint := preload("res://core/campaign_checkpoint.gd")
const BATTLE := "res://main.tscn"
const CAMP := "res://camp.tscn"
const TITLE := "res://title.tscn"

var in_battle := false
## Set by the battle scene; kept so older callers keep working. The pause menu no longer uses it.
var battle_map_entry := {}
var saved_entry := {}
var page := ""
var canvas: Control
var body := Control.new()
var note := ""
var _shot_page := ""
var _shot_path := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not in_battle and OS.get_cmdline_user_args().has("--flow") and not get_tree().root.has_node("CampaignFlow"):
		# The whole journey, walked by a script: see tests/flow/campaign_flow.gd.
		get_tree().root.add_child.call_deferred(load("res://tests/flow/campaign_flow.gd").new())
		return
	if not in_battle and not get_tree().has_meta("battle_entered"):
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--ui="):
				_shot_page = arg.trim_prefix("--ui=")
			elif arg.begins_with("--shot="):
				_shot_path = arg.trim_prefix("--shot=")
		for arg in OS.get_cmdline_user_args() if _shot_page == "" else []:
			if arg.begins_with("--battle=") or arg.begins_with("--demo=") or arg.begins_with("--capture="):
				get_tree().change_scene_to_file.call_deferred(BATTLE)
				return
	if _shot_page != "" and _shot_page not in ["title","settings","controls"]:
		# Every other page lives in the camp; hand the request over.
		get_tree().set_meta("shot",{"page":_shot_page,"path":_shot_path})
		get_tree().change_scene_to_file.call_deferred(CAMP)
		return
	if in_battle:
		var veil := ColorRect.new()
		veil.color = Color(Px.INK,.72)
		veil.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(veil)
		veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		saved_entry = Checkpoint.read_entry()
		Soundscape.score("jar")
		_stage_scene()
	canvas = Px.stage(self)
	body.size = Px.SIZE
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(body)
	_show("settings" if _shot_page == "settings" else ("controls" if _shot_page == "controls" else "root"))
	if _shot_path != "":
		UiShot.take(self,_shot_path,2.2)

## The scene behind the front page: the party on the low ground, the lion above them.
func _stage_scene() -> void:
	var scene := Diorama.new()
	add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.lay(["2222222222222","2222233333222","2222233333222","1122233333221","1111222222211","0011111111100","0000011110000","0000000000000","0000000000000","0000000000000"],
		[Vector2i(1,7),Vector2i(11,8),Vector2i(9,9),Vector2i(2,9)])
	scene.unit("lion",Vector2(7.0,2.6),Defs.SOUTH,true)
	scene.unit("hero",Vector2(6.5,8.5),Defs.NORTH)
	scene.unit("atalanta",Vector2(7.7,9.2),Defs.NORTH)
	scene.unit("heracles",Vector2(5.3,9.3),Defs.NORTH)
	scene.sway = 5.0
	scene.look.call_deferred(Vector2(8.6,5.6),0,1)

func _line(value: String, at: Vector2, points: int, tone: Color, width := 0.0) -> float:
	if in_battle:
		Px.text(body,value,Rect2(at,Vector2(width,0)),points,tone)
	else:
		Px.caption(body,value,Rect2(at,Vector2(width,0)),points,tone)
	return at.y+Px.measure(value,points,width if width > 0 else 9999.0)

func _show(which: String, selected := 0) -> void:
	page = which
	Px.clear(body)
	# The front page sets its words on the scene at the lower left; a paused battle and the
	# inner pages use a sheet so the text has a quiet ground.
	var left := 72.0
	var top := 300.0
	var wide := 250.0
	if in_battle:
		left = Px.SIZE.x*.5-wide*.5
		top = 150.0
		Px.sheet(body,Rect2(left-28,top-28,wide+56,300))
	elif which != "root":
		top = 190.0
		Px.sheet(body,Rect2(left-28,top-28,wide+56,300))
	else:
		# A soft dark corner under the title so it holds against bright stone.
		var shade := TextureRect.new()
		var fade := GradientTexture2D.new()
		fade.gradient = Gradient.new()
		fade.gradient.colors = PackedColorArray([Color(Px.INK,.78),Color(Px.INK,0)])
		fade.fill = GradientTexture2D.FILL_RADIAL
		fade.fill_from = Vector2(0,1)
		fade.fill_to = Vector2(1,1)
		shade.texture = fade
		shade.size = Vector2(620,420)
		shade.position = Vector2(0,Px.SIZE.y-420)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(shade)
	var y := top
	var entries: Array = []
	match which:
		"root":
			if in_battle:
				y = _line("战斗暂停",Vector2(left,y),Px.TITLE,Px.IVORY)+10
				entries = [["继续战斗",_resume_battle],["设置",_show.bind("settings")],["操作说明",_show.bind("controls")],["撤回营地",_show.bind("leave")]]
			else:
				_line("HEIR OF PANDORA",Vector2(left+2,y-16),Px.SMALL,Px.OCHRE)
				y = _line("潘多拉之裔",Vector2(left,y),Px.DISPLAY,Px.IVORY)+8
				Px.rule(body,Vector2(left,y),180,Px.OCHRE)
				y += 12
				if saved_entry.is_empty():
					entries = [["踏上征程",_begin_new]]
				else:
					entries = [["回到营地",_continue],["重新开始",_show.bind("restart")]]
				entries.append_array([["设置",_show.bind("settings")],["操作说明",_show.bind("controls")],["离开",Soundscape.quit_game]])
		"settings":
			y = _line("设置",Vector2(left,y),Px.TITLE,Px.IVORY)+10
			var cap := "不限" if DisplayPrefs.frame_cap == 0 else "%d 帧" % DisplayPrefs.frame_cap
			entries = [["显示　　%s" % ("全屏" if DisplayPrefs.fullscreen else "窗口"),_setting.bind(0)],
				["分辨率　%s" % ("跟随屏幕" if DisplayPrefs.fullscreen else "%d × %d" % [DisplayPrefs.size.x,DisplayPrefs.size.y]),_setting.bind(1)],
				["垂直同步　%s" % ("开" if DisplayPrefs.vsync else "关"),_setting.bind(2)],
				["帧率上限　%s" % cap,_setting.bind(3)],
				["音乐　　%d" % Soundscape.levels[Soundscape.MUSIC],_volume.bind(Soundscape.MUSIC,4)],
				["音效　　%d" % Soundscape.levels[Soundscape.EFFECTS],_volume.bind(Soundscape.EFFECTS,5)],
				["返回",_show.bind("root")]]
		"controls":
			y = _line("操作说明",Vector2(left,y),Px.TITLE,Px.IVORY)+10
			for pair: Array in [["左键","选择、移动、确认"],["右键","取消"],["W A S D","平移镜头"],["Q / E","旋转镜头"],["滚轮","缩放"],["Tab","战术地图"],["Esc","暂停"]]:
				Px.text(body,pair[0],Rect2(left,y,70,0),Px.BODY,Px.OCHRE)
				Px.text(body,pair[1],Rect2(left+78,y,180,0),Px.BODY,Px.IVORY)
				y += 20
			y += 6
			entries = [["返回",_show.bind("root")]]
		"restart":
			y = _line("重新开始？",Vector2(left,y),Px.TITLE,Px.IVORY)+6
			y = _line("现在的进度会被新的征程替换。",Vector2(left,y),Px.BODY,Px.MUTED,wide)+10
			entries = [["返回",_show.bind("root")],["重新开始",_begin_new]]
		"leave":
			y = _line("撤回营地？",Vector2(left,y),Px.TITLE,Px.IVORY)+6
			y = _line("这场战斗的进度不会保留。",Vector2(left,y),Px.BODY,Px.MUTED,wide)+10
			entries = [["继续战斗",_show.bind("root")],["撤回营地",_retreat]]
	var rows: Array[Button] = []
	for entry: Array in entries:
		rows.append(Px.row(body,entry[0],Rect2(left-10,y,wide,24),false,entry[1]))
		y += 26
	Px.chain(rows)
	rows[mini(selected,rows.size()-1)].grab_focus()
	if note != "":
		_line(note,Vector2(left,y+8),Px.SMALL,Px.OCHRE,wide)
		note = ""
	if not in_battle and which == "root":
		Px.caption(body,"↑↓ 选择　Enter 确认",Rect2(left,Px.SIZE.y-28,300,0),Px.SMALL,Px.MUTED)

func _setting(index: int) -> void:
	match index:
		0: DisplayPrefs.fullscreen = not DisplayPrefs.fullscreen
		1:
			if DisplayPrefs.fullscreen:
				note = "全屏时用的是屏幕的分辨率。切到窗口后可以选。"
				_show("settings",index)
				return
			DisplayPrefs.next_size()
		2: DisplayPrefs.vsync = not DisplayPrefs.vsync
		3: DisplayPrefs.frame_cap = DisplayPrefs.CAPS[(DisplayPrefs.CAPS.find(DisplayPrefs.frame_cap)+1) % DisplayPrefs.CAPS.size()]
	if DisplayPrefs.commit() != OK:
		note = "设置已生效，但没能写入本机。"
	_show("settings",index)

func _volume(bus: StringName, index: int) -> void:
	if Soundscape.cycle_volume(bus) != OK:
		note = "音量已生效，但没能写入本机。"
	_show("settings",index)

func _continue() -> void:
	get_tree().change_scene_to_file(CAMP)

func _begin_new() -> void:
	var fresh := {"id":"1-1","stage":"camp","picks":{"hero":[],"atalanta":[Checkpoint.STARTERS.atalanta]},"rescued":[],"chiron_joined":false,
		"outcomes":{},"choose_route":false,"purse":{"coins":Checkpoint.STARTING_COINS,"owned":[],"equipped":{},"paid":[]},
		"camp_summary":"山村在身后烧着。先在这里整备，再上路。"}
	if Checkpoint.write_entry(fresh) != OK:
		note = "没能写入存档，请检查本机存储空间。"
		_show("root")
		return
	get_tree().change_scene_to_file(CAMP)

func _resume_battle() -> void:
	get_tree().paused = false
	queue_free()

func _retreat() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(CAMP)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if page != "root":
			_show("root")
		elif in_battle:
			_resume_battle()
