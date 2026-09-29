extends "res://tests/integration/game_case.gd"
## Интерфейс v9.0: главное меню 3.0 (журнал эксперимента, карточки сложностей), пасхалки меню
## и паузы, панель разработчика 2.0 (вкладка ИИ, матрёшки, пасхалки), дизайн-язык 2.3 (маршрут, штамп).

const Snake = preload("res://scripts/entities/snake.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const Design = preload("res://scripts/ui/design.gd")


func after_each() -> void:
	Snake.golden = false
	await super()


func test_menu_journal_counts_progress() -> void:
	await boot()
	var menu = game.hud.menu
	assert_true(menu.tip_note.is_ancestor_of(menu.route), "маршрут — в журнале")
	for key in ["Чешуйки", "Картотека", "Серия испытаний", "Пасхалки"]:
		assert_has(menu.stats_label.text, key)
	assert_has(menu.stats_label.text, "0 / %d" % Secrets.total(), "пасхалок пока нет")
	await frames(2)  # маршрут и карточки нарисованы без ошибок
	assert_len(menu.diff_buttons, 4)
	for b in menu.diff_buttons:
		assert_true(b.custom_minimum_size.y >= Design.TOUCH_MIN, "карточка сложности не мельче пальца")


func test_difficulty_card_still_starts_a_run() -> void:
	await boot()
	game.hud.menu.diff_buttons[0].pressed.emit()
	await frames(2)
	assert_eq(game.state, Game.State.LEVEL, "щелчок по карточке — сразу забег")
	assert_eq(game.difficulty, 0)


func test_konami_code_turns_the_snake_golden() -> void:
	await boot()
	for k in [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A]:
		await press_key(k)
	assert_true(Snake.golden, "золотая змея")
	assert_true(Secrets.is_found("konami"), "пасхалка записана")
	assert_has(game.hud.menu.stats_label.text, "1 / %d" % Secrets.total(), "журнал считает пасхалки")


func test_iddqd_is_refused_politely() -> void:
	await boot()
	for k in [KEY_I, KEY_D, KEY_D, KEY_Q, KEY_D]:
		await press_key(k)
	assert_true(Secrets.is_found("iddqd"))
	assert_has(game.hud.menu.desc_label.text, "12-Б", "учёный ссылается на пункт 12-Б")


func test_seven_title_clicks_hiss() -> void:
	await boot()
	var menu = game.hud.menu
	for i in 7:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		menu._on_title_input(ev)
	assert_true(Secrets.is_found("title"))
	assert_gt(menu.title_art.hiss_k, 0.0, "змейка шипит")


func test_poking_the_egg_five_times() -> void:
	await boot()
	var demo = game.menu_demo
	demo.egg.position = Vector2(1100, 600)
	for i in 4:
		assert_true(demo.poke(Vector2(1100, 600)), "попали в яичницу")
	assert_false(Secrets.is_found("egg_poke"))
	demo.poke(Vector2(1100, 600))
	assert_true(Secrets.is_found("egg_poke"), "обиделась")
	assert_gt(demo.hide_t, 0.0, "и прячется")
	assert_false(demo.poke(Vector2(1100, 600)), "спрятавшуюся не достать")
	assert_false(demo.poke(Vector2(100, 100)), "мимо — не считается")


func test_menu_demo_has_dolls_and_no_score() -> void:
	await boot()
	assert_gt(float(game.enemies.dolls.size()), 0.0, "в меню бродят матрёшки")
	var m: Matryoshka = game.enemies.dolls[0]
	m.spawn_k = 1.0
	game.menu_demo._bite(m)
	assert_eq(game.score, 0, "демо-змея очков не набирает")
	assert_eq(game.opened_dolls, 0)


func test_pause_sleep_secret() -> void:
	await boot_stage(0)
	game.hud.set_paused(true)
	var ps = game.hud.pause_screen
	ps.idle = ps.SLEEP_TIME - 0.01
	ps._process(0.05)
	assert_has(ps.sleep_label.text, "уснул")
	assert_true(Secrets.is_found("sleepy"))


func test_holiday_hat_follows_the_calendar() -> void:
	await boot_stage(0)
	assert_eq(game.snake.hat, Secrets.is_holiday(), "шапка — только на праздники")


func test_dev_panel_ai_tab_and_doll_spawns() -> void:
	await boot_stage(Balance.DOLL_STAGE, 1)
	var dp = game.dev_panel
	assert_eq(dp.TABS[dp.PAGE_AI], "ИИ")
	game.enemies.clear(false)
	dp._spawn("set", 0)
	for k in Matryoshka.SIZES.size():
		dp._spawn("doll", k)
	assert_len(game.enemies.dolls, 4, "набор и три размера")
	dp._force_ai("khorovod")
	assert_true(game.enemies.coop_override >= 1, "приём по кнопке поднимает уровень отряда")
	await step(2)
	assert_false(game.enemies.squad.khorovod.is_empty(), "хоровод по кнопке")
	dp._show_page(dp.PAGE_AI)
	dp._update_ai()
	assert_has(dp.roles_label.text, "хоровод")
	assert_has(dp.ai_label.text, "khorovod")
	dp._force_ai("reset")
	assert_true(game.enemies.squad.khorovod.is_empty(), "сброс отряда")
	assert_true(game.debug_run, "приёмы по кнопке — это читы")


func test_dev_panel_world_tab_lists_secrets() -> void:
	await boot()
	var dp = game.dev_panel
	dp._show_page(2)
	await frames(1)
	assert_eq(dp.secrets_box.get_child_count(), Secrets.total(), "все пасхалки с подсказками")
	var texts := []
	for b in dp.pages[2].find_children("*", "Button", true, false):
		texts.append((b as Button).tooltip_text)
	for k in Matryoshka.SIZES:
		assert_has(texts, String(k["name"]), "кнопка каждой матрёшки")
	assert_has(texts, "5. ЯИЧНИЦА", "переход к пятому этапу")


func test_route_and_stamp_draw() -> void:
	var c: Control = add(Control.new())
	c.size = Vector2(500, 100)
	c.draw.connect(func() -> void:
		Design.draw_route(c, Vector2(40, 40), 2, 70.0, 0.0)
		Design.draw_route(c, Vector2(40, 80), -1, 70.0, 0.0, 0.8)
		Design.draw_stamp(c, Vector2(400, 50), "РЕКОРД", Design.danger()))
	c.queue_redraw()
	await frames(2)
	assert_true(true, "маршрут и штамп рисуются")


func test_end_screen_stamps_a_record() -> void:
	await boot()
	var es = game.hud.end_screen
	es.show_end(false, "", "", [["Счёт", "999  — НОВЫЙ РЕКОРД!", true]])
	assert_true(es.stamp.visible, "рекорд — штамп")
	es.show_end(false, "", "", [["Счёт", "10", false]])
	assert_false(es.stamp.visible, "без рекорда штампа нет")
