extends RefCounted
## Витрина дизайн-языка «Ящик экспериментов» 2.0 (вкладка UI-КИТ панели разработчика): палитра,
## материалы, типографика, клавиши, рычажные тумблеры, клавиши-вкладки, галетник, крутилка, фейдер,
## таблички, трубки-индикаторы, иконки.

const Design = preload("res://scripts/ui/design.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Segmented = preload("res://scripts/ui/widgets/segmented.gd")
const ToggleSwitch = preload("res://scripts/ui/widgets/toggle_switch.gd")
const RotaryKnob = preload("res://scripts/ui/widgets/rotary_knob.gd")
const Fader = preload("res://scripts/ui/widgets/fader.gd")
const RotarySwitch = preload("res://scripts/ui/widgets/rotary_switch.gd")
const Materials = preload("res://scripts/ui/materials.gd")

const MATERIAL_NAMES := ["бакелит", "латунь", "хром", "дерево", "эмаль", "бумага", "бархат", "резина"]

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
		chip.add_theme_stylebox_override("panel", Design.key(Materials.Kind.ENAMEL, col, "normal", Design.RADIUS_SM, 2.0, Vector2(8, 6)))
		chip.custom_minimum_size = Vector2(130, 40)
		var dark := col.get_luminance() > 0.55
		chip.add_child(Design.label(sw[0], "caption", Design.INK if dark else Design.CREAM))
		grid.add_child(chip)
	p.add_child(grid)

	p.add_child(Design.label("МАТЕРИАЛЫ", "overline", Design.YOLK))
	var mats := GridContainer.new()
	mats.columns = 4
	mats.add_theme_constant_override("h_separation", Design.SPACE[2])
	mats.add_theme_constant_override("v_separation", Design.SPACE[2])
	for m in MATERIAL_NAMES.size():
		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", Design.key(m, Color(0, 0, 0, 0), "normal", Design.RADIUS_SM, 3.0, Vector2(6, 6)))
		tile.custom_minimum_size = Vector2(96, 44)
		var light: bool = m in [Materials.Kind.BRASS, Materials.Kind.CHROME, Materials.Kind.PAPER]
		tile.add_child(Design.label(MATERIAL_NAMES[m], "caption", Design.INK if light else Design.CREAM))
		mats.add_child(tile)
	p.add_child(mats)

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
	for v in [["ЛАТУНЬ", "Primary"], ["БАКЕЛИТ", ""], ["РЕЗИНА", "Ghost"], ["ЭМАЛЬ", "Danger"]]:
		var b: Button
		b = Design.button(v[0], func() -> void:
			if v[1] == "Danger":  # крышка: первое нажатие откидывает, второе — закрывает
				Design.set_cover(b, not Design.cover_open(b)), v[1], Vector2(190, Design.TOUCH_MIN))
		buttons.add_child(b)
	buttons.add_child(Design.button("КАРТОЧКА", func() -> void: pass, "Card", Vector2(190, Design.TOUCH_MIN)))
	p.add_child(buttons)

	p.add_child(Design.label("ПЕРЕКЛЮЧАТЕЛИ", "overline", Design.YOLK))
	var row := Design.hbox(Design.SPACE[3], BoxContainer.ALIGNMENT_BEGIN)
	var t1 := ToggleSwitch.new()
	t1.set_on(true)
	row.add_child(t1)
	row.add_child(ToggleSwitch.new())
	var knob := RotaryKnob.new()
	knob.set_value_no_signal(0.6)
	knob.default_value = 0.6
	row.add_child(knob)
	p.add_child(row)
	var seg := Segmented.new()
	seg.setup(["НИЗКО", "СРЕДНЕ", "ВЫСОКО"], 1)
	p.add_child(seg)
	var rot := RotarySwitch.new()
	rot.setup(["30", "60", "120", "БЕЗ"], 1)
	p.add_child(rot)
	var fader := Fader.new()
	fader.set_value_no_signal(0.6)
	fader.custom_minimum_size = Vector2(300, 44)
	p.add_child(fader)

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
	icons.custom_minimum_size = Vector2(0, 136)
	icons.draw.connect(func() -> void:
		var x := 20.0
		for i in 4:
			Icons.stage(icons, Vector2(x, 20), i)
			x += 44.0
		Icons.heart(icons, Vector2(x, 20), 11.0, Color(0.95, 0.15, 0.25))
		Icons.shield(icons, Vector2(x + 44, 20), 13.0)
		Icons.scale_coin(icons, Vector2(x + 88, 20))
		x = 20.0
		for f in [Icons.pause, Icons.gear, Icons.arrow_back, Icons.lock, Icons.check, Icons.bolt, Icons.code,
				Icons.folder, Icons.calendar]:
			f.call(icons, Vector2(x, 66), Design.CREAM, 1.0)
			x += 44.0
		x = 20.0
		for k in 3:
			Icons.fork_kind(icons, Vector2(x, 112), k)
			x += 44.0
		for atk in 4:
			Icons.fork_attack(icons, Vector2(x, 112), atk, Design.warn())
			x += 44.0)
	p.add_child(icons)
