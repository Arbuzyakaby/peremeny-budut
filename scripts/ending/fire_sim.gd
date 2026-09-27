extends RefCounted
## Симуляция пожара в ящике — упрощённая физическая модель горения на сетке (рендер — шейдер в fire.gd).
## В каждой клетке: температура (°C), топливо и его начальный запас, кислород, степень обугливания,
## зола, расплав и пена огнетушителя. За шаг:
## - теплопроводность: тепло перетекает к холодным соседям (закон Фурье, коэффициент — материала);
## - конвекция: горячий воздух поднимается (в виде 3/4 — вверх по экрану) и подогревает клетки над собой;
## - излучение пламени: горящая клетка прогревает соседей в радиусе двух клеток (поток ~1/d², выше
##   по «течению» пламени — сильнее) — так фронт огня бежит по материалу, как в жизни;
## - горение: при температуре выше точки воспламенения материала топливо расходуется со скоростью,
##   зависящей от кислорода и перегрева, и выделяет тепло; кислород тратится и медленно подтекает из воздуха;
## - остывание: излучение (закон Стефана–Больцмана, ~T⁴) и теплоотдача воздуху (закон Ньютона);
## - пластик выше температуры плавления течёт вниз (сохраняя массу) и горит лужей;
## - выгоревшее топливо превращается в уголь, а уголь — в золу; зола не исчезает никогда, даже после тушения;
## - пена охлаждает и перекрывает доступ кислорода.
## Металл не горит, но раскаляется и светится по температуре (цвет — кривая «абсолютно чёрного тела»).

enum Mat { NONE, WOOD, PAPER, PLASTIC, METAL, OIL, FABRIC, SHELL }

const AMBIENT := 20.0
const MAX_T := 1400.0
## Свойства материалов: ignite — точка воспламенения °C, fuel — запас топлива, rate — доля запаса,
## сгорающая за секунду при полном кислороде, heat — нагрев клетки на единицу сгоревшего топлива,
## cond — теплопроводность, ash — выход золы, melt — точка плавления (0 — не плавится).
const PROPS := {
	Mat.NONE: {"ignite": 9999.0, "fuel": 0.0, "rate": 0.0, "heat": 0.0, "cond": 1.2, "ash": 0.0, "melt": 0.0},
	Mat.WOOD: {"ignite": 290.0, "fuel": 1.0, "rate": 0.075, "heat": 5200.0, "cond": 0.9, "ash": 0.85, "melt": 0.0},
	Mat.PAPER: {"ignite": 233.0, "fuel": 0.45, "rate": 0.55, "heat": 3600.0, "cond": 0.8, "ash": 0.7, "melt": 0.0},
	Mat.PLASTIC: {"ignite": 340.0, "fuel": 0.8, "rate": 0.13, "heat": 5600.0, "cond": 0.5, "ash": 0.2, "melt": 150.0},
	Mat.METAL: {"ignite": 9999.0, "fuel": 0.0, "rate": 0.0, "heat": 0.0, "cond": 3.2, "ash": 0.0, "melt": 0.0},
	Mat.OIL: {"ignite": 255.0, "fuel": 0.35, "rate": 0.3, "heat": 6200.0, "cond": 2.4, "ash": 0.3, "melt": 0.0},
	Mat.FABRIC: {"ignite": 255.0, "fuel": 0.6, "rate": 0.3, "heat": 4300.0, "cond": 0.7, "ash": 0.55, "melt": 0.0},
	Mat.SHELL: {"ignite": 9999.0, "fuel": 0.0, "rate": 0.0, "heat": 0.0, "cond": 0.6, "ash": 0.0, "melt": 0.0},
}
const RISE := 1.6          # конвекция: доля перегрева соседа снизу, уходящая вверх за секунду
const NEWTON := 0.35       # теплоотдача воздуху, 1/с
const RADIATE := 2.6e-10   # излучение: коэффициент при (T⁴ − T₀⁴), в кельвинах
const O2_USE := 2.2        # кислород на единицу топлива
const O2_REFILL := 1.4     # подтекание кислорода из воздуха, 1/с
const COND_SCALE := 0.8    # масштаб теплопроводности сетки
const FLAME_FLUX := 2200.0  # лучистый поток пламени на соседние клетки, °C/с (с весом 1/d², вверх — сильнее)

var w := 96
var h := 54
var area := Rect2(0, 0, 1280, 720)
var temp := PackedFloat32Array()
var fuel := PackedFloat32Array()
var fuel0 := PackedFloat32Array()
var oxy := PackedFloat32Array()
var charred := PackedFloat32Array()  # доля сгоревшего топлива 0..1 (уголь)
var ash := PackedFloat32Array()
var melt := PackedFloat32Array()
var foam := PackedFloat32Array()
var mat := PackedByteArray()
var burning_cells := 0
var time := 0.0
var _next := PackedFloat32Array()
var _flux := PackedFloat32Array()
# свойства материалов в плоских массивах (индекс — Mat): словари в горячем цикле слишком медленные
var _ign := PackedFloat32Array()
var _rate := PackedFloat32Array()
var _heat := PackedFloat32Array()
var _cond := PackedFloat32Array()
var _ashy := PackedFloat32Array()
var _melt := PackedFloat32Array()


func _init(cols := 96, rows := 54, rect := Rect2(0, 0, 1280, 720)) -> void:
	w = cols
	h = rows
	area = rect
	var n := w * h
	temp.resize(n)
	fuel.resize(n)
	fuel0.resize(n)
	oxy.resize(n)
	charred.resize(n)
	ash.resize(n)
	melt.resize(n)
	foam.resize(n)
	_next.resize(n)
	_flux.resize(n)
	mat.resize(n)
	temp.fill(AMBIENT)
	oxy.fill(1.0)
	for m in Mat.size():
		var pr: Dictionary = PROPS[m]
		_ign.append(pr["ignite"])
		_rate.append(pr["rate"])
		_heat.append(pr["heat"])
		_cond.append(pr["cond"])
		_ashy.append(pr["ash"])
		_melt.append(pr["melt"])


func cell_size() -> Vector2:
	return area.size / Vector2(w, h)


func index_at(p: Vector2) -> int:
	var c := ((p - area.position) / cell_size()).floor()
	return clampi(int(c.y), 0, h - 1) * w + clampi(int(c.x), 0, w - 1)


func cell_center(i: int) -> Vector2:
	return area.position + (Vector2(i % w, i / w) + Vector2(0.5, 0.5)) * cell_size()


## Задать материал клетки (с полным запасом топлива).
func set_mat(i: int, m: int) -> void:
	mat[i] = m
	fuel[i] = PROPS[m]["fuel"]
	fuel0[i] = fuel[i]
	charred[i] = 0.0


## Залить прямоугольник (в пикселях) материалом.
func fill_rect(r: Rect2, m: int) -> void:
	var cs := cell_size()
	for y in h:
		for x in w:
			var c := area.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cs
			if r.has_point(c):
				set_mat(y * w + x, m)


func fill_circle(center: Vector2, radius: float, m: int) -> void:
	var cs := cell_size()
	for y in h:
		for x in w:
			var c := area.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cs
			if c.distance_to(center) <= radius:
				set_mat(y * w + x, m)


## Отрезок толщиной width (например, обломок вилки).
func fill_line(a: Vector2, b: Vector2, width: float, m: int) -> void:
	var cs := cell_size()
	for y in h:
		for x in w:
			var c := area.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cs
			var t := clampf((c - a).dot(b - a) / maxf((b - a).length_squared(), 0.001), 0.0, 1.0)
			if c.distance_to(a.lerp(b, t)) <= width * 0.5 + cs.x * 0.35:
				set_mat(y * w + x, m)


## Поднести пламя: нагреть круг до temperature.
func ignite(center: Vector2, radius: float, temperature := 900.0) -> void:
	for i in w * h:
		if cell_center(i).distance_to(center) <= radius:
			temp[i] = maxf(temp[i], temperature)


## Пена огнетушителя в круге (amount — толщина слоя за один вызов).
func add_foam(center: Vector2, radius: float, amount: float) -> void:
	for i in w * h:
		var d := cell_center(i).distance_to(center)
		if d <= radius:
			foam[i] = minf(foam[i] + amount * (1.0 - d / radius * 0.5), 1.0)


## Пена на прямоугольник (фронт огнетушителя: за ним слой держится, пока идёт тушение).
func add_foam_rect(r: Rect2, amount: float) -> void:
	for i in w * h:
		if r.has_point(cell_center(i)):
			foam[i] = minf(foam[i] + amount, 1.0)


func temp_at(p: Vector2) -> float:
	return temp[index_at(p)]


func is_burning(i: int) -> bool:
	return fuel[i] > 0.001 and temp[i] >= float(PROPS[mat[i]]["ignite"]) and oxy[i] > 0.05


## Доля клеток с топливом, которые сейчас горят.
func burning_fraction() -> float:
	return float(burning_cells) / float(w * h)


func total_fuel() -> float:
	var s := 0.0
	for f in fuel:
		s += f
	return s


## Шаг симуляции на dt секунд (внутри — подшаги не длиннее 0.09 с ради устойчивости).
func step(dt: float) -> void:
	var sub := maxi(1, ceili(dt / 0.09))
	var d := dt / sub
	for k in sub:
		_substep(d)


func _substep(dt: float) -> void:
	time += dt
	var burning := 0
	var n := w * h
	_radiate()
	for i in n:
		var x := i % w
		var y := i / w
		var t := temp[i]
		var m: int = mat[i]
		var ign := _ign[m]
		var tl := temp[i - 1] if x > 0 else AMBIENT
		var tr := temp[i + 1] if x < w - 1 else AMBIENT
		var tu := temp[i - w] if y > 0 else AMBIENT
		var td := temp[i + w] if y < h - 1 else AMBIENT
		# теплопроводность (явная схема, коэффициент ≤ 0.24 на подшаг — устойчиво)
		var k := minf(_cond[m] * dt * COND_SCALE, 0.24)
		var nt := t + k * (tl + tr + tu + td - 4.0 * t)
		# конвекция: горячий воздух снизу поднимается и греет клетку
		if td > t:
			nt += (td - t) * RISE * dt
		nt += _flux[i] * dt * (1.0 - foam[i])
		# горение
		var f := fuel[i]
		if f > 0.0 and t >= ign and oxy[i] > 0.05:
			var over := clampf((t - ign) / 250.0, 0.25, 1.6)
			var burn := minf(f, _rate[m] * fuel0[i] * oxy[i] * over * dt)
			f -= burn
			nt += burn * _heat[m]
			oxy[i] = maxf(oxy[i] - burn * O2_USE, 0.0)
			burning += 1
		fuel[i] = f
		oxy[i] = minf(oxy[i] + (1.0 - oxy[i]) * O2_REFILL * dt * (1.0 - foam[i]), 1.0 - foam[i] * 0.95)
		# остывание: излучение ~T⁴ и теплоотдача воздуху
		var tk := nt + 273.15
		nt -= (RADIATE * (tk * tk * tk * tk - 293.15 * 293.15 * 293.15 * 293.15) + NEWTON * (nt - AMBIENT)) * dt
		# пена: холодный слой отбирает тепло
		if foam[i] > 0.0:
			nt -= foam[i] * 900.0 * dt
			foam[i] = maxf(foam[i] - 0.22 * dt, 0.0)  # пена оседает, под ней — уголь и зола
		_next[i] = clampf(nt, AMBIENT, MAX_T)
		# уголь и зола — только растут
		if fuel0[i] > 0.0:
			charred[i] = maxf(charred[i], 1.0 - f / fuel0[i])
			ash[i] = maxf(ash[i], clampf((charred[i] - 0.55) / 0.45, 0.0, 1.0) * _ashy[m])
		# пластик плавится и течёт вниз, сохраняя массу
		if m == Mat.PLASTIC and t > _melt[m]:
			melt[i] = minf(melt[i] + 0.7 * dt, 1.0)
			if y < h - 1 and f > 0.02:
				var j := i + w
				if mat[j] != Mat.WOOD:
					var flow := minf(f * 0.5, 0.35 * melt[i] * dt)
					fuel[i] -= flow
					fuel0[i] -= flow
					fuel[j] += flow
					fuel0[j] += flow
					if mat[j] != Mat.PLASTIC:
						mat[j] = Mat.PLASTIC
						charred[j] = 0.0
					melt[j] = maxf(melt[j], melt[i] * 0.9)
	var tmp := temp
	temp = _next
	_next = tmp
	burning_cells = burning


## Лучистый подогрев: каждая горящая клетка отдаёт поток более холодным соседям в квадрате 5×5
## (чистый поток пропорционален разности температур — как обмен излучением).
func _radiate() -> void:
	_flux.fill(0.0)
	for i in w * h:
		var m: int = mat[i]
		if fuel[i] <= 0.001 or temp[i] < _ign[m]:
			continue
		var x := i % w
		var y := i / w
		var ti := temp[i]
		var power := FLAME_FLUX * clampf(ti / 1000.0, 0.3, 1.3) * oxy[i]
		for dy in range(-2, 3):
			var yy := y + dy
			if yy < 0 or yy >= h:
				continue
			for dx in range(-2, 3):
				var xx := x + dx
				if xx < 0 or xx >= w or (dx == 0 and dy == 0):
					continue
				var j := yy * w + xx
				var tj := temp[j]
				if tj >= ti:  # излучение между одинаково горячими клетками взаимно гасится
					continue
				var up := 1.6 if dy < 0 else (0.7 if dy > 0 else 1.0)  # пламя тянется вверх
				_flux[j] += power * up * (ti - tj) / ti / float(dx * dx + dy * dy)


## Мгновенно довести пожар до конца: всё выгорело, осталась зола (пропуск финала).
func burn_out() -> void:
	for i in w * h:
		if fuel0[i] > 0.0:
			fuel[i] = 0.0
			charred[i] = 1.0
			ash[i] = maxf(ash[i], float(PROPS[mat[i]]["ash"]))
		temp[i] = AMBIENT + 60.0
	burning_cells = 0


## Упаковать поля в байты для текстур шейдера:
## data — RGBA: температура, обугливание, зола, расплав; info — RG: материал, пена.
func pack(data: PackedByteArray, info: PackedByteArray) -> void:
	var n := w * h
	if data.size() != n * 4:
		data.resize(n * 4)
	if info.size() != n * 2:
		info.resize(n * 2)
	for i in n:
		var o := i * 4
		data[o] = int(clampf(temp[i] / MAX_T, 0.0, 1.0) * 255.0)
		data[o + 1] = int(charred[i] * 255.0)
		data[o + 2] = int(ash[i] * 255.0)
		data[o + 3] = int(melt[i] * 255.0)
		info[i * 2] = mat[i] * 32
		info[i * 2 + 1] = int(foam[i] * 255.0)
