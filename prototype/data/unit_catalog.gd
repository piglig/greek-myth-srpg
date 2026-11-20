class_name UnitCatalog
extends RefCounted
## 单位定义（显示用），来自 Go 引擎读到的 units.json。

static var _units: Dictionary = {}


static func units() -> Dictionary:
	if _units.is_empty():
		_units = GoEngine.pairs(GoEngine.data().get("units", []))
	return _units


static func unit_def(def_id: String) -> Dictionary:
	return units().get(def_id, {"name": def_id})
