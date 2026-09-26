extends RefCounted
## Синтезатор: генерирует звуковые эффекты и музыку (PCM) прямо в коде — без аудиофайлов.

enum W { SINE, SQUARE, SAW, TRI, NOISE }

const SR := 22050

const LEVEL_PATTERNS := [
	[0, -1, 1, 2, -1, 1, 0, -1, 2, -1, 3, -1, 2, 1, -1, -1],
	[3, -1, 2, -1, 1, -1, 2, 3, -1, 4, -1, 3, 2, -1, 1, -1],
]
const BOSS_PATTERNS := [
	[0, 0, 3, 0, 2, 0, 1, 0, 0, 0, 3, 0, 4, 3, 2, 1],
	[3, -1, 3, 2, -1, 2, 1, -1, 1, 0, -1, 0, 2, -1, 5, 4],
]

var _buf := PackedFloat32Array()


func tone(dur: float, f0: float, f1: float, wave: int, vol: float,
		noise_mix := 0.0, decay_pow := 2.0) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var attack := 0.004 * SR
	for i in n:
		var k := float(i) / n
		ph = fmod(ph + lerpf(f0, f1, k) / SR, 1.0)
		var v := _wave(wave, ph)
		if noise_mix > 0.0:
			v = lerpf(v, randf() * 2.0 - 1.0, noise_mix)
		out[i] = v * vol * minf(i / attack, 1.0) * pow(1.0 - k, decay_pow)
	return out


func _wave(wave: int, ph: float) -> float:
	match wave:
		W.SINE:
			return sin(ph * TAU)
		W.SQUARE:
			return 1.0 if ph < 0.5 else -1.0
		W.SAW:
			return ph * 2.0 - 1.0
		W.TRI:
			return 4.0 * absf(ph - 0.5) - 1.0
	return randf() * 2.0 - 1.0


func seq(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: PackedFloat32Array in parts:
		out.append_array(p)
	return out


func mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var longer: PackedFloat32Array = a if a.size() >= b.size() else b
	var shorter: PackedFloat32Array = b if a.size() >= b.size() else a
	var out := longer.duplicate()
	for i in shorter.size():
		out[i] += shorter[i]
	return out


func to_stream(buf: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = buf.size()
	return s


func _notes(freqs: Array, dur: float, wave: int, vol: float, last_dur := 0.0) -> PackedFloat32Array:
	var parts := []
	for i in freqs.size():
		var d := last_dur if i == freqs.size() - 1 and last_dur > 0.0 else dur
		parts.append(tone(d, freqs[i], freqs[i], wave, vol, 0.0, 1.0))
	return seq(parts)


func build_sounds() -> Dictionary:
	var s := {}
	s["eat"] = to_stream(seq([tone(0.06, 440, 700, W.SQUARE, 0.22), tone(0.1, 700, 1200, W.SQUARE, 0.22)]))
	s["hurt"] = to_stream(tone(0.35, 320, 70, W.SAW, 0.45, 0.35, 1.5))
	s["bite"] = to_stream(mix(tone(0.12, 0, 0, W.NOISE, 0.5, 0.0, 3.0), tone(0.25, 260, 90, W.SQUARE, 0.35)))
	s["shoot"] = to_stream(tone(0.18, 0, 0, W.NOISE, 0.2, 0.0, 2.5))
	s["tick"] = to_stream(tone(0.05, 900, 500, W.SQUARE, 0.1))
	s["charge"] = to_stream(tone(0.45, 90, 420, W.SAW, 0.3, 0.1, 0.8))
	s["slam"] = to_stream(mix(tone(0.6, 110, 30, W.SINE, 0.9, 0.0, 1.5), tone(0.4, 0, 0, W.NOISE, 0.4, 0.0, 3.0)))
	s["yolk"] = to_stream(_notes([660, 880, 1100, 1320], 0.07, W.TRI, 0.35, 0.2))
	s["punch"] = to_stream(mix(tone(0.08, 0, 0, W.NOISE, 0.5, 0.0, 3.0), tone(0.15, 200, 80, W.SINE, 0.6)))
	s["whoosh"] = to_stream(tone(0.25, 0, 0, W.NOISE, 0.22, 0.0, 1.0))
	s["throw"] = to_stream(tone(0.1, 900, 400, W.SQUARE, 0.14))
	s["warn"] = to_stream(seq([tone(0.06, 1000, 1000, W.SQUARE, 0.14, 0.0, 0.5), tone(0.04, 0, 0, W.SINE, 0.0),
		tone(0.06, 1000, 1000, W.SQUARE, 0.14, 0.0, 0.5)]))
	s["phase"] = to_stream(mix(tone(0.9, 140, 50, W.SAW, 0.4, 0.15, 1.2), tone(0.9, 147, 52, W.SAW, 0.3, 0.0, 1.2)))
	s["pepper"] = to_stream(tone(0.12, 1400, 600, W.SINE, 0.3))
	s["splat"] = to_stream(tone(0.1, 0, 0, W.NOISE, 0.3, 0.0, 3.0))
	s["win"] = to_stream(_notes([523, 659, 784, 1047, 784, 1047], 0.12, W.TRI, 0.4, 0.6))
	s["lose"] = to_stream(_notes([440, 370, 311, 262], 0.18, W.SQUARE, 0.2, 0.6))
	s["ui_move"] = to_stream(tone(0.04, 1200, 1200, W.SQUARE, 0.08, 0.0, 1.0))
	s["ui_select"] = to_stream(seq([tone(0.05, 700, 700, W.SQUARE, 0.14, 0.0, 0.5), tone(0.09, 1050, 1400, W.SQUARE, 0.14)]))
	s["boss_down"] = to_stream(mix(tone(1.3, 0, 0, W.NOISE, 0.6, 0.0, 1.5), tone(1.3, 200, 20, W.SINE, 0.7, 0.0, 1.2)))
	s["bonk"] = to_stream(mix(tone(0.07, 0, 0, W.NOISE, 0.35, 0.0, 3.0), tone(0.22, 620, 180, W.TRI, 0.45)))
	s["match"] = to_stream(seq([tone(0.12, 0, 0, W.NOISE, 0.25, 0.0, 0.5),
		mix(tone(0.5, 0, 0, W.NOISE, 0.3, 0.0, 1.5), tone(0.5, 180, 90, W.SINE, 0.2))]))
	s["ignite"] = to_stream(mix(tone(1.6, 0, 0, W.NOISE, 0.6, 0.0, 1.2), tone(1.6, 70, 35, W.SINE, 0.8, 0.0, 1.3)))
	s["crackle"] = to_stream(seq([tone(0.03, 0, 0, W.NOISE, 0.5, 0.0, 4.0), tone(0.05, 0, 0, W.SINE, 0.0),
		tone(0.02, 0, 0, W.NOISE, 0.4, 0.0, 4.0), tone(0.08, 0, 0, W.SINE, 0.0), tone(0.04, 0, 0, W.NOISE, 0.45, 0.0, 4.0)]))
	s["burn"] = to_stream(mix(tone(1.2, 0, 0, W.NOISE, 0.35, 0.0, 1.0), tone(1.2, 300, 60, W.SAW, 0.2, 0.3, 1.4)))
	s["hiya"] = to_stream(seq([tone(0.05, 500, 900, W.SQUARE, 0.2), tone(0.16, 900, 700, W.SAW, 0.22, 0.15, 1.2)]))
	s["kick"] = to_stream(mix(tone(0.1, 0, 0, W.NOISE, 0.6, 0.0, 3.0), tone(0.25, 260, 60, W.SINE, 0.8, 0.0, 1.8)))
	s["needle"] = to_stream(tone(0.16, 2400, 1500, W.SINE, 0.18))
	s["snake_shot"] = to_stream(seq([tone(0.03, 0, 0, W.NOISE, 0.3, 0.0, 3.0), tone(0.08, 700, 1100, W.TRI, 0.3)]))
	s["spin"] = to_stream(mix(tone(0.35, 0, 0, W.NOISE, 0.35, 0.0, 1.0), tone(0.35, 200, 600, W.TRI, 0.25)))
	s["step"] = to_stream(mix(tone(0.12, 90, 50, W.SINE, 0.5, 0.0, 2.0), tone(0.05, 0, 0, W.NOISE, 0.12, 0.0, 3.0)))
	s["power"] = to_stream(_notes([523, 659, 784, 1047], 0.06, W.SQUARE, 0.18, 0.18))
	s["no_stamina"] = to_stream(tone(0.25, 220, 140, W.TRI, 0.25, 0.3, 1.2))
	s["thunder"] = to_stream(mix(tone(2.0, 0, 0, W.NOISE, 0.4, 0.0, 1.6), tone(2.0, 55, 30, W.SINE, 0.6, 0.0, 1.4)))
	return s


func build_music() -> Dictionary:
	var m := {}
	m["level"] = _track(0.13, [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]], [48, 45, 41, 43],
		LEVEL_PATTERNS, W.SQUARE, 0.08, [0, 8], [4, 12])
	m["boss"] = _track(0.1, [[57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 56, 59]], [45, 41, 43, 40],
		BOSS_PATTERNS, W.SAW, 0.08, [0, 4, 8, 12], [4, 12])
	return m


func build_sad_music() -> Dictionary:
	return {"sad": _sad_track()}


## Медленная грустная мелодия: арпеджио Am–F–C–E, «пианино» из синуса с обертоном.
func _sad_track() -> AudioStreamWAV:
	var step := 0.3
	var chords := [[57, 60, 64], [53, 57, 60], [48, 52, 55], [52, 56, 59],
		[57, 60, 64], [50, 53, 57], [52, 56, 59], [57, 60, 64]]
	var melody := [[76, 72, 71, 72], [69, 72, 77, 76], [76, 74, 72, 67], [68, 71, 76, 74],
		[72, 71, 69, 72], [74, 72, 69, 65], [64, 68, 71, 68], [69, -1, -1, -1]]
	var arp := [0, 1, 2, 1, 3, 2, 1, 2]
	_buf = PackedFloat32Array()
	_buf.resize(int(step * 8 * chords.size() * SR))
	for b in chords.size():
		var chord: Array = chords[b]
		var bar_start := b * 8
		_add(int(bar_start * step * SR), _piano(_hz(chord[0] - 12), step * 8.0, 0.22))
		for s in 8:
			var idx: int = arp[s]
			var note: int = chord[idx % 3] + 12 * (idx / 3)
			_add(int((bar_start + s) * step * SR), _piano(_hz(note), step * 3.0, 0.1))
		var mel: Array = melody[b]
		for k in 4:
			if mel[k] >= 0:
				var dur := step * (8.0 if b == chords.size() - 1 else 2.2)
				_add(int((bar_start + k * 2) * step * SR), _piano(_hz(mel[k]), dur, 0.17))
	return to_stream(_buf, true)


func _piano(f: float, dur: float, vol: float) -> PackedFloat32Array:
	return mix(tone(dur, f, f, W.SINE, vol, 0.0, 2.5), tone(dur * 0.6, f * 2.0, f * 2.0, W.TRI, vol * 0.25, 0.0, 3.0))


func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


func _track(step: float, chords: Array, bass: Array, patterns: Array, lead_wave: int, lead_vol: float,
		kicks: Array, snares: Array) -> AudioStreamWAV:
	var bars := chords.size()
	_buf = PackedFloat32Array()
	_buf.resize(int(step * 16 * bars * SR))
	for b in bars:
		var chord: Array = chords[b]
		var pat: Array = patterns[b % patterns.size()]
		for s in 16:
			var start := int((b * 16 + s) * step * SR)
			var idx: int = pat[s]
			if idx >= 0:
				var note: int = chord[idx % 3] + 12 * (idx / 3)
				_add(start, tone(step * 0.95, _hz(note), _hz(note), lead_wave, lead_vol, 0.0, 0.7))
			if s % 2 == 0:
				var bn: int = bass[b] + (12 if s % 4 == 2 else 0)
				_add(start, tone(step * 1.9, _hz(bn), _hz(bn), W.TRI, 0.3, 0.0, 0.8))
			if s in kicks:
				_add(start, tone(0.14, 150, 45, W.SINE, 0.55, 0.0, 1.5))
			if s in snares:
				_add(start, tone(0.1, 0, 0, W.NOISE, 0.18, 0.0, 2.5))
			elif s % 2 == 1:
				_add(start, tone(0.03, 0, 0, W.NOISE, 0.06, 0.0, 3.0))
	return to_stream(_buf, true)


func _add(start: int, snd: PackedFloat32Array) -> void:
	var n := mini(snd.size(), _buf.size() - start)
	for i in n:
		_buf[start + i] += snd[i]
