class_name Px
## The interface kit. Menus are laid out on a 960x540 canvas shown at twice its size (the
## project's 1920x1080 base). The look is spare: translucent ink sheets over the live
## battlefield, hairline rules, one pixel typeface in whole multiples of its design size.

const SIZE := Vector2(960,540)
const ART := "res://art/pixel_ui/"
const INK := Color("#14100d")
const CLAY := Color("#c47a3e")
const CLAY_DARK := Color("#7a4626")
const OCHRE := Color("#e2ac60")
const IVORY := Color("#f4e5c6")
const MUTED := Color("#a8947a")
const FAINT := Color("#6f6152")
const RED := Color("#a8402a")
const GREEN := Color("#9ec9a4")
const BLUE := Color("#8fb6c9")
## Text sizes on the canvas. SMALL uses the 10-pixel face, the rest the 12-pixel one.
const SMALL := 10
const BODY := 12
const TITLE := 24
const DISPLAY := 36

static var _faces := {}
static var _cache := {}
## Whether the window shows the canvas at a whole multiple of its size. Only then can the
## pixel face be drawn dot for dot; at any other size its strokes are smoothed, or they
## come out uneven and letters run together.
static var _whole := true


## Tells the faces how large the window is, so they are drawn the way that reads best.
## The canvas is doubled and then stretched to the window; left to itself the engine
## would draw each letter at the stretched size and double that, which at 1280x720 means
## eight-pixel letters blown up. So away from whole multiples the letters are drawn at the
## size they will really have on screen.
static func fit_window(window: Window) -> void:
	var by := minf(window.size.x/SIZE.x,window.size.y/SIZE.y)
	var whole := by >= 1.0 and absf(by-roundf(by)) < .02
	window.oversampling_override = 0.0 if whole else by
	if whole == _whole: return
	_whole = whole
	for face: FontFile in _faces.values():
		face.antialiasing = TextServer.FONT_ANTIALIASING_NONE if whole else TextServer.FONT_ANTIALIASING_GRAY


static func font(points: int) -> FontFile:
	var design := 10 if points % 10 == 0 and points % 12 != 0 else 12
	if not _faces.has(design):
		var face := load("res://art/thirdparty/fusion-pixel/fusion-pixel-%dpx-proportional-zh_hans.ttf" % design) as FontFile
		face.antialiasing = TextServer.FONT_ANTIALIASING_NONE if _whole else TextServer.FONT_ANTIALIASING_GRAY
		face.hinting = TextServer.HINTING_NONE
		face.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_faces[design] = face
	return _faces[design]


static func art(name: String) -> Texture2D:
	return load(ART+name+".png")


## A canvas of SIZE centred in `host` and kept at a whole-number scale.
static func stage(host: Control) -> Control:
	var canvas := Control.new()
	canvas.size = SIZE
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(canvas)
	var fit_canvas := func():
		var factor := maxf(1.0,floorf(minf(host.size.x/SIZE.x,host.size.y/SIZE.y)))
		canvas.scale = Vector2.ONE*factor
		canvas.position = ((host.size-SIZE*factor)*.5).floor()
	host.resized.connect(fit_canvas)
	fit_canvas.call()
	return canvas


static func flat(fill: Color, edge := Color.TRANSPARENT, sides := [0,0,0,0], pad := Vector2(8,2)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.border_width_left = sides[0]
	style.border_width_top = sides[1]
	style.border_width_right = sides[2]
	style.border_width_bottom = sides[3]
	style.content_margin_left = pad.x
	style.content_margin_right = pad.x
	style.content_margin_top = pad.y
	style.content_margin_bottom = pad.y
	style.anti_aliasing = false
	return style


static func block(parent: Control, rect: Rect2, tone: Color) -> ColorRect:
	var fill := ColorRect.new()
	fill.color = tone
	fill.position = rect.position
	fill.size = rect.size
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fill)
	return fill


## A panel: black glaze, streaked as the wheel leaves it, with two opposite corners cut as
## a tag is trimmed, and an edge drawn with a brush rather than a rule. Bars that run the
## width of the screen, and small labels, keep square corners.
static func sheet(parent: Control, rect: Rect2, weight := .80, lined := true) -> Control:
	var panel := Control.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(panel)
	var cut := 10.0 if rect.size.y >= 60 and rect.size.x < SIZE.x-1 else 0.0
	var salt := int(rect.position.x*7+rect.position.y*13+rect.size.x)
	panel.draw.connect(func():
		var size := panel.size
		var shape := PackedVector2Array([Vector2.ZERO,Vector2(size.x-cut,0),Vector2(size.x,cut),size,Vector2(cut,size.y),Vector2(0,size.y-cut)])
		var uvs := PackedVector2Array()
		for point in shape: uvs.append((panel.position+point)/128.0)
		panel.draw_colored_polygon(shape,Color(1,1,1,weight),uvs,Vase.glaze())
		if not lined: return
		# Brighter along the top and round the cut corner, fainter along the foot.
		var waver := .7 if size.y >= 60 else 0.0
		var top := Vase.stroke(Vector2(0,.5),Vector2(size.x-cut,.5),waver,salt)
		top.append(Vector2(size.x-.5,cut))
		panel.draw_polyline(top,Color(OCHRE,.6),1.0)
		var foot := PackedVector2Array([Vector2(.5,size.y-cut)])
		foot.append_array(Vase.stroke(Vector2(cut,size.y-.5),Vector2(size.x,size.y-.5),waver,salt+3))
		panel.draw_polyline(foot,Color(OCHRE,.28),1.0)
		if cut > 0:
			# A bead where each cut begins, as a rivet holds a plate.
			panel.draw_circle(Vector2(size.x-cut-5,5),1.5,Color(OCHRE,.7))
			panel.draw_circle(Vector2(cut+5,size.y-5),1.5,Color(OCHRE,.35)))
	return panel


static func rule(parent: Control, at: Vector2, length: float, tone := Color(OCHRE,.4), upright := false) -> ColorRect:
	return block(parent,Rect2(at,Vector2(1,length) if upright else Vector2(length,1)),tone)


static func picture(parent: Control, texture: Texture2D, rect: Rect2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.position = rect.position
	image.size = rect.size
	parent.add_child(image)
	return image


static func text(parent: Control, value: String, rect: Rect2, points := BODY, tone := IVORY, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var line := Label.new()
	line.text = value
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.horizontal_alignment = align
	# Wrapping has to be on before the width is set, or the label keeps its one-line width.
	if rect.size.x > 0:
		line.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	line.position = rect.position
	line.size = rect.size
	line.add_theme_font_override("font",font(points))
	line.add_theme_font_size_override("font_size",points)
	line.add_theme_color_override("font_color",tone)
	line.add_theme_constant_override("line_spacing",3)
	parent.add_child(line)
	return line


## Text set straight on the scene, with a one-pixel ink edge so it reads on any ground.
static func caption(parent: Control, value: String, rect: Rect2, points := BODY, tone := IVORY, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var line := text(parent,value,rect,points,tone,align)
	line.add_theme_color_override("font_outline_color",INK)
	line.add_theme_constant_override("outline_size",4 if points >= TITLE else 2)
	return line


## Height of `value` set in `points` and wrapped to `width` canvas pixels.
static func measure(value: String, points: int, width: float) -> float:
	var face := font(points)
	var lines := 0
	for paragraph in value.split("\n"):
		var run := face.get_string_size(paragraph,HORIZONTAL_ALIGNMENT_LEFT,-1,points).x
		lines += maxi(1,ceili(run/maxf(1.0,width)))
	return lines*(face.get_height(points)+3.0)


static func width_of(value: String, points := BODY) -> float:
	return font(points).get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,points).x


static func _control(parent: Control, value: String, rect: Rect2, action: Callable, points: int) -> Button:
	var control := Button.new()
	control.text = value
	control.position = rect.position
	control.size = rect.size
	control.clip_text = true
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.add_theme_font_override("font",font(points))
	control.add_theme_font_size_override("font_size",points)
	control.add_theme_color_override("font_disabled_color",FAINT)
	parent.add_child(control)
	control.pressed.connect(Soundscape.cue.bind("confirm"))
	if action.is_valid():
		control.pressed.connect(action)
	control.focus_entered.connect(Soundscape.cue.bind("focus"))
	control.mouse_entered.connect(func():
		if not control.disabled:
			control.grab_focus())
	return control


static func _paint(control: Button, rest: StyleBox, lit: StyleBox, off: StyleBox, ink_rest: Color, ink_lit: Color) -> void:
	control.add_theme_stylebox_override("normal",rest)
	control.add_theme_stylebox_override("hover",lit)
	control.add_theme_stylebox_override("focus",lit)
	control.add_theme_stylebox_override("pressed",lit)
	control.add_theme_stylebox_override("disabled",off)
	control.add_theme_color_override("font_color",ink_rest)
	for state in ["font_hover_color","font_focus_color","font_pressed_color","font_hover_pressed_color"]:
		control.add_theme_color_override(state,ink_lit)


## Rounds a box's corners, in whole pixels, so buttons read as tags and not as cells.
static func rounded(style: StyleBoxFlat, radius: float) -> StyleBoxFlat:
	style.set_corner_radius_all(int(radius))
	style.anti_aliasing = false
	return style


## The main action on a screen: a solid tag, round at both ends.
static func primary(parent: Control, value: String, rect: Rect2, action: Callable) -> Button:
	var control := _control(parent,value,rect,action,BODY)
	var turn := rect.size.y*.5
	_paint(control,rounded(flat(RED,OCHRE,[1,1,1,1]),turn),rounded(flat(RED.lightened(.14),IVORY,[1,1,1,1]),turn),rounded(flat(Color(INK,.6),FAINT,[1,1,1,1]),turn),IVORY,IVORY)
	return control


## An ordinary action: an outlined tag that fills when pointed at.
static func button(parent: Control, value: String, rect: Rect2, action: Callable) -> Button:
	var control := _control(parent,value,rect,action,BODY)
	var turn := minf(rect.size.y*.5,14.0)
	_paint(control,rounded(flat(Color(INK,.55),Color(OCHRE,.5),[1,1,1,1]),turn),rounded(flat(Color(CLAY_DARK,.9),OCHRE,[1,1,1,1]),turn),rounded(flat(Color(INK,.4),Color(FAINT,.6),[1,1,1,1]),turn),IVORY,IVORY)
	return control


## A page tab: plain words with a bar under the open one.
static func tab(parent: Control, value: String, rect: Rect2, open: bool, action: Callable) -> Button:
	var control := _control(parent,value,rect,action,BODY)
	var bar := flat(Color.TRANSPARENT,OCHRE,[0,0,0,2],Vector2(4,2))
	var none := flat(Color.TRANSPARENT,Color.TRANSPARENT,[0,0,0,2],Vector2(4,2))
	_paint(control,bar if open else none,flat(Color(CLAY_DARK,.45),OCHRE if open else Color(OCHRE,.5),[0,0,0,2],Vector2(4,2)),none,IVORY if open else MUTED,IVORY)
	return control


## A line in a list: left-aligned, with a marker bar when chosen.
static func row(parent: Control, value: String, rect: Rect2, chosen: bool, action: Callable, points := BODY) -> Button:
	var control := _control(parent,value,rect,action,points)
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var rest := flat(Color(CLAY_DARK,.55) if chosen else Color.TRANSPARENT,OCHRE if chosen else Color.TRANSPARENT,[2,0,0,0],Vector2(10,2))
	var lit := flat(Color(CLAY_DARK,.8),IVORY,[2,0,0,0],Vector2(10,2))
	# The marker stays square on the left; the far end is turned.
	for style: StyleBoxFlat in [rest,lit]:
		style.corner_radius_top_right = int(minf(rect.size.y*.5,10.0))
		style.corner_radius_bottom_right = int(minf(rect.size.y*.5,10.0))
		style.anti_aliasing = false
	_paint(control,rest,lit,flat(Color.TRANSPARENT,Color.TRANSPARENT,[2,0,0,0],Vector2(10,2)),IVORY if chosen else MUTED,IVORY)
	return control


## An invisible press area over something drawn underneath, outlined when focused.
static func hotspot(parent: Control, rect: Rect2, action: Callable, hint := "") -> Button:
	var control := _control(parent,"",rect,action,BODY)
	control.tooltip_text = hint
	var none := StyleBoxEmpty.new()
	var ring := flat(Color(OCHRE,.10),OCHRE,[1,1,1,1])
	_paint(control,none,ring,none,IVORY,IVORY)
	return control


## A scrolling window onto `height` pixels of content. Draw into the control it returns.
## The bar is a thin ochre line; lists follow the keyboard focus.
static func scroll(parent: Control, rect: Rect2, height: float) -> Control:
	var area := ScrollContainer.new()
	area.position = rect.position
	area.size = rect.size
	area.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	area.follow_focus = true
	var bar := area.get_v_scroll_bar()
	bar.custom_minimum_size.x = 3
	bar.add_theme_stylebox_override("scroll",flat(Color(INK,.5),Color.TRANSPARENT,[0,0,0,0],Vector2.ZERO))
	bar.add_theme_stylebox_override("grabber",flat(Color(OCHRE,.6),Color.TRANSPARENT,[0,0,0,0],Vector2.ZERO))
	bar.add_theme_stylebox_override("grabber_highlight",flat(OCHRE,Color.TRANSPARENT,[0,0,0,0],Vector2.ZERO))
	bar.add_theme_stylebox_override("grabber_pressed",flat(IVORY,Color.TRANSPARENT,[0,0,0,0],Vector2.ZERO))
	parent.add_child(area)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(rect.size.x-6,height)
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	area.add_child(inner)
	return inner


## Arrow keys walk these controls in order and wrap at either end.
static func chain(controls: Array, vertical := true) -> void:
	var live := controls.filter(func(c): return c is Button and not c.disabled)
	for i in live.size():
		var here: Control = live[i]
		var before: NodePath = here.get_path_to(live[posmod(i-1,live.size())])
		var after: NodePath = here.get_path_to(live[(i+1)%live.size()])
		if vertical:
			here.focus_neighbor_top = before
			here.focus_neighbor_bottom = after
		else:
			here.focus_neighbor_left = before
			here.focus_neighbor_right = after


static func clear(parent: Control) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## A technique can share a drawing, or share its ID with a different status badge.
static func technique_stamp(id: String) -> String:
	const STAMPS := {"pho_gallop":"eury_gallop","pho_vault":"eury_vault",
		"kindling":"medea_kindling","bind_hex":"medea_bind_hex"}
	return STAMPS.get(id,id)


static func icon_path(name: String) -> String:
	var original := "res://art/original/icons/%s.svg" % name
	if ResourceLoader.exists(original):
		return original
	return "res://art/thirdparty/game-icons/%s.svg" % name


## Rasterize the stamp at its display size before applying the interface tint.
static func icon(name: String, size := 16) -> Texture2D:
	var key := "icon/%s/%d" % [name,size]
	if not _cache.has(key):
		var path := icon_path(name)
		var image: Image
		if ResourceLoader.exists(path):
			image = (load(path) as Texture2D).get_image()
		else:
			image = Image.create(size,size,false,Image.FORMAT_RGBA8)
		image.convert(Image.FORMAT_RGBA8)
		# The files are white drawings on a black square: brightness becomes the stamp.
		image.resize(size,size,Image.INTERPOLATE_LANCZOS)
		for y in size:
			for x in size:
				var value := image.get_pixel(x,y)
				image.set_pixel(x,y,Color(1,1,1,1.0 if value.v*value.a > .5 else 0.0))
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


## Units drawn on four legs, whose portrait is the whole animal.
const BEASTS := ["wolf","boar","lion"]

## The face of a unit, cut from the sprite it fights with.
static func face(def_id: String, size := 32) -> Texture2D:
	var key := "face/%s/%d" % [def_id,size]
	if not _cache.has(key):
		var sheet_image: Image = (load("res://art/pixel/%s/actors.png" % def_id) as Texture2D).get_image()
		var first := sheet_image.get_region(Rect2i(0,0,160,128))
		var used := first.get_used_rect()
		# The head is the widest run of solid pixels near the top; a raised spear or bow is
		# thin, so rows are judged by how many pixels they hold, not by where they start.
		var side := roundi(used.size.y*.34)
		var best := 0
		var centre := used.position.x+used.size.x*.5
		for y in range(used.position.y+roundi(used.size.y*.08),used.position.y+roundi(used.size.y*.30)):
			var count := 0
			var sum := 0.0
			for x in range(used.position.x,used.end.x):
				if first.get_pixel(x,y).a > .5:
					count += 1
					sum += x
			if count > best:
				best = count
				centre = sum/count
		var left := clampi(roundi(centre-side*.5),0,160-side)
		var head := first.get_region(Rect2i(left,clampi(used.position.y+roundi(used.size.y*.02),0,128-side),side,side))
		if def_id in BEASTS:
			# A beast on four legs has no head at the top of its frame: show the whole animal.
			var whole := maxi(used.size.x,used.size.y)
			head = Image.create(whole,whole,false,first.get_format())
			head.blit_rect(first,used,Vector2i((whole-used.size.x)/2,(whole-used.size.y)/2))
		head.resize(size,size,Image.INTERPOLATE_NEAREST)
		head.convert(Image.FORMAT_RGBA8)
		# Set in a roundel, as a face is painted inside a cup: clay behind, a ring round it.
		var medal := Image.create(size,size,false,Image.FORMAT_RGBA8)
		var middle := (size-1)*.5
		var reach := size*.5
		var ground := CLAY_DARK.darkened(.35)
		for y in size:
			for x in size:
				var far := Vector2(x-middle,y-middle).length()
				if far > reach: continue
				if far > reach-maxf(1.0,size/20.0):
					medal.set_pixel(x,y,OCHRE)
					continue
				var paint := head.get_pixel(x,y)
				medal.set_pixel(x,y,ground.lerp(Color(paint.r,paint.g,paint.b,1),paint.a))
		_cache[key] = ImageTexture.create_from_image(medal)
	return _cache[key]


## Battle screens are laid out in window pixels, not on the canvas, so their text snaps to
## the nearest size the faces draw cleanly at: 20 (the small face doubled), 24 or 36.
static func snap(wanted: float) -> int:
	return 20 if wanted <= 19.0 else (24 if wanted <= 30.0 else 36)


static func fit(control: Control, wanted: float) -> void:
	var points := snap(wanted)
	control.add_theme_font_override("font",font(points))
	control.add_theme_font_size_override("font_size",points)


## The battle panels' boxes, in window pixels: the same sheet-and-hairline look as the menus.
static func big_box(kind: String, pad := Vector2(18,8)) -> StyleBox:
	match kind:
		"panel":
			# Two opposite corners turned, where the menus' panels have theirs cut.
			var plate := flat(Color(INK,.86),Color(OCHRE,.6),[0,2,0,0],pad)
			plate.corner_radius_top_right = 14
			plate.corner_radius_bottom_left = 14
			plate.anti_aliasing = false
			return plate
		"button_hover": return rounded(flat(Color(CLAY_DARK,.95),OCHRE,[2,2,2,2],pad),16)
		"button_pressed","button_primary": return rounded(flat(RED,OCHRE,[2,2,2,2],pad),16)
		"button_disabled": return rounded(flat(Color(INK,.5),Color(FAINT,.6),[2,2,2,2],pad),16)
		"card_chosen": return rounded(flat(Color(CLAY_DARK,.9),OCHRE,[2,2,2,2],pad),8)
		"focus": return rounded(flat(Color.TRANSPARENT,IVORY,[2,2,2,2],pad),16)
	return rounded(flat(Color(INK,.6),Color(OCHRE,.5),[2,2,2,2],pad),16)
