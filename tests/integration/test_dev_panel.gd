extends "res://tests/integration/game_case.gd"
## Панель разработчика: открывается настоящими клавишами (F1, `/ё, Ctrl+Shift+D) в меню, в забеге,
## на паузе и на выборе улучшений — там, где раньше не открывалась. Спавн вилок и их приёмов.

const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")


func test_f1_toggles_in_menu() -> void:
	await boot()
	assert_false(game.dev_panel.open)
	await press_key(KEY_F1)
	assert_true(game.dev_panel.open, "F1 открыл")
	assert_true(game.dev_panel.panel.visible)
	await press_key(KEY_F1)
	assert_false(game.dev_panel.open, "F1 закрыл")


func test_f1_works_while_paused() -> void:
	await boot_stage(0)
	game.hud.set_paused(true)
	assert_true(tree.paused)
	await press_key(KEY_F1)
	assert_true(game.dev_panel.open, "на паузе тоже открывается (баг v6.1)")
	await press_key(KEY_F1)
	assert_false(game.dev_panel.open)


func test_f1_on_perk_screen() -> void:
	await boot_stage(0)
	tree.paused = true
	game.hud.show_perks(Skills.roll_perks(), "ВИЛКИ")
	await press_key(KEY_F1)
	assert_true(game.dev_panel.open, "и на выборе улучшений")


func test_backtick_and_ctrl_shift_d() -> void:
	await boot()
	await press_key(KEY_QUOTELEFT)
	assert_true(game.dev_panel.open, "` (на русской раскладке — ё)")
	await press_key(KEY_D, true, true)
	assert_false(game.dev_panel.open, "Ctrl+Shift+D")
	await press_key(KEY_D)
	assert_false(game.dev_panel.open, "просто D панель не трогает")


func test_spawn_every_fork_kind() -> void:
	await boot_stage(1)
	game.enemies.clear(false)
	var dp = game.dev_panel
	for k in Fork.KINDS:
		dp._spawn("fork", k)
	assert_eq(game.enemies.forks.size(), Fork.KINDS.size())
	var kinds := []
	for f in game.enemies.forks:
		kinds.append(f.kind)
	kinds.sort()
	assert_eq(kinds, [0, 1, 2], "все три вида")


func test_force_every_fork_attack() -> void:
	await boot_stage(1)
	game.enemies.clear(false)
	var dp = game.dev_panel
	var expected := [Fork.St.AIM, Fork.St.VOLLEY_AIM, Fork.St.WHIRL_UP, Fork.St.POGO_UP]
	for a in 4:
		game.enemies.clear(false)
		dp._fork_attack(a)  # вилок нет — панель создаст
		assert_eq(game.enemies.forks.size(), 1)
		assert_eq(game.enemies.forks[0].st, expected[a], Fork.ATTACK_NAMES[a])


func test_world_tab_has_fork_buttons() -> void:
	await boot()
	var texts := []
	for b in game.dev_panel.pages[2].find_children("*", "Button", true, false):
		texts.append((b as Button).tooltip_text)
	for k in Fork.KINDS:
		assert_has(texts, String(Fork.KINDS[k]["name"]))
	for n in Fork.ATTACK_NAMES:
		assert_has(texts, n)
	for pk in Pill.KINDS:
		assert_has(texts, String(pk["name"]), "кнопка каждого вида таблеток")


func test_spawn_every_pill_kind() -> void:
	await boot_stage(2)
	game.enemies.clear(false)
	for k in Pill.KINDS.size():
		game.dev_panel._spawn("pill", k)
	var kinds := []
	for p in game.enemies.pills:
		kinds.append(p.kind)
	kinds.sort()
	assert_eq(kinds, [0, 1, 2], "капсула, шайба и шипучка")


func test_dev_spin_and_puddle_buttons() -> void:
	await boot_stage(Balance.DOLL_STAGE)
	game.enemies.clear(false)
	game.dev_panel._doll_spin()
	var tiny = null
	for m in game.enemies.dolls:
		if m.is_last():
			tiny = m
	assert_true(tiny != null, "нет малышки — появилась")
	assert_eq(tiny.st, tiny.St.CROUCH, "и сразу раскручивается")
	assert_gt(tiny.spin_path.size(), 1, "с полосой на полу")
	game.dev_panel._fizz_puddle()
	assert_eq(game.enemies.puddles.size(), 1, "лужа шипучки")
	assert_true(game.enemies.puddles[0].position.distance_to(game.snake.head_pos) < 1.0, "прямо под змеёй")
	var texts := []
	for b in game.dev_panel.pages[2].find_children("*", "Button", true, false):
		texts.append((b as Button).tooltip_text)  # подпись кнопки панели — в подсказке
	assert_has(texts, "Юла — сейчас")
	assert_has(texts, "Лужа у змеи")
