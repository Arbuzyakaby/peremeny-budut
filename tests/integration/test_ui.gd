extends "res://tests/integration/game_case.gd"
## Интерфейс: навигация по экранам, настройки, тач-управление, панель разработчика.


func test_all_screens_open_and_close() -> void:
	await boot()
	var hud = game.hud
	hud.push(hud.settings_screen)
	assert_true(hud.settings_screen.visible)
	assert_false(hud.menu.visible, "меню скрыто под настройками")
	hud.pop()
	assert_true(hud.menu.visible, "вернулись в меню")
	hud.push(hud.skills_screen)
	assert_true(hud.skills_screen.visible)
	hud.pop()
	hud.show_perks(Skills.roll_perks(), "ВИЛКИ")
	assert_true(hud.perks.visible)
	hud.close_all()
	assert_false(hud.is_screen_open())
	# v12.4: открылся — мало; каждый экран должен помещаться, а его главная кнопка — быть на экране
	for s in [hud.settings_screen, hud.skills_screen, hud.bestiary_screen]:
		hud.push(s)
		await frames(2)
		assert_rect_inside(s.panel.get_global_rect(), game.get_viewport().get_visible_rect(), "%s в экране" % s.name)
		assert_eq(hud.stack.back(), s, "экран наверху стека")
		hud.pop()


func test_settings_rows_cover_schema() -> void:
	await boot()
	var screen = game.hud.settings_screen
	for s: Dictionary in Settings.SCHEMA:
		if s["tab"] != "" and Settings.visible_here(s):
			assert_true(screen.controls.has(s["key"]), "строка для " + s["key"])
	for i in Settings.TABS.size():
		screen._show_tab(i)
		assert_true(screen.pages[Settings.TABS[i]["id"]].visible)


func test_pause_settings_back_to_pause() -> void:
	await boot_stage(0)
	var hud = game.hud
	hud.set_paused(true)
	assert_true(tree.paused)
	assert_true(hud.pause_screen.visible)
	hud.push(hud.settings_screen)
	hud.pop()
	assert_true(hud.pause_screen.visible, "из настроек — обратно в паузу")
	hud.pause_screen.resume_requested.emit()
	assert_false(tree.paused)
	assert_false(hud.is_screen_open())


func test_confirm_quit_needs_second_press() -> void:
	await boot_stage(0)
	Settings.set_value("confirm_quit", true)
	var hud = game.hud
	hud.set_paused(true)
	var asked := [false]
	hud.menu_pressed.connect(func() -> void: asked[0] = true)
	hud.pause_screen._on_menu()
	assert_false(asked[0], "первое нажатие только предупреждает")
	hud.pause_screen._on_menu()
	assert_true(asked[0])


func _touch(tc, index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	tc._input(e)


func _drag(tc, index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	tc._input(e)


func test_touch_joystick_steers_and_sprints() -> void:
	Settings.set_value("touch_mode", 1)
	Settings.set_value("touch_scheme", 0)
	await boot_stage(0)
	var tc = game.hud.touch
	assert_true(tc.visible and tc.active, "тач-управление включено в забеге")
	_touch(tc, 0, Vector2(200, 500), true)
	_drag(tc, 0, Vector2(260, 500))
	assert_true(tc.steer.x > 0.5, "стик вправо — змея вправо")
	assert_false(tc.sprint_held)
	_drag(tc, 0, Vector2(400, 500))
	assert_true(tc.sprint_held, "стик до упора — спринт")
	game._process(1.0 / 60.0)
	assert_true(game.snake.touch_sprint, "змея получила спринт")
	_touch(tc, 0, Vector2(400, 500), false)
	assert_eq(tc.steer, Vector2.ZERO)


func test_touch_buttons_multitouch() -> void:
	Settings.set_value("touch_mode", 1)
	await boot_stage(0)
	var tc = game.hud.touch
	var attacks := [0]
	tc.attack_pressed.connect(func() -> void: attacks[0] += 1)
	_touch(tc, 0, Vector2(200, 500), true)          # палец 1 — стик
	_touch(tc, 1, tc.sprint_center(), true)          # палец 2 — спринт
	assert_true(tc.sprint_held)
	_touch(tc, 2, tc.attack_center(), true)          # палец 3 — атака
	assert_eq(attacks[0], 1)
	_touch(tc, 1, tc.sprint_center(), false)
	assert_false(tc.sprint_held, "спринт отпущен, стик держится")


func test_left_handed_swaps_sides() -> void:
	Settings.set_value("touch_mode", 1)
	await boot_stage(0)
	var tc = game.hud.touch
	var right: Vector2 = tc.attack_center()
	Settings.set_value("left_handed", true)
	assert_true(tc.attack_center().x < right.x, "у левши атака слева")


func test_touch_hidden_when_off() -> void:
	Settings.set_value("touch_mode", 2)
	await boot_stage(0)
	assert_false(game.hud.touch.visible)


func test_dev_panel_commands() -> void:
	await boot_stage(0)
	var dp = game.dev_panel
	dp.toggle()
	assert_true(dp.panel.visible)
	var n: int = game.enemies.bears.size()
	dp._spawn("bear", 5)
	dp._spawn("fork", 0)
	assert_eq(game.enemies.bears.size(), n + 1)
	assert_eq(game.enemies.forks.size(), 1)
	dp._jump(2)
	assert_eq(game.stage, 2)
	assert_true(game.enemies.pills.size() > 0)
	dp._win_stage()
	assert_eq(game.state, Game.State.PERK)
	assert_true(game.debug_run, "читы делают забег отладочным")
	dp.toggle()
	assert_false(dp.panel.visible)


func test_back_button_maps_to_pause() -> void:
	await boot_stage(0)
	game.hud._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_false(tree.paused, "обработка отложена до конца кадра")
	await frames(1)
	assert_true(tree.paused, "«Назад» ставит паузу")
	game.hud._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(1)
	assert_false(tree.paused, "второе «Назад» снимает паузу")


func test_ui_scale_changes_root() -> void:
	await boot()
	Settings.set_value("ui_scale", 4)
	game.hud.apply_setting("ui_scale")
	assert_near(game.hud.root.scale.x, 1.3)


func test_yolk_open_shades_hud_accent() -> void:
	await boot_stage(Balance.BOSS_STAGE)
	game.boss.yolk_opened.emit()
	await tree.create_timer(0.3).timeout
	assert_true(game.hud.overlay.modulate.v < 0.6, "желток открыт — табло ушли в тень")
	await tree.create_timer(1.3).timeout
	assert_near(game.hud.overlay.modulate.v, 1.0, 0.02, "через секунду акцент вернулся")
