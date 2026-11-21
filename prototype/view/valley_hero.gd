class_name ValleyHero
extends UnitView
## Articulated mesh sample for the valley. Its root stays on the rules anchor.
var guarding := false
var model: Node3D
var skeleton: Skeleton3D
var joints: Dictionary[StringName,int] = {}
var cape_swing := Vector3.ZERO
var surfaces: Array[MeshInstance3D] = []
var bearing := 0.
var cycle := 0.
var gait_distance := .88
var standing_turn_speed := 285.
var gait := 0.
# Foot positions are in model units, in the board's horizontal axes.
var planted: Array[Vector3] = []
var sole_yaw: Array[float] = []
var toe_start := 0.
var toe_end := 0.
var stepping := -1
var step_start := Vector3.ZERO
var step_end := Vector3.ZERO
var step_time := 0.
var step_duration := .16
var bash_phase := 1.
var hit_phase := 1.
var hit_direction := Vector3.ZERO
var catching_foot := 0
var guard := 0.
var thrust := 0.
var spear_pitch := 0.
var pitch_goal := 0.
var extension_goal := 0.
var flinch := Vector3.ZERO
var heavy_hit := false
var parry := false
var displaced := false
var knee_bend := 0.
var hit_seconds := .78
var last_position := Vector3.ZERO


func setup(u: UnitState, _tex: Texture2D, _motion: Texture2D) -> void:
	_setup_figure(u,preload("res://art/original/hero_valley.glb"),preload("res://art/original/hero_pigments.png"),1.10)


func _setup_figure(u: UnitState, scene: PackedScene, pigments: Texture2D, size_factor: float) -> void:
	_setup_base(u,false)
	model = scene.instantiate()
	add_child(model)
	model.scale = Vector3.ONE*size_factor
	skeleton = model.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	for i in skeleton.get_bone_count():
		joints[skeleton.get_bone_name(i)] = i
	var finish := ShaderMaterial.new()
	finish.shader = preload("res://view/hero_surface.gdshader")
	finish.set_shader_parameter("pigments",pigments)
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		surfaces.append(mesh)
		mesh.material_override = finish
	set_facing(u.facing)
	model.rotation.y = bearing


func _process(dt: float) -> void:
	if model == null:
		return
	_time += dt
	var step := position.slide(Vector3.UP).distance_to(last_position.slide(Vector3.UP))
	last_position = position
	if walking:
		cycle += minf(step,.35)*TAU/gait_distance
	gait = move_toward(gait,1. if walking else 0.,dt*9.)
	var swing := sin(cycle)*gait
	var old_yaw := model.rotation.y
	model.rotation.y = rotate_toward(old_yaw,bearing,dt*deg_to_rad(360. if walking else standing_turn_speed))
	var turn := clampf(angle_difference(old_yaw,model.rotation.y)/maxf(dt,.001),-6.,6.)
	guard = lerpf(guard,maxf(float(guarding)*.72,_push_weight*.8),1.-exp(-18.*dt))
	var load := smoothstep(0.,.34,bash_phase)*(1.-smoothstep(.34,.54,bash_phase))
	var drive := smoothstep(.34,.54,bash_phase)*(1.-smoothstep(.59,1.,bash_phase))
	hit_phase = minf(1.,hit_phase+dt/hit_seconds)
	var recoil := smoothstep(0.,.11,hit_phase)*(1.-smoothstep(.19,.65,hit_phase))
	var settle := smoothstep(.12,.48,hit_phase)*(1.-smoothstep(.60,1.,hit_phase))
	flinch = hit_direction.rotated(Vector3.UP,-model.rotation.y)*recoil
	_update_footwork(dt)
	thrust = lerpf(thrust,extension_goal,1.-exp(-27.*dt))
	spear_pitch = lerpf(spear_pitch,pitch_goal,1.-exp(-25.*dt))
	var hip_height := .795-(.040+.018*pow(cos(cycle),2))*gait-.028*guard-.032*flinch.length()
	hip_height -= .075*load+.038*drive+.048*settle
	var support_shift := 0.
	if stepping >= 0:
		support_shift = (-1. if stepping == 0 else 1.)*.036*sin(PI*step_time)
	var hip_pos := Vector3(.019*swing-.015*guard+support_shift-.052*load+.035*drive,
		hip_height,.020*thrust-.115*load+.185*drive)
	hip_pos += hit_direction.rotated(Vector3.UP,-model.rotation.y)*(.093*recoil+.058*settle)
	hip_pos += _effort_offset()
	skeleton.set_bone_pose_position(joints.Hips,hip_pos)
	_rotate_bone("Hips",Vector3(.025*thrust,-.095-.095*swing+_effort_yaw(),.030*swing))
	var chest := Vector3(.035+.09*guard+.16*thrust-.11*load+.24*drive+flinch.z*.30,
		.105*swing-.24*thrust+.14*guard+.29*load-.36*drive,-turn*.011-flinch.x*.30)
	_rotate_bone("Chest",chest)
	_rotate_bone("Head",-chest*.34)
	var cape_target := Vector3(-.09*gait-.035*sin(_time*2.2)-.11*thrust,turn*.021,.034*swing)
	cape_swing = cape_swing.lerp(cape_target,1.-exp(-7.*dt))
	_rotate_bone("Mantle",cape_swing)
	_leg(0,"L",cycle,.063,hip_pos)
	_leg(1,"R",cycle+PI,-.063,hip_pos)
	_pose_arms(swing,load,drive)


func _pose_arms(swing: float, load: float, drive: float) -> void:
	var catch := _cover()
	var crush := catch if heavy_hit else 0.
	var incoming := -hit_direction.rotated(Vector3.UP,-model.rotation.y)
	var lift := catch*(.77 if parry else .58)+.39*crush
	var shield_yaw := clampf(atan2(incoming.x,maxf(.24,incoming.z)),-1.12,1.12)
	var chest := skeleton.get_bone_pose_rotation(joints.Chest)
	skeleton.set_bone_pose_rotation(joints.Chest,chest*Quaternion.from_euler(Vector3(.13*crush,-.25*catch+.34*shield_yaw*catch,0.)))
	var upper_r := -.25-.20*crush-.19*swing-.88*thrust
	var fore_r := -.18-.19*maxf(-thrust,0.)+.15*thrust
	_rotate_bone("ArmL",Vector3(-.40-1.12*lift+.14*swing-.88*guard-.40*load-1.00*drive,-.18-.38*guard-.27*lift,.10))
	_rotate_bone("ForeL",Vector3(-.18-.13*guard-.52*lift-.43*load+.12*drive,0.,-.055*guard))
	_rotate_bone("HandL",Vector3(.12*guard,-.08*guard,0))
	_rotate_bone("Shield",Vector3(.46+1.34*lift+.88*guard+.50*load+.82*drive,.55-.46*guard+catch*(shield_yaw-.47),-.07))
	if catch > 0.:
		# Aim the convex face in skeleton space after the elbow has folded.
		var hand := skeleton.get_bone_global_pose(joints.HandL).basis
		var presented := Basis(Vector3.UP,shield_yaw)*Basis(Vector3.RIGHT,-.14-.12*crush)
		var target := (hand.inverse()*presented).orthonormalized().get_rotation_quaternion()
		var raised := skeleton.get_bone_pose_rotation(joints.Shield)
		skeleton.set_bone_pose_rotation(joints.Shield,raised.slerp(target,catch))
	_rotate_bone("ArmR",Vector3(upper_r,-.08-.07*thrust,-.12))
	_rotate_bone("ForeR",Vector3(fore_r,0,.05*thrust))
	_rotate_bone("HandR",Vector3(.21+spear_pitch-upper_r-fore_r,0.,.13))
	_rotate_bone("Spear",Vector3(.03,0.,.07))


func _rotate_bone(bone: StringName, angles: Vector3) -> void:
	skeleton.set_bone_pose_rotation(joints[bone],Quaternion.from_euler(angles))


func _stance(index: int) -> Vector3:
	var sign_x := 1. if index == 0 else -1.
	var target := Vector3(.145*sign_x,.062,.082*sign_x).rotated(Vector3.UP,model.rotation.y)
	if index == catching_foot:
		target += hit_direction*.20*(1.-smoothstep(.58,1.,hit_phase))
	return target


func _update_footwork(dt: float) -> void:
	knee_bend = move_toward(knee_bend,0.,dt*2.6)
	if displaced:
		return
	if planted.is_empty() or walking:
		planted.assign([_stance(0),_stance(1)])
		sole_yaw.assign([model.rotation.y,model.rotation.y])
		stepping = -1
		return
	if stepping >= 0:
		step_time = minf(1.,step_time+dt/step_duration)
		sole_yaw[stepping] = lerp_angle(toe_start,toe_end,smoothstep(0.,1.,step_time))
		planted[stepping] = step_start.lerp(step_end,smoothstep(0.,1.,step_time))
		planted[stepping].y += minf(.095,step_start.distance_to(step_end)*.47)*pow(sin(PI*step_time),2)
		if step_time >= 1.:
			stepping = -1
		return
	var left := planted[0].distance_to(_stance(0))
	var right := planted[1].distance_to(_stance(1))
	if maxf(left,right) < .033:
		return
	stepping = 0 if left > right else 1
	step_start = planted[stepping]
	step_end = _stance(stepping)
	# Aim ahead during a pivot so one stride covers the next arc.
	var remaining := angle_difference(model.rotation.y,bearing)
	var lead := clampf(remaining,-.58,.58)
	step_end = step_end.rotated(Vector3.UP,lead)
	toe_start = sole_yaw[stepping]
	toe_end = model.rotation.y+lead
	step_time = 0.
	step_duration = clampf(.11+step_start.distance_to(step_end)*.26,.12,.19)


# The planted foot tracks backwards at the unit's travel speed. The other
# foot clears the ground, then both joint angles are solved from its ankle.
func _leg(index: int, side: String, phase: float, stance_z: float, hip_pos: Vector3) -> void:
	# Measured in rest space, including the slightly offset knee and ankle.
	var thigh := Vector2(.33,.019).length()
	var shin := Vector2(.345,.012).length()
	var stride := fposmod(phase/TAU,1.)
	var swing_part := clampf((stride-.5)*2.,0.,1.)
	var offset := .22-.88*stride
	if stride > .5:
		# Match the ground speed at both heel strike and toe-off.
		offset = -.22-.44*swing_part+.88*smoothstep(0.,1.,swing_part)
	var lift := .115*pow(sin(PI*swing_part),2)*gait
	var forward := lerpf(stance_z,offset,gait)
	var ankle := planted[index].rotated(Vector3.UP,-model.rotation.y)
	var socket := skeleton.get_bone_rest(joints["Thigh"+side]).origin
	ankle = ankle.lerp(Vector3(socket.x,.062+lift,forward),gait)
	var hips_basis := Basis(skeleton.get_bone_pose_rotation(joints.Hips))
	var delta := hips_basis.inverse()*(ankle-hip_pos)-socket
	var roll := atan2(delta.x,-delta.y)
	var down := Vector2(delta.x,delta.y).length()
	forward = delta.z
	var distance := clampf(Vector2(forward,down).length(),.04,thigh+shin-.0001)
	var knee := acos(clampf((distance*distance-thigh*thigh-shin*shin)/(2.*thigh*shin),-1.,1.))
	var hip := -atan2(forward,down)-atan2(shin*sin(knee),thigh+shin*cos(knee))
	hip += atan2(.019,.33)
	knee += atan2(-.012,.345)-atan2(.019,.33)
	var thigh_basis := Basis(Vector3.BACK,roll)*Basis(Vector3.RIGHT,hip)
	skeleton.set_bone_pose_rotation(joints["Thigh"+side],thigh_basis.get_rotation_quaternion())
	_rotate_bone("Shin"+side,Vector3(knee,0.,0.))
	var shin_basis := hips_basis*thigh_basis*Basis(Vector3.RIGHT,knee)
	var yaw := angle_difference(model.rotation.y,sole_yaw[index])*(1.-gait)
	var sole := Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,.25*sin(TAU*swing_part)*gait)
	skeleton.set_bone_pose_rotation(joints["Foot"+side],(shin_basis.inverse()*sole).get_rotation_quaternion())


func set_facing(f: Vector2i) -> void:
	if f != Vector2i.ZERO:
		bearing = atan2(float(f.x),float(f.y))


func face_point(point: Vector3) -> void:
	var d := point-position
	if absf(d.x)+absf(d.z) > .001:
		bearing = atan2(d.x,d.z)


func turn_to_strike(point: Vector3) -> void:
	face_point(point)
	while absf(angle_difference(model.rotation.y,bearing)) > .20:
		await get_tree().process_frame


func shield_strike() -> Tween:
	var strike := create_tween()
	strike.tween_property(self,"bash_phase",.54,.32).from(0.)
	await strike.finished
	var recover := create_tween()
	recover.tween_property(self,"bash_phase",1.,.30)
	return recover


func attack_key(key: int, _seconds := .1) -> void:
	pitch_goal = [-.12,.95,1.35,.69][key]
	extension_goal = [-.15,-.35,1.0,.32][key]


func set_pose(pose: int, _seconds: float) -> void:
	if pose < 0:
		pitch_goal = 0.
		extension_goal = 0.


func react_to_hit(force: Vector3, severity: float) -> void:
	receive_impact(force,severity,"",false)


func receive_impact(force: Vector3, severity: float, source: String, blocked: bool) -> void:
	if source == "fall" and knee_bend > .01:
		return
	_start_hit(force,severity)
	heavy_hit = not blocked and source in ["gore","pounce","club"]
	parry = blocked
	hit_seconds = .80 if heavy_hit else .37
	hit_direction *= 1.18 if heavy_hit else .24


func _cover() -> float:
	return smoothstep(0.,.16,hit_phase)*(1.-smoothstep(.35,1.,hit_phase))


# Both soles travel through the same board displacement as the rules anchor.
# The leading foot catches first; the trailing foot follows through.
func take_knockback(end: Vector3) -> void:
	var start := position
	var delta := end-start
	if delta.slide(Vector3.UP).is_zero_approx():
		return
	var axis := delta.slide(Vector3.UP).normalized()
	if hit_phase > .8:
		receive_impact(axis,.3,"gore",false)
	heavy_hit = true
	var local := axis.rotated(Vector3.UP,-model.rotation.y)
	catching_foot = 0 if local.dot(Vector3(.145,0.,.082))>0. else 1
	if planted.is_empty():
		_update_footwork(0.)
	var soles := planted.duplicate()
	displaced = true
	stepping = -1
	var drop := maxf(0.,-delta.y)
	var step := create_tween()
	step.tween_method(func(t: float):
		var body := smoothstep(0.,1.,t)
		position = start.lerp(end,body)
		if drop>.01:
			position.y = lerpf(start.y,end.y,t*t)+.08*sin(PI*t)
		for i in 2:
			var lead := i==catching_foot
			var phase := clampf((t-(0. if lead else .18))/(.78 if lead else .82),0.,1.)
			var sole := (soles[i] as Vector3).lerp(_stance(i),smoothstep(0.,1.,phase))
			sole += delta.slide(Vector3.UP)/model.scale.x*(smoothstep(0.,1.,phase)-body)
			sole.y += (.14 if lead else .10)*pow(sin(PI*phase),2)
			planted[i] = sole,
		0.,1.,clampf(.32+.09*drop,.32,.56))
	await step.finished
	displaced = false
	knee_bend = .64 if drop>.01 else .44


func _start_hit(force: Vector3, severity: float) -> void:
	hit_direction = force.slide(Vector3.UP).normalized()
	if hit_direction.is_zero_approx():
		hit_direction = Vector3.FORWARD.rotated(Vector3.UP,model.rotation.y)
	var local := hit_direction.rotated(Vector3.UP,-model.rotation.y)
	catching_foot = 0 if local.dot(Vector3(.145,0.,.082)) > 0. else 1
	hit_direction *= clampf(.75+severity,.75,1.25)
	hit_phase = 0.


func set_hold_offset(offset: Vector3) -> void:
	model.position = offset


func lift_body(height: float) -> void:
	model.position.y = height


func set_reveal_region(rect: Rect2, screen_size: Vector2) -> void:
	var region := Vector4.ZERO
	if rect.has_area():
		var center := rect.get_center()/screen_size
		var radius := rect.size*.5/screen_size
		region = Vector4(center.x,center.y,radius.x,radius.y)
	if region != _reveal_region:
		_reveal_region = region
		for mesh in surfaces:
			mesh.set_instance_shader_parameter("reveal_region",region)


func _effort_yaw() -> float:
	return 0.


func _effort_offset() -> Vector3:
	var brace := _cover()*(1. if heavy_hit else .32)
	return Vector3(-.044*brace,-.10*brace-.075*knee_bend,-.046*brace)


func set_nearby_stone(_offset: Vector2) -> void:
	pass


# Solve both links against the actual rest vectors. The elbow pole keeps
# the drawing elbow behind the arrow instead of folding it across the chest.
func _reach(side: String, goal: Vector3, pole: Vector3) -> Vector3:
	var upper := joints["Arm"+side]
	var fore := joints["Fore"+side]
	var hand := joints["Hand"+side]
	var parent := skeleton.get_bone_global_pose(joints.Chest)
	var shoulder := parent*skeleton.get_bone_rest(upper).origin
	var a := skeleton.get_bone_rest(fore).origin
	var b := skeleton.get_bone_rest(hand).origin
	var direction := (goal-shoulder).normalized()
	var dist := clampf(shoulder.distance_to(goal),.04,a.length()+b.length()-.0001)
	var along := (dist*dist+a.length_squared()-b.length_squared())/(2.*dist)
	var elbow := direction*along+pole.slide(direction).normalized()*sqrt(maxf(0.,a.length_squared()-along*along))
	var rotation := Quaternion(a.normalized(),(parent.basis.inverse()*elbow).normalized())
	skeleton.set_bone_pose_rotation(upper,rotation)
	var arm_basis := parent.basis*Basis(rotation)
	var wrist := direction*dist-elbow
	skeleton.set_bone_pose_rotation(fore,Quaternion(b.normalized(),(arm_basis.inverse()*wrist).normalized()))
	return shoulder+direction*dist


func plant_and_turn(heading: Vector2i) -> void:
	set_facing(heading)
	while absf(angle_difference(model.rotation.y,bearing)) > .065:
		await get_tree().process_frame
