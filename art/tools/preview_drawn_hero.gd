extends SceneTree
## Run at 60 fixed fps, with --battle=1-4 and --data-dir pointing to hero-pixel-study/trial.
const LEFT = 1 << 18
const RIGHT = 1 << 19
var c
var hero
var panels = []
var output = OS.get_temp_dir().path_join("nemea-drawn-hero")
var baseline
var compare_brace = "--compare-brace" in OS.get_cmdline_user_args()
var token
var stage = "ready"
var done = false
var stopped = 0
var was_walking = false
var hit_seen = false
var path_length = 0.0

func _initialize(): call_deferred("run")

func act(command):
	var error = Rules.validate(c.state,command)
	if error != "":
		push_error(str(command,error))
		quit(1)
		return
	await c._perform(command)

func sequence():
	await create_timer(.6).timeout
	stage = "walk"
	await act({"type":"move","unit":"hero","to":Vector2i(5,4)})
	stage = "turn"
	await create_timer(.10).timeout
	await act({"type":"face","unit":"hero","facing":Vector2i.RIGHT})
	await create_timer(.36).timeout
	stage = "guard"
	await act({"type":"wait","unit":"hero"})
	await create_timer(.72).timeout
	Rules.end_phase(c.state)
	stage = "strike"
	var hp = c.state.unit("hero").hp
	await act({"type":"skill","skill":"gore","unit":"boar_w","target":Vector2i(5,4)})
	stage = "recover"
	await create_timer(1.1).timeout
	print("HP ",hp," -> ",c.state.unit("hero").hp," travel ",path_length," observed hit ",hit_seen)
	if not hit_seen or hp<=c.state.unit("hero").hp or abs(path_length-2.)>.05:
		push_error("Combat verification failed")
		quit(1)
	done = true

func run():
	change_scene_to_file("res://main.tscn")
	await scene_changed
	if compare_brace: output += "-brace"
	c = current_scene
	hero = c.unit_views.hero
	c.cam_rig.post.layers = 1<<17
	c.highlights.hide()
	var focus = Vector3(6.0,.86,5.05)
	for i in 2:
		DirAccess.make_dir_recursive_absolute(output.path_join(["left","right"][i]))
		var view = SubViewport.new()
		view.size = Vector2i(608,416)
		view.world_3d = hero.get_world_3d()
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		panels.append(view)
		var cam = Camera3D.new()
		view.add_child(cam)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 4.05
		cam.cull_mask = 1 | [LEFT,RIGHT][i]
		cam.position = focus+Vector3(.558,.616,.558)*30.
		cam.look_at(focus)
		cam.current = true
	hero.figure.layers = LEFT
	token = MeshInstance3D.new()
	token.mesh = QuadMesh.new()
	token.extra_cull_margin = 4.
	token.layers = RIGHT
	token.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hero.add_child(token)
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = preload("res://view/hoplite_frame.gdshader").code.replace("filter_linear","filter_nearest").replace("vec2(160.)","vec2(80.,116.)").replace("vec2(.015,-.015)","vec2(.021,-.021)").replace("offset.y+=1.18*cos(radians(38.));","")
	mat.shader = shader
	var img = Image.load_from_file(ProjectSettings.globalize_path("res://../art/originals/hero-pixel-study/hero.png"))
	mat.set_shader_parameter("atlas",ImageTexture.create_from_image(img))
	token.material_override = mat
	token.set_instance_shader_parameter("frame_origin",Vector2.ZERO)
	if compare_brace:
		hero.figure.hide()
		baseline = token.duplicate()
		hero.add_child(baseline)
		baseline.layers = LEFT
		var revised = mat.duplicate()
		var revised_image = Image.load_from_file(ProjectSettings.globalize_path("res://../art/originals/hero-pixel-study/hero-brace.png"))
		revised.set_shader_parameter("atlas",ImageTexture.create_from_image(revised_image))
		token.material_override = revised
	for k in 24: await process_frame
	var trace = FileAccess.open(output.path_join("trace.tsv"),FileAccess.WRITE)
	sequence()
	var n = 0
	var last_position = hero.position
	while not done and n<550:
		await process_frame
		var frame = 0
		if hero.walking:
			path_length += hero.position.slide(Vector3.UP).distance_to(last_position.slide(Vector3.UP))
			frame = 1 + posmod(roundi(path_length/.90*48),48)
		elif was_walking or stopped>0:
			if was_walking:
				path_length += hero.position.slide(Vector3.UP).distance_to(last_position.slide(Vector3.UP))
				stopped = 6
			frame = 49 + 6-stopped
			stopped -= 1
		elif stage!="ready" and stage!="walk":
			var yaw = clampf(angle_difference(hero.model.rotation.y,PI/2.)/(-PI/2.),0.,1.)
			frame = 57 + roundi((1.-yaw)*16)
			if stage in ["guard","strike","recover"]:
				frame = 74 + roundi(clampf(hero.raise_time/.30,0.,1.)*23)
				if hero.hit_phase < 1.:
					hit_seen = true
					frame = 98 + roundi(hero.hit_phase*39)
				elif hit_seen: frame = 137
		was_walking = hero.walking
		last_position = hero.position
		token.position = hero.figure.position
		token.set_instance_shader_parameter("frame_rect",Vector4((frame%12)*160,floori(frame/12.)*128,160,128))
		if compare_brace:
			baseline.position = token.position
			baseline.set_instance_shader_parameter("frame_rect",token.get_instance_shader_parameter("frame_rect"))
		await RenderingServer.frame_post_draw
		var event_label = "hit" if frame>=98 and frame<115 else ("settle" if frame>=115 else stage)
		trace.store_line(str(n,"\t",event_label,"\t",frame) if compare_brace else str(n,"\t",event_label))
		for i in 2:
			panels[i].get_texture().get_image().save_jpg(output.path_join(["left","right"][i]).path_join("%04d.jpg"%n),.97)
		n+=1
	if not done: quit(1)
	else:
		print("PASS ",n," matched frames")
		GoEngine.shutdown()
		root.get_node("Soundscape").quit_game()
