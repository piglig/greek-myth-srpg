extends NemeaField
## Soft banks and reed beds follow the same grid used for picking and unit anchors.

var pale_lake := false

func _blend(a: float, b: float, t: float) -> float:
	return lerpf(a,b,smoothstep(.19,.81,t))


## The marsh is a channel between two banks. These are the first and last columns that
## hold any water or bog; beyond the map's near and far edges the channel opens into water.
var channel := Vector2.ZERO

const ALTAR := preload("res://art/camp/altar.glb")
const BRAZIER := preload("res://art/camp/brazier.glb")


func build(battle_grid: BattleGrid, layer_height: float, _village := false, _woodland := false) -> void:
	grid = battle_grid
	map_layer_height = layer_height
	channel = Vector2(grid.width,0)
	for z in grid.depth:
		for x in grid.width:
			if _wetness(Vector2i(x,z)) > 0.:
				channel.x = minf(channel.x,x)
				channel.y = maxf(channel.y,x+1)
	var surface := _build_surface()
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://view/lerna_ground.gdshader")
	if pale_lake:
		paint.set_shader_parameter("silt",preload("res://art/original/stymphalus-silt.webp"))
		paint.set_shader_parameter("shallows",Vector3(.246,.276,.291))
		paint.set_shader_parameter("depths",Vector3(.145,.178,.204))
	else:
		paint.set_shader_parameter("silt",preload("res://art/original/lerna-mud.webp"))
	# Red is how wet a cell is; green marks bog, which is drawn as its own ground so that
	# it can be told from the dry silt beside it.
	var wet := Image.create(grid.width,grid.depth,false,Image.FORMAT_RG8)
	for z in grid.depth:
		for x in grid.width:
			var water := _wetness(Vector2i(x,z))
			wet.set_pixel(x,z,Color(water,1. if grid.terrain_at(Vector2i(x,z)) == Defs.Terrain.SWAMP else 0.,0))
	paint.set_shader_parameter("wet_cells",ImageTexture.create_from_image(wet))
	paint.set_shader_parameter("field_size",Vector2(grid.width,grid.depth))
	paint.set_shader_parameter("channel",channel)
	paint.set_shader_parameter("grid_lines",grid_lines)
	surface.material_override = paint
	add_child(surface)
	_reed_beds()
	_dress_banks()
	_shrine()
	_drowned_columns()


func _wetness(cell: Vector2i) -> float:
	match grid.terrain_at(cell):
		Defs.Terrain.SHALLOW: return .79
		Defs.Terrain.DEEP: return 1.
		Defs.Terrain.SWAMP: return .24
	return 0.


## How far a point lies beyond the map's near or far edge, inside the channel: there the
## marsh opens into standing water. The shader draws the same shape.
func _open_water(x: float, z: float) -> float:
	if channel.y <= channel.x:
		return 0.
	var beyond := maxf(-z,z-grid.depth)
	var inside := minf(x-channel.x,channel.y-x)+.35*beyond
	return smoothstep(1.2,3.6,beyond+.5*sin(x*.9))*smoothstep(-.6,.6,inside)


## How wet the ground is at a point, on the map or off it.
func _soak(x: float, z: float) -> float:
	var cell := Vector2i(floori(x),floori(z)).clamp(Vector2i.ZERO,Vector2i(grid.width-1,grid.depth-1))
	return maxf(_wetness(cell),_open_water(x,z))


## Water lies flat: beyond the map the channel settles to the level of the marsh.
func elevation(x: float, z: float) -> float:
	var land := super(x,z)
	if channel.y > channel.x and x > grid.width:
		# The shrine stands on level ground, at the height of the bank it faces.
		var ground := _shrine_ground()
		var point := Vector2(x,z)
		var off := point.distance_to(point.clamp(ground.position,ground.end))
		land = lerpf(_level(grid.width-1,grid.depth/2),land,smoothstep(.2,2.2,off))
	var open := _open_water(x,z)
	if open <= 0.:
		return land
	return lerpf(land,-.03,open)


func _reed_beds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2182
	var mesh_tool := SurfaceTool.new()
	mesh_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 0
	for z in range(-9,grid.depth+9):
		for x in range(-6,grid.width+6):
			var cell := Vector2i(x,z)
			var on_map := grid.in_bounds(cell)
			var soak := _soak(x+.5,z+.5)
			var beds := sin(x*.78+z*.43)+.7*sin(z*1.17-x*.31)
			if soak < .15:
				continue
			# On the map the beds stay thin and low, so a cell can still be read; round the
			# map they close in tall, and thin out again over open water.
			var chance := .72 if on_map else (.95 if soak < .95 else .42)
			if (on_map and beds < -.25) or rng.randf() > chance:
				continue
			for clump in (1 if on_map else rng.randi_range(1,3)):
				var edge := Vector2(x+rng.randf_range(.11,.29),z+rng.randf_range(.10,.28)) if on_map else Vector2(x+rng.randf(),z+rng.randf())
				var height := rng.randf_range(.24,.48) if on_map else rng.randf_range(.62,1.35)
				for blade in rng.randi_range(12,25):
					var radius := rng.randf_range(.0,.19 if on_map else .27)
					var dir := Vector2.from_angle(rng.randf()*TAU)
					var at := edge+radius*dir
					var foot := Vector3(at.x,elevation(at.x,at.y)-.025,at.y)
					var tip := foot+Vector3(dir.x*.15,height*rng.randf_range(.62,1.20),dir.y*.15)
					var width := Vector3(-dir.y,0,dir.x)*rng.randf_range(.012,.024)
					var middle := foot.lerp(tip,.62)+Vector3.UP*.045
					var ink := Color("#485a43").lerp(Color("#beaa77"),rng.randf()).srgb_to_linear()
					mesh_tool.set_color(ink)
					for point: Vector3 in [foot-width*.35,middle-width,middle+width,foot-width*.35,middle+width,foot+width*.35,middle-width,tip,middle+width]:
						mesh_tool.set_uv(Vector2(0,clampf((point.y-foot.y)/(tip.y-foot.y),0,1)))
						mesh_tool.add_vertex(point)
					blades += 1
	# Lily pads lie on the still water: flat, so they hide nothing that stands there.
	var pads := RandomNumberGenerator.new()
	pads.seed = 5521
	for z in range(-8,grid.depth+8):
		for x in range(-2,grid.width+2):
			if _soak(x+.5,z+.5) < .7 or pads.randf() > .5:
				continue
			var heart := Vector2(x+pads.randf_range(.2,.8),z+pads.randf_range(.2,.8))
			for pad in pads.randi_range(3,7):
				var at := heart+Vector2.from_angle(pads.randf()*TAU)*pads.randf_range(0.,.34)
				if _soak(at.x,at.y) < .7:
					continue
				var reach := pads.randf_range(.055,.115)
				var turn := pads.randf()*TAU
				var middle := Vector3(at.x,elevation(at.x,at.y)+.014,at.y)
				mesh_tool.set_color(Color("#4f6b3a").lerp(Color("#8ea05a"),pads.randf()).srgb_to_linear())
				mesh_tool.set_uv(Vector2.ZERO)
				# A round leaf with one notch cut to the middle.
				for i in 7:
					var a := turn+TAU*(i+.5)/8.
					var b := turn+TAU*(i+1.5)/8.
					mesh_tool.add_vertex(middle)
					mesh_tool.add_vertex(middle+Vector3(cos(b),0,sin(b))*reach)
					mesh_tool.add_vertex(middle+Vector3(cos(a),0,sin(a))*reach)
				blades += 1
	if blades > 0:
		mesh_tool.generate_normals()
		var reeds := MeshInstance3D.new()
		reeds.mesh = mesh_tool.commit()
		var paint := ShaderMaterial.new()
		paint.shader = preload("res://view/lerna_reed.gdshader")
		reeds.material_override = paint
		reeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(reeds)


## Trees, scrub and stones on the dry ground round the map, and a little litter on the
## dry cells of the map itself, kept to the corners and below the ankle.
func _dress_banks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 733
	for z in range(-8,grid.depth+8):
		for x in range(-9,grid.width+9):
			var cell := Vector2i(x,z)
			if _soak(x+.5,z+.5) > 0.:
				continue
			if grid.in_bounds(cell):
				if rng.randf() < .2:
					var corner := Vector2(x+(.15 if rng.randf() < .5 else .85),z+rng.randf_range(.1,.24))
					var small := ROCK if rng.randf() < .45 else THYME
					_plant(small,rng.randf_range(.16,.3) if small == ROCK else rng.randf_range(.34,.52),Vector3(corner.x,elevation(corner.x,corner.y),corner.y),rng,false)
				continue
			var away := maxi(maxi(-x,x-grid.width+1),maxi(-z,z-grid.depth+1))
			if _shrine_ground().grow(1.3).has_point(Vector2(x+.5,z+.5)) or rng.randf() >= (.34 if away < 3 else .26):
				continue
			var scene: PackedScene = THYME if rng.randf() < .55 else ROCK
			if away >= 2 and rng.randf() < .5:
				scene = OLIVE
			var width := rng.randf_range(1.7,3.0) if scene == OLIVE else rng.randf_range(.7,1.5)
			var at := Vector2(x+rng.randf_range(.25,.75),z+rng.randf_range(.25,.75))
			_plant(scene,width,Vector3(at.x,elevation(at.x,at.y),at.y),rng)
	if not plant_shadows.is_empty():
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = _shadow_mesh()
		batch.instance_count = plant_shadows.size()
		for i in plant_shadows.size():
			batch.set_instance_transform(i,plant_shadows[i])
		var shadows := MultiMeshInstance3D.new()
		shadows.multimesh = batch
		shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shadows)
		plant_shadows.clear()


## Where the shrine stands: on the far bank, just off the map, level with its middle.
func _shrine_ground() -> Rect2:
	return Rect2(grid.width+.4,grid.depth*.5-2.6,4.4,5.2)


## One drum of a column, or a run of them, in the pale stone of the landmarks. `drums`
## high, `lean` radians off true, sunk `sunk` of its height into the ground.
func _column(at: Vector2, drums: int, lean := 0., turn := 0., sunk := 0., girth := .2) -> Node3D:
	var column := Node3D.new()
	var drum_height := .3
	for i in drums:
		var drum := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.radial_segments = 12
		shape.rings = 0
		shape.top_radius = girth*(1.-.035*(i+1))
		shape.bottom_radius = girth*(1.-.035*i)
		shape.height = drum_height
		drum.mesh = shape
		drum.material_override = finish()
		drum.set_instance_shader_parameter("limestone",1.0)
		drum.position.y = drum_height*(i+.5)
		drum.rotation.y = i*.37
		column.add_child(drum)
	var grid_scale := global_basis.get_scale()
	column.scale = Vector3.ONE/grid_scale
	column.rotation = Vector3(0,turn,lean)
	column.position = Vector3(at.x,elevation(at.x,at.y)-sunk*drums*drum_height,at.y)
	add_child(column)
	return column


## A small ruined shrine on the far bank: what the crossing is for. An altar with a fire
## beside it, columns standing and fallen, on two worn steps.
func _shrine() -> void:
	if channel.y <= channel.x:
		return
	var ground := _shrine_ground()
	var heart := ground.get_center()
	var grid_scale := global_basis.get_scale()
	for piece: Array in [[ALTAR,Vector2(-.2,0.),1.25,PI*.5],[BRAZIER,Vector2(-.95,1.15),.95,0.]]:
		var model := (piece[0] as PackedScene).instantiate() as Node3D
		var at: Vector2 = heart+piece[1]
		model.scale = Vector3.ONE*float(piece[2])/grid_scale
		model.rotation.y = piece[3]
		model.position = Vector3(at.x,elevation(at.x,at.y)-.02,at.y)
		add_child(model)
	# The fire in the bowl: seen from the near bank, it says where to go.
	var bowl := heart+Vector2(-.95,1.15)
	var flame := MeshInstance3D.new()
	var card := QuadMesh.new()
	card.size = Vector2.ONE*1.5
	flame.mesh = card
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://view/pixel_flame.gdshader")
	paint.set_shader_parameter("atlas",preload("res://art/thirdparty/pixelfx/flame.png"))
	flame.material_override = paint
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.scale = Vector3.ONE/grid_scale
	flame.position = Vector3(bowl.x,elevation(bowl.x,bowl.y)+1.1/grid_scale.y,bowl.y)
	add_child(flame)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#ffb060")
	glow.light_energy = 1.3
	glow.omni_range = 4.2
	glow.position = flame.position
	add_child(glow)
	# Four columns stood at the corners once. Two still do.
	_column(heart+Vector2(-1.5,-1.7),6,0.,.2)
	_column(heart+Vector2(.9,-1.8),4,.04,1.1)
	_column(heart+Vector2(.8,1.9),5,-.03,.5)
	_column(heart+Vector2(1.7,.1),3,0.,2.1)
	_column(heart+Vector2(-1.9,2.2),3,PI*.5-.06,.7,0.,.2).position.y += .2/grid_scale.y
	for step in 2:
		var slab := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = Vector3(3.6-step*.5,.1,4.4-step*.5)
		slab.mesh = shape
		slab.material_override = finish()
		slab.set_instance_shader_parameter("limestone",1.0)
		slab.scale = Vector3.ONE/grid_scale
		slab.position = Vector3(heart.x-.1,elevation(heart.x,heart.y)+(.03+step*.09)/grid_scale.y,heart.y)
		add_child(slab)


## Columns of something older, half under: in the deep cells of the map, where nobody can
## stand, and out in the open water beyond it.
func _drowned_columns() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for z in grid.depth:
		for x in grid.width:
			if grid.terrain_at(Vector2i(x,z)) == Defs.Terrain.DEEP:
				_column(Vector2(x+rng.randf_range(.35,.65),z+rng.randf_range(.35,.65)),rng.randi_range(3,5),rng.randf_range(-.16,.16),rng.randf()*TAU,.3)
	if channel.y <= channel.x:
		return
	for i in 7:
		var far := rng.randf_range(2.8,7.)
		var at := Vector2(rng.randf_range(channel.x+.5,channel.y-.5),-far if i%2 == 0 else grid.depth+far)
		if _open_water(at.x,at.y) > .8:
			_column(at,rng.randi_range(2,6),rng.randf_range(-.22,.22),rng.randf()*TAU,.25,rng.randf_range(.18,.24))
