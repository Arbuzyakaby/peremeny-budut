extends RefCounted
## Витрина дизайн-языка «Ящик экспериментов» (вкладка UI-КИТ панели разработчика):
## палитра, типографика, кнопки, тумблер, сегменты, ползунок, бейджи, полосы, иконки.

const Design = preload("res://scripts/ui/design.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Segmented = preload("res://scripts/ui/widgets/segmented.gd")
const ToggleSwitch = preload("res://scripts/ui/widgets/toggle_switch.gd")

const SWATCHES := [
	["surface-1", Design.SURFACE_1], ["surface-2", Design.SURFACE_2], ["surface-3", Design.SURFACE_3],
	["line", Design.LINE], ["cream", Design.CREAM], ["muted", Design.MUTED],
	["yolk", Design.YOLK], ["mint", Design.MINT], ["tomato", Design.TOMATO],
	["steel", Design.STEEL], ["rust", Design.RUST], ["plum", Design.PLUM],
]


static func build(p: VBoxContainer) -> void:
	p.add_child(Design.label("ПАЛИТРА", "overline", Design.YOLK))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", Design.SPACE[2])
	grid.add_theme_constant_override("v_separation", Design.SPACE[2])
	for sw in SWATCHES:
		var chip := PanelContainer.new()
		var col: Color = sw[1]
		chip.add_theme_stylebox_override("panel", Design.box(Color(col, 1.0), Design.LINE, Design.RADIUS_SM, 1, Vector2(8, 6)))
		chip.custom_minimum_size = Vector2(130, 40)
		var dark := col.get_luminance() > 0.55
		chip.add_child(Design.label(sw[0], "caption", Design.INK if dark else Design.CREAM))
		grid.add_child(chip)
	p.add_child(grid)

	p.add_child(Design.label("ТИПОГРАФИКА", "overline", Design.YOLK))
	for role in ["h1", "h2", "h3", "body", "small", "caption"]:
		var l := Design.label("%s — Змея ест медведей" % role, role, Design.CREAM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.add_child(l)

	p.add_child(Design.label("КНОПКИ", "overline", Design.YOLK))
	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.add_theme_constant_override("h_separation", Design.SPACE[2])
	buttons.add_theme_constant_override("v_separation", Design.SPACE[2])
	for v in [["ГЛАВНАЯ", "Primary"], ["ОБЫЧНАЯ", ""], ["ТИХАЯ", "Ghost"], ["ОПАСНАЯ", "Danger"]]:
		var b := Design.button(v[0], func() -> void: pass, v[1], Vector2(190, Design.TOUCH_MIN))
		buttons.add_child(b)
	p.add_child(buttons)

	p.add_child(Design.label("ПЕРЕКЛЮЧАТЕЛИ", "overline", Design.YOLK))
	var row := Design.hbox(Design.SPACE[3], BoxContainer.ALIGNMENT_BEGIN)
	var t1 := ToggleSwitch.new()
	t1.set_on(true)
	row.add_child(t1)
	row.add_child(ToggleSwitch.new())
	var seg := Segmented.new()
	seg.setup(["НИЗКО", "СРЕДНЕ", "ВЫСОКО"], 1)
	row.add_child(seg)
	p.add_child(row)
	var slider := HSlider.new()
	slider.value = 0.6
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(300, 36)
	p.add_child(slider)

	p.add_child(Design.label("БЕЙДЖИ И ПОЛОСЫ", "overline", Design.YOLK))
	var chips := Design.hbox(Design.SPACE[2], BoxContainer.ALIGNMENT_BEGIN)
	chips.add_child(Design.chip("НОРМАЛЬНАЯ", Design.YOLK))
	chips.add_child(Design.chip("DEV", Design.PLUM))
	chips.add_child(Design.chip("РЕКОРД", Design.MINT))
	chips.add_child(Design.chip("УРОН", Design.TOMATO))
	p.add_child(chips)
	var bars := Control.new()
	bars.custom_minimum_size = Vector2(0, 60)
	bars.draw.connect(func() -> void:
		Design.draw_bar(bars, Rect2(4, 8, 300, 10), 0.7, Design.MINT)
		Design.draw_bar(bars, Rect2(4, 32, 300, 14), 0.45, Design.YOLK, 0.62))
	p.add_child(bars)

	p.add_child(Design.label("ИКОНКИ", "overline", Design.YOLK))
	var icons := Control.new()
	icons.custom_minimum_size = Vector2(0, 90)
	icons.draw.connect(func() -> void:
		var x := 20.0
		for i in 4:
			Icons.stage(icons, Vector2(x, 20), i)
			x += 44.0
		Icons.heart(icons, Vector2(x, 20), 11.0, Color(0.95, 0.15, 0.25))
		Icons.shield(icons, Vector2(x + 44, 20), 13.0)
		Icons.scale_coin(icons, Vector2(x + 88, 20))
		x = 20.0
		for f in [Icons.pause, Icons.gear, Icons.arrow_back, Icons.lock, Icons.check, Icons.bolt, Icons.code]:
			f.call(icons, Vector2(x, 66), Design.CREAM, 1.0)
			x += 44.0)
	p.add_child(icons)
