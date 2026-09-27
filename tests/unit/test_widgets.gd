extends "res://tests/test_case.gd"
## Приборные контролы дизайн-языка 2.0: крутилка, фейдер, галетный переключатель, рычажный тумблер,
## клавиши-вкладки, крышка опасной клавиши. Значения, упоры, мышь, колесо, клавиши и звуки.

const Design = preload("res://scripts/ui/design.gd")
const RotaryKnob = preload("res://scripts/ui/widgets/rotary_knob.gd")
const Fader = preload("res://scripts/ui/widgets/fader.gd")
const RotarySwitch = preload("res://scripts/ui/widgets/rotary_switch.gd")
const ToggleSwitch = preload("res://scripts/ui/widgets/toggle_switch.gd")
const Segmented = preload("res://scripts/ui/widgets/segmented.gd")
const SoundSpy = preload("res://tests/unit/sound_spy.gd")

var spy: SoundSpy
var old_player: Node


func before_each() -> void:
	use_temp_storage()
	spy = SoundSpy.new()
	add(spy)
	old_player = Design.sound_player
	Design.sound_player = spy


func after_each() -> void:
	Design.sound_player = old_player


func _knob(v := 0.5) -> RotaryKnob:
	var k: RotaryKnob = add(RotaryKnob.new())
	k.size = k.custom_minimum_size
	k.set_value_no_signal(v)
	k.last_detent = k.detent_index()
	return k


func _fader(v := 0.5) -> Fader:
	var f: Fader = add(Fader.new())
	f.size = Vector2(240, 52)
	f.set_value_no_signal(v)
	f.last_detent = f.detent_index()
	return f


func test_knob_clamps_at_both_ends() -> void:
	var k := _knob()
	k.nudge(100)
	assert_near(k.value, 1.0)
	k.nudge(-100)
	assert_near(k.value, 0.0)
	assert_near(k.angle_of(0.0), RotaryKnob.START, 0.0001, "ноль — «семь часов»")
	assert_near(k.angle_of(1.0) - k.angle_of(0.0), RotaryKnob.SWEEP, 0.0001, "шкала 270°")


func test_knob_drag_up_turns_it_up() -> void:
	var k := _knob(0.2)
	mouse_button(k, Vector2(30, 30), true)
	mouse_move(k, Vector2(30, 30 - RotaryKnob.DRAG_PIXELS * 0.5))
	mouse_button(k, Vector2(30, 30 - RotaryKnob.DRAG_PIXELS * 0.5), false)
	assert_near(k.value, 0.7, 0.051, "полдиапазона вверх")
	assert_false(k.dragging)


func test_knob_wheel_and_keys() -> void:
	var k := _knob(0.5)
	mouse_button(k, Vector2.ZERO, true, MOUSE_BUTTON_WHEEL_UP)
	assert_near(k.value, 0.55)
	mouse_button(k, Vector2.ZERO, true, MOUSE_BUTTON_WHEEL_DOWN)
	mouse_button(k, Vector2.ZERO, true, MOUSE_BUTTON_WHEEL_DOWN)
	assert_near(k.value, 0.45)
	k._gui_input(action_event("ui_right"))
	assert_near(k.value, 0.5, 0.001, "стрелка вправо")
	k._gui_input(action_event("ui_down"))
	assert_near(k.value, 0.45, 0.001, "стрелка вниз")


func test_knob_clicks_on_every_detent() -> void:
	var k := _knob(0.0)
	for i in 4:
		k.nudge(1)
	assert_eq(spy.count("ui_detent"), 4, "щелчок на каждом шаге")
	k.value = k.value  # то же значение — без щелчка
	assert_eq(spy.count("ui_detent"), 4)


func test_knob_double_click_resets_to_default() -> void:
	var k := _knob(0.2)
	k.default_value = 0.8
	mouse_button(k, Vector2(30, 30), true)
	mouse_button(k, Vector2(30, 30), false)
	mouse_button(k, Vector2(30, 30), true)
	mouse_button(k, Vector2(30, 30), false)
	assert_near(k.value, 0.8, 0.001, "двойной щелчок — значение по умолчанию")


func test_fader_click_jumps_and_drags() -> void:
	var f := _fader(0.0)
	var t := f.track()
	mouse_button(f, Vector2(t.position.x + t.size.x * 0.75, 26), true)
	assert_near(f.value, 0.75, 0.051, "щелчок по прорези")
	mouse_move(f, Vector2(t.position.x + t.size.x * 0.25, 26))
	assert_near(f.value, 0.25, 0.051, "перетаскивание")
	mouse_button(f, Vector2(t.position.x + t.size.x * 0.25, 26), false)
	assert_false(f.dragging)
	assert_gt(spy.count("ui_fader"), 0, "шорох шагов")


func test_fader_keys_and_limits() -> void:
	var f := _fader(0.95)
	f._gui_input(action_event("ui_right"))
	f._gui_input(action_event("ui_right"))
	assert_near(f.value, 1.0, 0.001, "упор справа")
	f.value_at(-50.0)
	assert_near(f.value_at(-50.0), 0.0, 0.001, "левее прорези — ноль")
	assert_near(f.value_at(9999.0), 1.0, 0.001, "правее — максимум")


func test_rotary_switch_cycles_and_emits() -> void:
	var sw: RotarySwitch = add(RotarySwitch.new())
	sw.setup(["А", "Б", "В"], 0)
	var got := []
	sw.changed.connect(func(i: int) -> void: got.append(i))
	sw.cycle()
	sw.cycle()
	sw.cycle()
	assert_eq(got, [1, 2, 0], "по кругу")
	assert_eq(spy.count("ui_rotary"), 3, "клац на каждом положении")
	assert_gt(sw.custom_minimum_size.y, Design.TOUCH_MIN - 0.1, "не мельче пальца")


func test_rotary_switch_turn_hits_end_stops() -> void:
	var sw: RotarySwitch = add(RotarySwitch.new())
	sw.setup(["30", "60", "120", "БЕЗ"], 0)
	var got := []
	sw.changed.connect(func(i: int) -> void: got.append(i))
	sw.turn(-1)
	assert_eq(sw.selected, 0, "упор")
	assert_eq(spy.count("ui_error"), 1)
	sw.turn(1)
	sw.turn(1)
	assert_eq(got, [1, 2])
	sw.select(3)
	assert_eq(sw.selected, 3)
	assert_len(got, 2, "select() без сигнала")
	assert_true(sw.position_angle(0) < sw.position_angle(3), "положения по дуге слева направо")


func test_toggle_lever() -> void:
	var t: ToggleSwitch = add(ToggleSwitch.new())
	var got := []
	t.toggled.connect(func(on: bool) -> void: got.append(on))
	t.set_on(true)
	assert_true(t.button_pressed)
	assert_near(t.knob, 1.0)
	assert_len(got, 0, "set_on — без сигнала")
	Settings.set_value("reduced_motion", true)  # без анимации — рычажок сразу на месте
	t.button_pressed = false
	assert_eq(got, [false])
	assert_eq(spy.count("ui_lever"), 1, "щелчок рычажка")
	assert_true(t.lever_angle() < 0.0, "рычажок влево")
	Settings.set_value("reduced_motion", false)
	assert_true(t.custom_minimum_size.y >= Design.TOUCH_MIN)


func test_segmented_keys() -> void:
	var s: Segmented = add(Segmented.new())
	s.setup(["РАЗ", "ДВА", "ТРИ"], 1)
	var got := []
	s.changed.connect(func(i: int) -> void: got.append(i))
	assert_true(s.buttons[1].button_pressed, "выбранная клавиша утоплена")
	s._on_pressed(2)
	assert_eq(got, [2])
	s._on_pressed(2)
	assert_eq(got, [2], "повторное нажатие не шлёт сигнал")
	s.select(0)
	assert_true(s.buttons[0].button_pressed)
	assert_false(s.buttons[2].button_pressed)


func test_danger_cover() -> void:
	var b: Button = add(Design.button("СБРОС", func() -> void: pass, "Danger"))
	assert_false(Design.cover_open(b), "под крышкой")
	Design.set_cover(b, true)
	assert_eq(spy.count("ui_cover"), 1)
	assert_false(Design.cover_open(add(Design.button("X", func() -> void: pass))), "у обычной крышки нет")
	Settings.set_value("reduced_motion", true)
	Design.set_cover(b, false)
	assert_false(Design.cover_open(b), "закрыта")
	Settings.set_value("reduced_motion", false)


func test_button_sounds() -> void:
	var pressed := [0]
	var b: Button = add(Design.button("ОК", func() -> void: pressed[0] += 1))
	b.button_down.emit()
	b.pressed.emit()
	assert_eq(pressed[0], 1)
	assert_eq(spy.count("ui_key_down"), 1, "глухой «тук» при нажатии")
	assert_eq(spy.count("ui_select"), 1, "щелчок при отпускании")
