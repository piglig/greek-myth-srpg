class_name VillageDisplay
extends Node3D
## Static village landmarks and the burning cells received from the rule engine.
var gate: Node3D
var known_fire := {}
var fire_material := ShaderMaterial.new()
var char_material := StandardMaterial3D.new()
var map_view: MapView
var plume_mesh: ArrayMesh
var flame_quad := QuadMesh.new()


func setup(view: MapView) -> void:
	map_view = view
	var field := view.field
	fire_material.shader = preload("res://view/village_flame.gdshader")
	fire_material.set_shader_parameter("atlas",preload("res://art/original/fire.png"))
	plume_mesh = _make_plume()
	flame_quad.size = Vector2(1.18,1.18)
	char_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	char_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	char_material.albedo_color = Color(0.17,0.10,0.08,0.36)
	var house := preload("res://art/landmarks/ruin.glb")
	var workshop := preload("res://art/landmarks/workshop.glb")
	var debris := preload("res://art/landmarks/debris.glb")
	for site in field.house_sites:
		var building := NemeaField.landmark(workshop if site.porch else house,site.width)
		building.transform = site.pose
		add_child(building)
		_seat_house(field,building,site.porch)
	_prop(field,debris,Vector2(0.3,7.6),1.1)
	_prop(field,debris,Vector2(2.4,9.5),1.0)
	_prop(field,preload("res://art/landmarks/cart.glb"),Vector2(10.8,2.6),1.8)
	gate = _prop(field,preload("res://art/landmarks/gate.glb"),Vector2(9.0,-2.1),2.5)


func _prop(field: NemeaField, model: PackedScene, point: Vector2, width: float) -> Node3D:
	var prop := NemeaField.landmark(model,width)
	prop.position = Vector3(point.x,field.elevation(point.x,point.y),point.y)
	prop.rotation.y = 0.16 * sin(point.x + point.y)
	add_child(prop)
	var shade := NemeaField.shadow(width*1.23,width*0.94)
	shade.position += prop.position
	add_child(shade)
	return prop


# The threshold stays level. Individual footing stones extend down into the hillside.
func _seat_house(field: NemeaField, house: Node3D, porch: bool) -> void:
	var footprint := PackedVector2Array([Vector2(-.49,-.333),Vector2(.49,-.333),
		Vector2(.49,.333),Vector2(.42,.34),Vector2(.42,.546),
		Vector2(-.42,.546),Vector2(-.42,.34),Vector2(-.49,.333)])
	if not porch:
		footprint = PackedVector2Array([Vector2(-.49,-.333),Vector2(.49,-.333),Vector2(.49,.333),Vector2(-.49,.333)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = roundi((house.position.x+22)*413+(house.position.z+14)*751)
	for i in footprint.size():
		var a := footprint[i]
		var b := footprint[(i+1)%footprint.size()]
		var normal := Vector2(b.y-a.y,a.x-b.x).normalized()
		var count := ceili(a.distance_to(b)/.14)
		for j in count:
			var start := a.lerp(b,float(j)/count)
			var finish := a.lerp(b,float(j+1)/count)
			var outward_l := start.normalized()
			var outward_r := finish.normalized()
			var left := house.transform*Vector3(start.x+outward_l.x*.011,0,start.y+outward_l.y*.011)
			var right := house.transform*Vector3(finish.x+outward_r.x*.011,0,finish.y+outward_r.y*.011)
			var low_l := field.elevation(left.x,left.z)-.085
			var low_r := field.elevation(right.x,right.z)-.085
			var top_l := house.transform*Vector3(start.x,.009,start.y)
			var top_r := house.transform*Vector3(finish.x,.009,finish.y)
			var rim_l := left + Vector3(outward_l.x,0,outward_l.y).rotated(Vector3.UP,house.rotation.y)*.16
			var rim_r := right + Vector3(outward_r.x,0,outward_r.y).rotated(Vector3.UP,house.rotation.y)*.16
			if rng.randf() < 0.48 and (normal.y < .8 or absf(start.x+.07)>.20):
				var foot := rim_l.lerp(rim_r,rng.randf_range(.12,.88))
				foot.y = field.elevation(foot.x,foot.z)
				var radius := rng.randf_range(.066,.135)
				var crown := foot+Vector3(radius*.13,radius*.68,-radius*.05)
				for k in 6:
					var angle := k*TAU/6.0
					var next := (k+1)*TAU/6.0
					var v := foot+Vector3(cos(angle)*radius,-.023,sin(angle)*radius*.68)
					var w := foot+Vector3(cos(next)*radius,-.023,sin(next)*radius*.68)
					_stone_face(st,v,w,crown,crown,Color("#AC9D85"))
			var rows := maxi(1,ceili((house.position.y-minf(low_l,low_r))/.23))
			_stone_face(st,top_l,top_r,right,left,Color("#B5A58C"))
			for row in rows:
				var q0 := float(row)/rows
				var q1 := float(row+1)/rows
				var l1 := left.lerp(Vector3(left.x,low_l,left.z),q1)
				var r1 := right.lerp(Vector3(right.x,low_r,right.z),q1)
				var l0 := left.lerp(Vector3(left.x,low_l,left.z),q0)
				var r0 := right.lerp(Vector3(right.x,low_r,right.z),q0)
				_stone_face(st,l0,r0,r1,l1,Color("#948874").darkened(rng.randf_range(0,.16)))
	# A run of dressed stone treads ends at the actual ground in front of this door.
	if porch:
		for j in 6:
			var x := -.42 + .14*j
			var c := Color("#B9A68D").darkened(.025*(j%3))
			_stone_face(st,house.transform*Vector3(x,.002,.319),house.transform*Vector3(x+.139,.002,.319),
				house.transform*Vector3(x+.139,.002,.546),house.transform*Vector3(x,.002,.546),c)
	_stone_face(st,house.transform*Vector3(-.46,.003,-.30),house.transform*Vector3(.46,.003,-.30),
		house.transform*Vector3(.46,.003,.32),house.transform*Vector3(-.46,.003,.32),Color("#AD9C80"))
	var entry_z := .546 if porch else .305
	var path_end := entry_z + .34
	var landing := house.transform*Vector3(-.07,0,path_end)
	var lower_y := field.elevation(landing.x,landing.z)
	var steps := clampi(ceili(absf(house.position.y-lower_y)/.16),2,6)
	for j in steps:
		var z0 := lerpf(entry_z,path_end,float(j)/steps)
		var z1 := lerpf(entry_z,path_end,float(j+1)/steps)
		var h := lerpf(house.position.y,lower_y,float(j+1)/steps)+.025
		var corners := PackedVector3Array()
		for xz in [Vector2(-.217,z0),Vector2(.079,z0),Vector2(.088,z1),Vector2(-.226,z1)]:
			var v := house.transform*Vector3(xz.x,0,xz.y)
			v.y = h
			corners.append(v)
		_stone_face(st,corners[0],corners[1],corners[2],corners[3],Color("#B9A58A"))
		for k in [1,2,3]:
			var a := corners[k]
			var b := corners[(k+1)%4]
			_stone_face(st,a,b,Vector3(b.x,minf(h-.04,field.elevation(b.x,b.z)-.065),b.z),
				Vector3(a.x,minf(h-.04,field.elevation(a.x,a.z)-.065),a.z),Color("#90816A"))
	var base := MeshInstance3D.new()
	base.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	base.material_override = mat
	add_child(base)


func _stone_face(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3,tint: Color) -> void:
	var normal := (c-a).cross(b-a).normalized()
	if normal == Vector3.ZERO:
		return
	var points := [a,b,c] if c == d else [a,b,c,a,c,d]
	for v in points:
		st.set_color(tint)
		st.set_normal(normal)
		st.add_vertex(v)


# Pack four smoke wisps and two sparks in one mesh shared by every fire cell.
func _make_plume() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var phase := float(i)/4.0 if i < 4 else 0.18+0.5*(i-4)
		for uv: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.ZERO,Vector2.ONE,Vector2.DOWN]:
			st.set_uv(uv)
			st.set_color(Color(phase,float(i>=4),0,1))
			st.add_vertex(Vector3(uv.x-.5,.5-uv.y,0))
	var mesh := st.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://view/fire_plume.gdshader")
	mesh.surface_set_material(0,material)
	mesh.custom_aabb = AABB(Vector3(-.85,-.2,-.85),Vector3(3.1,2.8,2.9))
	return mesh


func sync_fire(grid: BattleGrid) -> void:
	if map_view.field == null:
		return
	var spreading := not known_fire.is_empty()
	for z in grid.depth:
		for x in grid.width:
			var cell := Vector2i(x,z)
			if known_fire.has(cell) or grid.terrain_at(cell) != Defs.Terrain.BURNING:
				continue
			known_fire[cell] = true
			var floor_point := Vector3(x+0.5,grid.height_at(cell)*MapView.LEVEL_HEIGHT+0.014,z+0.5)
			var ash := MeshInstance3D.new()
			ash.mesh = map_view.field.patch(cell)
			ash.material_override = char_material
			ash.position.y = 0.014
			add_child(ash)
			var flame := MeshInstance3D.new()
			flame.mesh = flame_quad
			flame.material_override = fire_material
			flame.position = floor_point + Vector3(0,0.47,0)
			add_child(flame)
			var plume := MeshInstance3D.new()
			plume.mesh = plume_mesh
			plume.position = floor_point
			plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(plume)
			if spreading:
				plume.set_instance_shader_parameter("density",0.0)
				flame.set_instance_shader_parameter("growth",0.0)
				create_tween().tween_method(func(amount: float) -> void:
					plume.set_instance_shader_parameter("density",amount)
					flame.set_instance_shader_parameter("growth",amount),0.0,1.0,0.55)
