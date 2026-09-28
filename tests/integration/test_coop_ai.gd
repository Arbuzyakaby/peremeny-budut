extends "res://tests/integration/game_case.gd"
## Кооперативный ИИ (squad.gd): выключен на Лёгкой и Нормальной; на Сложной — клещи, спасение
## застрявшей вилки, прикрытие, перекрёстный огонь, загон таблетками; на Ультра — ещё тройные клещи,
## цепочки атак и медведь-обманщик. v7.2: окно обязательства ролей, просвет и прорыв клещей,
## телеграфы анимацией, промахи снарядов.

const Fork = preload("res://scripts/entities/fork.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Squad = preload("res://scripts/game/squad.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const OilDrop = preload("res://scripts/entities/oil_drop.gd")
const Tips = preload("res://scripts/core/tips.gd")


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
	assert_eq(sq.pincer[0].coop_tag, 0.0, "на Сложной без тега «!!» — телеграф анимацией")
	assert_gt(sq.pincer[0].pincer_id, 0, "вилка знает свои клещи")
	assert_gt(sq.pincer[0].pincer_half, 0.0, "рисует свою дугу кольца")


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
		assert_eq(f.st, Fork.St.ROAM, "сначала 0,3 с переглядываются")
		assert_gt(f.look_t, 0.0, "смотрит на напарника")
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
	assert_len(game.enemies.squad.pincer, 3, "на Ультра — втроём")
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


# ---------------------------------------------------------------- v7.2: окно обязательства

func _guard_setup() -> Array:
	var forks := _ready_forks(1)
	var f = forks[0]
	f.position = Vector2(640, 250)
	f.st = Fork.St.DIZZY
	f.st_t = 99.0
	var bear = game.enemies.spawn_bear(TeddyBear.Type.BOXER, Vector2(300, 600))
	return [f, bear]


func test_commit_window_is_two_ticks() -> void:
	assert_eq(Squad.COMMIT_TICKS, 2)
	assert_near(Squad.COMMIT_TICKS * Squad.TICK, 0.5, 0.001, "окно ≈0,5 с")


func test_role_holds_for_commit_window() -> void:
	await boot_stage(1, 2)
	var fb := _guard_setup()
	var bear = fb[1]
	var sq: Squad = game.enemies.squad
	_think()
	assert_eq(bear.order, "guard")
	assert_eq(sq.role_of(bear), "guard")
	game.snake.head_pos = Vector2(640, 700)  # змея далеко — новой роли прикрытия план бы уже не дал
	_think()
	assert_eq(bear.order, "guard", "роль держится всё окно, без дёрганья")
	assert_true(sq.is_committed(bear))
	_think()
	assert_eq(bear.order, "", "окно кончилось, план не продлил — роль снята")
	assert_eq(sq.role_of(bear), "")


func test_role_renews_while_needed() -> void:
	await boot_stage(1, 2)
	var fb := _guard_setup()
	var bear = fb[1]
	for i in 6:
		_think()
		bear.position = bear.order_pos  # медведь добегает до точки (в игре его двигает update)
		assert_eq(bear.order, "guard", "та же роль продлевается без мигания (такт %d)" % i)


func test_abort_drops_role_at_once() -> void:
	await boot_stage(1, 2)
	var fb := _guard_setup()
	var bear = fb[1]
	var sq: Squad = game.enemies.squad
	_think()
	assert_eq(bear.order, "guard")
	bear.st = TeddyBear.St.DIZZY  # оглушили
	sq.tick_t = 1.0  # до следующего такта далеко
	game.enemies.update_squad(1.0 / 60.0, game.snake)
	assert_eq(bear.order, "", "оглушение снимает роль сразу, не дожидаясь такта")
	assert_gt(sq.stats["abort"], 0)


func test_abort_when_target_dies() -> void:
	await boot_stage(1, 2)
	var forks := _ready_forks(1)
	var f = forks[0]
	f.st = Fork.St.STUCK
	f.st_t = 99.0
	var bear = game.enemies.spawn_bear(TeddyBear.Type.NORMAL, f.position + Vector2(200, 0))
	_think()
	assert_eq(bear.order, "rescue")
	game.enemies.break_fork(f)
	game.enemies.squad.tick_t = 1.0
	game.enemies.update_squad(1.0 / 60.0, game.snake)
	assert_eq(bear.order, "", "цель погибла — роль снята сразу")
	assert_true(bear.order_target == null)


func test_stall_aborts_role() -> void:
	await boot_stage(1, 2)
	var forks := _ready_forks(1)
	var f = forks[0]
	f.st = Fork.St.STUCK
	f.st_t = 99.0
	var bear = game.enemies.spawn_bear(TeddyBear.Type.NORMAL, f.position + Vector2(300, 0))
	_think()
	assert_eq(bear.order, "rescue")
	for i in Squad.STALL_TICKS:  # медведь не двигается — упёрся
		_think()
	assert_eq(bear.order, "rescue", "пока не набралось %d тактов без продвижения — держит" % Squad.STALL_TICKS)
	_think()
	assert_eq(bear.order, "", "застрял — роль снята")
	_think()
	assert_eq(bear.order, "", "и какое-то время новую не дают")


# ---------------------------------------------------------------- v7.2: клещи — просвет и прорыв

func test_pincer_leaves_gap_ahead() -> void:
	await boot_stage(1, 3)
	var sq: Squad = game.enemies.squad
	var head := Vector2(640, 360)
	for heading in [0.0, 1.3, -2.2]:
		for n in [2, 3]:
			var slots: Array[Vector2] = sq.pincer_slots(head, heading, n, Rect2(-2000, -2000, 5000, 5000))
			var min_off := PI
			for p in slots:
				min_off = minf(min_off, absf(angle_difference(heading, (p - head).angle())))
			assert_true(min_off >= Squad.pincer_gap(n) / 2.0 - 0.01,
				"%d вилки: по курсу змеи просвет (ближайшая в %.0f°)" % [n, rad_to_deg(min_off)])
	assert_between(rad_to_deg(Squad.PINCER_GAP), 120.0, 170.0, "тройные клещи не замыкаются")


func _pincer_in_aim(n: int, diff: int) -> Array:
	await boot_stage(1, diff)
	var forks := _ready_forks(n)
	var sq: Squad = game.enemies.squad
	_think()
	_think()
	for f in sq.pincer:
		f.position = f.slot
	_think()
	_think()
	return forks


func test_pincer_breakout_by_sprint() -> void:
	var forks: Array = await _pincer_in_aim(2, 2)
	var sq: Squad = game.enemies.squad
	var a = forks[0]
	var b = forks[1]
	assert_eq(a.st, Fork.St.AIM)
	assert_true(a.is_pincer_windup(), "замах клещей")
	var snake = game.snake
	var lives: int = snake.lives
	snake.invuln = 0.0
	snake.stamina = 1.0
	snake.sprinting = true
	snake.head_pos = a.position + a.facing() * 30.0  # прямо в зубцы
	game.enemies.update_forks(1.0 / 60.0, snake)
	assert_eq(snake.lives, lives, "прорыв без урона")
	assert_near(snake.stamina, 1.0 - Squad.BREAKOUT_STAMINA, 0.02, "стоит стамины")
	assert_eq(a.st, Fork.St.DIZZY, "вилку отбросило и оглушило")
	assert_true(a.is_vulnerable(), "теперь её можно кусать")
	assert_ne(b.st, Fork.St.AIM, "клещи развалились: вторая вилка сбита с замаха")
	assert_eq(b.pincer_id, 0)
	assert_eq(sq.stats["breakout"], 1)
	assert_true(game.enemies.forks.has(a), "прорыв не ломает вилку")


func test_pincer_without_sprint_hurts() -> void:
	var forks: Array = await _pincer_in_aim(2, 2)
	var a = forks[0]
	var snake = game.snake
	var lives: int = snake.lives
	snake.invuln = 0.0
	snake.sprinting = false
	snake.head_pos = a.position + a.facing() * 30.0
	game.enemies.update_forks(1.0 / 60.0, snake)
	assert_eq(snake.lives, lives - 1, "без спринта в зубцы клещей — урон")
	assert_eq(game.enemies.squad.stats["breakout"], 0)


func test_bite_from_behind_breaks_pincer() -> void:
	var forks: Array = await _pincer_in_aim(2, 2)
	var a = forks[0]
	var b = forks[1]
	var snake = game.snake
	snake.sprinting = false
	snake.head_pos = a.position - a.facing() * 40.0  # сзади, у ручки
	game.enemies.update_forks(1.0 / 60.0, snake)
	assert_false(game.enemies.forks.has(a), "укус сзади ломает вилку")
	assert_ne(b.st, Fork.St.AIM, "и клещи разваливаются")


# ---------------------------------------------------------------- v7.2: телеграфы

func test_tags_only_on_ultra() -> void:
	await boot_stage(1, 3)
	_ready_forks(3)
	_think()
	_think()
	var sq: Squad = game.enemies.squad
	assert_gt(sq.pincer[0].coop_tag, 0.0, "на Ультра «!!» остаётся")


func test_pincer_forks_look_at_each_other() -> void:
	await boot_stage(1, 3)
	_ready_forks(3)
	var sq: Squad = game.enemies.squad
	_think()
	_think()
	for f in sq.pincer:
		f.position = f.slot
	var group: Array = sq.pincer.duplicate()
	_think()
	var f0 = group[0]
	var mate = group[1]
	assert_gt(f0.look_t, 0.0)
	for i in 16:  # переглядывание 0,3 с: за это время вилка успевает развернуться даже на 180°
		f0.update(1.0 / 60.0, game.snake.head_pos, true)
	var want: float = (mate.position - f0.position).angle()
	assert_true(absf(angle_difference(f0.rotation, want)) < 0.3, "повернулась к напарнику")
	assert_gt(f0.height, 0.0, "подпрыгивает, кивая")


func test_rescuer_and_herder_telegraph() -> void:
	await boot_stage(1, 2)
	var forks := _ready_forks(1)
	var f = forks[0]
	f.st = Fork.St.STUCK
	f.st_t = 99.0
	var bear = game.enemies.spawn_bear(TeddyBear.Type.NORMAL, f.position + Vector2(200, 0))
	var pill = game.enemies.spawn_pill(Vector2(1000, 600))
	_think()
	assert_eq(bear.order, "rescue", "спасатель бежит с поднятой лапой (рисунок — по order)")
	assert_true(pill.herd, "загонщик")
	pill.update(0.5, game.snake.head_pos, Vector2.ZERO, true)
	assert_gt(pill.herd_k, 0.5, "таблетка наливается оттенком")
	var c: Color = pill.cols[0]
	assert_ne(pill.tint(c), c, "оттенок изменился")


# ---------------------------------------------------------------- v7.2: обманщик (Ультра)

func _lunge_and_bear(diff: int) -> Array:
	await boot_stage(1, diff)
	var forks := _ready_forks(1)
	var f = forks[0]
	f.begin_attack(Fork.Atk.LUNGE, game.snake.head_pos)
	var lure: Vector2 = game.snake.head_pos + f.facing() * Squad.DECOY_LURE
	var bear = game.enemies.spawn_bear(TeddyBear.Type.NORMAL, lure + Vector2(0, 150))
	return [f, bear, lure]


func test_decoy_only_on_ultra() -> void:
	var hard: Array = await _lunge_and_bear(2)
	_think()
	assert_eq(hard[1].order, "", "на Сложной обманщиков нет")
	assert_eq(game.enemies.squad.stats["decoy"], 0)
	game.queue_free()
	await frames(2)
	var ultra: Array = await _lunge_and_bear(3)
	var bear = ultra[1]
	_think()
	assert_eq(bear.order, "decoy", "на Ультра медведь идёт в приманку")
	assert_true(bear.order_pos.distance_to(ultra[2]) < 2.0, "на продолжение линии выпада")
	assert_eq(game.enemies.squad.stats["decoy"], 1)


func test_decoy_feints_then_reveals() -> void:
	var ultra: Array = await _lunge_and_bear(3)
	var bear = ultra[1]
	_think()
	bear.position = bear.order_pos
	bear.update(1.0 / 60.0, game.snake)
	assert_true(bear.feint, "сел и изображает оглушение (картонные звёзды)")
	assert_false(bear.is_dizzy(), "на самом деле не оглушён")
	game.snake.head_pos = bear.position + Vector2(60, 0)
	bear.update(1.0 / 60.0, game.snake)
	assert_false(bear.feint, "змея рядом — раскрылся")
	assert_gt(bear.tease_t, 0.0, "дразнится и удирает")


func test_decoy_leaves_when_attack_ends() -> void:
	var ultra: Array = await _lunge_and_bear(3)
	var f = ultra[0]
	var bear = ultra[1]
	_think()
	assert_eq(bear.order, "decoy")
	f.st = Fork.St.RECOVER  # выпад кончился
	game.enemies.squad.tick_t = 1.0
	game.enemies.update_squad(1.0 / 60.0, game.snake)
	assert_eq(bear.order, "", "настоящей атаки нет — приманка не нужна")


func test_new_hints_exist() -> void:
	assert_true(Tips.PINCER_HINT.length() > 20)
	assert_true(Tips.DECOY_HINT.length() > 20)
	assert_true("обманщик" in String(Bestiary.entry("bear_0")["tip"]), "обманщик упомянут в картотеке")


# ---------------------------------------------------------------- v7.2: промахи видны

func test_missed_tine_sticks_then_vanishes() -> void:
	await boot_stage(1, 1)
	game.enemies.clear(false)
	var snake = game.snake
	snake.head_pos = Vector2(640, 400)
	var d: OilDrop = game.shots.spawn_drop(Vector2(1252, 300), Vector2(600, 0), OilDrop.Kind.TINE)
	game.shots.update_drops(1.0 / 60.0)
	assert_true(game.shots.drops.has(d), "долетел до бортика и не исчез")
	assert_true(d.is_missed(), "воткнулся")
	assert_eq(d.vel, Vector2.ZERO, "торчит на месте")
	var lives: int = snake.lives
	snake.invuln = 0.0
	snake.head_pos = d.position
	game.shots.update_drops(1.0 / 60.0)
	assert_eq(snake.lives, lives, "торчащий зубец безвреден")
	snake.head_pos = Vector2(640, 400)
	for i in 20:
		game.shots.update_drops(1.0 / 60.0)
	assert_true(game.shots.drops.has(d), "торчит около 0,5 с")
	for i in 30:
		game.shots.update_drops(1.0 / 60.0)
	assert_false(game.shots.drops.has(d), "потом исчезает")


func test_missed_button_rolls_then_vanishes() -> void:
	await boot_stage(1, 1)
	game.enemies.clear(false)
	game.snake.head_pos = Vector2(640, 600)
	var d: OilDrop = game.shots.spawn_drop(Vector2(640, 27), Vector2(0, -300), OilDrop.Kind.BUTTON)
	game.shots.update_drops(1.0 / 60.0)
	assert_true(d.is_missed(), "ударилась о бортик и упала")
	assert_true(d.vel.y > 0.0, "отскочила внутрь")
	var p0 := d.position
	for i in 20:
		game.shots.update_drops(1.0 / 60.0)
	assert_true(d.position.distance_to(p0) > 10.0, "катится")
	for i in 60:
		game.shots.update_drops(1.0 / 60.0)
	assert_false(game.shots.drops.has(d), "потом исчезает")


func test_expired_tine_sticks_in_floor() -> void:
	await boot_stage(1, 1)
	game.enemies.clear(false)
	game.snake.head_pos = Vector2(200, 600)
	var d: OilDrop = game.shots.spawn_drop(Vector2(640, 360), Vector2(10, 0), OilDrop.Kind.TINE)
	d.life = 0.01
	game.shots.update_drops(1.0 / 60.0)
	assert_true(d.is_missed() and game.shots.drops.has(d), "выдохся посреди поля — воткнулся в пол")
	var oil: OilDrop = game.shots.spawn_drop(Vector2(640, 360), Vector2(10, 0), OilDrop.Kind.OIL)
	oil.life = 0.01
	game.shots.update_drops(1.0 / 60.0)
	assert_false(game.shots.drops.has(oil), "капля масла просто исчезает, как раньше")


# ---------------------------------------------------------------- v8.0: рассредоточение, уклонение, огонь по подходу, милосердие

func test_shooters_spread_around_snake() -> void:
	await boot_stage(0, 2)
	game.enemies.clear(false)
	var a = game.enemies.spawn_bear(TeddyBear.Type.THROWER, Vector2(300, 200))
	var b = game.enemies.spawn_bear(TeddyBear.Type.SEAMSTRESS, Vector2(360, 230))
	var c = game.enemies.spawn_bear(TeddyBear.Type.NINJA, Vector2(330, 280))
	game.snake.head_pos = Vector2(640, 400)
	_think()
	var sq: Squad = game.enemies.squad
	for bear in [a, b, c]:
		assert_eq(sq.role_of(bear), "spread", "стрелок рассредоточивается")
	var head := game.snake.head_pos
	var angles := []
	for bear in [a, b, c]:
		angles.append((bear.order_pos - head).angle())
	for i in 3:
		for j in range(i + 1, 3):
			assert_gt(absf(angle_difference(angles[i], angles[j])), 1.2, "с разных сторон, а не кучей")
	assert_gt(sq.stats["spread"], 0)


func test_single_shooter_does_not_spread() -> void:
	await boot_stage(0, 2)
	game.enemies.clear(false)
	var a = game.enemies.spawn_bear(TeddyBear.Type.THROWER, Vector2(300, 200))
	_think()
	assert_eq(game.enemies.squad.role_of(a), "", "одному рассредоточиваться не с кем")


func test_bear_dodges_snake_ranged_attack() -> void:
	await boot_stage(0, 2)
	game.enemies.clear(false)
	game.snake.head_pos = Vector2(400, 400)
	game.snake.heading = 0.0
	var target = game.enemies.spawn_bear(TeddyBear.Type.NORMAL, Vector2(700, 410))
	var aside = game.enemies.spawn_bear(TeddyBear.Type.NORMAL, Vector2(400, 150))
	_think()
	var sq: Squad = game.enemies.squad
	assert_eq(sq.role_of(target), "", "без стрелковой атаки не уклоняется")
	game.abilities.gain(2)  # пуговицы
	_think()
	assert_eq(sq.role_of(target), "dodge", "медведь на линии огня отскакивает")
	assert_eq(sq.role_of(aside), "", "а в стороне — нет")
	assert_gt(absf(target.order_pos.y - target.position.y), 80.0, "вбок от линии огня")
	assert_false(Squad.in_line_of_fire(game.snake.head_pos, Vector2.RIGHT, target.order_pos), "уходит с линии")


func test_dodge_needs_hard() -> void:
	await boot_stage(0, 1)
	game.enemies.clear(false)
	game.snake.head_pos = Vector2(400, 400)
	game.snake.heading = 0.0
	var target = game.enemies.spawn_bear(TeddyBear.Type.NORMAL, Vector2(700, 410))
	game.abilities.gain(2)
	_think()
	assert_eq(game.enemies.squad.role_of(target), "", "на Нормальной враги оружие змеи не читают")


func test_mercy_on_last_life() -> void:
	await boot_stage(1, 2)
	_ready_forks(2)
	game.snake.lives = 1
	var sq: Squad = game.enemies.squad
	sq.tick_t = 0.0
	game.enemies.update_squad(0.3, game.snake)
	assert_true(sq.mercy, "последняя жизнь — милосердие")
	assert_gt(sq.stats["mercy"], 0)
	game.snake.lives = game.snake.max_lives
	sq.tick_t = 0.0
	game.enemies.update_squad(0.3, game.snake)
	assert_false(sq.mercy)


func test_boss_fire_leads_to_yolk() -> void:
	await boot_stage(3, 2)
	await wait_state(game.State.BOSS, 400)
	game.enemies.clear(false)
	var boss = game.boss
	var t1 = game.enemies.spawn_bear(TeddyBear.Type.THROWER, Vector2(200, 600))
	game.snake.head_pos = Vector2(640, 650)
	boss.act = boss.Act.YOLK_OPEN
	boss.act_t = 5.0
	_think()
	var sq: Squad = game.enemies.squad
	assert_eq(sq.role_of(t1), "boss_fire", "желток открыт — стрелок бьёт по подходу")
	var yolk: Vector2 = boss.position + boss.YOLK_OFFSET
	assert_true(t1.lead_hint.distance_to(yolk) < game.snake.head_pos.distance_to(yolk), "упреждение — на пути к желтку")
	boss.act = boss.Act.IDLE
	game.enemies.update_squad(1.0 / 60.0, game.snake)
	assert_eq(t1.lead_hint, Vector2.INF, "желток закрылся — прицел снят")
