extends "res://tests/test_case.gd"
## Масло на сковороде (v11.0): свойства подсолнечного масла по справочным точкам, растекание по Хапперту
## с капиллярным пределом, прогрев плёнки к точке воспламенения ровно к концу телеграфа лужи, пламя.

const OilFilm = preload("res://scripts/entities/oil_film.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")


func test_oil_properties_match_reference_points() -> void:
	assert_near(OilFilm.viscosity(20.0), 0.050, 1e-4, "Андраде проходит через 0,050 Па·с при 20 °C")
	assert_near(OilFilm.viscosity(180.0), 0.0035, 1e-5, "и через 0,0035 Па·с при 180 °C")
	assert_true(OilFilm.viscosity(250.0) < OilFilm.viscosity(180.0), "горячее масло жиже")
	assert_near(OilFilm.density(20.0), 920.0, 0.01)
	assert_between(OilFilm.capillary_length(20.0) * 1000.0, 1.7, 2.1, "капиллярная длина ≈ 1,9 мм")
	assert_between(OilFilm.film_thickness(OilFilm.T_SPIT) * 1000.0, 0.3, 0.7, "лужа на чугуне — меньше миллиметра")


func test_huppert_spreading_law() -> void:
	var v := 5e-6
	var r1 := OilFilm.huppert_radius(v, 1.0, 180.0)
	var r256 := OilFilm.huppert_radius(v, 256.0, 180.0)
	assert_near(r256 / r1, 2.0, 1e-4, "R ∝ t^(1/8): в 256 раз дольше — вдвое шире")
	assert_gt(OilFilm.huppert_radius(v, 1.0, 250.0), OilFilm.huppert_radius(v, 1.0, 20.0), "горячее растекается быстрее")


func test_puddle_spreads_then_stops() -> void:
	var r_eq := FriedEggBoss.PUDDLE_RADIUS
	var prev := 0.0
	for k in 40:
		var st := OilFilm.state(r_eq, k * 0.1)
		assert_true(float(st["r_px"]) >= prev - 1e-4, "лужа не сжимается")
		prev = st["r_px"]
	assert_near(prev, r_eq, 0.5, "и останавливается на капиллярной толщине")
	assert_true(float(OilFilm.state(r_eq, 0.0)["r_px"]) < r_eq * 0.7, "сразу после удара — ещё узкая")


func test_film_reaches_fire_point_with_the_tell() -> void:
	var before := OilFilm.state(FriedEggBoss.PUDDLE_RADIUS, FriedEggBoss.PUDDLE_TELL - 0.15)
	var after := OilFilm.state(FriedEggBoss.PUDDLE_RADIUS, FriedEggBoss.PUDDLE_TELL + 0.05)
	assert_false(before["fire"], "до конца телеграфа масло ещё не вспыхнуло: %.0f °C" % before["temp"])
	assert_true(before["smoking"], "но уже дымит")
	assert_true(after["fire"], "к концу телеграфа — точка воспламенения: %.0f °C" % after["temp"])
	assert_between(OilFilm.heat_tau(), 0.3, 1.5, "прогрев тонкой плёнки — доли секунды")


func test_burning_puddle_flame() -> void:
	var st := OilFilm.state(FriedEggBoss.PUDDLE_RADIUS, 3.0)
	assert_between(float(st["q_kw"]), 5.0, 30.0, "мощность очага — киловатты")
	assert_between(float(st["flame_m"]), 0.2, 1.0, "пламя по Хескестаду — десятки сантиметров")
	assert_between(float(st["puff_hz"]), 3.0, 6.0, "пульсации 1,5/√D")
