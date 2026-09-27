extends "res://tests/test_case.gd"
## Звуки синтезатора: полный набор, без перегруза и щелчков в конце; петля огня бесшовна.

const Sfx = preload("res://scripts/audio/sfx.gd")
const SoundBank = preload("res://scripts/audio/sound_bank.gd")
const SynthMusic = preload("res://scripts/audio/synth_music.gd")


func _samples(s: AudioStreamWAV) -> PackedFloat32Array:
	var d := s.data
	var out := PackedFloat32Array()
	out.resize(d.size() / 2)
	for i in out.size():
		out[i] = d.decode_s16(i * 2) / 32768.0
	return out


func test_sound_count_matches_constant() -> void:
	assert_eq(Sfx.sounds.size(), SoundBank.SOUND_COUNT, "SOUND_COUNT для полосы загрузки")


func test_design_language_sounds_exist() -> void:
	for n in ["ui_move", "ui_select", "ui_toggle", "ui_back", "ui_error"]:
		assert_true(Sfx.sounds.has(n), n)


func test_no_clipping_and_no_end_clicks() -> void:
	for name: String in Sfx.sounds:
		var buf := _samples(Sfx.sounds[name])
		assert_true(buf.size() > 100, name + ": не пустой")
		var peak := 0.0
		for v in buf:
			peak = maxf(peak, absf(v))
		assert_true(peak <= 0.95, "%s: пик %.2f" % [name, peak])
		var tail := 0.0
		for i in range(maxi(buf.size() - 8, 0), buf.size()):
			tail = maxf(tail, absf(buf[i]))
		assert_true(tail < 0.02, "%s: щелчок в конце (%.3f)" % [name, tail])


func test_fire_loop_is_seamless() -> void:
	var fire := SynthMusic.new().build_fire_loop()
	assert_eq(fire.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	var buf := _samples(fire)
	# шов не должен выделяться: скачок на стыке не больше самого резкого соседнего перепада внутри петли
	var jump := 0.0
	for i in range(1, buf.size()):
		jump = maxf(jump, absf(buf[i] - buf[i - 1]))
	assert_true(absf(buf[buf.size() - 1] - buf[0]) <= jump + 0.001, "стык конца и начала")


func test_every_stage_track_is_known() -> void:
	for t in ["level", "boss", "forks", "pills", "sad", "fire"]:
		assert_true(t in SynthMusic.TRACKS, t)


# ---------------------------------------------------------------- шина: голоса, разброс, ducking, тишина

func _bus() -> Node:
	var s: Node = add(Sfx.new())
	s.last_played.clear()
	return s


func test_same_sound_uses_at_most_two_voices() -> void:
	var s := _bus()
	for i in 5:  # пять таблеток приземлились разом
		s.last_played.clear()  # мимо кулдауна — проверяем именно лимит голосов
		s.recent.clear()
		s.play("pill_land")
	assert_true(s.voices_of("pill_land") <= Sfx.MAX_SAME, "не больше двух приземлений одновременно")
	assert_true(s.voices_of("pill_land") >= 1)


func test_burst_limit_drops_extra_but_not_priority() -> void:
	var s := _bus()
	for n in ["bite", "pop", "step", "kick", "shuriken", "clang", "splat", "poof"]:
		s.play(n)
	assert_eq(s.recent.size(), Sfx.BURST_MAX, "за 100 мс — не больше четырёх новых звуков")
	assert_true(s.dropped >= 2, "лишние отброшены")
	var before: int = s.dropped
	s.play("ignite")
	s.play("ui_error")
	assert_eq(s.dropped, before, "важные и звуки интерфейса проходят всегда")


func test_pitch_jitter_ranges() -> void:
	for i in 40:
		var j := Sfx.jitter_of("step")
		assert_true(j >= 1.0 - Sfx.JITTER - 0.0001 and j <= 1.0 + Sfx.JITTER + 0.0001, "шаги ±3%")
		var d := Sfx.jitter_of("ui_detent")
		assert_true(d >= 0.95 and d <= 1.05, "детент ±5%")
	assert_eq(Sfx.jitter_of("win"), 1.0, "мелодичные — без разброса")
	for n in ["pill_land", "bite", "pop", "step", "shuriken"]:
		assert_false(n in Sfx.NO_JITTER, n + " — с разбросом")


func test_duck_and_hush() -> void:
	var s := _bus()
	s.duck(-4.0, 0.05, 0.05)
	assert_near(s.duck_db(), -4.0, 0.01, "огонь приглушён под огнетушителем")
	assert_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambient")),
		linear_to_db(maxf(Settings.num("ambient"), 0.0001)), 0.01, "громкость шины из настроек не тронута")
	await tree.create_timer(0.3).timeout
	assert_near(s.duck_db(), 0.0, 0.01, "вернулся")
	s.hush(0.05)
	assert_true(s.is_hushed(), "тишина перед вспышкой")
	await tree.create_timer(0.2).timeout
	assert_false(s.is_hushed(), "тишина кончилась")
	s.play("crackle")
	for i in s.players.size():
		if s.voice_names[i] == "crackle":
			assert_eq(s.players[i].bus, &"Ambient", "треск идёт через шину огня")


func test_hush_always_releases() -> void:
	var s := _bus()
	s.hush(0.3)
	s.hush(0.05)  # повторная пауза: снимает её таймер последнего вызова, а не первого
	await tree.create_timer(0.15).timeout
	assert_false(s.is_hushed(), "звук вернулся, даже если таймер сработал раньше часов")
	s.hush(5.0)
	s.hush(0.0)
	assert_false(s.is_hushed(), "hush(0) снимает тишину сразу")
	await tree.create_timer(0.3).timeout
	assert_false(s.is_hushed(), "старый таймер не глушит повторно")
