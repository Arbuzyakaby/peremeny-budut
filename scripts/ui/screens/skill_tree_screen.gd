extends "res://scripts/ui/screens/screen.gd"
## Экран «ДРЕВО НАВЫКОВ»: четыре ветки по пять узлов-медальонов со светящимися связями, описание
## выбранного узла, счётчик чешуек, сброс навыков с возвратом чешуек.

const Skills = preload("res://scripts/core/skills.gd")
const Icons = preload("res://scripts/ui/icons.gd")

const NODE_SIZE := Vector2(238, 54)
const MEDALLION := 36.0

var grid: GridContainer
var node_buttons: Dictionary = {}  # id -> Button
var node_medallions: Dictionary = {}  # id -> Control (медальон с иконкой ветки)
var node_pips: Dictionary = {}  # id -> Array[Control] (индикаторы рангов)
var node_state_labels: Dictionary = {}  # id -> Label (цена / МАКС / закрыто)
var scales_label: Label
var desc_title: Label
var desc_label: Label
var reset_button: Button
var reset_armed := false
var selected := "hide"


func build() -> void:
	# v12.0: плотнее по вертикали — на экране 720 px кнопки «Сбросить» и «Готово» видны без прокрутки
	make_frame(Design.SPACE[2], Design.plank(Color(0, 0, 0, 0), Design.RADIUS_LG, Vector2(Design.SPACE[6], Design.SPACE[4])))
	var head := Design.hbox(Design.SPACE[5])
	head.add_child(Design.label("ДРЕВО НАВЫКОВ", "h2", Design.YOLK))
	var chip_row := Design.hbox(Design.SPACE[2])
	var coin := Control.new()
	coin.custom_minimum_size = Vector2(22, 24)
	coin.draw.connect(func() -> void: Icons.scale_coin(coin, Vector2(11, 12), 1.0))
	chip_row.add_child(coin)
	scales_label = Design.label("", "h3", Design.MINT)
	chip_row.add_child(scales_label)
	head.add_child(chip_row)
	content.add_child(head)
	grid = GridContainer.new()
	grid.columns = Skills.BRANCHES.size()
	grid.add_theme_constant_override("h_separation", Design.SPACE[5])
	grid.add_theme_constant_override("v_separation", Design.SPACE[2])
	grid.draw.connect(_draw_links)
	grid.sort_children.connect(grid.queue_redraw)  # связи рисуем после раскладки кнопок
	var grid_center := CenterContainer.new()
	grid_center.add_child(grid)
	content.add_child(grid_center)
	for b in Skills.BRANCHES:
		var head_col := Design.hbox(Design.SPACE[2], BoxContainer.ALIGNMENT_CENTER)
		var bi := Control.new()
		bi.custom_minimum_size = Vector2(20, 20)
		bi.draw.connect(_draw_branch_icon.bind(bi, Skills.BRANCHES.find(b)))
		head_col.add_child(bi)
		head_col.add_child(Design.label(b["name"], "overline", b["color"], HORIZONTAL_ALIGNMENT_CENTER))
		grid.add_child(head_col)
	for row in Skills.ROWS:
		for branch in Skills.BRANCHES.size():
			var n: Dictionary = Skills.TREE[branch * Skills.ROWS + row]
			grid.add_child(_build_node(n))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Design.well(Design.RADIUS_MD, Vector2(Design.SPACE[4], Design.SPACE[3])))
	var desc_box := Design.vbox(Design.SPACE[1])
	card.add_child(desc_box)
	desc_title = Design.label("", "h3", Design.YOLK)
	desc_box.add_child(desc_title)
	desc_label = Design.label("", "small", Design.CREAM)
	desc_label.custom_minimum_size = Vector2(0, 40)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_box.add_child(desc_label)
	content.add_child(card)
	var row := Design.hbox(Design.SPACE[4])
	content.add_child(row)
	reset_button = Design.button("СБРОСИТЬ НАВЫКИ", _on_reset, "Ghost", Vector2(290, Design.TOUCH_MIN))
	row.add_child(reset_button)
	row.add_child(Design.button("ГОТОВО", closed.emit, "Primary", Vector2(210, Design.TOUCH_MIN)))
	first_focus = node_buttons["hide"]


## Медальон узла: круглая иконка ветки, кольцо ранга, замок или галочка максимума.
func _build_node(n: Dictionary) -> Button:
	var id: String = n["id"]
	var btn := Design.button("", _on_node.bind(id), "", NODE_SIZE)
	node_buttons[id] = btn
	var overlay := MarginContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_theme_constant_override("margin_left", Design.SPACE[3])
	overlay.add_theme_constant_override("margin_right", Design.SPACE[3])
	overlay.add_theme_constant_override("margin_top", Design.SPACE[1])
	overlay.add_theme_constant_override("margin_bottom", Design.SPACE[1])
	btn.add_child(overlay)
	var hb := Design.hbox(Design.SPACE[3], BoxContainer.ALIGNMENT_BEGIN)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(hb)
	var med := Control.new()
	med.custom_minimum_size = Vector2(MEDALLION, MEDALLION)
	med.mouse_filter = Control.MOUSE_FILTER_IGNORE
	med.draw.connect(_draw_medallion.bind(med, id))
	hb.add_child(med)
	node_medallions[id] = med
	var vb := Design.vbox(2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(vb)
	var name_label := Design.label(n["name"], "small", Design.CREAM)
	name_label.label_settings = Design.label_settings("small", Design.CREAM)
	name_label.label_settings.font = Design.font("heavy")
	name_label.clip_contents = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vb.add_child(name_label)
	var state_row := Design.hbox(Design.SPACE[1], BoxContainer.ALIGNMENT_BEGIN)
	state_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(state_row)
	var pip_row := Design.hbox(4, BoxContainer.ALIGNMENT_BEGIN)
	pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_row.add_child(pip_row)
	var pips: Array[Control] = []
	for i in int(n["max"]):
		var pip := Control.new()
		pip.custom_minimum_size = Vector2(10, 10)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.draw.connect(_draw_pip.bind(pip, id, i))
		pip_row.add_child(pip)
		pips.append(pip)
	node_pips[id] = pips
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(Design.SPACE[2], 0)
	state_row.add_child(spacer)
	var state_label := Design.label("", "caption", Design.MUTED)
	state_row.add_child(state_label)
	node_state_labels[id] = state_label
	btn.focus_entered.connect(_show_desc.bind(id))
	btn.mouse_entered.connect(_show_desc.bind(id))
	return btn


func _draw_branch_icon(bi: Control, branch: int) -> void:
	var c := bi.size / 2.0
	var col: Color = Skills.BRANCHES[branch]["color"]
	match branch:
		0: Icons.heart(bi, c, 6.0, col)
		1: Icons.bolt(bi, c, col, 0.9)
		2: Icons.fang(bi, c, col, 0.9)
		_: Icons.scale_coin(bi, c, 0.8)


func _draw_medallion(med: Control, id: String) -> void:
	var n := Skills.node(id)
	var branch_col: Color = Skills.BRANCHES[n["branch"]]["color"]
	var unlocked := Skills.unlocked(id)
	var maxed := Skills.maxed(id)
	var ranked := Skills.rank(id) > 0
	var c := med.size / 2.0
	var r := MEDALLION / 2.0 - 2.0
	med.draw_circle(c, r + 2.5, Design.INK)
	med.draw_circle(c, r, branch_col.darkened(0.55) if ranked or maxed else Design.SURFACE_0)
	med.draw_arc(c, r, 0, TAU, 28, branch_col if unlocked else Design.LINE, 2.5, true)
	if maxed:
		med.draw_arc(c, r + 3.0, 0, TAU, 28, Design.YOLK, 2.0, true)
	var icon_col := Color(1, 1, 1, 0.95) if unlocked else Color(Design.FAINT, 0.8)
	match n["branch"]:
		0: Icons.heart(med, c, 6.5, icon_col)
		1: Icons.bolt(med, c, icon_col, 1.0)
		2: Icons.fang(med, c, icon_col, 1.0)
		_: Icons.scale_coin(med, c, 0.85 if unlocked else 0.6)
	if not unlocked:
		med.draw_circle(c, r, Color(0, 0, 0, 0.5))
		Icons.lock(med, c, Design.MUTED, 0.8)
	if maxed:
		var badge := c + Vector2(r, -r) * 0.75
		med.draw_circle(badge, 8.0, Design.INK)
		med.draw_circle(badge, 6.5, Design.YOLK)
		Icons.check(med, badge, Design.INK, 0.45)


func _draw_pip(pip: Control, id: String, i: int) -> void:
	var n := Skills.node(id)
	var branch_col: Color = Skills.BRANCHES[n["branch"]]["color"]
	var c := pip.size / 2.0
	var filled := i < Skills.rank(id)
	if filled:
		pip.draw_circle(c, 5.0, branch_col)
	else:
		pip.draw_circle(c, 5.0, Design.SURFACE_0)
		pip.draw_arc(c, 4.0, 0, TAU, 12, Color(Design.LINE, 0.9), 1.5, true)


func open() -> void:
	Skills.ensure_loaded()
	reset_armed = false
	reset_button.text = "СБРОСИТЬ НАВЫКИ"
	refresh()
	_show_desc(selected)
	super()


func refresh() -> void:
	scales_label.text = Design.scales_text(Skills.scales)
	for id: String in node_buttons:
		var btn: Button = node_buttons[id]
		var n := Skills.node(id)
		var branch_col: Color = Skills.BRANCHES[n["branch"]]["color"]
		var state_label: Label = node_state_labels[id]
		if Skills.maxed(id):
			state_label.text = "МАКС"
			state_label.label_settings.font_color = Design.YOLK
		elif not Skills.unlocked(id):
			state_label.text = "закрыто"
			state_label.label_settings.font_color = Design.FAINT
		else:
			state_label.text = "%d чеш." % Skills.cost(id)
			state_label.label_settings.font_color = Design.MINT if Skills.can_buy(id) else Design.MUTED
		var border := Design.LINE
		if Skills.maxed(id):
			border = Design.YOLK
		elif Skills.rank(id) > 0:
			border = branch_col
		elif Skills.can_buy(id):
			border = branch_col.darkened(0.25)
		btn.modulate = Color(1, 1, 1, 1.0 if Skills.unlocked(id) else 0.55)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:  # клавиша узла: кромка и лампа ветки
			var sb := Design.card_style(border if st == "normal" else (Design.CREAM if st == "hover" else Design.YOLK), st,
				Design.RADIUS_MD, Vector2.ZERO)
			if Skills.rank(id) == 0:
				sb.lamp = Color(0, 0, 0, 0)
			btn.add_theme_stylebox_override(st, sb)
		node_medallions[id].queue_redraw()
		for pip in node_pips[id]:
			pip.queue_redraw()
	grid.queue_redraw()


## Связь между узлом и следующим рангом ветки: светится и «бьётся жилками», если открыта.
func _draw_links() -> void:
	for branch in Skills.BRANCHES.size():
		for row in range(1, Skills.ROWS):
			var a: Button = node_buttons[Skills.TREE[branch * Skills.ROWS + row - 1]["id"]]
			var b: Button = node_buttons[Skills.TREE[branch * Skills.ROWS + row]["id"]]
			var from := a.position + Vector2(MEDALLION / 2.0 + Design.SPACE[3], a.size.y)
			var to := b.position + Vector2(MEDALLION / 2.0 + Design.SPACE[3], 0)
			var lit := Skills.rank(Skills.TREE[branch * Skills.ROWS + row - 1]["id"]) > 0
			var col: Color = Skills.BRANCHES[branch]["color"] if lit else Design.LINE
			if lit:
				grid.draw_line(from, to, Color(col, 0.35), 9.0)
				grid.draw_line(from, to, col, 3.5)
				grid.draw_circle(from, 4.5, col)
				grid.draw_circle(to, 4.5, col)
			else:
				grid.draw_dashed_line(from, to, Color(col, 0.85), 2.5, 7.0, true)


func _show_desc(id: String) -> void:
	selected = id
	var n := Skills.node(id)
	desc_title.text = n["name"]
	var text: String = n["desc"]
	if not Skills.unlocked(id):
		text += "\nСначала вкачай предыдущий навык ветки."
	elif Skills.maxed(id):
		text += "\nВкачано до максимума."
	else:
		text += "\nЦена следующего ранга: %s." % Design.scales_text(Skills.cost(id))
	desc_label.text = text


func _on_node(id: String) -> void:
	if Skills.buy(id):
		Design.play("perk")
	else:
		Design.refuse(node_buttons[id])
	refresh()
	_show_desc(id)


func _on_reset() -> void:
	if not reset_armed:
		reset_armed = true
		reset_button.text = "ТОЧНО? ЖМИ ЕЩЁ РАЗ"
		return
	reset_armed = false
	reset_button.text = "НАВЫКИ СБРОШЕНЫ"
	Skills.reset_all()
	refresh()
