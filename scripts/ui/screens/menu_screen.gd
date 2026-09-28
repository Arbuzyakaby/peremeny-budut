extends "res://scripts/ui/screens/screen.gd"
## Главное меню (v7.1): доска на винтах слева — анимированный заголовок, карточки сложностей 2×2
## в утопленной рамке, испытание дня и картотека, навыки, настройки, выход. Справа видна живая
## демо-арена; на неё приколота записка с советом (core/tips.gd), внизу — латунная табличка
## с управлением и номером версии.

signal difficulty_chosen(index: int)
signal skills_requested
signal settings_requested
signal quit_requested
signal daily_requested
signal bestiary_requested


const Tips = preload("res://scripts/core/tips.gd")
const Bestiary = preload("res://scripts/core/bestiary.gd")
const Daily = preload("res://scripts/core/daily.gd")

const TitleArt = preload("res://scripts/ui/widgets/title_art.gd")

const TIP_WIDTH := 400.0
const PAPER_INK := Color(0.2, 0.14, 0.1)

var diff_buttons: Array[Button] = []
var desc_label: Label
var tree_button: Button
var daily_button: Button
var bestiary_button: Button
var quit_button: Button
var controls_label: Label
var controls_plate: PanelContainer
var tip_label: Label
var tip_note: PanelContainer
var title_art: TitleArt
var subtitle: Label
var fade_items: Array[Control] = []
var difficulties: Array = []
var bests: Array = []
var t := 0.0
var intro := 0.0
var tip_t := 0.0
var tip_index := 0


func _init() -> void:
	super()
	dim_background = false


func build() -> void:
	make_frame(Design.SPACE[2], Design.elevated(Design.SURFACE_1, Design.LINE, Design.RADIUS_LG, 2,
		Vector2(Design.SPACE[6], Design.SPACE[4])))
	center.anchor_right = 0.5
	center.offset_left = Design.SPACE[5]
	title_art = TitleArt.new()
	content.add_child(title_art)
	subtitle = Design.label("против ГИГАНТСКОЙ ЯИЧНИЦЫ", "h3", Design.YOLK, HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.label_settings = Design.label_settings("h2", Design.YOLK)
	subtitle.label_settings.font_size = 25
	content.add_child(subtitle)
	content.add_child(Design.spacer(Design.SPACE[1]))
	var choose := Design.label("ВЫБЕРИ СЛОЖНОСТЬ", "overline", Design.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(choose)
	# карточки сложностей сидят в утопленной рамке, как клавиши в приборной панели
	var bay := PanelContainer.new()
	bay.add_theme_stylebox_override("panel", Design.well(Design.RADIUS_MD + 4, Vector2(Design.SPACE[3], Design.SPACE[3])))
	bay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(bay)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Design.SPACE[3])
	grid.add_theme_constant_override("v_separation", Design.SPACE[3])
	bay.add_child(grid)
	for i in 4:
		var b := Design.button("", difficulty_chosen.emit.bind(i), "", Vector2(208, 60))
		b.add_theme_font_size_override("font_size", 18)
		b.focus_entered.connect(_show_desc.bind(i))
		b.mouse_entered.connect(_show_desc.bind(i))
		grid.add_child(b)
		diff_buttons.append(b)
		fade_items.append(b)
	desc_label = Design.label("", "small", Design.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	desc_label.custom_minimum_size = Vector2(0, 50)
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(desc_label)
	content.add_child(HSeparator.new())  # фрезерованная канавка: ниже — второстепенное
	var extra := Design.hbox(Design.SPACE[3])  # испытание дня и картотека
	content.add_child(extra)
	daily_button = Design.button("", daily_requested.emit, "", Vector2(290, Design.TOUCH_MIN))
	daily_button.add_theme_font_size_override("font_size", 15)
	daily_button.focus_entered.connect(func() -> void: _show_daily_desc())
	daily_button.mouse_entered.connect(func() -> void: _show_daily_desc())
	extra.add_child(daily_button)
	bestiary_button = Design.button("", bestiary_requested.emit, "", Vector2(150, Design.TOUCH_MIN))
	bestiary_button.add_theme_font_size_override("font_size", 15)
	extra.add_child(bestiary_button)
	for b in [daily_button, bestiary_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fade_items.append(b)
	var row := Design.hbox(Design.SPACE[3])  # навыки, настройки и выход — одним рядом
	content.add_child(row)
	tree_button = Design.button("НАВЫКИ", skills_requested.emit, "Primary", Vector2(214, Design.TOUCH_MIN))
	row.add_child(tree_button)
	var settings_b := Design.button("НАСТРОЙКИ", settings_requested.emit, "", Vector2(140, Design.TOUCH_MIN))
	row.add_child(settings_b)
	quit_button = Design.button("ВЫХОД", quit_requested.emit, "Ghost", Vector2(86, Design.TOUCH_MIN))
	row.add_child(quit_button)
	for b in [tree_button, settings_b, quit_button]:
		b.add_theme_font_size_override("font_size", 17)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fade_items.append(b)
	# латунная табличка с управлением и версией — внизу справа, поверх демо-арены
	controls_plate = PanelContainer.new()
	var plate := Design.key(Design.Materials.Kind.BRASS, Color(0, 0, 0, 0), "normal", Design.RADIUS_SM, 0.0,
		Vector2(Design.SPACE[5], Design.SPACE[2]))
	plate.screws = true
	controls_plate.add_theme_stylebox_override("panel", plate)
	controls_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls_plate.anchor_left = 1.0
	controls_plate.anchor_right = 1.0
	controls_plate.anchor_top = 1.0
	controls_plate.anchor_bottom = 1.0
	controls_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	controls_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls_plate.offset_right = -Design.SPACE[5]
	controls_plate.offset_bottom = -Design.SPACE[5]
	add_child(controls_plate)
	controls_label = Design.label("", "caption", Design.INK, HORIZONTAL_ALIGNMENT_CENTER)
	controls_label.label_settings.outline_size = 2  # гравировка: светлый отсвет на латуни
	controls_label.label_settings.outline_color = Color(1, 1, 1, 0.25)
	controls_plate.add_child(controls_label)
	fade_items.append(controls_plate)

	# записка с советом, приколотая латунной кнопкой к столу
	tip_note = PanelContainer.new()
	var paper := Design.key(Design.Materials.Kind.PAPER, Color(0, 0, 0, 0), "normal", 3, 0.0,
		Vector2(Design.SPACE[4], Design.SPACE[3]))
	paper.grain = 0.12
	tip_note.add_theme_stylebox_override("panel", paper)
	tip_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_note.anchor_left = 1.0
	tip_note.anchor_right = 1.0
	tip_note.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tip_note.offset_right = -Design.SPACE[6]
	tip_note.offset_top = Design.SPACE[6]
	tip_note.custom_minimum_size = Vector2(TIP_WIDTH, 0)
	tip_note.rotation = deg_to_rad(1.2)
	add_child(tip_note)
	var note := Design.vbox(Design.SPACE[1])
	tip_note.add_child(note)
	note.add_child(Design.label("СОВЕТ", "overline", Color(0.7, 0.16, 0.12)))
	tip_label = Design.label("", "small", PAPER_INK)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(TIP_WIDTH - Design.SPACE[4] * 2, 0)
	note.add_child(tip_label)
	tip_note.draw.connect(func() -> void:  # латунная кнопка-гвоздик сверху по центру
		var c := Vector2(tip_note.size.x / 2.0, 2.0)
		tip_note.draw_circle(c + Vector2(1.5, 3.0), 7.0, Color(0, 0, 0, 0.35))
		tip_note.draw_circle(c, 7.0, Design.BRASS.darkened(0.35))
		tip_note.draw_circle(c + Vector2(-0.8, -0.8), 5.6, Design.BRASS)
		tip_note.draw_circle(c + Vector2(-2.2, -2.2), 2.0, Color(1, 0.95, 0.75, 0.9)))
	first_focus = diff_buttons[1]


func show_menu(diffs: Array, best_scores: Array, selected: int, scales: int, touch: bool) -> void:
	set_data(diffs, best_scores, selected, scales, touch)
	open()
	_play_intro()
	tip_index = randi() % Tips.count()
	_next_tip()


## Обновить карточки, рекорды и подсказки без анимации появления.
func set_data(diffs: Array, best_scores: Array, selected: int, scales: int, touch: bool) -> void:
	difficulties = diffs
	bests = best_scores
	for i in diff_buttons.size():
		var d: Dictionary = diffs[i]
		var b := diff_buttons[i]
		var col: Color = d["color"]
		b.text = "%s\nрекорд %d" % [d["name"], best_scores[i]] if best_scores[i] > 0 else d["name"]
		for st in ["normal", "hover", "pressed", "hover_pressed"]:  # клавиша сложности: кромка и лампа её цвета
			b.add_theme_stylebox_override(st, Design.card_style(col, st))
		b.add_theme_color_override("font_color", col.lightened(0.35))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
	first_focus = diff_buttons[selected]
	update_scales(scales)
	var best_today := Daily.best(Daily.day_key())
	var run := Daily.streak()
	daily_button.text = "ИСПЫТАНИЕ ДНЯ%s%s" % ["  •  %d" % best_today if best_today > 0 else "",
		"  •  серия %d" % run if run > 1 else ""]
	bestiary_button.text = "КАРТОТЕКА %d/%d" % [Bestiary.known_count(), Bestiary.total()]
	quit_button.visible = not touch or not OS.has_feature("mobile")
	var version := "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	if touch:
		controls_label.text = "Джойстик слева — поворот  •  кнопки справа — спринт и атака  •  %s" % version
	else:
		controls_label.text = "← → / A D / мышь — поворот  •  Shift — спринт  •  Пробел / ЛКМ — атака\nEsc — пауза  •  F1 / Ctrl+Shift+D — разработчик  •  %s" % version
	_show_desc(selected)


func update_scales(scales: int) -> void:
	tree_button.text = "НАВЫКИ  •  %d ч." % scales


func _play_intro() -> void:
	intro = 0.0 if not Settings.flag("reduced_motion") else 5.0
	if Settings.flag("reduced_motion"):
		return
	var home := center.position.x
	center.position.x = -700.0
	var tw := create_tween()
	tw.tween_property(center, "position:x", home, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in fade_items.size():
		var c := fade_items[i]
		c.modulate.a = 0.0
		create_tween().tween_property(c, "modulate:a", 1.0, Design.SLOW).set_delay(0.9 + i * Design.STAGGER * 2.0)


func _next_tip() -> void:
	tip_index = (tip_index + 1) % Tips.count()
	tip_t = 5.0
	tip_label.text = Tips.GENERAL[tip_index]
	if Settings.flag("reduced_motion") or not is_inside_tree():
		return
	tip_label.modulate.a = 0.0
	create_tween().tween_property(tip_label, "modulate:a", 1.0, 0.4)


func _show_desc(i: int) -> void:
	if difficulties.is_empty():
		return
	var d: Dictionary = difficulties[i]
	desc_label.text = d["desc"]
	desc_label.label_settings.font_color = (d["color"] as Color).lightened(0.45)


func _show_daily_desc() -> void:
	var mod := Daily.today()
	var run := Daily.streak()
	desc_label.text = "Испытание дня %s: %s. Нормальная сложность.
%s
Серия: %d дн. (рекорд %d) — за первый забег дня +%d ч." % [
		Daily.day_key(), mod["name"], (mod["desc"] as String).replace("
", " • "), run, Daily.best_streak(),
		Daily.streak_bonus(run + (0 if Daily.best(Daily.day_key()) > 0 else 1))]
	desc_label.label_settings.font_color = Design.STEEL.lightened(0.3)


func handle_back() -> bool:
	return false  # из меню Esc никуда не ведёт


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	intro += delta
	if not Settings.flag("reduced_motion"):
		subtitle.pivot_offset = subtitle.size / 2.0
		subtitle.rotation = sin(t * 2.0) * 0.03
		subtitle.scale = Vector2.ONE * (1.0 + 0.04 * sin(t * 3.0))
	title_art.t = t
	title_art.intro = intro
	title_art.queue_redraw()
	tip_t -= delta
	if tip_t <= 0.0:
		_next_tip()
