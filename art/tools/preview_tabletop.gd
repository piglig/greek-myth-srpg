extends SceneTree
## Use --fixed-fps 60 -- --battle=1-4 --data-dir=<absolute art/originals/tabletop/trial>.
const ORIGINAL = 1 << 18
const MINI = 1 << 19
const IDS = ["hero","atalanta","boar_w"]
const WIDTH = [.93,1.13,1.62]
var compare_pixels = "--pixel" in OS.get_cmdline_user_args()
var c
var cameras = []
var panels = []
var pieces = []
var endpoints = []
var stage = "join"
var finished = false
var output = OS.get_temp_dir().path_join("nemea-tabletop")
var frame = 0

func _initialize():
	call_deferred("run")

func prepare_camera(parent_view, mask, focus):
	var cam = Camera3D.new()
	parent_view.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.85
	cam.cull_mask = 1 | mask
	cam.global_position = focus + Vector3(-.204,.616,.761)*30.
	cam.look_at(focus)
	cam.current = true
	return cam

func add_piece(index, layer, pixel):
	var actor = c.unit_views[IDS[index]]

	var token = Sprite3D.new()
	var asset = ProjectSettings.globalize_path("res://../art/originals/tabletop/").path_join(IDS[index]+".png")
	if pixel:
		asset = asset.get_base_dir().path_join("pixel").path_join(asset.get_file())
	var img = Image.load_from_file(asset)
	token.texture = ImageTexture.create_from_image(img)
	token.pixel_size = WIDTH[index]/img.get_width()
	token.centered = false
	# Bottom of ellipse sits in front of the logical cell centre.
	token.offset = Vector2(-img.get_width()*.5,-img.get_width()*[.17,.13,.16][index])
	var finish = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D piece : source_color, filter_linear, repeat_disable;
varying float floor_y;
void vertex(){floor_y=MODEL_MATRIX[3].y;}
void fragment(){
	vec4 paint=texture(piece,UV);
	if(paint.a<.43){discard;}
	vec3 p=VERTEX;
	float below=floor_y-(INV_VIEW_MATRIX*vec4(p,1.)).y;
	p.z+=max(0.,below)/max(.1,INV_VIEW_MATRIX[2].y);
	vec4 clip=PROJECTION_MATRIX*vec4(p,1.);
	DEPTH=clip.z/clip.w;
	ALBEDO=paint.rgb;
}"""
	if pixel:
		shader.code = shader.code.replace("filter_linear","filter_nearest")
	finish.shader = shader
	finish.set_shader_parameter("piece",token.texture)
	token.material_override = finish
	var shadow = NemeaField.shadow(WIDTH[index]*1.12,WIDTH[index]*.89)
	shadow.layers = layer
	actor.add_child(shadow)
	token.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	token.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	token.layers = layer
	var pivot = Node3D.new()
	actor.add_child(pivot)
	pivot.add_child(token)
	pieces.append(pivot)
	endpoints.append(token)

func perform(action):
	var problem = Rules.validate(c.state,action)
	if problem != "":
		push_error(str(action," ",problem))
		quit(1)
		return
	await c._perform(action)

func sequence():
	await create_timer(.65).timeout
	await perform({"type":"move","unit":"hero","to":Vector2i(5,4)})
	stage = "cluster"
	await create_timer(.9).timeout
	stage = "shoot"
	await perform({"type":"skill","skill":"shoot","unit":"atalanta","target":Vector2i(6,4)})
	stage = "guard"
	await perform({"type":"wait","unit":"hero"})
	await create_timer(.65).timeout
	Rules.end_phase(c.state)
	stage = "charge"
	await perform({"type":"skill","skill":"gore","unit":"boar_w","target":Vector2i(5,4)})
	stage = "settle"
	await create_timer(1.15).timeout
	print("Final HP hero ",c.state.unit("hero").hp," boar ",c.state.unit("boar_w").hp)
	finished = true

func run():
	change_scene_to_file("res://main.tscn")
	await scene_changed
	c = current_scene
	if compare_pixels: output += "-pixel"
	for side in ["left","right"]:
		DirAccess.make_dir_recursive_absolute(output.path_join(side))
	c._sync_views()
	for id in c.unit_views:
		if id not in IDS: c.unit_views[id].hide()
	c.highlights.hide()
	c.cam_rig.post.layers = 1<<17
	var focus = Vector3(6.1,.70,4.55)
	for layer in [ORIGINAL, MINI]:
		var view = SubViewport.new()
		view.size = Vector2i(608,416)
		view.world_3d = c.unit_views.hero.get_world_3d()
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		panels.append(view)
		cameras.append(prepare_camera(view,layer,focus))
	for i in IDS.size():
		var actor = c.unit_views[IDS[i]]
		for part in actor.find_children("*","GeometryInstance3D",true,false):
			part.layers = (1 << 16) if compare_pixels else ORIGINAL
		add_piece(i, MINI, compare_pixels)
	if compare_pixels:
		for i in IDS.size(): add_piece(i, ORIGINAL, false)
	for k in 18: await process_frame
	sequence()
	var notes = FileAccess.open(output.path_join("trace.tsv"),FileAccess.WRITE)
	while not finished and frame<610:
		await process_frame
		var hero = c.unit_views.hero
		var archer = c.unit_views.atalanta
		var boar = c.unit_views.boar_w
		var drive = sin(PI*boar.phase) if boar.phase<1. else 0.
		pieces[2].position = boar.figure.position + Vector3.LEFT*.14*drive
		pieces[0].position = hero.model.position + hero.hit_direction*.10*sin(PI*hero.hit_phase)
		pieces[0].position.y += .045*abs(sin(hero.cycle*TAU)) if hero.walking else 0.
		# Rock about the contact point, preserving the painted figure and base as one object.
		for i in IDS.size():
			var roll = [hero.guard*.045-.11*sin(PI*hero.hit_phase),-.05*archer.draw,.12*drive][i]
			endpoints[i].billboard = BaseMaterial3D.BILLBOARD_DISABLED
			endpoints[i].global_basis = cameras[1].global_basis*Basis(Vector3.BACK,roll)
			# Float the printed front half of the ellipse clear of terrain depth.
			endpoints[i].position.y = .028
		if compare_pixels:
			for i in IDS.size():
				pieces[i+3].transform = pieces[i].transform
				endpoints[i+3].transform = endpoints[i].transform
		await RenderingServer.frame_post_draw
		notes.store_line(str(frame,"\t",stage))
		for i in 2:
			var side = ["left","right"][i]
			panels[i].get_texture().get_image().save_jpg(output.path_join(side).path_join("%04d.jpg"%frame),.96)
		frame+=1
	if not finished:
		push_error("Trial sequence timed out")
		quit(1)
	else:
		print("Recorded ",frame," pairs in ",output)
		GoEngine.shutdown()
		root.get_node("Soundscape").quit_game()
