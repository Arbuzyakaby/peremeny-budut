extends "res://scripts/audio/synth.gd"
## Музыка 2.0 (v8.0). Каждый трек этапа — песня из 8 тактов формы A–A'–A–A''–B–B'–B–A' и два слоя
## одинаковой длины, которые играют синхронно:
## - основа (имя трека): бочка, малый, хэты с «живой» громкостью, бас с проходящими нотами, пэд
##   аккордов, мелодия и сбивки малого в конце фраз;
## - слой напряжения (имя + "_hi"): арпеджио шестнадцатыми, открытые хэты, октавный бас, стэбы —
##   sfx.gd подмешивает его по set_intensity() (мало жизней, клещи, фаза яичницы, открытый желток).
## Плюс тема меню, грустная тема финала и петля пожара. Каждый трек строится отдельно — sfx.gd
## строит их по очереди в фоновом потоке.

## Треки, которые строит фон. У треков из LAYERED есть ещё слой "<имя>_hi".
const TRACKS := ["level", "boss", "forks", "pills", "dolls", "menu", "sad", "fire"]
const LAYERED := ["level", "boss", "forks", "pills", "dolls", "menu"]
const HI_SUFFIX := "_hi"
## Какой паттерн мелодии звучит в каждом такте (индексы в patterns песни): форма A A' A A'' B B' B A'.
const FORM := [0, 1, 0, 2, 3, 4, 3, 1]
const FILL_BARS := [3, 7]  # в конце фраз — сбивка малого

## Песни: step — длительность шестнадцатой, chords/bass — по тактам, patterns — ступени аккорда
## (0..2 — аккорд, 3..5 — октавой выше, −1 — пауза), kicks/snares — шаги, swing — доля шага.
const SONGS := {
	"level": {  # бодрый до мажор: медведи
		"step": 0.13, "lead": W.SQUARE, "lead_vol": 0.065, "swing": 0.12, "pad": 0.035,
		"chords": [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62], [60, 64, 67], [57, 60, 64], [50, 53, 57], [55, 59, 62]],
		"bass": [48, 45, 41, 43, 48, 45, 38, 43],
		"patterns": [
			[0, -1, 1, 2, -1, 1, 0, -1, 2, -1, 3, -1, 2, 1, -1, -1],
			[3, -1, 2, -1, 1, -1, 2, 3, -1, 4, -1, 3, 2, -1, 1, -1],
			[0, -1, 1, 2, -1, 3, 4, -1, 5, -1, 4, 3, -1, 2, -1, -1],
			[4, -1, -1, 3, -1, 2, -1, -1, 3, -1, 1, -1, 2, -1, -1, -1],
			[2, -1, 3, -1, 4, -1, 3, 2, -1, 1, -1, 2, 3, -1, -1, -1],
		],
		"kicks": [0, 8], "snares": [4, 12], "arp": W.TRI,
	},
	"boss": {  # ля минор, пила: гигантская яичница
		"step": 0.1, "lead": W.SAW, "lead_vol": 0.06, "swing": 0.0, "pad": 0.04,
		"chords": [[57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 56, 59], [57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59]],
		"bass": [45, 41, 43, 40, 45, 41, 38, 40],
		"patterns": [
			[0, 0, 3, 0, 2, 0, 1, 0, 0, 0, 3, 0, 4, 3, 2, 1],
			[3, -1, 3, 2, -1, 2, 1, -1, 1, 0, -1, 0, 2, -1, 5, 4],
			[0, 0, 3, 0, 2, 0, 1, 0, 5, 4, 3, 2, 1, 2, 3, 4],
			[5, -1, -1, 4, -1, -1, 3, -1, 4, -1, -1, 3, -1, 2, -1, -1],
			[3, -1, 4, -1, 5, -1, 4, 3, 2, -1, 3, -1, 4, -1, -1, -1],
		],
		"kicks": [0, 4, 8, 12], "snares": [4, 12], "arp": W.SQUARE,
	},
	"forks": {  # ржавый марш: минор, пила, частая бочка
		"step": 0.11, "lead": W.SAW, "lead_vol": 0.055, "swing": 0.0, "pad": 0.03,
		"chords": [[52, 55, 59], [50, 53, 57], [48, 52, 55], [47, 50, 54], [52, 55, 59], [45, 48, 52], [48, 52, 55], [47, 51, 54]],
		"bass": [40, 38, 36, 35, 40, 33, 36, 35],
		"patterns": [
			[0, 0, -1, 1, 0, -1, 2, -1, 0, 0, -1, 1, 3, -1, 2, 1],
			[2, -1, 1, -1, 0, 0, -1, 2, 3, -1, 2, -1, 1, 0, -1, -1],
			[0, 0, -1, 1, 0, -1, 2, -1, 3, 3, -1, 4, 3, -1, 2, -1],
			[4, -1, 4, 3, -1, 3, 2, -1, 1, -1, 1, 0, -1, 0, -1, -1],
			[3, -1, 2, 3, -1, 4, -1, 3, 2, -1, 1, -1, 0, -1, -1, -1],
		],
		"kicks": [0, 6, 8, 14], "snares": [4, 12], "arp": W.SQUARE,
	},
	"pills": {  # прыгучая аптечная мелодия
		"step": 0.12, "lead": W.TRI, "lead_vol": 0.12, "swing": 0.18, "pad": 0.03,
		"chords": [[60, 64, 67], [65, 69, 72], [62, 65, 69], [67, 71, 74], [60, 64, 67], [57, 60, 64], [65, 69, 72], [67, 71, 74]],
		"bass": [48, 53, 50, 55, 48, 45, 53, 55],
		"patterns": [
			[0, -1, 2, -1, 1, -1, 3, -1, 2, -1, 4, -1, 3, -1, 2, -1],
			[4, -1, 3, 2, -1, 1, -1, 2, 0, -1, 1, -1, 2, 3, -1, -1],
			[0, -1, 2, -1, 1, -1, 3, -1, 5, -1, 4, -1, 3, -1, 2, -1],
			[3, -1, -1, 3, -1, -1, 4, -1, 2, -1, -1, 2, -1, 1, -1, -1],
			[5, -1, 4, -1, 3, -1, 4, -1, 2, -1, 3, -1, 1, -1, -1, -1],
		],
		"kicks": [0, 3, 8, 11], "snares": [4, 12], "arp": W.SINE,
	},
	"dolls": {  # терем матрёшек: ре минор, «балалайка» квадратом, притопы на сильные доли
		"step": 0.105, "lead": W.SQUARE, "lead_vol": 0.06, "swing": 0.0, "pad": 0.03,
		"chords": [[50, 53, 57], [55, 58, 62], [57, 61, 64], [50, 53, 57], [48, 52, 55], [53, 57, 60], [55, 58, 62], [57, 61, 64]],
		"bass": [38, 43, 45, 38, 36, 41, 43, 45],
		"patterns": [
			[0, 0, 1, 1, 2, -1, 1, -1, 0, 0, 1, 1, 2, -1, -1, -1],
			[2, 2, 3, 3, 2, -1, 1, -1, 2, 1, 0, -1, 1, -1, -1, -1],
			[3, 3, 4, 4, 5, -1, 4, -1, 3, 2, 1, 2, 3, -1, -1, -1],
			[5, -1, 4, -1, 3, -1, 2, -1, 3, -1, 2, -1, 1, 0, -1, -1],
			[0, 1, 2, 3, 4, -1, 3, 2, 1, -1, 2, -1, 0, -1, -1, -1],
		],
		"kicks": [0, 4, 8, 12], "snares": [6, 14], "arp": W.TRI,
	},
	"menu": {  # спокойная тема меню: фа мажор, мягкий треугольник, щётки
		"step": 0.16, "lead": W.TRI, "lead_vol": 0.09, "swing": 0.2, "pad": 0.045,
		"chords": [[53, 57, 60], [50, 53, 57], [46, 50, 53], [48, 52, 55], [53, 57, 60], [45, 48, 52], [46, 50, 53], [48, 52, 55]],
		"bass": [41, 38, 34, 36, 41, 33, 34, 36],
		"patterns": [
			[3, -1, -1, 2, -1, -1, 1, -1, 2, -1, -1, -1, 0, -1, -1, -1],
			[4, -1, -1, 3, -1, 2, -1, -1, 3, -1, -1, -1, -1, -1, -1, -1],
			[3, -1, -1, 4, -1, -1, 5, -1, 4, -1, 3, -1, 2, -1, -1, -1],
			[2, -1, 3, -1, 4, -1, -1, -1, 3, -1, 2, -1, 1, -1, -1, -1],
			[1, -1, -1, 2, -1, -1, 3, -1, -1, -1, 2, -1, -1, -1, -1, -1],
		],
		"kicks": [0, 10], "snares": [], "arp": W.SINE, "soft": true,
	},
}

var _buf := PackedFloat32Array()
var _hi := PackedFloat32Array()


## Один трек по имени (музыка строится по очереди в фоновом потоке). Возвращает все его слои.
func build_track(track: String) -> Dictionary:
	if SONGS.has(track):
		return _song(track, SONGS[track])
	match track:
		"sad":
			return {track: _sad_track()}
		"fire":
			return {track: build_fire_loop()}
	return {}


## Длина песни в секундах (слои одинаковой длины — поэтому играют синхронно).
static func song_length(track: String) -> float:
	var s: Dictionary = SONGS[track]
	return float(s["step"]) * 16.0 * (s["chords"] as Array).size()


func _song(track: String, s: Dictionary) -> Dictionary:
	var step: float = s["step"]
	var chords: Array = s["chords"]
	var bars := chords.size()
	var soft: bool = s.get("soft", false)
	var total := int(step * 16 * bars * SR)
	_buf = PackedFloat32Array()
	_buf.resize(total)
	_hi = PackedFloat32Array()
	_hi.resize(total)
	# ударные строим один раз и переиспользуем
	var kick := tone(0.14, 150, 45, W.SINE, 0.5 if soft else 0.55, 0.0, 1.5)
	var snare := mix(noise(0.12, 0.2, 2.5, 6000, 900), tone(0.08, 220, 160, W.TRI, 0.08, 0.0, 2.0))
	var brush := noise(0.1, 0.07, 1.5, 5000, 1500)
	var hat := noise(0.035, 0.06, 3.0, 0.0, 6000)
	var open_hat := noise(0.16, 0.05, 1.6, 0.0, 5000)
	var crash := noise(0.9, 0.09, 1.3, 0.0, 3500)
	var swing: float = s["swing"]
	for b in bars:
		var chord: Array = chords[b]
		var pat: Array = s["patterns"][FORM[b % FORM.size()] % (s["patterns"] as Array).size()]
		var bar0 := b * 16
		# пэд аккорда: мягкие треугольники на весь такт
		for n: int in chord:
			_add(_buf, int(bar0 * step * SR), tone(step * 16.0, _hz(n), _hz(n) * 1.003, W.TRI, float(s["pad"]), 0.0, 0.35))
		if b == 0 or b == 4:
			_add(_hi, int(bar0 * step * SR), crash)
		for st in 16:
			var at := (bar0 + st + (swing if st % 2 == 1 else 0.0)) * step
			var start := int(at * SR)
			# мелодия
			var idx: int = pat[st]
			if idx >= 0:
				var note: int = chord[idx % 3] + 12 * (idx / 3)
				var vel := randf_range(0.85, 1.0) * (1.1 if st % 4 == 0 else 1.0)
				_add(_buf, start, tone(step * 0.95, _hz(note), _hz(note), s["lead"], float(s["lead_vol"]) * vel, 0.0, 0.7))
			# бас: восьмые, с октавой и проходящей нотой в конце такта
			if st % 2 == 0:
				var bn: int = s["bass"][b] + (12 if st % 4 == 2 else 0)
				if st == 14:
					var next_bass: int = s["bass"][(b + 1) % bars]
					bn = s["bass"][b] + (2 if next_bass > s["bass"][b] else -1)
				_add(_buf, start, tone(step * 1.9, _hz(bn), _hz(bn), W.TRI, 0.28, 0.0, 0.8))
			# ударные
			var fill := b in FILL_BARS and st >= 12 and not soft
			if st in s["kicks"]:
				_add(_buf, start, kick)
			if fill:
				_add_scaled(_buf, start, snare, 0.5 + 0.17 * (st - 12))
			elif st in s["snares"]:
				_add(_buf, start, snare)
			elif soft and st % 4 == 2:
				_add(_buf, start, brush)
			elif st % 2 == 1:
				_add_scaled(_buf, start, hat, randf_range(0.6, 1.0))
			# слой напряжения: арпеджио шестнадцатыми, хэты на каждую долю, открытый хэт, октавный бас
			var arp_note: int = chord[[0, 1, 2, 1][st % 4]] + 12 * (1 + (st / 8) % 2)
			_add(_hi, start, tone(step * 0.8, _hz(arp_note), _hz(arp_note), s["arp"], 0.045, 0.0, 1.2))
			if st % 2 == 0:
				_add_scaled(_hi, start, hat, 0.7)
			if st % 4 == 2:
				_add(_hi, start, open_hat)
			if st % 4 == 0:
				var sub: int = s["bass"][b] - 12
				_add(_hi, start, tone(step * 3.0, _hz(sub), _hz(sub), W.SQUARE, 0.07, 0.0, 1.0))
			if not soft and st in [0, 6, 10]:  # стэбы аккорда
				for n: int in chord:
					_add(_hi, start, tone(step * 0.6, _hz(n + 12), _hz(n + 12), W.SAW, 0.025, 0.0, 1.5))
	return {track: to_stream(_buf, true), track + HI_SUFFIX: to_stream(_hi, true)}


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
		_add(_buf, int(bar_start * step * SR), _piano(_hz(chord[0] - 12), step * 8.0, 0.22))
		for s in 8:
			var idx: int = arp[s]
			var note: int = chord[idx % 3] + 12 * (idx / 3)
			_add(_buf, int((bar_start + s) * step * SR), _piano(_hz(note), step * 3.0, 0.1 * randf_range(0.85, 1.0)))
		var mel: Array = melody[b]
		for k in 4:
			if mel[k] >= 0:
				var dur := step * (8.0 if b == chords.size() - 1 else 2.2)
				_add(_buf, int((bar_start + k * 2) * step * SR), _piano(_hz(mel[k]), dur, 0.17))
	return to_stream(_buf, true)


func _piano(f: float, dur: float, vol: float) -> PackedFloat32Array:
	return mix(tone(dur, f, f, W.SINE, vol, 0.0, 2.5), tone(dur * 0.6, f * 2.0, f * 2.0, W.TRI, vol * 0.25, 0.0, 3.0))


func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


func _add(buf: PackedFloat32Array, start: int, snd: PackedFloat32Array) -> void:
	var n := mini(snd.size(), buf.size() - start)
	for i in n:
		buf[start + i] += snd[i]


func _add_scaled(buf: PackedFloat32Array, start: int, snd: PackedFloat32Array, k: float) -> void:
	var n := mini(snd.size(), buf.size() - start)
	for i in n:
		buf[start + i] += snd[i] * k
