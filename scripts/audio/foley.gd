extends "res://scripts/audio/synth.gd"
## Звуки лаборатории (v11.2) — финал и развязка «Контакта». Собраны как шумовое оформление в кино (фоли),
## а не как «пищалки»: 44 100 Гц вместо 22 050 (есть верхняя октава — щелчки и шорохи звучат чисто),
## удары — модальный синтез (сумма затухающих резонансов материала: кафель, дерево стола, металл
## пружины, стекло), трение и шорох — зернистый шум, у всего — короткий шумовой «контакт» в начале.
## Реверберации нет: звук сухой, как в остальной игре.
##
## Звуки: шаги по кафелю, часы, ручка по бумаге, спичка, гром за окном, вспышка, треск, горение,
## плавление, огнетушитель, штамп, выключатель, скорлупа, выстрел, рикошет и дождь по окну (петля).

const RATE := 44100
const NAMES := ["step", "tick", "scribble", "match", "thunder", "ignite", "crackle", "burn", "melt",
	"extinguisher", "stamp", "lamp_click", "hatch", "gunshot", "ricochet", "rain"]


func _init() -> void:
	sr = RATE


func build() -> Dictionary:
	# громкости (последний аргумент) выровнены по RMS прежних звуков — баланс с музыкой не сдвигается
	var out := {}
	out["step"] = to_stream(_step(), false, -11.6)
	out["tick"] = to_stream(_tick(), false, -6.6)
	out["scribble"] = to_stream(_pen(1.4), false, -2.0)
	out["match"] = to_stream(_match(), false, -4.5)
	out["thunder"] = to_stream(_thunder(), false, -1.0)
	out["ignite"] = to_stream(_ignite(), false, -0.3)
	out["crackle"] = to_stream(_crackle(), false, -4.0)
	out["burn"] = to_stream(_burn(), false, -6.0)
	out["melt"] = to_stream(_melt(), false, -2.5)
	out["extinguisher"] = to_stream(_extinguisher(), false, -9.3)
	out["stamp"] = to_stream(_stamp(), false, 0.0)
	out["lamp_click"] = to_stream(_switch(), false, -6.5)
	out["hatch"] = to_stream(_hatch(), false, -0.7)
	out["gunshot"] = to_stream(_gunshot(), false, -1.8)
	out["ricochet"] = to_stream(_ricochet(), false, -10.2)
	out["rain"] = to_stream(_rain(6.0), true, -4.0)
	return out


# ---------------------------------------------------------------- строительные блоки

## Модальный синтез: modes — [[частота, время затухания (с), громкость], ...]. Фазы случайные, атака 1 мс.
func modal(dur: float, modes: Array, detune := 0.0) -> PackedFloat32Array:
	var n := int(dur * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	for m: Array in modes:
		var f := float(m[0]) * (1.0 + randf_range(-detune, detune))
		var tau := float(m[1])
		var a := float(m[2])
		var ph := randf() * TAU
		var w := TAU * f / sr
		for i in n:
			var t := float(i) / sr
			out[i] += sin(ph + w * i) * a * exp(-t / tau) * minf(i / (0.001 * sr), 1.0)
	return out


## Короткий шумовой «контакт»: удар, щелчок, касание. dur — длительность, lp/hp — окраска.
func burst(dur: float, vol: float, lp := 0.0, hp := 0.0) -> PackedFloat32Array:
	var n := maxi(int(dur * sr), 2)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = (randf() * 2.0 - 1.0) * exp(-5.0 * float(i) / n)
	if lp > 0.0:
		b = lowpass(b, lp)
	if hp > 0.0:
		b = highpass(b, hp)
	_normalize(b, vol)
	return b


## Наложить src на dst с момента at (сек) прямо в dst, без копии длинного буфера (дождь — сотни капель).
## Упакованные массивы в GDScript передаются по ссылке, поэтому изменения видны вызывающему.
func _add(dst: PackedFloat32Array, src: PackedFloat32Array, at: float) -> void:
	var off := int(at * sr)
	for i in mini(src.size(), dst.size() - off):
		dst[off + i] += src[i]


## Огибающая: нарастание attack с, спад по экспоненте с постоянной tau.
func shape(buf: PackedFloat32Array, attack: float, tau: float) -> PackedFloat32Array:
	var out := buf.duplicate()
	for i in out.size():
		var t := float(i) / sr
		out[i] *= minf(t / maxf(attack, 0.0005), 1.0) * exp(-maxf(t - attack, 0.0) / tau)
	return out


## «Розоватый» шум: сумма фильтров разной полосы — мягче белого, как настоящие шорохи и гул.
func pinkish(dur: float) -> PackedFloat32Array:
	var w := noise(dur, 1.0, 0.0)
	var out := mix(mix(lowpass(w, 300.0), lowpass(w, 1500.0)), mix(lowpass(w, 6000.0), w))
	_normalize(out, 1.0)
	return out


# ---------------------------------------------------------------- звуки

## Шаг по кафелю: удар каблука (кафель звенит коротко и высоко, пол глухо), затем шлепок подошвы.
func _step() -> PackedFloat32Array:
	var heel := mix(burst(0.004, 0.8, 7000, 300), modal(0.12, [[1180, 0.025, 0.25], [2350, 0.018, 0.18],
		[3900, 0.012, 0.12], [95, 0.05, 0.5], [160, 0.035, 0.3]], 0.04))
	var sole := shape(lowpass(noise(0.08, 1.0, 0.0), 2200), 0.004, 0.02)
	_normalize(sole, 0.35)
	var out := mix_at(heel, sole, 0.055)
	return mix_at(out, burst(0.002, 0.12, 9000, 3000), 0.058)  # скрип кожи о кафель


## Часы: анкерный спуск — два металлических щелчка подряд и деревянный корпус.
func _tick() -> PackedFloat32Array:
	var click := mix(burst(0.0015, 0.7, 12000, 1500), modal(0.06, [[3150, 0.012, 0.3], [4720, 0.008, 0.2],
		[6230, 0.006, 0.14], [880, 0.02, 0.25]], 0.02))
	return mix_at(click, burst(0.0012, 0.35, 10000, 2000), 0.004)


## Ручка по бумаге: росчерки с паузами; шорох шарика — высокий зернистый шум по скорости пера,
## бумага и стол под ней — мягкий низ.
func _pen(dur: float) -> PackedFloat32Array:
	var out := silence(dur)
	var at := 0.03
	while at < dur - 0.12:
		var stroke := randf_range(0.06, 0.17)
		var buf := bandpass(noise(stroke, 1.0, 0.0), randf_range(2400, 3200), randf_range(7000, 10000))
		buf = mix(buf, lowpass(noise(stroke, 0.3, 0.0), 700))
		_normalize(buf, 1.0)
		var loops := randf_range(2.0, 4.0)
		for i in buf.size():
			var k := float(i) / buf.size()
			var speed := sin(PI * k) * (0.6 + 0.4 * absf(sin(PI * loops * k)))
			buf[i] *= 0.3 * speed * speed * (0.8 + 0.4 * randf())  # шарик катится неровно
		out = mix_at(out, buf, at)
		at += stroke + (randf_range(0.015, 0.05) if randf() < 0.8 else randf_range(0.12, 0.22))
	return out


## Спичка: чирк головкой о тёрку (шершавое трение), вспышка серы с треском, затем ровное пламя.
func _match() -> PackedFloat32Array:
	var scratch := bandpass(noise(0.13, 1.0, 0.0), 1800, 9000)
	for i in scratch.size():
		var k := float(i) / scratch.size()
		scratch[i] *= (0.35 + 0.65 * randf()) * sin(PI * k)  # зёрна тёрки
	_normalize(scratch, 0.7)
	var flare := shape(lowpass(noise(0.4, 1.0, 0.0), 3500), 0.02, 0.09)
	_normalize(flare, 0.85)
	for i in 6:
		flare = mix_at(flare, burst(0.003, randf_range(0.2, 0.4), 9000, 2500), randf_range(0.005, 0.12))
	var flame := shape(bandpass(pinkish(0.9), 150, 1600), 0.05, 0.35)
	_normalize(flame, 0.25)
	return mix_at(mix_at(scratch, flare, 0.12), flame, 0.2)


## Гром за окном: сухой треск разряда (стекло срезает верх), потом долгий перекатывающийся раскат —
## отражения от облаков и домов приходят пачками, и в самом низу — гул.
func _thunder() -> PackedFloat32Array:
	var dur := 4.5
	var out := silence(dur)
	var crack := shape(bandpass(noise(0.35, 1.0, 0.0), 300, 2600), 0.003, 0.07)
	_normalize(crack, 0.8)
	out = mix(out, crack)
	var t := 0.12
	while t < dur - 0.6:  # раскаты
		var len := randf_range(0.4, 1.1)
		var roll := shape(lowpass(noise(len, 1.0, 0.0), randf_range(160, 380)), randf_range(0.05, 0.2), len * 0.4)
		_normalize(roll, randf_range(0.35, 0.8) * exp(-t / 2.2))
		out = mix_at(out, roll, t)
		t += randf_range(0.15, 0.45)
	var sub := shape(lowpass(noise(dur, 1.0, 0.0), 60), 0.2, 1.6)
	_normalize(sub, 0.7)
	return mix(out, sub)


## Вспышка пожара: воздух втягивается («вух» с растущей яркостью) и вспыхивает, внизу — толчок.
func _ignite() -> PackedFloat32Array:
	var dur := 1.6
	var w := noise(dur, 1.0, 0.0)
	var out := PackedFloat32Array()
	out.resize(w.size())
	var y := 0.0
	for i in w.size():
		var t := float(i) / sr
		var cutoff := lerpf(180.0, 2600.0, minf(t / 0.35, 1.0)) * exp(-maxf(t - 0.35, 0.0) * 1.2)
		var a := 1.0 - exp(-TAU * cutoff / sr)
		y += a * (w[i] - y)
		out[i] = y * minf(t / 0.3, 1.0) * exp(-maxf(t - 0.3, 0.0) / 0.5)
	_normalize(out, 0.9)
	out = mix(out, shape(modal(0.8, [[55, 0.25, 0.8], [82, 0.18, 0.4]]), 0.02, 0.25))
	for i in 10:
		out = mix_at(out, _snap(randf_range(0.15, 0.4)), randf_range(0.2, 1.3))
	return out


## Щелчок сгорающего волокна: крошечный излом с короткой резонансной «пружинкой».
func _snap(vol: float) -> PackedFloat32Array:
	var f := randf_range(1800, 4500)
	return mix(burst(0.0015, vol, 14000, 1200), modal(0.03, [[f, 0.006, vol * 0.5], [f * 1.7, 0.004, vol * 0.3]]))


## Треск костра: пара-тройка сухих изломов волокон.
func _crackle() -> PackedFloat32Array:
	var out := silence(0.18)
	for i in randi_range(2, 3):
		out = mix_at(out, _snap(randf_range(0.4, 0.8)), randf_range(0.0, 0.1))
	return out


## Горение: ровное шипение с «дыханием» пламени и частыми мелкими щелчками.
func _burn() -> PackedFloat32Array:
	var dur := 1.3
	var hiss := bandpass(pinkish(dur), 1200, 9000)
	for i in hiss.size():
		var t := float(i) / sr
		hiss[i] *= (0.7 + 0.3 * sin(TAU * 3.1 * t + sin(TAU * 0.7 * t))) * minf(t / 0.08, 1.0) * (1.0 - t / dur)
	_normalize(hiss, 0.45)
	var roar := shape(lowpass(noise(dur, 1.0, 0.0), 400), 0.1, 0.8)
	_normalize(roar, 0.4)
	var out := mix(hiss, roar)
	for i in 16:
		out = mix_at(out, _snap(randf_range(0.15, 0.4)), randf_range(0.0, dur - 0.05))
	return out


## Плавление пластика: вязкие пузыри лопаются (резонанс пузыря — частота растёт по мере его схлопывания).
func _melt() -> PackedFloat32Array:
	var dur := 1.1
	var out := shape(bandpass(pinkish(dur), 800, 5000), 0.1, 0.5)
	_normalize(out, 0.2)
	for i in 9:
		var f0 := randf_range(350, 700)
		var b := PackedFloat32Array()
		b.resize(int(0.05 * sr))
		var ph := 0.0
		for k in b.size():
			var t := float(k) / sr
			ph += TAU * f0 * (1.0 + 8.0 * t) / sr  # пузырь схлопывается — тон вверх
			b[k] = sin(ph) * exp(-t / 0.012) * 0.35
		out = mix_at(out, b, randf_range(0.03, dur - 0.1))
	return out


## Углекислотный огнетушитель: удар клапана, рывок газа и ревущая струя: широкий шум с турбулентной
## «рябью», низкий рёв расширения и треск снега сухого льда в раструбе.
func _extinguisher() -> PackedFloat32Array:
	var dur := 3.0
	var valve := mix(burst(0.004, 0.8, 6000, 200), modal(0.15, [[180, 0.04, 0.5], [530, 0.03, 0.3], [1390, 0.02, 0.2]]))
	var jet := bandpass(noise(dur, 1.0, 0.0), 500, 12000)
	var roar := lowpass(noise(dur, 1.0, 0.0), 350)
	_normalize(jet, 1.0)
	_normalize(roar, 1.0)
	var out := PackedFloat32Array()
	out.resize(jet.size())
	var flutter := 1.0
	for i in out.size():
		var t := float(i) / sr
		if i % 441 == 0:
			flutter = lerpf(flutter, randf_range(0.75, 1.0), 0.5)  # турбулентность — неровная «рябь»
		var env := minf(t / 0.06, 1.0) * (1.0 if t < dur - 0.6 else (dur - t) / 0.6)
		var punch := 1.0 + 0.6 * exp(-t / 0.15)  # первый рывок газа
		out[i] = (jet[i] * 0.55 * flutter + roar[i] * 0.35) * env * punch
	for i in 40:  # треск снега сухого льда в раструбе
		_add(out, burst(0.002, randf_range(0.05, 0.15), 14000, 4000), randf_range(0.1, dur - 0.7))
	return mix(valve, out)


## Штамп: резина шлёпает по бумаге на деревянном столе — глухой удар стола и хлопок бумаги.
func _stamp() -> PackedFloat32Array:
	var desk := modal(0.3, [[110, 0.07, 0.8], [240, 0.05, 0.5], [455, 0.035, 0.35], [890, 0.02, 0.2]], 0.03)
	var paper := shape(bandpass(noise(0.06, 1.0, 0.0), 700, 6000), 0.001, 0.012)
	_normalize(paper, 0.6)
	var lift := shape(bandpass(noise(0.05, 1.0, 0.0), 1500, 5000), 0.005, 0.01)  # штамп отлипает
	_normalize(lift, 0.12)
	return mix_at(mix(mix(burst(0.003, 0.6, 3000), desk), paper), lift, 0.2)


## Выключатель лампы: взвод пружины и резкий щелчок рычажка в пластиковом корпусе.
func _switch() -> PackedFloat32Array:
	var pre := mix(burst(0.0015, 0.3, 12000, 2000), modal(0.02, [[4100, 0.004, 0.15]]))
	var snap := mix(burst(0.002, 0.8, 12000, 800), modal(0.05, [[2450, 0.01, 0.35], [3900, 0.006, 0.25], [1250, 0.014, 0.3]]))
	return mix_at(pre, snap, 0.012)


## Яйцо трескается: учащающиеся хрупкие надломы скорлупы, последний — громче; писк малыша.
func _hatch() -> PackedFloat32Array:
	var out := silence(0.95)
	var t := 0.04
	var gap := 0.14
	while t < 0.7:
		out = mix_at(out, mix(burst(0.002, randf_range(0.25, 0.45), 14000, 2500),
			modal(0.02, [[randf_range(3500, 6500), 0.004, 0.2]])), t)
		t += gap
		gap = maxf(gap * randf_range(0.7, 0.85), 0.018)  # учащаются, но не бесконечно
	out = mix_at(out, mix(burst(0.004, 0.8, 12000, 1500), modal(0.05, [[4200, 0.01, 0.4], [2600, 0.012, 0.3]])), 0.7)
	var peep := shape(tone(0.12, 1500, 2100, W.SINE, 0.22, 0.0, 0.5), 0.02, 0.05)
	return mix_at(out, peep, 0.8)


## Выстрел: ударная волна (резкий N-импульс), грохот дульных газов и лязг затвора — в тесной комнате
## без эха, но с плотным низом.
func _gunshot() -> PackedFloat32Array:
	var n := int(0.6 * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var wlen := int(0.0012 * sr)
	for i in wlen:  # N-волна
		out[i] = 1.0 - 2.0 * float(i) / wlen
	var blast := shape(lowpass(noise(0.6, 1.0, 0.0), 1800), 0.001, 0.07)
	_normalize(blast, 0.9)
	var boom := shape(modal(0.5, [[65, 0.12, 1.0], [110, 0.08, 0.5]]), 0.001, 0.12)
	out = mix(mix(out, blast), boom)
	var slide := mix(burst(0.003, 0.4, 9000, 1500), modal(0.06, [[2900, 0.012, 0.25], [5100, 0.008, 0.15]]))
	return mix_at(out, slide, 0.09)


## Рикошет: удар пули о металл и свист, уходящий вниз по Доплеру (пуля удаляется).
func _ricochet() -> PackedFloat32Array:
	var dur := 0.5
	var b := PackedFloat32Array()
	b.resize(int(dur * sr))
	var ph := 0.0
	for i in b.size():
		var t := float(i) / sr
		var f := 3000.0 / (1.0 + 2.5 * t)  # частота падает: источник удаляется
		ph += TAU * f * (1.0 + 0.02 * sin(TAU * 38.0 * t)) / sr  # пуля кувыркается
		b[i] = sin(ph) * 0.35 * minf(t / 0.01, 1.0) * exp(-t / 0.18)
	var hit := mix(burst(0.002, 0.7, 14000, 2500), modal(0.08, [[4700, 0.015, 0.3], [7300, 0.01, 0.2]]))
	return mix(hit, b)


## Дождь по окну лаборатории: ровный шелест вдалеке и отдельные капли по стеклу (короткий «тик»
## с высоким резонансом стекла), изредка — тяжёлая капля с подоконника. Бесшовная петля.
func _rain(dur: float) -> PackedFloat32Array:
	var bed := bandpass(pinkish(dur + 0.5), 400, 7000)
	_normalize(bed, 0.22)
	for i in bed.size():
		var t := float(i) / sr
		bed[i] *= 0.85 + 0.15 * sin(TAU * 0.13 * t + 1.7 * sin(TAU * 0.05 * t))  # порывы
	for i in int(dur * 55.0):  # капли по стеклу
		var f := randf_range(2600, 5200)
		_add(bed, mix(burst(0.0012, randf_range(0.05, 0.22), 14000, 1800), modal(0.02, [[f, 0.004, 0.08]])),
			randf_range(0.0, dur + 0.3))
	for i in int(dur * 0.8):  # капля с подоконника — ниже и плотнее
		_add(bed, modal(0.08, [[randf_range(700, 1100), 0.02, 0.25], [randf_range(1800, 2400), 0.01, 0.1]]),
			randf_range(0.0, dur + 0.3))
	return make_loop(bed, 0.5)
