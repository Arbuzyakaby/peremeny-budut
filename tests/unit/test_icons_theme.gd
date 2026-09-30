extends "res://tests/test_case.gd"
## Иконки (icons.gd), тема Godot из дизайн-языка (theme_factory.gd), витрина UI-кита (ui_kit.gd),
## журнал ошибок (dev_log.gd) и отладочный слой (dev_overlay.gd).

const Icons = preload("res://scripts/ui/icons.gd")
const ThemeFactory = preload("res://scripts/ui/theme_factory.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const DevOverlay = preload("res://scripts/ui/dev_overlay.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Design = preload("res://scripts/ui/design.gd")


## Холст, который рисует всё, что передано в painter.
func _canvas(painter: Callable) -> Control:
	var c := Control.new()
	c.size = Vector2(400, 400)
	c.draw.connect(painter.bind(c))
	add(c)
	return c


func test_every_icon_draws() -> void:
	var calls := [0]
	var c := _canvas(func(ci: Control) -> void:
		var p := Vector2(40, 40)
		Icons.heart(ci, p, 1.0, Design.TOMATO)
		Icons.bear(ci, p)
		Icons.fork(ci, p)
		Icons.pill(ci, p)
		Icons.tablet(ci, p)
		Icons.egg(ci, p)
		for size in 3:
			Icons.doll(ci, p, size)
		for st in 5:
			Icons.stage(ci, p, st)
		Icons.shield(ci, p, 20.0)
		Icons.scale_coin(ci, p)
		for f: Callable in [Icons.pause, Icons.gear, Icons.arrow_back, Icons.lock, Icons.check, Icons.bolt, Icons.code,
				Icons.fang, Icons.folder, Icons.calendar]:
			f.call(ci, p, Design.CREAM, 1.0)
		Icons.star(ci, p, 10.0, Design.YOLK)
		calls[0] += 1)
	await assert_draws(c, "все иконки")
	assert_gt(calls[0], 0, "отрисовка действительно была")


func test_every_ability_icon_draws() -> void:
	var types := [1, 2, 3, 4, 5, 6, 7] + Balance.FORK_ABILITY + [Balance.PILL_ABILITY, Balance.DOLL_ABILITY]
	var c := _canvas(func(ci: Control) -> void:
		for t: int in types:
			Icons.ability(ci, Vector2(40, 40), t, 0.7, 1.4))
	await assert_draws(c, "иконки приёмов")
	for t: int in types:
		assert_true(Balance.ABILITIES.has(t), "у приёма %d есть имя для подписи" % t)


func test_kind_icons_cover_every_kind() -> void:
	var c := _canvas(func(ci: Control) -> void:
		for k in Pill.KINDS.size():
			Icons.pill_kind(ci, Vector2(40, 40), k)
		for k in Icons.FORK_COLORS.size():
			Icons.fork_kind(ci, Vector2(40, 40), k)
		for atk in 4:
			Icons.fork_attack(ci, Vector2(40, 40), atk, Design.YOLK))
	await assert_draws(c, "все виды таблеток и вилок")


func test_theme_has_every_button_variant() -> void:
	var th := ThemeFactory.build()
	for v in ["PrimaryButton", "GhostButton", "DangerButton", "SegmentButton", "CardButton"]:
		assert_eq(th.get_type_variation_base(v), &"Button", "%s — вариант кнопки" % v)
		for st in ["normal", "hover", "pressed"]:
			assert_true(th.has_stylebox(st, v) or th.has_stylebox(st, "Button"), "%s: стиль %s" % [v, st])
	assert_true(th.has_stylebox("grabber", "VScrollBar"), "латунный бегунок прокрутки")
	assert_true(th.has_stylebox("separator", "HSeparator"))
	assert_eq(th.default_font_size, Design.size_of("body"))
	assert_eq(th.get_color("font_pressed_color", "SegmentButton"), Design.YOLK, "нажатая вкладка горит желтком")


func test_ui_kit_builds_the_showcase() -> void:
	var box: VBoxContainer = add(VBoxContainer.new())
	UiKit.build(box)
	assert_gt(box.get_child_count(), 5, "в витрине есть разделы")
	var labels := 0
	var stack: Array[Node] = [box]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			labels += 1
		stack.append_array(n.get_children())
	assert_gt(labels, 10, "подписи материалов и типографики")
	assert_len(UiKit.MATERIAL_NAMES, 8, "восемь материалов")


func test_dev_log_counts_errors_and_warnings() -> void:
	expect_errors()
	var lg: DevLog = DevLog.new()
	var bt: Array[ScriptBacktrace] = []
	lg._log_error("f", "res://a.gd", 10, "code", "что-то сломалось", false, Logger.ERROR_TYPE_ERROR, bt)
	lg._log_error("f", "res://b.gd", 20, "code", "", false, Logger.ERROR_TYPE_WARNING, bt)
	assert_eq(lg.errors, 1)
	assert_eq(lg.warnings, 1)
	assert_has(lg.snapshot(), "a.gd:10 — что-то сломалось")
	assert_has(lg.snapshot(), "b.gd:20 — code", "без пояснения — код ошибки")
	for i in DevLog.MAX_LINES + 10:
		lg._log_error("f", "c.gd", i, "x", "", false, Logger.ERROR_TYPE_ERROR, bt)
	assert_len(lg.lines, DevLog.MAX_LINES, "журнал не растёт бесконечно")
	lg.clear()
	assert_eq(lg.errors, 0)
	assert_len(lg.lines, 0)


func test_dev_overlay_hides_when_nothing_is_on() -> void:
	var o: DevOverlay = add(DevOverlay.new())
	o._process(0.016)
	assert_false(o.visible, "все слои выключены — узел не рисует")
	o.safe_grid = true
	o._process(0.016)
	assert_true(o.visible)
	await assert_draws(o, "сетка безопасной зоны")
