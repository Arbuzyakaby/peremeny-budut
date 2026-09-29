extends Node2D
## Рисунки змеи на полу в «Контакте» (v10.0): каждый знак остаётся на полу до конца режима,
## поверх — следы пуль в финале. Лежит под сущностями (z 0, после арены), рисуется кодом.

const MAX_STROKES := 40

var strokes: Array = []  # {"pts": PackedVector2Array, "color": Color}
var marks: Array[Vector2] = []  # выбоины от пуль


## Новый рисунок; точки добавляются по мере того, как змея ползёт (extend).
func begin(color: Color) -> void:
	strokes.append({"pts": PackedVector2Array(), "color": color})
	if strokes.size() > MAX_STROKES:
		strokes.pop_front()


func extend(p: Vector2) -> void:
	if strokes.is_empty():
		return
	var pts: PackedVector2Array = strokes[strokes.size() - 1]["pts"]
	if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 3.0:
		pts.append(p)
		strokes[strokes.size() - 1]["pts"] = pts
		queue_redraw()


func add_mark(p: Vector2) -> void:
	marks.append(p)
	queue_redraw()


func _draw() -> void:
	for s: Dictionary in strokes:
		var pts: PackedVector2Array = s["pts"]
		if pts.size() < 2:
			continue
		var c: Color = s["color"]
		draw_polyline(pts, Color(0, 0, 0, 0.25), 13.0, true)  # вдавленная борозда
		draw_polyline(pts, Color(c, 0.75), 8.0, true)
		draw_polyline(pts, Color(c.lightened(0.5), 0.6), 3.0, true)
	for m in marks:
		draw_circle(m, 7.0, Color(0.05, 0.04, 0.03, 0.8))
		draw_arc(m, 9.0, 0, TAU, 10, Color(0.6, 0.55, 0.45, 0.5), 2.0)
