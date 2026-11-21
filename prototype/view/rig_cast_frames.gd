extends CastFrames
## Draw baked poses while combat sockets still track projectiles, stones and captives.
var actor
var animal: bool
var travel := 0.
var last_position := Vector3.ZERO
var last_yaw := 0.
var breath_time := 0.
var hit_clock := 1.
var previous_recoil := 0.

func bind(unit,kind):
	actor=unit
	animal=unit is PaintedQuadruped
	setup(kind)
	if animal:
		actor.surface.hide()
	else:
		for surface in actor.surfaces: surface.hide()
		# Keep the live nocked arrow attached to the string until its flight begins.
		for part in actor.bow.limbs+actor.bow.strings: part.hide()
	last_position=actor.position
	last_yaw=actor.figure.rotation.y if animal else actor.model.rotation.y
	actor.add_child(NemeaField.shadow(actor.size*1.1,actor.size*.72))
	process_priority=5

func _process(dt: float):
	breath_time+=dt
	var root=actor.figure if animal else actor.model
	var angle=view_angle(root.rotation.y)
	var d=posmod(roundi(angle*8),8)
	position=root.position
	var turn=angle_difference(last_yaw,root.rotation.y)
	last_yaw=root.rotation.y
	if actor.walking:
		travel+=minf(.4,last_position.slide(Vector3.UP).distance_to(actor.position.slide(Vector3.UP)))
	last_position=actor.position
	set_instance_shader_parameter("reveal_region",actor._reveal_region)
	if animal:
		var magnitude: float=actor.recoil.length()
		if magnitude>.01 and previous_recoil<=.01: hit_clock=0.
		previous_recoil=magnitude
		hit_clock+=dt
		if actor.phase<1.:
			sample("strike",d,actor.phase)
			return
		if hit_clock<.40:
			sample("hit",d,hit_clock/.40)
			return
	else:
		if actor.hit_phase<1.:
			sample("heavy" if actor.heavy_hit else "hit",d,actor.hit_phase)
			return
		if actor is PaintedHeracles:
			if actor.released and actor.rock:
				sample("release",d,actor.recovery_time/2.)
				return
			if actor.rock:
				sample("push",d,actor.pressure)
				return
			if actor.clinch>.001:
				sample("hold",d,actor.clinch*.625+actor.squeeze*.375)
				return
			if actor.blow<1.:
				sample("club",d,actor.blow)
				return
			if bow_pose(d,actor.equip,actor.draw,actor.arrow_loose): return
		elif bow_pose(d,actor.aim,actor.draw,actor.released): return
	if actor.walking:
		var cycle_length: float=actor.gait_distance if not animal else (.98 if actor.boar else .68)
		display("walk",d,posmod(roundi(travel/cycle_length*32),32))
	elif absf(turn)>.0001:
		var sign_turn=1 if turn>0 else -1
		var tick=roundi(angle*64)*sign_turn
		display("turn_right" if turn>0 else "turn_left",posmod(floori(tick/8.)*sign_turn,8),posmod(tick,8))
	else:
		sample("idle",d,.5-.5*cos(breath_time*TAU/3.1))

func bow_pose(d,aim,draw,released):
	if aim<=.001: return false
	if aim<.995: sample("aim",d,aim)
	elif released: sample("loose",d,1.-draw)
	else: sample("draw",d,draw)
	return true
