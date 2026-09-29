extends "res://tests/integration/game_case.gd"
## v11.0: античит (страж забега, аргументы отладки в релизе, перевод часов в испытании дня, чит
## «Очистить поле») и регрессия ИИ отряда — роль с удалённой целью больше не роняет скрипт.

const RunGuard = preload("res://scripts/core/run_guard.gd")
const Squad = preload("res://scripts/game/squad.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")


func test_guard_catches_memory_edit() -> void:
	var g := RunGuard.new()
	g.note_score(120)
	assert_true(g.verify(120), "честный счёт сходится с тенью")
	assert_false(g.verify(99999), "подделанный — нет")
	assert_true(g.flagged())
	assert_has(g.reason, "памяти")


func test_guard_catches_speedhack_but_not_clock_jumps() -> void:
	var g := RunGuard.new()
	g.check_rate(5.0, 5.0)
	g.check_rate(5.2, 5.0)
	assert_false(g.flagged(), "обычная погрешность часов — не чит")
	g.check_rate(10.0, 5.0)
	assert_false(g.flagged(), "одно окно — ещё не приговор")
	g.check_rate(10.0, 5.0)
	assert_true(g.flagged(), "два окна подряд вдвое быстрее — спидхак")
	var slow := RunGuard.new()
	slow.check_rate(2.5, 5.0)
	slow.check_rate(2.5, 5.0)
	assert_has(slow.reason, "медленнее", "замедление тоже ловится")
	var t := RunGuard.new()
	t.tick(0.5)
	assert_has(t.reason, "скорость времени", "чужой Engine.time_scale")


func _fresh_save() -> void:
	use_temp_storage()
	DirAccess.remove_absolute(SaveData.path)


func test_edited_score_is_not_a_record() -> void:
	_fresh_save()
	await boot()
	game.start_game(1)
	await frames(2)
	game.add_score_raw(50, Vector2.ZERO)
	game.score = 999999  # «Cheat Engine»
	game._end(false)
	assert_true(game.debug_run, "забег не засчитан")
	assert_eq(SaveData.best(1), 0, "рекорд не записан")
	assert_true(game.guard.flagged(), game.guard.reason)


func test_honest_score_still_counts() -> void:
	_fresh_save()
	await boot()
	game.start_game(1)
	await frames(2)
	game.add_score_raw(70, Vector2.ZERO)
	game.add_score_raw(30, Vector2.ZERO)
	game._end(false)
	assert_false(game.debug_run, "честный забег остаётся честным")
	assert_eq(SaveData.best(1), 100, "и рекорд записан")


func test_slowed_time_before_run_is_not_counted() -> void:
	_fresh_save()
	await boot()
	Engine.time_scale = 0.5
	game.start_game(1)
	Engine.time_scale = 1.0
	await frames(2)
	game.add_score_raw(40, Vector2.ZERO)
	game._end(false)
	assert_eq(SaveData.best(1), 0, "замедлили время до забега — рекорд не пишется")


func test_debug_args_ignored_in_release() -> void:
	await boot()
	game.args["stage"] = -1
	game.args["perks"] = false
	game._parse_args(PackedStringArray(["--stage=4", "--perks", "--autopilot", "--touch"]), false)
	assert_eq(int(game.args["stage"]), -1, "в выпущенной сборке --stage не работает")
	assert_false(game.args["perks"], "и --perks")
	assert_false(game.debug_run, "забег не становится отладочным: аргументов как будто нет")
	assert_true(Game.is_debug_arg("--open=win"))
	assert_false(Game.is_debug_arg("--touch"), "--touch безвреден")


func test_perk_outside_a_run_gives_nothing() -> void:
	await boot()
	game._on_perk("heal")
	assert_true(game.perks.is_empty(), "мутация из меню не засчитывается и не роняет игру")
	assert_eq(game.state, game.State.MENU)


func test_daily_refuses_rolled_back_clock() -> void:
	_fresh_save()
	SaveData.write_section(Daily.STREAK_SECTION, {"last": "2026-09-29", "streak": 3, "best": 3})
	assert_eq(Daily.register_play("2026-09-20"), 0, "часы переведены назад — бонуса нет")
	assert_false(Daily.submit("2026-09-20", 5000), "и рекорда прошлого дня тоже")
	assert_gt(Daily.register_play("2026-09-30"), 0, "честный следующий день — бонус")


func test_clear_field_marks_cheat() -> void:
	await boot()
	game.start_game(1)
	await frames(2)
	assert_false(game.debug_run)
	game.dev_panel.toggle()
	var btn: Button = null
	for b in game.dev_panel.find_children("*", "Button", true, false):
		if (b as Button).text == "ОЧИСТИТЬ ПОЛЕ":
			btn = b
	assert_true(btn != null, "кнопка есть")
	btn.pressed.emit()
	assert_true(game.debug_run, "убрать всех врагов — чит")
	game.dev_panel.toggle()


func test_squad_survives_freed_role_target() -> void:
	await boot_stage(1, 3)
	var d = game.enemies
	var squad: Squad = d.squad
	var bear: TeddyBear = d.spawn_bear(0)
	var fork: Fork = d.spawn_fork(Vector2(400, 300), 0)
	await frames(1)
	squad.d = d
	assert_true(squad._assign(bear, "rescue", fork))
	fork.st = Fork.St.STUCK
	d.forks.erase(fork)
	fork.free()  # вилка исчезла посреди такта (как в сквозном прогоне v10.1)
	for i in 10:
		squad.update(0.3, game.snake, d)
	squad.d = d
	assert_eq(squad.role_of(bear), "", "роль с пропавшей целью снята, а не упала")
	squad.d = null
