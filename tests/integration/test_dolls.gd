extends "res://tests/integration/game_case.gd"
## Этап матрёшек (v9.0) в игре: раскол и наборы, юла малышки (v12.4), атака «прыжок малышки»,
## кооператив матрёшек — хоровод с просветом и лентами, разбег, заслон, дуэт на Ультра.

const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const Squad = preload("res://scripts/game/squad.gd")
const Tex = preload("res://scripts/gfx/tex.gd")


func _think() -> void:
	var sq: Squad = game.enemies.squad
	sq.tick_t = 0.0
	sq.pincer_cd = 0.0
	sq.kh_cd = 0.0
	sq.duet_cd = 0.0
	game.enemies.update_squad(0.3, game.snake)


func _ready_doll(size: int, pos: Vector2, set_id := 0) -> Matryoshka:
	var m: Matryoshka = game.enemies.spawn_doll(size, pos, set_id)
	m.spawn_k = 1.0
	m.st = Matryoshka.St.ROAM
	return m


func test_stage_is_the_terem() -> void:
	await boot_stage(Balance.DOLL_STAGE)
	assert_eq(game.arena.floor_kind, Tex.Floor.TEREM, "пол — расписные половицы терема")
	assert_eq(game.goal_total, 4, "на Нормальной — 4 набора")
	assert_eq(game.enemies.dolls.size(), Balance.DOLL_SETS_ON_FIELD, "на поле сразу два набора")
	for m in game.enemies.dolls:
		assert_eq(m.size, Matryoshka.Size.BIG, "наборы начинаются с больших")


func test_set_splits_then_completes_goal() -> void:
	await boot_stage(Balance.DOLL_STAGE)
	game.enemies.clear(false)
	var big := game.enemies.spawn_doll_set(Vector2(400, 360))
	big.spawn_k = 1.0
	var set_id: int = big.set_id
	game.enemies.bite_doll(big)
	assert_eq(game.enemies.dolls.size(), 2, "большая делится надвое")
	for m in game.enemies.dolls:
		assert_eq(m.size, Matryoshka.Size.MIDDLE)
		assert_eq(m.set_id, set_id, "средние — из того же набора")
	assert_eq(int(game.enemies.doll_sets[set_id]), 2)
	for m in game.enemies.dolls.duplicate():
		game.enemies.open_doll(m)
	assert_eq(game.enemies.dolls.size(), 2, "из каждой средней — малышка")
	for m in game.enemies.dolls:
		assert_true(m.is_last())
	var score0: int = game.score
	var eaten := 0
	for m in game.enemies.dolls.duplicate():
		if m.set_id == set_id:
			game.enemies.eat_doll(m)
			eaten += 1
	assert_eq(eaten, 2)
	assert_eq(game.goal_done, 1, "последняя малышка собрала набор")
	assert_eq(game.dolls_done, 1)
	assert_gt(game.score, score0, "очки за малышек и за набор")
	assert_eq(game.opened_dolls, 3, "раскрыто: большая и две средние")


func test_tiny_spin_hits_once_and_opens_dolls_on_its_way() -> void:
	await boot_stage(Balance.DOLL_STAGE)
	game.enemies.clear(false)
	var tiny := _ready_doll(Matryoshka.Size.TINY, Vector2(400, 360))
	var mid := _ready_doll(Matryoshka.Size.MIDDLE, Vector2(560, 360))
	game.snake.head_pos = Vector2(700, 360)
	game.snake.invuln = 0.0
	game.snake.shield = 0
	var lives: int = game.snake.lives
	tiny.crouch(game.snake.head_pos, Vector2.ZERO)
	tiny.st = Matryoshka.St.SPIN
	tiny.spin_hit_done = false
	tiny.position = Vector2(560, 360)
	game.enemies._spin_hits(tiny, game.snake)
	assert_false(game.enemies.dolls.has(mid), "юла снесла соседку на пути — та раскрылась")
	tiny.position = Vector2(700, 360)
	game.enemies._spin_hits(tiny, game.snake)
	assert_eq(game.snake.lives, lives - 1, "сбила змею")
	assert_eq(game.snake.last_cause, "doll")
	game.snake.invuln = 0.0
	game.enemies._spin_hits(tiny, game.snake)
	assert_eq(game.snake.lives, lives - 1, "за один проход — один удар")


func test_hopping_snake_jumps_over_the_top() -> void:
	await boot_stage(Balance.DOLL_STAGE)
	game.enemies.clear(false)
	var tiny := _ready_doll(Matryoshka.Size.TINY, Vector2(640, 360))
	game.abilities.gain(Balance.DOLL_ABILITY)
	game.abilities.use()
	assert_true(game.snake.is_hopping())
	game.snake.invuln = 0.0
	var lives: int = game.snake.lives
	tiny.crouch(game.snake.head_pos, Vector2.ZERO)
	tiny.st = Matryoshka.St.SPIN
	tiny.position = game.snake.head_pos
	game.enemies._spin_hits(tiny, game.snake)
	assert_eq(game.snake.lives, lives, "юлу можно перепрыгнуть прыжком малышки")
	assert_false(tiny.spin_hit_done)


func test_top_stops_without_crushing_the_snake() -> void:
	await boot_stage(Balance.DOLL_STAGE)
	game.enemies.clear(false)
	var tiny := _ready_doll(Matryoshka.Size.TINY, Vector2(500, 360))
	game.snake.head_pos = Vector2(500, 380)
	game.snake.invuln = 0.0
	var lives: int = game.snake.lives
	game.enemies._on_doll_landed(Vector2(500, 360), tiny)
	assert_eq(game.snake.lives, lives, "остановка юлы не давит — бьёт только путь")


func test_hop_ability_is_airborne_and_crushes_on_landing() -> void:
	await boot_stage(Balance.DOLL_STAGE)
	game.enemies.clear(false)
	game.abilities.gain(Balance.DOLL_ABILITY)
	assert_eq(game.abilities.type, Balance.DOLL_ABILITY)
	game.abilities.use()
	assert_true(game.snake.is_hopping(), "змея в прыжке")
	assert_gt(game.snake.invuln, 0.0, "в воздухе неуязвима")
	var m := _ready_doll(Matryoshka.Size.MIDDLE, game.snake.head_pos + Vector2.from_angle(game.snake.heading) * 60.0)
	await step(int(Balance.HOP_TIME * 60.0) + 4)
	assert_false(game.snake.is_hopping(), "приземлилась")
	assert_false(is_instance_valid(m) and game.enemies.dolls.has(m), "приземление раскрыло матрёшку рядом")
	var ring := false
	for w in game.shots.waves:
		if w.doll:
			ring = true
			assert_true(w.friendly, "хохломское кольцо змею не задевает")
	assert_true(ring, "у прыжка малышки своё кольцо, а не мятная волна таблетки")


func test_every_second_tiny_gives_hop() -> void:
	await boot_stage(Balance.DOLL_STAGE)
	game.enemies.clear(false)
	for i in 2:
		game.enemies.eat_doll(_ready_doll(Matryoshka.Size.TINY, Vector2(300 + i * 100, 300)))
	assert_eq(game.abilities.type, Balance.DOLL_ABILITY, "вторая малышка дала прыжок")


func test_no_doll_coop_on_normal() -> void:
	await boot_stage(Balance.DOLL_STAGE, 1)
	game.enemies.clear(false)
	for i in 4:
		_ready_doll(Matryoshka.Size.MIDDLE, game.snake.head_pos + Vector2.from_angle(i * 1.5) * 200.0)
	_think()
	assert_true(game.enemies.squad.khorovod.is_empty(), "на Нормальной хоровода нет")


func test_khorovod_forms_with_gap_and_ribbons() -> void:
	await boot_stage(Balance.DOLL_STAGE, 2)
	game.enemies.clear(false)
	game.snake.god = true
	var head: Vector2 = game.snake.head_pos
	for i in 4:
		_ready_doll(Matryoshka.Size.MIDDLE, head + Vector2.from_angle(i * 1.6 + 0.5) * 220.0)
	_think()
	var sq: Squad = game.enemies.squad
	assert_len(sq.khorovod, 4, "четыре матрёшки водят хоровод")
	assert_eq(sq.stats["khorovod"], 1)
	sq.d = game.enemies
	for k in 90:  # сбегаются на места
		game.snake.head_pos = head  # змея стоит — проверяем сам круг
		sq._update_khorovod(1.0 / 60.0, game.snake)
		for m in game.enemies.dolls:
			m.update(1.0 / 60.0, head, Vector2.ZERO, true)
	sq.d = null
	var dancing := 0
	var ribbons := 0
	for m in sq.khorovod:
		if m.dancing:
			dancing += 1
		if m.ribbon_to != null:
			ribbons += 1
	assert_gt(dancing, 2.0, "встали в круг")
	assert_true(ribbons >= 1 and ribbons < sq.khorovod.size(), "ленты между соседками, через просвет — нет")
	assert_eq(sq.khorovod.back().ribbon_to, null, "последняя не тянет ленту через просвет")


func test_biting_a_dancer_breaks_khorovod() -> void:
	await boot_stage(Balance.DOLL_STAGE, 2)
	game.enemies.clear(false)
	var head: Vector2 = game.snake.head_pos
	for i in 3:
		_ready_doll(Matryoshka.Size.MIDDLE, head + Vector2.from_angle(i * 2.0 + 0.8) * 230.0)
	_think()
	var sq: Squad = game.enemies.squad
	assert_len(sq.khorovod, 3)
	var victim: Matryoshka = sq.khorovod[1]
	game.enemies.bite_doll(victim)
	sq.d = game.enemies
	sq._update_khorovod(1.0 / 60.0, game.snake)
	sq.d = null
	assert_true(sq.khorovod.is_empty(), "укус танцующей рвёт хоровод")
	assert_eq(sq.stats["khorovod_break"], 1)
	for m in game.enemies.dolls:
		assert_false(m.dancing, "никто больше не держит ленту")


func test_ribbon_slows_the_snake() -> void:
	await boot_stage(Balance.DOLL_STAGE, 2)
	game.enemies.clear(false)
	var a := _ready_doll(Matryoshka.Size.MIDDLE, Vector2(500, 300))
	var b := _ready_doll(Matryoshka.Size.MIDDLE, Vector2(800, 300))
	a.dancing = true
	b.dancing = true
	a.ribbon_to = b
	game.snake.head_pos = Vector2(650, 304)
	game.snake.slow_timer = 0.0
	game.enemies._check_ribbons(game.snake)
	assert_gt(game.snake.slow_timer, 0.0, "лента путает — змея замедлена")
	assert_eq(game.snake.lives, game.snake.max_lives, "но не ранит")


func test_scatter_sends_middles_apart_on_hard() -> void:
	await boot_stage(Balance.DOLL_STAGE, 2)
	game.enemies.clear(false)
	var big := _ready_doll(Matryoshka.Size.BIG, game.snake.head_pos + Vector2(0, -120))
	game.enemies.open_doll(big)
	var kids: Array = game.enemies.dolls
	assert_len(kids, 2)
	assert_gt(kids[0].scatter_t, 0.0, "разбег")
	assert_true(kids[0].scatter_dir.dot(kids[1].scatter_dir) < 0.6, "в разные стороны")
	assert_eq(game.enemies.squad.stats["scatter"], 1)


func test_cover_guards_a_dazed_tiny() -> void:
	await boot_stage(Balance.DOLL_STAGE, 2)
	game.enemies.clear(false)
	var tiny := _ready_doll(Matryoshka.Size.TINY, game.snake.head_pos + Vector2(200, 0))
	tiny.daze(1.2)
	var guard := _ready_doll(Matryoshka.Size.BIG, game.snake.head_pos + Vector2(360, 80))
	var sq: Squad = game.enemies.squad
	sq.kh_cd = 99.0  # хоровод не мешает
	sq.tick_t = 0.0
	game.enemies.update_squad(0.3, game.snake)
	assert_eq(sq.role_of(guard), "cover", "большая заслоняет малышку")
	var between := guard.order_pos
	assert_true(between.distance_to(tiny.position) < between.distance_to(game.snake.head_pos) + 1.0,
		"точка заслона — между змеёй и малышкой")
	tiny.st = Matryoshka.St.ROAM  # отдышалась — заслон снимается срывом
	game.enemies.update_squad(1.0 / 60.0, game.snake)
	assert_eq(sq.role_of(guard), "")


func test_duet_on_ultra_jumps_to_both_sides() -> void:
	await boot_stage(Balance.DOLL_STAGE, 3)
	game.enemies.clear(false)
	var head: Vector2 = game.snake.head_pos
	var a := _ready_doll(Matryoshka.Size.TINY, head + Vector2(-150, 60))
	var b := _ready_doll(Matryoshka.Size.TINY, head + Vector2(150, 60))
	a.attack_cd = 0.3
	b.attack_cd = 0.3
	var sq: Squad = game.enemies.squad
	sq.kh_cd = 99.0
	sq.duet_cd = 0.0
	sq.tick_t = 0.0
	game.enemies.update_squad(0.3, game.snake)
	assert_eq(sq.stats["duet"], 1, "дуэт")
	assert_near(a.sync_jump, b.sync_jump, 0.001, "прыгнут одновременно")
	assert_gt(a.coop_tag, 0.0, "«!!» — только на Ультра")
	assert_true(a.jump_offset.dot(b.jump_offset) < 0.0, "по разные стороны от курса")


func test_mercy_and_ultra_stage_runs_with_autopilot() -> void:
	await boot_stage(Balance.DOLL_STAGE, 3)
	game.autopilot = true
	await step(1500)
	assert_true(game.snake.alive, "автопилот неуязвим — ошибок нет")
	assert_gt(float(game.opened_dolls), 0.0, "автопилот раскрывает матрёшек")
	for m in game.enemies.dolls:
		assert_true(game.bounds.grow(4.0).has_point(m.position), "матрёшки не вылетают из терема")


func test_boss_reinforcements_include_a_doll() -> void:
	await boot_stage(Balance.BOSS_STAGE)
	game.enemies.clear(false)
	game.enemies.reinforce_kind = 3
	game.enemies.reinforce_t = 0.0
	game.enemies.update_reinforcements(0.1)
	assert_len(game.enemies.dolls, 1, "матрёшка идёт на помощь яичнице")
