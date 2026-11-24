class_name DiamondBar
extends Control
## The battle's command bar: a diamond cut into four, in the shape of the cells the battle
## is fought on. 攻击 at the top, 技能 at the left, 物品 at the right, 待机 at the bottom.
##
## Pressing 技能 opens a second diamond of four to the left: the 技能 facet itself becomes
## the first technique, and three more grow at its upper left, lower left and straight left.
## 物品 does the same to the right. Anything beyond four grows one facet further out.
##
## The way back sits where the four facets meet: a small red diamond marked with a cross,
## shown while a group is open, a target is being chosen, or a facing is being chosen
## after 待机. While a facing is being chosen the top facet reads 确认: wait facing the way
## they already face.
##
## Moving has no facet: with nothing else chosen, clicking the ground moves. Once someone
## has moved, and nothing else is going on, the same middle place holds a small diamond
## to take the move back.
##
## The control covers the whole screen but only its facets take the mouse; everything else
## falls through to the battlefield.

signal chosen(index: int)  ## a command was pressed: its place in the list given to `show_commands`
signal cancelled  ## the way back was pressed while aiming or choosing a facing
signal pointed(index: int)  ## the command under the mouse changed (-1 for none)

## Where the four fixed facets sit on the lattice, and what each stands for.
const ROOT := [["attack","攻击","act_slash",Vector2i(1,1)],["skill","技能","skills",Vector2i(0,1)],
	["item","物品","act_item",Vector2i(1,0)],["wait","待机","act_wait",Vector2i(0,0)]]
## Where an open group's facets sit: the group's own facet first, then the three that make
## a diamond with it, then further out for anything beyond four.
const GROWTH := {
	"skill": [Vector2i(0,1),Vector2i(0,2),Vector2i(-1,1),Vector2i(-1,2),Vector2i(-1,3),Vector2i(-2,2),Vector2i(-2,3),Vector2i(0,3)],
	"item": [Vector2i(1,0),Vector2i(2,0),Vector2i(1,-1),Vector2i(2,-1),Vector2i(3,-1),Vector2i(2,-2)],
}
## How big the diamond at the middle is, against a facet: taking a move back, and the
## way back out of a group or an aim, which is a little larger.
const HUB := 0.40
const HUB_BACK := 0.50

var radius := 58.0  ## half a facet's width
var centre := Vector2.ZERO  ## where the four fixed facets meet
var open_group := ""
var mode := ""  ## "" | "aim" (choosing a target) | "facing" (choosing a facing after 待机)
var commands: Array = []
## What is drawn: {at, index, group, label, art, enabled, active, corner, key, order, press}.
## `press` is "" for a command, else "open", "close", "cancel".
var facets: Array = []
var hovered := -1  ## place in `facets`
var _grown := 2.0  ## how long the open group has been spreading, in seconds
var _font_size := 15


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## `list` are the controller's commands, each naming its group: move, attack, skill, item, wait.
func show_commands(list: Array, now := "") -> void:
	commands = list
	mode = now
	if list.is_empty() or mode != "": open_group = ""
	_build()


func toggle(group: String) -> void:
	open_group = "" if open_group == group else group
	_grown = 0.0
	_build()


## Closes the open group. True if one was open.
func close() -> bool:
	if open_group == "": return false
	open_group = ""
	_build()
	return true


## A number key: with a group open it picks among its facets, otherwise among the four.
func press_key(number: int) -> void:
	for facet: Dictionary in facets:
		if facet.key == number+1:
			_press(facet)
			return


func _facet(at: Vector2i, label: String, art: String) -> Dictionary:
	return {"at":at,"index":-1,"group":"","label":label,"art":art,"enabled":true,"active":false,"corner":"","key":0,"order":-1,"press":""}


func _build() -> void:
	facets.clear()
	var listed := {"skill":[],"item":[]}
	var single := {}
	for i in commands.size():
		var group: String = commands[i].get("group","")
		if listed.has(group): listed[group].append(i)
		elif not single.has(group): single[group] = i
	if open_group != "" and listed[open_group].is_empty(): open_group = ""
	var back := open_group != "" or mode != ""
	for slot in ROOT.size():
		var group: String = ROOT[slot][0]
		if group == open_group: continue  # its place is taken by the group's first entry
		var facet := _facet(ROOT[slot][3],ROOT[slot][1],ROOT[slot][2])
		facet.group = group
		facet.key = slot+1 if open_group == "" and mode == "" else 0
		if group == "wait" and mode == "aim":
			# Not while a target is being chosen: the way back is the middle.
			facet.enabled = false
		elif group == "attack" and mode == "facing" and single.has("wait"):
			# Keep the facing they have, and wait.
			facet.label = "确认"
			facet.art = "done"
			facet.index = single.wait
			facet.active = true
		elif mode == "facing":
			facet.enabled = false
		elif listed.has(group):
			var entries: Array = listed[group]
			facet.enabled = not entries.is_empty()
			facet.press = "open"
			for i: int in entries:
				if commands[i].get("active",false): facet.active = true
		elif single.has(group):
			var only: Dictionary = commands[single[group]]
			facet.index = single[group]
			facet.art = only.get("art",facet.art)
			facet.enabled = only.get("enabled",true)
			facet.active = only.get("active",false) and open_group == ""
			if int(only.get("cooldown",0)) > 0: facet.corner = str(only.cooldown)
		else:
			facet.enabled = false
		facets.append(facet)
	# Taking a move back: a small diamond over the point where the four meet, while it is
	# on offer and nothing else is going on. Added last so it is drawn, and hit, on top.
	var hub := {}
	if back:
		# The way back, at the middle.
		hub = _facet(Vector2i.ZERO,"取消","")
		hub.press = "close" if open_group != "" else "cancel"
		hub.hub = true
		hub.back = true
	elif single.has("move") and commands[single.move].get("kind","") == "do":
		hub = _facet(Vector2i.ZERO,"",str(commands[single.move].get("art","act_undo")))
		hub.index = single.move
		hub.group = "move"
		hub.hub = true
	if open_group != "":
		var spots: Array = GROWTH[open_group]
		var entries: Array = listed[open_group]
		for n in mini(entries.size(),spots.size()):
			var command: Dictionary = commands[entries[n]]
			var entry := _facet(spots[n],str(command.label),str(command.get("art","")))
			entry.index = entries[n]
			entry.group = open_group
			entry.enabled = command.get("enabled",true)
			entry.active = command.get("active",false)
			entry.key = n+1
			entry.order = n-1  # the first stands where the group's facet stood, and does not grow
			if int(command.get("cooldown",0)) > 0: entry.corner = str(command.cooldown)
			elif command.has("count"): entry.corner = "×%d" % int(command.count)
			facets.append(entry)
	if not hub.is_empty(): facets.append(hub)
	hovered = -1
	pointed.emit(-1)
	queue_redraw()


## The middle of a facet on the screen.
func spot(at: Vector2i) -> Vector2:
	return centre+Vector2((at.x-at.y)*radius,-(at.x+at.y)*radius+radius)


## The box around the four fixed facets, whatever else has grown: things placed beside the
## diamond stay where they are when a group opens.
func bounds() -> Rect2:
	return Rect2(centre-Vector2(radius*2,radius),Vector2(radius*4,radius*4))


## The box around everything drawn.
func spread_bounds() -> Rect2:
	var box := bounds()
	for facet: Dictionary in facets:
		box = box.merge(Rect2(spot(facet.at)-Vector2.ONE*radius,Vector2.ONE*radius*2))
	return box


## Where a facet's middle is, and how far it reaches: the hub is small and sits at the centre.
func _middle(facet: Dictionary) -> Vector2:
	return centre if facet.has("hub") else spot(facet.at)

func _reach(facet: Dictionary) -> float:
	if facet.has("back"): return radius*HUB_BACK
	return radius*HUB if facet.has("hub") else radius


func _facet_at(point: Vector2) -> int:
	# Last drawn is on top, so it is asked first.
	for i in range(facets.size()-1,-1,-1):
		var away: Vector2 = (point-_middle(facets[i])).abs()
		if away.x+away.y <= _reach(facets[i]) and _spread(facets[i]) >= 1.0: return i
	return -1


func _has_point(point: Vector2) -> bool:
	return visible and _facet_at(point) >= 0


## True if a facet lies under this point of the screen.
func covers(screen: Vector2) -> bool:
	return is_visible_in_tree() and _facet_at(screen-global_position) >= 0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var now := _facet_at(event.position)
		if now != hovered:
			hovered = now
			pointed.emit(facets[now].index if now >= 0 else -1)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var at := _facet_at(event.position)
		if at >= 0:
			accept_event()
			_press(facets[at])


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hovered >= 0:
		hovered = -1
		pointed.emit(-1)
		queue_redraw()


func _press(facet: Dictionary) -> void:
	if not facet.enabled: return
	match facet.press:
		"open": toggle(facet.group)
		"close": close()
		"cancel": cancelled.emit()
		_:
			if facet.index < 0: return
			open_group = ""
			chosen.emit(facet.index)


func _process(delta: float) -> void:
	if _grown < 2.0:
		_grown += delta
		queue_redraw()


## How far a facet has grown out, 0 to 1: the open group's spread one after another.
func _spread(facet: Dictionary) -> float:
	if facet.order < 0: return 1.0
	return clampf((_grown-facet.order*.05)/.14,0.0,1.0)


func _draw() -> void:
	var font := Px.font(_font_size)
	for i in facets.size():
		var facet: Dictionary = facets[i]
		var grown := _spread(facet)
		if grown <= 0.0: continue
		var eased := 1.0-pow(1.0-grown,3.0)
		var mid := _middle(facet)
		var reach := (_reach(facet)-(0.0 if facet.has("hub") else 2.0))*eased
		var shape := PackedVector2Array([mid+Vector2(0,-reach),mid+Vector2(reach,0),mid+Vector2(0,reach),mid+Vector2(-reach,0)])
		var way_back: bool = facet.press in ["close","cancel"]
		var lit: bool = facet.active or (i == hovered and facet.enabled)
		var fill := Color(Px.INK,.93)
		if facet.active: fill = Px.CLAY_DARK.lightened(.08)
		elif i == hovered and facet.enabled: fill = Px.CLAY_DARK
		elif way_back: fill = Color(Px.RED.darkened(.55),.95)
		elif facet.group == open_group and open_group != "": fill = Color(Px.INK.lightened(.07),.95)
		elif facet.has("hub"): fill = Px.CLAY_DARK.darkened(.15)
		draw_colored_polygon(shape,fill)
		var edge := Px.OCHRE if lit else Color(Px.OCHRE,.55 if facet.enabled else .25)
		if way_back and not lit: edge = Color(Px.RED.lightened(.25),.8)
		var outline := shape.duplicate()
		outline.append(shape[0])
		draw_polyline(outline,edge,2.0 if lit else 1.5)
		if grown < 1.0: continue
		if facet.has("back"):
			# A cross, drawn: the plainest sign there is for "not this".
			var arm := reach*.34
			var ink_back := Px.IVORY if lit else Px.RED.lightened(.55)
			draw_line(mid+Vector2(-arm,-arm),mid+Vector2(arm,arm),ink_back,3.0)
			draw_line(mid+Vector2(-arm,arm),mid+Vector2(arm,-arm),ink_back,3.0)
			continue
		if facet.has("hub"):
			# Only the turning arrow: there is no room for a word, and the card beside says it.
			var mark := reach*1.05
			draw_texture_rect(_stamp(str(facet.art)),Rect2(mid-Vector2.ONE*mark*.5,Vector2.ONE*mark),false,Px.IVORY if lit else Px.OCHRE)
			continue
		var ink := Px.IVORY if lit else (Px.OCHRE if facet.enabled else Color("#5d554e"))
		if way_back and not lit: ink = Px.RED.lightened(.45)
		var stamp := 32.0*radius/58.0
		draw_texture_rect(_stamp(str(facet.art)),Rect2(mid+Vector2(-stamp*.5,-stamp*.5-radius*.24),Vector2(stamp,stamp)),false,ink)
		var words: String = facet.label
		var room := radius*1.3
		var wide := font.get_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,-1,_font_size).x
		while wide > room and words.length() > 1:
			words = words.left(words.length()-1)
			wide = font.get_string_size(words+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,_font_size).x
		if words != facet.label: words += "…"
		var tone := Px.IVORY if lit else (Color("#d8c9b0") if facet.enabled else Color("#6f665e"))
		if way_back and not lit: tone = Px.RED.lightened(.55)
		draw_string(font,mid+Vector2(-wide*.5,radius*.14+font.get_ascent(_font_size)),words,HORIZONTAL_ALIGNMENT_LEFT,-1,_font_size,tone)
		if facet.key > 0:
			draw_string(font,mid+Vector2(-radius*.62,font.get_ascent(_font_size)*.5-2),str(facet.key),HORIZONTAL_ALIGNMENT_LEFT,-1,_font_size,Color("#8f8171"))
		if facet.corner != "":
			var mark: String = facet.corner
			var across := font.get_string_size(mark,HORIZONTAL_ALIGNMENT_LEFT,-1,_font_size).x
			draw_string(font,mid+Vector2(radius*.62-across,font.get_ascent(_font_size)*.5-2),mark,HORIZONTAL_ALIGNMENT_LEFT,-1,_font_size,Color("#e5a580") if mark.is_valid_int() else Color("#cfad89"))


func _stamp(name: String) -> Texture2D:
	var art: String = Hud.ACTION_ART.get(name,name)
	if not ResourceLoader.exists("res://art/thirdparty/game-icons/%s.svg" % art): art = "skills"
	return Px.icon(art,32)


## Sized for the window: `scale` is the battle interface's own.
func fit(window: Vector2, scale: float, margin: float) -> void:
	radius = roundf(58.0*scale)
	_font_size = roundi(15.0*maxf(1.0,scale))
	centre = Vector2(roundf(window.x*.5),window.y-margin-radius*2.0)
	queue_redraw()
