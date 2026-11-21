class_name PaintedQuadruped
extends UnitView

const FEET := ["FL","FR","HL","HR"]
var boar := false
var figure: Node3D
var rig: Skeleton3D
var surface: MeshInstance3D
var joints: Dictionary[StringName,int] = {}
var ankle_rest: Array[Vector3] = []
var planted: Array[Vector3] = []
var previous := Vector3.ZERO
var pair := 0
var step_progress := 1.
var starts: Array[Vector3] = []
var ends: Array[Vector3] = []
var yaw := 0.
var phase := 1.
var reach := 0.
var target_height := 0.
var recoil := Vector3.ZERO
var held_offset := Vector3.ZERO


func setup(u: UnitState, _tex: Texture2D, _motion: Texture2D) -> void:
	_setup_base(u,false)
	boar = u.def_id=="boar"
	var scene := preload("res://art/original/boar.glb") if boar else preload("res://art/original/wolf.glb")
	figure = scene.instantiate()
	add_child(figure)
	figure.scale = Vector3.ONE*(1.23 if boar else .86)
	rig = figure.find_children("*","Skeleton3D",true,false)[0]
	for i in rig.get_bone_count():
		joints[rig.get_bone_name(i)] = i
	surface = figure.find_children("*","MeshInstance3D",true,false)[0]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://view/hero_surface.gdshader")
	mat.set_shader_parameter("pigments",preload("res://art/original/boar_coat.png") if boar else preload("res://art/original/wolf_coat.png"))
	surface.material_override = mat
	for foot in FEET:
		ankle_rest.append(rig.get_bone_global_rest(joints["Paw"+foot]).origin)
	set_facing(u.facing)
	figure.rotation.y=yaw


func set_facing(f: Vector2i) -> void:
	if f!=Vector2i.ZERO:
		yaw = atan2(float(f.x),float(f.y))


func face_point(point: Vector3) -> void:
	var d := point-position
	if d.slide(Vector3.UP).length_squared()>.0001:
		yaw = atan2(d.x,d.z)


func turn_to_strike(point: Vector3) -> void:
	face_point(point)
	while absf(angle_difference(figure.rotation.y,yaw))>.055:
		await get_tree().process_frame


func _rotate(joint: String, angles: Vector3) -> void:
	rig.set_bone_pose_rotation(joints[joint],Quaternion.from_euler(angles))


func _process(dt: float) -> void:
	if figure==null: return
	_time += dt
	var old_yaw := figure.rotation.y
	figure.rotation.y=rotate_toward(old_yaw,yaw,dt*(4.4 if boar else 6.4))
	var turn := clampf(angle_difference(old_yaw,figure.rotation.y)/maxf(dt,.001),-4.,4.)
	var load := smoothstep(0.,.38,phase)*(1.-smoothstep(.38,.62,phase))
	var strike := smoothstep(.38,.63,phase)*(1.-smoothstep(.69,1.,phase))
	var direction := Vector3.BACK.rotated(Vector3.UP,figure.rotation.y)
	figure.position=held_offset+direction*(reach*strike-.095*load)+recoil*.065
	var hop := .14*pow(sin(PI*clampf((phase-.38)/.43,0.,1.)),2) if not boar else 0.
	figure.position.y+=hop+(0. if boar else target_height*strike)
	var now := (global_position+figure.position).slide(Vector3.UP)
	var travel := (now-previous)/figure.scale.x
	previous=now
	_plant_feet(travel,dt)
	var stride := sin(PI*step_progress)
	var lean := recoil.rotated(Vector3.UP,-figure.rotation.y)
	var body_motion := Vector3(.016*stride*(1. if pair==0 else -1.),
		-.038+.008*sin(_time*2.9)+.018*stride-.072*load, .022*strike)
	rig.set_bone_pose_position(joints.Body,rig.get_bone_rest(joints.Body).origin+body_motion)
	_rotate("Body",Vector3(.045*stride+.13*load-.08*strike,-turn*.023,lean.x*.14))
	_rotate("Chest",Vector3(.10*load-.09*strike+.15*lean.z,turn*.047,0.))
	_rotate("Neck",Vector3((.36 if boar else .17)*load-(.25+target_height if boar else .09)*strike,turn*.053,.05*lean.x))
	_rotate("Head",Vector3(.08*load-.09*strike,turn*.035,0))
	_rotate("Jaw",Vector3((.14 if boar else .54)*load+.035*sin(_time*2.1),0,0))
	_rotate("Tail",Vector3(.045*sin(_time*2.3),.15*sin(_time*3.)-turn*.095,0))
	_rotate("TailTip",Vector3(.08*sin(_time*2.3-.42),.12*sin(_time*3.-.55)-turn*.045,0))
	for i in FEET.size():
		_leg(i,planted[i].rotated(Vector3.UP,-figure.rotation.y))


# Each diagonal pair swings in turn; the support paws remain on the board
# while the hips travel or pivot above them.
func _plant_feet(travel: Vector3, dt: float) -> void:
	var wanted: Array[Vector3]=[]
	for ankle in ankle_rest:
		wanted.append(ankle.rotated(Vector3.UP,figure.rotation.y))
	if planted.is_empty() or travel.length()>1.5:
		planted.assign(wanted)
		step_progress=1.
		return
	for i in FEET.size():
		planted[i]-=travel
	if step_progress<1.:
		step_progress=minf(1.,step_progress+dt/(.16 if boar else .13))
		for k in 2:
			var i := pair if k==0 else 3-pair
			starts[k]-=travel
			ends[k]-=travel
			planted[i]=starts[k].lerp(ends[k],smoothstep(0.,1.,step_progress))
			planted[i].y+=(.081 if boar else .126)*sin(PI*step_progress)
		return
	var errors := Vector2(maxf(planted[0].distance_to(wanted[0]),planted[3].distance_to(wanted[3])),
		maxf(planted[1].distance_to(wanted[1]),planted[2].distance_to(wanted[2])))
	var next := 1-pair
	if errors[next]<.074:
		if errors[pair]<.074: return
		next=pair
	pair=next
	var lead := (travel/maxf(dt,.001)*(.13 if boar else .11)).limit_length(.35)
	starts.assign([planted[pair],planted[3-pair]])
	ends.assign([wanted[pair]+lead,wanted[3-pair]+lead])
	step_progress=0.


func _leg(index: int, ankle: Vector3) -> void:
	var foot := FEET[index] as String
	var upper := joints["Upper"+foot]
	var lower := joints["Lower"+foot]
	var paw := joints["Paw"+foot]
	var parent := rig.get_bone_global_pose(rig.get_bone_parent(upper))
	var hip := parent*rig.get_bone_rest(upper).origin
	var a := rig.get_bone_rest(lower).origin
	var b := rig.get_bone_rest(paw).origin
	var axis := (ankle-hip).normalized()
	var length := clampf(hip.distance_to(ankle),.06,a.length()+b.length()-.0001)
	var along := (length*length+a.length_squared()-b.length_squared())/(2.*length)
	var bend := Vector3.FORWARD if index<2 else Vector3.BACK
	var knee := axis*along+bend.slide(axis).normalized()*sqrt(maxf(0.,a.length_squared()-along*along))
	var upper_q := Quaternion(a.normalized(),(parent.basis.inverse()*knee).normalized())
	rig.set_bone_pose_rotation(upper,upper_q)
	var base := parent.basis*Basis(upper_q)
	var lower_q := Quaternion(b.normalized(),(base.inverse()*(axis*length-knee)).normalized())
	rig.set_bone_pose_rotation(lower,lower_q)
	var foot_rotation := (base*Basis(lower_q)).get_rotation_quaternion().inverse()
	if not boar and index < 2 and index == pair and step_progress < 1.:
		# Flex the wrist as the paw lifts, then reach forward before contact.
		var pitch := .26*sin(TAU*step_progress)*sin(PI*step_progress)
		foot_rotation *= Quaternion(Vector3.RIGHT,pitch)
	rig.set_bone_pose_rotation(paw,foot_rotation)


func strike_at(target: UnitView) -> Tween:
	await turn_to_strike(target.position)
	var delta := target.global_position-global_position
	reach=clampf(delta.slide(Vector3.UP).length()-.83*figure.scale.x-.15,.12,.67 if boar else .48)
	target_height=clampf(delta.y,-.17,.22)
	var wind := create_tween()
	wind.tween_property(self,"phase",.38,.34 if boar else .18).from(0.).set_trans(Tween.TRANS_SINE)
	wind.tween_callback(Soundscape.cue.bind("step" if boar else "wolf_breath"))
	wind.tween_property(self,"phase",.63,.18 if boar else .12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await wind.finished
	var land := create_tween()
	land.tween_property(self,"phase",1.,.40 if boar else .28).set_trans(Tween.TRANS_SINE)
	return land


func react_to_hit(force: Vector3, severity: float) -> void:
	if _hit_tween: _hit_tween.kill()
	_hit_tween=create_tween()
	_hit_tween.tween_property(self,"recoil",force.normalized()*clampf(.65+severity,.65,1.25),.06)
	_hit_tween.tween_property(self,"recoil",Vector3.ZERO,.24).set_trans(Tween.TRANS_SINE)


func set_hold_offset(offset: Vector3) -> void:
	held_offset=offset


func set_reveal_region(rect: Rect2, screen_size: Vector2) -> void:
	var region := Vector4.ZERO
	if rect.has_area():
		var center := rect.get_center()/screen_size
		var radius := rect.size*.5/screen_size
		region=Vector4(center.x,center.y,radius.x,radius.y)
	_reveal_region=region
	surface.set_instance_shader_parameter("reveal_region",region)


func set_nearby_stone(_offset: Vector2) -> void:
	pass
