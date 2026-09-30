extends "res://scripts/ui/screens/screen.gd"
## Картотека врагов: сетка карточек-«дел». Неизвестный враг — чёрный силуэт с вопросом;
## открытая карточка показывает рисунок, описание, слабое место и совет на кремовой бумаге.
## v12.4: вкладки по группам со счётчиками и полоса прогресса; на карточках — настоящие враги
## (portrait.gd), а не значки HUD; метка «НОВОЕ» до первого просмотра; в деле — сколько раз встречен
## и побеждён и на каком этапе впервые; текст дела переносится целиком (раньше обрезался на двух
## строках); у пустой карточки — подсказка, где искать. Сетка подстраивается под ширину экрана.

const Bestiary = preload("res://scripts/core/bestiary.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
const Segmented = preload("res://scripts/ui/widgets/segmented.gd")

const CARD := Vector2(108, 92)
const PAPER := Color(0.97, 0.92, 0.8)
const PAPER_INK := Color(0.2, 0.12, 0.06)
const SHEET_W := 400.0  # лист дела справа от сетки
const MIN_COLS := 3
const MAX_COLS := 7

var tabs: Segmented
var grid: GridContainer
var cards: Array[Button] = []
var portraits: Array = []   # Portrait на каждой карточке
var counter: Label
var bar: Control
var sheet: PanelContainer
var sheet_portrait: Portrait
var sheet_title: Label
var sheet_group: Label
var sheet_text: Label
var sheet_weak: Label
var sheet_tip: Label
var sheet_stats: Label
var stamp: Control
var selected := 0
var tab := 0


func build() -> void:
	make_frame(Design.SPACE[3])
	title("КАРТОТЕКА", "h2")
	var progress := Design.hbox(Design.SPACE[3])  # счётчик и полоса — одной строкой
	content.add_child(progress)
	counter = Design.label("", "caption", Design.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	progress.add_child(counter)
	bar = Control.new()
	bar.custom_minimum_size = Vector2(300, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.draw.connect(func() -> void:
		Design.draw_bar(bar, Rect2(Vector2.ZERO, bar.size), Bestiary.known_count() / float(Bestiary.total()), Design.YOLK))
	progress.add_child(bar)
	tabs = Segmented.new()
	var names := []
	for t: Dictionary in Bestiary.TABS:
		names.append(t["name"])
	tabs.setup(names, 0, 0.0)
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tabs.changed.connect(show_tab)
	content.add_child(tabs)
	grid = GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", Design.SPACE[2])
	grid.add_theme_constant_override("v_separation", Design.SPACE[2])
	var row := Design.hbox(Design.SPACE[4])  # сетка слева, дело справа — всё на одном экране
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var gc := CenterContainer.new()
	gc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	gc.add_child(grid)
	row.add_child(gc)
	content.add_child(row)
	for i in Bestiary.ENTRIES.size():
		var b := Design.button("", _select.bind(i), "Card", CARD)
		b.focus_entered.connect(_select.bind(i))
		var p := Portrait.new()
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.offset_bottom = -22.0  # под рисунком — имя
		b.add_child(p)
		var art := Control.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.draw.connect(_draw_card.bind(art, i))
		b.add_child(art)
		grid.add_child(b)
		cards.append(b)
		portraits.append(p)
	row.add_child(_build_sheet())
	var back := Design.button("НАЗАД", func() -> void: closed.emit(), "Primary", Vector2(220, Design.TOUCH_MIN))
	var bc := CenterContainer.new()
	bc.add_child(back)
	content.add_child(bc)
	first_focus = cards[0]


## Лист дела: бумага с линовкой и полем, слева портрет, справа текст (переносится целиком).
func _build_sheet() -> Control:
	sheet = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 24
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sheet.add_theme_stylebox_override("panel", sb)
	sheet.custom_minimum_size = Vector2(SHEET_W, 300)
	sheet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var lines := Control.new()  # линовка, поле и скрепка — под текстом
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.draw.connect(_draw_paper.bind(lines))
	sheet.add_child(lines)
	var col := Design.vbox(Design.SPACE[1])
	sheet.add_child(col)
	var head := Design.hbox(Design.SPACE[3], BoxContainer.ALIGNMENT_BEGIN)  # портрет и шапка дела
	col.add_child(head)
	sheet_portrait = Portrait.new()
	sheet_portrait.live = true
	sheet_portrait.custom_minimum_size = Vector2(120, 120)
	head.add_child(sheet_portrait)
	var head_col := Design.vbox(Design.SPACE[1])
	head_col.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(head_col)
	var text_w := SHEET_W - 36.0
	sheet_title = _paper_label("heavy", 18, PAPER_INK, text_w - 132.0)
	sheet_group = _paper_label("mono", 12, Color(0.6, 0.2, 0.15), text_w - 132.0)
	sheet_stats = _paper_label("mono", 12, Color(0.2, 0.3, 0.55), text_w - 132.0)
	for l in [sheet_title, sheet_group, sheet_stats]:
		head_col.add_child(l)
	sheet_text = _paper_label("mono", 14, PAPER_INK, text_w)
	sheet_weak = _paper_label("mono", 14, Color(0.1, 0.4, 0.2), text_w)
	sheet_tip = _paper_label("mono", 14, Color(0.45, 0.25, 0.05), text_w)
	for l in [sheet_text, sheet_weak, sheet_tip]:
		col.add_child(l)
	stamp = Control.new()  # штамп «ИЗУЧЕНО» — поверх листа, в правом нижнем углу
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.draw.connect(func() -> void:
		if Bestiary.is_known(Bestiary.ENTRIES[selected]["key"]):
			Design.draw_stamp(stamp, stamp.size - Vector2(90, 34), "ИЗУЧЕНО", Color(0.75, 0.15, 0.15), -0.2, 20))
	sheet.add_child(stamp)
	return sheet


func _paper_label(weight: String, fs: int, col: Color, width: float) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = Design.font(weight)
	ls.font_size = fs
	ls.font_color = col
	l.label_settings = ls
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _draw_paper(c: Control) -> void:
	var r := Rect2(Vector2(-12, -14), c.size + Vector2(36, 28))
	for y in range(int(r.position.y) + 34, int(r.end.y), 22):  # линовка
		c.draw_line(Vector2(r.position.x + 12, y), Vector2(r.end.x - 12, y), Color(0.55, 0.65, 0.85, 0.3), 1.0)
	c.draw_line(Vector2(r.position.x + 28, r.position.y), Vector2(r.position.x + 28, r.end.y), Color(0.9, 0.35, 0.35, 0.4), 1.5)
	var clip := Vector2(r.end.x - 40, r.position.y - 6)  # скрепка
	c.draw_arc(clip + Vector2(0, 14), 7.0, PI, TAU, 10, Color(0.6, 0.62, 0.66), 2.5)
	c.draw_line(clip + Vector2(-7, 14), clip + Vector2(-7, 36), Color(0.6, 0.62, 0.66), 2.5)
	c.draw_line(clip + Vector2(7, 14), clip + Vector2(7, 30), Color(0.6, 0.62, 0.66), 2.5)


func open() -> void:
	Bestiary.ensure_loaded()
	_refresh()
	show_tab(tab)
	super()


func _refresh() -> void:
	var n := Bestiary.new_count()
	counter.text = "Открыто %d из %d%s" % [Bestiary.known_count(), Bestiary.total(),
		"  •  новых: %d" % n if n > 0 else ""]
	bar.queue_redraw()
	for i in Bestiary.TABS.size():  # счётчики на вкладках
		var pr := Bestiary.tab_progress(i)
		tabs.buttons[i].text = "%s %d/%d" % [Bestiary.TABS[i]["name"], pr.x, pr.y]
	for i in cards.size():
		portraits[i].show_entry(Bestiary.ENTRIES[i], Bestiary.is_known(Bestiary.ENTRIES[i]["key"]))
		cards[i].get_child(1).queue_redraw()


## Показать вкладку: остальные карточки прячутся, выбор — на первой видимой.
func show_tab(i: int) -> void:
	tab = clampi(i, 0, Bestiary.TABS.size() - 1)
	tabs.select(tab)
	var ids := Bestiary.tab_entries(tab)
	for k in cards.size():
		cards[k].visible = k in ids
	if not selected in ids:
		_select(ids[0])
	else:
		_select(selected)
	first_focus = cards[selected]
	fit()


func _select(i: int) -> void:
	var prev := selected
	selected = i
	var e: Dictionary = Bestiary.ENTRIES[i]
	var known := Bestiary.is_known(e["key"])
	sheet_portrait.show_entry(e, known)
	if known:
		Bestiary.mark_read(e["key"])  # метка «НОВОЕ» гаснет, как только дело открыли
	_fill_sheet(e, known)
	stamp.queue_redraw()
	cards[prev].get_child(1).queue_redraw()
	cards[i].get_child(1).queue_redraw()
	if visible:
		var n := Bestiary.new_count()
		counter.text = "Открыто %d из %d%s" % [Bestiary.known_count(), Bestiary.total(),
			"  •  новых: %d" % n if n > 0 else ""]


func _fill_sheet(e: Dictionary, known: bool) -> void:
	var num := Bestiary.ENTRIES.find(e) + 1
	if not known:
		sheet_title.text = "ДЕЛО № %02d — НЕ ЗАПОЛНЕНО" % num
		sheet_group.text = String(e["group"])
		sheet_text.text = "Объект ещё не встречался в эксперименте."
		sheet_weak.text = Bestiary.where_text(e)
		sheet_tip.text = ""
		sheet_stats.text = ""
		return
	sheet_title.text = "ДЕЛО № %02d: %s" % [num, String(e["title"]).to_upper()]
	sheet_group.text = String(e["group"])
	sheet_text.text = String(e["text"])
	sheet_weak.text = "Слабое место: " + String(e["weak"])
	sheet_tip.text = "Совет: " + String(e["tip"])
	sheet_stats.text = stats_line(e["key"])


## «Встречено: 12 • Побеждено: 9 • Впервые: этап «Медведи»».
static func stats_line(key: String) -> String:
	var st := Bestiary.stats(key)
	if st.is_empty():
		return ""
	var parts := ["Встречено: %d" % int(st["met"])]
	if key != "scientist":
		parts.append("Побеждено: %d" % int(st["beaten"]))
	var stage := int(st.get("stage", -1))
	if stage >= 0 and stage < Balance.STAGES.size():
		parts.append("Впервые: этап «%s»" % String(Balance.STAGES[stage]["short"]).capitalize())
	return "  •  ".join(parts)


func _draw_card(art: Control, i: int) -> void:
	var e: Dictionary = Bestiary.ENTRIES[i]
	var known := Bestiary.is_known(e["key"])
	var font := Design.font("bold")
	var name := String(e["title"]).replace("Приём: ", "") if known else "???"
	var fs := 13
	var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while w > art.size.x - 10.0 and fs > 9:  # длинное имя — мельче, но целиком
		fs -= 1
		w = font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	art.draw_string(font, Vector2((art.size.x - w) / 2.0, art.size.y - 10), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Design.CREAM if known else Design.FAINT)
	if known and Bestiary.is_new(e["key"]):  # «НОВОЕ» — красная плашка в углу
		var tag := Rect2(art.size.x - 50, 4, 46, 16)
		art.draw_rect(tag, Design.danger())
		art.draw_string(Design.font("heavy"), tag.position + Vector2(4, 12), "НОВОЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Design.CREAM)
	if i == selected:
		art.draw_style_box(Design.focus_ring(Design.RADIUS_MD, 0.0), Rect2(Vector2.ZERO, art.size))


## Сетка — по ширине экрана: от 4 до 8 колонок.
func fit() -> void:
	if grid and is_inside_tree():
		var sep := float(grid.get_theme_constant("h_separation"))
		var avail := size.x - Design.SPACE[5] * 2.0 - 80.0 - SHEET_W - Design.SPACE[4]
		grid.columns = clampi(int((avail + sep) / (CARD.x + sep)), MIN_COLS, MAX_COLS)
	super()
