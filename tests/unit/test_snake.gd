extends "res://tests/test_case.gd"
## Змея: урон и неуязвимость, щит, линька, оглушение, стамина, тач-поворот.

const Snake = preload("res://scripts/entities/snake.gd")


func before_each() -> void:
	use_temp_storage()
	ensure_actions()


func _snake() -> Snake:
	var s: Snake = add(Snake.new())
	s.bounds = Rect2(24, 24, 1232, 672)
	s.lives = 3
	s.max_lives = 3
	s.reset(Vector2(640, 400))
	return s


func test_damage_then_invulnerable() -> void:
	var s := _snake()
	assert_true(s.take_damage())
	assert_eq(s.lives, 2)
	assert_false(s.take_damage(), "во время неуязвимости урона нет")
	assert_eq(s.lives, 2)


func test_shield_absorbs_hit() -> void:
	var s := _snake()
	s.shield = 1
	assert_false(s.take_damage())
	assert_eq(s.lives, 3)
	assert_eq(s.shield, 0)


func test_molt_saves_once() -> void:
	var s := _snake()
	s.apply_mods({"molt": true})
	s.lives = 1
	s.take_damage()
	assert_eq(s.lives, 1, "линька спасла")
	assert_true(s.alive)
	s.invuln = 0.0
	s.take_damage()
	assert_false(s.alive, "второй раз не спасает")


func test_death_emits_signal() -> void:
	var s := _snake()
	var died := [false]
	s.died.connect(func() -> void: died[0] = true)
	s.lives = 1
	s.take_damage()
	assert_true(died[0])


func test_god_mode() -> void:
	var s := _snake()
	s.god = true
	assert_false(s.take_damage())
	assert_eq(s.lives, 3)


func test_stun_ignored_while_dashing_and_resisted() -> void:
	var s := _snake()
	s.dash(0.3)
	assert_false(s.stun(1.0), "в рывке не оглушить")
	s.dash_t = 0.0
	s.apply_mods({"resist": 0.5})
	assert_true(s.stun(1.0))
	assert_near(s.stun_t, 0.5)


func test_spend_stamina() -> void:
	var s := _snake()
	assert_true(s.spend(0.4))
	assert_near(s.stamina, 0.6)
	assert_false(s.spend(0.7), "не хватает сил")
	assert_near(s.stamina, 0.6)


func test_sprint_drains_and_rest_regenerates() -> void:
	var s := _snake()
	s.touch_sprint = true
	for i in 30:
		s.update(1.0 / 60.0)
	assert_true(s.sprinting)
	assert_true(s.stamina < 1.0, "спринт тратит стамину")
	var low := s.stamina
	s.touch_sprint = false
	for i in 30:
		s.update(1.0 / 60.0)
	assert_true(s.stamina > low, "отдых восстанавливает")


func test_endless_stamina() -> void:
	var s := _snake()
	s.endless_stamina = true
	s.touch_sprint = true
	for i in 120:
		s.update(1.0 / 60.0)
	assert_near(s.stamina, 1.0)


func test_touch_steer_turns_head() -> void:
	var s := _snake()
	s.heading = 0.0
	s.touch_steer = Vector2.DOWN
	for i in 60:
		s.update(1.0 / 60.0)
	assert_near(s.heading, PI / 2, 0.05, "голова повернулась к направлению стика")


func test_growth() -> void:
	var s := _snake()
	var n := s.length
	s.grow(3)
	assert_eq(s.length, n + 3)


func test_wall_hit_hurts() -> void:
	var s := _snake()
	s.head_pos = Vector2(30, 400)
	s.heading = PI
	s.update(1.0 / 60.0)
	assert_eq(s.lives, 2, "удар о бортик")


func test_safe_snake_takes_no_damage() -> void:
	var s := _snake()
	s.safe = true
	s.head_pos = Vector2(30, 400)
	s.heading = PI
	s.update(1.0 / 60.0)
	assert_eq(s.lives, 3, "после победы бортик не ранит")
	assert_true(s.alive)


func test_segments_cache_follows_movement() -> void:
	var s := _snake()
	var before := s.get_segments().duplicate()
	for i in 10:
		s.update(1.0 / 60.0)
	var after := s.get_segments()
	assert_ne(before[0], after[0], "кэш сегментов обновляется при движении")
	assert_eq(after[0], s.trail[0], "первый сегмент — начало следа")
	s.grow(4)
	for i in 30:
		s.update(1.0 / 60.0)
	assert_eq(s.get_segments().size(), (s.trail.size() + Snake.POINTS_PER_SEGMENT - 1) / Snake.POINTS_PER_SEGMENT,
		"после роста сегментов столько же, сколько в следе")
