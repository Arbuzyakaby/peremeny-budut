extends Button
## Рычажный тумблер дизайн-языка 2.0: хромированный рычажок с шариком на конце в латунной шайбе,
## на бакелитовой пластине с гравировкой «0 / I»; рядом лампочка — горит желтком, когда включено.
## Рычажок перекидывается с упругим «перелётом», звук — сухой щелчок. Мышь, тач, Enter/Пробел.

const Design = preload("res://scripts/ui/design.gd")
const Materials = preload("res://scripts/ui/materials.gd")

const W := 84.0
const H := 40.0

var knob := 0.0  # 0 — выкл, 1 — вкл (анимируется, может «перелетать» за 1)


func _init() -> void:
	toggle_mode = true
	flat = true
	custom_minimum_size = Vector2(W + 8, maxf(H + 8, Design.TOUCH_MIN))
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	toggled.connect(_on_toggled)
	mouse_entered.connect(grab_focus)
	focus_entered.connect(Design.play.bind("ui_move"))


func set_on(on: bool) -> void:
	set_pressed_no_signal(on)
	knob = 1.0 if on else 0.0
	queue_redraw()


func _on_toggled(on: bool) -> void:
	Design.play("ui_lever")
	if Design.Settings.flag("reduced_motion"):
		knob = 1.0 if on else 0.0
		queue_redraw()
		return
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		knob = k
		queue_redraw(), knob, 1.0 if on else 0.0, Design.BASE * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Угол рычажка: -1 — влево (выкл), +1 — вправо (вкл).
func lever_angle() -> float:
	return lerpf(-0.75, 0.75, knob)


func _draw() -> void:
	var r := Rect2((size - Vector2(W, H)) / 2.0, Vector2(W, H))
	if has_focus():
		draw_style_box(Design.focus_ring(Design.RADIUS_SM, 2.0), r)
	# пластина с гравировкой
	draw_style_box(Design.cached("toggle_plate", func() -> StyleBox:
		var s := Design.key(Materials.Kind.BAKELITE, Color(0, 0, 0, 0), "normal", Design.RADIUS_SM, 2.0, Vector2.ZERO)
		return s), r)
	var font := Design.font("heavy")
	var eng := Color(0, 0, 0, 0.55)
	# гравировка — у нижней кромки, по бокам от шайбы: рычажок её не закрывает
	draw_string(font, r.position + Vector2(7, H - 7 + 1), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.12))
	draw_string(font, r.position + Vector2(7, H - 7), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, eng.lerp(Design.FAINT, 0.6))
	draw_string(font, r.position + Vector2(W - 32, H - 7 + 1), "I", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.12))
	draw_string(font, r.position + Vector2(W - 32, H - 7), "I", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, eng.lerp(Design.FAINT, 0.6))
	# лампочка
	var lp := r.position + Vector2(W - 12, H / 2.0 - 1)
	var on_k := clampf(knob, 0.0, 1.0)
	draw_circle(lp, 6.0, Color(0, 0, 0, 0.5))
	draw_circle(lp, 4.6, Color(0.25, 0.15, 0.05).lerp(Design.YOLK, on_k))
	if on_k > 0.05:
		draw_circle(lp, 9.0, Color(Design.YOLK, 0.25 * on_k))
	draw_circle(lp + Vector2(-1.3, -1.3), 1.4, Color(1, 1, 1, 0.3 + 0.5 * on_k))
	# латунная шайба
	var pivot := r.position + Vector2(W / 2.0 - 4, H / 2.0 + 4)
	draw_circle(pivot + Vector2(0, 1.5), 10.5, Color(0, 0, 0, 0.45))
	draw_circle(pivot, 10.0, Color(0.42, 0.27, 0.08))
	draw_circle(pivot + Vector2(-1, -1), 8.5, Color(0.86, 0.64, 0.25))
	draw_circle(pivot + Vector2(-2.5, -2.5), 4.0, Color(1, 0.9, 0.58, 0.8))
	draw_circle(pivot, 4.2, Color(0.2, 0.14, 0.08))
	# рычажок: сужающийся хромированный стержень с шариком, тень падает вниз-вправо
	var dir := Vector2.from_angle(-PI / 2.0 + lever_angle())
	var tip := pivot + dir * 16.0
	var side := dir.orthogonal()
	var shadow := PackedVector2Array([pivot + side * 3.2 + Vector2(3, 4), tip + side * 1.8 + Vector2(5, 6),
		tip - side * 1.8 + Vector2(5, 6), pivot - side * 3.2 + Vector2(3, 4)])
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
	var rod := PackedVector2Array([pivot + side * 3.2, tip + side * 2.0, tip - side * 2.0, pivot - side * 3.2])
	draw_colored_polygon(rod, Color(0.4, 0.42, 0.46))
	draw_line(pivot + side * 1.2, tip + side * 0.8, Color(0.95, 0.96, 1.0), 1.6)
	draw_circle(tip, 5.2, Color(0.28, 0.29, 0.32))
	draw_circle(tip + Vector2(-0.6, -0.6), 4.3, Color(0.75, 0.77, 0.8))
	draw_circle(tip + Vector2(-1.8, -1.8), 1.7, Color(1, 1, 1, 0.9))
