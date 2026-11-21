extends UnitView
var frames=preload("res://view/cast_frames.gd").new()
var yaw := 0.
var bearing := 0.
var previous_position := Vector3.ZERO
var distance := 0.
var hit_phase := 1.
var lift := 0.
var hold_offset := Vector3.ZERO
var transition := ""

func setup(u: UnitState,_tex: Texture2D,_motion: Texture2D):
	_setup_base(u)
	add_child(frames)
	frames.setup(u.def_id)
	set_facing(u.facing)
	yaw=bearing

func _process(dt):
	var previous_yaw=yaw
	yaw=rotate_toward(yaw,bearing,dt*5.6)
	var angle=frames.view_angle(yaw)
	var d=posmod(roundi(angle*8),8)
	if walking: distance+=minf(.36,previous_position.slide(Vector3.UP).distance_to(position.slide(Vector3.UP)))
	previous_position=position
	frames.position=hold_offset+Vector3.UP*lift
	hit_phase=minf(1.,hit_phase+dt/.30)
	_transition_time+=dt
	if _attacking:
		_time+=dt
		if _time>=.24:
			_attacking=false
			set_pose(-1,.16)
	if hit_phase<1.:
		frames.sample("hit",d,hit_phase)
	elif transition!="" and _transition_time<_pose_seconds:
		frames.sample(transition,d,_transition_time/maxf(.001,_pose_seconds))
	elif held_pose>=0:
		frames.display("pose%d"%held_pose,d,0)
	elif walking:
		var count=frames.clips.walk[d].size()
		frames.display("walk",d,floori(fposmod(distance,1.)*count))
	elif absf(angle_difference(previous_yaw,yaw))>.0001:
		var tick=roundi(angle*64)
		frames.display("turn",posmod(floori(tick/8.),8),posmod(tick,8))
	else:
		frames.display("idle",d,0)

func set_pose(pose: int,seconds: float):
	var before=maxi(held_pose,0)
	var after=maxi(pose,0)
	if not frames.clips.has("pose%d"%after): after=0
	var pair="from%dto%d"%[before,after]
	transition=pair if frames.clips.has(pair) else ""
	held_pose=after if pose>=0 else -1
	_transition_time=0.
	_pose_seconds=seconds

func set_facing(f: Vector2i):
	if f!=Vector2i.ZERO: bearing=atan2(float(f.x),float(f.y))

func face_point(point: Vector3):
	var delta=(point-position).slide(Vector3.UP)
	if delta.length_squared()>.0001: bearing=atan2(delta.x,delta.z)

func plant_and_turn(f: Vector2i):
	set_facing(f)
	while absf(angle_difference(yaw,bearing))>.09: await get_tree().process_frame

func turn_to_strike(point: Vector3):
	face_point(point)
	while absf(angle_difference(yaw,bearing))>.09: await get_tree().process_frame

func play_attack():
	_attacking=true
	_time=0.
	set_pose(2,.16)

func react_to_hit(_force: Vector3,_severity: float): hit_phase=0.
func lift_body(y: float): lift=y
func set_hold_offset(offset: Vector3): hold_offset=offset
func set_nearby_stone(_offset: Vector2): pass

func set_reveal_region(rect: Rect2,screen_size: Vector2):
	var region=Vector4.ZERO
	if rect.has_area():
		var mid=(rect.position+rect.size*.5)/screen_size
		var radii=rect.size*.5/screen_size
		region=Vector4(mid.x,mid.y,radii.x,radii.y)
	frames.set_instance_shader_parameter("reveal_region",region)
