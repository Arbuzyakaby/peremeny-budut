extends "res://tests/test_case.gd"
## Вилки v7.0: виды и четыре приёма — выпад, залп зубцов, вертушка, прыжок-укол. Кто когда опасен
## и уязвим, телеграфы, снаряды-зубцы, отрастание зубцов.

const Fork = preload("res://scripts/entities/fork.gd")

const AREA := Rect2(24, 24, 1232, 672)
const DT := 1.0 / 60.0
const HEAD := Vector2(900, 360)


func before_each() -> void:
	use_temp_storage()


func _fork(kind := Fork.Kind.TABLE, aggr := 1.0) -> Fork:
	var f: Fork = add(Fork.new())
	f.setup(Vector2(400, 360), AREA, 1.0, aggr, 1.0, kind)
	f.rotation = 0.0
	f.spawn_k = 1.0
	return f


func _run_until(f: Fork, st: int, max_frames := 600, head := HEAD) -> bool:
	for i in max_frames:
		f.update(DT, head, true)
		if f.st == st:
			return true
	return false


func test_first_attack_is_lunge() -> void:
	var f := _fork()
	assert_eq(f.next_atk, Fork.Atk.LUNGE, "сначала — выпад, главная опасность вилки")
	assert_eq(f.st, Fork.St.ROAM)


func test_kinds_differ() -> void:
	var sizes := []
	for k in Fork.KINDS:
		var f := _fork(k)
		sizes.append(f.sz)
		assert_eq(f.kind, k)
	assert_true(sizes[Fork.Kind.PITCH] > sizes[Fork.Kind.TABLE], "вилы крупнее столовой")
	assert_true(sizes[Fork.Kind.DESSERT] < sizes[Fork.Kind.TABLE], "десертная мельче")
	assert_eq(Fork.KINDS[Fork.Kind.TABLE]["tines"], 4)
	assert_eq(Fork.KINDS[Fork.Kind.DESSERT]["tines"], 3)
	assert_eq(Fork.KINDS[Fork.Kind.PITCH]["tines"], 2)
	assert_len(Fork.ATTACK_NAMES, 4)


func test_roam_hurts_only_from_front() -> void:
	var f := _fork()
	for p in [Vector2(445, 360), Vector2(400, 390), Vector2(340, 360), Vector2(450, 365)]:
		assert_eq(f.hurts(p), f.hits_tines(p), "в покое опасны только зубцы: %s" % str(p))


func test_volley_fires_tines_and_goes_bald() -> void:
	var f := _fork()
	var shots := []
	f.attack.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "tines":
			shots.append(data))
	f.begin_attack(Fork.Atk.VOLLEY, HEAD)
	assert_eq(f.st, Fork.St.VOLLEY_AIM, "сначала телеграф-веер")
	assert_true(_run_until(f, Fork.St.BALD), "выстрелила")
	assert_len(shots, 1)
	assert_len(shots[0]["dirs"], 4, "у столовой вилки четыре зубца")
	assert_near(f.tines_k, 0.0, 0.001, "зубцы отстреляны")
	assert_false(f.hurts(Vector2(445, 360)), "беззубую можно бить в лоб")


func test_volley_extra_tine_on_hard() -> void:
	var f := _fork(Fork.Kind.DESSERT, 1.5)
	var n := [0]
	f.attack.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "tines":
			n[0] = (data["dirs"] as Array).size())
	f.begin_attack(Fork.Atk.VOLLEY, HEAD)
	_run_until(f, Fork.St.BALD)
	assert_eq(n[0], 4, "десертная (3) + лишний зубец на злой сложности")


func test_tines_regrow() -> void:
	var f := _fork()
	f.begin_attack(Fork.Atk.VOLLEY, HEAD)
	_run_until(f, Fork.St.BALD)
	for i in 240:
		f.update(DT, HEAD, false)
	assert_near(f.tines_k, 1.0, 0.01, "зубцы отросли")


func test_whirl_hurts_from_every_side() -> void:
	var f := _fork()
	f.begin_attack(Fork.Atk.WHIRL, HEAD)
	assert_true(_run_until(f, Fork.St.WHIRL, 120), "раскрутилась")
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var p: Vector2 = f.position + dir * 40.0
		assert_true(f.touches(p, 16.0), "задевает кругом")
		assert_true(f.hurts(p), "режет со всех сторон")


func test_whirl_ends_dizzy_and_vulnerable() -> void:
	var f := _fork()
	f.begin_attack(Fork.Atk.WHIRL, HEAD)
	assert_true(_run_until(f, Fork.St.DIZZY, 400), "закружилась")
	assert_true(f.is_vulnerable())
	assert_false(f.hurts(f.position + f.facing() * 45.0), "даже зубцы не ранят")


func test_pogo_untouchable_in_air_then_stuck() -> void:
	var f := _fork(Fork.Kind.PITCH)
	var landed := []
	f.attack.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "pogo":
			landed.append(data))
	f.begin_attack(Fork.Atk.POGO, Vector2(700, 360))
	f.update(DT, Vector2(700, 360), true)
	assert_true(f.in_air())
	assert_false(f.touches(f.position, 30.0), "в прыжке не достать")
	assert_true(_run_until(f, Fork.St.POGO_STUCK, 200, Vector2(700, 360)), "воткнулась")
	assert_len(landed, 1)
	assert_true((landed[0]["at"] as Vector2).distance_to(Vector2(700, 360)) < 40.0, "в круг-телеграф")
	assert_near(f.height, 0.0, 0.01)
	assert_true(f.is_vulnerable(), "застрявшая в полу беззащитна")


func test_whirl_needs_normal_difficulty() -> void:
	var easy := _fork(Fork.Kind.DESSERT, 0.6)
	var normal := _fork(Fork.Kind.DESSERT, 1.0)
	var easy_whirl := 0
	var normal_whirl := 0
	for i in 300:
		easy_whirl += int(easy.roll_attack() == Fork.Atk.WHIRL)
		normal_whirl += int(normal.roll_attack() == Fork.Atk.WHIRL)
	assert_eq(easy_whirl, 0, "на Лёгкой вертушки нет")
	assert_gt(normal_whirl, 0, "на Нормальной есть")


func test_attacking_flags_and_bounce_in_air() -> void:
	var f := _fork()
	assert_false(f.is_attacking())
	f.begin_attack(Fork.Atk.LUNGE, HEAD)
	assert_true(f.is_attacking())
	var g := _fork()
	g.begin_attack(Fork.Atk.POGO, HEAD)
	g.bounce()
	assert_eq(g.st, Fork.St.POGO_UP, "в прыжке отскок не сбивает")


func test_start_signal_reports_attack() -> void:
	var f := _fork()
	var started := []
	f.attack.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "start":
			started.append(data["atk"]))
	for a in 4:
		f.begin_attack(a, HEAD)
	assert_eq(started, [0, 1, 2, 3])
