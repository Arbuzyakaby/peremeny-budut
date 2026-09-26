extends "res://scripts/audio/synth.gd"
## Музыка: треки уровней и боя (аккорды, бас, мелодия по паттернам, ударные), грустная тема финала
## и петля пожара. Каждый трек строится отдельно — sfx.gd строит их по очереди в фоновом потоке.

const TRACKS := ["level", "boss", "forks", "pills", "sad", "fire"]

const LEVEL_PATTERNS := [
	[0, -1, 1, 2, -1, 1, 0, -1, 2, -1, 3, -1, 2, 1, -1, -1],
	[3, -1, 2, -1, 1, -1, 2, 3, -1, 4, -1, 3, 2, -1, 1, -1],
]
const BOSS_PATTERNS := [
	[0, 0, 3, 0, 2, 0, 1, 0, 0, 0, 3, 0, 4, 3, 2, 1],
	[3, -1, 3, 2, -1, 2, 1, -1, 1, 0, -1, 0, 2, -1, 5, 4],
]
const FORK_PATTERNS := [
	[0, 0, -1, 1, 0, -1, 2, -1, 0, 0, -1, 1, 3, -1, 2, 1],
	[2, -1, 1, -1, 0, 0, -1, 2, 3, -1, 2, -1, 1, 0, -1, -1],
]
const PILL_PATTERNS := [
	[0, -1, 2, -1, 1, -1, 3, -1, 2, -1, 4, -1, 3, -1, 2, -1],
	[4, -1, 3, 2, -1, 1, -1, 2, 0, -1, 1, -1, 2, 3, -1, -1],
]

var _buf := PackedFloat32Array()


## Один трек по имени (музыка строится по очереди в фоновом потоке).
func build_track(track: String) -> Dictionary:
	match track:
		"level":
			return {track: _track(0.13, [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]], [48, 45, 41, 43],
				LEVEL_PATTERNS, W.SQUARE, 0.07, [0, 8], [4, 12])}
		"boss":
			return {track: _track(0.1, [[57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 56, 59]], [45, 41, 43, 40],
				BOSS_PATTERNS, W.SAW, 0.07, [0, 4, 8, 12], [4, 12])}
		"forks":  # ржавый марш: минор, пила, частая бочка
			return {track: _track(0.11, [[52, 55, 59], [50, 53, 57], [48, 52, 55], [47, 50, 54]], [40, 38, 36, 35],
				FORK_PATTERNS, W.SAW, 0.06, [0, 6, 8, 14], [4, 12])}
		"pills":  # прыгучая аптечная мелодия
			return {track: _track(0.12, [[60, 64, 67], [65, 69, 72], [62, 65, 69], [67, 71, 74]], [48, 53, 50, 55],
				PILL_PATTERNS, W.TRI, 0.13, [0, 3, 8, 11], [4, 12])}
		"sad":
			return {track: _sad_track()}
		"fire":
			return {track: build_fire_loop()}
	return {}


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
	# ударные строим один раз и переиспользуем
	var kick := tone(0.14, 150, 45, W.SINE, 0.55, 0.0, 1.5)
	var snare := mix(noise(0.12, 0.2, 2.5, 6000, 900), tone(0.08, 220, 160, W.TRI, 0.08, 0.0, 2.0))
	var hat := noise(0.035, 0.06, 3.0, 0.0, 6000)
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
				_add(start, kick)
			if s in snares:
				_add(start, snare)
			elif s % 2 == 1:
				_add(start, hat)
	return to_stream(_buf, true)


func _add(start: int, snd: PackedFloat32Array) -> void:
	var n := mini(snd.size(), _buf.size() - start)
	for i in n:
		_buf[start + i] += snd[i]
