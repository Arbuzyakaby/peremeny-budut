extends PanelContainer
## Сегментированный переключатель: вкладки настроек и значения-варианты («НИЗКО / СРЕДНЕ / ВЫСОКО»).
## Выбранный сегмент — золотая «таблетка». Стрелки ←/→ переключают соседей.

signal changed(index: int)

const Design = preload("res://scripts/ui/design.gd")

var buttons: Array[Button] = []
var selected := 0
var _group := ButtonGroup.new()


func setup(options: Array, current: int, min_seg_width := 0.0) -> void:
	add_theme_stylebox_override("panel", Design.box(Design.SURFACE_0, Design.LINE, Design.RADIUS_PILL, 1, Vector2(4, 4)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	add_child(row)
	for i in options.size():
		var b := Button.new()
		b.text = str(options[i])
		b.toggle_mode = true
		b.button_group = _group
		b.theme_type_variation = "SegmentButton"
		b.custom_minimum_size = Vector2(min_seg_width, Design.TOUCH_MIN - 12)
		b.pressed.connect(_on_pressed.bind(i))
		b.focus_entered.connect(Design.play.bind("ui_move"))
		b.mouse_entered.connect(b.grab_focus)
		row.add_child(b)
		buttons.append(b)
	select(current)


func select(i: int) -> void:
	selected = clampi(i, 0, buttons.size() - 1)
	for k in buttons.size():
		buttons[k].set_pressed_no_signal(k == selected)


func _on_pressed(i: int) -> void:
	if i == selected:
		return
	selected = i
	Design.play("ui_toggle")
	changed.emit(i)
