extends "res://tests/test_case.gd"
## Таблицы баланса согласованы между собой.

const Balance = preload("res://scripts/core/balance.gd")
const SynthMusic = preload("res://scripts/audio/synth_music.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Tex = preload("res://scripts/gfx/tex.gd")

const KEYS := ["name", "color", "lives", "bears", "forks", "pills", "bear_speed", "bear_aggr", "boss_hp",
	"proj_speed", "yolk_time", "tempo", "score_mult", "no_skills", "coop", "desc"]


func test_four_difficulties_with_all_keys() -> void:
	assert_eq(Balance.DIFFICULTIES.size(), 4)
	for d: Dictionary in Balance.DIFFICULTIES:
		for k in KEYS:
			assert_true(d.has(k), "%s: нет ключа %s" % [d.get("name", "?"), k])


func test_difficulty_grows_monotonically() -> void:
	for i in range(1, Balance.DIFFICULTIES.size()):
		var a: Dictionary = Balance.DIFFICULTIES[i - 1]
		var b: Dictionary = Balance.DIFFICULTIES[i]
		assert_true(b["lives"] <= a["lives"], "жизней не больше, чем на предыдущей")
		for k in ["bears", "forks", "pills", "boss_hp", "score_mult"]:
			assert_true(b[k] > a[k], "%s растёт: %s" % [k, b["name"]])
		assert_true(b["tempo"] < a["tempo"], "темп быстрее")


func test_only_ultra_disables_skills() -> void:
	for i in 3:
		assert_false(Balance.DIFFICULTIES[i]["no_skills"])
	assert_true(Balance.DIFFICULTIES[3]["no_skills"])
	assert_eq(Balance.DIFFICULTIES[3]["lives"], 1)


func test_stages_table() -> void:
	assert_eq(Balance.STAGES.size(), Balance.STAGE_COUNT)
	assert_eq(Balance.STAGES[Balance.BOSS_STAGE]["key"], "", "у босса нет счётчика цели")
	for st: Dictionary in Balance.STAGES:
		assert_true(st["music"] in SynthMusic.TRACKS, "трек %s существует" % st["music"])
	assert_eq(Balance.goal(Balance.DIFFICULTIES[1], 0), 15)
	assert_eq(Balance.goal(Balance.DIFFICULTIES[1], 3), 0)


func test_every_special_bear_gives_ability() -> void:
	for type in range(1, TeddyBear.Type.size()):
		assert_true(Balance.ABILITIES.has(type), "атака для типа %d" % type)
	assert_false(Balance.ABILITIES.has(TeddyBear.Type.NORMAL), "обычный медведь атаки не даёт")
	assert_eq(Balance.BEAR_POINTS.size(), TeddyBear.Type.size())


func test_difficulty_index_is_clamped() -> void:
	assert_eq(Balance.difficulty(-5)["name"], Balance.DIFFICULTIES[0]["name"])
	assert_eq(Balance.difficulty(99)["name"], Balance.DIFFICULTIES[3]["name"])


func test_coop_only_on_hard_and_ultra() -> void:
	assert_eq(Balance.DIFFICULTIES[0]["coop"], 0, "Лёгкая — без кооператива")
	assert_eq(Balance.DIFFICULTIES[1]["coop"], 0, "Нормальная — без кооператива")
	assert_eq(Balance.DIFFICULTIES[2]["coop"], 1, "Сложная — враги помогают друг другу")
	assert_eq(Balance.DIFFICULTIES[3]["coop"], 2, "Ультра — стаей")


func test_fork_stage_uses_drawer_floor() -> void:
	assert_eq(Balance.STAGES[1]["floor"], Tex.Floor.DRAWER, "вилки — в ящике для приборов, а не на сером подносе")
	assert_has(String(Balance.STAGES[1]["hint"]), "НЕ БЕЙ В ЛОБ")


# ---------------------------------------------------------------- v8.0: напряжение музыки

const GameScript = preload("res://scripts/game/game.gd")


func test_music_intensity_rules() -> void:
	assert_eq(GameScript.music_intensity(false, 1, 3, 3, false, false, 0.0), 0.0, "спокойное начало этапа")
	assert_gt(GameScript.music_intensity(false, 1, 3, 3, true, false, 0.0), 0.3, "клещи — напряжённее")
	assert_gt(GameScript.music_intensity(false, 1, 1, 3, false, false, 0.0), 0.4, "последняя жизнь")
	assert_eq(GameScript.music_intensity(false, 1, 1, 1, false, false, 0.0), 0.0, "Ультра с одной жизнью — не паника с начала")
	var p1 := GameScript.music_intensity(true, 1, 3, 3, false, false, 0.0)
	var p3 := GameScript.music_intensity(true, 3, 3, 3, false, false, 0.0)
	assert_gt(p3, p1, "третья фаза яичницы громче первой")
	assert_eq(GameScript.music_intensity(true, 1, 3, 3, false, true, 0.0), 1.0, "открытый желток — на полную")
