class_name PaintedHeracles
extends ValleyHero

var bow := PaintedBow.new()
var equip := 0.
var draw := 0.
var aim_point := Vector3.ZERO
var arrow_loose := false
var release_hand := Vector3.ZERO
var pressure := 0.
var drive := 0.
var rock: Node3D
var faces := PackedVector3Array()
var palms := [Vector3.ZERO,Vector3.ZERO]
var released := false
var recovery_time := 0.
var last_contact: Array[Vector3] = []
var blow := 1.
var club_target := Vector3.ZERO
var clinch := 0.
var squeeze := 0.
var captive: UnitView
var pull_offset := Vector3.ZERO


func _windup() -> float:
	return smoothstep(0.,.43,blow)*(1.-smoothstep(.43,.64,blow))


func _follow_through() -> float:
	return smoothstep(.43,.70,blow)*(1.-smoothstep(.74,1.,blow))



func setup(u: UnitState, _tex: Texture2D, _motion: Texture2D) -> void:
	_setup_figure(u,preload("res://art/original/heracles.glb"),preload("res://art/original/heracles_pigments.png"),1.29)
	skeleton.add_child(bow)
	bow.length_half = .62
	bow.build(.033)
	gait_distance = .88*model.scale.x
	standing_turn_speed = 225.


func _stance(index: int) -> Vector3:
	var side := 1. if index == 0 else -1.
	var brace := smoothstep(0.,.18,pressure)
	var extra := Vector3(side*.041,0.,side*(.145*brace+.10*(_windup()+_follow_through())+.14*clinch+.11*equip))
	return super(index)+extra.rotated(Vector3.UP,model.rotation.y)


func _effort_yaw() -> float:
	return -.21*draw+.23*_windup()-.29*smoothstep(.39,.59,blow)*(1.-smoothstep(.74,1.,blow))


func _effort_offset() -> Vector3:
	var combat := Vector3(-.068*_windup()+.054*_follow_through(),-.083*_windup()-.048*_follow_through()-.18*clinch,
		-.072*_windup()+.132*_follow_through()+.235*clinch-.064*squeeze)
	return Vector3.DOWN*(.085*knee_bend+(.045 if heavy_hit else .012)*_cover())+Vector3(-.045*draw,-.055*equip-.034*draw,-.055*draw)+combat+Vector3(.031*pressure,-(.168-.065*drive)*pressure,(.083+.13*drive)*pressure)


func begin_push(target: Node3D, triangles: PackedVector3Array) -> void:
	rock = target
	faces = triangles
	drive = 0.
	released = false
	palms.fill(Vector3.ZERO)
	_sample_palms()


func release_push() -> void:
	last_contact.clear()
	for hand in [joints.HandL,joints.HandR]:
		last_contact.append(skeleton.get_bone_global_pose(hand).origin)
	recovery_time = 0.
	released = true


func finish_push() -> void:
	rock = null
	drive = 0.
	released = false


# Pick the near face of the actual rotating mesh, separately for each palm.
func _sample_palms() -> void:
	var forward := model.global_basis.z.normalized()
	var right := model.global_basis.x.normalized()
	for i in 2:
		var side := 1. if i == 0 else -1.
		var center := rock.global_position+right*(side*.24)
		center.y = minf(global_position.y+1.34,rock.global_position.y+.72)+side*.038
		var origin := rock.to_local(center-forward*2.)
		var ray := rock.to_local(center)-origin
		var nearest := INF
		for j in range(0,faces.size(),3):
			var hit = Geometry3D.ray_intersects_triangle(origin,ray,faces[j],faces[j+1],faces[j+2])
			if hit != null:
				var distance := origin.distance_squared_to(hit)
				if distance < nearest:
					nearest = distance
					palms[i] = rock.to_global(hit)-forward*.035
		if is_inf(nearest) and palms[i].is_zero_approx():
			palms[i] = center-forward*.48


func _pose_arms(swing: float, _load: float, _drive: float) -> void:
	var cover := _cover()
	var recoil_side := hit_direction.rotated(Vector3.UP,-model.rotation.y).x
	var wind := _windup()
	var follow := _follow_through()
	var chest := skeleton.get_bone_pose_rotation(joints.Chest)
	skeleton.set_bone_pose_rotation(joints.Chest,chest*Quaternion.from_euler(Vector3(.14*cover+.54*pressure-.09*wind+.23*follow+.46*clinch, .39*signf(recoil_side)*cover+.81*wind-.87*follow-.12*squeeze-.64*draw-.25*equip,.05*pressure-.11*wind+.09*follow)))
	_rotate_bone("Head",Vector3(-.14*cover-.33*pressure-.25*clinch,-.09*swing-.45*wind+.39*follow+.49*draw+.22*equip,0.))
	if rock and not released:
		_sample_palms()
	if is_instance_valid(captive):
		pull_offset = _captive_offset()
		captive.set_hold_offset(pull_offset)
	var parent := skeleton.get_bone_global_pose(joints.Chest)
	# The handle projects forward beside the belt; the heavy end lies behind the hip.
	var slung := parent*Transform3D(Basis.from_euler(Vector3(.86,0.,-.12)),Vector3(-.317,.115,.169))
	var rack := parent*Vector3(.24,.18,-.17)
	var pickup := smoothstep(.02,.39,equip)
	var present := smoothstep(.40,1.,equip)
	var forward := Vector3.BACK
	if equip > 0.:
		forward = (skeleton.to_local(aim_point)-Vector3(.045,1.32,0.)).normalized()
	var ready := Vector3(.065,1.04+.30*draw,0.)+forward*(.34+.18*draw)
	var bow_grip := rack.lerp(ready,present)
	bow_grip.x += .12*sin(PI*present)
	var rest_direction := (parent.basis*Vector3.BACK).normalized()
	var bow_direction := rest_direction.slerp(forward,present).normalized()
	var rack_up := (parent.basis*Vector3(.65,.74,0.)).normalized()
	var aimed_up := Vector3.UP.slide(forward).normalized().rotated(forward,-.40+.19*draw)
	var bow_up := rack_up.slerp(aimed_up,present).normalized()
	var nock := bow_grip-bow_direction*(.19+.41*draw)
	for i in 2:
		var side := 1. if i == 0 else -1.
		var name_side := "L" if i == 0 else "R"
		var goal := Vector3(side*.314,.88+.038*absf(swing),.137+side*.185*swing)
		if i == 1:
			goal += Vector3(-.09,.47,-.055)*wind+Vector3(.37,.16,.34)*follow
		else:
			goal += Vector3(-.08,.19,.16)*wind+Vector3(.04,.13,-.04)*follow
		if cover > 0.:
			var spread := .14 if heavy_hit else -.075
			goal += Vector3(side*spread,.21 if heavy_hit else .31,.13)*cover
		if equip > 0.:
			if i == 0:
				goal = goal.lerp(bow_grip,pickup)
			else:
				goal = goal.lerp(slung.origin,smoothstep(0.,.31,equip))
				var pull := nock
				if arrow_loose:
					# Let the drawing hand finish beside the jaw before lowering it.
					var recoil := release_hand+Vector3(-.045,.012,-.065)*smoothstep(0.,.29,1.-draw)
					pull = recoil.lerp(nock,smoothstep(.32,.95,1.-draw))
				goal = goal.lerp(pull,smoothstep(.39,1.,equip))
		elif is_instance_valid(captive):
			var reach := smoothstep(.17,.82,clinch) if i == 0 else smoothstep(.35,.99,clinch)
			if i == 1:
				goal = goal.lerp(slung.origin,smoothstep(0.,.31,clinch))
			var center := skeleton.to_local(captive.global_position+pull_offset)
			var radius := .27*sqrt(float(captive.size))
			var height := clampf(center.y+captive.sprite_height*.48/model.scale.y,.67,1.36)
			var grip := Vector3(center.x+side*radius*(1.-.22*squeeze),height+side*.048,
				center.z-radius+.045*squeeze)
			goal = goal.lerp(grip,reach)
			goal.x += side*.10*sin(PI*reach)
		elif released:
			goal = _recover_hand(i,goal,slung.origin)
		elif rock:
			var grasp := smoothstep(0.,.60,pressure)
			if i == 1:
				goal = goal.lerp(slung.origin,smoothstep(0.,.31,pressure))
				grasp = smoothstep(.31,.74,pressure)
			goal = goal.lerp(skeleton.to_local(palms[i]),grasp)
		var pole := Vector3(side*.75,-.62,-.38)
		if i == 1 and (rock or equip > 0.):
			# Solve in a forward-bending elbow plane as the hand takes the handle.
			var shoulder := parent*skeleton.get_bone_rest(joints.ArmR).origin
			var bend := parent.basis.x.cross(goal-shoulder).normalized()
			var carry := 1.-smoothstep(.32,.74,pressure)
			if released:
				carry = smoothstep(.54,.84,recovery_time)*(1.-smoothstep(1.79,1.99,recovery_time))
			if equip > 0.:
				carry = 1.-smoothstep(.40,.90,equip)
				pole = pole.lerp(Vector3(-.88,-.14,-.48),draw)
			pole = pole.lerp(bend,carry)
		_reach(name_side,goal,pole)
		var fore := skeleton.get_bone_global_pose(joints["Fore"+name_side])
		var palm_rotation := fore.basis.get_rotation_quaternion().inverse()
		skeleton.set_bone_pose_rotation(joints["Hand"+name_side],Quaternion.IDENTITY.slerp(palm_rotation,smoothstep(0.,.65,pressure)))
	# Shift the club from the carrying hand into the belt sling.
	var wrist := skeleton.get_bone_global_pose(joints.HandR).origin
	var carried := Transform3D(Basis.from_euler(Vector3(-.45+.15*swing-2.49*wind-(.95 if parry else .61)*cover,0.,-.24-.70*wind)),wrist)
	if follow > 0.:
		var aim := (skeleton.to_local(club_target)-wrist).normalized()
		var cross_body := .94*smoothstep(.64,.78,blow)
		var aimed := Basis(Quaternion(Vector3.DOWN,aim.rotated(Vector3.UP,cross_body)))
		carried.basis = carried.basis.slerp(aimed,smoothstep(0.,.87,follow))
	var belt := maxf(equip,maxf(pressure,clinch))
	var stow := smoothstep(0.,.32,belt)
	var club_pose := carried.interpolate_with(slung,stow)
	club_pose.origin = wrist.lerp(slung.origin,smoothstep(.25,.32,belt))
	if released:
		var lower := smoothstep(1.43,1.99,recovery_time)
		club_pose = slung.interpolate_with(carried,lower)
		# Hold the sling until the wrist has arrived, then carry the
		# handle at the wrist throughout the lift and lowering arc.
		if recovery_time >= 1.43:
			club_pose.origin = wrist
	var club := parent.affine_inverse()*club_pose
	skeleton.set_bone_pose_position(joints.Club,club.origin)
	skeleton.set_bone_pose_rotation(joints.Club,club.basis.get_rotation_quaternion())

	# Once off the rack, bind the stave to the solved hand and the arrow to the string.
	var bow_hand := skeleton.get_bone_global_pose(joints.HandL).origin
	var bow_center := rack.lerp(bow_hand,smoothstep(.39,.44,equip))
	var string := bow_center-bow_direction*(.19+.10*draw)
	if not arrow_loose:
		string = string.lerp(wrist,present)
	bow.pose(bow_center,bow_up,bow_direction,string,draw)


func shoot(target: UnitView, point: Vector3) -> Tween:
	await turn_to_strike(target.position)
	aim_point = point
	arrow_loose = false
	var prepare := create_tween()
	prepare.tween_property(self,"equip",1.,.74).set_trans(Tween.TRANS_SINE)
	prepare.tween_callback(bow.nock)
	prepare.tween_callback(Soundscape.cue.bind("bow_draw"))
	prepare.tween_property(self,"draw",.76,.36).set_trans(Tween.TRANS_SINE)
	prepare.tween_property(self,"draw",1.,.22).set_trans(Tween.TRANS_SINE)
	prepare.tween_interval(.11)
	await prepare.finished
	Soundscape.cue("arrow")
	release_hand = skeleton.get_bone_global_pose(joints.HandR).origin
	arrow_loose = true
	var travel := clampf(bow.shaft.global_position.distance_to(point)/14.,.13,.40)
	var flight := bow.loose(get_parent(),point,travel)
	var settle := create_tween()
	settle.tween_interval(.07)
	settle.tween_property(self,"draw",.68,.13).set_trans(Tween.TRANS_SINE)
	settle.tween_property(self,"draw",0.,.30).set_trans(Tween.TRANS_SINE)
	settle.tween_property(self,"equip",0.,.80).set_trans(Tween.TRANS_SINE)
	await flight.finished
	return settle


func _recover_hand(index: int, idle: Vector3, handle: Vector3) -> Vector3:
	var left := index == 0
	var relaxed := idle+Vector3(.035 if left else -.035,.055,.070)
	var withdraw := smoothstep(.07 if left else .0,.67 if left else .54,recovery_time)
	var goal := last_contact[index].lerp(relaxed,withdraw)
	goal.y += .042*sin(PI*withdraw)
	if left:
		return goal.lerp(idle,smoothstep(.68,1.08,recovery_time))
	# Approach from above the belt and lift the head clear before lowering.
	var reach := smoothstep(.84,1.33,recovery_time)
	goal = goal.lerp(handle,reach)
	goal.y += .045*sin(PI*reach)
	var lower := smoothstep(1.43,1.99,recovery_time)
	goal = goal.lerp(idle,lower)
	goal.x -= .075*sin(PI*lower)
	goal.y += .078*sin(PI*lower)
	goal.z += .058*sin(PI*lower)
	return goal


# End the first tween at contact so damage and knockback run on the strike.
func swing_club(point: Vector3) -> Tween:
	club_target = point
	var strike := create_tween()
	strike.tween_property(self,"blow",.43,.39).from(0.)
	strike.tween_callback(Soundscape.cue.bind("swing"))
	strike.tween_property(self,"blow",.64,.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await strike.finished
	var settle := create_tween()
	settle.tween_property(self,"blow",.76,.14).set_trans(Tween.TRANS_SINE)
	settle.tween_property(self,"blow",1.,.38).set_trans(Tween.TRANS_SINE)
	return settle


func _captive_offset() -> Vector3:
	var toward := (global_position-captive.global_position).slide(Vector3.UP)
	var gap := toward.length()
	var touch := clampf(gap-.93,0.,.48)*smoothstep(.47,1.,clinch)
	var draw_in := (.07+.07*sqrt(float(captive.size)))*squeeze
	var offset := toward.normalized()*(touch+draw_in)
	# Lower the visual contact along the height difference between the two cells.
	offset.y = (global_position.y-captive.global_position.y)*(touch+draw_in)/maxf(gap,.01)
	return offset


func seize(target: UnitView) -> void:
	await turn_to_strike(target.position)
	captive = target
	var reach := create_tween()
	reach.tween_property(self,"clinch",.43,.25).set_trans(Tween.TRANS_SINE)
	reach.tween_property(self,"clinch",1.,.23).set_trans(Tween.TRANS_SINE)
	await reach.finished


func tighten_hold() -> void:
	var lock := create_tween()
	lock.tween_property(self,"squeeze",1.,.32).set_trans(Tween.TRANS_SINE)
	await lock.finished


func open_hold() -> void:
	if not captive:
		return
	var unwind := create_tween().set_parallel()
	unwind.tween_property(self,"squeeze",0.,.22)
	unwind.tween_property(self,"clinch",0.,.52).set_trans(Tween.TRANS_SINE)
	await unwind.finished
	captive.set_hold_offset(Vector3.ZERO)
	captive = null


func sync_hold(target: UnitView) -> void:
	if target != captive:
		if is_instance_valid(captive):
			captive.set_hold_offset(Vector3.ZERO)
		captive = target
		clinch = float(is_instance_valid(target))
		squeeze = clinch


func set_nearby_stone(_offset: Vector2) -> void:
	pass
