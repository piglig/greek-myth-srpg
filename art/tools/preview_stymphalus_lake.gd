extends SceneTree
## Normal-window shore study. Pass -- --frames-dir=/existing/path to save both views.

const SHORE := [
	"~~~~~~ww~~~~~~", "~~~~wwwwww~~~~", "~~wwmmmwwwwwww", "wwmmm..mmmwwww",
	"wmmm.....mmmww", "mmm........mmm", "mm..........mm", "m..........mmm",
	"mmm......mmmww", "wwmmm...mmww~~", "wwwwmmmmww~~~~", "~~~~wwwww~~~~~",
]
const BRONZE_CELL := Vector2(6.5,6.5)
const FLOCK_CELL := Vector2(7.5,6.5)
var board := Diorama.new()
var frames_dir := ""
var elapsed := 0.
var phase := 0

func _initialize() -> void:
	call_deferred("run")

func _shore() -> void:
	var heights := []
	var terrain := []
	var terrain_key := {"~":Defs.Terrain.DEEP,"w":Defs.Terrain.SHALLOW,"m":Defs.Terrain.SWAMP,".":Defs.Terrain.PLAIN}
	for row: String in SHORE:
		assert(row.length() == SHORE[0].length())
		for cell in row:
			terrain.append(terrain_key[cell])
			heights.append(0)
	board.map_view.wetland = MapView.Wetland.STYMPHALUS
	board.map_view.build(BattleGrid.from_dict({"w":SHORE[0].length(),"d":SHORE.size(),"heights":heights,"terrain":terrain}))

func _part(mesh: Mesh, at: Vector3, pigment: Color) -> MeshInstance3D:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = pigment
	paint.roughness = .91
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = paint
	board.stand.add_child(piece)
	piece.position = at
	return piece

func _timber(size: Vector3, at: Vector3, pigment: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	_part(box, at, pigment)

func _jetty() -> void:
	var foot := board.spot(Vector2(3.7,3.8))
	var oak := Color("#786956")
	for side: float in [-.48,.48]:
		_timber(Vector3(.11,.17,3.3),foot+Vector3(side,.14,-1.50),oak.darkened(.19))
		for along: float in [.02,-1.55,-3.0]:
			_timber(Vector3(.13,.88,.13),foot+Vector3(side,.11,along),oak.darkened(.32))
	for plank in 15:
		var offset := .018*sin(plank*11.0)
		_timber(Vector3(1.24+2.*offset,.10,.205),foot+Vector3(offset,.26,-.221*plank),oak.lightened(.09+.07*sin(plank*3.8)))
	var post := foot+Vector3(.76,0.,-.12)
	_timber(Vector3(.13,1.83,.13),post+Vector3.UP*.84,oak.darkened(.26))
	_timber(Vector3(.88,.10,.12),post+Vector3(.27,1.68,0),oak)
	for index in 2:
		var hang := post+Vector3(.28+index*.29,1.68,0)
		_timber(Vector3(.023,.24,.023),hang-Vector3.UP*.12,oak.darkened(.52))
		var bronze := SphereMesh.new()
		bronze.radius = .125
		bronze.height = .27
		var bell := _part(bronze,hang-Vector3.UP*.34,Color("#b58a51"))
		bell.scale = Vector3(.85,1.,.4)
		bell.rotation.z = -.18+index*.32

func _picture(label: String) -> void:
	if frames_dir.is_empty(): return
	assert(root.get_texture().get_image().save_png(frames_dir.path_join(label+".png")) == OK)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames-dir="): frames_dir = arg.trim_prefix("--frames-dir=")
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_shore()
	_jetty()
	board.rig.sun.light_color = Color("#f5f0df")
	var bronze := board.unit("stymphalian_bird",BRONZE_CELL,Vector2i.LEFT,true)
	var flock := board.unit("marsh_flock",FLOCK_CELL,Vector2i.LEFT,true)
	for unit: PixelUnit in [bronze,flock]: unit._disc.show()
	board.look((BRONZE_CELL+FLOCK_CELL)*.5)
	assert(is_equal_approx(bronze.position.distance_to(flock.position),MapView.CHAPTER_CELL_PITCH))
	phase = 1

func _process(delta: float) -> bool:
	if phase == 0: return false
	RenderingServer.force_draw(false,delta)
	elapsed += delta
	if phase == 1 and elapsed >= 1.0:
		_picture("front")
		phase = 2
	elif phase == 2 and elapsed >= 3.6:
		board.rig.rotate_step(1)
		phase = 3
	elif phase == 3 and elapsed >= 4.6:
		_picture("turn")
		phase = 4
	elif phase == 4 and elapsed >= 7.6:
		assert(board.rig.zoom_index == 1 and board.rig.yaw_quadrant() == 1)
		print("Stymphalus adjacent units, default zoom, one quarter turn. Window ",root.size)
		root.get_node("Soundscape").quit_game()
		phase = 5
	return false
