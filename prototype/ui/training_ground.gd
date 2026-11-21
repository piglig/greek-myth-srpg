extends Control

signal dismissed
signal ask_teacher
const Portraits := preload("res://art/original/interface/training_portraits.webp")
const Bronze := preload("res://art/original/interface/ceramic_marks.svg")
const Case := preload("res://art/original/interface/merchant_case.webp")
const Ivory := Color("#fff0d5")
const Gold := Color("#e8bc79")
const Green := Color("#a8d9be")
const Ash := Color("#b4a99a")
const Order := ["hero","atalanta","chiron","medea"]
const Role := {"hero":"持盾先锋","atalanta":"卡吕冬猎手","chiron":"半人马贤者","medea":"科尔喀斯女巫"}
const Glyph := {"purify_arrow":6,"field_medicine":7,"weak_point":6,"mentor_stagger":8,"kindling":4,"solar_flame":5,"frailty":3,"lingering_hex":7,"shield_wall":1,"intercept":8,"slam":2,"iron_arm":1,"vital_shot":6,"patience":7,"skirmish":12,"leap_shot":6}
var host: Control
var character := ""
var last_character := "hero"
var picked := ""
var note := ""
var progress := {}
var styles := SystemFont.new()

func setup(menu: Control):
	host=menu
	size=Vector2(1366,768)
	mouse_filter=MOUSE_FILTER_STOP
	styles.font_names=PackedStringArray(["Songti SC","STSong","SimSun","Georgia"])
	progress=host.saved_entry.get("picks",{}).duplicate(true)
	if progress.is_empty():progress=SkillTree.default_picks()
	roster()

func _style(fill: Color, edge: Color, width:=1) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=fill
	box.border_color=edge
	box.set_border_width_all(width)
	return box

func _image(tex: Texture2D, rect: Rect2, parent: Control=self) -> TextureRect:
	var image:=TextureRect.new()
	image.texture=tex
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.position=rect.position
	image.size=rect.size
	image.mouse_filter=MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func _slice(tex: Texture2D, region: Rect2) -> AtlasTexture:
	var atlas:=AtlasTexture.new()
	atlas.atlas=tex
	atlas.region=region
	atlas.filter_clip=true
	return atlas

func _portrait(id: String, rect: Rect2, parent: Control):
	var width:=Portraits.get_width()/4
	var tex:=_slice(Portraits,Rect2(Order.find(id)*width,0,width,Portraits.get_height()))
	var portrait:=_image(tex,rect,parent)
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED

func _text(value: String, rect: Rect2, points: int, tint: Color, parent: Control=self) -> Label:
	var l:=Label.new()
	l.text=value
	l.mouse_filter=MOUSE_FILTER_IGNORE
	l.position=rect.position
	l.size=rect.size
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font",styles)
	l.add_theme_font_size_override("font_size",points)
	l.add_theme_color_override("font_color",tint)
	parent.add_child(l)
	return l

func _panel(rect: Rect2, fill: Color, edge: Color, parent: Control=self):
	var p:=Panel.new()
	p.position=rect.position
	p.size=rect.size
	p.mouse_filter=MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",_style(fill,edge))
	parent.add_child(p)

func _button(title: String, rect: Rect2, fn: Callable, edge:=Color("#886a48"), fill:=Color("#302620")) -> Button:
	var b:=Button.new()
	b.text=title
	b.position=rect.position
	b.size=rect.size
	b.mouse_default_cursor_shape=CURSOR_POINTING_HAND
	b.add_theme_font_override("font",styles)
	b.add_theme_font_size_override("font_size",20)
	b.add_theme_color_override("font_color",Ivory)
	b.add_theme_stylebox_override("normal",_style(fill,edge))
	b.add_theme_stylebox_override("hover",_style(fill.lightened(.08),Gold))
	b.add_theme_stylebox_override("focus",_style(Color.TRANSPARENT,Gold,3))
	b.pressed.connect(Soundscape.cue.bind("confirm"))
	b.pressed.connect(fn)
	add_child(b)
	return b

func _base():
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_image(Case,Rect2(0,0,1366,768))
	_panel(Rect2(0,0,1366,768),Color("#18191567"),Color.TRANSPARENT)
	_text("达 蒙  /  练 兵 场",Rect2(69,38,360,31),17,Gold)

func roster():
	character=""
	note=""
	_base()
	_text("谁来操练？",Rect2(65,77,610,80),47,Ivory)
	_button("请教达蒙",Rect2(1002,63,132,44),ask_teacher.emit)
	_button("返回营地",Rect2(1151,63,140,44),dismissed.emit)
	var party: Dictionary=host._party()
	var width:=minf(310.,(1228.-20*(party.size()-1))/party.size())
	var left:=(1366.-party.size()*width-(party.size()-1)*20)*.5
	var i:=0
	for id in party:
		var rect:=Rect2(left+i*(width+20),177,width,460)
		var b:=_button("",rect,_open.bind(id))
		b.tooltip_text="查看"+str(party[id])+"的招式"
		_portrait(id,Rect2(4,4,width-8,308),b)
		_text(Role[id],Rect2(18,322,width-36,28),16,Gold,b)
		_text(party[id],Rect2(16,348,width-32,54),32,Ivory,b)
		var line:="固有招式 · 暂无操练分支"
		if SkillTree.trees().has(id):
			var learned: Array=progress.get(id,[])
			line="已学 %d 招　·　余 %d 点"%[learned.size(),SkillTree.budget(host.saved_entry)-SkillTree.cost(id,learned)]
		_text(line,Rect2(18,413,width-32,34),19,Ash,b)
		if id==last_character:b.grab_focus()
		i+=1
	_text("选择队员，查看个人招式与修习路线。",Rect2(69,676,760,42),20,Ash)

func _open(id: String):
	character=id
	last_character=id
	picked=""
	note=""
	_tree()

func _select(id: String):
	picked=id
	note=""
	_tree()

func _inscription(value: String, center: Vector2, width: float, pts: int, tint: Color) -> Label:
	var label:=_text(value,Rect2(center.x-width/2,center.y-19,width,38),pts,tint)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color",Color("#201913"))
	label.add_theme_constant_override("outline_size",5)
	return label

func _vine(a: Vector2, b: Vector2, ink: Color, thick: float):
	var line:=Line2D.new()
	line.antialiased=true
	line.width=thick
	line.default_color=ink
	var curve:=Curve2D.new()
	var bend:=(b.y-a.y)*.62
	curve.add_point(a,Vector2.ZERO,Vector2(0,bend))
	curve.add_point(b,Vector2(0,-bend),Vector2.ZERO)
	line.points=curve.tessellate(5,2)
	add_child(line)
	if thick<4 and absf(b.x-a.x)>45:
		for fraction in [.24,.72]:
			var at:=curve.sample(0,fraction)
			var tangent:=curve.sample(0,fraction+.02).direction_to(at)
			var normal:=tangent.orthogonal()
			for side: float in [-1.,1.]:
				var tip:=at+tangent*16.+normal*side*10.
				var leaf:=Polygon2D.new()
				leaf.polygon=PackedVector2Array([at,at+tangent*6.+normal*side*8.,tip,at+tangent*10.+normal*side*3.])
				leaf.color=ink.darkened(.12)
				add_child(leaf)

func _seal(pos: Vector2, radius: float, fill: Color, rim: Color) -> Panel:
	var plate:=Panel.new()
	plate.mouse_filter=MOUSE_FILTER_IGNORE
	plate.size=Vector2.ONE*radius*2
	plate.position=pos-plate.size/2
	var style:=_style(fill,rim,2)
	style.set_corner_radius_all(int(radius))
	style.corner_detail=12
	plate.add_theme_stylebox_override("panel",style)
	add_child(plate)
	return plate

func _tree():
	_base()
	var party: Dictionary=host._party()
	var learned: Array=progress.get(character,[])
	var branches: Array=SkillTree.trees()[character]
	var level:=SkillTree.campaign_level(host.saved_entry)
	var budget:=SkillTree.budget(host.saved_entry)
	var remaining:=budget-SkillTree.cost(character,learned)
	_text(party[character]+"的技艺谱",Rect2(65,67,730,75),43,Ivory)
	_text("等级 %d　 /　可用技能点 %d"%[level,remaining],Rect2(70,140,590,35),21,Gold)
	_button("更换队员",Rect2(1151,58,140,44),roster)
	var origin:=Vector2(483,610)
	var coords:={}
	var by_id:={}
	var selected: Dictionary
	var tree_name: String
	var focused: Button
	for arm in branches.size():
		var branch: Dictionary=branches[arm]
		var x:=264.+arm*444.
		var spots:=[Vector2(x,470),Vector2(x-97,335),Vector2(x+97,335),Vector2(x-119,204),Vector2(x+119,204)]
		for idx in branch.nodes.size():
			var node: Dictionary=branch.nodes[idx]
			coords[node.id]=spots[idx]
			by_id[node.id]=node
			if picked=="":picked=node.id
			if picked==node.id:
				selected=node
				tree_name=branch.branch
			var start: Vector2=origin if node.parent=="" else coords[node.parent]
			var end: Vector2=spots[idx]
			var ink:=Color("#75a79b") if learned.has(node.id) else Color("#b18e59") if node.parent=="" or learned.has(node.parent) else Color("#675a48")
			_vine(start,end,Color("#1c1916"),8)
			_vine(start,end,ink,3)
	_seal(origin,35,Color("#483328"),Gold)
	_portrait(character,Rect2(origin-Vector2(22,25),Vector2(44,50)),self)
	_inscription(Role[character],origin+Vector2(0,55),280,21,Ivory)
	for arm in branches.size():
		var branch: Dictionary=branches[arm]
		for idx in branch.nodes.size():
			var node: Dictionary=branch.nodes[idx]
			var pos: Vector2=coords[node.id]
			var have:=learned.has(node.id)
			var ready:bool=node.parent=="" or learned.has(node.parent)
			var status:="已掌握" if have else ("前置未学" if not ready else ("可学习" if remaining>=int(node.cost) else "点数不足"))
			var tint:=Green if have else Gold if status=="可学习" else Color("#aaa092")
			var fill:=Color("#29413b") if have else Color("#533c24") if status=="可学习" else Color("#302c29")
			var radius:=30 if idx>=3 else 26
			if picked==node.id:_seal(pos,radius+6,Color("#211d18"),Ivory)
			_seal(pos,radius,fill,tint)
			var glyph:int=Glyph.get(node.id,[1,7,6,8,0][idx] if arm==0 else [2,5,3,4,7][idx])
			_image(_slice(Bronze,Rect2((glyph%9)*48,(glyph/9)*48,48,48)),Rect2(pos-Vector2(17,17),Vector2(34,34)))
			_inscription(node.name,pos+Vector2(0,45),172,22,Ivory if have or ready else Ash)
			_inscription(status,pos+Vector2(0,69),160,15,tint)
			var btn:=Button.new()
			btn.flat=true
			btn.position=pos-Vector2(76,32)
			btn.size=Vector2(152,115)
			btn.tooltip_text=node.name+" · "+status
			btn.mouse_default_cursor_shape=CURSOR_POINTING_HAND
			for state in ["normal","hover","pressed"]:btn.add_theme_stylebox_override(state,StyleBoxEmpty.new())
			btn.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
			btn.focus_entered.connect(func():btn.modulate=Color("#fff0ca"))
			btn.pressed.connect(_select.bind(node.id))
			add_child(btn)
			if node.id==picked:focused=btn
		_inscription(branch.branch,Vector2(264+arm*444,570),245,23,Gold)
	_panel(Rect2(949,162,351,477),Color("#2b241e"),Color("#766044"))
	_portrait(character,Rect2(1195,177,88,103),self)
	_text(tree_name+"　/　"+("招式" if selected.has("skill") or selected.id=="slam" else "特性"),Rect2(977,192,300,36),19,Gold)
	_text(selected.name,Rect2(976,249,308,65),34,Ivory)
	_text(selected.desc,Rect2(978,321,285,105),22,Ivory)
	var parent_name: String=by_id[selected.parent].name if selected.parent!="" else "无"
	_text("前置　"+parent_name+"\n修习　%d 点"%selected.cost,Rect2(978,442,287,75),18,Ash)
	var next:=learned.duplicate()
	var known:=next.has(picked)
	if known:next.erase(picked)
	else:next.append(picked)
	var legal:=SkillTree.validate(character,next,budget)==""
	var title:="退还 %d 点"%selected.cost if known else "学习　%d 点"%selected.cost
	if not legal:
		title="先退还后续招式" if known else ("先学「"+parent_name+"」" if selected.parent!="" and not learned.has(selected.parent) else "还差 %d 点"%(selected.cost-remaining))
	var btn:=_button(title,Rect2(977,546,294,58),_apply.bind(next),Gold,Color("#69462e"))
	btn.disabled=not legal
	_text(note if note!="" else "首次通关一节，全队升一级。每级获得 1 点，已学技艺可退点重修。",Rect2(70,698,1220,38),18,Ash)
	if focused:focused.grab_focus()

func _apply(next: Array):
	if SkillTree.validate(character,next,SkillTree.budget(host.saved_entry))!="":return
	var updated:=progress.duplicate(true)
	updated[character]=next.duplicate()
	var entry: Dictionary=host.saved_entry.duplicate(true)
	entry.picks=updated
	if host._persist(entry):
		progress=updated
		note="已保存"+str(host._party()[character])+"的操练结果。"
	else:note="保存失败，技能点和已学招式保持原状。"
	_tree()

func _unhandled_key_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if character=="":dismissed.emit()
		else:roster()
