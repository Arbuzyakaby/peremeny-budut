extends "res://scripts/ui/screens/screen.gd"
## Главное меню: анимированный заголовок, карточки сложностей 2×2, древо навыков, настройки, выход.
## Панель слева — справа видна живая демо-арена. Сверху справа сменяются советы.

signal difficulty_chosen(index: int)
signal skills_requested
signal settings_requested
signal quit_requested

const Icons = preload("res://scripts/ui/icons.gd")

const TIPS := [
	"Shift или кнопка СПРИНТ — рывок, но следи за стаминой!",
	"Съешь медведя-боксёра — получишь удар с разбега.",
	"Каратист даёт вертушку: она сбивает даже снаряды.",
	"Пуговицы и иглы можно метать прямо в яичницу!",
	"Стравливай медведей — пусть попадают друг в друга.",
	"Оглушённый медведь приносит двойные очки.",
	"Каратисты бьют больно — держи дистанцию.",
	"Иглы швей пришивают змею — она замедляется.",
	"Вилку не бей в лоб — зубцы! Заходи сбоку или сзади.",
	"Вилка, врезавшаяся в бортик, застревает — кусай!",
	"Таблетку можно съесть, только пока она на земле.",
	"Ударная волна таблетки оглушает — уходи рывком.",
	"Ниндзя появляется сбоку — не подставляй бок.",
	"Хлопушка взрывается и по медведям — стравливай!",
	"Медведя в пузыре не съесть — сначала лопни щит.",
	"Чешуйки из забегов тратятся в Древе навыков.",
	"Вилку в спринте можно направить в яичницу!",
]

var diff_buttons: Array[Button] = []
var desc_label: Label
var tree_button: Button
var quit_button: Button
var controls_label: Label
var tip_label: Label
var title_art: Control
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
	title_art = Control.new()
	title_art.custom_minimum_size = Vector2(440, 104)
	title_art.draw.connect(_draw_title_art)
	content.add_child(title_art)
	subtitle = Design.label("против ГИГАНТСКОЙ ЯИЧНИЦЫ", "h3", Design.YOLK, HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.label_settings = Design.label_settings("h2", Design.YOLK)
	subtitle.label_settings.font_size = 25
	content.add_child(subtitle)
	var choose := Design.label("ВЫБЕРИ СЛОЖНОСТЬ", "overline", Design.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(choose)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Design.SPACE[3])
	grid.add_theme_constant_override("v_separation", Design.SPACE[3])
	var grid_center := CenterContainer.new()
	grid_center.add_child(grid)
	content.add_child(grid_center)
	for i in 4:
		var b := Design.button("", difficulty_chosen.emit.bind(i), "", Vector2(214, 64))
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
	controls_label = Design.label("", "caption", Design.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	controls_label.label_settings = Design.label_settings("hud", Design.MUTED)
	controls_label.label_settings.font_size = 13
	controls_label.anchor_left = 0.5
	controls_label.anchor_right = 1.0
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label.offset_left = Design.SPACE[5]
	controls_label.offset_right = -Design.SPACE[5]
	controls_label.offset_top = 96
	add_child(controls_label)
	fade_items.append(controls_label)

	tip_label = Design.label("", "h3", Design.CREAM, HORIZONTAL_ALIGNMENT_RIGHT)
	tip_label.label_settings = Design.label_settings("hud", Design.CREAM)
	tip_label.anchor_left = 0.5
	tip_label.anchor_right = 1.0
	tip_label.offset_left = Design.SPACE[5]
	tip_label.offset_right = -Design.SPACE[5]
	tip_label.offset_top = Design.SPACE[5]
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tip_label)
	first_focus = diff_buttons[1]


func show_menu(diffs: Array, best_scores: Array, selected: int, scales: int, touch: bool) -> void:
	set_data(diffs, best_scores, selected, scales, touch)
	open()
	_play_intro()
	tip_index = randi() % TIPS.size()
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
		b.add_theme_stylebox_override("normal", Design.box(col.darkened(0.72), col.darkened(0.25), Design.RADIUS_MD))
		b.add_theme_stylebox_override("hover", Design.box(col.darkened(0.55), col, Design.RADIUS_MD))
		b.add_theme_stylebox_override("pressed", Design.box(col.darkened(0.8), col, Design.RADIUS_MD))
		b.add_theme_color_override("font_color", col.lightened(0.35))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
	first_focus = diff_buttons[selected]
	update_scales(scales)
	quit_button.visible = not touch or not OS.has_feature("mobile")
	if touch:
		controls_label.text = "Джойстик слева — поворот  •  кнопки справа — спринт и атака"
	else:
		controls_label.text = "← → / A D / мышь — поворот  •  Shift — спринт\nПробел / ЛКМ — атака медведя  •  Esc — пауза  •  F1 — разработчик"
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
	tip_index = (tip_index + 1) % TIPS.size()
	tip_t = 4.5
	tip_label.text = "СОВЕТ: " + TIPS[tip_index]
	tip_label.modulate.a = 0.0
	create_tween().tween_property(tip_label, "modulate:a", 1.0, 0.4)


func _show_desc(i: int) -> void:
	if difficulties.is_empty():
		return
	var d: Dictionary = difficulties[i]
	desc_label.text = d["desc"]
	desc_label.label_settings.font_color = (d["color"] as Color).lightened(0.45)


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
	title_art.queue_redraw()
	tip_t -= delta
	if tip_t <= 0.0:
		_next_tip()


## Заголовок «ЗМЕЯ»: буквы падают по очереди, потом прыгают волной и переливаются;
## под ними ползёт змейка с языком.
func _draw_title_art() -> void:
	var c := title_art
	var font := Design.font("heavy")
	var text := "ЗМЕЯ"
	var fs := 86
	var widths: Array[float] = []
	var total := 0.0
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0
		widths.append(w)
		total += w
	var x := (c.size.x - total) / 2.0
	var x0 := x
	var calm := Settings.flag("reduced_motion")
	for i in text.length():
		var k := clampf((intro - 0.3 - i * 0.12) / 0.45, 0.0, 1.0)
		if k <= 0.0:
			x += widths[i]
			continue
		var drop := -170.0 * pow(1.0 - k, 2.0)
		var bounce := 0.0 if calm else sin(t * 3.2 - i * 0.8) * 7.0 * k
		var col := Color.from_hsv(0.29 + 0.05 * sin(t * 2.0 + i), 0.72, 0.97, k)
		var rot := 0.0 if calm else sin(t * 2.4 + i * 1.3) * 0.07
		c.draw_set_transform(Vector2(x + widths[i] / 2.0, 78.0 + drop + bounce), rot, Vector2.ONE)
		var off := Vector2(-widths[i] / 2.0 + 3.0, 0)
		c.draw_string_outline(font, off + Vector2(4, 5), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color(0, 0, 0, 0.35 * k))
		c.draw_string_outline(font, off, text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color(0.05, 0.2, 0.05, k))
		c.draw_string(font, off, text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		c.draw_string(font, off + Vector2(0, -3), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.12 * k))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		x += widths[i]
	var k := clampf((intro - 0.9) / 0.6, 0.0, 1.0)  # змейка-подчёркивание
	if k <= 0.0:
		return
	var pts := PackedVector2Array()
	var len := total * k
	for i in 40:
		var px := x0 + len * i / 39.0
		pts.append(Vector2(px, 94.0 + sin(px * 0.045 - t * 6.0) * 5.0))
	c.draw_polyline(pts, Color(0.08, 0.3, 0.1), 13.0)
	c.draw_polyline(pts, Color(0.4, 0.88, 0.35), 9.0)
	var head := pts[pts.size() - 1]
	c.draw_circle(head, 9.0, Color(0.08, 0.3, 0.1))
	c.draw_circle(head, 7.0, Color(0.45, 0.92, 0.4))
	c.draw_circle(head + Vector2(2, -3), 2.2, Color.WHITE)
	c.draw_circle(head + Vector2(2.6, -3), 1.1, Color.BLACK)
	if fmod(t, 1.6) < 0.35:
		c.draw_line(head + Vector2(8, 0), head + Vector2(18, 0), Color(0.85, 0.1, 0.2), 2.0)
		c.draw_line(head + Vector2(18, 0), head + Vector2(22, -3), Color(0.85, 0.1, 0.2), 1.5)
		c.draw_line(head + Vector2(18, 0), head + Vector2(22, 3), Color(0.85, 0.1, 0.2), 1.5)
