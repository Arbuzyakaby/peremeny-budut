extends "res://tests/integration/game_case.gd"
## Пожар финала (fire.gd): поджигается, охватывает ящик и сжигает то, что в нём, тушится пеной,
## после себя оставляет золу; пропуск финала сразу даёт выгоревший ящик. Обломки битвы лежат
## на своих материалах (на любом сиде). Первое возгорание — событие (тишина, вспышка, удар),
## треск следует за силой огня, огнетушитель приглушает огонь, интерфейс паникует и успокаивается.

const Fire = preload("res://scripts/ending/fire.gd")
const FireSim = preload("res://scripts/ending/fire_sim.gd")
const Ending = preload("res://scripts/ending/ending.gd")
const Credits = preload("res://scripts/ending/credits.gd")
const Design = preload("res://scripts/ui/design.gd")


func after_each() -> void:
	Design.panic = 0.0
	await super()


func _fire(seed_value := 0) -> Fire:
	var f := Fire.new()
	f.seed_value = seed_value
	add(f)
	return f


func _run(f: Fire, seconds: float) -> void:
	for i in int(seconds * 12.0):
		f._process(1.0 / 12.0)


func test_fire_spreads_and_covers() -> void:
	var f := _fire()
	assert_false(f.covers(Vector2(640, 360)), "до поджига не горит")
	f.start(Vector2(640, 360))
	_run(f, 1.0)
	assert_true(f.covers(Vector2(640, 360)), "в точке поджига горит")
	assert_gt(f.coverage(), 0.0)
	var r1 := f.radius
	_run(f, 3.0)
	assert_gt(f.radius, r1, "огонь расползается")
	assert_true(f.rect != null and f.rect.material is ShaderMaterial, "рисуется шейдером")


func test_extinguish_keeps_ash() -> void:
	var f := _fire()
	f.start(Vector2(640, 360))
	_run(f, 4.0)
	var ash := f.ash_amount()
	var burnt := f.burnt_cells()
	f.extinguish(1.0)
	_run(f, 4.0)
	assert_eq(f.sim.burning_cells, 0, "потушен")
	assert_true(f.ash_amount() >= ash - 0.0001, "зола осталась")
	assert_true(f.burnt_cells() >= burnt, "сожжённое не восстанавливается")
	assert_near(f.coverage(), 0.0, 0.0001)
	assert_false(f.covers(Vector2(640, 360)))


func test_skip_burns_out_instantly() -> void:
	var f := _fire()
	f.fill_instantly()
	assert_true(f.active)
	assert_eq(f.sim.burning_cells, 0)
	assert_gt(f.ash_amount(), 0.1, "сразу пепелище")
	assert_eq(f.burnt_cells(), f.sim.fuel_cells(), "сгорело всё")


func test_debris_lie_on_their_materials() -> void:
	for sd in [0, 1, 17, 12345]:
		var f := _fire(sd)
		assert_eq(f.layout.size(), Fire.DEBRIS.size() + 4, "обломки и по затравке под каждой капсулой")
		for d: Array in f.layout:
			assert_eq(int(f.sim.mat[f.sim.index_at(d[1])]), Fire.MAT_OF[d[0]], "сид %d: %s в %s" % [sd, d[0], str(d[1])])
		assert_eq(int(f.sim.mat[f.sim.index_at(Vector2(10, 360))]), FireSim.Mat.WOOD, "бортик — дерево")
		f.free()
	var a := _fire(1)
	var b := _fire(2)
	assert_ne(str(a.layout), str(b.layout), "раскладка зависит от сида")


func test_glow_color_follows_temperature() -> void:
	var cold := Fire.glow_color(300.0)
	var hot := Fire.glow_color(1400.0)
	assert_true(hot.get_luminance() > cold.get_luminance(), "чем горячее, тем светлее")
	assert_true(Fire.glow_color(700.0).r > Fire.glow_color(700.0).b, "накал — красно-оранжевый")
	var peak := Fire.glow_color(FireSim.MAX_T)
	assert_true(peak.r > 0.95 and peak.g > 0.9 and peak.b > 0.7 and peak.b < peak.g, "пик — бело-жёлтый: %s" % str(peak))
	var real_peak := Fire.glow_color(1250.0)  # столько реально набирают горящие клетки
	assert_true(real_peak.g > 0.85 and real_peak.b > 0.6, "и у реального пика пламени — бело-жёлтый: %s" % str(real_peak))


func test_crackle_follows_fire_both_ways() -> void:
	assert_true(Ending.crackle_rate(0.05) < 2.0, "огонёк — редкие щелчки")
	assert_true(Ending.crackle_rate(1.0) > 10.0, "весь ящик — плотный треск")
	assert_true(Ending.crackle_db(0.05) < -10.0, "огонёк — тихо")
	assert_true(Ending.crackle_db(1.0) >= -1.0, "пожар — громко")
	var last_rate := -1.0
	var last_db := -99.0
	for k in 11:
		var c := k / 10.0
		assert_true(Ending.crackle_rate(c) > last_rate and Ending.crackle_db(c) > last_db, "монотонно при %.1f" % c)
		last_rate = Ending.crackle_rate(c)
		last_db = Ending.crackle_db(c)
	assert_near(Ending.panic_level(0.0), 0.0, 0.0001, "нет огня — нет паники")
	assert_near(Ending.panic_level(1.0), 1.0, 0.0001)


func test_protocol_shows_burnt_cells() -> void:
	assert_eq(Credits.burnt_line(1), "Сожжено: 1 клетка")
	assert_eq(Credits.burnt_line(3), "Сожжено: 3 клетки")
	assert_eq(Credits.burnt_line(12), "Сожжено: 12 клеток")
	assert_eq(Credits.burnt_line(2021), "Сожжено: 2021 клетка")
	await boot()
	var text := Credits.text(game, "", 1234)
	assert_true("Сожжено: 1234 клетки" in text, "строка в протоколе эксперимента")
	assert_false("Сожжено" in Credits.text(game, ""), "без числа строки нет")


## Финал до броска спички: сцена сразу к моменту падения.
func _ending_at_match() -> Ending:
	await boot()
	game.args["ending"] = true
	game.debug_run = true
	game.start_game(1)
	await frames(2)
	var e: Ending = game.ending
	e.tw.kill()
	return e


func test_first_ignition_is_an_event() -> void:
	var e := await _ending_at_match()
	var sfx = game.sfx
	e._ignite()
	assert_true(sfx.is_hushed(), "сначала — полная тишина")
	if sfx.music_player.playing:  # в тестах трек может быть ещё не собран — тогда и паузить нечего
		assert_true(sfx.music_player.stream_paused, "музыка на паузе")
	assert_false(e.fire.active, "в тишине ещё не вспыхнуло")
	await wait_until(func() -> bool: return e.fire.active, 2.0)
	assert_true(e.fire.active, "вспыхнуло после тишины")
	assert_false(sfx.is_hushed(), "тишина кончилась к удару")
	assert_gt(game.hud.overlay.white_flash, 0.0, "белая вспышка экрана")
	assert_gt(game.shake, 0.0, "тряска")
	var loud := false
	for i in sfx.players.size():
		if sfx.voice_names[i] == "ignite" and sfx.players[i].volume_db >= -4.0 + Ending.IGNITE_DB - 1.01:
			loud = true
	assert_true(loud, "«ignite» в полную силу (volume_db ≥ 0)")
	await wait_until(func() -> bool: return not sfx.music_player.stream_paused, 1.0)
	assert_false(sfx.music_player.stream_paused, "музыка вернулась через ~100 мс")


func test_calm_flash_respects_settings() -> void:
	await boot()
	var ov = game.hud.overlay
	ov.flash(1.0)
	var full: float = ov.white_flash
	ov.white_flash = 0.0
	Settings.set_value("reduced_motion", true)
	ov.flash(1.0)
	assert_true(ov.white_flash < full, "«меньше анимации» — вспышка мягче")
	Design.panic = 1.0
	assert_eq(ov.panic_jitter(), Vector2.ZERO, "и без дрожи")
	Settings.set_value("reduced_motion", false)


func test_extinguisher_ducks_fire_and_panic_settles() -> void:
	var e := await _ending_at_match()
	e._ignite()
	await wait_until(func() -> bool: return e.fire.active, 2.0)
	for i in 60:  # 3 с пожара
		e.fire._process(1.0 / 20.0)
		e._process(1.0 / 20.0)
	assert_gt(Design.panic, 0.05, "интерфейс паникует вместе с пожаром")
	assert_gt(e.crackles, 3, "огонь трещит")
	e.lab.holding = Ending.Lab.Hold.EXTINGUISHER
	e._spray()
	assert_near(game.sfx.duck_db(), -4.0, 0.01, "огнетушитель приглушил огонь (ducking −4 дБ)")
	await wait_until(func() -> bool: return game.sfx.duck_db() > -0.01, 2.0)
	assert_near(game.sfx.duck_db(), 0.0, 0.01, "и отпустил")
	for i in 120:  # тушение: огонь опадает — паника уходит
		e.fire._process(1.0 / 20.0)
		e._process(1.0 / 20.0)
	await wait_until(func() -> bool: return e.fire.strength <= 0.0, 4.0)
	for i in 60:
		e.fire._process(1.0 / 20.0)
		e._process(1.0 / 20.0)
	assert_true(Design.panic < 0.05, "потушили — интерфейс успокоился: %.2f" % Design.panic)
	e.skip()
	assert_eq(Design.panic, 0.0, "после пропуска — ноль")
