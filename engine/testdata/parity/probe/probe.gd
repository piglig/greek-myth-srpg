extends SceneTree
## 对拍探针：把 Godot 的随机数、排序、JSON 浮点格式原样导出，供 Go 测试逐位比较。
## godot --headless --path <prototype> --script <本文件> -- --out=<目录>


func _hex(x: float) -> String:
	return PackedFloat64Array([x]).to_byte_array().hex_encode()


func _init() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_rng(out.path_join("rng.txt"))
	_sort(out.path_join("sort.txt"))
	_floats(out.path_join("floats.txt"))
	quit(0)


func _rng(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for seed in [0, 1, 42, 123456789, -7, 9223372036854775807]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		f.store_line("seed %d" % seed)
		for i in 3000:
			match i % 5:
				0:
					f.store_line("randi %d" % rng.randi())
				1:
					f.store_line("randf %s" % _hex(rng.randf()))
				2:
					f.store_line("randf_range %s" % _hex(rng.randf_range(-0.3, 0.3)))
				3:
					f.store_line("randi_range %d" % rng.randi_range(-5, 17))
				4:
					f.store_line("mix %s" % _hex(12.25 + rng.randf_range(-0.3, 0.3)))
	f.close()


var _x := 12345

func _next() -> int:
	_x = (_x * 1103515245 + 12345) % 2147483648
	return _x


func _sort(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for round in 600:
		var n := _next() % 300
		if round < 40:
			n = round
		var spread := 1 + _next() % 40
		var arr: Array = []
		for i in n:
			arr.append({"score": float(_next() % spread) * 0.5, "i": i})
		arr.sort_custom(func(a, b): return a["score"] > b["score"])
		var ids := PackedStringArray()
		for e in arr:
			ids.append(str(e["i"]))
		f.store_line(" ".join(ids))
	f.close()


func _floats(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for den in [150, 110, 7, 3, 1000]:
		for num in den + 1:
			var v: float = float(num) / den
			f.store_line("%s %s" % [_hex(v), JSON.stringify(v)])
	for i in 2000:
		var v: float = float(_next()) / float(1 + _next() % 100000)
		f.store_line("%s %s" % [_hex(v), JSON.stringify(v)])
	f.close()
