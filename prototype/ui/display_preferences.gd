extends Node

const PATH := "user://display.cfg"
const CAPS := [0, 30, 60, 120]
var fullscreen := false
var vsync := true
var frame_cap := 0

func _ready() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		fullscreen = file.get_value("display", "fullscreen", false) == true
		vsync = file.get_value("display", "vsync", true) == true
		frame_cap = int(file.get_value("display", "frame_cap", 0))
		if frame_cap not in CAPS:
			frame_cap = 0
		apply()

func apply() -> void:
	var window := get_window()
	if fullscreen != (window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]):
		window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = frame_cap

func commit() -> Error:
	apply()
	var file := ConfigFile.new()
	file.set_value("display", "fullscreen", fullscreen)
	file.set_value("display", "vsync", vsync)
	file.set_value("display", "frame_cap", frame_cap)
	return file.save(PATH)
