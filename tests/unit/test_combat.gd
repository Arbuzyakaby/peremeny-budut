extends "res://tests/test_case.gd"
## Боевые расчёты и геометрия вилки: бить можно сбоку и сзади, но не в лоб.

const Combat = preload("res://scripts/core/combat.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")

var normal: Dictionary = Balance.DIFFICULTIES[1]


func test_boss_chip_scales_with_fangs() -> void:
	assert_near(Combat.boss_chip("fork", {}), 0.5)
	assert_near(Combat.boss_chip("fork", {"boss_dmg": 2.0}), 1.0)


func test_shot_into_open_yolk_is_triple() -> void:
	var plain := Combat.shot_chip(true, false, {})
	assert_near(Combat.shot_chip(true, true, {}), plain * 3.0)
	assert_true(Combat.shot_chip(true, false, {}) > Combat.shot_chip(false, false, {}), "пуговица сильнее иглы")


func test_points_use_difficulty_multiplier() -> void:
	assert_eq(Combat.points(10, Balance.DIFFICULTIES[0]), 10)
	assert_eq(Combat.points(10, Balance.DIFFICULTIES[3]), 50)


func test_dizzy_bear_worth_more() -> void:
	var base := Combat.bear_points(TeddyBear.Type.BOXER, false, normal, {})
	assert_eq(Combat.bear_points(TeddyBear.Type.BOXER, true, normal, {}), base * 2)
	assert_eq(Combat.bear_points(TeddyBear.Type.BOXER, true, normal, {"knockout": 3}), base * 3)


func test_ability_charges_and_cost_mods() -> void:
	assert_eq(Combat.ability_charges(2, {}), 8)
	assert_eq(Combat.ability_charges(2, {"charges": 3}), 11)
	assert_near(Combat.ability_cost(1, {"cost": 0.5}), 0.125)


func _fork_facing_right() -> Fork:
	var f: Fork = add(Fork.new())
	f.setup(Vector2(500, 300), Rect2(0, 0, 1280, 720), 1.0, 1.0, 1.0)
	f.rotation = 0.0  # зубцы смотрят вправо (+X)
	return f


func test_fork_front_hit_is_tines() -> void:
	var f := _fork_facing_right()
	assert_true(f.hits_tines(Vector2(500 + 45, 300)), "спереди — зубцы")
	assert_true(f.touches(Vector2(500 + 45, 300), 16.0))


func test_fork_side_and_back_are_safe() -> void:
	var f := _fork_facing_right()
	assert_false(f.hits_tines(Vector2(500, 300 + 30)), "сбоку — можно кусать")
	assert_false(f.hits_tines(Vector2(500 - 60, 300)), "сзади — можно кусать")
	assert_true(f.touches(Vector2(500, 300 + 20), 16.0), "сбоку касается")


func test_fork_far_point_does_not_touch() -> void:
	var f := _fork_facing_right()
	assert_false(f.touches(Vector2(500, 300 + 200), 16.0))
