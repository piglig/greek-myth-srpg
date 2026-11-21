extends MeshInstance2D
## Correspondences in the two paintings, authored on a 700 by 394 reference.
## Each moving landmark follows the same feature in both poses.
const Landmarks := [
	# Merchant: turban, face, shoulders, elbows, both hands and the pendant.
	[70,120,72,124],[94,109,102,113],[112,119,122,127],[115,139,127,146],
	[89,157,99,167],[67,165,65,168],[62,205,55,205],[119,171,110,186],
	[146,150,133,181],[161,145,152,178],[169,166,160,195],[168,184,161,210],
	[165,192,166,217],[178,191,180,215],[145,219,148,225],[89,220,86,222],
	# Veteran: spear tip, grip and butt, face, sword-arm and shield rim.
	[277,14,220,24],[277,50,233,62],[278,97,251,117],[269,105,246,122],
	[278,144,269,163],[281,218,292,223],[285,321,325,315],
	[266,143,261,147],[290,110,282,117],[313,72,305,68],[328,73,318,72],
	[337,95,293,93],[317,105,303,103],[354,115,347,115],[378,146,371,144],
	[389,188,385,191],[350,243,354,244],[389,312,389,311],
	[289,213,287,213],[291,323,290,323],[347,318,345,318],
	# Pathfinder: bun, nose, shoulders, drawing elbow, wrist and reed pen.
	[585,119,582,130],[609,125,610,135],[614,154,620,165],[584,169,589,178],
	[559,170,563,177],[533,217,561,216],[550,224,581,223],
	[587,237,630,251],[595,244,640,258],[601,260,656,267],
	[627,211,631,211],[640,240,648,243],[655,245,660,245]
]
const Fixed := [
	Vector2(46,95),Vector2(137,95),Vector2(187,127),Vector2(201,183),
	Vector2(202,242),Vector2(136,255),Vector2(55,252),Vector2(35,180),
	Vector2(201,25),Vector2(202,85),Vector2(214,171),Vector2(250,257),
	Vector2(264,336),Vector2(330,342),Vector2(400,327),Vector2(411,205),
	Vector2(409,133),Vector2(371,58),Vector2(307,21),
	Vector2(522,99),Vector2(638,100),Vector2(661,160),Vector2(676,234),
	Vector2(677,279),Vector2(615,288),Vector2(530,264),Vector2(508,222),Vector2(528,151)
]
const Reference := Vector2(700,394)
const Display := Vector2(1366,768)

func _ready():
	var source:=PackedVector2Array()
	var target:=PackedVector2Array()
	var colors:=PackedColorArray()
	var centers:=PackedVector2Array()
	var anchors: Array=Fixed.duplicate()
	for x in range(0,701,100):
		anchors.append(Vector2(x,0))
		anchors.append(Vector2(x,394))
	for y in [100,200,300]:
		anchors.append(Vector2(0,y))
		anchors.append(Vector2(700,y))
	for p: Vector2 in anchors:
		source.append(p/Reference*Display)
		target.append(p/Reference)
		centers.append(p)
		colors.append(Color.BLACK)
	for mark in Landmarks:
		var from:=Vector2(mark[0],mark[1])
		var to:=Vector2(mark[2],mark[3])
		source.append(from/Reference*Display)
		target.append(to/Reference)
		centers.append((from+to)*.5)
		colors.append(Color.WHITE)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=source
	arrays[Mesh.ARRAY_TEX_UV]=target
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=Geometry2D.triangulate_delaunay(centers)
	var surface:=ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh=surface
	texture=preload("res://art/original/interface/companions_camp.webp")
	var paint:=ShaderMaterial.new()
	paint.shader=preload("res://ui/camp_light.gdshader")
	paint.set_shader_parameter("work_pose",preload("res://art/original/interface/camp_work_pose.webp"))
	paint.set_shader_parameter("registration",preload("res://art/original/interface/camp_work_registration.png"))
	material=paint
