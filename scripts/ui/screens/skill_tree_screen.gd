extends "res://scripts/ui/screens/screen.gd"
## Экран «ДРЕВО НАВЫКОВ»: три ветки узлов со связями, описание выбранного узла, счётчик чешуек,
## сброс навыков с возвратом чешуек.

const Skills = preload("res://scripts/core/skills.gd")
const Icons = preload("res://scripts/ui/icons.gd")

var grid: GridContainer
var node_buttons: Dictionary = {}  # id -> Button
var scales_label: Label
var desc_title: Label
var desc_label: Label
var reset_button: Button
var reset_armed := false
var selected := "hide"


func build() -> void:
	make_frame(Design.SPACE[3])
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
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", Design.SPACE[5])
	grid.add_theme_constant_override("v_separation", Design.SPACE[4])
	grid.draw.connect(_draw_links)
	grid.sort_children.connect(grid.queue_redraw)  # связи рисуем после раскладки кнопок
	var grid_center := CenterContainer.new()
	grid_center.add_child(grid)
	content.add_child(grid_center)
	for b in Skills.BRANCHES:
		grid.add_child(Design.label(b["name"], "overline", b["color"], HORIZONTAL_ALIGNMENT_CENTER))
	for row in 4:
		for branch in 3:
			var n: Dictionary = Skills.TREE[branch * 4 + row]
			var btn := Design.button("", _on_node.bind(n["id"]), "", Vector2(250, 56))
			btn.add_theme_font_size_override("font_size", 16)
			btn.focus_entered.connect(_show_desc.bind(n["id"]))
			btn.mouse_entered.connect(_show_desc.bind(n["id"]))
			grid.add_child(btn)
			node_buttons[n["id"]] = btn
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Design.box(Design.SURFACE_2, Design.LINE, Design.RADIUS_MD, 1,
		Vector2(Design.SPACE[4], Design.SPACE[3])))
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


func open() -> void:
	Skills.ensure_loaded()
	reset_armed = false
	reset_button.text = "СБРОСИТЬ НАВЫКИ"
	refresh()
	_show_desc(selected)
	super()


func refresh() -> void:
	scales_label.text = "%d чешуек" % Skills.scales
	for id: String in node_buttons:
		var btn: Button = node_buttons[id]
		var n := Skills.node(id)
		var r := Skills.rank(id)
		var branch_col: Color = Skills.BRANCHES[n["branch"]]["color"]
		var state := "%d/%d" % [r, int(n["max"])]
		if Skills.maxed(id):
			state += "  •  МАКС"
		elif not Skills.unlocked(id):
			state += "  •  закрыто"
		else:
			state += "  •  %d ч." % Skills.cost(id)
		btn.text = "%s\n%s" % [n["name"], state]
		var bg := Design.SURFACE_2
		var border := Design.LINE
		if Skills.maxed(id):
			bg = branch_col.darkened(0.6)
			border = Design.YOLK
		elif r > 0:
			bg = branch_col.darkened(0.7)
			border = branch_col
		elif Skills.can_buy(id):
			border = branch_col.darkened(0.25)
		btn.modulate = Color(1, 1, 1, 1.0 if Skills.unlocked(id) else 0.5)
		btn.add_theme_stylebox_override("normal", Design.box(bg, border, Design.RADIUS_MD, 2, Vector2(12, 8)))
		btn.add_theme_stylebox_override("hover", Design.box(bg.lightened(0.08), Design.CREAM, Design.RADIUS_MD, 2, Vector2(12, 8)))
		btn.add_theme_stylebox_override("pressed", Design.box(bg.darkened(0.2), Design.YOLK, Design.RADIUS_MD, 2, Vector2(12, 8)))
	grid.queue_redraw()


func _draw_links() -> void:
	for branch in 3:
		for row in range(1, 4):
			var a: Button = node_buttons[Skills.TREE[branch * 4 + row - 1]["id"]]
			var b: Button = node_buttons[Skills.TREE[branch * 4 + row]["id"]]
			var from := a.position + Vector2(a.size.x / 2.0, a.size.y)
			var to := b.position + Vector2(b.size.x / 2.0, 0)
			var lit := Skills.rank(Skills.TREE[branch * 4 + row - 1]["id"]) > 0
			var col: Color = Skills.BRANCHES[branch]["color"] if lit else Design.LINE
			grid.draw_line(from, to, Design.INK, 8.0)
			grid.draw_line(from, to, col, 4.0)


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
		text += "\nЦена следующего ранга: %d чешуек." % Skills.cost(id)
	desc_label.text = text


func _on_node(id: String) -> void:
	if Skills.buy(id):
		Design.play("perk")
	else:
		Design.play("no_stamina")
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
