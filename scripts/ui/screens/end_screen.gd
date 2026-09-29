extends "res://scripts/ui/screens/screen.gd"
## Итоги забега: заголовок (победа / поражение / «КОНЕЦ»), строки статистики, чешуйки, кнопки.
## После гибели — совет по причине удара и клавиша «ПОВТОР» (запись последних секунд, replay_screen.gd).
## Новый рекорд (дизайн-язык 2.3) — красный штамп протокола «РЕКОРД» у заголовка.

signal retry_requested
signal menu_requested
signal replay_requested

var head: Label
var headline: Label
var stats: VBoxContainer
var tip_label: Label
var replay_button: Button
var stamp: Control
var stamp_k := 0.0  # штамп «прилетает» сверху и пристукивается


func build() -> void:
	make_frame(Design.SPACE[3])
	head = title("", "display")
	stamp = Control.new()
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	stamp.draw.connect(func() -> void:  # справа от строк итогов, поверх прокрутки
		var to_local := stamp.get_global_transform().affine_inverse() * panel.get_global_transform()
		var at := to_local * Vector2(panel.size.x - 170, panel.size.y * 0.56)
		Design.draw_stamp(stamp, at, "РЕКОРД", Design.danger(), -0.18, 26, 1.0 + 0.6 * (1.0 - stamp_k)))
	add_child(stamp)
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


func _process(_delta: float) -> void:
	if visible and stamp.visible:
		stamp.modulate.a = stamp_k
		stamp.queue_redraw()


func handle_back() -> bool:
	menu_requested.emit()
	return true
