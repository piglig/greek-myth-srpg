class_name MapView
extends Node3D
## The rule grid drives picking and anchors in both scenic and tactical views.

const CHAPTER_CELL_PITCH := 1.20
const LEVEL_HEIGHT := 0.75
const BASE_DEPTH := 0.5

const TERRAIN_COLORS := {
	Defs.Terrain.PLAIN: Color(0.47, 0.56, 0.38),
	Defs.Terrain.FOREST: Color(0.3, 0.44, 0.27),
	Defs.Terrain.SHALLOW: Color(0.36, 0.55, 0.68),
	Defs.Terrain.DEEP: Color(0.18, 0.3, 0.52),
	Defs.Terrain.SWAMP: Color(0.42, 0.45, 0.28),
	Defs.Terrain.BURNING: Color(0.85, 0.42, 0.18),
	Defs.Terrain.STYX: Color(0.34, 0.24, 0.45),
}

enum Wetland { NONE, LERNA, STYMPHALUS }
var wetland := Wetland.NONE
## Whether the wetland has a shrine on its far bank (the reed marsh does).
var shrine := false
var nemea := false
var village_sites := false
var woodland := false
var grid_lines := true
var field: NemeaField
var grid: BattleGrid
var tactical := false
var _materials := {}


func build(g: BattleGrid) -> void:
	grid = g
	for child in get_children():
		child.queue_free()
	field = null
	if (wetland != Wetland.NONE or nemea) and not tactical:
		if wetland == Wetland.NONE:
			field = NemeaField.new()
		else:
			var shore := preload("res://view/lerna_field.gd").new()
			shore.pale_lake = wetland == Wetland.STYMPHALUS
			shore.shrine = shrine
			field = shore
		field.grid_lines = grid_lines
		add_child(field)
		field.build(g, LEVEL_HEIGHT, village_sites, woodland)
		return
	for y in g.depth:
		for x in g.width:
			_add_column(Vector2i(x, y))


func set_tactical(on: bool) -> void:
	if on == tactical:
		return
	tactical = on
	build(grid)


func cell_top(c: Vector2i) -> float:
	return grid.height_at(c) * LEVEL_HEIGHT


## World position of a unit footprint's center on its standing height.
func anchor_world(state: BattleState, anchor: Vector2i, size: int) -> Vector3:
	var top := state.standing_height(anchor, size) * LEVEL_HEIGHT
	return to_global(Vector3(anchor.x + size * 0.5, top, anchor.y + size * 0.5))


## Cell whose column the ray hits first, or Defs.NO_POS.
func pick(origin: Vector3, dir: Vector3) -> Vector2i:
	origin = to_local(origin)
	dir = global_basis.inverse()*dir
	if field != null:
		var hit := field.picking_surface.intersect_ray(origin,dir)
		if hit.is_empty():
			return Defs.NO_POS
		var point: Vector3 = hit["position"]
		var cell := Vector2i(floori(point.x),floori(point.z))
		return cell if grid.in_bounds(cell) else Defs.NO_POS
	var best_t := INF
	var best := Defs.NO_POS
	for y in grid.depth:
		for x in grid.width:
			var c := Vector2i(x, y)
			var t := _ray_box(origin, dir, Vector3(x, -BASE_DEPTH, y), Vector3(x + 1, cell_top(c), y + 1))
			if t >= 0.0 and t < best_t:
				best_t = t
				best = c
	return best


func _add_column(c: Vector2i) -> void:
	var top := cell_top(c)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, top + BASE_DEPTH, 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(c.x + 0.5, (top - BASE_DEPTH) * 0.5, c.y + 0.5)
	mi.material_override = _material(c)
	add_child(mi)
	if grid.terrain_at(c) == Defs.Terrain.FOREST and not tactical:
		_add_tree(c, top)


func _add_tree(c: Vector2i, top: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.3
	cone.height = 0.75
	cone.radial_segments = 6
	var tree := MeshInstance3D.new()
	tree.mesh = cone
	# Offset toward the back corner so units standing in the cell stay visible.
	tree.position = Vector3(c.x + 0.28, top + 0.375, c.y + 0.28)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.32, 0.18)
	m.roughness = 1.0
	tree.material_override = m
	add_child(tree)


func _material(c: Vector2i) -> StandardMaterial3D:
	var h := grid.height_at(c)
	var t := grid.terrain_at(c)
	var checker := (c.x + c.y) % 2 == 0
	var key := "%d_%d_%s_%s" % [t, h, checker, tactical]
	if _materials.has(key):
		return _materials[key]
	var col: Color
	if tactical:
		col = Color(0.35, 0.35, 0.38).lightened(h * 0.11)
		if t != Defs.Terrain.PLAIN:
			col = col.lerp(TERRAIN_COLORS[t], 0.35)
	else:
		col = (TERRAIN_COLORS[t] as Color).lightened(h * 0.05)
	if checker:
		col = col.darkened(0.06)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	_materials[key] = m
	return m


static func _ray_box(o: Vector3, d: Vector3, bmin: Vector3, bmax: Vector3) -> float:
	var tmin := -INF
	var tmax := INF
	for i in 3:
		if absf(d[i]) < 0.00000001:
			if o[i] < bmin[i] or o[i] > bmax[i]:
				return -1.0
		else:
			var t1 := (bmin[i] - o[i]) / d[i]
			var t2 := (bmax[i] - o[i]) / d[i]
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
	if tmax < maxf(tmin, 0.0):
		return -1.0
	return tmin if tmin >= 0.0 else tmax
