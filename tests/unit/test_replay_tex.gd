extends "res://tests/test_case.gd"
## Повтор гибели (кольцевой буфер, поиск источника удара), процедурные текстуры и шейдеры,
## все иконки рисуются без ошибок.

const Replay = preload("res://scripts/game/replay.gd")
const Tex = preload("res://scripts/gfx/tex.gd")
const Icons = preload("res://scripts/ui/icons.gd")


func _frame(head: Vector2, enemies := [], drops := [], boss := Vector2.INF) -> Dictionary:
	return {"head": head, "heading": 0.0, "body": PackedVector2Array([head]), "hurt": false,
		"enemies": enemies, "drops": drops, "waves": [], "boss": boss}


func test_replay_is_a_ring_buffer() -> void:
	var r := Replay.new()
	assert_false(r.has_data())
	for i in Replay.CAPACITY + 40:
		r.push(_frame(Vector2(i, 0)))
	assert_eq(r.frames.size(), Replay.CAPACITY, "хранит только последние секунды")
	assert_eq((r.frames[0]["head"] as Vector2).x, 40.0, "старые кадры выброшены")
	assert_true(r.has_data())
	assert_near(r.duration(), Replay.SECONDS, 0.05)


func test_replay_record_rate() -> void:
	var r := Replay.new()
	# вместо игры — словарь с теми же полями: пустое поле, без змеи и босса
	var fake := {"snake": null, "boss": null, "enemies": {"bears": [], "forks": [], "pills": [], "dolls": []},
		"shots": {"drops": [], "waves": []}}
	for i in 60:
		r.record(fake, 1.0 / 60.0)
	assert_between(r.frames.size(), 28, 31, "≈30 кадров в секунду")
	assert_eq(r.frames[0]["boss"], Vector2.INF)
	assert_len(r.frames[0]["enemies"], 0)


func test_replay_frame_at_clamps() -> void:
	var r := Replay.new()
	for i in 30:
		r.push(_frame(Vector2(i, 0)))
	assert_eq((r.frame_at(-5.0)["head"] as Vector2).x, 0.0)
	assert_eq((r.frame_at(999.0)["head"] as Vector2).x, 29.0)
	assert_eq((r.frame_at(10.0 / Replay.RATE)["head"] as Vector2).x, 10.0)
	assert_true(Replay.new().frame_at(1.0).is_empty())


func test_replay_finds_what_hit() -> void:
	var r := Replay.new()
	r.push(_frame(Vector2(500, 300), [["bear", Vector2(900, 300), 0.0, 0], ["fork", Vector2(530, 300), 0.0, 1]],
		[[Vector2(600, 300), 3, false], [Vector2(505, 300), 3, true]]))
	r.finish("fork_tines")
	assert_eq(r.cause, "fork_tines")
	assert_eq(r.source, Vector2(530, 300), "ближайший враг, а не снаряд змеи")
	r.finish("wall")
	assert_eq(r.source, Vector2(500, 300), "об бортик — место удара у головы")
	r.clear()
	assert_eq(r.cause, "")
	assert_eq(r.source, Vector2.INF)


func test_floor_materials_per_stage() -> void:
	Tex.clear_cache()
	for k in Tex.Floor.size():
		var m := Tex.floor_material(k)
		assert_true(m is ShaderMaterial)
		assert_eq(int(m.get_shader_parameter("kind")), k)
		assert_true(m == Tex.floor_material(k), "кэшируется")
	var code := Tex.FLOOR_SHADER
	assert_has(code, "kind == 4", "пол ящика для приборов")
	assert_has(code, "fork_sdf", "вмятины от вилок в бархате")


func test_object_materials() -> void:
	for mode in Tex.Mat.size():
		var m := Tex.material(mode, 1.5)
		assert_eq(int(m.get_shader_parameter("mode")), mode)
		assert_near(float(m.get_shader_parameter("seed")), 1.5, 0.0001)
	assert_has(Tex.MAT_SHADER, "uniform float burn", "обугливание и зола в финале")
	assert_has(Tex.MAT_SHADER, "mode == 4", "ткань отдельной веткой, латунь — своей")


func test_cache_can_be_cleared() -> void:
	var a := Tex.soft()
	Tex.clear_cache()
	var b := Tex.soft()
	assert_false(a == b, "после очистки — новая текстура")
	assert_true(Tex.ring() == Tex.ring())
	assert_true(Tex.vignette() is GradientTexture2D)


func test_every_icon_draws() -> void:
	var c: Control = add(Control.new())
	c.size = Vector2(400, 200)
	var drawn := [0]
	c.draw.connect(func() -> void:
		var p := Vector2(20, 20)
		Icons.heart(c, p, 10.0, Color.RED)
		Icons.bear(c, p)
		Icons.fork(c, p)
		Icons.pill(c, p)
		Icons.egg(c, p)
		for i in 4:
			Icons.stage(c, p, i)
		for t in range(1, 8):
			Icons.ability(c, p, t, 0.5)
		Icons.shield(c, p, 10.0)
		Icons.scale_coin(c, p)
		for f in [Icons.pause, Icons.gear, Icons.arrow_back, Icons.lock, Icons.check, Icons.bolt, Icons.code, Icons.fang,
				Icons.folder, Icons.calendar]:
			f.call(c, p, Color.WHITE, 1.0)
		Icons.star(c, p, 8.0, Color.YELLOW)
		for k in 3:
			Icons.fork_kind(c, p, k)
		for a in 4:
			Icons.fork_attack(c, p, a, Color.ORANGE)
		drawn[0] += 1)
	c.queue_redraw()
	await frames(2)
	assert_eq(drawn[0], 1, "все иконки нарисованы за один кадр")
	assert_len(Icons.FORK_COLORS, 3)


# ---------------------------------------------------------------- v12.4: повтор подробнее

func _snap(head: Vector2, enemies := [], drops := [], boss := Vector2.INF) -> Dictionary:
	return {"head": head, "body": PackedVector2Array([head]), "enemies": enemies, "drops": drops, "waves": [],
		"boss": boss, "hp": 3}


func test_finish_points_at_the_nearest_culprit() -> void:
	var r := Replay.new()
	r.push(_snap(Vector2(100, 100), [["bear", Vector2(130, 100), 0.0, 0], ["fork", Vector2(400, 400), 0.0, 0]]))
	r.finish("bear")
	assert_eq(r.source, Vector2(130, 100), "подсвечен ближний медведь, а не дальняя вилка")
	assert_eq(r.cause, "bear")


func test_finish_ignores_own_shots_and_far_things() -> void:
	var r := Replay.new()
	r.push(_snap(Vector2(100, 100), [], [[Vector2(110, 100), 0, true], [Vector2(150, 100), 0, false]]))
	r.finish("shot")
	assert_eq(r.source, Vector2(150, 100), "свой снаряд змеи — не виноват")
	var far := Replay.new()
	far.push(_snap(Vector2(100, 100), [["bear", Vector2(900, 600), 0.0, 0]]))
	far.finish("bear")
	assert_eq(far.source, Vector2.INF, "дальше 260 px — никого не подсвечиваем")


func test_finish_blames_the_boss_or_the_snake_itself() -> void:
	var r := Replay.new()
	r.push(_snap(Vector2(100, 100), [["pill", Vector2(160, 100), 0.0, 0, 0]], [], Vector2(180, 100)))
	r.finish("boss")
	assert_eq(r.source, Vector2(180, 100), "яичница рядом — виновата она")
	for cause in ["wall", "self"]:
		var w := Replay.new()
		w.push(_snap(Vector2(40, 40), [["bear", Vector2(60, 40), 0.0, 0]]))
		w.finish(cause)
		assert_eq(w.source, Vector2(40, 40), "%s: подсвечена сама змея" % cause)


func test_clear_and_empty_finish() -> void:
	var r := Replay.new()
	r.finish("bear")
	assert_eq(r.source, Vector2.INF, "пустая запись не падает")
	for i in 20:
		r.push(_snap(Vector2(i, 0)))
	assert_true(r.has_data())
	assert_near(r.duration(), 20.0 / Replay.RATE, 0.0001)
	r.clear()
	assert_false(r.has_data())
	assert_eq(r.cause, "")
	assert_eq(r.frame_at(1.0), {})
