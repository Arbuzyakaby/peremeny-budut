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


func test_save_is_encrypted_not_plain_text() -> void:
	SaveData.submit_score(1, 4242)
	var raw := FileAccess.get_file_as_bytes(SaveData.path).get_string_from_ascii()
	assert_false(raw.contains("4242"), "рекорд не виден в файле открытым текстом")
	assert_false(raw.contains("[best]"), "секции не видны")
	assert_eq(SaveData.best(1), 4242, "а игра читает")
	assert_false(FileAccess.file_exists(SaveData.path + ".tmp"), "временный файл подменил настоящий")


func test_hand_edited_save_is_ignored() -> void:
	var f := FileAccess.open(SaveData.path, FileAccess.WRITE)
	f.store_string("[best]\n1=999999\n\n[skills]\nscales=99999\n")
	f.close()
	assert_eq(SaveData.best(1), 0, "правка в блокноте не даёт рекорд")
	Skills.load_progress()
	assert_eq(Skills.scales, 0, "и чешуйки тоже")


func test_legacy_plain_save_migrates_once() -> void:
	var legacy := TMP + "/save.cfg"
	var old := ConfigFile.new()
	old.set_value("best", "2", 1500)
	old.set_value("skills", "scales", 33)
	old.save(legacy)
	SaveData.legacy_path = legacy
	assert_eq(SaveData.best(2), 1500, "рекорд из старого сохранения")
	Skills.load_progress()
	assert_eq(Skills.scales, 33, "чешуйки из старого сохранения")
	assert_false(FileAccess.file_exists(legacy), "старый файл убран")
	assert_true(FileAccess.file_exists(legacy + ".old"), "но оставлен копией")
	var again := ConfigFile.new()
	again.set_value("best", "2", 999999)
	again.save(legacy)  # подложить текстовый файл заново — уже не читается
	assert_eq(SaveData.best(2), 1500, "повторного переноса нет")
	SaveData.legacy_path = ""
