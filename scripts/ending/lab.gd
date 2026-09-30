extends "res://scripts/ending/lab_room.gd"
## Кабинет-лаборатория, который виден, когда камера отдаляется в финале. Арена оказывается
## маленьким ящиком на столе учёного-бюрократа: белый халат поверх серого костюма, очки, бейдж,
## планшет с протоколом (v8.0: халат, новая комната — см. lab_room.gd).
## Всё рисуется кодом в мировых координатах (арена занимает 0..1280 × 0..720).
## Рука со спичкой (или огнетушителем) рисуется отдельным узлом поверх арены.
## v12.4 — учёный ожил: моргает (blink_amount), дышит плечами, наклоняет голову туда, куда смотрит,
## брови скучают, хмурятся на словах и взлетают от испуга, рот открывается по слогам реплики
## (speak → mouth_open: гласные — шире, пробел — закрыт), по очкам пробегает блик, при ходьбе
## плечи раскачиваются. Кисть — в стиле подробной руки из финала «Контакта»: тыльная сторона,
## костяшки, ногти, манжета рубашки и часы. На халате — складки и пятно от реактива.


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
	for i in 26:
		motes.append(Vector3(randf(), randf(), randf() * TAU))


## Реплика: рот двигается по её слогам, пока идёт talk.
func speak(text: String, time: float) -> void:
	say_text = text
	say_t = 0.0
	talk = time


## 0 — глаза открыты, 1 — закрыты. Моргает раз в 3–4 с, на 0,14 с; ритм сбивается, чтобы не было метронома.
static func blink_amount(time: float) -> float:
	const PERIOD := 3.6
	var cycle := floorf(time / PERIOD)
	var jitter := fmod(absf(sin(cycle * 12.9898) * 437.585), 1.0) * 1.2  # у каждого цикла свой сдвиг
	var ph := time - cycle * PERIOD - jitter
	if ph < 0.0 or ph > 0.14:
		return 0.0
	return sin(ph / 0.14 * PI)


## Насколько открыт рот (0..1) на слоге реплики: гласные — широко, согласные — чуть, пробел и знаки — закрыт.
static func mouth_open(text: String, elapsed: float) -> float:
	if text == "":
		return 0.5 + 0.5 * absf(sin(elapsed * 12.0))
	var i := int(elapsed * 15.0) % text.length()  # ~15 букв в секунду — как читают субтитры
	var ch := text[i].to_lower()
	if ch in "аеёиоуыэюяaeiouy":
		return 1.0 if ch in "аоуыяa o" else 0.8
	if ch == " " or ch in ",.!?…—-«»":
		return 0.0
	return 0.35


## Наклон головы к точке, куда смотрит учёный: чуть-чуть, иначе мультяшно.
func head_tilt() -> float:
	return clampf((look.x - sx) / 4000.0, -0.09, 0.09) + (sin(t * 1.3) * 0.012 if not walking else 0.0)


func _breath() -> float:
	return sin(t * 1.6) * 7.0


func _process(delta: float) -> void:
	t += delta
	say_t += delta
	talk = maxf(talk - delta, 0.0)
	flash = maxf(flash - delta * 1.8, 0.0)
	if walking:
		walk += delta * 7.0
	if holding == Hold.EXTINGUISHER:
		took_extinguisher = true  # шкаф на стене опустел
	queue_redraw()
	front.queue_redraw()


func head_pos() -> Vector2:
	return Vector2(sx, HEAD_Y - _bob() - startle * 45.0 + _breath() * 0.6)


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


func _draw() -> void:
	_draw_wall()
	_draw_window(WINDOW)
	_draw_chalkboard(CHALKBOARD)
	_draw_pipe()
	_draw_sign(SIGN)
	_draw_board(BOARD)
	_draw_fire_box(FIRE_BOX)
	_draw_shelves()
	_draw_clock(Vector2(-1600, -750))
	_draw_lamp()
	_draw_person()
	_draw_table()
	_draw_box_front()
	if flash > 0.0:
		draw_rect(Rect2(-3000, -2500, 9000, 6000), Color(0.85, 0.9, 1, 0.35 * flash))
	if glow > 0.0:
		var fl := 0.8 + 0.2 * sin(t * 17.0) * sin(t * 5.3)
		draw_rect(Rect2(-3000, -2500, 9000, 6000), Color(1, 0.4, 0.1, 0.13 * glow * fl))


func _draw_person() -> void:
	if sx > OUTSIDE_X - 10.0:
		return
	var up := Vector2(0, -_bob() - startle * 45.0 + _breath() * 0.6)
	var jitter := Vector2(sin(t * 60.0), 0) * 8.0 * startle
	var sway := Vector2(sin(walk) * 16.0, 0) if walking else Vector2.ZERO  # плечи раскачиваются на ходу
	var o := up + jitter + sway
	var skin := SKIN.lerp(Color(1, 0.6, 0.35), glow * 0.2)
	# правая рука (у нас справа) с планшетом
	var sh := Vector2(sx + 420, 20) + o
	var el := Vector2(sx + 560, 440) + o
	var hand_r := Vector2(sx + 430, 700) + o
	for pass_i in 2:
		var col := LINE if pass_i == 0 else COAT
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
	# белый халат нараспашку поверх костюма: полы, воротник, нагрудный карман с ручками
	for s in [-1.0, 1.0]:
		var coat := PackedVector2Array([c + Vector2(s * 150, -110), c + Vector2(s * 390, -100), c + Vector2(s * 530, 60),
			c + Vector2(s * 600, 900), c + Vector2(s * 230, 900), c + Vector2(s * 200, 300)])
		draw_colored_polygon(coat, COAT)
		draw_polyline(PackedVector2Array([coat[0], coat[5], coat[4]]), COAT_SHADE, 12.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(s * 150, -110), c + Vector2(s * 290, -80),
			c + Vector2(s * 210, 150)]), COAT_SHADE)  # воротник
	var pocket := Rect2(c + Vector2(260, 180), Vector2(170, 150))
	draw_rect(pocket, COAT_SHADE)
	for k in 3:
		draw_line(pocket.position + Vector2(30 + k * 45, 10), pocket.position + Vector2(30 + k * 45, -70),
			[Color(0.15, 0.25, 0.6), Color(0.75, 0.15, 0.12), Color(0.15, 0.15, 0.18)][k], 16.0)
	draw_line(c + Vector2(420, 600), c + Vector2(560, 600), COAT_SHADE, 10.0)  # боковой карман
	for sd: float in [-1.0, 1.0]:  # складки халата от плеча вниз
		for k in 3:
			var x0: float = sd * (300.0 + k * 70.0)
			draw_line(c + Vector2(x0, 120 + k * 90), c + Vector2(x0 + sd * 40.0, 520 + k * 110), Color(COAT_SHADE, 0.8), 7.0)
	var stain := c + Vector2(-420, 640)  # пятно от реактива: бурое, с ореолом
	draw_circle(stain, 34.0, Color(0.72, 0.6, 0.35, 0.45))
	draw_circle(stain + Vector2(18, 10), 20.0, Color(0.62, 0.48, 0.25, 0.5))
	draw_circle(stain + Vector2(-26, 22), 9.0, Color(0.62, 0.48, 0.25, 0.45))
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
	if writing:  # ручка бегает по строчкам
		var line_i := int(t * 1.5) % 6
		var pen := clip.position + Vector2(50 + fmod(t * 260.0, 200.0), 86 + line_i * 42) + Vector2(0, sin(t * 40.0) * 6.0)
		draw_line(pen, pen + Vector2(90, -150), Color(0.1, 0.15, 0.4), 16.0)
		draw_line(pen, pen + Vector2(12, -20), Color(0.8, 0.75, 0.3), 10.0)
		draw_circle(pen + Vector2(90, -150), 40.0, LINE)
		draw_circle(pen + Vector2(90, -150), 32.0, skin)
	_draw_palm(self, hand_r, skin, true)  # держит планшет: та же подробная кисть
	# шея и голова (голова рисуется в своих координатах: наклон к взгляду)
	var h := Vector2(sx, HEAD_Y) + o
	draw_rect(Rect2(c + Vector2(-95, -200), Vector2(190, 110)), skin.darkened(0.1))
	draw_set_transform(h, head_tilt())
	_draw_head(skin)
	draw_set_transform(Vector2.ZERO)


## Голова в своих координатах (центр — середина лица). Всё настроение — здесь.
func _draw_head(skin: Color) -> void:
	var h := Vector2.ZERO
	for s in [-1.0, 1.0]:  # уши
		draw_circle(h + Vector2(s * 245, 20), 60.0, LINE)
		draw_circle(h + Vector2(s * 245, 20), 50.0, skin)
		draw_arc(h + Vector2(s * 245, 22), 26.0, PI * 0.6 if s > 0 else -PI * 0.4, PI * 1.4 if s > 0 else PI * 0.4, 8,
			skin.darkened(0.2), 6.0)
	draw_circle(h, 262.0, LINE)
	draw_circle(h, 250.0, skin)
	# свет лампы сверху: низ лица в лёгкой тени, румянец на щеках
	draw_arc(h + Vector2(0, -30), 225.0, 0.35, PI - 0.35, 24, Color(skin.darkened(0.25), 0.35), 40.0)
	for s in [-1.0, 1.0]:
		draw_circle(h + Vector2(s * 150, 70), 38.0, Color(0.95, 0.55, 0.5, 0.18))
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
	for k in 3:  # седая прядь от пробора
		draw_line(h + Vector2(-40 + k * 26, -240), h + Vector2(10 + k * 34, -176), Color(0.66, 0.66, 0.66, 0.8), 9.0)
	for s in [-1.0, 1.0]:  # седина на висках
		draw_circle(h + Vector2(s * 225, -30), 26.0, Color(0.62, 0.62, 0.62))
	# брови: скучают ровно, на словах хмурятся к переносице, при испуге взлетают
	var frown := clampf(talk, 0.0, 1.0) * (1.0 - startle)
	for s in [-1.0, 1.0]:
		var by := -85.0 - startle * 45.0
		var inner := h + Vector2(s * 55, by + 14.0 * frown)
		var outer := h + Vector2(s * 165, by - 6.0 * startle - 6.0 * frown)
		draw_line(inner, outer, HAIR, 22.0)
	# глаза за очками: скучающие, полуприкрытые; при испуге — круглые; моргают
	var blink := blink_amount(t) * (1.0 - startle)
	for s in [-1.0, 1.0]:
		var e := h + Vector2(s * 105, -20)
		var r := lerpf(34.0, 52.0, startle)
		draw_circle(e, r, Color.WHITE)
		var dir := (look - head_pos() - e).normalized()
		draw_circle(e + dir * r * 0.35, lerpf(17.0, 10.0, startle), Color(0.2, 0.15, 0.1))
		draw_circle(e + dir * r * 0.35 + Vector2(-5, -6), 4.0, Color(1, 1, 1, 0.8))  # блик в зрачке
		var lid := maxf(0.475 if startle < 0.5 else 0.0, blink)  # доля глаза под веком
		if lid > 0.0:
			draw_rect(Rect2(e + Vector2(-r - 2, -r - 2), Vector2(r * 2 + 4, (r * 2 + 4) * lid)), skin)
			draw_line(e + Vector2(-r, -r + r * 2.0 * lid), e + Vector2(r, -r + r * 2.0 * lid), LINE, 6.0)
		# прямоугольная оправа и стекло
		var frame := Rect2(e + Vector2(-80, -55), Vector2(160, 105))
		draw_rect(frame, Color(0.8, 0.9, 1.0, 0.12))
		var g := fmod(t * 0.23 + (0.0 if s < 0 else 0.08), 1.0)  # блик пробегает по стеклу раз в ~4 с
		if g < 0.18:
			var gx := frame.position.x + frame.size.x * (g / 0.18)
			draw_line(Vector2(gx - 30, frame.end.y - 6), Vector2(gx + 20, frame.position.y + 6), Color(1, 1, 1, 0.55), 12.0)
		draw_line(frame.position + Vector2(14, 14), frame.position + Vector2(44, 14), Color(1, 1, 1, 0.4), 5.0)
		draw_rect(frame, LINE, false, 11.0)
	draw_line(h + Vector2(-25, -30), h + Vector2(25, -30), LINE, 10.0)
	for s in [-1.0, 1.0]:
		draw_line(h + Vector2(s * 185, -30), h + Vector2(s * 245, -10), LINE, 9.0)
	# нос
	draw_line(h + Vector2(0, 5), h + Vector2(-18, 85), skin.darkened(0.25), 9.0)
	draw_line(h + Vector2(-18, 85), h + Vector2(12, 92), skin.darkened(0.25), 9.0)
	# рот: ровная линия; говорит — открывается по слогам; испуг — «о»
	var m := h + Vector2(0, 150)
	if startle > 0.3:
		draw_circle(m + Vector2(0, 10), 34.0 * startle, LINE)
		draw_circle(m + Vector2(0, 10), 24.0 * startle, Color(0.45, 0.12, 0.12))
	elif talk > 0.0:
		var k := mouth_open(say_text, say_t)
		var open := 6.0 + k * 34.0
		var w := 120.0 - k * 30.0  # на «о» и «у» губы собираются
		draw_rect(Rect2(m + Vector2(-w / 2.0, -open / 2.0), Vector2(w, open)), Color(0.35, 0.1, 0.1))
		if k > 0.5:
			draw_rect(Rect2(m + Vector2(-w / 2.0 + 10, -open / 2.0), Vector2(w - 20, 8)), Color(0.96, 0.95, 0.92))  # зубы
		draw_rect(Rect2(m + Vector2(-w / 2.0, -open / 2.0), Vector2(w, open)), LINE, false, 6.0)
	else:
		draw_line(m + Vector2(-65, 0), m + Vector2(65, 0), LINE, 10.0)
		draw_line(m + Vector2(-65, 0), m + Vector2(-75, 8), LINE, 8.0)  # уголки губ вниз — скучает


func _draw_front() -> void:
	if sx > OUTSIDE_X - 10.0:
		return
	var suit := COAT
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
	var down := (hd - elbow).normalized()
	front.draw_line(wrist, hd - down * 40.0, Color(0.96, 0.96, 0.97), 120.0)  # манжета рубашки
	_draw_watch(hd - down * 70.0, down)
	if holding == Hold.EXTINGUISHER:
		_draw_extinguisher(hd)
	elif match_state == Match.HELD or match_state == Match.LIT:
		_draw_match(hd + Vector2(-10, -30), match_tip(), match_state == Match.LIT)
	_draw_palm(front, hd, skin)
	if match_state == Match.FLYING:
		var dir := Vector2.from_angle(match_rot)
		_draw_match(match_pos - dir * 190.0, match_pos, true)


## Раструб углекислотного огнетушителя (откуда бьёт струя CO₂).
func nozzle() -> Vector2:
	return _hand_drawn() + Vector2(-210, -40)


func _draw_extinguisher(hd: Vector2) -> void:
	var body := Rect2(hd + Vector2(-70, -40), Vector2(140, 420))
	front.draw_rect(body.grow(10), LINE)
	front.draw_rect(body, Color(0.8, 0.1, 0.1))
	front.draw_rect(Rect2(body.position + Vector2(18, 0), Vector2(26, body.size.y)), Color(1, 0.4, 0.35, 0.6))
	front.draw_rect(Rect2(body.position + Vector2(0, 150), Vector2(140, 90)), Color(0.95, 0.95, 0.92))
	front.draw_string(font, body.position + Vector2(14, 212), "ОУ-5", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, LINE)
	front.draw_rect(Rect2(hd + Vector2(-40, -110), Vector2(80, 80)), Color(0.2, 0.2, 0.22))  # вентиль
	var n := nozzle()
	front.draw_line(hd + Vector2(0, -90), hd + Vector2(-110, -60), LINE, 34.0)
	front.draw_line(hd + Vector2(0, -90), hd + Vector2(-110, -60), Color(0.15, 0.15, 0.17), 24.0)
	front.draw_line(hd + Vector2(-110, -60), n, Color(0.15, 0.15, 0.17), 24.0)
	front.draw_colored_polygon(PackedVector2Array([n + Vector2(10, -20), n + Vector2(-70, -45), n + Vector2(-70, 45),
		n + Vector2(10, 20)]), Color(0.12, 0.12, 0.14))
	if spraying:
		Tex.blob(front, n + Vector2(-140, 60), Vector2(230, 160), Color(1, 1, 1, 0.55))


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


## Кисть (v12.4, в стиле руки из «Контакта»): тыльная сторона с тенью и сухожилиями, костяшки,
## пальцы-«капсулы» с ногтями. Держит спичку щепотью; от испуга пальцы разжимаются веером.
func _draw_palm(ci: CanvasItem, hd: Vector2, skin: Color, grip := false) -> void:
	var skin_d := skin.darkened(0.14)
	var back := PackedVector2Array()
	for v in [Vector2(-70, -60), Vector2(-18, -80), Vector2(50, -72), Vector2(84, -20), Vector2(82, 40),
			Vector2(52, 72), Vector2(-4, 80), Vector2(-56, 68), Vector2(-84, 16)]:
		back.append(hd + v)
	_poly(ci, back, skin, 7.0)
	ci.draw_colored_polygon(PackedVector2Array([hd + Vector2(40, -58), hd + Vector2(82, -18), hd + Vector2(80, 36),
		hd + Vector2(50, 68), hd + Vector2(28, 20)]), Color(skin_d, 0.55))  # теневая сторона
	for k in 3:  # сухожилия
		var x := -30.0 + k * 26.0
		ci.draw_line(hd + Vector2(x * 0.6, -58), hd + Vector2(x, 42), Color(skin_d, 0.5), 4.0)
	var knuckles := [Vector2(-46, -70), Vector2(-12, -78), Vector2(22, -74), Vector2(52, -60)]
	var spread := startle * 0.5
	for k in 4:
		var kn: Vector2 = hd + knuckles[k]
		var a := -PI / 2.0 - 0.55 + k * 0.28 + (k - 1.5) * spread
		var len := 66.0 + startle * 20.0 - k * 4.0
		var tip := kn + Vector2.from_angle(a) * len
		if grip:  # обхватил край планшета: пальцы загнуты вниз
			tip = kn + Vector2(-6.0 + k * 4.0, 58.0)
		elif not startle > 0.2:  # щепоть: кончики к спичке
			tip = kn.lerp(hd + Vector2(-10, -130), 0.75)
		_capsule(ci, kn, tip, 20.0 - k * 1.5, skin)
		_nail(ci, tip, (tip - kn).normalized())
	_capsule(ci, hd + Vector2(-82, -4), hd + Vector2(-60, -96) if startle < 0.2 else hd + Vector2(-126, -40), 22.0, skin)
	for kn in knuckles:
		ci.draw_arc(hd + kn + Vector2(0, 10), 12.0, 0.2, PI - 0.2, 8, Color(skin_d, 0.9), 3.0)


## Часы на запястье: ремешок поперёк руки, корпус, циферблат, стрелки идут.
func _draw_watch(at: Vector2, along: Vector2) -> void:
	var n := along.orthogonal()
	front.draw_line(at + n * 62.0, at - n * 62.0, LINE, 34.0)
	front.draw_line(at + n * 60.0, at - n * 60.0, Color(0.36, 0.22, 0.13), 24.0)
	front.draw_circle(at, 32.0, LINE)
	front.draw_circle(at, 26.0, Color(0.78, 0.75, 0.68))
	front.draw_circle(at, 20.0, Color(0.96, 0.95, 0.9))
	front.draw_line(at, at + Vector2.from_angle(t * 0.5) * 13.0, LINE, 3.0)
	front.draw_line(at, at + Vector2.from_angle(t * 6.0) * 17.0, Color(0.7, 0.1, 0.1), 2.0)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, w := 6.0) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, LINE, w, true)


static func _capsule(ci: CanvasItem, a: Vector2, b: Vector2, r: float, fill: Color) -> void:
	ci.draw_line(a, b, LINE, r * 2.0 + 8.0)
	ci.draw_circle(a, r + 4.0, LINE)
	ci.draw_circle(b, r + 4.0, LINE)
	ci.draw_line(a, b, fill, r * 2.0)
	ci.draw_circle(a, r, fill)
	ci.draw_circle(b, r, fill)


static func _nail(ci: CanvasItem, at: Vector2, dir: Vector2) -> void:
	var n := dir.orthogonal()
	var c := at - dir * 5.0
	ci.draw_colored_polygon(PackedVector2Array([c + n * 9.0, c + dir * 10.0 + n * 6.0, c + dir * 10.0 - n * 6.0, c - n * 9.0]),
		Color(0.98, 0.86, 0.82))
