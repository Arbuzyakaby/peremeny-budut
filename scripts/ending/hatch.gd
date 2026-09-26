extends Node2D
## Финальный кадр: в пепле блестит зелёное яйцо, трескается, половинки скорлупы раскрываются.
## Свойства k (появление), glint (блик), crack (трещины) анимирует ending.gd.

const Tex = preload("res://scripts/gfx/tex.gd")

var egg_pos := Vector2(640, 360)
var egg_k := 0.0      # 0 — нет, 1 — яйцо лежит
var egg_glint := 0.0
var egg_crack := 0.0  # 0..1 — трещины, 1 — скорлупа раскрылась
var t := 0.0


func _process(delta: float) -> void:
	t += delta
	egg_glint = maxf(egg_glint - delta * 0.8, 0.0)
	if egg_k > 0.0:
		queue_redraw()


func _draw() -> void:
	if egg_k <= 0.0:
		return
	var c := egg_pos
	var k := egg_k
	Tex.blob(self, c + Vector2(0, 6), Vector2(34, 16) * k, Color(0, 0, 0, 0.5))
	if egg_crack < 1.0:
		var wob := sin(t * 18.0) * 0.12 * egg_crack
		draw_set_transform(c, wob, Vector2(k, k))
		_egg_shape(Vector2.ZERO, 1.0)
		for i in int(egg_crack * 6.0):  # трещины
			var a := -1.2 + i * 0.5
			var p0 := Vector2(cos(a) * 9.0, -6.0 + sin(a) * 4.0)
			draw_polyline(PackedVector2Array([p0, p0 + Vector2(3, 4), p0 + Vector2(-1, 8)]), Color(0.2, 0.25, 0.15), 1.2)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:  # половинки скорлупы
		for s in [-1.0, 1.0]:
			draw_set_transform(c + Vector2(s * 16, 6), s * 0.9, Vector2.ONE * 0.8)
			var half := PackedVector2Array()
			for i in 9:
				var a := PI * i / 8.0
				half.append(Vector2(cos(a) * 12.0, sin(a) * 14.0))
			for i in range(1, 4):  # зубчатый край скорлупы
				half.append(Vector2(-12.0 + i * 6.0, -3.0 if i % 2 == 1 else 1.0))
			draw_colored_polygon(half, Color(0.85, 0.95, 0.8))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if egg_glint > 0.0:  # блик в темноте
		var g := egg_glint
		var p := c + Vector2(-6, -12)
		Tex.blob(self, p, Vector2.ONE * 26.0 * g, Color(1, 1, 0.8, 0.7 * g))
		draw_line(p - Vector2(18, 0) * g, p + Vector2(18, 0) * g, Color(1, 1, 1, g), 2.0)
		draw_line(p - Vector2(0, 18) * g, p + Vector2(0, 18) * g, Color(1, 1, 1, g), 2.0)



func _egg_shape(o: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		var r := 1.0 + 0.18 * sin(a)  # к низу шире
		pts.append(o + Vector2(cos(a) * 13.0 * s, sin(a) * 17.0 * s * r))
	draw_colored_polygon(pts, Color(0.15, 0.25, 0.12))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(o + (p - o) * 0.88)
	draw_colored_polygon(inner, Color(0.75, 0.92, 0.65))
	for i in 7:  # крапинки
		draw_circle(o + Vector2(sin(i * 2.3) * 7.0, cos(i * 1.7) * 10.0), 1.6, Color(0.35, 0.6, 0.3))
	Tex.blob(self, o + Vector2(-4, -7), Vector2(5, 7), Color(1, 1, 1, 0.7))
