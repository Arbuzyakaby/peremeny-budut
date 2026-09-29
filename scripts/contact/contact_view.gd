extends Node2D
## Слой «Контакта» над сущностями (v10.0): знаки над врагами (сердечко — убеждён, дуга — доверие,
## «!» — сам идёт поговорить, «…» — вестник), кольцо вокруг того, с кем можно заговорить,
## светящийся контур знака и обводка игрока. Здесь же ввод обводки мышью и пальцем.

const Design = preload("res://scripts/ui/design.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Gesture = preload("res://scripts/contact/gesture.gd")

var contact  # contact_mode.gd
var touch_index := -1


func _process(_delta: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	if contact == null or contact.phase != contact.Phase.TRACE:
		return
	match contact.trace_mode:
		"mouse":
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
					and event.device != InputEvent.DEVICE_ID_EMULATION:
				if event.pressed:
					contact.add_trace_point(get_global_mouse_position())
				else:
					contact.end_stroke()
			elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT \
					and event.device != InputEvent.DEVICE_ID_EMULATION:
				contact.add_trace_point(get_global_mouse_position())
		"touch":
			if event is InputEventScreenTouch:
				var p := _world(event.position)
				if event.pressed and touch_index < 0 and Gesture.dist_to(p, contact.tmpl) < 170.0:
					touch_index = event.index
					contact.add_trace_point(p)
				elif not event.pressed and event.index == touch_index:
					touch_index = -1
					contact.end_stroke()
			elif event is InputEventScreenDrag and event.index == touch_index:
				contact.add_trace_point(_world(event.position))


func _world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func _draw() -> void:
	if contact == null:
		return
	var t: float = contact.t
	var f := Design.font("heavy")
	for e: Dictionary in contact.entries:
		var node: Node2D = e["node"]
		if not is_instance_valid(node) or e.get("dead", false):
			continue
		var top: Vector2 = node.position + Vector2(0, -float(e["r"]) - 14.0)
		if e["convinced"]:
			var bob := sin(t * 3.0 + node.get_instance_id() % 7) * 2.0
			if contact.peace.is_herald(node):
				for k in 3:
					draw_circle(top + Vector2(-8 + k * 8, bob), 2.6, Color(1, 1, 1, 0.5 + 0.5 * sin(t * 6.0 - k)))
			elif not e["protected"] or contact.phase != contact.Phase.FINALE:
				Icons.heart(self, top + Vector2(0, bob), 6.5, Color(contact.COLORS[e["kind"]], 0.9))
			if e["protected"]:  # швея — со своей ниточкой-меткой
				draw_arc(top + Vector2(0, bob), 10.0, 0.0, TAU, 14, Color(1, 1, 1, 0.5), 1.5)
			continue
		var trust: float = e["trust"]
		draw_arc(top, 9.0, 0.0, TAU, 18, Color(0, 0, 0, 0.35), 3.5)
		if trust > 0.01:
			draw_arc(top, 9.0, -PI / 2.0, -PI / 2.0 + TAU * trust, 18, Color(0.6, 1, 0.6, 0.9), 3.0)
		var mark := "!" if trust >= contact.peace.LEAD_TRUST else "?"
		if float(e.get("scared", 0.0)) > 0.0:
			mark = "!!"
		draw_string_outline(f, top + Vector2(-5, 6), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
		draw_string(f, top + Vector2(-5, 6), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	# с кем можно заговорить
	var cand: Dictionary = contact.candidate
	if contact.phase == contact.Phase.ROAM and not cand.is_empty() and is_instance_valid(cand["node"]):
		var r: float = float(cand["r"]) + 12.0 + 3.0 * sin(t * 6.0)
		draw_arc(cand["node"].position, r, 0.0, TAU, 40, Color(contact.COLORS[cand["kind"]], 0.8), 3.0)
	if contact.phase == contact.Phase.TRACE:
		_draw_template(t, f)


## Светящийся контур знака, обводка игрока и кисть (на клавиатуре).
func _draw_template(t: float, f: Font) -> void:
	var tmpl: PackedVector2Array = contact.tmpl
	if tmpl.size() < 2:
		return
	var col: Color = contact.COLORS[contact.talking.get("kind", "bear")]
	var tol: float = contact.tol()
	var pulse := 0.6 + 0.4 * sin(t * 5.0)
	draw_polyline(tmpl, Color(col, 0.12), tol * 2.0, true)  # коридор допуска
	for i in range(0, tmpl.size() - 1, 2):  # пунктир контура
		draw_line(tmpl[i], tmpl[i + 1], Color(col, 0.55 + 0.35 * pulse), 4.0, true)
	var trace: PackedVector2Array = contact.trace
	if trace.size() >= 2:
		draw_polyline(trace, Color(0, 0, 0, 0.35), 9.0, true)
		draw_polyline(trace, Color(1, 1, 1, 0.95), 5.0, true)
	if contact.trace_mode == "keys":
		var b: Vector2 = contact.brush_pos()
		draw_circle(b, 11.0, Color(0, 0, 0, 0.4))
		draw_circle(b, 8.0, Color.WHITE)
		var on_line := Gesture.dist_to(b, tmpl) <= tol
		draw_arc(b, 15.0, 0.0, TAU, 20, Color(0.6, 1, 0.6) if on_line else Color(1, 0.4, 0.3), 3.0)
	# подпись: какой знак и сколько обведено, полоска времени
	var top := Vector2(INF, INF)
	var left := INF
	var right := -INF
	for p in tmpl:
		top.y = minf(top.y, p.y)
		left = minf(left, p.x)
		right = maxf(right, p.x)
	var cx := (left + right) / 2.0
	var cov := int(float(contact.live.get("coverage", 0.0)) * 100.0)
	var label := "%s  %d%%" % [Gesture.NAMES.get(contact.talking.get("kind", ""), ""), cov]
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var at := Vector2(cx - w / 2.0, maxf(top.y - 22.0, 40.0))
	draw_string_outline(f, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.8))
	draw_string(f, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col.lightened(0.3))
	var left_k := 1.0 - clampf(contact.trace_t / contact.TRACE_TIME, 0.0, 1.0)
	var bar := Rect2(Vector2(cx - 60.0, at.y + 8.0), Vector2(120.0, 5.0))
	draw_rect(bar, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * left_k, bar.size.y)), Color(col, 0.9))
