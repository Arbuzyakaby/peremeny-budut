extends Node2D
## Шипящая лужа (v12.4): что остаётся от шипучки после серии прыжков. Пена вязкая — змея в ней
## ползёт медленнее (Snake.slow), пока не выберется. Лужа шипит, пузырится и за несколько секунд
## высыхает. Рисуется кодом; перерисовка 12 раз в секунду — пузыри не требуют большего.

const LIFE := 3.2
const RADIUS := 56.0
const SLOW_TIME := 0.3  # змея в луже: замедление продлевается, пока она внутри
const SLOW_K := 0.65    # в пене змея ползёт на 35 % медленнее (лента хоровода — вдвое)
const MAX_ON_FIELD := 4

var life := LIFE
var color := Color(1.0, 0.86, 0.45)
var foam := Color(1.0, 0.97, 0.85)
var t := 0.0
var _seed := 0.0
var _last_frame := -1


func setup(pos: Vector2, tint: Color, foam_col: Color) -> void:
	position = pos
	color = tint
	foam = foam_col
	_seed = randf() * 10.0
	z_index = 0


## 0..1: разливается за 0,2 с, держится, последние 0,8 с высыхает.
func size_k() -> float:
	var age := LIFE - life
	return clampf(age / 0.2, 0.0, 1.0) * clampf(life / 0.8, 0.0, 1.0)


func radius() -> float:
	return RADIUS * (0.4 + 0.6 * size_k())


func contains(p: Vector2) -> bool:
	return life > 0.0 and p.distance_to(position) < radius()


func finished() -> bool:
	return life <= 0.0


func update(delta: float) -> void:
	life -= delta
	t += delta
	var frame := int(t * 12.0)
	if frame != _last_frame:
		_last_frame = frame
		queue_redraw()


func _draw() -> void:
	var k := size_k()
	if k <= 0.0:
		return
	var r := radius()
	# неровное пятно: окружность с «языками»
	var pts := PackedVector2Array()
	for i in 20:
		var a := i * TAU / 20.0
		var wob := 1.0 + 0.12 * sin(a * 3.0 + _seed) + 0.07 * sin(a * 5.0 + _seed * 2.0)
		pts.append(Vector2.from_angle(a) * r * wob * Vector2(1.0, 0.72))
	draw_colored_polygon(pts, Color(color.darkened(0.25), 0.45 * k))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p * 0.78)
	draw_colored_polygon(inner, Color(color, 0.55 * k))
	# кромка пены
	for i in 14:
		var a := i * TAU / 14.0 + _seed
		var p := Vector2.from_angle(a) * r * 0.9 * Vector2(1.0, 0.72)
		draw_circle(p, 3.0 + 1.5 * sin(t * 6.0 + i), Color(foam, 0.75 * k))
	# пузыри вздуваются и лопаются
	for i in 7:
		var ph := fmod(t * 1.3 + i * 0.37 + _seed, 1.0)
		var p := Vector2.from_angle(i * 2.4 + _seed) * r * 0.55 * sqrt((i + 0.5) / 7.0) * Vector2(1.0, 0.72)
		draw_arc(p, 2.0 + 5.0 * ph, 0, TAU, 12, Color(foam, 0.9 * (1.0 - ph) * k), 1.4)
	draw_circle(Vector2(-r * 0.3, -r * 0.2), r * 0.12, Color(1, 1, 1, 0.25 * k))  # блик
