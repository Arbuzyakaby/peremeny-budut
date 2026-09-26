extends "res://tests/test_case.gd"
## Рекорды по сложностям.


func before_each() -> void:
	use_temp_storage()


func test_no_records_at_start() -> void:
	assert_eq(SaveData.bests(4), [0, 0, 0, 0] as Array[int])


func test_only_higher_score_is_record() -> void:
	assert_true(SaveData.submit_score(1, 300))
	assert_false(SaveData.submit_score(1, 200))
	assert_false(SaveData.submit_score(1, 300), "равный — не рекорд")
	assert_true(SaveData.submit_score(1, 301))
	assert_eq(SaveData.best(1), 301)
	assert_eq(SaveData.best(0), 0, "другие сложности не тронуты")


func test_reset_keeps_skills() -> void:
	SaveData.submit_score(2, 500)
	Skills.scales = 7
	Skills.save()
	SaveData.reset_records()
	assert_eq(SaveData.best(2), 0)
	Skills.load_progress()
	assert_eq(Skills.scales, 7, "сброс рекордов не трогает чешуйки")


func test_tests_do_not_touch_real_save() -> void:
	assert_true(SaveData.path.begins_with(TMP), "тесты пишут во временный файл")
