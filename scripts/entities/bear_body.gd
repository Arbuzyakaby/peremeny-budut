extends Node2D
## Плюшевый медведь: состояние и внешний вид всех восьми видов (уши, мех со швами, пуговичные глаза,
## костюмы, предупреждения атак, щит-пузырь, оглушение). Поведение — в наследнике teddy_bear.gd.

const Tex = preload("res://scripts/gfx/tex.gd")
const Design = preload("res://scripts/ui/design.gd")

enum Type { NORMAL, BOXER, THROWER, KARATE, SEAMSTRESS, NINJA, BOMBER, MEDIC }
enum St { ROAM, WINDUP, DASH, DIZZY, AIM, RECOVER, VANISH }

const RADIUS := 18.0
const BOW_COLORS := [
	Color(0.9, 0.2, 0.3), Color(0.25, 0.5, 0.95), Color(0.95, 0.75, 0.15),
	Color(0.6, 0.3, 0.85), Color(0.2, 0.75, 0.55),
]
const SHIELD_TIME := 10.0

var type := Type.NORMAL
var st := St.ROAM
var st_t := 0.0
var bounds := Rect2(0, 0, 1280, 720)
var speed := 60.0
var aggr := 1.0
var vel := Vector2.ZERO
var dash_dir := Vector2.ZERO
var attack_cd := 2.0
var no_eat_t := 0.0
var bow_color := Color.RED
var fur := Color(0.62, 0.4, 0.22)
var wobble := 0.0
var wander_t := 0.0
var t := 0.0
var grudge: Node2D = null  # медведь, которому мстим
var grudge_t := 0.0
var friend_cd := 0.0
var hit_flash := 0.0
var shield_t := 0.0        # щит-пузырь от медсестры
var allies: Array = []     # все медведи на поле (для медсестры)
var heal_target = null     # медведь, к которому бежит медсестра (без типа — тот же скрипт)
var heal_glow := 0.0
var fade := 1.0            # ниндзя растворяется
## Кооператив (squad.gd): "" — сам по себе, "guard" — встать в точку order_pos (прикрыть союзника),
## "rescue" — добежать до order_target (выдернуть застрявшую вилку), "decoy" — обманщик (только
## Ультра): сесть в order_pos на линии чужой атаки и изображать оглушение.
var order := ""
var order_pos := Vector2.INF
var order_target: Node2D = null
var lead_hint := Vector2.INF  # куда целиться метателю (перекрёстный огонь)
var feint := false            # обманщик сидит на месте и притворяется оглушённым
var tease_t := 0.0            # обманщик раскрылся: дразнится и удирает


func is_edible() -> bool:
	return st != St.DASH and st != St.VANISH and no_eat_t <= 0.0 and not is_shielded()


func is_shielded() -> bool:
	return shield_t > 0.0


func is_dizzy() -> bool:
	return st == St.DIZZY


func has_grudge() -> bool:
	return is_instance_valid(grudge) and grudge_t > 0.0


## Сейчас таранит/бьёт — касание оглушает других медведей.
func is_ramming() -> bool:
	return st == St.DASH or (type == Type.NORMAL and st == St.ROAM and has_grudge())


## Медведя достаточно перерисовать, когда изменился его вид: сдвиг и поворот узла холст применяет сам.
## Покачивание (rotation) — шагами по ~5°: тень чуть отстаёт от поворота, но это доли пикселя.
## Анимация по времени (хвосты повязок, звёзды, пульс щита и злости) идёт шагами по 1/12 с и только там,
## где она видна. Раньше все медведи перерисовывались каждый кадр.
var _last_look: Array = []


func refresh_look() -> void:
	var animated := type == Type.KARATE or type == Type.NINJA or st == St.WINDUP or st == St.AIM 		or st == St.DIZZY or feint or tease_t > 0.0 or shield_t > 0.0 or has_grudge() or order == "rescue"
	var look := [type, st, fur, bow_color, int(rotation * 12.0), int(heal_glow * 10.0), int(hit_flash * 10.0),
		int(shield_t * 10.0) if shield_t < 1.5 else 15, feint, tease_t > 0.0, order == "rescue",
		has_grudge(), int(t * 12.0) if animated else 0]
	if look != _last_look:
		_last_look = look
		queue_redraw()


func _draw() -> void:
	var dark := fur.darkened(0.35)
	var light := fur.lightened(0.35)
	var stitch := fur.darkened(0.55)
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	Tex.blob(self, Vector2(4, 10), Vector2(24, 17), Color(0, 0, 0, 0.25))  # мягкая тень
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for s in [-1.0, 1.0]:  # уши
		draw_circle(Vector2(s * 10, -16), 7.5, dark)
		draw_circle(Vector2(s * 10, -16), 6.0, fur)
		draw_circle(Vector2(s * 10, -15.5), 3.2, light.lerp(Color(0.95, 0.7, 0.7), 0.3))
	for s in [-1.0, 1.0]:  # ноги с подушечками
		draw_circle(Vector2(s * 7, 16), 6.0, dark)
		draw_circle(Vector2(s * 7, 16), 5.0, fur)
		draw_circle(Vector2(s * 7, 17.5), 2.6, light)
	if type == Type.KARATE and st == St.DASH:  # выставленная нога
		draw_line(Vector2(0, 12), Vector2(0, 30), dark, 9.0)
		draw_circle(Vector2(0, 31), 5.5, dark)
		draw_circle(Vector2(0, 31), 4.5, fur)
	if type != Type.BOXER:
		for s in [-1.0, 1.0]:
			var arm := Vector2(s * 12, 5)
			if type in [Type.THROWER, Type.SEAMSTRESS, Type.NINJA, Type.BOMBER] and st == St.AIM and s > 0:
				arm = Vector2(14, -10)
			elif type == Type.KARATE and st == St.WINDUP:
				arm = Vector2(s * 15, -4 if s > 0 else 8)
			elif type == Type.MEDIC and heal_glow > 0.0:
				arm = Vector2(s * 15, -2)
			elif order == "rescue" and s > 0:  # спасатель бежит с поднятой лапой
				arm = Vector2(13, -19 + sin(t * 14.0) * 2.5)
			elif tease_t > 0.0:  # обманщик дразнится: лапы к ушам
				arm = Vector2(s * 15, -14 + sin(t * 20.0) * 2.0)
			draw_circle(arm, 5.5, dark)
			draw_circle(arm, 4.5, _arm_col())
	# тело
	var body_col := fur
	match type:
		Type.KARATE:
			body_col = Color(0.97, 0.97, 0.95)  # белое кимоно
		Type.NINJA:
			body_col = Color(0.14, 0.15, 0.2)
		Type.MEDIC:
			body_col = Color(0.96, 0.97, 0.98)
	draw_circle(Vector2(0, 8), 11.5, body_col.darkened(0.4))
	draw_circle(Vector2(0, 8), 10.5, body_col)
	draw_circle(Vector2(-2, 6), 6.5, body_col.lightened(0.08))
	match type:
		Type.KARATE:
			draw_line(Vector2(-6, 1), Vector2(0, 9), Color(0.75, 0.75, 0.75), 1.5)
			draw_line(Vector2(6, 1), Vector2(0, 9), Color(0.75, 0.75, 0.75), 1.5)
			draw_line(Vector2(-10, 12), Vector2(10, 12), Color(0.08, 0.08, 0.08), 3.5)  # чёрный пояс
			draw_line(Vector2(3, 12), Vector2(7, 19), Color(0.08, 0.08, 0.08), 2.0)
		Type.SEAMSTRESS:
			draw_colored_polygon(PackedVector2Array([Vector2(-7, 2), Vector2(7, 2), Vector2(9, 17), Vector2(-9, 17)]),
				Color(0.95, 0.55, 0.7))  # фартук
			draw_rect(Rect2(-5, 9, 10, 5), Color(0.85, 0.45, 0.6))  # кармашек
			draw_circle(Vector2(0, 11), 3.2, Color(0.85, 0.2, 0.3))  # игольница
			for k in 3:
				draw_line(Vector2(0, 11), Vector2(0, 11) + Vector2.from_angle(-2.2 + k * 0.6) * 5.5, Color(0.8, 0.8, 0.85), 1.0)
		Type.NINJA:
			draw_line(Vector2(-10, 10), Vector2(10, 10), Color(0.7, 0.12, 0.15), 3.0)  # пояс
			draw_line(Vector2(-7, 1), Vector2(6, 17), Color(0.25, 0.26, 0.32), 1.5)
		Type.BOMBER:
			draw_line(Vector2(-9, 1), Vector2(8, 16), Color(0.45, 0.3, 0.15), 3.5)  # патронташ хлопушек
			for k in 3:
				var p := Vector2(-6, 4).lerp(Vector2(6, 14), k / 2.0)
				draw_rect(Rect2(p - Vector2(2, 3), Vector2(4, 6)), [Color(0.95, 0.3, 0.5), Color(0.3, 0.7, 0.95), Color(0.6, 0.9, 0.3)][k])
		Type.MEDIC:
			draw_rect(Rect2(-2, 4, 4, 11), Color(0.9, 0.12, 0.15))  # красный крест
			draw_rect(Rect2(-5.5, 7.5, 11, 4), Color(0.9, 0.12, 0.15))
			draw_arc(Vector2(0, 2), 7.0, 0.3, PI - 0.3, 10, Color(0.3, 0.3, 0.35), 1.4)  # стетоскоп
			draw_circle(Vector2(5, 9), 1.8, Color(0.6, 0.62, 0.68))
		_:
			draw_circle(Vector2(0, 10), 6.5, light)  # пузико-заплатка со швом
			for k in 6:
				var a := TAU * k / 6.0 + 0.3
				var p := Vector2(0, 10) + Vector2.from_angle(a) * 6.8
				draw_line(p, p + Vector2.from_angle(a + PI / 2) * 1.8, stitch, 1.0)
	# голова
	var head_col := fur
	if type == Type.NINJA:
		head_col = Color(0.14, 0.15, 0.2)  # капюшон
	draw_circle(Vector2(0, -7), 13.0, head_col.darkened(0.4))
	draw_circle(Vector2(0, -7), 12.0, head_col)
	draw_circle(Vector2(-2.5, -10), 7.0, head_col.lightened(0.07))
	if type == Type.NINJA:  # открытая полоса для глаз
		draw_rect(Rect2(-10.5, -13.5, 21, 7.5), fur)
		draw_line(Vector2(9, -11), Vector2(17, -8 + sin(t * 10.0) * 2.0), Color(0.14, 0.15, 0.2), 2.5)
	else:
		draw_circle(Vector2(0, -2.5), 5.8, light)  # мордочка
		draw_line(Vector2(0, -7.5), Vector2(0, -12), stitch, 0.9)  # шов по лбу
		for k in 2:
			draw_line(Vector2(-1.2, -9 - k * 2), Vector2(1.2, -9 - k * 2), stitch, 0.9)
		draw_circle(Vector2(0, -4.5), 2.4, Color(0.15, 0.08, 0.05))  # нос
		draw_circle(Vector2(-0.7, -5.2), 0.8, Color(1, 1, 1, 0.6))
		draw_line(Vector2(0, -2.5), Vector2(0, -0.8), Color(0.15, 0.08, 0.05), 1.2)
		draw_arc(Vector2(-1.4, -0.8), 1.4, 0.2, PI - 0.2, 5, Color(0.15, 0.08, 0.05), 1.0)
		draw_arc(Vector2(1.4, -0.8), 1.4, 0.2, PI - 0.2, 5, Color(0.15, 0.08, 0.05), 1.0)
	for s in [-1.0, 1.0]:
		var e := Vector2(s * 4.5, -10)
		if st == St.DIZZY or (feint and s < 0):  # обманщик подглядывает одним глазом
			draw_line(e - Vector2(2, 2), e + Vector2(2, 2), Color.BLACK, 1.5)
			draw_line(e - Vector2(2, -2), e + Vector2(2, -2), Color.BLACK, 1.5)
		else:  # глаза-пуговки
			draw_circle(e, 2.4, Color(0.05, 0.03, 0.03))
			draw_circle(e, 1.5, Color(0.18, 0.12, 0.1))
			draw_circle(e - Vector2(0.7, 0.8), 0.8, Color.WHITE)
		if type == Type.SEAMSTRESS:  # круглые очки
			draw_arc(e, 3.8, 0, TAU, 12, Color(0.3, 0.2, 0.15), 1.2)
		if type in [Type.BOXER, Type.KARATE, Type.NINJA] and st != St.DIZZY:  # злые брови
			draw_line(e + Vector2(s * 3, -4), e + Vector2(-s * 2, -2.5), Color(0.15, 0.08, 0.05), 1.6)
	if type == Type.SEAMSTRESS:
		draw_line(Vector2(-0.7, -10), Vector2(0.7, -10), Color(0.3, 0.2, 0.15), 1.2)

	match type:
		Type.NORMAL:
			var c := Vector2(0, 3)
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(-7, -4), c + Vector2(-7, 4)]), bow_color)
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(7, -4), c + Vector2(7, 4)]), bow_color)
			draw_line(c + Vector2(-6, -2), c + Vector2(-2, -0.5), bow_color.lightened(0.35), 1.0)
			draw_circle(c, 2.2, bow_color.darkened(0.3))
		Type.BOXER:
			draw_line(Vector2(-11, -14), Vector2(11, -14), Color(0.9, 0.15, 0.15), 3.0)  # повязка
			draw_line(Vector2(10, -14), Vector2(15, -9), Color(0.9, 0.15, 0.15), 2.0)
			for s in [-1.0, 1.0]:
				var g := Vector2(s * 13, 4)
				if st == St.WINDUP:
					g = Vector2(s * 9, -3)
				elif order == "rescue" and s > 0:
					g = Vector2(11, -22 + sin(t * 14.0) * 2.5)
				elif st == St.DASH:
					g = Vector2(s * 6, -16)
				draw_circle(g, 7.5, Color(0.55, 0.05, 0.05))
				draw_circle(g, 6.5, Color(0.92, 0.15, 0.12))
				draw_line(g + Vector2(-4, 3), g + Vector2(4, 3), Color(0.98, 0.95, 0.9), 2.0)  # манжета
				draw_circle(g + Vector2(-2, -2), 2.2, Color(1, 1, 1, 0.55))
		Type.THROWER:
			draw_arc(Vector2(0, -13), 10.0, PI, TAU, 12, Color(0.2, 0.45, 0.85), 6.0)  # кепка
			draw_line(Vector2(2, -13), Vector2(15, -12), Color(0.15, 0.35, 0.7), 3.0)
			draw_circle(Vector2(0, -19), 1.6, Color(0.9, 0.9, 0.95))
			if st == St.AIM:
				draw_circle(Vector2(14, -16), 5.0, Color(0.95, 0.8, 0.2))
		Type.KARATE:
			draw_line(Vector2(-11, -14), Vector2(11, -14), Color(0.1, 0.1, 0.1), 3.0)  # чёрная повязка
			draw_line(Vector2(-10, -14), Vector2(-16, -8 + sin(t * 12.0) * 2.0), Color(0.1, 0.1, 0.1), 2.0)
			draw_line(Vector2(-10, -14), Vector2(-17, -12 + sin(t * 12.0 + 1.0) * 2.0), Color(0.1, 0.1, 0.1), 2.0)
		Type.SEAMSTRESS:
			# катушка ниток на макушке и воткнутая иголка
			draw_rect(Rect2(-5, -25, 10, 8), Color(0.9, 0.8, 0.6))
			draw_rect(Rect2(-4, -24, 8, 6), Color(0.85, 0.15, 0.3))
			for k in 3:
				draw_line(Vector2(-4, -23 + k * 2), Vector2(4, -23 + k * 2), Color(0.65, 0.1, 0.2), 0.8)
			draw_line(Vector2(3, -27), Vector2(10, -34), Color(0.8, 0.82, 0.88), 1.5)
			if st == St.AIM:
				draw_line(Vector2(14, -10), Vector2(18, -22), Color(0.85, 0.87, 0.92), 2.0)
				draw_circle(Vector2(14, -10), 3.0, Color(0.95, 0.8, 0.2))
		Type.NINJA:
			draw_line(Vector2(-12, -15), Vector2(12, -15), Color(0.7, 0.12, 0.15), 2.5)  # красная повязка
			if st == St.AIM:
				var p := Vector2(15, -12)
				for k in 4:
					draw_line(p, p + Vector2.from_angle(t * 20.0 + k * PI / 2) * 5.0, Color(0.7, 0.73, 0.8), 2.0)
		Type.BOMBER:
			var hat := PackedVector2Array([Vector2(-7, -17), Vector2(7, -17), Vector2(1, -34)])
			draw_colored_polygon(hat, Color(0.95, 0.85, 0.2))  # праздничный колпак
			for k in 3:
				var y := -19.0 - k * 5.0
				var w := 6.0 * (1.0 - (k + 0.5) / 3.3)
				draw_line(Vector2(-w, y), Vector2(w, y - 1), [Color(0.9, 0.2, 0.4), Color(0.2, 0.6, 0.95), Color(0.3, 0.8, 0.3)][k], 2.0)
			draw_circle(Vector2(1, -34), 3.0, Color(0.9, 0.2, 0.4))
			if st == St.AIM:
				draw_rect(Rect2(10, -18, 9, 6), Color(0.95, 0.3, 0.5))
				Tex.blob(self, Vector2(20, -19), Vector2.ONE * (4.0 + sin(t * 30.0)), Color(1, 0.8, 0.3))
		Type.MEDIC:
			var cap := PackedVector2Array([Vector2(-9, -16), Vector2(9, -16), Vector2(7, -24), Vector2(-7, -24)])
			draw_colored_polygon(cap, Color(0.98, 0.98, 1.0))  # чепчик
			draw_line(Vector2(-9, -16), Vector2(9, -16), Color(0.8, 0.82, 0.88), 1.5)
			draw_rect(Rect2(-1.2, -23, 2.4, 6), Color(0.9, 0.12, 0.15))
			draw_rect(Rect2(-3, -21.2, 6, 2.4), Color(0.9, 0.12, 0.15))

	# эффекты поверх (без поворота медведя)
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	if heal_glow > 0.0:
		Tex.blob(self, Vector2.ZERO, Vector2.ONE * 34.0, Color(0.4, 1, 0.5, 0.45 * heal_glow))
	if st == St.WINDUP or (st == St.AIM and type != Type.NINJA):
		var font := Design.font("heavy")
		var col := Design.danger() if st == St.WINDUP else Design.warn()
		var txt := "ХЬЯ!" if type == Type.KARATE else "!"
		var fs := int((16 if type == Type.KARATE else 26) * (1.35 if Design.Settings.flag("high_contrast") else 1.0))
		var x := -18.0 if type == Type.KARATE else -6.0
		draw_string_outline(font, Vector2(x, -32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color.BLACK)
		draw_string(font, Vector2(x, -32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if has_grudge() and st != St.DIZZY:  # значок злости
		var c := Vector2(13, -24)
		var pulse := 1.0 + 0.15 * sin(t * 12.0)
		for i in 4:
			var a := i * PI / 2.0 + PI / 4.0
			draw_arc(c + Vector2.from_angle(a) * 5.0 * pulse, 3.5 * pulse, a + PI * 0.75, a + PI * 1.25, 6,
				Color(0.95, 0.1, 0.1), 2.2)
	if st == St.DIZZY:
		for i in 3:
			var a := t * 5.0 + TAU * i / 3.0
			_draw_star(Vector2(0, -28) + Vector2(cos(a) * 14.0, sin(a) * 5.0), 4.5, Color(1, 0.9, 0.2))
	elif feint:  # картонные звёзды обманщика: вертятся медленно и качаются на проволочке
		for i in 3:
			var a := t * 2.0 + TAU * i / 3.0
			var p := Vector2(0, -28) + Vector2(cos(a) * 14.0, sin(a) * 5.0)
			draw_line(Vector2(0, -20), p, Color(0.35, 0.3, 0.25, 0.7), 1.0)
			_draw_star(p, 4.8, Color(0.62, 0.48, 0.3))
			_draw_star(p, 3.0, Color(0.8, 0.66, 0.42))
	if tease_t > 0.0:  # показывает язык
		draw_circle(Vector2(0, 1.5), 2.6, Color(0.95, 0.4, 0.5))
	if is_shielded():  # щит-пузырь
		var k := minf(shield_t / 1.5, 1.0)
		var blink := shield_t > 1.5 or int(shield_t * 10.0) % 2 == 0
		if blink:
			Tex.blob(self, Vector2(0, 0), Vector2.ONE * 30.0, Color(0.5, 1, 0.7, 0.25 * k))
			draw_arc(Vector2.ZERO, 26.0 + sin(t * 5.0), 0, TAU, 32, Color(0.6, 1, 0.8, 0.8 * k), 2.5)
			draw_arc(Vector2.ZERO, 21.0, -2.5, -1.7, 8, Color(1, 1, 1, 0.7 * k), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hit_flash > 0.0:
		draw_circle(Vector2(0, 0), 22.0, Color(1, 1, 1, 0.55 * hit_flash))


func _arm_col() -> Color:
	match type:
		Type.NINJA:
			return Color(0.14, 0.15, 0.2)
		Type.MEDIC:
			return Color(0.96, 0.97, 0.98)
		Type.KARATE:
			return Color(0.97, 0.97, 0.95)
	return fur


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2 + TAU * i / 10.0) * rr)
	draw_colored_polygon(pts, col)
