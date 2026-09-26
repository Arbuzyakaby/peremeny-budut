extends RefCounted
## Синтезатор: генерирует звуковые эффекты и музыку (PCM) прямо в коде — без аудиофайлов.
## Квадрат и пила сглажены PolyBLEP (без металлического алиасинга), шум проходит через фильтры,
## а готовый звук ограничивается по пику и плавно затухает в конце — без перегруза и щелчков.

enum W { SINE, SQUARE, SAW, TRI, NOISE }

const SR := 22050
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


# ---------------------------------------------------------------- генераторы

func tone(dur: float, f0: float, f1: float, wave: int, vol: float,
		noise_mix := 0.0, decay_pow := 2.0) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var attack := 0.004 * SR
	for i in n:
		var k := float(i) / n
		var dt := lerpf(f0, f1, k) / SR
		ph = fmod(ph + dt, 1.0)
		var v := _wave(wave, ph, dt)
		if noise_mix > 0.0:
			v = lerpf(v, randf() * 2.0 - 1.0, noise_mix)
		out[i] = v * vol * minf(i / attack, 1.0) * pow(1.0 - k, decay_pow)
	return out


## Шум через фильтры. Перед огибающей нормализуется, поэтому громкость не зависит от фильтра.
func noise(dur: float, vol: float, decay_pow := 2.0, lp := 0.0, hp := 0.0, swell := 0.0) -> PackedFloat32Array:
	var n := int(dur * SR)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = randf() * 2.0 - 1.0
	if lp > 0.0:
		raw = lowpass(lowpass(raw, lp), lp)
	if hp > 0.0:
		raw = highpass(raw, hp)
	_normalize(raw, 1.0)
	var attack := maxf(0.004, swell) * SR
	for i in n:
		var k := float(i) / n
		var env := minf(i / attack, 1.0)
		if swell > 0.0:
			env = sin(minf(i / attack, 1.0) * PI * 0.5)
		raw[i] *= vol * env * pow(1.0 - k, decay_pow)
	return raw


func _wave(wave: int, ph: float, dt: float) -> float:
	match wave:
		W.SINE:
			return sin(ph * TAU)
		W.SQUARE:
			var v := 1.0 if ph < 0.5 else -1.0
			return v + _blep(ph, dt) - _blep(fmod(ph + 0.5, 1.0), dt)
		W.SAW:
			return ph * 2.0 - 1.0 - _blep(ph, dt)
		W.TRI:
			return 4.0 * absf(ph - 0.5) - 1.0
	return randf() * 2.0 - 1.0


## PolyBLEP — сглаживание скачка формы волны.
func _blep(t: float, dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0


# ---------------------------------------------------------------- обработка

func lowpass(buf: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / SR)
	var y := 0.0
	var out := buf.duplicate()
	for i in out.size():
		y += a * (out[i] - y)
		out[i] = y
	return out


func highpass(buf: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var low := lowpass(buf, cutoff)
	var out := buf.duplicate()
	for i in out.size():
		out[i] -= low[i]
	return out


func bandpass(buf: PackedFloat32Array, lo: float, hi: float) -> PackedFloat32Array:
	return highpass(lowpass(buf, hi), lo)


func _normalize(buf: PackedFloat32Array, peak: float) -> void:
	var m := 0.0
	for v in buf:
		m = maxf(m, absf(v))
	if m < 0.00001:
		return
	var g := peak / m
	for i in buf.size():
		buf[i] *= g


## Амплитудная модуляция: «дребезг», шуршание, скрежет.
func am(buf: PackedFloat32Array, rate: float, depth: float, jitter := false) -> PackedFloat32Array:
	var out := buf.duplicate()
	var lvl := 1.0
	var hold := 0
	for i in out.size():
		if jitter:
			hold -= 1
			if hold <= 0:
				hold = int(SR / rate * randf_range(0.5, 1.5))
				lvl = randf_range(1.0 - depth, 1.0)
			out[i] *= lvl
		else:
			out[i] *= 1.0 - depth * (0.5 + 0.5 * sin(TAU * rate * i / SR))
	return out


func seq(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: PackedFloat32Array in parts:
		out.append_array(p)
	return out


func mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	return mix_at(a, b, 0.0)


## Наложить b на a со смещением (сек).
func mix_at(a: PackedFloat32Array, b: PackedFloat32Array, offset: float) -> PackedFloat32Array:
	var off := int(offset * SR)
	var out := a.duplicate()
	if out.size() < off + b.size():
		out.resize(off + b.size())
	for i in b.size():
		out[off + i] += b[i]
	return out


func silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * SR))
	return out


func to_stream(buf: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	buf = buf.duplicate()
	var m := 0.0
	for v in buf:
		m = maxf(m, absf(v))
	if m > 0.9:  # ограничитель: никакого жёсткого клиппинга
		var g := 0.9 / m
		for i in buf.size():
			buf[i] *= g
	if not loop:  # фейд в конце — без щелчка
		var f := mini(int(0.006 * SR), buf.size())
		for i in f:
			buf[buf.size() - 1 - i] *= float(i) / f
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


## Бесшовная петля: хвост плавно переходит в начало.
func make_loop(buf: PackedFloat32Array, xfade: float) -> PackedFloat32Array:
	var x := int(xfade * SR)
	var n := buf.size() - x
	var out := buf.slice(0, n)
	for i in x:
		var k := float(i) / x
		out[i] = buf[i] * k + buf[n + i] * (1.0 - k)
	return out


func _notes(freqs: Array, dur: float, wave: int, vol: float, last_dur := 0.0) -> PackedFloat32Array:
	var parts := []
	for i in freqs.size():
		var d := last_dur if i == freqs.size() - 1 and last_dur > 0.0 else dur
		parts.append(tone(d, freqs[i], freqs[i], wave, vol, 0.0, 1.0))
	return seq(parts)


func _whoosh(dur: float, vol: float, lo: float, hi: float) -> PackedFloat32Array:
	var b := bandpass(noise(dur, 1.0, 0.0), lo, hi)
	_normalize(b, 1.0)
	for i in b.size():
		b[i] *= vol * pow(sin(PI * float(i) / b.size()), 1.5)
	return b


func _pop(dur: float, vol: float, lo: float, hi: float) -> PackedFloat32Array:
	var b := bandpass(noise(dur, 1.0, 5.0), lo, hi)
	_normalize(b, vol)
	return b


func _metal(freqs: Array, dur: float, vol: float) -> PackedFloat32Array:
	var out := silence(dur)
	for i in freqs.size():
		out = mix(out, tone(dur * (1.0 - i * 0.15), freqs[i], freqs[i] * 0.995, W.SINE, vol / (1.0 + i * 0.5), 0.0, 3.0))
	return out


# ---------------------------------------------------------------- звуки

func build_sounds() -> Dictionary:
	var s := {}
	s["eat"] = to_stream(seq([tone(0.06, 440, 700, W.SQUARE, 0.2), tone(0.1, 700, 1200, W.SQUARE, 0.2)]))
	s["hurt"] = to_stream(mix(tone(0.35, 320, 70, W.SAW, 0.35, 0.0, 1.5), noise(0.25, 0.3, 2.0, 1800)))
	s["bite"] = to_stream(mix(noise(0.1, 0.5, 3.0, 3000), tone(0.25, 260, 90, W.SQUARE, 0.28)))
	s["shoot"] = to_stream(mix(noise(0.2, 0.4, 2.5, 2200, 250), tone(0.18, 320, 110, W.SINE, 0.3)))
	s["tick"] = to_stream(mix(tone(0.05, 2100, 1900, W.SINE, 0.3, 0.0, 6.0), noise(0.02, 0.25, 4.0, 0.0, 4000)))
	s["charge"] = to_stream(mix(tone(0.45, 90, 420, W.SAW, 0.25, 0.0, 0.8), _whoosh(0.45, 0.2, 300, 1500)))
	s["slam"] = to_stream(mix(tone(0.6, 110, 30, W.SINE, 0.9, 0.0, 1.5), noise(0.45, 0.5, 3.0, 900)))
	s["yolk"] = to_stream(_notes([660, 880, 1100, 1320], 0.07, W.TRI, 0.35, 0.2))
	s["punch"] = to_stream(mix(noise(0.08, 0.5, 3.0, 2500), tone(0.15, 200, 80, W.SINE, 0.6)))
	s["whoosh"] = to_stream(_whoosh(0.28, 0.45, 350, 2200))
	s["throw"] = to_stream(mix(tone(0.1, 900, 400, W.SQUARE, 0.12), _whoosh(0.12, 0.2, 800, 3000)))
	s["warn"] = to_stream(seq([tone(0.06, 1000, 1000, W.SQUARE, 0.13, 0.0, 0.5), silence(0.04),
		tone(0.06, 1000, 1000, W.SQUARE, 0.13, 0.0, 0.5)]))
	s["phase"] = to_stream(mix(tone(0.9, 140, 50, W.SAW, 0.35, 0.0, 1.2), tone(0.9, 147, 52, W.SAW, 0.28, 0.0, 1.2)))
	s["pepper"] = to_stream(tone(0.12, 1400, 600, W.SINE, 0.3))
	s["splat"] = to_stream(mix(noise(0.12, 0.45, 3.0, 1500), tone(0.1, 180, 90, W.SINE, 0.3)))
	s["win"] = to_stream(_notes([523, 659, 784, 1047, 784, 1047], 0.12, W.TRI, 0.4, 0.6))
	s["lose"] = to_stream(_notes([440, 370, 311, 262], 0.18, W.SQUARE, 0.18, 0.6))
	s["ui_move"] = to_stream(tone(0.04, 1200, 1200, W.SQUARE, 0.07, 0.0, 1.0))
	s["ui_select"] = to_stream(seq([tone(0.05, 700, 700, W.SQUARE, 0.13, 0.0, 0.5), tone(0.09, 1050, 1400, W.SQUARE, 0.13)]))
	s["boss_down"] = to_stream(mix(noise(1.3, 0.6, 1.5, 1400), tone(1.3, 200, 20, W.SINE, 0.7, 0.0, 1.2)))
	s["bonk"] = to_stream(mix(noise(0.07, 0.35, 3.0, 2500), tone(0.22, 620, 180, W.TRI, 0.45)))
	# спичка: чирк по коробку + вспышка серы
	var scratch := am(noise(0.14, 0.55, 0.5, 6000, 1800), 90.0, 0.7, true)
	s["match"] = to_stream(seq([scratch, mix(noise(0.55, 0.4, 1.6, 3000, 400), tone(0.5, 180, 90, W.SINE, 0.12))]))
	# воспламенение: глухое «вух» с нарастанием и треском сверху
	var whoomp := noise(1.8, 0.8, 1.3, 500, 0.0, 0.18)
	whoomp = mix(whoomp, tone(1.6, 70, 35, W.SINE, 0.55, 0.0, 1.3))
	for i in 10:
		whoomp = mix_at(whoomp, _pop(randf_range(0.01, 0.03), randf_range(0.15, 0.35), 1200, 5000), randf_range(0.15, 1.3))
	s["ignite"] = to_stream(whoomp)
	s["crackle"] = to_stream(seq([_pop(0.02, 0.4, 1500, 5000), silence(0.05), _pop(0.015, 0.3, 2000, 6000)]))
	# горение: шипение и потрескивание
	var sizzle := noise(1.3, 0.3, 1.0, 7000, 2500, 0.1)
	sizzle = mix(sizzle, noise(1.3, 0.35, 1.4, 600))
	for i in 12:
		sizzle = mix_at(sizzle, _pop(randf_range(0.01, 0.025), randf_range(0.2, 0.45), 1500, 6000), randf_range(0.0, 1.1))
	s["burn"] = to_stream(sizzle)
	s["hiya"] = to_stream(seq([tone(0.05, 500, 900, W.SQUARE, 0.18), tone(0.16, 900, 700, W.SAW, 0.2, 0.1, 1.2)]))
	s["kick"] = to_stream(mix(noise(0.1, 0.55, 3.0, 2800), tone(0.25, 260, 60, W.SINE, 0.8, 0.0, 1.8)))
	s["needle"] = to_stream(mix(tone(0.16, 2400, 1500, W.SINE, 0.18), _whoosh(0.1, 0.12, 3000, 8000)))
	s["snake_shot"] = to_stream(seq([noise(0.03, 0.3, 3.0, 4000), tone(0.08, 700, 1100, W.TRI, 0.3)]))
	s["spin"] = to_stream(mix(_whoosh(0.35, 0.4, 400, 2500), tone(0.35, 200, 600, W.TRI, 0.22)))
	# шаг учёного: глухой удар каблука
	s["step"] = to_stream(mix(tone(0.14, 85, 45, W.SINE, 0.55, 0.0, 2.2), noise(0.06, 0.18, 3.0, 450)))
	s["power"] = to_stream(_notes([523, 659, 784, 1047], 0.06, W.SQUARE, 0.16, 0.18))
	s["no_stamina"] = to_stream(tone(0.25, 220, 140, W.TRI, 0.25, 0.2, 1.2))
	# гром: резкий треск и долгий раскат с «биением»
	var crack := noise(0.3, 0.8, 4.0, 0.0, 1400)
	var rumble := am(noise(3.2, 0.9, 1.3, 170, 0.0, 0.25), 7.0, 0.6, true)
	rumble = lowpass(rumble, 220)
	_normalize(rumble, 0.9)
	s["thunder"] = to_stream(mix(mix(crack, rumble), tone(2.5, 48, 30, W.SINE, 0.5, 0.0, 1.4)))

	# ----- новые звуки v5.0
	s["clang"] = to_stream(mix(_metal([523, 1187, 1873, 2711], 0.7, 0.4), noise(0.05, 0.4, 3.0, 0.0, 2500)))
	s["fork_aim"] = to_stream(am(bandpass(noise(0.55, 0.5, 0.3), 1500, 4200), 28.0, 0.7))
	s["fork_dash"] = to_stream(mix(_whoosh(0.4, 0.45, 600, 3500), _metal([880, 1320], 0.4, 0.12)))
	var boing := PackedFloat32Array()
	boing.resize(int(0.2 * SR))
	var ph := 0.0
	for i in boing.size():
		var k := float(i) / boing.size()
		ph += (300.0 + 450.0 * k + 40.0 * sin(k * 60.0)) / SR
		boing[i] = sin(ph * TAU) * 0.4 * pow(1.0 - k, 1.5) * minf(i / 90.0, 1.0)
	s["pill_hop"] = to_stream(boing)
	s["pill_land"] = to_stream(mix(mix(tone(0.3, 120, 45, W.SINE, 0.8, 0.0, 2.0), noise(0.2, 0.4, 3.0, 800)),
		am(noise(0.25, 0.2, 2.0, 5000, 1500), 40.0, 0.8)))
	var dizzy := PackedFloat32Array()
	dizzy.resize(int(0.7 * SR))
	ph = 0.0
	for i in dizzy.size():
		var k := float(i) / dizzy.size()
		ph += (900.0 - 350.0 * k + 90.0 * sin(k * 40.0)) / SR
		dizzy[i] = (4.0 * absf(fmod(ph, 1.0) - 0.5) - 1.0) * 0.3 * pow(1.0 - k, 1.2)
	s["stun"] = to_stream(mix(dizzy, _metal([1568, 2349], 0.5, 0.15)))
	s["poof"] = to_stream(noise(0.4, 0.5, 1.5, 1300, 150, 0.05))
	s["shuriken"] = to_stream(mix(_whoosh(0.16, 0.35, 3000, 8000), tone(0.12, 3000, 2000, W.SINE, 0.1)))
	s["fuse"] = to_stream(am(noise(0.35, 0.3, 0.5, 8000, 3000), 60.0, 0.8, true))
	var boom := mix(noise(0.7, 0.8, 2.0, 1500), tone(0.5, 90, 30, W.SINE, 0.8, 0.0, 1.6))
	boom = mix(boom, noise(0.08, 0.6, 4.0, 0.0, 2000))
	for i in 6:
		boom = mix_at(boom, _pop(0.02, 0.3, 2000, 7000), randf_range(0.05, 0.4))
	s["boom"] = to_stream(boom)
	s["heal"] = to_stream(_notes([784, 988, 1175, 1568], 0.06, W.TRI, 0.3, 0.3))
	s["pop"] = to_stream(mix(tone(0.07, 500, 1500, W.SINE, 0.45, 0.0, 2.0), _pop(0.02, 0.2, 1500, 6000)))
	s["shield"] = to_stream(mix(tone(0.35, 400, 900, W.TRI, 0.28, 0.0, 1.0), tone(0.35, 604, 1350, W.SINE, 0.12, 0.0, 1.0)))
	s["perk"] = to_stream(_notes([523, 659, 784, 1047, 1319], 0.07, W.SQUARE, 0.14, 0.35))
	s["stage_clear"] = to_stream(_notes([523, 659, 784, 659, 784, 1047], 0.1, W.TRI, 0.38, 0.5))
	s["scale"] = to_stream(seq([tone(0.05, 1400, 1400, W.SINE, 0.3, 0.0, 0.5), tone(0.14, 2100, 2100, W.SINE, 0.3, 0.0, 1.5)]))
	s["scribble"] = to_stream(am(bandpass(noise(0.9, 0.45, 0.4), 1800, 5500), 14.0, 0.95, true))
	s["stamp"] = to_stream(mix(noise(0.08, 0.6, 3.0, 1200), tone(0.22, 150, 55, W.SINE, 0.75, 0.0, 2.0)))
	s["extinguisher"] = to_stream(noise(2.0, 0.55, 0.7, 7000, 700, 0.06))
	s["lamp_click"] = to_stream(mix(noise(0.03, 0.4, 4.0, 0.0, 2500), tone(0.03, 1600, 1500, W.SINE, 0.2, 0.0, 4.0)))
	var hatch := silence(0.9)
	for i in 3:
		hatch = mix_at(hatch, _pop(0.03, 0.35, 1000, 4500), 0.05 + i * 0.22)
	hatch = mix_at(hatch, tone(0.12, 1300, 1900, W.SINE, 0.25, 0.0, 1.5), 0.75)
	s["hatch"] = to_stream(hatch)
	return s


## Фон пожара: низкий гул, шипение и редкие потрескивания. Бесшовная 4-секундная петля.
func build_fire_loop() -> AudioStreamWAV:
	var total := 4.4
	var roar := noise(total, 0.55, 0.0, 380)
	roar = am(roar, 0.5, 0.3)
	var hiss := noise(total, 0.08, 0.0, 9000, 3500)
	var buf := mix(roar, hiss)
	for i in 70:
		var at := randf_range(0.0, total - 0.05)
		if randf() < 0.75:
			buf = mix_at(buf, _pop(randf_range(0.004, 0.018), randf_range(0.12, 0.5), randf_range(1200, 2500), randf_range(3500, 8000)), at)
		else:  # хлопок покрупнее — лопается смола
			buf = mix_at(buf, _pop(randf_range(0.02, 0.05), randf_range(0.3, 0.55), 250, 1400), at)
	return to_stream(make_loop(buf.slice(0, int(total * SR)), 0.4), true)


# ---------------------------------------------------------------- музыка

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
