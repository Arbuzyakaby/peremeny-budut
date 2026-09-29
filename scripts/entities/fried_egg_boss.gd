extends Node2D
## Финальный босс — Гигантская Яичница (v8.0: переработана целиком).
## Уязвима, когда желток «открыт» — тогда змея должна укусить его головой. Ещё её понемногу ранят
## атаки змеи (take_chip): накопленный урон ≥ 1 снимает одно деление HP.
##
## Три фазы со своим характером (по доле HP), переход — рёв (ROAR), в котором она неуязвима:
##   1. ШКВОРЧИТ — кольцо брызг, таран, прицельный веер;
##   2. ПОДГОРАЕТ — плюс спираль масла, прыжок с ударной волной и горящие лужи масла (SIZZLE);
##   3. ПРИГОРЕЛА — плюс самонаводящиеся перчинки, темп выше, атаки чаще идут цепочкой.
## Каждая атака начинается с телеграфа (TELL): белок раздувается перед кольцом, к змее тянутся
## пунктиры прицела, на полу вспухают пузыри будущих луж, щёки надуваются перед перчинками.
##
## Яичница читает манеру змеи (habit): кружит ли та вокруг, держится ли далеко или липнет близко, —
## и выбирает атаки против этой манеры, а таран, веер и лужи бросает НАПЕРЕРЕЗ (predict).
## У каждой силовой атаки есть окно наказания (DAZED, желток открыт):
##   - таран, врезавшийся в бортик, — оглушена (DAZE_WALL);
##   - после последнего прыжка — вязнет в сковороде (DAZE_SLAM).
## После серии атак желток открывается как раньше (YOLK_OPEN).

signal shoot(pos: Vector2, velocity: Vector2, kind: int)
signal shockwave(pos: Vector2, gaps: int)
signal sound(sound_name: String)
signal bitten(hp_left: int)
signal phase_changed(phase: int)
signal yolk_opened
signal dazed(reason: String)
signal defeated

const Snake = preload("res://scripts/entities/snake.gd")
const Tex = preload("res://scripts/gfx/tex.gd")
const OilFilm = preload("res://scripts/entities/oil_film.gd")
const Design = preload("res://scripts/ui/design.gd")

enum Act { IDLE, TELL, RING, WINDUP, CHARGE, AIMED, SPIRAL, JUMP, FALL, PEPPER, SIZZLE, YOLK_OPEN, DAZED, HIT, ROAR, DEAD }
enum Atk { RING, CHARGE, AIMED, SPIRAL, SLAM, PEPPER, SIZZLE }

const WHITE_RADIUS := 150.0
const YOLK_RADIUS := 48.0
const YOLK_OFFSET := Vector2(0, -10)
const HIT_TIME := 0.8
const JUMP_TIME := 0.75
const FALL_TIME := 0.22
const JUMP_HEIGHT := 260.0
const ROAR_TIME := 1.2
const DAZE_WALL := 1.6       # таран в бортик: столько секунд оглушена, желток открыт
const DAZE_SLAM := 1.0       # после прыжка вязнет в сковороде
const DAZE_GRACE := 0.25     # оглушение началось — укус засчитывается не сразу (приземлилась прямо на змею)
const PUDDLE_RADIUS := 46.0
const PUDDLE_TELL := 0.9     # пузыри на полу — лужа ещё не горит
const PUDDLE_BURN := 2.6
const PUDDLE_MAX := 7
const ORBIT_READ := 0.8      # рад/с вокруг яичницы — «кружит»
const FAR_READ := 380.0
const CLOSE_READ := 240.0
const PHASE_NAMES := ["ШКВОРЧИТ", "ПОДГОРАЕТ", "ПРИГОРЕЛА"]
## Длительность телеграфа атаки (× tempo).
const TELL := {Atk.RING: 0.55, Atk.AIMED: 0.5, Atk.SPIRAL: 0.6, Atk.PEPPER: 0.5, Atk.SIZZLE: 0.45}


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
var tell_atk := -1          # какая атака телеграфируется (Act.TELL)
var aim_to := Vector2.ZERO  # куда нацелен телеграф (веер, таран, лужи)
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
var daze_reason := ""
var daze_total := 1.0
## Чтение змеи: сглаженные дистанция, угловая скорость вокруг яичницы и скорость головы.
var habit_dist := 300.0
var habit_orbit := 0.0
var head_vel := Vector2.ZERO
var _prev_head := Vector2.INF
## Горящие лужи масла: {pos, t (с рождения), r — радиус, до которого лужа растечётся}. Горят после
## PUDDLE_TELL, гаснут после PUDDLE_BURN. Растекание, нагрев и пламя — по физике масла (oil_film.gd):
## лужа растекается вязким течением, греется сковородой, дымит с 230 °C и вспыхивает с 340 °C —
## как раз к концу телеграфа.
var puddles: Array[Dictionary] = []
var stats := {"orbit": 0, "far": 0, "close": 0, "daze_wall": 0, "daze_slam": 0, "puddles": 0}
var lace: Array[Vector3] = []     # хрустящее кружево по краю: угол, радиус, размер
var blisters: Array[Vector3] = [] # пузыри на белке: угол, доля радиуса, фаза
var seeds: Array[float] = [randf() * TAU, randf() * TAU, randf() * TAU]


func _ready() -> void:
	material = Tex.material(Tex.Mat.EGG, randf() * 10.0)
	for i in 84:
		lace.append(Vector3(randf() * TAU, randf_range(0.92, 1.05), randf_range(4.0, 12.0)))
	for i in 9:
		blisters.append(Vector3(randf() * TAU, randf_range(0.45, 0.8), randf() * TAU))


func configure(boss_hp: int, projectile_speed: float, yolk_time: float, idle_tempo: float) -> void:
	max_hp = boss_hp
	hp = boss_hp
	proj_mult = projectile_speed
	yolk_mult = yolk_time
	tempo = idle_tempo


func phase() -> int:
	return clampi(1 + int(float(max_hp - hp) * 3.0 / max_hp), 1, 3)


func phase_name() -> String:
	return PHASE_NAMES[phase() - 1]


# ---------------------------------------------------------------- чтение змеи

## Сгладить наблюдения за змеёй: дистанцию, кружение вокруг яичницы, скорость головы.
func read_snake(head: Vector2, delta: float) -> void:
	if delta <= 0.0:
		return
	if _prev_head != Vector2.INF:
		var v := (head - _prev_head) / delta
		if v.length() < 2000.0:  # телепорт (отбрасывание, перезапуск) — не скорость
			head_vel = head_vel.lerp(v, clampf(delta * 6.0, 0.0, 1.0))
			var a0 := (_prev_head - position).angle()
			var a1 := (head - position).angle()
			habit_orbit = lerpf(habit_orbit, angle_difference(a0, a1) / delta, clampf(delta * 0.8, 0.0, 1.0))
	_prev_head = head
	habit_dist = lerpf(habit_dist, head.distance_to(position), clampf(delta * 0.6, 0.0, 1.0))


## Манера змеи: "orbit" — кружит, "far" — держится далеко, "close" — липнет, "" — ничего явного.
func habit() -> String:
	if absf(habit_orbit) > ORBIT_READ and habit_dist < FAR_READ + 120.0:
		return "orbit"
	if habit_dist > FAR_READ:
		return "far"
	if habit_dist < CLOSE_READ:
		return "close"
	return ""


## Куда голова придёт через time секунд (для «наперерез»), не дальше арены.
func predict(head: Vector2, time: float) -> Vector2:
	var inner := bounds.grow(-30.0)
	return (head + head_vel * time).clamp(inner.position, inner.end)


## Веса атак фазы p с поправкой на манеру змеи. Без повтора последней атаки.
func attack_weights(p: int, read: String) -> Dictionary:
	var w := {Atk.RING: 1.0, Atk.CHARGE: 1.0, Atk.AIMED: 1.0}
	if p >= 2:
		w[Atk.SPIRAL] = 0.8
		w[Atk.SLAM] = 0.9
		w[Atk.SIZZLE] = 0.9
	if p >= 3:
		w[Atk.PEPPER] = 0.8
	match read:
		"orbit":  # кружит — таран и веер наперерез, лужи на пути
			for k in [Atk.CHARGE, Atk.AIMED, Atk.SIZZLE]:
				if w.has(k):
					w[k] *= 2.2
		"far":  # держится далеко — достать издалека
			for k in [Atk.AIMED, Atk.SLAM, Atk.SIZZLE, Atk.PEPPER]:
				if w.has(k):
					w[k] *= 2.0
		"close":  # липнет — отогнать
			for k in [Atk.RING, Atk.SPIRAL, Atk.SLAM]:
				if w.has(k):
					w[k] *= 2.0
	w.erase(last_attack)
	return w


static func _pick(weights: Dictionary) -> int:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys()[0]


# ---------------------------------------------------------------- цикл

func update(delta: float, snake: Snake) -> void:
	t += delta
	flash = maxf(flash - delta * 2.5, 0.0)
	queue_redraw()
	_update_puddles(delta, snake)
	if not active or act == Act.DEAD:
		return

	var head := snake.head_pos
	last_head = head
	read_snake(head, delta)
	look_dir = (head - position).normalized()
	act_t -= delta
	shot_timer -= delta
	var p := phase()

	match act:
		Act.IDLE:
			var goal := bounds.get_center().lerp(head, 0.3)
			position = position.move_toward(goal, 40.0 * p * delta)
			if act_t <= 0.0:
				_next_attack(head)
		Act.TELL:
			if tell_atk == Atk.AIMED or tell_atk == Atk.SIZZLE:
				aim_to = predict(head, 0.5)
			if act_t <= 0.0:
				_launch(tell_atk, head)
		Act.RING:
			if shot_timer <= 0.0 and count_left > 0:
				_fire_ring()
				count_left -= 1
				shot_timer = 0.55 * tempo
			if act_t <= 0.0:
				_after_attack()
		Act.AIMED:
			if shot_timer <= 0.0 and count_left > 0:
				_fire_aimed(predict(head, head.distance_to(position) / (330.0 * proj_mult)))
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
				spiral_angle += 0.33 * signf(habit_orbit if habit_orbit != 0.0 else 1.0)  # крутит навстречу змее
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
		Act.SIZZLE:
			if shot_timer <= 0.0 and count_left > 0:
				_spit_puddle(head, count_left)
				count_left -= 1
				shot_timer = 0.22 * tempo
			if act_t <= 0.0:
				_after_attack()
		Act.WINDUP:
			aim_to = predict(head, 0.35)  # таран — наперерез
			if act_t <= 0.0:
				act = Act.CHARGE
				act_t = 0.75
				vel = (aim_to - position).normalized() * (520.0 + 120.0 * p) * proj_mult
				sound.emit("whoosh")
		Act.CHARGE:
			position += vel * delta
			var inner := bounds.grow(-WHITE_RADIUS * 0.7)
			var hit_wall := position.x < inner.position.x or position.x > inner.end.x \
				or position.y < inner.position.y or position.y > inner.end.y
			position = position.clamp(inner.position, inner.end)
			if head.distance_to(position) < WHITE_RADIUS * 0.8:
				if snake.take_damage(1, "boss"):
					snake.push((head - position).normalized() * 750.0)
			if hit_wall:  # врезалась в бортик — окно наказания
				vel = Vector2.ZERO
				stats["daze_wall"] += 1
				_daze("wall", DAZE_WALL)
			elif act_t <= 0.0:
				vel = Vector2.ZERO
				count_left -= 1
				if count_left > 0:
					act = Act.WINDUP
					act_t = 0.45 * tempo
					sound.emit("charge")
				else:
					_after_attack()
		Act.JUMP:
			var k := 1.0 - act_t / (JUMP_TIME * tempo)
			position = jump_from.lerp(jump_to, clampf(k, 0.0, 1.0))
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
					_start_jump(predict(head, JUMP_TIME * tempo * 0.6))
				else:
					stats["daze_slam"] += 1
					_daze("slam", DAZE_SLAM)
		Act.YOLK_OPEN, Act.DAZED, Act.HIT:
			if act_t <= 0.0:
				_go_idle()
		Act.ROAR:
			if act_t <= 0.0:
				_go_idle()

	# Столкновение головы змеи с желтком (в прыжке — нет)
	var yolk := position + YOLK_OFFSET
	if act != Act.HIT and act != Act.ROAR and height < 20.0 and head.distance_to(yolk) < YOLK_RADIUS + Snake.HEAD_RADIUS:
		var away := (head - yolk).normalized()
		if is_yolk_open():
			if act == Act.YOLK_OPEN or act_t < daze_total - DAZE_GRACE:
				_take_bite(snake, away)  # в первые мгновения оглушения укусить нельзя: не бесплатно
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


## Выбрать атаку против манеры змеи и начать её телеграф.
func _next_attack(head: Vector2) -> void:
	var read := habit()
	if read != "":
		stats[read] += 1
	var atk := _pick(attack_weights(phase(), read))
	last_attack = atk
	begin_attack(atk, head)


## Начать атаку (с телеграфом). Таран и прыжок телеграфируют по-своему: дрожь и прицел приземления.
func begin_attack(atk: int, head: Vector2) -> void:
	shot_timer = 0.2
	aim_to = predict(head, 0.5)
	match atk:
		Atk.CHARGE:
			act = Act.WINDUP
			count_left = phase()
			act_t = 0.7 * tempo
			sound.emit("charge")
		Atk.SLAM:
			count_left = 1 if phase() < 3 else 2
			_start_jump(predict(head, JUMP_TIME * tempo * 0.6))
		_:
			act = Act.TELL
			tell_atk = atk
			act_t = float(TELL[atk]) * tempo
			sound.emit("warn" if atk == Atk.AIMED else "charge")


func _launch(atk: int, head: Vector2) -> void:
	var p := phase()
	shot_timer = 0.0
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
			spiral_angle = (head - position).angle() + PI * 0.5
			act_t = 2.6
			sound.emit("shoot")
		Atk.PEPPER:
			act = Act.PEPPER
			count_left = 3 + (1 if proj_mult > 1.1 else 0)
			act_t = 0.35 * tempo * count_left + 0.8
		Atk.SIZZLE:
			act = Act.SIZZLE
			count_left = 3 if p < 3 else 4
			act_t = 0.22 * tempo * count_left + 0.5
			sound.emit("splat")


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


## Окно наказания: оглушена, желток открыт.
func _daze(reason: String, time: float) -> void:
	act = Act.DAZED
	daze_reason = reason
	daze_total = time * yolk_mult
	act_t = daze_total
	sound.emit("bonk" if reason == "wall" else "slam")
	dazed.emit(reason)
	yolk_opened.emit()


func _fire_ring() -> void:
	var p := phase()
	var n := 8 + 4 * p
	var offset := randf() * TAU
	for i in n:
		var dir := Vector2.from_angle(offset + TAU * i / n)
		var kind := 1 if p >= 3 and i % 3 == 0 else 0
		shoot.emit(position + dir * WHITE_RADIUS * 0.6, dir * (170.0 + 40.0 * p) * proj_mult, kind)
	sound.emit("shoot")


func _fire_aimed(target: Vector2) -> void:
	var p := phase()
	var fan := 3 if p == 1 else 5
	var base := (target - position).angle()
	for i in fan:
		var dir := Vector2.from_angle(base + (i - (fan - 1) / 2.0) * 0.17)
		shoot.emit(position + dir * WHITE_RADIUS * 0.5, dir * 330.0 * proj_mult, 0)
	sound.emit("shoot")


# ---------------------------------------------------------------- лужи масла

## Плевок: лужа ложится туда, куда ползёт змея (первая — на прогноз, остальные — веером вокруг).
func _spit_puddle(head: Vector2, left: int) -> void:
	var at := predict(head, 0.8)
	if left % 2 == 0:
		at += Vector2.from_angle(randf() * TAU) * randf_range(60.0, 130.0)
	add_puddle(at)
	sound.emit("pepper")


func add_puddle(at: Vector2) -> void:
	var inner := bounds.grow(-PUDDLE_RADIUS)
	puddles.append({"pos": at.clamp(inner.position, inner.end), "t": 0.0, "r": PUDDLE_RADIUS * randf_range(0.85, 1.15)})
	while puddles.size() > PUDDLE_MAX:
		puddles.pop_front()
	stats["puddles"] += 1


## Текущий радиус лужи, px: она ещё растекается (Хапперт), но не шире своего предела.
static func puddle_radius(pd: Dictionary) -> float:
	return float(OilFilm.state(float(pd["r"]), float(pd["t"]))["r_px"])


static func puddle_burning(pd: Dictionary) -> bool:
	return float(pd["t"]) >= PUDDLE_TELL and float(pd["t"]) < PUDDLE_TELL + PUDDLE_BURN


func _update_puddles(delta: float, snake: Snake) -> void:
	for i in range(puddles.size() - 1, -1, -1):
		var pd := puddles[i]
		pd["t"] = float(pd["t"]) + delta
		if float(pd["t"]) > PUDDLE_TELL + PUDDLE_BURN + 0.4:
			puddles.remove_at(i)
			continue
		if active and act != Act.DEAD and snake and snake.alive and puddle_burning(pd) \
				and snake.head_pos.distance_to(pd["pos"]) < puddle_radius(pd) * 0.8:
			if snake.take_damage(1, "oil"):
				snake.slow(0.8)


# ---------------------------------------------------------------- урон

## Желток можно укусить: открыт после серии или в окне наказания.
func is_yolk_open() -> bool:
	return act == Act.YOLK_OPEN or act == Act.DAZED


## Урон от атак змеи. Возвращает false, если сейчас не пробить (в прыжке, ревёт, ранена, мертва).
func take_chip(amount: float) -> bool:
	if not active or act in [Act.DEAD, Act.HIT, Act.ROAR] or height > 20.0:
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
		last_phase = phase()
		bitten.emit(hp)


func _take_bite(snake: Snake, away: Vector2) -> void:
	snake.push(away * 650.0)
	_lose_hp(bite_damage)


func _lose_hp(amount := 1) -> void:
	hp = maxi(hp - amount, 0)
	flash = 1.0
	height = 0.0  # ранена на взлёте или в конце падения — на пол, иначе зависнет над ним
	vel = Vector2.ZERO
	bitten.emit(hp)
	if hp <= 0:
		act = Act.DEAD
		puddles.clear()
		defeated.emit()
		return
	act = Act.HIT
	act_t = HIT_TIME
	if phase() != last_phase:
		last_phase = phase()
		act = Act.ROAR  # новая фаза — рёв: неуязвима, пар, масло гаснет
		act_t = ROAR_TIME
		chip = 0.0
		puddles.clear()
		sound.emit("roar")
		phase_changed.emit(last_phase)


# ---------------------------------------------------------------- рисунок

func _draw() -> void:
	var p := phase()
	var rage := float(p - 1) / 2.0
	var in_air := act == Act.JUMP or act == Act.FALL
	_draw_puddles()
	_draw_pan_oil(in_air)

	# Прицел места приземления — язык телеграфов 2.2: «здесь ударит»
	if in_air:
		var total := JUMP_TIME * tempo + FALL_TIME
		var left := act_t + (FALL_TIME if act == Act.JUMP else 0.0)
		Design.draw_tell_ring(self, jump_to - position, WHITE_RADIUS * 0.9, Design.Tell.AREA, 1.0 - left / total)
	_draw_tell()

	var offset := Vector2(0, -height)
	var sq := Vector2(1.0 + 0.02 * sin(t * 2.0), 1.0 - 0.02 * sin(t * 2.0))
	match act:
		Act.WINDUP:
			offset += Vector2(randf_range(-5, 5), randf_range(-5, 5))
			sq *= Vector2(1.06, 0.92)
		Act.TELL:
			var k := 1.0 - act_t / maxf(float(TELL.get(tell_atk, 0.5)) * tempo, 0.01)
			if tell_atk == Atk.RING or tell_atk == Atk.SPIRAL:
				sq *= Vector2.ONE * (1.0 + 0.1 * k)  # раздувается перед выстрелом
			else:
				sq *= Vector2(1.0 + 0.05 * k, 1.0 - 0.05 * k)
		Act.HIT:
			var k := act_t / HIT_TIME
			sq *= Vector2(1.0 + 0.18 * k * sin(t * 30.0), 1.0 - 0.18 * k * sin(t * 30.0))
		Act.ROAR:
			var k := act_t / ROAR_TIME
			sq *= Vector2.ONE * (1.0 + 0.12 * k * absf(sin(t * 16.0)))
			offset += Vector2(randf_range(-3, 3), randf_range(-3, 3)) * k
		Act.DAZED:
			sq *= Vector2(1.0 + 0.06 * sin(t * 5.0), 1.0 - 0.06 * sin(t * 5.0))
			if daze_reason == "slam":
				sq *= Vector2(1.12, 0.88)  # расплылась по сковороде
	if in_air:
		sq *= Vector2(0.92, 1.1)

	# Тень
	var shadow_k := 1.0 - height / (JUMP_HEIGHT * 1.6)
	Tex.blob(self, Vector2(10, 16), Vector2.ONE * WHITE_RADIUS * 1.3 * shadow_k, Color(0, 0, 0, 0.3 * shadow_k))

	draw_set_transform(offset, 0.0, sq)
	_draw_white(p, rage)
	_draw_yolk(rage)
	_draw_face()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_steam(rage, offset)
	if act == Act.DAZED:
		_draw_stars(offset)


## Масло сковороды вокруг яичницы: глянцевое пятно и лопающиеся пузырьки (яичница «жарится»).
func _draw_pan_oil(in_air: bool) -> void:
	if in_air:
		return
	var r := WHITE_RADIUS * 1.22
	Tex.blob(self, Vector2(0, 6), Vector2(r, r * 0.9), Color(0.95, 0.72, 0.2, 0.16))
	for i in 14:
		var ph := fmod(t * (0.7 + 0.05 * i) + i * 0.37, 1.0)
		var a := seeds[i % 3] + i * 0.45 + floorf(t * (0.7 + 0.05 * i) + i * 0.37) * 1.7
		var bp := Vector2.from_angle(a) * WHITE_RADIUS * (1.05 + 0.1 * float(i % 3))
		var br := 2.0 + 3.0 * ph
		draw_arc(bp, br, 0, TAU, 10, Color(1, 0.93, 0.6, 0.55 * (1.0 - ph)), 1.3)


func _draw_white(p: int, rage: float) -> void:
	var crust := Color(0.86, 0.6, 0.26).lerp(Color(0.62, 0.3, 0.1), rage)
	var char_col := Color(0.2, 0.1, 0.05)
	var white := Color(0.99, 0.98, 0.94)
	if act == Act.WINDUP or act == Act.CHARGE:
		white = white.lerp(Color(1.0, 0.78, 0.72), 0.45)
	elif act == Act.ROAR:
		white = white.lerp(Color(1.0, 0.6, 0.4), 0.35)
	white = white.lerp(Color(1, 0.4, 0.4), flash * 0.6)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 64:
		var a := TAU * i / 64.0
		var r := WHITE_RADIUS * (1.0 + 0.07 * sin(3.0 * a + seeds[0] + t * 1.5) \
			+ 0.05 * sin(5.0 * a + seeds[1] - t * 2.2) + 0.03 * sin(9.0 * a + seeds[2]))
		var v := Vector2.from_angle(a)
		outer.append(v * r)
		inner.append(v * (r - 10.0))
	for l in lace:  # хрустящее поджаристое кружево по краю: темнеет с каждой фазой
		var lp := Vector2.from_angle(l.x) * WHITE_RADIUS * l.y
		var burnt := smoothstep(0.35, 1.0, rage) * (0.5 + 0.5 * sin(l.x * 7.0 + seeds[1]))
		var c := crust.lerp(char_col, burnt)
		draw_circle(lp, l.z, c.darkened(0.25))
		draw_circle(lp + Vector2(-1, -1), l.z * 0.6, c.lightened(0.12))
	draw_colored_polygon(outer, crust)
	# полупрозрачный край белка (сквозь него чуть видно масло) и плотная середина
	draw_colored_polygon(inner, white.darkened(0.06).lerp(Color(0.93, 0.9, 0.8), 0.3))
	var mid := PackedVector2Array()
	for v in inner:
		mid.append(v * 0.8 + Vector2(-4, -5))
	draw_colored_polygon(mid, white)
	Tex.blob(self, Vector2(-40, -52), Vector2(100, 72), Color(1, 1, 1, 0.5))
	# пригоревшие пятна на третьей фазе
	if p >= 3:
		for i in 5:
			var sp := Vector2.from_angle(seeds[i % 3] * 3.0 + i * 1.25) * WHITE_RADIUS * 0.86
			Tex.blob(self, sp, Vector2(22, 14), Color(0.35, 0.18, 0.06, 0.55))
	# пузыри на белке: вспухают и лопаются
	for b in blisters:
		var ph := fmod(t * 0.35 + b.z, TAU) / TAU
		var bp := Vector2.from_angle(b.x) * WHITE_RADIUS * b.y
		var br := 4.0 + 7.0 * smoothstep(0.0, 0.8, ph) * (1.0 - smoothstep(0.92, 1.0, ph))
		if br < 4.5:
			continue
		draw_circle(bp + Vector2(1.5, 2), br, Color(0.82, 0.78, 0.7, 0.5))
		draw_circle(bp, br, Color(0.97, 0.95, 0.9))
		draw_arc(bp, br, 0, TAU, 14, Color(0.78, 0.74, 0.66), 1.4)
		draw_circle(bp + Vector2(-br * 0.35, -br * 0.35), br * 0.3, Color(1, 1, 1, 0.95))
	for i in 3:  # масляные блики
		var op := Vector2.from_angle(seeds[i] * 2.0 + 0.8) * 112.0
		Tex.blob(self, op, Vector2(20, 9), Color(1, 0.85, 0.35, 0.35))


func _draw_yolk(rage: float) -> void:
	var yc := YOLK_OFFSET
	var yr := YOLK_RADIUS
	var open := is_yolk_open()
	if open:
		var pulse := 0.5 + 0.5 * sin(t * 10.0)
		draw_circle(yc, yr + 12.0 + 8.0 * pulse, Color(1.0, 0.95, 0.3, 0.35))
		draw_arc(yc, yr + 7.0, 0, TAU, 40, Design.tell_color(Design.Tell.OPEN, 0.85), Design.telegraph_width(3.0))  # «окно — бей»
		yr *= 1.0 + 0.06 * pulse
		var total := daze_total if act == Act.DAZED else 0.8
		if act_t < minf(0.8, total * 0.5) and int(act_t * 10.0) % 2 == 0:  # скоро закроется
			draw_arc(yc, yr + 16.0, 0, TAU, 40, Color(1, 0.3, 0.1, 0.8), 3.0)
	Tex.blob(self, yc + Vector2(6, 10), Vector2.ONE * yr * 1.35, Color(0.55, 0.3, 0.0, 0.35))
	draw_circle(yc + Vector2(3, 5), yr, Color(0.82, 0.4, 0.04))       # тень купола
	var yolk_col := Color(1.0, 0.8, 0.1) if open else Color(0.95, 0.6, 0.12).lerp(Color(0.85, 0.45, 0.1), rage)
	draw_circle(yc, yr, yolk_col.darkened(0.1))
	draw_circle(yc + Vector2(-3, -4), yr * 0.86, yolk_col)
	draw_circle(yc + Vector2(-8, -10), yr * 0.52, yolk_col.lightened(0.14))
	if open:  # жидкий: блестящий, дрожит, по краю стекает капля
		var drip := yc + Vector2.from_angle(PI * 0.35) * yr
		draw_circle(drip + Vector2(0, 4 + 3 * sin(t * 4.0)), 7.0, yolk_col.darkened(0.05))
	else:  # запёкшаяся плёнка с морщинками — укусить нельзя
		draw_circle(yc, yr, Color(1, 1, 1, 0.2))
		draw_arc(yc, yr - 3.0, 0, TAU, 32, Color(1, 1, 1, 0.32), 3.0)
		for i in 3:
			var a := seeds[i] + i * 2.1
			draw_arc(yc + Vector2.from_angle(a) * yr * 0.4, yr * 0.35, a + 0.6, a + 2.0, 8, Color(0.75, 0.45, 0.08, 0.5), 1.5)
	Tex.blob(self, yc + Vector2(-yr * 0.4, -yr * 0.45), Vector2.ONE * yr * 0.36, Color(1, 1, 1, 0.75))
	draw_circle(yc + Vector2(-yr * 0.42, -yr * 0.45), yr * 0.14, Color(1, 1, 1, 0.95))
	if act == Act.TELL and tell_atk == Atk.PEPPER:  # перчинки проступают на желтке
		for i in 6:
			draw_circle(yc + Vector2.from_angle(i * 1.05 + t) * yr * 0.55, 3.0, Color(0.12, 0.08, 0.06))


func _draw_face() -> void:
	var yc := YOLK_OFFSET
	var dark := Color(0.35, 0.15, 0.05)
	var hurt := act == Act.HIT or act == Act.DEAD
	var angry := act in [Act.WINDUP, Act.CHARGE, Act.JUMP, Act.FALL, Act.TELL, Act.ROAR]
	var blink := fmod(t + seeds[0], 3.7) < 0.12 and not angry and not hurt
	for s in [-1.0, 1.0]:
		var e: Vector2 = yc + Vector2(s * 16.0, -6.0)
		if hurt:
			draw_line(e - Vector2(5, 5), e + Vector2(5, 5), dark, 3.0)
			draw_line(e - Vector2(5, -5), e + Vector2(5, -5), dark, 3.0)
		elif act == Act.DAZED:  # закатившиеся глаза-спирали
			for k in 3:
				draw_arc(e, 2.5 + k * 2.2, t * 6.0 * s + k, t * 6.0 * s + k + 4.2, 10, dark, 1.6)
		elif blink:
			draw_line(e - Vector2(7, 0), e + Vector2(7, 0), dark, 3.0)
		else:
			draw_circle(e, 8.5, Color.WHITE)
			var pupil := Color(0.85, 0.05, 0.0) if angry else Color.BLACK
			draw_circle(e + look_dir * 3.5, 4.2, pupil)
			if angry:
				Tex.blob(self, e + look_dir * 3.5, Vector2.ONE * 7.0, Color(1, 0.3, 0.1, 0.45))
			draw_circle(e + look_dir * 3.5 + Vector2(-1.2, -1.4), 1.3, Color(1, 1, 1, 0.9))
		var brow_lift := -4.0 if is_yolk_open() else (3.0 if angry else 0.0)
		draw_line(e + Vector2(s * 12.0, -13.0 + brow_lift), e + Vector2(-s * 7.0, -7.0 - brow_lift * 0.5), dark, 4.0)
	# щёки: надуваются перед плевком и перчинками
	if act == Act.TELL and (tell_atk == Atk.SIZZLE or tell_atk == Atk.PEPPER):
		for s in [-1.0, 1.0]:
			draw_circle(yc + Vector2(s * 26.0, 14.0), 9.0, Color(0.95, 0.35, 0.2, 0.55))
	if act == Act.ROAR:
		var k := 0.6 + 0.4 * absf(sin(t * 16.0))
		draw_circle(yc + Vector2(0, 25), 12.0 * k, dark)  # рёв
		draw_circle(yc + Vector2(0, 29), 6.0 * k, Color(0.8, 0.2, 0.15))
	elif is_yolk_open() or hurt:
		draw_circle(yc + Vector2(0, 22), 7.0, dark)  # испуганный «о»
	elif act in [Act.RING, Act.SPIRAL, Act.AIMED, Act.PEPPER, Act.SIZZLE]:
		draw_circle(yc + Vector2(0, 24), 9.0, dark)  # орёт и плюётся
		draw_circle(yc + Vector2(0, 27), 5.0, Color(0.8, 0.2, 0.15))
	else:
		draw_arc(yc + Vector2(0, 30), 13.0, PI + 0.5, TAU - 0.5, 12, dark, 3.5)  # злой рот


## Телеграфы: что сейчас прилетит.
func _draw_tell() -> void:
	if act == Act.WINDUP:  # таран: пунктир наперерез
		var dir := (aim_to - position).normalized()
		Design.draw_dashes(self, dir * (WHITE_RADIUS + 16.0), aim_to - position + dir * 60.0,
			Design.tell_color(Design.Tell.AIM, 0.85), 6.0, 22.0, 12.0, t)
		return
	if act != Act.TELL:
		return
	var k := 1.0 - act_t / maxf(float(TELL.get(tell_atk, 0.5)) * tempo, 0.01)
	match tell_atk:
		Atk.RING:  # край белка светится там, откуда полетят брызги
			var n := 8 + 4 * phase()
			for i in n:
				var v := Vector2.from_angle(TAU * i / n + t * 0.5) * WHITE_RADIUS * 1.02
				draw_circle(v, 3.0 + 4.0 * k, Color(1, 0.85, 0.3, 0.3 + 0.6 * k))
		Atk.AIMED:  # пунктиры прицела к упреждённой точке
			var fan := 3 if phase() == 1 else 5
			var base := (aim_to - position).angle()
			for i in fan:
				var dir := Vector2.from_angle(base + (i - (fan - 1) / 2.0) * 0.17)
				Design.draw_dashes(self, dir * WHITE_RADIUS * 0.7, dir * 520.0,
					Design.tell_color(Design.Tell.AIM, 0.3 + 0.5 * k), 3.0, 16.0, 14.0, t)
		Atk.SPIRAL:
			for i in 4:
				var a := TAU * i / 4.0 + t * 4.0
				draw_arc(Vector2.ZERO, WHITE_RADIUS * 1.12, a, a + 0.6, 10, Color(1, 0.8, 0.3, 0.3 + 0.5 * k), 4.0)
		Atk.SIZZLE:  # на полу проступает место будущей лужи
			Design.draw_tell_ring(self, aim_to - position, PUDDLE_RADIUS, Design.Tell.AREA, k)


func _draw_puddles() -> void:
	for pd in puddles:
		var c: Vector2 = pd["pos"] - position
		var tt: float = pd["t"]
		var st := OilFilm.state(float(pd["r"]), tt)
		var r: float = st["r_px"]
		if tt < PUDDLE_TELL:  # масло растекается и греется: блестит, пузырится, с 230 °C дымит
			var k := tt / PUDDLE_TELL
			var hot := clampf((float(st["temp"]) - OilFilm.T_SPIT) / (OilFilm.T_FIRE - OilFilm.T_SPIT), 0.0, 1.0)
			draw_circle(c, r, Color(0.55, 0.38, 0.08, 0.45).lerp(Color(0.45, 0.25, 0.05, 0.55), hot))
			draw_arc(c + Vector2(-r * 0.3, -r * 0.3), r * 0.5, 3.6, 4.6, 8, Color(1, 0.95, 0.75, 0.5), 2.0)  # блик
			Design.draw_tell_ring(self, c, float(pd["r"]), Design.Tell.AREA, k)
			for i in 4:
				var bp := c + Vector2.from_angle(i * 1.6 + tt * 3.0) * r * 0.45
				draw_arc(bp, 3.0 + 3.0 * fmod(tt * 2.0 + i * 0.3, 1.0), 0, TAU, 8, Color(1, 0.9, 0.6, 0.6), 1.2)
			if st["smoking"]:  # точка дымления: сизый дымок
				for i in 3:
					var ph := fmod(tt * 1.5 + i * 0.33, 1.0)
					Tex.blob(self, c + Vector2(sin(i * 2.1 + tt) * r * 0.3, -ph * 40.0), Vector2.ONE * (8.0 + 12.0 * ph),
						Color(0.8, 0.82, 0.88, 0.3 * (1.0 - ph)))
			continue
		var fade := 1.0 - clampf((tt - PUDDLE_TELL - PUDDLE_BURN) / 0.4, 0.0, 1.0)
		draw_circle(c, r, Color(0.3, 0.16, 0.04, 0.7 * fade))
		Tex.blob(self, c, Vector2.ONE * r * 1.25, Color(1.0, 0.45, 0.08, 0.35 * fade))
		# пламя: высота по Хескестаду (в виде сверху укорочена), пульсации 1,5/√D
		var fl0 := clampf(float(st["flame_m"]) / OilFilm.PX_M * 0.06, 8.0, 34.0)
		var ph0 := tt * TAU * float(st["puff_hz"])
		for i in 7:  # язычки пламени на масле: у основания синие, выше — жёлтые от сажи
			var a := i * TAU / 7.0 + seeds[i % 3]
			var fp := c + Vector2.from_angle(a) * r * 0.55
			var fl := fl0 * (0.85 + 0.15 * sin(ph0 + i * 0.9))
			var sway := sin(ph0 * 0.5 + i) * 3.0
			var tongue := PackedVector2Array([fp + Vector2(-6, 0), fp + Vector2(6, 0), fp + Vector2(sway, -fl)])
			draw_colored_polygon(tongue, Color(1.0, 0.62, 0.15, 0.85 * fade))
			var core := PackedVector2Array([fp + Vector2(-3, 0), fp + Vector2(3, 0), fp + Vector2(sway * 0.5, -fl * 0.45)])
			draw_colored_polygon(core, Color(1.0, 0.92, 0.55, 0.9 * fade))
			draw_line(fp + Vector2(-5, 0), fp + Vector2(5, 0), Color(0.35, 0.5, 1.0, 0.7 * fade), 2.0)
		draw_arc(c, r, 0, TAU, 28, Color(1, 0.35, 0.05, 0.6 * fade), 2.0)


## Пар над яичницей: гуще с каждой фазой, на третьей — с дымком.
func _draw_steam(rage: float, offset: Vector2) -> void:
	var n := 3 + int(rage * 5.0) + (4 if act == Act.ROAR else 0)
	for i in n:
		var ph := fmod(t * 0.45 + i * 0.37, 1.0)
		var x := sin(i * 2.3 + seeds[i % 3]) * WHITE_RADIUS * 0.6 + sin(t + i) * 10.0
		var p := offset + Vector2(x, -WHITE_RADIUS * 0.3 - ph * 160.0)
		var col := Color(1, 1, 1, 0.16 * (1.0 - ph)).lerp(Color(0.25, 0.22, 0.2, 0.2 * (1.0 - ph)), rage * 0.6)
		Tex.blob(self, p, Vector2.ONE * (18.0 + 30.0 * ph), col)


func _draw_stars(offset: Vector2) -> void:
	for i in 4:
		var a := t * 3.0 + TAU * i / 4.0
		var sp := offset + YOLK_OFFSET + Vector2(cos(a) * 60.0, -70.0 + sin(a) * 14.0)
		var pts := PackedVector2Array()
		for k in 10:
			pts.append(sp + Vector2.from_angle(k * TAU / 10.0 - PI / 2) * (8.0 if k % 2 == 0 else 3.5))
		draw_colored_polygon(pts, Color(1, 0.9, 0.3))
