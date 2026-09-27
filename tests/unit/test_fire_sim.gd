extends "res://tests/test_case.gd"
## Симуляция пожара: огонь распространяется, металл не горит, топливо только убывает, уголь и зола
## только растут и остаются после тушения, бумага горит быстрее дерева, пластик плавится и течёт,
## пена гасит, тепло поднимается вверх, всё остывает до комнатной температуры.
## Ящик финала: на любом сиде за 5 с есть фазовый переход, порядок воспламенения зависит от сида,
## копоть и счёт сожжённых клеток.

const FireSim = preload("res://scripts/ending/fire_sim.gd")
const Fire = preload("res://scripts/ending/fire.gd")

const R := Rect2(0, 0, 400, 240)


func _sim(m: int) -> FireSim:
	var s := FireSim.new(40, 24, R)
	s.fill_rect(R, m)
	return s


func _avg(arr: PackedFloat32Array) -> float:
	var t := 0.0
	for v in arr:
		t += v
	return t / arr.size()


func test_fire_spreads_through_oil() -> void:
	var s := _sim(FireSim.Mat.OIL)
	s.ignite(Vector2(200, 120), 25.0)
	s.step(0.1)
	assert_gt(s.burning_fraction(), 0.0, "загорелось")
	for i in 30:
		s.step(0.1)
	assert_gt(_avg(s.charred), 0.2, "выгорела заметная часть")
	assert_gt(s.charred[s.index_at(Vector2(290, 120))], 0.0, "огонь дошёл до соседних клеток")


func test_metal_heats_but_never_burns() -> void:
	var s := _sim(FireSim.Mat.METAL)
	s.ignite(Vector2(200, 120), 30.0, 900.0)
	for i in 20:
		s.step(0.1)
	assert_eq(s.burning_cells, 0, "металл не горит")
	assert_near(_avg(s.charred), 0.0, 0.0001, "и не обугливается")
	assert_gt(s.temp_at(Vector2(240, 120)), FireSim.AMBIENT + 5.0, "но проводит тепло")


func test_fuel_only_decreases() -> void:
	var s := _sim(FireSim.Mat.WOOD)
	s.ignite(Vector2(200, 120), 30.0)
	var last := s.total_fuel()
	for i in 25:
		s.step(0.1)
		var now := s.total_fuel()
		assert_true(now <= last + 0.0001, "топливо не берётся из ниоткуда")
		last = now


func test_char_and_ash_are_monotonic() -> void:
	var s := _sim(FireSim.Mat.PAPER)
	s.ignite(Vector2(200, 120), 40.0)
	var prev_c := s.charred.duplicate()
	var prev_a := s.ash.duplicate()
	for i in 20:
		s.step(0.1)
		var ok := true
		for k in s.charred.size():
			if s.charred[k] < prev_c[k] - 0.0001 or s.ash[k] < prev_a[k] - 0.0001:
				ok = false
		assert_true(ok, "уголь и зола не исчезают")
		prev_c = s.charred.duplicate()
		prev_a = s.ash.duplicate()


func test_paper_burns_faster_than_wood() -> void:
	var paper := _sim(FireSim.Mat.PAPER)
	var wood := _sim(FireSim.Mat.WOOD)
	for s: FireSim in [paper, wood]:
		s.ignite(Vector2(200, 120), 30.0)
		for i in 15:
			s.step(0.1)
	assert_true(_avg(paper.charred) > _avg(wood.charred), "бумага сгорает быстрее")


func test_plastic_melts_and_flows_down() -> void:
	var s := _sim(FireSim.Mat.METAL)
	s.fill_rect(Rect2(180, 60, 40, 30), FireSim.Mat.PLASTIC)
	var below := s.index_at(Vector2(200, 105))
	assert_eq(int(s.mat[below]), FireSim.Mat.METAL)
	for i in 10:
		for k in s.temp.size():  # держим выше плавления (150), но ниже воспламенения (340)
			if s.mat[k] == FireSim.Mat.PLASTIC:
				s.temp[k] = maxf(s.temp[k], 260.0)
		s.step(0.1)
	assert_gt(s.melt[s.index_at(Vector2(200, 75))], 0.3, "расплавился")
	assert_eq(int(s.mat[below]), FireSim.Mat.PLASTIC, "стёк вниз")
	assert_gt(s.fuel[below], 0.0, "вместе с массой")


func test_foam_puts_fire_out() -> void:
	var s := _sim(FireSim.Mat.OIL)
	s.ignite(Vector2(200, 120), 60.0)
	for i in 10:
		s.step(0.1)
	assert_gt(s.burning_cells, 0)
	var ash_before := _avg(s.ash)
	for i in 30:
		s.add_foam(Vector2(200, 120), 400.0, 1.0)
		s.step(0.1)
	assert_eq(s.burning_cells, 0, "пена погасила")
	var hottest := 0.0
	for t in s.temp:
		hottest = maxf(hottest, t)
	assert_true(hottest < 300.0, "остыло под пеной: %.0f" % hottest)
	assert_true(_avg(s.ash) >= ash_before - 0.0001, "зола осталась")


func test_heat_rises() -> void:
	var s := _sim(FireSim.Mat.NONE)
	s.temp[s.index_at(Vector2(200, 120))] = 900.0
	s.step(0.05)
	var above := s.temp_at(Vector2(200, 110))
	var below := s.temp_at(Vector2(200, 130))
	assert_true(above > below, "горячий воздух поднимается: %.0f > %.0f" % [above, below])


func test_everything_cools_to_room_temperature() -> void:
	var s := _sim(FireSim.Mat.NONE)
	s.ignite(Vector2(200, 120), 50.0, 1000.0)
	for i in 300:
		s.step(0.1)
	assert_true(_avg(s.temp) < 40.0, "в среднем остыло")
	assert_true(s.temp_at(Vector2(200, 120)) < 60.0, "и в центре")


func test_temperature_stays_in_physical_range() -> void:
	var s := _sim(FireSim.Mat.PLASTIC)
	s.ignite(Vector2(200, 120), 60.0, 1300.0)
	for i in 30:
		s.step(0.1)
	var lo := 9999.0
	var hi := 0.0
	for t in s.temp:
		lo = minf(lo, t)
		hi = maxf(hi, t)
	assert_between(lo, FireSim.AMBIENT, FireSim.MAX_T, "минимум")
	assert_between(hi, FireSim.AMBIENT, FireSim.MAX_T, "максимум")


func test_burn_out_leaves_only_ash() -> void:
	var s := _sim(FireSim.Mat.WOOD)
	s.burn_out()
	assert_near(s.total_fuel(), 0.0, 0.0001)
	assert_near(_avg(s.charred), 1.0, 0.0001)
	assert_near(_avg(s.ash), float(FireSim.PROPS[FireSim.Mat.WOOD]["ash"]), 0.0001)
	assert_eq(s.burning_cells, 0)


func test_pack_layout() -> void:
	var s := _sim(FireSim.Mat.OIL)
	s.ignite(Vector2(200, 120), 30.0, 700.0)
	var data := PackedByteArray()
	var info := PackedByteArray()
	s.pack(data, info)
	assert_eq(data.size(), s.w * s.h * 4)
	assert_eq(info.size(), s.w * s.h * 3)
	var i := s.index_at(Vector2(200, 120))
	assert_eq(int(info[i * 3]), FireSim.Mat.OIL * 32, "материал")
	assert_near(data[i * 4] / 255.0 * FireSim.MAX_T, 700.0, 10.0, "температура")


# ---------------------------------------------------------------- ящик финала: гарантии v7.2

## Ящик финала (раскладка fire.gd) с сидом; точка поджига — тоже от сида, как в финале (clamp в ending.gd).
func _box(seed_value: int, low := false) -> FireSim:
	var s := FireSim.new(64 if low else 96, 36 if low else 54, Fire.AREA)
	Fire.build_layout(s, seed_value)
	return s


func _impact(seed_value: int) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 1
	return Vector2(rng.randf_range(150, 1130), rng.randf_range(200, 560))


func _run_box(s: FireSim, at: Vector2, seconds: float) -> void:
	s.ignite(at, 42.0, 950.0)  # как fire.gd::start
	for i in int(seconds * 12.0):
		s.step(1.0 / 12.0)


func test_every_seed_reaches_a_phase_transition() -> void:
	var worst := 0.0
	for sd in 10:
		var s := _box(sd)
		var at := _impact(sd)
		if sd < 2:  # худшие точки — дальние углы
			at = [Vector2(150, 200), Vector2(1130, 200)][sd]
		_run_box(s, at, 5.0)
		var first := s.first_phase()
		assert_between(first, 0.0, 5.0, "сид %d, поджиг %s: пластик потёк / металл раскалился / скорлупа закоптилась" % [sd, str(at)])
		worst = maxf(worst, first)
	for sd in 4:  # на телефоне сетка грубее — гарантия та же
		var s := _box(100 + sd, true)
		_run_box(s, _impact(100 + sd), 5.0)
		assert_between(s.first_phase(), 0.0, 5.0, "телефон, сид %d" % (100 + sd))
	print("    худший первый фазовый переход: %.2f с" % worst)


func test_ignition_order_differs_between_seeds() -> void:
	var orders := {}
	for sd in 6:
		var s := _box(sd)
		_run_box(s, Vector2(640, 360), 4.0)  # одна и та же точка поджига — разница только от сида
		orders[str(s.ignition_order)] = true
		assert_true(s.ignition_order.size() >= 3, "за 4 с загорелись хотя бы три материала")
	assert_gt(orders.size(), 1, "порядок первого воспламенения меняется от рана к рану: %s" % str(orders.keys()))
	var a := _box(3)
	var b := _box(3)
	_run_box(a, Vector2(640, 360), 2.0)
	_run_box(b, Vector2(640, 360), 2.0)
	assert_eq(a.ignition_order, b.ignition_order, "один сид — один и тот же пожар")


func test_vary_is_small_and_deterministic() -> void:
	var base := _sim(FireSim.Mat.WOOD)
	var s1 := _sim(FireSim.Mat.WOOD)
	var s2 := _sim(FireSim.Mat.WOOD)
	var s3 := _sim(FireSim.Mat.WOOD)
	s1.vary(7)
	s2.vary(7)
	s3.vary(8)
	assert_eq(s1.fuel, s2.fuel, "один сид — одинаковое топливо")
	assert_eq(s1.temp, s2.temp, "и прогрев")
	assert_ne(s1.fuel, s3.fuel, "другой сид — другое")
	var f0: float = base.fuel[0]
	var dev := 0.0
	var hi := 0.0
	var lo := 9999.0
	for i in s1.fuel.size():
		dev = maxf(dev, absf(s1.fuel[i] / f0 - 1.0))
		hi = maxf(hi, s1.temp[i])
		lo = minf(lo, s1.temp[i])
	assert_between(dev, 0.001, FireSim.FUEL_JITTER + 0.0001, "топливо гуляет не больше чем на ±%d%%" % int(FireSim.FUEL_JITTER * 100))
	assert_between(lo, FireSim.AMBIENT, FireSim.AMBIENT + FireSim.SEED_WARM, "прогрев")
	assert_between(hi, FireSim.AMBIENT + 1.0, FireSim.AMBIENT + FireSim.SEED_WARM + 0.01, "прогрев есть, но умеренный")
	assert_true(hi < FireSim.PROPS[FireSim.Mat.PLASTIC]["melt"], "от прогрева ничего не плавится и не загорается само")


func test_burnt_cells_counts_the_damage() -> void:
	var s := _box(5)
	assert_eq(s.burnt_cells(), 0, "до огня — ничего")
	_run_box(s, Vector2(640, 360), 3.0)
	var mid := s.burnt_cells()
	assert_gt(mid, 0, "огонь сжёг клетки")
	assert_true(mid < s.fuel_cells(), "но не все за 3 с")
	s.burn_out()
	assert_eq(s.burnt_cells(), s.fuel_cells(), "пропуск финала — сгорело всё")


func test_scorch_stays_after_cooling() -> void:
	var s := _sim(FireSim.Mat.SHELL)
	s.ignite(Vector2(200, 120), 40.0, 800.0)
	s.step(0.2)
	var i := s.index_at(Vector2(200, 120))
	var sc := s.scorch[i]
	assert_gt(sc, FireSim.SOOT_SEEN, "скорлупа закоптилась")
	assert_true(s.phase_at[FireSim.Phase.SOOT] >= 0.0, "переход записан")
	for k in 200:
		s.step(0.1)
	assert_true(s.temp[i] < 60.0, "остыла")
	assert_true(s.scorch[i] >= sc, "а копоть осталась")
