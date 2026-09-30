extends "res://tests/integration/game_case.gd"
## Экраны глубже, чем «открылся»: дерево навыков (покупка, отказ, закрытые узлы, сброс в два нажатия),
## выбор улучшения (клавиши 1–N, нельзя закрыть без выбора), пауза (сон, подтверждение выхода),
## экран загрузки (советы меняются, полоса догоняет прогресс), повтор (кадры по кругу).

const LoadingScreen = preload("res://scripts/ui/screens/loading_screen.gd")
const ReplayScreen = preload("res://scripts/ui/screens/replay_screen.gd")
const Tips = preload("res://scripts/core/tips.gd")
const Design = preload("res://scripts/ui/design.gd")


# ---------------------------------------------------------------- навыки

func test_skill_buy_spends_scales_and_refreshes_the_node() -> void:
	await boot()
	Skills.reset_all()
	Skills.scales = 0
	Skills.add_scales(20)
	var s = game.hud.skills_screen
	game.hud.open_skills()
	assert_true(s.visible)
	assert_eq(s.scales_label.text, Design.scales_text(20))
	var cost := Skills.cost("hide")
	assert_has(s.node_state_labels["hide"].text, str(cost), "на узле цена")
	s._on_node("hide")
	assert_eq(Skills.rank("hide"), 1, "купили ранг")
	assert_eq(Skills.scales, 20 - cost, "чешуйки списаны")
	assert_eq(s.scales_label.text, Design.scales_text(20 - cost), "счётчик обновился")
	assert_eq(s.desc_title.text, Skills.node("hide")["name"], "описание — купленного узла")


func test_skill_refused_when_too_poor_or_locked() -> void:
	await boot()
	Skills.reset_all()
	Skills.scales = 0
	var s = game.hud.skills_screen
	game.hud.open_skills()
	s._on_node("hide")
	assert_eq(Skills.rank("hide"), 0, "без чешуек не купить")
	var second: String = Skills.TREE[1]["id"]
	assert_false(Skills.unlocked(second), "второй узел ветки закрыт")
	assert_eq(s.node_state_labels[second].text, "закрыто")
	s._show_desc(second)
	assert_has(s.desc_label.text, "Сначала вкачай предыдущий", "описание объясняет, почему закрыто")
	Skills.add_scales(999)
	s._on_node(second)
	assert_eq(Skills.rank(second), 0, "даже с чешуйками закрытый не покупается")


func test_skill_node_shows_max_when_maxed() -> void:
	await boot()
	Skills.reset_all()
	Skills.add_scales(999)
	var s = game.hud.skills_screen
	game.hud.open_skills()
	for i in Skills.node("hide")["max"]:
		s._on_node("hide")
	assert_true(Skills.maxed("hide"))
	assert_eq(s.node_state_labels["hide"].text, "МАКС")
	assert_has(s.desc_label.text, "до максимума")


func test_skill_reset_needs_two_presses() -> void:
	await boot()
	Skills.reset_all()
	Skills.add_scales(50)
	Skills.buy("hide")
	var s = game.hud.skills_screen
	game.hud.open_skills()
	s._on_reset()
	assert_true(s.reset_armed, "первое нажатие только взводит")
	assert_eq(Skills.rank("hide"), 1, "ничего не сброшено")
	assert_has(s.reset_button.text, "ЕЩЁ РАЗ")
	s._on_reset()
	assert_eq(Skills.rank("hide"), 0, "второе — сбросило")
	assert_false(s.reset_armed)
	s.close()
	game.hud.open_skills()
	assert_eq(s.reset_button.text, "СБРОСИТЬ НАВЫКИ", "после переоткрытия кнопка снова обычная")
	await assert_draws(s.grid, "связи узлов")


# ---------------------------------------------------------------- улучшения

func test_perk_keys_choose_and_back_is_refused() -> void:
	await boot()
	var p = game.hud.perks
	var list := Skills.roll_perks(3)
	var chosen := []
	p.perk_chosen.connect(func(id: String) -> void: chosen.append(id))
	p.show_perks(list, "ВИЛКИ", false)
	assert_eq(p.heading.text, "ДАЛЬШЕ: ВИЛКИ")
	assert_has(p.hint.text, "1–3", "подсказка про клавиши")
	assert_true(p.handle_back(), "Esc не закрывает — улучшение обязательно")
	assert_true(p.visible)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_2
	ev.pressed = true
	p._unhandled_input(ev)
	assert_eq(chosen, [list[1]["id"]], "клавиша 2 — вторая карточка")
	assert_false(p.visible)


func test_perk_cards_hide_extra_and_touch_hint() -> void:
	await boot()
	var p = game.hud.perks
	var list := Skills.roll_perks(2)
	p.show_perks(list, "ТАБЛЕТКИ", true)
	assert_eq(p.hint.text, "Нажми на карточку")
	var shown := 0
	for c: Button in p.cards:
		if c.visible:
			shown += 1
	assert_eq(shown, 2, "лишние карточки спрятаны")
	p._choose(5)
	assert_true(p.visible, "несуществующая карточка ничего не выбирает")


# ---------------------------------------------------------------- пауза

func test_pause_sleeps_after_a_minute_and_wakes_on_input() -> void:
	await boot_stage(0)
	var ps = game.hud.pause_screen
	var found := []
	ps.secret_found.connect(func(id: String) -> void: found.append(id))
	ps.show_pause("Этап 1")
	assert_eq(ps.info.text, "Этап 1")
	ps._process(ps.SLEEP_TIME + 0.1)
	assert_has(ps.sleep_label.text, "уснул")
	assert_eq(found, ["sleepy"], "пасхалка «сон» — один раз")
	ps._process(1.0)
	assert_eq(found.size(), 1)
	var ev := InputEventKey.new()
	ev.pressed = true
	ps._input(ev)
	assert_eq(ps.sleep_label.text, "", "нажали клавишу — проснулся")
	assert_eq(ps.idle, 0.0)


func test_pause_menu_asks_for_confirmation() -> void:
	await boot_stage(0)
	var ps = game.hud.pause_screen
	var left := [0]
	ps.menu_requested.connect(func() -> void: left[0] += 1)
	Settings.set_value("confirm_quit", true)
	ps.show_pause("")
	ps._on_menu()
	assert_eq(left[0], 0, "первое нажатие только предупреждает")
	assert_has(ps.menu_button.text, "ЖМИ ЕЩЁ РАЗ")
	ps.show_pause("")
	assert_eq(ps.menu_button.text, "В МЕНЮ", "новая пауза — предупреждение сброшено")
	Settings.set_value("confirm_quit", false)
	ps._on_menu()
	assert_eq(left[0], 1, "без подтверждения — сразу")


# ---------------------------------------------------------------- загрузка

func test_loading_bar_catches_up_and_tips_rotate() -> void:
	var l: LoadingScreen = add(LoadingScreen.new())
	l.size = Vector2(1280, 720)
	l.progress = 1.0
	l._process(0.2)
	assert_between(l.shown, 0.4, 0.6, "полоса догоняет прогресс плавно")
	l._process(1.0)
	assert_eq(l.shown, 1.0)
	l.tip = "старый совет"
	l._process(4.1)
	assert_ne(l.tip, "старый совет", "через 4 с — другой совет")
	assert_near(l.tip_t, 4.0, 0.001)
	await assert_draws(l, "экран загрузки")


# ---------------------------------------------------------------- повтор

func test_replay_screen_loops_the_recording() -> void:
	await boot_stage(0)
	await step(60)
	assert_true(game.replay.has_data(), "запись идёт")
	var rs = game.hud.replay_screen
	game.hud.push(rs)
	rs.show_replay(game.replay)
	assert_eq(rs.t, 0.0, "с начала")
	rs._process(0.5)
	assert_gt(rs.t, 0.0)
	await assert_draws(rs.monitor, "монитор повтора")
	rs.restart()
	assert_eq(rs.t, 0.0, "перезапуск — с первого кадра")


func test_every_death_cause_has_a_title_and_a_tip() -> void:
	for cause: String in Tips.BY_CAUSE:
		assert_ne(ReplayScreen.cause_title(cause), "ПРИЧИНА НЕИЗВЕСТНА", "у причины «%s» есть заголовок" % cause)
		assert_ne(Tips.for_cause(cause), "", "и совет")
	assert_eq(ReplayScreen.cause_title("что-то новое"), "ПРИЧИНА НЕИЗВЕСТНА", "незнакомая причина не ломает экран")
