extends Node2D
## Половинка скорлупки раскрытой матрёшки: верх (голова в платке) или низ (сарафан с фартуком)
## разлетаются, крутятся, стукаются об пол и тают. Чистая картинка — никого не ранит.

const Matryoshka = preload("res://scripts/entities/matryoshka.gd")

const LIFE := 0.9

var top := true
var dress := Color.RED
var head_scarf := Color.YELLOW
var k := 1.0          # масштаб куклы
var vel := Vector2.ZERO
var spin := 0.0
var life := LIFE
var lift := 0.0       # подброс верхней половинки


func setup(pos: Vector2, is_top: bool, doll_dress: Color, doll_scarf: Color, doll_scale: float, dir: Vector2) -> void:
	position = pos
	top = is_top
	dress = doll_dress
	head_scarf = doll_scarf
	k = doll_scale
	vel = dir * randf_range(160.0, 240.0)
	spin = randf_range(-7.0, 7.0)
	z_index = 1


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	position += vel * delta
	vel = vel.move_toward(Vector2.ZERO, 380.0 * delta)
	rotation += spin * delta
	spin = move_toward(spin, 0.0, 6.0 * delta)
	var f := 1.0 - life / LIFE
	lift = sin(clampf(f * 1.6, 0.0, 1.0) * PI) * 26.0 * k if top else 0.0
	modulate.a = clampf(life / 0.35, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, -lift), 0.0, Vector2.ONE * k)
	var outline := dress.darkened(0.6)
	var inside := Color(0.62, 0.42, 0.24)  # светлое дерево изнутри
	if top:
		draw_circle(Vector2(0, -12), 15.0, outline)
		draw_circle(Vector2(0, -12), 13.5, head_scarf)
		draw_colored_polygon(PackedVector2Array([Vector2(-11.5, -8), Vector2(11.5, -8), Vector2(17, -1), Vector2(-17, -1)]), dress)
		draw_circle(Vector2(0, -11), 9.0, Matryoshka.SKIN)
		for sd in [-1.0, 1.0]:
			draw_circle(Vector2(sd * 3.4, -11.5), 1.5, Matryoshka.INK)
			draw_circle(Vector2(sd * 5.2, -8.2), 2.2, Color(0.95, 0.45, 0.45, 0.7))
		draw_set_transform(Vector2(0, -lift), 0.0, Vector2(k, k * 0.35))
		draw_circle(Vector2(0, -1.0 / 0.35), 16.0, inside.darkened(0.25))  # полость снизу
	else:
		draw_circle(Vector2(0, 7), 22.5, outline)
		draw_circle(Vector2(0, 7), 21.0, dress)
		draw_circle(Vector2(0, 11), 13.0, Color(0.99, 0.95, 0.84))
		draw_circle(Vector2(0, 11), 2.8, Matryoshka.GOLD)
		draw_set_transform(Vector2(0, -2.0 * k), 0.0, Vector2(k, k * 0.38))
		draw_circle(Vector2.ZERO, 19.0, inside)       # срез: светлое дерево
		draw_circle(Vector2.ZERO, 15.0, inside.darkened(0.45))  # и полость, где сидела следующая
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
