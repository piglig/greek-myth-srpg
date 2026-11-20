class_name GoEngine
extends RefCounted
## 连接 Go 规则引擎（engine/bin/srpg.exe play）。规则只在 Go 里实现；这里只负责
## 拉起服务进程、收发消息、把 JSON 转成界面代码用的形状。
##
## 传输：127.0.0.1 上的 TCP，一问一答，每条消息 = 4 字节小端长度 + UTF-8 JSON。
## 服务进程只服务这一个连接：游戏退出、连接断开，它就自己结束。
##
## 命令行（`--` 之后）的 --data-dir=<目录> 和 --set=<表>:<键>=<值> 会原样交给引擎。
## 环境变量 SRPG_BIN 可以指定引擎程序的位置。

const PROTOCOL := 1
const BUILD_HINT := "请先构建规则引擎：在 engine/ 目录运行 build.bat（或 ./build.sh），生成 engine/bin/srpg.exe。"

static var error := ""  ## 最近一次失败的原因（给界面显示）
static var _pid := -1
static var _tcp: StreamPeerTCP
static var _data: Dictionary = {}


## 引擎程序的绝对路径。
static func binary_path() -> String:
	var env: String = OS.get_environment("SRPG_BIN")
	if env != "":
		return env
	var exe: String = "srpg.exe" if OS.get_name() == "Windows" else "srpg"
	return ProjectSettings.globalize_path("res://").path_join("../engine/bin").path_join(exe).simplify_path()


## 确保引擎已启动并连上。失败时返回 false，原因在 GoEngine.error。
static func ensure() -> bool:
	if _tcp != null:
		_tcp.poll()
		if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			return true
	_tcp = null
	_data = {}
	var exe: String = binary_path()
	if not FileAccess.file_exists(exe):
		return _fail("找不到规则引擎 %s。\n%s" % [exe, BUILD_HINT])
	# 端口由引擎挑，写进这个文件告诉我们
	var port_file: String = OS.get_cache_dir().path_join("srpg_port_%d_%d.txt" % [OS.get_process_id(), Time.get_ticks_usec()])
	var args: PackedStringArray = ["play", "-port", "0", "-port-file", port_file,
		"-tables", ProjectSettings.globalize_path("res://data/tables")]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-dir="):
			args.append_array(["-data-dir", arg.trim_prefix("--data-dir=")])
		elif arg.begins_with("--set="):
			args.append_array(["-set", arg.trim_prefix("--set=")])
	_pid = OS.create_process(exe, args)
	if _pid <= 0:
		return _fail("规则引擎启动失败：%s" % exe)
	var port: int = 0
	var deadline: int = Time.get_ticks_msec() + 10000
	while port == 0 and Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(port_file):
			port = int(FileAccess.get_file_as_string(port_file).strip_edges())
		if port == 0:
			if not OS.is_process_running(_pid):
				return _fail("规则引擎启动后立刻退出了（数据表有错？）。可以手动运行查看原因：\n%s play -tables %s" % [exe, args[6]])
			OS.delay_msec(5)
	DirAccess.remove_absolute(port_file)
	if port == 0:
		shutdown()
		return _fail("规则引擎没有在 10 秒内就绪。")
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host("127.0.0.1", port) != OK:
		shutdown()
		return _fail("连不上规则引擎（端口 %d）。" % port)
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		OS.delay_msec(2)
		tcp.poll()
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		shutdown()
		return _fail("连不上规则引擎（端口 %d）。" % port)
	tcp.set_no_delay(true)
	_tcp = tcp
	var hello: Dictionary = _exchange({"op": "data"})
	if hello.has("fail") or int(hello.get("protocol", 0)) != PROTOCOL:
		shutdown()
		return _fail("规则引擎的版本和游戏不匹配（%s）。%s" % [hello.get("fail", "协议版本不同"), BUILD_HINT])
	_data = hello
	error = ""
	return true


## 关掉引擎进程（退出游戏时调用；不调用也没关系，连接一断它就会自己结束）。
static func shutdown() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tcp = null
	_data = {}
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1


## 发一条请求并等应答。出错时返回 {"fail": 原因}。
static func request(req: Dictionary) -> Dictionary:
	if not ensure():
		return {"fail": error}
	return _exchange(req)


## 数据表里界面要用的部分（技能、单位、技能树、战斗列表），整场游戏只取一次。
static func data() -> Dictionary:
	if _data.is_empty():
		ensure()
	return _data


## 把请求里的 Vector2i 换成 [x, y]。
static func encode(v: Variant) -> Variant:
	if v is Vector2i:
		var c: Vector2i = v
		return [c.x, c.y]
	if v is Dictionary:
		var src: Dictionary = v
		var out: Dictionary = {}
		for k: Variant in src:
			out[k] = encode(src[k])
		return out
	if v is Array:
		var arr: Array = v
		var out_arr: Array = []
		for e: Variant in arr:
			out_arr.append(encode(e))
		return out_arr
	return v


## 应答里的 [x, y] -> Vector2i。
static func cell(v: Variant) -> Vector2i:
	var a: Array = v
	return Vector2i(int(a[0]), int(a[1]))


static func cells(v: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var arr: Array = v
	for e: Variant in arr:
		out.append(cell(e))
	return out


## [[键, 值], ...] -> 保持顺序的字典。
static func pairs(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	var arr: Array = v
	for e: Variant in arr:
		var kv: Array = e
		out[kv[0]] = kv[1]
	return out


static func _fail(msg: String) -> bool:
	error = msg
	push_error(msg)
	return false


static func _exchange(req: Dictionary) -> Dictionary:
	var body: PackedByteArray = JSON.stringify(encode(req)).to_utf8_buffer()
	_tcp.put_u32(body.size())
	if _tcp.put_data(body) != OK:
		return _lost()
	var head: Array = _tcp.get_data(4)
	if int(head[0]) != OK:
		return _lost()
	var head_bytes: PackedByteArray = head[1]
	var reply: Array = _tcp.get_data(head_bytes.decode_u32(0))
	if int(reply[0]) != OK:
		return _lost()
	var reply_bytes: PackedByteArray = reply[1]
	var parsed: Variant = _ints(JSON.parse_string(reply_bytes.get_string_from_utf8()))
	if not (parsed is Dictionary):
		return {"fail": "规则引擎的应答无法解析"}
	var out: Dictionary = parsed
	if out.has("fail"):
		error = str(out["fail"])
		push_error("规则引擎：%s（请求 %s）" % [error, req.get("op", "")])
	return out


static func _lost() -> Dictionary:
	_tcp = null
	_fail("和规则引擎的连接断了。")
	return {"fail": error}


## JSON 的数字都是浮点；整数值的换回 int（协议里的数量、坐标、编号都是整数）。
static func _ints(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if f == floorf(f) and absf(f) < 1e15:
			return int(f)
		return f
	if v is Dictionary:
		var d: Dictionary = v
		for k: Variant in d:
			d[k] = _ints(d[k])
		return d
	if v is Array:
		var a: Array = v
		for i in a.size():
			a[i] = _ints(a[i])
		return a
	return v
