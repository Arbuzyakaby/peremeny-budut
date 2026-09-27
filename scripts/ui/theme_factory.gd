extends RefCounted
## Сборка темы Godot из дизайн-языка «Ящик экспериментов»: клавиши всех вариантов (бакелит, латунь,
## резина, эмаль, карточка, вкладка), фокус, ползунок, прокрутка, разделитель. Значения — в design.gd.

const Design = preload("res://scripts/ui/design.gd")


static func build() -> Theme:
	var th := Theme.new()
	th.default_font = Design.font("body")
	th.default_font_size = Design.size_of("body")
	th.set_stylebox("panel", "PanelContainer", Design.panel_style())
	th.set_stylebox("panel", "Panel", Design.panel_style())
	_key_styles(th, "Button", Design.Materials.Kind.BAKELITE, Design.CREAM, Color.WHITE)
	_key_styles(th, "PrimaryButton", Design.Materials.Kind.BRASS, Design.INK, Design.INK)
	_key_styles(th, "GhostButton", Design.Materials.Kind.RUBBER, Design.MUTED, Design.CREAM, 2.0)
	_key_styles(th, "DangerButton", Design.Materials.Kind.ENAMEL, Design.CREAM, Color.WHITE)
	_key_styles(th, "CardButton", Design.Materials.Kind.BAKELITE, Design.CREAM, Color.WHITE)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		th.set_stylebox(st, "CardButton", Design.card_style(Design.LINE_STRONG if st == "normal" else Design.YOLK, st, Design.RADIUS_MD, Vector2(Design.SPACE[2], Design.SPACE[2])))
	# клавиши-вкладки «как у радиолы»: нажатая остаётся утопленной, на ней горит лампа
	_key_styles(th, "SegmentButton", Design.Materials.Kind.BAKELITE, Design.MUTED, Design.CREAM, 3.0, Design.RADIUS_SM, Vector2(Design.SPACE[4], Design.SPACE[2]))
	for st in ["pressed", "hover_pressed"]:
		var on := Design.key(Design.Materials.Kind.BAKELITE, Color(0, 0, 0, 0), st, Design.RADIUS_SM, 3.0, Vector2(Design.SPACE[4], Design.SPACE[2]))
		on.lamp = Design.YOLK
		on.lamp_left = true
		th.set_stylebox(st, "SegmentButton", on)
	th.set_color("font_pressed_color", "SegmentButton", Design.YOLK)
	th.set_color("font_hover_pressed_color", "SegmentButton", Design.YOLK)
	th.set_font_size("font_size", "SegmentButton", 15)
	for v in ["PrimaryButton", "GhostButton", "DangerButton", "SegmentButton", "CardButton"]:
		th.set_type_variation(v, "Button")
	# ползунок (запасной — в интерфейсе вместо него фейдеры и крутилки)
	th.set_stylebox("slider", "HSlider", Design.well(Design.RADIUS_PILL, Vector2(0, 5)))
	var fill := Design.key(Design.Materials.Kind.BRASS, Color(0, 0, 0, 0), "normal", Design.RADIUS_PILL, 0.0, Vector2(0, 5))
	fill.shadow = false
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_stylebox("focus", "HSlider", Design.focus_ring(Design.RADIUS_PILL, 0.0))
	th.set_icon("grabber", "HSlider", Design.knob_texture(24, false))
	th.set_icon("grabber_highlight", "HSlider", Design.knob_texture(26, true))
	# прокрутка — латунный бегунок в утопленной щели
	th.set_stylebox("scroll", "VScrollBar", Design.well(Design.RADIUS_PILL, Vector2(3, 3)))
	var grab := Design.key(Design.Materials.Kind.BRASS, Color(0, 0, 0, 0), "normal", Design.RADIUS_PILL, 0.0, Vector2(3, 3))
	grab.shadow = false
	var grab_hi := Design.key(Design.Materials.Kind.BRASS, Color(0, 0, 0, 0), "hover", Design.RADIUS_PILL, 0.0, Vector2(3, 3))
	grab_hi.shadow = false
	th.set_stylebox("grabber", "VScrollBar", grab)
	th.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	th.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
	th.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var sep := StyleBoxLine.new()  # разделитель — фрезерованная канавка
	sep.color = Color(0, 0, 0, 0.45)
	sep.thickness = 2
	th.set_stylebox("separator", "HSeparator", sep)
	th.set_constant("separation", "HSeparator", Design.SPACE[4])
	th.set_color("font_color", "Label", Design.CREAM)
	th.set_font("font", "TooltipLabel", Design.font("body"))
	return th


static func _key_styles(th: Theme, type: String, material: int, text: Color, text_hover: Color,
		travel := Design.KEY_TRAVEL, radius := Design.RADIUS_MD, pad := Vector2(Design.SPACE[5], Design.SPACE[3])) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		th.set_stylebox(st, type, Design.key(material, Color(0, 0, 0, 0), st, radius, travel, pad))
	th.set_stylebox("focus", type, Design.focus_ring(radius, travel))
	th.set_font("font", type, Design.font("heavy"))
	th.set_font_size("font_size", type, 19)
	th.set_color("font_color", type, text)
	th.set_color("font_focus_color", type, text_hover)
	th.set_color("font_hover_color", type, text_hover)
	th.set_color("font_pressed_color", type, text_hover)
	th.set_color("font_hover_pressed_color", type, text_hover)
	th.set_color("font_disabled_color", type, Color(text, 0.4))
	# гравировка: светлый отсвет вокруг букв на латуни, тёмный — на бакелите и эмали
	th.set_color("font_outline_color", type, Color(1, 1, 1, 0.2) if text == Design.INK else Color(0, 0, 0, 0.45))
	th.set_constant("outline_size", type, 2)
