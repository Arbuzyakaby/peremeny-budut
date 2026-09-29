extends "res://tests/test_case.gd"
## Audio Rebound (v11.0): формулы акустики сверены со справочными значениями, трассировка лучей —
## со статистической теорией (Эйринг), отражения несут направление (панорама), материалы звучат по-разному,
## пожар и углекислый газ меняют звук, шина World получает осмысленные параметры и выключается настройкой.

const Acoustics = preload("res://scripts/audio/rebound/acoustics.gd")
const Tracer = preload("res://scripts/audio/rebound/tracer.gd")
const Rebound = preload("res://scripts/audio/rebound/rebound.gd")
const Tex = preload("res://scripts/gfx/tex.gd")
const FireSim = preload("res://scripts/ending/fire_sim.gd")


func before_each() -> void:
	use_temp_storage()


func test_speed_of_sound_follows_temperature_and_gas() -> void:
	assert_near(Acoustics.speed_of_sound(20.0), 343.2, 0.6, "воздух при 20 °C")
	assert_near(Acoustics.speed_of_sound(0.0), 331.3, 0.6, "воздух при 0 °C")
	assert_near(Acoustics.speed_of_sound(20.0, Acoustics.GAS["co2"]), 267.0, 2.0, "углекислый газ медленнее")
	assert_gt(Acoustics.speed_of_sound(800.0), 640.0, "в горячем воздухе звук быстрее: c ∝ √T")
	var mix := Acoustics.mixture({"air": 0.7, "co2": 0.3})
	assert_between(Acoustics.speed_of_sound(20.0, mix), 267.0, 343.0, "смесь — между газами")


func test_air_absorption_matches_iso_9613() -> void:
	# ISO 9613-1, таблица 1: 20 °C, 50 %, дБ/км
	var ref := [0.44, 1.31, 2.73, 4.66, 9.86, 29.7]
	for b in Acoustics.NB:
		var got := Acoustics.air_absorption_db(Acoustics.BANDS[b]) * 1000.0
		assert_near(got, ref[b], ref[b] * 0.1, "%d Гц: %.2f дБ/км" % [int(Acoustics.BANDS[b]), got])
	assert_gt(Acoustics.air_absorption_db(4000.0, 20.0, 20.0), Acoustics.air_absorption_db(4000.0, 20.0, 80.0),
		"сухой воздух глушит 4 кГц сильнее влажного")


func test_sabine_and_eyring() -> void:
	var surf := [[80.0, "plaster"], [80.0, "linoleum"], [108.0, "plaster"]]  # 10 × 8 × 3 м
	var t_s := Acoustics.sabine(240.0, surf, Acoustics.MID)
	var a := 80.0 * 0.03 + 80.0 * 0.03 + 108.0 * 0.03
	assert_near(t_s, 0.161 * 240.0 / a, 0.05, "Сэбин: 0,161·V/A")
	var t_e := Acoustics.eyring(240.0, surf, Acoustics.MID)
	assert_true(t_e < t_s, "Эйринг всегда короче Сэбина")
	assert_near(t_e / t_s, 1.0, 0.03, "при малом поглощении они сходятся")
	var loud := [[268.0, "rug"]]
	assert_true(Acoustics.eyring(240.0, loud, Acoustics.MID) < Acoustics.sabine(240.0, loud, Acoustics.MID) * 0.85,
		"а при большом — заметно расходятся")
	assert_near(Acoustics.mean_free_path(240.0, 268.0), 4.0 * 240.0 / 268.0, 1e-4, "свободный пробег 4V/S")


func test_schroeder_decay_times() -> void:
	var bin := 0.002
	var h := PackedFloat32Array()
	for i in 1500:  # идеальный экспоненциальный спад с T60 = 1 с
		h.append(exp(-i * bin * 6.0 * log(10.0) / 1.0))
	var edc := Acoustics.schroeder_db(h)
	assert_near(edc[0], 0.0, 1e-4, "кривая начинается с 0 дБ")
	assert_near(Acoustics.t30(edc, bin), 1.0, 0.03, "T30")
	assert_near(Acoustics.t20(edc, bin), 1.0, 0.03, "T20")
	assert_near(Acoustics.edt(edc, bin), 1.0, 0.05, "EDT")
	assert_near(Acoustics.center_time(h, bin), 1.0 / (6.0 * log(10.0)), 0.004, "Ts = τ для экспоненты")


func test_ray_tracing_agrees_with_eyring() -> void:
	var size := Vector3(3.0, 4.0, 5.0)
	var scene := {"size": size, "faces": ["rug", "rug", "rug", "rug", "rug", "rug"], "listener": Vector3(1.2, 2.3, 2.1),
		"sources": [Vector3(1.9, 1.4, 2.8)], "rays": 3000, "seed": 3, "t_max": 0.4, "bin": 0.001, "receiver_r": 0.4}
	var res := Tracer.trace(scene)
	var a := Tracer.analyze(res)
	var surf := [[2.0 * (12.0 + 15.0 + 20.0), "rug"]]
	var expect := Acoustics.eyring(60.0, surf, Acoustics.MID, Acoustics.air_m(Acoustics.MID))
	var got := float(a["bands"][Acoustics.MID]["t20"])
	print("    трассировка T20 %.3f с, Эйринг %.3f с" % [got, expect])
	assert_near(got, expect, expect * 0.35, "трассировка сходится со статистической теорией")
	assert_gt(int(res["hits"]), 100, "лучи доходят до приёмника")


func test_open_room_has_no_reflections() -> void:
	var scene := {"size": Vector3(2, 2, 2), "faces": ["open", "open", "open", "open", "open", "open"],
		"listener": Vector3(1, 1, 1), "sources": [Vector3(1.5, 1, 1)], "rays": 400, "seed": 1}
	var res := Tracer.trace(scene)
	assert_eq(int(res["hits"]), 0, "в свободном поле отражений нет")
	assert_near(float(res["escape"][Acoustics.MID]), 1.0, 0.01, "вся энергия ушла")
	assert_near(float(res["direct"]), 1.0 / 0.25, 0.01, "прямой звук — 1/r²")


func test_tracing_is_deterministic() -> void:
	var s := Rebound.box_scene(Vector2(300, 300), Rebound.static_floor(Tex.Floor.TILES), [], 64, 11)
	var a := Tracer.trace(s)
	var b := Tracer.trace(s)
	assert_eq(a["hist"][3], b["hist"][3], "одна сцена и сид — один отклик")
	var c := Tracer.trace(Rebound.box_scene(Vector2(300, 300), Rebound.static_floor(Tex.Floor.TILES), [], 64, 12))
	assert_ne(a["hist"][3], c["hist"][3], "другой сид — другая выборка лучей")


func _early(kind: int, head := Vector2(640, 360)) -> float:
	var res := Tracer.trace(Rebound.box_scene(head, Rebound.static_floor(kind), [], 800, 5))
	var sum := 0.0
	for b in [3, 4, 5]:
		for v in res["hist"][b]:
			sum += v
	return sum


func test_materials_sound_different() -> void:
	var tiles := _early(Tex.Floor.TILES)
	var velvet := _early(Tex.Floor.DRAWER)
	var rug := _early(Tex.Floor.WOOD)  # в центре детской — вязаный коврик
	print("    отражённая энергия 1–4 кГц: плитка %.2f, бархат %.2f, коврик %.2f" % [tiles, velvet, rug])
	assert_gt(tiles, velvet * 1.3, "плитка звонче бархата")
	assert_gt(tiles, rug * 1.3, "и коврика")


func test_reflection_comes_from_the_near_wall() -> void:
	var s := Rebound.box_scene(Vector2(60, 360), Rebound.static_floor(Tex.Floor.TILES), [], 800, 2)
	var a := Tracer.analyze(Tracer.trace(s))
	var taps: Array = a["taps"]
	assert_gt(taps.size(), 0, "есть ранние отражения")
	var left := 0.0
	for t: Dictionary in taps:
		left = minf(left, float(t["pan"]))
	assert_true(left < -0.1, "у левого бортика отражение слышно слева: %s" % str(taps))


func test_obstacle_casts_acoustic_shadow() -> void:
	var head := Vector2(640, 360)
	var free := Tracer.trace(Rebound.box_scene(head, Rebound.static_floor(Tex.Floor.TILES), [], 16, 1))
	var sp: Array = []
	for k in 4:  # плюшевые медведи вплотную на всех четырёх путях к источникам
		var p := head + Vector2.from_angle(k * PI / 2.0 + 0.4) * 120.0
		sp.append(Rebound.obstacle(p, 18.0, 0.0, "plush"))
	var shaded := Tracer.trace(Rebound.box_scene(head, Rebound.static_floor(Tex.Floor.TILES), sp, 16, 1))
	assert_true(float(shaded["direct"]) < float(free["direct"]) * 0.6, "медведь заслоняет прямой звук")
	var cap := Rebound.obstacle(Vector2(640, 360), 150.0, 30.0, "egg_white")
	var top: Vector3 = cap[0] + Vector3(0, 0, cap[1])
	assert_near(top.z, 30.0 * Rebound.PX_M, 1e-5, "яичница — плоский сегмент высотой 30 px")


func test_floor_grid_and_fire_marks() -> void:
	var g := Rebound.static_floor(Tex.Floor.WOOD)
	var center := int(Rebound.GRID.y / 2) * Rebound.GRID.x + Rebound.GRID.x / 2
	assert_eq(String(g["palette"][g["cells"][center]]), "rug", "посреди детской — коврик")
	assert_eq(String(g["palette"][g["cells"][0]]), "wood_floor", "в углу — доски")
	var r := Rebound.new()
	add(r)
	var fire := FireSim.new(96, 54, Rect2(0, 0, 1280, 720))
	for i in fire.charred.size():
		fire.charred[i] = 1.0
		fire.ash[i] = 1.0
	var burnt := r.floor_grid(Tex.Floor.WOOD, fire)
	assert_eq(String(burnt["palette"][burnt["cells"][center]]), "ash", "после пожара — зола")


func test_hot_air_shortens_delays() -> void:
	var fl := Rebound.static_floor(Tex.Floor.TILES)
	var cold := Tracer.analyze(Tracer.trace(Rebound.box_scene(Vector2(80, 360), fl, [], 400, 4, 20.0)))
	var hot := Tracer.analyze(Tracer.trace(Rebound.box_scene(Vector2(80, 360), fl, [], 400, 4, 600.0)))
	assert_true(float(hot["direct_t"]) < float(cold["direct_t"]) * 0.8, "горячий воздух — звук быстрее")


func test_bus_params_are_physical() -> void:
	var r := Rebound.new()
	add(r)
	var tiles := r.compute_now(Rebound.box_scene(Vector2(640, 360), Rebound.static_floor(Tex.Floor.TILES), [], 800, 1))
	assert_false(tiles["reverb_on"], "в ящике нет хвоста — ни гула, ни эха")
	assert_near(float(r.reverb.wet), 0.0, 1e-6, "и на шине он выключен")
	var top := -99.0
	for g in tiles["eq"]:
		top = maxf(top, g)
		assert_between(g, -Rebound.EQ_DEPTH, 0.0, "эквалайзер только срезает: с отражениями не громче")
	assert_near(top, 0.0, 0.5, "самая громкая полоса — без изменений")
	var velvet := r.compute_now(Rebound.box_scene(Vector2(640, 360), Rebound.static_floor(Tex.Floor.DRAWER), [], 800, 1))
	assert_true(float(velvet["eq_octaves"][5]) < float(tiles["eq_octaves"][5]) - 0.1,
		"бархат глушит верха сильнее плитки: %.2f < %.2f" % [velvet["eq_octaves"][5], tiles["eq_octaves"][5]])
	assert_near(r.eq.get_band_gain_db(5), float(velvet["eq"][5]), 0.06, "окраска дошла до шины")
	assert_between(float(velvet["flutter_ms"]), 3.0, 10.0, "период 2L/c для 0,84 м ≈ 4,9 мс (для справки)")
	var lab := r.compute_now(Rebound.lab_scene(300))
	assert_true(lab["reverb_on"], "в лаборатории — хвост комнаты")
	assert_between(float(r.reverb.wet), 0.01, Rebound.WET_MAX_LAB, "тихий")
	assert_gt(float(lab["t60"]), 0.6, "лаборатория гулкая: штукатурка и линолеум")
	assert_true(r.summary().begins_with("Audio Rebound: лаборатория"), r.summary())


func test_eq_changes_slowly() -> void:
	var r := Rebound.new()
	add(r)
	r.target = {"eq": PackedFloat32Array([-6, -6, -6, -6, -6, -6]), "reverb_on": false}
	r.current = {"eq": PackedFloat32Array([0, 0, 0, 0, 0, 0])}
	r._approach(0.1)
	assert_near(r.eq.get_band_gain_db(0), -Rebound.EQ_RATE * 0.1, 0.01, "за 0,1 с — только на 0,15 дБ: без щелчков")


func test_setting_bypasses_effects() -> void:
	var r := Rebound.new()
	add(r)
	var idx := AudioServer.get_bus_index(Rebound.BUS)
	assert_true(idx >= 0, "шина World есть")
	assert_eq(AudioServer.get_bus_send(idx), &"SFX", "и отправляет в SFX — громкость эффектов общая")
	Settings.set_value("rebound", false)
	for i in AudioServer.get_bus_effect_count(idx):
		assert_false(AudioServer.is_bus_effect_enabled(idx, i), "выключено — отражений нет")
	Settings.set_value("rebound", true)
	for i in AudioServer.get_bus_effect_count(idx):
		assert_true(AudioServer.is_bus_effect_enabled(idx, i), "включено — снова отражается")
