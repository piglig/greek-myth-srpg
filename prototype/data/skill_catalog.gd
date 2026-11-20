class_name SkillCatalog
extends RefCounted
## 技能定义（名字、射程等显示用的字段），来自 Go 引擎读到的 skills.json。

static var _skills: Dictionary = {}


static func _table() -> Dictionary:
	if _skills.is_empty():
		for item: Variant in (GoEngine.data().get("skills", []) as Array):
			var kv: Array = item
			var sk: Dictionary = kv[1]
			sk["id"] = kv[0]
			_skills[kv[0]] = sk
	return _skills


static func has_skill(id: String) -> bool:
	return _table().has(id)


static func get_skill(id: String) -> Dictionary:
	return _table().get(id, {"id": id, "name": id})


static func reload() -> void:
	_skills.clear()
