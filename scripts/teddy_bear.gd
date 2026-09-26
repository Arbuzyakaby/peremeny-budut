extends Node2D
## Плюшевый медведь. Пять видов:
## - обычный: бродит и убегает от змеи;
## - боксёр: замахивается («!») и делает рывок в голову змеи, после чего оглушён — лучший момент съесть;
## - метатель: держит дистанцию и кидает пуговицы;
## - каратист: кружит вокруг змеи, кричит «ХЬЯ!» и бьёт ногой в прыжке — сильно (2 жизни);
## - швея: держит дистанцию и метает веером иголки с пуговицами — они ещё и пришивают (замедляют).
## Френдли фаер: пуговица или рывок боксёра оглушает другого медведя, и тот начинает мстить
## обидчику (обычный — таранит, боксёр — бьёт, метатель — кидает в ответ). Так медведей можно стравить.

signal throw_button(pos: Vector2, velocity: Vector2, needle: bool)
signal sound(sound_name: String)

const Snake = preload("res://scripts/snake.gd")

enum Type { NORMAL, BOXER, THROWER, KARATE, SEAMSTRESS }
enum St { ROAM, WINDUP, DASH, DIZZY, AIM, RECOVER }

const RADIUS := 18.0
const BOW_COLORS := [
	Color(0.9, 0.2, 0.3), Color(0.25, 0.5, 0.95), Color(0.95, 0.75, 0.15),
	Color(0.6, 0.3, 0.85), Color(0.2, 0.75, 0.55),
]

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


func setup(pos: Vector2, spd: float, area: Rect2, bear_type: int, aggression: float) -> void:
	position = pos
	speed = spd
	bounds = area
	type = bear_type as Type
	aggr = aggression
	attack_cd = randf_range(1.5, 3.0) / aggr
	vel = Vector2.from_angle(randf() * TAU) * speed
	bow_color = BOW_COLORS.pick_random()
	fur = Color(0.62, 0.4, 0.22).lerp(Color(0.85, 0.65, 0.4), randf() * 0.6)
	if type == Type.BOXER:
		fur = Color(0.55, 0.33, 0.2)
	elif type == Type.KARATE:
		fur = Color(0.5, 0.36, 0.25)
	elif type == Type.SEAMSTRESS:
		fur = Color(0.8, 0.6, 0.45)
	wobble = randf() * TAU
	scale = Vector2.ZERO
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Можно ли сейчас съесть медведя (в рывке — нельзя, он сам бьёт).
func is_edible() -> bool:
	return st != St.DASH and no_eat_t <= 0.0


func is_dizzy() -> bool:
	return st == St.DIZZY


func has_grudge() -> bool:
	return is_instance_valid(grudge) and grudge_t > 0.0


## Сейчас таранит/бьёт — касание оглушает других медведей.
func is_ramming() -> bool:
	return st == St.DASH or (type == Type.NORMAL and st == St.ROAM and has_grudge())


## В медведя попал свой: оглушение и жажда мести.
func hit_by_friend(attacker: Node2D, push_vel: Vector2) -> bool:
	if friend_cd > 0.0:
		return false
	friend_cd = 0.5
	hit_flash = 1.0
	_get_dizzy(1.6)
	vel = push_vel
	if is_instance_valid(attacker) and attacker != self:
		grudge = attacker
		grudge_t = 9.0
		attack_cd = 0.2
	sound.emit("bonk")
	return true


## Таран достиг цели.
func on_ram_hit() -> void:
	grudge = null
	if st == St.DASH and type == Type.KARATE:
		_recover(0.7)
	elif st == St.DASH:
		_get_dizzy(1.0)
	else:
		vel = -vel * 0.5
		attack_cd = 1.0


func update(delta: float, snake: Snake) -> void:
	t += delta
	st_t -= delta
	attack_cd -= delta
	no_eat_t = maxf(no_eat_t - delta, 0.0)
	friend_cd = maxf(friend_cd - delta, 0.0)
	hit_flash = maxf(hit_flash - delta * 4.0, 0.0)
	grudge_t -= delta
	if not has_grudge():
		grudge = null
	var avenging := grudge != null
	var head := snake.head_pos if snake else Vector2(-9999, -9999)
	var target := grudge.position if avenging else head
	var to_head := target - position
	var dist := to_head.length()
	var can_attack := attack_cd <= 0.0 and (avenging or (snake != null and snake.alive))

	match st:
		St.ROAM:
			_roam(delta, to_head, dist, avenging)
			if can_attack and type == Type.BOXER and dist < 240.0:
				st = St.WINDUP
				st_t = 0.6
				sound.emit("warn")
			elif can_attack and type == Type.KARATE and dist < 230.0:
				st = St.WINDUP
				st_t = 0.45
				sound.emit("hiya")
			elif can_attack and type == Type.THROWER and dist > 150.0 and dist < 560.0:
				st = St.AIM
				st_t = 0.55
			elif can_attack and type == Type.SEAMSTRESS and dist > 170.0 and dist < 600.0:
				st = St.AIM
				st_t = 0.65
		St.WINDUP:
			vel = vel.move_toward(Vector2.ZERO, 500.0 * delta)
			dash_dir = to_head.normalized()
			if st_t <= 0.0:
				st = St.DASH
				if type == Type.KARATE:  # удар ногой в прыжке: быстрее и короче
					st_t = 0.3
					vel = dash_dir * (620.0 + 40.0 * aggr)
				else:
					st_t = 0.4
					vel = dash_dir * (430.0 + 60.0 * aggr)
				sound.emit("whoosh")
		St.DASH:
			var karate := type == Type.KARATE
			if avenging:  # столкновение с медведем обрабатывает игра
				if st_t <= 0.0:
					grudge = null
					if karate:
						_recover(0.9)
					else:
						_get_dizzy(1.0)
			elif dist < RADIUS + Snake.HEAD_RADIUS + 4.0:
				var dmg := 2 if karate and aggr >= 0.9 else 1
				if snake.take_damage(dmg):
					sound.emit("kick" if karate else "punch")
				snake.push(dash_dir * (800.0 if karate else 520.0))
				no_eat_t = 0.4
				if karate:
					_recover(0.7)
				else:
					_get_dizzy(1.8)
			elif st_t <= 0.0:
				if karate:
					_recover(0.9)
				else:
					_get_dizzy(1.3)
		St.RECOVER:  # каратист не падает, а встаёт в стойку — но в это время его можно съесть
			vel = vel.move_toward(Vector2.ZERO, 900.0 * delta)
			if st_t <= 0.0:
				st = St.ROAM
				attack_cd = randf_range(1.6, 2.8) / aggr
		St.DIZZY:
			vel = vel.move_toward(Vector2.ZERO, 600.0 * delta)
			if st_t <= 0.0:
				st = St.ROAM
				attack_cd = randf_range(2.5, 4.0) / aggr
		St.AIM:
			vel = vel.move_toward(Vector2.ZERO, 500.0 * delta)
			if st_t <= 0.0:
				var lead := head + Vector2.from_angle(snake.heading) * 70.0 if snake else target
				if avenging:
					lead = target + (grudge.get("vel") as Vector2) * 0.3
					grudge = null
				var dir := (lead - position).normalized()
				if type == Type.SEAMSTRESS:  # веер иголок
					var n := 1 if aggr < 0.9 else (2 if aggr < 1.3 else 3)
					for i in n:
						var a := (i - (n - 1) / 2.0) * 0.2
						throw_button.emit(position, dir.rotated(a) * (330.0 + 50.0 * aggr), true)
					sound.emit("needle")
				else:
					throw_button.emit(position, dir * (230.0 + 40.0 * aggr), false)
					sound.emit("throw")
				st = St.ROAM
				attack_cd = randf_range(1.8, 3.2) / aggr

	position += vel * delta
	var inner := bounds.grow(-RADIUS - 4.0)
	if position.x < inner.position.x or position.x > inner.end.x:
		vel.x = -vel.x
	if position.y < inner.position.y or position.y > inner.end.y:
		vel.y = -vel.y
	position = position.clamp(inner.position, inner.end)

	wobble += delta * (6.0 + vel.length() * 0.05)
	rotation = sin(wobble) * 0.18
	if st == St.WINDUP:
		rotation = randf_range(-0.15, 0.15)
	elif st == St.DASH and type == Type.KARATE:
		rotation = dash_dir.angle() + PI / 2 - PI * 0.35  # летит боком, выставив ногу
	queue_redraw()


func _roam(delta: float, to_head: Vector2, dist: float, avenging: bool) -> void:
	if avenging:  # догоняем обидчика
		var k := 1.4 if type == Type.NORMAL else 1.0
		if (type == Type.THROWER or type == Type.SEAMSTRESS) and dist < 200.0:
			k = -0.8
		vel = vel.lerp(to_head.normalized() * speed * k, 3.0 * delta)
		return
	var flee_dist := 160.0
	if type == Type.KARATE and dist < 400.0:  # кружит вокруг змеи в стойке
		var toward := to_head.normalized()
		var want := toward * clampf((dist - 170.0) * 0.02, -1.0, 1.0) + toward.orthogonal() * 0.8
		vel = vel.lerp(want.normalized() * speed * 1.1, 3.0 * delta)
		return
	if type == Type.THROWER:
		flee_dist = 220.0
	elif type == Type.SEAMSTRESS:
		flee_dist = 250.0
	elif type == Type.BOXER:
		flee_dist = 0.0
		if dist < 360.0:  # боксёр сам подбирается к змее
			vel = vel.lerp(to_head.normalized() * speed * 0.9, 2.0 * delta)
			return
	if dist < flee_dist:
		vel = vel.lerp(-to_head.normalized() * speed * 1.8, 4.0 * delta)
	else:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(1.0, 2.5)
			vel = Vector2.from_angle(randf() * TAU) * speed


func _recover(time: float) -> void:
	st = St.RECOVER
	st_t = time
	vel *= 0.3


func _get_dizzy(time: float) -> void:
	st = St.DIZZY
	st_t = time
	vel *= 0.3


func _draw() -> void:
	var dark := fur.darkened(0.35)
	var light := fur.lightened(0.35)
	draw_circle(Vector2(3, 5), 20.0, Color(0, 0, 0, 0.15))  # тень
	for s in [-1.0, 1.0]:  # уши
		draw_circle(Vector2(s * 10, -16), 7.0, dark)
		draw_circle(Vector2(s * 10, -16), 5.5, fur)
		draw_circle(Vector2(s * 10, -16), 3.0, light)
	for s in [-1.0, 1.0]:  # ноги
		draw_circle(Vector2(s * 7, 16), 5.5, dark)
		draw_circle(Vector2(s * 7, 16), 4.5, fur)
		draw_circle(Vector2(s * 7, 17), 2.2, light)
	if type == Type.KARATE and st == St.DASH:  # выставленная нога
		draw_line(Vector2(0, 12), Vector2(0, 30), dark, 9.0)
		draw_circle(Vector2(0, 31), 5.5, dark)
		draw_circle(Vector2(0, 31), 4.5, fur)
	if type != Type.BOXER:
		for s in [-1.0, 1.0]:
			var arm := Vector2(s * 12, 5)
			if (type == Type.THROWER or type == Type.SEAMSTRESS) and st == St.AIM and s > 0:
				arm = Vector2(14, -10)
			elif type == Type.KARATE and st == St.WINDUP:
				arm = Vector2(s * 15, -4 if s > 0 else 8)
			draw_circle(arm, 5.0, dark)
			draw_circle(arm, 4.0, fur)
	# тело
	var body_col := fur
	if type == Type.KARATE:
		body_col = Color(0.97, 0.97, 0.95)  # белое кимоно
	draw_circle(Vector2(0, 8), 11.0, dark)
	draw_circle(Vector2(0, 8), 10.0, body_col)
	if type == Type.KARATE:
		draw_line(Vector2(-6, 1), Vector2(0, 9), Color(0.75, 0.75, 0.75), 1.5)
		draw_line(Vector2(6, 1), Vector2(0, 9), Color(0.75, 0.75, 0.75), 1.5)
		draw_line(Vector2(-10, 12), Vector2(10, 12), Color(0.08, 0.08, 0.08), 3.5)  # чёрный пояс
		draw_line(Vector2(3, 12), Vector2(7, 19), Color(0.08, 0.08, 0.08), 2.0)
	elif type == Type.SEAMSTRESS:
		draw_colored_polygon(PackedVector2Array([Vector2(-7, 2), Vector2(7, 2), Vector2(9, 17), Vector2(-9, 17)]),
			Color(0.95, 0.55, 0.7))  # фартук
		draw_circle(Vector2(0, 11), 3.2, Color(0.85, 0.2, 0.3))  # игольница
		for k in 3:
			draw_line(Vector2(0, 11), Vector2(0, 11) + Vector2.from_angle(-2.2 + k * 0.6) * 5.5, Color(0.8, 0.8, 0.85), 1.0)
	else:
		draw_circle(Vector2(0, 10), 6.0, light)
	# голова
	draw_circle(Vector2(0, -7), 12.5, dark)
	draw_circle(Vector2(0, -7), 11.5, fur)
	draw_circle(Vector2(0, -3), 5.5, light)
	draw_circle(Vector2(0, -5), 2.2, Color(0.15, 0.08, 0.05))
	draw_line(Vector2(0, -3), Vector2(0, -1), Color(0.15, 0.08, 0.05), 1.2)
	for s in [-1.0, 1.0]:
		var e := Vector2(s * 4.5, -10)
		if st == St.DIZZY:
			draw_line(e - Vector2(2, 2), e + Vector2(2, 2), Color.BLACK, 1.5)
			draw_line(e - Vector2(2, -2), e + Vector2(2, -2), Color.BLACK, 1.5)
		else:
			draw_circle(e, 2.0, Color.BLACK)
			draw_circle(e - Vector2(0.6, 0.6), 0.7, Color.WHITE)
		if type == Type.SEAMSTRESS:  # круглые очки
			draw_arc(e, 3.6, 0, TAU, 12, Color(0.3, 0.2, 0.15), 1.2)
		if (type == Type.BOXER or type == Type.KARATE) and st != St.DIZZY:  # злые брови
			draw_line(e + Vector2(s * 3, -4), e + Vector2(-s * 2, -2.5), Color(0.15, 0.08, 0.05), 1.6)

	match type:
		Type.NORMAL:
			var c := Vector2(0, 3)
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(-7, -4), c + Vector2(-7, 4)]), bow_color)
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(7, -4), c + Vector2(7, 4)]), bow_color)
			draw_circle(c, 2.2, bow_color.darkened(0.3))
		Type.BOXER:
			draw_line(Vector2(-11, -14), Vector2(11, -14), Color(0.9, 0.15, 0.15), 3.0)  # повязка
			draw_line(Vector2(10, -14), Vector2(15, -9), Color(0.9, 0.15, 0.15), 2.0)
			for s in [-1.0, 1.0]:
				var g := Vector2(s * 13, 4)
				if st == St.WINDUP:
					g = Vector2(s * 9, -3)
				elif st == St.DASH:
					g = Vector2(s * 6, -16)
				draw_circle(g, 7.5, Color(0.55, 0.05, 0.05))
				draw_circle(g, 6.5, Color(0.92, 0.15, 0.12))
				draw_circle(g + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.5))
		Type.THROWER:
			# кепка
			draw_arc(Vector2(0, -13), 10.0, PI, TAU, 12, Color(0.2, 0.45, 0.85), 6.0)
			draw_line(Vector2(2, -13), Vector2(15, -12), Color(0.15, 0.35, 0.7), 3.0)
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
			draw_line(Vector2(3, -27), Vector2(10, -34), Color(0.8, 0.82, 0.88), 1.5)
			if st == St.AIM:
				draw_line(Vector2(14, -10), Vector2(18, -22), Color(0.85, 0.87, 0.92), 2.0)
				draw_circle(Vector2(14, -10), 3.0, Color(0.95, 0.8, 0.2))

	# эффекты поверх (без поворота медведя)
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	if st == St.WINDUP or st == St.AIM:
		var font := ThemeDB.fallback_font
		var col := Color(1, 0.15, 0.1) if st == St.WINDUP else Color(1, 0.7, 0.1)
		var txt := "ХЬЯ!" if type == Type.KARATE else "!"
		var fs := 16 if type == Type.KARATE else 26
		var x := -18.0 if type == Type.KARATE else -6.0
		draw_string_outline(font, Vector2(x, -30), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color.BLACK)
		draw_string(font, Vector2(x, -30), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hit_flash > 0.0:
		draw_circle(Vector2(0, 0), 22.0, Color(1, 1, 1, 0.55 * hit_flash))


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2 + TAU * i / 10.0) * rr)
	draw_colored_polygon(pts, col)
