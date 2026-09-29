extends RefCounted
## Фигуры технического режима «Контакт» (v10.0): змея встаёт на дыбы и рисует на полу знак, понятный
## врагу. У каждого вида свой знак — одной линией: медведю сердце, вилке волна, таблетке
## бесконечность, матрёшке спираль, яичнице солнце. Здесь шаблоны и оценка обводки игрока.
## Всё статическое: без узлов, тестам удобно.

const KINDS := ["bear", "fork", "pill", "doll", "egg"]
const NAMES := {"bear": "СЕРДЦЕ", "fork": "ВОЛНА", "pill": "БЕСКОНЕЧНОСТЬ", "doll": "СПИРАЛЬ", "egg": "СОЛНЦЕ"}
const SAMPLES := 64
## Засчитано: обведено не меньше этой доли фигуры, и след в среднем не дальше допуска от неё —
## по порядку обхода (как в распознавателе жестов $1): так «сердце» не сойдёт за «солнце».
const MIN_COVERAGE := 0.85
## Допуск (px) по сложностям: лёгкая … ультра. Ближайшие знаки (сердце и солнце) расходятся на ~34 px.
const TOLERANCE := [30.0, 26.0, 22.0, 19.0]


## Шаблон вида kind: точки в квадрате −1..1 одной линией.
static func unit(kind: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	match kind:
		"bear":  # сердце
			for i in 73:
				var a := TAU * i / 72.0
				var x := 16.0 * pow(sin(a), 3)
				var y := 13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)
				out.append(Vector2(x / 17.0, -(y + 2.5) / 15.0))
		"fork":  # волна «≈»: два периода
			for i in 61:
				var k := i / 60.0
				out.append(Vector2(-1.0 + 2.0 * k, sin(k * TAU * 2.0) * 0.45))
		"pill":  # бесконечность (лемниската Бернулли)
			for i in 81:
				var a := TAU * i / 80.0
				var d := 1.0 + sin(a) * sin(a)
				out.append(Vector2(cos(a) / d, sin(a) * cos(a) / d * 1.3))
		"doll":  # спираль: два витка изнутри наружу
			for i in 81:
				var k := i / 80.0
				var a := k * TAU * 2.0
				out.append(Vector2.from_angle(a) * (0.12 + 0.88 * k))
		"egg":  # солнце: восемь лучей ломаной
			for i in 17:
				var a := TAU * i / 16.0 - PI / 2.0
				out.append(Vector2.from_angle(a) * (1.0 if i % 2 == 0 else 0.5))
	return out


## Шаблон в мире: центр и полуразмер (px).
static func template(kind: String, center: Vector2, half: float) -> PackedVector2Array:
	var out := unit(kind)
	for i in out.size():
		out[i] = center + out[i] * half
	return out


static func length(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(1, pts.size()):
		s += pts[i - 1].distance_to(pts[i])
	return s


## Точка на ломаной на расстоянии d от начала.
static func point_at(pts: PackedVector2Array, d: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if d <= seg and seg > 0.0:
			return pts[i - 1].lerp(pts[i], d / seg)
		d -= seg
	return pts[pts.size() - 1]


## n точек, равномерно по длине ломаной.
static func resample(pts: PackedVector2Array, n := SAMPLES) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return pts.duplicate()
	var total := length(pts)
	for i in n:
		out.append(point_at(pts, total * i / float(n - 1)))
	return out


## Расстояние от точки до ломаной.
static func dist_to(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in range(1, pts.size()):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])))
	return best


## Оценка обводки: coverage — доля фигуры, до которой след ближе tol; error — среднее расстояние
## между соответственными точками следа и фигуры; ok — засчитано. Направление не важно, а у замкнутых
## знаков — и место начала.
static func score(trace: PackedVector2Array, tmpl: PackedVector2Array, tol: float) -> Dictionary:
	if trace.size() < 2 or tmpl.size() < 2:
		return {"coverage": 0.0, "error": INF, "ok": false}
	var tr := resample(trace)
	var tp := resample(tmpl)
	var covered := 0
	for p in tp:
		if dist_to(p, tr) <= tol:
			covered += 1
	var cov := float(covered) / tp.size()
	var err := seq_error(tr, tp, tmpl[0].distance_to(tmpl[tmpl.size() - 1]) < 4.0)
	return {"coverage": cov, "error": err, "ok": cov >= MIN_COVERAGE and err <= tol}


## Среднее расстояние между i-ми точками следа и фигуры (обе — resample на SAMPLES): лучшее по
## направлению обхода и, для замкнутой фигуры, по сдвигу начала.
static func seq_error(tr: PackedVector2Array, tp: PackedVector2Array, closed: bool) -> float:
	var n := tp.size()
	var best := INF
	for rev in [false, true]:
		var a := tr.duplicate()
		if rev:
			a.reverse()
		var shifts := n - 1 if closed else 1
		for k in shifts:
			var sum := 0.0
			for i in n:
				sum += a[i].distance_to(tp[(i + k) % (n - 1)] if closed else tp[i])
				if sum >= best * n:  # уже хуже лучшего — дальше не считать
					break
			best = minf(best, sum / n)
	return best


static func tol_for(difficulty: int) -> float:
	return TOLERANCE[clampi(difficulty, 0, TOLERANCE.size() - 1)]
