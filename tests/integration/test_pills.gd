extends "res://tests/integration/game_case.gd"
## Этап таблеток v12.4: шипучка (серия из трёх скачков, без волны, лужа в конце), шипящая лужа
## (замедляет, высыхает, не копится), веса видов по ходу этапа, аптечная лампа мигает на новую
## таблетку, бортик и пол аптеки рисуются.

const Pill = preload("res://scripts/entities/pill.gd")
const FizzPuddle = preload("res://scripts/entities/fizz_puddle.gd")
const EnemyDirector = preload("res://scripts/game/enemy_director.gd")
const Tex = preload("res://scripts/gfx/tex.gd")


func _fizz(at := Vector2(400, 360)) -> Pill:
	var p: Pill = add(Pill.new())
	p.setup(at, Rect2(0, 0, 1280, 720), 1.0, 1.0, Pill.Kind.FIZZ)
	p.spawn_k = 1.0
	return p


## Прогнать таблетку до конца серии: head — куда она целится.
func _run(p: Pill, head: Vector2, sec: float) -> void:
	var t := 0.0
	while t < sec:
		p.update(1.0 / 60.0, head, Vector2.ZERO, true)
		t += 1.0 / 60.0


func test_fizz_hops_three_times_then_rests() -> void:
	var p := _fizz()
	var lands := []
	var fizz := []
	p.landed.connect(func(pos: Vector2) -> void: lands.append(pos))
	p.fizzed.connect(func(pos: Vector2) -> void: fizz.append(pos))
	p.st_t = 0.0
	for i in 300:  # до конца серии
		p.update(1.0 / 60.0, Vector2(900, 360), Vector2.ZERO, true)
		if not fizz.is_empty():
			break
	assert_len(lands, 3, "серия из трёх скачков")
	assert_len(fizz, 1, "лужа — один раз, в конце серии")
	assert_eq(fizz[0], lands[2], "лужа там, где последний скачок")
	assert_eq(p.st, Pill.St.IDLE, "после серии отдыхает")
	assert_gt(p.st_t, 0.5, "и отдых долгий")
	for i in 2:
		assert_lt(lands[i].distance_to(lands[i + 1]), float(Pill.KINDS[2]["hop"]) + 1.0, "скачки короткие")
	assert_gt(lands[2].x, 400.0 + 200.0, "серия несёт её к змее")


func test_fizz_is_edible_between_hops_but_not_in_the_air() -> void:
	var p := _fizz()
	p.st_t = 0.0
	var seen_air := false
	var seen_ground_mid_chain := false
	for i in 120:
		p.update(1.0 / 60.0, Vector2(900, 360), Vector2.ZERO, true)
		if p.in_air():
			seen_air = true
			assert_false(p.is_edible(), "в воздухе не съесть")
		elif p.hops_left > 0 and p.st == Pill.St.CROUCH:
			seen_ground_mid_chain = true
			assert_true(p.is_edible(), "между скачками — можно, если успеть")
	assert_true(seen_air and seen_ground_mid_chain)


func test_other_pills_still_hop_once() -> void:
	for kind in [Pill.Kind.CAPSULE, Pill.Kind.TABLET]:
		var p: Pill = add(Pill.new())
		p.setup(Vector2(400, 360), Rect2(0, 0, 1280, 720), 1.0, 1.0, kind)
		p.spawn_k = 1.0
		p.st_t = 0.0
		var lands := [0]
		p.landed.connect(func(_pos: Vector2) -> void: lands[0] += 1)
		_run(p, Vector2(900, 360), 1.6)
		assert_eq(lands[0], 1, "вид %d прыгает по одному разу" % kind)
		assert_eq(p.chain(), 1)
		assert_true(p.last_hop)


func test_fizz_colors_and_look() -> void:
	var p := _fizz()
	assert_has(Pill.FIZZ_COLORS, p.cols, "палитра шипучек")
	assert_eq(p.bestiary_key(), "pill_2")
	for st in [Pill.St.IDLE, Pill.St.CROUCH, Pill.St.JUMP]:
		p.st = st
		p.air_time = 0.4
		p.st_t = 0.2
		await assert_draws(p, "шипучка в состоянии %d" % st)
	var look: Array = p._last_look.duplicate()
	p.st = Pill.St.IDLE
	p.squash = 0.0
	p.t += 0.2
	p.refresh_look()
	assert_ne(p._last_look, look, "пузырьки на шипучке живут и в покое")


# ---------------------------------------------------------------- лужа

func test_puddle_spreads_holds_and_dries() -> void:
	var d: FizzPuddle = add(FizzPuddle.new())
	d.setup(Vector2(300, 300), Color.ORANGE, Color.WHITE)
	assert_lt(d.radius(), FizzPuddle.RADIUS * 0.5, "сначала маленькая")
	d.update(0.3)
	assert_near(d.radius(), FizzPuddle.RADIUS, 0.5, "разлилась")
	assert_true(d.contains(Vector2(300 + FizzPuddle.RADIUS * 0.8, 300)))
	assert_false(d.contains(Vector2(300 + FizzPuddle.RADIUS * 1.2, 300)))
	await assert_draws(d, "лужа")
	d.update(FizzPuddle.LIFE - 0.3 - 0.4)
	assert_lt(d.radius(), FizzPuddle.RADIUS, "высыхает с краёв")
	d.update(1.0)
	assert_true(d.finished())
	assert_false(d.contains(Vector2(300, 300)), "высохла — не мешает")


func test_puddle_slows_the_snake_and_is_removed_when_dry() -> void:
	await boot_stage(2)
	var e = game.enemies
	e.clear(false)
	var p: Pill = e.spawn_pill(Vector2(640, 360), Pill.Kind.FIZZ)
	var d: FizzPuddle = e.spawn_puddle(Vector2(640, 360), p)
	assert_len(e.puddles, 1)
	d.update(0.3)
	game.snake.head_pos = Vector2(640, 360)
	game.snake.slow_timer = 0.0
	e.update_puddles(0.016, game.snake)
	assert_gt(game.snake.slow_timer, 0.0, "в пене змея вязнет")
	assert_eq(game.snake.slow_k, FizzPuddle.SLOW_K, "на 35 %, а не вдвое, как лента хоровода")
	game.snake.slow_timer = 0.0
	game.snake.head_pos = Vector2(100, 100)
	e.update_puddles(0.016, game.snake)
	assert_eq(game.snake.slow_timer, 0.0, "вне лужи — нет")
	e.update_puddles(FizzPuddle.LIFE, game.snake)
	assert_len(e.puddles, 0, "высохшая лужа убрана")
	assert_true(e.fizz_hinted, "подсказка про пену показана")


func test_puddles_are_capped_and_cleared() -> void:
	await boot_stage(2)
	var e = game.enemies
	var p: Pill = e.spawn_pill(Vector2(640, 360), Pill.Kind.FIZZ)
	for i in FizzPuddle.MAX_ON_FIELD + 3:
		e.spawn_puddle(Vector2(100 + i * 50, 300), p)
	assert_len(e.puddles, FizzPuddle.MAX_ON_FIELD, "старые лужи высыхают раньше")
	assert_eq(e.puddles[0].position.x, 100.0 + 3 * 50.0, "уходят самые старые")
	e.clear(false)
	assert_len(e.puddles, 0, "между этапами луж нет")


func test_fizz_landing_crushes_but_makes_no_wave() -> void:
	await boot_stage(2)
	var e = game.enemies
	e.clear(false)
	var p: Pill = e.spawn_pill(Vector2(640, 360), Pill.Kind.FIZZ)
	var waves_before: int = game.shots.waves.size()
	game.snake.head_pos = Vector2(900, 600)
	e._on_pill_landed(Vector2(640, 360), p)
	assert_eq(game.shots.waves.size(), waves_before, "у шипучки нет оглушающей волны")
	var cap: Pill = e.spawn_pill(Vector2(300, 300), Pill.Kind.CAPSULE)
	e._on_pill_landed(Vector2(300, 300), cap)
	assert_eq(game.shots.waves.size(), waves_before + 1, "а у капсулы есть")


func test_fizz_damage_has_its_own_cause() -> void:
	await boot_stage(2)
	var e = game.enemies
	e.clear(false)
	var p: Pill = e.spawn_pill(Vector2(640, 360), Pill.Kind.FIZZ)
	var s = game.snake
	s.head_pos = Vector2(640, 360)
	s.invuln = 0.0
	s.shield = 0
	s.lives = 3
	e._on_pill_landed(Vector2(640, 360), p)
	assert_eq(s.last_cause, "fizz", "причина — шипучка: свой совет и заголовок повтора")


# ---------------------------------------------------------------- веса видов

func test_fizz_appears_only_in_the_second_half_of_the_stage() -> void:
	for i in 100:
		assert_ne(EnemyDirector.pick_pill_kind(0.3, i / 100.0), Pill.Kind.FIZZ, "в начале этапа шипучек нет")
	var fizz := 0
	var tablets := 0
	for i in 100:
		var k := EnemyDirector.pick_pill_kind(1.0, i / 100.0)
		if k == Pill.Kind.FIZZ:
			fizz += 1
		elif k == Pill.Kind.TABLET:
			tablets += 1
	assert_eq(fizz, 25, "к концу этапа — четверть шипучек")
	assert_eq(tablets, 50, "и половина — шайбы")
	assert_eq(EnemyDirector.pick_pill_kind(0.0, 0.99), Pill.Kind.CAPSULE, "капсулы остаются")


# ---------------------------------------------------------------- аптека

func test_pharmacy_lamp_flickers_only_on_tiles() -> void:
	await boot_stage(2)
	var a = game.arena
	a.lamp = 0.0
	game.enemies.spawn_pill()
	assert_eq(a.lamp, 1.0, "новая таблетка — лампа мигнула")
	await assert_draws(a.lamp_node, "мигание")
	a._process(1.0)
	assert_eq(a.lamp, 0.0, "за секунду погасло")
	a.set_floor(Tex.Floor.WOOD)
	a.flicker()
	assert_eq(a.lamp, 0.0, "в детской лампа не мигает")


func test_pharmacy_frame_and_floor_draw() -> void:
	await boot_stage(2)
	var a = game.arena
	assert_eq(a.floor_kind, Tex.Floor.TILES)
	await assert_draws(a.frame, "бортик аптечного шкафа")
	await assert_draws(a.floor_decor, "пол аптеки")
