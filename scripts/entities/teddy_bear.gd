extends "res://scripts/entities/bear_body.gd"
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

const Snake = preload("res://scripts/entities/snake.gd")
const OilDrop = preload("res://scripts/entities/oil_drop.gd")

signal throw_item(pos: Vector2, velocity: Vector2, kind: int)
signal sound(sound_name: String)
signal puff(pos: Vector2)


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
				if snake.take_damage(dmg, "bear"):
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
	if lead_hint != Vector2.INF and not avenging:  # отряд подсказал, куда змею отбросит вилка
		lead = lead_hint
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
	if order != "" and _follow_order(delta, dist):
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


## Приказ отряда: бежать к точке прикрытия или к застрявшей вилке. false — приказ неактуален.
func _follow_order(delta: float, dist: float) -> bool:
	if dist < 110.0:  # змея вплотную — не до приказов
		return false
	var goal := order_pos
	if order == "rescue":
		if not is_instance_valid(order_target):
			order = ""
			return false
		goal = order_target.position
	if goal == Vector2.INF:
		return false
	var to_goal := goal - position
	if to_goal.length() < 14.0:
		vel = vel.move_toward(Vector2.ZERO, 600.0 * delta)
	else:
		vel = vel.lerp(to_goal.normalized() * speed * 1.6, 4.0 * delta)
	return true


func _recover(time: float) -> void:
	st = St.RECOVER
	st_t = time
	vel *= 0.3


func _get_dizzy(time: float) -> void:
	st = St.DIZZY
	st_t = time
	vel *= 0.3
