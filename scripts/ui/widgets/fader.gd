extends Range
## Фейдер дизайн-языка 2.0: прорезь в латунной пластине, под ней шкала с рисками, по прорези ходит
## бакелитовый колпачок с белой риской. Пройденная часть прорези подсвечена. Каждый шаг — тихий тик.
## Управление: тянуть колпачок или щёлкнуть по прорези (мышь и палец), колесо, стрелки.

const Design = preload("res://scripts/ui/design.gd")
const Materials = preload("res://scripts/ui/materials.gd")

const H := 44.0
const CAP := Vector2(20, 32)
const PAD := 16.0

var dragging := false
var last_detent := -1


func _init() -> void:
	min_value = 0.0
	max_value = 1.0
	step = 0.05
	custom_minimum_size = Vector2(240, maxf(H, Design.TOUCH_MIN))
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	value_changed.connect(_on_value_changed)
	mouse_entered.connect(grab_focus)
	focus_entered.connect(Design.play.bind("ui_move"))
	focus_exited.connect(queue_redraw)


func _ready() -> void:
	last_detent = detent_index()


func detent_index() -> int:
	return roundi((value - min_value) / maxf(step, 0.0001))


func track() -> Rect2:
	return Rect2(PAD, size.y / 2.0 - 3.0, size.x - PAD * 2.0, 6.0)


func ratio() -> float:
	return clampf((value - min_value) / maxf(max_value - min_value, 0.0001), 0.0, 1.0)


func value_at(x: float) -> float:
	var t := track()
	return min_value + clampf((x - t.position.x) / t.size.x, 0.0, 1.0) * (max_value - min_value)


func _on_value_changed(_v: float) -> void:
	var i := detent_index()
	if i != last_detent:
		last_detent = i
		Design.play("ui_fader")
	queue_redraw()


func nudge(n: int) -> void:
	value = clampf(value + step * n, min_value, max_value)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			dragging = mb.pressed
			if mb.pressed:
				value = value_at(mb.position.x)
				grab_focus()
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			nudge(1)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			nudge(-1)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		value = value_at((event as InputEventMouseMotion).position.x)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		nudge(1)
		accept_event()
	elif event.is_action_pressed("ui_left"):
		nudge(-1)
		accept_event()


func _draw() -> void:
	var t := track()
	# латунная пластина под прорезью
	var plate := Rect2(Vector2(4, size.y / 2.0 - 13.0), Vector2(size.x - 8, 26))
	draw_style_box(Design.cached("fader_plate", func() -> StyleBox:
		var s := Design.key(Materials.Kind.BRASS, Color(0, 0, 0, 0), "normal", Design.RADIUS_SM, 0.0, Vector2.ZERO)
		s.shadow = false
		return s), plate)
	# шкала: риски сверху и снизу прорези
	var n := clampi(int(round((max_value - min_value) / maxf(step, 0.0001))), 4, 20)
	for i in n + 1:
		var x := t.position.x + t.size.x * i / n
		var major := i % 5 == 0 or i == n
		var h := 6.0 if major else 3.5
		draw_line(Vector2(x, plate.position.y + 2), Vector2(x, plate.position.y + 2 + h), Color(0.25, 0.15, 0.04, 0.8), 1.2)
		draw_line(Vector2(x, plate.end.y - 2 - h), Vector2(x, plate.end.y - 2), Color(0.25, 0.15, 0.04, 0.8), 1.2)
	# прорезь
	draw_style_box(Design.cached("fader_slot", func() -> StyleBox: return Design.well(3, Vector2.ZERO)), t)
	var lit := Rect2(t.position, Vector2(t.size.x * ratio(), t.size.y)).grow(-1.0)
	if lit.size.x > 0.0:
		draw_rect(lit, Color(Design.YOLK, 0.55))
	if has_focus():
		draw_style_box(Design.focus_ring(Design.RADIUS_SM, 0.0), plate)
	# колпачок
	var cx := t.position.x + t.size.x * ratio()
	var cap := Rect2(Vector2(cx - CAP.x / 2.0, size.y / 2.0 - CAP.y / 2.0), CAP)
	draw_style_box(Design.cached("fader_cap_%s" % dragging, func() -> StyleBox:
		return Design.key(Materials.Kind.BAKELITE, Color(0, 0, 0, 0), "pressed" if dragging else "normal", 4, 3.0, Vector2.ZERO)), cap)
	for k in 3:  # рифление под палец
		var y := cap.position.y + 6.0 + k * 3.0
		draw_line(Vector2(cap.position.x + 4, y), Vector2(cap.end.x - 4, y), Color(0, 0, 0, 0.35), 1.0)
	draw_line(Vector2(cx, cap.position.y + 15), Vector2(cx, cap.end.y - 6), Design.CREAM, 2.0)
