extends "res://tests/integration/game_case.gd"
## Регрессии v12.4: баги, найденные по ходу работы над версией.


func test_stage_bonus_does_not_extend_the_streak() -> void:
	await boot_stage(0)
	game.stats.reset()
	game.add_score(10, Vector2(400, 300))
	game.add_score(10, Vector2(400, 300))
	assert_eq(game.stats.combo, 2)
	var score_before := game.score
	game._stage_cleared()
	assert_gt(game.score, score_before, "бонус этапа начислен")
	assert_eq(game.stats.combo, 2, "но серию он не продлил — это не действие змеи")


func test_dev_panel_points_are_not_a_streak() -> void:
	await boot_stage(0)
	game.stats.reset()
	game.add_score_raw(1000, Vector2(400, 300), "", false)
	assert_eq(game.stats.combo, 0)
	assert_eq(game.score, 1000)


# ---------------------------------------------------------------- шипучка вне этапа таблеток

const Pill = preload("res://scripts/entities/pill.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const Replay = preload("res://scripts/game/replay.gd")
const ReplayScreen = preload("res://scripts/ui/screens/replay_screen.gd")
const Squad = preload("res://scripts/game/squad.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")


func test_menu_demo_fizz_leaves_a_quiet_puddle() -> void:
	await boot()
	var demo = game.menu_demo
	var p: Pill = demo._add_pill(Vector2(640, 360), Pill.Kind.FIZZ)
	assert_true(p != null)
	var n: int = game.enemies.puddles.size()
	demo._on_fizzed(Vector2(640, 360), p)
	assert_eq(game.enemies.puddles.size(), n + 1, "в демо шипучка тоже растекается")
	assert_false(game.enemies.fizz_hinted, "но без подсказки: в меню она ни к чему")
	for i in 3:
		demo._update_pills(2.0)
	assert_eq(game.enemies.puddles.size(), n, "лужа высохла")


func test_demo_pill_kinds_include_fizz() -> void:
	var kinds := {}
	for i in 300:
		kinds[MenuDemoRef._demo_pill_kind()] = true
	assert_eq(kinds.size(), 3, "в демо — капсулы, шайбы и шипучки")


const MenuDemoRef = preload("res://scripts/game/menu_demo.gd")


func test_calm_pills_never_jump_or_puddle() -> void:
	await boot()
	var e = game.enemies
	var kinds := [Pill.Kind.CAPSULE, Pill.Kind.TABLET, Pill.Kind.FIZZ]
	for k in 3:
		var p: Pill = e.spawn_pill(Vector2(300 + k * 100, 300), kinds[k % 3])
		p.calm_update(0.1, Vector2(40, 0))
		assert_eq(p.st, Pill.St.IDLE, "в «Контакте» таблетки не прыгают на змею")
	assert_eq(e.puddles.size(), 0, "и мирная шипучка не растекается")


func test_replay_remembers_the_pill_kind() -> void:
	await boot_stage(2)
	game.enemies.clear(false)
	game.enemies.spawn_pill(Vector2(400, 300), Pill.Kind.FIZZ)
	var f := Replay.snapshot(game)
	var pill: Array = []
	for e: Array in f["enemies"]:
		if e[0] == "pill":
			pill = e
	assert_eq(int(pill[4]), Pill.Kind.FIZZ, "в записи — вид таблетки")
	var rs = game.hud.replay_screen
	game.replay.push(f)
	game.hud.push(rs)
	rs.show_replay(game.replay)
	await assert_draws(rs.monitor, "повтор с шипучкой")
	assert_eq(ReplayScreen.cause_title("fizz"), "РАЗДАВИЛА ШИПУЧКА")
	assert_eq(ReplayScreen.cause_title("doll"), "СБИЛА ЮЛА-МАЛЫШКА")


# ---------------------------------------------------------------- юла вне этапа матрёшек

func test_menu_demo_tiny_never_spins_at_nobody() -> void:
	await boot()
	var demo = game.menu_demo
	var m: Matryoshka = demo._add_doll(Vector2(640, 360))
	if m == null:
		return
	m.size = Matryoshka.Size.TINY
	m.spawn_k = 1.0
	m.attack_cd = 0.0
	for i in 120:
		demo._update_dolls(1.0 / 60.0)
	assert_false(m.is_spinning(), "в меню малышки не нападают")
	assert_ne(m.st, Matryoshka.St.CROUCH)


func test_duet_tops_cross_on_both_sides_of_the_snake() -> void:
	await boot_stage(Balance.DOLL_STAGE, 3)
	game.enemies.clear(false)
	var head: Vector2 = game.snake.head_pos
	var a: Matryoshka = game.enemies.spawn_doll(Matryoshka.Size.TINY, head + Vector2(-150, 60))
	var b: Matryoshka = game.enemies.spawn_doll(Matryoshka.Size.TINY, head + Vector2(150, 60))
	for m in [a, b]:
		m.spawn_k = 1.0
		m.st = Matryoshka.St.ROAM
		m.attack_cd = 0.3
	var sq: Squad = game.enemies.squad
	sq.kh_cd = 99.0
	sq.duet_cd = 0.0
	sq.tick_t = 0.0
	game.enemies.update_squad(0.3, game.snake)
	assert_eq(sq.stats["duet"], 1)
	a.crouch(head, Vector2.ZERO)
	b.crouch(head, Vector2.ZERO)
	var sa := (a.spin_path[1] - a.spin_path[0]).normalized()
	var sb := (b.spin_path[1] - b.spin_path[0]).normalized()
	assert_lt(sa.dot(sb), 0.9, "две юлы идут разными дорожками")


func test_snake_hop_ring_is_its_own_wave() -> void:
	await boot_stage(Balance.DOLL_STAGE)
	game.enemies.clear(false)
	var before: int = game.world.get_child_count()
	game.abilities._hop_land(Vector2(640, 360))
	var ring = null
	for w in game.shots.waves:
		if w.doll:
			ring = w
	assert_true(ring != null, "хохломское кольцо")
	assert_false(ring.stun and not ring.friendly, "змею не оглушает")
	assert_gt(game.world.get_child_count(), before + 5, "разлетелись половинки скорлупок")
	await assert_draws(ring, "кольцо прыжка малышки")


func test_new_sounds_are_short_and_dry() -> void:
	for n in ["fizz_hop", "fizz_land", "fizz_hiss", "doll_spin", "doll_ring"]:
		assert_true(Sfx.sounds.has(n), "звук " + n)
		var s: AudioStreamWAV = Sfx.sounds[n]
		assert_lt(s.get_length(), 0.8, "%s короткий и сухой, без хвоста эха" % n)


func test_minimizing_saves_the_bestiary() -> void:
	await boot()
	game.args["stage"] = 1
	game.start_game(1)
	await frames(2)
	var key := "fork_%d" % game.enemies.forks[0].kind
	assert_true(Bestiary.is_known(key))
	assert_false(SaveData.read_section(Bestiary.SECTION).has(key), "встреча пока в памяти")
	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_true(SaveData.read_section(Bestiary.SECTION).has(key), "свернули — записано на диск")
	game._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	game.hud.set_paused(false)
