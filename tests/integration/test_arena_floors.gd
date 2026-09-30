extends "res://tests/integration/game_case.gd"
## Арена-ящик: у каждого этапа свой пол и бортик, пол печётся один раз (а не каждый кадр), жар
## сковороды и мигание аптечной лампы включают обработку только пока нужны, масштаб запекания.

const Tex = preload("res://scripts/gfx/tex.gd")


func test_every_floor_bakes_and_draws() -> void:
	await boot()
	var a = game.arena
	for kind in Tex.Floor.values():
		a.set_floor(kind)
		assert_eq(a.floor_kind, kind)
		assert_eq(a.floor_view.render_target_update_mode, SubViewport.UPDATE_ONCE, "пол %d печётся один раз" % kind)
		await assert_draws(a.frame, "бортик пола %d" % kind)
		await assert_draws(a.floor_decor, "рисунок пола %d" % kind)


func test_same_floor_is_not_rebaked() -> void:
	await boot()
	var a = game.arena
	a.set_floor(Tex.Floor.TILES)
	await frames(2)
	a.floor_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	a.set_floor(Tex.Floor.TILES)
	assert_eq(a.floor_view.render_target_update_mode, SubViewport.UPDATE_DISABLED, "тот же пол — без перепечки")


func test_stage_floors_follow_the_table() -> void:
	for i in Balance.STAGES.size():
		await boot_stage(i)
		assert_eq(game.arena.floor_kind, Balance.STAGES[i]["floor"], "этап %d — свой пол" % i)
		game.queue_free()
		game = null
		await frames(2)


func test_heat_processes_only_on_the_pan() -> void:
	await boot()
	var a = game.arena
	a.set_floor(Tex.Floor.PAN)
	a.set_heat(0.6)
	assert_true(a.is_processing(), "жар дышит — обработка включена")
	await assert_draws(a.heat_node, "жар сковороды")
	a.set_heat(0.0)
	assert_false(a.is_processing(), "остыла — выключена")
	a.set_heat(0.8)
	a.set_floor(Tex.Floor.WOOD)
	assert_eq(a.heat, 0.0, "сменили пол — жара нет")


func test_lamp_flicker_switches_processing_off_after() -> void:
	await boot()
	var a = game.arena
	a.set_floor(Tex.Floor.TILES)
	a.flicker()
	assert_true(a.is_processing())
	a._process(0.2)
	await assert_draws(a.lamp_node, "мигание в провале")
	a._process(2.0)
	assert_false(a.is_processing(), "отмигала — узел спит")


func test_bake_scale_is_stepped_and_capped() -> void:
	await boot()
	var k: float = game.arena.wanted_scale()
	assert_between(k, 1.0, game.arena.MAX_BAKE_SCALE)
	assert_near(fmod(k * 4.0, 1.0), 0.0, 0.0001, "шагами по 0,25 — не перепекать на каждый пиксель")
