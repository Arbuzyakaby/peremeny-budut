extends "res://tests/test_case.gd"
## Звуки синтезатора: полный набор, без перегруза и щелчков в конце; петля огня бесшовна.

const Sfx = preload("res://scripts/audio/sfx.gd")
const Synth = preload("res://scripts/audio/synth.gd")
const SynthMusic = preload("res://scripts/audio/synth_music.gd")


func _samples(s: AudioStreamWAV) -> PackedFloat32Array:
	var d := s.data
	var out := PackedFloat32Array()
	out.resize(d.size() / 2)
	for i in out.size():
		out[i] = d.decode_s16(i * 2) / 32768.0
	return out


func test_sound_count_matches_constant() -> void:
	assert_eq(Sfx.sounds.size(), Synth.SOUND_COUNT, "SOUND_COUNT для полосы загрузки")


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
