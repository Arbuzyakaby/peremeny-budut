extends "res://tests/test_case.gd"
## Настройки: схема, значения по умолчанию, защита от мусора, сохранение, чтение старого формата.


func before_each() -> void:
	use_temp_storage()


func test_schema_is_well_formed() -> void:
	var keys := {}
	var tabs := []
	for t in Settings.TABS:
		tabs.append(t["id"])
	for s: Dictionary in Settings.SCHEMA:
		assert_false(keys.has(s["key"]), "ключ %s не повторяется" % s["key"])
		keys[s["key"]] = true
		assert_true(s["tab"] == "" or s["tab"] in tabs, "%s: вкладка существует" % s["key"])
		assert_true(s.has("label") and s["label"] != "", "%s: есть подпись" % s["key"])
		if s["kind"] == Settings.Kind.ENUM:
			assert_true((s["options"] as Array).size() >= 2, "%s: варианты" % s["key"])
	assert_true(Settings.SCHEMA.size() >= 30, "переключателей стало заметно больше")


func test_every_tab_has_rows() -> void:
	for t in Settings.TABS:
		var n := 0
		for s: Dictionary in Settings.SCHEMA:
			if s["tab"] == t["id"]:
				n += 1
		assert_true(n >= 3, "во вкладке %s хотя бы 3 строки" % t["id"])


func test_defaults_loaded_without_file() -> void:
	for s: Dictionary in Settings.SCHEMA:
		assert_eq(Settings.get_value(s["key"]), Settings.default_of(s), s["key"])


func test_sanitize_clamps_and_rejects_garbage() -> void:
	assert_near(Settings.sanitize("music", 7.0), 1.0)
	assert_near(Settings.sanitize("turn_sensitivity", 0.1), 0.6)
	assert_eq(Settings.sanitize("particles", 42), 2)
	assert_eq(Settings.sanitize("hints", "да"), true, "строка вместо bool — значение по умолчанию")
	assert_eq(Settings.sanitize("particles", "много"), Settings.spec("particles")["default"])


func test_save_and_load_roundtrip() -> void:
	Settings.set_value("music", 0.25)
	Settings.set_value("left_handed", true)
	Settings.set_value("particles", 0)
	Settings.save()
	Settings.reset_to_defaults()
	Settings.load_from_disk()
	assert_near(Settings.num("music"), 0.25)
	assert_true(Settings.flag("left_handed"))
	assert_eq(Settings.choice("particles"), 0)


func test_reads_v5_settings_file() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "music", 0.3)
	cf.set_value("game", "shake", 0.5)
	cf.set_value("game", "mouse_control", false)
	cf.set_value("video", "vsync", false)
	cf.save(Settings.path)
	Settings.load_from_disk()
	assert_near(Settings.num("music"), 0.3)
	assert_near(Settings.num("shake"), 0.5)
	assert_false(Settings.flag("mouse_control"))
	assert_false(Settings.flag("vsync"))
	assert_true(Settings.flag("hints"), "новые ключи — по умолчанию")


func test_derived_values() -> void:
	Settings.set_value("particles", 0)
	assert_true(Settings.particle_mult() < 0.5)
	Settings.set_value("ui_scale", 3)
	assert_near(Settings.ui_scale(), 1.3)
	Settings.set_value("touch_mode", 1)
	assert_true(Settings.touch_enabled())
	Settings.set_value("touch_mode", 2)
	assert_false(Settings.touch_enabled())
