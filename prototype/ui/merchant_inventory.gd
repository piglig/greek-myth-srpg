extends Control

signal closed
const Catalog := preload("res://core/campaign_checkpoint.gd")
const Icons := preload("res://art/original/interface/merchant_goods.webp")
const Ivory := Color("#f5e6c9")
const Gold := Color("#d9b678")
const Case := preload("res://art/original/interface/merchant_case.webp")
const Muted := Color("#c1aa86")
const Categories := ["全部","攻势","守御","行军"]
var host: Control
var bag := false
var at_stall := false
var category := "全部"
var selected := ""
var assigning := false
var message := ""
var font := SystemFont.new()

func setup(menu: Control, open_bag: bool, trading: bool):
	host=menu
	bag=open_bag
	at_stall=trading
	size=Vector2(1366,768)
	font.font_names=PackedStringArray(["Songti SC","STSong","SimSun","Georgia"])
	_render()

func _box(fill: Color, edge: Color, stroke:=1) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=edge
	style.set_border_width_all(stroke)
	return style

func _panel(rect: Rect2, fill: Color, edge: Color):
	var panel:=Panel.new()
	panel.add_theme_stylebox_override("panel",_box(fill,edge))
	panel.mouse_filter=MOUSE_FILTER_IGNORE
	panel.position=rect.position
	panel.size=rect.size
	add_child(panel)

func _text(caption: String, rect: Rect2, pts: int, tone: Color, center:=false) -> Label:
	var l:=Label.new()
	l.text=caption
	l.mouse_filter=MOUSE_FILTER_IGNORE
	l.position=rect.position
	l.size=rect.size
	l.add_theme_font_override("font",font)
	l.add_theme_font_size_override("font_size",pts)
	l.add_theme_color_override("font_color",tone)
	if center:l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l

func _button(caption: String, rect: Rect2, action: Callable, active:=false) -> Button:
	var b:=Button.new()
	b.text=caption
	b.position=rect.position
	b.size=rect.size
	b.mouse_default_cursor_shape=CURSOR_POINTING_HAND
	b.add_theme_font_override("font",font)
	b.add_theme_font_size_override("font_size",19)
	b.add_theme_color_override("font_color",Ivory)
	b.add_theme_stylebox_override("normal",_box(Color("#684631") if active else Color("#322b25"),Gold if active else Color("#695541")))
	b.add_theme_stylebox_override("hover",_box(Color("#614932"),Gold))
	var focus:=_box(Color.TRANSPARENT,Color("#ffdc95"),2)
	b.add_theme_stylebox_override("focus",focus)
	b.pressed.connect(Soundscape.cue.bind("confirm"))
	b.pressed.connect(action)
	add_child(b)
	return b

func _icon(index: int, rect: Rect2):
	var image:=TextureRect.new()
	var atlas:=AtlasTexture.new()
	atlas.atlas=Icons
	var cell:=Vector2(Icons.get_width()/3.,Icons.get_height()/2.)
	atlas.region=Rect2(Vector2(index%3,index/3)*cell,cell)
	image.texture=atlas
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter=MOUSE_FILTER_IGNORE
	image.position=rect.position
	image.size=rect.size
	add_child(image)

func _switch(to_bag: bool, group: String):
	bag=to_bag
	category=group
	selected=""
	assigning=false
	message=""
	_render()

func _select(id: String):
	selected=id
	assigning=false
	message=""
	_render()

func _render():
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var purse: Dictionary=host.saved_entry.get("purse",{})
	var owned: Array=purse.get("owned",[])
	var equipped: Dictionary=purse.get("equipped",{})
	var visible_items: Array[String]=[]
	for id in Catalog.GOODS:
		if bag and not owned.has(id):continue
		if not bag and not Catalog.stocked(id,host.saved_entry):continue
		if category=="全部" or Catalog.GOODS[id].group==category:visible_items.append(id)
	if not visible_items.has(selected):
		selected="" if visible_items.is_empty() else visible_items[0]
	_panel(Rect2(0,0,1366,768),Color("#100e0bc2"),Color.TRANSPARENT)
	var leather:=TextureRect.new()
	leather.texture=Case
	leather.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	leather.position=Vector2(105,68)
	leather.size=Vector2(1156,635)
	leather.mouse_filter=MOUSE_FILTER_IGNORE
	add_child(leather)
	_text("队伍行囊" if bag else "阿齐尔的货摊",Rect2(147,93,550,62),40,Ivory)
	_icon(5,Rect2(914,102,46,40))
	_text("%d 德拉克马"%host._coins(),Rect2(968,105,175,40),23,Gold)
	_button("离开",Rect2(1140,99,83,44),closed.emit)
	if at_stall:_button("商人货物",Rect2(147,172,154,46),_switch.bind(false,"全部"),not bag)
	_button("队伍行囊",Rect2(311 if at_stall else 147,172,154,46),_switch.bind(true,"全部"),bag)
	for i in Categories.size():
		_button(Categories[i],Rect2(147+i*110,237,98,36),_switch.bind(bag,Categories[i]),category==Categories[i])
	var chosen: Button
	for i in maxi(6,visible_items.size()):
		var pos:=Vector2(147+i%3*164,297+i/3*148)
		var bounds:=Rect2(pos,Vector2(150,135))
		if i>=visible_items.size():
			_panel(bounds,Color("#221f1b"),Color("#463c30"))
			continue
		var id:=visible_items[i]
		var g: Dictionary=Catalog.GOODS[id]
		var b:=_button("",bounds,_select.bind(id),selected==id)
		b.add_theme_stylebox_override("normal",_box(Color("#97683a6e") if selected==id else Color("#34282283"),Gold if selected==id else Color("#7a5e41")))
		b.tooltip_text=g.name+" · "+g.effect
		_icon(g.icon,Rect2(pos+Vector2(32,7),Vector2(86,79)))
		_text(g.name,Rect2(pos+Vector2(0,88),Vector2(150,27)),20,Ivory,true)
		var tag: String="已购" if owned.has(id) else "%d 德拉克马"%g.price
		if bag:tag=host._party().get(equipped.get(id,""),"收在行囊")
		_text(tag,Rect2(pos+Vector2(0,112),Vector2(150,21)),14,Gold,true)
		if id==selected:chosen=b
	_text("%d 件%s"%[visible_items.size(),"随身物品" if bag else "在售货物"],Rect2(148,632,460,31),18,Muted)
	if selected=="":
		_text("行囊里还没有这类物品。" if bag else "此分类暂无货物。",Rect2(723,356,436,85),24,Muted,true)
		for control in get_children():
			if control is Button and control.text==category:control.grab_focus();break
		return
	var goods: Dictionary=Catalog.GOODS[selected]
	_text("护符  /  "+goods.group,Rect2(720,178,320,28),17,Gold)
	_icon(goods.icon,Rect2(851,207,190,156))
	_text(goods.name,Rect2(720,365,460,48),33,Ivory)
	_text(goods.lore,Rect2(722,419,475,72),19,Muted)
	_text(goods.effect,Rect2(722,498,474,38),22,Ivory)
	var wearer: String=host._party().get(equipped.get(selected,""),"行囊")
	var note: String=message
	if note=="":note="所在　"+wearer if owned.has(selected) else "售价　%d 德拉克马"%goods.price
	_text(note,Rect2(722,546,472,34),18,Gold)
	if assigning:
		var party: Dictionary=host._party()
		var i:=0
		for who in party:
			var prior=equipped.find_key(who)
			var caption: String=party[who]
			if prior!=null:caption+=" · "+str(Catalog.GOODS[prior].name)
			var slot:=_button(caption,Rect2(720+i%2*247,586+i/2*45,235,40),_assign.bind(who))
			if i==0:slot.grab_focus()
			i+=1
	else:
		if owned.has(selected):
			_button("分配护符",Rect2(720,596,220,50),_choose_wearer,true)
			if equipped.has(selected):_button("卸下放回行囊",Rect2(950,596,226,50),_assign.bind(""))
		else:
			var enough:bool=host._coins()>=goods.price
			var buy:=_button("购买　%d"%goods.price if enough else "还差 %d 德拉克马"%(goods.price-host._coins()),Rect2(720,596,456,50),_buy,true)
			buy.disabled=not enough
	if chosen and not assigning:chosen.grab_focus()

func _choose_wearer():
	assigning=true
	message="选择佩戴者，将替换该角色当前的护符。"
	_render()

func _assign(who: String):
	if host._assign_charm(selected,who):
		message="已放回行囊" if who=="" else "已交给"+str(host._party()[who])
	else:message="换装保存失败，请重试。"
	assigning=false
	_render()

func _buy():
	message="已收入队伍行囊" if host._buy(selected) else "购买未完成，请检查余额后重试。"
	_render()

func back():
	if assigning:
		assigning=false
		message=""
		_render()
	else:closed.emit()
