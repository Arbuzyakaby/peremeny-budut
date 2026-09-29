extends RefCounted
## Газы в ящике (v11.0): слой воздуха над дном ящика высотой LAYER_H на сетке вдвое грубее пожара.
## В каждой клетке — массовые доли O₂, CO₂, H₂O, CO, сажи, пиролизного «белого дыма» (смолы и пары),
## взвеси сухого льда и тумана (облако огнетушителя), температура газа, скорость течения.
##
## Химия горения (на килограмм сгоревшего топлива — по стехиометрии брутто-формул):
## - дерево, бумага, ткань — целлюлоза C₆H₁₀O₅ + 6 O₂ → 6 CO₂ + 5 H₂O: O₂ 1,185 кг, CO₂ 1,63 кг, H₂O 0,56 кг;
## - пластик — полипропилен (C₃H₆)ₙ + 4,5n O₂ → 3n CO₂ + 3n H₂O: O₂ 3,43, CO₂ 3,14, H₂O 1,29;
## - масло — триолеин C₅₇H₁₀₄O₆ + 80 O₂ → 57 CO₂ + 52 H₂O: O₂ 2,89, CO₂ 2,83, H₂O 1,06.
## Тепло — по правилу Хаггета: 13,1 МДж на килограмм израсходованного кислорода (для любого органического
## топлива ±5 %). Выход CO и сажи — справочные (SFPE Handbook) и растёт при нехватке воздуха
## (коэффициент избытка топлива φ > 1, форма зависимости Тьюарсона).
##
## Пламя гаснет по критерию критической адиабатической температуры пламени (Бейлер): если кислорода
## так мало, а теплоёмкость смеси так велика, что пламя не нагреется выше 1600 К, горение невозможно.
## Для воздуха с азотом это ≈ 14 % O₂; углекислый газ с его большой теплоёмкостью тушит раньше —
## как в справочниках. Горячий газ, наоборот, поддерживает пламя при меньшем кислороде.
##
## Течение: ящик открыт сверху. Горячий газ лёгкий (ρ = pM/RT) — всплывает и уходит вверх со скоростью
## ≈ √(2gH·ΔT/T), а на его место по полу подтягивается свежий воздух (подсос к основанию пламени);
## холодный тяжёлый CO₂ огнетушителя не всплывает, а растекается по дну и держится в ящике, как вода
## в ведре. Двумерное поле скоростей у пола — потенциальное: ∇²φ = S (источники — расширение газа
## и впрыск CO₂, стоки — уход вверх), u = ∇φ; плюс импульс струи огнетушителя. Вещества переносятся
## полулагранжевой схемой и диффундируют (закон Фика, турбулентная диффузия).
##
## Огнетушитель ОУ-5: 3,5 кг жидкого CO₂ под давлением насыщенных паров 57 бар (20 °C) выходят за ≈ 8 с.
## При дросселировании до 1 атм (изоэнтальпийно) часть жидкости замерзает: доля снега
## x = (h_газа(−78,5 °C) − h_жидкости(20 °C)) / L_сублимации ≈ 0,29. Снег (сухой лёд, −78,5 °C) ложится
## на горящее и охлаждает, сублимируя (571 кДж/кг), газ вытесняет кислород. Белое облако — не сам CO₂
## (он прозрачен), а туман: водяной пар воздуха конденсируется в холодной струе, плюс мелкие кристаллы.

const FireSim = preload("res://scripts/ending/fire_sim.gd")

const PX_M := 0.00125          # метров в пикселе ящика (как в Audio Rebound)
const LAYER_H := 0.35          # столб газа над клеткой — вся высота ящика, м (ящик держит тяжёлый газ, как ведро)
const BOX_H := 0.35            # высота бортиков, м
const G := 9.81
const R_GAS := 8.314462618
const P_ATM := 101325.0
const T0 := 20.0
## Воздух: массовые доли (влажность 50 % при 20 °C — влагосодержание 7,3 г/кг).
const AIR_O2 := 0.2314
const AIR_CO2 := 0.0006
const AIR_H2O := 0.0073
## Молярные массы, кг/моль, и теплоёмкости при температуре пламени, Дж/(кг·К).
const M := {"o2": 0.032, "n2": 0.028014, "co2": 0.04401, "h2o": 0.018015, "co": 0.02801}
const CP_HOT := {"o2": 1100.0, "n2": 1200.0, "co2": 1250.0, "h2o": 2300.0, "co": 1200.0}
const HUGGETT := 13.1e6        # Дж на кг O₂
const T_AD_CRIT := 1600.0      # К — критическая адиабатическая температура пламени
const T_REACT_MAX := 200.0     # °C — самый горячий окислитель, который доходит до основания пламени
const ETA_AD := 0.773          # доля тепла, идущая на нагрев смеси (калибровка: воздух → T_ад ≈ 2250 К)
const SLUMP_FR := 1.19         # число Фруда фронта гравитационного течения (Бенджамин, 1968)
const CONV_TAU := 5.0          # с — прогрев слоя газа от горячего дна конвекцией
const FLAME_TO_LAYER := 0.05   # доля тепла пламени, остающаяся в слое у дна
const D_TURB := 0.002          # турбулентная диффузия у пола, м²/с
const VENT0 := 6.0             # обмен с воздухом комнаты через открытый верх без огня, 1/с
const JACOBI := 24
## Огнетушитель ОУ-5.
const CO2_CHARGE := 3.5        # кг
const CO2_RATE := 0.45         # кг/с (3,5 кг примерно за 8 с)
const H_LIQ_20 := 237.6e3      # Дж/кг — насыщенная жидкость, 20 °C (отсчёт IIR)
const H_GAS_SUB := 401.4e3     # Дж/кг — газ при −78,5 °C и 1 атм
const L_SUB := 571.0e3         # Дж/кг — теплота сублимации сухого льда
const T_SUB := -78.5           # °C
const HORN_D := 0.07           # м — диаметр раструба
const NOZZLE_H := 0.45         # м — раструб над дном ящика
const BLOWOFF := 6.0           # м/с — скорость срыва небольшого диффузионного пламени
## Топливо по материалам: areal — кг/м² на единицу «топлива» клетки, o2/co2/h2o/co/soot — кг на кг топлива,
## dhc — теплота сгорания, МДж/кг (для справки: ≈ 13,1·o2), pyro — начало пиролиза, °C.
const FUEL := {
	FireSim.Mat.WOOD: {"areal": 1.8, "o2": 1.185, "co2": 1.63, "h2o": 0.56, "co": 0.004, "soot": 0.015, "dhc": 17.3, "tar": 0.25},
	FireSim.Mat.PAPER: {"areal": 0.18, "o2": 1.185, "co2": 1.63, "h2o": 0.56, "co": 0.004, "soot": 0.01, "dhc": 16.0, "tar": 0.2},
	FireSim.Mat.PLASTIC: {"areal": 0.9, "o2": 3.43, "co2": 3.14, "h2o": 1.29, "co": 0.024, "soot": 0.059, "dhc": 43.4, "tar": 0.1},
	FireSim.Mat.OIL: {"areal": 0.3, "o2": 2.89, "co2": 2.83, "h2o": 1.06, "co": 0.01, "soot": 0.03, "dhc": 37.0, "tar": 0.3},
	FireSim.Mat.FABRIC: {"areal": 0.4, "o2": 1.185, "co2": 1.63, "h2o": 0.56, "co": 0.004, "soot": 0.01, "dhc": 16.5, "tar": 0.2},
}
## Массовый коэффициент ослабления света сажей, м²/кг (Малхолланд: ≈ 8,7 м²/г), и «белым» дымом.
const K_SOOT := 8700.0
const K_TAR := 3000.0
const K_FOG := 900.0
const VIEW_PATH := 0.3         # м — сколько дыма над клеткой видит камера

var sim: FireSim
var w := 48
var h := 27
var dx := 0.0333
var o2 := PackedFloat32Array()
var co2 := PackedFloat32Array()
var h2o := PackedFloat32Array()
var co := PackedFloat32Array()
var soot := PackedFloat32Array()
var tar := PackedFloat32Array()
var fog := PackedFloat32Array()
var tg := PackedFloat32Array()      # температура газа, °C
var u := PackedFloat32Array()       # скорость, м/с (x — вправо, y — вниз по экрану)
var v := PackedFloat32Array()
var ju := PackedFloat32Array()      # скорость струи огнетушителя (затухает)
var jv := PackedFloat32Array()
var phi := PackedFloat32Array()
var src := PackedFloat32Array()
var hrr := PackedFloat32Array()     # тепловыделение клетки, Вт
var flame_h := PackedFloat32Array() # высота пламени над клеткой по Хескестаду, м
var flame_ok := PackedFloat32Array()  # 0..1 — хватает ли кислорода на пламя (критерий Бейлера)
var surf_t := PackedFloat32Array()  # средняя температура дна под клеткой
var time := 0.0
var total_heat := 0.0               # Дж, выделено за пожар
var o2_used := 0.0                  # кг
## Огнетушитель: {"on", "left" (кг), "aim" (px), "from" (px)}.
var spray := {"on": false, "left": CO2_CHARGE, "aim": Vector2.ZERO, "from": Vector2.ZERO}
var co2_released := 0.0
## Ящик накрыт противопожарным полотном (кошмой): 0 — открыт, 1 — воздух сверху не поступает.
## Тогда пламя само съедает кислород ящика и гаснет, когда адиабатическая температура падает ниже 1600 К.
var sealed := 0.0
const SNOW_FLAKES := 40        # сколько кучек снега падает за шаг
var _rng := RandomNumberGenerator.new()
var jet_speed := PackedFloat32Array()  # скорость струи у дна, м/с (срыв пламени)
var jet_state := {}                    # последние параметры струи — для тестов и панели
var _tmp := PackedFloat32Array()


func _init(fire_sim: FireSim) -> void:
	sim = fire_sim
	_rng.seed = 4242  # хлопья снега: повторяемо от запуска к запуску
	w = maxi(sim.w / 2, 2)
	h = maxi(sim.h / 2, 2)
	dx = sim.area.size.x / w * PX_M
	var n := w * h
	for arr_name in ["o2", "co2", "h2o", "co", "soot", "tar", "fog", "tg", "u", "v", "ju", "jv", "phi", "src", "hrr",
			"flame_h", "flame_ok", "surf_t", "_tmp", "jet_speed"]:
		var arr := PackedFloat32Array()  # упакованные массивы — значения: размер задаём самому полю
		arr.resize(n)
		set(arr_name, arr)
	o2.fill(AIR_O2)
	co2.fill(AIR_CO2)
	h2o.fill(AIR_H2O)
	tg.fill(T0)
	surf_t.fill(T0)
	flame_ok.fill(1.0)


func cell_of_fine(i: int) -> int:
	var x := mini((i % sim.w) * w / sim.w, w - 1)
	var y := mini((i / sim.w) * h / sim.h, h - 1)
	return y * w + x


func index_at(p: Vector2) -> int:
	var c := ((p - sim.area.position) / sim.area.size * Vector2(w, h)).floor()
	return clampi(int(c.y), 0, h - 1) * w + clampi(int(c.x), 0, w - 1)


## Мольная доля кислорода (объёмная концентрация, как пишут в справочниках: воздух — 20,9 %).
func x_o2(c: int) -> float:
	return (o2[c] / M["o2"]) / _moles(c)


func x_co2(c: int) -> float:
	return (co2[c] / M["co2"]) / _moles(c)


func _moles(c: int) -> float:
	var n2 := maxf(1.0 - o2[c] - co2[c] - h2o[c] - co[c], 0.0)
	return o2[c] / M["o2"] + co2[c] / M["co2"] + h2o[c] / M["h2o"] + co[c] / M["co"] + n2 / M["n2"]


## Молярная масса смеси, кг/моль.
func molar_mass(c: int) -> float:
	return 1.0 / maxf(_moles(c), 1e-6)


## Плотность газа по уравнению состояния идеального газа ρ = pM/(RT).
func density(c: int) -> float:
	return P_ATM * molar_mass(c) / (R_GAS * (tg[c] + 273.15))


static func air_density(t_c := T0) -> float:
	return P_ATM * 0.028964 / (R_GAS * (t_c + 273.15))


func _cp_hot(c: int) -> float:
	var n2 := maxf(1.0 - o2[c] - co2[c] - h2o[c] - co[c], 0.0)
	return o2[c] * CP_HOT["o2"] + co2[c] * CP_HOT["co2"] + h2o[c] * CP_HOT["h2o"] + co[c] * CP_HOT["co"] + n2 * CP_HOT["n2"]


## Адиабатическая температура пламени в смеси клетки, К: тепло от сгорания всего её кислорода
## (с долей ETA_AD) делится на теплоёмкость смеси. Ниже T_AD_CRIT пламя невозможно.
## Начальная температура — окислителя, который подсасывается к основанию пламени: это воздух слоя,
## но не горячие продукты (они уходят вверх), поэтому не выше T_REACT_MAX.
func flame_temp(c: int) -> float:
	return minf(tg[c], T_REACT_MAX) + 273.15 + o2[c] * HUGGETT * ETA_AD / _cp_hot(c)


## Средняя по ящику мольная доля CO₂ (для скорости звука в Audio Rebound).
func co2_mean() -> float:
	var s := 0.0
	for c in w * h:
		s += x_co2(c)
	return s / (w * h)


# ---------------------------------------------------------------- огнетушитель

## Доля жидкого CO₂, замерзающая в снег при сбросе давления (изоэнтальпийное дросселирование).
static func snow_fraction() -> float:
	return (H_GAS_SUB - H_LIQ_20) / L_SUB


func start_spray(from_px: Vector2, aim_px: Vector2) -> void:
	if not spray["on"]:
		spray["prev"] = aim_px  # новый нажим — снег начинается отсюда, а не тянется от прошлой точки
	spray["on"] = spray["left"] > 0.0
	spray["from"] = from_px
	spray["aim"] = aim_px


func stop_spray() -> void:
	spray["on"] = false


## Струя ОУ-5 — затопленная турбулентная круглая струя (Поуп, «Турбулентные течения», гл. 5):
## - на выходе из раструба (d₀ = 7 см) газ при −78,5 °C плотностью ρ₀ = pM/RT ≈ 2,75 кг/м³, скорость
##   u₀ = ṁ_газа / (ρ₀·πd₀²/4) ≈ 30 м/с;
## - плотная струя в лёгком воздухе ведёт себя как струя эффективного диаметра d_эф = d₀·√(ρ₀/ρ_в)
##   (Тринг — Ньюби); скорость на оси u_c = 6,2·u₀·d₀/x, доля CO₂ на оси Y_c = 5·d_эф/x, полуширина
##   r½ = 0,094·x (скорость) и 0,11·x (примесь), профиль — гауссов;
## - струя подсасывает воздух: расход ṁ(x) = 0,32·ṁ₀·(x/d₀)·√(ρ_в/ρ₀) (Рику — Сполдинг), поэтому
##   у дна это уже смесь CO₂ с воздухом, и температура — по балансу энтальпий смеси;
## - ударившись о дно, струя растекается радиальной пристенной струёй (скорость ∝ 1/r);
## - где скорость струи больше скорости срыва пламени (≈ 6 м/с для небольших диффузионных пламён),
##   пламя сдувает, даже если кислорода хватает;
## - снег (доля snow_fraction) — крупные частицы, они долетают до дна в пятне струи.
func _spray_step(dt: float) -> void:
	jet_speed.fill(0.0)
	if not spray["on"]:
		return
	var m0 := minf(CO2_RATE * dt, float(spray["left"]))
	spray["left"] = float(spray["left"]) - m0
	if spray["left"] <= 0.0:
		spray["on"] = false
	co2_released += m0
	# турбулентная струя не бьёт в одну точку: ось гуляет на ~ полуширину (крупные вихри, частоты ~ u_c/x)
	var aim: Vector2 = spray["aim"] + Vector2(sin(time * 9.3) + sin(time * 14.1 + 1.3), cos(time * 11.7) + sin(time * 7.9 + 0.6)) * 14.0
	var from: Vector2 = spray["from"]
	var xs := snow_fraction()
	var mdot0 := CO2_RATE * (1.0 - xs)
	var rho0 := P_ATM * float(M["co2"]) / (R_GAS * (T_SUB + 273.15))
	var rho_a := air_density()
	var u0 := mdot0 / (rho0 * PI * HORN_D * HORN_D / 4.0)
	var d_eff := HORN_D * sqrt(rho0 / rho_a)
	var hor := from.distance_to(aim) * PX_M
	var x := sqrt(hor * hor + NOZZLE_H * NOZZLE_H)
	var u_c := minf(u0, 6.2 * u0 * HORN_D / x)
	var y_c := minf(1.0, 5.0 * d_eff / x)
	var r_u := 0.094 * x
	var r_y := 0.11 * x
	var mdot := maxf(mdot0, 0.32 * mdot0 * (x / HORN_D) * sqrt(rho_a / rho0))
	var t_mix := (mdot0 * 846.0 * T_SUB + (mdot - mdot0) * 1005.0 * T0) / (mdot0 * 846.0 + (mdot - mdot0) * 1005.0)
	jet_state = {"u0": u0, "x": x, "u_c": u_c, "y_c": y_c, "r_half": r_u, "mdot": mdot, "t_mix": t_mix}
	var dir := (aim - from).normalized()
	var cell_px := sim.area.size.x / w
	var reach_px := maxf(r_y * 2.5 / PX_M, cell_px * 1.5)
	var wall_px := 0.35 / PX_M
	var wsum := 0.0
	var cells: Array[int] = []
	var shares := PackedFloat32Array()
	for c in w * h:
		var p := sim.area.position + (Vector2(c % w, c / w) + Vector2(0.5, 0.5)) * sim.area.size / Vector2(w, h)
		var d := p.distance_to(aim)
		if d < wall_px:
			var r := d * PX_M
			var outward := (p - aim).normalized() if d > 1.0 else dir
			# пристенная струя: радиально от точки удара, u ∝ r½/r; плюс горизонтальная часть импульса струи
			var u_w := u_c * clampf(r_u / maxf(r, r_u), 0.0, 1.0)
			ju[c] += outward.x * u_w * 0.5 + dir.x * u_w * 0.3
			jv[c] += outward.y * u_w * 0.5 + dir.y * u_w * 0.3
			jet_speed[c] = maxf(jet_speed[c], u_c * exp(-0.693 * (r / r_u) * (r / r_u)) + u_w * 0.3)
		if d < reach_px:
			var k := exp(-0.693 * pow(d * PX_M / r_y, 2.0))
			cells.append(c)
			shares.append(k)
			wsum += k
	for k in cells.size():
		var c := cells[k]
		var prof := shares[k]
		var mg := density(c) * dx * dx * LAYER_H
		# доля газа клетки, которую за шаг вытесняет поток струи (смесь CO₂ и подсосанного воздуха)
		var f := clampf(mdot * dt * prof / maxf(wsum, 1e-6) / mg, 0.0, 1.0)
		var y_co2 := y_c * prof
		var air := 1.0 - y_co2
		var t_here := T0 + (t_mix - T0) * prof
		o2[c] = lerpf(o2[c], AIR_O2 * air, f)
		co2[c] = lerpf(co2[c], y_co2 + AIR_CO2 * air, f)
		h2o[c] = lerpf(h2o[c], AIR_H2O * air, f)
		co[c] = lerpf(co[c], 0.0, f)
		soot[c] = lerpf(soot[c], 0.0, f)
		tar[c] = lerpf(tar[c], 0.0, f)
		tg[c] = lerpf(tg[c], t_here, f)
		src[c] += mdot * prof / maxf(wsum, 1e-6) / (density(c) * dx * dx * LAYER_H)
	# снег — хлопья сухого льда: разлетаются конусом (разброс ~ полуширины струи) вдоль пути пятна за шаг
	# и падают кучками, поэтому слой неровный, а не мазок кистью
	var snow := m0 * xs
	var r_px := r_y / PX_M
	var prev: Vector2 = spray.get("prev", aim)
	for k in SNOW_FLAKES:
		var at := prev.lerp(aim, _rng.randf()) + Vector2(_rng.randfn(0.0, r_px * 0.9), _rng.randfn(0.0, r_px * 0.9))
		var clump := snow / SNOW_FLAKES * 60.0 * 4.0 * _rng.randf_range(0.3, 1.7)
		var ci := sim.index_at(at)
		var cx := ci % sim.w
		var cy := ci / sim.w
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var x2 := cx + ox
				var y2 := cy + oy
				if x2 < 0 or y2 < 0 or x2 >= sim.w or y2 >= sim.h:
					continue
				var wgt := 1.0 if ox == 0 and oy == 0 else 0.35
				sim.foam[y2 * sim.w + x2] = minf(sim.foam[y2 * sim.w + x2] + clump * wgt * 0.4, 1.0)
	spray["prev"] = aim


## Туман: водяной пар в холодной смеси конденсируется. Насыщение — формула Магнуса над водой
## (ниже 0 °C — над льдом), влагосодержание насыщения Y = 0,622·e / (p − e).
## Туман — избыток пара над насыщением; в тёплом газе он испаряется.
static func saturation_y(t_c: float) -> float:
	var e := 610.94 * exp(17.625 * t_c / (t_c + 243.04)) if t_c >= 0.0 else 611.15 * exp(22.452 * t_c / (t_c + 272.55))
	return 0.622 * e / maxf(P_ATM - e, 1.0)


func _condense(dt: float) -> void:
	var k := 1.0 - exp(-dt / 0.15)
	for c in w * h:
		var want := maxf(h2o[c] - saturation_y(tg[c]), 0.0)
		fog[c] += (want - fog[c]) * k


# ---------------------------------------------------------------- шаг

func step(dt: float) -> void:
	time += dt
	src.fill(0.0)
	_gather(dt)
	_spray_step(dt)
	_vent(dt)
	_condense(dt)
	_solve_flow()
	_advect(dt)
	_diffuse(dt)
	_feedback()


## Собрать с дна всё, что выделилось за шаг: сгоревшее топливо (химия и тепло), пиролиз, температуру.
func _gather(dt: float) -> void:
	hrr.fill(0.0)
	surf_t.fill(0.0)
	var cnt := PackedFloat32Array()
	cnt.resize(w * h)
	var fine_area := (sim.cell_size().x * PX_M) * (sim.cell_size().y * PX_M)
	var o2_need := PackedFloat32Array()
	o2_need.resize(w * h)
	var fuel_kg := PackedFloat32Array()
	fuel_kg.resize(w * h)
	var prod := {}  # клетка → [co2, h2o, co, soot]
	for i in sim.w * sim.h:
		var c := cell_of_fine(i)
		surf_t[c] += sim.temp[i]
		cnt[c] += 1.0
		var m: int = sim.mat[i]
		if not FUEL.has(m):
			continue
		var fp: Dictionary = FUEL[m]
		var burnt := sim.burn_acc[i]
		var pyro := sim.pyro_acc[i]
		if burnt > 0.0:
			var kg := burnt * float(fp["areal"]) * fine_area
			fuel_kg[c] += kg
			o2_need[c] += kg * float(fp["o2"])
			var pr: Array = prod.get(c, [0.0, 0.0, 0.0, 0.0])
			pr[0] += kg * float(fp["co2"])
			pr[1] += kg * float(fp["h2o"])
			pr[2] += kg * float(fp["co"])
			pr[3] += kg * float(fp["soot"])
			prod[c] = pr
		if pyro > 0.0:  # пиролиз без пламени: смолы и пары — белый дым
			var mg := density(c) * dx * dx * LAYER_H
			tar[c] = minf(tar[c] + pyro * float(fp["areal"]) * fine_area * float(fp["tar"]) / mg, 0.05)
	sim.burn_acc.fill(0.0)
	sim.pyro_acc.fill(0.0)
	for c in w * h:
		surf_t[c] /= maxf(cnt[c], 1.0)
		# газ у дна греется от поверхности конвекцией: τ = ρ·cp·H / h ≈ 5 с (h ≈ 25 Вт/(м²·К));
		# быстро газ греет только само пламя (ниже, по тепловыделению клетки)
		tg[c] += (surf_t[c] - tg[c]) * clampf(dt / CONV_TAU, 0.0, 1.0)
		if fuel_kg[c] <= 0.0:
			continue
		var mg := density(c) * dx * dx * LAYER_H
		var o2_have := o2[c] * mg
		var need := o2_need[c]
		var phi_eq := need / maxf(o2_have, 1e-12)  # φ > 1 — воздуха не хватает
		var burnt_frac := minf(1.0, 1.0 / maxf(phi_eq, 1e-6))
		var used := need * burnt_frac
		var pr: Array = prod[c]
		# при нехватке воздуха (φ > 1) выход CO и сажи растёт (форма зависимости Тьюарсона)
		var rich := 1.0 + 10.0 / exp(2.5 * pow(maxf(1.0 / maxf(phi_eq, 1e-3), 1e-3), 1.2))
		var tot := mg + fuel_kg[c] * burnt_frac
		o2[c] = maxf(o2_have - used, 0.0) / tot
		co2[c] = (co2[c] * mg + pr[0] * burnt_frac) / tot
		h2o[c] = (h2o[c] * mg + pr[1] * burnt_frac) / tot
		co[c] = minf((co[c] * mg + pr[2] * burnt_frac * rich) / tot, 0.1)
		soot[c] = minf((soot[c] * mg + pr[3] * burnt_frac * rich) / tot, 0.02)
		tar[c] *= maxf(0.0, 1.0 - 8.0 * dt)  # пламя дожигает смолы
		var q := used * HUGGETT
		total_heat += q
		o2_used += used
		hrr[c] = q / maxf(dt, 1e-6)
		# конвективная доля тепла пламени остаётся в слое (остальное уносит факел вверх и излучение)
		tg[c] = minf(tg[c] + FLAME_TO_LAYER * q / (mg * 1005.0), 1200.0)
		src[c] += 3.0 * burnt_frac  # горячие продукты расширяются
	_flame_heights()


## Высота пламени по корреляции Хескестада: L = 0,235·Q^(2/5) − 1,02·D (Q — кВт, L и D — м).
## Q и D — по окрестности клетки 5×5 (очаг, к которому она принадлежит).
func _flame_heights() -> void:
	for y in h:
		for x in w:
			var q := 0.0
			var n := 0
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var xx := x + ox
					var yy := y + oy
					if xx < 0 or yy < 0 or xx >= w or yy >= h:
						continue
					var hh := hrr[yy * w + xx]
					if hh > 1.0:
						q += hh
						n += 1
			var c := y * w + x
			if hrr[c] <= 1.0 or n == 0:
				flame_h[c] = 0.0
				continue
			var d := sqrt(4.0 * n * dx * dx / PI)
			flame_h[c] = heskestad(q / 1000.0, d)


static func heskestad(q_kw: float, d_m: float) -> float:
	return maxf(0.235 * pow(maxf(q_kw, 0.0), 0.4) - 1.02 * d_m, 0.0)


## Частота пульсаций пламени бассейна, Гц: f ≈ 1,5/√D (Пагни; Цетеген и Ахмед).
static func puffing_hz(d_m: float) -> float:
	return 1.5 / sqrt(maxf(d_m, 0.01))


## Открытый верх: горячий газ всплывает и уносит с собой примеси, сверху приходит воздух комнаты.
## Скорость всплытия — по числу Фруда: w ≈ √(2gH·(ρ₀ − ρ)/ρ₀); тяжёлый холодный газ (CO₂) не всплывает.
func _vent(dt: float) -> void:
	var rho0 := air_density()
	for c in w * h:
		var rho := density(c)
		var buoy := maxf((rho0 - rho) / rho0, 0.0)
		var heavy := maxf((rho - rho0) / rho0, 0.0)
		# тяжёлый слой перемешивается с воздухом сверху слабо: устойчивая стратификация (большое число Ричардсона)
		var lam := (VENT0 / (1.0 + 400.0 * heavy) + sqrt(2.0 * G * BOX_H * buoy) / BOX_H) * (1.0 - sealed)
		var k := 1.0 - exp(-lam * dt)
		o2[c] += (AIR_O2 - o2[c]) * k
		co2[c] += (AIR_CO2 - co2[c]) * k
		h2o[c] += (AIR_H2O - h2o[c]) * k
		co[c] -= co[c] * k
		soot[c] -= soot[c] * k * 0.6  # дым уходит столбом — над клеткой он ещё виден
		tar[c] -= tar[c] * k * 0.6
		tg[c] += (T0 - tg[c]) * k * 0.3
		src[c] -= lam * buoy * 2.0  # уход вверх — сток: к основанию пламени подсасывается воздух
		# тяжёлый газ оседает и растекается по дну гравитационным течением (Бенджамин): скорость фронта
		# U = Fr·√(g′h), Fr ≈ 1,19, g′ = g·Δρ/ρ — как вода в ведре; ящик держит его бортиками
		if heavy > 0.02:
			src[c] += SLUMP_FR * sqrt(G * heavy * LAYER_H) / dx
		# туман тает: капли и кристаллы испаряются в тёплом газе


## Потенциальное течение у пола: ∇²φ = S − S̄ (избыток уходит вверх или приходит сверху), u = ∇φ + струя.
func _solve_flow() -> void:
	var mean := 0.0
	for c in w * h:
		mean += src[c]
	mean /= w * h
	var dx2 := dx * dx
	for it in JACOBI:
		for y in h:
			for x in w:
				var c := y * w + x
				var s := 0.0
				var n := 0
				if x > 0:
					s += phi[c - 1]
					n += 1
				if x < w - 1:
					s += phi[c + 1]
					n += 1
				if y > 0:
					s += phi[c - w]
					n += 1
				if y < h - 1:
					s += phi[c + w]
					n += 1
				_tmp[c] = (s - (src[c] - mean) * dx2) / n
		var t := phi
		phi = _tmp
		_tmp = t
	for y in h:
		for x in w:
			var c := y * w + x
			var gx := (phi[c + 1] if x < w - 1 else phi[c]) - (phi[c - 1] if x > 0 else phi[c])
			var gy := (phi[c + w] if y < h - 1 else phi[c]) - (phi[c - w] if y > 0 else phi[c])
			u[c] = clampf(gx / (2.0 * dx) + ju[c], -6.0, 6.0)
			v[c] = clampf(gy / (2.0 * dx) + jv[c], -6.0, 6.0)
			ju[c] *= 0.7
			jv[c] *= 0.7


## Полулагранжев перенос: значение приходит из точки, откуда его принесло течение.
func _advect(dt: float) -> void:
	for arr_name in ["o2", "co2", "h2o", "co", "soot", "tar", "fog", "tg"]:
		var a: PackedFloat32Array = get(arr_name)
		for y in h:
			for x in w:
				var c := y * w + x
				var px := clampf(x - u[c] * dt / dx, 0.0, w - 1.001)
				var py := clampf(y - v[c] * dt / dx, 0.0, h - 1.001)
				var x0 := int(px)
				var y0 := int(py)
				var fx := px - x0
				var fy := py - y0
				var i0 := y0 * w + x0
				var top := lerpf(a[i0], a[i0 + 1], fx) if x0 < w - 1 else a[i0]
				var bot := lerpf(a[i0 + w], a[i0 + w + 1] if x0 < w - 1 else a[i0 + w], fx) if y0 < h - 1 else top
				_tmp[c] = lerpf(top, bot, fy)
		set(arr_name, _tmp.duplicate())


## Диффузия (закон Фика), явная схема: коэффициент D·dt/dx² ≤ 0,2 — устойчиво.
func _diffuse(dt: float) -> void:
	var k := minf(D_TURB * dt / (dx * dx), 0.2)
	for arr_name in ["o2", "co2", "h2o", "co", "soot", "tar", "fog", "tg"]:
		var a: PackedFloat32Array = get(arr_name)
		for y in h:
			for x in w:
				var c := y * w + x
				var s := a[c]
				var l := a[c - 1] if x > 0 else s
				var r := a[c + 1] if x < w - 1 else s
				var t := a[c - w] if y > 0 else s
				var b := a[c + w] if y < h - 1 else s
				_tmp[c] = s + k * (l + r + t + b - 4.0 * s)
		set(arr_name, _tmp.duplicate())


## Обратно в пожар: доступный кислород (доля от воздуха) с учётом критерия пламени.
func _feedback() -> void:
	for c in w * h:
		var tad := flame_temp(c)
		flame_ok[c] = clampf((tad - T_AD_CRIT) / 150.0, 0.0, 1.0)  # у предела пламя слабеет, а не гаснет разом
		flame_ok[c] *= clampf(1.0 - (jet_speed[c] - BLOWOFF) / BLOWOFF, 0.0, 1.0)  # струя сдувает пламя
	for i in sim.w * sim.h:
		var c := cell_of_fine(i)
		sim.gas_oxy[i] = clampf(x_o2(c) / 0.2095, 0.0, 1.0) * flame_ok[c]


# ---------------------------------------------------------------- картинка

## Упаковать для шейдера: a — RGBA: оптическая толщина сажи, белого дыма, тумана, высота пламени;
## b — RGBA: кислород (доля от воздуха), тепловыделение, CO₂, температура газа.
func pack(a: PackedByteArray, b: PackedByteArray) -> void:
	var n := w * h
	if a.size() != n * 4:
		a.resize(n * 4)
	if b.size() != n * 4:
		b.resize(n * 4)
	for c in n:
		var rho := density(c)
		# закон Бугера — Ламберта — Бера: τ = K·ρ_частиц·L
		var t_soot := K_SOOT * soot[c] * rho * VIEW_PATH
		var t_tar := K_TAR * tar[c] * rho * VIEW_PATH
		var t_fog := K_FOG * fog[c] * rho * VIEW_PATH
		a[c * 4] = int(clampf(t_soot / 4.0, 0.0, 1.0) * 255.0)
		a[c * 4 + 1] = int(clampf(t_tar / 4.0, 0.0, 1.0) * 255.0)
		a[c * 4 + 2] = int(clampf(t_fog / 4.0, 0.0, 1.0) * 255.0)
		a[c * 4 + 3] = int(clampf(flame_h[c] / 0.5, 0.0, 1.0) * 255.0)
		b[c * 4] = int(clampf(x_o2(c) / 0.2095, 0.0, 1.0) * 255.0)
		b[c * 4 + 1] = int(clampf(hrr[c] / 3000.0, 0.0, 1.0) * 255.0)
		b[c * 4 + 2] = int(clampf(x_co2(c), 0.0, 1.0) * 255.0)
		b[c * 4 + 3] = int(clampf((tg[c] - T_SUB) / 1300.0, 0.0, 1.0) * 255.0)
