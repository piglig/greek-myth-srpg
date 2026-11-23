class_name UiShot
## Saves a picture of whatever screen is up, then quits. Used by `-- --ui=<page> --shot=<png>`.

static func take(from: Node, path: String, wait := 1.6) -> void:
	if path == "":
		return
	var tree := from.get_tree()
	await tree.create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(path)
	print("captured ",path)
	Soundscape.quit_game()
