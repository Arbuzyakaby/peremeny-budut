extends Node2D
## Снаряд: капля масла (урон), капля белка (замедляет), перчинка (самонаводится, урон)
## пуговица медведя-метателя (урон) или иголка с пуговицей медведя-швеи (урон + пришивает — замедляет).
## Эти же пуговицы и иголки может выпускать змея, съевшая такого медведя (from_snake).

enum Kind { OIL, WHITE, PEPPER, BUTTON, NEEDLE }

const RADIUS := 9.0
const PEPPER_TURN := 2.2

var vel := Vector2.ZERO
var kind := Kind.OIL
var life := 6.0
var spin := 0.0
var button_color := Color(0.3, 0.55, 0.95)
var thrower: Node2D = null  # медведь, кинувший пуговицу (в него самого она не попадает)
var from_snake := false


func setup(pos: Vector2, velocity: Vector2, drop_kind: int) -> void:
	position = pos
	vel = velocity
	kind = drop_kind as Kind
	rotation = vel.angle()
	if kind == Kind.PEPPER:
		life = 4.5
	elif kind == Kind.BUTTON or kind == Kind.NEEDLE:
		life = 3.5
		button_color = [Color(0.3, 0.55, 0.95), Color(0.9, 0.3, 0.35), Color(0.95, 0.8, 0.2)].pick_random()


func update(delta: float, target: Vector2) -> void:
	if kind == Kind.PEPPER:
		var ang := rotate_toward(vel.angle(), (target - position).angle(), PEPPER_TURN * delta)
		vel = Vector2.from_angle(ang) * vel.length()
	position += vel * delta
	life -= delta
	spin += delta * 12.0
	rotation = spin if kind == Kind.BUTTON else vel.angle()
	if kind == Kind.NEEDLE:
		queue_redraw()
	if kind == Kind.PEPPER:
		queue_redraw()


func _draw() -> void:
	if from_snake:  # снаряды змеи подсвечены зелёным
		draw_circle(Vector2.ZERO, RADIUS + 6.0, Color(0.4, 1, 0.4, 0.3))
	match kind:
		Kind.OIL, Kind.WHITE:
			var fill := Color(0.98, 0.78, 0.2, 0.92) if kind == Kind.OIL else Color(1, 1, 1, 0.95)
			var edge := Color(0.6, 0.4, 0.05) if kind == Kind.OIL else Color(0.6, 0.6, 0.6)
			draw_colored_polygon(PackedVector2Array([Vector2(-RADIUS * 2.2, 0), Vector2(0, -RADIUS), Vector2(0, RADIUS)]), edge)
			draw_circle(Vector2.ZERO, RADIUS + 1.5, edge)
			draw_colored_polygon(PackedVector2Array([Vector2(-RADIUS * 1.9, 0), Vector2(0, -RADIUS + 1.5), Vector2(0, RADIUS - 1.5)]), fill)
			draw_circle(Vector2.ZERO, RADIUS, fill)
			draw_circle(Vector2(2, -3), 2.5, Color(1, 1, 1, 0.8))
		Kind.PEPPER:
			var blink := life < 1.0 and int(life * 10.0) % 2 == 0
			var red := Color(1, 1, 1) if blink else Color(0.9, 0.12, 0.1)
			var body := PackedVector2Array()
			for i in 16:
				var a := TAU * i / 16.0
				var w := 6.5 * (0.55 + 0.45 * cos(a * 0.5))  # к хвосту сужается
				body.append(Vector2(cos(a) * 13.0, sin(a) * w))
			draw_colored_polygon(body, red.darkened(0.35))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.85, 0.75))
			draw_colored_polygon(body, red)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_line(Vector2(-12, 0), Vector2(-18, -4), Color(0.2, 0.6, 0.15), 3.5)
			draw_circle(Vector2(4, -2), 1.8, Color(1, 1, 1, 0.7))
		Kind.BUTTON:
			draw_circle(Vector2.ZERO, RADIUS + 1.5, button_color.darkened(0.45))
			draw_circle(Vector2.ZERO, RADIUS, button_color)
			draw_arc(Vector2.ZERO, RADIUS - 3.0, 0, TAU, 16, button_color.darkened(0.2), 1.5)
			for d in [Vector2(-2.5, -2.5), Vector2(2.5, -2.5), Vector2(-2.5, 2.5), Vector2(2.5, 2.5)]:
				draw_circle(d, 1.4, button_color.darkened(0.55))
		Kind.NEEDLE:
			var thread := PackedVector2Array()
			for i in 8:  # нитка тянется за иголкой
				thread.append(Vector2(-14.0 - i * 5.0, sin(spin * 1.5 + i * 0.9) * (1.0 + i * 0.5)))
			draw_polyline(thread, Color(0.9, 0.15, 0.3, 0.8), 1.5)
			draw_line(Vector2(-12, 0), Vector2(14, 0), Color(0.45, 0.47, 0.52), 3.5)
			draw_line(Vector2(-12, 0), Vector2(14, 0), Color(0.88, 0.9, 0.95), 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(14, -1.5), Vector2(20, 0), Vector2(14, 1.5)]), Color(0.88, 0.9, 0.95))
			draw_circle(Vector2(-12, 0), 5.5, button_color.darkened(0.45))
			draw_circle(Vector2(-12, 0), 4.5, button_color)
			draw_circle(Vector2(-12, 0), 1.2, button_color.darkened(0.55))
