extends Control
## Заголовок главного меню «ЗМЕЯ»: буквы падают по очереди, потом прыгают волной и переливаются;
## под ними ползёт змейка с языком. Время (t) и ход появления (intro) задаёт меню.
## По щелчку буква под курсором подпрыгивает (poke), а пасхалка hiss() подбрасывает все буквы
## волной и высовывает у змейки длинный язык: «шшш!».

const Design = preload("res://scripts/ui/design.gd")
const Settings = preload("res://scripts/core/settings.gd")

var t := 0.0
var intro := 0.0
var jump := 0.0     # щелчок: буквы подпрыгивают
var hiss_k := 0.0   # пасхалка: волна и длинный язык


func poke() -> void:
	jump = 1.0


func hiss() -> void:
	hiss_k = 1.0


func _init() -> void:
	custom_minimum_size = Vector2(440, 104)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	jump = maxf(jump - delta * 3.0, 0.0)
	hiss_k = maxf(hiss_k - delta * 0.5, 0.0)


func _draw() -> void:
	var c := self
	var font := Design.font("heavy")
	var text := "ЗМЕЯ"
	var fs := 86
	var widths: Array[float] = []
	var total := 0.0
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0
		widths.append(w)
		total += w
	var x := (c.size.x - total) / 2.0
	var x0 := x
	var calm := Settings.flag("reduced_motion")
	for i in text.length():
		var k := clampf((intro - 0.3 - i * 0.12) / 0.45, 0.0, 1.0)
		if k <= 0.0:
			x += widths[i]
			continue
		var drop := -170.0 * pow(1.0 - k, 2.0)
		var bounce := 0.0 if calm else sin(t * 3.2 - i * 0.8) * 7.0 * k
		bounce -= 14.0 * jump * absf(sin(jump * PI * 2.0 + i))  # щелчок
		bounce -= 60.0 * hiss_k * maxf(sin(hiss_k * 9.0 - i * 0.9), 0.0)  # волна пасхалки
		var col := Color.from_hsv(0.29 + 0.05 * sin(t * 2.0 + i), 0.72, 0.97, k)
		var rot := 0.0 if calm else sin(t * 2.4 + i * 1.3) * 0.07
		c.draw_set_transform(Vector2(x + widths[i] / 2.0, 78.0 + drop + bounce), rot, Vector2.ONE)
		var off := Vector2(-widths[i] / 2.0 + 3.0, 0)
		c.draw_string_outline(font, off + Vector2(4, 5), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color(0, 0, 0, 0.35 * k))
		c.draw_string_outline(font, off, text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color(0.05, 0.2, 0.05, k))
		c.draw_string(font, off, text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		c.draw_string(font, off + Vector2(0, -3), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.12 * k))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		x += widths[i]
	var k := clampf((intro - 0.9) / 0.6, 0.0, 1.0)  # змейка-подчёркивание
	if k <= 0.0:
		return
	var pts := PackedVector2Array()
	var len := total * k
	for i in 40:
		var px := x0 + len * i / 39.0
		pts.append(Vector2(px, 94.0 + sin(px * 0.045 - t * 6.0) * 5.0))
	c.draw_polyline(pts, Color(0.08, 0.3, 0.1), 13.0)
	c.draw_polyline(pts, Color(0.4, 0.88, 0.35), 9.0)
	var head := pts[pts.size() - 1]
	c.draw_circle(head, 9.0, Color(0.08, 0.3, 0.1))
	c.draw_circle(head, 7.0, Color(0.45, 0.92, 0.4))
	c.draw_circle(head + Vector2(2, -3), 2.2, Color.WHITE)
	c.draw_circle(head + Vector2(2.6, -3), 1.1, Color.BLACK)
	if hiss_k > 0.0:  # шшш! — длинный раздвоенный язык
		var tip := head + Vector2(30.0 + 30.0 * hiss_k, sin(t * 40.0) * 3.0)
		c.draw_line(head + Vector2(8, 0), tip, Color(0.85, 0.1, 0.2), 3.0)
		c.draw_line(tip, tip + Vector2(8, -5), Color(0.85, 0.1, 0.2), 2.0)
		c.draw_line(tip, tip + Vector2(8, 5), Color(0.85, 0.1, 0.2), 2.0)
		c.draw_string(Design.font("heavy"), head + Vector2(20, -16), "шшш!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(0.45, 0.92, 0.4, hiss_k))
	elif fmod(t, 1.6) < 0.35:
		c.draw_line(head + Vector2(8, 0), head + Vector2(18, 0), Color(0.85, 0.1, 0.2), 2.0)
		c.draw_line(head + Vector2(18, 0), head + Vector2(22, -3), Color(0.85, 0.1, 0.2), 1.5)
		c.draw_line(head + Vector2(18, 0), head + Vector2(22, 3), Color(0.85, 0.1, 0.2), 1.5)
