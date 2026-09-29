extends RefCounted
## Audio Rebound — стохастическая трассировка лучей (метод Краусада, 1968, с приёмником-сферой).
##
## Помещение — прямоугольный объём («коробка»): у каждой из шести граней свой материал, грань может быть
## проёмом ("open" — звук уходит наружу, как через открытый верх ящика). Пол можно задать сеткой
## материалов (коврик посреди детской, половик в тереме, уголь и зола после пожара). Внутри — препятствия-
## сферы со своим материалом: медведи из плюша, стальные вилки, пластиковые таблетки, лаковые матрёшки.
##
## Из каждого источника вылетает rays лучей (равномерно по сфере). Луч несёт энергию по шести октавным
## полосам; на каждом отражении полоса теряет долю α своего материала, по пути — энергию на поглощение
## воздухом (ISO 9613-1). Отражение зеркальное с вероятностью 1 − s, иначе рассеянное по Ламберту
## (косинусное распределение). Когда луч проходит сквозь приёмник-сферу, его энергия записывается
## в гистограмму по времени прихода (импульсный отклик), а направление прихода — в панораму.
## Прямой звук считается точно (закон обратных квадратов), а не лучами — так он не «шумит».
## Энергия нормирована так, что прямой звук на расстоянии r равен 1/r² (1 — на одном метре).
## Всё детерминировано сидом: одна сцена и один сид — один и тот же отклик.

const Acoustics = preload("res://scripts/audio/rebound/acoustics.gd")

const NB := 6
const MAX_BOUNCES := 60
const E_MIN := 1e-5      # луч с меньшей энергией (во всех полосах) дальше не ведём
const SHADOW := 0.35     # доля энергии прямого звука за препятствием (дифракция огибает его частично)

## Сцена для трассировки — словарь (его можно собрать в основном потоке и отдать в фоновый):
## size: Vector3 (м), faces: 6 материалов [−x, +x, −y, +y, пол −z, верх +z],
## floor: {"w", "h", "cells": PackedByteArray (индексы в palette), "palette": Array[String]} — необязательно,
## spheres: [[Vector3 центр, радиус, материал], ...], listener: Vector3, sources: [Vector3, ...],
## rays, seed, t_max (с), bin (с), receiver_r (м), temp_c, gas ({M, gamma}), rh (%).


static func trace(scene: Dictionary) -> Dictionary:
	var size: Vector3 = scene["size"]
	var faces: Array = scene["faces"]
	var spheres: Array = scene.get("spheres", [])
	var listener: Vector3 = scene["listener"]
	var sources: Array = scene["sources"]
	var rays := int(scene.get("rays", 256))
	var t_max := float(scene.get("t_max", 0.12))
	var bin := float(scene.get("bin", 0.0005))
	var rr := float(scene.get("receiver_r", 0.1))
	var temp_c := float(scene.get("temp_c", 20.0))
	var gas: Dictionary = scene.get("gas", Acoustics.GAS["air"])
	var rh := float(scene.get("rh", 50.0))
	var c := Acoustics.speed_of_sound(temp_c, gas)
	var nbins := maxi(1, ceili(t_max / bin))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(scene.get("seed", 1))

	# палитра материалов: грани, пол, сферы — в плоские массивы (словари в горячем цикле медленные)
	var palette: Array[String] = []
	var face_idx := PackedInt32Array()
	for m in faces:
		face_idx.append(_pal(palette, String(m)))
	var floor_map: Dictionary = scene.get("floor", {})
	var fw := int(floor_map.get("w", 0))
	var fh := int(floor_map.get("h", 0))
	var fcells: PackedByteArray = floor_map.get("cells", PackedByteArray())
	var fpal := PackedInt32Array()
	for m in floor_map.get("palette", []):
		fpal.append(_pal(palette, String(m)))
	var sph_c: Array[Vector3] = []
	var sph_r := PackedFloat32Array()
	var sph_m := PackedInt32Array()
	for s: Array in spheres:
		sph_c.append(s[0])
		sph_r.append(float(s[1]))
		sph_m.append(_pal(palette, String(s[2])))
	var refl := PackedFloat32Array()
	var scat := PackedFloat32Array()
	var is_open := PackedByteArray()
	for m in palette:
		for b in NB:
			refl.append(Acoustics.reflectance(m, b))
		scat.append(Acoustics.scatter(m))
		is_open.append(1 if m == "open" else 0)
	var air := PackedFloat32Array()
	for b in NB:
		air.append(Acoustics.air_m(b, clampf(temp_c, -20.0, 50.0), rh))

	var hist: Array[PackedFloat32Array] = []
	for b in NB:
		var hb := PackedFloat32Array()
		hb.resize(nbins)
		hist.append(hb)
	var pan := PackedFloat32Array()
	pan.resize(nbins)
	var escape := PackedFloat32Array()
	escape.resize(NB)
	var hits := 0
	var direct := 0.0
	var direct_t := 0.0
	var e0 := 1.0 / float(rays)
	var norm := 4.0 / (rr * rr) / float(maxi(sources.size(), 1))
	var e := PackedFloat32Array()
	e.resize(NB)

	for src: Vector3 in sources:
		# прямой звук — точно: 1/r², воздух, тень препятствий
		var r := maxf(src.distance_to(listener), rr)
		var shade := 1.0
		for k in sph_c.size():
			if _segment_hits_sphere(src, listener, sph_c[k], sph_r[k]):
				shade *= SHADOW
		direct += shade * exp(-air[Acoustics.MID] * r) / (r * r) / float(sources.size())
		direct_t += r / c / float(sources.size())
		for i in rays:
			var pos := src
			var dir := _sphere_dir(rng)
			for b in NB:
				e[b] = e0
			var dist := 0.0
			for bounce in MAX_BOUNCES:
				# ближайшая грань ящика
				var t_hit := INF
				var face := -1
				for a in 3:
					var d := dir[a]
					if d > 1e-9:
						var t := (size[a] - pos[a]) / d
						if t < t_hit:
							t_hit = t
							face = a * 2 + 1
					elif d < -1e-9:
						var t := -pos[a] / d
						if t < t_hit:
							t_hit = t
							face = a * 2
				# препятствия
				var sph := -1
				for k in sph_c.size():
					var t := _ray_sphere(pos, dir, sph_c[k], sph_r[k])
					if t > 1e-6 and t < t_hit:
						t_hit = t
						sph = k
				t_hit = maxf(t_hit, 0.0)
				# приёмник: отражённый звук (прямой посчитан точно)
				if bounce > 0:
					var to_l := listener - pos
					var tc := to_l.dot(dir)
					if tc > 0.0 and tc < t_hit and to_l.length_squared() - tc * tc < rr * rr:
						var at := dist + tc
						var k_bin := int(at / c / bin)
						if k_bin < nbins:
							for b in NB:
								hist[b][k_bin] += e[b] * exp(-air[b] * at) * norm
							pan[k_bin] += e[Acoustics.MID] * exp(-air[Acoustics.MID] * at) * norm * -dir.x
							hits += 1
				pos += dir * t_hit
				dist += t_hit
				if dist / c > t_max:
					break
				var mi: int
				var n: Vector3
				if sph >= 0:
					mi = sph_m[sph]
					n = (pos - sph_c[sph]).normalized()
				else:
					var ax := face / 2
					n = Vector3.ZERO
					n[ax] = -1.0 if face % 2 == 1 else 1.0
					mi = face_idx[face]
					if face == 4 and fw > 0:  # пол — по сетке материалов
						var gx := clampi(int(pos.x / size.x * fw), 0, fw - 1)
						var gy := clampi(int(pos.y / size.y * fh), 0, fh - 1)
						mi = fpal[fcells[gy * fw + gx]]
				if is_open[mi] == 1:  # проём: звук ушёл из объёма
					for b in NB:
						escape[b] += e[b] * exp(-air[b] * dist) / float(sources.size())
					break
				var alive := false
				for b in NB:
					e[b] *= refl[mi * NB + b]
					if e[b] > E_MIN * e0:
						alive = true
				if not alive:
					break
				if rng.randf() < scat[mi]:
					dir = _lambert(n, rng)
				else:
					dir = dir - 2.0 * dir.dot(n) * n
				pos += n * 1e-5  # чуть отступить от поверхности
	# escape — доля мощности источника, ушедшая через проёмы (по полосам)
	return {"hist": hist, "pan": pan, "direct": direct, "direct_t": direct_t, "escape": escape, "c": c,
		"bin": bin, "t_max": t_max, "hits": hits, "rays": rays * sources.size()}


static func _pal(palette: Array[String], m: String) -> int:
	var i := palette.find(m)
	if i < 0:
		palette.append(m)
		i = palette.size() - 1
	return i


## Равномерное направление на сфере.
static func _sphere_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var phi := rng.randf() * TAU
	var r := sqrt(maxf(1.0 - z * z, 0.0))
	return Vector3(r * cos(phi), r * sin(phi), z)


## Рассеянное отражение по Ламберту: плотность ∝ cos θ относительно нормали.
static func _lambert(n: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var u := rng.randf()
	var phi := rng.randf() * TAU
	var r := sqrt(u)
	var t := (Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).cross(n).normalized()
	var bt := n.cross(t)
	return (t * (r * cos(phi)) + bt * (r * sin(phi)) + n * sqrt(maxf(1.0 - u, 0.0))).normalized()


## Расстояние до пересечения луча со сферой снаружи (INF — мимо).
static func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.length_squared() - r * r
	if cc < 0.0:  # луч внутри сферы (источник в препятствии) — препятствия не видит
		return INF
	var disc := b * b - cc
	if disc < 0.0:
		return INF
	var t := -b - sqrt(disc)
	return t if t > 0.0 else INF


static func _segment_hits_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	if a.distance_to(c) < r or b.distance_to(c) < r:
		return false  # источник или слушатель сами внутри — не тень
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r


# ---------------------------------------------------------------- разбор отклика

## Сводка отклика: полосы, ранние отражения (две самые сильные — с задержкой относительно прямого звука,
## уровнем и панорамой), наклон спада, ясность. tail — поздний хвост соседнего помещения (см. rebound.gd):
## {"energy": [по полосам], "t60": [по полосам], "start": с}; он дописывается в отклик для EDT/T30/C50.
## with_direct = false — только отражения (так считается скорость спада ящика для порхающего эха:
## прямой звук в ящике громче всех отражений и «съел» бы первые −10 дБ кривой).
static func analyze(res: Dictionary, tail: Dictionary = {}, with_direct := true) -> Dictionary:
	var bin := float(res["bin"])
	var direct := float(res["direct"])
	var t0 := float(res["direct_t"])
	var hist: Array = res["hist"]
	var pan: PackedFloat32Array = res["pan"]
	var n := pan.size()
	# ранние отражения: сумма средних полос (500–2000 Гц), пики после прямого звука
	var mid := PackedFloat32Array()
	mid.resize(n)
	for i in n:
		mid[i] = (hist[2][i] + hist[3][i] + hist[4][i]) / 3.0
	var taps: Array = []
	var used := {}
	for k in 2:
		var best := -1
		for i in n:
			if (i + 0.5) * bin < t0 + 0.0003 or used.has(i):
				continue
			if best < 0 or mid[i] > mid[best]:
				best = i
		if best < 0 or mid[best] <= 0.0:
			break
		for j in range(best - 3, best + 4):  # соседние корзины — это то же отражение
			used[j] = true
		var e_sum := 0.0
		var p_sum := 0.0
		for j in range(maxi(best - 1, 0), mini(best + 2, n)):
			e_sum += hist[3][j]
			p_sum += pan[j]
		taps.append({"delay": maxf((best + 0.5) * bin - t0, 0.0), "db": Acoustics.db(mid[best] / maxf(direct, 1e-30)),
			"pan": clampf(p_sum / maxf(e_sum, 1e-30), -1.0, 1.0)})
	# полный отклик по полосам (прямой звук + лучи + хвост), шаг 2 мс
	var step := 0.002
	var dur := float(res.get("t_max", n * bin))
	var t60_tail: Array = tail.get("t60", [])
	var e_tail: Array = tail.get("energy", [])
	if not t60_tail.is_empty():
		dur = maxf(dur, float(tail.get("start", 0.0)) + float(t60_tail[Acoustics.MID]) * 1.2)
	var m := maxi(ceili(dur / step), 8)
	var out := {"taps": taps, "direct": direct, "direct_t": t0, "bands": []}
	for b in NB:
		var h := PackedFloat32Array()
		h.resize(m)
		if with_direct:
			h[mini(int(t0 / step), m - 1)] += direct
		var hb: PackedFloat32Array = hist[b]
		for i in hb.size():
			h[mini(int((i + 0.5) * bin / step), m - 1)] += hb[i]
		if not e_tail.is_empty():
			var t60 := maxf(float(t60_tail[b]), 0.01)
			var tau := t60 / (6.0 * log(10.0))  # энергия e^(−t/τ): −60 дБ за T60
			var start := float(tail.get("start", 0.0))
			var total := float(e_tail[b])
			for i in m:
				var t1 := i * step - start
				var t2 := t1 + step
				if t2 <= 0.0:
					continue
				h[i] += total * (exp(-maxf(t1, 0.0) / tau) - exp(-t2 / tau))
		var edc := Acoustics.schroeder_db(h)
		var early := 0.0
		for i in hb.size():
			early += hb[i]
		out["bands"].append({"edt": Acoustics.edt(edc, step), "t30": Acoustics.t30(edc, step),
			"t20": Acoustics.t20(edc, step), "c50": Acoustics.clarity(h, step, t0), "d50": Acoustics.definition(h, step, t0),
			"ts": Acoustics.center_time(h, step), "early": early})
	return out
