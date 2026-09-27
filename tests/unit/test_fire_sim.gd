extends "res://tests/test_case.gd"
## Симуляция пожара: огонь распространяется, металл не горит, топливо только убывает, уголь и зола
## только растут и остаются после тушения, бумага горит быстрее дерева, пластик плавится и течёт,
## пена гасит, тепло поднимается вверх, всё остывает до комнатной температуры.

const FireSim = preload("res://scripts/ending/fire_sim.gd")

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
	assert_eq(info.size(), s.w * s.h * 2)
	var i := s.index_at(Vector2(200, 120))
	assert_eq(int(info[i * 2]), FireSim.Mat.OIL * 32, "материал")
	assert_near(data[i * 4] / 255.0 * FireSim.MAX_T, 700.0, 10.0, "температура")
