extends Control
## Four stable directions around the selected unit. Entries reference the command bar's action indices.
signal chosen(index: int)

const RADIUS := 112.0
const INNER := 32.0
var sectors: Array = []
var hovered := -1
var opening_pointer := Vector2.INF
var ui_scale := 1.0
var anchor: Callable
var bounds := Rect2()


func open(entries: Array, unit_anchor: Callable, available: Rect2, factor: float) -> void:
	sectors = entries
	anchor = unit_anchor
	bounds = available
	ui_scale = minf(factor,minf(available.size.x,available.size.y)/(2*RADIUS))
	if ui_scale <= 0:
		return
	size = Vector2.ONE*RADIUS*2*ui_scale
	hovered = -1
	opening_pointer = get_global_mouse_position()
	show()
	_place()
	queue_redraw()


func _place() -> void:
	var center: Vector2 = anchor.call()
	position = (center-size*.5).clamp(bounds.position,bounds.end-size)


func _process(_dt: float) -> void:
	if visible and anchor.is_valid():
		_place()


func _has_point(point: Vector2) -> bool:
	return point.distance_to(size*.5) <= RADIUS*ui_scale


func _sector_at(point: Vector2) -> int:
	var delta := (point-size*.5)/ui_scale
	if delta.length() < INNER or delta.length() > RADIUS:
		return -1
	return posmod(roundi((delta.angle()+PI/2)/(PI/2)),4)


func _pointed_sector(point: Vector2) -> int:
	# Near an edge the wheel shifts under the cursor. A repeated click must only dismiss it.
	if opening_pointer != Vector2.INF:
		if (global_position+point).distance_to(opening_pointer) < 8*ui_scale:
			return -1
		opening_pointer = Vector2.INF
	return _sector_at(point)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered = _pointed_sector(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		accept_event()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			hide()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var slot := _pointed_sector(event.position)
			if slot < 0 or sectors[slot].is_empty():
				hide()
			elif sectors[slot].enabled:
				hide()
				chosen.emit(sectors[slot].index)


func _ready() -> void:
	hide()
	mouse_exited.connect(func(): hovered = -1; queue_redraw())


func _draw() -> void:
	if sectors.is_empty():
		return
	draw_set_transform(size*.5,0,Vector2.ONE*ui_scale)
	var font := get_theme_default_font()
	for i in 4:
		var entry: Dictionary = sectors[i]
		if entry.is_empty():
			continue
		var angle := -PI/2+i*PI/2
		var start := angle-PI/4+.017
		var end := angle+PI/4-.017
		var polygon := PackedVector2Array()
		for j in 25:
			polygon.append(Vector2.from_angle(lerpf(start,end,j/24.0))*RADIUS)
		for j in range(24,-1,-1):
			polygon.append(Vector2.from_angle(lerpf(start,end,j/24.0))*INNER)
		var hot: bool = i == hovered and entry.enabled
		var ink := Color("#ffebc9") if entry.enabled else Color("#ab9b88")
		draw_colored_polygon(polygon,Color("#985332") if hot else Color("#302521f5"))
		polygon.append(polygon[0])
		draw_polyline(polygon,Color("#f2c595") if hot else Color("#ad8261"),1.5,true)
		var at := Vector2.from_angle(angle)*72
		draw_texture_rect(entry.icon,Rect2(at-Vector2(14,22),Vector2(28,28)),false,ink)
		draw_string(font,at+Vector2(-44,25),entry.label,HORIZONTAL_ALIGNMENT_CENTER,88,16,ink)
		if entry.cooldown > 0:
			draw_string(font,at+Vector2(16,-4),str(entry.cooldown),HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)
