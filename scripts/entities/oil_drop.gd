extends Node2D
## Снаряд: капля масла (урон), капля белка (замедляет), перчинка (самонаводится, урон),
## пуговица медведя-метателя (урон), иголка с пуговицей медведя-швеи (урон + пришивает — замедляет),
## сюрикен ниндзя (урон) и хлопушка (катится, тормозит и взрывается, когда догорит фитиль).
## Эти же снаряды может выпускать змея, съевшая такого медведя (from_snake).

const Tex = preload("res://scripts/gfx/tex.gd")

enum Kind { OIL, WHITE, PEPPER, BUTTON, NEEDLE, SHURIKEN, CRACKER }

const RADIUS := 9.0
const PEPPER_TURN := 2.2
const BLAST_RADIUS := 95.0

var vel := Vector2.ZERO
var kind := Kind.OIL
var life := 6.0
var spin := 0.0
var fuse := 0.0
var button_color := Color(0.3, 0.55, 0.95)
var thrower: Node2D = null  # медведь, кинувший снаряд (в него самого он не попадает)
var from_snake := false


func setup(pos: Vector2, velocity: Vector2, drop_kind: int) -> void:
	position = pos
	vel = velocity
	kind = drop_kind as Kind
	rotation = vel.angle()
	if kind == Kind.PEPPER:
		life = 4.5
	elif kind == Kind.BUTTON or kind == Kind.NEEDLE or kind == Kind.SHURIKEN:
		life = 3.5
		button_color = [Color(0.3, 0.55, 0.95), Color(0.9, 0.3, 0.35), Color(0.95, 0.8, 0.2)].pick_random()
	elif kind == Kind.CRACKER:
		fuse = 1.3
		life = 99.0
		button_color = [Color(0.95, 0.3, 0.5), Color(0.3, 0.7, 0.95), Color(0.6, 0.9, 0.3)].pick_random()


## Хлопушка догорела и должна взорваться.
func should_explode() -> bool:
	return kind == Kind.CRACKER and fuse <= 0.0


func update(delta: float, target: Vector2) -> void:
	if kind == Kind.PEPPER:
		var ang := rotate_toward(vel.angle(), (target - position).angle(), PEPPER_TURN * delta)
		vel = Vector2.from_angle(ang) * vel.length()
	if kind == Kind.CRACKER:
		vel = vel.move_toward(Vector2.ZERO, 420.0 * delta)
		fuse -= delta
		var inner := Rect2(24, 24, 1232, 672).grow(-RADIUS)
		if position.x < inner.position.x or position.x > inner.end.x:
			vel.x = -vel.x * 0.6
		if position.y < inner.position.y or position.y > inner.end.y:
			vel.y = -vel.y * 0.6
		position = position.clamp(inner.position, inner.end)
	position += vel * delta
	life -= delta
	spin += delta * (22.0 if kind == Kind.SHURIKEN else 12.0)
	match kind:
		Kind.BUTTON, Kind.SHURIKEN:
			rotation = spin
		Kind.CRACKER:
			rotation = vel.angle() if vel.length() > 20.0 else rotation
		_:
			rotation = vel.angle()
	queue_redraw()


func _draw() -> void:
	var glow := Color(1, 0.8, 0.3, 0.3)
	match kind:
		Kind.WHITE:
			glow = Color(1, 1, 1, 0.3)
		Kind.PEPPER:
			glow = Color(1, 0.2, 0.1, 0.35)
		Kind.NEEDLE, Kind.SHURIKEN:
			glow = Color(0.85, 0.9, 1, 0.25)
		Kind.BUTTON:
			glow = Color(button_color, 0.25)
	if from_snake:  # снаряды змеи подсвечены зелёным
		glow = Color(0.4, 1, 0.4, 0.4)
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	Tex.blob(self, Vector2(4, 6), Vector2.ONE * RADIUS * 1.3, Color(0, 0, 0, 0.18))
	Tex.blob(self, Vector2.ZERO, Vector2.ONE * RADIUS * 2.6, glow)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match kind:
		Kind.OIL, Kind.WHITE:
			var fill := Color(0.98, 0.78, 0.2, 0.92) if kind == Kind.OIL else Color(1, 1, 1, 0.95)
			var edge := Color(0.6, 0.4, 0.05) if kind == Kind.OIL else Color(0.6, 0.6, 0.6)
			draw_colored_polygon(PackedVector2Array([Vector2(-RADIUS * 2.2, 0), Vector2(0, -RADIUS), Vector2(0, RADIUS)]), edge)
			draw_circle(Vector2.ZERO, RADIUS + 1.5, edge)
			draw_colored_polygon(PackedVector2Array([Vector2(-RADIUS * 1.9, 0), Vector2(0, -RADIUS + 1.5), Vector2(0, RADIUS - 1.5)]), fill)
			draw_circle(Vector2.ZERO, RADIUS, fill)
			draw_circle(Vector2(1, 1.5), RADIUS * 0.6, fill.darkened(0.08))
			draw_circle(Vector2(2, -3), 2.5, Color(1, 1, 1, 0.85))
			draw_circle(Vector2(-4, -1), 1.3, Color(1, 1, 1, 0.5))
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
			draw_line(Vector2(-4, -3), Vector2(8, -3), Color(1, 1, 1, 0.55), 1.8)
			for k in 3:  # огненный шлейф
				Tex.blob(self, Vector2(-20.0 - k * 7.0, 0), Vector2.ONE * (6.0 - k * 1.5), Color(1, 0.5, 0.1, 0.5 - k * 0.15))
		Kind.BUTTON:
			draw_circle(Vector2.ZERO, RADIUS + 1.5, button_color.darkened(0.45))
			draw_circle(Vector2.ZERO, RADIUS, button_color)
			draw_circle(Vector2(-1, -1), RADIUS * 0.75, button_color.lightened(0.12))
			draw_arc(Vector2.ZERO, RADIUS - 3.0, 0, TAU, 16, button_color.darkened(0.25), 1.5)
			for d in [Vector2(-2.5, -2.5), Vector2(2.5, -2.5), Vector2(-2.5, 2.5), Vector2(2.5, 2.5)]:
				draw_circle(d, 1.4, button_color.darkened(0.55))
			draw_line(Vector2(-2.5, -2.5), Vector2(2.5, 2.5), Color(0.95, 0.9, 0.8), 1.0)  # нитка крест-накрест
			draw_line(Vector2(2.5, -2.5), Vector2(-2.5, 2.5), Color(0.95, 0.9, 0.8), 1.0)
		Kind.NEEDLE:
			var thread := PackedVector2Array()
			for i in 8:  # нитка тянется за иголкой
				thread.append(Vector2(-14.0 - i * 5.0, sin(spin * 1.5 + i * 0.9) * (1.0 + i * 0.5)))
			draw_polyline(thread, Color(0.9, 0.15, 0.3, 0.8), 1.5)
			draw_line(Vector2(-12, 0), Vector2(14, 0), Color(0.45, 0.47, 0.52), 3.5)
			draw_line(Vector2(-12, -0.5), Vector2(14, -0.5), Color(0.92, 0.94, 0.98), 1.6)
			draw_colored_polygon(PackedVector2Array([Vector2(14, -1.5), Vector2(20, 0), Vector2(14, 1.5)]), Color(0.88, 0.9, 0.95))
			draw_circle(Vector2(-12, 0), 5.5, button_color.darkened(0.45))
			draw_circle(Vector2(-12, 0), 4.5, button_color)
			draw_circle(Vector2(-12, 0), 1.2, button_color.darkened(0.55))
		Kind.SHURIKEN:
			var pts := PackedVector2Array()
			for i in 8:
				var r := 12.0 if i % 2 == 0 else 4.0
				pts.append(Vector2.from_angle(TAU * i / 8.0) * r)
			draw_colored_polygon(pts, Color(0.25, 0.27, 0.32))
			var inner := PackedVector2Array()
			for p in pts:
				inner.append(p * 0.75 + Vector2(-0.8, -0.8))
			draw_colored_polygon(inner, Color(0.7, 0.73, 0.8))
			draw_circle(Vector2.ZERO, 2.2, Color(0.15, 0.15, 0.18))
		Kind.CRACKER:
			var blink := fuse < 0.5 and int(fuse * 16.0) % 2 == 0
			var body := Rect2(-11, -6, 22, 12)
			draw_rect(body.grow(1.5), button_color.darkened(0.5))
			draw_rect(body, Color.WHITE if blink else button_color)
			for k in 3:  # полоски обёртки
				draw_line(Vector2(-7 + k * 7, -6), Vector2(-4 + k * 7, 6), button_color.lightened(0.45), 2.5)
			draw_rect(Rect2(-11, -6, 22, 3), Color(1, 1, 1, 0.3))
			var tip := Vector2(-11, 0) + Vector2(-6, -4)
			draw_line(Vector2(-11, 0), tip, Color(0.3, 0.25, 0.2), 1.6)  # фитиль
			if fuse > 0.0:
				Tex.blob(self, tip, Vector2.ONE * (5.0 + 2.0 * sin(spin * 3.0)), Color(1, 0.8, 0.3, 0.9))
				draw_circle(tip, 1.8, Color(1, 1, 0.8))
