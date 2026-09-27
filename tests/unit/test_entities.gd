extends "res://tests/test_case.gd"
## Враги: автомат вилки, прыжок таблетки, медведи (щит, френдли фаер), яичница (урон, фазы).

const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const Snake = preload("res://scripts/entities/snake.gd")

const AREA := Rect2(24, 24, 1232, 672)
const DT := 1.0 / 60.0


func before_each() -> void:
	use_temp_storage()


func test_fork_aims_then_sprints_at_snake() -> void:
	var f: Fork = add(Fork.new())
	f.setup(Vector2(300, 360), AREA, 1.0, 1.0, 1.0)
	f.rotation = 0.0
	f.attack_cd = 0.0
	var head := Vector2(900, 360)
	var seen := {}
	for i in 240:
		f.update(DT, head, true)
		seen[f.st] = true
	assert_true(seen.has(Fork.St.AIM), "прицеливается")
	assert_true(seen.has(Fork.St.SPRINT), "спринтует")


func test_fork_gets_stuck_in_wall() -> void:
	var f: Fork = add(Fork.new())
	f.setup(Vector2(1150, 360), AREA, 1.0, 1.0, 1.0)
	f.rotation = 0.0
	f.st = Fork.St.SPRINT
	f.st_t = 1.0
	f.vel = Vector2(700, 0)
	for i in 30:
		f.update(DT, Vector2(200, 360), true)
		if f.st == Fork.St.STUCK:
			break
	assert_eq(f.st, Fork.St.STUCK, "врезалась в бортик и застряла")


func test_pill_jumps_and_lands() -> void:
	var p: Pill = add(Pill.new())
	p.setup(Vector2(400, 400), AREA, 1.0, 1.0)
	await frames(30)  # появление (spawn_k)
	var landed := []
	p.landed.connect(func(pos: Vector2) -> void: landed.append(pos))
	var was_in_air := false
	var edible_in_air := false
	for i in 400:
		p.update(DT, Vector2(600, 400), Vector2.ZERO, true)
		if p.in_air():
			was_in_air = true
			edible_in_air = edible_in_air or p.is_edible()
		if not landed.is_empty():
			break
	assert_true(was_in_air, "прыгнула")
	assert_false(edible_in_air, "в воздухе съесть нельзя")
	assert_eq(landed.size(), 1, "приземлилась")
	assert_true(p.is_edible(), "на земле — можно съесть")


func test_tablet_rolls_and_hops_low() -> void:
	var p: Pill = add(Pill.new())
	p.setup(Vector2(300, 400), AREA, 1.0, 1.0, Pill.Kind.TABLET)
	await frames(30)
	assert_eq(p.bestiary_key(), "pill_1")
	p.st_t = 5.0  # не прыгать — только катиться
	var start := p.position
	for i in 30:
		p.update(DT, Vector2(900, 400), Vector2.ZERO, true)
	assert_gt(p.position.x, start.x + 10.0, "шайба катится к змее")
	p.st_t = 0.0
	var landed := []
	p.landed.connect(func(pos: Vector2) -> void: landed.append(pos))
	var top := 0.0
	for i in 400:
		p.update(DT, Vector2(900, 400), Vector2.ZERO, true)
		top = maxf(top, p.height)
		if not landed.is_empty():
			break
	assert_eq(landed.size(), 1, "атака та же: прыжок и приземление")
	assert_gt(float(Pill.KINDS[Pill.Kind.CAPSULE]["height"]), top, "прыгает ниже капсулы")


func test_capsule_stays_put() -> void:
	var p: Pill = add(Pill.new())
	p.setup(Vector2(300, 400), AREA, 1.0, 1.0)
	await frames(30)
	p.st_t = 5.0
	var start := p.position
	for i in 30:
		p.update(DT, Vector2(900, 400), Vector2.ZERO, true)
	assert_eq(p.position, start, "капсула между прыжками стоит")


func _bear(type: int) -> TeddyBear:
	var b: TeddyBear = add(TeddyBear.new())
	b.setup(Vector2(500, 300), 60.0, AREA, type, 1.0)
	return b


func test_shielded_bear_is_not_edible() -> void:
	var b := _bear(TeddyBear.Type.NORMAL)
	b.no_eat_t = 0.0
	assert_true(b.is_edible())
	b.give_shield()
	assert_false(b.is_edible())
	b.pop_shield()
	assert_false(b.is_shielded())


func test_friendly_fire_dizzies_and_sets_grudge() -> void:
	var victim := _bear(TeddyBear.Type.NORMAL)
	var attacker := _bear(TeddyBear.Type.BOXER)
	assert_true(victim.hit_by_friend(attacker, Vector2(100, 0)))
	assert_true(victim.is_dizzy())
	assert_eq(victim.grudge, attacker)
	assert_false(victim.hit_by_friend(attacker, Vector2.ZERO), "короткая неуязвимость после удара")


func test_shield_takes_friendly_hit() -> void:
	var b := _bear(TeddyBear.Type.NORMAL)
	b.give_shield()
	assert_false(b.hit_by_friend(null, Vector2(50, 0)))
	assert_false(b.is_shielded(), "пузырь лопнул")
	assert_false(b.is_dizzy())


func test_every_bear_type_updates() -> void:
	var s: Snake = add(Snake.new())
	s.reset(Vector2(640, 500))
	for type in TeddyBear.Type.size():
		var b := _bear(type)
		for i in 120:
			b.update(DT, s)
		assert_true(AREA.grow(1.0).has_point(b.position), "медведь %d остался на арене" % type)


func _boss() -> FriedEggBoss:
	var e: FriedEggBoss = add(FriedEggBoss.new())
	e.bounds = AREA
	e.configure(12, 1.0, 1.0, 1.0)
	e.position = Vector2(640, 300)
	e.active = true
	return e


func test_boss_chips_add_up_to_damage() -> void:
	var e := _boss()
	var hp := e.hp
	assert_true(e.take_chip(0.6))
	assert_eq(e.hp, hp, "0.6 — ещё не деление")
	e.take_chip(0.6)
	assert_eq(e.hp, hp - 1)


func test_boss_phases_and_defeat() -> void:
	var e := _boss()
	var phases := []
	var defeated := [false]
	e.phase_changed.connect(func(p: int) -> void: phases.append(p))
	e.defeated.connect(func() -> void: defeated[0] = true)
	e.dev_set_hp(7)
	e.act = FriedEggBoss.Act.IDLE
	e.take_chip(1.0)
	assert_eq(e.phase(), 2)
	e.dev_set_hp(0)
	assert_true(defeated[0], "побеждена")
	assert_false(e.take_chip(1.0), "мёртвую не ранить")
