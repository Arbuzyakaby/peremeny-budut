extends "res://tests/integration/game_case.gd"
## Пересадка образца №48 (transfer.gd) — продолжение финала: утро, учёный возвращается и говорит,
## щепоть берёт змейку, кадры глазами змейки между морганиями, змейка в новом ящике, done.
## Сцену гоняем ускоренно и проверяем, что она проходит все стадии по порядку.

const Lab = preload("res://scripts/ending/lab.gd")


func _to_transfer() -> Variant:
	await boot()
	game.args["ending"] = true
	game.start_game(1)
	Engine.time_scale = 8.0
	var ok := await wait_until(func() -> bool: return game.ending != null and game.ending.transfer != null, 40.0)
	assert_true(ok, "финал дошёл до пересадки")
	return game.ending.transfer if ok else null


func test_transfer_plays_every_stage_in_order() -> void:
	var tr = await _to_transfer()
	if tr == null:
		return
	var lab: Lab = tr.lab
	assert_true(lab.show_new_box, "на столе — новый ящик для №48")
	assert_true(await wait_until(func() -> bool: return lab.sx <= Lab.STAND_X + 1.0 and lab.lights >= 1.0, 6.0),
		"утро: свет и учёный у стола")
	assert_true(await wait_until(func() -> bool: return lab.say_text.begins_with("Образец №48"), 6.0),
		"учёный говорит — и рот двигается по его реплике")
	assert_true(await wait_until(func() -> bool: return tr.carrying, 8.0), "щепоть взяла змейку")
	assert_true(await wait_until(func() -> bool: return tr.pov, 4.0), "дальше — глазами змейки")
	var saw_open := [false]
	var done := [false]
	tr.done.connect(func() -> void: done[0] = true)
	while not done[0] and is_instance_valid(tr):
		if tr.lids > 0.9:
			saw_open[0] = true
		await tree.process_frame
		if Engine.get_frames_drawn() > 100000:
			break
	assert_true(saw_open[0], "между морганиями веки открываются")
	assert_true(done[0], "сцена закончилась")
	Engine.time_scale = 1.0


func test_eye_and_pinch_draw_in_every_phase() -> void:
	var tr = await _to_transfer()
	if tr == null:
		return
	Engine.time_scale = 1.0
	for lids in [0.0, 0.5, 1.0]:
		tr.pov = true
		tr.lids = lids
		await assert_draws(tr.eye, "веки %.1f" % lids)
	tr.pinch_close = 1.0
	tr.pinch_pos = tr.baby.head_pos
	await assert_draws(tr.pinch, "щепоть")
