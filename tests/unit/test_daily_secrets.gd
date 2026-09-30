extends "res://tests/test_case.gd"
## Испытание дня и пасхалки подробнее: ключ и сид дня, пара модификаторов не повторяется, серия дней
## (продолжение, разрыв, предел бонуса, лучшая серия), рекорд дня и античит часов; пасхалки —
## открытие один раз, сохранение, праздник по календарю, сброс.

const Balance = preload("res://scripts/core/balance.gd")


func before_each() -> void:
	use_temp_storage()


# ---------------------------------------------------------------- день

func test_day_key_is_padded_and_seed_is_stable() -> void:
	assert_eq(Daily.day_key({"year": 2026, "month": 3, "day": 5}), "2026-03-05")
	assert_eq(Daily.seed_for("2026-03-05"), Daily.seed_for("2026-03-05"), "сид дня один для всех")
	assert_ne(Daily.seed_for("2026-03-05"), Daily.seed_for("2026-03-06"), "у соседних дней разный")


func test_prev_key_crosses_months_and_years() -> void:
	assert_eq(Daily.prev_key("2026-01-01"), "2025-12-31")
	assert_eq(Daily.prev_key("2024-03-01"), "2024-02-29", "високосный год")
	assert_eq(Daily.prev_key("2026-10-01"), "2026-09-30")


func test_pair_has_two_different_modifiers_all_year() -> void:
	var seen := {}
	for m in range(1, 13):
		for d in range(1, 29):
			var pair := Daily.pair_for(Daily.day_key({"year": 2026, "month": m, "day": d}))
			assert_len(pair, 2)
			assert_ne(pair[0]["id"], pair[1]["id"], "два разных модификатора (%d.%d)" % [d, m])
			seen[pair[0]["id"]] = true
			seen[pair[1]["id"]] = true
	assert_eq(seen.size(), Daily.MODIFIERS.size(), "за год выпадает каждый модификатор")


func test_combined_score_multiplier_is_generous_but_bounded() -> void:
	for a in Daily.MODIFIERS.size():
		for b in Daily.MODIFIERS.size():
			if a == b:
				continue
			var c := Daily.combine([Daily.MODIFIERS[a], Daily.MODIFIERS[b]])
			var cfg := Daily.apply(Balance.difficulty(Daily.BASE_DIFFICULTY), c)
			assert_between(float(cfg["score_mult"]), 1.0, 8.0, "%s + %s: множитель очков" % [c["id"], ""])
			assert_has(String(cfg["name"]), "ИСПЫТАНИЕ", "имя в итогах")


func test_apply_never_rounds_counts_to_zero() -> void:
	var cfg := Balance.difficulty(0).duplicate()
	cfg["bears"] = 1
	var out := Daily.apply(cfg, {"id": "x", "name": "X", "mul": {"bears": 0.1}})
	assert_eq(out["bears"], 1, "врагов не меньше одного")
	assert_eq(cfg["bears"], 1, "исходная таблица не меняется")


# ---------------------------------------------------------------- серия

func test_streak_grows_breaks_and_remembers_the_best() -> void:
	assert_eq(Daily.streak("2026-05-01"), 0)
	for d in ["2026-05-01", "2026-05-02", "2026-05-03"]:
		Daily.register_play(d)
	assert_eq(Daily.streak("2026-05-03"), 3, "три дня подряд")
	assert_eq(Daily.streak("2026-05-04"), 3, "на следующий день серия ещё жива (не сыграно)")
	assert_eq(Daily.streak("2026-05-05"), 0, "пропуск дня — серия оборвалась")
	Daily.register_play("2026-05-06")
	assert_eq(Daily.streak("2026-05-06"), 1, "началась заново")
	assert_eq(Daily.best_streak(), 3, "лучшая серия помнится")


func test_streak_bonus_is_capped() -> void:
	assert_eq(Daily.streak_bonus(1), Daily.STREAK_SCALES)
	assert_eq(Daily.streak_bonus(Daily.STREAK_CAP), Daily.STREAK_CAP * Daily.STREAK_SCALES)
	assert_eq(Daily.streak_bonus(Daily.STREAK_CAP + 20), Daily.STREAK_CAP * Daily.STREAK_SCALES, "дальше не дорожает")


func test_day_record_and_clock_cheat() -> void:
	assert_true(Daily.submit("2026-06-10", 500), "первый результат — рекорд")
	assert_false(Daily.submit("2026-06-10", 400), "хуже — не рекорд")
	assert_true(Daily.submit("2026-06-10", 900))
	assert_eq(Daily.best("2026-06-10"), 900)
	Daily.register_play("2026-06-10")
	assert_false(Daily.submit("2026-06-01", 99999), "перевели часы назад — рекорд прошлого дня не принимается")
	assert_eq(Daily.best("2026-06-01"), 0)
	Daily.load_progress()
	assert_eq(Daily.best("2026-06-10"), 900, "рекорд дня сохранился")
	assert_eq(Daily.days_played(), 1)


# ---------------------------------------------------------------- пасхалки

func test_secrets_unlock_once_and_persist() -> void:
	var id: String = Secrets.LIST[0]["id"]
	assert_false(Secrets.is_found(id))
	assert_true(Secrets.unlock(id), "первый раз — нашли")
	assert_false(Secrets.unlock(id), "второй раз — уже найдена")
	assert_false(Secrets.unlock("нет-такой"), "неизвестная не открывается")
	Secrets.load_progress()
	assert_true(Secrets.is_found(id), "сохранилась")
	assert_eq(Secrets.found_count(), 1)
	Secrets.reset()
	assert_eq(Secrets.found_count(), 0, "сброс")


func test_every_secret_has_a_name_and_a_hint() -> void:
	var ids := {}
	for e: Dictionary in Secrets.LIST:
		assert_false(ids.has(e["id"]), "id пасхалки уникален: " + String(e["id"]))
		ids[e["id"]] = true
		assert_false(Secrets.entry(e["id"]).is_empty())
		for field in e:
			assert_ne(String(e[field]), "", "%s: поле %s не пустое" % [e["id"], field])
	assert_eq(Secrets.total(), Secrets.LIST.size())
	assert_true(Secrets.entry("нет-такой").is_empty())


func test_holiday_follows_the_calendar() -> void:
	var yes := 0
	for m in range(1, 13):
		for d in range(1, 29):
			if Secrets.is_holiday({"year": 2026, "month": m, "day": d}):
				yes += 1
	assert_eq(yes, 4 + 7, "с 25 декабря по 7 января: 25–28.12 и 1–7.01 в этой выборке")
