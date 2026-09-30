extends "res://tests/integration/game_case.gd"
## Картотека v12.4: дело карточки (встречи, победы, первый этап, «НОВОЕ»), перевод старых сохранений,
## запись на диск одной порцией, вкладки со счётчиками, портреты-враги, лист дела без обрезки,
## досье на учёного, всё помещается на экран телефона.

const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
const Platform = preload("res://scripts/core/platform.gd")
const BestiaryScreen = preload("res://scripts/ui/screens/bestiary_screen.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")


# ---------------------------------------------------------------- данные

func test_old_saves_are_migrated() -> void:
	SaveData.write_section(Bestiary.SECTION, {"fork_2": true, "bear_0": true})
	Bestiary.load_progress()
	assert_true(Bestiary.is_known("fork_2"), "старая карточка открыта")
	var st := Bestiary.stats("fork_2")
	assert_eq(st["met"], 1, "встреч — хотя бы одна")
	assert_eq(st["beaten"], 0)
	assert_eq(st["stage"], -1, "этап неизвестен")
	assert_false(Bestiary.is_new("fork_2"), "старые карточки не помечаются новыми")
	assert_eq(Bestiary.known_count(), 2)


func test_unlock_marks_new_and_remembers_the_stage() -> void:
	assert_true(Bestiary.unlock("pill_2", true, 2))
	assert_true(Bestiary.is_new("pill_2"))
	assert_eq(Bestiary.stats("pill_2")["stage"], 2)
	assert_eq(Bestiary.new_count(), 1)
	Bestiary.load_progress()
	assert_true(Bestiary.is_new("pill_2"), "метка «НОВОЕ» переживает перезапуск")
	Bestiary.mark_read("pill_2")
	Bestiary.load_progress()
	assert_false(Bestiary.is_new("pill_2"), "прочитали — метка погасла навсегда")


func test_counters_are_saved_only_on_flush() -> void:
	Bestiary.unlock("bear_1", true, 0)
	for i in 5:
		Bestiary.note_met("bear_1")
	for i in 3:
		Bestiary.note_beaten("bear_1")
	assert_eq(Bestiary.stats("bear_1")["met"], 6)
	assert_eq(Bestiary.stats("bear_1")["beaten"], 3)
	var on_disk: Dictionary = SaveData.read_section(Bestiary.SECTION).get("bear_1", {})
	assert_eq(int(on_disk.get("met", 0)), 1, "пока не записано — на диске первая встреча")
	Bestiary.flush()
	on_disk = SaveData.read_section(Bestiary.SECTION)["bear_1"]
	assert_eq(int(on_disk["met"]), 6, "записано одной порцией")
	assert_eq(int(on_disk["beaten"]), 3)


func test_unknown_keys_do_not_count() -> void:
	Bestiary.note_met("дракон")
	Bestiary.note_beaten("bear_5")  # не встречен — не побеждён
	assert_false(Bestiary.is_known("bear_5"))
	assert_true(Bestiary.stats("bear_5").is_empty())


func test_tabs_cover_every_entry_exactly_once() -> void:
	var seen := {}
	for t in range(1, Bestiary.TABS.size()):
		for i in Bestiary.tab_entries(t):
			assert_false(seen.has(i), "карточка %d не на двух вкладках" % i)
			seen[i] = true
	assert_eq(seen.size(), Bestiary.total(), "каждая карточка на какой-то вкладке")
	assert_eq(Bestiary.tab_entries(0).size(), Bestiary.total(), "«ВСЕ» — все")
	Bestiary.unlock("fork_0", false)
	Bestiary.unlock("fork_atk_2", false)
	assert_eq(Bestiary.tab_progress(2), Vector2i(2, 7), "вилки и приёмы: 2 из 7")
	for e: Dictionary in Bestiary.ENTRIES:
		assert_has(Bestiary.where_text(e), "Встречается", "у «%s» есть подсказка, где искать" % e["key"])


# ---------------------------------------------------------------- игра

func test_game_counts_meetings_and_wins() -> void:
	await boot()
	game.args["stage"] = 1
	game.start_game(1)  # не отладочный — считается
	await frames(2)
	var key := "fork_%d" % game.enemies.forks[0].kind
	assert_true(Bestiary.is_known(key), "вилка попала в картотеку")
	assert_eq(Bestiary.stats(key)["stage"], 1, "впервые — на этапе вилок")
	var met: int = Bestiary.stats(key)["met"]
	game.enemies.spawn_fork(Vector2.INF, game.enemies.forks[0].kind)
	assert_eq(Bestiary.stats(key)["met"], met + 1, "ещё одна такая же — ещё встреча")
	game.enemies.break_fork(game.enemies.forks[0])
	assert_eq(Bestiary.stats(key)["beaten"], 1, "сломали — победа")
	game._commit_run(false)
	assert_eq(int(SaveData.read_section(Bestiary.SECTION)[key]["beaten"]), 1, "в конце забега записано")


func test_debug_runs_do_not_count() -> void:
	await boot_stage(1)
	var key := "fork_%d" % game.enemies.forks[0].kind
	assert_false(Bestiary.is_known(key), "отладочный забег карточек не открывает")
	game.enemies.break_fork(game.enemies.forks[0])
	assert_true(Bestiary.stats(key).is_empty())


func test_ending_opens_the_scientist_dossier() -> void:
	await boot()
	game.args["ending"] = true
	game.start_game(1)
	await frames(3)
	assert_true(Bestiary.is_known("scientist"), "досье на учёного — после победы")
	assert_true(Bestiary.is_new("scientist"))


# ---------------------------------------------------------------- экран

func _open() -> Variant:
	await boot()
	var scr = game.hud.bestiary_screen
	game.hud.push(scr)
	await frames(2)
	return scr


func test_tabs_filter_cards_and_show_counts() -> void:
	Bestiary.unlock("bear_0", false)
	Bestiary.unlock("pill", false)
	var scr = await _open()
	assert_has(scr.tabs.buttons[1].text, "1/8", "на вкладке медведей — счётчик")
	scr.show_tab(3)
	var visible := 0
	for c: Button in scr.cards:
		if c.visible:
			visible += 1
	assert_eq(visible, Bestiary.tab_entries(3).size(), "видны только таблетки")
	assert_true(Bestiary.ENTRIES[scr.selected]["group"] == "ТАБЛЕТКИ", "выбор перескочил на первую таблетку")
	scr.show_tab(0)
	visible = 0
	for c: Button in scr.cards:
		if c.visible:
			visible += 1
	assert_eq(visible, Bestiary.total())


func test_selecting_a_card_reads_it_and_fills_the_sheet() -> void:
	Bestiary.unlock("doll_0", false, 3)
	Bestiary.note_met("doll_0")
	Bestiary.note_beaten("doll_0")
	var scr = await _open()
	var i := Bestiary.ENTRIES.find(Bestiary.entry("doll_0"))
	assert_true(Bestiary.is_new("doll_0"))
	scr._select(i)
	assert_false(Bestiary.is_new("doll_0"), "открыли дело — не новое")
	assert_has(scr.sheet_title.text, "МАЛЫШКА-ЮЛА")
	assert_has(scr.sheet_stats.text, "Встречено: 2")
	assert_has(scr.sheet_stats.text, "Побеждено: 1")
	assert_has(scr.sheet_stats.text, "Впервые: этап")
	assert_eq(scr.sheet_tip.text, "Совет: " + Bestiary.entry("doll_0")["tip"], "совет целиком, без обрезки")
	assert_eq(scr.sheet_tip.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "и переносится")


func test_unknown_card_says_where_to_look() -> void:
	var scr = await _open()
	var i := Bestiary.ENTRIES.find(Bestiary.entry("pill_2"))
	scr._select(i)
	assert_has(scr.sheet_title.text, "НЕ ЗАПОЛНЕНО")
	assert_has(scr.sheet_weak.text, "шипучки", "подсказка: где искать")
	assert_eq(scr.sheet_stats.text, "")


func test_portraits_are_real_enemies() -> void:
	Bestiary.unlock("bear_3", false)
	Bestiary.unlock("fork_2", false)
	Bestiary.unlock("boss", false)
	var scr = await _open()
	var by_key := {}
	for i in Bestiary.ENTRIES.size():
		by_key[Bestiary.ENTRIES[i]["key"]] = scr.portraits[i]
	var bear: Portrait = by_key["bear_3"]
	assert_true(bear.actor is TeddyBear, "на карточке каратиста — медведь")
	assert_eq(bear.actor.type, 3, "именно каратист")
	assert_eq(bear.holder.modulate, Color.WHITE, "известный — в цвете")
	var unknown: Portrait = by_key["bear_5"]
	assert_lt(unknown.holder.modulate.v, 0.2, "неизвестный — силуэт")
	assert_true(by_key["fork_atk_0"].actor == null, "приём — значком")
	assert_true(by_key["boss"].actor != null, "яичница — настоящая")
	for key: String in ["bear_3", "fork_2", "boss", "pill"]:
		await assert_draws(by_key[key].actor if by_key[key].actor else by_key[key].overlay, "портрет " + key)
	for p: Portrait in scr.portraits:
		if p.actor:
			assert_false(p.actor.is_processing(), "враги на портретах не живут своей жизнью")


func test_sheet_portrait_breathes_but_cards_do_not() -> void:
	Bestiary.unlock("bear_0", false)
	var scr = await _open()
	assert_true(scr.sheet_portrait.is_processing(), "на листе дела — живой")
	assert_false(scr.portraits[0].is_processing(), "в сетке — неподвижный")


func test_new_badge_counter() -> void:
	Bestiary.unlock("bear_0", false)
	Bestiary.unlock("bear_1", false)
	var scr = await _open()
	assert_has(scr.counter.text, "новых:", "есть новые — счётчик")
	for key in ["bear_0", "bear_1"]:
		scr._select(Bestiary.ENTRIES.find(Bestiary.entry(key)))
	assert_false("новых" in scr.counter.text, "всё прочитали — счётчика нет")


func test_columns_follow_the_screen_width() -> void:
	var scr = await _open()
	var root: Control = game.hud.root
	root.size = Vector2(1920, 1080)
	scr.fit()
	var wide: int = scr.grid.columns
	root.size = Vector2(1000, 720)
	scr.fit()
	assert_lt(scr.grid.columns, wide, "уже экран — меньше колонок")
	assert_true(scr.grid.columns >= BestiaryScreen.MIN_COLS)
	game.hud.layout()


func test_fits_on_a_phone() -> void:
	Platform.force_mobile = true
	Platform.force_touch = true
	Settings.reset_to_defaults()
	var scr = await _open()
	game.hud.layout()
	await frames(2)
	var vp := game.get_viewport().get_visible_rect()
	assert_rect_inside(scr.panel.get_global_rect(), vp, "картотека на телефоне")
	Platform.force_mobile = false
	Platform.force_touch = false


func test_menu_button_counts_new_cards_and_updates_after_reading() -> void:
	Bestiary.unlock("bear_0", false)
	Bestiary.unlock("bear_1", false)
	await boot()
	var menu = game.hud.menu
	assert_has(menu.bestiary_button.text, "НОВЫХ 2", "в меню видно, что есть непрочитанные")
	var scr = game.hud.bestiary_screen
	game.hud.push(scr)
	for key in ["bear_0", "bear_1"]:
		scr._select(Bestiary.ENTRIES.find(Bestiary.entry(key)))
	scr.closed.emit()
	assert_false("НОВЫХ" in menu.bestiary_button.text, "прочитали и вышли — кнопка обновилась сразу")
	assert_has(menu.bestiary_button.text, "2/%d" % Bestiary.total())


func test_stats_line_formats() -> void:
	assert_eq(BestiaryScreen.stats_line("bear_0"), "", "не встречен — строки нет")
	Bestiary.unlock("bear_0", false, 0)
	assert_eq(BestiaryScreen.stats_line("bear_0"), "Встречено: 1  •  Побеждено: 0  •  Впервые: этап «Медведи»")
	Bestiary.unlock("scientist", false, -1)
	assert_eq(BestiaryScreen.stats_line("scientist"), "Встречено: 1", "учёного не побеждают, и этапа у него нет")
	Bestiary.unlock("fork_0", false, 99)
	assert_false("Впервые" in BestiaryScreen.stats_line("fork_0"), "этап вне маршрута не показываем")


func test_scientist_dossier_is_last_and_in_other() -> void:
	var last: Dictionary = Bestiary.ENTRIES.back()
	assert_eq(last["key"], "scientist", "досье — последняя карточка")
	assert_true(Bestiary.tab_entries(5).has(Bestiary.ENTRIES.size() - 1), "на вкладке «ПРОЧЕЕ»")
	assert_has(Bestiary.where_text(last), "после победы над яичницей")
