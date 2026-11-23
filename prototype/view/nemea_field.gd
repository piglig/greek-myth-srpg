class_name NemeaField
extends Node3D
## Render the rule cells and continue their geology beyond the playable area.
const OLIVE := preload("res://art/landmarks/olive.glb")
const CYPRESS := preload("res://art/landmarks/cypress.glb")
const THYME := preload("res://art/landmarks/scrub.glb")
const ROCK := preload("res://art/landmarks/boulder.glb")
const CAVE := preload("res://art/landmarks/cave.glb")


static var landmark_finish: ShaderMaterial
static var shadow_plane: PlaneMesh


# Stand-ins from the Quaternius Stylized Nature MegaKit (CC0): [scene, footprint in model units].
const KIT := "res://art/thirdparty/nature/"
static var kit_flora := OS.get_environment("SRPG_FLORA") != "0"
static var flora_cast := {}
static var flora_paint := {}
static var flora_turn := 0


static func _flora_material(source: Material, part: int, shade: Color, light: Color) -> ShaderMaterial:
	var key := "%s/%d/%s" % [source.resource_name,part,light.to_html()]
	if not flora_paint.has(key):
		var paint := ShaderMaterial.new()
		paint.shader = preload("res://view/flora.gdshader")
		paint.set_shader_parameter("albedo_map",(source as BaseMaterial3D).albedo_texture)
		paint.set_shader_parameter("part",part)
		paint.set_shader_parameter("shade_pigment",shade)
		paint.set_shader_parameter("light_pigment",light)
		flora_paint[key] = paint
	return flora_paint[key]


## A kit plant scaled so that its crown spans what the generated one did at this width.
static func flora(kind: PackedScene, width: float) -> Node3D:
	if flora_cast.is_empty():
		flora_cast[OLIVE] = [["TwistedTree_1",1.0],["TwistedTree_2",1.0],["TwistedTree_3",1.0]]
		flora_cast[CYPRESS] = [["Pine_1",.62],["Pine_3",.56]]
		flora_cast[THYME] = [["Bush_Common",.62],["Grass_Wispy_Short",.5],["Bush_Common",.55]]
	var choices: Array = flora_cast[kind]
	var pick: Array = choices[flora_turn%choices.size()]
	flora_turn += 1
	var model := (load(KIT+pick[0]+".gltf") as PackedScene).instantiate() as Node3D
	var parts := model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:
		parts.append(model)
	var span := 1.0
	for part: MeshInstance3D in parts:
		var box := part.mesh.get_aabb()
		span = maxf(box.size.x,box.size.z)
		part.extra_cull_margin = 1.5
		part.set_instance_shader_parameter("crown_centre",box.position+box.size*Vector3(.5,.66,.5))
		part.set_instance_shader_parameter("crown_reach",box.size*Vector3(.5,.36,.5))
		part.set_instance_shader_parameter("tallness",box.end.y)
		for surface in part.mesh.get_surface_count():
			var source := part.mesh.surface_get_material(surface)
			var label := source.resource_name
			var paint: ShaderMaterial
			if label.begins_with("Bark"):
				paint = _flora_material(source,0,Color.BLACK,Color.WHITE)
			elif label.begins_with("Grass"):
				paint = _flora_material(source,2,Color("4a4c2c"),Color("a39a5c"))
			elif kind == CYPRESS:
				paint = _flora_material(source,1,Color("2b3b27"),Color("6f8256"))
			elif kind == THYME:
				paint = _flora_material(source,1,Color("3c4428"),Color("8a8a55"))
			else:
				paint = _flora_material(source,1,Color("3f4f33"),Color("a8b27e"))
			part.set_surface_override_material(surface,paint)
	model.scale = Vector3.ONE*width*float(pick[1])/span
	return model


static func landmark(scene: PackedScene, width: float) -> Node3D:
	if kit_flora and scene in [OLIVE,CYPRESS,THYME]:
		return flora(scene,width)
	var model := scene.instantiate() as Node3D
	if landmark_finish == null:
		landmark_finish = ShaderMaterial.new()
		landmark_finish.shader = preload("res://view/landmark.gdshader")
		landmark_finish.set_shader_parameter("grain", preload("res://art/original/earth.webp"))
		landmark_finish.set_shader_parameter("cliff", preload("res://art/original/cliff.webp"))
		landmark_finish.set_shader_parameter("leaf_strokes", preload("res://art/original/leaf_strokes.png"))
	var parts := model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:
		parts.append(model)
	for part: MeshInstance3D in parts:
		part.material_override = landmark_finish
		if scene in [ROCK,CAVE]:
			part.set_instance_shader_parameter("limestone",1.0)
		if scene in [OLIVE,CYPRESS,THYME]:
			part.set_instance_shader_parameter("flexibility",3.2 if scene == THYME else 1.0)
			part.extra_cull_margin = 1.3 if scene == OLIVE else 0.4
	model.scale = Vector3.ONE * width
	return model


static func _shadow_mesh() -> PlaneMesh:
	if shadow_plane == null:
		shadow_plane = PlaneMesh.new()
		shadow_plane.size = Vector2.ONE
		var material := ShaderMaterial.new()
		material.shader = preload("res://view/ground_shadow.gdshader")
		shadow_plane.material = material
	return shadow_plane


static func shadow(width: float, depth: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _shadow_mesh()
	node.scale = Vector3(width,1,depth)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position.y = 0.012
	return node


const BORDER := 14
const DETAIL := 12
const CLIFF_HALF_WIDTH := 0.085
var plant_shadows: Array[Transform3D] = []
var grid: BattleGrid
var map_layer_height: float
var picking_surface: TriangleMesh
var patches := {}
var patch_uvs := PackedVector2Array()
var patch_indices := PackedInt32Array()
var vertices := PackedVector3Array()
var stride := 0
var origin_index := 0


func _level(x: int, z: int) -> float:
	return grid.height_at(Vector2i(clampi(x,0,grid.width-1),clampi(z,0,grid.depth-1))) * map_layer_height


func _blend(a: float, b: float, t: float) -> float:
	if a == b:
		return a
	# Keep each tile flat and put the whole rise in a narrow band on the shared edge,
	# so a height step reads as a rock face. Taller faces get a slightly wider foot.
	var step_count := absf(a-b)/map_layer_height
	var half_face := minf(CLIFF_HALF_WIDTH+0.015*(step_count-1.0),0.16)
	return lerpf(a,b,smoothstep(0.5-half_face,0.5+half_face,t))


class HouseSite:
	const SILL_HEIGHT := .018
	var pose: Transform3D
	var width: float
	var porch: bool
	var center: Vector2
	var yaw: float

	func _init(at: Vector2, size: float, angle: float, has_porch: bool, height: float):
		center = at
		width = size
		yaw = angle
		porch = has_porch
		pose = Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*size),Vector3(at.x,height+SILL_HEIGHT,at.y))

	func distance_to_pad(point: Vector2) -> float:
		var local := (point-center).rotated(yaw)
		var rear := -.35*width
		var front := (.57 if porch else .36)*width
		var offset := Vector2(absf(local.x)-.52*width,maxf(rear-local.y,local.y-front))
		return offset.max(Vector2.ZERO).length()


var house_sites: Array[HouseSite] = []


func _add_site(point: Vector2, width: float, yaw: float, porch: bool) -> void:
	house_sites.append(HouseSite.new(point,width,yaw,porch,_natural_elevation(point.x,point.y)))


func elevation(x: float, z: float) -> float:
	var land := _natural_elevation(x,z)
	var point := Vector2(x,z)
	var outside := point.distance_to(point.clamp(Vector2.ZERO,Vector2(grid.width,grid.depth)))
	if outside == 0 or house_sites.is_empty():
		return land
	var strongest := 0.0
	var target := land
	for site in house_sites:
		if point.distance_squared_to(site.center) > 16.0:
			continue
		var distance := site.distance_to_pad(point)
		var apron := 1.15+.14*sin(x*2.2+z*1.4)
		var weight := 1.0-smoothstep(.20,apron,distance)
		if weight > strongest:
			strongest = weight
			target = site.pose.origin.y-HouseSite.SILL_HEIGHT
	return lerpf(land,target,strongest*smoothstep(0.0,.28,outside))


func _natural_elevation(x: float, z: float) -> float:
	# Shift the transition sideways between anchors, tapering the shift to zero at cell centres.
	var px := x-0.5
	var pz := z-0.5
	var ix := floori(px)
	var iz := floori(pz)
	var h00 := _level(ix,iz)
	var h10 := _level(ix+1,iz)
	var h01 := _level(ix,iz+1)
	var h11 := _level(ix+1,iz+1)
	var height := h00
	if h00 != h10 or h00 != h01 or h00 != h11:
		var tx := px-ix
		var tz := pz-iz
		tx += sin(PI*tx)*(0.055*sin(z*2.1)+0.03*sin(z*4.5+x))
		tz += sin(PI*tz)*(0.055*sin(x*1.6)+0.03*cos(x*3.7-z))
		height = _blend(_blend(h00,h10,tx),_blend(h01,h11,tx),tz)
	var outside := Vector2(x-clampf(x,0.0,grid.width),z-clampf(z,0.0,grid.depth)).length()
	if outside == 0:
		return height
	return height + smoothstep(0.0,3.0,outside)*(-0.5+0.45*sin(x*.55)+0.42*cos(z*.64))


func _axis(length: int) -> PackedFloat32Array:
	var coords := PackedFloat32Array()
	for i in range(-BORDER,length+BORDER):
		var count := DETAIL if i >= -4 and i < length+4 else 1
		for j in count:
			coords.append(i+float(j)/count)
	coords.append(length+BORDER)
	return coords


func build(battle_grid: BattleGrid, layer_height: float, village: bool = false, woodland: bool = false) -> void:
	grid = battle_grid
	map_layer_height = layer_height
	if village:
		_add_site(Vector2(-2.15,6.65),3.1,3.10,false)
		_add_site(Vector2(3.8,grid.depth+1.95),2.2,5.20,false)
		_add_site(Vector2(-2.20,3.36),2.9,.12,true)
		_add_site(Vector2(grid.width+2.45,5.8),3.2,1.76,true)
		_add_site(Vector2(1.6,-2.10),2.6,-.39,false)
	var xs := _axis(grid.width)
	var zs := _axis(grid.depth)
	origin_index = xs.find(0.0)
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in zs:
		for x in xs:
			vertices.append(Vector3(x,elevation(x,z),z))
	stride = xs.size()
	for j in zs.size():
		for i in stride:
			var n := j*stride+i
			var dx := vertices[j*stride+mini(stride-1,i+1)]-vertices[j*stride+maxi(0,i-1)]
			var dz := vertices[mini(zs.size()-1,j+1)*stride+i]-vertices[maxi(0,j-1)*stride+i]
			normals.append(dz.cross(dx).normalized())
			if j+1 < zs.size() and i+1 < stride:
				indices.append_array(PackedInt32Array([n,n+1,n+stride+1,n,n+stride+1,n+stride]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	picking_surface = mesh.generate_triangle_mesh()
	var world_mesh := MeshInstance3D.new()
	world_mesh.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://view/nemea_ground.gdshader")
	mat.set_shader_parameter("village_lane",village)
	mat.set_shader_parameter("woodland",woodland)
	mat.set_shader_parameter("field_size",Vector2(grid.width,grid.depth))
	var levels := Image.create(grid.width,grid.depth,false,Image.FORMAT_RF)
	for z in grid.depth:
		for x in grid.width:
			levels.set_pixel(x,z,Color(_level(x,z),0,0))
	mat.set_shader_parameter("levels",ImageTexture.create_from_image(levels))
	mat.set_shader_parameter("cliff",preload("res://art/original/cliff.webp"))
	mat.set_shader_parameter("stone",preload("res://art/original/earth.webp"))
	world_mesh.material_override = mat
	add_child(world_mesh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 195
	for z in range(-BORDER,grid.depth+BORDER):
		for x in range(-BORDER,grid.width+BORDER):
			var cell := Vector2i(x,z)
			if not grid.in_bounds(cell):
				if rng.randf() >= 0.22:
					continue
				var scene := [OLIVE,CYPRESS,ROCK,THYME][rng.randi_range(0,3)] as PackedScene
				if maxi(maxi(-x,x-grid.width+1),maxi(-z,z-grid.depth+1)) < 3:
					scene = THYME if rng.randf() < 0.6 else ROCK
				var width := rng.randf_range(1.5,2.9) if scene == OLIVE else rng.randf_range(0.8,1.8)
				var near_house := false
				for site in house_sites:
					if site.distance_to_pad(Vector2(x+.5,z+.5)) < width*.46:
						near_house = true
						break
				if near_house:
					continue
				_plant(scene,width,Vector3(x+.5,elevation(x+.5,z+.5),z+.5),rng)
			elif woodland and grid.terrain_at(cell) == Defs.Terrain.FOREST and (2*x+z)%4 == 0:
				var point := Vector3(x+.22,elevation(x+.22,z+.23),z+.23)
				_plant(OLIVE if (x+z)%3 else CYPRESS,rng.randf_range(1.45,2.2),point,rng)
			elif grid.terrain_at(cell) == Defs.Terrain.FOREST and (x+z)%2 == 0:
				_plant(THYME,rng.randf_range(.9,1.45),Vector3(x+.36,elevation(x+.36,z+.42),z+.42),rng)

	# Loose stones gather under each rise and dry tufts break up open ground. Both stay
	# near tile edges and below ankle height, so they never hide a unit or a footprint.
	var litter := RandomNumberGenerator.new()
	litter.seed = 4107
	for z in grid.depth:
		for x in grid.width:
			var here := _level(x,z)
			for step: Vector2i in [Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0)]:
				if not grid.in_bounds(Vector2i(x,z)+step) or _level(x+step.x,z+step.y) <= here:
					continue
				for i in litter.randi_range(0,2):
					var along := litter.randf_range(-.42,.42)
					var out := litter.randf_range(.27,.36)
					var at := Vector2(x+.5,z+.5)+Vector2(step)*out+Vector2(step.y,step.x)*along
					_plant(ROCK,litter.randf_range(.13,.30),Vector3(at.x,here,at.y),litter,false)
			if litter.randf() < .11 and grid.terrain_at(Vector2i(x,z)) != Defs.Terrain.FOREST:
				var corner := Vector2(x+(.16 if litter.randf() < .5 else .84),z+litter.randf_range(.12,.26))
				_plant(THYME,litter.randf_range(.36,.58),Vector3(corner.x,here,corner.y),litter,false)

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


# Identical triangles to the land beneath; UVs are local to the tactical cell.
func patch(cell: Vector2i) -> ArrayMesh:
	if patches.has(cell):
		return patches[cell]
	var side := DETAIL+1
	if patch_uvs.is_empty():
		for z in side:
			for x in side:
				patch_uvs.append(Vector2(x,z)/DETAIL)
				if x < DETAIL and z < DETAIL:
					var i := z*side+x
					patch_indices.append_array(PackedInt32Array([i,i+1,i+side+1,i,i+side+1,i+side]))
	var points := PackedVector3Array()
	var start := (origin_index+cell.y*DETAIL)*stride+origin_index+cell.x*DETAIL
	for z in side:
		var row := start+z*stride
		points.append_array(vertices.slice(row,row+side))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = patch_uvs
	arrays[Mesh.ARRAY_INDEX] = patch_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	patches[cell] = mesh
	return mesh


func _plant(scene: PackedScene, width: float, point: Vector3, rng: RandomNumberGenerator, grounded: bool = true) -> void:
	var plant := landmark(scene,width)
	plant.rotation.y = TAU * rng.randf()
	var grid_scale := global_basis.get_scale()
	plant.scale /= grid_scale
	plant.position = point
	add_child(plant)
	if not grounded:
		return
	var footprint := Basis.from_scale(Vector3(width*.95/grid_scale.x,1,width*.56/grid_scale.z))
	plant_shadows.append(Transform3D(footprint,point+Vector3.UP*.012))
