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
## Копоть и окалина (scorch) копятся на всём, что побывало в жару, и тоже не исчезают.
## Каждый пожар свой: vary(seed) прогревает углы ящика по-разному и чуть меняет запас топлива.
## Фазовые переходы (пластик потёк, металл раскалился, скорлупа закоптилась) и порядок первого
## воспламенения материалов записываются — по ним тесты проверяют, что огонь «дошёл» и что раны разные.
## Подробно — docs/FIRE.md.

enum Mat { NONE, WOOD, PAPER, PLASTIC, METAL, OIL, FABRIC, SHELL }

const AMBIENT := 20.0
const MAX_T := 1400.0
## Свойства материалов: ignite — точка воспламенения °C, fuel — запас топлива, rate — доля запаса,
## сгорающая за секунду при полном кислороде, heat — нагрев клетки на единицу сгоревшего топлива,
## cond — теплопроводность, ash — выход золы, melt — точка плавления (0 — не плавится).
const PROPS := {
	Mat.NONE: {"ignite": 9999.0, "fuel": 0.0, "rate": 0.0, "heat": 0.0, "cond": 1.2, "ash": 0.0, "melt": 0.0},
	Mat.WOOD: {"ignite": 290.0, "fuel": 0.85, "rate": 0.075, "heat": 5200.0, "cond": 0.9, "ash": 0.85, "melt": 0.0},
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
const FLAME_REACH := 9      # радиус излучения: клетки с d² ≤ 9 (квадрат 5×5 и ещё по клетке на осях)
const SEED_WARM := 110.0    # vary(): прогрев углов ящика до +110 °C (квадратично — обычно тёплый один угол)
const FUEL_JITTER := 0.06   # vary(): запас топлива ±6% пятнами
const MELT_SEEN := 0.3      # расплав, с которого лужа заметна (фазовый переход «пластик потёк»)
const GLOW_SEEN := 520.0    # накал металла, с которого он светится (fire.gd::_draw_debris — от 480)
const SOOT_SEEN := 0.3      # копоть на скорлупе, которую видно
## Фазовые переходы, которые игрок должен увидеть.
enum Phase { MELT, GLOW, SOOT }

var w := 96
var h := 54
var area := Rect2(0, 0, 1280, 720)
var temp := PackedFloat32Array()
var amb := PackedFloat32Array()   # температура «комнаты» над клеткой: у тёплого угла ящика (vary) выше
var fuel := PackedFloat32Array()
var fuel0 := PackedFloat32Array()
var oxy := PackedFloat32Array()
var charred := PackedFloat32Array()  # доля сгоревшего топлива 0..1 (уголь)
var ash := PackedFloat32Array()
var melt := PackedFloat32Array()
var foam := PackedFloat32Array()
var scorch := PackedFloat32Array()  # копоть/окалина 0..1 — только растёт
var mat := PackedByteArray()
var burning_cells := 0
var time := 0.0
## Время первого воспламенения каждого материала (индекс — Mat, −1 — ещё не горел) и их порядок.
var ignited_at := PackedFloat32Array()
var ignition_order: Array[int] = []
## Время фазовых переходов (индекс — Phase, −1 — ещё не было).
var phase_at := PackedFloat32Array([-1.0, -1.0, -1.0])
var _offs: Array[Vector3i] = []  # смещения излучения: (dx, dy, d²)
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
	amb.resize(n)
	fuel.resize(n)
	fuel0.resize(n)
	oxy.resize(n)
	charred.resize(n)
	ash.resize(n)
	melt.resize(n)
	foam.resize(n)
	scorch.resize(n)
	_next.resize(n)
	_flux.resize(n)
	mat.resize(n)
	temp.fill(AMBIENT)
	oxy.fill(1.0)
	amb.fill(AMBIENT)
	for m in Mat.size():
		var pr: Dictionary = PROPS[m]
		_ign.append(pr["ignite"])
		_rate.append(pr["rate"])
		_heat.append(pr["heat"])
		_cond.append(pr["cond"])
		_ashy.append(pr["ash"])
		_melt.append(pr["melt"])
		ignited_at.append(-1.0)
	var r := ceili(sqrt(float(FLAME_REACH)))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d2 := dx * dx + dy * dy
			if d2 > 0 and d2 <= FLAME_REACH:
				_offs.append(Vector3i(dx, dy, d2))


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


## Разнообразие от сида: углы ящика прогреты по-разному (билинейно между четырьмя углами), запас
## топлива гуляет на ±FUEL_JITTER пятнами размером в несколько клеток. Вызывать после раскладки.
func vary(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var corner := [rng.randf(), rng.randf(), rng.randf(), rng.randf()]  # левый верх, правый верх, левый низ, правый низ
	var gw := 9
	var gh := 6
	var lat := PackedFloat32Array()
	for k in (gw + 1) * (gh + 1):
		lat.append(rng.randf_range(-1.0, 1.0))
	for i in w * h:
		var u := (float(i % w) + 0.5) / w
		var v := (float(i / w) + 0.5) / h
		var warm: float = lerpf(lerpf(corner[0], corner[1], u), lerpf(corner[2], corner[3], u), v)
		amb[i] = AMBIENT + SEED_WARM * warm * warm
		temp[i] = amb[i]
		if fuel0[i] <= 0.0:
			continue
		var gx := u * gw
		var gy := v * gh
		var x0 := mini(int(gx), gw - 1)
		var y0 := mini(int(gy), gh - 1)
		var a := lerpf(lat[y0 * (gw + 1) + x0], lat[y0 * (gw + 1) + x0 + 1], gx - x0)
		var b := lerpf(lat[(y0 + 1) * (gw + 1) + x0], lat[(y0 + 1) * (gw + 1) + x0 + 1], gx - x0)
		fuel[i] *= 1.0 + FUEL_JITTER * lerpf(a, b, gy - y0)
		fuel0[i] = fuel[i]


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


## Сколько клеток сгорело (обуглено больше чем наполовину) — для протокола «сожжено: N клеток».
func burnt_cells() -> int:
	var n := 0
	for i in w * h:
		if fuel0[i] > 0.0 and charred[i] >= 0.5:
			n += 1
	return n


## Сколько клеток вообще могло сгореть.
func fuel_cells() -> int:
	var n := 0
	for f in fuel0:
		if f > 0.0:
			n += 1
	return n


## Когда случился первый фазовый переход (−1 — ещё не было).
func first_phase() -> float:
	var best := -1.0
	for p in phase_at:
		if p >= 0.0 and (best < 0.0 or p < best):
			best = p
	return best


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
			if ignited_at[m] < 0.0:
				ignited_at[m] = time
				ignition_order.append(m)
		fuel[i] = f
		oxy[i] = minf(oxy[i] + (1.0 - oxy[i]) * O2_REFILL * dt * (1.0 - foam[i]), 1.0 - foam[i] * 0.95)
		# остывание: излучение ~T⁴ и теплоотдача воздуху
		var tk := nt + 273.15
		nt -= (RADIATE * (tk * tk * tk * tk - 293.15 * 293.15 * 293.15 * 293.15) + NEWTON * (nt - amb[i])) * dt
		# пена: холодный слой отбирает тепло
		if foam[i] > 0.0:
			nt -= foam[i] * 900.0 * dt
			foam[i] = maxf(foam[i] - 0.22 * dt, 0.0)  # пена оседает, под ней — уголь и зола
		_next[i] = clampf(nt, AMBIENT, MAX_T)
		# копоть и окалина — только растут: скорлупа коптится, металл темнеет и раскаляется
		if t > 180.0:
			scorch[i] = maxf(scorch[i], minf((t - 180.0) / 420.0, 1.0))
			if m == Mat.SHELL and scorch[i] >= SOOT_SEEN and phase_at[Phase.SOOT] < 0.0:
				phase_at[Phase.SOOT] = time
			elif m == Mat.METAL and t >= GLOW_SEEN and phase_at[Phase.GLOW] < 0.0:
				phase_at[Phase.GLOW] = time
		# уголь и зола — только растут
		if fuel0[i] > 0.0:
			charred[i] = maxf(charred[i], 1.0 - f / fuel0[i])
			ash[i] = maxf(ash[i], clampf((charred[i] - 0.55) / 0.45, 0.0, 1.0) * _ashy[m])
		# пластик плавится и течёт вниз, сохраняя массу
		if m == Mat.PLASTIC and t > _melt[m]:
			melt[i] = minf(melt[i] + 0.7 * dt, 1.0)
			if melt[i] >= MELT_SEEN and phase_at[Phase.MELT] < 0.0:
				phase_at[Phase.MELT] = time
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


## Лучистый подогрев: каждая горящая клетка отдаёт поток более холодным соседям в радиусе
## √FLAME_REACH клеток (чистый поток пропорционален разности температур — как обмен излучением).
func _radiate() -> void:
	_flux.fill(0.0)
	for i in w * h:
		var m: int = mat[i]
		if fuel[i] <= 0.001 or temp[i] < _ign[m]:
			continue
		var x := i % w
		var y := i / w
		var ti := temp[i]
		var power := FLAME_FLUX * clampf(ti / 1000.0, 0.3, 1.3) * oxy[i] / ti
		for o in _offs:
			var yy := y + o.y
			var xx := x + o.x
			if yy < 0 or yy >= h or xx < 0 or xx >= w:
				continue
			var j := yy * w + xx
			var tj := temp[j]
			if tj >= ti:  # излучение между одинаково горячими клетками взаимно гасится
				continue
			var up := 1.6 if o.y < 0 else (0.7 if o.y > 0 else 1.0)  # пламя тянется вверх
			_flux[j] += power * up * (ti - tj) / float(o.z)


## Мгновенно довести пожар до конца: всё выгорело, осталась зола (пропуск финала).
func burn_out() -> void:
	for i in w * h:
		if fuel0[i] > 0.0:
			fuel[i] = 0.0
			charred[i] = 1.0
			ash[i] = maxf(ash[i], float(PROPS[mat[i]]["ash"]))
		scorch[i] = maxf(scorch[i], 0.8)
		temp[i] = AMBIENT + 60.0
	burning_cells = 0


## Упаковать поля в байты для текстур шейдера:
## data — RGBA: температура, обугливание, зола, расплав; info — RGB: материал, пена, копоть.
func pack(data: PackedByteArray, info: PackedByteArray) -> void:
	var n := w * h
	if data.size() != n * 4:
		data.resize(n * 4)
	if info.size() != n * 3:
		info.resize(n * 3)
	for i in n:
		var o := i * 4
		data[o] = int(clampf(temp[i] / MAX_T, 0.0, 1.0) * 255.0)
		data[o + 1] = int(charred[i] * 255.0)
		data[o + 2] = int(ash[i] * 255.0)
		data[o + 3] = int(melt[i] * 255.0)
		info[i * 3] = mat[i] * 32
		info[i * 3 + 1] = int(foam[i] * 255.0)
		info[i * 3 + 2] = int(scorch[i] * 255.0)
