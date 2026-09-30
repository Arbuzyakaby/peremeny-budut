extends "res://tests/test_case.gd"
## Газ над ящиком финала (gas_sim.gd): справочные формулы (плотность воздуха, насыщение пара, высота
## пламени по Хескестаду, пульсации, доля снега CO₂), состав смеси и её поведение на шаге —
## без огня воздух остаётся воздухом, огонь ест кислород и греет газ, струя огнетушителя тратит заряд.

const FireSim = preload("res://scripts/ending/fire_sim.gd")
const GasSim = preload("res://scripts/ending/gas_sim.gd")

const R := Rect2(0, 0, 400, 240)


func _gas(m := FireSim.Mat.OIL) -> GasSim:
	var s := FireSim.new(40, 24, R)
	s.fill_rect(R, m)
	return GasSim.new(s)


func _mean(g: GasSim, arr: PackedFloat32Array) -> float:
	var t := 0.0
	for v in arr:
		t += v
	return t / arr.size()


# ---------------------------------------------------------------- справочные формулы

func test_air_density_matches_the_handbook() -> void:
	assert_near(GasSim.air_density(20.0), 1.204, 0.005, "воздух при 20 °C — 1,204 кг/м³")
	assert_near(GasSim.air_density(0.0), 1.292, 0.005, "при 0 °C — 1,292")
	assert_lt(GasSim.air_density(300.0), GasSim.air_density(20.0), "горячий воздух легче")


func test_saturation_grows_with_temperature_and_is_continuous_at_zero() -> void:
	var prev := 0.0
	for t in range(-40, 81, 10):
		var y := GasSim.saturation_y(float(t))
		assert_gt(y, prev, "при %d °C насыщение больше, чем при %d °C" % [t, t - 10])
		prev = y
	assert_near(GasSim.saturation_y(20.0), 0.0147, 0.0005, "20 °C — около 14,7 г пара на кг воздуха")
	var below := GasSim.saturation_y(-0.01)
	var above := GasSim.saturation_y(0.01)
	assert_near(below, above, 0.0001, "лёд и вода сходятся на нуле без скачка")


func test_heskestad_flame_height() -> void:
	assert_eq(GasSim.heskestad(0.0, 0.1), 0.0, "нет тепла — нет пламени")
	assert_eq(GasSim.heskestad(-5.0, 0.1), 0.0, "отрицательная мощность не ломает формулу")
	assert_eq(GasSim.heskestad(1.0, 1.0), 0.0, "широкий и слабый очаг — пламя не поднимается")
	var small := GasSim.heskestad(10.0, 0.1)
	var big := GasSim.heskestad(100.0, 0.1)
	assert_gt(big, small, "мощнее — выше")
	assert_near(GasSim.heskestad(100.0, 0.3), 0.235 * pow(100.0, 0.4) - 1.02 * 0.3, 0.0001, "формула Хескестада")


func test_puffing_frequency() -> void:
	assert_near(GasSim.puffing_hz(1.0), 1.5, 0.001, "метровый очаг — 1,5 Гц")
	assert_gt(GasSim.puffing_hz(0.1), GasSim.puffing_hz(1.0), "маленький очаг пульсирует чаще")
	assert_near(GasSim.puffing_hz(0.0), 15.0, 0.01, "нулевой диаметр ограничен 1 см, а не делится на ноль")


func test_snow_fraction_of_co2() -> void:
	assert_between(GasSim.snow_fraction(), 0.25, 0.32, "около трети жидкой углекислоты замерзает в снег")


# ---------------------------------------------------------------- состав

func test_fresh_box_is_room_air() -> void:
	var g := _gas()
	var c := g.index_at(Vector2(200, 120))
	assert_near(g.x_o2(c), 0.209, 0.002, "20,9 % кислорода по объёму")
	assert_near(g.molar_mass(c), 0.02897, 0.0003, "молярная масса воздуха")
	assert_near(g.density(c), GasSim.air_density(), 0.02, "плотность — как у воздуха")
	assert_gt(g.flame_temp(c), 2000.0, "в воздухе пламя горячее критических 1600 К")


func test_co2_makes_the_gas_heavier_and_the_flame_colder() -> void:
	var g := _gas()
	var c := g.index_at(Vector2(200, 120))
	var rho := g.density(c)
	var t_ad := g.flame_temp(c)
	g.co2[c] = 0.4
	g.o2[c] = 0.12
	assert_gt(g.density(c), rho, "углекислота тяжелее воздуха")
	assert_lt(g.flame_temp(c), GasSim.T_AD_CRIT, "мало кислорода — пламя не держится")
	assert_gt(g.x_co2(c), 0.2)
	assert_lt(t_ad, 3000.0, "адиабатическая температура в разумных пределах")


func test_index_at_clamps_to_the_grid() -> void:
	var g := _gas()
	assert_eq(g.index_at(Vector2(-100, -100)), 0, "левее и выше ящика — первая клетка")
	assert_eq(g.index_at(Vector2(9999, 9999)), g.w * g.h - 1, "правее и ниже — последняя")
	assert_eq(g.w, 20, "сетка газа вдвое грубее сетки огня")
	assert_eq(g.h, 12)


func test_fine_cells_map_into_the_coarse_grid() -> void:
	var g := _gas()
	for i in [0, 41, 40 * 24 - 1, 40 * 12 + 20]:
		var c := g.cell_of_fine(i)
		assert_between(c, 0, g.w * g.h - 1, "клетка огня %d попадает в сетку газа" % i)
	assert_eq(g.cell_of_fine(0), 0)
	assert_eq(g.cell_of_fine(40 * 24 - 1), g.w * g.h - 1)


# ---------------------------------------------------------------- шаг

func test_without_fire_air_stays_air() -> void:
	var g := _gas(FireSim.Mat.METAL)
	for i in 20:
		g.sim.step(0.05)
		g.step(0.05)
	assert_near(_mean(g, g.o2), GasSim.AIR_O2, 0.001, "кислород на месте")
	assert_near(_mean(g, g.tg), GasSim.T0, 0.5, "температура комнатная")
	assert_near(_mean(g, g.soot), 0.0, 0.0001, "копоти нет")
	assert_eq(g.total_heat, 0.0, "ничего не горело")


func test_fire_eats_oxygen_and_heats_the_gas() -> void:
	var g := _gas()
	g.sim.ignite(Vector2(200, 120), 60.0)
	for i in 30:
		g.sim.step(0.05)
		g.step(0.05)
	assert_gt(g.total_heat, 0.0, "выделилось тепло")
	assert_gt(g.o2_used, 0.0, "сгорел кислород")
	assert_gt(_mean(g, g.tg), GasSim.T0 + 1.0, "газ прогрелся")
	var c := g.index_at(Vector2(200, 120))
	assert_gt(g.hrr[c] + g.flame_h[c] + g.tg[c] - GasSim.T0, 0.0, "над очагом что-то происходит")
	assert_gt(g.time, 1.4)


func test_spray_uses_the_charge_and_stops_when_empty() -> void:
	var g := _gas()
	g.start_spray(Vector2(200, -200), Vector2(200, 120))
	assert_true(g.spray["on"])
	for i in 20:
		g.step(0.1)
	assert_lt(g.spray["left"], GasSim.CO2_CHARGE, "заряд тратится")
	assert_gt(g.co2_released, 0.0, "углекислота в ящике")
	var peak := 0.0
	for v in g.co2:
		peak = maxf(peak, v)
	assert_gt(peak, GasSim.AIR_CO2 * 1.5, "где-то в ящике углекислоты больше, чем в воздухе")
	g.stop_spray()
	assert_false(g.spray["on"])
	g.spray["left"] = 0.0
	g.start_spray(Vector2(200, -200), Vector2(200, 120))
	assert_false(g.spray["on"], "пустой огнетушитель не включается")


func test_pack_encodes_fresh_air() -> void:
	var g := _gas()
	var n := g.w * g.h
	var a := PackedByteArray()
	var b := PackedByteArray()
	a.resize(n * 4)
	b.resize(n * 4)
	g.pack(a, b)
	assert_eq(a[0], 0, "в чистом воздухе нет сажи")
	assert_eq(a[3], 0, "и пламени")
	assert_between(b[0], 250, 255, "кислорода — как в воздухе")
	assert_eq(b[1], 0, "тепловыделения нет")
	assert_between(b[3], 18, 22, "температура 20 °C в шкале от −78,5 °C")
