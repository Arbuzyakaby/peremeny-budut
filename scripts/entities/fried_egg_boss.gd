extends Node2D
## Финальный босс — гигантская яичница.
## Уязвима только когда желток «открыт» (светится) — тогда змея должна укусить его головой.
## Ещё её понемногу ранят атаки, которые змея переняла у съеденных медведей (take_chip):
## накопленный урон ≥ 1 снимает одно деление HP.
## Атаки: кольцо брызг, таран, прицельные залпы, спираль масла, прыжок с ударной волной, перчинки.

signal shoot(pos: Vector2, velocity: Vector2, kind: int)
signal shockwave(pos: Vector2, gaps: int)
signal sound(sound_name: String)
signal bitten(hp_left: int)
signal phase_changed(phase: int)
signal yolk_opened
signal defeated

const Snake = preload("res://scripts/entities/snake.gd")
const Tex = preload("res://scripts/gfx/tex.gd")

const WHITE_RADIUS := 150.0
const YOLK_RADIUS := 48.0
const YOLK_OFFSET := Vector2(0, -10)
const HIT_TIME := 0.8
const JUMP_TIME := 0.75
const FALL_TIME := 0.22
const JUMP_HEIGHT := 260.0

enum Act { IDLE, RING, WINDUP, CHARGE, AIMED, SPIRAL, JUMP, FALL, PEPPER, YOLK_OPEN, HIT, DEAD }
enum Atk { RING, CHARGE, AIMED, SPIRAL, SLAM, PEPPER }

var bounds := Rect2(0, 0, 1280, 720)
var max_hp := 12
var hp := 12
var proj_mult := 1.0
var yolk_mult := 1.0
var tempo := 1.0

var active := false
var act := Act.IDLE
var act_t := 1.5
var t := 0.0
var count_left := 0
var shot_timer := 0.0
var spiral_angle := 0.0
var chain_left := 0
var last_attack := -1
var vel := Vector2.ZERO
var height := 0.0
var jump_from := Vector2.ZERO
var jump_to := Vector2.ZERO
var look_dir := Vector2.DOWN
var last_head := Vector2.ZERO
var flash := 0.0
var last_phase := 1
var chip := 0.0
var bite_damage := 1  # «Сильные челюсти» — укус снимает 2 деления
var lace: Array[Vector3] = []  # хрустящее кружево по краю: угол, радиус, размер
var seeds: Array[float] = [randf() * TAU, randf() * TAU, randf() * TAU]


func _ready() -> void:
	material = Tex.material(Tex.Mat.EGG, randf() * 10.0)
	for i in 70:
		lace.append(Vector3(randf() * TAU, randf_range(0.93, 1.04), randf_range(4.0, 11.0)))


func configure(boss_hp: int, projectile_speed: float, yolk_time: float, idle_tempo: float) -> void:
	max_hp = boss_hp
	hp = boss_hp
	proj_mult = projectile_speed
	yolk_mult = yolk_time
	tempo = idle_tempo


func phase() -> int:
	return clampi(1 + int(float(max_hp - hp) * 3.0 / max_hp), 1, 3)


func update(delta: float, snake: Snake) -> void:
	t += delta
	flash = maxf(flash - delta * 2.5, 0.0)
	queue_redraw()
	if not active or act == Act.DEAD:
		return

	var head := snake.head_pos
	last_head = head
	look_dir = (head - position).normalized()
	act_t -= delta
	shot_timer -= delta
	var p := phase()

	match act:
		Act.IDLE:
			var goal := bounds.get_center().lerp(head, 0.3)
			position = position.move_toward(goal, 40.0 * p * delta)
			if act_t <= 0.0:
				_next_attack()
		Act.RING:
			if shot_timer <= 0.0 and count_left > 0:
				_fire_ring()
				count_left -= 1
				shot_timer = 0.55 * tempo
			if act_t <= 0.0:
				_after_attack()
		Act.AIMED:
			if shot_timer <= 0.0 and count_left > 0:
				_fire_aimed(head)
				count_left -= 1
				shot_timer = 0.45 * tempo
			if act_t <= 0.0:
				_after_attack()
		Act.SPIRAL:
			if shot_timer <= 0.0:
				shot_timer = 0.075 * tempo
				var arms := 1 + p
				for i in arms:
					var dir := Vector2.from_angle(spiral_angle + TAU * i / arms)
					shoot.emit(position + dir * WHITE_RADIUS * 0.4, dir * 190.0 * proj_mult, 0)
				spiral_angle += 0.33
				count_left += 1
				if count_left % 4 == 0:
					sound.emit("tick")
			if act_t <= 0.0:
				_after_attack()
		Act.PEPPER:
			if shot_timer <= 0.0 and count_left > 0:
				var dir := Vector2.from_angle(randf_range(-PI, 0.0))
				shoot.emit(position + YOLK_OFFSET + dir * YOLK_RADIUS, dir * 170.0 * proj_mult, 2)
				sound.emit("pepper")
				count_left -= 1
				shot_timer = 0.35 * tempo
			if act_t <= 0.0:
				_after_attack()
		Act.WINDUP:
			if act_t <= 0.0:
				act = Act.CHARGE
				act_t = 0.75
				vel = (head - position).normalized() * (520.0 + 120.0 * p) * proj_mult
				sound.emit("whoosh")
		Act.CHARGE:
			position += vel * delta
			var inner := bounds.grow(-WHITE_RADIUS * 0.7)
			if position.x < inner.position.x or position.x > inner.end.x:
				vel.x = -vel.x
			if position.y < inner.position.y or position.y > inner.end.y:
				vel.y = -vel.y
			position = position.clamp(inner.position, inner.end)
			if head.distance_to(position) < WHITE_RADIUS * 0.8:
				if snake.take_damage(1, "boss"):
					snake.push((head - position).normalized() * 750.0)
			if act_t <= 0.0:
				vel = Vector2.ZERO
				count_left -= 1
				if count_left > 0:
					act = Act.WINDUP
					act_t = 0.45 * tempo
					sound.emit("charge")
				else:
					_after_attack()
		Act.JUMP:
			var k := 1.0 - act_t / JUMP_TIME
			position = jump_from.lerp(jump_to, k)
			height = sin(clampf(k, 0.0, 1.0) * PI * 0.5) * JUMP_HEIGHT
			if act_t <= 0.0:
				act = Act.FALL
				act_t = FALL_TIME
		Act.FALL:
			height = JUMP_HEIGHT * maxf(act_t / FALL_TIME, 0.0)
			if act_t <= 0.0:
				height = 0.0
				shockwave.emit(position, 4 - p)
				sound.emit("slam")
				if head.distance_to(position) < WHITE_RADIUS * 0.9:
					snake.take_damage(1, "boss")
					snake.push((head - position).normalized() * 750.0)
				count_left -= 1
				if count_left > 0:
					_start_jump(head)
				else:
					_after_attack()
		Act.YOLK_OPEN:
			if act_t <= 0.0:
				_go_idle()
		Act.HIT:
			if act_t <= 0.0:
				_go_idle()

	# Столкновение головы змеи с желтком (в прыжке — нет)
	var yolk := position + YOLK_OFFSET
	if act != Act.HIT and height < 20.0 and head.distance_to(yolk) < YOLK_RADIUS + Snake.HEAD_RADIUS:
		var away := (head - yolk).normalized()
		if act == Act.YOLK_OPEN:
			_take_bite(snake, away)
		else:
			snake.take_damage(1, "boss")
			snake.push(away * 600.0)


func _go_idle() -> void:
	act = Act.IDLE
	act_t = (1.6 - 0.35 * (phase() - 1)) * tempo
	var chain_chance: float = [0.0, 0.4, 0.65][phase() - 1]
	chain_left = 1 if randf() < chain_chance else 0


func _after_attack() -> void:
	if chain_left > 0:
		chain_left -= 1
		act = Act.IDLE
		act_t = 0.35 * tempo
	else:
		_open_yolk()


func _next_attack() -> void:
	var p := phase()
	var pool: Array[int] = [Atk.RING, Atk.CHARGE, Atk.AIMED]
	if p >= 2:
		pool.append_array([Atk.SPIRAL, Atk.SLAM])
	if p >= 3:
		pool.append(Atk.PEPPER)
	pool.erase(last_attack)
	var atk: int = pool.pick_random()
	last_attack = atk
	shot_timer = 0.2
	match atk:
		Atk.RING:
			act = Act.RING
			count_left = p + 1
			act_t = 0.55 * tempo * count_left + 0.6
		Atk.AIMED:
			act = Act.AIMED
			count_left = 2 + p
			act_t = 0.45 * tempo * count_left + 0.5
		Atk.SPIRAL:
			act = Act.SPIRAL
			count_left = 0
			spiral_angle = randf() * TAU
			act_t = 2.6
			sound.emit("shoot")
		Atk.PEPPER:
			act = Act.PEPPER
			count_left = 3 + (1 if proj_mult > 1.1 else 0)
			act_t = 0.35 * tempo * count_left + 0.8
		Atk.CHARGE:
			act = Act.WINDUP
			count_left = p
			act_t = 0.7 * tempo
			sound.emit("charge")
		Atk.SLAM:
			count_left = 1 if p < 3 else 2
			_start_jump(last_head)


func _start_jump(target: Vector2) -> void:
	act = Act.JUMP
	act_t = JUMP_TIME * tempo
	jump_from = position
	var inner := bounds.grow(-WHITE_RADIUS * 0.6)
	jump_to = target.clamp(inner.position, inner.end)
	sound.emit("charge")


func _open_yolk() -> void:
	act = Act.YOLK_OPEN
	act_t = (3.2 - 0.5 * (phase() - 1)) * yolk_mult
	yolk_opened.emit()
	sound.emit("yolk")


func _fire_ring() -> void:
	var p := phase()
	var n := 8 + 4 * p
	var offset := randf() * TAU
	for i in n:
		var dir := Vector2.from_angle(offset + TAU * i / n)
		var kind := 1 if p >= 3 and i % 3 == 0 else 0
		shoot.emit(position + dir * WHITE_RADIUS * 0.6, dir * (170.0 + 40.0 * p) * proj_mult, kind)
	sound.emit("shoot")


func _fire_aimed(head: Vector2) -> void:
	var p := phase()
	var fan := 3 if p == 1 else 5
	var base := (head - position).angle()
	for i in fan:
		var dir := Vector2.from_angle(base + (i - (fan - 1) / 2.0) * 0.17)
		shoot.emit(position + dir * WHITE_RADIUS * 0.5, dir * 330.0 * proj_mult, 0)
	sound.emit("shoot")


func is_yolk_open() -> bool:
	return act == Act.YOLK_OPEN


## Урон от атак змеи. Возвращает false, если сейчас не пробить (в прыжке, уже ранена, мертва).
func take_chip(amount: float) -> bool:
	if not active or act == Act.DEAD or act == Act.HIT or height > 20.0:
		return false
	chip += amount
	flash = maxf(flash, 0.45)
	if chip >= 1.0:
		chip -= 1.0
		_lose_hp()
	return true


## Панель разработчика: оставить яичнице n делений (или сразу победить при n = 0).
func dev_set_hp(n: int) -> void:
	if act == Act.DEAD:
		return
	if n <= 0:
		hp = 1
		_lose_hp()
	else:
		hp = mini(n, max_hp)
		bitten.emit(hp)


func _take_bite(snake: Snake, away: Vector2) -> void:
	snake.push(away * 650.0)
	_lose_hp(bite_damage)


func _lose_hp(amount := 1) -> void:
	hp = maxi(hp - amount, 0)
	flash = 1.0
	bitten.emit(hp)
	if hp <= 0:
		act = Act.DEAD
		defeated.emit()
		return
	act = Act.HIT
	act_t = HIT_TIME
	if phase() != last_phase:
		last_phase = phase()
		phase_changed.emit(last_phase)


func _draw() -> void:
	var p := phase()
	var in_air := act == Act.JUMP or act == Act.FALL

	# Прицел места приземления
	if in_air:
		var target := jump_to - position
		var pulse := 0.5 + 0.5 * sin(t * 18.0)
		draw_circle(target, WHITE_RADIUS * 0.9, Color(1, 0.1, 0.1, 0.12 + 0.1 * pulse))
		draw_arc(target, WHITE_RADIUS * 0.9, 0, TAU, 48, Color(1, 0.15, 0.1, 0.7), 4.0)

	var offset := Vector2(0, -height)
	if act == Act.WINDUP:
		offset += Vector2(randf_range(-5, 5), randf_range(-5, 5))
	var sq := Vector2(1.0 + 0.02 * sin(t * 2.0), 1.0 - 0.02 * sin(t * 2.0))
	if act == Act.HIT:
		var k := act_t / HIT_TIME
		sq *= Vector2(1.0 + 0.18 * k * sin(t * 30.0), 1.0 - 0.18 * k * sin(t * 30.0))
	elif in_air:
		sq *= Vector2(0.92, 1.1)

	# Белок: волнистый край
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var shadow := PackedVector2Array()
	var shadow_k := 1.0 - height / (JUMP_HEIGHT * 1.6)
	for i in 56:
		var a := TAU * i / 56.0
		var r := WHITE_RADIUS * (1.0 + 0.07 * sin(3.0 * a + seeds[0] + t * 1.5) \
			+ 0.05 * sin(5.0 * a + seeds[1] - t * 2.2) + 0.03 * sin(9.0 * a + seeds[2]))
		var v := Vector2.from_angle(a)
		outer.append(v * r)
		inner.append(v * (r - 9.0))
		shadow.append(v * r * shadow_k + Vector2(10, 14))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.2 * shadow_k))
	Tex.blob(self, Vector2(10, 14), Vector2.ONE * WHITE_RADIUS * 1.25 * shadow_k, Color(0, 0, 0, 0.18 * shadow_k))

	draw_set_transform(offset, 0.0, sq)
	var rage := float(p - 1) / 2.0
	var crust := Color(0.86, 0.62, 0.28).lerp(Color(0.85, 0.2, 0.1), rage)
	var white := Color(0.99, 0.98, 0.94)
	if act == Act.WINDUP or act == Act.CHARGE:
		white = white.lerp(Color(1.0, 0.75, 0.7), 0.5)
	white = white.lerp(Color(1, 0.4, 0.4), flash * 0.6)
	for l in lace:  # хрустящее поджаристое кружево по краю
		var lp := Vector2.from_angle(l.x) * WHITE_RADIUS * l.y
		draw_circle(lp, l.z, crust.darkened(0.25))
		draw_circle(lp + Vector2(-1, -1), l.z * 0.6, crust.lightened(0.1))
	draw_colored_polygon(outer, crust)
	draw_colored_polygon(inner, white.darkened(0.04))
	# полупрозрачный край белка и более плотная середина
	var mid := PackedVector2Array()
	for v in inner:
		mid.append(v * 0.78 + Vector2(-4, -5))
	draw_colored_polygon(mid, white)
	Tex.blob(self, Vector2(-40, -50), Vector2(95, 70), Color(1, 1, 1, 0.45))
	for i in 6:  # пузырьки на белке
		var bp := Vector2.from_angle(seeds[i % 3] + i * 1.1) * (80.0 + 12.0 * sin(t + i))
		draw_circle(bp, 5.0 + i % 3, Color(0.93, 0.91, 0.86))
		draw_arc(bp, 5.0 + i % 3, 0, TAU, 12, Color(0.8, 0.78, 0.72), 1.5)
		draw_circle(bp + Vector2(-1.5, -1.5), 1.5, Color(1, 1, 1, 0.9))
	for i in 3:  # масляные блики
		var op := Vector2.from_angle(seeds[i] * 2.0 + 0.8) * 110.0
		Tex.blob(self, op, Vector2(18, 9), Color(1, 0.85, 0.35, 0.35))

	# Желток
	var yc := YOLK_OFFSET
	var yr := YOLK_RADIUS
	var open := act == Act.YOLK_OPEN
	if open:
		var pulse := 0.5 + 0.5 * sin(t * 10.0)
		draw_circle(yc, yr + 12.0 + 8.0 * pulse, Color(1.0, 0.95, 0.3, 0.35))
		yr *= 1.0 + 0.06 * pulse
		if act_t < 0.8 and int(act_t * 10.0) % 2 == 0:  # скоро закроется
			draw_arc(yc, yr + 16.0, 0, TAU, 40, Color(1, 0.3, 0.1, 0.8), 3.0)
	Tex.blob(self, yc + Vector2(6, 9), Vector2.ONE * yr * 1.3, Color(0.6, 0.35, 0.0, 0.35))
	draw_circle(yc + Vector2(3, 5), yr, Color(0.85, 0.45, 0.05))
	var yolk_col := Color(1.0, 0.8, 0.1) if open else Color(0.95, 0.6, 0.12)
	draw_circle(yc, yr, yolk_col.darkened(0.08))
	draw_circle(yc + Vector2(-3, -4), yr * 0.86, yolk_col)
	draw_circle(yc + Vector2(-7, -9), yr * 0.55, yolk_col.lightened(0.12))
	if not open:
		draw_circle(yc, yr, Color(1, 1, 1, 0.22))  # запёкшаяся плёнка — укусить нельзя
		draw_arc(yc, yr - 3.0, 0, TAU, 32, Color(1, 1, 1, 0.35), 3.0)
	Tex.blob(self, yc + Vector2(-yr * 0.4, -yr * 0.45), Vector2.ONE * yr * 0.35, Color(1, 1, 1, 0.7))
	draw_circle(yc + Vector2(-yr * 0.42, -yr * 0.45), yr * 0.14, Color(1, 1, 1, 0.9))

	# Лицо
	var dark := Color(0.35, 0.15, 0.05)
	var hurt := act == Act.HIT or act == Act.DEAD
	var angry := act == Act.WINDUP or act == Act.CHARGE or in_air
	for s in [-1.0, 1.0]:
		var e: Vector2 = yc + Vector2(s * 16.0, -6.0)
		if hurt:
			draw_line(e - Vector2(5, 5), e + Vector2(5, 5), dark, 3.0)
			draw_line(e - Vector2(5, -5), e + Vector2(5, -5), dark, 3.0)
		else:
			draw_circle(e, 8.0, Color.WHITE)
			draw_circle(e + look_dir * 3.5, 4.0, Color(0.8, 0.0, 0.0) if angry else Color.BLACK)
		var brow_lift := -4.0 if open else 0.0
		draw_line(e + Vector2(s * 12.0, -13.0 + brow_lift), e + Vector2(-s * 7.0, -7.0 - brow_lift * 0.5), dark, 4.0)
	if open or hurt:
		draw_circle(yc + Vector2(0, 22), 7.0, dark)  # испуганный «о»
	elif act == Act.RING or act == Act.SPIRAL or act == Act.AIMED or act == Act.PEPPER:
		draw_circle(yc + Vector2(0, 24), 9.0, dark)  # орёт и плюётся
		draw_circle(yc + Vector2(0, 27), 5.0, Color(0.8, 0.2, 0.15))
	else:
		draw_arc(yc + Vector2(0, 30), 13.0, PI + 0.5, TAU - 0.5, 12, dark, 3.5)  # злой рот

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
