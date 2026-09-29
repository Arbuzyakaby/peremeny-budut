extends Node2D
## Матрёшка (v9.0) — расписная деревянная кукла из комнаты-терема. Три размера:
## - БОЛЬШАЯ: переваливается с боку на бок и неторопливо уходит от змеи. Укус раскрывает её: верх
##   и низ скорлупки разлетаются, а изнутри выскакивают ДВЕ средние — кукла «делится»;
## - СРЕДНЯЯ: удирает зигзагом и держится подальше от углов (в углу её легко поймать). Укус —
##   из неё выскакивает малышка;
## - МАЛЫШКА: самая маленькая и цельная, у неё нет шва — и она не убегает, а нападает. Подбирается
##   к змее, приседает (на полу кольцо «здесь ударит» со стрелкой часов), прыгает и давит;
##   приземлившись, переводит дух (зелёная кромка «окно, бей»). В прыжке неуязвима, на земле — съедобна.
## Только что выскочившая кукла полсекунды неуязвима — она вылетает из скорлупки.
## Кооператив (squad.gd): хоровод с лентами вокруг змеи, разбег в разные стороны после раскола,
## заслон для переводящей дух малышки, дуэт малышек на Ультра.

signal sound(sound_name: String)
signal landed(pos: Vector2)  # малышка приземлилась — директор решает, кого задавило

const Tex = preload("res://scripts/gfx/tex.gd")
const Design = preload("res://scripts/ui/design.gd")

enum Size { TINY, MIDDLE, BIG }
enum St { ROAM, POP, CROUCH, JUMP, DAZED }

## Размеры: имя, ключ карточки картотеки, радиус тела, масштаб рисунка, скорость.
const SIZES := [
	{"name": "Малышка", "key": "doll_0", "radius": 14.0, "scale": 0.6, "speed": 92.0},
	{"name": "Средняя", "key": "doll_1", "radius": 21.0, "scale": 0.88, "speed": 122.0},
	{"name": "Большая", "key": "doll_2", "radius": 29.0, "scale": 1.22, "speed": 48.0},
]
## Росписи наборов: у каждого набора свой ряд сарафанов (большая → средняя → малышка) и платков.
const SARAFANS := [
	[Color(0.8, 0.1, 0.1), Color(0.14, 0.36, 0.72), Color(0.95, 0.68, 0.12)],
	[Color(0.12, 0.45, 0.28), Color(0.78, 0.12, 0.2), Color(0.95, 0.48, 0.16)],
	[Color(0.2, 0.3, 0.7), Color(0.9, 0.62, 0.1), Color(0.82, 0.18, 0.4)],
	[Color(0.55, 0.12, 0.35), Color(0.12, 0.5, 0.55), Color(0.9, 0.3, 0.15)],
]
const SCARVES := [Color(0.98, 0.8, 0.22), Color(0.96, 0.42, 0.18), Color(0.2, 0.5, 0.85), Color(0.92, 0.2, 0.25)]
const SKIN := Color(1.0, 0.88, 0.76)
const INK := Color(0.16, 0.08, 0.05)
const GOLD := Color(0.98, 0.78, 0.25)
const CRUSH_RADIUS := 38.0
const JUMP_HEIGHT := 95.0
const HOP_REACH := 280.0
const ATTACK_RANGE := 300.0
const POP_TIME := 0.5

var size := Size.BIG
var st := St.ROAM
var st_t := 0.0
var bounds := Rect2(0, 0, 1280, 720)
var speed := 48.0
var aggr := 1.0
var tempo := 1.0
var vel := Vector2.ZERO
var t := 0.0
var rock := 0.0          # переваливание с боку на бок
var spawn_k := 0.0
var set_id := 0          # номер набора: набор собран, когда съедена последняя малышка
var paint := 0           # роспись набора (индекс в SARAFANS)
var attack_cd := 1.5
var height := 0.0
var jump_from := Vector2.ZERO
var jump_to := Vector2.ZERO
var air_time := 0.55
var crouch_total := 0.55
var squash := 0.0
var wander_t := 0.0
var hit_flash := 0.0
## Кооператив (squad.gd).
var order_pos := Vector2.INF   # встать в точку: место в хороводе или заслон малышки
var dancing := false           # водит хоровод: руки подняты, лента к соседке
var ribbon_to: Node2D = null   # лента хоровода — к этой кукле (null — здесь просвет)
var scatter_dir := Vector2.ZERO  # разбег после раскола: бежать сюда
var scatter_t := 0.0
var jump_offset := Vector2.ZERO  # дуэт: прыгнуть со сдвигом вбок от змеи
var sync_jump := -1.0          # дуэт: присесть через столько секунд (−1 — решает сама)
var coop_tag := 0.0            # «!!» над малышкой в дуэте (только Ультра)
var _grow: Tween


func setup(pos: Vector2, area: Rect2, doll_size: int, idle_tempo: float, aggression: float, speed_mult := 1.0) -> void:
	position = pos
	bounds = area
	size = doll_size as Size
	tempo = idle_tempo
	aggr = aggression
	speed = float(spec()["speed"]) * speed_mult
	attack_cd = randf_range(1.0, 1.8) * tempo
	rock = randf() * TAU
	vel = Vector2.from_angle(randf() * TAU) * speed * 0.5
	material = Tex.material(Tex.Mat.PLASTIC, randf() * 10.0)  # лак: мелкая крапинка
	_grow = create_tween()
	_grow.tween_property(self, "spawn_k", 1.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Выскочить из раскрытой скорлупки: полсекунды неуязвима, летит наружу.
func pop_out(dir: Vector2) -> void:
	st = St.POP
	st_t = POP_TIME
	vel = dir * (230.0 + 60.0 * randf())
	if _grow:
		_grow.kill()
	spawn_k = 0.3  # вырастает в update(): вместе с неуязвимостью, а не отдельным таймером


func spec() -> Dictionary:
	return SIZES[size]


func radius() -> float:
	return spec()["radius"]


func bestiary_key() -> String:
	return spec()["key"]


## Цвет сарафана этой куклы (у каждой в наборе — свой).
func sarafan() -> Color:
	var row: Array = SARAFANS[paint % SARAFANS.size()]
	return row[2 - int(size)]


func scarf() -> Color:
	return SCARVES[(paint + int(size)) % SCARVES.size()]


## Малышка — последняя, цельная: её съедают, а не раскрывают.
func is_last() -> bool:
	return size == Size.TINY


## Можно укусить: на земле и уже выбралась из скорлупки.
func can_bite() -> bool:
	return st != St.JUMP and st != St.POP and spawn_k > 0.85


func in_air() -> bool:
	return st == St.JUMP


func is_dazed() -> bool:
	return st == St.DAZED


## Оглушить (ударная волна, рывок сквозь хоровод): стоит и переводит дух.
func daze(time: float) -> void:
	if st == St.JUMP or st == St.POP:
		return
	st = St.DAZED
	st_t = time
	vel *= 0.3
	leave_dance()


## Выйти из хоровода (отряд или срыв).
func leave_dance() -> void:
	dancing = false
	ribbon_to = null
	order_pos = Vector2.INF


func update(delta: float, head: Vector2, head_vel: Vector2, snake_alive: bool) -> void:
	t += delta
	st_t -= delta
	attack_cd -= delta
	scatter_t = maxf(scatter_t - delta, 0.0)
	squash = maxf(squash - delta * 3.0, 0.0)
	hit_flash = maxf(hit_flash - delta * 3.0, 0.0)
	coop_tag = maxf(coop_tag - delta, 0.0)
	match st:
		St.POP:
			vel = vel.move_toward(Vector2.ZERO, 420.0 * delta)
			var k := 1.0 - clampf(st_t / POP_TIME, 0.0, 1.0)
			spawn_k = 0.3 + 0.7 * k + 0.25 * sin(k * PI)  # с упругим перелётом
			if st_t <= 0.0:
				st = St.ROAM
				spawn_k = 1.0
		St.ROAM:
			_move(delta, head, snake_alive)
			if size == Size.TINY and snake_alive and spawn_k > 0.9:
				if sync_jump >= 0.0:
					sync_jump -= delta
					if sync_jump < 0.0:
						crouch(head, head_vel)
				elif attack_cd <= 0.0 and position.distance_to(head) < ATTACK_RANGE and not dancing:
					crouch(head, head_vel)
		St.CROUCH:
			vel = vel.move_toward(Vector2.ZERO, 900.0 * delta)
			if st_t <= 0.0:
				st = St.JUMP
				air_time = 0.55 * clampf(tempo, 0.7, 1.2)
				st_t = air_time
				jump_from = position
				sound.emit("doll_hop")
		St.JUMP:
			var k := clampf(1.0 - st_t / air_time, 0.0, 1.0)
			position = jump_from.lerp(jump_to, k)
			height = sin(k * PI) * JUMP_HEIGHT
			if st_t <= 0.0:
				height = 0.0
				position = jump_to
				st = St.DAZED  # перевести дух — окно, чтобы съесть
				st_t = 1.1 * clampf(tempo, 0.6, 1.3)
				squash = 1.0
				landed.emit(position)
				sound.emit("doll_land")
		St.DAZED:
			vel = vel.move_toward(Vector2.ZERO, 600.0 * delta)
			if st_t <= 0.0:
				st = St.ROAM
				attack_cd = randf_range(1.3, 2.2) * tempo / clampf(aggr, 0.6, 2.0)
	if st != St.JUMP:
		position += vel * delta
		var inner := bounds.grow(-radius() - 6.0)
		if position.x < inner.position.x or position.x > inner.end.x:
			vel.x = -vel.x
		if position.y < inner.position.y or position.y > inner.end.y:
			vel.y = -vel.y
		position = position.clamp(inner.position, inner.end)
	rock += delta * (3.0 + vel.length() * 0.05)
	queue_redraw()


## Присесть перед прыжком. Точка приземления выбирается сейчас и больше не меняется — кольцо честное.
func crouch(head: Vector2, head_vel: Vector2) -> void:
	st = St.CROUCH
	crouch_total = 0.55 * clampf(tempo, 0.6, 1.3)
	st_t = crouch_total
	var lead := head + head_vel * (crouch_total + 0.5) * clampf(0.3 * aggr, 0.15, 0.6) + jump_offset
	var hop := lead - position
	if hop.length() > HOP_REACH:
		hop = hop.normalized() * HOP_REACH
	var inner := bounds.grow(-radius() - 10.0)
	jump_to = (position + hop).clamp(inner.position, inner.end)
	jump_offset = Vector2.ZERO
	sound.emit("doll_giggle")


## До прыжка осталось (0..1) — для «стрелки часов» кольца.
func strike_progress() -> float:
	if st == St.CROUCH:
		return clampf(1.0 - st_t / crouch_total, 0.0, 1.0) * 0.5
	if st == St.JUMP:
		return 0.5 + 0.5 * clampf(1.0 - st_t / air_time, 0.0, 1.0)
	return 0.0


func _move(delta: float, head: Vector2, snake_alive: bool) -> void:
	var to := head - position
	var dist := to.length()
	var want := Vector2.ZERO
	var k := 4.0
	if order_pos != Vector2.INF:  # приказ отряда: место в хороводе или заслон
		var to_goal := order_pos - position
		var hurry := maxf(speed * 1.4, 190.0)  # в хоровод и в заслон бегут бегом — даже большая
		want = to_goal.normalized() * minf(hurry, to_goal.length() * 6.0) if to_goal.length() > 4.0 else Vector2.ZERO
		vel = vel.lerp(want, 5.0 * delta)
		return
	if scatter_t > 0.0:  # разбег: каждая в свою сторону
		vel = vel.lerp(scatter_dir * speed * 1.6, 5.0 * delta)
		return
	if not snake_alive:
		dist = 9999.0
	match size:
		Size.BIG:
			if dist < 230.0:
				want = -to.normalized() * speed * 1.3
			else:
				want = _wander(delta, 0.6)
				k = 1.5
		Size.MIDDLE:
			if dist < 340.0:  # удирает зигзагом, заворачивая к центру поля
				var away := -to.normalized()
				var center := (bounds.get_center() - position) / (bounds.size.x * 0.5)
				var dir := (away + away.orthogonal() * sin(t * 6.0) * 0.7 + center * 0.9).normalized()
				want = dir * speed * 1.5
			else:
				want = _wander(delta, 0.7)
				k = 2.0
		Size.TINY:
			if dist < 9000.0:  # подбирается на дистанцию прыжка и кружит
				var keep := clampf((dist - 190.0) / 80.0, -1.0, 1.0)
				want = (to.normalized() * keep + to.normalized().orthogonal() * 0.6).normalized() * speed * 1.2
			else:
				want = _wander(delta, 0.8)
	want += _wall_push() * speed
	vel = vel.lerp(want, k * delta)


func _wander(delta: float, mult: float) -> Vector2:
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = randf_range(1.2, 2.6)
		vel = Vector2.from_angle(randf() * TAU) * speed * mult
	return vel


## Отталкивание от бортиков: не забиваться в угол.
func _wall_push() -> Vector2:
	var p := Vector2.ZERO
	var m := 70.0
	var inner := bounds.grow(-radius())
	p.x += clampf((inner.position.x + m - position.x) / m, 0.0, 1.0) - clampf((position.x - (inner.end.x - m)) / m, 0.0, 1.0)
	p.y += clampf((inner.position.y + m - position.y) / m, 0.0, 1.0) - clampf((position.y - (inner.end.y - m)) / m, 0.0, 1.0)
	return p * 1.2


# ---------------------------------------------------------------- рисунок

func _draw() -> void:
	var s: float = spec()["scale"] * spawn_k
	var r := radius()
	if st in [St.CROUCH, St.JUMP]:  # «здесь ударит»: кольцо на месте приземления со стрелкой часов
		Design.draw_tell_ring(self, jump_to - position, CRUSH_RADIUS, Design.Tell.AREA, strike_progress())
	elif st == St.DAZED and size == Size.TINY:  # «окно, бей»: сплошная кромка
		Design.draw_open_arc(self, Vector2(0, 4), r + 8.0, clampf(st_t / (1.1 * clampf(tempo, 0.6, 1.3)), 0.0, 1.0))
	if dancing and is_instance_valid(ribbon_to):
		_draw_ribbon(ribbon_to.position - position)
	var shadow_k := 1.0 - height / (JUMP_HEIGHT * 1.6)
	Tex.blob(self, Vector2(3, r * 0.75), Vector2(r * 1.05, r * 0.55) * shadow_k * maxf(spawn_k, 0.3), Color(0, 0, 0, 0.28 * shadow_k))
	var sc := Vector2.ONE * s
	match st:
		St.CROUCH:
			var k := 1.0 - st_t / crouch_total
			sc *= Vector2(1.0 + 0.22 * k, 1.0 - 0.25 * k)
			sc += Vector2(randf_range(-0.02, 0.02), 0)
		St.JUMP:
			sc *= Vector2(0.88, 1.14)
	if squash > 0.0:
		sc *= Vector2(1.0 + 0.3 * squash, 1.0 - 0.25 * squash)
	var tilt := sin(rock) * (0.16 if size == Size.BIG else 0.1)
	if st == St.DAZED:
		tilt = sin(t * 9.0) * 0.2
	elif dancing:
		tilt = sin(t * 7.0) * 0.12
	draw_set_transform(Vector2(0, -height), tilt, sc)
	draw_doll(self, sarafan(), scarf(), size != Size.TINY, _face_mode(), dancing, hit_flash)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if st == St.DAZED:  # звёздочки над головой
		for i in 3:
			var a := t * 4.0 + TAU * i / 3.0
			var p := Vector2(cos(a) * r * 0.8, -r * 1.3 - height + sin(a) * 4.0)
			draw_circle(p, 2.6, GOLD)
	if coop_tag > 0.0:
		draw_string(Design.font("heavy"), Vector2(-9, -r * 1.6 - height), "!!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(Design.danger(), minf(coop_tag * 2.0, 1.0)))


func _face_mode() -> int:
	match st:
		St.DAZED:
			return 2
		St.CROUCH, St.JUMP:
			return 1
	return 0


## Лента хоровода к соседке: волнистая, красная с золотой каймой.
func _draw_ribbon(to: Vector2) -> void:
	var from := Vector2(0, -2)
	var pts := PackedVector2Array()
	var n := 14
	var side := (to - from).normalized().orthogonal()
	for i in n + 1:
		var k := float(i) / n
		pts.append(from.lerp(to + Vector2(0, -2), k) + side * sin(k * TAU * 2.0 + t * 6.0) * 5.0 * sin(k * PI))
	draw_polyline(pts, Color(0.35, 0.05, 0.05, 0.5), Design.telegraph_width(6.0))
	draw_polyline(pts, Color(0.85, 0.12, 0.14), Design.telegraph_width(4.0))
	draw_polyline(pts, Color(GOLD, 0.8), 1.2)


## Матрёшка спереди, в своих координатах (центр — пояс). seam — шов, по которому кукла
## раскрывается (у малышки его нет: она цельная). face: 0 — улыбка, 1 — злая (замах, прыжок),
## 2 — глаза-крестики. Статическая — ей же пользуются иконки и скорлупки.
static func draw_doll(ci: CanvasItem, dress: Color, head_scarf: Color, seam := true, face := 0, arms_up := false,
		flash := 0.0) -> void:
	var outline := dress.darkened(0.6)
	var body := dress.lerp(Color.WHITE, flash * 0.6)
	# силуэт: широкий низ, талия, голова
	ci.draw_circle(Vector2(0, 7), 22.5, outline)
	ci.draw_circle(Vector2(0, -12), 15.0, outline)
	ci.draw_colored_polygon(_waist(1.5), outline)
	ci.draw_circle(Vector2(0, 7), 21.0, body)
	ci.draw_colored_polygon(_waist(0.0), body)
	ci.draw_circle(Vector2(0, -12), 13.5, head_scarf.lerp(Color.WHITE, flash * 0.6))
	# руки: у пояса или подняты в хороводе
	for sd in [-1.0, 1.0]:
		var hand := Vector2(sd * 16.5, -4.0) if arms_up else Vector2(sd * 11.0, 2.0)
		ci.draw_circle(hand, 3.4, outline)
		ci.draw_circle(hand, 2.6, SKIN)
	# фартук с цветком
	ci.draw_circle(Vector2(0, 11), 13.0, Color(0.99, 0.95, 0.84))
	ci.draw_arc(Vector2(0, 11), 13.0, 0, TAU, 28, GOLD, 1.6)
	for i in 5:
		var p := Vector2(0, 11) + Vector2.from_angle(TAU * i / 5.0 - PI / 2) * 5.2
		ci.draw_circle(p, 3.6, dress.lightened(0.15))
	ci.draw_circle(Vector2(0, 11), 2.8, GOLD)
	for sd in [-1.0, 1.0]:  # листики
		ci.draw_colored_polygon(PackedVector2Array([Vector2(sd * 4, 18), Vector2(sd * 11, 16), Vector2(sd * 7, 21)]),
			Color(0.2, 0.55, 0.25))
	# шов, по которому кукла раскрывается
	if seam:
		ci.draw_arc(Vector2(0, -2), 17.0, 0.18, PI - 0.18, 20, Color(outline, 0.9), 1.4)
		ci.draw_line(Vector2(-16.5, -1.5), Vector2(16.5, -1.5), Color(1, 1, 1, 0.18), 1.0)
	# платок в горошек и узелок под подбородком
	for p in [Vector2(-9, -18), Vector2(9, -18), Vector2(-11, -9), Vector2(11, -9), Vector2(0, -24)]:
		ci.draw_circle(p, 1.5, Color(1, 1, 1, 0.75))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-5, -3), Vector2(5, -3), Vector2(0, 2)]), head_scarf.darkened(0.2))
	# лицо
	ci.draw_circle(Vector2(0, -11), 9.0, SKIN)
	ci.draw_arc(Vector2(0, -15.5), 6.5, PI + 0.35, TAU - 0.35, 10, Color(0.35, 0.18, 0.08), 3.0)  # чёлка
	for sd in [-1.0, 1.0]:
		ci.draw_circle(Vector2(sd * 5.2, -8.2), 2.4, Color(0.95, 0.45, 0.45, 0.7))  # румянец
		var e := Vector2(sd * 3.4, -11.5)
		match face:
			2:
				ci.draw_line(e - Vector2(1.6, 1.6), e + Vector2(1.6, 1.6), INK, 1.2)
				ci.draw_line(e - Vector2(1.6, -1.6), e + Vector2(1.6, -1.6), INK, 1.2)
			_:
				ci.draw_circle(e, 1.6, INK)
				ci.draw_circle(e - Vector2(0.5, 0.6), 0.6, Color.WHITE)
				ci.draw_line(e + Vector2(-1.6, -2.0), e + Vector2(-2.6, -2.8), INK, 0.8)  # реснички
				if face == 1:  # злые брови
					ci.draw_line(e + Vector2(sd * 2.2, -3.8), e + Vector2(-sd * 1.6, -2.6), INK, 1.3)
	if face == 1:
		ci.draw_rect(Rect2(-2.2, -7.6, 4.4, 2.0), Color(0.6, 0.05, 0.08))
	else:
		ci.draw_circle(Vector2(-0.9, -7.2), 1.1, Color(0.85, 0.1, 0.15))  # губки бантиком
		ci.draw_circle(Vector2(0.9, -7.2), 1.1, Color(0.85, 0.1, 0.15))
	# лак: блик слева сверху
	ci.draw_arc(Vector2(0, 7), 17.5, PI + 0.5, PI + 1.3, 8, Color(1, 1, 1, 0.35), 2.5)
	ci.draw_arc(Vector2(0, -12), 11.0, PI + 0.6, PI + 1.3, 6, Color(1, 1, 1, 0.45), 2.0)


static func _waist(grow: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-11.5 - grow, -8), Vector2(11.5 + grow, -8), Vector2(20.5 + grow, 4),
		Vector2(-20.5 - grow, 4)])
