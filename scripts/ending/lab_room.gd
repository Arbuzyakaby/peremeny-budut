extends Node2D
## Комната-лаборатория финала (v8.0: переработана целиком). Всё рисуется кодом в мировых координатах:
## арена — ящик на лабораторном столе (0..1280 × 0..720), камера отдаляется и видит комнату.
## Слева направо: шкаф с образцами прошлых экспериментов (банки в формалине), часы, окно с дождём,
## меловая доска с итогами забега (зарубки по медведям, вилкам и таблеткам — tally), табло
## «ИДЁТ ЭКСПЕРИМЕНТ», труба с манометром, пожарный шкаф (огнетушитель исчезает, когда учёный его взял),
## доска приказов. На столе — колбы с реактивами, микроскоп, монитор наблюдения, бланки и печать.
## Над ящиком — зелёная эмалевая лампа, в её луче пляшут пылинки.
## Состояние сцены (учёный, рука, свет) объявлено здесь же, учёного и руку рисует наследник lab.gd.
## Во время пожара (Design.panic) лампа и табло мигают, стрелки часов и манометра дёргаются;
## с «меньше анимации» — нет. Когда лампа гаснет, светятся только монитор и луна в окне.

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
const COAT := Color(0.93, 0.94, 0.92)       # лабораторный халат
const COAT_SHADE := Color(0.78, 0.8, 0.8)
const LINE := Color(0.14, 0.14, 0.17)
const SKIN := Color(0.93, 0.8, 0.7)
const HAIR := Color(0.3, 0.28, 0.27)
const CHALK := Color(0.93, 0.95, 0.9, 0.85)
const TILE := Color(0.78, 0.84, 0.8)
const PAINT := Color(0.52, 0.6, 0.57)
## Раскладка стены.
const WINDOW := Rect2(150, -1000, 980, 560)
const CHALKBOARD := Rect2(1330, -1080, 1560, 660)
const SIGN := Rect2(1450, -330, 480, 112)
const BOARD := Rect2(3330, -950, 800, 500)
const CABINET := Rect2(-1180, -1150, 1210, 1100)
const FIRE_BOX := Rect2(3400, -330, 300, 460)
const PIPE_X := 3200.0
const MONITOR := Rect2(3130, 430, 470, 380)

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
var motes: Array[Vector3] = []  # пылинки в луче лампы: x, y (0..1), фаза
var holding := Hold.MATCH
var writing := false    # пишет в протоколе
var stamped := 0.0      # 0..1 — на столе лежит протокол со штампом
var lights := 1.0       # лампа: 1 — горит, 0 — выключена
var spraying := false
var took_extinguisher := false  # шкаф пуст: огнетушитель в руке или уже использован
## Итоги забега мелом на доске: съедено медведей, сломано вилок, съедено таблеток.
var tally: Array[int] = [0, 0, 0]
## Протокол забега — строки мелом справа на доске (ending.gd → board_notes).
var notes := PackedStringArray()


func _draw_wall() -> void:
	# верх — казённая краска, низ — кафель с затиркой до уровня стола
	draw_rect(Rect2(-3000, -2500, 9000, 2700), PAINT)
	draw_rect(Rect2(-3000, 200, 9000, 1550), TILE)
	for x in range(-3000, 6000, 150):
		draw_line(Vector2(x, 200), Vector2(x, 1750), Color(0.62, 0.68, 0.65), 5.0)
	for y in range(200, 1750, 150):
		draw_line(Vector2(-3000, y), Vector2(6000, y), Color(0.62, 0.68, 0.65), 5.0)
	draw_rect(Rect2(-3000, 176, 9000, 36), Color(0.3, 0.36, 0.34))  # бордюрная плитка
	draw_rect(Rect2(-3000, 1750, 9000, 1500), Color(0.25, 0.22, 0.2))  # пол: линолеум «шахматкой»
	for x in range(-3000, 6000, 300):
		for y in range(1750, 3250, 300):
			if (x / 300 + y / 300) % 2 == 0:
				draw_rect(Rect2(x, y, 300, 300), Color(0.29, 0.26, 0.23))
	# вентиляционная решётка
	var vent := Rect2(-2300, -1300, 420, 260)
	draw_rect(vent.grow(14), Color(0.4, 0.44, 0.43))
	draw_rect(vent, Color(0.2, 0.22, 0.22))
	for k in 8:
		draw_line(vent.position + Vector2(10, 18 + k * 30), vent.position + Vector2(vent.size.x - 10, 18 + k * 30),
			Color(0.55, 0.6, 0.58), 10.0)
	# пятно света лампы на стене и холодный свет из окна
	Tex.blob(self, Vector2(640, -200), Vector2(2200, 1500), Color(1, 0.9, 0.6, 0.22 * lights * _lamp_flicker()))
	Tex.blob(self, Vector2(640, -600), Vector2(1400, 1000), Color(0.6, 0.7, 1.0, 0.12 + 0.25 * flash))


func _draw_window(r: Rect2) -> void:
	var sky := Color(0.08, 0.1, 0.18).lerp(Color(0.85, 0.88, 1.0), flash * 0.9)
	draw_rect(r.grow(46), Color(0.86, 0.86, 0.84))
	draw_rect(r.grow(46), Color(0.6, 0.6, 0.58), false, 8.0)
	draw_rect(r, sky)
	# луна за облаками и силуэты крыш напротив
	Tex.blob(self, r.position + Vector2(760, 150), Vector2(140, 140), Color(0.9, 0.92, 1.0, 0.6))
	draw_circle(r.position + Vector2(760, 150), 44.0, Color(0.92, 0.94, 1.0, 0.9))
	var roofs := PackedVector2Array([r.position + Vector2(0, r.size.y)])
	for i in 9:
		var x := i * r.size.x / 8.0
		roofs.append(r.position + Vector2(x, r.size.y - 110 - (i % 3) * 55 - (40 if i == 5 else 0)))
	roofs.append(r.end)
	draw_colored_polygon(roofs, Color(0.05, 0.06, 0.1))
	for i in 6:  # окна домов: пара горит
		var w := r.position + Vector2(60 + i * 150, r.size.y - 70)
		draw_rect(Rect2(w, Vector2(30, 34)), Color(1, 0.85, 0.45, 0.8) if i % 3 == 1 else Color(0.12, 0.13, 0.2))
	for d in drops:  # дождь и потёки на стекле
		var p := r.position + Vector2(d.x * r.size.x, fmod(d.y * r.size.y + t * 900.0, r.size.y))
		var e := p + Vector2(-20, 60)
		if e.y < r.end.y:
			draw_line(p, e, Color(0.6, 0.7, 0.95, 0.35), 5.0)
	for i in 5:
		var sx0 := r.position.x + 90.0 + i * 190.0
		var len := fmod(t * 40.0 + i * 97.0, r.size.y)
		draw_line(Vector2(sx0, r.position.y), Vector2(sx0 + sin(i + t) * 6.0, r.position.y + len), Color(0.75, 0.82, 1.0, 0.25), 6.0)
	if flash > 0.5:  # молния
		var pts := PackedVector2Array([r.position + Vector2(r.size.x * 0.62, 0)])
		for i in 6:
			pts.append(pts[i] + Vector2(randf_range(-70, 70), r.size.y / 6.0))
		draw_polyline(pts, Color(1, 1, 1, flash), 12.0)
	draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), Color(0.86, 0.86, 0.84), 26.0)
	draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color(0.86, 0.86, 0.84), 26.0)
	draw_line(r.position + Vector2(30, 30), r.position + Vector2(220, 220), Color(1, 1, 1, 0.08), 40.0)  # блик стекла
	# жалюзи, поднятые наверх
	draw_rect(Rect2(r.position.x - 20, r.position.y - 20, r.size.x + 40, 70), Color(0.9, 0.9, 0.86))
	for k in 4:
		draw_line(Vector2(r.position.x - 20, r.position.y - 5 + k * 16), Vector2(r.end.x + 20, r.position.y - 5 + k * 16),
			Color(0.7, 0.7, 0.68), 3.0)
	# подоконник с кактусом в горшке
	draw_rect(Rect2(r.position.x - 70, r.end.y + 46, r.size.x + 140, 44), Color(0.9, 0.9, 0.88))
	draw_rect(Rect2(r.position.x - 70, r.end.y + 86, r.size.x + 140, 12), Color(0.7, 0.7, 0.68))
	var pot := Vector2(r.end.x - 120, r.end.y + 46)
	draw_colored_polygon(PackedVector2Array([pot + Vector2(-60, -110), pot + Vector2(60, -110), pot + Vector2(45, 0),
		pot + Vector2(-45, 0)]), Color(0.72, 0.36, 0.2))
	draw_rect(Rect2(pot + Vector2(-68, -126), Vector2(136, 26)), Color(0.62, 0.3, 0.16))
	draw_rect(Rect2(pot + Vector2(-26, -300), Vector2(52, 180)), Color(0.3, 0.55, 0.3))
	draw_circle(pot + Vector2(0, -300), 26.0, Color(0.3, 0.55, 0.3))
	draw_rect(Rect2(pot + Vector2(-80, -230), Vector2(56, 26)), Color(0.3, 0.55, 0.3))
	draw_rect(Rect2(pot + Vector2(-80, -290), Vector2(26, 70)), Color(0.3, 0.55, 0.3))
	for k in 6:  # колючки
		draw_line(pot + Vector2(-26 + (k % 2) * 52, -150 - k * 25), pot + Vector2(-40 + (k % 2) * 80, -156 - k * 25),
			Color(0.95, 0.95, 0.85), 3.0)


func _draw_clock(c: Vector2) -> void:
	draw_circle(c + Vector2(8, 12), 150.0, Color(0, 0, 0, 0.2))
	draw_circle(c, 150.0, LINE)
	draw_circle(c, 136.0, Color(0.97, 0.97, 0.94))
	for i in 12:
		var d := Vector2.from_angle(TAU * i / 12.0)
		draw_line(c + d * 110.0, c + d * 128.0, LINE, 8.0 if i % 3 == 0 else 4.0)
	draw_string(font, c + Vector2(-44, 70), "НИИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.5, 0.5, 0.55))
	var tw := _panic_twitch()  # в панике стрелки дёргаются, как у прибора на пределе
	var sec := Vector2.from_angle(-PI / 2 + TAU * floorf(t) / 60.0 + tw * 0.35)
	draw_line(c, c + Vector2.from_angle(-PI / 2 + 0.9 + tw * 0.06) * 70.0, LINE, 12.0)
	draw_line(c, c + Vector2.from_angle(-PI / 2 + 4.1 - tw * 0.1) * 105.0, LINE, 8.0)
	draw_line(c, c + sec * 115.0, Color(0.8, 0.15, 0.1), 4.0)
	draw_circle(c, 12.0, LINE)


## Меловая доска: «ЭКСПЕРИМЕНТ №47», змея → яичница и зарубки по итогам забега.
func _draw_chalkboard(r: Rect2) -> void:
	draw_rect(Rect2(r.position + Vector2(14, 20), r.size), Color(0, 0, 0, 0.25))
	draw_rect(r.grow(30), Color(0.5, 0.36, 0.22))
	draw_rect(r, Color(0.15, 0.24, 0.2))
	Tex.blob(self, r.get_center() + Vector2(-200, -80), r.size * 0.55, Color(0.9, 0.95, 0.9, 0.05))  # разводы мела
	draw_rect(Rect2(r.position.x - 30, r.end.y + 30, r.size.x + 60, 30), Color(0.45, 0.32, 0.2))  # полочка
	draw_rect(Rect2(r.position.x + 200, r.end.y + 12, 90, 20), Color(0.95, 0.95, 0.9))  # мелок
	draw_rect(Rect2(r.position.x + 1180, r.end.y + 6, 180, 26), Color(0.35, 0.25, 0.2))  # губка
	var o := r.position
	draw_string(font, o + Vector2(60, 110), "ЭКСПЕРИМЕНТ №47", HORIZONTAL_ALIGNMENT_LEFT, -1, 78, CHALK)
	draw_line(o + Vector2(60, 132), o + Vector2(820, 128), CHALK, 6.0)
	# схема: змейка → яичница
	var s0 := o + Vector2(120, 290)
	var pts := PackedVector2Array()
	for i in 16:
		pts.append(s0 + Vector2(i * 22.0, sin(i * 0.8) * 30.0))
	draw_polyline(pts, CHALK, 10.0)
	draw_circle(pts[pts.size() - 1], 22.0, CHALK)
	draw_line(s0 + Vector2(400, 0), s0 + Vector2(560, 0), CHALK, 8.0)
	draw_colored_polygon(PackedVector2Array([s0 + Vector2(580, 0), s0 + Vector2(545, -22), s0 + Vector2(545, 22)]), CHALK)
	draw_arc(s0 + Vector2(700, 0), 90.0, 0, TAU, 28, CHALK, 8.0)
	draw_arc(s0 + Vector2(690, -8), 34.0, 0, TAU, 20, CHALK, 8.0)
	draw_string(font, s0 + Vector2(830, 26), "= ?", HORIZONTAL_ALIGNMENT_LEFT, -1, 80, CHALK)
	# зарубки: пучки по пять
	var names := ["МЕДВ.", "ВИЛК.", "ТАБЛ."]
	for row in 3:
		var y := o.y + 440.0 + row * 75.0
		draw_string(font, Vector2(o.x + 60, y + 22), names[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 44, CHALK)
		var n := mini(tally[row], 20)  # четыре пучка, дальше — «+N»: справа протокол
		for k in n:
			var group := k / 5
			var x := o.x + 260.0 + group * 150.0 + (k % 5) * 24.0
			if k % 5 == 4:  # пятая — наискось через пучок
				draw_line(Vector2(x - 110, y + 22), Vector2(x + 6, y - 22), CHALK, 7.0)
			else:
				draw_line(Vector2(x, y - 24), Vector2(x - 4, y + 24), CHALK, 7.0)
		if tally[row] > 20:
			draw_string(font, Vector2(o.x + 860, y + 20), "+%d" % (tally[row] - 20), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, CHALK)
	# протокол забега: колонка справа, отчёркнута вертикальной чертой
	draw_line(o + Vector2(1000, 380), o + Vector2(996, 640), CHALK, 5.0)
	draw_string(font, o + Vector2(1030, 404), "ПРОТОКОЛ", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, CHALK)
	var shown := mini(notes.size(), 9)
	for i in shown:
		var line := notes[i] if i < 8 or notes.size() <= 9 else "  … ещё %d" % (notes.size() - 8)
		draw_string(font, o + Vector2(1030, 450 + i * 25.0), line, HORIZONTAL_ALIGNMENT_LEFT, 510, 24, CHALK)
	draw_string(font, o + Vector2(1270, 110), "п. 12-Б", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1, 0.6, 0.55, 0.8))
	draw_arc(o + Vector2(1350, 96), 100.0, 0, TAU, 28, Color(1, 0.6, 0.55, 0.6), 6.0)


## Табло «ИДЁТ ЭКСПЕРИМЕНТ»: горит, пока горит лампа; в панике мигает.
func _draw_sign(r: Rect2) -> void:
	draw_rect(r.grow(18), Color(0.2, 0.2, 0.22))
	var on := lights * _lamp_flicker()
	draw_rect(r, Color(0.35, 0.05, 0.05).lerp(Color(0.95, 0.18, 0.12), on))
	if on > 0.1:
		Tex.blob(self, r.get_center(), r.size * 1.2, Color(1, 0.25, 0.15, 0.35 * on))
	draw_string(font, r.position + Vector2(0, 72), "ИДЁТ ЭКСПЕРИМЕНТ", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 42,
		Color(1, 0.92, 0.85, 0.3 + 0.7 * on))
	draw_line(Vector2(r.position.x + 60, r.position.y - 18), Vector2(r.position.x + 60, r.position.y - 40), LINE, 8.0)
	draw_line(Vector2(r.end.x - 60, r.position.y - 18), Vector2(r.end.x - 60, r.position.y - 40), LINE, 8.0)


## Труба вдоль стены с вентилем и манометром: в панике стрелка бьётся о красную зону.
func _draw_pipe() -> void:
	var col := Color(0.55, 0.52, 0.48)
	draw_rect(Rect2(PIPE_X - 34, -2500, 68, 2700), col.darkened(0.4))
	draw_rect(Rect2(PIPE_X - 26, -2500, 52, 2700), col)
	draw_rect(Rect2(PIPE_X - 18, -2500, 12, 2700), col.lightened(0.25))
	for y in [-1300.0, -500.0, 100.0]:  # хомуты
		draw_rect(Rect2(PIPE_X - 46, y, 92, 30), Color(0.35, 0.33, 0.3))
	var wheel := Vector2(PIPE_X, -800)  # вентиль
	draw_arc(wheel, 70.0, 0, TAU, 24, Color(0.75, 0.15, 0.12), 18.0)
	for k in 4:
		draw_line(wheel, wheel + Vector2.from_angle(k * PI / 2 + 0.4) * 70.0, Color(0.75, 0.15, 0.12), 12.0)
	draw_circle(wheel, 18.0, Color(0.5, 0.1, 0.08))
	var g := Vector2(PIPE_X - 170, -560)  # манометр
	draw_line(Vector2(PIPE_X, g.y), g, col, 30.0)
	draw_circle(g, 100.0, LINE)
	draw_circle(g, 88.0, Color(0.96, 0.95, 0.9))
	draw_arc(g, 70.0, PI * 0.15, PI * 0.45, 12, Color(0.85, 0.15, 0.1), 16.0)  # красная зона
	for i in 9:
		var d := Vector2.from_angle(PI * 0.75 + PI * 1.5 * i / 8.0)
		draw_line(g + d * 62.0, g + d * 80.0, LINE, 5.0)
	var pressure := clampf(0.35 + 0.1 * sin(t * 0.7) + Design.panic * 0.6 + _panic_twitch() * 0.12, 0.0, 1.05)
	var needle := Vector2.from_angle(PI * 0.75 + PI * 1.5 * pressure)
	draw_line(g, g + needle * 72.0, Color(0.1, 0.1, 0.12), 7.0)
	draw_circle(g, 12.0, LINE)


func _draw_board(r: Rect2) -> void:
	# доска объявлений с приказами
	draw_rect(Rect2(r.position + Vector2(14, 20), r.size + Vector2(48, 48)), Color(0, 0, 0, 0.2))
	draw_rect(r.grow(24), Color(0.45, 0.32, 0.2))
	draw_rect(r, Color(0.72, 0.58, 0.4))
	for k in 30:  # пробка
		draw_circle(r.position + Vector2(fmod(k * 173.0, r.size.x), fmod(k * 97.0, r.size.y)), 6.0, Color(0.62, 0.48, 0.32))
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


## Пожарный шкаф: красный, со стеклом. Огнетушитель висит, пока учёный его не взял.
func _draw_fire_box(r: Rect2) -> void:
	draw_rect(Rect2(r.position + Vector2(12, 16), r.size), Color(0, 0, 0, 0.25))
	draw_rect(r.grow(12), Color(0.55, 0.08, 0.06))
	draw_rect(r, Color(0.2, 0.07, 0.06))
	if not took_extinguisher:
		var body := Rect2(r.position + Vector2(90, 110), Vector2(120, 300))
		draw_rect(body, Color(0.8, 0.1, 0.1))
		draw_rect(Rect2(body.position + Vector2(16, 0), Vector2(22, body.size.y)), Color(1, 0.4, 0.35, 0.6))
		draw_rect(Rect2(body.position + Vector2(0, 110), Vector2(120, 70)), Color(0.95, 0.95, 0.92))
		draw_rect(Rect2(body.position + Vector2(30, -50), Vector2(60, 50)), Color(0.2, 0.2, 0.22))
	else:  # пустой крючок
		draw_line(r.position + Vector2(150, 80), r.position + Vector2(150, 130), Color(0.6, 0.6, 0.6), 10.0)
		draw_arc(r.position + Vector2(165, 130), 15.0, 0, PI, 8, Color(0.6, 0.6, 0.6), 8.0)
	draw_rect(r, Color(0.8, 0.9, 1.0, 0.12))  # стекло
	draw_line(r.position + Vector2(30, 40), r.position + Vector2(120, 200), Color(1, 1, 1, 0.2), 16.0)
	draw_rect(Rect2(r.position + Vector2(20, -70), Vector2(r.size.x - 40, 50)), Color(0.85, 0.1, 0.08))
	draw_string(font, r.position + Vector2(20, -32), "ОУ-2 · 01", HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 40, 36, Color.WHITE)


## Шкаф с образцами: стеклянные дверцы, банки в формалине с пузырьками, папки с отчётами сверху.
func _draw_shelves() -> void:
	var r := CABINET
	draw_rect(Rect2(r.position + Vector2(16, 20), r.size), Color(0, 0, 0, 0.22))
	draw_rect(r.grow(20), Color(0.42, 0.44, 0.45))
	draw_rect(r, Color(0.2, 0.22, 0.23))
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
	# архив образцов: банки в формалине с образцами прошлых экспериментов
	for i in 4:
		var base := Vector2(-1080 + i * 270, -120)
		var jar := Rect2(base.x, base.y - 250, 190, 250)
		draw_rect(jar, Color(0.75, 0.85, 0.45, 0.22))  # желтоватый формалин
		match i:
			1:
				_draw_mini_fork(jar.get_center() + Vector2(0, 20))
			2:
				_draw_mini_pill(jar.get_center() + Vector2(0, 40))
			_:
				_draw_mini_bear(jar.get_center() + Vector2(0, 30), 3.4, [Color(0.62, 0.4, 0.22), Color(0.55, 0.33, 0.2),
					Color(0.75, 0.55, 0.35), Color(0.65, 0.45, 0.25)][i])
		for k in 3:  # пузырьки
			var ph := fmod(t * 0.4 + k * 0.33 + i * 0.21, 1.0)
			draw_arc(jar.position + Vector2(40 + k * 50, jar.size.y * (1.0 - ph)), 7.0, 0, TAU, 8, Color(1, 1, 1, 0.5 * (1.0 - ph)), 3.0)
		draw_rect(jar, Color(0.75, 0.9, 0.95, 0.55), false, 7.0)
		draw_line(jar.position + Vector2(25, 30), jar.position + Vector2(25, 200), Color(1, 1, 1, 0.35), 10.0)
		draw_rect(Rect2(jar.position.x - 8, jar.position.y - 34, jar.size.x + 16, 38), Color(0.35, 0.35, 0.4))
		draw_rect(Rect2(jar.position.x + 45, jar.position.y + 150, 100, 55), Color(0.93, 0.88, 0.75))
		draw_string(font, Vector2(jar.position.x + 52, jar.position.y + 192), "№%d" % [21, 44, 45, 46][i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.2, 0.1, 0.05))
	# стеклянные дверцы с бликами
	for k in 2:
		var door := Rect2(r.position.x + k * r.size.x / 2.0, r.position.y, r.size.x / 2.0, r.size.y)
		draw_rect(door, Color(0.7, 0.85, 0.95, 0.07))
		draw_rect(door, Color(0.6, 0.62, 0.62), false, 12.0)
		draw_line(door.position + Vector2(60, 80), door.position + Vector2(260, 480), Color(1, 1, 1, 0.1), 30.0)
		draw_circle(Vector2(door.end.x - 30 if k == 0 else door.position.x + 30, door.get_center().y), 14.0, Color(0.75, 0.65, 0.4))
	draw_rect(Rect2(r.position.x + 300, r.position.y - 90, 600, 70), Color(0.9, 0.9, 0.86))
	draw_string(font, Vector2(r.position.x + 300, r.position.y - 38), "ОБРАЗЦЫ · АРХИВ", HORIZONTAL_ALIGNMENT_CENTER, 600, 40,
		Color(0.2, 0.2, 0.25))


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


## Зелёная эмалевая лампа над ящиком; в луче пляшут пылинки.
func _draw_lamp() -> void:
	var lit := lights * _lamp_flicker()
	draw_line(Vector2(640, -2500), Vector2(640, -600), Color(0.1, 0.1, 0.1), 10.0)
	var cone := PackedVector2Array([Vector2(520, -330), Vector2(760, -330), Vector2(1080, 20), Vector2(200, 20)])
	draw_colored_polygon(cone, Color(1, 0.95, 0.6, 0.08 * lit))
	for m in motes:
		var y := fmod(m.y + t * 0.02, 1.0)
		var half := lerpf(120.0, 440.0, y)
		var x := 640.0 + (m.x * 2.0 - 1.0) * half + sin(t * 0.6 + m.z) * 20.0
		draw_circle(Vector2(x, lerpf(-320.0, 0.0, y)), 6.0, Color(1, 0.97, 0.8, 0.35 * lit * sin(y * PI)))
	var shade := PackedVector2Array([Vector2(590, -610), Vector2(690, -610), Vector2(800, -360), Vector2(480, -360)])
	draw_colored_polygon(shade, Color(0.18, 0.4, 0.3))
	draw_polyline(PackedVector2Array([shade[0], shade[1], shade[2], shade[3], shade[0]]), Color(0.1, 0.22, 0.17), 8.0)
	draw_line(Vector2(560, -470), Vector2(620, -600), Color(0.4, 0.65, 0.5, 0.6), 10.0)  # блик эмали
	draw_rect(Rect2(610, -640, 60, 34), Color(0.7, 0.62, 0.35))  # латунный патрон
	draw_circle(Vector2(640, -360), 50.0, Color(1, 0.97, 0.85).lerp(Color(0.35, 0.33, 0.3), 1.0 - lit))
	Tex.blob(self, Vector2(640, -360), Vector2.ONE * 240.0, Color(1, 0.95, 0.7, 0.35 * lit))


func _draw_table() -> void:
	draw_rect(Rect2(-1300, TABLE_Y, 5800, 100), Color(0.2, 0.22, 0.22))  # столешница: тёмный лабораторный пластик
	draw_rect(Rect2(-1300, TABLE_Y, 5800, 14), Color(0.34, 0.37, 0.37))
	draw_rect(Rect2(-1300, TABLE_Y + 100, 5800, 320), Color(0.55, 0.57, 0.55))  # тумбы с ящиками
	for x in range(-1260, 4460, 470):
		for row in 2:
			var dr := Rect2(x, TABLE_Y + 120 + row * 150, 440, 130)
			draw_rect(dr, Color(0.62, 0.64, 0.62))
			draw_rect(dr, Color(0.45, 0.47, 0.45), false, 6.0)
			draw_rect(Rect2(dr.get_center() - Vector2(60, 10), Vector2(120, 20)), Color(0.35, 0.35, 0.37))
	Tex.blob(self, Vector2(1600, TABLE_Y + 520), Vector2(3600, 140), Color(0, 0, 0, 0.35))  # тень под столом
	for x in [-1150.0, 4250.0]:
		draw_rect(Rect2(x - 55, TABLE_Y + 420, 110, 1400), Color(0.3, 0.32, 0.32))
	# стопки бланков и печать
	for k in 6:
		draw_rect(Rect2(-1000 + k * 5, TABLE_Y - 14 - k * 14, 520, 14),
			Color(0.95, 0.93, 0.88) if k % 2 == 0 else Color(0.88, 0.86, 0.8))
	_draw_flasks(Vector2(-400, TABLE_Y))
	_draw_microscope(Vector2(1480, TABLE_Y))
	_draw_monitor(MONITOR)
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


## Колбы с реактивами на штативе: жидкость бурлит.
func _draw_flasks(base: Vector2) -> void:
	var cols := [Color(0.35, 0.85, 0.5), Color(0.95, 0.55, 0.2), Color(0.4, 0.6, 1.0)]
	for i in 3:
		var c := base + Vector2(i * 120, 0)
		var neck := Rect2(c + Vector2(-18, -260), Vector2(36, 110))
		var body := PackedVector2Array([c + Vector2(-18, -150), c + Vector2(18, -150), c + Vector2(62, -10),
			c + Vector2(-62, -10)])
		var liquid := PackedVector2Array([c + Vector2(-38, -80), c + Vector2(38, -80), c + Vector2(62, -10), c + Vector2(-62, -10)])
		draw_colored_polygon(liquid, Color(cols[i], 0.8))
		for k in 3:
			var ph := fmod(t * 0.9 + k * 0.3 + i * 0.17, 1.0)
			draw_circle(c + Vector2(-20 + k * 20, -20 - ph * 60.0), 5.0, Color(1, 1, 1, 0.55 * (1.0 - ph)))
		draw_colored_polygon(body, Color(0.8, 0.95, 1.0, 0.18))
		draw_polyline(PackedVector2Array([body[0], body[3], body[2], body[1]]), Color(0.75, 0.9, 0.95, 0.8), 6.0)
		draw_rect(neck, Color(0.8, 0.95, 1.0, 0.18))
		draw_rect(neck, Color(0.75, 0.9, 0.95, 0.8), false, 5.0)
	draw_rect(Rect2(base + Vector2(-90, -12), Vector2(420, 12)), Color(0.35, 0.35, 0.38))  # подставка


func _draw_microscope(base: Vector2) -> void:
	var dark := Color(0.2, 0.22, 0.26)
	draw_rect(Rect2(base + Vector2(-110, -40), Vector2(220, 40)), dark)
	draw_line(base + Vector2(60, -40), base + Vector2(60, -300), dark, 40.0)
	draw_line(base + Vector2(60, -280), base + Vector2(-40, -380), dark, 44.0)
	draw_line(base + Vector2(-40, -380), base + Vector2(-60, -460), Color(0.3, 0.32, 0.36), 30.0)
	draw_rect(Rect2(base + Vector2(-90, -160), Vector2(130, 18)), Color(0.35, 0.37, 0.4))
	draw_line(base + Vector2(-30, -300), base + Vector2(-30, -200), Color(0.55, 0.58, 0.6), 18.0)
	draw_circle(base + Vector2(60, -200), 24.0, Color(0.45, 0.47, 0.5))


## Монитор наблюдения: зелёный люминофор с «картинкой из ящика». Светится и после того, как погас свет.
func _draw_monitor(r: Rect2) -> void:
	draw_rect(Rect2(r.position + Vector2(r.size.x / 2 - 60, r.size.y), Vector2(120, 30)), Color(0.35, 0.33, 0.3))
	draw_rect(r, Color(0.78, 0.75, 0.68))
	draw_rect(r, Color(0.5, 0.48, 0.44), false, 8.0)
	var screen := Rect2(r.position + Vector2(40, 36), r.size - Vector2(80, 110))
	var phosphor := Color(0.4, 1.0, 0.55)
	draw_rect(screen, Color(0.03, 0.08, 0.04))
	var k := 0.85 + 0.15 * sin(t * 13.0) * sin(t * 3.1)
	for y in range(int(screen.position.y), int(screen.end.y), 12):
		draw_line(Vector2(screen.position.x, y), Vector2(screen.end.x, y), Color(phosphor, 0.06 * k), 3.0)
	var box := screen.grow(-30)
	draw_rect(box, Color(phosphor, 0.35 * k), false, 4.0)
	var snake := PackedVector2Array()
	for i in 9:
		snake.append(box.position + Vector2(60 + i * 18, box.size.y * 0.6 + sin(i * 0.9 + t * 2.0) * 16.0))
	draw_polyline(snake, Color(phosphor, 0.7 * k), 7.0)
	draw_circle(box.position + Vector2(box.size.x * 0.72, box.size.y * 0.4), 28.0, Color(phosphor, 0.4 * k))
	if fmod(t, 1.2) < 0.7:
		draw_circle(screen.position + Vector2(30, 30), 10.0, Color(1, 0.2, 0.15))
	draw_string(font, screen.position + Vector2(50, 42), "REC  ЯЩИК-47", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(phosphor, 0.8))
	Tex.blob(self, screen.get_center(), screen.size * 0.9, Color(phosphor, 0.12))
	draw_circle(r.position + Vector2(r.size.x - 60, r.size.y - 36), 12.0, Color(0.3, 0.9, 0.4))


func _draw_box_front() -> void:
	draw_rect(Rect2(-10, 720, 1300, TABLE_Y - 720), Color(0.45, 0.27, 0.13))
	for y in [760.0, 800.0]:
		draw_line(Vector2(-10, y), Vector2(1290, y), Color(0.35, 0.2, 0.1), 5.0)
	var plate := Rect2(400, 738, 480, 84)
	draw_rect(plate, Color(0.9, 0.9, 0.88))
	draw_rect(plate, Color(0.5, 0.5, 0.5), false, 6.0)
	for s in [plate.position + Vector2(14, 42), plate.end - Vector2(14, 42)]:
		draw_circle(s, 7.0, Color(0.55, 0.5, 0.35))
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
