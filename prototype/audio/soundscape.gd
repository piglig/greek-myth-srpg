extends Node

const SETTINGS := "user://sound.cfg"
const MUSIC := &"Music"
const EFFECTS := &"Effects"
const DIRECTORY := "res://audio/"
var levels := {MUSIC: 80, EFFECTS: 80}
var score_players: Array[AudioStreamPlayer] = []
var voices: Array[AudioStreamPlayer] = []
var tracks := {}
var sounds := {}
var last_take := {}
var variation := RandomNumberGenerator.new()
const COMBAT_CUES := ["bow_draw","arrow","arrow_hit","swing","spear_hit","shield_hit",
	"guard","break_guard","bite","wolf_breath","hit","step","splash","paw"]
var current := ""
var deck := 0
var next_voice := 0
var transition: Tween
var last_focus := -1000
var closing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	var prefs := ConfigFile.new()
	prefs.load(SETTINGS)
	for bus: StringName in levels:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		levels[bus] = clampi(int(prefs.get_value("volume", bus, 80)), 0, 100)
		_apply_volume(bus)
	for title in ["jar", "ridge"]:
		var track := load(DIRECTORY + title + ".ogg") as AudioStreamOggVorbis
		track.loop = true
		tracks[title] = track
	variation.randomize()
	for id in ["focus","confirm","warning","victory","defeat"] + COMBAT_CUES:
		var takes := [load(DIRECTORY + id + ".wav")]
		if id in COMBAT_CUES:
			for suffix in ["_2","_3"]:
				takes.append(load(DIRECTORY + id + suffix + ".wav"))
		sounds[id] = takes
	for i in 2:
		score_players.append(_player(MUSIC))
	for i in 8:
		voices.append(_player(EFFECTS))

func _player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player

func _apply_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(index, levels[bus] == 0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(.001, levels[bus] / 100.0)))

func cycle_volume(bus: StringName) -> Error:
	levels[bus] = (int(levels[bus]) + 20) % 120
	_apply_volume(bus)
	var file := ConfigFile.new()
	for key: StringName in levels:
		file.set_value("volume", key, levels[key])
	return file.save(SETTINGS)

func score(title: String) -> void:
	if current == title:
		return
	current = title
	if transition:
		transition.kill()
	var previous := score_players[deck]
	deck = 1 - deck
	var incoming := score_players[deck]
	incoming.stop()
	transition = create_tween().set_parallel()
	transition.tween_property(previous, "volume_db", -55.0, .48)
	if title != "":
		incoming.stream = tracks[title]
		incoming.volume_db = -38
		incoming.play()
		transition.tween_property(incoming, "volume_db", -7.0, .65)
	transition.chain().tween_callback(previous.stop)

func cue(id: String) -> void:
	if closing:
		return
	if id == "focus":
		var now := Time.get_ticks_msec()
		if now - last_focus < 85:
			return
		last_focus = now
	var player := voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	var takes: Array = sounds[id]
	var index := 0
	if takes.size() > 1:
		index = (int(last_take.get(id, -1)) + variation.randi_range(1,takes.size()-1)) % takes.size()
		last_take[id] = index
	player.stream = takes[index]
	player.volume_db = -2
	player.play()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

func quit_game() -> void:
	if closing:
		return
	closing = true
	# Let a same-frame confirmation reach the mixer before stopping its voice.
	await get_tree().create_timer(.06, true, false, true).timeout
	if transition:
		transition.kill()
	for player in score_players + voices:
		player.stop()
	# The mixer releases active stream playbacks on its next audio buffers.
	await get_tree().create_timer(.28, true, false, true).timeout
	get_tree().quit()
