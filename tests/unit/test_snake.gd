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


# ---------------------------------------------------------------- v12.4: движение и состояния подробнее

func test_reset_lays_the_body_straight_behind_the_head() -> void:
	var s := _snake()
	var segs := s.get_segments()
	assert_eq(segs[0], Vector2(640, 400), "первый сегмент — голова")
	assert_len(segs, s.length + 1, "сегментов — по длине")
	for i in range(1, segs.size()):
		assert_gt(segs[i].y, segs[i - 1].y, "тело уходит вниз: змея смотрит вверх")
		assert_near(segs[i].x, 640.0, 0.01)


func test_growth_lengthens_the_trail_as_it_moves() -> void:
	var s := _snake()
	var n0 := s.get_segments().size()
	s.grow(3)
	assert_gt(s.bite_t, 0.0, "проглотила — жуёт")
	for i in 60:
		s.update(1.0 / 60.0)
	assert_eq(s.get_segments().size(), n0 + 3, "тело выросло на три сегмента")


func test_slow_and_stun_scale_speed_and_respect_resist() -> void:
	var s := _snake()
	s.slow(1.0)
	assert_eq(s.slow_timer, 1.0)
	s.slow(0.2)
	assert_eq(s.slow_timer, 1.0, "короткое замедление не укорачивает длинное")
	s.resist = 0.5
	s.slow_timer = 0.0
	s.slow(1.0)
	assert_eq(s.slow_timer, 0.5, "стойкость вдвое сокращает замедление")
	var from := s.head_pos
	s.update(0.1)
	var slow_step := s.head_pos.distance_to(from)
	var fresh := _snake()
	from = fresh.head_pos
	fresh.update(0.1)
	assert_near(slow_step / fresh.head_pos.distance_to(from), 0.5, 0.05, "замедленная ползёт вдвое медленнее")


func test_dash_and_hop_grant_invulnerability() -> void:
	var s := _snake()
	s.dash(0.3)
	assert_true(s.is_dashing())
	assert_gt(s.invuln, 0.3, "в рывке неуязвима")
	assert_false(s.stun(1.0), "и не оглушается")
	var from := s.head_pos
	s.update(0.1)
	assert_near(s.head_pos.distance_to(from), Snake.DASH_SPEED * 0.1, 2.0, "летит со скоростью рывка")
	var h := _snake()
	h.hop(0.4)
	assert_true(h.is_hopping())
	h.update(0.2)
	assert_gt(h.small, 1.2, "в прыжке — ближе к камере (крупнее)")
	h.update(0.3)
	assert_false(h.is_hopping())
	assert_eq(h.small, 1.0, "приземлилась — обычного размера")


func test_push_turns_the_snake_and_fades() -> void:
	var s := _snake()
	s.push(Vector2(500, 0))
	assert_near(s.heading, 0.0, 0.001, "толчок разворачивает по направлению")
	s.update(0.1)
	assert_lt(s.knockback.length(), 500.0, "толчок гаснет")
	for i in 30:
		s.update(0.05)
	assert_eq(s.knockback, Vector2.ZERO)


func test_heal_is_capped_and_signals() -> void:
	var s := _snake()
	var got := []
	s.damaged.connect(func(n: int) -> void: got.append(n))
	assert_false(s.heal(), "полные жизни — лечить нечего")
	s.lives = 1
	assert_true(s.heal(5))
	assert_eq(s.lives, 3, "не больше максимума")
	assert_eq(got, [3], "табло узнаёт о лечении")


func test_phoenix_revives_once_with_two_lives() -> void:
	var s := _snake()
	s.apply_mods({"phoenix": true})
	s.lives = 1
	assert_true(s.take_damage(1, "bear"))
	assert_true(s.alive, "феникс восстал")
	assert_eq(s.lives, 2)
	assert_eq(s.stamina, 1.0, "и с полным баком")
	assert_gt(s.invuln, 2.5)
	s.invuln = 0.0
	s.lives = 1
	s.take_damage(1, "bear")
	assert_false(s.alive, "второй раз феникс не спасает")
	s.apply_mods({"phoenix": true})
	assert_false(s.phoenix, "использованный феникс не возвращается модами")


func test_self_bite_needs_a_long_body() -> void:
	var s := _snake()
	s.length = 30
	s.reset(Vector2(640, 200))
	s.invuln = 0.0
	var segs := s.get_segments()
	s.head_pos = segs[5]  # на шее: ближние сегменты не проверяются
	s._check_self_bite()
	assert_eq(s.lives, 3, "шея за головой не кусается")
	s.head_pos = segs[Snake.SELF_HIT_SKIP + 6]
	s._check_self_bite()
	assert_eq(s.lives, 2, "дальний сегмент — укусила себя")
	assert_eq(s.last_cause, "self")


func test_glide_moves_the_head_exactly() -> void:
	var s := _snake()
	s.glide_to(Vector2(700, 400), 0.016)
	assert_eq(s.head_pos, Vector2(700, 400), "в «Контакте» голова идёт точно по знаку")
	assert_near(s.heading, 0.0, 0.001, "и смотрит по ходу")


func test_autopilot_stays_inside_and_picks_new_targets() -> void:
	var s := _snake()
	s.autopilot = true
	s.auto_target = Vector2(640, 380)
	for i in 600:
		s._autopilot(1.0 / 60.0)
		assert_true(s.bounds.grow(-Snake.HEAD_RADIUS + 0.5).has_point(s.head_pos), "в пределах ящика")
	assert_ne(s.auto_target, Vector2(640, 380), "доехала — выбрала новую цель")


func test_every_look_draws() -> void:
	var s := _snake()
	for setup: Callable in [
			func() -> void: pass,
			func() -> void: s.shield = 1,
			func() -> void: s.hat = true,
			func() -> void: s.burnt = 0.7,
			func() -> void: s.rear = 1.0,
			func() -> void: s.stun_t = 1.0,
			func() -> void: s.dash(0.3, Snake.DASH_SPEED, true),
			func() -> void: s.hop(0.3)]:
		setup.call()
		await assert_draws(s, "змея")
