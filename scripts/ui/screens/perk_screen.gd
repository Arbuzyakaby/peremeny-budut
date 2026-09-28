extends "res://scripts/ui/screens/screen.gd"
## Выбор мутации между этапами: три карточки (с навыком «Четвёртая карта» — четыре).
## На карточке — редкость. Мышь, тач или клавиши 1–4.

const Skills = preload("res://scripts/core/skills.gd")

signal perk_chosen(id: String)

var heading: Label
var cards: Array[Button] = []
var names: Array[Label] = []
var descs: Array[Label] = []
var rarities: Array[Label] = []
var ids: Array = []
var hint: Label


func build() -> void:
	make_frame(Design.SPACE[4])
	heading = title("", "h3", Design.MUTED)
	title("ВЫБЕРИ МУТАЦИЮ", "h1")
	var row := Design.hbox(Design.SPACE[4])
	content.add_child(row)
	for i in 4:
		var b := Design.button("", _choose.bind(i), "", Vector2(236, 210))
		var box := Design.vbox(Design.SPACE[2])
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = Design.SPACE[4]
		box.offset_right = -Design.SPACE[4]
		box.offset_top = Design.SPACE[4]
		box.offset_bottom = -Design.SPACE[4]
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		var top := Design.hbox(Design.SPACE[2], BoxContainer.ALIGNMENT_BEGIN)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(Design.label(str(i + 1), "overline", Design.FAINT))
		var rar := Design.label("", "overline", Design.FAINT)
		top.add_child(rar)
		rarities.append(rar)
		box.add_child(top)
		var n := Design.label("", "h3", Design.CREAM)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(n)
		var d := Design.label("", "small", Design.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(d)
		row.add_child(b)
		cards.append(b)
		names.append(n)
		descs.append(d)
	hint = Design.label("", "caption", Design.FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(hint)
	first_focus = cards[0]


func show_perks(list: Array, next_stage: String, touch: bool) -> void:
	ids.clear()
	heading.text = "ДАЛЬШЕ: " + next_stage
	hint.text = "Нажми на карточку" if touch else "Клавиши 1–%d, мышь или Enter" % list.size()
	for i in cards.size():
		cards[i].visible = i < list.size()
		if i >= list.size():
			continue
		var c: Dictionary = list[i]
		var r: Dictionary = Skills.RARITY[int(c.get("rarity", 0))]
		rarities[i].text = r["name"]
		rarities[i].label_settings.font_color = r["color"]
		ids.append(c["id"])
		var col: Color = c["color"]
		names[i].text = c["name"]
		names[i].label_settings.font_color = col.lightened(0.3)
		descs[i].text = (c["desc"] as String).replace("\n", " ")
		var b := cards[i]
		for st in ["normal", "hover", "pressed", "hover_pressed"]:  # карточка-клавиша с лампой цвета улучшения
			b.add_theme_stylebox_override(st, Design.card_style(col, st, Design.RADIUS_LG))
		Design.appear(b, 0.1 + i * Design.STAGGER * 2.0)
	open()
	Design.play("perk")


func _choose(i: int) -> void:
	if not visible or i >= ids.size():
		return
	close()
	perk_chosen.emit(ids[i])


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k < KEY_1 + ids.size():
			Design.play("ui_select")
			_choose(k - KEY_1)
			get_viewport().set_input_as_handled()


func handle_back() -> bool:
	return true  # улучшение обязательно выбрать
