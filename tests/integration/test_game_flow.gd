extends "res://tests/integration/game_case.gd"
## Сквозные сценарии: меню, каждый этап, переход между этапами, бой с яичницей, финал, итоги.


func test_menu_boots_with_demo() -> void:
	await boot()
	assert_eq(game.state, Game.State.MENU)
	assert_true(game.hud.menu.visible, "меню видно")
	assert_eq(game.enemies.bears.size(), 7, "демо-медведи на фоне")
	await step(120)
	assert_eq(game.state, Game.State.MENU)


func test_every_stage_starts_and_runs() -> void:
	for stage in 4:
		await boot_stage(stage)
		await step(240)
		if stage < 3:
			assert_eq(game.state, Game.State.LEVEL, "этап %d идёт" % stage)
			assert_true(game.enemies.count() > 0, "враги на этапе %d" % stage)
		else:
			assert_true(game.state in [Game.State.BOSS_INTRO, Game.State.BOSS], "бой с яичницей")
			assert_true(game.boss != null)
		assert_true(game.snake.alive or game.state == Game.State.GAME_OVER)
		game.queue_free()
		await frames(2)


func test_autopilot_plays_stage_without_errors() -> void:
	await boot_stage(1, 0)
	game.autopilot = true
	await step(1800)
	assert_true(game.forks_broken > 0, "автопилот ломает вилки сбоку")
	assert_true(game.snake.alive)


func test_clearing_stage_offers_perks_then_next_stage() -> void:
	await boot_stage(0)
	game.goal_done = game.goal_total - 1
	game.goal_progress(0)
	assert_eq(game.state, Game.State.PERK)
	await wait_until(func() -> bool: return game.hud.perks.visible)  # пауза перед выбором 1.6 с
	assert_true(game.hud.perks.visible, "выбор улучшения")
	assert_true(tree.paused, "игра на паузе, пока выбираешь")
	game.hud.perks._choose(0)
	assert_false(tree.paused)
	assert_eq(game.stage, 1)
	assert_eq(game.state, Game.State.LEVEL)
	assert_eq(game.perks.size(), 1)


func test_ultra_skips_perks() -> void:
	await boot_stage(0, 3)
	game.goal_done = game.goal_total - 1
	game.goal_progress(0)
	await wait_until(func() -> bool: return game.stage == 1)
	assert_eq(game.stage, 1, "на Ультра улучшений нет — сразу следующий этап")
	assert_true(game.perks.is_empty())


func test_boss_defeat_leads_to_ending_and_results() -> void:
	await boot_stage(3)
	await wait_until(func() -> bool: return game.state == Game.State.BOSS)
	assert_eq(game.state, Game.State.BOSS, "яичница приземлилась")
	game.boss.dev_set_hp(0)
	assert_eq(game.state, Game.State.OUTRO)
	await wait_until(func() -> bool: return game.state == Game.State.CUTSCENE)
	assert_eq(game.state, Game.State.CUTSCENE, "финальная катсцена")
	game.ending.skip()
	await frames(2)
	assert_eq(game.state, Game.State.WIN)
	assert_true(game.hud.end_screen.visible, "экран итогов")
	assert_eq(SaveData.best(1), 0, "отладочный забег не пишет рекорд")


func test_real_run_saves_record_and_scales() -> void:
	await boot()
	game.start_game(0)
	game.score = 777
	game.run_scales = 10.0
	game._end(false)
	assert_eq(SaveData.best(0), 777, "рекорд сохранён")
	assert_eq(Skills.scales, 10, "чешуйки начислены")


func test_death_shows_game_over() -> void:
	await boot_stage(0)
	game.snake.invuln = 0.0
	game.snake.lives = 1
	game.snake.take_damage()
	assert_eq(game.state, Game.State.GAME_OVER)
	assert_true(game.hud.end_screen.visible)


func test_ability_from_eaten_bear() -> void:
	await boot_stage(0)
	game.abilities.gain(2)  # метатель — пуговицы
	assert_eq(game.abilities.type, 2)
	var charges: int = game.abilities.charges
	game.abilities.use()
	assert_eq(game.abilities.charges, charges - 1)
	assert_true(game.shots.drops.size() > 0, "пуговица вылетела")


func test_full_ending_plays_to_results() -> void:
	await boot()
	game.args["ending"] = true
	game.debug_run = true
	game.start_game(1)
	Engine.time_scale = 8.0  # финал длится ~90 с — ускоряем
	await wait_until(func() -> bool: return game.state != Game.State.CUTSCENE, 30.0)
	assert_eq(game.state, Game.State.WIN, "финал доигран до конца")
	assert_eq(game.ending.choice, "thunder", "без действия игрока спичку роняет гром")
	assert_true(game.ending.hatch_node.egg_crack >= 1.0, "яйцо раскрылось")
	assert_true(game.hud.end_screen.visible)


func test_throwing_match_is_players_choice() -> void:
	await boot()
	game.args["ending"] = true
	game.debug_run = true
	game.start_game(1)
	Engine.time_scale = 8.0
	await wait_until(func() -> bool: return game.ending.waiting_choice, 30.0)
	game.ending.choose_throw()
	assert_eq(game.ending.choice, "throw")
	game.ending.skip()
	await frames(2)
	assert_eq(game.state, Game.State.WIN)
