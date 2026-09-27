extends "res://tests/integration/game_case.gd"
## Кооперативный ИИ (squad.gd): выключен на Лёгкой и Нормальной; на Сложной — клещи, спасение
## застрявшей вилки, прикрытие, перекрёстный огонь, загон таблетками; на Ультра — ещё тройные клещи
## и цепочки атак.

const Fork = preload("res://scripts/entities/fork.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Squad = preload("res://scripts/game/squad.gd")


func _ready_forks(n: int) -> Array:
	game.enemies.clear(false)
	var out := []
	for i in n:
		var f = game.enemies.spawn_fork(Vector2(300 + i * 250, 200), Fork.Kind.TABLE)
		f.spawn_k = 1.0
		f.attack_cd = 0.0
		f.st = Fork.St.ROAM
		out.append(f)
	game.snake.head_pos = Vector2(640, 400)
	return out


func _think() -> void:
	game.enemies.squad.tick_t = 0.0
	game.enemies.squad.pincer_cd = 0.0
	game.enemies.update_squad(0.3, game.snake)


func test_coop_is_off_on_normal() -> void:
	await boot_stage(1, 1)
	var forks := _ready_forks(3)
	_think()
	assert_eq(game.enemies.squad.level, 0)
	assert_eq(game.enemies.squad.stats["pincer"], 0, "на Нормальной — каждый сам по себе")
	for f in forks:
		assert_eq(f.slot, Vector2.INF)


func test_pincer_on_hard() -> void:
	await boot_stage(1, 2)
	_ready_forks(2)
	_think()
	var sq: Squad = game.enemies.squad
	assert_eq(sq.level, 1)
	assert_len(sq.pincer, 2, "две вилки заходят в клещи")
	_think()  # второй проход раздаёт позиции
	var a: Vector2 = sq.pincer[0].slot - game.snake.head_pos
	var b: Vector2 = sq.pincer[1].slot - game.snake.head_pos
	assert_true(a.normalized().dot(b.normalized()) < -0.8, "с противоположных сторон")
	assert_gt(sq.pincer[0].coop_tag, 0.0, "над вилкой «!!»")


func test_pincer_strikes_together() -> void:
	await boot_stage(1, 2)
	var forks := _ready_forks(2)
	_think()
	var sq: Squad = game.enemies.squad
	_think()
	for f in sq.pincer:
		f.position = f.slot  # вилки дошли до позиций
	_think()
	for f in forks:
		assert_eq(f.st, Fork.St.AIM, "обе начинают выпад одновременно")
		assert_eq(f.slot, Vector2.INF)
	assert_len(sq.pincer, 0)


func test_triple_pincer_on_ultra() -> void:
	await boot_stage(1, 3)
	_ready_forks(3)
	_think()
	assert_eq(game.enemies.squad.level, 2)
	assert_len(game.enemies.squad.pincer, 3, "на Ультра — втроём, через 120°")
	var slots: Array[Vector2] = game.enemies.squad.pincer_slots(Vector2(640, 360), 0.0, 3, game.bounds)
	assert_len(slots, 3)
	assert_near(slots[0].distance_to(Vector2(640, 360)), Squad.PINCER_RADIUS, 1.0)


func test_bear_rescues_stuck_fork() -> void:
	await boot_stage(1, 2)
	var forks := _ready_forks(1)
	var f = forks[0]
	f.st = Fork.St.STUCK
	f.st_t = 5.0
	var bear = game.enemies.spawn_bear(TeddyBear.Type.NORMAL, f.position + Vector2(200, 0))
	_think()
	assert_eq(bear.order, "rescue", "медведь бежит выручать")
	assert_true(bear.order_target == f)
	bear.position = f.position + Vector2(20, 0)
	_think()
	assert_gt(f.rescued, 0.0, "выдёргивает вилку")


func test_bear_guards_dizzy_fork() -> void:
	await boot_stage(1, 2)
	var forks := _ready_forks(1)
	var f = forks[0]
	f.position = Vector2(640, 250)
	f.st = Fork.St.DIZZY
	f.st_t = 5.0
	var bear = game.enemies.spawn_bear(TeddyBear.Type.BOXER, Vector2(300, 600))
	_think()
	assert_eq(bear.order, "guard")
	var gp := Squad.guard_point(f.position, game.snake.head_pos)
	assert_true(bear.order_pos.distance_to(gp) < 1.0, "встаёт между змеёй и вилкой")
	assert_true(gp.distance_to(f.position) < gp.distance_to(game.snake.head_pos) + 200.0)


func test_crossfire_and_herding() -> void:
	await boot_stage(1, 2)
	var forks := _ready_forks(1)
	forks[0].begin_attack(Fork.Atk.LUNGE, game.snake.head_pos)
	var thrower = game.enemies.spawn_bear(TeddyBear.Type.THROWER, Vector2(200, 600))
	var pill = game.enemies.spawn_pill(Vector2(1000, 600))
	_think()
	assert_ne(thrower.lead_hint, Vector2.INF, "метатель целится туда, куда вилка отбросит змею")
	assert_ne(pill.aim_offset, Vector2.ZERO, "таблетка загоняет к вилкам")
	var away: Vector2 = (game.snake.head_pos - forks[0].position).normalized()
	assert_true(pill.aim_offset.normalized().dot(away) > 0.9, "прыгает со стороны, противоположной вилкам")


func test_chain_attacks_only_on_ultra() -> void:
	for diff in [2, 3]:
		await boot_stage(0, diff)
		game.enemies.clear(false)
		var leader = game.enemies.spawn_bear(TeddyBear.Type.BOXER, Vector2(600, 400))
		leader.st = TeddyBear.St.WINDUP
		var mate = game.enemies.spawn_bear(TeddyBear.Type.BOXER, Vector2(700, 420))
		mate.attack_cd = 5.0
		game.snake.head_pos = Vector2(640, 420)
		_think()
		if diff == 3:
			assert_true(mate.attack_cd < 1.0, "Ультра: сосед подхватывает атаку")
		else:
			assert_near(mate.attack_cd, 5.0, 0.5, "Сложная: без цепочек")
		game.queue_free()
		await frames(2)
