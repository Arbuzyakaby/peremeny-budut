extends Node
## Пересадка образца №48 (v10.0), продолжение финала после вылупления. Утро: учёный возвращается,
## включает свет и решает переселить змейку в чистый ящик. Щепоть пальцев опускается и поднимает её —
## дальше мы смотрим глазами змейки: веки моргают, а между морганиями мелькает лаборатория —
## банки с образцами, окно, лицо учёного снизу, новый ящик «ОБРАЗЕЦ №48». Веки смыкаются — done.

signal done

const Lab = preload("res://scripts/ending/lab.gd")

const SKIN := Color(0.93, 0.8, 0.7)
const LINE := Color(0.14, 0.14, 0.17)
const LAB_VIEW_POS := Vector2(1600, 60)
const LAB_VIEW_ZOOM := Vector2(0.25, 0.25)

var ending  # ending.gd
var lab: Lab
var baby
var camera: Camera2D
var pinch: Node2D
var eye_layer: CanvasLayer
var eye: Control
var pinch_pos := Vector2(640, -600)
var pinch_close := 0.0
var carrying := false
var lids := 1.0     # 1 — глаза открыты, 0 — закрыты (вид змейки)
var pov := false
var tw: Tween
var t := 0.0


func start(e) -> void:
	ending = e
	lab = e.lab
	baby = e.baby
	camera = e.camera
	pinch = Node2D.new()
	pinch.z_as_relative = false
	pinch.z_index = 46
	pinch.draw.connect(_draw_pinch)
	e.game.world.add_child(pinch)
	eye_layer = CanvasLayer.new()
	eye_layer.layer = 6
	add_child(eye_layer)
	eye = Control.new()
	eye.set_anchors_preset(Control.PRESET_FULL_RECT)
	eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eye.draw.connect(_draw_eye)
	eye_layer.add_child(eye)
	var egg_pos: Vector2 = baby.head_pos
	pinch_pos = egg_pos + Vector2(0, -700)
	lab.show_new_box = true
	tw = create_tween()
	# утро: свет, учёный возвращается
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		ending.in_dark = false
		lab.lights = 1.0
		ending.sfx.play("lamp_click")
		ending.hud.show_caption("", "Утро. Лаборатория НИИ."))
	tw.tween_property(ending.darkness, "color", Color.WHITE, 1.2)
	tw.parallel().tween_property(camera, "position", LAB_VIEW_POS, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(camera, "zoom", LAB_VIEW_ZOOM, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_callback(func() -> void: lab.walking = true).set_delay(0.3)
	tw.parallel().tween_property(lab, "sx", Lab.STAND_X, 3.0).set_delay(0.3)
	tw.parallel().tween_property(lab, "hand", Vector2(Lab.STAND_X - 560, 700), 3.0).set_delay(0.3)
	tw.tween_callback(func() -> void:
		lab.walking = false
		lab.look = egg_pos
		ending.hud.hide_caption())
	tw.tween_interval(0.4)
	tw.tween_callback(ending._say.bind("Образец №48. Вылупился в золе. Живучий.", 2.6))
	tw.tween_interval(3.2)
	tw.tween_callback(ending._say.bind("Переселить в чистый ящик. Протокол начнём заново.", 2.8))
	tw.tween_interval(3.3)
	# щепоть: камера к змейке, пальцы опускаются
	tw.tween_callback(func() -> void: ending.hud.hide_caption())
	tw.tween_property(camera, "position", egg_pos + Vector2(0, -40), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(camera, "zoom", Vector2(2.2, 2.2), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(self, "pinch_pos", egg_pos + Vector2(0, -4), 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "pinch_close", 1.0, 0.3)
	tw.tween_callback(func() -> void:
		carrying = true
		baby.autopilot = false
		ending.sfx.play("pop", 1.3))
	tw.tween_property(self, "pinch_pos", egg_pos + Vector2(0, -260), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# глазами змейки: моргание — кадр — моргание
	tw.tween_callback(func() -> void: pov = true)
	tw.tween_property(self, "lids", 0.0, 0.18)
	_shot(Lab.CABINET.get_center() + Vector2(0, 200), Vector2(0.55, 0.55), Vector2(-160, 0), 1.5, "")
	_shot(Lab.WINDOW.get_center(), Vector2(0.55, 0.55), Vector2(120, 40), 1.2, "")
	_shot(lab.head_pos() + Vector2(0, 140), Vector2(0.62, 0.62), Vector2(0, -60), 1.6, "Тише, тише. Не кусаться.")
	_shot(Lab.NEW_BOX.get_center() + Vector2(0, -60), Vector2(0.9, 0.9), Vector2(0, 60), 1.4, "")
	# опустили в новый ящик — веки смыкаются
	tw.tween_callback(func() -> void:
		carrying = false
		pinch.visible = false
		baby.visible = true
		var drop := Lab.NEW_BOX.get_center() + Vector2(-40, -110)
		baby.reset(drop)
		baby.autopilot = true
		baby.bounds = Rect2(drop - Vector2(80, 30), Vector2(160, 60))
		ending.hud.hide_caption())
	tw.tween_property(self, "lids", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.2)
	tw.tween_callback(done.emit)


## Кадр глазами змейки: веки открываются, камера плывёт от pos на drift, веки закрываются.
func _shot(pos: Vector2, zoom: Vector2, drift: Vector2, time: float, line: String) -> void:
	tw.tween_callback(func() -> void:
		camera.position = pos - drift * 0.5
		camera.zoom = zoom
		baby.visible = false
		lab.look = camera.position if line != "" else lab.look
		if line != "":
			ending._say(line, 1.6))
	tw.tween_property(self, "lids", 1.0, 0.22).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(camera, "position", pos + drift * 0.5, time)
	tw.tween_property(self, "lids", 0.0, 0.16).set_ease(Tween.EASE_IN)


func _process(delta: float) -> void:
	t += delta
	if carrying and baby:  # змейка болтается в щепоти
		baby.glide_to(pinch_pos + Vector2(0, 20) + Vector2(sin(t * 7.0), 0) * 3.0, delta)
	if pinch:
		pinch.queue_redraw()
	if eye:
		eye.queue_redraw()


## Большой и указательный пальцы сверху (мир): сходятся, когда хватают.
func _draw_pinch() -> void:
	if pinch_pos.y < -500.0:
		return
	var gap := lerpf(46.0, 10.0, pinch_close)
	for s in [-1.0, 1.0]:
		var tip: Vector2 = pinch_pos + Vector2(s * gap, 0)
		var base: Vector2 = tip + Vector2(s * 60.0, -260.0)
		pinch.draw_line(base, tip, LINE, 44.0)
		pinch.draw_line(base, tip, SKIN, 36.0)
		pinch.draw_circle(tip, 22.0, LINE)
		pinch.draw_circle(tip, 18.0, SKIN)
		pinch.draw_circle(tip + Vector2(-s * 4.0, 6.0), 9.0, Color(0.98, 0.9, 0.85))  # ноготь


## Веки змейки: сверху и снизу — тьма, между ними — вытянутое окно взгляда.
func _draw_eye() -> void:
	if not pov:
		return
	var size := eye.size
	if size.x < 8.0 or size.y < 8.0:  # окно ещё не разложено (или без экрана) — рисовать не во что
		return
	if lids < 0.04:  # веки сомкнуты — дуги вырождаются в прямую, рисуем просто тьму
		eye.draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		return
	var c := size / 2.0
	var half := Vector2(size.x * 0.62, size.y * 0.62 * lids)
	# веки — полосами по строкам: вне эллипса взгляда темно (многоугольник с острыми углами на стыке
	# кромки и дуги не триангулируется)
	var row := 4.0
	var y := 0.0
	while y < size.y:
		var dy := (y + row / 2.0 - c.y) / half.y
		if absf(dy) >= 1.0:
			eye.draw_rect(Rect2(0, y, size.x, row), Color.BLACK)
		else:
			var w := half.x * sqrt(1.0 - dy * dy)
			eye.draw_rect(Rect2(0, y, maxf(c.x - w, 0.0), row), Color.BLACK)
			eye.draw_rect(Rect2(c.x + w, y, maxf(size.x - c.x - w, 0.0), row), Color.BLACK)
		y += row
	for k in 4:  # ресничный край век — мягкая кромка
		var h2 := half.y + 6.0 + k * 6.0
		var edge := PackedVector2Array()
		for i in 17:
			var a := PI * i / 16.0
			edge.append(c + Vector2(cos(a) * half.x, -sin(a) * h2))
		eye.draw_polyline(edge, Color(0, 0, 0, 0.25), 8.0)


func _exit_tree() -> void:
	if is_instance_valid(pinch):
		pinch.queue_free()
