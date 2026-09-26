extends Node2D
## Ударная волна: расширяющееся кольцо.
## - от прыжка яичницы: наносит урон, в кольце есть проходы, в которые можно проскользнуть;
## - от приземления таблетки (stun): небольшая голубая волна без проходов, оглушает змею.

const Tex = preload("res://scripts/gfx/tex.gd")

const THICKNESS := 16.0
const GAP_HALF := 0.32

var radius := 40.0
var speed := 300.0
var max_radius := 820.0
var stun := false
var gaps: Array[float] = []
var hit_done := false
var t := 0.0


func setup(pos: Vector2, gap_count: int) -> void:
	position = pos
	var start := randf() * TAU
	for i in gap_count:
		gaps.append(start + TAU * i / gap_count)


func setup_stun(pos: Vector2, reach: float) -> void:
	position = pos
	stun = true
	radius = 20.0
	speed = 360.0
	max_radius = reach


func update(delta: float) -> void:
	t += delta
	radius += speed * delta
	queue_redraw()


func finished() -> bool:
	return radius > max_radius


func hits(p: Vector2) -> bool:
	if hit_done or absf(p.distance_to(position) - radius) > THICKNESS:
		return false
	var a := (p - position).angle()
	for g in gaps:
		if absf(angle_difference(a, g)) < GAP_HALF:
			return false
	return true


func _draw() -> void:
	var fade := clampf(1.0 - radius / max_radius, 0.0, 1.0)
	if stun:
		var r := radius + THICKNESS
		draw_texture_rect(Tex.ring(), Rect2(-Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0.45, 0.7, 1.0, 0.8 * fade))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(0.75, 0.9, 1.0, 0.9 * fade), 5.0)
		for i in 10:  # пыль, поднятая волной
			var a := TAU * i / 10.0 + t * 0.8
			Tex.blob(self, Vector2.from_angle(a) * radius, Vector2.ONE * 10.0, Color(0.9, 0.95, 1.0, 0.5 * fade))
		return
	for i in gaps.size():
		var a0 := gaps[i] + GAP_HALF
		var a1 := gaps[(i + 1) % gaps.size()] - GAP_HALF
		if a1 < a0:
			a1 += TAU
		draw_arc(Vector2.ZERO, radius, a0, a1, 64, Color(0.95, 0.55, 0.12, 0.18 * fade + 0.1), THICKNESS * 2.2)
		draw_arc(Vector2.ZERO, radius, a0, a1, 64, Color(0.95, 0.6, 0.15, 0.35 + 0.5 * fade), THICKNESS)
		draw_arc(Vector2.ZERO, radius, a0, a1, 64, Color(1, 0.95, 0.7, 0.3 + 0.6 * fade), 4.0)
