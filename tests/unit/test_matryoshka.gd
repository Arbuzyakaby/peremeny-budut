extends "res://tests/test_case.gd"
## Матрёшка (v9.0) без игры: размеры, бегство, юла малышки (v12.4) с честной полосой и отскоком,
## окно после вращения, выход из скорлупки; места хоровода с просветом; пасхалки; маршрут этапов.

const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const Squad = preload("res://scripts/game/squad.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Design = preload("res://scripts/ui/design.gd")

const AREA := Rect2(24, 24, 1232, 672)


func before_each() -> void:
	use_temp_storage()


func _doll(size: int, pos := Vector2(640, 360)) -> Matryoshka:
	var m: Matryoshka = add(Matryoshka.new())
	m.setup(pos, AREA, size, 1.0, 1.0)
	m.spawn_k = 1.0
	return m


func test_sizes_grow_and_only_tiny_is_last() -> void:
	var r := []
	for s in Matryoshka.SIZES:
		r.append(float(s["radius"]))
	assert_true(r[0] < r[1] and r[1] < r[2], "малышка < средняя < большая")
	assert_true(_doll(Matryoshka.Size.TINY).is_last(), "малышка цельная — её едят")
	assert_false(_doll(Matryoshka.Size.MIDDLE).is_last())
	assert_false(_doll(Matryoshka.Size.BIG).is_last())
	assert_gt(float(Matryoshka.SIZES[1]["speed"]), float(Matryoshka.SIZES[2]["speed"]), "средняя шустрее большой")


func test_big_and_middle_run_away() -> void:
	for size in [Matryoshka.Size.BIG, Matryoshka.Size.MIDDLE]:
		var m := _doll(size, Vector2(640, 360))
		var head := Vector2(560, 360)
		var d0 := m.position.distance_to(head)
		for i in 60:
			m.update(1.0 / 60.0, head, Vector2.ZERO, true)
		assert_gt(m.position.distance_to(head), d0 + 10.0, "размер %d убегает от змеи" % size)


func test_tiny_spin_path_is_fixed_at_windup() -> void:
	var m := _doll(Matryoshka.Size.TINY, Vector2(640, 360))
	m.attack_cd = 0.0
	m.update(1.0 / 60.0, Vector2(760, 360), Vector2.ZERO, true)
	assert_eq(m.st, Matryoshka.St.CROUCH, "малышка раскручивается перед рывком")
	var path := m.spin_path
	assert_gt(path.size(), 1.0, "путь выбран сразу")
	var dir := (path[1] - path[0]).normalized()
	assert_near(dir.angle_to(Vector2.RIGHT), 0.0, 0.05, "целится в голову")
	assert_near(m.spin_len, Matryoshka.SPIN_REACH, 1.0, "и проносится дальше головы — на всю длину")
	for i in 20:  # змея ушла — полоса на месте (честный телеграф)
		m.update(1.0 / 60.0, Vector2(900, 200), Vector2.ZERO, true)
	assert_eq(m.spin_path, path, "путь юлы не догоняет змею")
	assert_gt(m.spin_angle, 0.0, "раскручивается на месте")


func test_tiny_spins_untouchable_then_totters_and_is_edible() -> void:
	var m := _doll(Matryoshka.Size.TINY)
	var stopped := [false]
	m.landed.connect(func(_p: Vector2) -> void: stopped[0] = true)
	m.crouch(Vector2(700, 360), Vector2.ZERO)
	var saw_spin := false
	var start := m.position
	for i in 120:
		m.update(1.0 / 60.0, Vector2(900, 600), Vector2.ZERO, true)
		if m.is_spinning():
			saw_spin = true
			assert_false(m.can_bite(), "пока крутится — не укусить")
			assert_eq(m.height, 0.0, "юла не прыгает — катится по полу")
		if stopped[0]:
			break
	assert_true(saw_spin, "крутилась")
	assert_true(stopped[0], "докрутилась")
	assert_near(m.position.distance_to(start), Matryoshka.SPIN_REACH, 2.0, "прошла весь путь")
	assert_true(m.is_dazed(), "шатается — окно")
	assert_true(m.can_bite(), "после — съедобна")
	assert_near(m.strike_progress(), 0.0, 0.001, "полосы больше нет")
	assert_gt(m.trail.size(), 0, "за ней осталась стружка")


func test_spin_path_bounces_off_the_wall() -> void:
	var inner := Rect2(0, 0, 1000, 600)
	var pts := Matryoshka.plan_path(Vector2(900, 300), Vector2.RIGHT, 300.0, inner)
	assert_len(pts, 3, "старт, бортик, конец после отскока")
	assert_near(pts[1].x, 1000.0, 0.01, "дошла до бортика")
	assert_near(pts[2].x, 1000.0 - 200.0, 0.01, "и откатилась назад на остаток пути")
	var straight := Matryoshka.plan_path(Vector2(100, 300), Vector2.RIGHT, 300.0, inner)
	assert_len(straight, 2, "до бортика далеко — прямая")
	var corner := Matryoshka.plan_path(Vector2(950, 550), Vector2(1, 1), 400.0, inner)
	assert_true(corner.size() <= 3, "в углу — не больше одного отскока")
	for p in corner:
		assert_true(inner.grow(0.5).has_point(p), "путь не выходит за поле")


func test_spin_touch_is_a_lane_not_a_landing_ring() -> void:
	var m := _doll(Matryoshka.Size.TINY, Vector2(300, 360))
	m.crouch(Vector2(700, 360), Vector2.ZERO)
	assert_false(m.spin_touches(Vector2(300, 360)), "на раскрутке не бьёт")
	m.st = Matryoshka.St.SPIN
	m.position = Vector2(400, 360)
	assert_true(m.spin_touches(Vector2(400, 360 + m.radius() + 5.0)), "задевает в пределах полосы")
	assert_false(m.spin_touches(Vector2(400, 360 + m.radius() + Matryoshka.SPIN_HIT + 5.0)), "вбок — мимо")


func test_pop_out_is_briefly_untouchable() -> void:
	var m := _doll(Matryoshka.Size.MIDDLE)
	m.pop_out(Vector2.RIGHT)
	assert_false(m.can_bite(), "вылетает из скорлупки — не укусить")
	for i in int(Matryoshka.POP_TIME * 60.0) + 30:
		m.update(1.0 / 60.0, Vector2(100, 100), Vector2.ZERO, true)
	assert_true(m.can_bite(), "выбралась — можно кусать")
	assert_gt(m.position.x, 640.0, "отлетела в свою сторону")


func test_daze_leaves_dance() -> void:
	var m := _doll(Matryoshka.Size.BIG)
	var mate := _doll(Matryoshka.Size.MIDDLE, Vector2(700, 360))
	m.dancing = true
	m.ribbon_to = mate
	m.order_pos = Vector2(600, 300)
	m.daze(1.0)
	assert_true(m.is_dazed())
	assert_false(m.dancing, "оглушённая бросает хоровод")
	assert_eq(m.ribbon_to, null)
	assert_eq(m.order_pos, Vector2.INF)


func test_doll_draws_every_state() -> void:
	for size in 3:
		var m := _doll(size)
		m.crouch(Vector2(800, 360), Vector2.ZERO)
		m.trail = [Vector2(600, 360), Vector2(620, 360)]
		for st in [Matryoshka.St.ROAM, Matryoshka.St.CROUCH, Matryoshka.St.SPIN, Matryoshka.St.DAZED, Matryoshka.St.POP]:
			m.st = st
			m.st_t = 0.3
			await assert_draws(m, "кукла %d в состоянии %d" % [size, st])


func test_khorovod_slots_keep_gap_ahead() -> void:
	for n in [3, 4, 5]:
		var heading := 0.7
		var slots := Squad.khorovod_slots(Vector2(640, 360), 200.0, heading, n)
		assert_len(slots, n)
		for p: Vector2 in slots:
			var off := absf(angle_difference(heading, (p - Vector2(640, 360)).angle()))
			assert_true(off >= Squad.KHOROVOD_GAP / 2.0 - 0.01, "по курсу змеи пусто (n=%d)" % n)
	assert_true(Squad.KHOROVOD_GAP >= deg_to_rad(120.0) - 0.01, "просвет не уже 120°")


func test_secrets_unlock_once_and_count() -> void:
	Secrets.reset()
	assert_eq(Secrets.found_count(), 0)
	assert_true(Secrets.unlock("konami"), "первая находка")
	assert_false(Secrets.unlock("konami"), "второй раз — не находка")
	assert_false(Secrets.unlock("нет-такой"), "неизвестная пасхалка")
	assert_eq(Secrets.found_count(), 1)
	Secrets._loaded = false  # перечитать с диска
	assert_true(Secrets.is_found("konami"), "сохранилась")
	assert_gt(Secrets.total(), 5.0, "пасхалок несколько")
	for e: Dictionary in Secrets.LIST:
		assert_true(String(e["hint"]).length() > 10, "у %s есть подсказка для панели" % e["id"])


func test_holiday_window() -> void:
	assert_true(Secrets.is_holiday({"year": 2026, "month": 12, "day": 31}))
	assert_true(Secrets.is_holiday({"year": 2027, "month": 1, "day": 7}))
	assert_false(Secrets.is_holiday({"year": 2027, "month": 1, "day": 8}))
	assert_false(Secrets.is_holiday({"year": 2026, "month": 9, "day": 28}))


func test_doll_stage_and_ability_in_balance() -> void:
	assert_eq(Balance.STAGE_COUNT, 5)
	assert_eq(Balance.BOSS_STAGE, 4, "яичница — последняя")
	assert_eq(Balance.STAGES[Balance.DOLL_STAGE]["key"], "dolls")
	for d: Dictionary in Balance.DIFFICULTIES:
		assert_true(int(d["dolls"]) >= 3, "наборов матрёшек хватает: " + String(d["name"]))
	assert_eq(Balance.ABILITIES[Balance.DOLL_ABILITY]["source"], "doll")
	assert_has(Design.SOURCE_COLORS, "doll", "у матрёшки свой цвет источника")
	assert_eq(Design.STAGE_ACCENTS.size(), Balance.STAGE_COUNT, "акцент у каждого этапа")


func test_khorovod_slots_are_evenly_spaced_around_the_gap() -> void:
	var slots := Squad.khorovod_slots(Vector2(0, 0), 100.0, 0.0, 5)
	for p in slots:
		assert_near(p.length(), 100.0, 0.01, "все на круге")
		assert_gt(absf(p.angle()), Squad.KHOROVOD_GAP / 2.0 - 0.01, "просвет по курсу свободен")
	for i in range(1, slots.size() - 1):
		var d1 := slots[i].distance_to(slots[i - 1])
		var d2 := slots[i].distance_to(slots[i + 1])
		assert_near(d1, d2, 0.5, "танцующие — на равных расстояниях")


func test_spread_and_guard_geometry() -> void:
	var slots := Squad.spread_slots(Vector2(640, 360), 0.3, 4, Rect2(0, 0, 1280, 720))
	assert_len(slots, 4)
	for i in 4:
		for j in range(i + 1, 4):
			assert_gt(slots[i].distance_to(slots[j]), 50.0, "разбегаются в разные стороны")
	var edge := Squad.spread_slots(Vector2(10, 10), 0.0, 3, Rect2(0, 0, 1280, 720))
	for p in edge:
		assert_true(Rect2(0, 0, 1280, 720).grow(-49.0).has_point(p), "в углу — всё равно на поле")
	var g := Squad.guard_point(Vector2(100, 100), Vector2(300, 100), 48.0)
	assert_eq(g, Vector2(148, 100), "заслон — между подопечной и змеёй")


func test_line_of_fire_cone() -> void:
	var head := Vector2.ZERO
	assert_true(Squad.in_line_of_fire(head, Vector2.RIGHT, Vector2(200, 5)), "прямо впереди — на линии")
	assert_false(Squad.in_line_of_fire(head, Vector2.RIGHT, Vector2(-200, 0)), "сзади — нет")
	assert_false(Squad.in_line_of_fire(head, Vector2.RIGHT, Vector2(200, 200)), "сбоку — нет")
	assert_false(Squad.in_line_of_fire(head, Vector2.RIGHT, Vector2(0.5, 0)), "вплотную — не считается")
	assert_eq(Squad.pincer_gap(2), PI, "две вилки — строго по бокам")
	assert_lt(Squad.pincer_gap(3), PI)
