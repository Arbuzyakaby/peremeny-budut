extends "res://tests/test_case.gd"
## v12.3: статистика забега для расширенных итогов — серия, удары, прозвище, лучшая серия в сохранении.

const RunStats = preload("res://scripts/game/run_stats.gd")
const RunReport = preload("res://scripts/game/run_report.gd")


func before_each() -> void:
	use_temp_storage()


func test_combo_grows_within_gap_and_breaks_after() -> void:
	var s := RunStats.new()
	s.on_score(1.0)
	s.on_score(2.5)
	s.on_score(5.0)
	assert_eq(s.combo, 3, "промежутки не больше 3 с — серия идёт")
	s.on_score(9.0)
	assert_eq(s.combo, 1, "пауза длиннее 3 с рвёт серию")
	assert_eq(s.best_combo, 3, "лучшая серия помнится")


func test_hit_breaks_combo_and_counts() -> void:
	var s := RunStats.new()
	s.on_score(1.0)
	s.on_score(2.0)
	s.on_hit()
	assert_eq(s.combo, 0)
	assert_eq(s.hits, 1)
	assert_eq(s.best_combo, 2)


func test_stage_times_and_flawless() -> void:
	var s := RunStats.new()
	s.stage_begin(0.0)
	s.stage_end(40.0, 0)          # без ударов
	s.stage_begin(40.0)
	s.on_hit()
	s.stage_end(75.0, 1)          # с ударом
	s.stage_begin(75.0)
	s.stage_end(95.0, 2)          # без ударов, самый быстрый
	assert_eq(s.flawless, 2)
	assert_eq(s.stage_times.size(), 3)
	assert_eq(s.fastest_stage(), 2)
	assert_eq(s.stage_ids[s.fastest_stage()], 2, "запоминается номер этапа, а не позиция")


func test_reset_clears_everything() -> void:
	var s := RunStats.new()
	s.on_score(1.0)
	s.on_hit()
	s.on_ability()
	s.note_length(30)
	s.stage_begin(0.0)
	s.stage_end(10.0, 0)
	s.reset()
	assert_eq(s.best_combo + s.hits + s.abilities + s.peak_length + s.flawless, 0)
	assert_eq(s.fastest_stage(), -1)


func test_peak_length_only_grows() -> void:
	var s := RunStats.new()
	s.note_length(20)
	s.note_length(15)
	assert_eq(s.peak_length, 20)


func test_nickname_priorities() -> void:
	var s := RunStats.new()
	assert_eq(s.nickname(true), "Неприкосновенная", "победа без ударов — самое редкое")
	s.on_hit()
	assert_eq(s.nickname(false), "Ползучая")
	assert_eq(s.nickname(true), "Просто молодец")
	s.best_combo = 12
	assert_eq(s.nickname(true), "Мясорубка")
	s.best_combo = 0
	s.abilities = 15
	assert_eq(s.nickname(false), "Арсенал на ножках")
	s.abilities = 0
	s.peak_length = 60
	assert_eq(s.nickname(false), "Длинная история")


func test_best_combo_saved_only_when_beaten() -> void:
	assert_false(RunStats.submit_best_combo(2), "короче трёх не записывается")
	assert_true(RunStats.submit_best_combo(5))
	assert_false(RunStats.submit_best_combo(5), "равная — не рекорд")
	assert_false(RunStats.submit_best_combo(4))
	assert_true(RunStats.submit_best_combo(6))
	assert_eq(RunStats.saved_best_combo(), 6)


func test_best_combo_does_not_touch_score_records() -> void:
	SaveData.submit_score(1, 900)
	RunStats.submit_best_combo(7)
	assert_eq(SaveData.best(1), 900)


func test_stat_rows_show_what_happened() -> void:
	var s := RunStats.new()
	s.best_combo = 8
	s.abilities = 4
	s.peak_length = 33
	s.stage_begin(0.0)
	s.stage_end(70.0, 0)
	s.stage_begin(70.0)
	s.stage_end(105.0, 1)
	var rows := RunReport.stat_rows(s, true)
	var by := {}
	for r: Array in rows:
		by[r[0]] = r
	assert_true(by.has("Лучшая серия"))
	assert_true(str(by["Лучшая серия"][1]).contains("8 подряд"))
	assert_true(str(by["Лучшая серия"][1]).contains("ЛИЧНЫЙ РЕКОРД"))
	assert_eq(by["Получено ударов"][1], "ни одного!\u0020\u0020(этапов без ударов: 2)")
	assert_eq(by["Приёмов / длина змеи"][1], "4 / 33")
	assert_true(str(by["Быстрее всего"][1]).ends_with("0:35"), "самый быстрый этап — 35 с")


func test_short_combo_and_single_stage_rows_are_hidden() -> void:
	var s := RunStats.new()
	s.best_combo = 2
	s.stage_begin(0.0)
	s.stage_end(30.0, 0)
	var labels := []
	for r: Array in RunReport.stat_rows(s, false):
		labels.append(r[0])
	assert_false(labels.has("Лучшая серия"), "серия из двух — не серия")
	assert_false(labels.has("Быстрее всего"), "с одним этапом сравнивать не с чем")
