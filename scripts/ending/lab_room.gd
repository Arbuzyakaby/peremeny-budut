extends Node2D
## Комната-лаборатория финала: стена, окно с дождём, часы, доска, полки с образцами, лампа,
## стол и передняя стенка ящика. Состояние сцены (учёный, рука, свет) объявлено здесь же,
## а учёного и руку рисует наследник lab.gd.
## Во время пожара (Design.panic) лампа мигает, а стрелки часов дёргаются; с «меньше анимации» — нет.

enum Match { NONE, HELD, LIT, FLYING, GONE }
enum Hold { MATCH, EXTINGUISHER }

const Tex = preload("res://scripts/gfx/tex.gd")
const Design = preload("res://scripts/ui/design.gd")
const Settings = preload("res://scripts/core/settings.gd")

const STAND_X := 2550.0   # где учёный останавливается у стола
const OUTSIDE_X := 5600.0 # откуда он входит
const HEAD_Y := -400.0
const TABLE_Y := 840.0
const SUIT := Color(0.33, 0.35, 0.4)
const SUIT_DARK := Color(0.22, 0.23, 0.27)
const LINE := Color(0.14, 0.14, 0.17)
const SKIN := Color(0.93, 0.8, 0.7)
const HAIR := Color(0.3, 0.28, 0.27)

var t := 0.0
var sx := OUTSIDE_X
var walk := 0.0      # фаза походки (растёт, пока учёный идёт)
var walking := false
var startle := 0.0   # 0..1 — испуг от грома
var tremble := false # рука со спичкой подрагивает (ждёт решения)
var hand := Vector2(OUTSIDE_X - 600, 700)
var match_state := Match.NONE
var match_pos := Vector2.ZERO
var match_rot := 0.0
var look := Vector2(640, 360)
var talk := 0.0
var glow := 0.0
var flash := 0.0
var font: SystemFont
var front: Node2D
var drops: Array[Vector2] = []  # капли дождя в окне
var holding := Hold.MATCH
var writing := false    # пишет в протоколе
var stamped := 0.0      # 0..1 — на столе лежит протокол со штампом
var lights := 1.0       # лампа: 1 — горит, 0 — выключена
var spraying := false


func _draw_wall() -> void:
	# казённая покраска: сверху светлая, снизу панели
	draw_rect(Rect2(-3000, -2500, 9000, 4250), Color(0.55, 0.6, 0.55))
	draw_rect(Rect2(-3000, 200, 9000, 1550), Color(0.35, 0.42, 0.38))
	draw_rect(Rect2(-3000, 185, 9000, 30), Color(0.28, 0.32, 0.3))
	for x in range(-3000, 6000, 260):
		draw_line(Vector2(x, 215), Vector2(x, 1750), Color(0.3, 0.37, 0.33), 6.0)
	draw_rect(Rect2(-3000, 1750, 9000, 1500), Color(0.25, 0.22, 0.2))  # пол-линолеум
	for x in range(-3000, 6000, 300):
		draw_line(Vector2(x, 1750), Vector2(x, 3200), Color(0.2, 0.18, 0.16), 5.0)
	for x in range(-3000, 6000, 600):  # стыки плиток линолеума
		draw_line(Vector2(x + 150, 1750), Vector2(x - 250, 3200), Color(0.28, 0.25, 0.22), 3.0)
	# пятно света лампы на стене и холодный свет из окна
	Tex.blob(self, Vector2(640, -200), Vector2(2200, 1500), Color(1, 0.9, 0.6, 0.22 * lights * _lamp_flicker()))
	Tex.blob(self, Vector2(640, -500), Vector2(1300, 900), Color(0.6, 0.7, 1.0, 0.1 + 0.25 * flash))


func _draw_window(r: Rect2) -> void:
	var sky := Color(0.1, 0.12, 0.2).lerp(Color(0.85, 0.88, 1.0), flash * 0.9)
	draw_rect(r.grow(36), Color(0.82, 0.82, 0.8))
	draw_rect(r, sky)
	for d in drops:  # дождь
		var p := r.position + Vector2(d.x * r.size.x, fmod(d.y * r.size.y + t * 900.0, r.size.y))
		var e := p + Vector2(-20, 60)
		if e.y < r.end.y:
			draw_line(p, e, Color(0.6, 0.7, 0.95, 0.35), 5.0)
	if flash > 0.5:  # молния
		var pts := PackedVector2Array([r.position + Vector2(r.size.x * 0.62, 0)])
		for i in 6:
			pts.append(pts[i] + Vector2(randf_range(-70, 70), r.size.y / 6.0))
		draw_polyline(pts, Color(1, 1, 1, flash), 12.0)
	draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), Color(0.82, 0.82, 0.8), 26.0)
	draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color(0.82, 0.82, 0.8), 26.0)
	# жалюзи, поднятые наверх
	draw_rect(Rect2(r.position.x - 20, r.position.y - 20, r.size.x + 40, 70), Color(0.9, 0.9, 0.86))
	for k in 4:
		draw_line(Vector2(r.position.x - 20, r.position.y - 5 + k * 16), Vector2(r.end.x + 20, r.position.y - 5 + k * 16),
			Color(0.7, 0.7, 0.68), 3.0)


func _draw_clock(c: Vector2) -> void:
	draw_circle(c, 150.0, LINE)
	draw_circle(c, 136.0, Color(0.97, 0.97, 0.94))
	for i in 12:
		var d := Vector2.from_angle(TAU * i / 12.0)
		draw_line(c + d * 110.0, c + d * 128.0, LINE, 8.0 if i % 3 == 0 else 4.0)
	var tw := _panic_twitch()  # в панике стрелки дёргаются, как у прибора на пределе
	var sec := Vector2.from_angle(-PI / 2 + TAU * floorf(t) / 60.0 + tw * 0.35)
	draw_line(c, c + Vector2.from_angle(-PI / 2 + 0.9 + tw * 0.06) * 70.0, LINE, 12.0)
	draw_line(c, c + Vector2.from_angle(-PI / 2 + 4.1 - tw * 0.1) * 105.0, LINE, 8.0)
	draw_line(c, c + sec * 115.0, Color(0.8, 0.15, 0.1), 4.0)
	draw_circle(c, 12.0, LINE)


func _draw_board(r: Rect2) -> void:
	# доска объявлений с приказами
	draw_rect(r.grow(24), Color(0.45, 0.32, 0.2))
	draw_rect(r, Color(0.72, 0.58, 0.4))
	var paper := Rect2(r.position + Vector2(40, 40), Vector2(430, 420))
	draw_rect(paper, Color(0.97, 0.96, 0.92))
	draw_circle(paper.position + Vector2(paper.size.x / 2, 18), 12.0, Color(0.85, 0.2, 0.2))
	var ink := Color(0.15, 0.15, 0.2)
	draw_string(font, paper.position + Vector2(30, 80), "ПРИКАЗ №47", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, ink)
	draw_string(font, paper.position + Vector2(30, 135), "Об утилизации образца", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	for k in 5:
		draw_line(paper.position + Vector2(30, 180 + k * 36), paper.position + Vector2(paper.size.x - 40 - (k % 2) * 90, 180 + k * 36),
			Color(0.6, 0.6, 0.65), 6.0)
	# печать «УТВЕРЖДЕНО»
	draw_set_transform(paper.position + Vector2(250, 370), -0.2, Vector2.ONE)
	draw_rect(Rect2(-150, -40, 300, 80), Color(0.8, 0.1, 0.1, 0.8), false, 8.0)
	draw_string(font, Vector2(-135, 18), "УТВЕРЖДЕНО", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(0.8, 0.1, 0.1, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# график рядом
	var g := Rect2(r.position + Vector2(510, 60), Vector2(240, 200))
	draw_rect(g, Color(0.97, 0.96, 0.92))
	draw_circle(g.position + Vector2(g.size.x / 2, 14), 10.0, Color(0.2, 0.4, 0.85))
	draw_polyline(PackedVector2Array([g.position + Vector2(25, 170), g.position + Vector2(80, 130),
		g.position + Vector2(130, 145), g.position + Vector2(210, 50)]), Color(0.2, 0.5, 0.25), 8.0)
	var memo := Rect2(r.position + Vector2(530, 300), Vector2(200, 150))
	draw_rect(memo, Color(1, 0.93, 0.45))
	for k in 3:
		draw_line(memo.position + Vector2(20, 40 + k * 35), memo.position + Vector2(170, 40 + k * 35), Color(0.5, 0.45, 0.2), 5.0)


func _draw_shelves() -> void:
	for y in [-650.0, -120.0]:
		draw_rect(Rect2(-1150, y, 1150, 34), Color(0.5, 0.5, 0.52))
		draw_rect(Rect2(-1150, y + 34, 1150, 10), Color(0.35, 0.35, 0.37))
	# папки с отчётами
	var colors := [Color(0.2, 0.35, 0.65), Color(0.6, 0.15, 0.15), Color(0.2, 0.5, 0.3), Color(0.55, 0.5, 0.2)]
	for i in 12:
		var x := -1110.0 + i * 88.0
		var h := 260.0 - (i % 3) * 20.0
		var col: Color = colors[i % colors.size()]
		draw_rect(Rect2(x, -650 - h, 80, h), col)
		draw_rect(Rect2(x + 14, -650 - h + 40, 52, 70), Color(0.95, 0.94, 0.9))
		draw_circle(Vector2(x + 40, -650 - 50), 14.0, col.darkened(0.4))
	# архив образцов: банки с плюшевыми медведями прошлых экспериментов
	for i in 4:
		var base := Vector2(-1080 + i * 270, -120)
		var jar := Rect2(base.x, base.y - 250, 190, 250)
		draw_rect(jar, Color(0.55, 0.75, 0.8, 0.18))
		match i:
			1:
				_draw_mini_fork(jar.get_center() + Vector2(0, 20))
			2:
				_draw_mini_pill(jar.get_center() + Vector2(0, 40))
			_:
				_draw_mini_bear(jar.get_center() + Vector2(0, 30), 3.4, [Color(0.62, 0.4, 0.22), Color(0.55, 0.33, 0.2),
					Color(0.75, 0.55, 0.35), Color(0.65, 0.45, 0.25)][i])
		draw_rect(jar, Color(0.75, 0.9, 0.95, 0.55), false, 7.0)
		draw_line(jar.position + Vector2(25, 30), jar.position + Vector2(25, 200), Color(1, 1, 1, 0.35), 10.0)
		draw_rect(Rect2(jar.position.x - 8, jar.position.y - 34, jar.size.x + 16, 38), Color(0.35, 0.35, 0.4))
		draw_rect(Rect2(jar.position.x + 45, jar.position.y + 150, 100, 55), Color(0.93, 0.88, 0.75))
		draw_string(font, Vector2(jar.position.x + 52, jar.position.y + 192), "№%d" % [21, 44, 45, 46][i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.2, 0.1, 0.05))


func _draw_mini_fork(c: Vector2) -> void:
	var steel := Color(0.55, 0.45, 0.4)
	draw_line(c + Vector2(0, 90), c + Vector2(0, -10), Color(0.2, 0.15, 0.12), 26.0)
	draw_line(c + Vector2(0, 90), c + Vector2(0, -10), steel, 18.0)
	for k in 4:
		var x := -33.0 + k * 22.0
		draw_line(c + Vector2(x, -10), c + Vector2(x, -95), Color(0.2, 0.15, 0.12), 13.0)
		draw_line(c + Vector2(x, -10), c + Vector2(x, -95), steel, 8.0)
	draw_line(c + Vector2(-36, -10), c + Vector2(36, -10), steel, 16.0)
	for k in 5:  # пятна ржавчины
		draw_circle(c + Vector2(-12 + k * 6, -40 + k * 25), 7.0, Color(0.55, 0.25, 0.1, 0.8))


func _draw_mini_pill(c: Vector2) -> void:
	draw_circle(c + Vector2(-38, 0), 38.0, Color(0.15, 0.1, 0.12))
	draw_circle(c + Vector2(38, 0), 38.0, Color(0.15, 0.1, 0.12))
	draw_rect(Rect2(c + Vector2(-38, -38), Vector2(76, 76)), Color(0.15, 0.1, 0.12))
	draw_circle(c + Vector2(-38, 0), 32.0, Color(0.92, 0.2, 0.22))
	draw_rect(Rect2(c + Vector2(-38, -32), Vector2(38, 64)), Color(0.92, 0.2, 0.22))
	draw_circle(c + Vector2(38, 0), 32.0, Color(0.97, 0.95, 0.9))
	draw_rect(Rect2(c + Vector2(0, -32), Vector2(38, 64)), Color(0.97, 0.95, 0.9))
	for k in [-1.0, 1.0]:  # глаза-крестики
		var e: Vector2 = c + Vector2(-38 + k * 12, -6)
		draw_line(e - Vector2(7, 7), e + Vector2(7, 7), Color.BLACK, 5.0)
		draw_line(e - Vector2(7, -7), e + Vector2(7, -7), Color.BLACK, 5.0)


func _draw_mini_bear(c: Vector2, s: float, fur: Color) -> void:
	for k in [-1.0, 1.0]:
		draw_circle(c + Vector2(k * 10, -16) * s, 6.0 * s, fur.darkened(0.3))
	draw_circle(c + Vector2(0, 8) * s, 10.0 * s, fur)
	draw_circle(c + Vector2(0, -7) * s, 11.5 * s, fur)
	draw_circle(c + Vector2(0, -3) * s, 5.0 * s, fur.lightened(0.35))
	for k in [-1.0, 1.0]:  # глаза-крестики
		var e := c + Vector2(k * 4.5, -10) * s
		draw_line(e - Vector2(6, 6), e + Vector2(6, 6), Color.BLACK, 5.0)
		draw_line(e - Vector2(6, -6), e + Vector2(6, -6), Color.BLACK, 5.0)


## Рывок стрелки −1..1 (0 — спокойно): резкие скачки, чаще и сильнее с паникой.
func _panic_twitch() -> float:
	var p := Design.panic
	if p < 0.05 or Settings.flag("reduced_motion"):
		return 0.0
	var k := floorf(t * lerpf(4.0, 14.0, p))
	return sin(k * 91.7) * p


## Лампа на плохом контакте: при панике мигает (чем сильнее огонь, тем чаще).
func _lamp_flicker() -> float:
	var p := Design.panic
	if p < 0.05 or Settings.flag("reduced_motion"):
		return 1.0
	return 1.0 - 0.6 * p * float(sin(t * lerpf(5.0, 19.0, p) * TAU) * sin(t * 2.3) > 0.5 - 0.3 * p)


func _draw_lamp() -> void:
	var lit := lights * _lamp_flicker()
	draw_line(Vector2(640, -2500), Vector2(640, -560), Color(0.1, 0.1, 0.1), 10.0)
	draw_colored_polygon(PackedVector2Array([Vector2(560, -300), Vector2(720, -300), Vector2(1000, 0), Vector2(280, 0)]),
		Color(1, 0.95, 0.6, 0.07 * lit))
	draw_colored_polygon(PackedVector2Array([Vector2(600, -560), Vector2(680, -560), Vector2(780, -380), Vector2(500, -380)]),
		Color(0.3, 0.32, 0.35))
	draw_circle(Vector2(640, -370), 45.0, Color(1, 0.97, 0.85).lerp(Color(0.35, 0.33, 0.3), 1.0 - lit))
	Tex.blob(self, Vector2(640, -370), Vector2.ONE * 220.0, Color(1, 0.95, 0.7, 0.35 * lit))


func _draw_table() -> void:
	draw_rect(Rect2(-1300, TABLE_Y, 5800, 100), Color(0.42, 0.32, 0.24))
	draw_rect(Rect2(-1300, TABLE_Y, 5800, 14), Color(0.55, 0.43, 0.33))
	draw_rect(Rect2(-1300, TABLE_Y + 100, 5800, 80), Color(0.3, 0.23, 0.17))
	for k in 5:  # волокна столешницы
		draw_line(Vector2(-1300, TABLE_Y + 22 + k * 16), Vector2(4500, TABLE_Y + 26 + k * 16 + sin(k) * 6.0),
			Color(0.36, 0.27, 0.2, 0.7), 3.0)
	Tex.blob(self, Vector2(1600, TABLE_Y + 260), Vector2(3600, 120), Color(0, 0, 0, 0.35))  # тень под столом
	for x in [-1150.0, 4250.0]:
		draw_rect(Rect2(x - 55, TABLE_Y + 180, 110, 1600), Color(0.3, 0.23, 0.17))
	# стопки бланков и печать
	for k in 6:
		draw_rect(Rect2(-1000 + k * 5, TABLE_Y - 14 - k * 14, 520, 14),
			Color(0.95, 0.93, 0.88) if k % 2 == 0 else Color(0.88, 0.86, 0.8))
	draw_rect(Rect2(3700, TABLE_Y - 60, 170, 60), Color(0.15, 0.15, 0.18))
	draw_rect(Rect2(3755, TABLE_Y - 190, 60, 130), Color(0.55, 0.35, 0.2))
	draw_circle(Vector2(3785, TABLE_Y - 200), 45.0, Color(0.55, 0.35, 0.2))
	draw_rect(Rect2(3920, TABLE_Y - 30, 200, 30), Color(0.6, 0.15, 0.15))  # штемпельная подушка
	if stamped > 0.0:  # протокол со штампом рядом с ящиком
		draw_set_transform(Vector2(1770, TABLE_Y - 300), -0.12, Vector2.ONE)
		var sheet := Rect2(-330, -260, 660, 440)
		draw_rect(Rect2(sheet.position + Vector2(14, 18), sheet.size), Color(0, 0, 0, 0.25))
		draw_rect(sheet, Color(0.98, 0.97, 0.93))
		draw_string(font, Vector2(-290, -190), "ПРОТОКОЛ №47", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(0.15, 0.15, 0.2))
		for k in 5:
			draw_line(Vector2(-290, -130 + k * 40), Vector2(260 - (k % 2) * 110, -130 + k * 40), Color(0.6, 0.6, 0.65), 7.0)
		var red := Color(0.8, 0.08, 0.08, 0.85 * minf(stamped * 3.0, 1.0))
		draw_set_transform(Vector2(1770, TABLE_Y - 250), -0.3, Vector2.ONE * (1.0 + (1.0 - stamped) * 0.8))
		draw_rect(Rect2(-280, -55, 560, 110), red, false, 12.0)
		draw_string(font, Vector2(-262, 26), "УТИЛИЗИРОВАНО", HORIZONTAL_ALIGNMENT_LEFT, -1, 66, red)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_box_front() -> void:
	draw_rect(Rect2(-10, 720, 1300, TABLE_Y - 720), Color(0.45, 0.27, 0.13))
	for y in [760.0, 800.0]:
		draw_line(Vector2(-10, y), Vector2(1290, y), Color(0.35, 0.2, 0.1), 5.0)
	var plate := Rect2(400, 738, 480, 84)
	draw_rect(plate, Color(0.9, 0.9, 0.88))
	draw_rect(plate, Color(0.5, 0.5, 0.5), false, 6.0)
	draw_string(font, Vector2(plate.position.x, plate.position.y + 54), "ОБРАЗЕЦ №47  •  ИНВ. 0047-Б",
		HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, 26, Color(0.2, 0.2, 0.25))


func _grow_poly(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (p - c).normalized() * by)
	return out
