extends Node2D
## Прыгающая таблетка. Приседает и прыгает на змею по дуге. В воздухе неуязвима (видна метка
## приземления), при приземлении давит всех под собой и поднимает ударную волну, оглушающую змею.
## На земле её можно съесть. Атака у всех видов одна, отличаются повадки:
## - капсула стоит на месте и прыгает высоко и далеко;
## - шайба (круглая прессованная таблетка) между прыжками катится на ребре к змее, прыгает
##   ниже, короче и чаще;
## - шипучка (v12.4) прыгает серией из трёх коротких скачков без волны, пенится и шипит, а после
##   последнего растворяется в шипящую лужу (fizz_puddle.gd), которая вязнет и замедляет змею.

signal landed(pos: Vector2)
signal sound(sound_name: String)
signal fizzed(pos: Vector2)  # шипучка закончила серию и растеклась лужей

const Tex = preload("res://scripts/gfx/tex.gd")
const Design = preload("res://scripts/ui/design.gd")

enum St { IDLE, CROUCH, JUMP }
enum Kind { CAPSULE, TABLET, FIZZ }

## Виды таблеток: высота и дальность прыжка, время в воздухе, приседание, скорость качения по полу,
## множитель паузы между прыжками.
const KINDS := [
	{"name": "Капсула", "key": "pill", "height": 190.0, "hop": 420.0, "air": 0.85, "crouch": 0.35, "roll": 0.0, "rest": 1.0},
	{"name": "Шайба", "key": "pill_1", "height": 120.0, "hop": 300.0, "air": 0.62, "crouch": 0.26, "roll": 62.0, "rest": 0.8},
	{"name": "Шипучка", "key": "pill_2", "height": 70.0, "hop": 170.0, "air": 0.4, "crouch": 0.24, "roll": 0.0, "rest": 1.8,
		"chain": 3},
]
const CHAIN_GAP := 0.14  # пауза между скачками серии шипучки, с
## Шипучки — растворимые таблетки со вкусом: [лицо, ребро, пена].
const FIZZ_COLORS := [
	[Color(1.0, 0.86, 0.45), Color(0.9, 0.6, 0.18), Color(1.0, 0.97, 0.85)],   # апельсин
	[Color(0.93, 0.98, 0.62), Color(0.7, 0.8, 0.25), Color(0.98, 1.0, 0.88)],   # лимон
	[Color(0.98, 0.72, 0.85), Color(0.82, 0.38, 0.55), Color(1.0, 0.92, 0.96)], # малина
]
## Шайбы — прессованный мел пастельных цветов: [лицо, ребро].
const TABLET_COLORS := [
	[Color(0.97, 0.96, 0.92), Color(0.78, 0.76, 0.7)],
	[Color(1.0, 0.93, 0.62), Color(0.85, 0.72, 0.3)],
	[Color(0.98, 0.78, 0.82), Color(0.8, 0.52, 0.58)],
	[Color(0.72, 0.86, 1.0), Color(0.45, 0.6, 0.82)],
]

const HERD_TINT := Color(1.0, 0.42, 0.08)  # оттенок загонщика
const RADIUS := 26.0
const CRUSH_RADIUS := 40.0
const COLORS := [
	[Color(0.92, 0.2, 0.22), Color(0.97, 0.95, 0.9)],
	[Color(0.25, 0.45, 0.92), Color(0.98, 0.85, 0.25)],
	[Color(0.3, 0.75, 0.4), Color(0.97, 0.95, 0.9)],
	[Color(0.75, 0.35, 0.85), Color(0.95, 0.7, 0.8)],
]

var kind := Kind.CAPSULE
var st := St.IDLE
var st_t := 1.0
var bounds := Rect2(0, 0, 1280, 720)
var tempo := 1.0
var aggr := 1.0
var height := 0.0
var jump_from := Vector2.ZERO
var jump_to := Vector2.ZERO
var air_time := 0.85
var angle := 0.0
var cols: Array = COLORS[0]
var t := 0.0
var squash := 0.0
var spawn_k := 0.0
var aim_offset := Vector2.ZERO  # кооператив (squad.gd): прыгнуть так, чтобы загнать змею к вилкам
var herd := false   # роль загонщика: таблетка наливается жарким оттенком (телеграф вместо тега)
var herd_k := 0.0
var roll := 0.0  # угол качения шайбы (для рисунка)
var hops_left := 0  # сколько скачков серии шипучки осталось после текущего
var last_hop := true  # текущий прыжок — последний в серии (для обычных таблеток — всегда)


func setup(pos: Vector2, area: Rect2, idle_tempo: float, aggression: float, pill_kind := Kind.CAPSULE) -> void:
	position = pos
	bounds = area
	tempo = idle_tempo
	aggr = aggression
	kind = pill_kind
	angle = randf_range(-0.6, 0.6)
	cols = _palette().pick_random()
	st_t = randf_range(0.6, 1.4) * tempo * float(spec()["rest"])
	material = Tex.material(Tex.Mat.PLASTIC, randf() * 10.0)
	create_tween().tween_property(self, "spawn_k", 1.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _palette() -> Array:
	match kind:
		Kind.TABLET:
			return TABLET_COLORS
		Kind.FIZZ:
			return FIZZ_COLORS
	return COLORS


func spec() -> Dictionary:
	return KINDS[kind]


## Скачков в серии: у шипучки три, у остальных один.
func chain() -> int:
	return int(spec().get("chain", 1))


## Ключ карточки в картотеке.
func bestiary_key() -> String:
	return spec()["key"]


func jump_height() -> float:
	return spec()["height"]


## На земле — можно съесть.
func is_edible() -> bool:
	return st != St.JUMP and spawn_k > 0.9


func in_air() -> bool:
	return st == St.JUMP


func update(delta: float, head: Vector2, head_vel: Vector2, snake_alive: bool) -> void:
	t += delta
	st_t -= delta
	squash = maxf(squash - delta * 3.0, 0.0)
	herd_k = move_toward(herd_k, 1.0 if herd else 0.0, delta * 3.0)
	match st:
		St.IDLE:
			var roll_speed: float = spec()["roll"]
			if roll_speed > 0.0 and snake_alive and spawn_k > 0.9:  # шайба катится на ребре к змее
				var to := head - position
				if to.length() > 60.0:
					var step := to.normalized() * roll_speed * clampf(aggr, 0.6, 1.6) * delta
					var inner := bounds.grow(-RADIUS - 10.0)
					position = (position + step).clamp(inner.position, inner.end)
					roll += step.length() / 14.0
			if st_t <= 0.0 and snake_alive:
				st = St.CROUCH
				st_t = float(spec()["crouch"]) * clampf(tempo, 0.6, 1.3)
				if hops_left == 0:  # новая серия
					hops_left = chain() - 1
		St.CROUCH:
			if st_t <= 0.0:
				st = St.JUMP
				air_time = float(spec()["air"]) * clampf(tempo, 0.7, 1.2)
				st_t = air_time
				jump_from = position
				var lead := head + head_vel * air_time * clampf(0.35 * aggr, 0.2, 0.8) + aim_offset
				var inner := bounds.grow(-RADIUS - 10.0)
				var hop := lead - position
				var reach: float = spec()["hop"]
				if hop.length() > reach:  # за один прыжок не дальше reach
					hop = hop.normalized() * reach
				jump_to = (position + hop).clamp(inner.position, inner.end)
				last_hop = hops_left == 0
				sound.emit("fizz_hop" if kind == Kind.FIZZ else "pill_hop")
		St.JUMP:
			var k := clampf(1.0 - st_t / air_time, 0.0, 1.0)
			position = jump_from.lerp(jump_to, k)
			height = sin(k * PI) * jump_height()
			angle += delta * (7.0 if kind == Kind.CAPSULE else 11.0)
			if st_t <= 0.0:
				height = 0.0
				position = jump_to
				squash = 1.0
				if hops_left > 0:  # серия шипучки: тут же следующий скачок
					hops_left -= 1
					st = St.CROUCH
					st_t = CHAIN_GAP
				else:
					st = St.IDLE
					st_t = randf_range(0.8, 1.2) * tempo * float(spec()["rest"])
				landed.emit(position)
				sound.emit("pill_land" if kind != Kind.FIZZ else "fizz_land")
				if kind == Kind.FIZZ and last_hop:
					fizzed.emit(position)
	refresh_look()


## Перерисовка только при изменении вида: в покое капсула чуть качается (шагами по ~0,003 рад), шайба катится;
## всё остальное — прыжок, присед, шлепок, появление, ореол загонщика — рисуется каждый кадр.
var _last_look: Array = []


func refresh_look() -> void:
	var busy := st != St.IDLE or squash > 0.0 or spawn_k < 1.0 or herd_k > 0.001
	var wobble := 0
	if kind == Kind.CAPSULE:
		wobble = int(sin(t * 3.0) * 16.0)
	elif kind == Kind.FIZZ:
		wobble = int(t * 12.0)  # пузырьки на шипучке поднимаются и в покое — 12 кадров в секунду
	var look := [wobble, int(roll * 12.0), cols, kind]
	if busy or look != _last_look:
		_last_look = look
		queue_redraw()


## Технический режим «Контакт»: не прыгает на змею — мирно подскакивает, передвигаясь со скоростью want.
func calm_update(delta: float, want: Vector2) -> void:
	t += delta
	st = St.IDLE
	herd = false
	aim_offset = Vector2.ZERO
	herd_k = move_toward(herd_k, 0.0, delta * 3.0)
	squash = maxf(squash - delta * 3.0, 0.0)
	var moving := clampf(want.length() / 80.0, 0.0, 1.0)
	height = absf(sin(t * 6.0)) * lerpf(3.0, 16.0, moving)
	var inner := bounds.grow(-RADIUS - 10.0)
	position = (position + want * delta).clamp(inner.position, inner.end)
	roll += want.length() * delta / 14.0
	refresh_look()


## Цвета половинок/лица с учётом роли загонщика.
func tint(c: Color) -> Color:
	return c.lerp(HERD_TINT, 0.55 * herd_k)


func _draw() -> void:
	var s := spawn_k
	var c0 := tint(cols[0])
	var c1 := tint(cols[1])
	if st == St.JUMP:  # «здесь ударит» (язык телеграфов 2.3): кольцо со стрелкой часов на месте приземления
		var target := jump_to - position
		var k := 1.0 - st_t / air_time
		Tex.blob(self, target, Vector2.ONE * CRUSH_RADIUS * 1.2, Color(0, 0, 0, 0.1 + 0.12 * k))
		Design.draw_tell_ring(self, target, CRUSH_RADIUS, Design.Tell.AREA, k)
	var shadow_k := 1.0 - height / (jump_height() * 1.5)
	Tex.blob(self, Vector2(3, 8), Vector2(30, 16) * shadow_k * s, Color(0, 0, 0, 0.28 * shadow_k))
	if herd_k > 0.01:  # загонщик: жаркий ореол
		Tex.blob(self, Vector2(0, -height - 4.0), Vector2.ONE * 36.0 * s, Color(HERD_TINT, 0.2 * herd_k))

	var sc := Vector2.ONE * s * 1.25
	match st:
		St.CROUCH:
			var k := 1.0 - st_t / float(spec()["crouch"])
			sc *= Vector2(1.0 + 0.25 * k, 1.0 - 0.3 * k)
			sc += Vector2(randf_range(-0.03, 0.03), 0)
		St.JUMP:
			sc *= Vector2(0.88, 1.15)
	if squash > 0.0:
		sc *= Vector2(1.0 + 0.35 * squash, 1.0 - 0.3 * squash)
	var a := angle if st == St.JUMP else angle + sin(t * 3.0) * 0.05
	if kind == Kind.FIZZ:
		draw_set_transform(Vector2(0, -height - 4.0), 0.0, sc)
		_draw_fizz(c0, c1, tint(cols[2]))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if kind == Kind.TABLET:
		draw_set_transform(Vector2(0, -height - 4.0), a if st == St.JUMP else 0.0, sc)
		_draw_tablet(c0, c1)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_set_transform(Vector2(0, -height - 4.0), a, sc)
	var half := 22.0
	var r := 11.0
	var outline := Color(0.15, 0.1, 0.12)
	draw_circle(Vector2(-half + r, 0), r + 1.8, outline)
	draw_circle(Vector2(half - r, 0), r + 1.8, outline)
	draw_rect(Rect2(-half + r, -r - 1.8, (half - r) * 2.0, (r + 1.8) * 2.0), outline)
	# две половинки капсулы
	draw_circle(Vector2(-half + r, 0), r, c0)
	draw_rect(Rect2(-half + r, -r, half - r, r * 2.0), c0)
	draw_circle(Vector2(half - r, 0), r, c1)
	draw_rect(Rect2(0, -r, half - r, r * 2.0), c1)
	draw_line(Vector2(0, -r), Vector2(0, r), outline.lerp(Color.WHITE, 0.4), 1.5)  # шов
	# объём: тень снизу, блик сверху
	draw_rect(Rect2(-half + r, r * 0.35, (half - r) * 2.0, r * 0.65), Color(0, 0, 0, 0.12))
	draw_line(Vector2(-half + r - 2, -r * 0.55), Vector2(half - r + 2, -r * 0.55), Color(1, 1, 1, 0.6), 3.0)
	draw_circle(Vector2(-half + r - 3, -r * 0.35), 2.2, Color(1, 1, 1, 0.8))
	# тиснение «мг»
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(3, 4), "мг", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c1.darkened(0.3))
	# лицо: злые глазки, в прыжке — оскал
	var face := Vector2(-half + r, -1)
	for side in [-1.0, 1.0]:
		var e: Vector2 = face + Vector2(side * 3.5, -1)
		draw_circle(e, 2.2, Color.WHITE)
		draw_circle(e + Vector2(0.4, 0.5), 1.2, Color.BLACK)
		draw_line(e + Vector2(-side * 2.8, -3.8), e + Vector2(side * 1.8, -2.6), outline, 1.3)
	if st == St.JUMP or st == St.CROUCH:
		draw_rect(Rect2(face + Vector2(-3, 3), Vector2(6, 2.5)), outline)
	else:
		draw_line(face + Vector2(-2.5, 4), face + Vector2(2.5, 4), outline, 1.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Шайба: круглая прессованная таблетка с ребром, риской разлома и выдавленным «мг»; риска
## поворачивается, когда шайба катится.
func _draw_tablet(face_col: Color, rim_col: Color) -> void:
	var r := 16.0
	var outline := Color(0.15, 0.1, 0.12)
	var rim_h := 4.0  # видимое ребро снизу — таблетка толстая
	draw_circle(Vector2(0, rim_h * 0.5), r + 1.8, outline)
	draw_circle(Vector2(0, rim_h), r, rim_col)
	draw_rect(Rect2(-r, 0, r * 2.0, rim_h), rim_col)
	draw_circle(Vector2.ZERO, r, face_col)
	# меловая поверхность: фаска по краю лица и блик
	draw_arc(Vector2.ZERO, r - 1.5, 0, TAU, 32, Color(rim_col, 0.55), 2.0)
	draw_circle(Vector2(-5, -6), 6.0, Color(1, 1, 1, 0.35))
	draw_circle(Vector2(-6, -7), 2.2, Color(1, 1, 1, 0.8))
	# риска разлома: вращается при качении
	var d := Vector2.from_angle(roll)
	draw_line(-d * (r - 3.0), d * (r - 3.0), Color(rim_col.darkened(0.25), 0.9), 2.2)
	draw_line(-d * (r - 3.0) + Vector2(0, 1), d * (r - 3.0) + Vector2(0, 1), Color(1, 1, 1, 0.35), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(4, 12), "мг", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, rim_col.darkened(0.3))
	# лицо: злые глазки, в прыжке — оскал
	var face := Vector2(0, -2)
	for side in [-1.0, 1.0]:
		var e: Vector2 = face + Vector2(side * 5.0, -1)
		draw_circle(e, 2.6, Color.WHITE)
		draw_circle(e + Vector2(0.4, 0.5), 1.4, Color.BLACK)
		draw_line(e + Vector2(-side * 3.2, -4.2), e + Vector2(side * 2.0, -3.0), outline, 1.4)
	if st == St.JUMP or st == St.CROUCH:
		draw_rect(Rect2(face + Vector2(-4, 4), Vector2(8, 3)), outline)
	else:
		draw_line(face + Vector2(-3, 5), face + Vector2(3, 5), outline, 1.3)


## Шипучка: толстый пористый диск растворимой таблетки. По краям пенится, от неё поднимаются
## пузырьки; в прыжке за ней тянется струйка газа, как у ракеты из бутылки.
func _draw_fizz(face_col: Color, rim_col: Color, foam: Color) -> void:
	var r := 18.0
	var outline := Color(0.15, 0.1, 0.12)
	var rim_h := 6.0
	if st == St.JUMP:  # струйка газа из-под таблетки
		for i in 5:
			var k := fmod(t * 3.0 + i * 0.2, 1.0)
			var y := rim_h + 4.0 + k * 22.0
			draw_circle(Vector2(sin(t * 9.0 + i) * 4.0 * k, y), (5.0 - 3.0 * k), Color(foam, 0.7 * (1.0 - k)))
	draw_circle(Vector2(0, rim_h * 0.5), r + 1.8, outline)
	draw_circle(Vector2(0, rim_h), r, rim_col)
	draw_rect(Rect2(-r, 0, r * 2.0, rim_h), rim_col)
	for i in 7:  # пена по ребру
		var x := -r + 3.0 + i * (r * 2.0 - 6.0) / 6.0
		draw_circle(Vector2(x, rim_h + sin(t * 5.0 + i * 1.7) * 1.2), 2.6, Color(foam, 0.9))
	draw_circle(Vector2.ZERO, r, face_col)
	# поры прессованного порошка: одни и те же у каждой таблетки
	for i in 11:
		var p := Vector2.from_angle(i * 2.39996) * (r - 4.0) * sqrt((i + 0.5) / 11.0)
		draw_circle(p, 1.3 + (i % 3) * 0.4, Color(rim_col, 0.55))
	draw_arc(Vector2.ZERO, r - 1.5, 0, TAU, 32, Color(rim_col, 0.6), 2.0)
	draw_circle(Vector2(-6, -7), 5.0, Color(1, 1, 1, 0.3))
	# пузырьки поднимаются вверх и лопаются
	for i in 4:
		var k := fmod(t * 0.9 + i * 0.25, 1.0)
		var b := Vector2(-12.0 + i * 8.0 + sin(t * 4.0 + i) * 2.0, -r * 0.4 - k * 26.0)
		draw_arc(b, 1.8 + 1.4 * k, 0, TAU, 10, Color(foam, 0.85 * (1.0 - k)), 1.2)
	# лицо: глазки щурятся от газа, в прыжке рот открыт — «пш-ш»
	var face := Vector2(0, -3)
	for side in [-1.0, 1.0]:
		var e: Vector2 = face + Vector2(side * 5.5, -1)
		draw_circle(e, 2.6, Color.WHITE)
		draw_circle(e + Vector2(0.3, 0.6), 1.4, Color.BLACK)
		draw_line(e + Vector2(-side * 3.4, -3.6), e + Vector2(side * 2.2, -3.4), outline, 1.4)
	if st == St.JUMP or st == St.CROUCH:
		draw_circle(face + Vector2(0, 6), 3.0, outline)
		draw_circle(face + Vector2(0, 6), 1.6, Color(foam, 0.9))
	else:
		draw_arc(face + Vector2(0, 3), 3.5, 0.3, PI - 0.3, 8, outline, 1.3)
