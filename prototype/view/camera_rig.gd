class_name CameraRig
extends Node3D
## Orthographic tactics camera: fixed pitch, 90° yaw steps, three zoom levels, pixel-snapped.

const PITCH_DEG := 33.0
const DISTANCE := 40.0
const BASE_YAW := 45.0
const ZOOM_PPU := [24.0, 32.0, 48.0]  ## low-res pixels per world unit
const ROTATE_SPEED := 600.0  ## degrees per second
const PAN_SPEED := 7.0  ## world units per second at the middle zoom

var camera: Camera3D
var post: MeshInstance3D
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
	post.extra_cull_margin = 16384.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://view/pixel_post.gdshader")
	post.material_override = mat
	camera.add_child(post)


func ppu() -> float:
	return ZOOM_PPU[zoom_index]


func focus(point: Vector3) -> void:
	pivot = point


func rotate_step(dir: int) -> void:
	_target_yaw += 90.0 * dir


## 0..3, the current quarter-turn (for mapping screen directions to the grid).
func yaw_quadrant() -> int:
	return posmod(roundi((_target_yaw - BASE_YAW) / 90.0), 4)


func zoom_step(dir: int) -> void:
	zoom_index = clampi(zoom_index + dir, 0, ZOOM_PPU.size() - 1)


func set_post_enabled(on: bool) -> void:
	(post.material_override as ShaderMaterial).set_shader_parameter("enabled", on)


## Pans by a screen-space vector expressed in low-res pixels.
func pan_pixels(delta: Vector2) -> void:
	var right := _ground_right()
	var fwd := _ground_forward()
	pivot -= right * (delta.x / ppu()) - fwd * (delta.y / (ppu() * sin(deg_to_rad(PITCH_DEG))))
	_clamp_pivot()


func _process(dt: float) -> void:
	var move := Vector2(
		Input.get_axis("ui_left", "ui_right") + _key_axis(KEY_A, KEY_D),
		Input.get_axis("ui_up", "ui_down") + _key_axis(KEY_W, KEY_S))
	if move != Vector2.ZERO:
		var speed := PAN_SPEED * (32.0 / ppu()) * dt
		pivot += (_ground_right() * move.x - _ground_forward() * move.y).normalized() * speed * move.length()
		_clamp_pivot()
	_yaw = move_toward(_yaw, _target_yaw, ROTATE_SPEED * dt)
	_apply()


func _apply() -> void:
	var vh := float(get_viewport().get_visible_rect().size.y)
	camera.size = vh / ppu()
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(PITCH_DEG)
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
