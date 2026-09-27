extends "res://scripts/ui/screens/screen.gd"
## Итоги забега: заголовок (победа / поражение / «КОНЕЦ»), строки статистики, чешуйки, кнопки.
## После гибели — совет по причине удара и клавиша «ПОВТОР» (запись последних секунд, replay_screen.gd).

signal retry_requested
signal menu_requested
signal replay_requested

var head: Label
var headline: Label
var stats: VBoxContainer
var tip_label: Label
var replay_button: Button


func build() -> void:
	make_frame(Design.SPACE[3])
	head = title("", "display")
	headline = Design.label("", "h3", Design.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(headline)
	content.add_child(HSeparator.new())
	stats = Design.vbox(Design.SPACE[1])
	content.add_child(stats)
	content.add_child(HSeparator.new())
	var row := Design.hbox(Design.SPACE[4])
	content.add_child(row)
	first_focus = Design.button("ЕЩЁ РАЗ", retry_requested.emit, "Primary", Vector2(230, Design.TOUCH_MIN + 4))
	row.add_child(first_focus)
	row.add_child(Design.button("В МЕНЮ", menu_requested.emit, "", Vector2(230, Design.TOUCH_MIN + 4)))
	replay_button = Design.button("ПОВТОР", replay_requested.emit, "Ghost", Vector2(160, Design.TOUCH_MIN + 4))
	row.add_child(replay_button)
	tip_label = Design.label("", "small", Design.STEEL.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(560, 0)
	content.add_child(tip_label)


## rows — пары [подпись, значение]; highlight — строки, которые подсвечиваются золотом.
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
	for c in stats.get_children():
		c.queue_free()
	for i in rows.size():
		var r: Array = rows[i]
		var h := Design.hbox(Design.SPACE[5], BoxContainer.ALIGNMENT_BEGIN)
		var k := Design.label(r[0], "small", Design.MUTED)
		k.custom_minimum_size = Vector2(220, 0)
		h.add_child(k)
		var accent: bool = r.size() > 2 and r[2]
		h.add_child(Design.label(r[1], "h3", Design.YOLK if accent else Design.CREAM))
		stats.add_child(h)
		Design.appear(h, 0.25 + i * Design.STAGGER * 2.0, 0.0)
	open()


func handle_back() -> bool:
	menu_requested.emit()
	return true
