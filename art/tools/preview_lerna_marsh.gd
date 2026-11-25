extends SceneTree
## Standalone material study using the battle camera and native unit frames.
## godot --path prototype --script ../art/tools/preview_lerna_marsh.gd
## Pass -- --frames-dir=/path to an existing directory to save stills.

var board := Diorama.new()
var frames_dir := ""
const BANKS := [
	"~~~wwww~~www~~","~~wmmww~wmmmww","wwmmmwwwm...mw","mm..mmwm..mmww",
	"wmm...mm.mmwww","wwmm......mmww","wwwwwm...mwwww","wwwwm...mmww~~",
	"wwmmmmm..mww~~","wm...mwwmmmw~~","mm..mmwwwmmwww","wwmmww~~~~wwww"
]

func _initialize() -> void:
	call_deferred("run")

func picture(label: String) -> void:
	if frames_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	var saved := root.get_texture().get_image().save_png(frames_dir.path_join(label+".png"))
	assert(saved == OK)

func walk(actor: PixelUnit, to: Vector2) -> void:
	actor.walking = true
	var start := board.map_view.to_local(actor.position)
	var from := Vector2(start.x,start.z)
	var stride := create_tween()
	stride.tween_method(func(t: float): actor.position = board.spot(from.lerp(to,t)),0.,1.,.85)
	await stride.finished
	actor.walking = false

# Three fluted drums with chipped upper edges, including a fallen section at the shore.
func _drum(radius: float, height: float, chip: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 72
	for i in SIDES:
		var corners: Array[Vector3] = []
		for n in [i,i+1]:
			var angle: float = TAU*n/SIDES
			var rim := Vector3(cos(angle),0,sin(angle))*radius*(1.-.064*(1.-cos(angle*18.)))
			corners.append(rim)
			var broken := chip*(.5+.34*sin(angle+1.2)+.16*cos(3.*angle))
			corners.append(rim*.92+Vector3.UP*(height-broken))
		var cap := Vector3.UP*(height-chip*.55)
		for vertex: Vector3 in [corners[0],corners[2],corners[1],corners[2],corners[3],corners[1],corners[1],corners[3],cap]:
			tool.set_uv(Vector2(vertex.x+vertex.z,-vertex.y))
			tool.add_vertex(vertex)
	tool.generate_normals()
	return tool.commit()

func _shrine() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#9c9d98")
	stone.albedo_texture = preload("res://art/original/cliff.webp")
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3.ONE*.78
	stone.roughness = 1.0
	stone.cull_mode = BaseMaterial3D.CULL_DISABLED
	for step in 2:
		var slab := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = Vector3(3.1-.24*step,.66 if step == 0 else .15,1.52-.18*step)
		slab.mesh = shape
		slab.material_override = stone
		board.stand.add_child(slab)
		slab.position = board.spot(Vector2(10.65,2.72))+Vector3.UP*(-.275 if step == 0 else .13)
	for at: Vector3 in [Vector3(9.9,1.82,2.72),Vector3(11.47,1.15,2.72),Vector3(10.55,.57,2.72),Vector3(3.,.85,8.8)]:
		var drum := MeshInstance3D.new()
		drum.mesh = _drum(.31,at.y,.17)
		drum.material_override = stone
		board.stand.add_child(drum)
		drum.position = board.spot(Vector2(at.x,at.z))
		if at.x > 9.:
			drum.position.y = board.spot(Vector2(10.65,2.72)).y+.20
		else:
			drum.rotation.z = 1.18
	var pit := Vector2(10.,3.55)
	board.camp_prop(preload("res://art/camp/brazier.glb"),pit,0.,.64)
	board.fire(pit,.40)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames-dir="): frames_dir = arg.trim_prefix("--frames-dir=")
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.map_view.wetland = MapView.Wetland.LERNA
	var heights := []
	var terrain := []
	for row: String in BANKS:
		assert(row.length() == BANKS[0].length())
		for cell in row:
			terrain.append({"~":Defs.Terrain.DEEP,"w":Defs.Terrain.SHALLOW,"m":Defs.Terrain.SWAMP,".":Defs.Terrain.PLAIN}[cell])
			heights.append(1 if cell == "." else 0)
	board.map_view.build(BattleGrid.from_dict({"w":BANKS[0].length(),"d":BANKS.size(),"heights":heights,"terrain":terrain}))
	board.rig.sun.light_color = Color("#ffe1bd")
	_shrine()
	var snake := board.unit("marsh_snake",Vector2(5.5,6.5),Vector2i.LEFT,true)
	var crab := board.unit("giant_crab",Vector2(6.5,6.5),Vector2i.LEFT,true)
	var priest := board.unit("hera_priestess",Vector2(7.5,5.5),Vector2i.LEFT,true)
	for actor: PixelUnit in [snake,crab,priest]: actor._disc.show()
	board.look(Vector2(6.9,5.8))
	await create_timer(1.0).timeout
	await picture("field")
	await create_timer(.7).timeout
	await walk(snake,Vector2(4.5,6.5))
	await walk(crab,Vector2(5.5,6.5))
	board.rig.ease_zoom(2,.5)
	await create_timer(.95).timeout
	await picture("shore")
	for actor: PixelUnit in [snake,crab,priest]:
		actor.play_attack()
		await create_timer(.72).timeout
	board.rig.rotate_step(1)
	await create_timer(1.4).timeout
	await picture("turn")
	await create_timer(.85).timeout
	print("Lerna terrain study complete")
	root.get_node("Soundscape").quit_game()
