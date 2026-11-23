class_name BattleOverlay
extends Control
## Native-resolution overlay over the pixelated world: HP and stagger bars, escape values,
## floating combat text, tactical height labels and the hovered enemy's intent arrow.

var controller: Node  ## battle_controller.gd
var popups: Array = []  ## {world, text, color, age}
var marker_hits := {}
var holds := {}
var fall_preview := {}
var charge_lanes: Array = []
var rescue_route: Array[Vector2i] = []
var rescue_threats: Array[String] = []
var intent_from := Vector3.INF
var intent_to := Vector3.INF
## Where the enemy being looked at means to walk before it acts: ground points, first to last.
var intent_walk: Array[Vector3] = []

var forecasts := {}
var playback_hp := {}
var resolving := false
var hit_target := ""

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


func set_health_forecast(row: Dictionary) -> void:
	var id: String = row.target_id
	if not forecasts.has(id):
		forecasts[id] = {"before":row.before,"direction":row.direction}
	if row.after >= 0:
		if forecasts[id].before < 0:
			forecasts[id].before = row.before
		forecasts[id].after = row.after
	elif not forecasts[id].has("after"):
		forecasts[id].after = -1
	forecasts[id].outcome = row.outcome


func _process(dt: float) -> void:
	for p in popups:
		p["age"] += dt
	popups = popups.filter(func(p): return p["age"] < POPUP_LIFE)
	queue_redraw()


func _draw() -> void:
	if controller == null or controller.state == null:
		return
	var s: float = controller.ui_scale
	var font := Px.font(20)
	var fs := 20
	var state: BattleState = controller.state

	for holder_id in holds:
		var holder: UnitView = controller.unit_views[holder_id]
		var held: UnitView = controller.unit_views[holds[holder_id]]
		var a: Vector2 = controller.world_to_screen(holder.position)
		var b: Vector2 = controller.world_to_screen(held.position)
		var mid := a.lerp(b,.5)
		draw_line(a,b,Color("#442f26"),5*s,true)
		draw_line(a,b,Color("#e3b66f"),2*s,true)
		for offset in [-3.,3.]:
			draw_arc(mid+a.direction_to(b)*offset*s,4.5*s,0,TAU,18,Color("#ffe0a3"),2*s,true)
	if not fall_preview.is_empty():
		var pos: Vector2 = controller.world_to_screen(fall_preview.world)
		var caption := "落差 %d 层" % fall_preview.levels
		if fall_preview.has("damage"):
			caption += "  ·  坠落 −%d" % fall_preview.damage
		_rescue_tag(font,pos+Vector2(0,26*s),caption,fs,Color("#ffcc90"))
	for lane: Array in charge_lanes:
		var points := PackedVector2Array()
		for cell: Vector2i in lane:
			points.append(controller.world_to_screen(controller.map_view.to_global(Vector3(cell.x+.5,controller.map_view.cell_top(cell)+.06,cell.y+.5))))
		for i in range(1,points.size()):
			var a := points[i-1]
			var b := points[i]
			var d := a.direction_to(b)
			var tip := a.lerp(b,.70)
			draw_line(a,b,Color("#64352b"),5*s,true)
			draw_line(a,b,Color("#ffa16b"),2*s,true)
			draw_colored_polygon(PackedVector2Array([tip+d*6*s,tip-d*5*s+d.orthogonal()*5*s,tip-d*5*s-d.orthogonal()*5*s]),Color("#ffd394"))
		_rescue_tag(font,points[0]+Vector2(0,20*s),"冲锋",fs,Color("#ffc499"))
	if not rescue_route.is_empty():
		var trail := PackedVector2Array()
		for cell in rescue_route:
			trail.append(controller.world_to_screen(controller.map_view.to_global(Vector3(cell.x+.5,controller.map_view.cell_top(cell)+.08,cell.y+.5))))
		var stop := trail[-1]
		for i in range(1,trail.size()):
			var a := trail[i-1]
			var b := trail[i]
			draw_line(a,b,Color("#28342c"),5*s,true)
			draw_line(a,b,Color("#a4e6c4"),2.5*s,true)
			var dir := a.direction_to(b)
			var mid := a.lerp(b,.67)
			draw_colored_polygon(PackedVector2Array([mid+dir*6*s,mid-dir*4*s+dir.orthogonal()*4*s,mid-dir*4*s-dir.orthogonal()*4*s]),Color("#a4e6c4"))
		for id in rescue_threats:
			var view: UnitView = controller.unit_views[id]
			var threat: Vector2 = controller.world_to_screen(view.position)
			draw_dashed_line(threat,stop,Color("#dc825d"),2*s,8*s)
			draw_arc(threat,17*s,0,TAU,32,Color("#ffc29b"),3*s,true)
		draw_circle(stop,5*s,Color("#a4e6c4"))

	if controller.village != null:
		var gate: Node3D = controller.village.gate
		var label_pos: Vector2 = controller.world_to_screen(gate.global_position+Vector3.UP*2.02)
		var label_width := font.get_string_size("北门",HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		_text(font,label_pos-Vector2(label_width*.5,0),"北门",fs,Color("#b2e7ce"))

	if not state.rescue_exits.is_empty():
		var exit := state.rescue_exits[0]
		var pos: Vector2 = controller.world_to_screen(controller.map_view.to_global(Vector3(exit.x+.35,controller.map_view.cell_top(exit)+.58,exit.y+.95)))
		_rescue_tag(font,pos,"← 西侧出口",fs,Color("#a4e1c9"))

	if controller.tactical:
		for y in state.grid.depth:
			for x in state.grid.width:
				var c := Vector2i(x, y)
				var w := Vector3(x + 0.5, controller.map_view.cell_top(c) + 0.02, y + 0.5)
				var sp: Vector2 = controller.world_to_screen(controller.map_view.to_global(w))
				_text(font, sp + Vector2(-4 * s, 6 * s), str(state.grid.height_at(c)), int(14 * s), Color(1, 1, 1, 0.9))

	var labels := []
	var occupied: Array[Rect2] = []
	var hud: Hud = controller.hud
	var heads := {}
	var bodies := {}
	var hovered := state.unit_at(controller._hovered)
	var focus_id: String = hit_target
	if focus_id.is_empty():
		focus_id = hud.inspected_enemy
	if focus_id.is_empty():
		focus_id = hovered.id if hovered != null else controller._selected
	marker_hits.clear()
	for id in state.order:
		var u := state.unit(id)
		var view: UnitView = controller.unit_views.get(id)
		if view == null or not view.visible or u.hidden or (not u.alive and playback_hp.get(id,0) <= 0):
			continue
		var foot: Vector2 = controller.world_to_screen(view.position)
		var top: Vector2 = controller.world_to_screen(view.position+controller.cam_rig.camera.global_basis.y*view.sprite_height)
		var h := foot.y-top.y
		bodies[id] = Rect2(top-Vector2(h*.29,0),Vector2(h*.58,h))
		heads[id] = top-Vector2(0,5*s)
	var focus: UnitView = controller.unit_views.get(focus_id)
	for id: String in heads:
		var u := state.unit(id)
		var view: UnitView = controller.unit_views[id]
		var head: Vector2 = heads[id]
		var body: Rect2 = bodies[id]
		var compact := false
		for other in heads:
			if other != id and body.grow(5*s).intersects(bodies[other]):
				compact = true
				break
		var reveal := Rect2()
		if focus != null and id != focus_id and bodies.has(focus_id) and body.intersects(bodies[focus_id]):
			var toward_camera := controller.cam_rig.camera.global_basis.z as Vector3
			if (view.position-focus.position).dot(toward_camera) > .04:
				reveal = bodies[focus_id]
		reveal.position -= controller._container.position
		view.set_reveal_region(reveal,controller._container.size)
		var detailed: bool = not compact or id == focus_id or id == hud.acting_enemy or forecasts.has(id) or u.is_boss()
		var bw := (30.0 if compact else 46.0) * s * (1.4 if u.size > 1 else 1.0)
		var bh := (4.0 if compact else 6.0) * s
		var numbered: bool = hud.enemy_numbers.has(id) and hud._order_panel.visible
		var r := Rect2(head-Vector2(bw/2,bh),Vector2(bw,bh))
		var marker := Rect2(r.position-Vector2(25*s if numbered else 0.,10*s),Vector2(bw+(25*s if numbered else 0.),22*s))
		var offset := _marker_offset(marker,s)
		marker.position += offset
		r.position += offset
		if offset != Vector2.ZERO:
			draw_line(r.get_center(),head,Color("#52402ece"),1.5*s,true)
		marker_hits[id] = marker
		occupied.append(marker)
		head.y = r.end.y
		if u.id == "wounded_chiron":
			_rescue_tag(font,Vector2(head.x,r.position.y-6*s),"喀戎 · 负伤",fs,Color("#b3e6d5"))
		if u.def_id == "refugee":
			var blocker: UnitState
			for enemy in state.living(Defs.Team.ENEMY):
				if not enemy.hidden and absi(enemy.pos.x-u.pos.x)+absi(enemy.pos.y-u.pos.y)==1:
					blocker = enemy
					break
			var caption := "向西撤离"
			var brief := "←"
			var tint := Color("#b2e7ce")
			if blocker != null:
				caption = "%d 号拦截" % int(hud.enemy_numbers[blocker.id]) if hud.enemy_numbers.has(blocker.id) else "受阻"
				brief = "拦"
				tint = Color("#ffc09b")
			# A small mark is enough to read the field; the words come when you point at them.
			if id == focus_id:
				_rescue_tag(font,Vector2(head.x,r.position.y-5*s),u.display_name+" · "+caption,fs,tint)
			else:
				_rescue_tag(font,Vector2(head.x,r.position.y-5*s),brief,fs,tint)
		draw_rect(r.grow(1.0 * s), Color(0, 0, 0, 0.85))
		var hp_col := Color(0.35, 0.8, 0.45) if u.team == Defs.Team.PLAYER else Color(0.9, 0.3, 0.25)
		draw_rect(Rect2(r.position, Vector2(bw * clampf(float(playback_hp.get(id,u.hp)) / u.max_hp, 0, 1), bh)), hp_col)
		if forecasts.has(id) and not hud.journal_open():
			var prediction: Dictionary = forecasts[id]
			var caption: String = prediction.outcome
			if prediction.after >= 0:
				var remaining := bw * clampf(float(prediction.after)/u.max_hp,0,1)
				var loss := bw * clampf(float(prediction.before-prediction.after)/u.max_hp,0,1)
				draw_rect(Rect2(r.position+Vector2(remaining,0),Vector2(loss,bh)),Color("#f2c08e"))
				var relation: String = {"侧面":"侧击","背面":"背击"}.get(prediction.direction,"")
				caption = "−%d  %s剩 %d" % [prediction.before-prediction.after,relation+" · " if relation else "",prediction.after]
			labels.append({"anchor":r,"text":caption})
		if u.has_status("guard"):
			# Braced: a shield beside the bar and a pale ring round the feet for as long as
			# the stance holds, so it reads at a glance on either side.
			var ours := u.team == Defs.Team.PLAYER
			var badge := Vector2(r.position.x-13*s,r.get_center().y) if ours else Vector2(r.end.x+13*s,r.get_center().y)
			draw_circle(badge,11*s,Color("#16232c"),true,-1,true)
			draw_arc(badge,11*s,0,TAU,28,Color("#8fd0ff"),2*s,true)
			draw_texture_rect(Px.icon("act_guard",16),Rect2(badge-Vector2(8,8)*s,Vector2(16,16)*s),false,Color("#d6efff"))
			var feet: Vector2 = controller.world_to_screen(view.position)
			draw_set_transform(feet,0.0,Vector2(1.0,.5))
			draw_arc(Vector2.ZERO,30*s*(1.4 if u.size > 1 else 1.0),0,TAU,40,Color("#16232c"),5*s,true)
			draw_arc(Vector2.ZERO,30*s*(1.4 if u.size > 1 else 1.0),0,TAU,40,Color("#8fd0ff"),2.5*s,true)
			draw_set_transform(Vector2.ZERO)
		if id == hit_target:
			draw_arc(controller.world_to_screen(view.position),22*s,0,TAU,36,Color("#ffac83"),3*s,true)

		if numbered:
			var chosen := id == hud.inspected_enemy or id == hud.acting_enemy
			var center := Vector2(r.position.x-12*s,head.y-bh*.5)
			var radius := (12 if chosen else 10)*s
			draw_circle(center,radius+1.5*s,Color("#f2d4a7"),true,-1,true)
			draw_circle(center,radius,Color("#a95235") if chosen else Color("#31231f"),true,-1,true)
			var numeral := str(hud.enemy_numbers[id])
			draw_string(font,center+Vector2(-radius,5*s),numeral,HORIZONTAL_ALIGNMENT_CENTER,radius*2,20,Color("#ffebc9"))
			if chosen:
				var foot: Vector2 = controller.world_to_screen(view.position)
				draw_arc(foot,20*s,0,TAU,32,Color("#ffdfa0"),2*s,true)
		head.x = r.get_center().x
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
		if u.id in [state.marked_id,state.previous_mark]:
			tags.append("◎标记")
		if u.has_status("staggered"):
			tags.append("破势")
		if not tags.is_empty() and (detailed or u.grappled_by_id != "" or u.has_status("staggered")):
			var t := " ".join(tags)
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_text(font, Vector2(head.x - tw / 2, y), t, fs, Color(1.0, 0.92, 0.55))
		if detailed and not resolving and u.team == Defs.Team.PLAYER and u.has_acted and state.phase == Defs.Phase.PLAYER:
			_text(font, Vector2(r.end.x + 3 * s, r.end.y + 2 * s), "可再移动" if u.post_move > 0 else "✓", fs, Color(0.75, 0.75, 0.75))

	for label in labels:
		var anchor: Rect2 = label.anchor
		var extent := font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs)+Vector2(14,6)*s
		var tag := Rect2(Vector2(anchor.end.x+9*s,anchor.get_center().y-extent.y/2),extent)
		tag.position.x = clampf(tag.position.x,4*s,size.x-extent.x-4*s)
		var origin := tag.position.y
		var free_top := hud._top.get_global_rect().end.y+4*s if hud._top.visible else 4*s
		var free_bottom := size.y-4*s
		for box: Control in [hud._card,hud._bar,hud._side]:
			if box.is_visible_in_tree() and tag.end.x >= box.position.x and tag.position.x <= box.get_global_rect().end.x:
				free_bottom = minf(free_bottom,box.position.y-4*s)
		var max_y := maxf(free_top,free_bottom-extent.y)
		for step in range(occupied.size()*2+3):
			var offset := ceilf(step*.5)*(extent.y+3*s)
			tag.position.y = clampf(origin+(offset if step%2==0 else -offset),free_top,max_y)
			var collision := false
			for other in occupied:
				if tag.grow(2*s).intersects(other):
					collision = true
					break
			if not collision:
				break
		occupied.append(tag)
		draw_line(anchor.end,Vector2(tag.position.x,tag.get_center().y),Color("#d5ae81"),s)
		draw_rect(tag,Color("#30231ff5"))
		draw_rect(Rect2(tag.position,Vector2(3*s,tag.size.y)),Color("#e3a573"))
		draw_string(font,tag.position+Vector2(8*s,3*s+font.get_ascent(fs)),label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color("#ffebc9"))

	if intent_walk.size() > 1:
		# Footsteps to where it means to stand, and a ring there.
		var steps := PackedVector2Array()
		for point in intent_walk: steps.append(controller.world_to_screen(point))
		for i in range(1,steps.size()):
			draw_dashed_line(steps[i-1],steps[i],Color("#3a231c"),5*s,9*s)
			draw_dashed_line(steps[i-1],steps[i],Color("#ffb37a"),2.5*s,9*s)
		draw_arc(steps[-1],15*s,0,TAU,28,Color("#3a231c"),5*s,true)
		draw_arc(steps[-1],15*s,0,TAU,28,Color("#ffb37a"),2.5*s,true)
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


func _marker_offset(rect: Rect2, scale_factor: float) -> Vector2:
	if not _overlaps_marker(rect):
		return Vector2.ZERO
	# Prefer nearby positions on the same row, then try the next tier up.
	for row in range(marker_hits.size()+1):
		for column: float in [0.,-.5,.5,-1.,1.]:
			var offset := Vector2(column*(rect.size.x+3*scale_factor),-row*24*scale_factor)
			var candidate := Rect2(rect.position+offset,rect.size)
			if candidate.position.x >= 0 and candidate.end.x <= size.x and not _overlaps_marker(candidate):
				return offset
	return Vector2.ZERO


func _overlaps_marker(rect: Rect2) -> bool:
	for other: Rect2 in marker_hits.values():
		if rect.intersects(other):
			return true
	return false


func _rescue_tag(font: Font, base: Vector2, label: String, fs: int, tint: Color) -> void:
	var s: float = controller.ui_scale
	var width := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	var rect := Rect2(base-Vector2(width*.5+5*s,font.get_ascent(fs)+2*s),Vector2(width+10*s,font.get_height(fs)+4*s))
	draw_rect(rect,Color("#252522ed"))
	draw_rect(Rect2(rect.position,Vector2(2*s,rect.size.y)),tint)
	draw_string(font,base-Vector2(width*.5,0),label,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,tint)


func _text(font: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, size / 5), Color(0, 0, 0, col.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
