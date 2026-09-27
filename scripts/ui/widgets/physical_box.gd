extends StyleBox
## Физическая поверхность дизайн-языка 2.0 — вместо плоского StyleBoxFlat. Рисует предмет, а не заливку:
## - клавиша (depth > 0): лицевая грань с выпуклым градиентом и бликом по верхней кромке, под ней —
##   боковина клавиши и тень на столе; нажатая клавиша уходит вниз на ход depth, боковина прячется;
## - колодец (inset): утопленная ниша — дорожка фейдера, окно шкалы, подложка тумблера;
## - панель (screws): лакированная доска на винтах.
## Материал (Materials.Kind) задаёт палитру и текстуру поверхности (крап, волокна, шлифовку),
## tint — цвет смысла (золото главной кнопки, томат опасной). Рисуется через RenderingServer,
## поэтому один экземпляр можно делить между десятками кнопок темы.

const Materials = preload("res://scripts/ui/materials.gd")

enum Mode { KEY, INSET, PANEL, FOCUS }

@export var mode := Mode.KEY
@export var kind := Materials.Kind.BAKELITE
@export var tint := Color(0, 0, 0, 0)     # a = 0 — цвет материала
@export var radius := 14.0
@export var depth := 4.0                  # ход клавиши / высота боковины
@export var pressed := false
@export var hover := false
@export var grain := 0.1                  # заметность текстуры
@export var accent := Color(0, 0, 0, 0)   # кольцо смысла (выбранное, фокус карточки)
@export var lamp := Color(0, 0, 0, 0)     # лампочка в углу (a = 0 — нет)
@export var lamp_left := false    # лампа слева по центру (узкие клавиши-вкладки), иначе — в правом верхнем углу
@export var screws := false
@export var shadow := true
@export var disabled := false


## Отступы содержимого с учётом хода клавиши: нажатая опускает текст вместе с гранью.
func set_pads(pad: Vector2) -> void:
	content_margin_left = pad.x
	content_margin_right = pad.x
	var d := depth if mode == Mode.KEY else 0.0
	content_margin_top = pad.y + (d - 1.0 if pressed else 0.0)
	content_margin_bottom = pad.y + (1.0 if pressed else d)


func colors() -> Array:
	var pal: Array = Materials.palette(kind)
	var hi: Color = pal[0]
	var mid: Color = pal[1]
	var lo: Color = pal[2]
	if tint.a > 0.0:
		hi = tint.lightened(0.4)
		mid = tint
		lo = tint.darkened(0.62)
	if hover and not pressed:
		hi = hi.lightened(0.12)
		mid = mid.lightened(0.1)
	if disabled:
		hi = hi.lerp(lo, 0.5)
		mid = mid.lerp(lo, 0.45)
	return [hi, mid, lo]


## Лицевая грань клавиши внутри rect (для виджетов, которые рисуют себя сами).
func face_rect(rect: Rect2) -> Rect2:
	if mode != Mode.KEY or depth <= 0.0:
		return rect
	if pressed:
		return Rect2(rect.position + Vector2(0, depth - 1.0), Vector2(rect.size.x, rect.size.y - depth + 1.0))
	return Rect2(rect.position, Vector2(rect.size.x, rect.size.y - depth))


func _draw(ci: RID, rect: Rect2) -> void:
	var c := colors()
	var hi: Color = c[0]
	var mid: Color = c[1]
	var lo: Color = c[2]
	var r := minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	match mode:
		Mode.FOCUS:
			for k in 3:  # мягкое свечение лампы вокруг
				var g := rect.grow(2.0 + k * 2.0)
				RenderingServer.canvas_item_add_polyline(ci, rrect(g, r + 2.0 + k * 2.0, true),
					PackedColorArray([Color(accent, 0.55 - k * 0.17)]), 2.0, true)
			return
		Mode.INSET:
			RenderingServer.canvas_item_add_polygon(ci, rrect(rect.grow(1.0), r + 1.0), PackedColorArray([Color(hi, 0.18)]))
			var pts := rrect(rect, r)
			RenderingServer.canvas_item_add_polygon(ci, pts, vgrad(pts, rect, lo.darkened(0.45), mid.darkened(0.25)))
			_grain(ci, pts, rect, 0.6)
			_top_line(ci, rect.grow(-1.0), r, Color(0, 0, 0, 0.55), 2.5)  # тень от верхней кромки ниши
			if accent.a > 0.0:
				RenderingServer.canvas_item_add_polyline(ci, rrect(rect.grow(-1.0), r, true), PackedColorArray([accent]), 2.0, true)
			return
	var face := face_rect(rect)
	if shadow and mode != Mode.FOCUS:
		var lift := 1.0 if pressed else 3.0
		for k in 3:
			var sr := Rect2(rect.position + Vector2(0, lift + k), rect.size).grow(k * 1.5)
			RenderingServer.canvas_item_add_polygon(ci, rrect(sr, r + k * 1.5), PackedColorArray([Color(0, 0, 0, 0.16 - k * 0.04)]))
	if mode == Mode.KEY and depth > 0.0:  # боковина клавиши
		var skirt := Rect2(face.position + Vector2(0, 2), Vector2(face.size.x, rect.end.y - face.position.y - 2.0))
		var sp := rrect(skirt, r)
		RenderingServer.canvas_item_add_polygon(ci, sp, vgrad(sp, skirt, lo, lo.darkened(0.4)))
	var edge := rrect(face, r)
	RenderingServer.canvas_item_add_polygon(ci, edge, PackedColorArray([lo.darkened(0.25)]))
	var body_r := face.grow(-1.5)
	var body := rrect(body_r, maxf(r - 1.5, 0.0))
	var top := hi.lerp(mid, 0.3)
	var bottom := mid.lerp(lo, 0.4)
	if pressed:  # утопленная грань: свет падает сверху, верх в тени
		top = mid.lerp(lo, 0.35)
		bottom = mid
	RenderingServer.canvas_item_add_polygon(ci, body, vgrad(body, body_r, top, bottom))
	_grain(ci, body, body_r, 1.0)
	if kind in [Materials.Kind.BRASS, Materials.Kind.CHROME]:  # полоса отражения на металле
		var band := Rect2(body_r.position + Vector2(r * 0.5, body_r.size.y * 0.18),
			Vector2(maxf(body_r.size.x - r, 1.0), body_r.size.y * 0.22))
		RenderingServer.canvas_item_add_polygon(ci, rrect(band, band.size.y / 2.0),
			vgrad(rrect(band, band.size.y / 2.0), band, Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.0)))
	if not pressed:
		_top_line(ci, body_r.grow(-0.5), maxf(r - 2.0, 0.0), Color(hi.lightened(0.3), 0.7), 1.5)
	else:
		_top_line(ci, body_r.grow(-0.5), maxf(r - 2.0, 0.0), Color(0, 0, 0, 0.45), 2.0)
	if accent.a > 0.0:
		RenderingServer.canvas_item_add_polyline(ci, rrect(face.grow(-1.0), r, true), PackedColorArray([accent]), 2.0, true)
	if screws:
		var inset := maxf(r * 0.62, 9.0)
		for p in [face.position + Vector2(inset, inset), Vector2(face.end.x - inset, face.position.y + inset),
				Vector2(face.position.x + inset, face.end.y - inset), face.end - Vector2(inset, inset)]:
			_screw(ci, p)
	if lamp.a > 0.0:
		var lp := Vector2(face.end.x - 12.0, face.position.y + 11.0)
		if lamp_left:
			lp = Vector2(face.position.x + 8.0, face.get_center().y)
		RenderingServer.canvas_item_add_circle(ci, lp, 7.0, Color(lamp, 0.22 * lamp.a))
		RenderingServer.canvas_item_add_circle(ci, lp, 4.0, lo.darkened(0.3))
		RenderingServer.canvas_item_add_circle(ci, lp, 3.0, lamp)
		RenderingServer.canvas_item_add_circle(ci, lp + Vector2(-1, -1), 1.0, Color(1, 1, 1, 0.8 * lamp.a))


func _grain(ci: RID, pts: PackedVector2Array, r: Rect2, k: float) -> void:
	if grain <= 0.0:
		return
	var tex := Materials.texture(kind)
	var ts := Vector2(tex.get_width(), tex.get_height())
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(((p - r.position) / ts).clamp(Vector2.ZERO, Vector2.ONE))
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([Color(1, 1, 1, grain * k)]), uvs, tex.get_rid())


func _top_line(ci: RID, r: Rect2, rad: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var steps := 5
	for i in steps + 1:  # левое верхнее скругление
		var a := PI + PI / 2.0 * i / steps
		pts.append(r.position + Vector2(rad, rad) + Vector2.from_angle(a) * rad)
	for i in steps + 1:  # правое верхнее
		var a := PI * 1.5 + PI / 2.0 * i / steps
		pts.append(Vector2(r.end.x - rad, r.position.y + rad) + Vector2.from_angle(a) * rad)
	RenderingServer.canvas_item_add_polyline(ci, pts, _fade_colors(pts.size(), col), w, true)


static func _fade_colors(n: int, col: Color) -> PackedColorArray:
	var out := PackedColorArray()
	for i in n:
		var k := float(i) / maxf(n - 1, 1)
		out.append(Color(col, col.a * clampf(minf(k, 1.0 - k) * 6.0, 0.0, 1.0)))
	return out


func _screw(ci: RID, p: Vector2) -> void:
	RenderingServer.canvas_item_add_circle(ci, p + Vector2(0, 1), 4.2, Color(0, 0, 0, 0.45))
	RenderingServer.canvas_item_add_circle(ci, p, 3.8, Color(0.55, 0.45, 0.3))
	RenderingServer.canvas_item_add_circle(ci, p + Vector2(-0.8, -0.8), 2.6, Color(0.85, 0.72, 0.48))
	RenderingServer.canvas_item_add_line(ci, p + Vector2(-2.6, 1.2), p + Vector2(2.6, -1.2), Color(0.25, 0.18, 0.1), 1.2)


## Контур скруглённого прямоугольника. closed — замкнуть (для обводки).
static func rrect(r: Rect2, rad: float, closed := false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	rad = clampf(rad, 0.0, minf(r.size.x, r.size.y) / 2.0)
	var steps := 6 if rad > 3.0 else 1
	var corners := [r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad),
		r.end - Vector2(rad, rad), Vector2(r.position.x + rad, r.end.y - rad)]
	for ci in 4:
		for i in steps + 1:
			var a := PI + PI / 2.0 * (ci + float(i) / steps)
			var p: Vector2 = corners[ci] + Vector2.from_angle(a) * rad
			# у «таблетки» дуги сходятся — совпадающие точки ломают триангуляцию
			if pts.is_empty() or p.distance_squared_to(pts[pts.size() - 1]) > 0.01:
				pts.append(p)
	if pts.size() > 2 and pts[0].distance_squared_to(pts[pts.size() - 1]) <= 0.01:
		pts.remove_at(pts.size() - 1)
	if closed:
		pts.append(pts[0])
	return pts


## Вертикальный градиент по точкам контура: цвет — линейная функция высоты.
static func vgrad(pts: PackedVector2Array, r: Rect2, top: Color, bottom: Color) -> PackedColorArray:
	var out := PackedColorArray()
	for p in pts:
		out.append(top.lerp(bottom, clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)))
	return out
