class_name Diorama
extends SubViewportContainer
## A piece of battlefield shown behind a menu: the same terrain, light and unit sprites the
## battles use, with no rules behind it. Lay out a grid, stand units and props on it, and
## point the camera.

var map_view := MapView.new()
var rig := CameraRig.new()
var stand := Node3D.new()
var _viewport := SubViewport.new()
var _units := 0
## Degrees the camera swings to either side of its heading, and how many seconds a swing takes.
var sway := 0.0
var sway_seconds := 40.0
var _heading := 0.0


func _init() -> void:
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.positional_shadow_atlas_size = 1024
	add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color("#1a120e")
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color(0.78,0.8,0.88)
	sky.ambient_light_energy = 0.6
	sky.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var air := WorldEnvironment.new()
	air.environment = sky
	world.add_child(air)
	var sun := DirectionalLight3D.new()
	sun.directional_shadow_max_distance = 70.0
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.72
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	world.add_child(sun)
	map_view.nemea = true
	map_view.scale = Vector3(MapView.CHAPTER_CELL_PITCH,1.0,MapView.CHAPTER_CELL_PITCH)
	world.add_child(map_view)
	world.add_child(stand)
	rig.sun = sun
	rig.painted = true
	rig.steered = false
	world.add_child(rig)


## `rows` are strings of height digits, one character per cell, north row first. Cells listed
## in `scrub` are planted like forest tiles.
func lay(rows: Array, scrub: Array = [], woodland := false) -> void:
	var heights := []
	var terrain := []
	for z in rows.size():
		for x in rows[z].length():
			heights.append(int(rows[z][x]))
			terrain.append(Defs.Terrain.FOREST if Vector2i(x,z) in scrub else Defs.Terrain.PLAIN)
	map_view.woodland = woodland
	map_view.build(BattleGrid.from_dict({"w":rows[0].length(),"d":rows.size(),"heights":heights,"terrain":terrain}))


func _ready() -> void:
	rig.post.hide()
	rig.set_quadrant(0)
	_heading = rig._target_yaw


## Ground point at the centre of a cell (or any fractional cell position).
func spot(cell: Vector2) -> Vector3:
	return map_view.to_global(Vector3(cell.x,map_view.field.elevation(cell.x,cell.y),cell.y))


## `look` draws them from another folder of sheets than their kind's own.
func unit(def_id: String, cell: Vector2, facing: Vector2i, enemy := false, look := "") -> PixelUnit:
	var state := UnitState.new()
	_units += 1
	state.id = "%s_%d" % [def_id,_units]
	state.def_id = def_id
	if look != "": UnitState.looks[state.id] = look
	state.team = Defs.Team.ENEMY if enemy else Defs.Team.PLAYER
	state.facing = facing
	state.size = 2 if def_id in ["lion","boar"] else 1
	var view := PixelUnit.new()
	stand.add_child(view)
	view.setup(state,null,null)
	view.position = spot(cell)
	view.set_facing(facing)
	# Menus show people, not selectable pieces: no team ring under their feet.
	view._disc.hide()
	return view


func prop(scene: PackedScene, width: float, cell: Vector2, turn := 0.0) -> Node3D:
	var model := NemeaField.landmark(scene,width)
	model.position = spot(cell)
	model.rotation.y = turn
	stand.add_child(model)
	return model


## A model from a third-party kit, in its own materials. `tall` is how high it should stand
## in the world (a person is about 1.8); it is set down on the ground at `cell`.
## `canvas` repaints it as linen and wood (see camp_canvas.gdshader).
## `stone` carves it from the valley's limestone, for models that come without paint.
func kit(path: String, cell: Vector2, tall: float, turn := 0.0, canvas := false, stone := false) -> Node3D:
	var model := (load(path) as PackedScene).instantiate() as Node3D
	stand.add_child(model)
	var box := AABB()
	var any := false
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for surface in part.mesh.get_surface_count() if canvas else 0:
			var given := part.mesh.surface_get_material(surface) as BaseMaterial3D
			var paint := ShaderMaterial.new()
			paint.shader = preload("res://view/camp_canvas.gdshader")
			if given != null: paint.set_shader_parameter("albedo_map",given.albedo_texture)
			part.set_surface_override_material(surface,paint)
		if stone:
			part.material_override = NemeaField.finish()
			part.set_instance_shader_parameter("limestone",1.0)
		var reach: AABB = (model.global_transform.affine_inverse()*part.global_transform)*part.get_aabb()
		box = reach if not any else box.merge(reach)
		any = true
	var size := tall/maxf(box.size.y,.001)
	model.scale = Vector3.ONE*size
	model.rotation.y = turn
	model.position = spot(cell)-Vector3.UP*box.position.y*size
	return model


## A campfire: a ring of stones and a looping flame.
func fire(cell: Vector2) -> void:
	var pit := Node3D.new()
	pit.position = spot(cell)
	stand.add_child(pit)
	for i in 9:
		var rock := NemeaField.landmark(preload("res://art/landmarks/boulder.glb"),.33)
		rock.scale.y *= .68
		rock.position = Vector3(cos(TAU*i/9)*.42,0,sin(TAU*i/9)*.42)
		pit.add_child(rock)
	var flame := MeshInstance3D.new()
	var card := QuadMesh.new()
	card.size = Vector2(2.4,2.4)
	flame.mesh = card
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://view/pixel_flame.gdshader")
	paint.set_shader_parameter("atlas",preload("res://art/thirdparty/pixelfx/flame.png"))
	flame.material_override = paint
	flame.position.y = 2.4*.375
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pit.add_child(flame)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#ffb060")
	glow.light_energy = 1.6
	glow.omni_range = 5.0
	glow.position.y = .8
	pit.add_child(glow)


## Look at a cell from one of the four quarters, at a zoom step (0 far, 2 near).
func look(cell: Vector2, quarter := 0, zoom := 1) -> void:
	if not rig.is_inside_tree(): return
	rig.zoom_index = zoom
	rig.set_quadrant(quarter)
	_heading = rig._target_yaw
	rig.focus(spot(cell)+Vector3.UP*.8)


func _process(_delta: float) -> void:
	if sway > 0.0:
		var angle := _heading+sway*sin(Time.get_ticks_msec()*.001*TAU/sway_seconds)
		rig._target_yaw = angle
		rig._yaw = angle
