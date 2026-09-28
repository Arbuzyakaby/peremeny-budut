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


func test_ultra_fork_stage_with_coop_runs() -> void:
	await boot_stage(1, 3)
	game.autopilot = true
	await step(1500)
	assert_eq(game.enemies.squad.level, 2, "на Ультра кооператив включён")
	assert_true(game.forks_broken > 0 or game.enemies.forks.size() > 0)
	assert_true(game.snake.alive, "автопилот неуязвим — ошибок нет")
	for f in game.enemies.forks:
		assert_true(game.bounds.grow(4.0).has_point(f.position), "вилки не вылетают из ящика")


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
	assert_true(game.snake.material is ShaderMaterial, "змея горела шейдером")
	assert_gt(float(game.snake.material.get_shader_parameter("burn")), 1.0, "обуглилась и покрылась золой")
	assert_gt(game.ending.fire.ash_amount(), 0.0, "в ящике осталась зола")
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


# ---------------------------------------------------------------- v8.0: атаки вилок и таблеток

const Fork = preload("res://scripts/entities/fork.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")


func test_every_second_fork_gives_its_attack() -> void:
	await boot_stage(1)
	var ab = game.abilities
	ab.reset()
	ab.gain_fork(Fork.Kind.TABLE)
	assert_eq(ab.type, -1, "первая вилка — ещё нет")
	ab.gain_fork(Fork.Kind.TABLE)
	assert_eq(ab.type, 10, "вторая столовая — залп зубцов")
	assert_eq(ab.charges, 2)
	for i in 6:
		ab.gain_fork(Fork.Kind.TABLE)
	assert_eq(ab.charges, 4, "не больше максимума")


func test_fork_attack_does_not_replace_bear_attack() -> void:
	await boot_stage(1)
	var ab = game.abilities
	ab.reset()
	ab.gain(TeddyBear.Type.BOMBER)
	ab.gain_fork(Fork.Kind.DESSERT)
	ab.gain_fork(Fork.Kind.DESSERT)
	assert_eq(ab.type, TeddyBear.Type.BOMBER, "атака медведя не пропадает")
	ab.gain_pill()
	ab.gain_pill()
	assert_eq(ab.type, TeddyBear.Type.BOMBER, "и от таблеток тоже")


func test_breaking_forks_and_eating_pills_feed_attacks() -> void:
	await boot_stage(1)
	game.abilities.reset()
	game.enemies.clear(false)
	for i in 2:
		var f = game.enemies.spawn_fork(Vector2(300 + i * 200, 300), Fork.Kind.PITCH)
		game.enemies.break_fork(f)
	assert_eq(game.abilities.type, 12, "вилы — укол")
	await boot_stage(2)
	game.abilities.reset()
	game.enemies.clear(false)
	for i in 2:
		game.enemies.eat_pill(game.enemies.spawn_pill(Vector2(300 + i * 200, 300)))
	assert_eq(game.abilities.type, 13, "таблетки — ударная волна")


func test_tine_volley_is_short_range() -> void:
	await boot_stage(1)
	game.enemies.clear(false)
	game.abilities.reset()
	game.abilities.gain(10)
	game.snake.stamina = 1.0
	game.abilities.use()
	var tines := game.shots.drops.filter(func(d) -> bool: return d.from_snake)
	assert_len(tines, 3, "три зубца")
	assert_true(tines[0].life <= 0.6, "летят недалеко")
	game.abilities.use()
	assert_eq(game.abilities.charges, 1, "пауза между атаками — второй выстрел сразу не проходит")


func test_pill_wave_stuns_forks_but_spares_snake() -> void:
	await boot_stage(1)
	game.enemies.clear(false)
	game.abilities.reset()
	var f = game.enemies.spawn_fork(game.snake.head_pos + Vector2(120, 0), Fork.Kind.TABLE)
	f.st = Fork.St.ROAM
	game.abilities.gain(13)
	game.snake.stamina = 1.0
	var lives: int = game.snake.lives
	game.abilities.use()
	assert_eq(f.st, Fork.St.DIZZY, "вилка оглушена волной")
	await step(60)
	assert_eq(game.snake.lives, lives, "своя волна змею не бьёт")
	assert_false(game.snake.is_stunned(), "и не оглушает")


func test_snake_cannot_die_between_boss_and_ending() -> void:
	await boot_stage(3)
	await wait_until(func() -> bool: return game.state == Game.State.BOSS)
	game.boss.dev_set_hp(0)
	assert_eq(game.state, Game.State.OUTRO)
	game.snake.invuln = 0.0
	game.snake.lives = 1
	game.snake.head_pos = Vector2(game.bounds.position.x + 2, 360)
	game.snake.heading = PI
	await step(3)
	assert_true(game.snake.alive, "после победы бортик не убивает")
	assert_eq(game.state, Game.State.OUTRO)


func test_run_ends_only_once() -> void:
	await boot()
	game.start_game(0)
	game.score = 500
	game._end(true)
	assert_eq(game.state, Game.State.WIN)
	game.score = 900
	game._end(false)
	assert_eq(game.state, Game.State.WIN, "поражение не перекрывает победу")
	assert_eq(SaveData.best(0), 500, "рекорд записан один раз")


func test_huge_frame_is_clamped() -> void:
	await boot_stage(0)
	game.enemies.clear(false)
	game.snake.head_pos = Vector2(640, 360)
	game.snake.heading = 0.0
	var lives: int = game.snake.lives
	game._process(3.0)  # окно тащили три секунды
	assert_eq(game.snake.lives, lives, "змея не улетела в бортик за один кадр")
	assert_between(game.snake.head_pos.x, 640.0, 640.0 + Game.MAX_STEP * 700.0, "шаг ограничен")


func test_stage_clear_mid_frame_does_not_double_count() -> void:
	await boot_stage(0)
	game.enemies.clear(false)
	game.goal_done = game.goal_total - 1
	var a = game.enemies.spawn_bear(0, Vector2(300, 300))
	var b = game.enemies.spawn_bear(0, Vector2(900, 300))
	game.enemies.eat_bear(a)  # последний медведь этапа — поле очищается
	assert_eq(game.state, Game.State.PERK)
	var eaten: int = game.bears_eaten
	var score: int = game.score
	game.enemies.eat_bear(b)  # тот же кадр: второй медведь уже убран
	assert_eq(game.bears_eaten, eaten, "убранный медведь не съедается")
	assert_eq(game.score, score, "и очков за него нет")


func test_debug_open_does_not_write_records() -> void:
	await boot()
	game._parse_args(PackedStringArray(["--open=win"]))
	assert_true(game.debug_run, "--open=win — отладочный забег")
	game._open_for_debug("win")
	assert_eq(SaveData.best(game.difficulty), 0, "выдуманный счёт 1234 не становится рекордом")
