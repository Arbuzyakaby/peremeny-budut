extends Node2D
## Ржавая вилка. Разворачивается к змее и атакует одним из приёмов своего вида:
## - ВЫПАД: прицеливается (дрожит, зубцы краснеют) и спринтует по прямой; врезавшись в бортик,
##   застревает зубцами в дереве — лучший момент ударить;
## - ЗАЛП: отстреливает зубцы веером, потом пару секунд «лысая» — спереди безопасна;
## - ВЕРТУШКА: раскручивается пропеллером и едет на змею — опасна со всех сторон, после неё
##   кружится голова, и бить можно откуда угодно;
## - ПРЫЖОК-УКОЛ: подпрыгивает, на полу загорается круг, втыкается зубцами и застревает в полу.
## Зубцы спереди опасны: атаковать вилку в лоб нельзя — только сбоку или сзади.
## Виды: столовая (сталь в рыжей ржавчине), десертная (латунь — мелкая и шустрая),
## вилы-сервировочная (тёмная бронза с патиной — крупная, медленная, прыгает).

signal sound(sound_name: String)
## Атака, которую обрабатывает директор врагов: "start" {atk}, "tines" {from, dirs}, "pogo" {at, radius}.
signal attack(kind: String, data: Dictionary)

const Tex = preload("res://scripts/gfx/tex.gd")
const Design = preload("res://scripts/ui/design.gd")

enum St { ROAM, AIM, SPRINT, STUCK, RECOVER, VOLLEY_AIM, BALD, WHIRL_UP, WHIRL, DIZZY, POGO_UP, POGO_STUCK }
enum Kind { TABLE, DESSERT, PITCH }
enum Atk { LUNGE, VOLLEY, WHIRL, POGO }

const TAIL := -46.0    # конец ручки (локально, вилка смотрит по +X)
const TIP := 40.0      # кончики зубцов
const TINES_FROM := 16.0
const HALF_WIDTH := 12.0
const SIZE := 1.35     # размер столовой вилки; у других видов свой (sz)
const POGO_RADIUS := 70.0
const WHIRL_RADIUS := 52.0

## Вид вилки: размер, скорость, число зубцов, веса атак [выпад, залп, вертушка, прыжок], краски.
const KINDS := {
	Kind.TABLE: {"name": "Столовая", "size": 1.35, "speed": 1.0, "tines": 4, "weights": [3.0, 2.0, 1.2, 1.0],
		"metal": Color(0.74, 0.72, 0.7), "edge": Color(0.24, 0.16, 0.12), "accent": Color(0.85, 0.42, 0.16), "mat": Tex.Mat.RUST},
	Kind.DESSERT: {"name": "Десертная", "size": 1.1, "speed": 1.25, "tines": 3, "weights": [3.0, 1.0, 2.2, 0.6],
		"metal": Color(0.93, 0.74, 0.36), "edge": Color(0.36, 0.2, 0.06), "accent": Color(1.0, 0.86, 0.5), "mat": Tex.Mat.PATINA},
	Kind.PITCH: {"name": "Вилы", "size": 1.7, "speed": 0.8, "tines": 2, "weights": [1.2, 1.8, 0.6, 3.0],
		"metal": Color(0.58, 0.42, 0.28), "edge": Color(0.16, 0.1, 0.06), "accent": Color(0.38, 0.78, 0.62), "mat": Tex.Mat.PATINA},
}
const ATTACK_NAMES := ["Выпад", "Залп зубцов", "Вертушка", "Прыжок-укол"]

var st := St.ROAM
var st_t := 0.0
var kind := Kind.TABLE
var sz := SIZE
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
var height := 0.0           # высота прыжка-укола
var spin := 0.0             # угол вертушки
var tines_k := 1.0          # 1 — зубцы на месте, 0 — отстреляны (отрастают)
var next_atk := Atk.LUNGE   # первая атака — всегда выпад: так игрок сразу видит главную опасность
var pogo_at := Vector2.ZERO
var pogo_from := Vector2.ZERO
var last_atk := Atk.LUNGE
## Кооператив (squad.gd): куда встать перед совместной атакой; INF — свободная охота.
var slot := Vector2.INF
var coop_tag := 0.0         # >0 — над вилкой рисуется «!!» (атака в паре; отряд ставит только на Ультра)
var rescued := 0.0          # медведь выдёргивает вилку из бортика
## Клещи (squad.gd): номер группы (0 — вне клещей), ведущая рисует просвет, дуга кольца вокруг головы.
var pincer_id := 0
var pincer_lead := false
var pincer_half := 0.0      # полуширина дуги кольца, которую перекрывает вилка (рад)
var pincer_gap_dir := Vector2.ZERO  # куда смотрит просвет — выход из клещей
var look_pos := Vector2.INF # телеграф клещей: смотрит на напарника и кивает
var look_t := 0.0
var look_total := 0.3
var last_head := Vector2.ZERO


func setup(pos: Vector2, area: Rect2, spd: float, aggression: float, idle_tempo: float, fork_kind := Kind.TABLE) -> void:
	position = pos
	bounds = area
	kind = fork_kind
	var k: Dictionary = KINDS[kind]
	sz = k["size"]
	speed_mult = spd * k["speed"]
	aggr = aggression
	tempo = idle_tempo
	rotation = randf() * TAU
	attack_cd = randf_range(1.2, 2.2) * tempo
	material = Tex.material(k["mat"], randf() * 10.0)
	create_tween().tween_property(self, "spawn_k", 1.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func facing() -> Vector2:
	return Vector2.from_angle(rotation)


func is_sprinting() -> bool:
	return st == St.SPRINT


func is_whirling() -> bool:
	return st == St.WHIRL


func in_air() -> bool:
	return st == St.POGO_UP


## Вилка беззащитна со всех сторон: застряла в полу, кружится голова или зубцы отстреляны.
func is_vulnerable() -> bool:
	return st in [St.STUCK, St.DIZZY, St.POGO_STUCK] or rescued > 0.0


## Сейчас готовит или проводит атаку (для очереди атак отряда).
func is_attacking() -> bool:
	return st in [St.AIM, St.SPRINT, St.VOLLEY_AIM, St.WHIRL_UP, St.WHIRL, St.POGO_UP]


## Вилка в клещах замахивается (переглядывается с напарником или целится): её можно прорвать спринтом.
func is_pincer_windup() -> bool:
	return pincer_id != 0 and (look_t > 0.0 or st == St.AIM)


## Телеграф клещей: повернуться к напарнику и кивнуть.
func look_at_mate(pos: Vector2, time: float) -> void:
	look_pos = pos
	look_t = time
	look_total = time


func leave_pincer() -> void:
	pincer_id = 0
	pincer_lead = false
	look_t = 0.0
	look_pos = Vector2.INF


## Змея прорвалась сквозь вилку: отлетает и оглушена — теперь беззащитна.
func knock_back(from: Vector2) -> void:
	leave_pincer()
	slot = Vector2.INF
	st = St.DIZZY
	st_t = 1.2
	vel = (position - from).normalized() * 320.0
	shake = 1.0
	sound.emit("clang")


## Клещи развалились (напарника прорвали): замах сбит, вилка теряет синхрон.
func collapse() -> void:
	leave_pincer()
	slot = Vector2.INF
	if st in [St.ROAM, St.AIM]:
		st = St.RECOVER
		st_t = 0.5
		shake = 0.8
		attack_cd = maxf(attack_cd, 1.0)


## Ближайшая к точке позиция на оси вилки: (продольная координата, расстояние до оси).
func contact(p: Vector2) -> Vector2:
	var local := (p - position).rotated(-rotation) / sz
	var s := clampf(local.x, TAIL, TIP)
	return Vector2(s, Vector2(local.x - s, local.y).length() * sz)


## Касается ли круг радиуса r вилки. В прыжке до вилки не дотянуться, вертушка задевает кругом.
func touches(p: Vector2, r: float) -> bool:
	if in_air():
		return false
	if st in [St.WHIRL, St.WHIRL_UP]:
		return p.distance_to(position) < r + WHIRL_RADIUS * sz / SIZE
	if st == St.POGO_STUCK:
		return p.distance_to(position) < r + 16.0 * sz
	return contact(p).y < r + HALF_WIDTH * 0.8 * sz


## Удар пришёлся в зубцы (спереди), а не в бок/ручку. Чистая геометрия.
func hits_tines(p: Vector2) -> bool:
	var local := (p - position).rotated(-rotation) / sz
	return local.x > TINES_FROM and absf(local.y) < local.x * 0.9


## Касание в этой точке ранит того, кто коснулся. Учитывает состояние: вертушка режет всем,
## «лысая», застрявшая в полу или оглушённая вилка — никому.
func hurts(p: Vector2) -> bool:
	if st in [St.WHIRL, St.WHIRL_UP]:
		return true
	if is_vulnerable() or st == St.BALD or tines_k < 0.5:
		return false
	return hits_tines(p)


## Начать атаку немедленно (отряд синхронизирует выпады, dev-панель проверяет атаки).
func begin_attack(a: int, head: Vector2) -> void:
	last_atk = a as Atk
	attack.emit("start", {"atk": a})
	var to_head := head - position
	match a:
		Atk.LUNGE:
			rotation = to_head.angle()
			st = St.AIM
			st_t = 0.75 * tempo
			sound.emit("fork_aim")
		Atk.VOLLEY:
			rotation = to_head.angle()
			st = St.VOLLEY_AIM
			st_t = 0.8 * tempo
			sound.emit("fork_aim")
		Atk.WHIRL:
			st = St.WHIRL_UP
			st_t = 0.7 * tempo
			sound.emit("fork_whirl")
		Atk.POGO:
			st = St.POGO_UP
			st_t = 0.95 * clampf(tempo, 0.7, 1.3)
			pogo_from = position
			pogo_at = (head + (head - position).normalized() * 10.0).clamp(bounds.grow(-60.0).position, bounds.grow(-60.0).end)
			sound.emit("fork_pogo")


## Выбрать следующий приём по весам вида; вертушку дают только с нормальной сложности.
func roll_attack() -> int:
	var w: Array = (KINDS[kind]["weights"] as Array).duplicate()
	if aggr < 0.9:
		w[Atk.WHIRL] = 0.0
	w[last_atk] *= 0.5  # реже повторяется подряд
	var total := 0.0
	for x in w:
		total += x
	var r := randf() * total
	for i in w.size():
		r -= w[i]
		if r < 0.0:
			return i
	return Atk.LUNGE


func update(delta: float, head: Vector2, snake_alive: bool) -> void:
	t += delta
	st_t -= delta
	attack_cd -= delta
	coop_tag = maxf(coop_tag - delta, 0.0)
	look_t = maxf(look_t - delta, 0.0)
	last_head = head
	if look_t > 0.0 and st == St.ROAM:  # клещи: подпрыгивает, кивая напарнику
		height = sin((1.0 - look_t / look_total) * PI) * 10.0
	elif st != St.POGO_UP:
		height = 0.0
	shake = maxf(shake - delta * 3.0, 0.0)
	if st != St.BALD:
		tines_k = minf(tines_k + delta * 0.8, 1.0)
	var to_head := head - position
	match st:
		St.ROAM:
			var want := to_head.angle()
			if look_t > 0.0 and look_pos != Vector2.INF:  # клещи: смотрит на напарника
				rotation = rotate_toward(rotation, (look_pos - position).angle(), 14.0 * delta)
			else:
				rotation = rotate_toward(rotation, want, 1.6 * delta * speed_mult)
			if slot != Vector2.INF:  # отряд велел занять позицию для атаки в паре
				var to_slot := slot - position
				vel = vel.lerp(to_slot.limit_length(1.0) * minf(to_slot.length() * 2.0, 220.0 * speed_mult), 3.0 * delta)
			else:
				vel = vel.lerp(facing() * 45.0 * speed_mult, 2.0 * delta)
				if to_head.length() < 150.0:  # слишком близко — пятится
					vel = vel.lerp(-to_head.normalized() * 90.0, 3.0 * delta)
			if snake_alive and slot == Vector2.INF and attack_cd <= 0.0 and to_head.length() < 700.0 \
					and (absf(angle_difference(rotation, want)) < 0.25 or next_atk in [Atk.WHIRL, Atk.POGO]):
				begin_attack(next_atk, head)
				next_atk = roll_attack() as Atk
		St.AIM:
			vel = vel.move_toward(Vector2.ZERO, 300.0 * delta)
			# доводит прицел; в клещах — почти не доводит, чтобы просвет оставался выходом
			rotation = rotate_toward(rotation, to_head.angle(), (0.3 if pincer_id != 0 else 0.9) * delta)
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
		St.VOLLEY_AIM:
			vel = vel.move_toward(Vector2.ZERO, 300.0 * delta)
			rotation = rotate_toward(rotation, to_head.angle(), 1.4 * delta)
			if st_t <= 0.0:
				_fire_tines()
		St.BALD:
			vel = vel.move_toward(-facing() * 60.0, 200.0 * delta)  # отдача
			if st_t <= 0.0:
				st = St.RECOVER
				st_t = 0.3
		St.WHIRL_UP:
			vel = vel.move_toward(Vector2.ZERO, 300.0 * delta)
			spin += delta * lerpf(4.0, 26.0, 1.0 - clampf(st_t / (0.7 * tempo), 0.0, 1.0))
			rotation = spin
			if st_t <= 0.0:
				st = St.WHIRL
				st_t = 1.6 + 0.3 * aggr
		St.WHIRL:
			spin += delta * 26.0
			rotation = spin
			vel = vel.lerp(to_head.normalized() * (200.0 + 40.0 * aggr) * speed_mult, 1.6 * delta)
			if st_t <= 0.0:
				st = St.DIZZY
				st_t = 1.6 * clampf(tempo, 0.8, 1.3)
				vel *= 0.3
		St.DIZZY:
			vel = vel.move_toward(Vector2.ZERO, 250.0 * delta)
			rotation += sin(t * 9.0) * delta * 3.0
			if st_t <= 0.0:
				st = St.RECOVER
				st_t = 0.2
		St.POGO_UP:
			var total := 0.95 * clampf(tempo, 0.7, 1.3)
			var k := 1.0 - clampf(st_t / total, 0.0, 1.0)
			position = pogo_from.lerp(pogo_at, k)
			height = sin(k * PI) * 170.0
			rotation = rotate_toward(rotation, (pogo_at - pogo_from).angle(), 6.0 * delta)
			vel = Vector2.ZERO
			if st_t <= 0.0:
				height = 0.0
				position = pogo_at
				st = St.POGO_STUCK
				st_t = 1.5 * clampf(tempo, 0.8, 1.3)
				shake = 1.0
				sound.emit("fork_thud")
				attack.emit("pogo", {"at": position, "radius": POGO_RADIUS})
		St.POGO_STUCK, St.STUCK:
			vel = Vector2.ZERO
			if rescued > 0.0:  # медведь-помощник выдёргивает быстрее
				st_t -= delta * 2.0
			if st_t <= 0.0:
				if st == St.STUCK:
					rotation += PI  # выдёргивает зубцы и разворачивается
				st = St.RECOVER
				st_t = 0.4
				rescued = 0.0
		St.RECOVER:
			vel = vel.move_toward(Vector2.ZERO, 700.0 * delta)
			if st_t <= 0.0:
				st = St.ROAM
				attack_cd = randf_range(1.4, 2.6) * tempo / clampf(aggr, 0.6, 2.0)

	rescued = maxf(rescued - delta, 0.0)
	if pincer_id != 0 and not st in [St.ROAM, St.AIM]:  # выпад пошёл — клещи закончились
		leave_pincer()
	if st != St.POGO_UP:
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


func _fire_tines() -> void:
	var n: int = KINDS[kind]["tines"]
	var count := n + (1 if aggr >= 1.5 else 0)
	var spread := 0.22 + 0.05 * count
	var dirs: Array[Vector2] = []
	for i in count:
		var k := 0.0 if count == 1 else float(i) / (count - 1) - 0.5
		dirs.append(facing().rotated(k * spread * 2.0))
	st = St.BALD
	st_t = 1.3 * clampf(tempo, 0.8, 1.3)
	tines_k = 0.0
	sound.emit("fork_volley")
	attack.emit("tines", {"from": position + facing() * TIP * sz, "dirs": dirs})


## Вилка отскочила от чего-то (яичницы, змеи).
func bounce() -> void:
	if st == St.POGO_UP:
		return
	st = St.RECOVER
	st_t = 0.7
	vel = -vel * 0.3
	shake = 0.6


func _draw() -> void:
	var s := spawn_k * sz
	var k: Dictionary = KINDS[kind]
	var jitter := Vector2.ZERO
	if st in [St.AIM, St.VOLLEY_AIM]:
		jitter = Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	if st in [St.STUCK, St.POGO_STUCK]:
		jitter = Vector2(0, sin(t * 60.0) * 2.5 * shake)
	# прицел: пунктир траектории (выпад) или веер (залп)
	if st == St.AIM:
		var ka := 1.0 - st_t / (0.75 * tempo)
		for i in 14:
			var x := TIP * sz + 20.0 + i * 38.0
			draw_line(Vector2(x, 0), Vector2(x + 18.0, 0), Color(Design.danger(), 0.5 * ka), Design.telegraph_width(4.0))
	elif st == St.VOLLEY_AIM:
		var kv := 1.0 - st_t / (0.8 * tempo)
		var n: int = k["tines"] + (1 if aggr >= 1.5 else 0)
		var spread := 0.22 + 0.05 * n
		for j in n:
			var kk := 0.0 if n == 1 else float(j) / (n - 1) - 0.5
			var d := Vector2.from_angle(kk * spread * 2.0)
			for i in 6:
				var a := d * (TIP * sz + 24.0 + i * 34.0)
				draw_line(a, a + d * 14.0, Color(Design.warn(), 0.55 * kv), Design.telegraph_width(3.0))
	# круг-телеграф прыжка на полу — в мировых координатах
	if st == St.POGO_UP:
		var total := 0.95 * clampf(tempo, 0.7, 1.3)
		var kp := 1.0 - clampf(st_t / total, 0.0, 1.0)
		draw_set_transform((pogo_at - position).rotated(-rotation), -rotation, Vector2.ONE)
		draw_arc(Vector2.ZERO, POGO_RADIUS, 0, TAU, 40, Color(Design.danger(), 0.35 + 0.5 * kp), Design.telegraph_width(3.0))
		draw_circle(Vector2.ZERO, POGO_RADIUS * kp, Color(Design.danger(), 0.12))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if pincer_id != 0 and pincer_half > 0.0:
		_draw_pincer_ring()
	# тень: в прыжке уменьшается и отстаёт
	var sh_k := 1.0 - height / 260.0
	Tex.blob(self, (Vector2(7, 12) + Vector2(0, height * 0.35)).rotated(-rotation) + Vector2(-3, 0),
		Vector2(52, 17) * s * sh_k, Color(0, 0, 0, 0.35 * sh_k))
	if st in [St.WHIRL, St.WHIRL_UP]:  # диск вертушки
		var kw := 1.0 if st == St.WHIRL else 1.0 - clampf(st_t / (0.7 * tempo), 0.0, 1.0)
		var rr := WHIRL_RADIUS * sz / SIZE
		draw_circle(Vector2.ZERO, rr, Color(k["metal"], 0.12 * kw))
		draw_arc(Vector2.ZERO, rr, 0, TAU, 32, Color(Design.danger(), 0.45 * kw), Design.telegraph_width(2.5))
		for i in 3:
			draw_arc(Vector2.ZERO, rr * (0.55 + i * 0.18), -spin * 0.3 + i, -spin * 0.3 + i + 1.4, 12, Color(1, 1, 1, 0.25 * kw), 2.0)
	var lift := Vector2(0, -height)
	var persp := 1.0 + height / 300.0
	var body_scale := Vector2.ONE * s * persp
	if look_t > 0.0:  # кивок напарнику: зубцы дважды клюют вниз
		var nod := absf(sin((1.0 - look_t / look_total) * TAU))
		body_scale *= Vector2(1.0 - 0.22 * nod, 1.0 + 0.06 * nod)
	draw_set_transform(jitter + lift.rotated(-rotation), 0.0, body_scale)
	if st == St.POGO_STUCK:  # воткнута в пол: видна ручка сверху, зубцы ушли в доски
		_draw_stuck_top(k)
	else:
		_draw_body(k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if st == St.DIZZY:  # звёздочки над головой
		for i in 3:
			var a := t * 4.0 + TAU * i / 3.0
			var p := Vector2(cos(a) * 22.0, sin(a) * 8.0 - 34.0).rotated(-rotation)
			draw_circle(p, 3.0, Color(1, 0.95, 0.5))
	if coop_tag > 0.0:  # атака в паре
		var p2 := Vector2(0, -44.0 - height).rotated(-rotation)
		draw_set_transform(p2, -rotation, Vector2.ONE)
		draw_string(ThemeDB.fallback_font, Vector2(-11, 6), "!!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(Design.danger(), clampf(coop_tag * 3.0, 0.0, 1.0)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Кольцо клещей вокруг головы змеи: каждая вилка рисует свою дугу, просвет между дугами — выход.
## Ведущая вилка отмечает главный просвет по курсу змеи шевронами.
func _draw_pincer_ring() -> void:
	var strong := look_t > 0.0 or st == St.AIM
	var alpha := 0.55 if strong else 0.22
	var r := 64.0
	draw_set_transform((last_head - position).rotated(-rotation), -rotation, Vector2.ONE)
	var mid := (position - last_head).angle()
	draw_arc(Vector2.ZERO, r, mid - pincer_half, mid + pincer_half, 18, Color(Design.danger(), alpha), Design.telegraph_width(3.0))
	if pincer_lead and pincer_gap_dir != Vector2.ZERO:
		var g := pincer_gap_dir.normalized()
		var side := g.orthogonal()
		for i in 2:
			var c := g * (r + 6.0 + i * 16.0)
			draw_polyline(PackedVector2Array([c - g * 7.0 + side * 8.0, c, c - g * 7.0 - side * 8.0]),
				Color(Design.safe(), alpha * (1.0 - i * 0.3)), Design.telegraph_width(2.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_body(k: Dictionary) -> void:
	if st == St.SPRINT:  # след скорости
		for i in 3:
			draw_line(Vector2(TAIL - 10.0 - i * 22.0, -8 + i * 8), Vector2(TAIL - 40.0 - i * 22.0, -8 + i * 8),
				Color(1, 1, 1, 0.45 - i * 0.12), 3.0)
	var metal: Color = k["metal"]
	var edge: Color = k["edge"]
	var accent: Color = k["accent"]
	# ручка: у столовой — с медной вставкой, у десертной — резная, у вил — деревянная
	var handle := PackedVector2Array([Vector2(TAIL + 4, -7), Vector2(4, -3.5), Vector2(4, 3.5), Vector2(TAIL + 4, 7)])
	draw_colored_polygon(_grow(handle, 1.8), edge)
	draw_circle(Vector2(TAIL + 4, 0), 8.8, edge)
	var handle_col := Color(0.45, 0.26, 0.12) if kind == Kind.PITCH else metal
	draw_colored_polygon(handle, handle_col)
	draw_circle(Vector2(TAIL + 4, 0), 7.0, handle_col)
	if kind == Kind.PITCH:  # волокна дерева и латунное кольцо
		for i in 3:
			draw_line(Vector2(TAIL + 6, -3.5 + i * 3.5), Vector2(0, -1.8 + i * 1.8), handle_col.darkened(0.25), 1.0)
		draw_rect(Rect2(-2, -4.5, 5, 9), Color(0.9, 0.7, 0.3))
	elif kind == Kind.TABLE:
		draw_colored_polygon(PackedVector2Array([Vector2(TAIL + 14, -4.5), Vector2(-10, -3), Vector2(-10, 3), Vector2(TAIL + 14, 4.5)]),
			accent.darkened(0.15))
	else:
		for i in 4:
			draw_circle(Vector2(TAIL + 12 + i * 9, 0), 1.6, edge.lightened(0.2))
	draw_line(Vector2(TAIL + 2, -3), Vector2(0, -1.5), Color(1, 1, 1, 0.5), 1.6)  # блик
	draw_arc(Vector2(TAIL + 4, 0), 4.5, 0, TAU, 12, accent, 1.4)  # гравировка/клеймо
	# шейка и основание зубцов
	var neck := PackedVector2Array([Vector2(2, -3.5), Vector2(TINES_FROM, -12), Vector2(TINES_FROM + 4, -12),
		Vector2(TINES_FROM + 4, 12), Vector2(TINES_FROM, 12), Vector2(2, 3.5)])
	draw_colored_polygon(_grow(neck, 1.8), edge)
	draw_colored_polygon(neck, metal)
	draw_line(Vector2(4, -2), Vector2(TINES_FROM + 2, -9), Color(1, 1, 1, 0.3), 1.2)
	# зубцы
	var glow := 0.0
	if st == St.AIM:
		glow = 1.0 - st_t / (0.75 * tempo)
	elif st == St.VOLLEY_AIM:
		glow = 1.0 - st_t / (0.8 * tempo)
	elif st in [St.SPRINT, St.WHIRL]:
		glow = 1.0
	var tine_col := metal.lerp(Design.danger(), glow * 0.7)
	var n: int = k["tines"]
	var length := (TIP - TINES_FROM - 2.0) * tines_k
	if kind == Kind.PITCH:
		length *= 1.25
	if length < 8.0:  # зубцы отстреляны: торчат обломки
		for i in n:
			var y := -9.0 + i * 18.0 / maxf(n - 1, 1)
			draw_rect(Rect2(TINES_FROM + 2, y - 1.5, 3, 3), edge)
		return
	var tip_x := TINES_FROM + 2.0 + length
	for i in n:
		var y := -9.0 + i * 18.0 / maxf(n - 1, 1)
		var w := 2.2 if kind == Kind.PITCH else 1.8
		var tine := PackedVector2Array([Vector2(TINES_FROM + 2, y - w), Vector2(tip_x - 4, y - w * 0.8),
			Vector2(tip_x, y), Vector2(tip_x - 4, y + w * 0.8), Vector2(TINES_FROM + 2, y + w)])
		draw_colored_polygon(_grow(tine, 1.4), edge)
		draw_colored_polygon(tine, tine_col)
		draw_line(Vector2(TINES_FROM + 4, y - 0.8), Vector2(tip_x - 6, y - 0.6), Color(1, 1, 1, 0.4), 0.9)
		if glow > 0.3:
			Tex.blob(self, Vector2(tip_x, y), Vector2.ONE * 6.0, Color(1, 0.35, 0.1, glow * 0.6))


## Вилка воткнута в пол: сверху видна ручка в перспективе и трещины в досках вокруг.
func _draw_stuck_top(k: Dictionary) -> void:
	var metal: Color = k["metal"]
	var edge: Color = k["edge"]
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		draw_line(Vector2.ZERO, Vector2.from_angle(a) * (14.0 + 5.0 * (i % 2)), Color(0.1, 0.06, 0.03, 0.7), 1.5)
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.4))
	var h := PackedVector2Array([Vector2(-4, 2), Vector2(4, 2), Vector2(7, -30), Vector2(-7, -30)])
	draw_colored_polygon(_grow(h, 1.6), edge)
	draw_colored_polygon(h, Color(0.45, 0.26, 0.12) if kind == Kind.PITCH else metal)
	draw_circle(Vector2(0, -30), 7.5, edge)
	draw_circle(Vector2(0, -30), 6.0, Color(0.45, 0.26, 0.12) if kind == Kind.PITCH else metal)
	draw_line(Vector2(-2, 0), Vector2(-4, -28), Color(1, 1, 1, 0.45), 1.4)


func _grow(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (p - c).normalized() * by)
	return out
