extends "res://tests/integration/game_case.gd"
## Бой с яичницей (boss_fight.gd) по событиям: приземление, укус, фазы, оглушение, открытый желток,
## победа. Титры финала и «Контакта» (credits.gd) и яйцо в пепле (hatch.gd).

const BossFight = preload("res://scripts/game/boss_fight.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const Credits = preload("res://scripts/ending/credits.gd")
const Hatch = preload("res://scripts/ending/hatch.gd")


func _boss() -> FriedEggBoss:
	await boot_stage(Balance.BOSS_STAGE)
	assert_true(await wait_until(func() -> bool: return game.boss != null, 3.0), "яичница появилась")
	return game.boss


func test_heat_grows_with_phase_and_is_clamped() -> void:
	assert_near(BossFight.heat_for(1), 0.2, 0.001)
	assert_near(BossFight.heat_for(2), 0.6, 0.001)
	assert_near(BossFight.heat_for(3), 1.0, 0.001)
	assert_near(BossFight.heat_for(0), 0.2, 0.001, "ниже первой — как первая")
	assert_near(BossFight.heat_for(9), 1.0, 0.001, "выше третьей — как третья")


func test_boss_drops_from_above_and_pushes_the_snake_away() -> void:
	var boss := await _boss()
	assert_lt(boss.position.y, 0.0, "сначала над полем")
	game.snake.head_pos = Vector2(650, 310)
	game.snake.alive = true
	assert_true(await wait_until(func() -> bool: return boss.position.y >= 299.0, 4.0), "упала на сковороду")
	await frames(2)
	assert_gt(game.shake, 0.0, "земля дрогнула")
	assert_true(game.hud.overlay.boss_visible, "появилось табло яичницы")


func test_bite_scores_and_updates_the_board() -> void:
	var boss := await _boss()
	var fight = game.boss_fight
	var before: int = game.score
	fight._on_bitten(boss.max_hp - 1)
	assert_gt(game.score, before, "укус желтка — очки")
	assert_eq(game.hud.overlay.boss_hp, boss.max_hp - 1, "табло показывает оставшиеся укусы")
	assert_true(game.hud.overlay.boss_visible)


func test_phase_heats_the_pan_and_blows_oil_away() -> void:
	var boss := await _boss()
	var fight = game.boss_fight
	game.shots.spawn_drop(Vector2(300, 300), Vector2(10, 0), 0)
	fight._on_phase(2)
	assert_near(game.arena.heat, BossFight.heat_for(2), 0.01, "сковорода разогрелась")
	fight._on_phase(3)
	assert_near(game.arena.heat, BossFight.heat_for(3), 0.01)
	assert_true(boss != null)


func test_daze_hint_once_per_reason() -> void:
	await _boss()
	var fight = game.boss_fight
	Settings.set_value("hints", true)
	fight._on_dazed("wall")
	fight._on_dazed("wall")
	fight._on_dazed("jump")
	assert_eq(fight.daze_hinted.size(), 2, "по одной подсказке на каждую причину")


func test_yolk_hints_stop_after_two() -> void:
	var boss := await _boss()
	var fight = game.boss_fight
	boss.act = FriedEggBoss.Act.IDLE
	for i in 5:
		fight._on_yolk_opened()
	assert_true(fight.yolk_hints <= 2, "не больше двух подсказок про желток")


func test_defeat_scores_and_starts_the_ending() -> void:
	var boss := await _boss()
	var before: int = game.score
	game.boss_fight._on_defeated()
	assert_gt(game.score, before + Balance.BOSS_POINTS - 1, "за яичницу — большие очки")
	assert_true(await wait_until(func() -> bool: return game.ending != null or game.state == game.State.OUTRO, 4.0),
		"после победы — финал")
	assert_true(is_instance_valid(boss))


# ---------------------------------------------------------------- титры

class _FakeGame extends RefCounted:
	var play_time := 125.0
	var cfg := {"name": "НОРМАЛЬНАЯ"}
	var bears_eaten := 8
	var forks_broken := 5
	var pills_eaten := 7
	var dolls_done := 2
	var score := 4321


class _FakeContact extends RefCounted:
	var counts := {"bear": 3, "fork": 2, "pill": 4, "doll": 1}


func test_credits_show_the_protocol() -> void:
	var text := Credits.text(_FakeGame.new(), "Спичка: зажжена")
	assert_has(text, "Медведей съедено: 8")
	assert_has(text, "Вилок сломано: 5")
	assert_has(text, "Таблеток съедено: 7")
	assert_has(text, "Матрёшек собрано: 2 наб.")
	assert_has(text, "Время: 2:05")
	assert_has(text, "Счёт: 4321")
	assert_has(text, "Спичка: зажжена")
	assert_has(text, "версия " + str(ProjectSettings.get_setting("application/config/version")), "версия из project.godot")
	assert_false("Сожжено" in text, "без пожара строки о клетках нет")
	assert_has(Credits.text(_FakeGame.new(), "", 21), "Сожжено: 21 клетка")


func test_burnt_line_declension() -> void:
	var want := {1: "клетка", 2: "клетки", 5: "клеток", 11: "клеток", 12: "клеток", 21: "клетка", 22: "клетки",
		111: "клеток", 104: "клетки", 0: "клеток"}
	for n: int in want:
		assert_eq(Credits.burnt_line(n), "Сожжено: %d %s" % [n, want[n]])


func test_contact_credits_list_the_convinced() -> void:
	var text := Credits.contact_text(_FakeGame.new(), _FakeContact.new())
	assert_has(text, "ТЕХНИЧЕСКИЙ РЕЖИМ «КОНТАКТ»")
	assert_has(text, "Медведей убеждено: 3")
	assert_has(text, "Таблеток убеждено: 4")
	assert_has(text, "Выжили двое.")
	assert_has(text, "Время: 2:05")


# ---------------------------------------------------------------- яйцо

func test_hatch_glint_fades_and_draws_every_stage() -> void:
	var h: Hatch = add(Hatch.new())
	h.egg_glint = 1.0
	h._process(0.5)
	assert_near(h.egg_glint, 0.6, 0.001, "блик гаснет")
	h._process(5.0)
	assert_eq(h.egg_glint, 0.0, "и не уходит в минус")
	for k: float in [0.0, 0.5, 1.0]:
		h.egg_k = 1.0
		h.egg_crack = k
		await assert_draws(h, "яйцо, трещины %.1f" % k)
