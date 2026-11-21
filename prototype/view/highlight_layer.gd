class_name HighlightLayer
extends Node3D
## Tile overlays drawn as stippled (alpha-scissor style) quads so they stay in the opaque pass
## and survive the pixel post-process. Each named group is replaced as a whole.

const SHADER := preload("res://view/highlight.gdshader")

var map_view: MapView
var _groups := {}
var _materials := {}
var _order := {}


## `layer` orders overlapping groups (higher draws above). `pattern` 0/1 picks the stipple phase;
## 2 = solid.
func show_cells(key: String, cells: Array, color: Color, layer: int = 0, pattern: int = 0,
		inset: float = 0.06) -> void:
	clear(key)
	if cells.is_empty():
		return
	var group := Node3D.new()
	add_child(group)
	_groups[key] = group
	if map_view.field != null:
		_drape(group,cells,_material(color,pattern,inset),layer)
		return
	var mat := _material(color, pattern)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0 - inset * 2.0, 1.0 - inset * 2.0)
	for c in cells:
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(c.x + 0.5, map_view.cell_top(c) + 0.012 + layer * 0.004, c.y + 0.5)
		group.add_child(mi)


func show_threat(key: String, cells: Array) -> void:
	clear(key)
	if cells.is_empty():
		return
	var region := {}
	for cell in cells:
		region[cell] = true
	var group := Node3D.new()
	add_child(group)
	_groups[key] = group
	var mat := _material(Color("#ba6d52"),3)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	for cell: Vector2i in region:
		var tile := MeshInstance3D.new()
		if map_view.field != null:
			tile.mesh = map_view.field.patch(cell)
			tile.position.y = 0.013
		else:
			tile.mesh = plane
			tile.position = Vector3(cell.x+.5,map_view.cell_top(cell)+.013,cell.y+.5)
		tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tile.material_override = mat
		var edges := 0
		for side in 4:
			if not region.has(cell+[Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN][side]):
				edges |= 1 << side
		tile.set_instance_shader_parameter("edges",edges)
		group.add_child(tile)


## A solid frame around one cell (hover cursor, knockback landing spot...).
func show_frame(key: String, cells: Array, color: Color, layer: int = 10) -> void:
	clear(key)
	if cells.is_empty():
		return
	var group := Node3D.new()
	add_child(group)
	_groups[key] = group
	if map_view.field != null:
		_drape(group,cells,_material(color,2,0.0,true),layer)
		return
	var mat := _material(color, 2)
	for c in cells:
		var y := map_view.cell_top(c) + 0.015 + layer * 0.004
		for side in 4:
			var bar := BoxMesh.new()
			var horizontal := side < 2
			bar.size = Vector3(1.0, 0.01, 0.07) if horizontal else Vector3(0.07, 0.01, 1.0)
			var mi := MeshInstance3D.new()
			mi.mesh = bar
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var off := Vector3(0, 0, -0.465) if side == 0 else Vector3(0, 0, 0.465) if side == 1 \
				else Vector3(-0.465, 0, 0) if side == 2 else Vector3(0.465, 0, 0)
			mi.position = Vector3(c.x + 0.5, y, c.y + 0.5) + off
			group.add_child(mi)


func _drape(group: Node3D, cells: Array, mat: ShaderMaterial, layer: int) -> void:
	for cell in cells:
		var mi := MeshInstance3D.new()
		mi.mesh = map_view.field.patch(cell)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = 0.015 + layer*0.004
		group.add_child(mi)


func clear(key: String) -> void:
	if _groups.has(key):
		(_groups[key] as Node).queue_free()
		_groups.erase(key)


func clear_all() -> void:
	for key in _groups.keys():
		clear(key)


func _material(color: Color, pattern: int, inset := 0.0, frame := false) -> ShaderMaterial:
	var key := "%s_%d_%s_%s" % [color.to_html(),pattern,inset,frame]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("pattern", pattern)
		m.set_shader_parameter("inset",inset)
		m.set_shader_parameter("frame",frame)
		_materials[key] = m
	return _materials[key]
