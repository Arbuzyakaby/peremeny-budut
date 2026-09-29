extends RefCounted
## Физика масла на сковороде (v11.0) — для луж, которые плюёт яичница. Только формулы, без узлов.
##
## Растительное (подсолнечное) масло на раскалённом чугуне:
## - плотность падает с температурой: ρ = 920 − 0,67·(T − 20) кг/м³;
## - вязкость — уравнение Андраде μ = A·e^(B/T): по двум точкам 0,050 Па·с при 20 °C и 0,0035 Па·с при 180 °C;
## - поверхностное натяжение линейно: σ = 0,033 − 5,5·10⁻⁵·(T − 20) Н/м;
## - капля растекается как вязкое гравитационное течение (Хапперт, 1982): R(t) = 0,894·(ρgV³t / 3μ)^(1/8),
##   пока не упрётся в капиллярную толщину h∞ = 2·l_c·sin(θ/2), l_c = √(σ/ρg) — дальше плёнка не тоньшает;
## - плёнку греет сковорода снизу: T(t) = T_ск − (T_ск − T₀)·e^(−t/τ), τ = h²/(3a), a = k/(ρc) — время
##   прогрева тонкого слоя теплопроводностью;
## - дым с 230 °C (точка дымления), пламя с 340 °C (точка воспламенения — пар над маслом горит сам);
## - горящая лужа: пламя высотой по Хескестаду L = 0,235·Q^0,4 − 1,02·D, Q = m″·ΔH_c·A (выгорание
##   m″ = 0,035 кг/(м²·с), ΔH_c = 37 МДж/кг), пульсирует с частотой 1,5/√D (Пагни).

const PX_M := 0.00125          # метров в пикселе арены
const G := 9.81
const K_OIL := 0.17            # теплопроводность, Вт/(м·К)
const C_OIL := 2000.0          # теплоёмкость, Дж/(кг·К)
const THETA := 0.26            # краевой угол на прокалённом чугуне, рад (≈ 15°)
const T_SPIT := 180.0          # масло во рту яичницы — температура жарки, °C
const T_PAN := 400.0           # раскалённая сковорода третьей фазы, °C
const T_SMOKE := 230.0
const T_FIRE := 340.0
const BURN_RATE := 0.035       # кг/(м²·с)
const DHC := 37.0e6            # Дж/кг
## Вязкость Андраде по двум точкам.
const MU_A := [0.050, 293.15]
const MU_B := [0.0035, 453.15]


static func density(t_c: float) -> float:
	return 920.0 - 0.67 * (t_c - 20.0)


static func viscosity(t_c: float) -> float:
	var b := log(MU_A[0] / MU_B[0]) / (1.0 / MU_A[1] - 1.0 / MU_B[1])
	var a := MU_A[0] / exp(b / MU_A[1])
	return a * exp(b / (t_c + 273.15))


static func surface_tension(t_c: float) -> float:
	return maxf(0.033 - 5.5e-5 * (t_c - 20.0), 0.005)


## Капиллярная длина, м.
static func capillary_length(t_c: float) -> float:
	return sqrt(surface_tension(t_c) / (density(t_c) * G))


## Предельная толщина растёкшейся лужи, м.
static func film_thickness(t_c: float) -> float:
	return 2.0 * capillary_length(t_c) * sin(THETA / 2.0)


## Объём лужи, которая растечётся до радиуса r_px, м³.
static func volume_for(r_px: float, t_c := T_SPIT) -> float:
	var r := r_px * PX_M
	return PI * r * r * film_thickness(t_c)


## Радиус растекания по Хапперту, м (без капиллярного предела).
static func huppert_radius(volume: float, t: float, t_c: float) -> float:
	return 0.894 * pow(density(t_c) * G * volume * volume * volume * maxf(t, 0.0) / (3.0 * viscosity(t_c)), 0.125)


## Время прогрева плёнки толщиной h, с.
static func heat_tau(t_c := T_SPIT) -> float:
	var h := film_thickness(t_c)
	return h * h / (3.0 * K_OIL / (density(t_c) * C_OIL))


static func temperature(t: float) -> float:
	return T_PAN - (T_PAN - T_SPIT) * exp(-maxf(t, 0.0) / heat_tau())


## Состояние лужи на время t после плевка: радиус (px), температура, стадия, пламя.
## splash — доля конечного радиуса сразу после удара (инерционный разлёт капли).
static func state(r_eq_px: float, t: float, splash := 0.55) -> Dictionary:
	var temp := temperature(t)
	var v := volume_for(r_eq_px)
	var r_eq := r_eq_px * PX_M
	var r0 := r_eq * splash
	# виртуальное начало: к моменту удара течение Хапперта уже «шло» t0 секунд
	var t0 := pow(r0 / 0.894, 8.0) * 3.0 * viscosity(temp) / (density(temp) * G * v * v * v)
	var r := clampf(huppert_radius(v, t + t0, temp), r0, r_eq)
	var d := 2.0 * r
	var q := BURN_RATE * DHC * PI * r * r / 1000.0  # кВт
	return {"r_px": r / PX_M, "temp": temp, "smoking": temp >= T_SMOKE, "fire": temp >= T_FIRE,
		"flame_m": maxf(0.235 * pow(q, 0.4) - 1.02 * d, 0.0), "puff_hz": 1.5 / sqrt(maxf(d, 0.01)), "q_kw": q}
