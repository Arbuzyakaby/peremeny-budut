extends "res://tests/integration/game_case.gd"
## v12.1: оптимизация — табло и враги перерисовываются только при изменении вида, звук лежит на диске.

const AudioCache = preload("res://scripts/audio/audio_cache.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")


func _cache_on() -> void:
	AudioCache.force = true
	AudioCache.dir = "user://test_audio_cache"


func _cache_off() -> void:
	for f in DirAccess.get_files_at(AudioCache.dir):
		DirAccess.remove_absolute(AudioCache.dir.path_join(f))
	DirAccess.remove_absolute(AudioCache.dir)
	AudioCache.force = false
	AudioCache.dir = "user://audio_cache"


func _stream(seed: int, loop: bool) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 22050
	var b := PackedByteArray()
	b.resize(400)
	for i in b.size():
		b[i] = (i * 7 + seed) % 256
	s.data = b
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = 190
	return s


func test_audio_cache_round_trip() -> void:
	_cache_on()
	AudioCache.save_group("unit", {"a": _stream(1, false), "b": _stream(2, true)})
	var got := AudioCache.load_group("unit")
	assert_eq(got.size(), 2, "оба звука вернулись")
	assert_eq((got["a"] as AudioStreamWAV).data, _stream(1, false).data, "байты те же")
	assert_eq((got["b"] as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD, "петля сохранилась")
	assert_eq((got["b"] as AudioStreamWAV).loop_end, 190, "конец петли сохранился")
	assert_eq(int((got["a"] as AudioStreamWAV).mix_rate), 22050, "частота сохранилась")
	_cache_off()


func test_audio_cache_ignores_broken_files() -> void:
	_cache_on()
	AudioCache.save_group("unit", {"a": _stream(3, false)})
	var path := AudioCache._path("unit")
	var f := FileAccess.open(path, FileAccess.READ)
	var bytes := f.get_buffer(f.get_length() - 10)  # оборванный файл
	f.close()
	var w := FileAccess.open(path, FileAccess.WRITE)
	w.store_buffer(bytes)
	w.close()
	assert_true(AudioCache.load_group("unit").is_empty(), "оборванный файл — не кэш")
	assert_true(AudioCache.load_group("нет_такого").is_empty(), "нет файла — пусто")
	_cache_off()


func test_audio_cache_is_off_in_editor_runs() -> void:
	assert_false(AudioCache.enabled(), "в редакторе и тестах звук всегда свежий")


func test_hud_redraws_only_when_the_picture_changes() -> void:
	await boot_stage(0)
	var o = game.hud.overlay
	o._redraw_if_changed()
	var key: Array = o._last_key.duplicate()
	o._redraw_if_changed()
	assert_eq(o._last_key, key, "ничего не менялось — ключ тот же")
	o.score_shown = 250.0
	o._redraw_if_changed()
	assert_ne(o._last_key, key, "счёт изменился — табло перерисуется")
	key = o._last_key.duplicate()
	o.stamina = 0.5
	o._redraw_if_changed()
	assert_ne(o._last_key, key, "стамина изменилась — перерисуется")
	key = o._last_key.duplicate()
	o.t += 1.0
	o._redraw_if_changed()
	assert_ne(o._last_key, key, "пульс маршрута идёт шагами — кадр анимации сменился")


func test_bear_look_changes_with_state_and_stays_put_otherwise() -> void:
	var b: TeddyBear = add(TeddyBear.new())
	b.refresh_look()
	var look: Array = b._last_look.duplicate()
	b.refresh_look()
	assert_eq(b._last_look, look, "в покое вид не меняется")
	b.hit_flash = 1.0
	b.refresh_look()
	assert_ne(b._last_look, look, "вспышка удара меняет вид")
	look = b._last_look.duplicate()
	b.give_shield()
	b.refresh_look()
	assert_ne(b._last_look, look, "щит меняет вид")
