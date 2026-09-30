extends Node
## Развязка «Контакта» (v10.0): камера отъезжает — ящик горит на столе учёного. Сбоку видно, как
## медведь-швея прыгает со стола на пол, а змея падает следом прямо на неё — как на подушку.
## Вдвоём они заползают в щель в цоколе напольной тумбы. Учёный светит фонарём, ищет — и сдаётся.
## Свет гаснет, в щели моргают две пары глаз. «КОНТАКТ УСТАНОВЛЕН», титры. Esc — пропустить.

signal finished

const Lab = preload("res://scripts/ending/lab.gd")
const Design = preload("res://scripts/ui/design.gd")
const Credits = preload("res://scripts/ending/credits.gd")
const Tex = preload("res://scripts/gfx/tex.gd")

const SCIENTIST := "УЧЁНЫЙ-БЮРОКРАТ"
const CAM_POS := Vector2(1600, 1250)
const CAM_ZOOM := Vector2(0.5, 0.5)
const TABLE_TOP := 836.0
const FLOOR := 1746.0
const BEAR_R := 46.0
const FUR := Color(0.8, 0.6, 0.45)
const SNAKE_GREEN := Color(0.33, 0.76, 0.28)

var g
var contact
var lab: Lab
var actors: Node2D
var darkness: CanvasModulate
var tw: Tween
var t := 0.0
var done := false
## Состояние сцены (всё в мировых координатах лаборатории).
var bear := Vector2(1330, TABLE_TOP - BEAR_R)
var bear_squash := 0.0
var bear_a := 1.0
var snake_pts := PackedVector2Array()
var snake_head := Vector2(1250, TABLE_TOP - 14)
var snake_a := 1.0
var beam_x := -1.0         # луч фонаря на полу (−1 — выключен)
var eyes := 0.0            # глаза в щели
var blink := 0.0


func start(game, c) -> void:
	g = game
	contact = c
	lab = Lab.new()
	lab.z_index = -10
	lab.show_cabinet = true
	lab.show_new_box = true
	lab.sx = Lab.STAND_X
	lab.hand = Vector2(Lab.STAND_X - 560, 700)
	lab.glow = 1.0
	lab.match_state = Lab.Match.NONE
	lab.tally = [int(c.counts["bear"]), int(c.counts["fork"]), int(c.counts["pill"]), int(c.counts["doll"])]
	g.add_child(lab)
	actors = Node2D.new()
	actors.z_as_relative = false
	actors.z_index = 45
	actors.draw.connect(_draw_actors)
	g.add_child(actors)
	darkness = CanvasModulate.new()
	darkness.color = Color.WHITE
	g.add_child(darkness)
	for i in 12:
		snake_pts.append(snake_head + Vector2(-i * 13.0, 0))
	g.hud.set_cinematic(true)
	g.sfx.play_music("")
	var cam: Camera2D = g.camera
	tw = create_tween()
	tw.tween_property(cam, "zoom", CAM_ZOOM, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(cam, "position", CAM_POS, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		g.sfx.play("gunshot", 0.9)
		lab.flash = 0.6
		_say("Стоять! Куда?!", 1.6))
	tw.tween_interval(0.6)
	# швея прыгает со стола
	tw.tween_callback(g.sfx.play.bind("whoosh", 0.8))
	tw.tween_method(_bear_jump, 0.0, 1.0, 0.9)
	tw.tween_callback(func() -> void:
		bear_squash = 0.6
		g.sfx.play("slam", 1.4, -8.0))
	tw.tween_interval(0.35)
	# змея — следом, прямо на неё
	tw.tween_callback(g.sfx.play.bind("whoosh", 1.1))
	tw.tween_method(_snake_jump, 0.0, 1.0, 0.8)
	tw.tween_callback(func() -> void:
		bear_squash = 1.0
		g.sfx.play("bonk", 0.7)
		g.hud.show_caption("", "Швея смягчила падение."))
	tw.tween_method(_bounce, 0.0, 1.0, 0.6)
	# вдвоём — в щель тумбы
	tw.tween_method(_crawl, 0.0, 1.0, 2.2)
	tw.tween_callback(func() -> void:
		g.hud.hide_caption()
		bear_a = 0.0
		snake_a = 0.0)
	tw.tween_interval(0.8)
	# учёный ищет с фонарём
	tw.tween_callback(func() -> void:
		beam_x = 2600.0
		g.sfx.play("lamp_click")
		_say("Где вы?.. Образцы не испаряются. По регламенту.", 3.0))
	tw.tween_property(self, "beam_x", 1250.0, 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "beam_x", 2300.0, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_say.bind("…Сбежали. Ну и ладно. В отчёте укажу: утилизированы.", 3.4))
	tw.tween_interval(3.6)
	tw.tween_callback(func() -> void:
		beam_x = -1.0
		lab.lights = 0.0
		g.hud.hide_caption()
		g.sfx.play("lamp_click")
		g.sfx.stop_ambient(2.0))
	tw.tween_property(darkness, "color", Color(0.2, 0.22, 0.34), 0.4)
	tw.tween_interval(1.0)
	tw.tween_property(self, "eyes", 1.0, 0.8)
	tw.tween_interval(1.6)
	tw.tween_callback(func() -> void:
		g.sfx.play("win", 0.6, -6.0)
		g.hud.show_title_card("КОНТАКТ УСТАНОВЛЕН", Color(0.6, 1, 0.55)))
	tw.tween_interval(4.2)
	tw.tween_callback(g.hud.hide_title_card)
	tw.tween_callback(func() -> void:
		g.sfx.play_music("sad")
		g.hud.roll_credits(Credits.contact_text(g, c), 16.0))
	tw.tween_interval(16.4)
	tw.tween_callback(_finish)


func _say(text: String, talk: float) -> void:
	g.hud.show_caption(SCIENTIST, text)
	lab.speak(text, talk)


func _bear_jump(k: float) -> void:
	var from := Vector2(1330, TABLE_TOP - BEAR_R)
	var to := Vector2(1780, FLOOR - BEAR_R)
	bear = from.lerp(to, k) + Vector2(0, -sin(k * PI) * 260.0)


func _snake_jump(k: float) -> void:
	var from := Vector2(1270, TABLE_TOP - 14)
	var to := bear + Vector2(0, -BEAR_R - 10)
	snake_head = from.lerp(to, k) + Vector2(0, -sin(k * PI) * 220.0)
	_drag_body()


func _bounce(k: float) -> void:
	bear_squash = 1.0 - k
	snake_head = bear + Vector2(20.0 * k, -BEAR_R - 10.0 - sin(k * PI) * 60.0)
	if k > 0.7:
		snake_head.y = lerpf(snake_head.y, FLOOR - 12.0, (k - 0.7) / 0.3)
		snake_head.x = bear.x + 60.0
	_drag_body()


## Бегут к щели: медведь впереди, змея за ним; у щели — растворяются в темноте.
func _crawl(k: float) -> void:
	var gap := Lab.CABINET_GAP.get_center() + Vector2(0, 8)
	bear = Vector2(lerpf(1780.0, gap.x - 10.0, k), FLOOR - BEAR_R + absf(sin(k * 30.0)) * -8.0)
	snake_head = Vector2(lerpf(1840.0, gap.x + 20.0, minf(k * 1.1, 1.0)), FLOOR - 12.0)
	_drag_body()
	bear_a = clampf((1.0 - k) * 4.0, 0.0, 1.0)
	snake_a = clampf((1.0 - k) * 3.0, 0.0, 1.0)


## Тело змеи тянется за головой, как след.
func _drag_body() -> void:
	snake_pts[0] = snake_head
	for i in range(1, snake_pts.size()):
		var d := snake_pts[i] - snake_pts[i - 1]
		if d.length() > 13.0:
			snake_pts[i] = snake_pts[i - 1] + d.normalized() * 13.0
		snake_pts[i].y = minf(snake_pts[i].y + 1.5, FLOOR - 10.0)  # тело провисает к полу


func _process(delta: float) -> void:
	t += delta
	blink = maxf(blink - delta * 5.0, 0.0)
	if eyes > 0.5 and randf() < delta * 0.5:
		blink = 1.0
	if actors:
		actors.queue_redraw()


func _draw_actors() -> void:
	if beam_x > 0.0:  # луч фонаря сверху на пол
		var spot := Vector2(beam_x + sin(t * 2.3) * 30.0, FLOOR - 30.0)
		actors.draw_colored_polygon(PackedVector2Array([Vector2(beam_x + 300.0, 150.0), Vector2(beam_x + 380.0, 150.0),
			spot + Vector2(170, 20), spot + Vector2(-170, 20)]), Color(1, 0.96, 0.7, 0.14))
		Tex.blob(actors, spot, Vector2(360, 80), Color(1, 0.96, 0.75, 0.4))
	if snake_a > 0.0:
		_draw_snake_side()
	if bear_a > 0.0:
		_draw_bear_side()
	if eyes > 0.0:  # в щели — две пары глаз
		var gap := Lab.CABINET_GAP.get_center()
		var open := eyes * (1.0 - blink)
		for pair in [[gap + Vector2(-44, 4), Color(0.25, 0.2, 0.15), 7.0], [gap + Vector2(40, 10), Color(1, 0.85, 0.2), 5.0]]:
			for s in [-1.0, 1.0]:
				var p: Vector2 = pair[0] + Vector2(s * 13.0, 0)
				actors.draw_set_transform(p, 0.0, Vector2(1.0, maxf(open, 0.08)))
				actors.draw_circle(Vector2.ZERO, pair[2], Color(1, 1, 1, eyes))
				actors.draw_circle(Vector2.ZERO, float(pair[2]) * 0.55, Color(pair[1], eyes))
				actors.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Швея сбоку: круглое тело, голова с ушами, фартук с подушечкой для иголок, очки.
func _draw_bear_side() -> void:
	var sq := bear_squash
	var scl := Vector2(1.0 + 0.35 * sq, 1.0 - 0.45 * sq)
	var c := bear
	var a := bear_a
	actors.draw_set_transform(c + Vector2(0, BEAR_R * 0.45 * sq), 0.0, scl * (BEAR_R / 34.0))
	var line := Color(0.2, 0.12, 0.08, a)
	var fur := Color(FUR, a)
	actors.draw_circle(Vector2(0, 6), BEAR_R + 3.0, line)
	actors.draw_circle(Vector2(0, 6), BEAR_R, fur)
	actors.draw_rect(Rect2(-18, -6, 36, 34), Color(0.97, 0.95, 0.9, a))  # фартук
	actors.draw_circle(Vector2(0, 10), 7.0, Color(0.85, 0.2, 0.3, a))  # подушечка
	for k in 3:
		actors.draw_line(Vector2(-4 + k * 4, 6), Vector2(-6 + k * 5, -4), Color(0.8, 0.8, 0.85, a), 1.5)
	var head := Vector2(0, -BEAR_R - 6)
	for s in [-1.0, 1.0]:
		actors.draw_circle(head + Vector2(s * 16, -18), 10.0, line)
		actors.draw_circle(head + Vector2(s * 16, -18), 7.5, fur.darkened(0.2))
	actors.draw_circle(head, 24.0, line)
	actors.draw_circle(head, 21.5, fur)
	actors.draw_circle(head + Vector2(6, 6), 9.0, Color(fur.lightened(0.35), a))
	actors.draw_circle(head + Vector2(10, 4), 3.0, line)
	for s in [-1.0, 1.0]:  # глаза-пуговки и очки
		var e := head + Vector2(s * 8 + 2, -4)
		actors.draw_circle(e, 3.0, line)
		actors.draw_arc(e, 7.0, 0.0, TAU, 12, Color(0.3, 0.3, 0.35, a), 1.5)
	actors.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Змея сбоку: цепочка кружков от хвоста к голове.
func _draw_snake_side() -> void:
	var n := snake_pts.size()
	for i in range(n - 1, -1, -1):
		var r := lerpf(17.0, 8.0, float(i) / n)
		actors.draw_circle(snake_pts[i], r + 2.0, Color(0.06, 0.24, 0.08, snake_a))
		actors.draw_circle(snake_pts[i], r, Color(SNAKE_GREEN if (i / 3) % 2 == 0 else SNAKE_GREEN.darkened(0.12), snake_a))
	var h := snake_head
	actors.draw_circle(h, 21.0, Color(0.06, 0.24, 0.08, snake_a))
	actors.draw_circle(h, 18.5, Color(0.4, 0.86, 0.34, snake_a))
	actors.draw_circle(h + Vector2(7, -6), 5.0, Color(0.98, 0.96, 0.8, snake_a))
	actors.draw_circle(h + Vector2(8.5, -6), 2.8, Color(0.1, 0.1, 0.1, snake_a))


func skip() -> void:
	if done:
		return
	if tw:
		tw.kill()
	g.hud.stop_credits()
	g.hud.hide_title_card(0.1)
	g.hud.hide_caption()
	_finish()


func _finish() -> void:
	if done:
		return
	done = true
	g.sfx.stop_ambient(0.5)
	finished.emit()
