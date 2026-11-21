extends SceneTree
## Run with the prototype project and pass -- followed by an output folder.
const STEP := 1.0/60.0
const TILE := 320
const SIZE := 4.8
const CENTER := Vector3(0,1.18,0)
const CLIPS := {"idle":1,"walk":32,"turn_left":8,"turn_right":8,"guard":63,"guard_lower":20,
	"spear":36,"bash":38,"light":25,"heavy":50,"block":25}
var driver: ValleyHero
var viewport: SubViewport
var figures: Array[Node3D]=[]
var rigs: Array[Skeleton3D]=[]

func _initialize(): call_deferred("bake")

func bake():
	var output=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var sources=ProjectSettings.globalize_path("res://../art/originals/hoplite-bake/")
	var doc=GLTFDocument.new()
	var data=GLTFState.new()
	assert(doc.append_from_file(sources+"paint.glb",data)==OK)
	var template=doc.generate_scene(data)
	var material=ShaderMaterial.new()
	var shader=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D pigments: source_color,filter_linear,repeat_disable;
uniform float elapsed;
void vertex(){
 float hem=UV2.x;
 float corner=UV2.y;
 float t=max(0.,elapsed-.042-.105*hem-.050*corner);
 float drive=sin(10.8*t)*exp(-4.05*t)*smoothstep(0.,.09,t)*(1.-smoothstep(.78,.96,elapsed));
 float fold=sin(14.5*t-2.1*corner)*exp(-5.*t)*smoothstep(0.,.15,t)*(1.-smoothstep(.74,.94,elapsed));
 VERTEX.xyz+=hem*vec3((.39+.102*corner)*drive,.24*abs(drive)+.042*fold,-.40*drive+.055*fold);
}
void fragment(){
vec3 paint=mix(COLOR.rgb,texture(pigments,UV).rgb,COLOR.a);
vec3 n=normalize(mat3(INV_VIEW_MATRIX)*NORMAL);
ALBEDO=paint*(.89+.15*max(dot(n,normalize(vec3(-.4,.8,.45))),0.));
}"""
	material.shader=shader
	material.set_shader_parameter("pigments", ImageTexture.create_from_image(Image.load_from_file(sources+"paint.png")))
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.size=Vector2i(TILE*8,TILE)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var cam=Camera3D.new()
	viewport.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	cam.size=SIZE
	cam.position=CENTER+Vector3(0,.7813,1)*20.
	cam.look_at(CENTER)
	for d in 8:
		var figure=template.duplicate()
		viewport.add_child(figure)
		figure.scale=Vector3.ONE*1.10
		figure.position.x=(d-3.5)*SIZE
		figure.find_children("*","MeshInstance3D",true,false)[0].material_override=material
		figures.append(figure)
		rigs.append(figure.find_children("*","Skeleton3D",true,false)[0])
	template.free()
	for clip in CLIPS:
		driver=ValleyHero.new()
		root.add_child(driver)
		var u=UnitState.new()
		u.id="hero"
		u.def_id="hero"
		driver.setup(u,null,null)
		driver.set_process(false)
		driver.bearing=0
		driver.model.rotation.y=0
		for t in 75: driver._process(STEP)
		driver.walking=clip=="walk"
		driver.guarding=clip in ["guard","guard_lower"]
		if clip in ["light","heavy","block"]:
			driver.receive_impact(Vector3.FORWARD, .6 if clip=="heavy" else .18,
				"gore" if clip=="heavy" else "bite",clip=="block")
		if driver.walking:
			driver.gait=1.
			driver.cycle=0
		for t in CLIPS[clip]:
			var elapsed=t*STEP
			if clip=="walk": driver.position.z+=driver.gait_distance/32.
			if clip.begins_with("turn_"):
				driver.bearing=(1. if clip=="turn_right" else -1.)*t*TAU/64.
				driver.standing_turn_speed=400.
			if clip=="spear":
				if t in [0,5,11,18]: driver.attack_key([0,5,11,18].find(t))
				if t==26: driver.set_pose(-1,.12)
			if clip=="bash":
				driver.bash_phase=.54*(1-cos(clampf(elapsed/.32,0,1)*PI))*.5 if elapsed<.32 else .54+.46*clampf((elapsed-.32)/.30,0,1)
			if clip!="guard" or t<20: driver._process(STEP)
			material.set_shader_parameter("elapsed",elapsed if clip=="guard" else 0.)
			for d in 8:
				figures[d].rotation.y=driver.model.rotation.y+d*TAU/8.-deg_to_rad(15.)
				for j in rigs[d].get_bone_count():
					var bone=driver.joints[rigs[d].get_bone_name(j)]
					rigs[d].set_bone_pose(j,driver.skeleton.get_bone_pose(bone))
			await process_frame
			await RenderingServer.frame_post_draw
			assert(viewport.get_texture().get_image().save_png(output+"/%s-%02d.png"%[clip,t])==OK)
		driver.free()
		print("Baked ",clip)
	quit()
