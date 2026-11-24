class_name BattleFX
extends Sprite3D
## One-shot, opaque pixel effects on the same world layer as combatants.

## Effects baked from pixelfx by art/tools/bake_pixelfx.py, with how long each one runs.
const KIT := "res://art/thirdparty/pixelfx/"
static var _seconds := {}


## How long a baked effect runs, from the list the bake writes beside the sheets.
static func kit_seconds(file: String) -> float:
	if _seconds.is_empty():
		var listed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KIT+"effects.json"))
		for effect: String in listed: _seconds[effect+".png"] = float(listed[effect].seconds)
	return float(_seconds.get(file,.5))


static func _sprite(parent: Node3D, effect: Texture2D) -> BattleFX:
	var fx := BattleFX.new()
	fx.texture = effect
	fx.hframes = effect.get_width()/effect.get_height()
	fx.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fx.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fx.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.pixel_size = 0.036
	if effect.resource_path.begins_with(KIT):
		# pixelfx sheets carry soft glow and smoke, so they blend instead of cutting out.
		fx.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		fx.pixel_size = 0.026
	parent.add_child(fx)
	return fx


static func spawn(parent: Node3D, effect: Texture2D, origin: Vector3, duration: float) -> Tween:
	var fx := _sprite(parent,effect)
	fx.position = origin
	if effect.resource_path.begins_with(KIT):
		duration = maxf(duration,kit_seconds(effect.resource_path.get_file()))
		# Lift the card toward the camera so its lower half is not buried in the ground.
		fx.position += parent.get_viewport().get_camera_3d().global_basis.z*effect.get_height()*fx.pixel_size*.5
	var animation := fx.create_tween()
	if fx.hframes > 1:
		animation.tween_property(fx, "frame", fx.hframes-1, duration)
	else:
		animation.tween_interval(duration)
	animation.tween_callback(fx.queue_free)
	return animation


## An effect that stays on someone and plays round and round until it is freed: the
## flame on the burning, the stars over the stunned. Smaller and fainter than the
## one-shots, so three of them on one person still leave the person in view.
static func aura(wearer: Node3D, effect: Texture2D, offset: Vector3, size := 1.0) -> BattleFX:
	var fx := _sprite(wearer,effect)
	fx.pixel_size = .021*size
	fx.modulate.a = .9
	fx.position = offset
	fx.render_priority = 1
	var round := fx.create_tween().set_loops()
	# Sheets from the kit say how long they run; ones drawn for the game play at ten a second.
	var kit := effect.resource_path.begins_with(KIT)
	round.tween_property(fx,"frame",fx.hframes-1,kit_seconds(effect.resource_path.get_file()) if kit else fx.hframes*.1).from(0)
	return fx


static func nock(parent: Node3D, arrow: Texture2D) -> BattleFX:
	var fx := _sprite(parent,arrow)
	fx.pixel_size = .014
	fx.offset.x = -27.
	fx.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	return fx


func align_to_grip(grip: Vector3, target: Vector3) -> void:
	var basis_camera := get_viewport().get_camera_3d().global_basis
	var delta := target-grip
	var axis := Vector2(delta.dot(basis_camera.x),delta.dot(basis_camera.y)).normalized()
	global_basis = basis_camera.rotated(basis_camera.z,axis.angle())
	# The same sprite remains on the string and in flight. Its origin is the
	# arrowhead, a short distance in front of the grip along the shot line.
	global_position = grip + global_basis.x*pixel_size*13.


func fly_to(target: Vector3, duration: float) -> Tween:
	var flight := create_tween()
	flight.tween_property(self,"global_position",target,duration)
	flight.tween_callback(queue_free)
	return flight


static func contact(parent: Node3D, skill: String, origin: Vector3, direction: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE*(.96 if skill=="shield_bash" else .73)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://view/contact_flash.gdshader")
	mat.set_shader_parameter("strike",["spear","shield_bash","bite","arrow"].find(skill))
	flash.mesh = quad
	flash.material_override = mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flash)
	var camera := parent.get_viewport().get_camera_3d().global_basis
	var angle := atan2(direction.dot(camera.y),direction.dot(camera.x))
	flash.global_basis = camera.rotated(camera.z,angle)
	flash.global_position = origin
	var tween := flash.create_tween()
	tween.tween_method(func(t: float): mat.set_shader_parameter("progress",t),0.,1.,.22 if skill=="shield_bash" else .15)
	tween.tween_callback(flash.queue_free)
