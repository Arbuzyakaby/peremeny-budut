extends Control
## Сенсорное управление. Мультитач: каждый палец отслеживается по индексу.
## - Схема «джойстик»: плавающий (или фиксированный) стик в своей половине экрана задаёт направление
##   головы; стик, отклонённый до упора, включает спринт.
## - Схема «палец»: змея ползёт к точке касания.
## - Справа (у левши — слева) кнопки АТАКА и СПРИНТ, сверху — пауза. Двойной тап — атака.
## Наружу: steer (направление, Vector2.ZERO — нет ввода), sprint_held, сигналы attack и pause.

signal attack_pressed
signal pause_pressed

const Design = preload("res://scripts/ui/design.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Settings = preload("res://scripts/core/settings.gd")

const STICK_R := 78.0
const DEADZONE := 0.22
const SPRINT_EDGE := 0.94
const DOUBLE_TAP := 0.32
const TAP_TIME := 0.22

var active := false          # идёт забег (кнопки видны и принимают касания)
var preview := false         # витрина в настройках (v12.3): рисуется вживую, касаний не принимает
var steer := Vector2.ZERO
var sprint_held := false
var head_screen := Vector2(-1, -1)  # голова змеи на экране — для схемы «палец»
var ability_type := -1
var ability_charges := 0
var stamina := 1.0
var safe := Vector4.ZERO
var pause_rect := Rect2()

var _stick_index := -1
var _stick_center := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _finger_index := -1
var _finger_pos := Vector2.ZERO
var _sprint_index := -1
var _attack_flash := 0.0
var _last_tap := -10.0
var _touch_start: Dictionary = {}  # index -> [время, позиция]
var _time := 0.0
var _pulse_t := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	release_all()


func release_all() -> void:
	_stick_index = -1
	_finger_index = -1
	_sprint_index = -1
	_touch_start.clear()
	_attack_flash = 0.0
	steer = Vector2.ZERO
	sprint_held = false


## Игра свёрнута или окно потеряло фокус: палец, который держал стик, никогда не пришлёт «отпустил».
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		release_all()


# ---------------------------------------------------------------- раскладка

func _scale() -> float:
	return [0.8, 1.0, 1.25][Settings.choice("button_size")]


func _lefty() -> bool:
	return Settings.flag("left_handed")


func _stick_side_has(p: Vector2) -> bool:
	return p.x > size.x * 0.5 if _lefty() else p.x < size.x * 0.5


func _fixed_center() -> Vector2:
	var m := 150.0 * _scale()
	var x := size.x - m - safe.z if _lefty() else m + safe.x
	return Vector2(x, size.y - m - safe.w)


func attack_center() -> Vector2:
	var m := 110.0 * _scale()
	var x := m + safe.x if _lefty() else size.x - m - safe.z
	return Vector2(x, size.y - m - safe.w)


func sprint_center() -> Vector2:
	var a := attack_center()
	var dx := 150.0 * _scale()
	return a + Vector2(dx if _lefty() else -dx, 30.0 * _scale())


func _attack_r() -> float:
	return 62.0 * _scale()


func _sprint_r() -> float:
	return 46.0 * _scale()


# ---------------------------------------------------------------- ввод

func _input(event: InputEvent) -> void:
	if preview or not active or not visible:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)


func _on_touch(e: InputEventScreenTouch) -> void:
	var p := e.position
	if e.pressed:
		_forget(e.index)  # повторное «нажал» без «отпустил» (потерянное событие): старый след палца не должен липнуть
		if pause_rect.grow(10).has_point(p):
			pause_pressed.emit()
			_handled()
			return
		if p.distance_to(attack_center()) < _attack_r() * 1.2:
			_fire()
			_handled()
			return
		if p.distance_to(sprint_center()) < _sprint_r() * 1.25:
			_sprint_index = e.index
			_update_outputs()
			_handled()
			return
		_touch_start[e.index] = [_time, p]  # касание не по кнопке — может оказаться тапом
		if Settings.choice("touch_scheme") == 1:
			if _finger_index < 0:
				_finger_index = e.index
				_finger_pos = p
		elif _stick_side_has(p) and _stick_index < 0:
			_stick_index = e.index
			_stick_center = p if Settings.flag("stick_floating") else _fixed_center()
			_stick_pos = p
		_handled()
	else:
		if _touch_start.has(e.index):
			var start: Array = _touch_start[e.index]
			_touch_start.erase(e.index)
			if not e.canceled and _time - float(start[0]) < TAP_TIME and p.distance_to(start[1]) < 24.0:
				if _time - _last_tap < DOUBLE_TAP and Settings.flag("double_tap_attack"):
					_fire()
					_last_tap = -10.0
				else:
					_last_tap = _time
		_forget(e.index)
	_update_outputs()


## Палец с этим номером больше ничего не держит.
func _forget(index: int) -> void:
	if index == _stick_index:
		_stick_index = -1
	if index == _finger_index:
		_finger_index = -1
	if index == _sprint_index:
		_sprint_index = -1
	_touch_start.erase(index)


func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _stick_index:
		_stick_pos = e.position
	elif e.index == _finger_index:
		_finger_pos = e.position
	elif e.index == _sprint_index and e.position.distance_to(sprint_center()) > _sprint_r() * 2.2:
		_sprint_index = -1  # палец уехал с кнопки
	_update_outputs()
	_handled()


func _handled() -> void:
	get_viewport().set_input_as_handled()


func _fire() -> void:
	_attack_flash = 1.0
	attack_pressed.emit()


func _update_outputs() -> void:
	steer = Vector2.ZERO
	var edge_sprint := false
	if _stick_index >= 0:
		var v := (_stick_pos - _stick_center) / STICK_R
		if v.length() > 1.0:
			if Settings.flag("stick_floating"):  # плавающий стик подтягивается за пальцем
				_stick_center = _stick_pos - v.normalized() * STICK_R
			v = v.normalized()
		if v.length() > DEADZONE:
			steer = v.normalized() * Settings.num("turn_sensitivity")
		edge_sprint = v.length() >= SPRINT_EDGE
	elif _finger_index >= 0 and head_screen.x >= 0.0:
		var d := _finger_pos - head_screen
		if d.length() > 24.0:
			steer = d.normalized()
	sprint_held = _sprint_index >= 0 or edge_sprint


func _process(delta: float) -> void:
	_time += delta
	if preview:
		_animate_preview(delta)
	_attack_flash = maxf(_attack_flash - delta * 4.0, 0.0)
	if _finger_index >= 0:
		_update_outputs()  # змея движется — направление к пальцу меняется
	if visible:
		queue_redraw()


# ---------------------------------------------------------------- витрина

## Витрина для экрана настроек: стик ходит по кругу, стамина качается, атака мигает. Раскладка, размер,
## прозрачность, рука и схема берутся из настроек на лету — кнопки стоят там же, где будут в забеге.
func start_preview() -> void:
	preview = true
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	ability_type = 2
	ability_charges = 3
	_stick_index = 90
	_finger_index = 91


func _animate_preview(delta: float) -> void:
	var a := _time * 1.5
	_stick_center = _fixed_center()
	_stick_pos = _stick_center + Vector2.from_angle(a) * STICK_R * 0.8
	_finger_pos = Vector2(size.x * 0.5, size.y * 0.5) + Vector2.from_angle(a) * 110.0
	stamina = 0.6 + 0.35 * sin(_time * 0.8)
	_pulse_t -= delta
	if _pulse_t <= 0.0:
		_pulse_t = 2.4
		_attack_flash = 1.0


# ---------------------------------------------------------------- рисование

func _draw() -> void:
	if not active and not preview:
		return
	var a := Settings.num("button_opacity")
	var s := _scale()
	# пауза
	if pause_rect.size.x > 0.0:
		var pc := pause_rect.get_center()
		_arcade(pc, pause_rect.size.x / 2.0 - 3.0, Color(0.22, 0.15, 0.1), false, a)
		Icons.pause(self, pc, Color(Design.CREAM, a), 0.9)
	# стик
	if Settings.choice("touch_scheme") == 0:
		var shown := _stick_index >= 0 or not Settings.flag("stick_floating")
		var c := _stick_center if _stick_index >= 0 else _fixed_center()
		var ka := a if _stick_index >= 0 else a * 0.45
		if shown:  # аркадный стик: латунная шайба-ограничитель, шток и шарик
			draw_circle(c, STICK_R + 8.0, Color(0, 0, 0, 0.35 * ka))
			draw_arc(c, STICK_R + 6.0, 0, TAU, 48, Color(Design.BRASS, 0.55 * ka), 4.0)
			draw_arc(c, STICK_R + 3.0, 0, TAU, 48, Color(0.05, 0.03, 0.02, 0.5 * ka), 2.0)
			draw_circle(c, 16.0, Color(0.1, 0.07, 0.05, 0.8 * ka))
			var knob := c
			if _stick_index >= 0:
				knob = c + (_stick_pos - c).limit_length(STICK_R)
			var edge := sprint_held and _sprint_index < 0
			draw_line(c, knob, Color(0.2, 0.21, 0.24, 0.9 * ka), 12.0)
			draw_line(c, knob, Color(0.75, 0.77, 0.8, 0.7 * ka), 4.0)
			var ball := Design.YOLK if edge else Design.TOMATO
			draw_circle(knob + Vector2(3, 6), 32.0, Color(0, 0, 0, 0.3 * ka))
			draw_circle(knob, 32.0, Color(ball.darkened(0.45), 0.95 * ka))
			draw_circle(knob + Vector2(-2, -2), 28.0, Color(ball, 0.95 * ka))
			draw_circle(knob + Vector2(-9, -10), 11.0, Color(1, 1, 1, 0.35 * ka))
			draw_circle(knob + Vector2(-11, -12), 4.0, Color(1, 1, 1, 0.7 * ka))
		elif _stick_index < 0:  # подсказка, где стик
			var hint := _fixed_center()
			draw_arc(hint, STICK_R * 0.6, 0, TAU, 40, Color(Design.CREAM, 0.12 * a), 2.0)
	elif _finger_index >= 0:
		draw_arc(_finger_pos, 30.0, 0, TAU, 32, Color(Design.YOLK, 0.7 * a), 3.0)
	# спринт: кольцо стамины вокруг кнопки
	var sc := sprint_center()
	var sr := _sprint_r()
	var held := _sprint_index >= 0
	_arcade(sc, sr, Design.YOLK_DEEP, held, a)
	draw_arc(sc, sr + 6.0, 0, TAU, 40, Color(0, 0, 0, 0.4 * a), 5.0)
	draw_arc(sc, sr + 6.0, -PI / 2, -PI / 2 + TAU * stamina, 40, Color(Design.MINT, a), 4.0)
	Icons.bolt(self, sc, Color(Design.INK if held else Design.CREAM, a), s * 1.1)
	# атака
	var ac := attack_center()
	var ar := _attack_r()
	var ready := ability_type >= 0 and ability_charges > 0
	var base := Color(0.22, 0.15, 0.1).lerp(Design.MINT.darkened(0.35), 0.8 if ready else 0.0)
	_arcade(ac, ar, base.lerp(Color.WHITE, _attack_flash * 0.4), _attack_flash > 0.5, a)
	if ready:
		Icons.ability(self, ac + Vector2(-4, -6) * s, ability_type, _time, s * 1.5)
		var shown := mini(ability_charges, 8)  # заряды — лампами, как на табло (дизайн-язык 2.2)
		var step := 12.0 * s
		Design.draw_lamps(self, ac + Vector2(-(shown - 1) * step / 2.0, ar * 0.62), ability_charges, ability_charges,
			Design.MINT, 4.0 * s, step)
	else:
		var f2 := Design.font("heavy")
		var txt := "АТАКА"
		var w := f2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(f2, ac + Vector2(-w / 2.0, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Design.FAINT, a))


## Аркадная кнопка: латунный ободок, боковина колпачка и выпуклый колпачок с бликом.
## Нажатая опускается — боковина прячется, блик тускнеет.
func _arcade(c: Vector2, r: float, col: Color, pressed: bool, a: float) -> void:
	var travel := 1.5 if pressed else 6.0
	draw_circle(c + Vector2(0, 4), r + 7.0, Color(0, 0, 0, 0.35 * a))
	draw_circle(c, r + 6.0, Color(0.42, 0.27, 0.08, 0.95 * a))
	draw_circle(c + Vector2(-1, -1), r + 4.5, Color(Design.BRASS, 0.95 * a))
	draw_circle(c, r + 1.5, Color(0.05, 0.03, 0.02, 0.9 * a))
	var face := c - Vector2(0, travel - 1.5)
	draw_circle(c + Vector2(0, 1), r, Color(col.darkened(0.55), 0.95 * a))  # боковина
	draw_circle(face, r - 1.0, Color(col.darkened(0.12), 0.95 * a))
	draw_circle(face + Vector2(-r * 0.12, -r * 0.14), r * 0.72, Color(col.lightened(0.12), 0.9 * a))
	draw_circle(face + Vector2(-r * 0.35, -r * 0.4), r * 0.22, Color(1, 1, 1, (0.18 if pressed else 0.4) * a))
