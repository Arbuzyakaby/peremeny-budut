extends Node2D
## Ржавая вилка. Разворачивается к змее, прицеливается (дрожит, зубцы краснеют) и спринтует
## по прямой. Зубцы спереди опасны: атаковать вилку в лоб нельзя — только сбоку или сзади.
## Врезавшись в бортик, вилка на время застревает зубцами в дереве — лучший момент ударить.

signal sound(sound_name: String)

const Tex = preload("res://scripts/gfx/tex.gd")
const Design = preload("res://scripts/ui/design.gd")

enum St { ROAM, AIM, SPRINT, STUCK, RECOVER }

const TAIL := -46.0    # конец ручки (локально, вилка смотрит по +X)
const TIP := 40.0      # кончики зубцов
const TINES_FROM := 16.0
const HALF_WIDTH := 12.0
const SIZE := 1.35     # вилка крупнее своей базовой отрисовки

var st := St.ROAM
var st_t := 0.0
var bounds := Rect2(0, 0, 1280, 720)
var speed_mult := 1.0
var aggr := 1.0
var tempo := 1.0
var vel := Vector2.ZERO
var attack_cd := 1.5
var t := 0.0
var shake := 0.0
var hit_boss := false
var spawn_k := 0.0


func setup(pos: Vector2, area: Rect2, spd: float, aggression: float, idle_tempo: float) -> void:
	position = pos
	bounds = area
	speed_mult = spd
	aggr = aggression
	tempo = idle_tempo
	rotation = randf() * TAU
	attack_cd = randf_range(1.2, 2.2) * tempo
	material = Tex.material(Tex.Mat.RUST, randf() * 10.0)
	create_tween().tween_property(self, "spawn_k", 1.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func facing() -> Vector2:
	return Vector2.from_angle(rotation)


func is_sprinting() -> bool:
	return st == St.SPRINT


## Ближайшая к точке позиция на оси вилки: (продольная координата, расстояние до оси).
func contact(p: Vector2) -> Vector2:
	var local := (p - position).rotated(-rotation) / SIZE
	var s := clampf(local.x, TAIL, TIP)
	return Vector2(s, Vector2(local.x - s, local.y).length() * SIZE)


## Касается ли круг радиуса r вилки.
func touches(p: Vector2, r: float) -> bool:
	return contact(p).y < r + HALF_WIDTH * 0.8 * SIZE


## Удар пришёлся в зубцы (спереди), а не в бок/ручку.
func hits_tines(p: Vector2) -> bool:
	var local := (p - position).rotated(-rotation) / SIZE
	return local.x > TINES_FROM and absf(local.y) < local.x * 0.9


func update(delta: float, head: Vector2, snake_alive: bool) -> void:
	t += delta
	st_t -= delta
	attack_cd -= delta
	shake = maxf(shake - delta * 3.0, 0.0)
	var to_head := head - position
	match st:
		St.ROAM:
			var want := to_head.angle()
			rotation = rotate_toward(rotation, want, 1.6 * delta * speed_mult)
			vel = vel.lerp(facing() * 45.0 * speed_mult, 2.0 * delta)
			if to_head.length() < 150.0:  # слишком близко — пятится
				vel = vel.lerp(-to_head.normalized() * 90.0, 3.0 * delta)
			if snake_alive and attack_cd <= 0.0 and absf(angle_difference(rotation, want)) < 0.25 and to_head.length() < 700.0:
				st = St.AIM
				st_t = 0.75 * tempo
				sound.emit("fork_aim")
		St.AIM:
			vel = vel.move_toward(Vector2.ZERO, 300.0 * delta)
			rotation = rotate_toward(rotation, to_head.angle(), 0.9 * delta)  # доводит прицел
			if st_t <= 0.0:
				st = St.SPRINT
				st_t = 1.0
				hit_boss = false
				vel = facing() * (560.0 + 90.0 * aggr) * speed_mult
				sound.emit("fork_dash")
		St.SPRINT:
			if st_t <= 0.0:
				st = St.RECOVER
				st_t = 0.6
		St.STUCK:
			vel = Vector2.ZERO
			if st_t <= 0.0:
				st = St.RECOVER
				st_t = 0.4
				rotation += PI  # выдёргивает зубцы и разворачивается
		St.RECOVER:
			vel = vel.move_toward(Vector2.ZERO, 700.0 * delta)
			if st_t <= 0.0:
				st = St.ROAM
				attack_cd = randf_range(1.4, 2.6) * tempo / clampf(aggr, 0.6, 2.0)

	position += vel * delta
	var inner := bounds.grow(-26.0)
	var hit_wall := false
	if position.x < inner.position.x or position.x > inner.end.x:
		vel.x = -vel.x
		hit_wall = true
	if position.y < inner.position.y or position.y > inner.end.y:
		vel.y = -vel.y
		hit_wall = true
	position = position.clamp(inner.position, inner.end)
	if hit_wall and st == St.SPRINT:
		st = St.STUCK
		st_t = 1.3
		shake = 1.0
		vel = Vector2.ZERO
		sound.emit("clang")
	queue_redraw()


## Вилка отскочила от чего-то (яичницы, змеи).
func bounce() -> void:
	st = St.RECOVER
	st_t = 0.7
	vel = -vel * 0.3
	shake = 0.6


func _draw() -> void:
	var s := spawn_k * SIZE
	var jitter := Vector2.ZERO
	if st == St.AIM:
		jitter = Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	if st == St.STUCK:
		jitter = Vector2(0, sin(t * 60.0) * 2.5 * shake)
	# прицел: пунктир траектории
	if st == St.AIM:
		var k := 1.0 - st_t / (0.75 * tempo)
		for i in 14:
			var x := TIP * SIZE + 20.0 + i * 38.0
			draw_line(Vector2(x, 0), Vector2(x + 18.0, 0), Color(Design.danger(), 0.5 * k), Design.telegraph_width(4.0))
	Tex.blob(self, Vector2(7, 12).rotated(-rotation) + Vector2(-3, 0), Vector2(52, 17) * s, Color(0, 0, 0, 0.35))
	draw_set_transform(jitter, 0.0, Vector2.ONE * s)
	if st == St.SPRINT:  # след скорости
		for k in 3:
			draw_line(Vector2(TAIL - 10.0 - k * 22.0, -8 + k * 8), Vector2(TAIL - 40.0 - k * 22.0, -8 + k * 8),
				Color(1, 1, 1, 0.45 - k * 0.12), 3.0)
	var steel := Color(0.66, 0.67, 0.7)
	var edge := Color(0.22, 0.2, 0.2)
	# ручка
	var handle := PackedVector2Array([Vector2(TAIL + 4, -7), Vector2(4, -3.5), Vector2(4, 3.5), Vector2(TAIL + 4, 7)])
	draw_colored_polygon(_grow(handle, 1.8), edge)
	draw_circle(Vector2(TAIL + 4, 0), 8.8, edge)
	draw_colored_polygon(handle, steel)
	draw_circle(Vector2(TAIL + 4, 0), 7.0, steel)
	draw_line(Vector2(TAIL + 2, -3), Vector2(0, -1.5), Color(1, 1, 1, 0.45), 1.6)  # блик
	draw_arc(Vector2(TAIL + 4, 0), 4.5, 0, TAU, 12, steel.darkened(0.3), 1.2)  # гравировка
	# шейка и основание зубцов
	var neck := PackedVector2Array([Vector2(2, -3.5), Vector2(TINES_FROM, -12), Vector2(TINES_FROM + 4, -12),
		Vector2(TINES_FROM + 4, 12), Vector2(TINES_FROM, 12), Vector2(2, 3.5)])
	draw_colored_polygon(_grow(neck, 1.8), edge)
	draw_colored_polygon(neck, steel)
	# зубцы
	var glow := 0.0
	if st == St.AIM:
		glow = 1.0 - st_t / (0.75 * tempo)
	elif st == St.SPRINT:
		glow = 1.0
	var tine_col := steel.lerp(Design.danger(), glow * 0.7)
	for i in 4:
		var y := -9.0 + i * 6.0
		var tine := PackedVector2Array([Vector2(TINES_FROM + 2, y - 1.8), Vector2(TIP - 4, y - 1.4),
			Vector2(TIP, y), Vector2(TIP - 4, y + 1.4), Vector2(TINES_FROM + 2, y + 1.8)])
		draw_colored_polygon(_grow(tine, 1.4), edge)
		draw_colored_polygon(tine, tine_col)
		draw_line(Vector2(TINES_FROM + 4, y - 0.8), Vector2(TIP - 6, y - 0.6), Color(1, 1, 1, 0.35), 0.9)
		if glow > 0.3:
			Tex.blob(self, Vector2(TIP, y), Vector2.ONE * 6.0, Color(1, 0.35, 0.1, glow * 0.6))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _grow(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (p - c).normalized() * by)
	return out
