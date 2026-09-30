extends Node2D
## Матрёшка (v9.0) — расписная деревянная кукла из комнаты-терема. Три размера:
## - БОЛЬШАЯ: переваливается с боку на бок и неторопливо уходит от змеи. Укус раскрывает её: верх
##   и низ скорлупки разлетаются, а изнутри выскакивают ДВЕ средние — кукла «делится»;
## - СРЕДНЯЯ: удирает зигзагом и держится подальше от углов (в углу её легко поймать). Укус —
##   из неё выскакивает малышка;
## - МАЛЫШКА: самая маленькая и цельная, у неё нет шва — и она не убегает, а нападает. v12.4 — юла:
##   подбирается к змее, раскручивается на месте (на полу — полоса-дорожка «здесь пройдёт» со стрелкой),
##   срывается волчком по прямой, отскакивая от бортика, и сбивает всех на пути; за ней вьётся стружка.
##   Докрутившись, шатается (зелёная кромка «окно, бей»). Пока крутится — не укусить, пока шатается — можно.
##   Раньше малышка прыгала с кольцом приземления — точь-в-точь таблетка; теперь у неё своя атака.
## Только что выскочившая кукла полсекунды неуязвима — она вылетает из скорлупки.
## Кооператив (squad.gd): хоровод с лентами вокруг змеи, разбег в разные стороны после раскола,
## заслон для переводящей дух малышки, дуэт малышек на Ультра.

signal sound(sound_name: String)
signal landed(pos: Vector2)  # юла докрутилась и встала — директор раскрывает соседок рядом

const Tex = preload("res://scripts/gfx/tex.gd")
const Design = preload("res://scripts/ui/design.gd")

enum Size { TINY, MIDDLE, BIG }
enum St { ROAM, POP, CROUCH, SPIN, DAZED }  # CROUCH — раскрутка на месте, SPIN — юла в пути

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
const CRUSH_RADIUS := 38.0   # докрутилась — раскрывает соседок в этом круге
const SPIN_REACH := 380.0    # длина пути юлы
const SPIN_TIME := 0.7       # сколько юла в пути, с
const SPIN_HIT := 16.0       # ширина полосы: касание головы в пределах radius + SPIN_HIT
const ATTACK_RANGE := 300.0
const TRAIL := 12            # точек в следе стружки
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
var height := 0.0              # у юлы всегда 0 (повтор и отладка читают поле)
var spin_path := PackedVector2Array()  # путь юлы: старт, (отскок от бортика), финиш — выбран при раскрутке
var spin_len := 0.0
var spin_time := SPIN_TIME
var spin_angle := 0.0          # угол вращения для рисунка
var spin_hit_done := false     # за один проход юла бьёт змею один раз
var trail: Array[Vector2] = [] # след стружки
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
	return st != St.SPIN and st != St.POP and spawn_k > 0.85


func is_spinning() -> bool:
	return st == St.SPIN


## Прежнее имя «в воздухе» (в прыжке не укусить) — теперь юла в пути. Им пользуются отряд и тесты.
func in_air() -> bool:
	return is_spinning()


func is_dazed() -> bool:
	return st == St.DAZED


## Оглушить (ударная волна, рывок сквозь хоровод): стоит и переводит дух.
func daze(time: float) -> void:
	if st == St.SPIN or st == St.POP:
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
		St.CROUCH:  # раскрутка: вращение нарастает
			vel = vel.move_toward(Vector2.ZERO, 900.0 * delta)
			var k := clampf(1.0 - st_t / crouch_total, 0.0, 1.0)
			spin_angle += delta * lerpf(3.0, 32.0, k * k)
			if st_t <= 0.0:
				st = St.SPIN
				spin_time = SPIN_TIME * clampf(tempo, 0.7, 1.2)
				st_t = spin_time
				spin_hit_done = false
				trail.clear()
				sound.emit("doll_spin")
		St.SPIN:  # волчком по пути: быстро со старта, к концу замедляется
			var k := clampf(1.0 - st_t / spin_time, 0.0, 1.0)
			position = path_point((1.0 - (1.0 - k) * (1.0 - k)) * spin_len)
			spin_angle += delta * lerpf(34.0, 16.0, k)
			trail.push_front(position)
			if trail.size() > TRAIL:
				trail.pop_back()
			if st_t <= 0.0:
				position = spin_path[spin_path.size() - 1]
				st = St.DAZED  # шатается — окно, чтобы съесть
				st_t = 1.1 * clampf(tempo, 0.6, 1.3)
				squash = 0.7
				landed.emit(position)
				sound.emit("doll_land")
		St.DAZED:
			vel = vel.move_toward(Vector2.ZERO, 600.0 * delta)
			if st_t <= 0.0:
				st = St.ROAM
				attack_cd = randf_range(1.3, 2.2) * tempo / clampf(aggr, 0.6, 2.0)
	if st == St.DAZED and not trail.is_empty():
		trail.pop_back()  # след стружки оседает
	if st != St.SPIN:
		position += vel * delta
		var inner := bounds.grow(-radius() - 6.0)
		if position.x < inner.position.x or position.x > inner.end.x:
			vel.x = -vel.x
		if position.y < inner.position.y or position.y > inner.end.y:
			vel.y = -vel.y
		position = position.clamp(inner.position, inner.end)
	rock += delta * (3.0 + vel.length() * 0.05)
	refresh_look()


## Перерисовка только при изменении вида: в покое кукла лишь покачивается (шагами по 0,02 рад — почти
## незаметно), в любом другом состоянии — прыжок, присед, оглушение, хоровод, вспышка — рисуется каждый кадр.
var _last_look: Array = []


func refresh_look() -> void:
	var busy := st != St.ROAM or dancing or coop_tag > 0.0 or squash > 0.0 or hit_flash > 0.0 or spawn_k < 1.0
	var look := [int(sin(rock) * 50.0), set_id, size]
	if busy or look != _last_look:
		_last_look = look
		queue_redraw()


## Технический режим «Контакт»: без прыжков и хоровода — переваливается со скоростью want.
func calm_update(delta: float, want: Vector2) -> void:
	t += delta
	st = St.ROAM
	dancing = false
	ribbon_to = null
	order_pos = Vector2.INF
	sync_jump = -1.0
	coop_tag = 0.0
	height = 0.0
	squash = maxf(squash - delta * 3.0, 0.0)
	hit_flash = maxf(hit_flash - delta * 3.0, 0.0)
	vel = vel.lerp(want, 4.0 * delta)
	position += vel * delta
	var inner := bounds.grow(-radius() - 6.0)
	position = position.clamp(inner.position, inner.end)
	rock += delta * (3.0 + vel.length() * 0.05)
	refresh_look()


## Раскрутиться перед рывком. Путь выбирается сейчас и больше не меняется — полоса честная.
## Юла целится туда, где будет голова, и проносится дальше, на всю длину пути; у бортика отскакивает.
func crouch(head: Vector2, head_vel: Vector2) -> void:
	st = St.CROUCH
	crouch_total = 0.55 * clampf(tempo, 0.6, 1.3)
	st_t = crouch_total
	var lead := head + head_vel * (crouch_total + 0.3) * clampf(0.3 * aggr, 0.15, 0.6) + jump_offset
	var dir := (lead - position).normalized() if lead.distance_to(position) > 1.0 else Vector2.RIGHT
	spin_path = plan_path(position, dir, SPIN_REACH, bounds.grow(-radius() - 10.0))
	spin_len = 0.0
	for i in spin_path.size() - 1:
		spin_len += spin_path[i].distance_to(spin_path[i + 1])
	jump_offset = Vector2.ZERO
	sound.emit("doll_giggle")


## Путь волчка от from в сторону dir длиной reach внутри inner: при встрече с бортиком — один отскок.
static func plan_path(from: Vector2, dir: Vector2, reach: float, inner: Rect2) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var p := from.clamp(inner.position, inner.end)
	var d := dir.normalized()
	var left := reach
	for bounce in 2:
		var tx := INF
		var ty := INF
		if d.x > 0.0001:
			tx = (inner.end.x - p.x) / d.x
		elif d.x < -0.0001:
			tx = (inner.position.x - p.x) / d.x
		if d.y > 0.0001:
			ty = (inner.end.y - p.y) / d.y
		elif d.y < -0.0001:
			ty = (inner.position.y - p.y) / d.y
		var hit := minf(tx, ty)
		if hit >= left or bounce == 1:
			pts.append(p + d * minf(left, maxf(hit, 0.0)))
			break
		p += d * hit
		pts.append(p)
		left -= hit
		if tx < ty:
			d.x = -d.x
		else:
			d.y = -d.y
	return pts


## Точка на пути юлы на расстоянии dist от старта.
func path_point(dist: float) -> Vector2:
	var left := dist
	for i in spin_path.size() - 1:
		var seg := spin_path[i].distance_to(spin_path[i + 1])
		if left <= seg or i == spin_path.size() - 2:
			return spin_path[i].lerp(spin_path[i + 1], clampf(left / maxf(seg, 0.001), 0.0, 1.0))
		left -= seg
	return spin_path[0] if not spin_path.is_empty() else position


## Касается ли юла в пути точки p (голова змеи, медведь): p в полосе радиуса radius() + extra.
func spin_touches(p: Vector2, extra := SPIN_HIT) -> bool:
	return is_spinning() and position.distance_to(p) < radius() + extra


## До рывка осталось (0..1) — для стрелки на полосе: раскрутка — первая половина, путь — вторая.
func strike_progress() -> float:
	if st == St.CROUCH:
		return clampf(1.0 - st_t / crouch_total, 0.0, 1.0) * 0.5
	if st == St.SPIN:
		return 0.5 + 0.5 * clampf(1.0 - st_t / spin_time, 0.0, 1.0)
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
	if st in [St.CROUCH, St.SPIN] and spin_path.size() > 1:  # «здесь пройдёт»: полоса-дорожка юлы
		var local := PackedVector2Array()
		for p in spin_path:
			local.append(p - position)
		Design.draw_tell_lane(self, local, (r + SPIN_HIT) * 2.0, Design.Tell.AIM, strike_progress())
	if not trail.is_empty():
		_draw_trail(r)
	if st == St.DAZED and size == Size.TINY:  # «окно, бей»: сплошная кромка
		Design.draw_open_arc(self, Vector2(0, 4), r + 8.0, clampf(st_t / (1.1 * clampf(tempo, 0.6, 1.3)), 0.0, 1.0))
	if dancing and is_instance_valid(ribbon_to):
		_draw_ribbon(ribbon_to.position - position)
	var shadow_k := 1.0
	Tex.blob(self, Vector2(3, r * 0.75), Vector2(r * 1.05, r * 0.55) * shadow_k * maxf(spawn_k, 0.3), Color(0, 0, 0, 0.28 * shadow_k))
	var sc := Vector2.ONE * s
	match st:
		St.CROUCH:
			var k := 1.0 - st_t / crouch_total
			sc *= Vector2(1.0 + 0.22 * k, 1.0 - 0.25 * k)
			sc += Vector2(randf_range(-0.02, 0.02), 0)
		St.SPIN:  # волчок: кукла «сплющивается» по мере поворота — видно вращение
			sc *= Vector2(0.7 + 0.3 * absf(cos(spin_angle)), 1.0)
	if st == St.CROUCH:
		sc.x *= 0.75 + 0.25 * absf(cos(spin_angle))
	if squash > 0.0:
		sc *= Vector2(1.0 + 0.3 * squash, 1.0 - 0.25 * squash)
	var tilt := sin(rock) * (0.16 if size == Size.BIG else 0.1)
	if st == St.DAZED:
		tilt = sin(t * 9.0) * (0.34 if size == Size.TINY else 0.2)  # юла шатается сильнее
	elif st == St.SPIN:
		tilt = sin(spin_angle * 0.23) * 0.22  # волчок прецессирует
	elif dancing:
		tilt = sin(t * 7.0) * 0.12
	draw_set_transform(Vector2(0, -height), tilt, sc)
	draw_doll(self, sarafan(), scarf(), size != Size.TINY, _face_mode(), dancing, hit_flash)
	if st == St.SPIN or (st == St.CROUCH and strike_progress() > 0.2):
		_draw_swirl(maxf(strike_progress(), 0.3))
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
		St.CROUCH, St.SPIN:
			return 1
	return 0


## Вихрь росписи вокруг вращающейся юлы: дуги сарафана и золота бегут по кругу.
func _draw_swirl(k: float) -> void:
	for i in 3:
		var a := -spin_angle * 1.3 + TAU * i / 3.0
		draw_arc(Vector2(0, 2), 25.0, a, a + 1.4, 10, Color(sarafan().lightened(0.2), 0.55 * k), 3.0)
		draw_arc(Vector2(0, 2), 29.0, a + 0.5, a + 1.3, 8, Color(GOLD, 0.7 * k), 2.0)


## След стружки: золотые завитки и щепочки там, где прошла юла, тают к хвосту.
func _draw_trail(r: float) -> void:
	for i in trail.size():
		var p: Vector2 = trail[i] - position
		var a := 1.0 - float(i) / TRAIL
		var curl := 3.0 + (i % 3) * 1.5
		draw_arc(p + Vector2(0, r * 0.6), curl, spin_angle * 0.5 + i, spin_angle * 0.5 + i + 4.2, 8,
			Color(0.93, 0.75, 0.45, 0.8 * a), 1.6)
		if i % 2 == 0:
			draw_circle(p + Vector2(0, r * 0.7) + Vector2.from_angle(i * 2.1) * 6.0, 1.6, Color(GOLD, 0.7 * a))


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
