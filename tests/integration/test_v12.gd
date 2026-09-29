extends "res://tests/integration/game_case.gd"
## v12.0: дизайн-язык 2.4 (табличка объявлений, лента подсказки, чугун), сковорода яичницы и найденные
## в «человеческой» проверке ошибки: подсказка поверх табло яичницы, баннер из-за паузы, надписи у края
## поля, «каждая 2-я» при «Железном желудке», склонение чешуек, прыжок, перенесённый на новый этап.

const Captions = preload("res://scripts/ui/captions.gd")
const Design = preload("res://scripts/ui/design.gd")
const Materials = preload("res://scripts/ui/materials.gd")
const Abilities = preload("res://scripts/game/abilities.gd")
const BossFight = preload("res://scripts/game/boss_fight.gd")
const Tex = preload("res://scripts/gfx/tex.gd")
const Tips = preload("res://scripts/core/tips.gd")


func before_each() -> void:
	super()
	Settings.set_value("touch_mode", 2)  # раскладка ПК: табло яичницы снизу, табличка сверху


func test_plural_forms() -> void:
	assert_eq(Design.scales_text(1), "1 чешуйка")
	assert_eq(Design.scales_text(42), "42 чешуйки")
	assert_eq(Design.scales_text(8), "8 чешуек")
	assert_eq(Design.scales_text(11), "11 чешуек", "11–14 — всегда «чешуек»")
	assert_eq(Design.scales_text(112), "112 чешуек")
	assert_eq(Design.scales_text(121), "121 чешуйка")
	assert_eq(Design.plural(0, "день", "дня", "дней"), "0 дней")


func test_banner_splits_into_title_and_line() -> void:
	var p := Captions.split_banner("ЯИЧНИЦА ПОДГОРАЕТ! Прыгает и плюётся горящим маслом")
	assert_eq(p[0], "ЯИЧНИЦА ПОДГОРАЕТ!")
	assert_eq(p[1], "Прыгает и плюётся горящим маслом")
	p = Captions.split_banner("КУСАЙ ЖЕЛТОК! Врезалась в бортик и оглушена")
	assert_eq(p[0], "КУСАЙ ЖЕЛТОК!", "действие — в заголовке таблички")
	p = Captions.split_banner("ЭТАП 1: МЕДВЕДИ")
	assert_eq(p[1], "", "короткое объявление не делится")


func test_source_hint_respects_iron_stomach() -> void:
	assert_true(Abilities.source_hint("fork", 2).begins_with("Каждая 2-я вилка"))
	var each := Abilities.source_hint("pill", 1)
	assert_true(each.begins_with("Каждая таблетка"), "с «Железным желудком» — каждая, а не каждая 2-я: " + each)
	assert_false("2-я" in each)


func test_hint_sits_above_the_boss_bar() -> void:
	await boot_stage(Balance.BOSS_STAGE)
	game.hud.set_boss(true, 12, 12, 1)
	game.hud.show_hint("Подсказка во время боя с яичницей")
	await frames(3)
	var cap: Captions = game.hud.captions
	var k: float = game.hud.root.scale.y
	var strip_bottom: float = game.hud.root.position.y + (cap.caption_plate.position.y + cap.caption_plate.size.y) * k
	var bar_top: float = game.hud.overlay._boss_rect().position.y
	assert_true(strip_bottom <= bar_top, "лента подсказки (низ %.0f) над табло яичницы (верх %.0f)" % [strip_bottom, bar_top])


func test_banner_is_a_plate_between_the_panels() -> void:
	await boot_stage(0)
	game.hud.show_banner("ЭТАП 3: ПРЫГАЮЩИЕ ТАБЛЕТКИ", Design.YOLK, 1.0)
	await frames(3)
	var cap: Captions = game.hud.captions
	assert_true(cap.is_banner_shown() or cap.banner_plate.visible)
	var k: float = game.hud.root.scale.x
	var left_panel: Rect2 = game.hud.overlay._left_rect()
	var plate_left: float = game.hud.root.position.x + cap.banner_plate.position.x * k
	assert_true(plate_left >= left_panel.end.x, "табличка (%.0f) не наезжает на левое табло (%.0f)" % [plate_left, left_panel.end.x])
	assert_true(cap.banner_plate.position.y <= 60.0, "в игре табличка сверху, а не посреди арены")


func test_pause_hides_the_banner() -> void:
	await boot_stage(1)
	game.hud.show_banner("ЭТАП 2: РЖАВЫЕ ВИЛКИ", Design.YOLK, 2.0)
	await frames(2)
	game.hud.set_paused(true)
	assert_false(game.hud.captions.banner_plate.visible, "табличка не выглядывает из-за паузы")
	assert_true("этап 2" in game.hud.pause_screen.info.text, "строка паузы собрана при открытии")
	game.hud.set_paused(false)


func test_popup_stays_inside_the_field() -> void:
	await boot_stage(0)
	game.fx.popup(Vector2(1270, 300), "НА ПОМОЩЬ ЯИЧНИЦЕ!", Color.WHITE)
	var label: Label = null
	for c in game.world.get_children():
		if c is Label and c.text == "НА ПОМОЩЬ ЯИЧНИЦЕ!":
			label = c
	assert_true(label != null)
	var w: float = label.label_settings.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.label_settings.font_size).x
	var center_x: float = label.position.x + label.size.x / 2.0
	assert_true(center_x + w / 2.0 <= 1280.0, "надпись у правого бортика не уходит за край")


func test_boss_stage_is_cast_iron_and_hot() -> void:
	await boot_stage(Balance.BOSS_STAGE)
	assert_eq(game.arena.floor_kind, Tex.Floor.PAN)
	assert_gt(game.arena.heat, 0.0, "сковорода на огне")
	assert_true(game.hud.captions.iron, "таблички этапа яичницы — из чугуна")
	game.hud.show_banner("ЯИЧНИЦА ПРИБЛИЖАЕТСЯ!")
	var st: StyleBox = game.hud.captions.banner_plate.get_theme_stylebox("panel")
	assert_eq(st.kind, Materials.Kind.CAST_IRON)
	assert_near(BossFight.heat_for(3), 1.0, 0.001, "на третьей фазе чугун раскалён")
	game.arena.set_floor(Tex.Floor.WOOD)
	assert_eq(game.arena.heat, 0.0, "другой этап — жара нет")
	assert_false(game.arena.is_processing())


func test_ending_shows_a_wooden_box_not_a_pan() -> void:
	await boot_stage(Balance.BOSS_STAGE)
	assert_true(game.arena.pan_rim)
	game.start_ending()
	assert_false(game.arena.pan_rim, "в лаборатории ящик деревянный: ручка сковороды не торчит")
	assert_eq(game.arena.heat, 0.0)


func test_new_run_resets_iron_look() -> void:
	await boot_stage(Balance.BOSS_STAGE)
	game.hud.show_game("НОРМАЛЬНАЯ", Design.YOLK, 3)
	assert_false(game.hud.captions.iron)
	assert_false(game.hud.overlay.iron)


func test_stage_clear_cancels_a_hop() -> void:
	await boot_stage(3)
	game.snake.hop(0.3)
	game.snake.dash(0.3)
	game.abilities.hop_land_t = 0.3
	game._stage_cleared()
	assert_false(game.snake.is_hopping(), "прыжок не переносится на следующий этап")
	assert_false(game.snake.is_dashing())
	assert_eq(game.abilities.hop_land_t, -1.0)
	assert_eq(game.snake.small, 1.0)


func test_hop_clears_waves_and_drops() -> void:
	await boot_stage(2)
	game.enemies.clear(false)
	var s = game.snake
	s.hop(0.5)
	game.shots.spawn_stun_wave(s.head_pos, 200.0)
	var w = game.shots.waves.back()
	w.radius = 0.0  # кольцо ровно под головой
	game.shots.update_waves(0.0)
	assert_false(s.is_stunned(), "волну таблетки перепрыгивают")
	var d = game.shots.spawn_drop(s.head_pos, Vector2(10, 0), 1)  # капля белка прямо в голову
	game.shots.update_drops(0.0)
	assert_eq(s.slow_timer, 0.0, "белок пролетел под прыгнувшей змеёй")
	assert_true(game.shots.drops.has(d), "и не потратился о неё")


func test_texts_fixed_by_the_human_check() -> void:
	assert_false("всё целы" in String(Skills.perk("heal")["desc"]))
	for tip: String in Tips.GENERAL:
		assert_false("правом нижнем углу" in tip, "табличка атаки — справа вверху")
		assert_false("включи управление мышью" in tip, "мышь включена по умолчанию")
	assert_false("Следи за тенью" in String(Tips.BY_CAUSE["pill"]), "у таблетки кольцо на полу, а не тень")


func test_menu_counts_scales_in_words() -> void:
	await boot()
	assert_false(game.hud.menu.tree_button.text.ends_with(" Ч."), "не «42 Ч.»: " + game.hud.menu.tree_button.text)
	assert_true("ЧЕШУ" in game.hud.menu.tree_button.text)
