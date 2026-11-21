class_name PaintedBow
extends Node3D

var limbs: Array[MeshInstance3D] = []
var strings: Array[MeshInstance3D] = []
var shaft: Node3D
var length_half := .55


func build(thickness := .024) -> void:
	for side in 2:
		for i in 4:
			var radius := thickness-i*.004
			limbs.append(_rod(self,radius,radius-.004,Color("#825635") if i else Color("#543b2b")))
		strings.append(_rod(self,.004,.004,Color("#dac29b")))


func _rod(parent: Node3D, base: float, tip: float, color: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.bottom_radius = base
	cylinder.top_radius = tip
	cylinder.height = 1.
	cylinder.radial_segments = 7
	cylinder.rings = 0
	piece.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .92
	piece.material_override = mat
	parent.add_child(piece)
	return piece


func _span(piece: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b-a
	var basis := Basis(Quaternion(Vector3.UP,d.normalized()))
	piece.transform = Transform3D(basis.scaled_local(Vector3(1.,d.length(),1.)),(a+b)*.5)


func pose(left: Vector3, vertical: Vector3, forward: Vector3, center_string: Vector3, draw: float) -> void:
	for side in 2:
		var last := left
		var sign_y := -1. if side == 0 else 1.
		for j in 4:
			var t := float(j+1)/4.
			var end := left+vertical*sign_y*t*(length_half-.047*draw)-forward*(.19+.10*draw)*smoothstep(0.,.91,t)
			_span(limbs[side*4+j],last,end)
			last = end
		_span(strings[side],last,center_string)
	if is_instance_valid(shaft):
		shaft.position = center_string
		shaft.basis = Basis(Quaternion(Vector3.BACK,forward))


func nock() -> void:
	shaft = Node3D.new()
	add_child(shaft)
	_span(_rod(shaft,.007,.006,Color("#b18961")),Vector3.ZERO,Vector3.BACK*.64)
	_span(_rod(shaft,.023,.001,Color("#b5a082")),Vector3.BACK*.62,Vector3.BACK*.69)
	_span(_rod(shaft,.018,.009,Color("#c0a685")),Vector3.BACK*.012,Vector3.BACK*.082)


func loose(flight_parent: Node3D, target: Vector3, seconds: float) -> Tween:
	var arrow := shaft
	shaft = null
	arrow.reparent(flight_parent,true)
	var tip := arrow.global_basis*Vector3.BACK*.69
	var flight := create_tween()
	flight.tween_property(arrow,"global_position",target-tip,seconds)
	flight.tween_callback(arrow.queue_free)
	return flight


