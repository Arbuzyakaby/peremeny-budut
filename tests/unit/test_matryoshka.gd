extends "res://tests/test_case.gd"
## Матрёшка (v9.0) без игры: размеры, бегство, прыжок малышки с честным кольцом, окно после
## приземления, выход из скорлупки; места хоровода с просветом; пасхалки; маршрут этапов.

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


func test_tiny_jump_target_is_fixed_at_crouch() -> void:
	var m := _doll(Matryoshka.Size.TINY, Vector2(640, 360))
	m.attack_cd = 0.0
	m.update(1.0 / 60.0, Vector2(760, 360), Vector2.ZERO, true)
	assert_eq(m.st, Matryoshka.St.CROUCH, "малышка приседает перед прыжком")
	var target := m.jump_to
	assert_near(target.distance_to(Vector2(760, 360)), 0.0, 1.0, "целится в голову")
	for i in 20:  # змея ушла — кольцо на месте, прыжок туда же (честный телеграф)
		m.update(1.0 / 60.0, Vector2(900, 200), Vector2.ZERO, true)
	assert_eq(m.jump_to, target, "точка прыжка не догоняет змею")


func test_tiny_is_safe_in_air_and_edible_after_landing() -> void:
	var m := _doll(Matryoshka.Size.TINY)
	var landed := [false]
	m.landed.connect(func(_p: Vector2) -> void: landed[0] = true)
	m.crouch(Vector2(700, 360), Vector2.ZERO)
	var saw_air := false
	for i in 120:
		m.update(1.0 / 60.0, Vector2(900, 600), Vector2.ZERO, true)
		if m.in_air():
			saw_air = true
			assert_false(m.can_bite(), "в прыжке неуязвима")
		if landed[0]:
			break
	assert_true(saw_air, "прыгнула")
	assert_true(landed[0], "приземлилась")
	assert_true(m.is_dazed(), "переводит дух — окно")
	assert_true(m.can_bite(), "после приземления съедобна")
	assert_near(m.strike_progress(), 0.0, 0.001, "кольца больше нет")


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
		for st in [Matryoshka.St.ROAM, Matryoshka.St.CROUCH, Matryoshka.St.JUMP, Matryoshka.St.DAZED, Matryoshka.St.POP]:
			m.st = st
			m.st_t = 0.3
			m.queue_redraw()
		await frames(1)
	assert_true(true, "рисуется без ошибок")


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
