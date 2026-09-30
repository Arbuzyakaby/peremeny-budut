extends "res://tests/test_case.gd"
## Правила яичницы без игры: какие атаки открываются по фазам, как манера змеи смещает выбор,
## атака не повторяется подряд, случайный выбор честен к весам; лужи масла (предел, в пределах
## сковороды, окно «пузыри → горит → гаснет»); когда её нельзя ранить; деления панели разработчика.

const Boss = preload("res://scripts/entities/fried_egg_boss.gd")


func _boss() -> Boss:
	var b: Boss = add(Boss.new())
	b.bounds = Rect2(24, 24, 1232, 672)
	b.configure(12, 1.0, 1.0, 1.0)
	b.position = Vector2(640, 360)
	b.active = true
	return b


func test_phases_unlock_attacks() -> void:
	var b := _boss()
	var p1 := b.attack_weights(1, "")
	assert_eq(p1.keys().size(), 3, "в первой фазе — кольцо, таран, веер")
	assert_false(p1.has(Boss.Atk.SLAM), "прыжка ещё нет")
	var p2 := b.attack_weights(2, "")
	for k in [Boss.Atk.SPIRAL, Boss.Atk.SLAM, Boss.Atk.SIZZLE]:
		assert_true(p2.has(k), "во второй фазе открылась атака %d" % k)
	assert_false(p2.has(Boss.Atk.PEPPER))
	assert_true(b.attack_weights(3, "").has(Boss.Atk.PEPPER), "перец — только в ярости")


func test_habits_shift_the_choice() -> void:
	var b := _boss()
	var base := b.attack_weights(3, "")
	var orbit := b.attack_weights(3, "orbit")
	assert_gt(orbit[Boss.Atk.CHARGE], base[Boss.Atk.CHARGE], "кружит — чаще таран наперерез")
	var far := b.attack_weights(3, "far")
	assert_gt(far[Boss.Atk.SLAM], base[Boss.Atk.SLAM], "далеко — прыгает")
	var close := b.attack_weights(3, "close")
	assert_gt(close[Boss.Atk.RING], base[Boss.Atk.RING], "липнет — отгоняет кольцом")
	assert_eq(close[Boss.Atk.AIMED], base[Boss.Atk.AIMED], "остальное не трогает")


func test_no_attack_twice_in_a_row() -> void:
	var b := _boss()
	b.last_attack = Boss.Atk.CHARGE
	assert_false(b.attack_weights(2, "orbit").has(Boss.Atk.CHARGE), "только что таранила — не повторяет")


func test_pick_follows_weights() -> void:
	var counts := {0: 0, 1: 0}
	for i in 2000:
		counts[Boss._pick({0: 1.0, 1: 3.0})] += 1
	assert_between(counts[1] / 2000.0, 0.7, 0.8, "вес 3 из 4 — три четверти выборов")
	assert_eq(Boss._pick({5: 1.0}), 5)


func test_habit_reading() -> void:
	var b := _boss()
	b.habit_dist = 500.0
	b.habit_orbit = 0.0
	assert_eq(b.habit(), "far")
	b.habit_dist = 150.0
	assert_eq(b.habit(), "close")
	b.habit_orbit = 1.5
	assert_eq(b.habit(), "orbit", "кружение важнее дистанции")
	b.habit_dist = 300.0
	b.habit_orbit = 0.0
	assert_eq(b.habit(), "", "ничего явного")


func test_prediction_stays_on_the_pan() -> void:
	var b := _boss()
	b.head_vel = Vector2(2000, 0)
	var p := b.predict(Vector2(1200, 300), 1.0)
	assert_true(b.bounds.has_point(p), "наперерез — но не за бортик")


func test_puddles_are_capped_and_kept_inside() -> void:
	var b := _boss()
	for i in Boss.PUDDLE_MAX + 4:
		b.add_puddle(Vector2(-500, 9999))
	assert_len(b.puddles, Boss.PUDDLE_MAX, "луж не больше предела")
	assert_eq(b.stats["puddles"], Boss.PUDDLE_MAX + 4, "но счётчик помнит все")
	for pd: Dictionary in b.puddles:
		assert_true(b.bounds.has_point(pd["pos"]), "лужа на дне сковороды")


func test_puddle_window_bubbles_burns_and_goes_out() -> void:
	assert_false(Boss.puddle_burning({"t": 0.0}), "сначала пузыри — не жжёт")
	assert_true(Boss.puddle_burning({"t": Boss.PUDDLE_TELL + 0.1}), "потом горит")
	assert_false(Boss.puddle_burning({"t": Boss.PUDDLE_TELL + Boss.PUDDLE_BURN + 0.1}), "потом гаснет")
	var b := _boss()
	b.add_puddle(Vector2(300, 300))
	b._update_puddles(Boss.PUDDLE_TELL + Boss.PUDDLE_BURN + 0.5, null)
	assert_len(b.puddles, 0, "погасшая лужа убирается")


func test_cannot_be_wounded_while_roaring_hit_airborne_or_dead() -> void:
	var b := _boss()
	b.act = Boss.Act.IDLE
	assert_true(b.take_chip(0.2), "в покое — пробивается")
	for act in [Boss.Act.ROAR, Boss.Act.HIT, Boss.Act.DEAD]:
		b.act = act
		assert_false(b.take_chip(1.0), "в состоянии %d не пробить" % act)
	b.act = Boss.Act.JUMP
	b.height = 100.0
	assert_false(b.take_chip(1.0), "в воздухе не достать")
	b.height = 0.0
	b.active = false
	b.act = Boss.Act.IDLE
	assert_false(b.take_chip(1.0), "до начала боя — тоже")


func test_chips_accumulate_into_a_bite() -> void:
	var b := _boss()
	b.act = Boss.Act.IDLE
	var hp := b.hp
	for i in 4:
		b.act = Boss.Act.IDLE
		b.take_chip(0.25)
	assert_eq(b.hp, hp - 1, "четыре четвертинки — одно деление")


func test_dev_panel_sets_hp_and_can_win() -> void:
	var b := _boss()
	var got := []
	b.bitten.connect(func(n: int) -> void: got.append(n))
	b.dev_set_hp(5)
	assert_eq(b.hp, 5)
	assert_eq(b.phase(), 2, "5 из 12 — подгорает")
	b.dev_set_hp(3)
	assert_eq(b.phase(), 3, "3 из 12 — ярость")
	assert_eq(b.phase_name(), "ПРИГОРЕЛА")
	b.dev_set_hp(99)
	assert_eq(b.hp, 12, "не больше максимума")
	var won := [false]
	b.defeated.connect(func() -> void: won[0] = true)
	b.dev_set_hp(0)
	assert_true(won[0], "ноль — победа")
	assert_eq(b.act, Boss.Act.DEAD)
	b.dev_set_hp(3)
	assert_eq(b.hp, 0, "побеждённую не воскресить")


func test_yolk_open_states() -> void:
	var b := _boss()
	for act in Boss.Act.values():
		b.act = act
		assert_eq(b.is_yolk_open(), act == Boss.Act.YOLK_OPEN or act == Boss.Act.DAZED, "желток в состоянии %d" % act)


func test_draws_in_every_act() -> void:
	var b := _boss()
	for act in Boss.Act.values():
		b.act = act
		b.act_t = 0.3
		await assert_draws(b, "яичница в состоянии %d" % act)
