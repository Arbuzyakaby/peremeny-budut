extends RefCounted
## Синтезатор: генерирует звуковые эффекты и музыку (PCM) прямо в коде — без аудиофайлов.
## Квадрат и пила сглажены PolyBLEP (без металлического алиасинга), шум проходит через фильтры,
## а готовый звук ограничивается по пику и плавно затухает в конце — без перегруза и щелчков.

enum W { SINE, SQUARE, SAW, TRI, NOISE }

const SR := 22050

## Сколько звуков в build_sounds() — для полосы загрузки (тест сверяет с фактом).
const SOUND_COUNT := 69
const LOOP_GUARD := 8

## Сколько звуков уже построено (читает экран загрузки из главного потока).
var built_count := 0
var _bank: Dictionary = {}


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
	built_count += 1
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
		# конец петли — с запасом: интерполяция микшера читает соседние сэмплы, и на Android
		# петля до самого последнего сэмпла роняла аудиопоток (чтение за границей буфера)
		s.loop_end = maxi(buf.size() - LOOP_GUARD, 1)
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
	_bank = {}
	built_count = 0
	_bank["eat"] = to_stream(seq([tone(0.06, 440, 700, W.SQUARE, 0.2), tone(0.1, 700, 1200, W.SQUARE, 0.2)]))
	_bank["hurt"] = to_stream(mix(tone(0.35, 320, 70, W.SAW, 0.35, 0.0, 1.5), noise(0.25, 0.3, 2.0, 1800)))
	_bank["bite"] = to_stream(mix(noise(0.1, 0.5, 3.0, 3000), tone(0.25, 260, 90, W.SQUARE, 0.28)))
	_bank["shoot"] = to_stream(mix(noise(0.2, 0.4, 2.5, 2200, 250), tone(0.18, 320, 110, W.SINE, 0.3)))
	_bank["tick"] = to_stream(mix(tone(0.05, 2100, 1900, W.SINE, 0.3, 0.0, 6.0), noise(0.02, 0.25, 4.0, 0.0, 4000)))
	_bank["charge"] = to_stream(mix(tone(0.45, 90, 420, W.SAW, 0.25, 0.0, 0.8), _whoosh(0.45, 0.2, 300, 1500)))
	_bank["slam"] = to_stream(mix(tone(0.6, 110, 30, W.SINE, 0.9, 0.0, 1.5), noise(0.45, 0.5, 3.0, 900)))
	_bank["yolk"] = to_stream(_notes([660, 880, 1100, 1320], 0.07, W.TRI, 0.35, 0.2))
	_bank["punch"] = to_stream(mix(noise(0.08, 0.5, 3.0, 2500), tone(0.15, 200, 80, W.SINE, 0.6)))
	_bank["whoosh"] = to_stream(_whoosh(0.28, 0.45, 350, 2200))
	_bank["throw"] = to_stream(mix(tone(0.1, 900, 400, W.SQUARE, 0.12), _whoosh(0.12, 0.2, 800, 3000)))
	_bank["warn"] = to_stream(seq([tone(0.06, 1000, 1000, W.SQUARE, 0.13, 0.0, 0.5), silence(0.04),
		tone(0.06, 1000, 1000, W.SQUARE, 0.13, 0.0, 0.5)]))
	_bank["phase"] = to_stream(mix(tone(0.9, 140, 50, W.SAW, 0.35, 0.0, 1.2), tone(0.9, 147, 52, W.SAW, 0.28, 0.0, 1.2)))
	_bank["pepper"] = to_stream(tone(0.12, 1400, 600, W.SINE, 0.3))
	_bank["splat"] = to_stream(mix(noise(0.12, 0.45, 3.0, 1500), tone(0.1, 180, 90, W.SINE, 0.3)))
	_bank["win"] = to_stream(_notes([523, 659, 784, 1047, 784, 1047], 0.12, W.TRI, 0.4, 0.6))
	_bank["lose"] = to_stream(_notes([440, 370, 311, 262], 0.18, W.SQUARE, 0.18, 0.6))
	# интерфейс 2.0 — механика: фокус — лёгкий тик, отпускание клавиши — сухой щелчок
	_bank["ui_move"] = to_stream(mix(_pop(0.012, 0.12, 3000, 7000), tone(0.02, 2600, 2400, W.SINE, 0.04, 0.0, 5.0)))
	_bank["ui_select"] = to_stream(mix(_pop(0.016, 0.34, 1800, 6500), tone(0.05, 1900, 1700, W.SINE, 0.1, 0.0, 5.0)))
	_bank["boss_down"] = to_stream(mix(noise(1.3, 0.6, 1.5, 1400), tone(1.3, 200, 20, W.SINE, 0.7, 0.0, 1.2)))
	_bank["bonk"] = to_stream(mix(noise(0.07, 0.35, 3.0, 2500), tone(0.22, 620, 180, W.TRI, 0.45)))
	# спичка: чирк по коробку + вспышка серы
	var scratch := am(noise(0.14, 0.55, 0.5, 6000, 1800), 90.0, 0.7, true)
	_bank["match"] = to_stream(seq([scratch, mix(noise(0.55, 0.4, 1.6, 3000, 400), tone(0.5, 180, 90, W.SINE, 0.12))]))
	# воспламенение: глухое «вух» с нарастанием и треском сверху
	var whoomp := noise(1.8, 0.8, 1.3, 500, 0.0, 0.18)
	whoomp = mix(whoomp, tone(1.6, 70, 35, W.SINE, 0.55, 0.0, 1.3))
	for i in 10:
		whoomp = mix_at(whoomp, _pop(randf_range(0.01, 0.03), randf_range(0.15, 0.35), 1200, 5000), randf_range(0.15, 1.3))
	_bank["ignite"] = to_stream(whoomp)
	_bank["crackle"] = to_stream(seq([_pop(0.02, 0.4, 1500, 5000), silence(0.05), _pop(0.015, 0.3, 2000, 6000)]))
	# горение: шипение и потрескивание
	var sizzle := noise(1.3, 0.3, 1.0, 7000, 2500, 0.1)
	sizzle = mix(sizzle, noise(1.3, 0.35, 1.4, 600))
	for i in 12:
		sizzle = mix_at(sizzle, _pop(randf_range(0.01, 0.025), randf_range(0.2, 0.45), 1500, 6000), randf_range(0.0, 1.1))
	_bank["burn"] = to_stream(sizzle)
	_bank["hiya"] = to_stream(seq([tone(0.05, 500, 900, W.SQUARE, 0.18), tone(0.16, 900, 700, W.SAW, 0.2, 0.1, 1.2)]))
	_bank["kick"] = to_stream(mix(noise(0.1, 0.55, 3.0, 2800), tone(0.25, 260, 60, W.SINE, 0.8, 0.0, 1.8)))
	_bank["needle"] = to_stream(mix(tone(0.16, 2400, 1500, W.SINE, 0.18), _whoosh(0.1, 0.12, 3000, 8000)))
	_bank["snake_shot"] = to_stream(seq([noise(0.03, 0.3, 3.0, 4000), tone(0.08, 700, 1100, W.TRI, 0.3)]))
	_bank["spin"] = to_stream(mix(_whoosh(0.35, 0.4, 400, 2500), tone(0.35, 200, 600, W.TRI, 0.22)))
	# шаг учёного: глухой удар каблука
	_bank["step"] = to_stream(mix(tone(0.14, 85, 45, W.SINE, 0.55, 0.0, 2.2), noise(0.06, 0.18, 3.0, 450)))
	_bank["power"] = to_stream(_notes([523, 659, 784, 1047], 0.06, W.SQUARE, 0.16, 0.18))
	_bank["no_stamina"] = to_stream(tone(0.25, 220, 140, W.TRI, 0.25, 0.2, 1.2))
	# гром: резкий треск и долгий раскат с «биением»
	var crack := noise(0.3, 0.8, 4.0, 0.0, 1400)
	var rumble := am(noise(3.2, 0.9, 1.3, 170, 0.0, 0.25), 7.0, 0.6, true)
	rumble = lowpass(rumble, 220)
	_normalize(rumble, 0.9)
	_bank["thunder"] = to_stream(mix(mix(crack, rumble), tone(2.5, 48, 30, W.SINE, 0.5, 0.0, 1.4)))

	# ----- новые звуки v5.0
	_bank["clang"] = to_stream(mix(_metal([523, 1187, 1873, 2711], 0.7, 0.4), noise(0.05, 0.4, 3.0, 0.0, 2500)))
	_bank["fork_aim"] = to_stream(am(bandpass(noise(0.55, 0.5, 0.3), 1500, 4200), 28.0, 0.7))
	_bank["fork_dash"] = to_stream(mix(_whoosh(0.4, 0.45, 600, 3500), _metal([880, 1320], 0.4, 0.12)))
	var boing := PackedFloat32Array()
	boing.resize(int(0.2 * SR))
	var ph := 0.0
	for i in boing.size():
		var k := float(i) / boing.size()
		ph += (300.0 + 450.0 * k + 40.0 * sin(k * 60.0)) / SR
		boing[i] = sin(ph * TAU) * 0.4 * pow(1.0 - k, 1.5) * minf(i / 90.0, 1.0)
	_bank["pill_hop"] = to_stream(boing)
	_bank["pill_land"] = to_stream(mix(mix(tone(0.3, 120, 45, W.SINE, 0.8, 0.0, 2.0), noise(0.2, 0.4, 3.0, 800)),
		am(noise(0.25, 0.2, 2.0, 5000, 1500), 40.0, 0.8)))
	var dizzy := PackedFloat32Array()
	dizzy.resize(int(0.7 * SR))
	ph = 0.0
	for i in dizzy.size():
		var k := float(i) / dizzy.size()
		ph += (900.0 - 350.0 * k + 90.0 * sin(k * 40.0)) / SR
		dizzy[i] = (4.0 * absf(fmod(ph, 1.0) - 0.5) - 1.0) * 0.3 * pow(1.0 - k, 1.2)
	_bank["stun"] = to_stream(mix(dizzy, _metal([1568, 2349], 0.5, 0.15)))
	_bank["poof"] = to_stream(noise(0.4, 0.5, 1.5, 1300, 150, 0.05))
	_bank["shuriken"] = to_stream(mix(_whoosh(0.16, 0.35, 3000, 8000), tone(0.12, 3000, 2000, W.SINE, 0.1)))
	_bank["fuse"] = to_stream(am(noise(0.35, 0.3, 0.5, 8000, 3000), 60.0, 0.8, true))
	var boom := mix(noise(0.7, 0.8, 2.0, 1500), tone(0.5, 90, 30, W.SINE, 0.8, 0.0, 1.6))
	boom = mix(boom, noise(0.08, 0.6, 4.0, 0.0, 2000))
	for i in 6:
		boom = mix_at(boom, _pop(0.02, 0.3, 2000, 7000), randf_range(0.05, 0.4))
	_bank["boom"] = to_stream(boom)
	_bank["heal"] = to_stream(_notes([784, 988, 1175, 1568], 0.06, W.TRI, 0.3, 0.3))
	_bank["pop"] = to_stream(mix(tone(0.07, 500, 1500, W.SINE, 0.45, 0.0, 2.0), _pop(0.02, 0.2, 1500, 6000)))
	_bank["shield"] = to_stream(mix(tone(0.35, 400, 900, W.TRI, 0.28, 0.0, 1.0), tone(0.35, 604, 1350, W.SINE, 0.12, 0.0, 1.0)))
	_bank["perk"] = to_stream(_notes([523, 659, 784, 1047, 1319], 0.07, W.SQUARE, 0.14, 0.35))
	_bank["stage_clear"] = to_stream(_notes([523, 659, 784, 659, 784, 1047], 0.1, W.TRI, 0.38, 0.5))
	_bank["scale"] = to_stream(seq([tone(0.05, 1400, 1400, W.SINE, 0.3, 0.0, 0.5), tone(0.14, 2100, 2100, W.SINE, 0.3, 0.0, 1.5)]))
	_bank["scribble"] = to_stream(am(bandpass(noise(0.9, 0.45, 0.4), 1800, 5500), 14.0, 0.95, true))
	_bank["stamp"] = to_stream(mix(noise(0.08, 0.6, 3.0, 1200), tone(0.22, 150, 55, W.SINE, 0.75, 0.0, 2.0)))
	_bank["extinguisher"] = to_stream(noise(2.0, 0.55, 0.7, 7000, 700, 0.06))
	_bank["lamp_click"] = to_stream(mix(noise(0.03, 0.4, 4.0, 0.0, 2500), tone(0.03, 1600, 1500, W.SINE, 0.2, 0.0, 4.0)))
	var hatch := silence(0.9)
	for i in 3:
		hatch = mix_at(hatch, _pop(0.03, 0.35, 1000, 4500), 0.05 + i * 0.22)
	hatch = mix_at(hatch, tone(0.12, 1300, 1900, W.SINE, 0.25, 0.0, 1.5), 0.75)
	_bank["hatch"] = to_stream(hatch)

	# ----- звуки интерфейса: дизайн-язык 2.0, всё — механика прибора
	# защёлка клавиши-вкладки: металлический язычок и щелчок
	_bank["ui_toggle"] = to_stream(mix(seq([_pop(0.012, 0.3, 2000, 7000), silence(0.025), _pop(0.01, 0.22, 2500, 7000)]),
		_metal([2400, 3650], 0.09, 0.07)))
	# отпускание с понижением — «назад»
	_bank["ui_back"] = to_stream(mix(_pop(0.016, 0.3, 1400, 5000), tone(0.07, 700, 420, W.SINE, 0.14, 0.0, 2.5)))
	# нельзя: дребезг реле
	_bank["ui_error"] = to_stream(mix(am(tone(0.16, 120, 110, W.SQUARE, 0.1, 0.0, 1.2), 50.0, 0.8), _pop(0.02, 0.25, 600, 2500)))
	# нажатие бакелитовой клавиши: глухое «тук»
	_bank["ui_key_down"] = to_stream(mix(lowpass(noise(0.04, 0.5, 3.5), 1800), tone(0.06, 150, 85, W.SINE, 0.35, 0.0, 3.0)))
	# рычажный тумблер: резкий щелчок, звон пружины, толчок в корпус
	_bank["ui_lever"] = to_stream(mix(mix(_pop(0.01, 0.5, 1500, 8000), _metal([1850, 2930, 4100], 0.14, 0.09)),
		tone(0.05, 110, 70, W.SINE, 0.3, 0.0, 3.0)))
	# детент крутилки: крошечный щелчок храповика
	_bank["ui_detent"] = to_stream(mix(_pop(0.008, 0.22, 2500, 7000), tone(0.015, 3300, 3000, W.SINE, 0.05, 0.0, 6.0)))
	# галетник: два контакта и глухой упор
	_bank["ui_rotary"] = to_stream(mix(seq([_pop(0.01, 0.35, 1500, 6000), silence(0.018), _pop(0.012, 0.3, 1200, 5000)]),
		tone(0.08, 220, 140, W.SINE, 0.28, 0.0, 3.0)))
	# шаг фейдера: мягкий шорох ползунка
	_bank["ui_fader"] = to_stream(bandpass(noise(0.025, 0.25, 2.0), 700, 3200))
	# откидная крышка: шорох петли и стук пластика
	_bank["ui_cover"] = to_stream(seq([_whoosh(0.08, 0.18, 1200, 4000), mix(_pop(0.02, 0.35, 900, 4000), tone(0.05, 420, 300, W.TRI, 0.12))]))

	# ----- вилки v7.0
	var volley := _whoosh(0.3, 0.3, 1200, 6000)
	for i in 3:
		volley = mix_at(volley, _metal([1320 + i * 190, 2210 + i * 260], 0.18, 0.18), i * 0.045)
	_bank["fork_volley"] = to_stream(volley)
	_bank["fork_whirl"] = to_stream(mix(am(_whoosh(0.75, 0.5, 500, 3200), 22.0, 0.75), tone(0.75, 180, 520, W.TRI, 0.12, 0.0, 0.6)))
	var spring := PackedFloat32Array()
	spring.resize(int(0.35 * SR))
	ph = 0.0
	for i in spring.size():
		var k := float(i) / spring.size()
		ph += (220.0 + 700.0 * k + 60.0 * sin(k * 80.0)) / SR
		spring[i] = sin(ph * TAU) * 0.32 * pow(1.0 - k, 1.3) * minf(i / 80.0, 1.0)
	_bank["fork_pogo"] = to_stream(mix(spring, _whoosh(0.35, 0.2, 400, 2000)))
	_bank["fork_thud"] = to_stream(mix(mix(tone(0.3, 95, 40, W.SINE, 0.8, 0.0, 2.2), lowpass(noise(0.12, 0.5, 3.0), 1200)),
		_metal([740, 1460], 0.45, 0.12)))
	# плавление: шипение с каплями
	var melt := noise(1.1, 0.25, 0.8, 6000, 1800, 0.15)
	for i in 7:
		melt = mix_at(melt, tone(0.06, randf_range(500, 900), randf_range(250, 400), W.SINE, 0.25, 0.0, 3.0), randf_range(0.05, 0.95))
	_bank["melt"] = to_stream(melt)
	return _bank


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
