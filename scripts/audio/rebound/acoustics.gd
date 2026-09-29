extends RefCounted
## Audio Rebound — физика звука. Здесь только формулы и таблицы, без узлов и шин: их проверяют тесты
## и использует трассировщик (tracer.gd).
##
## Всё считается по шести октавным полосам 125…4000 Гц — так, как это делают в архитектурной акустике:
## у каждого материала свой коэффициент звукопоглощения α (доля энергии, которую поверхность не
## отражает) и коэффициент рассеяния s (доля отражённой энергии, ушедшей не зеркально, а по закону
## Ламберта, ISO 17497-1). Значения α — справочные (таблицы Кутруффа, Эвереста, Бис–Хансена) для
## похожих поверхностей; там, где справочника нет (зола, уголь, белок яичницы), — оценка по пористости.
##
## Формулы:
## - скорость звука в газе c = √(γ·R·T / M) — зависит от температуры и состава (в горячем воздухе
##   звук быстрее, в углекислом газе — медленнее);
## - поглощение звука воздухом — ISO 9613-1 (релаксация кислорода и азота, зависит от влажности);
## - время реверберации Сэбина T = 0,161·V / A и Эйринга T = 0,161·V / (−S·ln(1 − ᾱ) + 4mV);
## - кривая спада Шрёдера (обратное интегрирование импульсного отклика) и по ней EDT, T20, T30;
## - ясность C50, чёткость D50 и центральное время Ts (ISO 3382-1).

## Октавные полосы, Гц.
const BANDS := [125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0]
const NB := 6
const MID := 3  # 1 кГц — «средняя» полоса для сводных чисел

const R_GAS := 8.314462618    # Дж/(моль·К)
const P_REF := 101.325        # кПа
const T_REF := 293.15         # К (20 °C)
const T_TRIPLE := 273.16      # К, тройная точка воды

## Газы: молярная масса, кг/моль, и показатель адиабаты γ = cp/cv.
const GAS := {
	"air": {"M": 0.028964, "gamma": 1.400},
	"co2": {"M": 0.044010, "gamma": 1.289},
	"h2o": {"M": 0.018015, "gamma": 1.330},
}

## Материалы: a — α по полосам 125…4000 Гц, s — рассеяние (средние частоты), name — для панели.
const MAT := {
	"open": {"a": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0], "s": 0.0, "name": "проём (звук уходит)"},
	"plywood": {"a": [0.28, 0.22, 0.17, 0.09, 0.10, 0.11], "s": 0.10, "name": "фанера на относе"},
	"lacquer": {"a": [0.05, 0.04, 0.04, 0.04, 0.05, 0.05], "s": 0.05, "name": "дерево под лаком"},
	"wood_floor": {"a": [0.15, 0.11, 0.10, 0.07, 0.06, 0.07], "s": 0.10, "name": "дощатый пол"},
	"rug": {"a": [0.08, 0.24, 0.57, 0.69, 0.71, 0.73], "s": 0.30, "name": "вязаный коврик"},
	"textile": {"a": [0.04, 0.10, 0.20, 0.35, 0.45, 0.50], "s": 0.20, "name": "тканый половик"},
	"velvet": {"a": [0.05, 0.12, 0.35, 0.45, 0.38, 0.36], "s": 0.25, "name": "бархат"},
	"plush": {"a": [0.14, 0.35, 0.55, 0.72, 0.70, 0.65], "s": 0.60, "name": "плюш с набивкой"},
	"tile": {"a": [0.01, 0.01, 0.01, 0.01, 0.02, 0.02], "s": 0.05, "name": "глазурованная плитка"},
	"steel": {"a": [0.01, 0.01, 0.01, 0.02, 0.02, 0.02], "s": 0.10, "name": "сталь"},
	"cast_iron_oil": {"a": [0.01, 0.01, 0.015, 0.015, 0.02, 0.025], "s": 0.05, "name": "чугун под маслом"},
	"plastic": {"a": [0.02, 0.03, 0.03, 0.03, 0.03, 0.02], "s": 0.10, "name": "твёрдый пластик"},
	"egg_white": {"a": [0.03, 0.05, 0.08, 0.12, 0.16, 0.20], "s": 0.20, "name": "белок яичницы"},
	"paper": {"a": [0.04, 0.06, 0.10, 0.15, 0.20, 0.25], "s": 0.20, "name": "бумага"},
	"char": {"a": [0.18, 0.22, 0.30, 0.40, 0.45, 0.50], "s": 0.40, "name": "уголь (пористый)"},
	"ash": {"a": [0.10, 0.20, 0.40, 0.60, 0.70, 0.75], "s": 0.50, "name": "слой золы"},
	"frost": {"a": [0.05, 0.10, 0.20, 0.35, 0.50, 0.60], "s": 0.40, "name": "снег сухого льда"},
	"linoleum": {"a": [0.02, 0.03, 0.03, 0.03, 0.03, 0.02], "s": 0.05, "name": "линолеум"},
	"plaster": {"a": [0.01, 0.02, 0.02, 0.03, 0.04, 0.05], "s": 0.05, "name": "крашеная штукатурка"},
	"glass": {"a": [0.35, 0.25, 0.18, 0.12, 0.07, 0.04], "s": 0.02, "name": "оконное стекло"},
	"shelves": {"a": [0.20, 0.25, 0.30, 0.30, 0.35, 0.40], "s": 0.70, "name": "полки с образцами"},
	"door": {"a": [0.14, 0.10, 0.06, 0.08, 0.10, 0.10], "s": 0.05, "name": "деревянная дверь"},
}


static func alpha(mat: String, band: int) -> float:
	return float(MAT.get(mat, MAT["plywood"])["a"][band])


static func scatter(mat: String) -> float:
	return float(MAT.get(mat, MAT["plywood"])["s"])


## Коэффициент отражения энергии 1 − α.
static func reflectance(mat: String, band: int) -> float:
	return 1.0 - alpha(mat, band)


# ---------------------------------------------------------------- газ

## Молярная масса и γ смеси по мольным долям {газ: доля}. Для смеси идеальных газов складываются
## молярные теплоёмкости: cv = R/(γ − 1), cp = cv + R.
static func mixture(fractions: Dictionary) -> Dictionary:
	var total := 0.0
	for k in fractions:
		total += float(fractions[k])
	if total <= 0.0:
		return GAS["air"].duplicate()
	var m := 0.0
	var cv := 0.0
	for k in fractions:
		var x := float(fractions[k]) / total
		var g: Dictionary = GAS[k]
		m += x * float(g["M"])
		cv += x * R_GAS / (float(g["gamma"]) - 1.0)
	return {"M": m, "gamma": (cv + R_GAS) / cv}


## Скорость звука, м/с: c = √(γRT/M). По умолчанию — сухой воздух; при 20 °C ≈ 343 м/с.
static func speed_of_sound(t_celsius: float, gas: Dictionary = GAS["air"]) -> float:
	var t := maxf(t_celsius + 273.15, 1.0)
	return sqrt(float(gas["gamma"]) * R_GAS * t / float(gas["M"]))


## Поглощение звука воздухом, дБ/м — ISO 9613-1:1993, формулы (3)–(5).
## f — частота, Гц; t_celsius — температура; rh — относительная влажность, %; p_kpa — давление.
static func air_absorption_db(f: float, t_celsius := 20.0, rh := 50.0, p_kpa := P_REF) -> float:
	var t := t_celsius + 273.15
	var pr := p_kpa / P_REF
	var c := -6.8346 * pow(T_TRIPLE / t, 1.261) + 4.6151
	var h := rh * pow(10.0, c) / pr  # мольная доля водяного пара, %
	var fr_o := pr * (24.0 + 4.04e4 * h * (0.02 + h) / (0.391 + h))
	var fr_n := pr * pow(t / T_REF, -0.5) * (9.0 + 280.0 * h * exp(-4.170 * (pow(t / T_REF, -1.0 / 3.0) - 1.0)))
	var f2 := f * f
	return 8.686 * f2 * (1.84e-11 / pr * sqrt(t / T_REF)
		+ pow(t / T_REF, -2.5) * (0.01275 * exp(-2239.1 / t) / (fr_o + f2 / fr_o)
		+ 0.1068 * exp(-3352.0 / t) / (fr_n + f2 / fr_n)))


## Энергетический коэффициент затухания m, 1/м (энергия падает как e^(−m·x)): m = α_дБ / (10·lg e).
static func air_m(band: int, t_celsius := 20.0, rh := 50.0) -> float:
	return air_absorption_db(BANDS[band], t_celsius, rh) / 4.3429448


# ---------------------------------------------------------------- статистическая акустика

## Площадь эквивалентного поглощения A = Σ S·α (+ 4mV), м². surfaces — [[площадь, материал], ...].
static func absorption_area(surfaces: Array, band: int, volume := 0.0, m := 0.0) -> float:
	var a := 0.0
	for s: Array in surfaces:
		a += float(s[0]) * alpha(String(s[1]), band)
	return a + 4.0 * m * volume


static func total_area(surfaces: Array) -> float:
	var s := 0.0
	for x: Array in surfaces:
		s += float(x[0])
	return s


## Время реверберации по Сэбину, с. 0,161 = 24·ln 10 / c при c = 343 м/с.
static func sabine(volume: float, surfaces: Array, band: int, m := 0.0, c := 343.2) -> float:
	var a := absorption_area(surfaces, band, volume, m)
	return 24.0 * log(10.0) / c * volume / maxf(a, 1e-6)


## Время реверберации по Эйрингу, с (точнее Сэбина при большом поглощении).
static func eyring(volume: float, surfaces: Array, band: int, m := 0.0, c := 343.2) -> float:
	var s := total_area(surfaces)
	var mean_a := clampf(absorption_area(surfaces, band) / maxf(s, 1e-6), 0.0, 0.999999)
	return 24.0 * log(10.0) / c * volume / maxf(-s * log(1.0 - mean_a) + 4.0 * m * volume, 1e-6)


## Средняя длина свободного пробега луча в объёме, м: 4V/S (Кнудсен).
static func mean_free_path(volume: float, area: float) -> float:
	return 4.0 * volume / maxf(area, 1e-6)


# ---------------------------------------------------------------- импульсный отклик

## Кривая спада Шрёдера в дБ: обратное интегрирование энергии, 0 дБ в начале.
static func schroeder_db(h: PackedFloat32Array) -> PackedFloat32Array:
	var n := h.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var acc := 0.0
	for i in range(n - 1, -1, -1):
		acc += h[i]
		out[i] = acc
	var e0 := maxf(out[0] if n > 0 else 0.0, 1e-30)
	for i in n:
		out[i] = 10.0 * log(maxf(out[i], 1e-30) / e0) / log(10.0)
	return out


## Время спада на 60 дБ по участку кривой Шрёдера [from_db, to_db] (линейная регрессия, как в ISO 3382).
## Если кривая не опустилась до to_db — продлевает по доступному наклону; −1, если данных нет.
static func decay_time(edc: PackedFloat32Array, bin: float, from_db: float, to_db: float) -> float:
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	var n := 0
	for i in edc.size():
		var y := edc[i]
		if y > from_db:
			continue
		if y < to_db:
			break
		var x := (i + 0.5) * bin
		sx += x
		sy += y
		sxx += x * x
		sxy += x * y
		n += 1
	if n < 3:
		return -1.0
	var slope := (n * sxy - sx * sy) / maxf(n * sxx - sx * sx, 1e-30)  # дБ/с, отрицательный
	if slope >= -1e-6:
		return -1.0
	return -60.0 / slope


static func edt(edc: PackedFloat32Array, bin: float) -> float:
	return decay_time(edc, bin, 0.0, -10.0)


static func t20(edc: PackedFloat32Array, bin: float) -> float:
	return decay_time(edc, bin, -5.0, -25.0)


static func t30(edc: PackedFloat32Array, bin: float) -> float:
	return decay_time(edc, bin, -5.0, -35.0)


## Ясность C50, дБ: энергия первых 50 мс против всей поздней. t0 — время прямого звука.
static func clarity(h: PackedFloat32Array, bin: float, t0 := 0.0, split := 0.05) -> float:
	var early := 0.0
	var late := 0.0
	for i in h.size():
		if (i + 0.5) * bin - t0 < split:
			early += h[i]
		else:
			late += h[i]
	return 10.0 * log(maxf(early, 1e-30) / maxf(late, 1e-30)) / log(10.0)


## Чёткость D50 (доля ранней энергии, 0..1).
static func definition(h: PackedFloat32Array, bin: float, t0 := 0.0) -> float:
	var early := 0.0
	var all := 0.0
	for i in h.size():
		all += h[i]
		if (i + 0.5) * bin - t0 < 0.05:
			early += h[i]
	return early / maxf(all, 1e-30)


## Центральное время Ts, с — «центр тяжести» импульсного отклика.
static func center_time(h: PackedFloat32Array, bin: float) -> float:
	var num := 0.0
	var den := 0.0
	for i in h.size():
		num += (i + 0.5) * bin * h[i]
		den += h[i]
	return num / maxf(den, 1e-30)


static func db(x: float) -> float:
	return 10.0 * log(maxf(x, 1e-30)) / log(10.0)
