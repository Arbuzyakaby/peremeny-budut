extends RefCounted
## Процедурные иконки интерфейса. Каждая рисуется вокруг центра c в квадрате ~24×24 (s — масштаб).
## Сюжетные иконки (медведь, вилка, таблетка, яичница, атаки) — цветные «игрушки», служебные
## (пауза, шестерёнка, стрелка, замок...) — монохромные со штрихом 2.5.

const STROKE := 2.5

const INK := Color(0.078, 0.039, 0.02)


static func heart(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(-s * 0.5, -s * 0.2), s * 0.55, col)
	ci.draw_circle(c + Vector2(s * 0.5, -s * 0.2), s * 0.55, col)
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-s * 1.03, 0), c + Vector2(s * 1.03, 0), c + Vector2(0, s * 1.1)]), col)


static func bear(ci: CanvasItem, c: Vector2, s := 1.0, a := 1.0) -> void:
	var fur := Color(0.72, 0.5, 0.3, a)
	for k in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(k * 8, -8) * s, 5.0 * s, fur.darkened(0.3))
	ci.draw_circle(c, 10.0 * s, fur)
	ci.draw_circle(c + Vector2(0, 3) * s, 4.5 * s, fur.lightened(0.35))
	ci.draw_circle(c + Vector2(0, 1.5) * s, 1.8 * s, Color(0.15, 0.08, 0.05, a))
	for k in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(k * 4, -3) * s, 1.6 * s, Color(0, 0, 0, a))


static func fork(ci: CanvasItem, c: Vector2, s := 1.0, a := 1.0) -> void:
	var col := Color(0.72, 0.62, 0.55, a)
	ci.draw_line(c + Vector2(-12, 10) * s, c + Vector2(4, -4) * s, Color(0.2, 0.15, 0.12, a), 6.0 * s)
	ci.draw_line(c + Vector2(-12, 10) * s, c + Vector2(4, -4) * s, col, 3.5 * s)
	for i in 3:
		var o := Vector2(-4 + i * 4, -4 + i * 4) * 0.7
		ci.draw_line(c + (Vector2(2, -2) + o) * s, c + (Vector2(12, -12) + o) * s, col, 2.2 * s)
	ci.draw_circle(c + Vector2(-4, 2) * s, 2.2 * s, Color(0.65, 0.3, 0.12, a))


static func pill(ci: CanvasItem, c: Vector2, s := 1.0, a := 1.0) -> void:
	var red := Color(0.92, 0.2, 0.22, a)
	var white := Color(0.97, 0.95, 0.9, a)
	ci.draw_circle(c - Vector2(6, 0) * s, 6.5 * s, red)
	ci.draw_circle(c + Vector2(6, 0) * s, 6.5 * s, white)
	ci.draw_rect(Rect2(c + Vector2(-6, -6.5) * s, Vector2(6, 13) * s), red)
	ci.draw_rect(Rect2(c + Vector2(0, -6.5) * s, Vector2(6, 13) * s), white)
	ci.draw_line(c + Vector2(-7, -3.5) * s, c + Vector2(4, -3.5) * s, Color(1, 1, 1, 0.45 * a), 1.5 * s)


## Таблетка-шайба: круглая, с ребром и риской разлома.
static func tablet(ci: CanvasItem, c: Vector2, s := 1.0, a := 1.0) -> void:
	ci.draw_circle(c + Vector2(0, 2) * s, 9.5 * s, Color(0.78, 0.76, 0.7, a))
	ci.draw_circle(c, 9.5 * s, Color(0.97, 0.96, 0.92, a))
	ci.draw_line(c + Vector2(-6.5, 0) * s, c + Vector2(6.5, 0) * s, Color(0.6, 0.58, 0.52, a), 1.8 * s)
	ci.draw_circle(c + Vector2(-3.5, -4) * s, 2.2 * s, Color(1, 1, 1, 0.8 * a))


## Шипучка (v12.4): пористый апельсиновый диск и пузырьки над ним.
static func fizz(ci: CanvasItem, c: Vector2, s := 1.0, a := 1.0) -> void:
	ci.draw_circle(c + Vector2(0, 2.5) * s, 9.5 * s, Color(0.9, 0.6, 0.18, a))
	ci.draw_circle(c, 9.5 * s, Color(1.0, 0.86, 0.45, a))
	for i in 5:
		ci.draw_circle(c + Vector2.from_angle(i * 2.4) * 5.0 * s * sqrt((i + 0.5) / 5.0), 1.1 * s, Color(0.9, 0.6, 0.18, 0.7 * a))
	for i in 3:
		ci.draw_arc(c + Vector2(-5 + i * 5, -12 - i * 2.5) * s, (1.6 + i * 0.5) * s, 0, TAU, 10,
			Color(1.0, 0.97, 0.85, 0.9 * a), 1.2 * s)


## Учёный (досье, v12.4): голова в очках, седые виски, воротник халата и галстук.
static func scientist(ci: CanvasItem, c: Vector2, s := 1.0, a := 1.0) -> void:
	var line := Color(0.14, 0.14, 0.17, a)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-14, 16) * s, c + Vector2(14, 16) * s, c + Vector2(8, 6) * s,
		c + Vector2(-8, 6) * s]), Color(0.96, 0.96, 0.94, a))  # халат
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-2, 6) * s, c + Vector2(2, 6) * s, c + Vector2(1.5, 15) * s,
		c + Vector2(-1.5, 15) * s]), Color(0.55, 0.12, 0.14, a))  # галстук
	ci.draw_circle(c + Vector2(0, -3) * s, 10.5 * s, line)
	ci.draw_circle(c + Vector2(0, -3) * s, 9.5 * s, Color(0.93, 0.8, 0.7, a))
	ci.draw_arc(c + Vector2(0, -5) * s, 9.5 * s, PI + 0.2, TAU - 0.2, 12, Color(0.35, 0.3, 0.28, a), 4.0 * s)  # волосы
	for sd in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(sd * 9.5, -3) * s, 2.2 * s, Color(0.8, 0.8, 0.8, a))  # седые виски
		ci.draw_rect(Rect2(c + Vector2(sd * 4.2 - 3.2, -5) * s, Vector2(6.4, 4.4) * s), line, false, 1.2 * s)  # очки
	ci.draw_line(c + Vector2(-1, -3) * s, c + Vector2(1, -3) * s, line, 1.2 * s)
	ci.draw_line(c + Vector2(-3, 3) * s, c + Vector2(3, 3) * s, line, 1.3 * s)


## Таблетка по виду: 0 — капсула, 1 — шайба, 2 — шипучка.
static func pill_kind(ci: CanvasItem, c: Vector2, kind: int, s := 1.0, a := 1.0) -> void:
	match kind:
		1:
			tablet(ci, c, s, a)
		2:
			fizz(ci, c, s, a)
		_:
			pill(ci, c, s, a)


static func egg(ci: CanvasItem, c: Vector2, s := 1.0, a := 1.0) -> void:
	ci.draw_circle(c, 12.0 * s, Color(0.99, 0.97, 0.9, a))
	ci.draw_circle(c + Vector2(1, -1) * s, 5.5 * s, Color(1, 0.75, 0.1, a))
	ci.draw_circle(c + Vector2(-0.5, -2.5) * s, 1.8 * s, Color(1, 1, 1, 0.7 * a))


## Матрёшка: size 0 — малышка, 1 — средняя, 2 — большая (крупнее и с другим сарафаном).
static func doll(ci: CanvasItem, c: Vector2, size := 2, s := 1.0, a := 1.0) -> void:
	var dress: Color = [Color(0.95, 0.68, 0.12), Color(0.14, 0.36, 0.72), Color(0.8, 0.1, 0.1)][clampi(size, 0, 2)]
	var k: float = s * [0.8, 0.9, 1.0][clampi(size, 0, 2)]
	var d := Color(dress, a)
	ci.draw_circle(c + Vector2(0, 4) * k, 10.5 * k, Color(dress.darkened(0.6), a))
	ci.draw_circle(c + Vector2(0, -6) * k, 7.8 * k, Color(dress.darkened(0.6), a))
	ci.draw_circle(c + Vector2(0, 4) * k, 9.5 * k, d)
	ci.draw_circle(c + Vector2(0, -6) * k, 6.8 * k, Color(0.98, 0.8, 0.22, a))
	ci.draw_circle(c + Vector2(0, -5.5) * k, 4.6 * k, Color(1.0, 0.88, 0.76, a))
	ci.draw_circle(c + Vector2(0, 6) * k, 5.2 * k, Color(0.99, 0.95, 0.84, a))
	ci.draw_circle(c + Vector2(0, 6) * k, 2.2 * k, Color(dress.lightened(0.2), a))
	for sd in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(sd * 1.7, -6) * k, 0.8 * k, Color(0.16, 0.08, 0.05, a))
		ci.draw_circle(c + Vector2(sd * 2.6, -4.2) * k, 1.0 * k, Color(0.95, 0.45, 0.45, 0.7 * a))
	if size > 0:  # шов, по которому раскрывается
		ci.draw_arc(c + Vector2(0, -0.5) * k, 8.2 * k, 0.25, PI - 0.25, 10, Color(dress.darkened(0.6), a), 1.0 * k)
	ci.draw_arc(c + Vector2(0, 4) * k, 7.5 * k, PI + 0.5, PI + 1.3, 5, Color(1, 1, 1, 0.4 * a), 1.5 * k)


## Иконка цели этапа: 0 медведь, 1 вилка, 2 таблетка, 3 матрёшка, 4 яичница.
static func stage(ci: CanvasItem, c: Vector2, which: int, s := 1.0, a := 1.0) -> void:
	match which:
		0: bear(ci, c, s, a)
		1: fork(ci, c, s, a)
		2: pill(ci, c, s, a)
		3: doll(ci, c, 2, s, a)
		_: egg(ci, c, s, a)


## Иконка атаки: медведь-источник + его предмет.
static func ability(ci: CanvasItem, c: Vector2, type: int, t: float, s := 1.0) -> void:
	if type >= 10:  # v8.0: атаки вилок и таблеток — вилка своего вида или таблетка с бейджем приёма
		_enemy_ability(ci, c, type, t, s)
		return
	bear(ci, c, s)
	var o := c
	match type:
		1:  # боксёр — перчатка
			ci.draw_circle(o + Vector2(10, 7) * s, 6.0 * s, Color(0.55, 0.05, 0.05))
			ci.draw_circle(o + Vector2(10, 7) * s, 5.0 * s, Color(0.92, 0.15, 0.12))
		2:  # метатель — пуговица
			ci.draw_circle(o + Vector2(10, 8) * s, 6.0 * s, Color(0.2, 0.35, 0.7))
			ci.draw_circle(o + Vector2(10, 8) * s, 5.0 * s, Color(0.3, 0.55, 0.95))
		3:  # каратист — чёрная повязка
			ci.draw_line(o + Vector2(-9, -5) * s, o + Vector2(9, -5) * s, Color(0.08, 0.08, 0.08), 3.0 * s)
			ci.draw_line(o + Vector2(-9, -5) * s, o + Vector2(-14, 0) * s, Color(0.08, 0.08, 0.08), 2.0 * s)
		4:  # швея — иголка
			ci.draw_line(o + Vector2(4, 14) * s, o + Vector2(16, 0) * s, Color(0.85, 0.87, 0.92), 2.0 * s)
			ci.draw_circle(o + Vector2(4, 14) * s, 3.5 * s, Color(0.95, 0.8, 0.2))
		5:  # ниндзя — сюрикен
			var pts := PackedVector2Array()
			for i in 8:
				pts.append(o + Vector2(10, 8) * s + Vector2.from_angle(TAU * i / 8.0 + t * 3.0) * (8.0 if i % 2 == 0 else 3.0) * s)
			ci.draw_colored_polygon(pts, Color(0.7, 0.73, 0.8))
		6:  # хлопушка
			ci.draw_rect(Rect2(o + Vector2(4, 4) * s, Vector2(13, 8) * s), Color(0.95, 0.3, 0.5))
			ci.draw_circle(o + Vector2(2, 3) * s, (2.5 + sin(t * 20.0)) * s, Color(1, 0.85, 0.3))
		7:  # медсестра — крест
			ci.draw_rect(Rect2(o + Vector2(7, 1) * s, Vector2(5, 15) * s), Color(0.9, 0.12, 0.15))
			ci.draw_rect(Rect2(o + Vector2(2, 6) * s, Vector2(15, 5) * s), Color(0.9, 0.12, 0.15))


## Атаки вилок (10 залп, 11 выпад, 12 укол вилами), таблетки (13 ударная волна) и малышки (14 прыжок).
static func _enemy_ability(ci: CanvasItem, c: Vector2, type: int, t: float, s: float) -> void:
	if type == 14:
		var k := absf(sin(t * 4.0))
		ci.draw_arc(c + Vector2(0, 9) * s, 9.0 * s, 0, TAU, 18, Color(1.0, 0.75, 0.3, 0.8), 1.8 * s)
		doll(ci, c + Vector2(0, -2.0 - 5.0 * k) * s, 0, s)
		return
	if type == 13:
		pill(ci, c + Vector2(-2, 1) * s, s * 0.85)
		var k := fmod(t * 1.5, 1.0)
		ci.draw_arc(c + Vector2(-2, 1) * s, (8.0 + 8.0 * k) * s, 0, TAU, 20, Color(0.45, 1.0, 0.7, 1.0 - k), 2.0 * s)
		return
	fork_kind(ci, c + Vector2(-2, 2) * s, type - 10, s * 0.9)
	var badge := c + Vector2(10, 8) * s
	ci.draw_circle(badge, 7.0 * s, Color(0.08, 0.04, 0.02))
	fork_attack(ci, badge, [1, 0, 3][type - 10], Color(1, 0.85, 0.5), s * 0.45)


static func shield(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, Color(0.3, 0.55, 0.9, 0.5))
	ci.draw_arc(c, r, 0, TAU, 24, Color(0.75, 0.9, 1.0), 2.5)
	ci.draw_arc(c, r * 0.7, -2.5, -1.6, 6, Color(1, 1, 1, 0.8), 2.0)


## Чешуйка — валюта древа навыков.
static func scale_coin(ci: CanvasItem, c: Vector2, s := 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI * (0.05 + 0.9 * i / 12.0)
		pts.append(c + Vector2(cos(a) * 9.0, -sin(a) * 10.0 + 5.0) * s)
	pts.append(c + Vector2(0, 9) * s)
	ci.draw_colored_polygon(pts, Color(0.33, 0.8, 0.45))
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.1, 0.35, 0.15), 1.5 * s)
	ci.draw_arc(c + Vector2(0, 2) * s, 5.0 * s, PI * 1.15, PI * 1.85, 6, Color(0.75, 1, 0.8), 1.5 * s)


static func pause(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	for k in [-1.0, 1.0]:
		ci.draw_rect(Rect2(c + Vector2(k * 4.5 - 2.5, -8) * s, Vector2(5, 16) * s), col)


static func gear(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	for i in 8:
		var d := Vector2.from_angle(TAU * i / 8.0)
		ci.draw_line(c + d * 6.0 * s, c + d * 10.5 * s, col, 3.5 * s)
	ci.draw_arc(c, 6.5 * s, 0, TAU, 20, col, STROKE * s)
	ci.draw_circle(c, 2.0 * s, col)


static func arrow_back(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	ci.draw_line(c + Vector2(8, 0) * s, c + Vector2(-8, 0) * s, col, STROKE * s)
	ci.draw_polyline(PackedVector2Array([c + Vector2(-1, -7) * s, c + Vector2(-8, 0) * s, c + Vector2(-1, 7) * s]), col, STROKE * s)


static func lock(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	ci.draw_arc(c + Vector2(0, -3) * s, 5.0 * s, PI, TAU, 10, col, STROKE * s)
	ci.draw_rect(Rect2(c + Vector2(-7, -3) * s, Vector2(14, 11) * s), col)


static func check(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(-7, 0) * s, c + Vector2(-2, 5) * s, c + Vector2(8, -6) * s]), col, 3.0 * s)


static func bolt(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(2, -10) * s, c + Vector2(-6, 2) * s, c + Vector2(0, 2) * s,
		c + Vector2(-2, 10) * s, c + Vector2(6, -2) * s, c + Vector2(0, -2) * s]), col)


static func code(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(-4, -7) * s, c + Vector2(-10, 0) * s, c + Vector2(-4, 7) * s]), col, STROKE * s)
	ci.draw_polyline(PackedVector2Array([c + Vector2(4, -7) * s, c + Vector2(10, 0) * s, c + Vector2(4, 7) * s]), col, STROKE * s)
	ci.draw_line(c + Vector2(2, -9) * s, c + Vector2(-2, 9) * s, col, 2.0 * s)


## Клык — узел ветки «атака» в древе навыков.
static func fang(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	for k in [-1.0, 1.0]:
		ci.draw_colored_polygon(PackedVector2Array([
			c + Vector2(k * 6.5, -7) * s, c + Vector2(k * 1.5, -7) * s, c + Vector2(k * 4.0, 8) * s]), col)


static func star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2 + TAU * i / 10.0) * rr)
	ci.draw_colored_polygon(pts, col)


## Вилка своего вида: 0 столовая (сталь с ржавчиной), 1 десертная (латунь), 2 вилы (бронза, дерево).
const FORK_COLORS := [Color(0.74, 0.72, 0.7), Color(0.93, 0.74, 0.36), Color(0.58, 0.42, 0.28)]


static func fork_kind(ci: CanvasItem, c: Vector2, kind: int, s := 1.0, a := 1.0) -> void:
	var col: Color = FORK_COLORS[clampi(kind, 0, 2)]
	col.a = a
	var handle := Color(0.45, 0.26, 0.12, a) if kind == 2 else col
	ci.draw_line(c + Vector2(-12, 10) * s, c + Vector2(4, -4) * s, Color(0.2, 0.13, 0.08, a), 6.0 * s)
	ci.draw_line(c + Vector2(-12, 10) * s, c + Vector2(4, -4) * s, handle, 3.5 * s)
	var n: int = [4, 3, 2][clampi(kind, 0, 2)]
	for i in n:
		var o := Vector2(-4 + i * 8.0 / maxf(n - 1, 1), -4 + i * 8.0 / maxf(n - 1, 1)) * 0.7
		var tip := 12.0 if kind != 2 else 15.0
		ci.draw_line(c + (Vector2(2, -2) + o) * s, c + (Vector2(tip, -tip) + o) * s, col, 2.2 * s)
	if kind == 0:
		ci.draw_circle(c + Vector2(-4, 2) * s, 2.2 * s, Color(0.85, 0.42, 0.16, a))
	elif kind == 2:
		ci.draw_circle(c + Vector2(3, -3) * s, 2.0 * s, Color(0.38, 0.78, 0.62, a))


## Пиктограмма приёма вилки: 0 выпад, 1 залп, 2 вертушка, 3 прыжок-укол.
static func fork_attack(ci: CanvasItem, c: Vector2, atk: int, col: Color, s := 1.0) -> void:
	match atk:
		0:  # стрела выпада
			ci.draw_line(c + Vector2(-10, 0) * s, c + Vector2(8, 0) * s, col, STROKE * s)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(11, 0) * s, c + Vector2(4, -5) * s, c + Vector2(4, 5) * s]), col)
			for i in 2:
				ci.draw_line(c + Vector2(-10 - i * 4, -6 + i * 12) * s, c + Vector2(-4 - i * 4, -6 + i * 12) * s, Color(col, 0.5), 1.5 * s)
		1:  # веер зубцов
			for i in 3:
				var d := Vector2.from_angle(-0.45 + i * 0.45)
				ci.draw_line(c + Vector2(-9, 0) * s + d * 6.0 * s, c + Vector2(-9, 0) * s + d * 20.0 * s, col, 2.2 * s)
			ci.draw_circle(c + Vector2(-9, 0) * s, 3.0 * s, col)
		2:  # вертушка
			ci.draw_arc(c, 9.0 * s, 0.3, PI - 0.3, 12, col, STROKE * s)
			ci.draw_arc(c, 9.0 * s, PI + 0.3, TAU - 0.3, 12, col, STROKE * s)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -4) * s, c + Vector2(-13, 1) * s, c + Vector2(-5, 1) * s]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(9, 4) * s, c + Vector2(13, -1) * s, c + Vector2(5, -1) * s]), col)
		_:  # прыжок и круг на полу
			ci.draw_arc(c + Vector2(0, 7) * s, 10.0 * s, 0, TAU, 16, Color(col, 0.6), 1.8 * s)
			ci.draw_line(c + Vector2(0, -11) * s, c + Vector2(0, 4) * s, col, STROKE * s)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 8) * s, c + Vector2(-5, 1) * s, c + Vector2(5, 1) * s]), col)


## Картотека: карточка-папка.
static func folder(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -7) * s, c + Vector2(-3, -7) * s, c + Vector2(-1, -4) * s,
		c + Vector2(10, -4) * s, c + Vector2(10, 8) * s, c + Vector2(-10, 8) * s]), col)
	ci.draw_line(c + Vector2(-7, 1) * s, c + Vector2(7, 1) * s, Color(0, 0, 0, 0.35), 1.5 * s)
	ci.draw_line(c + Vector2(-7, 4.5) * s, c + Vector2(3, 4.5) * s, Color(0, 0, 0, 0.35), 1.5 * s)


## Календарь с отмеченным днём — ежедневное испытание.
static func calendar(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	ci.draw_rect(Rect2(c + Vector2(-9, -7) * s, Vector2(18, 16) * s), col, false, STROKE * s)
	ci.draw_line(c + Vector2(-9, -2) * s, c + Vector2(9, -2) * s, col, STROKE * s)
	for k in [-5.0, 5.0]:
		ci.draw_line(c + Vector2(k, -10) * s, c + Vector2(k, -5) * s, col, STROKE * s)
	ci.draw_rect(Rect2(c + Vector2(1, 1) * s, Vector2(5, 5) * s), col)
