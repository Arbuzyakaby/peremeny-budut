extends "res://tests/test_case.gd"
## v12.2: доска-выход в «Контакте» ломается по-настоящему — нагрев, перелом, провис половин, щепа.

const PlankBreak = preload("res://scripts/contact/plank_break.gd")


func _plank(seed_value := 7) -> PlankBreak:
	var p := PlankBreak.new()
	p.seed_value = seed_value
	add(p)
	return p


func _run(p: PlankBreak, seconds: float) -> void:
	var n := int(seconds * 60.0)
	for i in n:
		p.update(1.0 / 60.0)


func test_intact_plank_sleeps() -> void:
	var p := _plank()
	assert_false(p.active(), "целая остывшая доска не перерисовывается")
	assert_false(p.is_broken())
	assert_near(p.gap_width(), 0.0, 1e-6, "щели нет")


func test_heat_wakes_the_plank_and_creaks() -> void:
	var p := _plank()
	var creaks := [0]
	p.sound.connect(func(n: String, _pitch: float, _vol: float) -> void:
		if n == "wood_creak":
			creaks[0] += 1)
	p.set_heat(0.6)
	assert_true(p.active(), "жар будит доску")
	_run(p, 4.0)
	assert_gt(creaks[0], 2, "дерево скрипит от жара")
	assert_false(p.is_broken(), "одним жаром доска не ломается — только по snap()")


func test_snap_opens_a_gap_and_throws_chips() -> void:
	var p := _plank()
	var sounds := []
	p.sound.connect(func(n: String, _pitch: float, _vol: float) -> void: sounds.append(n))
	p.set_heat(1.0)
	p.snap()
	assert_true(p.is_broken())
	assert_has(sounds, "wood_snap", "треск излома")
	var flying := 0
	for b: Dictionary in p.bits:
		if b["k"] in ["chip", "sliver", "nail"]:
			flying += 1
	assert_gt(flying, 15, "щепа и лучины летят")
	_run(p, 1.5)
	assert_gt(p.gap_width(), 60.0, "половины провисли — змея проходит (ширина щели %.1f)" % p.gap_width())
	assert_gt(PlankBreak.X1 - PlankBreak.X0, p.gap_width(), "щель не шире самой доски")


func test_halves_swing_bounce_and_settle() -> void:
	var p := _plank()
	p.snap()
	var peak := 0.0
	for i in 240:
		p.update(1.0 / 60.0)
		peak = maxf(peak, p.left_a)
		assert_between(p.left_a, 0.0, 1.0, "угол левой половины в пределах")
		assert_between(p.right_a, 0.0, 1.0, "угол правой половины в пределах")
	assert_near(p.left_a, p.left_max, 0.02, "левая осела на упоре")
	assert_near(p.right_a, p.right_max, 0.02, "правая осела на упоре")
	assert_near(p.left_av, 0.0, 0.05, "качание затухло")


func test_debris_lands_rests_and_the_plank_falls_asleep() -> void:
	var p := _plank(11)
	p.snap()
	_run(p, 6.0)
	for b: Dictionary in p.bits:
		assert_eq(b["k"] in ["chip", "sliver", "nail", "ember"], false, "ничего не висит в воздухе: " + str(b["k"]))
	assert_false(p.active(), "через 6 секунд доска снова спит — без перерисовки каждый кадр")
	assert_gt(PlankBreak.MAX_BITS + 1, p.bits.size(), "обломков не больше предела")


func test_debris_stays_within_the_cap() -> void:
	var p := _plank()
	p.snap()
	for i in 20:
		p._burst(30, 10, 1.0)
	assert_gt(PlankBreak.MAX_BITS + 1, p.bits.size(), "лимит обломков держится")


func test_profile_is_jagged_and_spans_the_plank() -> void:
	var p := _plank(3)
	assert_gt(p.profile.size(), 8, "рваная линия излома, а не прямая")
	var lo := INF
	var hi := -INF
	for pt in p.profile:
		lo = minf(lo, pt.y)
		hi = maxf(hi, pt.y)
		assert_between(pt.y, PlankBreak.X0 + 15.0, PlankBreak.X1 - 13.0, "излом внутри доски, не у гвоздей")
	assert_gt(hi - lo, 30.0, "есть длинные язычки щепы")
	assert_near(p.profile[0].x, -PlankBreak.HW, 1e-3, "линия начинается у одного края доски")
	assert_near(p.profile[p.profile.size() - 1].x, PlankBreak.HW, 1e-3, "и кончается у другого")


func test_geometry_is_deterministic_by_seed() -> void:
	var a := _plank(5)
	var b := _plank(5)
	var c := _plank(6)
	assert_eq(a.profile, b.profile, "один сид — один и тот же излом")
	assert_ne(a.profile, c.profile, "другой сид — другой излом")


func test_draws_without_errors_in_every_stage() -> void:
	var p := _plank()
	await frames(1)
	p.set_heat(0.3)
	_run(p, 0.5)
	await frames(1)
	p.set_heat(1.0)
	_run(p, 0.5)
	await frames(1)
	p.snap()
	for i in 90:
		p.update(1.0 / 60.0)
		if i % 15 == 0:
			await frames(1)
	assert_true(true, "все стадии нарисовались")
