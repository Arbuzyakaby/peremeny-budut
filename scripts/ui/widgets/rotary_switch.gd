extends Control
## Галетный переключатель дизайн-языка 2.0 (выбор из 2–4 вариантов в настройках): бакелитовая ручка-
## «клюв» с положениями по дуге, у каждого — точка-лампа; справа — окошко-шильдик с названием
## выбранного положения. Щелчок — следующее положение (правый — предыдущее), колесо, стрелки,
## перетаскивание вбок. Каждый щелчок — глухой «клац» галетника.
## API совпадает с Segmented: setup(), select(), selected, сигнал changed.

signal changed(index: int)

const Design = preload("res://scripts/ui/design.gd")
const Materials = preload("res://scripts/ui/materials.gd")

const KNOB := 46.0
const ARC := PI * 0.9           # дуга положений

var options: Array = []
var selected := 0
var shown := 0.0                # угол ручки (анимируется)
var window_w := 124.0
var dragging := false
var drag_x := 0.0


func setup(opts: Array, current: int, _min_seg_width := 0.0) -> void:
	options = opts
	var font := Design.font("heavy")
	var widest := 0.0
	for o in opts:
		widest = maxf(widest, font.get_string_size(str(o), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
	window_w = maxf(widest + 28.0, 84.0)
	custom_minimum_size = Vector2(KNOB + 22.0 + window_w, maxf(KNOB + 14.0, Design.TOUCH_MIN))
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not mouse_entered.is_connected(grab_focus):
		mouse_entered.connect(grab_focus)
		focus_entered.connect(Design.play.bind("ui_move"))
		focus_exited.connect(queue_redraw)
	select(current)
	shown = position_angle(selected)


func select(i: int) -> void:
	selected = clampi(i, 0, maxi(options.size() - 1, 0))
	queue_redraw()


func position_angle(i: int) -> float:
	var n := maxi(options.size() - 1, 1)
	return -PI / 2.0 - ARC / 2.0 + ARC * float(i) / n


## Повернуть на шаг (с упором в крайних положениях, как у настоящего галетника).
func turn(dir: int) -> void:
	var to := clampi(selected + dir, 0, options.size() - 1)
	if to == selected:
		Design.play("ui_error")
		return
	_go(to)


## Щелчок: следующее положение, после последнего — обратно к первому.
func cycle() -> void:
	_go((selected + 1) % maxi(options.size(), 1))


func _go(i: int) -> void:
	selected = i
	Design.play("ui_rotary")
	changed.emit(i)
	if Design.Settings.flag("reduced_motion") or not is_inside_tree():
		shown = position_angle(i)
		queue_redraw()
		return
	create_tween().tween_method(func(a: float) -> void:
		shown = a
		queue_redraw(), shown, position_angle(i), Design.FAST * 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			dragging = true
			drag_x = mb.position.x
			grab_focus()
			accept_event()
		elif not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and dragging:
			dragging = false
			if absf(mb.position.x - drag_x) < 8.0:
				cycle()
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			turn(-1)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			turn(1)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			turn(-1)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		var dx := (event as InputEventMouseMotion).position.x - drag_x
		if absf(dx) > 34.0:
			turn(1 if dx > 0.0 else -1)
			drag_x = (event as InputEventMouseMotion).position.x
		accept_event()
	elif event.is_action_pressed("ui_right"):
		turn(1)
		accept_event()
	elif event.is_action_pressed("ui_left"):
		turn(-1)
		accept_event()


func _draw() -> void:
	var c := Vector2(KNOB / 2.0 + 8.0, size.y / 2.0 + 4.0)
	var r := KNOB * 0.36
	if has_focus():
		draw_arc(c, r + 14.0, 0, TAU, 40, Color(Design.YOLK, 0.35), 3.0, true)
	# точки-лампы положений
	for i in options.size():
		var d := Vector2.from_angle(position_angle(i))
		var p := c + d * (r + 9.0)
		var on := i == selected
		draw_circle(p, 3.6, Color(0, 0, 0, 0.55))
		draw_circle(p, 2.6, Design.YOLK if on else Color(0.3, 0.2, 0.1))
		if on:
			draw_circle(p, 6.0, Color(Design.YOLK, 0.25))
	# ручка-«клюв»
	draw_circle(c + Vector2(1.5, 3), r + 1.0, Color(0, 0, 0, 0.45))
	draw_circle(c, r, Color(0.09, 0.06, 0.04))
	draw_circle(c + Vector2(-1, -1), r - 1.5, Color(0.22, 0.15, 0.1))
	draw_circle(c + Vector2(-3, -3), r * 0.5, Color(0.4, 0.28, 0.18, 0.6))
	var d0 := Vector2.from_angle(shown)
	var side := d0.orthogonal()
	var beak := PackedVector2Array([c + side * 7.0 - d0 * 4.0, c + d0 * (r + 5.0), c - side * 7.0 - d0 * 4.0])
	draw_colored_polygon(beak, Color(0.14, 0.09, 0.06))
	draw_line(c, c + d0 * (r + 2.0), Design.CREAM, 2.0)
	# окошко-шильдик
	var win := Rect2(Vector2(KNOB + 18.0, size.y / 2.0 - 15.0), Vector2(window_w, 30))
	draw_style_box(Design.cached("rot_window", func() -> StyleBox: return Design.well(6, Vector2.ZERO)), win)
	if options.is_empty():
		return
	var text := str(options[selected])
	var font := Design.font("heavy")
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var tp := win.position + Vector2((win.size.x - tw) / 2.0, 21)
	draw_string(font, tp + Vector2(0, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.6))
	draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Design.YOLK)
	draw_line(win.position + Vector2(6, 4), win.position + Vector2(win.size.x - 6, 4), Color(1, 1, 1, 0.08), 2.0)  # стекло
