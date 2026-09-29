extends RefCounted
## Синтезатор: генерирует звуковые эффекты и музыку (PCM) прямо в коде — без аудиофайлов.
## Квадрат и пила сглажены PolyBLEP (без металлического алиасинга), шум проходит через фильтры,
## а готовый звук ограничивается по пику и плавно затухает в конце — без перегруза и щелчков.
## Здесь — только генераторы и обработка; рецепты звуков — в sound_bank.gd, музыка — в synth_music.gd.

enum W { SINE, SQUARE, SAW, TRI, NOISE }

const SR := 22050
## Частота дискретизации этого синтезатора: по умолчанию SR, звуки лаборатории (foley.gd) — 44 100 Гц.
var sr := SR

const LOOP_GUARD := 8

## Сколько звуков уже построено (читает экран загрузки из главного потока).
var built_count := 0


# ---------------------------------------------------------------- генераторы

func tone(dur: float, f0: float, f1: float, wave: int, vol: float,
		noise_mix := 0.0, decay_pow := 2.0) -> PackedFloat32Array:
	var n := int(dur * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var attack := 0.004 * sr
	for i in n:
		var k := float(i) / n
		var dt := lerpf(f0, f1, k) / sr
		ph = fmod(ph + dt, 1.0)
		var v := _wave(wave, ph, dt)
		if noise_mix > 0.0:
			v = lerpf(v, randf() * 2.0 - 1.0, noise_mix)
		out[i] = v * vol * minf(i / attack, 1.0) * pow(1.0 - k, decay_pow)
	return out


## Шум через фильтры. Перед огибающей нормализуется, поэтому громкость не зависит от фильтра.
func noise(dur: float, vol: float, decay_pow := 2.0, lp := 0.0, hp := 0.0, swell := 0.0) -> PackedFloat32Array:
	var n := int(dur * sr)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = randf() * 2.0 - 1.0
	if lp > 0.0:
		raw = lowpass(lowpass(raw, lp), lp)
	if hp > 0.0:
		raw = highpass(raw, hp)
	_normalize(raw, 1.0)
	var attack := maxf(0.004, swell) * sr
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
	var a := 1.0 - exp(-TAU * cutoff / sr)
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
				hold = int(sr / rate * randf_range(0.5, 1.5))
				lvl = randf_range(1.0 - depth, 1.0)
			out[i] *= lvl
		else:
			out[i] *= 1.0 - depth * (0.5 + 0.5 * sin(TAU * rate * i / sr))
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
	var off := int(offset * sr)
	var out := a.duplicate()
	if out.size() < off + b.size():
		out.resize(off + b.size())
	for i in b.size():
		out[off + i] += b[i]
	return out


func silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * sr))
	return out


## gain_db — поправка громкости после ограничителя: так тихим делается и звук, упёршийся в потолок.
func to_stream(buf: PackedFloat32Array, loop := false, gain_db := 0.0) -> AudioStreamWAV:
	built_count += 1
	buf = buf.duplicate()
	var m := 0.0
	for v in buf:
		m = maxf(m, absf(v))
	var g := 0.9 / m if m > 0.9 else 1.0  # ограничитель: никакого жёсткого клиппинга
	g *= db_to_linear(gain_db)
	if not is_equal_approx(g, 1.0):
		for i in buf.size():
			buf[i] *= g
	if not loop:  # фейд в конце — без щелчка
		var f := mini(int(0.006 * sr), buf.size())
		for i in f:
			buf[buf.size() - 1 - i] *= float(i) / f
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sr
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		# конец петли — с запасом: интерполяция микшера читает соседние сэмплы, и на Android
		# петля до самого последнего сэмпла роняла аудиопоток (чтение за границей буфера)
		s.loop_end = maxi(buf.size() - LOOP_GUARD, 1)
	return s


## Бесшовная петля: хвост плавно переходит в начало.
func make_loop(buf: PackedFloat32Array, xfade: float) -> PackedFloat32Array:
	var x := int(xfade * sr)
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
	return to_stream(make_loop(buf.slice(0, int(total * sr)), 0.4), true)
