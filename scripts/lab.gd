extends Node2D
## Кабинет-лаборатория, который виден, когда камера отдаляется в финале. Арена оказывается
## маленьким ящиком на столе учёного-бюрократа: серый костюм, очки, бейдж, планшет с протоколом.
## Всё рисуется кодом в мировых координатах (арена занимает 0..1280 × 0..720).
## Рука со спичкой рисуется отдельным узлом поверх арены.

enum Match { NONE, HELD, LIT, FLYING, GONE }

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


func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI Black", "Arial Black", "Segoe UI", "Arial"])
	font.font_weight = 900
	front = Node2D.new()
	front.z_as_relative = false
	front.z_index = 40
	front.draw.connect(_draw_front)
	add_child(front)
	for i in 40:
		drops.append(Vector2(randf(), randf()))


func _process(delta: float) -> void:
	t += delta
	talk = maxf(talk - delta, 0.0)
	flash = maxf(flash - delta * 1.8, 0.0)
	if walking:
		walk += delta * 7.0
	queue_redraw()
	front.queue_redraw()


func head_pos() -> Vector2:
	return Vector2(sx, HEAD_Y - _bob() - startle * 45.0)


func shoulder() -> Vector2:
	return Vector2(sx - 430, 20 - _bob() - startle * 45.0)


func rest_hand() -> Vector2:
	return Vector2(sx - 560, 700 - _bob())


func _bob() -> float:
	return absf(sin(walk)) * 22.0 if walking else 0.0


## Кончик спички в руке.
func match_tip() -> Vector2:
	return _hand_drawn() + Vector2(-50, -190)


func _hand_drawn() -> Vector2:
	var h := hand
	if tremble:
		h += Vector2(sin(t * 31.0), cos(t * 27.0)) * 6.0
	return h


# ---------------------------------------------------------------- комната

func _draw() -> void:
	_draw_wall()
	_draw_window(Rect2(150, -1000, 980, 560))
	_draw_clock(Vector2(-560, -820))
	_draw_board(Rect2(3330, -950, 800, 500))
	_draw_shelves()
	_draw_lamp()
	_draw_person()
	_draw_table()
	_draw_box_front()
	if flash > 0.0:
		draw_rect(Rect2(-3000, -2500, 9000, 6000), Color(0.85, 0.9, 1, 0.35 * flash))
	if glow > 0.0:
		var fl := 0.8 + 0.2 * sin(t * 17.0) * sin(t * 5.3)
		draw_rect(Rect2(-3000, -2500, 9000, 6000), Color(1, 0.4, 0.1, 0.13 * glow * fl))


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
	var sec := Vector2.from_angle(-PI / 2 + TAU * floorf(t) / 60.0)
	draw_line(c, c + Vector2.from_angle(-PI / 2 + 0.9) * 70.0, LINE, 12.0)
	draw_line(c, c + Vector2.from_angle(-PI / 2 + 4.1) * 105.0, LINE, 8.0)
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
		_draw_mini_bear(jar.get_center() + Vector2(0, 30), 3.4, [Color(0.62, 0.4, 0.22), Color(0.55, 0.33, 0.2),
			Color(0.75, 0.55, 0.35), Color(0.65, 0.45, 0.25)][i])
		draw_rect(jar, Color(0.75, 0.9, 0.95, 0.55), false, 7.0)
		draw_line(jar.position + Vector2(25, 30), jar.position + Vector2(25, 200), Color(1, 1, 1, 0.35), 10.0)
		draw_rect(Rect2(jar.position.x - 8, jar.position.y - 34, jar.size.x + 16, 38), Color(0.35, 0.35, 0.4))
		draw_rect(Rect2(jar.position.x + 45, jar.position.y + 150, 100, 55), Color(0.93, 0.88, 0.75))
		draw_string(font, Vector2(jar.position.x + 52, jar.position.y + 192), "№%d" % (12 + i * 9),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.2, 0.1, 0.05))


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


func _draw_lamp() -> void:
	draw_line(Vector2(640, -2500), Vector2(640, -560), Color(0.1, 0.1, 0.1), 10.0)
	draw_colored_polygon(PackedVector2Array([Vector2(560, -300), Vector2(720, -300), Vector2(1000, 0), Vector2(280, 0)]),
		Color(1, 0.95, 0.6, 0.07))
	draw_colored_polygon(PackedVector2Array([Vector2(600, -560), Vector2(680, -560), Vector2(780, -380), Vector2(500, -380)]),
		Color(0.3, 0.32, 0.35))
	draw_circle(Vector2(640, -370), 45.0, Color(1, 0.97, 0.85))
	draw_circle(Vector2(640, -370), 110.0, Color(1, 0.95, 0.7, 0.12))


# ---------------------------------------------------------------- учёный-бюрократ

func _draw_person() -> void:
	if sx > OUTSIDE_X - 10.0:
		return
	var up := Vector2(0, -_bob() - startle * 45.0)
	var jitter := Vector2(sin(t * 60.0), 0) * 8.0 * startle
	var o := up + jitter
	var skin := SKIN.lerp(Color(1, 0.6, 0.35), glow * 0.2)
	# правая рука (у нас справа) с планшетом
	var sh := Vector2(sx + 420, 20) + o
	var el := Vector2(sx + 560, 440) + o
	var hand_r := Vector2(sx + 430, 700) + o
	for pass_i in 2:
		var col := LINE if pass_i == 0 else SUIT
		var w := 190.0 if pass_i == 0 else 164.0
		draw_line(sh, el, col, w)
		draw_line(el, hand_r, col, w)
		draw_circle(el, w / 2.0, col)
	# туловище: пиджак
	var body := PackedVector2Array([Vector2(sx - 380, -100), Vector2(sx + 380, -100), Vector2(sx + 520, 60),
		Vector2(sx + 580, 900), Vector2(sx - 580, 900), Vector2(sx - 520, 60)])
	for i in body.size():
		body[i] += o
	draw_colored_polygon(_grow_poly(body, 14.0), LINE)
	draw_colored_polygon(body, SUIT)
	var c := Vector2(sx, 0) + o
	draw_colored_polygon(PackedVector2Array([c + Vector2(-150, -100), c + Vector2(150, -100), c + Vector2(0, 360)]),
		Color(0.96, 0.96, 0.97))  # рубашка
	draw_colored_polygon(PackedVector2Array([c + Vector2(-34, -90), c + Vector2(34, -90), c + Vector2(50, 260),
		c + Vector2(0, 330), c + Vector2(-50, 260)]), Color(0.16, 0.2, 0.36))  # галстук
	draw_colored_polygon(PackedVector2Array([c + Vector2(-40, -100), c + Vector2(40, -100), c + Vector2(25, -40),
		c + Vector2(-25, -40)]), Color(0.12, 0.15, 0.28))  # узел
	for s in [-1.0, 1.0]:  # лацканы
		draw_colored_polygon(PackedVector2Array([c + Vector2(s * 150, -100), c + Vector2(s * 240, -60),
			c + Vector2(s * 120, 200), c + Vector2(s * 20, 380)]), SUIT_DARK)
	draw_line(c + Vector2(0, 380), c + Vector2(0, 900), SUIT_DARK, 6.0)
	for y in [520.0, 700.0]:
		draw_circle(c + Vector2(30, y), 16.0, SUIT_DARK)
	# бейдж на шнурке
	draw_line(c + Vector2(-120, -90), c + Vector2(-230, 180), Color(0.2, 0.35, 0.7), 10.0)
	draw_line(c + Vector2(-60, -90), c + Vector2(-150, 180), Color(0.2, 0.35, 0.7), 10.0)
	var badge := Rect2(c + Vector2(-290, 170), Vector2(180, 230))
	draw_rect(badge, Color(0.97, 0.97, 0.97))
	draw_rect(Rect2(badge.position, Vector2(180, 50)), Color(0.2, 0.35, 0.7))
	draw_string(font, badge.position + Vector2(18, 36), "НИИ ЭКСП.", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	draw_rect(Rect2(badge.position + Vector2(20, 68), Vector2(70, 85)), Color(0.7, 0.72, 0.75))
	draw_circle(badge.position + Vector2(55, 100), 20.0, Color(0.9, 0.78, 0.68))
	for k in 3:
		draw_line(badge.position + Vector2(100, 80 + k * 26), badge.position + Vector2(165, 80 + k * 26), Color(0.5, 0.5, 0.55), 6.0)
	draw_line(badge.position + Vector2(20, 190), badge.position + Vector2(160, 190), Color(0.5, 0.5, 0.55), 6.0)
	# планшет с протоколом у правой руки
	var clip := Rect2(Vector2(sx + 250, 480) + o, Vector2(330, 380))
	draw_rect(clip, Color(0.5, 0.35, 0.2))
	draw_rect(clip.grow(-22), Color(0.98, 0.98, 0.95))
	for k in 6:
		draw_line(clip.position + Vector2(50, 90 + k * 42), clip.position + Vector2(280 - (k % 3) * 40, 90 + k * 42),
			Color(0.55, 0.55, 0.6), 6.0)
	draw_rect(Rect2(clip.position + Vector2(110, -20), Vector2(110, 50)), Color(0.72, 0.74, 0.78))
	draw_circle(hand_r, 78.0, LINE)
	draw_circle(hand_r, 68.0, skin)
	# шея и голова
	var h := Vector2(sx, HEAD_Y) + o
	draw_rect(Rect2(c + Vector2(-95, -200), Vector2(190, 110)), skin.darkened(0.1))
	for s in [-1.0, 1.0]:  # уши
		draw_circle(h + Vector2(s * 245, 20), 60.0, LINE)
		draw_circle(h + Vector2(s * 245, 20), 50.0, skin)
	draw_circle(h, 262.0, LINE)
	draw_circle(h, 250.0, skin)
	# аккуратная стрижка с пробором
	var hair := PackedVector2Array()
	for i in 19:
		var a := PI + PI * i / 18.0
		hair.append(h + Vector2.from_angle(a) * 256.0)
	hair.append(h + Vector2(236, -40))
	hair.append(h + Vector2(120, -165))
	hair.append(h + Vector2(-60, -175))
	hair.append(h + Vector2(-210, -120))
	hair.append(h + Vector2(-236, -40))
	draw_colored_polygon(hair, HAIR)
	draw_line(h + Vector2(-70, -250), h + Vector2(-60, -175), skin.darkened(0.15), 8.0)  # пробор
	for s in [-1.0, 1.0]:  # седина на висках
		draw_circle(h + Vector2(s * 225, -30), 26.0, Color(0.62, 0.62, 0.62))
	# брови: ровные, а при испуге — вверх
	for s in [-1.0, 1.0]:
		var by := -85.0 - startle * 45.0
		draw_line(h + Vector2(s * 55, by), h + Vector2(s * 165, by - 6.0 * startle), HAIR, 22.0)
	# глаза за очками: скучающие, полуприкрытые; при испуге — круглые
	for s in [-1.0, 1.0]:
		var e := h + Vector2(s * 105, -20)
		var r := lerpf(34.0, 52.0, startle)
		draw_circle(e, r, Color.WHITE)
		var dir := (look - e).normalized()
		draw_circle(e + dir * r * 0.35, lerpf(17.0, 10.0, startle), Color(0.2, 0.15, 0.1))
		if startle < 0.5:  # веко
			draw_rect(Rect2(e + Vector2(-r - 2, -r - 2), Vector2(r * 2 + 4, r * 0.95)), skin)
			draw_line(e + Vector2(-r, -r * 0.05), e + Vector2(r, -r * 0.05), LINE, 6.0)
		# прямоугольная оправа
		var frame := Rect2(e + Vector2(-80, -55), Vector2(160, 105))
		draw_rect(frame, Color(0.8, 0.9, 1.0, 0.12))
		draw_rect(frame, LINE, false, 11.0)
	draw_line(h + Vector2(-25, -30), h + Vector2(25, -30), LINE, 10.0)
	for s in [-1.0, 1.0]:
		draw_line(h + Vector2(s * 185, -30), h + Vector2(s * 245, -10), LINE, 9.0)
	# нос
	draw_line(h + Vector2(0, 5), h + Vector2(-18, 85), skin.darkened(0.25), 9.0)
	draw_line(h + Vector2(-18, 85), h + Vector2(12, 92), skin.darkened(0.25), 9.0)
	# рот: ровная линия; говорит — чуть приоткрывается; испуг — «о»
	var m := h + Vector2(0, 150)
	if startle > 0.3:
		draw_circle(m + Vector2(0, 10), 34.0 * startle, LINE)
		draw_circle(m + Vector2(0, 10), 24.0 * startle, Color(0.45, 0.12, 0.12))
	elif talk > 0.0:
		var open := 8.0 + absf(sin(t * 12.0)) * 22.0
		draw_rect(Rect2(m + Vector2(-60, -open / 2.0), Vector2(120, open)), Color(0.35, 0.1, 0.1))
		draw_rect(Rect2(m + Vector2(-60, -open / 2.0), Vector2(120, open)), LINE, false, 6.0)
	else:
		draw_line(m + Vector2(-65, 0), m + Vector2(65, 0), LINE, 10.0)


func _draw_table() -> void:
	draw_rect(Rect2(-1300, TABLE_Y, 5800, 100), Color(0.42, 0.32, 0.24))
	draw_rect(Rect2(-1300, TABLE_Y, 5800, 14), Color(0.55, 0.43, 0.33))
	draw_rect(Rect2(-1300, TABLE_Y + 100, 5800, 80), Color(0.3, 0.23, 0.17))
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


func _draw_box_front() -> void:
	draw_rect(Rect2(-10, 720, 1300, TABLE_Y - 720), Color(0.45, 0.27, 0.13))
	for y in [760.0, 800.0]:
		draw_line(Vector2(-10, y), Vector2(1290, y), Color(0.35, 0.2, 0.1), 5.0)
	var plate := Rect2(400, 738, 480, 84)
	draw_rect(plate, Color(0.9, 0.9, 0.88))
	draw_rect(plate, Color(0.5, 0.5, 0.5), false, 6.0)
	draw_string(font, Vector2(plate.position.x, plate.position.y + 54), "ОБРАЗЕЦ №47  •  ИНВ. 0047-Б",
		HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, 26, Color(0.2, 0.2, 0.25))


# ---------------------------------------------------------------- рука со спичкой (поверх арены)

func _draw_front() -> void:
	if sx > OUTSIDE_X - 10.0:
		return
	var suit := SUIT
	var skin := SKIN
	if glow > 0.0:
		suit = suit.lerp(Color(1, 0.6, 0.3), glow * 0.2)
		skin = skin.lerp(Color(1, 0.55, 0.3), glow * 0.25)
	var sh := shoulder()
	var hd := _hand_drawn()
	var elbow := (sh + hd) / 2.0 + Vector2(140, 220)
	var wrist := hd + (elbow - hd).normalized() * 70.0
	for pass_i in 2:  # сначала контур, потом заливка
		var col := LINE if pass_i == 0 else suit
		var w := 180.0 if pass_i == 0 else 154.0
		front.draw_line(sh, elbow, col, w)
		front.draw_line(elbow, wrist, col, w)
		front.draw_circle(sh, w / 2.0, col)
		front.draw_circle(elbow, w / 2.0, col)
	front.draw_line(wrist, hd + (elbow - hd).normalized() * 40.0, Color(0.96, 0.96, 0.97), 120.0)  # манжета
	if match_state == Match.HELD or match_state == Match.LIT:
		_draw_match(hd + Vector2(-10, -30), match_tip(), match_state == Match.LIT)
	front.draw_circle(hd, 80.0, LINE)
	front.draw_circle(hd, 70.0, skin)
	var spread := 0.45 + startle * 0.35  # от испуга пальцы разжимаются
	for k in 4:
		var f := hd + Vector2.from_angle(-2.4 + k * spread) * (66.0 + startle * 18.0)
		front.draw_circle(f, 28.0, LINE)
		front.draw_circle(f, 22.0, skin)
	if match_state == Match.FLYING:
		var dir := Vector2.from_angle(match_rot)
		_draw_match(match_pos - dir * 190.0, match_pos, true)


func _draw_match(from: Vector2, tip: Vector2, lit: bool) -> void:
	front.draw_line(from, tip, Color(0.85, 0.7, 0.45), 16.0)
	front.draw_circle(tip, 20.0, Color(0.7, 0.1, 0.1))
	if not lit:
		return
	front.draw_circle(tip, 150.0, Color(1, 0.6, 0.2, 0.12))
	var fl := 1.0 + 0.15 * sin(t * 25.0)
	for layer in [[34.0, 110.0, Color(1, 0.35, 0.05)], [22.0, 75.0, Color(1, 0.7, 0.15)], [12.0, 40.0, Color(1, 0.95, 0.6)]]:
		var w: float = layer[0]
		var h: float = layer[1] * fl
		var pts := PackedVector2Array()
		for i in 9:
			var a := deg_to_rad(-30.0 + 240.0 * i / 8.0)
			pts.append(tip + Vector2(cos(a), sin(a)) * w)
		pts.append(tip + Vector2(sin(t * 9.0) * 8.0, -h))
		front.draw_colored_polygon(pts, layer[2])


## Грубое «раздувание» выпуклого многоугольника от центра — для контура.
func _grow_poly(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (p - c).normalized() * by)
	return out
