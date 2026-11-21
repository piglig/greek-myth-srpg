extends Node3D
## The arch sits behind the exit tile so an emerging unit can stand in front of it.

const ARCH := preload("res://art/landmarks/cave.glb")
const ROCK := preload("res://art/landmarks/boulder.glb")
var warning := Timer.new()


func _ready() -> void:
	var arch := NemeaField.landmark(ARCH, 2.6)
	arch.position.z = -.83
	add_child(arch)
	for side: float in [-1.,1.]:
		var shoulder := NemeaField.landmark(ROCK,1.32)
		shoulder.scale *= Vector3(1.65,.9,1.28)
		shoulder.position = Vector3(side*1.11,.03,-1.02)
		shoulder.rotation.y = side*.8
		add_child(shoulder)
	warning.wait_time = 1.65
	warning.timeout.connect(shed_stones)
	add_child(warning)


func set_warning(active: bool) -> void:
	if active and warning.is_stopped():
		shed_stones()
		warning.start()
	elif not active:
		warning.stop()


func shed_stones() -> void:
	for i in 5:
		var chip := NemeaField.landmark(ROCK, .22 + .062 * (i % 3))
		add_child(chip)
		var side := -1.0 if i % 2 == 0 else 1.0
		var start := Vector3(side * (.40 + .09 * i), 1.16 - .08 * i, -.52)
		var foot := Vector3(start.x + side * .11, .035, -.25 + .04 * i)
		chip.position = start
		var fall := chip.create_tween()
		fall.tween_interval(.045 * i)
		fall.tween_property(chip, "position", foot, .26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.parallel().tween_property(chip, "rotation:z", side * 1.8, .26)
		fall.tween_property(chip, "position", foot + Vector3(side * .11,.12,.12), .1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		fall.tween_property(chip, "position", foot + Vector3(side * .19,-.05,.24), .15)
		fall.tween_property(chip, "scale", Vector3.ONE * .001, .24)
		fall.tween_callback(chip.queue_free)
