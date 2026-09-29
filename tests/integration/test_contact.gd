extends "res://tests/integration/game_case.gd"
## Технический режим «Контакт» (v10.0) целиком: без урона, знак убеждает, убеждённые переходят на
## следующий этап, финал с пожаром и выстрелами оставляет в живых только змею и швею, пасхалка
## открывается. И путь к нему: финал → пересадка → фальшивое меню → «Контакт».

const ContactMode = preload("res://scripts/contact/contact_mode.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")


func _contact() -> ContactMode:
	await boot()
	game.debug_run = true
	game.start_contact()
	await frames(2)
	return game.contact


## Прокручивать игру, пока не выполнится условие (не больше max_steps кадров по 1/60 с).
func run_until(cond: Callable, max_steps := 6000) -> bool:
	var n := 0
	while not cond.call() and n < max_steps:
		await step(20)
		n += 20
	return cond.call()


func test_contact_starts_peaceful() -> void:
	var c := await _contact()
	assert_eq(game.state, Game.State.CONTACT)
	assert_eq(c.stage, 0)
	assert_eq(game.enemies.bears.size(), Balance.CONTACT_GOALS[0], "на поле ровно столько медведей, сколько убедить")
	assert_true(c.seamstress().size() > 0, "среди них — швея")
	assert_true(game.snake.safe, "смерти в режиме нет")
	# змею тащим прямо сквозь медведей — ни урона, ни съеденных
	for i in 240:
		game.snake.head_pos = game.enemies.bears[i % game.enemies.bears.size()].position
		game._process(1.0 / 60.0)
	assert_eq(game.snake.lives, 1, "никто не бьёт")
	assert_eq(game.enemies.bears.size(), Balance.CONTACT_GOALS[0], "никого не съели")
	assert_eq(game.bears_eaten, 0)


func test_talk_needs_someone_near() -> void:
	var c := await _contact()
	c.candidate = {}
	game.snake.head_pos = Vector2(40, 40)
	for b: Node2D in game.enemies.bears:
		b.position = Vector2(1200, 650)
	game._try_attack("keys")
	assert_eq(c.phase, ContactMode.Phase.ROAM, "рядом никого — разговор не начинается")


func test_gesture_convinces_and_followers_carry_over() -> void:
	var c := await _contact()
	game.autopilot = true
	assert_true(await run_until(func() -> bool: return c.done >= 1), "первый медведь убеждён")
	var e: Dictionary = c.entries.filter(func(x: Dictionary) -> bool: return x["convinced"])[0]
	assert_true(c.paint.strokes.size() >= 1, "знак остался на полу")
	assert_true(await run_until(func() -> bool: return c.stage == 1, 12000), "все медведи убеждены — этап вилок")
	assert_eq(game.enemies.bears.size(), Balance.CONTACT_GOALS[0], "медведи перешли к вилкам вместе со змеёй")
	assert_true(is_instance_valid(e["node"]) and e["convinced"], "убеждённый остался убеждённым")
	assert_eq(game.enemies.forks.size(), Balance.CONTACT_GOALS[1])
	assert_eq(c.counts["bear"], Balance.CONTACT_GOALS[0])


func test_failed_trace_scares_instead_of_convincing() -> void:
	var c := await _contact()
	var b: TeddyBear = game.enemies.bears[0]
	b.position = game.snake.head_pos + Vector2(100, 0)
	c._find_candidate()
	c.talk("mouse")
	assert_eq(c.phase, ContactMode.Phase.TRACE, "встала на дыбы — рисует")
	game._process(1.0 / 60.0)
	assert_gt(game.snake.rear, 0.0, "поднимается на дыбы")
	for p in [Vector2(100, 100), Vector2(1100, 600), Vector2(100, 600), Vector2(1100, 100)]:
		c.add_trace_point(p)
	c._finish_trace()
	assert_eq(c.phase, ContactMode.Phase.ROAM)
	assert_eq(c.done, 0, "каракули никого не убеждают")
	assert_gt(float(c.entries[0]["scared"]) + float(c.entries[1]["scared"]) + float(c.entries[2]["scared"])
		+ float(c.entries[3]["scared"]) + float(c.entries[4]["scared"]), 0.0, "а пугают")


func test_finale_leaves_only_snake_and_seamstress() -> void:
	var c := await _contact()
	game.autopilot = true
	c.debug_skip_to_finale()
	assert_true(await wait_until(func() -> bool: return c.phase == ContactMode.Phase.FINALE, 8.0), "яичница убеждена — финал")
	assert_true(await run_until(func() -> bool: return c.phase == ContactMode.Phase.HIDEOUT, 9000), "змея выбралась из ящика")
	var alive: Array = c.survivors()
	assert_eq(alive.size(), 1, "выжил один спутник")
	assert_true(alive[0]["protected"] and alive[0]["node"] is TeddyBear, "и это швея")
	assert_eq((alive[0]["node"] as TeddyBear).type, TeddyBear.Type.SEAMSTRESS)
	assert_true(c.finale.fire != null and c.finale.fire.plain, "пожар — чистый ящик, без обломков")
	assert_gt(float(c.finale.shots), 0.0, "учёный стрелял")
	c.skip()
	await frames(2)
	assert_eq(game.state, Game.State.WIN, "после развязки — итоги")
	assert_true(Secrets.is_found("contact"), "«Контакт» пройден — пасхалка открыта")
	assert_true(game.hud.end_screen.visible)


func test_menu_offers_contact_after_it_is_found() -> void:
	await boot()
	assert_false(game.hud.menu.contact_button.visible, "до прохождения входа нет")
	Secrets.unlock("contact", false)
	game.menu_demo_refresh()
	assert_true(game.hud.menu.contact_button.visible, "после — неприметная кнопка «КОНТАКТ»")
	game.hud.menu.contact_button.pressed.emit()
	assert_eq(game.state, Game.State.CONTACT)


# ---------------------------------------------------------------- финал → «Контакт»

func test_ending_goes_through_fake_menu_into_contact() -> void:
	await boot()
	game.args["ending"] = true
	game.start_game(1)
	game.score = 300
	Engine.time_scale = 8.0
	assert_true(await wait_until(func() -> bool: return game.state == Game.State.FAKE_MENU, 40.0), "финал → фальшивое меню")
	assert_true(game.ending == null, "финал убран")
	assert_false(game.contact_report.is_empty(), "итоги обычного забега подведены до «Контакта»")
	assert_eq(SaveData.best(1), 300, "и записаны — ровно один раз")
	assert_true(game.hud.menu.glitch, "меню — фальшивое")
	assert_true(game.hud.menu.glitch_button.visible and not game.hud.menu.diff_buttons[0].is_visible_in_tree(),
		"одна кнопка вместо карточек")
	assert_true(await wait_until(func() -> bool: return game.state == Game.State.CONTACT, 10.0), "курсор нажал — «Контакт»")
	assert_true(game.contact != null)
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "курсор мыши вернули")


func test_skipping_ending_still_leads_to_contact() -> void:
	await boot()
	game.args["ending"] = true
	game.debug_run = true
	game.start_game(1)
	await frames(2)
	game.ending.skip()
	await frames(2)
	assert_eq(game.state, Game.State.FAKE_MENU, "пропуск финала не отменяет продолжения")


func test_daily_ending_stays_classic() -> void:
	await boot()
	Game.daily_mode = true
	game.args["ending"] = true
	game.debug_run = true
	game.start_game(1)
	await frames(2)
	assert_false(game.ending.to_contact, "испытание дня кончается как раньше")
	game.ending.skip()
	await frames(2)
	assert_eq(game.state, Game.State.WIN)
	Game.daily_mode = false
