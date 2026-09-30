extends "res://tests/integration/game_case.gd"
## Директор врагов (enemy_director.gd) и автопилот: сколько врагов на старте этапа, где они появляются,
## каких видов (веса зависят от прогресса и агрессии), помощники и подкрепления яичнице, уборка поля,
## защита от двойного подсчёта. Автопилот выбирает ближайшую съедобную цель.

const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const Autopilot = preload("res://scripts/game/autopilot.gd")


func test_stage_start_spawns_the_right_enemies() -> void:
	await boot_stage(0)
	assert_eq(game.enemies.bears.size(), Balance.BEARS_ON_FIELD, "медведи этапа 1")
	assert_eq(game.enemies.forks.size() + game.enemies.pills.size() + game.enemies.dolls.size(), 0)
	game.enemies.clear(false)
	game.enemies.spawn_for_stage(1, 2)
	assert_eq(game.enemies.forks.size(), 2, "вилок не больше, чем нужно сломать")
	game.enemies.clear(false)
	game.enemies.spawn_for_stage(2, 10)
	assert_eq(game.enemies.pills.size(), 3, "таблеток — три на поле")
	game.enemies.clear(false)
	game.enemies.spawn_for_stage(Balance.DOLL_STAGE, 10)
	assert_gt(game.enemies.dolls.size(), 0, "матрёшки")
	assert_false(game.enemies.doll_sets.is_empty(), "наборы учтены")


func test_spawn_position_keeps_away_from_the_snake() -> void:
	await boot_stage(0)
	game.snake.head_pos = Vector2(640, 360)
	var b: Rect2 = game.bounds
	for i in 50:
		var p: Vector2 = game.enemies.spawn_pos(40.0)
		assert_true(b.grow(-39.0).has_point(p), "внутри поля с отступом")
		assert_gt(p.distance_to(game.snake.head_pos), 260.0, "не под носом у змеи")


func test_bear_types_get_harder_but_normals_never_vanish() -> void:
	await boot_stage(0)
	var early := _bear_mix(0)
	var late := _bear_mix(game.goal_total)
	assert_gt(early[TeddyBear.Type.NORMAL], late[TeddyBear.Type.NORMAL], "к концу этапа обычных меньше")
	assert_eq(early[TeddyBear.Type.KARATE], 0, "каратисты в начале не приходят")
	assert_gt(late[TeddyBear.Type.KARATE], 0, "а к концу — да")
	game.cfg = game.cfg.duplicate()  # настройки сложности — константа, меняем копию
	game.cfg["bear_aggr"] = 3.0
	var brutal := _bear_mix(game.goal_total)
	assert_gt(brutal[TeddyBear.Type.NORMAL], 400 * 0.1, "даже на злой сложности обычных хоть немного")


func _bear_mix(done: int) -> Dictionary:
	game.goal_done = done
	var mix := {}
	for t in TeddyBear.Type.values():
		mix[t] = 0
	for i in 400:
		mix[game.enemies.pick_bear_type()] += 1
	return mix


func test_fork_kinds_follow_progress() -> void:
	await boot_stage(1)
	game.goal_done = 0
	var table := 0
	for i in 300:
		if game.enemies.pick_fork_kind() == Fork.Kind.TABLE:
			table += 1
	assert_gt(table, 300 * 0.6, "в начале — в основном столовые")
	game.goal_done = game.goal_total
	var late_table := 0
	for i in 300:
		if game.enemies.pick_fork_kind() == Fork.Kind.TABLE:
			late_table += 1
	assert_lt(late_table, table, "к концу — больше десертных и вил")


func test_clear_empties_everything() -> void:
	await boot_stage(0)
	game.enemies.spawn_fork()
	game.enemies.spawn_pill()
	game.enemies.spawn_doll_set()
	assert_gt(game.enemies.count(), Balance.BEARS_ON_FIELD)
	game.enemies.clear()
	assert_eq(game.enemies.count(), 0)
	assert_true(game.enemies.doll_sets.is_empty(), "наборы матрёшек забыты")


func test_helpers_only_after_the_first_stage_and_capped() -> void:
	await boot_stage(0)
	var n := game.enemies.bears.size()
	game.enemies.update_helpers(99.0)
	assert_eq(game.enemies.bears.size(), n, "на этапе медведей помощников нет")
	game.enemies.clear(false)
	game.stage = 1
	for i in Balance.HELPERS_MAX + 3:
		game.enemies.update_helpers(Balance.HELPER_INTERVAL + 0.1)
	assert_eq(game.enemies.bears.size(), Balance.HELPERS_MAX, "помощников не больше предела")


func test_reinforcements_rotate_kinds_and_respect_the_cap() -> void:
	await boot_stage(0)
	game.enemies.clear(false)
	var e = game.enemies
	e.reinforce_t = 0.0
	e.update_reinforcements(0.1)
	assert_eq(e.bears.size(), 1, "первыми — медведь")
	e.reinforce_t = 0.0
	e.update_reinforcements(0.1)
	assert_eq(e.forks.size(), 1, "потом вилка")
	e.reinforce_t = 0.0
	e.update_reinforcements(0.1)
	assert_eq(e.pills.size(), 1, "потом таблетка")
	assert_eq(e.count(), Balance.REINFORCE_MAX, "трое на поле — это предел")
	e.reinforce_t = 0.0
	e.update_reinforcements(0.1)
	assert_eq(e.count(), Balance.REINFORCE_MAX, "четвёртый не приходит, пока не освободится место")
	e.eat_pill(e.pills[0])
	e.reinforce_t = 0.0
	e.update_reinforcements(0.1)
	assert_eq(e.dolls.size(), 1, "место освободилось — пришла матрёшка")
	assert_true(e.reinforce_hinted, "подсказка показана один раз")
	for i in 40:
		e.reinforce_t = 0.0
		e.update_reinforcements(0.1)
	assert_true(e.count() <= Balance.REINFORCE_MAX, "не больше предела подкреплений")


func test_breaking_or_eating_twice_counts_once() -> void:
	await boot_stage(1)
	var f: Fork = game.enemies.forks[0]
	var before: int = game.forks_broken
	game.enemies.break_fork(f)
	game.enemies.break_fork(f)
	assert_eq(game.forks_broken, before + 1, "вилка засчитана один раз")
	game.enemies.clear(false)
	game.stage = 2
	game.goal_done = 0
	var p: Pill = game.enemies.spawn_pill()
	var pills_before: int = game.pills_eaten
	game.enemies.eat_pill(p)
	game.enemies.eat_pill(p)
	assert_eq(game.pills_eaten, pills_before + 1, "таблетка — тоже")


func test_pill_kind_weights_follow_progress() -> void:
	await boot_stage(2)
	game.enemies.clear(false)
	game.goal_done = 0
	var tablets := 0
	for i in 200:
		var p: Pill = game.enemies.spawn_pill(Vector2(640, 360))
		if p.kind == Pill.Kind.TABLET:
			tablets += 1
		game.enemies.clear(false)
	assert_between(tablets, 200 * 0.12, 200 * 0.4, "в начале шайб около четверти")


# ---------------------------------------------------------------- автопилот

func test_autopilot_chases_the_nearest_edible_target() -> void:
	await boot_stage(0)
	game.enemies.clear(false)
	game.snake.head_pos = Vector2(200, 200)
	var near: TeddyBear = game.enemies.spawn_bear(TeddyBear.Type.NORMAL, Vector2(300, 200))
	var far: TeddyBear = game.enemies.spawn_bear(TeddyBear.Type.NORMAL, Vector2(1000, 600))
	Autopilot.drive(game)
	assert_true(game.snake.autopilot)
	assert_gt(game.snake.invuln, 0.0, "на автопилоте неуязвима")
	assert_eq(game.snake.auto_target, near.position, "едет к ближнему")
	near.shield_t = 5.0  # под щитом его не съесть — к дальнему
	Autopilot.drive(game)
	assert_eq(game.snake.auto_target, far.position)
	game.snake.autopilot = false


func test_autopilot_goes_behind_a_fork() -> void:
	await boot_stage(1)
	game.enemies.clear(false)
	game.snake.head_pos = Vector2(200, 200)
	var f: Fork = game.enemies.spawn_fork(Vector2(500, 300))
	Autopilot.drive(game)
	var behind: Vector2 = f.position - f.facing() * 40.0
	assert_eq(game.snake.auto_target, behind, "к вилке — со спины")
	game.snake.autopilot = false
