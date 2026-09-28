extends "res://tests/integration/game_case.gd"
## Экраны v7.0: меню с испытанием дня и картотекой, картотека, испытание дня, повтор гибели
## с советом, приборные контролы в настройках, крышка опасной клавиши, советы в меню.

const RotaryKnob = preload("res://scripts/ui/widgets/rotary_knob.gd")
const Fader = preload("res://scripts/ui/widgets/fader.gd")
const RotarySwitch = preload("res://scripts/ui/widgets/rotary_switch.gd")
const ToggleSwitch = preload("res://scripts/ui/widgets/toggle_switch.gd")
const Tips = preload("res://scripts/core/tips.gd")
const LoadingScreen = preload("res://scripts/ui/screens/loading_screen.gd")
const Design = preload("res://scripts/ui/design.gd")


func test_menu_offers_daily_and_bestiary() -> void:
	await boot()
	var menu = game.hud.menu
	assert_has(menu.daily_button.text, "ИСПЫТАНИЕ ДНЯ")
	assert_has(menu.daily_button.text, "ИСПЫТАНИЕ ДНЯ")
	assert_has(menu.bestiary_button.text, "0/%d" % Bestiary.total())
	menu._show_daily_desc()
	assert_has(menu.desc_label.text, Daily.day_key())


func test_bestiary_screen_round_trip() -> void:
	await boot()
	Bestiary.unlock("fork_0")
	game.hud.menu.bestiary_requested.emit()
	var scr = game.hud.bestiary_screen
	assert_true(scr.visible, "картотека открыта")
	assert_eq(scr.cards.size(), Bestiary.total())
	assert_has(scr.counter.text, "1 из")
	for i in scr.cards.size():
		scr._select(i)
	assert_eq(scr.selected, scr.cards.size() - 1)
	await frames(2)  # карточки и лист нарисованы без ошибок
	game.hud.back()
	assert_true(game.hud.menu.visible, "назад — в меню")


func test_daily_run_applies_modifier() -> void:
	await boot()
	game.hud.daily_chosen.emit()
	await frames(2)
	assert_true(Game.daily_mode)
	assert_eq(game.state, Game.State.LEVEL)
	assert_true(String(game.cfg["name"]).begins_with("ИСПЫТАНИЕ"))
	assert_eq(game.cfg["daily"], Daily.today()["id"])
	assert_eq(game.darkness != null, bool(Daily.today().get("dark", false)), "темнота только в своё испытание")
	game.show_menu()
	assert_false(Game.daily_mode, "в меню испытание сбрасывается")


func test_seen_enemies_fill_bestiary() -> void:
	await boot()
	game.start_game(1)  # обычный забег (не отладочный) — картотека пополняется
	await frames(2)
	assert_true(Bestiary.is_known("bear_0") or Bestiary.known_count() > 0, "медведи этапа попали в картотеку")
	var n := Bestiary.known_count()
	game.enemies.spawn_fork(Vector2.INF, 2)
	assert_true(Bestiary.is_known("fork_2"), "вилы — новая карточка")
	assert_eq(Bestiary.known_count(), n + 1)


func test_death_replay_and_advice() -> void:
	await boot_stage(0)
	await step(90)  # полторы секунды записи
	var snake = game.snake
	snake.lives = 1
	snake.invuln = 0.0
	snake.shield = 0
	snake.extra_life = false
	snake.take_damage(1, "bear")
	await frames(2)
	assert_eq(game.state, Game.State.GAME_OVER)
	var end = game.hud.end_screen
	assert_true(end.replay_button.visible, "есть повтор")
	assert_has(end.tip_label.text, Tips.BY_CAUSE["bear"], "совет по причине гибели")
	end.replay_requested.emit()
	var rs = game.hud.replay_screen
	assert_true(rs.visible)
	assert_eq(rs.cause_label.text, "УДАР МЕДВЕДЯ")
	assert_true(game.replay.has_data())
	assert_true(game.replay.frames.size() <= game.replay.CAPACITY)
	await frames(3)
	rs.closed.emit()
	assert_true(end.visible, "из повтора — обратно к итогам")


func test_settings_use_instrument_controls() -> void:
	await boot()
	var scr = game.hud.settings_screen
	assert_true(scr.controls["master"] is RotaryKnob, "громкость — крутилка")
	assert_true(scr.controls["turn_sensitivity"] is Fader, "чувствительность — фейдер")
	assert_true(scr.controls["particles"] is RotarySwitch, "варианты — галетник")
	assert_true(scr.controls["hints"] is ToggleSwitch, "вкл/выкл — рычажный тумблер")
	Settings.set_value("master", 0.3)
	Settings.set_value("particles", 0)
	scr.refresh()
	assert_near(scr.controls["master"].value, 0.3, 0.001)
	assert_eq(scr.value_labels["master"].text, "30%")
	assert_eq(scr.controls["particles"].selected, 0)
	scr.controls["master"].value = 0.5
	assert_near(Settings.num("master"), 0.5, 0.001, "крутилка меняет настройку")


func test_reset_records_behind_cover() -> void:
	await boot()
	var scr = game.hud.settings_screen
	var fired := [false]
	scr.records_reset.connect(func() -> void: fired[0] = true)
	Settings.set_value("reduced_motion", true)
	scr._on_reset_records()
	assert_true(Design.cover_open(scr.reset_records_button), "первое нажатие откинуло крышку")
	assert_false(fired[0])
	scr._on_reset_records()
	assert_true(fired[0], "второе — сброс")
	assert_false(Design.cover_open(scr.reset_records_button), "крышка закрылась")


func test_menu_tips_rotate_and_loading_tip() -> void:
	await boot()
	var menu = game.hud.menu
	var first: String = menu.tip_label.text
	menu._next_tip()
	assert_ne(menu.tip_label.text, first, "совет сменился")
	assert_true(menu.tip_note.is_ancestor_of(menu.tip_label), "совет — на приколотой записке")
	var ls: LoadingScreen = add(LoadingScreen.new())
	assert_has(Tips.GENERAL, ls.tip, "на загрузке — совет")


func test_settings_fit_without_scroll() -> void:
	await boot()
	var scr = game.hud.settings_screen
	game.hud.push(scr)
	for i in Settings.TABS.size():
		scr._show_tab(i)
		await frames(2)
		var need: float = scr.content.get_combined_minimum_size().y
		assert_true(need <= 640.0, "вкладка %d влезает в 720 без прокрутки (%.0f)" % [i, need])
	assert_true(scr.panel.size.x <= 1100.0, "пульт компактный")
