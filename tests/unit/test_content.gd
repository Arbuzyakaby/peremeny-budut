extends "res://tests/test_case.gd"
## Контент v7.0: советы, картотека врагов, ежедневное испытание.

const Tips = preload("res://scripts/core/tips.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const ReplayScreen = preload("res://scripts/ui/screens/replay_screen.gd")

const CAUSES := ["fork_tines", "fork_whirl", "fork_pogo", "tine", "bear", "shot", "blast", "pill", "wave", "boss",
	"oil", "self", "wall"]


func before_each() -> void:
	use_temp_storage()


# ---------------------------------------------------------------- советы

func test_tips_are_plenty_and_unique() -> void:
	assert_true(Tips.count() >= 45, "советов много: %d" % Tips.count())
	var seen := {}
	for t: String in Tips.GENERAL:
		assert_false(seen.has(t), "без повторов: " + t)
		seen[t] = true
		assert_true(t.length() <= 110, "влезает в две строки: " + t)
		assert_true(t.length() >= 15, "не пустышка")


func test_every_fork_attack_has_a_hint() -> void:
	assert_eq(Tips.FORK_ATTACK_HINTS.size(), Fork.ATTACK_NAMES.size())
	for h: String in Tips.FORK_ATTACK_HINTS:
		assert_true(h.length() > 20)
	assert_true(Tips.COOP_HINT.length() > 20)


func test_every_damage_cause_has_advice() -> void:
	for c in CAUSES:
		assert_has(Tips.BY_CAUSE, c, "совет для " + c)
		assert_ne(ReplayScreen.cause_title(c), "ПРИЧИНА НЕИЗВЕСТНА", "название для " + c)
	assert_has(Tips.GENERAL, Tips.for_cause("нечто"), "неизвестная причина — общий совет")


func test_every_stage_has_hint() -> void:
	for i in Balance.STAGES.size() - 1:
		assert_true(String(Balance.STAGES[i]["hint"]).length() > 10, "подсказка этапа %d" % i)


# ---------------------------------------------------------------- картотека

func test_bestiary_entries() -> void:
	var keys := {}
	for e: Dictionary in Bestiary.ENTRIES:
		assert_false(keys.has(e["key"]), "ключ уникален")
		keys[e["key"]] = true
		for f in ["title", "group", "text", "weak", "tip", "icon"]:
			assert_true(e.has(f), "%s: поле %s" % [e["key"], f])
	for t in 8:
		assert_has(keys, "bear_%d" % t)
	for k in Fork.KINDS:
		assert_has(keys, "fork_%d" % k)
	for a in Fork.ATTACK_NAMES.size():
		assert_has(keys, "fork_atk_%d" % a)
	assert_has(keys, "pill")
	assert_has(keys, "pill_1")
	assert_has(keys, "boss")


func test_bestiary_unlock_persists() -> void:
	assert_eq(Bestiary.known_count(), 0, "с чистого листа")
	assert_true(Bestiary.unlock("fork_2"), "первая встреча")
	assert_false(Bestiary.unlock("fork_2"), "второй раз — уже известно")
	assert_false(Bestiary.unlock("дракон"), "неизвестный ключ")
	Bestiary.load_progress()
	assert_true(Bestiary.is_known("fork_2"), "сохранилось")
	assert_eq(Bestiary.known_count(), 1)
	Bestiary.reset()
	assert_false(Bestiary.is_known("fork_2"), "сброс")


# ---------------------------------------------------------------- испытание дня

func test_daily_key_and_seed() -> void:
	var d := {"year": 2026, "month": 9, "day": 7}
	assert_eq(Daily.day_key(d), "2026-09-07")
	assert_eq(Daily.seed_for("2026-09-07"), Daily.seed_for("2026-09-07"), "одинаковый у всех")
	assert_ne(Daily.seed_for("2026-09-07"), Daily.seed_for("2026-09-08"))
	assert_true(Daily.seed_for("2026-09-07") >= 0)


func test_daily_modifiers_vary() -> void:
	var ids := {}
	for day in range(1, 31):
		var m := Daily.modifier_for(Daily.day_key({"year": 2026, "month": 10, "day": day}))
		assert_has(Daily.MODIFIERS, m)
		ids[m["id"]] = true
	assert_true(ids.size() >= 3, "за месяц встречаются разные испытания: %d" % ids.size())


func test_daily_apply_does_not_touch_original() -> void:
	var base: Dictionary = Balance.difficulty(Daily.BASE_DIFFICULTY)
	var speed_before: float = base["bear_speed"]
	for m: Dictionary in Daily.MODIFIERS:
		var cfg := Daily.apply(base, m)
		assert_true(String(cfg["name"]).begins_with("ИСПЫТАНИЕ"), m["id"])
		assert_eq(cfg["daily"], m["id"])
		assert_true(int(cfg["score_mult"]) >= int(base["score_mult"]), "очков не меньше")
		assert_eq(typeof(cfg["forks"]), TYPE_INT, "цели остаются целыми")
		assert_true(int(cfg["forks"]) >= 1)
	assert_near(float(base["bear_speed"]), speed_before, 0.0001, "таблица сложности не испорчена")


func test_daily_specific_rules() -> void:
	var base: Dictionary = Balance.difficulty(1)
	var by_id := {}
	for m: Dictionary in Daily.MODIFIERS:
		by_id[m["id"]] = Daily.apply(base, m)
	assert_eq(by_id["one_life"]["lives"], 1)
	assert_gt(by_id["speed"]["bear_speed"], base["bear_speed"])
	assert_eq(by_id["forks"]["forks"], int(base["forks"]) * 2)
	assert_true(int(by_id["forks"]["bears"]) < int(base["bears"]))


func test_daily_record() -> void:
	var key := "2026-01-01"
	assert_eq(Daily.best(key), 0)
	assert_true(Daily.submit(key, 500))
	assert_false(Daily.submit(key, 300), "меньше рекорда")
	assert_true(Daily.submit(key, 800))
	Daily.load_progress()
	assert_eq(Daily.best(key), 800, "сохранилось")
	assert_eq(Daily.days_played(), 1)
