extends VBoxContainer
## Экран «ДРЕВО НАВЫКОВ»: три ветки кнопок-узлов со связями, описание выбранного узла,
## счётчик чешуек, сброс навыков. Строится hud.gd (берёт его шрифты и кнопки).

signal closed

const Skills = preload("res://scripts/skills.gd")
const GOLD := Color(1, 0.82, 0.3)

var hud  # hud.gd (без типа — чтобы не было циклического preload)
var grid: GridContainer
var node_buttons: Dictionary = {}  # id -> Button
var scales_label: Label
var desc_label: Label
var reset_button: Button
var reset_armed := false
var first: Button


func build(owner_hud) -> void:
	hud = owner_hud
	add_theme_constant_override("separation", 12)
	add_child(hud._centered(hud._label("ДРЕВО НАВЫКОВ", 44, GOLD, true)))
	scales_label = hud._centered(hud._label("", 21, Color(0.6, 1, 0.7), true))
	add_child(scales_label)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 22)
	grid.draw.connect(_draw_links)
	grid.sort_children.connect(grid.queue_redraw)  # связи рисуем после раскладки кнопок
	add_child(grid)
	for b in Skills.BRANCHES:
		grid.add_child(hud._centered(hud._label(b["name"], 20, b["color"], true)))
	for row in 4:
		for branch in 3:
			var n: Dictionary = Skills.TREE[branch * 4 + row]
			var btn: Button = hud._button("", _on_node.bind(n["id"]))
			btn.custom_minimum_size = Vector2(260, 62)
			btn.add_theme_font_size_override("font_size", 17)
			btn.focus_entered.connect(_show_desc.bind(n["id"]))
			btn.mouse_entered.connect(_show_desc.bind(n["id"]))
			grid.add_child(btn)
			node_buttons[n["id"]] = btn
	first = node_buttons["hide"]
	desc_label = hud._centered(hud._label("", 18, Color(1, 0.95, 0.88)))
	desc_label.custom_minimum_size = Vector2(0, 52)
	add_child(desc_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	reset_button = hud._button("СБРОСИТЬ НАВЫКИ", _on_reset)
	reset_button.custom_minimum_size = Vector2(300, 52)
	row.add_child(reset_button)
	var back: Button = hud._button("НАЗАД", closed.emit)
	back.custom_minimum_size = Vector2(200, 52)
	row.add_child(back)


func open() -> void:
	Skills.ensure_loaded()
	reset_armed = false
	reset_button.text = "СБРОСИТЬ НАВЫКИ"
	refresh()
	first.grab_focus.call_deferred()
	_show_desc("hide")


func refresh() -> void:
	scales_label.text = "Чешуйки: %d" % Skills.scales
	for id: String in node_buttons:
		var btn: Button = node_buttons[id]
		var n := Skills.node(id)
		var r := Skills.rank(id)
		var mx: int = n["max"]
		var branch_col: Color = Skills.BRANCHES[n["branch"]]["color"]
		var state := "%d/%d" % [r, mx]
		if Skills.maxed(id):
			state += "  • МАКС"
		elif not Skills.unlocked(id):
			state += "  • закрыто"
		else:
			state += "  • %d ч." % Skills.cost(id)
		btn.text = "%s\n%s" % [n["name"], state]
		var bg := Color(0.16, 0.11, 0.08)
		var border := Color(0.35, 0.28, 0.2)
		if Skills.maxed(id):
			bg = branch_col.darkened(0.55)
			border = GOLD
		elif r > 0:
			bg = branch_col.darkened(0.65)
			border = branch_col
		elif Skills.can_buy(id):
			border = branch_col.darkened(0.2)
		btn.modulate = Color(1, 1, 1, 1.0 if Skills.unlocked(id) else 0.5)
		btn.add_theme_stylebox_override("normal", hud._box(bg, border, 12, 3))
		btn.add_theme_stylebox_override("hover", hud._box(bg.lightened(0.1), Color.WHITE, 12, 3))
		btn.add_theme_stylebox_override("pressed", hud._box(bg.darkened(0.2), Color.WHITE, 12, 3))
	grid.queue_redraw()


func _draw_links() -> void:
	for branch in 3:
		for row in range(1, 4):
			var a: Button = node_buttons[Skills.TREE[branch * 4 + row - 1]["id"]]
			var b: Button = node_buttons[Skills.TREE[branch * 4 + row]["id"]]
			var from := a.position + Vector2(a.size.x / 2.0, a.size.y)
			var to := b.position + Vector2(b.size.x / 2.0, 0)
			var lit := Skills.rank(Skills.TREE[branch * 4 + row - 1]["id"]) > 0
			var col: Color = Skills.BRANCHES[branch]["color"] if lit else Color(0.35, 0.28, 0.2)
			grid.draw_line(from, to, Color(0.05, 0.03, 0.02), 9.0)
			grid.draw_line(from, to, col, 5.0)


func _show_desc(id: String) -> void:
	var n := Skills.node(id)
	var text: String = n["desc"]
	if not Skills.unlocked(id):
		text += "\nСначала вкачай предыдущий навык ветки"
	elif not Skills.maxed(id):
		text += "\nЦена: %d чешуек" % Skills.cost(id)
	desc_label.text = text


func _on_node(id: String) -> void:
	if Skills.buy(id):
		hud._sound("perk")
	else:
		hud._sound("no_stamina")
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
