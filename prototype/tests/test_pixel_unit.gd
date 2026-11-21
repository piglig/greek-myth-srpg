extends GdUnitTestSuite

func test_hero_brace_and_unguarded_hits_select_separate_strips() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.current=true
	var hero := PixelUnit.new()
	add_child(hero)
	var u := UnitState.new()
	u.id="hero"
	u.def_id="hero"
	hero.setup(u,null,null)
	for d in 8:
		var yaw := -d*PI/4.
		camera.position=Vector3(sin(yaw)*10,8,cos(yaw)*10)
		camera.look_at(Vector3.ZERO)
		hero.set_facing(Vector2i.DOWN)
		hero.guarding=false
		hero.receive_impact(Vector3.LEFT,.05,"bite",false)
		hero._process(.09)
		assert_str(hero.active_clip).is_equal("light")
		assert_int(hero.reaction.frame_coords.y).is_equal(d)
		hero.receive_impact(Vector3.LEFT,.20,"gore",false)
		hero._process(.22)
		assert_str(hero.active_clip).is_equal("heavy")
		hero.guarding=true
		hero.receive_impact(Vector3.LEFT,.15,"gore",false)
		hero._process(.22)
		assert_str(hero.active_clip).is_equal("block")
		assert_int(hero.reaction.frame_coords.y).is_equal(d)
	hero.free()
	camera.free()
