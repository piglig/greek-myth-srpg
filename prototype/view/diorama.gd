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
	else: UnitState.looks.erase(state.id)
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


## Camp meshes are authored in metres with the origin at the centre of the footprint.
## Follow the local ground plane so stretcher legs and tent pegs meet the slope.
func camp_prop(asset: PackedScene, cell: Vector2, turn := 0., size := 1., sample_radius := .4) -> Node3D:
	var prop_node := asset.instantiate() as Node3D
	stand.add_child(prop_node)
	var east := spot(cell+Vector2.RIGHT*sample_radius)-spot(cell-Vector2.RIGHT*sample_radius)
	var south := spot(cell+Vector2.DOWN*sample_radius)-spot(cell-Vector2.DOWN*sample_radius)
	var up := south.cross(east).normalized()
	prop_node.basis = Basis(Quaternion(Vector3.UP,up))*Basis(Vector3.UP,turn)
	prop_node.scale *= size
	prop_node.position = spot(cell)-Vector3.UP*.018
	# A small contact shadow keeps the legs, pegs and pointed vessels anchored in soft light.
	var meshes := prop_node.find_children("*","MeshInstance3D",true,false)
	if not meshes.is_empty():
		var bounds: AABB = (meshes[0] as MeshInstance3D).get_aabb()
		var shadow := MeshInstance3D.new()
		shadow.mesh = NemeaField._shadow_mesh()
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stand.add_child(shadow)
		shadow.transform = prop_node.transform
		shadow.scale *= Vector3(maxf(.35,bounds.size.x*1.20),1.,maxf(.32,bounds.size.z*1.20))
		shadow.position += up*.045
	return prop_node


## A campfire: a ring of stones and a looping flame.
func fire(cell: Vector2, bowl_height := 0.) -> void:
	var pit := Node3D.new()
	pit.position = spot(cell)
	stand.add_child(pit)
	for i in (9 if bowl_height==0. else 0):
		var rock := NemeaField.landmark(preload("res://art/landmarks/boulder.glb"),.33)
		rock.scale.y *= .68
		rock.position = Vector3(cos(TAU*i/9)*.42,0,sin(TAU*i/9)*.42)
		pit.add_child(rock)
	var flame := MeshInstance3D.new()
	var card := QuadMesh.new()
	var span := 2.4 if bowl_height==0. else 1.65
	card.size = Vector2.ONE*span
	flame.mesh = card
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://view/pixel_flame.gdshader")
	paint.set_shader_parameter("atlas",preload("res://art/thirdparty/pixelfx/flame.png"))
	flame.material_override = paint
	flame.position.y = bowl_height+span*.375
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pit.add_child(flame)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#ffb060")
	glow.light_energy = 1.6
	glow.omni_range = 5.0
	glow.position.y = bowl_height+.8
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
