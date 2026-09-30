extends "res://tests/test_case.gd"
## Сенсорное управление без игры: мёртвая зона стика, чувствительность, плавающий и неподвижный стик,
## схема «палец», палец уехал с кнопки спринта, пауза, двойной тап (и его выключение), размер кнопок,
## витрина настроек не принимает касаний.

const TouchControls = preload("res://scripts/ui/touch_controls.gd")


func before_each() -> void:
	use_temp_storage()
	Settings.set_value("touch_scheme", 0)
	Settings.set_value("stick_floating", true)
	Settings.set_value("double_tap_attack", true)
	Settings.set_value("left_handed", false)
	Settings.set_value("button_size", 1)
	Settings.set_value("turn_sensitivity", 1.0)


func _tc() -> TouchControls:
	var tc: TouchControls = add(TouchControls.new())
	tc.size = Vector2(1280, 720)
	tc.set_active(true)
	return tc


func _touch(tc: TouchControls, i: int, p: Vector2, down: bool, canceled := false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = p
	e.pressed = down
	e.canceled = canceled
	tc._on_touch(e)


func _drag(tc: TouchControls, i: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = p
	tc._on_drag(e)


func test_deadzone_ignores_a_trembling_thumb() -> void:
	var tc := _tc()
	_touch(tc, 0, Vector2(200, 500), true)
	_drag(tc, 0, Vector2(200 + TouchControls.STICK_R * 0.15, 500))
	assert_eq(tc.steer, Vector2.ZERO, "дрожь пальца в мёртвой зоне — змея не поворачивает")
	_drag(tc, 0, Vector2(200, 500 - TouchControls.STICK_R * 0.5))
	assert_near(tc.steer.angle(), -PI / 2.0, 0.01, "вверх — вверх")


func test_sensitivity_scales_steer() -> void:
	Settings.set_value("turn_sensitivity", 1.4)
	var tc := _tc()
	_touch(tc, 0, Vector2(200, 500), true)
	_drag(tc, 0, Vector2(260, 500))
	assert_near(tc.steer.length(), 1.4, 0.001, "чувствительность из настроек")


func test_floating_stick_follows_the_thumb_fixed_does_not() -> void:
	var tc := _tc()
	_touch(tc, 0, Vector2(300, 450), true)
	assert_eq(tc._stick_center, Vector2(300, 450), "плавающий стик — там, где коснулись")
	_drag(tc, 0, Vector2(300 + TouchControls.STICK_R * 3.0, 450))
	assert_near(tc._stick_center.distance_to(tc._stick_pos), TouchControls.STICK_R, 0.5, "и подтягивается за пальцем")
	_touch(tc, 0, Vector2(0, 0), false)
	Settings.set_value("stick_floating", false)
	_touch(tc, 1, Vector2(300, 450), true)
	assert_eq(tc._stick_center, tc._fixed_center(), "неподвижный — всегда на своём месте")


func test_stick_only_on_its_half() -> void:
	var tc := _tc()
	_touch(tc, 0, Vector2(900, 300), true)
	assert_eq(tc._stick_index, -1, "справа стик не ставится")
	Settings.set_value("left_handed", true)
	_touch(tc, 1, Vector2(900, 300), true)
	assert_eq(tc._stick_index, 1, "у левши — справа")


func test_finger_scheme_steers_toward_the_finger() -> void:
	Settings.set_value("touch_scheme", 1)
	var tc := _tc()
	tc.head_screen = Vector2(640, 360)
	_touch(tc, 0, Vector2(640, 100), true)
	assert_near(tc.steer.angle(), -PI / 2.0, 0.01, "змея ползёт к пальцу")
	_drag(tc, 0, Vector2(650, 365))
	assert_eq(tc.steer, Vector2.ZERO, "палец на голове — не дёргать")


func test_sliding_off_sprint_releases_it() -> void:
	var tc := _tc()
	_touch(tc, 3, tc.sprint_center(), true)
	assert_true(tc.sprint_held)
	_drag(tc, 3, tc.sprint_center() + Vector2(0, -tc._sprint_r() * 3.0))
	assert_false(tc.sprint_held, "палец уехал с кнопки — спринт отпущен")


func test_pause_button() -> void:
	var tc := _tc()
	tc.pause_rect = Rect2(1200, 10, 60, 60)
	var paused := [0]
	tc.pause_pressed.connect(func() -> void: paused[0] += 1)
	_touch(tc, 0, Vector2(1230, 40), true)
	assert_eq(paused[0], 1)
	assert_eq(tc._stick_index, -1, "касание паузы не ставит стик")


func test_double_tap_attacks_unless_disabled() -> void:
	var tc := _tc()
	var hits := [0]
	tc.attack_pressed.connect(func() -> void: hits[0] += 1)
	for i in 2:
		_touch(tc, i, Vector2(640, 300), true)
		tc._time += 0.05
		_touch(tc, i, Vector2(640, 300), false)
		tc._time += 0.1
	assert_eq(hits[0], 1, "двойной тап — атака")
	Settings.set_value("double_tap_attack", false)
	for i in 2:
		_touch(tc, 5 + i, Vector2(640, 300), true)
		tc._time += 0.05
		_touch(tc, 5 + i, Vector2(640, 300), false)
		tc._time += 0.1
	assert_eq(hits[0], 1, "выключено в настройках — не атакует")


func test_slow_taps_are_not_a_double_tap() -> void:
	var tc := _tc()
	var hits := [0]
	tc.attack_pressed.connect(func() -> void: hits[0] += 1)
	for i in 2:
		_touch(tc, i, Vector2(640, 300), true)
		tc._time += 0.05
		_touch(tc, i, Vector2(640, 300), false)
		tc._time += TouchControls.DOUBLE_TAP + 0.1
	assert_eq(hits[0], 0, "два тапа с паузой — не атака")


func test_button_size_scales_the_layout() -> void:
	var tc := _tc()
	Settings.set_value("button_size", 0)
	var small_r := tc._attack_r()
	Settings.set_value("button_size", 2)
	assert_gt(tc._attack_r(), small_r, "крупные кнопки")
	assert_lt(tc.attack_center().x, 1280.0 - 110.0, "крупные — дальше от края")


func test_release_all_drops_every_finger() -> void:
	var tc := _tc()
	_touch(tc, 0, Vector2(200, 500), true)
	_touch(tc, 1, tc.sprint_center(), true)
	tc.release_all()
	assert_eq(tc.steer, Vector2.ZERO)
	assert_false(tc.sprint_held, "свернули игру — ничего не залипло")


func test_preview_ignores_touches_and_animates() -> void:
	var tc := _tc()
	tc.start_preview()
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = tc.attack_center()
	var hits := [0]
	tc.attack_pressed.connect(func() -> void: hits[0] += 1)
	tc._input(ev)
	assert_eq(hits[0], 0, "витрина не принимает касаний")
	var p0 := tc._stick_pos
	tc._process(0.5)
	assert_ne(tc._stick_pos, p0, "стик на витрине ходит по кругу")
	await assert_draws(tc, "витрина кнопок")
