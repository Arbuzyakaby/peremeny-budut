extends "res://tests/integration/game_case.gd"
## Экран итогов (v12.4): после 12.3 строк стало 11–18, и на телефоне кнопки уезжали за край панели.
## Проверяем глазами игрока: на любом экране и масштабе кнопки и заголовок видны целиком, панель не шире
## экрана, прокручиваются только строки, а штамп «РЕКОРД» стоит у строки «Счёт».

const RunReport = preload("res://scripts/game/run_report.gd")
const Platform = preload("res://scripts/core/platform.gd")
const Design = preload("res://scripts/ui/design.gd")

## Экраны в логических пикселях интерфейса: ПК 720p, ПК 1080p, узкий телефон 19.5:9, планшет 4:3.
const SCREENS := [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1560, 720), Vector2(1024, 768)]
const SCALES := [1.0, 1.15, 1.3]


func _rows(n: int, long_values := false) -> Array:
	var rows := []
	for i in n:
		var v := str(i * 37)
		if long_values and i % 4 == 0:
			v = "Все медведи, вилки и таблетки согласились жить в мире — кроме одной %d" % i
		rows.append(["Строка итогов %d" % i, v])
	rows.append(["Счёт", "12345  — НОВЫЙ РЕКОРД!", true])
	return rows


## Настоящий забег: полные строки итогов после этапа (прозвище, серия, удары и всё, что добавила 12.3).
func _real_rows() -> Array:
	game.stats.best_combo = 12
	game.stats.hits = 3
	game.stats.flawless = 2
	game.stats.abilities = 9
	game.stats.peak_length = 31
	game.stats.stage_ids = [0, 1]
	game.stats.stage_times = [61.0, 47.0]
	game.enemies.friendly_hits = 4
	return RunReport.rows(game, false, true, 100)


## Поставить интерфейс на экран size с масштабом k (как hud.layout, но без смены окна).
func _set_screen(size: Vector2, k: float) -> void:
	var root: Control = game.hud.root
	root.scale = Vector2(k, k)
	root.position = Vector2.ZERO
	root.size = size / k
	game.hud.end_screen.fit()
	await frames(2)


func _check_fits(label: String) -> void:
	var es = game.hud.end_screen
	var vp := Rect2(Vector2.ZERO, game.hud.root.size * game.hud.root.scale)
	assert_rect_inside(es.panel.get_global_rect(), vp, label + ": панель")
	for b: Control in es.buttons.get_children():
		if b.visible:
			assert_rect_inside(b.get_global_rect(), vp, label + ": кнопка " + b.text)
	assert_rect_inside(es.head.get_global_rect(), vp, label + ": заголовок")
	if es.tip_label.visible:
		assert_rect_inside(es.tip_label.get_global_rect(), vp, label + ": совет")


## Метка значения в n-й ячейке-паре сетки (левое значение завёрнуто в отступ).
func _value(es, n: int) -> Label:
	var c: Control = es.stats.get_child(n * 2 + 1)
	return c if c is Label else c.get_child(0)


func after_each() -> void:
	if is_instance_valid(game):
		game.hud.layout()
	await super.after_each()


func test_buttons_visible_on_every_screen_and_scale() -> void:
	await boot()
	var rows := _rows(17, true)
	game.hud.show_end(false, "", "Не сдавайся — яичница ждёт!", rows)
	for sz: Vector2 in SCREENS:
		for k: float in SCALES:
			await _set_screen(sz, k)
			_check_fits("%dx%d ×%.2f" % [sz.x, sz.y, k])


func test_real_death_rows_fit_on_a_phone() -> void:
	Platform.force_mobile = true
	Platform.force_touch = true
	Settings.reset_to_defaults()
	await boot_stage(1)
	var rows := _real_rows()
	assert_gt(rows.size(), 12, "длинные итоги")
	game.hud.show_end(false, "", RunReport.headline(false), rows)
	game.hud.layout()
	await frames(3)
	_check_fits("телефон")
	var es = game.hud.end_screen
	assert_on_screen(es.first_focus, "ЕЩЁ РАЗ")
	Platform.force_mobile = false
	Platform.force_touch = false


func test_only_rows_scroll_and_start_at_top() -> void:
	await boot()
	game.hud.show_end(false, "", "Тест", _rows(40))
	await _set_screen(Vector2(1280, 720), 1.3)
	var es = game.hud.end_screen
	assert_true(es.buttons.get_parent() != es.content, "кнопки не в прокрутке")
	assert_true(es.head.get_parent() == es.body, "заголовок не в прокрутке")
	assert_eq(es.scroll.scroll_vertical, 0, "прокрутка на первой строке")
	assert_gt(es.content.get_combined_minimum_size().y, es.scroll.size.y, "строк больше окна — есть прокрутка")
	es.first_focus.grab_focus()
	await frames(2)
	assert_eq(es.scroll.scroll_vertical, 0, "фокус на кнопке не прокручивает строки прочь")


func test_two_columns_when_wide_one_when_narrow() -> void:
	await boot()
	game.hud.show_end(false, "", "Тест", _rows(12))
	await _set_screen(Vector2(1920, 1080), 1.0)
	var es = game.hud.end_screen
	assert_eq(es.columns, 2, "на широком экране — две колонки")
	assert_eq(es.stats.columns, 4)
	await _set_screen(Vector2(1024, 768), 1.3)
	assert_eq(es.columns, 1, "на узком — одна")
	game.hud.show_end(false, "", "Тест", _rows(3))
	await _set_screen(Vector2(1920, 1080), 1.0)
	assert_eq(es.columns, 1, "короткие итоги в одну колонку")


func test_two_columns_keep_reading_order() -> void:
	await boot()
	game.hud.show_end(false, "", "Тест", _rows(9))
	await _set_screen(Vector2(1920, 1080), 1.0)
	var es = game.hud.end_screen
	assert_eq(es.columns, 2)
	var cells: Array = es.stats.get_children()
	assert_eq(cells[0].text, "Строка итогов 0", "левая колонка начинается с первой строки")
	assert_eq(cells[2].text, "Строка итогов 5", "правая — с середины списка")
	assert_eq(cells[4].text, "Строка итогов 1", "дальше вниз по левой")


func test_long_values_wrap_instead_of_widening() -> void:
	await boot()
	var rows := [["Убеждено", "Медведей 8 из 8, вилок 5 из 5, таблеток 7 из 7, матрёшек 3 из 3 — все живы"]]
	game.hud.show_end(true, "КОНТАКТ", "Образец №48 договорился со всеми… кроме своего создателя.", rows)
	await _set_screen(Vector2(1280, 720), 1.15)
	var es = game.hud.end_screen
	var v: Label = _value(es, 0)
	assert_eq(v.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "длинное значение переносится")
	assert_gt(v.get_line_count(), 1, "в несколько строк")
	_check_fits("Контакт")


func test_compact_values_when_rows_do_not_fit() -> void:
	await boot()
	game.hud.show_end(false, "", "Тест", _rows(6))
	await _set_screen(Vector2(1920, 1080), 1.0)
	var es = game.hud.end_screen
	assert_false(es.compact, "мало строк — крупные значения")
	game.hud.show_end(false, "", "Тест", _rows(30))
	await _set_screen(Vector2(1280, 720), 1.3)
	assert_true(es.compact, "много строк на маленьком экране — значения мельче")
	var v: Label = _value(es, 0)
	assert_eq(v.label_settings.font_size, Design.size_of("body"))


func test_record_stamp_sits_next_to_score_and_scrolls() -> void:
	await boot()
	game.hud.show_end(false, "", "Тест", _rows(4))
	await _set_screen(Vector2(1280, 720), 1.0)
	var es = game.hud.end_screen
	assert_true(es.stamp.visible)
	assert_true(es.score_label != null, "строка «Счёт» найдена")
	var at: Vector2 = es.stamp_anchor()
	var sr: Rect2 = es.score_label.get_global_rect()
	assert_between(at.y, sr.position.y, sr.end.y, "штамп на высоте строки «Счёт»")
	assert_gt(at.x, sr.position.x, "правее начала значения")
	# длинный список: «Счёт» в конце — пока строка за окном, штампа не видно, прокрутили — появился
	game.hud.show_end(false, "", "Тест", _rows(40))
	await _set_screen(Vector2(1280, 720), 1.3)
	assert_eq(es.stamp_anchor(), Vector2.INF, "строка ниже окна — штамп спрятан")
	es.scroll.scroll_vertical = int(es.content.size.y)
	await frames(2)
	assert_ne(es.stamp_anchor(), Vector2.INF, "докрутили — штамп на месте")
	await assert_draws(es.stamp, "штамп")


func test_no_record_no_stamp_and_no_empty_headline() -> void:
	await boot()
	var es = game.hud.end_screen
	es.show_end(false, "", "", [["Счёт", "10", false]])
	assert_false(es.stamp.visible)
	assert_false(es.headline.visible, "пустая строка под заголовком не занимает места")


func test_replay_button_only_after_death_with_record() -> void:
	await boot()
	var es = game.hud.end_screen
	es.show_end(false, "", "", _rows(2), true, "Держись дальше от медведя.")
	assert_true(es.replay_button.visible, "после гибели с записью — ПОВТОР")
	assert_true(es.tip_label.visible)
	assert_has(es.tip_label.text, "СОВЕТ: ")
	es.show_end(true, "", "", _rows(2))
	assert_false(es.replay_button.visible, "после победы повтора нет")
	assert_false(es.tip_label.visible, "и совета тоже")
	assert_eq(es.head.text, "ПОБЕДА!")
	assert_eq(es.head.label_settings.font_color, Design.MINT)


func test_desktop_720p_shows_a_typical_run_without_scrolling() -> void:
	await boot_stage(1)
	game.hud.show_end(false, "", RunReport.headline(false), _real_rows())
	await _set_screen(Vector2(1280, 720), 1.0)
	var es = game.hud.end_screen
	assert_lt(es.content.get_combined_minimum_size().y, es.scroll.size.y + 1.0,
		"на ПК обычные итоги видны целиком, без прокрутки")
	assert_lt(es.headline.get_combined_minimum_size().y, 40.0, "строка под заголовком — одна строка, а не столбик слов")


# ---------------------------------------------------------------- все виды итогов на телефоне

func _phone() -> void:
	Platform.force_mobile = true
	Platform.force_touch = true
	Settings.reset_to_defaults()


func _unphone() -> void:
	Platform.force_mobile = false
	Platform.force_touch = false


func test_win_rows_fit_on_a_phone() -> void:
	_phone()
	await boot_stage(1)
	var rows := _real_rows()
	rows = RunReport.rows(game, true, true, 100)
	game.hud.show_end(true, "КОНЕЦ", RunReport.headline(true), rows)
	game.hud.layout()
	await frames(3)
	_check_fits("победа на телефоне")
	_unphone()


func test_daily_rows_fit_on_a_phone() -> void:
	_phone()
	await boot_stage(1)
	game.daily_mode = true
	game.daily = {"name": "УСКОРЕНИЕ + ТАБЛЕТОЧНЫЙ ДОЖДЬ", "id": "speed+pills"}
	game.streak_bonus = 6
	var rows := _real_rows()
	var labels := []
	for r: Array in rows:
		labels.append(r[0])
	assert_has(labels, "Испытание дня")
	assert_has(labels, "Серия испытаний")
	game.hud.show_end(false, "", RunReport.headline(false), rows)
	game.hud.layout()
	await frames(3)
	_check_fits("испытание дня на телефоне")
	game.daily_mode = false
	_unphone()


func test_contact_rows_joined_with_the_run_fit_on_a_phone() -> void:
	_phone()
	await boot_stage(1)
	var rows := _real_rows()
	rows.append(["Убеждено", "Медведей 8 из 8, вилок 5 из 5, таблеток 7 из 7, матрёшек 3 из 3 — все живы"])
	rows.append(["Выжили", "змея и медведь-швея"])
	rows.append(["Время «Контакта»", "3:12"])
	game.hud.show_end(true, "КОНТАКТ", "Образец №48 договорился со всеми… кроме своего создателя.", rows)
	game.hud.layout()
	await frames(3)
	_check_fits("«Контакт» на телефоне")
	var es = game.hud.end_screen
	var v: Label = null
	for c in es.stats.get_children():
		var l: Label = c if c is Label else (c.get_child(0) if c.get_child_count() > 0 else null)
		if l and l.text.begins_with("Медведей 8"):
			v = l
	assert_true(v != null, "строка «Убеждено» на месте")
	assert_eq(v.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "длинная — переносится, а не раздвигает панель")
	assert_on_screen(es.first_focus, "ЕЩЁ РАЗ после «Контакта»")
	_unphone()


func test_relayout_after_resize_is_stable() -> void:
	await boot()
	game.hud.show_end(false, "", "Тест", _rows(14))
	var es = game.hud.end_screen
	for i in 3:  # несколько fit подряд без смены экрана — сетка не перестраивается туда-обратно
		es.fit()
	var cells: int = es.stats.get_child_count()
	var cols: int = es.columns
	es.fit()
	await frames(2)
	assert_eq(es.stats.get_child_count(), cells, "повторный fit ничего не перестраивает")
	assert_eq(es.columns, cols)
