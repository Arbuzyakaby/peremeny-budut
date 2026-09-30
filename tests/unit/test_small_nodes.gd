extends "res://tests/test_case.gd"
## Мелкие узлы мира, у которых раньше не было своих тестов: ударная волна, половинки скорлупки
## матрёшки, всплывашки и частицы, «Темнота», тело медведя (состояния, перерисовка по изменению вида).

const Shockwave = preload("res://scripts/entities/shockwave.gd")
const DollShell = preload("res://scripts/entities/doll_shell.gd")
const Fx = preload("res://scripts/game/fx.gd")
const Darkness = preload("res://scripts/game/darkness.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const BearBody = preload("res://scripts/entities/bear_body.gd")


# ---------------------------------------------------------------- ударная волна

func test_boss_wave_grows_and_finishes() -> void:
	var w: Shockwave = add(Shockwave.new())
	w.setup(Vector2(640, 360), 3)
	assert_len(w.gaps, 3, "три прохода в кольце")
	var r0 := w.radius
	w.update(0.5)
	assert_near(w.radius, r0 + w.speed * 0.5, 0.01, "радиус растёт со скоростью волны")
	assert_false(w.finished())
	w.update(10.0)
	assert_true(w.finished(), "дошла до края — закончилась")


func test_boss_wave_hits_only_on_the_ring_and_not_in_gaps() -> void:
	var w: Shockwave = add(Shockwave.new())
	w.setup(Vector2.ZERO, 2)
	w.gaps = [0.0, PI]  # проходы справа и слева
	w.radius = 200.0
	assert_true(w.hits(Vector2(0, 200)), "снизу на кольце — удар")
	assert_false(w.hits(Vector2(0, 100)), "внутри кольца — мимо")
	assert_false(w.hits(Vector2(0, 300)), "снаружи — мимо")
	assert_false(w.hits(Vector2(200, 0)), "в проходе справа — проскользнула")
	assert_false(w.hits(Vector2(-200, 5)), "и слева")
	w.hit_done = true
	assert_false(w.hits(Vector2(0, 200)), "волна бьёт один раз")


func test_stun_wave_has_no_gaps_and_short_reach() -> void:
	var w: Shockwave = add(Shockwave.new())
	w.setup_stun(Vector2(100, 100), 180.0)
	assert_true(w.stun)
	assert_len(w.gaps, 0, "у волны таблетки нет проходов")
	assert_eq(w.max_radius, 180.0)
	w.radius = 150.0
	for a in 8:
		assert_true(w.hits(Vector2(100, 100) + Vector2.from_angle(a * TAU / 8.0) * 150.0), "удар со всех сторон")
	await assert_draws(w, "волна оглушения")
	w.friendly = true
	await assert_draws(w, "волна змеи")


# ---------------------------------------------------------------- скорлупка матрёшки

func test_doll_shell_flies_slows_and_disappears() -> void:
	var s: DollShell = add(DollShell.new())
	s.setup(Vector2(300, 300), true, Color.RED, Color.YELLOW, 1.0, Vector2.RIGHT)
	assert_between(s.vel.length(), 160.0, 240.0, "разлетается")
	var v0 := s.vel.length()
	s._process(0.2)
	assert_gt(s.position.x, 300.0, "летит в сторону толчка")
	assert_lt(s.vel.length(), v0, "тормозит о пол")
	assert_gt(s.lift, 0.0, "верхняя половинка подпрыгивает")
	await assert_draws(s, "верх")
	s._process(DollShell.LIFE)
	await frames(1)
	assert_false(is_instance_valid(s), "растаяла и удалилась")


func test_bottom_shell_stays_on_the_floor() -> void:
	var s: DollShell = add(DollShell.new())
	s.setup(Vector2(300, 300), false, Color.BLUE, Color.WHITE, 0.6, Vector2.LEFT)
	s._process(0.3)
	assert_eq(s.lift, 0.0, "низ не подбрасывается")
	assert_lt(s.modulate.a, 1.01)
	await assert_draws(s, "низ")
	s._process(0.5)
	assert_lt(s.modulate.a, 0.5, "к концу жизни тает")


# ---------------------------------------------------------------- всплывашки и частицы

func test_popup_stays_inside_the_field() -> void:
	Settings.set_value("score_popups", true)
	var world: Node2D = add(Node2D.new())
	var fx := Fx.new(world)
	fx.popup(Vector2(5, 5), "НОКАУТ! +250", Color.YELLOW, true)
	fx.popup(Vector2(1279, 719), "+25", Color.YELLOW, true)
	assert_eq(world.get_child_count(), 2)
	for l: Label in world.get_children():
		var center := l.position + l.pivot_offset
		assert_between(center.x, 12.0, 1268.0, "надпись «%s» не за краем по X" % l.text)
		assert_between(center.y, 50.0, 720.0, "и по Y")


func test_score_popups_can_be_switched_off() -> void:
	var world: Node2D = add(Node2D.new())
	var fx := Fx.new(world)
	Settings.set_value("score_popups", false)
	fx.popup(Vector2(300, 300), "+25", Color.YELLOW, true)
	assert_eq(world.get_child_count(), 0, "очки выключены — надписи нет")
	fx.popup(Vector2(300, 300), "ЭТАП ПРОЙДЕН!", Color.YELLOW, false)
	assert_eq(world.get_child_count(), 1, "а обычная надпись осталась")
	Settings.set_value("score_popups", true)


func test_burst_respects_particle_quality() -> void:
	var world: Node2D = add(Node2D.new())
	var fx := Fx.new(world)
	fx.burst(Vector2(100, 100), Color.RED, 40)
	var p: CPUParticles2D = world.get_child(0)
	assert_eq(p.amount, maxi(int(round(40 * Settings.particle_mult())), 2), "число частиц по настройке качества")
	assert_true(p.one_shot and p.emitting)
	fx.burst(Vector2(100, 100), Color.RED, 0)
	assert_eq((world.get_child(1) as CPUParticles2D).amount, 2, "не меньше двух частиц")
	assert_true(p.scale_amount_curve == (world.get_child(1) as CPUParticles2D).scale_amount_curve,
		"кривая размера общая, а не новая на каждый взрыв")
	Fx.clear_cache()


# ---------------------------------------------------------------- «Темнота»

func test_darkness_covers_the_field_and_follows_the_head() -> void:
	var d: Darkness = add(Darkness.new())
	assert_eq(d.size, Vector2(1280, 720), "накрывает всё поле")
	assert_eq(d.mouse_filter, Control.MOUSE_FILTER_IGNORE, "не мешает нажатиям")
	assert_gt(d.z_index, 10, "поверх врагов")
	var m := d.material as ShaderMaterial
	assert_eq(m.get_shader_parameter("radius"), 190.0)
	d.follow(Vector2(200, 300))
	assert_eq(m.get_shader_parameter("center"), Vector2(200, 300), "пятно света над головой")


# ---------------------------------------------------------------- тело медведя

func _bear(type: int) -> TeddyBear:
	var b: TeddyBear = add(TeddyBear.new())
	b.setup(Vector2(400, 300), 60.0, Rect2(0, 0, 1280, 720), type, 1.0)
	return b


func test_bear_states_decide_what_the_snake_can_do() -> void:
	var b := _bear(BearBody.Type.BOXER)
	b.st = BearBody.St.ROAM
	b.no_eat_t = 0.0
	assert_true(b.is_edible(), "бродит — можно съесть")
	b.st = BearBody.St.DASH
	assert_false(b.is_edible(), "в рывке — нельзя")
	assert_true(b.is_ramming(), "рывок боксёра таранит")
	b.st = BearBody.St.DIZZY
	assert_true(b.is_dizzy())
	assert_true(b.is_edible(), "оглушённого — можно")
	b.shield_t = 2.0
	assert_true(b.is_shielded())
	assert_false(b.is_edible(), "под щитом медсестры — нельзя")


func test_normal_bear_with_a_grudge_rams() -> void:
	var a := _bear(BearBody.Type.NORMAL)
	var enemy := _bear(BearBody.Type.NORMAL)
	a.st = BearBody.St.ROAM
	assert_false(a.is_ramming(), "без обиды мирный")
	a.grudge = enemy
	a.grudge_t = 3.0
	assert_true(a.has_grudge())
	assert_true(a.is_ramming(), "обиженный медведь бросается")
	enemy.free()
	assert_false(a.has_grudge(), "обидчик пропал — обида прошла")


func test_bear_redraws_only_when_its_look_changes() -> void:
	var b := _bear(BearBody.Type.NORMAL)
	b.st = BearBody.St.ROAM
	b.refresh_look()
	var look: Array = b._last_look.duplicate()
	b.t += 0.5  # время идёт, но обычный медведь без анимации выглядит так же
	b.refresh_look()
	assert_eq(b._last_look, look, "тот же вид — без перерисовки")
	b.st = BearBody.St.DIZZY
	b.refresh_look()
	assert_ne(b._last_look, look, "оглушили — вид изменился")


func test_every_bear_type_and_state_draws() -> void:
	for type in BearBody.Type.values():
		var b := _bear(type)
		for st in [BearBody.St.ROAM, BearBody.St.WINDUP, BearBody.St.DIZZY, BearBody.St.AIM]:
			b.st = st
			b.shield_t = 1.0 if st == BearBody.St.AIM else 0.0
			await assert_draws(b, "медведь %d в состоянии %d" % [type, st])
		b.queue_free()
