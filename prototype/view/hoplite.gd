extends ValleyHero
## Painted chapter-one hero. The scene uses baked frames; the authoring rig lives offline.
const FRAMES=preload("res://art/original/hoplite/frames.json")
const VIEWS=[
	preload("res://art/original/hoplite/view_0.webp"),preload("res://art/original/hoplite/view_1.webp"),
	preload("res://art/original/hoplite/view_2.webp"),preload("res://art/original/hoplite/view_3.webp"),
	preload("res://art/original/hoplite/view_4.webp"),preload("res://art/original/hoplite/view_5.webp"),
	preload("res://art/original/hoplite/view_6.webp"),preload("res://art/original/hoplite/view_7.webp")]
var figure: MeshInstance3D
var materials: Array[ShaderMaterial]=[]
var spear_time := 1.
var raise_time := 0.
var settled_guard := false
var active_clip := ""
var last_frame := -1
var last_view := -1

func setup(u: UnitState,_tex: Texture2D,_motion: Texture2D) -> void:
	_setup_base(u)
	model=Node3D.new()
	add_child(model)
	set_facing(u.facing)
	model.rotation.y=bearing
	figure=MeshInstance3D.new()
	figure.mesh=QuadMesh.new()
	figure.extra_cull_margin=3.
	figure.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(figure)
	for atlas in VIEWS:
		var material=ShaderMaterial.new()
		material.shader=preload("res://view/hoplite_frame.gdshader")
		material.set_shader_parameter("atlas",atlas)
		materials.append(material)
	_show("idle",0,0)

func _show(clip: String,direction: int,index: int) -> void:
	var frames: Array=FRAMES.data[clip][direction]
	index=clampi(index,0,frames.size()-1)
	if active_clip==clip and last_view==direction and last_frame==index: return
	if last_view!=direction: figure.material_override=materials[direction]
	active_clip=clip
	last_view=direction
	last_frame=index
	var rect: Array=frames[index]
	figure.set_instance_shader_parameter("frame_rect",Vector4(rect[0],rect[1],rect[2],rect[3]))
	figure.set_instance_shader_parameter("frame_origin",Vector2(rect[4],rect[5]))

func _process(dt: float) -> void:
	if figure==null: return
	var previous=model.rotation.y
	model.rotation.y=rotate_toward(previous,bearing,dt*deg_to_rad(360. if walking else standing_turn_speed))
	var turn=angle_difference(previous,model.rotation.y)
	var camera=get_viewport().get_camera_3d()
	var yaw:=0.
	if camera:
		var eye=camera.global_basis.z
		yaw=atan2(eye.x,eye.z)
	var angle=fposmod(model.rotation.y-yaw+deg_to_rad(15.),TAU)/TAU
	var direction=posmod(roundi(angle*8),8)
	var travel=position.slide(Vector3.UP).distance_to(last_position.slide(Vector3.UP))
	last_position=position
	if walking: cycle=fposmod(cycle+minf(.35,travel)/gait_distance,1.)
	var brace=guarding or _push_weight>.1
	if raise_time>=.96: settled_guard=true
	if raise_time<=0.: settled_guard=false
	if not brace: raise_time=minf(raise_time,19./60.)
	raise_time=move_toward(raise_time,62./60. if brace else 0.,dt)
	guard=.72*(1.-exp(-18.*raise_time))
	hit_phase=minf(1.,hit_phase+dt/hit_seconds)
	spear_time+=dt
	figure.position=model.position
	if hit_phase<1.:
		var clip="block" if parry else ("heavy" if heavy_hit else "light")
		_show(clip,direction,roundi(hit_phase*(FRAMES.data[clip][direction].size()-1)))
	elif bash_phase<1.:
		var elapsed=.32*acos(1.-2.*clampf(bash_phase/.54,0.,1.))/PI if bash_phase<.54 else .32+.30*(bash_phase-.54)/.46
		_show("bash",direction,roundi(elapsed*60))
	elif spear_time<.60:
		_show("spear",direction,int(spear_time*60))
	elif absf(turn)>.001 and not walking:
		var right=turn>0
		var tick=roundi(angle*64)*(1 if right else -1)
		var sector=floori(tick/8.)*(1 if right else -1)
		_show("turn_right" if right else "turn_left",posmod(sector,8),posmod(tick,8))
	elif walking:
		_show("walk",direction,posmod(roundi(cycle*32)-1,32))
	elif raise_time>0.:
		_show("guard_lower" if settled_guard and not brace else "guard",direction,roundi(raise_time*60))
	else:
		_show("idle",direction,0)

func attack_key(key: int,_seconds := .1) -> void:
	spear_time=[0.,5./60.,11./60.,18./60.][key]

func set_reveal_region(rect: Rect2,screen_size: Vector2) -> void:
	super.set_reveal_region(rect,screen_size)
	figure.set_instance_shader_parameter("reveal_region",_reveal_region)
