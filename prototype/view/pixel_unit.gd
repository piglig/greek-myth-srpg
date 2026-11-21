class_name PixelUnit
extends UnitView
## Painted locomotion, weapon keys and eight camera-relative impact strips.
const FALL_SECONDS := {"wolf":.64,"bandit":.91,"bandit_archer":1.09,"bandit_chief":1.48,"centaur":1.24,"boar":.98,"lion":1.32,"hero":1.38,"atalanta":1.03,"heracles":1.52,"chiron":1.46,"refugee":1.22}
var falling := false
var fall_tween: Tween
var raider_throw_sheet: Texture2D
var in_raider_throw := false
var wrestle_sheet: Texture2D
var fall_sheet: Texture2D
var lion_exposed := false
var balance_sheet: Texture2D
var balance_motion: Tween
var evade_origin: Vector3
var kind: String
var reaction := Sprite3D.new()
var strips := {}
var intercept_pose := -1.0
var intercept_contact := false
var intercept_side := 0.0
var guarding := false
var raise_time := 0.0
var hit_phase := 1.0
var hit_seconds := .34
var hit_clip := "light"
var braced_light := false
var bash_clock := 1.0
var active_clip := ""
var active_view := 0
var bow_draw := -1.0
var clinch := 0.0
var clinch_reach := Vector3.ZERO
var holding: UnitView
var impact_side := 0.

func setup(u: UnitState, _tex: Texture2D, _motion: Texture2D) -> void:
	kind = u.def_id
	var folder := "res://art/pixel/%s/"%kind
	super.setup(u,load(folder+"actors.png"),load(folder+"motion.png"))
	if kind in ["centaur","chiron"]:
		var action := "spear.png" if kind=="centaur" else "bow.png"
		_sprite.material_override.set_shader_parameter("painted_action_sheet",load(folder+action))
	if kind in ["atalanta","bandit_chief","lion"]:
		balance_sheet=load(folder+("evade.png" if kind=="atalanta" else "break.png"))
	if kind in ["hero","bandit"]:
		raider_throw_sheet=load(folder+"throw.png")
	if kind=="lion":
		wrestle_sheet=load(folder+"wrestle.png")
	if kind in FALL_SECONDS:
		fall_sheet=load(folder+"fall.png")
	var clips := [] if kind=="medea" else ["light","heavy"]
	if kind=="hero": clips.append_array(["guard","block"])
	if kind=="heracles": clips.append_array(["push","hold","bow"])
	for clip in clips: strips[clip]=load(folder+clip+".png")
	reaction.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reaction.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	reaction.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reaction.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	reaction.shaded = false
	reaction.offset.y = 52 # Native tile baseline is 116 in a 128-pixel cell.
	if kind=="boar":
		_sprite.pixel_size*=1.35
	if kind=="hero":
		_sprite.pixel_size = .021
		_sprite.offset.y = 52
	reaction.pixel_size = _sprite.pixel_size
	var ink := ShaderMaterial.new()
	ink.shader=preload("res://view/pixel_reaction.gdshader")
	reaction.material_override=ink
	reaction.hide()
	add_child(reaction)

func receive_impact(force: Vector3, severity: float, source: String, blocked: bool):
	if kind=="medea":
		super.react_to_hit(force,severity)
		return
	var heavy := severity>=.24 or source in ["gore","pounce","club","fall"]
	hit_clip="heavy" if heavy else "light"
	if kind=="hero" and (guarding or blocked): hit_clip="block"
	braced_light=hit_clip=="block" and not heavy
	hit_seconds=.80 if heavy else .34
	hit_phase=0.
	if force.length_squared()>.001:
		var cam=get_viewport().get_camera_3d()
		if cam:
			impact_side=clampf(force.normalized().dot(cam.global_basis.x),-1.,1.)
	else: impact_side=0.

func react_to_hit(force: Vector3,severity: float):
	receive_impact(force,severity,"",false)

func _process(dt: float):
	super._process(dt)
	if falling or balance_motion!=null:
		return
	var cam=get_viewport().get_camera_3d()
	if not cam:return
	var f: Vector3=[Vector3.BACK,Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT][_direction]
	active_view=posmod(roundi(atan2(f.dot(cam.global_basis.x),f.dot(cam.global_basis.z.slide(Vector3.UP).normalized()))*4./PI),8)
	raise_time=move_toward(raise_time,float(guarding),dt/.30)
	hit_phase=minf(1.,hit_phase+dt/hit_seconds)
	bash_clock+=dt
	if is_instance_valid(holding):
		var toward := (holding.position-position).slide(Vector3.UP).normalized()
		clinch_reach=toward*.34+Vector3.DOWN*.09 if holding.size==2 else Vector3.ZERO
		holding.set_hold_offset(-toward*(.48 if holding.size==2 else .18)*clinch)
	if in_raider_throw:
		reaction.hide()
		_sprite.show()
		return
	reaction.position=_sprite.position+clinch_reach*clinch
	if lion_exposed:
		reaction.hide()
		_sprite.show()
		var breath := 32.+5.*(1.-cos(_time*4.))
		set_painted_action_frame(43.+12.*hit_phase if hit_phase<1. else breath)
		return
	if intercept_pose>=0.:
		_strip("block" if intercept_contact else "guard",intercept_pose)
		var stride := sin(PI*intercept_pose) if not intercept_contact else 0.
		reaction.material_override.set_shader_parameter("sidestep",intercept_side*stride)
	elif hit_phase<1.:
		if hit_clip!="block":
			reaction.position+=cam.global_basis.x*impact_side*(.065 if hit_clip=="heavy" else .025)*sin(PI*hit_phase)
		var phase:=hit_phase
		if braced_light:
			phase=.21*sin(PI*hit_phase)
		_strip(hit_clip,phase)
	elif kind=="hero" and clinch>.001:
		_strip("guard",clinch*.80)
	elif kind=="hero" and bash_clock<.56:
		_strip("guard",smoothstep(0.,.17,bash_clock)*(1.-smoothstep(.35,.56,bash_clock)))
	elif kind=="hero" and raise_time>0. and not walking and not _attacking and held_pose<0:
		_strip("guard",raise_time)
	elif kind=="heracles" and bow_draw>=0.:
		_strip("bow",bow_draw)
	elif kind=="heracles" and _push_weight>.001:
		_strip("push",_push_weight)
	elif kind=="heracles" and clinch>.001:
		_strip("hold",clinch)
	else:
		active_clip=""
		reaction.hide()
		_sprite.show()

func shield_contact() -> Vector3:
	# The bronze boss in each full-guard painting, measured in its native cell.
	var centers := [Vector2(98,65),Vector2(93,60),Vector2(91,60),Vector2(98,64),
		Vector2(98,64),Vector2(62,64),Vector2(68,60),Vector2(66,60)]
	var center: Vector2=centers[active_view]
	var camera := get_viewport().get_camera_3d().global_basis
	return reaction.global_position+(camera.x*(center.x-80.)+camera.y*(64.+reaction.offset.y-center.y))*reaction.pixel_size


func aim_covered_spear(frame: float, hero: PixelUnit) -> void:
	set_painted_action_frame(frame)
	var rear := _sprite.frame_coords.y==1
	# Registered spear point and shoulder at full reach in the 256px attack cell.
	var tip := Vector2(211,43) if rear else Vector2(38,57)
	var shoulder_x := 163. if rear else 91.
	var camera := get_viewport().get_camera_3d().global_basis
	var offset := hero.shield_contact()-_sprite.global_position
	var mirror := -1. if _sprite.flip_h else 1.
	var goal := Vector2(128.+mirror*offset.dot(camera.x)/(_sprite.pixel_size*_sprite.scale.x),
		64.+_sprite.offset.y-offset.dot(camera.y)/(_sprite.pixel_size*_sprite.scale.y))
	var blend := smoothstep(8.,21.,frame)*(1.-smoothstep(26.,38.,frame))
	var delta := (goal-tip)*blend
	_sprite.material_override.set_shader_parameter("parry_warp",Vector4(shoulder_x,tip.x,delta.x,delta.y))


func release_intercept() -> void:
	intercept_pose=-1.
	intercept_contact=false
	reaction.material_override.set_shader_parameter("sidestep",0.)


func _strip(clip: String,phase: float):
	if active_clip!=clip:
		active_clip=clip
		reaction.texture=strips[clip]
		reaction.material_override.set_shader_parameter("atlas",reaction.texture)
		reaction.hframes=reaction.texture.get_width()/160
		reaction.vframes=8
	reaction.frame_coords=Vector2i(roundi(clampf(phase,0.,1.)*(reaction.hframes-1)),active_view)
	_sprite.hide()
	reaction.show()

func set_reveal_region(rect: Rect2,screen_size: Vector2):
	super.set_reveal_region(rect,screen_size)
	if reaction.material_override:
		reaction.material_override.set_shader_parameter("region",_reveal_region)

func set_bow_tension(amount: float):
	if kind=="heracles":bow_draw=amount
	else:super.set_bow_tension(amount)

func lower_bow():
	super.lower_bow()
	bow_draw=-1.


func bow_grip(tension: float) -> Vector3:
	if kind not in ["bandit_archer","chiron"]:
		return super.bow_grip(tension)
	# Native 160x128 cells. The same hand is visible on opposite sides of the two drawings.
	var grip := Vector2(111,35) if _sprite.frame_coords.y == 1 else Vector2(49,41)
	if kind == "chiron":
		grip = Vector2(124,35) if _sprite.frame_coords.y == 1 else Vector2(31,41)
	var lateral := (grip.x-80.) * (-1. if _sprite.flip_h else 1.) * _sprite.scale.x
	var axes := get_viewport().get_camera_3d().global_basis
	return _sprite.global_position + (axes.x*lateral + axes.y*(64.+_sprite.offset.y-grip.y))*_sprite.pixel_size + axes.z*.02


func turn_to_strike(point: Vector3):
	if kind in ["bandit","bandit_archer","bandit_chief","centaur","chiron"]:
		await super.turn_to_strike(point)
		return
	face_point(point)
	var heading: Vector2i = [Vector2i.DOWN,Vector2i.RIGHT,Vector2i.UP,Vector2i.LEFT][_direction]
	await plant_and_turn(heading)


func set_painted_action_frame(frame: float) -> void:
	_sprite.material_override.set_shader_parameter("painted_action_key",roundf(frame))

func _start_balance_motion() -> Tween:
	hit_phase=1.
	active_clip=""
	reaction.hide()
	_sprite.show()
	_sprite.material_override.set_shader_parameter("painted_action_sheet",balance_sheet)
	set_painted_action_frame(0.)
	balance_motion=create_tween()
	return balance_motion


func _place_balance_shadow(offset: Vector3, height_fraction: float) -> void:
	var caster := get_node("Caster") as MeshInstance3D
	caster.scale.y=height_fraction
	caster.position=offset+Vector3.UP*(sprite_height*.49*height_fraction)
	var shadow := get_node("GroundShadow") as MeshInstance3D
	shadow.position=offset+Vector3.UP*.012


func begin_evade(source: UnitView) -> void:
	if kind!="atalanta" or balance_motion!=null or falling:
		return
	var right := get_viewport().get_camera_3d().global_basis.x.slide(Vector3.UP).normalized()
	var incoming := right if source==null else (position-source.position).slide(Vector3.UP).normalized()
	var lateral := incoming.cross(Vector3.UP)
	var painted_side := -1. if _sprite.flip_h != (_sprite.frame_coords.y==1) else 1.
	if lateral.dot(right)*painted_side<0.:
		lateral=-lateral
	evade_origin=_sprite.position
	var motion := _start_balance_motion()
	motion.tween_method(set_painted_action_frame,0.,24.,.23)
	var shift := lateral*.48+right*painted_side*20.*_sprite.pixel_size
	motion.parallel().tween_method(func(t: float): _place_balance_shadow(shift*t,1.-.13*t),0.,1.,.23)
	motion.parallel().tween_property(_sprite,"position",evade_origin+lateral*.48,.23).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func finish_evade() -> void:
	if balance_motion.is_running():
		await balance_motion.finished
	balance_motion=create_tween()
	balance_motion.tween_interval(.09)
	balance_motion.tween_method(set_painted_action_frame,24.,55.,.40)
	var shift := (get_node("GroundShadow") as Node3D).position.slide(Vector3.UP)
	balance_motion.parallel().tween_method(func(t: float): _place_balance_shadow(shift*t,1.-.13*t),1.,0.,.40)
	balance_motion.parallel().tween_property(_sprite,"position",evade_origin,.40).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await balance_motion.finished
	set_painted_action_frame(-1.)
	balance_motion=null


func set_lion_exposed(active: bool) -> void:
	if active==lion_exposed:
		return
	lion_exposed=active
	var ink := _sprite.material_override as ShaderMaterial
	if active:
		ink.set_shader_parameter("painted_action_sheet",balance_sheet)
		set_painted_action_frame(32.)
	elif ink.get_shader_parameter("painted_action_sheet")==balance_sheet:
		set_painted_action_frame(-1.)


func lose_balance() -> void:
	var motion := _start_balance_motion()
	if kind=="lion":
		motion.tween_method(set_painted_action_frame,0.,20.,.34)
		motion.tween_method(set_painted_action_frame,20.,32.,.37)
		await motion.finished
		balance_motion=null
		set_lion_exposed(true)
		return
	motion.tween_method(set_painted_action_frame,0.,29.,.41)
	motion.parallel().tween_method(func(h: float): _place_balance_shadow(Vector3.ZERO,h),1.,.70,.41)
	motion.tween_interval(.12)
	motion.tween_method(set_painted_action_frame,29.,55.,.50)
	motion.parallel().tween_method(func(h: float): _place_balance_shadow(Vector3.ZERO,h),.70,1.,.50)
	await motion.finished
	set_painted_action_frame(-1.)
	balance_motion=null


func set_raider_throw(frame: float) -> void:
	in_raider_throw=frame>=0. and not falling
	if falling:
		return
	_sprite.material_override.set_shader_parameter("painted_action_sheet",raider_throw_sheet)
	set_painted_action_frame(frame)
	if frame<0.:
		hit_phase=1.


func set_lion_wrestle(frame: float) -> void:
	if wrestle_sheet == null or falling:
		return
	set_lion_exposed(false)
	_sprite.material_override.set_shader_parameter("painted_action_sheet",wrestle_sheet)
	set_painted_action_frame(frame)


func start_fall(from_frame := 0.) -> void:
	if falling or fall_sheet == null:
		return
	var ink := _sprite.material_override as ShaderMaterial
	if from_frame==0. and wrestle_sheet!=null and ink.get_shader_parameter("painted_action_sheet")==wrestle_sheet:
		var frame=ink.get_shader_parameter("painted_action_key")
		if frame!=null and frame>=0.:
			from_frame=14.
	falling=true
	in_raider_throw=false
	reaction.hide()
	_sprite.show()
	_sprite.material_override.set_shader_parameter("painted_action_sheet",fall_sheet)
	set_painted_action_frame(from_frame)
	var duration: float=FALL_SECONDS[kind]
	fall_tween=create_tween()
	fall_tween.tween_method(set_painted_action_frame,from_frame,40.,duration*(40.-from_frame)/55.)
	fall_tween.tween_callback(get_node("Caster").hide)
	fall_tween.tween_method(set_painted_action_frame,40.,55.,duration*15./55.)
	fall_tween.tween_interval(.26)
	fall_tween.tween_callback(hide)


func finish_fall() -> void:
	if fall_sheet == null:
		fade_out()
		return
	start_fall()
	if fall_tween.is_running():
		await fall_tween.finished
