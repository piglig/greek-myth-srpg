class_name CameraRig
extends Node3D
## Orthographic tactics camera: fixed pitch, 90° yaw steps, three zoom levels, pixel-snapped.

const PITCH_DEG := 30.0
const DISTANCE := 40.0
const BASE_YAW := 45.0
const ZOOM_PPU := [21.213203, 28.284271, 42.426407]  ## low-res pixels per world unit
const ROTATE_SPEED := 600.0  ## degrees per second
const PAN_SPEED := 7.0  ## world units per second at the middle zoom

var tactical := false
var painted := false
## False for menu dioramas: the keyboard belongs to the menu, not the camera.
var steered := true
var camera: Camera3D
var post: MeshInstance3D
## Key light for the painted battlefields. It turns with the camera so rock faces toward the
## viewer stay a step darker than the ground above them from every quadrant.
var sun: DirectionalLight3D
var _zoom_motion: Tween
var _zoom_ratio := 1.0
var _glide: Tween
var pivot := Vector3.ZERO
var bounds := AABB()
var zoom_index := 1
var _yaw := BASE_YAW
var _target_yaw := BASE_YAW


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 120.0
	add_child(camera)
	camera.current = true

	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	post = MeshInstance3D.new()
	post.mesh = quad
	post.position.z = -1.0
	post.extra_cull_margin = 16384.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://view/pixel_post.gdshader")
	post.material_override = mat
	camera.add_child(post)


func ppu() -> float:
	var density := float(ZOOM_PPU[zoom_index])
	if painted:
		density *= get_viewport().get_visible_rect().size.y / 360.0
	return density*_zoom_ratio


func focus(point: Vector3) -> void:
	pivot = point
	_apply()


## Whether the points' vertical spread fits the given band of the screen at the current zoom.
func spans(points: Array[Vector3], top_fraction: float, bottom_fraction: float) -> bool:
	var up := camera.global_transform.basis.y
	var highest := -INF
	var lowest := INF
	for point in points:
		highest = maxf(highest,point.dot(up))
		lowest = minf(lowest,point.dot(up))
	return (highest-lowest)*ppu() <= get_viewport().get_visible_rect().size.y*(bottom_fraction-top_fraction)


## Slide the view just far enough along the ground that every given point sits inside the
## band of the screen left clear by the top bar and the command panel.
func keep_in_view(points: Array[Vector3], top_fraction: float, bottom_fraction: float) -> void:
	if points.is_empty():
		return
	var height := float(get_viewport().get_visible_rect().size.y)
	var up := camera.global_transform.basis.y
	var highest := -INF
	var lowest := INF
	for point in points:
		var row := height*.5 - (point-pivot).dot(up)*ppu()
		highest = maxf(highest,row)
		lowest = minf(lowest,row)
	var shift := 0.0
	if highest > height*bottom_fraction:
		shift = minf(highest-height*bottom_fraction,maxf(0.0,lowest-height*top_fraction))
	elif lowest < height*top_fraction:
		shift = -minf(height*top_fraction-lowest,maxf(0.0,height*bottom_fraction-highest))
	pivot -= _ground_forward()*shift/(ppu()*sin(deg_to_rad(_pitch_degrees())))
	_apply()


func ease_zoom(index: int, seconds: float) -> void:
	if _zoom_motion: _zoom_motion.kill()
	var current := float(ZOOM_PPU[zoom_index])*_zoom_ratio
	zoom_index = index
	_zoom_ratio = current/float(ZOOM_PPU[index])
	_zoom_motion = create_tween()
	_zoom_motion.tween_property(self,"_zoom_ratio",1.,seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func glide_to(point: Vector3) -> void:
	if _glide:
		_glide.kill()
	_glide = create_tween()
	_glide.tween_property(self,"pivot",point,0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func set_quadrant(turn: int) -> void:
	_target_yaw = (-15.0 if painted else BASE_YAW) + 90.0 * turn
	_yaw = _target_yaw


func rotate_step(dir: int) -> void:
	_target_yaw += 90.0 * dir


## 0..3, the current quarter-turn (for mapping screen directions to the grid).
func yaw_quadrant() -> int:
	return posmod(roundi((_target_yaw - (-15.0 if painted else BASE_YAW)) / 90.0), 4)


func zoom_step(dir: int) -> void:
	zoom_index = clampi(zoom_index + dir, 0, ZOOM_PPU.size() - 1)


func set_post_enabled(on: bool) -> void:
	(post.material_override as ShaderMaterial).set_shader_parameter("enabled", on)


## Pans by a screen-space vector expressed in low-res pixels.
func pan_pixels(delta: Vector2) -> void:
	if _glide:
		_glide.kill()
	var right := _ground_right()
	var fwd := _ground_forward()
	pivot -= right * (delta.x / ppu()) - fwd * (delta.y / (ppu() * sin(deg_to_rad(_pitch_degrees()))))
	_clamp_pivot()


func _process(dt: float) -> void:
	var move := Vector2(
		Input.get_axis("ui_left", "ui_right") + _key_axis(KEY_A, KEY_D),
		Input.get_axis("ui_up", "ui_down") + _key_axis(KEY_W, KEY_S))
	if move != Vector2.ZERO and steered:
		if _glide:
			_glide.kill()
		var speed := PAN_SPEED * (32.0 / float(ZOOM_PPU[zoom_index])) * dt
		pivot += (_ground_right() * move.x - _ground_forward() * move.y).normalized() * speed * move.length()
		_clamp_pivot()
	_yaw = move_toward(_yaw, _target_yaw, ROTATE_SPEED * dt)
	_apply()


func _pitch_degrees() -> float:
	return 56.0 if tactical else (45.0 if painted else PITCH_DEG)


func _apply() -> void:
	var vh := float(get_viewport().get_visible_rect().size.y)
	camera.size = vh / ppu()
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(_pitch_degrees())
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var pos := pivot + dir * DISTANCE
	camera.global_transform = Transform3D(Basis(), pos).looking_at(pivot, Vector3.UP)
	# Snap to the low-res texel grid in camera space so static pixels never swim while panning.
	var b := camera.global_transform.basis
	var t := 1.0 / ppu()
	var x := snappedf(pos.dot(b.x), t)
	var y := snappedf(pos.dot(b.y), t)
	var z := pos.dot(b.z)
	camera.global_position = b.x * x + b.y * y + b.z * z
	if sun != null and painted:
		var to_light := -0.52*_ground_right() + 0.82*Vector3.UP - 0.24*_ground_forward()
		sun.basis = Basis.looking_at(-to_light.normalized(),Vector3.UP)


func _ground_right() -> Vector3:
	var yaw := deg_to_rad(_yaw)
	return Vector3(cos(yaw), 0, -sin(yaw))


func _ground_forward() -> Vector3:
	var yaw := deg_to_rad(_yaw)
	return Vector3(-sin(yaw), 0, -cos(yaw))


func _clamp_pivot() -> void:
	if bounds.size != Vector3.ZERO:
		pivot.x = clampf(pivot.x, bounds.position.x, bounds.end.x)
		pivot.z = clampf(pivot.z, bounds.position.z, bounds.end.z)


static func _key_axis(neg: Key, pos: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(pos) else 0.0) - (1.0 if Input.is_physical_key_pressed(neg) else 0.0)
