extends "res://scripts/audio/synth.gd"
## Банк звуковых эффектов: рецепты всех звуков игры поверх генераторов synth.gd.
## Громкости выровнены по замеру RMS: частые звуки (приземление таблетки, лязг вилки) тише,
## резкие верха срезаны фильтрами; поправка — третьим аргументом to_stream (дБ).

## Сколько звуков в build_sounds() — для полосы загрузки (тест сверяет с фактом).
const SOUND_COUNT := 83

const Foley = preload("res://scripts/audio/foley.gd")

var _bank: Dictionary = {}


func build_sounds() -> Dictionary:
	_bank = {}
	built_count = 0
	_bank["eat"] = to_stream(seq([tone(0.06, 440, 700, W.SQUARE, 0.2), tone(0.1, 700, 1200, W.SQUARE, 0.2)]))
	_bank["hurt"] = to_stream(mix(tone(0.35, 320, 70, W.SAW, 0.35, 0.0, 1.5), noise(0.25, 0.3, 2.0, 1800)))
	_bank["bite"] = to_stream(mix(noise(0.1, 0.5, 3.0, 3000), tone(0.25, 260, 90, W.SQUARE, 0.28)), false, -2.0)
	_bank["shoot"] = to_stream(mix(noise(0.2, 0.4, 2.5, 2200, 250), tone(0.18, 320, 110, W.SINE, 0.3)))
	_bank["charge"] = to_stream(mix(tone(0.45, 90, 420, W.SAW, 0.25, 0.0, 0.8), _whoosh(0.45, 0.2, 300, 1500)))
	_bank["slam"] = to_stream(mix(tone(0.6, 110, 30, W.SINE, 0.9, 0.0, 1.5), noise(0.45, 0.5, 3.0, 900)), false, -3.0)
	_bank["yolk"] = to_stream(_notes([660, 880, 1100, 1320], 0.07, W.TRI, 0.35, 0.2))
	_bank["punch"] = to_stream(mix(noise(0.08, 0.4, 3.0, 2000), tone(0.15, 200, 80, W.SINE, 0.6)), false, -3.0)
	_bank["whoosh"] = to_stream(_whoosh(0.28, 0.45, 350, 1900), false, -2.0)
	_bank["throw"] = to_stream(mix(tone(0.1, 900, 400, W.SQUARE, 0.12), _whoosh(0.12, 0.2, 800, 3000)))
	_bank["warn"] = to_stream(seq([tone(0.06, 1000, 1000, W.SQUARE, 0.13, 0.0, 0.5), silence(0.04),
		tone(0.06, 1000, 1000, W.SQUARE, 0.13, 0.0, 0.5)]))
	# рёв яичницы на смене фазы: низкое рычание пилой с вибрато и нарастающее шкворчание масла
	var growl := am(mix(tone(1.1, 95, 62, W.SAW, 0.3, 0.0, 1.1), tone(1.1, 101, 66, W.SAW, 0.22, 0.0, 1.1)), 11.0, 0.45)
	_bank["roar"] = to_stream(mix(lowpass(growl, 1400), noise(1.1, 0.3, 1.4, 5200, 1800, 0.35)), false, -3.0)
	_bank["phase"] = to_stream(mix(tone(0.9, 140, 50, W.SAW, 0.35, 0.0, 1.2), tone(0.9, 147, 52, W.SAW, 0.28, 0.0, 1.2)))
	_bank["pepper"] = to_stream(tone(0.12, 1400, 600, W.SINE, 0.3))
	_bank["splat"] = to_stream(mix(noise(0.12, 0.45, 3.0, 1500), tone(0.1, 180, 90, W.SINE, 0.3)))
	_bank["win"] = to_stream(_notes([523, 659, 784, 1047, 784, 1047], 0.12, W.TRI, 0.4, 0.6))
	_bank["lose"] = to_stream(_notes([440, 370, 311, 262], 0.18, W.SQUARE, 0.18, 0.6))
	# интерфейс 2.0 — механика: фокус — лёгкий тик, отпускание клавиши — сухой щелчок
	_bank["ui_move"] = to_stream(mix(_pop(0.012, 0.12, 3000, 7000), tone(0.02, 2600, 2400, W.SINE, 0.04, 0.0, 5.0)))
	_bank["ui_select"] = to_stream(mix(_pop(0.016, 0.34, 1800, 6500), tone(0.05, 1900, 1700, W.SINE, 0.1, 0.0, 5.0)))
	_bank["boss_down"] = to_stream(mix(noise(1.3, 0.6, 1.5, 1400), tone(1.3, 200, 20, W.SINE, 0.7, 0.0, 1.2)), false, -2.0)
	_bank["bonk"] = to_stream(mix(noise(0.07, 0.35, 3.0, 2500), tone(0.22, 620, 180, W.TRI, 0.45)))
	_bank["hiya"] = to_stream(seq([tone(0.05, 500, 900, W.SQUARE, 0.18), tone(0.16, 900, 700, W.SAW, 0.2, 0.1, 1.2)]))
	_bank["kick"] = to_stream(mix(noise(0.1, 0.45, 3.0, 2200), tone(0.25, 260, 60, W.SINE, 0.8, 0.0, 1.8)), false, -4.0)
	_bank["needle"] = to_stream(mix(tone(0.16, 2400, 1500, W.SINE, 0.18), _whoosh(0.1, 0.12, 3000, 8000)))
	_bank["snake_shot"] = to_stream(seq([noise(0.03, 0.3, 3.0, 4000), tone(0.08, 700, 1100, W.TRI, 0.3)]))
	_bank["spin"] = to_stream(mix(_whoosh(0.35, 0.4, 400, 2500), tone(0.35, 200, 600, W.TRI, 0.22)))
	_bank["power"] = to_stream(_notes([523, 659, 784, 1047], 0.06, W.SQUARE, 0.16, 0.18))
	_bank["no_stamina"] = to_stream(tone(0.25, 220, 140, W.TRI, 0.25, 0.2, 1.2))

	# ----- новые звуки v5.0
	_bank["clang"] = to_stream(mix(_metal([523, 1187, 1873, 2711], 0.7, 0.4), noise(0.05, 0.2, 3.0, 5500, 2000)), false, -5.0)
	_bank["fork_aim"] = to_stream(am(bandpass(noise(0.55, 0.5, 0.3), 1100, 3000), 22.0, 0.55), false, -5.0)
	_bank["fork_dash"] = to_stream(mix(_whoosh(0.4, 0.45, 500, 2800), _metal([880, 1320], 0.4, 0.12)), false, -3.0)
	var boing := PackedFloat32Array()
	boing.resize(int(0.2 * SR))
	var ph := 0.0
	for i in boing.size():
		var k := float(i) / boing.size()
		ph += (300.0 + 450.0 * k + 40.0 * sin(k * 60.0)) / SR
		boing[i] = sin(ph * TAU) * 0.4 * pow(1.0 - k, 1.5) * minf(i / 90.0, 1.0)
	_bank["pill_hop"] = to_stream(boing)
	_bank["pill_land"] = to_stream(mix(mix(tone(0.3, 120, 45, W.SINE, 0.8, 0.0, 2.0), noise(0.2, 0.4, 3.0, 800)),
		am(noise(0.25, 0.12, 2.0, 3500, 1200), 40.0, 0.6)), false, -6.0)
	var dizzy := PackedFloat32Array()
	dizzy.resize(int(0.7 * SR))
	ph = 0.0
	for i in dizzy.size():
		var k := float(i) / dizzy.size()
		ph += (900.0 - 350.0 * k + 90.0 * sin(k * 40.0)) / SR
		dizzy[i] = (4.0 * absf(fmod(ph, 1.0) - 0.5) - 1.0) * 0.3 * pow(1.0 - k, 1.2)
	_bank["stun"] = to_stream(mix(dizzy, _metal([1568, 2349], 0.5, 0.15)))
	_bank["poof"] = to_stream(noise(0.4, 0.5, 1.5, 1300, 150, 0.05))
	_bank["shuriken"] = to_stream(mix(_whoosh(0.16, 0.35, 2200, 6000), tone(0.12, 3000, 2000, W.SINE, 0.1)), false, -3.0)
	_bank["fuse"] = to_stream(am(noise(0.35, 0.3, 0.5, 6000, 2500), 60.0, 0.6), false, -3.0)
	var boom := mix(noise(0.7, 0.8, 2.0, 1500), tone(0.5, 90, 30, W.SINE, 0.8, 0.0, 1.6))
	boom = mix(boom, noise(0.08, 0.4, 4.0, 5000, 1500))
	for i in 6:
		boom = mix_at(boom, _pop(0.02, 0.3, 2000, 7000), randf_range(0.05, 0.4))
	_bank["boom"] = to_stream(boom, false, -3.0)
	_bank["heal"] = to_stream(_notes([784, 988, 1175, 1568], 0.06, W.TRI, 0.3, 0.3))
	_bank["pop"] = to_stream(mix(tone(0.07, 500, 1500, W.SINE, 0.45, 0.0, 2.0), _pop(0.02, 0.2, 1500, 6000)), false, -2.0)
	_bank["shield"] = to_stream(mix(tone(0.35, 400, 900, W.TRI, 0.28, 0.0, 1.0), tone(0.35, 604, 1350, W.SINE, 0.12, 0.0, 1.0)))
	_bank["perk"] = to_stream(_notes([523, 659, 784, 1047, 1319], 0.07, W.SQUARE, 0.14, 0.35))
	_bank["stage_clear"] = to_stream(_notes([523, 659, 784, 659, 784, 1047], 0.1, W.TRI, 0.38, 0.5))
	_bank["scale"] = to_stream(seq([tone(0.05, 1400, 1400, W.SINE, 0.3, 0.0, 0.5), tone(0.14, 2100, 2100, W.SINE, 0.3, 0.0, 1.5)]))

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
	_bank["ui_lever"] = to_stream(mix(mix(_pop(0.01, 0.32, 1500, 6000), _metal([1850, 2930, 4100], 0.14, 0.07)),
		tone(0.05, 110, 70, W.SINE, 0.3, 0.0, 3.0)), false, -2.0)
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
	var volley := _whoosh(0.3, 0.3, 1000, 4500)
	for i in 3:
		volley = mix_at(volley, _metal([1320 + i * 190, 2210 + i * 260], 0.18, 0.18), i * 0.045)
	_bank["fork_volley"] = to_stream(volley, false, -3.0)
	_bank["fork_whirl"] = to_stream(mix(am(_whoosh(0.75, 0.5, 450, 2600), 22.0, 0.6), tone(0.75, 180, 520, W.TRI, 0.12, 0.0, 0.6)), false, -3.0)
	var spring := PackedFloat32Array()
	spring.resize(int(0.35 * SR))
	ph = 0.0
	for i in spring.size():
		var k := float(i) / spring.size()
		ph += (220.0 + 700.0 * k + 60.0 * sin(k * 80.0)) / SR
		spring[i] = sin(ph * TAU) * 0.32 * pow(1.0 - k, 1.3) * minf(i / 80.0, 1.0)
	_bank["fork_pogo"] = to_stream(mix(spring, _whoosh(0.35, 0.2, 400, 2000)))
	_bank["fork_thud"] = to_stream(mix(mix(tone(0.3, 95, 40, W.SINE, 0.8, 0.0, 2.2), lowpass(noise(0.12, 0.5, 3.0), 1200)),
		_metal([740, 1460], 0.45, 0.12)), false, -4.0)

	# ----- матрёшки v9.0: всё деревянное и лакированное
	# раскрылась: пустотелый «чпок» — щелчок шва и гулкое дерево внутри
	_bank["doll_open"] = to_stream(mix(mix(_pop(0.02, 0.4, 800, 4000), tone(0.12, 540, 400, W.TRI, 0.3, 0.0, 2.5)),
		tone(0.2, 262, 250, W.SINE, 0.28, 0.0, 1.8)), false, -3.0)
	# прыжок малышки: деревянная пружинка вверх
	_bank["doll_hop"] = to_stream(mix(tone(0.14, 420, 950, W.TRI, 0.2, 0.0, 1.5), _whoosh(0.12, 0.12, 900, 3500)))
	# приземление: сухой стук дерева о половицу
	_bank["doll_land"] = to_stream(mix(tone(0.16, 190, 90, W.SINE, 0.55, 0.0, 2.5), _pop(0.025, 0.35, 1200, 5000)), false, -4.0)
	# «хи-хи» перед прыжком: три коротких писка с дрожью
	var giggle := seq([tone(0.05, 1250, 1450, W.SQUARE, 0.06), silence(0.03), tone(0.05, 1300, 1500, W.SQUARE, 0.06),
		silence(0.03), tone(0.07, 1350, 1150, W.SQUARE, 0.06)])
	_bank["doll_giggle"] = to_stream(lowpass(am(giggle, 30.0, 0.4), 3500), false, -4.0)
	# лента хоровода: шорох ткани и звон натянутой струны
	_bank["ribbon"] = to_stream(mix(_whoosh(0.22, 0.2, 1500, 5000), tone(0.3, 330, 318, W.TRI, 0.14, 0.0, 1.5)))
	# найдена пасхалка: волшебный перезвон
	_bank["secret"] = to_stream(_notes([784, 988, 1319, 1568, 1976], 0.06, W.SINE, 0.28, 0.5))

	# ----- «Контакт» v10.0
	# шипение змеи: высокий шум с нарастанием и дрожью языка
	_bank["hiss"] = to_stream(am(noise(0.75, 0.3, 0.6, 9000, 3200, 0.3), 18.0, 0.25), false, -4.0)
	# ----- доска в «Контакте» трескается (v12.2)
	# скрип нагретого дерева: узкий шум с неровной дрожью и медленно «плывущий» тон
	var creak := am(bandpass(noise(0.6, 1.0, 0.9, 0.0, 0.0, 0.14), 180, 900), 13.0, 0.7, true)
	_normalize(creak, 0.55)
	_bank["wood_creak"] = to_stream(mix(creak, tone(0.55, 150, 104, W.SAW, 0.07, 0.35, 1.3)), false, -4.0)
	# излом: сухой треск, глухой удар доски и два вторичных щелчка волокон
	var snap := mix(_pop(0.18, 0.9, 400, 4500), tone(0.4, 120, 42, W.SINE, 0.7, 0.0, 2.2))
	snap = mix_at(snap, _pop(0.06, 0.5, 900, 3500), 0.07)
	snap = mix_at(snap, _pop(0.05, 0.35, 1200, 4000), 0.15)
	_bank["wood_snap"] = to_stream(mix(snap, noise(0.3, 0.22, 2.5, 1500)), false, -3.0)
	# щепа: пачка коротких сухих щелчков, затухающих
	var spl := silence(0.34)
	for i in 7:
		spl = mix_at(spl, _pop(0.02, 0.4 * (1.0 - i * 0.11), randf_range(1500, 3500), 6500), i * 0.04 + randf() * 0.02)
	_bank["splinter"] = to_stream(spl, false, -6.0)
	# ----- лаборатория (v11.2): фоли-звуки на 44,1 кГц — шаги, часы, спичка, гром, огонь, огнетушитель,
	# штамп, выключатель, скорлупа, выстрел, рикошет и дождь по окну (foley.gd)
	var fol := Foley.new().build()
	_bank.merge(fol, true)
	built_count += fol.size()
	return _bank
