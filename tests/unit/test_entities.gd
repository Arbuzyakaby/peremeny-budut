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


# ---------------------------------------------------------------- v7.2: промахи и телеграфы

const OilDrop = preload("res://scripts/entities/oil_drop.gd")


func test_which_drops_stay_after_miss() -> void:
	for k in [OilDrop.Kind.BUTTON, OilDrop.Kind.TINE, OilDrop.Kind.NEEDLE, OilDrop.Kind.SHURIKEN]:
		assert_true(OilDrop.misses_visibly(k), "промах виден: %d" % k)
	for k in [OilDrop.Kind.OIL, OilDrop.Kind.WHITE, OilDrop.Kind.PEPPER, OilDrop.Kind.CRACKER]:
		assert_false(OilDrop.misses_visibly(k), "исчезает сразу: %d" % k)


func test_tine_miss_sticks_and_quivers() -> void:
	var d: OilDrop = add(OilDrop.new())
	d.setup(Vector2(1270, 300), Vector2(430, 0), OilDrop.Kind.TINE)
	d.begin_miss(AREA)
	assert_true(d.is_missed())
	assert_eq(d.vel, Vector2.ZERO)
	assert_true(AREA.has_point(d.position), "воткнулся в бортик изнутри")
	var p := d.position
	await frames(2)
	for i in 20:
		d.update(DT, Vector2.ZERO)
	assert_eq(d.position, p, "не двигается")
	assert_false(d.miss_done())
	for i in 15:
		d.update(DT, Vector2.ZERO)
	assert_true(d.miss_done(), "через ~0,5 с убрать")


func test_button_miss_rolls_back_inside() -> void:
	var d: OilDrop = add(OilDrop.new())
	d.setup(Vector2(20, 300), Vector2(-300, 40), OilDrop.Kind.BUTTON)
	d.begin_miss(AREA)
	assert_true(d.vel.x > 0.0, "отскочила от бортика внутрь")
	assert_between(d.vel.length(), 60.0, 150.0, "катится медленно")
	var p := d.position
	await frames(2)
	for i in 30:
		d.update(DT, Vector2.ZERO)
	assert_true(d.position.x > p.x, "катится")
	for i in 60:
		d.update(DT, Vector2.ZERO)
	assert_true(d.miss_done(), "потом исчезает")


func test_herding_pill_tint_and_feint_bear_draw() -> void:
	var p: Pill = add(Pill.new())
	p.setup(Vector2(400, 400), AREA, 1.0, 1.0, Pill.Kind.TABLET)
	p.herd = true
	for i in 30:
		p.update(DT, Vector2(900, 400), Vector2.ZERO, false)
	assert_near(p.herd_k, 1.0, 0.01)
	assert_ne(p.tint(Color.WHITE), Color.WHITE)
	var b := _bear(TeddyBear.Type.NORMAL)
	b.order = "decoy"
	b.feint = true
	var r := _bear(TeddyBear.Type.BOXER)
	r.order = "rescue"
	await frames(2)  # картонные звёзды, поднятая лапа, оттенок — рисуются без ошибок
	assert_false(b.is_dizzy(), "обманщик не оглушён по-настоящему")


# ---------------------------------------------------------------- v8.0: новая яичница

func _snake_at(p: Vector2) -> Snake:
	var s: Snake = add(Snake.new())
	s.bounds = AREA
	s.reset(p)
	return s


func test_boss_reads_orbit_far_and_close() -> void:
	var e := _boss()
	for i in 180:  # кружит вокруг на 260 px
		e.read_snake(e.position + Vector2.from_angle(i * DT * 2.0) * 260.0, DT)
	assert_eq(e.habit(), "orbit", "кружит")
	var far := _boss()
	for i in 300:
		far.read_snake(Vector2(1200, 650), DT)
	assert_eq(far.habit(), "far", "держится далеко")
	var close := _boss()
	for i in 300:
		close.read_snake(close.position + Vector2(170, 0), DT)
	assert_eq(close.habit(), "close", "липнет")


func test_boss_counters_habit() -> void:
	var e := _boss()
	var base := e.attack_weights(2, "")
	var orbit := e.attack_weights(2, "orbit")
	assert_gt(orbit[FriedEggBoss.Atk.CHARGE], base[FriedEggBoss.Atk.CHARGE], "против кружения — таран")
	var close := e.attack_weights(2, "close")
	assert_gt(close[FriedEggBoss.Atk.RING], base[FriedEggBoss.Atk.RING], "против липкой — кольцо")
	assert_false(e.attack_weights(1, "").has(FriedEggBoss.Atk.SIZZLE), "лужи — со второй фазы")
	assert_true(e.attack_weights(3, "").has(FriedEggBoss.Atk.PEPPER), "перчинки — на третьей")
	e.last_attack = FriedEggBoss.Atk.RING
	assert_false(e.attack_weights(1, "").has(FriedEggBoss.Atk.RING), "без повтора")


func test_boss_predicts_ahead_of_moving_head() -> void:
	var e := _boss()
	for i in 60:
		e.read_snake(Vector2(300 + i * 4.0, 600), DT)  # 240 px/с вправо
	var ahead := e.predict(Vector2(540, 600), 0.5)
	assert_gt(ahead.x, 600.0, "наперерез — впереди головы")


func test_boss_attack_starts_with_tell() -> void:
	var e := _boss()
	var s := _snake_at(Vector2(640, 650))
	e.begin_attack(FriedEggBoss.Atk.RING, s.head_pos)
	assert_eq(e.act, FriedEggBoss.Act.TELL, "сначала телеграф")
	var shots := [0]
	e.shoot.connect(func(_p: Vector2, _v: Vector2, _k: int) -> void: shots[0] += 1)
	for i in 20:
		e.update(DT, s)
	assert_eq(shots[0], 0, "во время телеграфа не стреляет")
	for i in 40:
		e.update(DT, s)
	assert_gt(shots[0], 0, "после телеграфа — кольцо")


func test_boss_charge_into_wall_opens_yolk() -> void:
	var e := _boss()
	var s := _snake_at(Vector2(640, 660))
	s.god = true
	var dazed := [""]
	e.dazed.connect(func(r: String) -> void: dazed[0] = r)
	e.act = FriedEggBoss.Act.CHARGE
	e.act_t = 2.0
	e.vel = Vector2(900, 0)
	for i in 60:
		e.update(DT, s)
		if e.act == FriedEggBoss.Act.DAZED:
			break
	assert_eq(e.act, FriedEggBoss.Act.DAZED, "таран в бортик — оглушена")
	assert_eq(dazed[0], "wall")
	assert_true(e.is_yolk_open(), "окно наказания: желток открыт")
	var hp := e.hp
	s.head_pos = e.position + FriedEggBoss.YOLK_OFFSET
	e.update(DT, s)
	assert_eq(e.hp, hp, "в первые мгновения оглушения укус не засчитан")
	for i in int(FriedEggBoss.DAZE_GRACE / DT) + 2:
		e.update(DT, s)
	assert_eq(e.hp, hp - 1, "укус в окне наказания снимает деление")


func test_boss_slam_ends_in_daze() -> void:
	var e := _boss()
	var s := _snake_at(Vector2(200, 650))
	s.god = true
	e.begin_attack(FriedEggBoss.Atk.SLAM, s.head_pos)
	assert_eq(e.act, FriedEggBoss.Act.JUMP)
	for i in 120:
		e.update(DT, s)
		if e.act == FriedEggBoss.Act.DAZED:
			break
	assert_eq(e.act, FriedEggBoss.Act.DAZED, "после прыжка вязнет в сковороде")
	assert_eq(e.daze_reason, "slam")


func test_boss_puddle_tells_then_burns() -> void:
	var e := _boss()
	var s := _snake_at(Vector2(300, 600))
	e.add_puddle(s.head_pos)
	var lives := s.lives
	e.update(DT, s)
	assert_eq(s.lives, lives, "пузырится — ещё не жжёт")
	for i in int(FriedEggBoss.PUDDLE_TELL / DT) + 2:
		e.update(DT, s)
	assert_eq(s.lives, lives - 1, "горящее масло жжёт")
	for i in int((FriedEggBoss.PUDDLE_BURN + 0.6) / DT):
		e.update(DT, s)
	assert_true(e.puddles.is_empty(), "лужа догорела")


func test_boss_phase_change_roars_and_is_invulnerable() -> void:
	var e := _boss()
	var phases := []
	e.phase_changed.connect(func(p: int) -> void: phases.append(p))
	e.dev_set_hp(9)
	e.act = FriedEggBoss.Act.IDLE
	e.take_chip(1.0)
	assert_eq(phases, [2])
	assert_eq(e.act, FriedEggBoss.Act.ROAR, "новая фаза — рёв")
	assert_eq(e.phase_name(), "ПОДГОРАЕТ")
	var hp := e.hp
	assert_false(e.take_chip(5.0), "в рёве неуязвима")
	assert_eq(e.hp, hp)
