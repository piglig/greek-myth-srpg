class_name PaintedAtalanta
extends ValleyHero

var draw := 0.
var aim := 0.
var bow := PaintedBow.new()
var shooting := false
var released := false
var shot_point := Vector3.ZERO


func setup(u: UnitState, _tex: Texture2D, _motion: Texture2D) -> void:
	_setup_figure(u,preload("res://art/original/atalanta.glb"),preload("res://art/original/atalanta_pigments.png"),1.05)
	skeleton.add_child(bow)
	bow.build()


func _sidestep() -> float:
	var local := hit_direction.rotated(Vector3.UP,-model.rotation.y)
	return -1. if local.x < -.02 else 1.


func _stance(index: int) -> Vector3:
	var side := _sidestep()
	var outer := (index==0)==(side>0.)
	var width := .17 if heavy_hit else .043
	var offset := Vector3(side*width,.0,-width*.48)*_cover()*(1. if outer else .18)
	return super(index)+offset.rotated(Vector3.UP,model.rotation.y)


func _effort_offset() -> Vector3:
	var shift := _cover()*(1. if heavy_hit else .38)
	return Vector3(_sidestep()*.116*shift,-.082*shift-.065*knee_bend,-.075*shift)


func _pose_arms(swing: float, _load: float, _drive: float) -> void:
	# Open the left shoulder toward the target; keep the eyes on the shot.
	var chest := skeleton.get_bone_pose_rotation(joints.Chest)
	var protect := _cover()*(1.-aim)
	var recoil := protect*(1. if heavy_hit else .56)
	var twist := Quaternion(Vector3.UP,-1.12*aim+_sidestep()*.79*recoil)
	skeleton.set_bone_pose_rotation(joints.Chest,chest*twist)
	skeleton.set_bone_pose_rotation(joints.Head,twist.inverse()*skeleton.get_bone_pose_rotation(joints.Head))
	var grip := Vector3(.245,.92+.035*swing,.19-.08*swing)
	var forward := Vector3.BACK
	if is_instance_valid(_bow_target):
		forward = (skeleton.to_local(shot_point)-Vector3(.03,1.35,.48)).normalized()
	var aimed := Vector3(.046,1.39,0.)+forward*.535
	grip = grip.lerp(aimed,aim)
	grip = grip.lerp(Vector3(.17+_sidestep()*.15,1.13,.17),recoil)
	var rest_hand := Vector3(-.235,.92-.04*swing,.14+.085*swing)
	var anchor := grip-forward*(.23+.31*draw)
	if released:
		var full_draw := aimed-forward*.54
		anchor = full_draw.lerp(Vector3(-.10,1.41,-.15),smoothstep(0.,.62,1.-draw))
	var pull := rest_hand.lerp(anchor,aim)
	pull = pull.lerp(grip+Vector3(-.20,.13,.057),recoil)
	var left := _reach("L",grip,Vector3(.85,-.65,.12))
	var right := _reach("R",pull,Vector3(-.76,-.28,-.50))
	var vertical := Vector3.UP.slide(forward).normalized().rotated(forward,.36*(1.-aim)+.12+.68*recoil)
	var center_string := left-forward*(.20+.095*draw)
	if shooting and not released:
		center_string = center_string.lerp(right,aim)
	bow.pose(left,vertical,forward,center_string,draw)


func raise_bow(target: Node3D) -> void:
	_bow_target = target
	await turn_to_strike(target.position)
	released = false
	shooting = true
	var raise := create_tween()
	raise.tween_property(self,"aim",1.,.23).set_trans(Tween.TRANS_SINE)
	await raise.finished


func set_bow_tension(amount: float) -> void:
	draw = amount


func show_live_arrow() -> void:
	bow.nock()


func release_arrow(target: Vector3, seconds: float) -> Tween:
	released = true
	return bow.loose(get_parent(),target,seconds)


func lower_bow() -> void:
	var lower := create_tween()
	lower.tween_property(self,"aim",0.,.18).set_trans(Tween.TRANS_SINE)
	await lower.finished
	shooting = false
	released = false
	_bow_target = null


func set_nearby_stone(_offset: Vector2) -> void:
	pass
