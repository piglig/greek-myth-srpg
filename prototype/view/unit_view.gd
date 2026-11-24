class_name UnitView
extends Node3D
## Directional battle sprite + team disc + facing marker for one unit.

const PLAYER_COLOR := Color("#497c78")
const ENEMY_COLOR := Color("#963e32")
const SELECTED_COLOR := Color("#d9a441")

const FRAME_TIME := 0.11
var _time := 0.0
const INBETWEENS := 8
const MOTION_COLUMNS := 16
var _gait_keys := 2
var _strike: Array[int] = []
var _motion_rows := 0
var _pairs: Array[Vector2i] = []
var _gait_entry := -1
var _pose_seconds := .11
var _turn_time := .13
var _shown_side := Vector2i(-1,-1)
var _turn_from := Vector2i.ZERO
var _turn_to := Vector2i.ZERO
var _stride_lean := Vector2.ZERO
var _push_direction := Vector3.ZERO
var _push_weight := 0.0
var _braced_step := false
var _has_pivot := false
var _pivot_speed := PIVOT_SPEED
var _pivot_angle := INF
var _club_turn_speed := 0.0
var _aim_offset := 0.0
const PIVOT_SPEED := deg_to_rad(740.0)
var _last_pose := 0
var _transition := -1
var _transition_time := 0.0
var _step_distance := 0.0
var _last_ground := Vector2.ZERO
var walking := false:
	set(value):
		if walking and not value and _gait_entry >= 0:
			_last_pose = _pairs[_gait_entry].x
			_pose_seconds = .11
		walking = value
		if value:
			_step_distance = 0.0
			_last_ground = Vector2(position.x, position.z)
var _attacking := false
var _direction := 0
var held_pose := -1

var unit_id := ""
var size := 1
var sprite_height := 0.8  ## world units, used to place overlay bars
var _art_scale := 1.0
var _sprite: Sprite3D
var _disc: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _team_color: Color


func setup(u: UnitState, tex: Texture2D, motion: Texture2D) -> void:
	_setup_base(u)
	_sprite = Sprite3D.new()
	_sprite.texture = tex
	_art_scale = tex.get_height()/512.0
	_sprite.hframes = roundi(tex.get_width() / (320*_art_scale))
	_sprite.vframes = 2
	if u.def_id in ["hero","wolf"]:
		_gait_keys = 6
	elif u.def_id == "refugee":
		_gait_keys = 4
	var first := _sprite.hframes-4
	match u.def_id:
		"hero": _strike = [0,first,first+1,first+2,first+3,0]
		"wolf": _strike = [0,first,first+1,first+2,first+3,0]
		_: _strike = [0,2,0]
	for i in _strike.size()-1:
		_pairs.append(Vector2i(_strike[i], _strike[i+1]))
	if u.def_id in ["hero","wolf"]:
		_pairs.append_array([Vector2i(0,2), Vector2i(2,0), Vector2i(first-6,0)])
		_gait_entry = _pairs.size()-1
	if u.def_id == "bandit_archer":
		_pairs.append(Vector2i(3,0))
	if u.def_id == "chiron":
		_pairs.append_array([Vector2i(2,3),Vector2i(3,0)])
	if u.def_id == "lion":
		_pairs.append_array([Vector2i(0,3), Vector2i(3,2), Vector2i(2,4), Vector2i(4,0)])
	_sprite.offset.y = 112.0*_art_scale
	_sprite.position.y = 0.014
	_sprite.pixel_size = sprite_height / (208.0*_art_scale)
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://view/baked_actor.gdshader")
	mat.set_shader_parameter("sheet",tex)
	_bow_carrier = u.def_id == "atalanta"
	var beast_turn := _art_scale == .5 and u.def_id in ["wolf","boar"]
	_has_pivot = u.def_id == "hero" or _bow_carrier or _braced_step or beast_turn
	if beast_turn:
		_pivot_speed = deg_to_rad(445. if u.def_id == "wolf" else 325.)
	mat.set_shader_parameter("spear_carrier",u.def_id == "hero")
	if _has_pivot and _art_scale==.5:
		mat.set_shader_parameter("pivot_sheet",load("res://art/pixel/%s/turns.png"%u.look()))
	elif _bow_carrier:
		mat.set_shader_parameter("pivot_sheet",preload("res://art/original/turns/atalanta.png"))
	elif _braced_step:
		mat.set_shader_parameter("pivot_sheet",preload("res://art/original/turns/heracles.png"))
	elif _has_pivot:
		mat.set_shader_parameter("pivot_sheet",preload("res://art/original/turns/hero.png"))
	mat.set_shader_parameter("bow_carrier",_bow_carrier)
	mat.set_shader_parameter("wolf_coat",u.def_id=="wolf")
	_motion_rows = roundi(motion.get_height()/(512*_art_scale))
	mat.set_shader_parameter("art_scale",_art_scale)
	mat.set_shader_parameter("motion_sheet",motion)
	mat.set_shader_parameter("source_columns",float(_sprite.hframes))
	mat.set_shader_parameter("breath_phase",float(absi(u.id.hash())%628)/100.0)
	_sprite.material_override = mat
	add_child(_sprite)

	var caster := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	var quadruped := u.def_id in ["wolf","boar","lion","chiron","centaur"]
	capsule.radius = sprite_height * (0.16 if u.def_id == "wolf" else (0.2 if quadruped else 0.105))
	capsule.height = sprite_height * (.88 if u.def_id == "wolf" else (1.12 if quadruped else 0.91))
	caster.mesh = capsule
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.position.y = sprite_height * (0.30 if u.def_id == "wolf" else 0.49)
	if quadruped:
		caster.rotation.x = PI/2
	caster.name = "Caster"
	add_child(caster)
	set_facing(u.facing)


func _setup_base(u: UnitState, draw_ground_shadow := true) -> void:
	unit_id = u.id
	_braced_step = u.def_id == "heracles"
	size = u.size
	name = "Unit_" + u.id
	_team_color = PLAYER_COLOR if u.team == Defs.Team.PLAYER else ENEMY_COLOR

	_disc_mat = _flat(_team_color)
	var disc_mesh := TorusMesh.new()
	disc_mesh.inner_radius = 0.385 * size
	disc_mesh.outer_radius = 0.42 * size
	disc_mesh.rings = 20
	disc_mesh.ring_segments = 4
	_disc = MeshInstance3D.new()
	_disc.mesh = disc_mesh
	_disc.scale.y = 0.12
	_disc.material_override = _disc_mat
	_disc.position.y = 0.02
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	if draw_ground_shadow:
		var shadow := NemeaField.shadow(size * 1.1, size * 0.72)
		shadow.name="GroundShadow"
		add_child(shadow)

	sprite_height = {"wolf":1.18,"boar":1.16,"lion":1.75,"heracles":2.18,"centaur":2.28,"chiron":2.28}.get(u.def_id,1.88)


func set_pose(pose: int, seconds: float) -> void:
	_pose_seconds = seconds
	held_pose = pose


func attack_key(key: int, seconds := .1) -> void:
	set_pose(_sprite.hframes - 4 + key, seconds)


var _bow_target: Node3D
var _bow_drop := 0.0
var _bow_carrier := false


func raise_bow(target: Node3D) -> void:
	_bow_target = target
	face_point(target.position)
	# Use the actual shot bearing (including elevation) for the pivot and draw.
	var camera := get_viewport().get_camera_3d()
	while camera != null and is_instance_valid(target) and not is_inf(_pivot_angle):
		var shot := target.global_position-global_position
		var goal := _view_angle(shot.dot(camera.global_basis.z)<0,shot.dot(camera.global_basis.x)>0)
		if absf(angle_difference(_pivot_angle,goal)) <= PI/10.:
			break
		await get_tree().process_frame
	set_pose(2, .17)
	_sprite.set_instance_shader_parameter("live_arrow",false)
	set_bow_tension(0.0)


func set_bow_tension(amount: float) -> void:
	_sprite.set_instance_shader_parameter("bow_tension",amount)


func show_live_arrow() -> void:
	_sprite.set_instance_shader_parameter("live_arrow",true)


func bow_grip(tension: float) -> Vector3:
	var reverse := _sprite.frame_coords.y == 1
	var grip := Vector2(206,72) if reverse else Vector2(114,112)
	var displacement := 5.+11.*tension
	grip.x += displacement if reverse else -displacement
	var lateral := grip.x - 160.
	if _sprite.flip_h:
		lateral = -lateral
	var height := _sprite.offset.y/_art_scale + 128. - grip.y - _bow_drop - (1.-tension)*24.
	var basis := get_viewport().get_camera_3d().global_basis
	return _sprite.global_position+(basis.x*lateral+basis.y*height)*_sprite.pixel_size*_art_scale+basis.z*.12


func lower_bow() -> void:
	_bow_target = null
	set_pose(-1, .15)
	set_bow_tension(0.0)


var _reveal_region := Vector4.ZERO

func set_reveal_region(rect: Rect2, screen_size: Vector2) -> void:
	var region := Vector4.ZERO
	if rect.has_area():
		var center := rect.get_center()/screen_size
		var radius := rect.size*.5/screen_size
		region = Vector4(center.x,center.y,radius.x,radius.y)
	if region != _reveal_region:
		_reveal_region = region
		_sprite.set_instance_shader_parameter("reveal_region",region)


func set_hold_offset(offset: Vector3) -> void:
	_sprite.position = offset+Vector3.UP*.014


func lift_body(height: float) -> void:
	_sprite.position.y = 0.014 + height


var _hit_tween: Tween
var _recoil := Vector2.ZERO


func react_to_hit(force: Vector3, severity: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var lateral := force.dot(camera.global_basis.x)
	var strength := lerpf(.72,1.28,clampf(severity*2.0,0,1))
	var peak := Vector2(lateral*.24,-.14)*strength
	if _hit_tween != null:
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_method(_set_recoil,_recoil,peak,.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_method(_set_recoil,peak,Vector2(-peak.x*.20,.025),.115).set_trans(Tween.TRANS_SINE)
	_hit_tween.tween_method(_set_recoil,Vector2(-peak.x*.20,.025),Vector2.ZERO,.13).set_trans(Tween.TRANS_SINE)


func _set_recoil(value: Vector2) -> void:
	_recoil = value
	_sprite.set_instance_shader_parameter("recoil",value)


func set_nearby_stone(offset: Vector2) -> void:
	_sprite.set_instance_shader_parameter("nearby_stone",offset)


func brace_against(direction: Vector3, weight: float) -> void:
	_push_direction = direction
	_push_weight = weight


func signal_post_move() -> void:
	var pulse := create_tween()
	pulse.tween_property(_disc,"scale",Vector3(1.32,.12,1.32),.13).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_disc,"scale",Vector3(1.,.12,1.),.24).set_trans(Tween.TRANS_SINE)


func set_roar_lift(amount: float) -> void:
	_sprite.set_instance_shader_parameter("roar_lift",amount)


func signal_pounce() -> void:
	var cue := create_tween()
	cue.tween_property(_disc_mat,"albedo_color",Color("#f0a65e"),.09)
	cue.tween_interval(.16)
	cue.tween_property(_disc_mat,"albedo_color",_team_color,.13)


func play_attack() -> void:
	_attacking = true
	_pose_seconds = .16
	_time = 0


func _process(delta: float) -> void:
	_time += delta
	if _attacking and _time >= FRAME_TIME * 4:
		_attacking = false
		_time = 0
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var back := camera.global_basis.z
	var direction := [Vector3.BACK,Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT][_direction] as Vector3
	var reverse := direction.dot(back) < 0
	var screen_right := direction.dot(camera.global_basis.x) > 0
	if is_instance_valid(_bow_target):
		var shot := _bow_target.global_position-global_position
		screen_right = shot.dot(camera.global_basis.x)>0
		reverse = shot.dot(back)<0
		var slope := -shot.dot(camera.global_basis.y)/maxf(.5,absf(shot.dot(camera.global_basis.x)))
		_bow_drop = clampf(44.0*slope,-22.,26.)
		_sprite.set_instance_shader_parameter("bow_drop",_bow_drop)
	var pose := 0
	var frame := -1
	var lean := Vector2.ZERO
	if walking:
		var ground := Vector2(position.x,position.z)
		var travel := ground - _last_ground
		_step_distance += travel.length()
		_last_ground = ground
		var cycle := _step_distance
		if _gait_entry >= 0 and cycle < 1.0:
			cycle = maxf(0., (cycle-.22)/.78)
		frame = int(cycle*_gait_keys*INBETWEENS) % (_gait_keys*INBETWEENS)
		if _braced_step:
			# Two planted steps per cycle. Its two neutral keys fall on grid boundaries.
			const WALK_TILES := 6 * INBETWEENS
			frame = _motion_rows*MOTION_COLUMNS-WALK_TILES + roundi(_step_distance*WALK_TILES*.5)%WALK_TILES
		if _gait_entry >= 0 and _step_distance < .22:
			var entry_part := clampi(roundi((1.-_step_distance/.22)*INBETWEENS),0,INBETWEENS)
			frame = -1 if entry_part == INBETWEENS else (_gait_keys+_gait_entry)*INBETWEENS+entry_part
		var speed := minf(1., travel.length()/maxf(delta*3.8,.001))
		var lateral := Vector3(travel.x,0,travel.y).normalized().dot(camera.global_basis.x)
		lean = Vector2(lateral*.038, -.022*pow(sin(cycle*PI*2),2))*speed
	lean.x += _aim_offset
	_stride_lean = _stride_lean.lerp(lean,1.-exp(-22.*delta))
	# Shift the shoulders into the stone while keeping the supporting foot planted.
	var shoulders := Vector2(_push_direction.dot(camera.global_basis.x)*.29,-.17)
	_sprite.set_instance_shader_parameter("stride",_stride_lean + shoulders*_push_weight)
	if _attacking:
		pose = 2
	if held_pose >= 0:
		pose = held_pose if held_pose < _sprite.hframes else 0
	if pose != _last_pose:
		_transition = _pairs.find(Vector2i(_last_pose,pose))
		_transition_time = 0.
		_last_pose = pose
	if _braced_step and _push_weight > 0.:
		frame = roundi(_push_weight * INBETWEENS)
	var bow_pose := 1.0 if pose == 2 else 0.0
	if _transition >= 0 and not walking:
		var part := int(_transition_time/_pose_seconds*INBETWEENS)
		if part < INBETWEENS:
			frame = (_gait_keys+_transition)*INBETWEENS+part
			if _bow_carrier:
				var segment := _pairs[_transition]
				bow_pose = lerpf(float(segment.x == 2),float(segment.y == 2),float(part)/INBETWEENS)
		else:
			_transition = -1
		_transition_time += delta
	if _bow_carrier:
		_sprite.set_instance_shader_parameter("bow_pose",bow_pose)
	var side := Vector2i(int(screen_right != reverse), int(reverse))
	if _has_pivot:
		var goal := _view_angle(reverse,screen_right)
		var turn_frame := _advance_pivot(goal, delta)
		_sprite.set_instance_shader_parameter("pivot_frame",float(turn_frame))
		if turn_frame >= 0:
			_sprite.flip_h = false
			_sprite.frame_coords = Vector2i(pose,0)
			_sprite.set_instance_shader_parameter("motion_tile",Vector2(-1,-1))
			return
		_shown_side = side
	elif _shown_side.x == -1:
		_shown_side = side
		_turn_to = side
	if not _has_pivot and side != _turn_to:
		_turn_from = _shown_side
		_turn_to = side
		_turn_time = 0.
	_turn_time = minf(.13, _turn_time+delta)
	if not _has_pivot:
		_shown_side = _turn_from if _turn_time < .065 else _turn_to
	_sprite.scale.x = 1. - .17*sin(PI*_turn_time/.13)
	_sprite.flip_h = bool(_shown_side.x)
	_sprite.frame_coords = Vector2i(pose,_shown_side.y)
	var tile := Vector2(-1,-1)
	if frame >= 0:
		tile = Vector2(frame%MOTION_COLUMNS,frame/MOTION_COLUMNS+_shown_side.y*_motion_rows)
	_sprite.set_instance_shader_parameter("motion_tile",tile)


func _view_angle(reverse: bool, right: bool) -> float:
	var diagonal := 3.0*PI/4.0 if reverse else PI/4.0
	return diagonal if right else -diagonal


func _advance_pivot(goal: float, delta: float) -> int:
	if is_inf(_pivot_angle):
		_pivot_angle = goal
	var distance := angle_difference(_pivot_angle,goal)
	var step := _pivot_speed*delta
	if _braced_step:
		var acceleration := deg_to_rad(4200.)
		var speed_limit := minf(deg_to_rad(490.),sqrt(2.*acceleration*absf(distance)))
		_club_turn_speed = move_toward(_club_turn_speed,speed_limit,acceleration*delta)
		step = _club_turn_speed*delta
	if absf(distance) <= step:
		_club_turn_speed = 0.
		_pivot_angle = goal
		return -1
	_pivot_angle += signf(distance)*step
	return posmod(roundi(_pivot_angle*64.0/TAU),64)


func plant_and_turn(heading: Vector2i) -> void:
	set_facing(heading)
	var direction := Vector3(heading.x,0,heading.y)
	var camera := get_viewport().get_camera_3d()
	while camera != null and not is_inf(_pivot_angle):
		var goal := _view_angle(direction.dot(camera.global_basis.z)<0,direction.dot(camera.global_basis.x)>0)
		if absf(angle_difference(_pivot_angle,goal)) < .001:
			break
		await get_tree().process_frame


func turn_to_strike(point: Vector3) -> void:
	face_point(point)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var direction := [Vector3.BACK,Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT][_direction] as Vector3
	if not _has_pivot:
		# Wait for the direction shown on the sprite, including a camera rotation.
		while true:
			var reverse := direction.dot(cam.global_basis.z)<0.
			var right := direction.dot(cam.global_basis.x)>0.
			if _shown_side == Vector2i(int(right != reverse),int(reverse)):
				return
			await get_tree().process_frame
	if is_inf(_pivot_angle):
		return
	# Begin the wind-up during the final part of a large pivot.
	while absf(angle_difference(_pivot_angle,_view_angle(direction.dot(cam.global_basis.z)<0,direction.dot(cam.global_basis.x)>0))) > PI/6.0:
		await get_tree().process_frame


func set_facing(f: Vector2i) -> void:
	_aim_offset = 0.0
	_direction = [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT].find(f)
	if has_node("Caster"):
		get_node("Caster").rotation.y = atan2(float(f.x), float(f.y))


func set_selected(on: bool) -> void:
	_disc_mat.albedo_color = SELECTED_COLOR if on else _team_color


func fade_out() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), 0.25)
	tw.tween_callback(hide)


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func face_point(point: Vector3) -> void:
	var toward := point - position
	var axis := Vector2(toward.x,toward.z)
	var current := [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT][_direction] as Vector2
	if _has_pivot and axis.length_squared() > .001 and absf(current.angle_to(axis)) < PI*.24:
		_aim_offset = current.angle_to(axis)*.075
		return
	if axis.length_squared() < .000001:
		return
	if absf(toward.x) >= absf(toward.z):
		set_facing(Vector2i(int(signf(toward.x)),0))
	elif toward.z != 0:
		set_facing(Vector2i(0,int(signf(toward.z))))
