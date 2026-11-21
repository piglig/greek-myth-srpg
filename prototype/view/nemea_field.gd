class_name NemeaField
extends Node3D
## Render the rule cells and continue their geology beyond the playable area.
const OLIVE := preload("res://art/landmarks/olive.glb")
const CYPRESS := preload("res://art/landmarks/cypress.glb")
const THYME := preload("res://art/landmarks/scrub.glb")
const ROCK := preload("res://art/landmarks/boulder.glb")


static var landmark_finish: ShaderMaterial
static var shadow_plane: PlaneMesh


static func landmark(scene: PackedScene, width: float) -> Node3D:
	var model := scene.instantiate() as Node3D
	if landmark_finish == null:
		landmark_finish = ShaderMaterial.new()
		landmark_finish.shader = preload("res://view/landmark.gdshader")
		landmark_finish.set_shader_parameter("grain", preload("res://art/original/earth.webp"))
	var parts := model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:
		parts.append(model)
	for part: MeshInstance3D in parts:
		part.material_override = landmark_finish
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
const DETAIL := 8
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
	var step_count := absf(a-b)/map_layer_height
	var margin := lerpf(0.08,0.33,smoothstep(1.0,3.0,step_count))
	return lerpf(a,b,smoothstep(margin,1.0-margin,t))


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
		tx += sin(PI*tx)*(0.105*sin(z*2.1)+0.045*sin(z*4.5+x))
		tz += sin(PI*tz)*(0.12*sin(x*1.6)+0.055*cos(x*3.7-z))
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
				if rng.randf() >= 0.14:
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


func _plant(scene: PackedScene, width: float, point: Vector3, rng: RandomNumberGenerator) -> void:
	var plant := landmark(scene,width)
	plant.rotation.y = TAU * rng.randf()
	var grid_scale := global_basis.get_scale()
	plant.scale /= grid_scale
	plant.position = point
	add_child(plant)
	var footprint := Basis.from_scale(Vector3(width*.95/grid_scale.x,1,width*.56/grid_scale.z))
	plant_shadows.append(Transform3D(footprint,point+Vector3.UP*.012))
