extends Control

const Save := preload("res://core/campaign_checkpoint.gd")
const Paper := Color("#fff0d4")
const Brass := Color("#ebc384")
const Roles := ["腓尼基行商","老教习","领路人"]
const Names := ["阿齐尔","达蒙","伊俄"]
const Stations := [Vector2(210,394),Vector2(632,343),Vector2(1150,384)]
const Topics := ["这些护符从哪来？","教我一招。","说说前面的路。"]
signal prepare
signal depart
signal leave
var host: Control
var canvas := Control.new()
var overlay := Control.new()
var serif := SystemFont.new()
var person := -1
var last_person := 0
var layer := "yard"
var camera: Tween
var choice_x := 58.
var choice_y := 676.
var first_choice: Button

func setup(menu: Control):
	host=menu
	size=Vector2(1366,768)
	clip_contents=true
	serif.font_names=PackedStringArray(["Songti SC","STSong","SimSun","Georgia"])
	canvas.size=size
	add_child(canvas)
	canvas.add_child(preload("res://ui/camp_work.gd").new())
	overlay.size=size
	add_child(overlay)
	yard()

func _clear():
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	first_choice=null
	choice_x=58.
	choice_y=676.

func _pan(zoom: float, anchor: Vector2):
	if camera:camera.kill()
	camera=create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	camera.tween_property(canvas,"scale",Vector2.ONE*zoom,.40)
	camera.tween_property(canvas,"position",-anchor*(zoom-1.),.40)

func _words(value: String, pos: Vector2, pts: int, tone: Color, parent: Control=null) -> Label:
	var label:=Label.new()
	label.text=value
	label.position=pos
	label.mouse_filter=MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",serif)
	label.add_theme_font_size_override("font_size",pts)
	label.add_theme_color_override("font_color",tone)
	label.add_theme_color_override("font_shadow_color",Color("#16130fe0"))
	label.add_theme_constant_override("shadow_offset_y",2)
	(overlay if parent==null else parent).add_child(label)
	return label

func _button(value: String, rect: Rect2, action: Callable, invisible:=false) -> Button:
	var b:=Button.new()
	b.text=value
	b.position=rect.position
	b.size=rect.size
	b.mouse_default_cursor_shape=CURSOR_POINTING_HAND
	b.add_theme_font_override("font",serif)
	b.add_theme_font_size_override("font_size",20)
	b.add_theme_color_override("font_color",Paper)
	for key in ["normal","hover","focus","pressed"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color.TRANSPARENT if invisible else (Color("#25221fdf") if key=="normal" else Color("#764b32"))
		if not invisible:
			style.border_width_bottom=1
			style.border_color=Brass
		b.add_theme_stylebox_override(key,style)
	overlay.add_child(b)
	b.pressed.connect(Soundscape.cue.bind("confirm"))
	b.pressed.connect(action)
	return b

func yard():
	layer="yard"
	person=-1
	_clear()
	_pan(1.,Vector2.ZERO)
	_words("行 军 营 地",Vector2(50,32),34,Paper)
	_words(str(host.saved_entry.get("camp_summary","队伍驻扎于此。")),Vector2(53,84),19,Brass)
	for i in Roles.size():
		var at: Vector2=Stations[i]
		var hit:=_button("",Rect2(at-Vector2(118,213),Vector2(236,390)),talk.bind(i),true)
		hit.tooltip_text=Roles[i]+" · "+Names[i]
		var plate:=Panel.new()
		plate.mouse_filter=MOUSE_FILTER_IGNORE
		plate.size=Vector2(134,39)
		plate.position=Vector2(51,351)
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("#201e19db")
		style.border_width_bottom=1
		style.border_color=Brass.darkened(.25)
		plate.add_theme_stylebox_override("panel",style)
		hit.add_child(plate)
		var nameplate:=_words(Roles[i],Vector2.ZERO,20,Paper,plate)
		nameplate.size=plate.size
		nameplate.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		nameplate.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		hit.focus_entered.connect(func():nameplate.modulate=Brass; plate.scale=Vector2.ONE*1.05)
		hit.focus_exited.connect(func():nameplate.modulate=Color.WHITE; plate.scale=Vector2.ONE)
		hit.mouse_entered.connect(hit.grab_focus)
		if i==last_person:hit.grab_focus()
	_button("队伍行囊",Rect2(1050,696,130,44),shop.bind(true))
	_words("点选人物交谈",Vector2(52,708),18,Paper)
	_button("返回首页",Rect2(1200,696,116,44),leave.emit)

func _panel(stage: String, line: String):
	layer=stage
	_clear()
	var backdrop:=TextureRect.new()
	var gradient:=Gradient.new()
	gradient.colors=PackedColorArray([Color("#17171400"),Color("#171714e8"),Color("#171714fc")])
	gradient.offsets=PackedFloat32Array([0.,.32,1.])
	var shade:=GradientTexture2D.new()
	shade.gradient=gradient
	shade.fill_to=Vector2(0,1)
	backdrop.texture=shade
	backdrop.position=Vector2(0,459)
	backdrop.size=Vector2(1366,309)
	backdrop.mouse_filter=MOUSE_FILTER_IGNORE
	overlay.add_child(backdrop)
	_words(Names[person],Vector2(56,533),36,Paper)
	_words(Roles[person],Vector2(198,550),18,Brass)
	_words(line,Vector2(58,607),24,Paper)
	if person==0:_words("%d 德拉克马"%host._coins(),Vector2(1120,553),20,Brass)

func _choice(value: String, callback: Callable, enabled:=true):
	var width:=maxf(106.,serif.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x+38.)
	var b:=_button(value,Rect2(choice_x,choice_y,width,48),callback)
	choice_x+=width+14
	b.disabled=not enabled
	if enabled and first_choice==null:
		first_choice=b
		b.grab_focus()

func talk(index: int, converse:=false):
	person=index
	last_person=index
	if index==1 and not converse:
		prepare.emit()
		return
	_pan(1.19,Stations[index])
	var lines:=["坐。我这秤称过腓尼基的银子，也称过阿卡迪亚最后一袋麦子。",
		"把盾放低些。你看得见我的肩，才看得见我什么时候出手。",
		"过来搭把手，压住这张图。夜里起风，明早的路可不能让它吹走。"]
	_panel("talk",lines[index])
	_choice(Topics[index],_story)
	match index:
		0:_choice("看看你的货",shop)
		1:_choice("一起操练",prepare.emit)
		2:
			_choice("清点队伍行装",_roster)
			_choice("展开行军图",depart.emit)
	_choice("告辞",yard)

func _roster():
	var party: Dictionary=host._party()
	var entry: Dictionary=host.saved_entry
	var line: String="今晚同行的人都在："+"、".join(party.values())+"。"
	if entry.has("equipped_relic"):
		line+="　狮皮由主角保管，同行的神赐是「"+str(Save.BOONS[entry.boon][1])+"」。"
	_panel("story",line)
	_choice("展开行军图",depart.emit)
	_choice("告辞",yard)

func _story():
	var entry: Dictionary=host.saved_entry
	var line: String
	match person:
		0:
			line="这枝橄榄是我女儿削的。举盾喘口气的时候，摸一摸，就记得为什么要活着回来。"
			if entry.get("rescued",[]).size()>=2:line="林道上得救的人替我把货送到了。那只牛皮腕带，就是赶车的老人亲手缝的。"
		1:
			line="记着狼扑过来的那一瞬。先稳后脚，再把盾送出去。光靠胳膊，你挡不住第二下。"
			if str(entry.get("camp_summary","")).contains("失利"):line="先别急着重来。告诉我，敌人逼近时是谁站得太靠前了？下一次，让盾手先接敌。"
			elif entry.get("chiron_joined",false):line="喀戎看了你的步子。他说弓手找的就是你抬盾时露出的空当。来，我们再走一遍。"
		2:
			line="我已把下一处落脚点圈在图上。先看路口，再看敌人能从哪边绕到你背后。"
			if entry.get("choose_route",false):line="村民说山上还亮着酒宴的灯。往山里去能赶上宴席，向东走则直通涅墨亚。"
			elif entry.get("id")=="2-1":
				line="东门已经安全，美狄亚和我们一道走。今晚可以收起这张刑场图了。" if entry.get("outcomes",{}).has("2-1") else "科林斯的东门有条窄路。接到美狄亚就往那里撤，别为了追守卫把她落下。"
	_panel("story",line)
	match person:
		0:_choice("看看你的货",shop)
		1:_choice("一起操练",prepare.emit)
		2:_choice("展开行军图",depart.emit)
	_choice("告辞",yard)

func shop(bag:=false):
	layer="inventory"
	_clear()
	var inventory:=preload("res://ui/merchant_inventory.gd").new()
	overlay.add_child(inventory)
	inventory.closed.connect(func():
		if person<0:yard()
		else:talk(person))
	inventory.setup(host,bag,person==0)

func back():
	match layer:
		"yard":leave.emit()
		"talk":yard()
		"story":talk(person)
		"inventory":overlay.get_child(0).back()
