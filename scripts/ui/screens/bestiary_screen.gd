extends "res://scripts/ui/screens/screen.gd"
## Картотека врагов: сетка карточек-«дел». Неизвестный враг — серый силуэт с вопросом;
## открытая карточка показывает рисунок, описание, слабое место и совет на кремовой бумаге.

const Bestiary = preload("res://scripts/core/bestiary.gd")
const Icons = preload("res://scripts/ui/icons.gd")

const CARD := Vector2(112, 92)
const PAPER := Color(0.97, 0.92, 0.8)
const PAPER_INK := Color(0.2, 0.12, 0.06)

var grid: GridContainer
var cards: Array[Button] = []
var counter: Label
var sheet: Control
var selected := 0


func build() -> void:
	make_frame(Design.SPACE[3])
	title("КАРТОТЕКА", "h1")
	counter = Design.label("", "caption", Design.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(counter)
	grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", Design.SPACE[2])
	grid.add_theme_constant_override("v_separation", Design.SPACE[2])
	var gc := CenterContainer.new()
	gc.add_child(grid)
	content.add_child(gc)
	for i in Bestiary.ENTRIES.size():
		var b := Design.button("", _select.bind(i), "Card", CARD)
		b.focus_entered.connect(_select.bind(i))
		var art := Control.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.draw.connect(_draw_card.bind(art, i))
		b.add_child(art)
		grid.add_child(b)
		cards.append(b)
	sheet = Control.new()
	sheet.custom_minimum_size = Vector2(CARD.x * 6 + Design.SPACE[2] * 5, 170)
	sheet.draw.connect(_draw_sheet)
	content.add_child(sheet)
	var back := Design.button("НАЗАД", func() -> void: closed.emit(), "Primary", Vector2(220, Design.TOUCH_MIN))
	var bc := CenterContainer.new()
	bc.add_child(back)
	content.add_child(bc)
	first_focus = cards[0]


func open() -> void:
	Bestiary.ensure_loaded()
	counter.text = "Открыто %d из %d" % [Bestiary.known_count(), Bestiary.total()]
	for c in cards:
		c.queue_redraw()
		c.get_child(0).queue_redraw()
	_select(selected)
	super()


func _select(i: int) -> void:
	selected = i
	sheet.queue_redraw()


static func draw_entry_icon(ci: CanvasItem, e: Dictionary, c: Vector2, s: float, known: bool) -> void:
	var a := 1.0 if known else 0.0
	if not known:  # силуэт неизвестного
		ci.draw_circle(c, 22.0 * s / 2.0, Color(0, 0, 0, 0.35))
		ci.draw_string(Design.font("heavy"), c + Vector2(-8, 11) * s / 2.0, "?", HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(30 * s / 2.0), Color(Design.FAINT, 0.9))
		return
	match e["icon"]:
		"bear":
			if int(e["arg"]) == 0:
				Icons.bear(ci, c, s, a)
			else:
				Icons.ability(ci, c, int(e["arg"]), 0.0, s)
		"fork":
			Icons.fork_kind(ci, c, int(e["arg"]), s, a)
		"fork_atk":
			Icons.fork_attack(ci, c, int(e["arg"]), Design.warn(), s)
		"pill":
			Icons.pill(ci, c, s, a)
		"egg":
			Icons.egg(ci, c, s, a)


func _draw_card(art: Control, i: int) -> void:
	var e: Dictionary = Bestiary.ENTRIES[i]
	var known := Bestiary.is_known(e["key"])
	draw_entry_icon(art, e, Vector2(art.size.x / 2.0, 36), 1.6, known)
	var font := Design.font("bold")
	var name := String(e["title"]).replace("Приём: ", "") if known else "???"
	var fs := 13
	var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while w > art.size.x - 10.0 and fs > 9:  # длинное имя — мельче, но целиком
		fs -= 1
		w = font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	art.draw_string(font, Vector2((art.size.x - w) / 2.0, art.size.y - 12), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Design.CREAM if known else Design.FAINT)
	if i == selected:
		art.draw_rect(Rect2(Vector2(3, 3), art.size - Vector2(6, 6)), Color(Design.YOLK, 0.8), false, 2.0)


## Карточка «дела»: кремовая бумага, скрепка, машинописный текст.
func _draw_sheet() -> void:
	var r := Rect2(Vector2(0, 4), sheet.size - Vector2(0, 8))
	sheet.draw_rect(r.grow(2), Color(0, 0, 0, 0.3))
	sheet.draw_rect(r, PAPER)
	for y in range(int(r.position.y) + 34, int(r.end.y), 22):  # линовка
		sheet.draw_line(Vector2(r.position.x + 12, y), Vector2(r.end.x - 12, y), Color(0.55, 0.65, 0.85, 0.3), 1.0)
	sheet.draw_line(Vector2(r.position.x + 150, r.position.y), Vector2(r.position.x + 150, r.end.y), Color(0.9, 0.35, 0.35, 0.4), 1.5)
	# скрепка
	var clip := Vector2(r.end.x - 40, r.position.y - 6)
	sheet.draw_arc(clip + Vector2(0, 14), 7.0, PI, TAU, 10, Color(0.6, 0.62, 0.66), 2.5)
	sheet.draw_line(clip + Vector2(-7, 14), clip + Vector2(-7, 36), Color(0.6, 0.62, 0.66), 2.5)
	sheet.draw_line(clip + Vector2(7, 14), clip + Vector2(7, 30), Color(0.6, 0.62, 0.66), 2.5)
	var e: Dictionary = Bestiary.ENTRIES[selected]
	var known := Bestiary.is_known(e["key"])
	draw_entry_icon(sheet, e, Vector2(r.position.x + 75, r.position.y + 80), 3.0, known)
	var mono := Design.font("mono")
	var semi := Design.font("heavy")
	var x := r.position.x + 166
	var y := r.position.y + 28
	var width := r.size.x - 166 - 60
	var text_w := width - 150.0  # справа внизу — штамп
	if not known:
		sheet.draw_string(semi, Vector2(x, y), "ДЕЛО № %02d — НЕ ЗАПОЛНЕНО" % (selected + 1), HORIZONTAL_ALIGNMENT_LEFT, width, 20, PAPER_INK)
		sheet.draw_string(mono, Vector2(x, y + 30), "Объект ещё не встречался в эксперименте.", HORIZONTAL_ALIGNMENT_LEFT, width, 14,
			Color(PAPER_INK, 0.7))
		return
	sheet.draw_string(semi, Vector2(x, y), "ДЕЛО № %02d: %s" % [selected + 1, String(e["title"]).to_upper()],
		HORIZONTAL_ALIGNMENT_LEFT, width, 20, PAPER_INK)
	sheet.draw_string(mono, Vector2(x, y + 22), String(e["group"]), HORIZONTAL_ALIGNMENT_LEFT, width, 12, Color(0.6, 0.2, 0.15))
	var lines := [[e["text"], PAPER_INK], ["Слабое место: " + String(e["weak"]), Color(0.1, 0.4, 0.2)],
		["Совет: " + String(e["tip"]), Color(0.45, 0.25, 0.05)]]
	var yy := y + 46
	for l: Array in lines:
		sheet.draw_multiline_string(mono, Vector2(x, yy), l[0], HORIZONTAL_ALIGNMENT_LEFT, text_w, 14, 2, l[1])
		yy += 36
	# штамп «ИЗУЧЕНО»
	sheet.draw_set_transform(Vector2(r.end.x - 110, r.end.y - 40), -0.2, Vector2.ONE)
	sheet.draw_rect(Rect2(-56, -18, 112, 34), Color(0.75, 0.15, 0.15, 0.7), false, 3.0)
	sheet.draw_string(semi, Vector2(-46, 8), "ИЗУЧЕНО", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.75, 0.15, 0.15, 0.7))
	sheet.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
