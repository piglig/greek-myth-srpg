extends SceneTree
## Bake the actors' actual gameplay poses into eight orthographic views.
const STEP=1./60.
const SCRIPTS={
	"atalanta":"res://view/atalanta.gd","heracles":"res://view/heracles.gd",
	"wolf":"res://view/quadruped.gd","boar":"res://view/quadruped.gd"}
var kind: String
var actors=[]
var pins=[]
var targets=[]
var rocks=[]
var viewport: SubViewport
var beast: bool

func _initialize(): call_deferred("run")

func run():
	var args=OS.get_cmdline_user_args()
	kind=args[0]
	beast=kind in ["wolf","boar"]
	DirAccess.make_dir_recursive_absolute(args[1])
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.size=Vector2i(2560,320)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var cam=Camera3D.new()
	viewport.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	cam.size=4.8
	var center=Vector3.UP*1.18
	cam.position=center+Vector3(0,.7813,1)*20.
	cam.look_at(center)
	var env=Environment.new()
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color.WHITE
	env.ambient_light_energy=1.
	cam.environment=env
	var clips={"idle":32,"walk":32,"turn_left":8,"turn_right":8,"hit":24}
	if beast: clips["strike"]=36
	else:
		clips.merge({"heavy":48,"aim":20,"draw":24,"loose":24})
	if kind=="heracles": clips.merge({"club":44,"hold":36,"push":32,"release":60})
	for clip in clips:
		for i in 8: make_actor(i)
		for f in clips[clip]:
			for i in 8: pose(i,clip,f,clips[clip])
			await process_frame
			await RenderingServer.frame_post_draw
			assert(viewport.get_texture().get_image().save_png(args[1]+"/%s-%02d.png"%[clip,f])==OK)
		for pin in pins: pin.free()
		pins.clear()
		actors.clear()
		rocks.clear()
		targets.clear()
		print(kind," ",clip)
	quit()

func make_actor(i):
	var pin=Node3D.new()
	viewport.add_child(pin)
	pin.position.x=(i-3.5)*4.8
	pin.rotation.y=i*TAU/8.-deg_to_rad(15.)
	var actor=load(SCRIPTS[kind]).new()
	pin.add_child(actor)
	var u=UnitState.new()
	u.id=kind
	u.def_id=kind
	actor.setup(u,null,null)
	actor.set_process(false)
	var model=actor.figure if beast else actor.model
	for child in actor.get_children():
		if child!=model and child is Node3D: child.hide()
	var mesh=actor.surface if beast else actor.surfaces[0]
	var mat=mesh.material_override
	var paint=mat.get_shader_parameter("pigments")
	var ink=ShaderMaterial.new()
	ink.shader=preload("res://view/bake_pigments.gdshader")
	ink.set_shader_parameter("pigments",paint)
	mesh.material_override=ink
	actor.set_facing(Vector2i.DOWN)
	model.rotation.y=0.
	var target=Node3D.new()
	pin.add_child(target)
	target.position=Vector3(0,1.4,2.5)
	var rock=Node3D.new()
	pin.add_child(rock)
	rock.position=Vector3(0,.59,1.15)
	actors.append(actor)
	targets.append(target)
	rocks.append(rock)
	pins.append(pin)
	for warm in 35: actor._process(STEP)

func pose(i,clip,f,count):
	var a=actors[i]
	if clip=="idle":
		for tick in 3: a._process(STEP)
	var t=float(f)/maxi(count-1,1)
	var turn=(1. if clip=="turn_right" else -1.)*f*TAU/64.
	if beast:
		if clip.begins_with("turn_"): a.yaw=turn
		if clip=="walk":
			a.previous-=Vector3.BACK*.034
		if clip=="hit": a.recoil=Vector3.FORWARD*sin(PI*t)*(1.-t)*2.
		if clip=="strike": a.phase=t
		a._process(STEP)
		# Root lunge and recoil offsets are applied by the gameplay driver.
		a.figure.position=Vector3.ZERO
		return
	if clip.begins_with("turn_"):
		a.bearing=turn
		a.standing_turn_speed=400.
	if clip=="walk":
		a.walking=true
		a.gait=1.
		a.last_position=a.position-Vector3.BACK*a.gait_distance/32.
	if clip in ["heavy","hit"] and f==0:
		a.receive_impact(Vector3.FORWARD,.65 if clip=="heavy" else .19,"gore" if clip=="heavy" else "bite",false)
	if clip in ["aim","draw","loose"]:
		var lift=t if clip=="aim" else 1.
		var draw=t if clip=="draw" else (1.-t if clip=="loose" else 0.)
		if kind=="atalanta":
			a.shot_point=targets[i].global_position
			a._bow_target=targets[i]
			a.aim=lift
			a.shooting=true
			a.released=clip=="loose"
		else:
			a.aim_point=targets[i].global_position
			a.equip=lift
			a.arrow_loose=clip=="loose"
			if f==0: a.release_hand=Vector3(-.1,1.4,-.1)
		a.draw=draw
	if clip=="club":
		a.blow=t
		a.club_target=targets[i].global_position
	if clip=="push" or clip=="release":
		a.rock=rocks[i]
		a.pressure=t if clip=="push" else 1.-t
		if clip=="release":
			if f==0:
				a._process(STEP)
				a.release_push()
			a.recovery_time=2.*t
	if clip=="hold":
		if f==0:
			var captive=UnitView.new()
			pins[i].add_child(captive)
			captive.position=Vector3.BACK*.94
			captive.sprite_height=1.7
			captive.set_process(false)
			captive._sprite=Sprite3D.new()
			captive.add_child(captive._sprite)
			a.captive=captive
		a.clinch=minf(1.,t*1.6)
		a.squeeze=maxf(0.,(t-.625)/.375)
	a._process(STEP)
