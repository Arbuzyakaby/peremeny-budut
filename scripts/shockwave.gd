extends Node2D
## Ударная волна от прыжка яичницы: расширяющееся кольцо с проходами, в которые можно проскользнуть.

const SPEED := 300.0
const MAX_RADIUS := 820.0
const THICKNESS := 16.0
const GAP_HALF := 0.32

var radius := 40.0
var gaps: Array[float] = []
var hit_done := false


func setup(pos: Vector2, gap_count: int) -> void:
	position = pos
	var start := randf() * TAU
	for i in gap_count:
		gaps.append(start + TAU * i / gap_count)


func update(delta: float) -> void:
	radius += SPEED * delta
	queue_redraw()


func finished() -> bool:
	return radius > MAX_RADIUS


func hits(p: Vector2) -> bool:
	if hit_done or absf(p.distance_to(position) - radius) > THICKNESS:
		return false
	var a := (p - position).angle()
	for g in gaps:
		if absf(angle_difference(a, g)) < GAP_HALF:
			return false
	return true


func _draw() -> void:
	var fade := clampf(1.0 - radius / MAX_RADIUS, 0.0, 1.0)
	for i in gaps.size():
		var a0 := gaps[i] + GAP_HALF
		var a1 := gaps[(i + 1) % gaps.size()] - GAP_HALF
		if a1 < a0:
			a1 += TAU
		draw_arc(Vector2.ZERO, radius, a0, a1, 64, Color(0.95, 0.6, 0.15, 0.35 + 0.5 * fade), THICKNESS)
		draw_arc(Vector2.ZERO, radius, a0, a1, 64, Color(1, 0.95, 0.7, 0.3 + 0.6 * fade), 4.0)
