extends SceneTree
## Trial: can a rigged 3D character stand in for a hand-drawn one? Renders a model from the
## battle's camera angle into frames the size of ours (160x128), facing front and back.
##
##     godot --path prototype -s ../art/tools/bake_3d_trial.gd -- <model.fbx in res://> <texture or ""> <out folder> [clip=frames ...]
##
## With no clips named it only lists the model's animations.

const FRAME := Vector2i(160,128)
const PITCH := 22.0  # our figures are drawn from lower than the field is seen: nearer eye level
const YAW := -15.0
const TALL := 1.88  # a person, in world units
const SPAN := 2.3  # world units the frame's height covers

func _initialize() -> void:
	_bake.call_deferred()

func _bake() -> void:
	var args := OS.get_cmdline_user_args()
	var view := SubViewport.new()
	view.size = FRAME
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var world := Node3D.new()
	view.add_child(world)
	var air := WorldEnvironment.new()
	air.environment = Environment.new()
	air.environment.background_mode = Environment.BG_COLOR
	air.environment.background_color = Color(0,0,0,0)
	air.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.environment.ambient_light_color = Color(0.78,0.8,0.88)
	air.environment.ambient_light_energy = 1.25
	world.add_child(air)
	var yaw := deg_to_rad(YAW)
	var pitch := deg_to_rad(PITCH)
	var back := Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = SPAN
	world.add_child(camera)
	var aim := Vector3(0,TALL*.5+.1,0)
	camera.look_at_from_position(aim+back*12.0,aim)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.7
	world.add_child(sun)
	# Light from the upper left of the picture, as on the field.
	sun.look_at_from_position(aim+(camera.global_basis.y*1.4-camera.global_basis.x+camera.global_basis.z*.9)*5.0,aim)
	var model := (load(args[0]) as PackedScene).instantiate() as Node3D
	world.add_child(model)
	if args.size() > 1 and args[1] != "":
		var paint := StandardMaterial3D.new()
		paint.albedo_texture = load(args[1])
		paint.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		paint.roughness = 1.0
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false): part.material_override = paint
	var box := AABB()
	var any := false
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var reach: AABB = (model.global_transform.affine_inverse()*part.global_transform)*part.get_aabb()
		box = reach if not any else box.merge(reach)
		any = true
	model.scale = Vector3.ONE*TALL/box.size.y
	var player: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
	print("animations: ",player.get_animation_list())
	for name: String in player.get_animation_list(): print("  ",name," ",snappedf(player.get_animation(name).length,.01),"s")
	if args.size() < 4:
		quit()
		return
	var right := camera.global_basis.x
	var away := -Vector3(back.x,0,back.z).normalized()
	var facings := {"front":(-right-away).normalized(),"back":(-right+away).normalized()}
	DirAccess.make_dir_recursive_absolute(args[2])
	for facing: String in facings:
		var toward: Vector3 = facings[facing]
		model.rotation.y = atan2(toward.x,toward.z)
		for want: String in args.slice(3):
			var clip := want.get_slice("=",0)
			var frames := int(want.get_slice("=",1))
			var length := player.get_animation(clip).length
			var strip := Image.create(FRAME.x*frames,FRAME.y,false,Image.FORMAT_RGBA8)
			for f in frames:
				player.play(clip)
				player.seek(length*f/float(frames),true)
				player.pause()
				for wait in 3: await process_frame
				await RenderingServer.frame_post_draw
				strip.blit_rect(view.get_texture().get_image(),Rect2i(Vector2i.ZERO,FRAME),Vector2i(FRAME.x*f,0))
			strip.save_png("%s/%s-%s.png" % [args[2],clip.get_slice("|",clip.get_slice_count("|")-1).to_lower(),facing])
			print("wrote ",clip," ",facing)
	quit()
