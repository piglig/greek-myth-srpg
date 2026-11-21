extends Control

const Seals := preload("res://art/original/interface/journey_seals.svg")
const Art := "res://art/original/interface/journey/"
const Routes := preload("res://data/chapter_routes.json")
const Numerals := ["一","二","三","四","五","六","七","八"]
const Gold := Color("#deb777")
const Ivory := Color("#f2e7cf")
signal closed
var inspecting := false
var entry: Dictionary
var chapter := 0
var selected := 0
var frame := Control.new()
var chart: Control
var standard_canvas: Control
var serif := SystemFont.new()
var sites: Array
var outcomes: Dictionary

func _ready():
	if not inspecting:
		entry = get_tree().get_meta("journey_entry",{})
		if get_tree().has_meta("journey_entry"): get_tree().remove_meta("journey_entry")
	outcomes = entry.get("outcomes",{})
	serif.font_names = PackedStringArray(["Songti SC","STSong","SimSun","Georgia"])
	var backdrop := ColorRect.new()
	backdrop.color = Color("#201e1b")
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(frame)
	frame.size = Vector2(1366,768)
	resized.connect(_layout)
	_layout()
	if not inspecting: Soundscape.score("jar")
	_open(1 if entry.get("id","")=="2-1" else 0)

func _layout():
	var s := minf(size.x/1366.,size.y/768.)
	frame.scale = Vector2.ONE*s
	frame.position = (size-frame.size*s)*.5

func _text(parent: Control, caption: String, pos: Vector2, pts: int, color: Color, heading := false) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = pos
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color",color)
	label.add_theme_font_size_override("font_size",pts)
	if heading: label.add_theme_font_override("font",serif)
	parent.add_child(label)
	return label

func _command(caption: String, pos: Vector2, dims: Vector2, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = "" if primary else caption
	button.position = pos
	button.size = dims
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.add_theme_font_override("font",serif)
	button.add_theme_font_size_override("font_size",26 if primary else 19)
	button.add_theme_color_override("font_color",Ivory)
	button.add_theme_color_override("font_hover_color",Color.WHITE)
	button.add_theme_color_override("font_outline_color",Color("#201c16"))
	button.add_theme_constant_override("outline_size",4)
	for state in ["normal","hover","pressed","focus"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	frame.add_child(button)
	button.draw.connect(func():
		var bright := button.has_focus() or button.is_hovered()
		var w := dims.x
		var h := dims.y
		if primary:
			var crest := PackedVector2Array([Vector2(0,5),Vector2(w-20,5),Vector2(w,h*.5),Vector2(w-20,h-5),Vector2(0,h-5),Vector2(10,h*.5)])
			button.draw_colored_polygon(crest, Color("#995635") if bright else Color("#743f29"))
			button.draw_polyline(PackedVector2Array([crest[0],crest[1],crest[2],crest[3],crest[4]]),Gold,2,true)
		elif bright:
			button.draw_line(Vector2(8,h-4),Vector2(w-8,h-4),Gold,1.5,true)
	)
	if primary:
		var label:=_text(button,caption,Vector2.ZERO,26,Ivory,true)
		label.size=dims
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	button.pressed.connect(action)
	return button

func _open(index: int):
	chapter = index
	sites = Routes.data[index].sites
	selected = 0
	if chapter==0:
		for i in sites.size():
			if sites[i].id==entry.get("id","1-1"): selected=i
	_render()

func _status(site: Dictionary) -> String:
	if chapter==1 and site.id=="2-1" and entry.get("id")=="2-1":
		if outcomes.has(site.id):return str(outcomes[site.id])
		return "交战中" if inspecting else "可出发"
	if chapter!=0:return "尚未开放"
	if chapter==0 and site.id=="1-5" and entry.has("equipped_relic"):return "已通关"
	if outcomes.has(site.id):return str(outcomes[site.id])
	if site.id==entry.get("id","1-1"):return "交战中" if inspecting else "可出发"
	if site.id=="1-3":
		if entry.get("choose_route",false):return "可出发"
		if entry.get("id","") in ["1-4","1-5"]:return "未到访"
		return "支线待解锁"
	return "尚未抵达"

func _render():
	for child in frame.get_children():
		frame.remove_child(child)
		child.queue_free()
	var region: Dictionary = Routes.data[chapter]
	chart = Control.new()
	chart.size = frame.size
	frame.add_child(chart)
	var land := TextureRect.new()
	land.texture = load(Art + ("arcadian_relief.webp" if chapter==0 else "map_%d.webp" % (chapter+1)))
	land.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	land.size = chart.size
	land.mouse_filter = MOUSE_FILTER_IGNORE
	var light := ShaderMaterial.new()
	light.shader = preload("res://ui/journey_light.gdshader")
	land.material = light
	chart.add_child(land)
	standard_canvas = Control.new()
	standard_canvas.mouse_filter=MOUSE_FILTER_IGNORE
	chart.add_child(standard_canvas)
	standard_canvas.draw.connect(_draw_chart.bind(standard_canvas))
	for i in sites.size():
		var site: Dictionary=sites[i]
		var button:=Button.new()
		button.name="Site%d"%i
		button.flat=true
		button.tooltip_text=site.name+" · "+_status(site)
		button.position=_point(i)-Vector2(76,68)
		button.size=Vector2(152,103)
		button.mouse_default_cursor_shape=CURSOR_POINTING_HAND
		for state in ["normal","hover","pressed","focus"]:
			button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		chart.add_child(button)
		button.pressed.connect(_select.bind(i))
	var cleared:=0
	for stop: Dictionary in sites:
		if _status(stop)=="已通关": cleared+=1
	_text(frame,"第 %s 章    /    已通关  %d / %d"%[Numerals[chapter],cleared,sites.size()],Vector2(58,31),18,Gold)
	_text(frame,region.name,Vector2(54,58),56,Ivory,true)
	_command("‹  上一章",Vector2(965,33),Vector2(105,46),_open.bind(posmod(chapter-1,Routes.data.size())))
	_command("下一章  ›",Vector2(1070,33),Vector2(105,46),_open.bind((chapter+1)%Routes.data.size()))
	_command("返回战场菜单" if inspecting else "返回首页",Vector2(1200,33),Vector2(132,46),_home)
	if not inspecting and entry.get("stage")=="map":
		_command("回营整备",Vector2(820,33),Vector2(125,46),_camp)
	var site: Dictionary=sites[selected]
	var status:=_status(site)
	_text(frame,"%s     /     %s     ·     %s"%[site.id,"支线" if site.optional else "主线",status],Vector2(62,590),19,Gold)
	_text(frame,site.name,Vector2(58,616),46,Ivory,true)
	var objective:=_text(frame,site.goal,Vector2(62,689),21,Ivory)
	objective.size.x=810
	objective.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var depart: Button
	if not inspecting and entry.get("id")=="1-5" and chapter==0 and site.id=="1-5" and entry.has("equipped_relic"):
		depart=_command("选择神赐" if entry.boon=="" else "查看章末战果",Vector2(1017,646),Vector2(282,65),_reward,true)
	elif not inspecting and status=="可出发":
		depart=_command("继续护送" if entry.get("stage")=="battle" else "向此地进军",Vector2(1017,646),Vector2(282,65),_travel,true)
	else:
		var hint: String = {"尚未开放":"此章尚未开放","尚未抵达":"沿主线继续前行","支线待解锁":"在林道救出至少两名村民","未到访":"本次行程已错过","已通关":"此地已通关","交战中":"返回战场继续战斗"}.get(status,status)
		var note:=_text(frame,hint,Vector2(937,672),20,Gold,true)
		note.size.x=360
		note.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	if depart: depart.grab_focus()
	else: (chart.get_node("Site%d"%selected) as Button).grab_focus()

func _process(_delta: float):
	if is_instance_valid(standard_canvas): standard_canvas.queue_redraw()

func _point(i: int) -> Vector2:
	var xy: Array=sites[i].xy
	return Vector2(52+xy[0]*1.44,91+xy[1]*1.08)

func _draw_chart(canvas: Control):
	var t:=Time.get_ticks_msec()*.001
	for path: Array in Routes.data[chapter].paths:
		var a:=_point(path[0])
		var b:=_point(path[1])
		var walked:=_status(sites[path[0]])=="已通关" and _status(sites[path[1]])=="已通关"
		if chapter==0 and path[0]==1 and path[1]==3 and outcomes.has("1-3"): walked=false
		var count:=ceili(a.distance_to(b)/13.)
		for j in range(1,count):
			var k:=float(j)/count
			var at:=a.lerp(b,k)+(b-a).orthogonal().normalized()*sin(TAU*k)*13.
			canvas.draw_circle(at,3.6,Color("#493622c0"),true,-1,true)
			canvas.draw_circle(at,2.3,Color("#a3d2bb") if walked else Color("#f8d598"),true,-1,true)
	for i in sites.size():
		var at:=_point(i)
		var site: Dictionary=sites[i]
		var status:=_status(site)
		var target:=chart.get_node("Site%d"%i) as Button
		var active:=i==selected
		var lit:=active or target.is_hovered() or target.has_focus()
		var available:=status in ["可出发","交战中"]
		var dye:=Color("#a8442d") if available else (Color("#26675c") if status=="已通关" else Color("#4f4d47"))
		canvas.draw_set_transform(at,0,Vector2(1,.36))
		canvas.draw_circle(Vector2.ZERO,24,Color("#251a14a8"),true,-1,true)
		if lit:
			canvas.draw_arc(Vector2.ZERO,28+sin(t*2.)*1.5,0,TAU,60,Gold,3,true)
		canvas.draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
		canvas.draw_line(at,at+Vector2(0,-68),Color("#312a20"),5,true)
		canvas.draw_line(at-Vector2(1,0),at+Vector2(-1,-68),Gold,1.6,true)
		var ripple:=sin(t*2.4+i)*2.
		var flag:=PackedVector2Array([at+Vector2(1,-63),at+Vector2(20,-65+ripple),at+Vector2(38,-61+ripple),at+Vector2(32,-48+ripple),at+Vector2(38,-35+ripple),at+Vector2(19,-39+ripple),at+Vector2(1,-37)])
		canvas.draw_colored_polygon(flag,dye)
		canvas.draw_polyline(flag,Color("#e5c085"),1.2,true)
		var symbol: int = i if chapter==0 else (2 if site.optional else 3)
		canvas.draw_texture_rect_region(Seals,Rect2(at+Vector2(6,-61+ripple*.4),Vector2(21,21)),Rect2(symbol*32,0,32,32))
		canvas.draw_circle(at+Vector2(0,-69),3.4,Gold,true,-1,true)
		var baseline:=at+Vector2(-115,27)
		var name_text:String=site.name
		canvas.draw_string_outline(serif,baseline,name_text,HORIZONTAL_ALIGNMENT_CENTER,230,21,5,Color("#221e17ee"))
		canvas.draw_string(serif,baseline,name_text,HORIZONTAL_ALIGNMENT_CENTER,230,21,Color("#ffe4a7") if lit else Ivory)

func _select(i: int):
	selected=i
	_render()
	(chart.get_node("Site%d"%i) as Button).grab_focus()

func _travel():
	if _status(sites[selected])!="可出发":return
	if entry.is_empty():
		get_tree().set_meta("campaign_build",true)
	else:
		var next:=entry.duplicate(true)
		next.id=sites[selected].id
		next.choose_route=false
		next.campaign=true
		get_tree().set_meta("battle_entry",next)
	get_tree().change_scene_to_file("res://main.tscn")

func _camp():
	var next:=entry.duplicate(true)
	next.stage="camp"
	if preload("res://core/campaign_checkpoint.gd").write_entry(next)!=OK:
		_text(frame,"回营进度保存失败，请重试。",Vector2(62,730),16,Gold)
		return
	get_tree().set_meta("return_to_camp",true)
	_home()

func _reward():
	get_tree().set_meta("chapter_reward_screen",{"entry":entry,"campaign":true})
	_home()

func _home():
	if inspecting:
		closed.emit()
		queue_free()
		return
	get_tree().change_scene_to_file("res://title.tscn")

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_home()
