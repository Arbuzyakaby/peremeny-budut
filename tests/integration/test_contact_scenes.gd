extends "res://tests/integration/game_case.gd"
## Сцены «Контакта» по отдельности (раньше их проходили только насквозь): рисунки на полу,
## фальшивое меню (ввод перехвачен, курсор сам едет к кнопке, мышь возвращается) и развязка в укрытии
## (камера отъезжает, пропуск завершает сцену ровно один раз).

const FloorPaint = preload("res://scripts/contact/floor_paint.gd")
const FakeMenu = preload("res://scripts/contact/fake_menu.gd")
const Hideout = preload("res://scripts/contact/hideout.gd")


# ---------------------------------------------------------------- рисунки на полу

func test_floor_paint_keeps_strokes_and_skips_tiny_steps() -> void:
	var p: FloorPaint = add(FloorPaint.new())
	p.extend(Vector2(10, 10))
	assert_len(p.strokes, 0, "без begin() точки некуда класть")
	p.begin(Color.RED)
	p.extend(Vector2(0, 0))
	p.extend(Vector2(1, 1))  # ближе 3 px — та же точка
	p.extend(Vector2(10, 0))
	var pts: PackedVector2Array = p.strokes[0]["pts"]
	assert_len(pts, 2, "мелкие шаги не раздувают рисунок")
	p.begin(Color.BLUE)
	p.extend(Vector2(50, 50))
	assert_len(p.strokes[0]["pts"], 2, "новый рисунок не трогает старый")
	assert_len(p.strokes[1]["pts"], 1)
	await assert_draws(p, "рисунки")


func test_floor_paint_is_capped_and_keeps_bullet_marks() -> void:
	var p: FloorPaint = add(FloorPaint.new())
	for i in FloorPaint.MAX_STROKES + 5:
		p.begin(Color(i / 50.0, 0.5, 0.5))
	assert_len(p.strokes, FloorPaint.MAX_STROKES, "старые рисунки стираются")
	assert_near(p.strokes[0]["color"].r, 5 / 50.0, 0.001, "первыми уходят самые старые")
	p.add_mark(Vector2(100, 100))
	p.add_mark(Vector2(120, 100))
	assert_len(p.marks, 2, "выбоины от пуль остаются")
	await assert_draws(p, "выбоины")


# ---------------------------------------------------------------- фальшивое меню

func test_fake_menu_clicks_by_itself_and_gives_the_mouse_back() -> void:
	await boot()
	var fm: FakeMenu = add(FakeMenu.new())
	var done := [0]
	fm.done.connect(func() -> void: done[0] += 1)
	fm.start(game)
	await frames(2)
	# (скрытие мыши и фокус без окна не проверить: в --headless курсора нет)
	assert_eq(fm.blocker.mouse_filter, Control.MOUSE_FILTER_STOP, "щелчки игрока перехвачены")
	assert_gt(fm.layer.layer, 50, "заслон поверх меню")
	assert_false(game.hud.menu.is_processing_input(), "коды меню не набираются")
	assert_true(is_instance_valid(game.hud.menu.glitch_button), "вместо карточек — одна кнопка")
	var start := fm.cursor
	Engine.time_scale = 6.0
	assert_true(await wait_until(func() -> bool: return fm.pressed > 0.0 or fm.typed > 0.0, 6.0), "курсор дошёл и нажал")
	assert_lt(fm.cursor.distance_to(fm._target()), start.distance_to(fm._target()), "курсор приблизился к кнопке")
	assert_true(await wait_until(func() -> bool: return done[0] > 0, 8.0), "сцена закончилась")
	Engine.time_scale = 1.0
	assert_eq(done[0], 1, "done ровно один раз")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "мышь вернули игроку")
	fm._done()
	assert_eq(done[0], 1, "повторный вызов ничего не шлёт")


func test_fake_menu_cursor_moves_in_an_arc() -> void:
	await boot()
	var fm: FakeMenu = add(FakeMenu.new())
	fm.start(game)
	await frames(2)
	var from := Vector2(1000, 650)
	var to := fm._target()
	fm._move_cursor(0.0, from)
	assert_near(fm.cursor.distance_to(from), 0.0, 0.5, "начало — там, где был курсор")
	fm._move_cursor(1.0, from)
	assert_near(fm.cursor.distance_to(to), 0.0, 0.5, "конец — на кнопке")
	fm._move_cursor(0.5, from)
	var straight := from.lerp(to, 0.5)
	assert_gt(fm.cursor.distance_to(straight), 40.0, "посередине курсор уходит с прямой — рука, а не линейка")
	fm.queue_free()
	await frames(1)
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "удалили сцену — мышь видна")


# ---------------------------------------------------------------- укрытие

## Подставной режим «Контакта»: укрытию нужны только счётчики убеждённых.
class _FakeContact extends RefCounted:
	var counts := {"bear": 3, "fork": 2, "pill": 4, "doll": 1}


func test_hideout_sets_up_the_room_and_zooms_out() -> void:
	await boot()
	var h: Hideout = add(Hideout.new())
	h.start(game, _FakeContact.new())
	assert_true(is_instance_valid(h.lab), "лаборатория на месте")
	assert_eq(h.lab.tally, [3, 2, 4, 1], "на столе учёного — счёт убеждённых")
	assert_eq(h.lab.sx, h.lab.STAND_X, "учёный уже стоит у стола")
	assert_len(h.snake_pts, 12, "змейка сбоку из 12 звеньев")
	var z0: Vector2 = game.camera.zoom
	await frames(30)
	assert_lt(game.camera.zoom.x, z0.x + 0.001, "камера отъезжает")
	await assert_draws(h.actors, "швея и змея сбоку")
	h.skip()


func test_hideout_skip_finishes_once() -> void:
	await boot()
	var h: Hideout = add(Hideout.new())
	var fin := [0]
	h.finished.connect(func() -> void: fin[0] += 1)
	h.start(game, _FakeContact.new())
	await frames(2)
	h.skip()
	h.skip()
	h._finish()
	assert_eq(fin[0], 1, "пропуск завершает сцену один раз")
	assert_true(h.done)


func test_hideout_actors_move_along_the_script() -> void:
	await boot()
	var h: Hideout = add(Hideout.new())
	h.start(game, _FakeContact.new())
	var bear0 := h.bear
	h._bear_jump(1.0)
	assert_gt(h.bear.y, bear0.y, "швея спрыгнула вниз со стола")
	assert_near(h.bear.y, Hideout.FLOOR - Hideout.BEAR_R, 30.0, "и стоит на полу")
	var head0 := h.snake_head
	h._snake_jump(1.0)
	assert_gt(h.snake_head.y, head0.y, "змея прыгнула следом")
	h._crawl(1.0)
	assert_ne(h.snake_head, head0, "и уползла в щель")
	h.skip()
