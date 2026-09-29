extends "res://scripts/ui/screens/screen.gd"
## Повтор гибели: запись «камеры наблюдения» лаборатории над ящиком. Последние секунды забега
## проигрываются замедленно на зелёном мониторе со строками развёртки; в конце пульсирует кольцо
## вокруг того, что нанесло удар, а снизу — совет, как этого избежать.

const Replay = preload("res://scripts/game/replay.gd")
const Tips = preload("res://scripts/core/tips.gd")

const SPEED := 0.4          # замедление
const HOLD := 1.4           # пауза на последнем кадре, потом по кругу
const MONITOR := Vector2(640, 360)
const PHOSPHOR := Color(0.55, 1.0, 0.62)

var replay: Replay
var monitor: Control
var cause_label: Label
var tip_label: Label
var t := 0.0


func build() -> void:
	make_frame(Design.SPACE[3])
	title("ЗАПИСЬ КАМЕРЫ №3", "h2")
	monitor = Control.new()
	monitor.custom_minimum_size = MONITOR
	monitor.draw.connect(_draw_monitor)
	content.add_child(monitor)
	cause_label = Design.label("", "h3", Design.TOMATO, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(cause_label)
	tip_label = Design.label("", "small", Design.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(MONITOR.x, 0)
	content.add_child(tip_label)
	var row := Design.hbox(Design.SPACE[4])
	content.add_child(row)
	row.add_child(Design.button("СНАЧАЛА", restart, "", Vector2(200, Design.TOUCH_MIN)))
	first_focus = Design.button("НАЗАД", func() -> void: closed.emit(), "Primary", Vector2(200, Design.TOUCH_MIN))
	row.add_child(first_focus)


func show_replay(r: Replay) -> void:
	replay = r
	cause_label.text = cause_title(r.cause)
	tip_label.text = "СОВЕТ: " + Tips.for_cause(r.cause)
	restart()


func restart() -> void:
	t = 0.0


static func cause_title(cause: String) -> String:
	match cause:
		"fork_tines":
			return "ЗУБЦЫ ВИЛКИ"
		"fork_whirl":
			return "ВЕРТУШКА"
		"fork_pogo":
			return "ПРЫЖОК-УКОЛ"
		"tine":
			return "ЗУБЕЦ ИЗ ЗАЛПА"
		"bear":
			return "УДАР МЕДВЕДЯ"
		"shot":
			return "СНАРЯД МЕДВЕДЯ"
		"blast":
			return "ВЗРЫВ ХЛОПУШКИ"
		"pill":
			return "РАЗДАВИЛА ТАБЛЕТКА"
		"doll":
			return "ПРИДАВИЛА МАЛЫШКА"
		"wave":
			return "УДАРНАЯ ВОЛНА"
		"boss", "oil":
			return "ЯИЧНИЦА"
		"wall":
			return "УДАР О БОРТИК"
		"self":
			return "УКУСИЛА СЕБЯ"
	return "ПРИЧИНА НЕИЗВЕСТНА"


func _process(delta: float) -> void:
	if not visible or replay == null:
		return
	t += delta * SPEED
	if t > replay.duration() + HOLD * SPEED:
		t = 0.0
	monitor.queue_redraw()


func _draw_monitor() -> void:
	var r := Rect2(Vector2.ZERO, MONITOR)
	monitor.draw_style_box(Design.box(Color(0.02, 0.06, 0.03), Color(0.12, 0.2, 0.12), Design.RADIUS_MD, 3, Vector2.ZERO), r)
	if replay == null or not replay.has_data():
		monitor.draw_string(Design.font("mono"), Vector2(24, MONITOR.y / 2.0), "НЕТ ЗАПИСИ", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 20, Color(PHOSPHOR, 0.7))
		return
	var k := MONITOR.x / 1280.0
	var f := replay.frame_at(t)
	var ended := t >= replay.duration() - 1.0 / Replay.RATE
	monitor.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	monitor.draw_rect(Rect2(24, 24, 1232, 672), Color(PHOSPHOR, 0.25), false, 4.0)  # бортик ящика
	for w: Array in f["waves"]:
		monitor.draw_arc(w[0], w[1], 0, TAU, 48, Color(PHOSPHOR, 0.35), 6.0)
	if f["boss"] != Vector2.INF:
		monitor.draw_circle(f["boss"], 150.0, Color(PHOSPHOR, 0.18))
		monitor.draw_circle(f["boss"] + Vector2(0, -10), 46.0, Color(PHOSPHOR, 0.4))
	for e: Array in f["enemies"]:
		match e[0]:
			"bear":
				monitor.draw_circle(e[1], 18.0, Color(PHOSPHOR, 0.55))
				monitor.draw_circle(e[1] + Vector2(-12, -14), 7.0, Color(PHOSPHOR, 0.55))
				monitor.draw_circle(e[1] + Vector2(12, -14), 7.0, Color(PHOSPHOR, 0.55))
			"fork":
				var dir := Vector2.from_angle(e[2])
				monitor.draw_line(e[1] - dir * 60.0, e[1] + dir * 20.0, Color(PHOSPHOR, 0.7), 8.0)
				for i in 4:
					var off := dir.orthogonal() * (-12.0 + i * 8.0)
					monitor.draw_line(e[1] + dir * 20.0 + off, e[1] + dir * 54.0 + off, Color(PHOSPHOR, 0.9), 3.0)
			"pill":
				var lift := Vector2(0, -float(e[2]))
				monitor.draw_circle(e[1], 16.0, Color(0, 0, 0, 0.5))
				monitor.draw_circle(e[1] + lift, 24.0, Color(PHOSPHOR, 0.6))
			"doll":  # матрёшка: низ и голова
				var up := Vector2(0, -float(e[2]))
				var dr := float(e[3])
				monitor.draw_circle(e[1] + up + Vector2(0, dr * 0.25), dr, Color(PHOSPHOR, 0.6))
				monitor.draw_circle(e[1] + up - Vector2(0, dr * 0.55), dr * 0.62, Color(PHOSPHOR, 0.8))
	for d: Array in f["drops"]:
		monitor.draw_circle(d[0], 8.0, Color(PHOSPHOR, 0.5 if d[2] else 0.95))
	var body: PackedVector2Array = f["body"]
	if body.size() > 1:
		monitor.draw_polyline(body, Color(PHOSPHOR, 0.8), 18.0)
	monitor.draw_circle(f["head"], 16.0, Color(1, 0.4, 0.35) if f["hurt"] else PHOSPHOR)
	if ended and replay.source != Vector2.INF:  # что нанесло удар
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		monitor.draw_arc(replay.source, 48.0 + 14.0 * pulse, 0, TAU, 40, Color(1, 0.35, 0.3, 0.9), 6.0)
		monitor.draw_line(f["head"], replay.source, Color(1, 0.35, 0.3, 0.5), 3.0)
	monitor.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for y in range(0, int(MONITOR.y), 3):  # строки развёртки
		monitor.draw_line(Vector2(0, y), Vector2(MONITOR.x, y), Color(0, 0, 0, 0.22), 1.0)
	var mono := Design.font("mono")
	var clock := "REC  00:%05.2f  ×%.1f" % [t, SPEED]
	monitor.draw_string(mono, Vector2(14, 24), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(PHOSPHOR, 0.85))
	if int(Time.get_ticks_msec() / 500) % 2 == 0:
		monitor.draw_circle(Vector2(MONITOR.x - 22, 18), 6.0, Color(1, 0.25, 0.2))
	monitor.draw_string(mono, Vector2(14, MONITOR.y - 12), "ОБЪЕКТ: ЗМЕЯ  •  ЯЩИК №1", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 12, Color(PHOSPHOR, 0.6))
