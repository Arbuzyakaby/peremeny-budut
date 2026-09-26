extends Button
## Тумблер дизайн-языка: «таблетка» с бегунком. Включённый — золотой. Мышь, тач, Enter/Пробел.

const Design = preload("res://scripts/ui/design.gd")

const W := 64.0
const H := 34.0

var knob := 0.0  # 0 — выкл, 1 — вкл (анимируется)


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
	Design.play("ui_toggle")
	if Design.Settings.flag("reduced_motion"):
		knob = 1.0 if on else 0.0
		queue_redraw()
		return
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		knob = k
		queue_redraw(), knob, 1.0 if on else 0.0, Design.BASE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var r := Rect2((size - Vector2(W, H)) / 2.0, Vector2(W, H))
	var track := Design.SURFACE_0.lerp(Design.YOLK_DEEP, knob)
	var border := Design.LINE.lerp(Design.YOLK, knob)
	if has_focus():
		draw_style_box(Design.focus_ring(Design.RADIUS_PILL), r)
	draw_style_box(Design.box(track, border, Design.RADIUS_PILL, 2, Vector2.ZERO), r)
	var kc := r.position + Vector2(H / 2.0 + (W - H) * knob, H / 2.0)
	draw_circle(kc + Vector2(0, 2), H / 2.0 - 4.0, Color(0, 0, 0, 0.3))
	draw_circle(kc, H / 2.0 - 4.0, Design.CREAM.lerp(Color.WHITE, knob))
	if knob > 0.5:
		draw_polyline(PackedVector2Array([kc + Vector2(-4, 0), kc + Vector2(-1, 3), kc + Vector2(4, -3)]),
			Design.YOLK_DEEP, 2.0)
