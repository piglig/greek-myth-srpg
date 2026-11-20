class_name UnitView
extends Node3D
## Billboard placeholder sprite + team disc + facing marker for one unit.

const TEXELS_PER_TILE := 32.0
const PLAYER_COLOR := Color(0.25, 0.55, 0.95)
const ENEMY_COLOR := Color(0.9, 0.25, 0.2)
const SELECTED_COLOR := Color(1.0, 0.86, 0.3)

var unit_id := ""
var size := 1
var sprite_height := 0.8  ## world units, used to place overlay bars
var _sprite: Sprite3D
var _disc: MeshInstance3D
var _nose: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _team_color: Color


func setup(u: UnitState) -> void:
	unit_id = u.id
	size = u.size
	name = "Unit_" + u.id
	_team_color = PLAYER_COLOR if u.team == Defs.Team.PLAYER else ENEMY_COLOR

	_disc_mat = _flat(_team_color)
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.4 * size
	disc_mesh.bottom_radius = 0.4 * size
	disc_mesh.height = 0.03
	disc_mesh.radial_segments = 16
	_disc = MeshInstance3D.new()
	_disc.mesh = disc_mesh
	_disc.material_override = _disc_mat
	_disc.position.y = 0.02
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)

	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.16, 0.05, 0.16)
	_nose = MeshInstance3D.new()
	_nose.mesh = nose_mesh
	_nose.material_override = _flat(Color(1, 1, 1))
	_nose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_nose)

	var tex := PlaceholderArt.texture(u.def_id)
	_sprite = Sprite3D.new()
	_sprite.texture = tex
	_sprite.pixel_size = 1.0 / TEXELS_PER_TILE
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = false
	_sprite.offset = Vector2(0, tex.get_height() * 0.5)
	_sprite.position.y = 0.04
	add_child(_sprite)
	sprite_height = tex.get_height() / TEXELS_PER_TILE
	set_facing(u.facing)


func set_facing(f: Vector2i) -> void:
	var r := 0.36 * size
	_nose.position = Vector3(f.x * r, 0.04, f.y * r)


func set_selected(on: bool) -> void:
	_disc_mat.albedo_color = SELECTED_COLOR if on else _team_color


func fade_out() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), 0.25)
	tw.tween_callback(hide)


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
