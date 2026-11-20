class_name BattleGrid
extends RefCounted
## 地图快照：每格的高度和地形，开战时从 Go 引擎拿一次。只读。

var width: int = 1
var depth: int = 1
var _heights := PackedInt32Array()
var _terrain := PackedInt32Array()


static func from_dict(d: Dictionary) -> BattleGrid:
	var g := BattleGrid.new()
	g.width = int(d["w"])
	g.depth = int(d["d"])
	g._heights = PackedInt32Array(d["heights"] as Array)
	g._terrain = PackedInt32Array(d["terrain"] as Array)
	return g


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < depth


func height_at(c: Vector2i) -> int:
	return _heights[c.y * width + c.x]


func terrain_at(c: Vector2i) -> int:
	return _terrain[c.y * width + c.x]
