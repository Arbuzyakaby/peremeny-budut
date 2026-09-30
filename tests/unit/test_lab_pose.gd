extends "res://tests/test_case.gd"
## Учёный и лаборатория финала (lab.gd, lab_room.gd) без игры: где голова, плечо и рука, куда смотрит
## кончик спички и раструб огнетушителя; моргание, рот по слогам, наклон головы, дыхание, ходьба;
## вся комната и учёный рисуются во всех состояниях без ошибок.

const Lab = preload("res://scripts/ending/lab.gd")


func _lab() -> Lab:
	var l: Lab = add(Lab.new())
	l.sx = Lab.STAND_X
	l.hand = l.rest_hand()
	return l


func test_body_parts_line_up() -> void:
	var l := _lab()
	var head := l.head_pos()
	assert_near(head.x, Lab.STAND_X, 0.01, "голова над учёным")
	assert_lt(head.y, l.shoulder().y, "голова выше плеча")
	assert_lt(l.shoulder().y, l.rest_hand().y, "рука ниже плеча")
	assert_lt(l.rest_hand().x, Lab.STAND_X, "левая рука тянется к столу (влево)")
	assert_eq(l.match_tip(), l.hand + Vector2(-50, -190), "спичка торчит из щепоти вверх")
	assert_eq(l.nozzle(), l.hand + Vector2(-210, -40), "раструб — сбоку от кисти")


func test_startle_lifts_everything() -> void:
	var l := _lab()
	var h0 := l.head_pos()
	var s0 := l.shoulder()
	l.startle = 1.0
	assert_near(h0.y - l.head_pos().y, 45.0, 1.0, "испуг — голова подпрыгивает")
	assert_near(s0.y - l.shoulder().y, 45.0, 1.0, "и плечо вместе с ней")


func test_walking_bobs_and_standing_breathes() -> void:
	var l := _lab()
	var ys := []
	for i in 20:
		l.t = i * 0.2
		ys.append(l.head_pos().y)
	var spread: float = ys.max() - ys.min()
	assert_between(spread, 2.0, 12.0, "стоя — дышит: голова чуть ходит")
	l.walking = true
	ys.clear()
	for i in 20:
		l.walk = i * 0.4
		ys.append(l.head_pos().y)
	assert_gt(ys.max() - ys.min(), 15.0, "на ходу — шагает вверх-вниз")


func test_blinks_briefly_and_regularly() -> void:
	var closed := 0
	var blinks := 0
	var was := false
	for i in 1200:  # 20 с по 1/60
		var b := Lab.blink_amount(i / 60.0)
		assert_between(b, 0.0, 1.0)
		if b > 0.5:
			closed += 1
		var now := b > 0.0
		if now and not was:
			blinks += 1
		was = now
	assert_between(blinks, 4, 8, "моргает раз в 3–4 секунды")
	assert_lt(closed, 40, "глаза закрыты меньше 3 % времени")


func test_mouth_follows_syllables() -> void:
	var text := "Ао бб"
	assert_eq(Lab.mouth_open(text, 0.0), 1.0, "«А» — рот широко")
	assert_eq(Lab.mouth_open(text, 1.0 / 15.0), 1.0, "«о» — тоже")
	assert_eq(Lab.mouth_open(text, 2.0 / 15.0), 0.0, "пробел — закрыт")
	assert_eq(Lab.mouth_open(text, 3.0 / 15.0), 0.35, "согласная — чуть приоткрыт")
	assert_eq(Lab.mouth_open(text, 5.0 / 15.0 + 0.001), 1.0, "реплика по кругу, пока идёт talk")
	assert_between(Lab.mouth_open("", 0.3), 0.5, 1.0, "без текста — просто шевелит губами")


func test_speak_sets_text_and_time() -> void:
	var l := _lab()
	l.speak("Регламент есть регламент.", 2.5)
	assert_eq(l.say_text, "Регламент есть регламент.")
	assert_eq(l.talk, 2.5)
	assert_eq(l.say_t, 0.0)
	l._process(1.0)
	assert_near(l.talk, 1.5, 0.001, "реплика убывает")
	assert_near(l.say_t, 1.0, 0.001, "слоги бегут")


func test_head_tilts_toward_the_gaze_but_only_slightly() -> void:
	var l := _lab()
	l.walking = true  # без покачивания в покое
	l.look = Vector2(l.sx - 5000, 0)
	assert_near(l.head_tilt(), -0.09, 0.001, "смотрит влево — наклон влево, не больше 5°")
	l.look = Vector2(l.sx + 5000, 0)
	assert_near(l.head_tilt(), 0.09, 0.001)
	l.look = Vector2(l.sx, 0)
	assert_near(l.head_tilt(), 0.0, 0.001, "прямо — прямо")


func test_hand_trembles_only_when_asked() -> void:
	var l := _lab()
	l.t = 1.3
	assert_eq(l._hand_drawn(), l.hand, "спокойная рука — на месте")
	l.tremble = true
	assert_ne(l._hand_drawn(), l.hand, "ждёт решения — дрожит")
	assert_lt(l._hand_drawn().distance_to(l.hand), 9.0, "но чуть-чуть")


func test_every_state_draws() -> void:
	var l := _lab()
	var states := [
		func() -> void: pass,
		func() -> void: l.speak("Эксперимент завершён.", 2.0),
		func() -> void:
			l.startle = 1.0
			l.talk = 0.0,
		func() -> void:
			l.startle = 0.0
			l.writing = true,
		func() -> void:
			l.writing = false
			l.walking = true
			l.walk = 1.3,
		func() -> void:
			l.walking = false
			l.match_state = Lab.Match.LIT
			l.glow = 1.0,
		func() -> void:
			l.match_state = Lab.Match.FLYING
			l.match_pos = Vector2(600, 300),
		func() -> void:
			l.holding = Lab.Hold.EXTINGUISHER
			l.spraying = true
			l.match_state = Lab.Match.GONE,
		func() -> void:
			l.lights = 0.0
			l.flash = 1.0
			l.show_cabinet = true
			l.show_new_box = true
			l.tally = [12, 5, 7, 3]
			l.notes = PackedStringArray(["СЧЁТ 1234"]),
		func() -> void: l.sx = Lab.OUTSIDE_X,  # ушёл — учёного не рисуют
	]
	for i in states.size():
		states[i].call()
		await assert_draws(l, "учёный, состояние %d" % i)
		await assert_draws(l.front, "рука, состояние %d" % i)


func test_blink_is_suppressed_when_startled() -> void:
	# испуг: глаза круглые, моргание не закрывает их (иначе испуг «мигает»)
	var l := _lab()
	l.startle = 1.0
	l.t = 0.0
	while Lab.blink_amount(l.t) < 0.9:  # найти середину моргания
		l.t += 0.01
	assert_gt(Lab.blink_amount(l.t), 0.9)
	await assert_draws(l, "испуганный учёный в момент моргания")
