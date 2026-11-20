class_name BattleOverlay
extends Control
## Native-resolution overlay over the pixelated world: HP and stagger bars, escape values,
## floating combat text, tactical height labels and the hovered enemy's intent arrow.

var controller: Node  ## battle_controller.gd
var popups: Array = []  ## {world, text, color, age}
var intent_from := Vector3.INF
var intent_to := Vector3.INF

const POPUP_LIFE := 1.1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func add_popup(world: Vector3, text: String, color: Color) -> void:
	# Stack popups that land on the same spot.
	var stacked := 0
	for p in popups:
		if (p["world"] as Vector3).distance_to(world) < 0.1 and p["age"] < 0.4:
			stacked += 1
	popups.append({"world": world, "text": text, "color": color, "age": -0.18 * stacked})


func _process(dt: float) -> void:
	for p in popups:
		p["age"] += dt
	popups = popups.filter(func(p): return p["age"] < POPUP_LIFE)
	queue_redraw()


func _draw() -> void:
	if controller == null or controller.state == null:
		return
	var s: float = controller.ui_scale
	var font := get_theme_default_font()
	var fs := int(16 * s)
	var state: BattleState = controller.state

	if controller.tactical:
		for y in state.grid.depth:
			for x in state.grid.width:
				var c := Vector2i(x, y)
				var w := Vector3(x + 0.5, controller.map_view.cell_top(c) + 0.02, y + 0.5)
				var sp: Vector2 = controller.world_to_screen(w)
				_text(font, sp + Vector2(-4 * s, 6 * s), str(state.grid.height_at(c)), int(14 * s), Color(1, 1, 1, 0.9))

	for id in state.order:
		var u: UnitState = state.units[id]
		if not u.alive:
			continue
		var view: UnitView = controller.unit_views[id]
		var head: Vector2 = controller.world_to_screen(view.position + Vector3(0, view.sprite_height + 0.12, 0))
		var bw := 46.0 * s * (1.4 if u.size > 1 else 1.0)
		var bh := 6.0 * s
		var r := Rect2(head - Vector2(bw / 2, bh), Vector2(bw, bh))
		draw_rect(r.grow(1.0 * s), Color(0, 0, 0, 0.85))
		var hp_col := Color(0.35, 0.8, 0.45) if u.team == Defs.Team.PLAYER else Color(0.9, 0.3, 0.25)
		draw_rect(Rect2(r.position, Vector2(bw * clampf(float(u.hp) / u.max_hp, 0, 1), bh)), hp_col)
		var y := r.position.y - 3 * s
		if u.is_boss():
			var sr := Rect2(r.position + Vector2(0, bh + 3 * s), Vector2(bw, 4 * s))
			draw_rect(sr.grow(1.0 * s), Color(0, 0, 0, 0.85))
			var full := u.has_status("staggered")
			var ratio := 1.0 if full else float(u.stagger) / u.stagger_max
			draw_rect(Rect2(sr.position, Vector2(bw * ratio, sr.size.y)),
				Color(1.0, 0.85, 0.2) if full else Color(0.95, 0.55, 0.15))
		var tags: Array[String] = []
		if u.grappled_by_id != "":
			tags.append("挣脱 %d" % u.escape)
		if state.marked_id == u.id:
			tags.append("◎标记")
		if u.has_status("staggered"):
			tags.append("破势")
		if u.has_status("guard"):
			tags.append("防御")
		if not tags.is_empty():
			var t := " ".join(tags)
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_text(font, Vector2(head.x - tw / 2, y), t, fs, Color(1.0, 0.92, 0.55))
		if u.team == Defs.Team.PLAYER and u.has_acted and state.phase == Defs.Phase.PLAYER:
			_text(font, Vector2(r.end.x + 3 * s, r.end.y + 2 * s), "✓", fs, Color(0.75, 0.75, 0.75))

	if intent_from != Vector3.INF:
		var a: Vector2 = controller.world_to_screen(intent_from)
		var b: Vector2 = controller.world_to_screen(intent_to)
		draw_line(a, b, Color(1.0, 0.6, 0.15), 3.0 * s)
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([b, b - dir * 12 * s + n * 7 * s, b - dir * 12 * s - n * 7 * s]),
			Color(1.0, 0.6, 0.15))

	for p in popups:
		var age: float = p["age"]
		if age < 0.0:
			continue
		var sp: Vector2 = controller.world_to_screen(p["world"])
		var col: Color = p["color"]
		col.a = clampf(1.5 - age / POPUP_LIFE * 1.5, 0, 1)
		var size := int(22 * s)
		var tw := font.get_string_size(p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_text(font, sp + Vector2(-tw / 2, -age * 40 * s), p["text"], size, col)


func _text(font: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, size / 5), Color(0, 0, 0, col.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
