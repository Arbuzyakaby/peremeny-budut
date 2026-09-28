extends "res://scripts/ending/lab_room.gd"
## Кабинет-лаборатория, который виден, когда камера отдаляется в финале. Арена оказывается
## маленьким ящиком на столе учёного-бюрократа: белый халат поверх серого костюма, очки, бейдж,
## планшет с протоколом (v8.0: халат, новая комната — см. lab_room.gd).
## Всё рисуется кодом в мировых координатах (арена занимает 0..1280 × 0..720).
## Рука со спичкой (или огнетушителем) рисуется отдельным узлом поверх арены.


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


func _process(delta: float) -> void:
	t += delta
	talk = maxf(talk - delta, 0.0)
	flash = maxf(flash - delta * 1.8, 0.0)
	if walking:
		walk += delta * 7.0
	if holding == Hold.EXTINGUISHER:
		took_extinguisher = true  # шкаф на стене опустел
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
	var up := Vector2(0, -_bob() - startle * 45.0)
	var jitter := Vector2(sin(t * 60.0), 0) * 8.0 * startle
	var o := up + jitter
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
	front.draw_line(wrist, hd + (elbow - hd).normalized() * 40.0, Color(0.96, 0.96, 0.97), 120.0)  # манжета
	if holding == Hold.EXTINGUISHER:
		_draw_extinguisher(hd)
	elif match_state == Match.HELD or match_state == Match.LIT:
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


## Сопло огнетушителя (куда бьёт пена).
func nozzle() -> Vector2:
	return _hand_drawn() + Vector2(-210, -40)


func _draw_extinguisher(hd: Vector2) -> void:
	var body := Rect2(hd + Vector2(-70, -40), Vector2(140, 420))
	front.draw_rect(body.grow(10), LINE)
	front.draw_rect(body, Color(0.8, 0.1, 0.1))
	front.draw_rect(Rect2(body.position + Vector2(18, 0), Vector2(26, body.size.y)), Color(1, 0.4, 0.35, 0.6))
	front.draw_rect(Rect2(body.position + Vector2(0, 150), Vector2(140, 90)), Color(0.95, 0.95, 0.92))
	front.draw_string(font, body.position + Vector2(14, 212), "ОУ-2", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, LINE)
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
