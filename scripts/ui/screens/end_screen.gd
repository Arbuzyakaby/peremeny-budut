extends "res://scripts/ui/screens/screen.gd"
## Итоги забега: заголовок (победа / поражение / «КОНЕЦ»), строки статистики, чешуйки, кнопки.
## После гибели — совет по причине удара и клавиша «ПОВТОР» (запись последних секунд, replay_screen.gd).
## Новый рекорд (дизайн-язык 2.3) — красный штамп протокола «РЕКОРД» рядом со строкой «Счёт».
##
## v12.4: строк после 12.3 стало 11–18, и на телефоне кнопки уезжали за край. Теперь прокручиваются
## только строки итогов, а заголовок, кнопки и совет всегда на экране. Строки раскладываются
## в две колонки, если хватает ширины; если и так не влезают — значения набираются мельче.

signal retry_requested
signal menu_requested
signal replay_requested

const KEY_W := 210.0       # ширина подписи в строке
const VALUE_WRAP := 300.0  # длинное значение переносится по этой ширине
const LONG_VALUE := 24     # с какой длины значение считается длинным
const MIN_ROWS_H := 120.0  # меньше этой высоты окно строк не ужимается

var head: Label
var headline: Label
var body: VBoxContainer   # всё содержимое панели: шапка, окно строк, кнопки, совет
var stats: GridContainer  # пары «подпись — значение», 2 или 4 столбца
var buttons: HBoxContainer
var tip_label: Label
var replay_button: Button
var stamp: Control
var stamp_k := 0.0  # штамп «прилетает» сверху и пристукивается
var score_label: Label  # значение строки «Счёт» — к нему пристёгнут штамп
var rows_data: Array = []
var columns := 1  # сколько пар в строке сетки: 1 или 2
var compact := false  # значения набраны шрифтом body вместо h3
var _cols_for_width := -1.0  # для какой ширины уже выбрано число колонок


func build() -> void:
	make_frame(Design.SPACE[2])
	# Каркас базового экрана прокручивает всё; здесь в прокрутке остаются только строки.
	panel.remove_child(scroll)
	body = Design.vbox(Design.SPACE[3])
	panel.add_child(body)
	head = Design.label("", "display", Design.YOLK, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(head)
	headline = Design.label("", "h3", Design.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(headline)
	body.add_child(HSeparator.new())
	body.add_child(scroll)
	stats = GridContainer.new()
	stats.add_theme_constant_override("h_separation", Design.SPACE[4])
	stats.add_theme_constant_override("v_separation", Design.SPACE[1])
	content.add_child(stats)
	body.add_child(HSeparator.new())
	buttons = Design.hbox(Design.SPACE[4])
	body.add_child(buttons)
	first_focus = Design.button("ЕЩЁ РАЗ", retry_requested.emit, "Primary", Vector2(230, Design.TOUCH_MIN + 4))
	buttons.add_child(first_focus)
	buttons.add_child(Design.button("В МЕНЮ", menu_requested.emit, "", Vector2(230, Design.TOUCH_MIN + 4)))
	replay_button = Design.button("ПОВТОР", replay_requested.emit, "Ghost", Vector2(160, Design.TOUCH_MIN + 4))
	buttons.add_child(replay_button)
	tip_label = Design.label("", "small", Design.STEEL.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(560, 0)
	body.add_child(tip_label)
	stamp = Control.new()
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	stamp.draw.connect(_draw_stamp)
	add_child(stamp)
	scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: stamp.queue_redraw())


## rows — пары [подпись, значение]; третий элемент true — строка подсвечивается золотом.
func show_end(win: bool, custom_title: String, line: String, rows: Array, can_replay := false, tip := "") -> void:
	replay_button.visible = can_replay
	tip_label.visible = tip != ""
	tip_label.text = "СОВЕТ: " + tip
	head.text = custom_title if custom_title != "" else ("ПОБЕДА!" if win else "ЗМЕЯ ПОВЕРЖЕНА")
	var col := Design.MINT if win else Design.TOMATO
	if custom_title != "":
		col = Design.YOLK
	head.label_settings.font_color = col
	headline.text = line
	headline.visible = line != ""
	var record := false
	for r: Array in rows:
		if r[0] == "Счёт" and r.size() > 2 and r[2]:
			record = true
	stamp.visible = record
	if record:
		stamp_k = 1.0 if Settings.flag("reduced_motion") else 0.0
		if stamp_k < 1.0:
			var tw := create_tween()
			tw.tween_interval(0.6)
			tw.tween_property(self, "stamp_k", 1.0, Design.BASE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(Design.play.bind("stamp"))
			tw.tween_method(func(_v: float) -> void: stamp.queue_redraw(), 0.0, 1.0, 0.05)
		stamp.modulate.a = 1.0
	rows_data = rows.duplicate()
	compact = false
	columns = 1
	_cols_for_width = -1.0
	_fill_rows(true)
	open()
	scroll.scroll_vertical = 0


## Раскладка строк в сетку. Две колонки читаются сверху вниз: левая — первая половина, правая — вторая.
func _fill_rows(animate := false) -> void:
	for c in stats.get_children():
		stats.remove_child(c)
		c.queue_free()
	score_label = null
	stats.columns = columns * 2
	var n := rows_data.size()
	var per_col := ceili(n / float(columns))
	for i in per_col:
		for c in columns:
			var idx := i + c * per_col
			if idx < n:
				_add_row(rows_data[idx], animate, i)
			elif c > 0:  # пустая ячейка под пару, чтобы сетка не съехала
				stats.add_child(Control.new())
				stats.add_child(Control.new())


func _add_row(r: Array, animate: bool, i: int) -> void:
	var k := Design.label(r[0], "small", Design.MUTED)
	k.custom_minimum_size = Vector2(KEY_W, 0)
	k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stats.add_child(k)
	var accent: bool = r.size() > 2 and r[2]
	var v := Design.label(r[1], "body" if compact else "h3", Design.YOLK if accent else Design.CREAM)
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if String(r[1]).length() > LONG_VALUE:
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size = Vector2(VALUE_WRAP, 0)
	if columns > 1 and stats.get_child_count() % 4 == 1:  # левая пара — отступ до правой колонки
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_right", Design.SPACE[6])
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(v)
		stats.add_child(m)
	else:
		stats.add_child(v)
	if r[0] == "Счёт":
		score_label = v
	if animate:
		var delay := 0.25 + i * Design.STAGGER * 2.0
		Design.appear(k, delay, 0.0)
		Design.appear(v, delay, 0.0)


## Сколько места у окна строк: экран минус поля панели, шапка, кнопки и совет.
func _chrome() -> Vector2:
	var st := panel.get_theme_stylebox("panel")
	return st.get_minimum_size() if st else Vector2.ZERO


## Узкий экран: заголовок набирается h1 вместо display, кнопки сужаются, совет — по ширине панели.
func _fit_width(avail: float) -> void:
	var ls := head.label_settings
	var big := Design.size_of("display")
	var w := ls.font.get_string_size(head.text, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	ls.font_size = big if w <= avail else Design.size_of("h1")
	var narrow := avail < 700.0
	var widths := [180, 180, 130] if narrow else [230, 230, 160]
	for i in buttons.get_child_count():
		var b: Control = buttons.get_child(i)
		b.custom_minimum_size.x = widths[i]
	tip_label.custom_minimum_size.x = minf(560.0, avail)
	# перенос у строки под заголовком — только когда не влезает: у метки с переносом без ширины
	# минимальная высота считается «по слову в строке» и отъедала место у окна строк
	var hs := headline.label_settings
	var hw := hs.font.get_string_size(headline.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hs.font_size).x
	if hw <= avail:
		headline.autowrap_mode = TextServer.AUTOWRAP_OFF
		headline.custom_minimum_size.x = 0.0
	else:
		headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		headline.custom_minimum_size.x = avail


func _rows_room() -> Vector2:
	var chrome := _chrome()
	var margin := Design.SPACE[5] * 2.0
	var fixed := 0.0
	var gap := float(body.get_theme_constant("separation"))
	var shown := 0
	for c: Control in body.get_children():
		if not c.visible:
			continue
		shown += 1
		if c != scroll:
			fixed += c.get_combined_minimum_size().y
	fixed += gap * maxf(shown - 1, 0)
	return Vector2(size.x - chrome.x - margin, size.y - chrome.y - margin - fixed)


func fit() -> void:
	if scroll == null or body == null or not is_inside_tree():
		return
	_fit_width(size.x - Design.SPACE[5] * 2.0 - _chrome().x)
	var room := _rows_room()
	# две колонки — если помещаются по ширине и строк достаточно, чтобы был смысл
	# пробуем две и меряем настоящую ширину сетки: подписи и значения переносятся, оценка по тексту врёт
	# (решение запоминается для ширины экрана: перестройка сетки сама зовёт fit() — без этого был бы цикл)
	if absf(room.x - _cols_for_width) > 1.0:
		_cols_for_width = room.x
		var want_cols := 2 if rows_data.size() >= 8 else 1
		if want_cols != columns:
			columns = want_cols
			_fill_rows()
		if columns == 2 and content.get_combined_minimum_size().x + 18.0 > room.x:
			columns = 1
			_fill_rows()
	var need := content.get_combined_minimum_size()
	if not compact and need.y > room.y and rows_data.size() > 0:
		compact = true  # мельче значения — выигрываем по 6–8 px на строку
		_fill_rows()
		need = content.get_combined_minimum_size()
	var h := minf(need.y, maxf(room.y, MIN_ROWS_H))
	var bar := 18 if need.y > h + 1.0 else 0
	gutter.add_theme_constant_override("margin_right", bar)
	scroll.custom_minimum_size = Vector2(need.x + bar, h)
	stamp.queue_redraw()


## Штамп садится правее значения «Счёт» и едет вместе с прокруткой; строка ушла из окна — штампа не видно.
func stamp_anchor() -> Vector2:
	if score_label == null or not is_instance_valid(score_label):
		return Vector2.INF
	var r := score_label.get_global_rect()
	var text_w := score_label.label_settings.font.get_string_size(score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		score_label.label_settings.font_size).x
	var at := Vector2(r.position.x + minf(text_w, r.size.x) + 70.0, r.get_center().y)
	var view := scroll.get_global_rect().grow(8.0)
	if not view.has_point(Vector2(view.get_center().x, at.y)):
		return Vector2.INF
	return at


func _draw_stamp() -> void:
	var at := stamp_anchor()
	if at == Vector2.INF:
		return
	var local := stamp.get_global_transform().affine_inverse() * at
	Design.draw_stamp(stamp, local, "РЕКОРД", Design.danger(), -0.18, 26, 1.0 + 0.6 * (1.0 - stamp_k))


func _process(_delta: float) -> void:
	if visible and stamp.visible:
		stamp.modulate.a = stamp_k
		stamp.queue_redraw()


func handle_back() -> bool:
	menu_requested.emit()
	return true
