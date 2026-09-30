extends "res://scripts/ui/screens/screen.gd"
## Главное меню 3.0 (v9.0). Слева — доска-пульт на винтах: заголовок, карточки сложностей 2×2
## (у каждой — лампа, сердца жизней и рекорд в окошке), описание, испытание дня и картотека,
## навыки, настройки, выход. Справа поверх живой демо-арены приколот «Журнал эксперимента»:
## маршрут забега от медведей до яичницы, штамп «ОБНОВЛЕНО» у яичницы (v12.0), счётчики (чешуйки,
## картотека, серия испытаний, пасхалки) и совет (core/tips.gd). Внизу справа — латунная табличка
## с управлением и номером версии.
## Пасхалки меню: код Konami, набранное iddqd, семь щелчков по заголовку (яичницу в углу ловит game.gd).

signal difficulty_chosen(index: int)
signal skills_requested
signal settings_requested
signal quit_requested
signal daily_requested
signal bestiary_requested
signal secret_found(id: String)
signal contact_requested

const Tips = preload("res://scripts/core/tips.gd")
const Bestiary = preload("res://scripts/core/bestiary.gd")
const Daily = preload("res://scripts/core/daily.gd")
const Secrets = preload("res://scripts/core/secrets.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Snake = preload("res://scripts/entities/snake.gd")
const TitleArt = preload("res://scripts/ui/widgets/title_art.gd")

const JOURNAL_WIDTH := 420.0
const PAPER_INK := Color(0.2, 0.14, 0.1)
const RED_INK := Color(0.7, 0.16, 0.12)
const CARD := Vector2(214, 78)
const ROUTE_STEP := 78.0
## Код Konami: ↑ ↑ ↓ ↓ ← → ← → B A (физические клавиши — раскладка не важна).
const KONAMI := [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A]
const IDDQD := [KEY_I, KEY_D, KEY_D, KEY_Q, KEY_D]
const TITLE_CLICKS := 7

var diff_buttons: Array[Button] = []
var desc_label: Label
var tree_button: Button
var daily_button: Button
var bestiary_button: Button
var quit_button: Button
var controls_label: Label
var controls_plate: PanelContainer
var tip_label: Label
var tip_note: PanelContainer  # «Журнал эксперимента» (совет — внизу журнала)
var route: Control
var stats_label: Label
var title_art: TitleArt
var subtitle: Label
var fade_items: Array[Control] = []
var difficulties: Array = []
var bests: Array = []
var t := 0.0
var intro := 0.0
var tip_t := 0.0
var tip_index := 0
var keys: Array[int] = []      # последние нажатые клавиши (коды пасхалок)
var title_clicks := 0
var title_click_t := 0.0
var scales_now := 0
## v10.0: фальшивое меню (одна кнопка вместо карточек — глюк) и скрытый вход в «Контакт».
var bay: PanelContainer
var choose_label: Label
var extra_row: BoxContainer
var action_row: BoxContainer
var glitch_button: Button
var glitch := false
var glitch_text := ""
var contact_button: Button


func _init() -> void:
	super()
	dim_background = false


func build() -> void:
	make_frame(Design.SPACE[2], Design.elevated(Design.SURFACE_1, Design.LINE, Design.RADIUS_LG, 2,
		Vector2(Design.SPACE[6], Design.SPACE[4])))
	center.anchor_right = 0.5
	center.offset_left = Design.SPACE[5]
	title_art = TitleArt.new()
	title_art.mouse_filter = Control.MOUSE_FILTER_STOP
	title_art.gui_input.connect(_on_title_input)
	content.add_child(title_art)
	subtitle = Design.label("против ГИГАНТСКОЙ ЯИЧНИЦЫ", "h3", Design.YOLK, HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.label_settings = Design.label_settings("h2", Design.YOLK)
	subtitle.label_settings.font_size = 25
	content.add_child(subtitle)
	content.add_child(Design.spacer(Design.SPACE[1]))
	choose_label = Design.label("ВЫБЕРИ СЛОЖНОСТЬ", "overline", Design.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(choose_label)
	# карточки сложностей сидят в утопленной рамке, как клавиши в приборной панели
	bay = PanelContainer.new()
	bay.add_theme_stylebox_override("panel", Design.well(Design.RADIUS_MD + 4, Vector2(Design.SPACE[3], Design.SPACE[3])))
	bay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(bay)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Design.SPACE[3])
	grid.add_theme_constant_override("v_separation", Design.SPACE[3])
	bay.add_child(grid)
	for i in 4:
		var b := Design.button("", difficulty_chosen.emit.bind(i), "", CARD)
		b.focus_entered.connect(_show_desc.bind(i))
		b.mouse_entered.connect(_show_desc.bind(i))
		var face := Control.new()  # лицо карточки: название, сердца жизней, рекорд
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.draw.connect(_draw_card.bind(face, b, i))
		b.add_child(face)
		# лицо карточки перерисовывается, когда меняется её вид (наведение, фокус, нажатие), а не каждый кадр
		for sig: Signal in [b.mouse_entered, b.mouse_exited, b.focus_entered, b.focus_exited, b.button_down, b.button_up]:
			sig.connect(face.queue_redraw)
		grid.add_child(b)
		diff_buttons.append(b)
		fade_items.append(b)
	desc_label = Design.label("", "small", Design.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	desc_label.custom_minimum_size = Vector2(0, 50)
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(desc_label)
	content.add_child(HSeparator.new())  # фрезерованная канавка: ниже — второстепенное
	var extra := Design.hbox(Design.SPACE[3])  # испытание дня и картотека
	extra_row = extra
	content.add_child(extra)
	daily_button = Design.button("", daily_requested.emit, "", Vector2(290, Design.TOUCH_MIN))
	daily_button.add_theme_font_size_override("font_size", 15)
	daily_button.focus_entered.connect(func() -> void: _show_daily_desc())
	daily_button.mouse_entered.connect(func() -> void: _show_daily_desc())
	extra.add_child(daily_button)
	bestiary_button = Design.button("", bestiary_requested.emit, "", Vector2(150, Design.TOUCH_MIN))
	bestiary_button.add_theme_font_size_override("font_size", 15)
	extra.add_child(bestiary_button)
	contact_button = Design.button("КОНТАКТ", contact_requested.emit, "Ghost", Vector2(110, Design.TOUCH_MIN))
	contact_button.add_theme_font_size_override("font_size", 15)
	contact_button.tooltip_text = "Технический режим «Контакт»"
	contact_button.visible = false
	extra.add_child(contact_button)
	for b in [daily_button, bestiary_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fade_items.append(b)
	var row := Design.hbox(Design.SPACE[3])  # навыки, настройки и выход — одним рядом
	action_row = row
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
	_build_plate()
	_build_journal()
	first_focus = diff_buttons[1]


## Латунная табличка с управлением и версией — внизу справа, поверх демо-арены.
func _build_plate() -> void:
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


## Журнал эксперимента: лист протокола, приколотый латунной кнопкой к столу.
func _build_journal() -> void:
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
	tip_note.custom_minimum_size = Vector2(JOURNAL_WIDTH, 0)
	tip_note.rotation = deg_to_rad(1.2)
	add_child(tip_note)
	var note := Design.vbox(Design.SPACE[1])
	tip_note.add_child(note)
	var head := Design.hbox(Design.SPACE[2], BoxContainer.ALIGNMENT_BEGIN)
	var title := Design.label("ЖУРНАЛ ЭКСПЕРИМЕНТА №47", "overline", RED_INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Design.label("п. 12-Б", "caption", Color(PAPER_INK, 0.55)))
	note.add_child(head)
	route = Control.new()  # маршрут забега: пять этапов
	route.custom_minimum_size = Vector2(0, 74)
	route.draw.connect(_draw_route)
	note.add_child(route)
	stats_label = Design.label("", "readout", PAPER_INK)
	stats_label.label_settings.font_size = 14
	note.add_child(stats_label)
	var rule := Control.new()  # черта ручкой
	rule.custom_minimum_size = Vector2(0, 8)
	rule.draw.connect(func() -> void:
		rule.draw_line(Vector2(0, 4), Vector2(rule.size.x, 3), Color(PAPER_INK, 0.35), 1.5))
	note.add_child(rule)
	note.add_child(Design.label("СОВЕТ", "overline", RED_INK))
	tip_label = Design.label("", "small", PAPER_INK)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(JOURNAL_WIDTH - Design.SPACE[4] * 2, 44)
	note.add_child(tip_label)
	tip_note.draw.connect(func() -> void:  # латунная кнопка-гвоздик сверху по центру
		var c := Vector2(tip_note.size.x / 2.0, 2.0)
		tip_note.draw_circle(c + Vector2(1.5, 3.0), 7.0, Color(0, 0, 0, 0.35))
		tip_note.draw_circle(c, 7.0, Design.BRASS.darkened(0.35))
		tip_note.draw_circle(c + Vector2(-0.8, -0.8), 5.6, Design.BRASS)
		tip_note.draw_circle(c + Vector2(-2.2, -2.2), 2.0, Color(1, 0.95, 0.75, 0.9)))
	fade_items.append(tip_note)


func show_menu(diffs: Array, best_scores: Array, selected: int, scales: int, touch: bool) -> void:
	set_glitch(false)
	set_data(diffs, best_scores, selected, scales, touch)
	open()
	_play_intro()
	tip_index = randi() % Tips.count()
	_next_tip()


## Обновить карточки, рекорды, журнал и подсказки без анимации появления.
func set_data(diffs: Array, best_scores: Array, selected: int, scales: int, touch: bool) -> void:
	difficulties = diffs
	bests = best_scores
	for i in diff_buttons.size():
		var d: Dictionary = diffs[i]
		var b := diff_buttons[i]
		var col: Color = d["color"]
		b.tooltip_text = String(d["name"]) + ("  •  рекорд %d" % best_scores[i] if best_scores[i] > 0 else "")
		for st in ["normal", "hover", "pressed", "hover_pressed"]:  # клавиша сложности: кромка и лампа её цвета
			b.add_theme_stylebox_override(st, Design.card_style(col, st))
		b.get_child(0).queue_redraw()
	first_focus = diff_buttons[selected]
	update_scales(scales)
	var best_today := Daily.best(Daily.day_key())
	var run := Daily.streak()
	daily_button.text = "ИСПЫТАНИЕ ДНЯ%s%s" % ["  •  %d" % best_today if best_today > 0 else "",
		"  •  серия %d" % run if run > 1 else ""]
	refresh_bestiary()
	contact_button.visible = Secrets.is_found("contact") and not glitch
	quit_button.visible = not touch or not OS.has_feature("mobile")
	var version := "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	if touch:
		controls_label.text = "Джойстик слева — поворот  •  кнопки справа — спринт и атака  •  %s" % version
	else:
		controls_label.text = "← → / A D / мышь — поворот  •  Shift — спринт  •  Пробел / ЛКМ — атака\nEsc — пауза  •  F1 / Ctrl+Shift+D — разработчик  •  %s" % version
	_update_journal()
	_show_desc(selected)


## Кнопка картотеки: сколько открыто и (v12.4) сколько новых карточек ещё не прочитано.
func refresh_bestiary() -> void:
	var fresh := Bestiary.new_count()
	bestiary_button.text = "КАРТОТЕКА %d/%d%s" % [Bestiary.known_count(), Bestiary.total(),
		"  •  НОВЫХ %d" % fresh if fresh > 0 else ""]
	if stats_label:
		_update_journal()


func update_scales(scales: int) -> void:
	scales_now = scales
	tree_button.text = "НАВЫКИ  •  " + Design.scales_text(scales).to_upper()
	if stats_label:
		_update_journal()


## Счётчики журнала: машинописью, с отточием до значения.
func _update_journal() -> void:
	var rows := [
		["Чешуйки", "%d" % scales_now],
		["Картотека", "%d / %d" % [Bestiary.known_count(), Bestiary.total()]],
		["Серия испытаний", Design.plural(Daily.streak(), "день", "дня", "дней")],
		["Пасхалки", "%d / %d" % [Secrets.found_count(), Secrets.total()]],
	]
	var lines := PackedStringArray()
	for r: Array in rows:
		var dots := maxi(34 - String(r[0]).length() - String(r[1]).length(), 2)
		lines.append("%s %s %s" % [r[0], ".".repeat(dots), r[1]])
	stats_label.text = "\n".join(lines)
	route.queue_redraw()


func _draw_route() -> void:
	var n := Balance.STAGE_COUNT
	var x0 := (route.size.x - ROUTE_STEP * (n - 1)) / 2.0
	Design.draw_route(route, Vector2(x0, 24), -1, ROUTE_STEP, t)
	var f := Design.font("bold")
	for i in n:
		var name: String = Balance.STAGES[i]["short"]
		var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		route.draw_string(f, Vector2(x0 + i * ROUTE_STEP - w / 2.0, 62), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(PAPER_INK, 0.75))
	# этап, переделанный в этой версии (v12.0 — сковорода яичницы), — штампом «ОБНОВЛЕНО»
	Design.draw_stamp(route, Vector2(x0 + Balance.BOSS_STAGE * ROUTE_STEP - 18, 34), "ОБНОВЛЕНО", RED_INK, -0.14, 10)


## Лицо карточки сложности: название цветом сложности, сердца жизней и рекорд в окошке.
## Нажатая клавиша уходит вниз — лицо опускается вместе с гранью.
func _draw_card(face: Control, b: Button, i: int) -> void:
	if difficulties.is_empty():
		return
	var d: Dictionary = difficulties[i]
	var col: Color = d["color"]
	var down := Design.KEY_TRAVEL - 1.0 if b.get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED] else 0.0
	var o := Vector2(0, down)
	var f := Design.font("heavy")
	var hover := b.get_draw_mode() == BaseButton.DRAW_HOVER or b.has_focus()
	var name: String = d["name"]
	var fs := 17
	while fs > 12 and f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > face.size.x - 42:
		fs -= 1  # длинное название («УЛЬТРА-ХАРДКОР») — мельче, а не обрезано
	face.draw_string_outline(f, o + Vector2(14, 29), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(Design.INK, 0.7))
	face.draw_string(f, o + Vector2(14, 29), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color.WHITE if hover else col.lightened(0.35))
	var lives := int(d["lives"])
	for k in lives:  # жизни — сердцами
		Icons.heart(face, o + Vector2(21 + k * 15, 52), 5.5, Color(0.15, 0.02, 0.05))
		Icons.heart(face, o + Vector2(21 + k * 15, 51), 4.6, Color(0.95, 0.2, 0.28))
	var best := int(bests[i]) if i < bests.size() else 0
	if best <= 0:  # рекорда ещё нет — без пустого окошка
		face.draw_string(Design.font("bold"), o + Vector2(face.size.x - 96, 56), "рекорда нет", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 11, Design.FAINT)
		return
	var rec := "%d" % best
	var mono := Design.font("mono")
	var w := mono.get_string_size(rec, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var win := Rect2(o + Vector2(face.size.x - w - 26, 40), Vector2(w + 14, 20))  # окошко-счётчик рекорда
	face.draw_rect(win, Color(0.03, 0.02, 0.01, 0.85))
	face.draw_rect(win, Color(Design.BRASS, 0.55), false, 1.0)
	face.draw_string(mono, win.position + Vector2(7, 15), rec, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Design.YOLK)
	face.draw_string(Design.font("bold"), win.position + Vector2(-44, 15), "рекорд", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Design.MUTED)


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
	tip_t = 6.0
	tip_label.text = Tips.GENERAL[tip_index]
	if Settings.flag("reduced_motion") or not is_inside_tree():
		return
	tip_label.modulate.a = 0.0
	create_tween().tween_property(tip_label, "modulate:a", 1.0, 0.4)


func _show_desc(i: int) -> void:
	if difficulties.is_empty() or glitch:
		return
	var d: Dictionary = difficulties[i]
	desc_label.text = d["desc"]
	desc_label.label_settings.font_color = (d["color"] as Color).lightened(0.45)


func _show_daily_desc() -> void:
	var mod := Daily.today()
	var run := Daily.streak()
	desc_label.text = "Испытание дня %s: %s. Нормальная сложность.
%s
Серия: %s (рекорд %d) — за первый забег дня +%s." % [
		Daily.day_key(), mod["name"], (mod["desc"] as String).replace("
", " • "), Design.plural(run, "день", "дня", "дней"), Daily.best_streak(),
		Design.scales_text(Daily.streak_bonus(run + (0 if Daily.best(Daily.day_key()) > 0 else 1)))]
	desc_label.label_settings.font_color = Design.STEEL.lightened(0.3)


## Фальшивое меню «Контакта»: вместо карточек и кнопок — одна кнопка с текстом text (нажимает её
## не игрок, а курсор — contact/fake_menu.gd).
func glitch_single(text: String) -> void:
	if glitch_button == null:
		glitch_button = Design.button(text, func() -> void: pass, "Primary", Vector2(440, 84))
		glitch_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		glitch_button.add_theme_font_size_override("font_size", 26)
		glitch_button.pivot_offset = Vector2(220, 42)
		content.add_child(glitch_button)
		content.move_child(glitch_button, bay.get_index())
	glitch_text = text
	glitch_button.text = text
	set_glitch(true)
	desc_label.text = "ОБРАЗЕЦ №48  •  ПРОТОКОЛ ПЕРЕЗАПУЩЕН"
	desc_label.label_settings.font_color = Design.MUTED
	first_focus = glitch_button


func set_glitch(on: bool) -> void:
	glitch = on
	if glitch_button:
		glitch_button.visible = on
	for n: Control in [bay, choose_label, extra_row, action_row]:
		n.visible = not on
	if not on and panel:
		panel.modulate = Color.WHITE


func handle_back() -> bool:
	return false  # из меню Esc никуда не ведёт


# ---------------------------------------------------------------- пасхалки меню

## Коды набираются где угодно в меню: стрелки при этом по-прежнему двигают фокус.
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	keys.append(int(event.physical_keycode))
	if keys.size() > KONAMI.size():
		keys.pop_front()
	if _ends_with(KONAMI):
		keys.clear()
		Snake.golden = not Snake.golden  # до перезапуска игры; повтор кода — обратно зелёная
		secret_found.emit("konami")
		desc_label.text = "Золотая змея!" if Snake.golden else "Змея снова зелёная."
		desc_label.label_settings.font_color = Design.YOLK
	elif _ends_with(IDDQD):
		keys.clear()
		secret_found.emit("iddqd")
		desc_label.text = "Режим бога протоколом не предусмотрен.\nСм. пункт 12-Б. — Учёный"
		desc_label.label_settings.font_color = Design.PLUM.lightened(0.3)


func _ends_with(code: Array) -> bool:
	if keys.size() < code.size():
		return false
	for i in code.size():
		if keys[keys.size() - code.size() + i] != code[i]:
			return false
	return true


## Семь щелчков по заголовку подряд — змейка шипит, буквы подпрыгивают.
func _on_title_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if not tap:
		return
	title_clicks = title_clicks + 1 if title_click_t > 0.0 else 1
	title_click_t = 1.2
	title_art.poke()
	if title_clicks >= TITLE_CLICKS:
		title_clicks = 0
		title_art.hiss()
		secret_found.emit("title")


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	intro += delta
	title_click_t = maxf(title_click_t - delta, 0.0)
	if not Settings.flag("reduced_motion"):
		subtitle.pivot_offset = subtitle.size / 2.0
		subtitle.rotation = sin(t * 2.0) * 0.03
		subtitle.scale = Vector2.ONE * (1.0 + 0.04 * sin(t * 3.0))
	title_art.t = t
	title_art.intro = intro
	title_art.queue_redraw()
	_fit_journal()
	_fit_plate()
	if glitch and panel and not Settings.flag("reduced_motion"):  # фальшивое меню подрагивает помехами
		var hit := fmod(t * 7.3, 1.0) < 0.08
		panel.modulate = Color(0.85, 1.0, 0.9, 0.9) if hit else Color.WHITE
		glitch_button.text = glitch_text.replace("О", "0") if hit else glitch_text
	tip_t -= delta
	if tip_t <= 0.0:
		_next_tip()


## Латунная табличка управления тоже не наезжает на доску: на узком экране она мельче.
func _fit_plate() -> void:
	if panel == null or not controls_plate.is_inside_tree() or controls_plate.size.x <= 0.0:
		return
	var right_edge := center.position.x + panel.position.x + panel.size.x
	var free := size.x - Design.SPACE[5] - Design.SPACE[3] - right_edge
	var k := clampf(free / controls_plate.size.x, 0.6, 1.0)
	controls_plate.pivot_offset = controls_plate.size
	controls_plate.scale = Vector2(k, k)


## Журнал не должен наезжать на доску слева (узкий экран, крупный интерфейс): тогда он мельче.
func _fit_journal() -> void:
	if panel == null or not tip_note.is_inside_tree():
		return
	var right_edge := center.position.x + panel.position.x + panel.size.x  # в координатах меню
	var free := size.x - Design.SPACE[6] - Design.SPACE[4] - right_edge
	var k := clampf(free / tip_note.size.x, 0.55, 1.0) if tip_note.size.x > 0.0 else 1.0
	tip_note.pivot_offset = Vector2(tip_note.size.x, 0)
	tip_note.scale = Vector2(k, k)
