extends "res://tests/test_case.gd"
## Пожар финала (fire.gd): поджигается, охватывает ящик и сжигает то, что в нём, тушится пеной,
## после себя оставляет золу; пропуск финала сразу даёт выгоревший ящик. Обломки битвы лежат
## на своих материалах.

const Fire = preload("res://scripts/ending/fire.gd")
const FireSim = preload("res://scripts/ending/fire_sim.gd")


func before_each() -> void:
	use_temp_storage()


func _fire() -> Fire:
	var f: Fire = add(Fire.new())
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
	f.extinguish(1.0)
	_run(f, 4.0)
	assert_eq(f.sim.burning_cells, 0, "потушен")
	assert_true(f.ash_amount() >= ash - 0.0001, "зола осталась")
	assert_near(f.coverage(), 0.0, 0.0001)
	assert_false(f.covers(Vector2(640, 360)))


func test_skip_burns_out_instantly() -> void:
	var f := _fire()
	f.fill_instantly()
	assert_true(f.active)
	assert_eq(f.sim.burning_cells, 0)
	assert_gt(f.ash_amount(), 0.1, "сразу пепелище")


func test_debris_lie_on_their_materials() -> void:
	var f := _fire()
	var want := {"paper": FireSim.Mat.PAPER, "plastic": FireSim.Mat.PLASTIC, "metal": FireSim.Mat.METAL,
		"fabric": FireSim.Mat.FABRIC, "shell": FireSim.Mat.SHELL}
	for d: Array in Fire.DEBRIS:
		assert_eq(int(f.sim.mat[f.sim.index_at(d[1])]), want[d[0]], "%s в %s" % [d[0], str(d[1])])
	assert_eq(int(f.sim.mat[f.sim.index_at(Vector2(10, 360))]), FireSim.Mat.WOOD, "бортик — дерево")
	assert_eq(int(f.sim.mat[f.sim.index_at(Vector2(640, 520))]), FireSim.Mat.OIL, "дно — масло на чугуне")


func test_glow_color_follows_temperature() -> void:
	var cold := Fire.glow_color(300.0)
	var hot := Fire.glow_color(1400.0)
	assert_true(hot.get_luminance() > cold.get_luminance(), "чем горячее, тем светлее")
	assert_true(Fire.glow_color(700.0).r > Fire.glow_color(700.0).b, "накал — красно-оранжевый")
