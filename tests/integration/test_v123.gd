extends "res://tests/integration/game_case.gd"
## v12.3: проверка сенсорного управления (потерянные и отменённые касания, свёрнутая игра, раскладка
## на разных экранах), расширенные итоги забега, подхват и терпение в клещах, живые настройки.

const Fork = preload("res://scripts/entities/fork.gd")
const Squad = preload("res://scripts/game/squad.gd")
const RunReport = preload("res://scripts/game/run_report.gd")
const Platform = preload("res://scripts/core/platform.gd")


func after_each() -> void:
	Platform.force_mobile = false   # тест «телефонного режима» мог упасть, не вернув флаги
	Platform.force_touch = false
	await super.after_each()


func _touch(tc, index: int, pos: Vector2, pressed: bool, canceled := false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	e.canceled = canceled
	tc._input(e)


func _drag(tc, index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	tc._input(e)


## Забег с включённым сенсорным управлением (настройки — до старта, иначе кнопки не оживут).
func _boot_touch() -> Node:
	Settings.set_value("touch_mode", 1)
	Settings.set_value("touch_scheme", 0)
	await boot_stage(0)
	return game.hud.touch


# ---------------------------------------------------------------- сенсорное управление

func test_double_tap_fires_attack() -> void:
	var tc = await _boot_touch()
	var attacks := [0]
	tc.attack_pressed.connect(func() -> void: attacks[0] += 1)
	for i in 2:
		_touch(tc, 0, Vector2(300, 300), true)
		_touch(tc, 0, Vector2(300, 300), false)
	assert_eq(attacks[0], 1, "два быстрых тапа — одна атака")


func test_canceled_touch_is_not_a_tap() -> void:
	var tc = await _boot_touch()
	var attacks := [0]
	tc.attack_pressed.connect(func() -> void: attacks[0] += 1)
	_touch(tc, 0, Vector2(300, 300), true)
	_touch(tc, 0, Vector2(300, 300), false, true)   # система отняла палец (жест «домой», звонок)
	_touch(tc, 0, Vector2(300, 300), true)
	_touch(tc, 0, Vector2(300, 300), false)
	assert_eq(attacks[0], 0, "отменённое касание не считается первым тапом двойного")


func test_app_focus_loss_releases_fingers() -> void:
	var tc = await _boot_touch()
	_touch(tc, 0, Vector2(200, 500), true)
	_drag(tc, 0, Vector2(400, 500))
	_touch(tc, 1, tc.sprint_center(), true)
	assert_true(tc.steer.length() > 0.5 and tc.sprint_held, "палец держит стик, второй — спринт")
	tc.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_eq(tc.steer, Vector2.ZERO, "игру свернули — змея не едет в никуда")
	assert_false(tc.sprint_held)
	_touch(tc, 0, Vector2(200, 500), false)         # запоздавшее «отпустил» ничего не ломает
	assert_eq(tc.steer, Vector2.ZERO)


func test_lost_release_does_not_stick_finger() -> void:
	var tc = await _boot_touch()
	_touch(tc, 0, tc.sprint_center(), true)
	assert_true(tc.sprint_held)
	_touch(tc, 0, Vector2(200, 500), true)          # тот же номер пальца снова «нажал», «отпустил» потерялся
	assert_false(tc.sprint_held, "старая привязка спринта сброшена")
	_drag(tc, 0, Vector2(280, 500))
	assert_true(tc.steer.x > 0.5, "палец теперь ведёт стик")


func test_touch_layout_fits_every_screen() -> void:
	var tc = await _boot_touch()
	var sizes := [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960), Vector2(2000, 720)]
	for sz: Vector2 in sizes:
		for lefty in [false, true]:
			for bs in 3:
				Settings.set_value("left_handed", lefty)
				Settings.set_value("button_size", bs)
				tc.size = sz
				tc.safe = Vector4(48, 0, 48, 24)   # вырез камеры слева и справа, жест-полоса снизу
				var tag := "%dx%d рука=%s размер=%d" % [sz.x, sz.y, "Л" if lefty else "П", bs]
				var parts := {
					"атака": [tc.attack_center(), tc._attack_r() * 1.2],
					"спринт": [tc.sprint_center(), tc._sprint_r() * 1.25],
					"стик": [tc._fixed_center(), tc.STICK_R + 8.0],
				}
				var names := parts.keys()
				for a in names.size():
					var c: Vector2 = parts[names[a]][0]
					var r: float = parts[names[a]][1]
					assert_true(c.x - r >= tc.safe.x and c.x + r <= sz.x - tc.safe.z, "%s: %s по ширине в безопасной зоне" % [tag, names[a]])
					assert_true(c.y - r >= 0.0 and c.y + r <= sz.y - tc.safe.w, "%s: %s по высоте в безопасной зоне" % [tag, names[a]])
					for b in range(a + 1, names.size()):
						var d: float = c.distance_to(parts[names[b]][0])
						assert_true(d > r + float(parts[names[b]][1]), "%s: %s и %s не налезают" % [tag, names[a], names[b]])
	Settings.set_value("left_handed", false)
	Settings.set_value("button_size", 1)


# ---------------------------------------------------------------- живые настройки

func _open_controls_tab() -> Node:
	var scr = game.hud.settings_screen
	game.hud.push(scr)
	for i in Settings.TABS.size():
		if Settings.TABS[i]["id"] == "controls":
			scr._show_tab(i)
	await frames(2)
	return scr


func test_settings_preview_lives_on_controls_tab_only() -> void:
	await boot()
	Settings.set_value("touch_mode", 1)
	var scr = await _open_controls_tab()
	assert_true(scr.preview.visible, "на вкладке управления показаны кнопки")
	scr._show_tab(0)
	assert_false(scr.preview.visible, "на других вкладках их нет")
	await _open_controls_tab()
	scr._apply("touch_mode", 2)
	assert_false(scr.preview.visible, "сенсорное управление выключено — показывать нечего")


func test_settings_preview_follows_hand_and_size() -> void:
	await boot()
	Settings.set_value("touch_mode", 1)
	var scr = await _open_controls_tab()
	var right: Vector2 = scr.preview.attack_center()
	scr._apply("left_handed", true)
	assert_true(scr.preview.attack_center().x < right.x, "рука поменялась — кнопки переехали сразу")
	var before: float = scr.preview._attack_r()
	scr._apply("button_size", 2)
	assert_true(scr.preview._attack_r() > before, "крупные кнопки видны сразу")


func test_settings_preview_ignores_touches() -> void:
	await boot()
	Settings.set_value("touch_mode", 1)
	var scr = await _open_controls_tab()
	_touch(scr.preview, 0, Vector2(200, 500), true)
	_drag(scr.preview, 0, Vector2(400, 500))
	assert_false(scr.preview.sprint_held, "витрина не принимает касаний")
	assert_true(scr.preview.preview)


func test_settings_preview_matches_screen_not_interface_scale() -> void:
	await boot()
	Settings.set_value("touch_mode", 1)
	Settings.set_value("ui_scale", 4)   # 130%
	game.hud.apply_setting("ui_scale")
	var scr = await _open_controls_tab()
	var k: float = scr.get_global_transform().get_scale().x
	assert_near(scr.preview.scale.x * k, 1.0, 0.001, "витрина в масштабе экрана, как и кнопки в забеге")
	assert_near(scr.preview.size.x * scr.preview.scale.x * k, scr.size.x * k, 1.0, "и занимает весь экран")


func test_shake_setting_wobbles_panel_then_settles() -> void:
	await boot()
	Settings.set_value("reduced_motion", false)
	var scr = await _open_controls_tab()
	scr._apply("shake", 1.0)
	assert_true(await wait_until(func() -> bool: return absf(scr.panel.rotation) > 0.0, 1.0), "панель качнулась")
	assert_true(await wait_until(func() -> bool: return is_zero_approx(scr.panel.rotation), 2.0), "и встала на место")


func test_shake_probe_respects_reduced_motion() -> void:
	await boot()
	Settings.set_value("reduced_motion", true)
	var scr = await _open_controls_tab()
	scr._apply("shake", 1.0)
	await frames(3)
	assert_eq(scr.panel.rotation, 0.0, "«меньше анимации» — панель не качается")


# ---------------------------------------------------------------- расширенные итоги

func test_run_records_combo_hits_and_abilities() -> void:
	await boot_stage(0)
	game.play_time = 10.0
	game.add_score_raw(10, Vector2.ZERO)
	game.play_time = 11.0
	game.add_score_raw(10, Vector2.ZERO)
	game.play_time = 12.0
	game.add_score_raw(10, Vector2.ZERO)
	assert_eq(game.stats.best_combo, 3, "три очковых события подряд — серия 3")
	game.snake.invuln = 0.0
	game.snake.take_damage(1, "test")
	assert_eq(game.stats.hits, 1)
	assert_eq(game.stats.combo, 0, "удар рвёт серию")


func test_new_run_starts_with_clean_stats() -> void:
	await boot_stage(0)
	game.stats.hits = 5
	game.stats.best_combo = 9
	game.start_game(1)
	assert_eq(game.stats.hits, 0)
	assert_eq(game.stats.best_combo, 0)
	assert_false(game.new_best_combo)


func test_end_screen_rows_include_v123_stats() -> void:
	await boot_stage(0)
	game.stats.best_combo = 6
	game.stats.abilities = 3
	game.stats.peak_length = 27
	var rows: Array = RunReport.rows(game, false, false, 0)
	var labels := []
	for r: Array in rows:
		labels.append(r[0])
	for want in ["Прозвище забега", "Лучшая серия", "Получено ударов", "Приёмов / длина змеи", "Счёт", "Чешуйки"]:
		assert_has(labels, want)
	assert_eq(rows[2][0], "Прозвище забега", "прозвище — сразу под этапом")


func test_commit_run_saves_best_combo_but_not_in_debug() -> void:
	await boot_stage(0)
	game.stats.best_combo = 7
	game.debug_run = true
	game._commit_run(false)
	assert_false(game.new_best_combo, "отладочный забег ничего не пишет")
	assert_eq(game.stats.saved_best_combo(), 0)
	game.state = game.State.LEVEL
	game.debug_run = false
	game._commit_run(false)
	assert_true(game.new_best_combo, "настоящий забег записал лучшую серию")
	assert_eq(game.stats.saved_best_combo(), 7)


# ---------------------------------------------------------------- кооперативный ИИ: подхват и терпение

func _fork_line(n: int) -> Array:
	game.enemies.clear(false)
	var out := []
	for i in n:
		var f = game.enemies.spawn_fork(Vector2(300 + i * 250, 200), Fork.Kind.TABLE)
		f.spawn_k = 1.0
		f.attack_cd = 0.0
		f.st = Fork.St.ROAM
		out.append(f)
	game.snake.head_pos = Vector2(640, 400)
	game.snake.invuln = 0.0
	game.snake.stun_t = 0.0
	return out


func _think() -> void:
	game.enemies.squad.tick_t = 0.0
	game.enemies.squad.pincer_cd = 0.0
	game.enemies.update_squad(0.3, game.snake)


func test_lost_pincer_fork_is_replaced_by_a_free_one() -> void:
	await boot_stage(1, 2)
	var forks := _fork_line(3)
	var sq: Squad = game.enemies.squad
	_think()
	assert_len(sq.pincer, 2, "Сложная: клещи из двух ближайших")
	var spare = forks[0]
	assert_false(sq.pincer.has(spare), "дальняя вилка осталась свободной")
	var lost = sq.pincer[0]
	game.enemies.forks.erase(lost)      # вилку сломали, пока клещи сходились
	lost.queue_free()
	_think()
	assert_len(sq.pincer, 2, "клещи снова полные")
	assert_true(sq.pincer.has(spare), "на место встала свободная вилка")
	assert_eq(sq.stats["recruit"], 1)
	assert_eq(spare.pincer_id, sq.pincer_id)
	assert_true(sq.pincer[0].pincer_lead, "шевроны просвета рисует первая")


func test_no_replacement_no_pincer() -> void:
	await boot_stage(1, 2)
	_fork_line(2)
	var sq: Squad = game.enemies.squad
	_think()
	assert_len(sq.pincer, 2)
	var lost = sq.pincer[0]
	game.enemies.forks.erase(lost)
	lost.queue_free()
	_think()
	assert_len(sq.pincer, 0, "заменить некем — клещи распущены, как и раньше")
	assert_eq(sq.stats["recruit"], 0)


func test_no_recruit_when_strike_is_near() -> void:
	await boot_stage(1, 2)
	_fork_line(3)
	var sq: Squad = game.enemies.squad
	_think()
	sq.pincer_t = Squad.RECRUIT_MIN_TIME - 0.2   # вот-вот удар
	var lost = sq.pincer[0]
	game.enemies.forks.erase(lost)
	lost.queue_free()
	_think()
	assert_eq(sq.stats["recruit"], 0, "замена не успела бы дойти")


func test_pincer_waits_while_snake_is_invulnerable_or_stunned() -> void:
	await boot_stage(1, 2)
	_fork_line(2)
	var sq: Squad = game.enemies.squad
	game.snake.invuln = 1.2
	_think()
	assert_len(sq.pincer, 0, "неуязвимую змею не гонят")
	assert_eq(sq.stats["patience"], 1)
	game.snake.invuln = 0.0
	game.snake.stun_t = 1.0
	_think()
	assert_len(sq.pincer, 0, "оглушённую тоже")
	game.snake.stun_t = 0.0
	_think()
	assert_len(sq.pincer, 2, "пришла в себя — клещи собрались")


func test_pincer_starts_at_end_of_invulnerability() -> void:
	await boot_stage(1, 2)
	_fork_line(2)
	var sq: Squad = game.enemies.squad
	game.snake.invuln = Squad.DAZE_GRACE - 0.1   # почти закончилась — за время сбора успеет
	_think()
	assert_len(sq.pincer, 2)


# ---------------------------------------------------------------- телефонный режим (замена проверки на устройстве)

func test_phone_defaults_and_screens_fit() -> void:
	Platform.force_mobile = true
	Platform.force_touch = true
	Settings.reset_to_defaults()
	assert_eq(Settings.choice("ui_scale"), 3, "на телефоне интерфейс 115%")
	assert_eq(Settings.choice("particles"), 1, "частицы средние")
	assert_eq(Settings.choice("fps_limit"), 1, "60 кадров")
	await boot()
	var vp := game.get_viewport().get_visible_rect().size
	var scr = game.hud.settings_screen
	game.hud.push(scr)
	for i in Settings.TABS.size():
		scr._show_tab(i)
		await frames(2)
		var rect: Rect2 = scr.panel.get_global_rect()
		assert_true(rect.position.x >= -1.0 and rect.end.x <= vp.x + 1.0, "вкладка %d по ширине на экране" % i)
		assert_true(rect.position.y >= -1.0 and rect.end.y <= vp.y + 1.0, "вкладка %d по высоте на экране" % i)
	var rows := []
	for i in 16:
		rows.append(["Строка %d" % i, str(i)])
	game.hud.pop()
	game.hud.show_end(false, "", "Тест", rows)
	await frames(3)
	var er: Rect2 = game.hud.end_screen.panel.get_global_rect()
	assert_true(er.end.y <= vp.y + 1.0 and er.position.y >= -1.0, "длинные итоги прокручиваются, а не вылезают за экран")
	# v12.4: раньше проверялась только рамка — а кнопки уезжали в прокрутку. Теперь — глазами игрока.
	for b: Control in game.hud.end_screen.buttons.get_children():
		if b.visible:
			assert_on_screen(b, "кнопка итогов на телефоне")
	Platform.force_mobile = false
	Platform.force_touch = false
