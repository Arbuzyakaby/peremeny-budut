extends "res://tests/integration/game_case.gd"
## Регрессии v10.1: «Премия» ровно +25, модификаторы дня переживают мутацию, яичница не оживает
## на экране поражения, ранение на взлёте не оставляет её висеть над полом.

const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")


func test_bounty_is_exactly_25_scales_with_any_multiplier() -> void:
	var saved_ranks := Skills.ranks.duplicate()
	for diff in 4:
		await boot_stage(Balance.BOSS_STAGE, diff)
		game.debug_run = false
		Skills.ranks["bounty"] = 1
		Skills.ranks["greed"] = 3
		game.mods = Skills.mods({"hoarder": 1}, false)
		game.run_scales = 0.0
		game.difficulty = diff
		game._commit_run(true)
		assert_eq(game.scales_gained, 25, "премия ровно 25 чешуек на сложности %d, несмотря на множители" % diff)
		game.queue_free()
		await frames(2)
	Skills.ranks = saved_ranks


func test_daily_snake_modifiers_survive_a_perk() -> void:
	await boot_stage(0)
	game.daily = {"snake": {"turn_mult": 0.66, "stamina_max": 0.6}}
	game._on_perk("tank")  # +25% стамины
	assert_near(game.snake.turn_mult, 0.66, 0.001, "«Гололёд» не сбросился выбором мутации")
	assert_near(game.snake.stamina_max, 0.6 * 1.25, 0.001, "«Одышка» перемножилась с мутацией, а не пропала")


func test_boss_landing_after_death_does_not_revive_the_fight() -> void:
	await boot_stage(Balance.BOSS_STAGE, 3)  # одна жизнь
	assert_eq(game.state, Game.State.BOSS_INTRO)
	game.snake.take_damage(1, "wall")  # разбилась о бортик, пока яичница падает
	assert_eq(game.state, Game.State.GAME_OVER)
	await wait_until(func() -> bool: return game.boss.position.y > 299.0, 5.0)
	await frames(3)
	assert_eq(game.state, Game.State.GAME_OVER)
	assert_eq(game.sfx.wanted_track, "", "на экране поражения музыка боя не включается")


func test_boss_wounded_mid_jump_lands_on_the_floor() -> void:
	var boss := FriedEggBoss.new()
	boss.configure(12, 1.0, 1.0, 1.0)
	boss.active = true
	boss.act = FriedEggBoss.Act.JUMP
	boss.height = 12.0
	boss.vel = Vector2(300, 0)
	boss._lose_hp()
	assert_eq(boss.height, 0.0, "ранена на взлёте — стоит на полу")
	assert_eq(boss.vel, Vector2.ZERO)
	boss.free()
