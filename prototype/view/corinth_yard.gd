extends Node3D
## The stacked timber and posts mark the execution ground beside the playable route.

func setup(field: NemeaField) -> void:
	var wood:=StandardMaterial3D.new()
	wood.albedo_color=Color("#5e3928")
	var bark:=StandardMaterial3D.new()
	bark.albedo_color=Color("#80573d")
	for point: Vector2 in [Vector2(1.45,6.65),Vector2(3.5,9.72),Vector2(6.75,.88)]:
		var pile:=Node3D.new()
		pile.position=Vector3(point.x,field.elevation(point.x,point.y),point.y)
		add_child(pile)
		for tier in 3:
			for index in 4:
				var log_piece:=MeshInstance3D.new()
				var log_mesh:=CylinderMesh.new()
				log_mesh.radial_segments=7
				log_mesh.rings=0
				log_mesh.top_radius=.09
				log_mesh.bottom_radius=.11
				log_mesh.height=1.18
				log_piece.mesh=log_mesh
				log_piece.material_override=wood if index%2 else bark
				var offset:=(index-1.5)*.21
				log_piece.position=Vector3(offset if tier%2 else 0.,.12+tier*.15,0. if tier%2 else offset)
				log_piece.rotation=Vector3(PI*.5,0,0) if tier%2 else Vector3(0,0,PI*.5)
				pile.add_child(log_piece)
		var post:=MeshInstance3D.new()
		var beam:=BoxMesh.new()
		beam.size=Vector3(.15,1.82,.17)
		post.mesh=beam
		post.material_override=wood
		post.position=Vector3(-.18,.9,-.25)
		pile.add_child(post)
