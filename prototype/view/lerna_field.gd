extends NemeaField
## Soft banks and reed beds follow the same grid used for picking and unit anchors.

var pale_lake := false

func _blend(a: float, b: float, t: float) -> float:
	return lerpf(a,b,smoothstep(.19,.81,t))


func build(battle_grid: BattleGrid, layer_height: float, _village := false, _woodland := false) -> void:
	grid = battle_grid
	map_layer_height = layer_height
	var surface := _build_surface()
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://view/lerna_ground.gdshader")
	if pale_lake:
		paint.set_shader_parameter("silt",preload("res://art/original/stymphalus-silt.webp"))
		paint.set_shader_parameter("shallows",Vector3(.246,.276,.291))
		paint.set_shader_parameter("depths",Vector3(.145,.178,.204))
	else:
		paint.set_shader_parameter("silt",preload("res://art/original/lerna-mud.webp"))
	var wet := Image.create(grid.width,grid.depth,false,Image.FORMAT_R8)
	for z in grid.depth:
		for x in grid.width:
			var water := _wetness(Vector2i(x,z))
			wet.set_pixel(x,z,Color(water,0,0))
	paint.set_shader_parameter("wet_cells",ImageTexture.create_from_image(wet))
	paint.set_shader_parameter("field_size",Vector2(grid.width,grid.depth))
	paint.set_shader_parameter("grid_lines",grid_lines)
	surface.material_override = paint
	add_child(surface)
	_reed_beds()


func _wetness(cell: Vector2i) -> float:
	match grid.terrain_at(cell):
		Defs.Terrain.SHALLOW: return .79
		Defs.Terrain.DEEP: return 1.
		Defs.Terrain.SWAMP: return .24
	return 0.


func _reed_beds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2182
	var mesh_tool := SurfaceTool.new()
	mesh_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 0
	for z in range(-4,grid.depth+4):
		for x in range(-4,grid.width+4):
			var cell := Vector2i(x,z)
			var sample_cell := cell.clamp(Vector2i.ZERO,Vector2i(grid.width-1,grid.depth-1))
			var beds := sin(x*.78+z*.43)+.7*sin(z*1.17-x*.31)
			if _wetness(sample_cell) < .15 or beds < -.25 or rng.randf() > .72:
				continue
			var edge := Vector2(x+rng.randf_range(.11,.29),z+rng.randf_range(.10,.28))
			var height := rng.randf_range(.24,.48) if grid.in_bounds(cell) else rng.randf_range(.48,.88)
			for blade in rng.randi_range(12,25):
				var radius := rng.randf_range(.0,.19)
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
	if blades > 0:
		mesh_tool.generate_normals()
		var reeds := MeshInstance3D.new()
		reeds.mesh = mesh_tool.commit()
		var paint := ShaderMaterial.new()
		paint.shader = preload("res://view/lerna_reed.gdshader")
		reeds.material_override = paint
		reeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(reeds)
