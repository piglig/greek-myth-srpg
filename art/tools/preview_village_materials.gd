extends SceneTree
## Run against battle 1-1. Add --pixel-village after -- for the material study.

func _initialize():
	call_deferred("run")

func run():
	change_scene_to_file("res://main.tscn")
	await scene_changed
	var battle = current_scene
	var field: NemeaField = battle.map_view.field
	var pixel := "--pixel-village" in OS.get_cmdline_user_args()
	for part in field.get_children():
		if part is MeshInstance3D and part.material_override is ShaderMaterial:
			if part.material_override.shader == preload("res://view/nemea_ground.gdshader"):
				part.material_override.set_shader_parameter("pixel_pigment",pixel)
	NemeaField.landmark_finish.set_shader_parameter("pixel_pigment",pixel)
	battle.cam_rig.set_quadrant(0)
	battle.cam_rig.zoom_step(1)
	battle.cam_rig.focus(Vector3(1.55,.45,4.75))
	for frame in 90: await process_frame
	print("BEGIN ",Engine.get_frames_drawn())
	await create_timer(.65).timeout
	await battle._perform({"type":"move","unit":"hero","to":Vector2i(2,4)})
	print("ARRIVED ",battle.state.unit("hero").pos==Vector2i(2,4))
	await create_timer(.55).timeout
	battle.cam_rig.rotate_step(1)
	await create_timer(1.3).timeout
	print("END ",Engine.get_frames_drawn())
	GoEngine.shutdown()
	root.get_node("Soundscape").quit_game()
