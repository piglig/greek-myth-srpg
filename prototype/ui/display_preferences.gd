extends Node

const PATH := "user://display.cfg"
const CAPS := [0, 30, 60, 120]
## Window sizes on offer. The picture is drawn for 16:9 and scaled to the window, so
## every one of these shows the same thing, only sharper or coarser.
const SIZES: Array[Vector2i] = [Vector2i(1280,720),Vector2i(1366,768),Vector2i(1600,900),
	Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]
const SMALLEST := Vector2i(960,540)
var size := Vector2i(1600,900)
var fullscreen := false
var vsync := true
var frame_cap := 0

func _ready() -> void:
	get_window().min_size = SMALLEST
	get_window().size_changed.connect(func(): Px.fit_window(get_window()))
	Px.fit_window(get_window())
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		var saved: Variant = file.get_value("display", "size", size)
		if saved is Vector2i and saved in SIZES:
			size = saved
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
	# Tests and screenshots (headless, or started with arguments of their own) keep the
	# size they were started at.
	if not fullscreen and not _fixed() and window.size != size:
		var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		window.size = size
		window.position = screen.position+(screen.size-size)/2
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = frame_cap

func _fixed() -> bool:
	return DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().is_empty()


## The sizes that fit on the screen the window is on. Never empty.
func sizes() -> Array[Vector2i]:
	# What is left of the screen beside the taskbar: a window as large as the whole screen
	# is what 全屏 is for.
	var room := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var out: Array[Vector2i] = []
	for option in SIZES:
		if option.x <= room.x and option.y <= room.y: out.append(option)
	if out.is_empty(): out.append(SIZES[0])
	return out


## Moves on to the next size that fits, coming round to the smallest after the largest.
func next_size() -> void:
	var options := sizes()
	size = options[(options.find(size)+1) % options.size()]


func commit() -> Error:
	apply()
	var file := ConfigFile.new()
	file.set_value("display", "size", size)
	file.set_value("display", "fullscreen", fullscreen)
	file.set_value("display", "vsync", vsync)
	file.set_value("display", "frame_cap", frame_cap)
	return file.save(PATH)
