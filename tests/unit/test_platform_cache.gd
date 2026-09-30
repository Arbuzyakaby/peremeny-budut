extends "res://tests/test_case.gd"
## Платформа (platform.gd) и дисковый кэш звука (audio_cache.gd) — то, что раньше проверялось
## только мимоходом: принудительный телефон, безопасная зона без окна, описание устройства; кэш
## отвергает чужие и испорченные файлы, выключен без флага, убирает кэш прошлых версий.

const Platform = preload("res://scripts/core/platform.gd")
const AudioCache = preload("res://scripts/audio/audio_cache.gd")

const DIR := "user://test_cache_unit"


func before_each() -> void:
	AudioCache.force = true
	AudioCache.dir = DIR
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)
	AudioCache.force = false
	AudioCache.dir = "user://audio_cache"
	Platform.force_mobile = false
	Platform.force_touch = false


# ---------------------------------------------------------------- платформа

func test_forced_phone_and_touch() -> void:
	Platform.force_mobile = true
	assert_true(Platform.is_mobile(), "--touch на ПК — телефонный режим")
	assert_has(Platform.describe(), "телефон")
	Platform.force_mobile = false
	assert_has(Platform.describe(), "ПК")
	Platform.force_touch = true
	assert_true(Platform.has_touchscreen())
	Platform.force_touch = false
	assert_false(Platform.has_touchscreen(), "без окна сенсора нет")


func test_safe_margins_are_zero_without_a_phone() -> void:
	var m := Platform.safe_margins(tree.root)
	assert_eq(m, Vector4.ZERO, "на ПК и в тестах выреза камеры нет")
	assert_true(Platform.is_headless(), "тесты идут без окна")
	Platform.vibrate(50, true)  # на ПК вибрация — тихо ничего не делает
	assert_ne(Platform.renderer_name(), "", "рендерер назван")


# ---------------------------------------------------------------- кэш звука

func _stream(seed_v: int) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 22050 + seed_v
	var data := PackedByteArray()
	data.resize(64)
	for i in 64:
		data[i] = (i * 7 + seed_v) % 256
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD if seed_v % 2 else AudioStreamWAV.LOOP_DISABLED
	s.loop_end = 16
	return s


func test_round_trip_keeps_every_field() -> void:
	AudioCache.save_group("g", {"a": _stream(1), "b": _stream(2)})
	var back := AudioCache.load_group("g")
	assert_len(back, 2)
	var a: AudioStreamWAV = back["a"]
	assert_eq(a.mix_rate, 22051)
	assert_eq(a.loop_mode, AudioStreamWAV.LOOP_FORWARD, "петля сохранилась")
	assert_eq(a.loop_end, 16)
	assert_eq(a.data, _stream(1).data, "те же отсчёты")


func test_disabled_cache_reads_and_writes_nothing() -> void:
	AudioCache.force = false
	AudioCache.save_group("g", {"a": _stream(1)})
	assert_len(DirAccess.get_files_at(DIR), 0, "в редакторе и тестах кэш не пишется")
	assert_eq(AudioCache.load_group("g"), {})


func test_foreign_and_truncated_files_are_rejected() -> void:
	AudioCache.save_group("g", {"a": _stream(1)})
	var path := AudioCache._path("g")
	var bytes := FileAccess.get_file_as_bytes(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes.slice(0, bytes.size() - 10))
	f.close()
	assert_eq(AudioCache.load_group("g"), {}, "оборванный файл — не кэш")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_32(0xDEADBEEF)
	f.store_buffer(bytes.slice(4))
	f.close()
	assert_eq(AudioCache.load_group("g"), {}, "чужая подпись — не кэш")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.store_8(1)
	f.close()
	assert_eq(AudioCache.load_group("g"), {}, "лишний хвост — не кэш")


func test_old_versions_are_dropped() -> void:
	var old := DIR.path_join("sounds_v11.2_s1.bin")
	var f := FileAccess.open(old, FileAccess.WRITE)
	f.store_32(1)
	f.close()
	var other := DIR.path_join("readme.txt")
	f = FileAccess.open(other, FileAccess.WRITE)
	f.store_string("не трогать")
	f.close()
	AudioCache.save_group("sounds", {"a": _stream(1)})
	assert_false(FileAccess.file_exists(old), "кэш прошлой версии удалён")
	assert_true(FileAccess.file_exists(other), "чужие файлы не трогаем")
	assert_true(FileAccess.file_exists(AudioCache._path("sounds")))
	assert_has(AudioCache._path("sounds"), "_v%s_" % ProjectSettings.get_setting("application/config/version"),
		"имя привязано к версии игры")


func test_empty_group_is_not_saved() -> void:
	AudioCache.save_group("g", {})
	assert_false(FileAccess.file_exists(AudioCache._path("g")))
