extends PanelContainer
## Ряд клавиш «как у радиолы» (дизайн-язык 2.0): вкладки настроек и панели разработчика, выбор
## варианта. Клавиши сидят в утопленной бакелитовой рамке; нажатая остаётся утопленной, на ней горит
## лампа, при нажатии соседней она со щелчком выскакивает. Стрелки ←/→ переключают соседей.

signal changed(index: int)

const Design = preload("res://scripts/ui/design.gd")

var buttons: Array[Button] = []
var selected := 0
var _group := ButtonGroup.new()


## fill — клавиши делят ширину рамки поровну (без пустого хвоста справа).
func setup(options: Array, current: int, min_seg_width := 0.0, fill := false) -> void:
	add_theme_stylebox_override("panel", Design.well(Design.RADIUS_SM + 4, Vector2(5, 5)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for i in options.size():
		var b := Button.new()
		b.text = str(options[i])
		b.toggle_mode = true
		b.button_group = _group
		b.theme_type_variation = "SegmentButton"
		b.custom_minimum_size = Vector2(min_seg_width, Design.TOUCH_MIN - 12)
		if fill:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_stretch_ratio = 1.0
		b.pressed.connect(_on_pressed.bind(i))
		b.button_down.connect(Design.play.bind("ui_key_down"))
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
