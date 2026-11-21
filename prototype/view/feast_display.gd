extends Node3D
## The gathering sits along the edge of the fight, leaving the charge lane open.

func setup(field: NemeaField) -> void:
	var cave := NemeaField.landmark(preload("res://art/landmarks/cave.glb"),3.1)
	_place(cave,field,Vector2(1.4,3.0))
	for xy: Vector2 in [Vector2(1.15,4.7),Vector2(1.72,4.9),Vector2(1.98,4.48),Vector2(6.7,2.12),Vector2(7.22,1.86)]:
		var jar := _amphora()
		jar.scale *= .78 + .22 * sin(xy.x*2)
		jar.rotation.y = xy.y
		_place(jar,field,xy)
	var pit := Node3D.new()
	_place(pit,field,Vector2(5.5,2.6))
	for i in 9:
		var rock := NemeaField.landmark(preload("res://art/landmarks/boulder.glb"),.33)
		var angle := TAU*i/9
		rock.scale.y *= .68
		rock.position = Vector3(cos(angle)*.39,0,sin(angle)*.39)
		pit.add_child(rock)
	var flame := MeshInstance3D.new()
	var sheet := QuadMesh.new()
	sheet.size = Vector2(.88,.82)
	flame.mesh = sheet
	var ink := ShaderMaterial.new()
	ink.shader = preload("res://view/village_flame.gdshader")
	ink.set_shader_parameter("atlas",preload("res://art/original/fire.png"))
	flame.material_override = ink
	flame.position.y = .45
	pit.add_child(flame)


func _place(prop: Node3D, field: NemeaField, point: Vector2) -> void:
	prop.position = Vector3(point.x,field.elevation(point.x,point.y),point.y)
	add_child(prop)


func _amphora() -> Node3D:
	var jar := Node3D.new()
	var profile := [Vector2(.08,0),Vector2(.12,.06),Vector2(.09,.12),Vector2(.22,.30),
		Vector2(.26,.49),Vector2(.24,.58),Vector2(.23,.61),Vector2(.15,.67),
		Vector2(.11,.70),Vector2(.11,.79),Vector2(.14,.80),Vector2(.14,.84)]
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color("#ad5938")
	var glaze := StandardMaterial3D.new()
	glaze.albedo_color = Color("#412d2b")
	for i in range(1,profile.size()):
		var lower: Vector2 = profile[i-1]
		var upper: Vector2 = profile[i]
		var part := MeshInstance3D.new()
		var section := CylinderMesh.new()
		section.radial_segments = 16
		section.rings = 0
		section.height = upper.y-lower.y
		section.top_radius = upper.x
		section.bottom_radius = lower.x
		section.cap_bottom = false
		section.cap_top = i==profile.size()-1
		part.mesh = section
		part.material_override = glaze if i in [1,6,11] else clay
		part.position.y = (upper.y+lower.y)*.5
		jar.add_child(part)
	for side in [-1,1]:
		var handle := MeshInstance3D.new()
		var loop := TorusMesh.new()
		loop.inner_radius = .088
		loop.outer_radius = .123
		handle.mesh = loop
		handle.material_override = clay
		handle.position = Vector3(side*.159,.655,0)
		handle.rotation.x = PI*.5
		handle.scale = Vector3(.7,1,1.34)
		jar.add_child(handle)
	return jar
