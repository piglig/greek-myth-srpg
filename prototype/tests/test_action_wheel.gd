extends GdUnitTestSuite


func test_repeated_click_after_wheel_is_shifted_off_bottom_edge() -> void:
	var wheel := preload("res://ui/action_wheel.gd").new()
	add_child(wheel)
	var pointer := wheel.get_global_mouse_position()
	var bounds := Rect2(pointer-Vector2(200,220),Vector2(400,240))
	wheel.open([{}, {}, {}, {}],func(): return pointer,bounds,1.0)
	var point := pointer-wheel.global_position
	assert_int(wheel._sector_at(point)).is_equal(2)
	assert_int(wheel._pointed_sector(point)).is_equal(-1)
	assert_int(wheel._pointed_sector(point+Vector2(1,-1))).is_equal(-1)
	assert_int(wheel._pointed_sector(wheel.size*.5+Vector2.RIGHT*70)).is_equal(1)
	assert_int(wheel._pointed_sector(point)).is_equal(2)
	wheel.free()
