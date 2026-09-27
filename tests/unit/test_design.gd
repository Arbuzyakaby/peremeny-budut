extends "res://tests/test_case.gd"
## Дизайн-язык 2.0: тема из физических материалов, ход клавиш, ниши, доски на винтах, фокус-лампа,
## кэш стилей и текстур, доступность (дальтоники, контраст).

const Design = preload("res://scripts/ui/design.gd")
const PhysicalBox = preload("res://scripts/ui/widgets/physical_box.gd")
const Materials = preload("res://scripts/ui/materials.gd")

const VARIANTS := ["Button", "PrimaryButton", "GhostButton", "DangerButton", "SegmentButton", "CardButton"]


func before_each() -> void:
	use_temp_storage()


func test_theme_is_physical() -> void:
	var th := Design.make_theme()
	for v in VARIANTS:
		for st in ["normal", "hover", "pressed", "disabled"]:
			if th.has_stylebox(st, v):
				assert_true(th.get_stylebox(st, v) is PhysicalBox, "%s/%s — предмет, а не плоская заливка" % [v, st])
		assert_true(th.get_stylebox("focus", v) is PhysicalBox, v + ": фокус-лампа")
	assert_true(th.get_stylebox("panel", "PanelContainer") is PhysicalBox, "панели — доски")
	assert_true(th.get_stylebox("slider", "HSlider") is PhysicalBox)


func test_materials_per_variant() -> void:
	var th := Design.make_theme()
	assert_eq(th.get_stylebox("normal", "Button").kind, Materials.Kind.BAKELITE)
	assert_eq(th.get_stylebox("normal", "PrimaryButton").kind, Materials.Kind.BRASS)
	assert_eq(th.get_stylebox("normal", "GhostButton").kind, Materials.Kind.RUBBER)
	assert_eq(th.get_stylebox("normal", "DangerButton").kind, Materials.Kind.ENAMEL)
	assert_true(th.get_stylebox("pressed", "SegmentButton").lamp.a > 0.0, "на нажатой вкладке горит лампа")


func test_pressed_key_travels_down() -> void:
	var up := Design.key(Materials.Kind.BAKELITE, Color(0, 0, 0, 0), "normal")
	var down := Design.key(Materials.Kind.BAKELITE, Color(0, 0, 0, 0), "pressed")
	assert_gt(down.content_margin_top, up.content_margin_top, "текст уходит вниз вместе с гранью")
	assert_near(up.content_margin_top + up.content_margin_bottom, down.content_margin_top + down.content_margin_bottom, 0.001,
		"высота кнопки не прыгает")
	var r := Rect2(0, 0, 200, 60)
	assert_gt(down.face_rect(r).position.y, up.face_rect(r).position.y, "грань опускается")
	assert_near(up.face_rect(r).size.y, 60.0 - Design.KEY_TRAVEL, 0.001, "под гранью — боковина")


func test_surfaces() -> void:
	var p := Design.plank()
	assert_eq(p.mode, PhysicalBox.Mode.PANEL)
	assert_true(p.screws, "доска на винтах")
	assert_eq(p.kind, Materials.Kind.WOOD)
	var w := Design.well()
	assert_eq(w.mode, PhysicalBox.Mode.INSET)
	var f := Design.focus_ring() as PhysicalBox
	assert_eq(f.mode, PhysicalBox.Mode.FOCUS)
	assert_eq(f.accent, Design.YOLK)
	var plate := Design.plate(Design.MINT)
	assert_eq(plate.kind, Materials.Kind.ENAMEL)
	assert_false(plate.shadow)


func test_card_style_states() -> void:
	var n := Design.card_style(Design.TOMATO, "normal")
	var h := Design.card_style(Design.TOMATO, "hover")
	var d := Design.card_style(Design.TOMATO, "disabled")
	assert_true(n.accent.a < h.accent.a, "наведение — кромка ярче")
	assert_eq(h.lamp, Design.TOMATO)
	assert_near(d.lamp.a, 0.0, 0.001, "выключенная карточка без лампы")
	assert_true(h.hover)


func test_rounded_rect_geometry() -> void:
	for r in [Rect2(0, 0, 20, 20), Rect2(0, 0, 100, 10), Rect2(5, 5, 200, 60)]:
		for rad in [0.0, 5.0, 10.0, 999.0]:
			var pts := PhysicalBox.rrect(r, rad)
			assert_true(pts.size() >= 3, "контур %s r=%s" % [str(r), str(rad)])
			var dup := false
			for i in pts.size():
				if pts[i].distance_squared_to(pts[(i + 1) % pts.size()]) <= 0.01:
					dup = true
			assert_false(dup, "без совпадающих точек (триангуляция)")
	var cols := PhysicalBox.vgrad(PackedVector2Array([Vector2(0, 0), Vector2(0, 10)]), Rect2(0, 0, 10, 10), Color.WHITE, Color.BLACK)
	assert_eq(cols[0], Color.WHITE)
	assert_eq(cols[1], Color.BLACK)


func test_caches() -> void:
	var a := Design.cached("test_style", func() -> StyleBox: return Design.well())
	var b := Design.cached("test_style", func() -> StyleBox: return Design.plank())
	assert_true(a == b, "второй раз — тот же объект")
	assert_true(Design.knob_texture(24, false) == Design.knob_texture(24, false))
	assert_eq(Design.knob_texture(24, false).get_width(), 24)
	assert_true(Materials.texture(Materials.Kind.WOOD) == Materials.texture(Materials.Kind.WOOD))
	for k in Materials.Kind.size():
		assert_len(Materials.palette(k), 3, "палитра материала %d" % k)


func test_accessibility_colors() -> void:
	Settings.set_value("colorblind", false)
	assert_eq(Design.danger(), Design.TOMATO)
	Settings.set_value("colorblind", true)
	assert_ne(Design.danger(), Design.TOMATO, "для дальтоников опасность не красная")
	assert_ne(Design.safe(), Design.MINT)
	Settings.set_value("colorblind", false)
	Settings.set_value("high_contrast", true)
	assert_near(Design.telegraph_width(4.0), 7.2, 0.001)
	Settings.set_value("high_contrast", false)
	assert_near(Design.telegraph_width(4.0), 4.0, 0.001)


func test_type_scale() -> void:
	var prev := 999
	for role in ["display", "h1", "h2", "h3", "body", "small", "caption"]:
		assert_true(Design.size_of(role) <= prev, role + ": шкала убывает")
		prev = Design.size_of(role)
	assert_true(Design.label_settings("hud").outline_size > 0, "над полем — с обводкой")
	assert_eq(Design.label_settings("body").outline_size, 0)


func test_fast_motion_is_responsive() -> void:
	assert_true(Design.FAST <= 0.08 + 0.0001, "нажатие не дольше 80 мс — иначе управление «лагает»")


func test_refuse_is_visible() -> void:
	Settings.set_value("reduced_motion", false)
	var b: Button = add(Button.new())
	b.position = Vector2(40, 10)
	Design.refuse(b)
	assert_true(b.modulate.g < 0.9, "отказ вспыхивает томатным")
	await tree.create_timer(Design.REFUSE_TIME + 0.15).timeout
	assert_near(b.modulate.g, 1.0, 0.01, "цвет вернулся")
	assert_near(b.position.x, 40.0, 0.01, "клавиша вернулась на место")
	Settings.set_value("reduced_motion", true)
	Design.refuse(b)
	assert_near(b.position.x, 40.0, 0.01, "«меньше анимации» — без дрожания")


func test_panic_resets_with_cache() -> void:
	Design.panic = 0.7
	Design.clear_cache()
	assert_eq(Design.panic, 0.0)
