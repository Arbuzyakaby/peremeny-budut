extends Node2D
## Плюшевый медведь. Восемь видов:
## - обычный: бродит и убегает от змеи;
## - боксёр: замахивается («!») и делает рывок в голову змеи, после чего оглушён — лучший момент съесть;
## - метатель: держит дистанцию и кидает пуговицы;
## - каратист: кружит вокруг змеи, кричит «ХЬЯ!» и бьёт ногой в прыжке — сильно (2 жизни);
## - швея: держит дистанцию и метает веером иголки с пуговицами — они ещё и пришивают (замедляют);
## - ниндзя: растворяется в дыму, появляется сбоку от змеи и мечет сюрикены;
## - хлопушка: бросает хлопушки с фитилём — взрыв задевает и змею, и медведей;
## - медсестра: держится подальше и накрывает других медведей щитом-пузырём (их нельзя съесть).
## Френдли фаер: снаряд или рывок боксёра оглушает другого медведя, и тот начинает мстить обидчику.

signal throw_item(pos: Vector2, velocity: Vector2, kind: int)
signal sound(sound_name: String)
signal puff(pos: Vector2)

const Snake = preload("res://scripts/snake.gd")
const Tex = preload("res://scripts/tex.gd")
const OilDrop = preload("res://scripts/oil_drop.gd")

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
	match type:
		Type.BOXER:
			fur = Color(0.55, 0.33, 0.2)
		Type.KARATE:
			fur = Color(0.5, 0.36, 0.25)
		Type.SEAMSTRESS:
			fur = Color(0.8, 0.6, 0.45)
		Type.NINJA:
			fur = Color(0.42, 0.3, 0.22)
		Type.BOMBER:
			fur = Color(0.78, 0.5, 0.28)
		Type.MEDIC:
			fur = Color(0.92, 0.82, 0.7)
	wobble = randf() * TAU
	material = Tex.material(Tex.Mat.FUR, randf() * 10.0)
	scale = Vector2.ZERO
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Можно ли сейчас съесть медведя (в рывке, в дыму и под щитом — нельзя).
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


func give_shield() -> void:
	shield_t = SHIELD_TIME
	if st == St.DIZZY:
		st = St.ROAM
		attack_cd = 1.0


## Змея врезалась в щит: пузырь лопается.
func pop_shield() -> void:
	shield_t = 0.0
	no_eat_t = 0.35
	hit_flash = 1.0
	sound.emit("pop")


## В медведя попал свой: оглушение и жажда мести. Щит принимает удар на себя.
func hit_by_friend(attacker: Node2D, push_vel: Vector2) -> bool:
	if friend_cd > 0.0:
		return false
	friend_cd = 0.5
	if is_shielded():
		pop_shield()
		vel = push_vel * 0.5
		return false
	hit_flash = 1.0
	fade = 1.0
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
	heal_glow = maxf(heal_glow - delta * 1.5, 0.0)
	shield_t = maxf(shield_t - delta, 0.0)
	grudge_t -= delta
	if not has_grudge():
		grudge = null
	var avenging := grudge != null
	var head := snake.head_pos if snake else Vector2(-9999, -9999)
	var target := grudge.position if avenging else head
	var to_head := target - position
	var dist := to_head.length()
	var can_attack := attack_cd <= 0.0 and (avenging or (snake != null and snake.alive))
	if st != St.VANISH:
		fade = move_toward(fade, 1.0, delta * 3.0)

	match st:
		St.ROAM:
			_roam(delta, to_head, dist, avenging, head)
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
			elif can_attack and type == Type.BOMBER and dist > 160.0 and dist < 540.0:
				st = St.AIM
				st_t = 0.6
			elif can_attack and type == Type.NINJA and dist < 560.0:
				if avenging:
					st = St.AIM
					st_t = 0.35
				else:
					st = St.VANISH
					st_t = 0.5
					puff.emit(position)
					sound.emit("poof")
		St.VANISH:  # ниндзя растворяется и переносится сбоку от змеи
			vel = vel.move_toward(Vector2.ZERO, 800.0 * delta)
			fade = maxf(st_t / 0.5, 0.0) * 0.8
			if st_t <= 0.0:
				var side := Vector2.from_angle(snake.heading).orthogonal() * (1.0 if randf() < 0.5 else -1.0) if snake else Vector2.RIGHT
				var inner := bounds.grow(-RADIUS - 30.0)
				position = (head + side * randf_range(150.0, 200.0) - Vector2.from_angle(snake.heading if snake else 0.0) * 40.0) \
					.clamp(inner.position, inner.end)
				puff.emit(position)
				sound.emit("poof")
				fade = 0.2
				st = St.AIM
				st_t = 0.4 / clampf(aggr, 0.6, 1.6)
				no_eat_t = 0.0
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
				_throw(snake, head, target, avenging)

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
	modulate.a = fade
	queue_redraw()


func _throw(snake: Snake, head: Vector2, target: Vector2, avenging: bool) -> void:
	var lead := head + Vector2.from_angle(snake.heading) * 70.0 if snake else target
	if avenging:
		lead = target + (grudge.get("vel") as Vector2) * 0.3
		grudge = null
	var dir := (lead - position).normalized()
	match type:
		Type.SEAMSTRESS:  # веер иголок
			var n := 1 if aggr < 0.9 else (2 if aggr < 1.3 else 3)
			for i in n:
				var a := (i - (n - 1) / 2.0) * 0.2
				throw_item.emit(position, dir.rotated(a) * (330.0 + 50.0 * aggr), OilDrop.Kind.NEEDLE)
			sound.emit("needle")
		Type.NINJA:  # сюрикены
			var n := 2 if aggr < 1.3 else 3
			var aim := (head - position).normalized() if not avenging else dir
			for i in n:
				var a := (i - (n - 1) / 2.0) * 0.16
				throw_item.emit(position, aim.rotated(a) * (380.0 + 50.0 * aggr), OilDrop.Kind.SHURIKEN)
			sound.emit("shuriken")
		Type.BOMBER:  # хлопушка катится и тормозит у цели
			var d := position.distance_to(lead)
			throw_item.emit(position, dir * clampf(sqrt(2.0 * 420.0 * d), 200.0, 620.0), OilDrop.Kind.CRACKER)
			sound.emit("fuse")
		_:
			throw_item.emit(position, dir * (230.0 + 40.0 * aggr), OilDrop.Kind.BUTTON)
			sound.emit("throw")
	st = St.ROAM
	attack_cd = randf_range(1.8, 3.2) / aggr
	if type == Type.NINJA:
		attack_cd *= 1.2


func _roam(delta: float, to_head: Vector2, dist: float, avenging: bool, head: Vector2) -> void:
	if avenging:  # догоняем обидчика
		var k := 1.4 if type == Type.NORMAL else 1.0
		if type in [Type.THROWER, Type.SEAMSTRESS, Type.NINJA, Type.BOMBER] and dist < 200.0:
			k = -0.8
		if type == Type.MEDIC:
			k = -0.8
		vel = vel.lerp(to_head.normalized() * speed * k, 3.0 * delta)
		return
	if type == Type.MEDIC:
		_medic(delta, to_head, dist)
		return
	var flee_dist := 160.0
	if type == Type.KARATE and dist < 400.0:  # кружит вокруг змеи в стойке
		var toward := to_head.normalized()
		var want := toward * clampf((dist - 170.0) * 0.02, -1.0, 1.0) + toward.orthogonal() * 0.8
		vel = vel.lerp(want.normalized() * speed * 1.1, 3.0 * delta)
		return
	match type:
		Type.THROWER, Type.BOMBER:
			flee_dist = 220.0
		Type.SEAMSTRESS:
			flee_dist = 250.0
		Type.NINJA:
			flee_dist = 190.0
		Type.BOXER:
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


## Медсестра: бежит к ближайшему медведю без щита и накрывает его пузырём; от змеи убегает.
func _medic(delta: float, to_head: Vector2, dist: float) -> void:
	if dist < 170.0:
		heal_target = null
		vel = vel.lerp(-to_head.normalized() * speed * 1.9, 4.0 * delta)
		return
	if not is_instance_valid(heal_target) or heal_target.is_shielded():
		heal_target = null
		if attack_cd <= 0.0:
			var best := 420.0
			for b in allies:
				if is_instance_valid(b) and b != self and not b.is_shielded() and b.type != Type.MEDIC:
					var d: float = position.distance_to(b.position)
					if d < best:
						best = d
						heal_target = b
			attack_cd = 1.0
	if heal_target:
		var to_t: Vector2 = heal_target.position - position
		vel = vel.lerp(to_t.normalized() * speed * 1.4, 3.0 * delta)
		if to_t.length() < RADIUS * 2.0 + 14.0:
			heal_target.give_shield()
			heal_glow = 1.0
			sound.emit("heal")
			heal_target = null
			attack_cd = randf_range(3.0, 4.5) / aggr
		return
	if dist < 280.0:
		vel = vel.lerp(-to_head.normalized() * speed * 1.4, 3.0 * delta)
		return
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


# ---------------------------------------------------------------- рисование

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
		if st == St.DIZZY:
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
		var font := ThemeDB.fallback_font
		var col := Color(1, 0.15, 0.1) if st == St.WINDUP else Color(1, 0.7, 0.1)
		var txt := "ХЬЯ!" if type == Type.KARATE else "!"
		var fs := 16 if type == Type.KARATE else 26
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
