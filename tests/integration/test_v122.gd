extends "res://tests/integration/game_case.gd"
## v12.2: доска-выход ломается по-настоящему (нагрев → перелом → щепа), «Вакханалия» в фоне меню
## (события, драки, вилки, таблетки, комбо, хоровод), новые возможности панели разработчика.

const ContactMode = preload("res://scripts/contact/contact_mode.gd")
const MenuDemo = preload("res://scripts/game/menu_demo.gd")
const PlankBreak = preload("res://scripts/contact/plank_break.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")


func _sim(seconds: float) -> void:
	for i in int(seconds * 60.0):
		game._process(1.0 / 60.0)
		if i % 30 == 0:
			await tree.process_frame


# ---------------------------------------------------------------- доска в финале «Контакта»

func test_finale_plank_heats_then_snaps_on_cue() -> void:
	await boot()
	game.debug_run = true
	game.start_contact()
	await frames(2)
	var c: ContactMode = game.contact
	c.debug_skip_to_finale()
	assert_true(await wait_until(func() -> bool: return c.phase == ContactMode.Phase.FINALE, 8.0), "финал начался")
	var f = c.finale
	assert_true(f.plank != null, "доска в финале есть")
	assert_false(f.plank.is_broken(), "пока не горит — цела")
	f.debug_crack()
	assert_true(f.plank.is_broken(), "по сигналу треснула")
	assert_gt(f.exit_open, 0.0, "выход открывается")
	for i in 90:
		f.plank.update(1.0 / 60.0)
	assert_gt(f.plank.gap_width(), 60.0, "щель достаточно широка для змеи")
	var before: int = f.plank.bits.size()
	f.debug_crack()
	assert_eq(f.plank.bits.size(), before, "второй раз доска не ломается")


func test_plank_sounds_exist_in_the_bank() -> void:
	var Sfx = load("res://scripts/audio/sfx.gd")
	Sfx.build_now()
	for n in ["wood_creak", "wood_snap", "splinter"]:
		assert_true(Sfx.sounds.has(n), n + " есть в банке звуков")


# ---------------------------------------------------------------- вакханалия в меню

func test_demo_runs_every_event_within_caps() -> void:
	await boot()
	var demo: MenuDemo = game.menu_demo
	for id in MenuDemo.EVENTS:
		assert_true(demo.run_event(id), "событие " + id)
		for i in 240:
			demo.update(1.0 / 60.0)
		assert_true(game.enemies.bears.size() <= MenuDemo.MAX_BEARS, "медведей не больше предела после " + id)
		assert_true(game.enemies.forks.size() <= MenuDemo.MAX_FORKS, "вилок не больше предела после " + id)
		assert_true(game.enemies.pills.size() <= MenuDemo.MAX_PILLS, "таблеток не больше предела после " + id)
		assert_true(game.enemies.dolls.size() <= MenuDemo.MAX_DOLLS, "матрёшек не больше предела после " + id)
		assert_true(game.shots.drops.size() <= MenuDemo.MAX_DROPS, "снарядов не больше предела после " + id)
	assert_true(demo.events_run >= MenuDemo.EVENTS.size(), "все события сыграны (сверх — по таймеру)")
	assert_false(demo.run_event("нет_такого"), "неизвестное событие отвергается")
	assert_eq(game.score, 0, "вакханалия очков не даёт")
	assert_eq(game.opened_dolls, 0)


func test_demo_soak_two_minutes_stays_alive() -> void:
	await boot()
	var demo: MenuDemo = game.menu_demo
	for i in 7200:  # две минуты демо: события идут сами по таймеру
		demo.update(1.0 / 60.0)
		if i % 600 == 0:
			await tree.process_frame
	assert_gt(demo.events_run, 8, "за две минуты сыграно больше восьми событий")
	assert_gt(demo.eaten, 5, "змея ела и ломала")
	assert_true(is_instance_valid(demo.snake) and is_instance_valid(demo.egg))
	assert_true(game.enemies.bears.size() >= 1, "поле не опустело")
	for b: TeddyBear in game.enemies.bears:
		assert_true(is_instance_valid(b) and not b.position.is_zero_approx(), "медведи целы")
		assert_true(is_finite(b.position.x) and is_finite(b.position.y), "и с нормальными координатами")


func test_demo_combo_counts_and_expires() -> void:
	await boot()
	var demo: MenuDemo = game.menu_demo
	for i in 4:
		demo._score_bite()
	assert_true(demo.combo >= 4, "четыре укуса подряд — комбо")
	demo.combo_t = 0.01
	demo.update(0.05)
	assert_eq(demo.combo, 0, "без укусов комбо сгорает")
	assert_true(demo.best_combo >= 4, "лучшее — помнится")


func test_demo_bites_pills_and_breaks_forks() -> void:
	await boot()
	var demo: MenuDemo = game.menu_demo
	game.enemies.forks.clear()
	game.enemies.pills.clear()
	var f: Fork = demo._add_fork(Vector2(800, 300))
	var p: Pill = demo._add_pill(Vector2(900, 400))
	var eaten: int = demo.eaten
	demo._bite(p)
	assert_false(game.enemies.pills.has(p), "таблетку съели")
	demo._bite(f)
	assert_false(game.enemies.forks.has(f), "вилку сломали")
	assert_eq(demo.eaten, eaten + 2)
	assert_eq(game.score, 0)


func test_demo_peace_choir_follows_then_disbands() -> void:
	await boot()
	var demo: MenuDemo = game.menu_demo
	assert_true(demo.run_event("peace"))
	assert_gt(demo.peace.size(), 0, "хоровод собрался")
	for i in int(9.0 * 60.0):
		demo.update(1.0 / 60.0)
	assert_eq(demo.peace.size(), 0, "через 8 секунд хоровод распался")


func test_demo_is_swept_away_when_a_run_starts() -> void:
	await boot()
	var demo: MenuDemo = game.menu_demo
	demo.run_event("forks")
	demo.run_event("egg_rage")
	for i in 60:
		demo.update(1.0 / 60.0)
	game.debug_run = true
	game.start_game(1)
	await frames(3)
	assert_true(game.menu_demo == null, "демо убрано")
	assert_true(game.shots.drops.is_empty(), "снарядов демо на поле нет")
	assert_eq(game.enemies.forks.size(), 0, "вилок демо нет")
	assert_eq(game.enemies.pills.size(), 0)
	assert_true(game.shots.waves.is_empty(), "волн нет")


func test_demo_bear_sounds_are_quiet() -> void:
	await boot()
	var demo: MenuDemo = game.menu_demo
	var b: TeddyBear = game.enemies.bears[0]
	assert_eq(b.sound.get_connections().size(), 1, "у медведя один приёмник звука — приглушённый")
	assert_true(demo.QUIET < -6.0)


# ---------------------------------------------------------------- панель разработчика

func test_dev_panel_new_tools() -> void:
	await boot_stage(1)
	var dp = game.dev_panel
	dp.spawn_count = 3
	game.enemies.clear(false)
	dp._spawn("bear", 0)
	assert_eq(game.enemies.bears.size(), 3, "×3 — три медведя за нажатие")
	dp.spawn_count = 1
	dp._step_stage(1)
	assert_eq(game.stage, 2, "этап вперёд")
	dp._step_stage(-1)
	assert_eq(game.stage, 1, "и назад")
	game.freeze_enemies = true
	var b = game.enemies.bears[0] if not game.enemies.bears.is_empty() else null
	var pos0: Vector2 = b.position if b else Vector2.ZERO
	for i in 30:
		game._process(1.0 / 60.0)
	if b and is_instance_valid(b):
		assert_eq(b.position, pos0, "замороженный медведь стоит")
	game.freeze_enemies = false


func test_dev_panel_report_log_and_time_step() -> void:
	await boot()
	var dp = game.dev_panel
	dp._update_info()
	assert_has(dp.info_label.text, "Журнал", "в инфо есть строка журнала")
	assert_has(dp.info_label.text, "Демо меню", "и состояние демо")
	var text: String = dp.copy_report()
	assert_has(text, "v12.2")
	dp.time_paused = true
	Engine.time_scale = 0.0
	await dp.step_frame()
	assert_near(Engine.time_scale, 0.0, 1e-6, "после шага кадра время снова стоит")
	dp.time_paused = false
	Engine.time_scale = 1.0
	push_warning("тестовое предупреждение журнала")
	dp._update_log()
	assert_true(dp.log_label.text != "", "журнал что-то показывает")


func test_dev_panel_demo_buttons_run_events() -> void:
	await boot()
	var texts := []
	for b in game.dev_panel.pages[2].find_children("*", "Button", true, false):
		texts.append((b as Button).tooltip_text)
	assert_has(texts, "ДОСКА В КОНТАКТЕ: ТРЕСНУТЬ")
	assert_has(texts, "МЕДВЕЖЬЯ СВАЛКА")
	var cheats := []
	for b in game.dev_panel.pages[1].find_children("*", "Button", true, false):
		cheats.append((b as Button).tooltip_text)
	assert_has(cheats, "ЯИЧНИЦА: ФАЗА 3")
	assert_has(cheats, "ПОЛНОЕ ЗДОРОВЬЕ")
