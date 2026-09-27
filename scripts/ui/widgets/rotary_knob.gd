extends Range
## Крутилка дизайн-языка 2.0 (громкости): накатанная латунная ручка с риской, шкала из рисок
## по дуге 270°, пройденные риски светятся лампами желтка. Каждый шаг — щелчок-детент.
## Управление: тянуть вверх/вниз (мышь и палец), колесо, стрелки; двойной щелчок — по умолчанию.

const Design = preload("res://scripts/ui/design.gd")

const D := 64.0
const SWEEP := PI * 1.5
const START := PI * 0.75       # угол нуля: «семь часов»
const DRAG_PIXELS := 160.0     # столько пикселей по вертикали — весь диапазон

var default_value := -1.0
var dragging := false
var drag_from := Vector2.ZERO
var drag_value := 0.0
var last_detent := -1
var _last_click := 0


func _init() -> void:
	min_value = 0.0
	max_value = 1.0
	step = 0.05
	custom_minimum_size = Vector2(D + 8, maxf(D + 4, Design.TOUCH_MIN))
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_VSIZE
	value_changed.connect(_on_value_changed)
	mouse_entered.connect(grab_focus)
	focus_entered.connect(Design.play.bind("ui_move"))
	focus_exited.connect(queue_redraw)


func _ready() -> void:
	last_detent = detent_index()


func detent_index() -> int:
	return roundi((value - min_value) / maxf(step, 0.0001))


func ratio_of(v: float) -> float:
	return clampf((v - min_value) / maxf(max_value - min_value, 0.0001), 0.0, 1.0)


func angle_of(v: float) -> float:
	return START + SWEEP * ratio_of(v)


func _on_value_changed(_v: float) -> void:
	var i := detent_index()
	if i != last_detent:
		last_detent = i
		Design.play("ui_detent")
	queue_redraw()


## Сдвинуть на n шагов (колесо, стрелки).
func nudge(n: int) -> void:
	value = clampf(value + step * n, min_value, max_value)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if Time.get_ticks_msec() - _last_click < 300 and default_value >= 0.0:  # двойной щелчок — сброс
					value = default_value
				_last_click = Time.get_ticks_msec()
				dragging = true
				drag_from = mb.position
				drag_value = value
				grab_focus()
			else:
				dragging = false
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			nudge(1)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			nudge(-1)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		var dy := drag_from.y - mm.position.y + (mm.position.x - drag_from.x) * 0.5
		value = clampf(drag_value + dy / DRAG_PIXELS * (max_value - min_value), min_value, max_value)
		accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_up"):
		nudge(1)
		accept_event()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_down"):
		nudge(-1)
		accept_event()


func _draw() -> void:
	var c := size / 2.0
	var r := D * 0.34
	if has_focus():
		draw_arc(c, r + 12.0, 0, TAU, 40, Color(Design.YOLK, 0.35), 3.0, true)
	# шкала: риски по дуге, пройденные — горят
	var n := clampi(int(round((max_value - min_value) / maxf(step, 0.0001))), 4, 20)
	var lit := ratio_of(value)
	for i in n + 1:
		var k := float(i) / n
		var a := START + SWEEP * k
		var d := Vector2.from_angle(a)
		var major := i % 5 == 0 or i == n
		var col := Design.YOLK if k <= lit + 0.001 else Color(0, 0, 0, 0.55)
		if k <= lit + 0.001:
			draw_line(c + d * (r + 5.0), c + d * (r + (10.0 if major else 8.0)), Color(Design.YOLK, 0.25), 5.0)
		draw_line(c + d * (r + 5.0), c + d * (r + (10.0 if major else 8.0)), col, 2.0 if major else 1.4)
	# тень ручки и юбка
	draw_circle(c + Vector2(1.5, 3.0), r + 1.5, Color(0, 0, 0, 0.45))
	draw_circle(c, r + 1.0, Color(0.3, 0.19, 0.06))
	# накатка по краю
	var ang := angle_of(value)
	for i in 36:
		var a := ang + TAU * i / 36.0
		var d := Vector2.from_angle(a)
		var shade := 0.5 + 0.5 * d.dot(Vector2(-0.6, -0.8))
		draw_line(c + d * (r - 3.5), c + d * r, Color(0.45, 0.3, 0.1).lerp(Color(1, 0.88, 0.55), shade), 2.0)
	# колпачок с радиальным бликом
	draw_circle(c, r - 4.0, Color(0.55, 0.38, 0.13))
	draw_circle(c + Vector2(-1, -1), r - 5.5, Color(0.8, 0.6, 0.24))
	draw_circle(c + Vector2(-3, -3), r * 0.45, Color(1, 0.9, 0.6, 0.55))
	draw_circle(c + Vector2(-4, -4), r * 0.18, Color(1, 1, 1, 0.5))
	# риска-указатель
	var d := Vector2.from_angle(ang)
	draw_line(c + d * 3.0, c + d * (r - 5.0), Color(0.15, 0.08, 0.02), 3.5)
	draw_line(c + d * 3.0, c + d * (r - 5.0), Design.CREAM, 1.6)
	draw_circle(c + d * (r - 7.0), 2.2, Design.YOLK)
