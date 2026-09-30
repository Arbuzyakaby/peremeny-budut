extends "res://tests/integration/game_case.gd"
## Меню и советы: описание сложности под карточкой, испытание дня, журнал с отточием, ротация советов,
## фальшивое меню «Контакта» прячет всё, кроме одной кнопки; советы короткие, без повторов, про новые
## враги 12.4 (шипучка, юла) и без устаревших «прыжков» малышки.

const Tips = preload("res://scripts/core/tips.gd")
const Design = preload("res://scripts/ui/design.gd")


func test_difficulty_description_follows_the_card() -> void:
	await boot()
	var m = game.hud.menu
	for i in Balance.DIFFICULTIES.size():
		m._show_desc(i)
		assert_eq(m.desc_label.text, Balance.DIFFICULTIES[i]["desc"], "описание сложности %d" % i)
	m._show_daily_desc()
	assert_has(m.desc_label.text, Daily.day_key(), "испытание дня — с датой")
	assert_has(m.desc_label.text, "Серия:")


func test_journal_lines_line_up() -> void:
	await boot()
	var m = game.hud.menu
	m._update_journal()
	var lines: PackedStringArray = m.stats_label.text.split("\n")
	assert_len(lines, 4, "чешуйки, картотека, серия, пасхалки")
	for l in lines:
		assert_has(l, "..", "отточие до значения")
	assert_between(lines[0].length(), 30, 40, "строки одной ширины — машинопись")
	assert_eq(lines[0].length(), lines[3].length())


func test_tips_rotate_in_the_menu() -> void:
	await boot()
	var m = game.hud.menu
	var first: String = m.tip_label.text
	m._next_tip()
	assert_ne(m.tip_label.text, first, "следующий совет другой")
	assert_has(Tips.GENERAL, m.tip_label.text)
	assert_eq(m.tip_t, 6.0, "совет висит шесть секунд")


func test_glitch_menu_hides_everything_but_one_button() -> void:
	await boot()
	var m = game.hud.menu
	m.glitch_single("НОВАЯ ИГРА")
	assert_true(m.glitch_button.visible)
	assert_eq(m.glitch_button.text, "НОВАЯ ИГРА")
	for n in [m.bay, m.choose_label, m.extra_row, m.action_row]:
		assert_false(n.visible, "в фальшивом меню лишнего нет")
	m._show_desc(0)
	assert_has(m.desc_label.text, "ОБРАЗЕЦ №48", "описание сложности не пробивается сквозь глюк")
	assert_eq(m.first_focus, m.glitch_button)
	m.set_glitch(false)
	assert_false(m.glitch_button.visible)
	assert_true(m.bay.visible, "меню вернулось")


func test_general_tips_are_short_and_unique() -> void:
	var seen := {}
	var f := Design.font("body")
	for t: String in Tips.GENERAL:
		assert_false(seen.has(t), "совет не повторяется: " + t.left(30))
		seen[t] = true
		assert_lt(f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, 2 * 560.0, "влезает в две строки: " + t.left(30))
		assert_true(t.ends_with(".") or t.ends_with("!") or t.ends_with("?"), "совет — законченная фраза: " + t.left(30))


func test_tips_know_the_new_enemies_and_forget_the_old_jump() -> void:
	var all := "\n".join(Tips.GENERAL)
	assert_has(all, "Шипучка", "совет про шипучку")
	assert_has(all, "юлой", "совет про юлу")
	for t: String in Tips.GENERAL:
		assert_false("Малышка не убегает — она прыгает" in t, "устаревший совет про прыжок малышки убран")
		assert_false("В прыжке малышка неуязвима" in t)
	for cause: String in Tips.BY_CAUSE:
		assert_true(String(Tips.BY_CAUSE[cause]).ends_with("."), "совет по причине «%s» — законченная фраза" % cause)
