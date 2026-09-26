extends Node2D
## Змея со свободным движением. Рисуется в мировых координатах (сам узел стоит в (0, 0)).
## Навыки и улучшения приходят словарём модификаторов (skills.gd → apply_mods).

signal damaged(lives_left: int)
signal died

const Settings = preload("res://scripts/settings.gd")
const Tex = preload("res://scripts/tex.gd")

const STEP := 3.0            # расстояние между точками следа
const POINTS_PER_SEGMENT := 3 # сегмент тела = каждая 3-я точка следа (9 px)
const HEAD_RADIUS := 16.0
const BODY_RADIUS := 13.0
const BASE_SPEED := 220.0
const SPRINT_SPEED := 370.0
const DASH_SPEED := 680.0
const STAMINA_DRAIN := 0.45     # в секунду спринта
const STAMINA_REGEN := 0.22     # в секунду отдыха
const EXHAUST_RECOVER := 0.35   # после полного истощения спринт снова доступен с этого уровня
const TURN_SPEED := 4.2
const INVULN_TIME := 1.5
const SELF_HIT_SKIP := 14     # первые сегменты за головой не проверяем на самоукус

var bounds := Rect2(0, 0, 1280, 720)
var head_pos := Vector2(640, 450)
var heading := -PI / 2
var trail := PackedVector2Array()
var length := 12
var lives := 3
var max_lives := 3
var invuln := 0.0
var slow_timer := 0.0
var stun_t := 0.0
var shield := 0      # щит поглощает удар (заплатка, улучшение)
var stamina := 1.0   # доля «бака» 0..1
var exhausted := false
var sprinting := false
var dash_t := 0.0   # удар с разбега (боксёр) или теневой рывок (ниндзя)
var dash_speed := DASH_SPEED
var shadow_dash := false
var spin_t := 0.0   # вертушка (способность каратиста)
var knockback := Vector2.ZERO
var use_mouse := false
var alive := true
var anim_t := 0.0
var bite_t := 0.0
var shield_flash := 0.0
## Катсцена: змея ползает сама, без урона.
var autopilot := false
var auto_speed := 90.0
var auto_target := Vector2(640, 360)
var burnt := 0.0  # 0..1 — обугливание
var small := 1.0  # масштаб (новорождённая змейка в финале)

# модификаторы навыков
var stamina_max := 1.0
var regen_mult := 1.0
var drain_mult := 1.0
var turn_mult := 1.0
var sprint_mult := 1.0
var invuln_bonus := 0.0
var resist := 1.0      # множитель длительности оглушения и замедления
var extra_life := false  # «Линька»: пережить смертельный удар
var molt_used := false


func apply_mods(m: Dictionary) -> void:
	stamina_max = m.get("stamina_max", 1.0)
	regen_mult = m.get("regen", 1.0)
	drain_mult = m.get("drain", 1.0)
	turn_mult = m.get("turn", 1.0)
	sprint_mult = m.get("sprint", 1.0)
	invuln_bonus = m.get("invuln", 0.0)
	resist = m.get("resist", 1.0)
	extra_life = m.get("molt", false) and not molt_used


func reset(pos: Vector2) -> void:
	head_pos = pos
	heading = -PI / 2
	trail.clear()
	var back := -Vector2.from_angle(heading)
	for i in length * POINTS_PER_SEGMENT + 1:
		trail.append(pos + back * STEP * i)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.relative.length() > 2.0 and Settings.mouse_control:
		use_mouse = true


func update(delta: float) -> void:
	anim_t += delta
	invuln = maxf(invuln - delta, 0.0)
	slow_timer = maxf(slow_timer - delta, 0.0)
	stun_t = maxf(stun_t - delta, 0.0)
	bite_t = maxf(bite_t - delta, 0.0)
	shield_flash = maxf(shield_flash - delta * 2.0, 0.0)
	modulate.a = 0.35 if invuln > 0.0 and dash_t <= 0.0 and int(invuln * 12.0) % 2 == 0 else 1.0
	if shadow_dash and dash_t > 0.0:
		modulate.a = 0.55
	queue_redraw()
	if not alive:
		return
	if autopilot:
		_autopilot(delta)
		return

	# Поворот: клавиши или мышь (оглушённая змея не управляется)
	var turn_speed := TURN_SPEED * turn_mult
	if stun_t > 0.0:
		heading += sin(anim_t * 9.0) * 2.5 * delta
	else:
		var turn := Input.get_axis("turn_left", "turn_right")
		if turn != 0.0:
			use_mouse = false
			heading += turn * turn_speed * delta
		elif use_mouse:
			var to_mouse := get_global_mouse_position() - head_pos
			if to_mouse.length() > 24.0:
				heading = rotate_toward(heading, to_mouse.angle(), turn_speed * delta)

	# Скорость: спринт тратит стамину; при нуле змея выдыхается и ползёт медленнее
	var speed := BASE_SPEED
	sprinting = Input.is_action_pressed("sprint") and not exhausted and stamina > 0.0 and stun_t <= 0.0
	if sprinting:
		speed = BASE_SPEED + (SPRINT_SPEED - BASE_SPEED) * sprint_mult
		stamina = maxf(stamina - delta * STAMINA_DRAIN * drain_mult / stamina_max, 0.0)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = minf(stamina + delta * STAMINA_REGEN * regen_mult / sqrt(stamina_max) * (0.7 if exhausted else 1.0), 1.0)
		if exhausted and stamina >= EXHAUST_RECOVER:
			exhausted = false
	if exhausted:
		speed *= 0.8
	if slow_timer > 0.0:
		speed *= 0.5
	if stun_t > 0.0:
		speed *= 0.35
	spin_t = maxf(spin_t - delta, 0.0)
	if dash_t > 0.0:
		dash_t -= delta
		speed = dash_speed
		if dash_t <= 0.0:
			shadow_dash = false

	head_pos += Vector2.from_angle(heading) * speed * delta + knockback * delta
	knockback = knockback.move_toward(Vector2.ZERO, 1800.0 * delta)

	_check_walls()
	_extend_trail()
	_check_self_bite()


func _autopilot(delta: float) -> void:
	var area := bounds.grow(-70.0)
	if head_pos.distance_to(auto_target) < 50.0:
		auto_target = area.position + Vector2(randf(), randf()) * area.size
	heading = rotate_toward(heading, (auto_target - head_pos).angle(), TURN_SPEED * delta)
	head_pos += Vector2.from_angle(heading) * auto_speed * delta + knockback * delta
	knockback = knockback.move_toward(Vector2.ZERO, 1800.0 * delta)
	head_pos = head_pos.clamp(bounds.grow(-HEAD_RADIUS).position, bounds.grow(-HEAD_RADIUS).end)
	_extend_trail()


func _extend_trail() -> void:
	while head_pos.distance_to(trail[0]) >= STEP:
		trail.insert(0, trail[0] + (head_pos - trail[0]).normalized() * STEP)
	var max_points := length * POINTS_PER_SEGMENT + 1
	if trail.size() > max_points:
		trail.resize(max_points)


func _check_walls() -> void:
	var inner := bounds.grow(-HEAD_RADIUS)
	var hit := false
	if head_pos.x < inner.position.x or head_pos.x > inner.end.x:
		heading = PI - heading
		hit = true
	if head_pos.y < inner.position.y or head_pos.y > inner.end.y:
		heading = -heading
		hit = true
	if hit:
		head_pos = head_pos.clamp(inner.position, inner.end)
		knockback = Vector2.ZERO
		take_damage()


func _check_self_bite() -> void:
	var segs := get_segments()
	for i in range(SELF_HIT_SKIP, segs.size()):
		if head_pos.distance_to(segs[i]) < BODY_RADIUS * 1.2:
			take_damage()
			return


func get_segments() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, trail.size(), POINTS_PER_SEGMENT):
		out.append(trail[i])
	return out


## Потратить стамину на атаку. false — не хватает сил.
func spend(amount: float) -> bool:
	amount /= stamina_max
	if stamina < amount:
		return false
	stamina -= amount
	if stamina <= 0.01:
		exhausted = true
	return true


func dash(time: float, speed := DASH_SPEED, shadow := false) -> void:
	dash_t = time
	dash_speed = speed
	shadow_dash = shadow
	invuln = maxf(invuln, time + (0.9 if shadow else 0.1))


func is_dashing() -> bool:
	return dash_t > 0.0


func grow(amount: int) -> void:
	length += amount
	bite_t = 0.25


func slow(time: float) -> void:
	slow_timer = maxf(slow_timer, time * resist)


## Оглушение: управление отключено. Во время рывка не действует. true — оглушило.
func stun(time: float) -> bool:
	if dash_t > 0.0 or not alive or stun_t > 0.0:
		return false
	stun_t = time * resist
	return true


func is_stunned() -> bool:
	return stun_t > 0.0


func push(force: Vector2) -> void:
	knockback = force
	heading = force.angle()


func heal(amount := 1) -> bool:
	if lives >= max_lives:
		return false
	lives = mini(lives + amount, max_lives)
	damaged.emit(lives)
	return true


## Возвращает true, если урон действительно прошёл (не было неуязвимости).
func take_damage(amount := 1) -> bool:
	if invuln > 0.0 or not alive:
		return false
	if shield > 0:
		shield -= 1
		shield_flash = 1.0
		invuln = 0.8
		return false
	lives = maxi(lives - amount, 0)
	invuln = INVULN_TIME + invuln_bonus
	if lives <= 0 and extra_life:  # линька: сбросить шкуру и выжить
		extra_life = false
		molt_used = true
		lives = 1
		invuln = 2.5
		shield_flash = 1.0
	damaged.emit(lives)
	if lives <= 0:
		alive = false
		died.emit()
	return true


# ---------------------------------------------------------------- рисование

func _draw() -> void:
	var segs := get_segments()
	var n := segs.size()
	var slowed := slow_timer > 0.0
	var ash := Color(0.13, 0.1, 0.08)
	var outline := Color(0.06, 0.24, 0.08).lerp(Color.BLACK, burnt)
	# Тень
	for i in range(n - 1, 0, -2):
		var r := _seg_radius(i, n) * small
		Tex.blob(self, segs[i] + Vector2(5, 8) * small, Vector2(r, r) * 1.5, Color(0, 0, 0, 0.16))
	Tex.blob(self, head_pos + Vector2(5, 8) * small, Vector2.ONE * HEAD_RADIUS * 1.6 * small, Color(0, 0, 0, 0.2))
	# Контур
	for i in range(n - 1, 0, -1):
		draw_circle(segs[i], _seg_radius(i, n) * small + 2.5, outline)
	# Заливка: объём, узор ромбами, чешуя
	for i in range(n - 1, 0, -1):
		var r := _seg_radius(i, n) * small
		var dir := (segs[i - 1] - segs[i]).normalized()
		var side := dir.orthogonal()
		var c := Color(0.33, 0.76, 0.28) if (i / 3) % 2 == 0 else Color(0.27, 0.67, 0.23)
		if slowed:
			c = c.lerp(Color.WHITE, 0.45)
		c = c.lerp(ash, burnt * 0.9)
		draw_circle(segs[i], r, c.darkened(0.18))
		draw_circle(segs[i] + Vector2(-1.2, -1.6) * small, r * 0.82, c)
		if i % 3 == 0 and burnt < 0.5:  # тёмный ромб узора на спине
			var d := r * 0.55
			draw_colored_polygon(PackedVector2Array([segs[i] + dir * d, segs[i] + side * d * 0.7,
				segs[i] - dir * d, segs[i] - side * d * 0.7]), c.darkened(0.35))
			draw_circle(segs[i], d * 0.25, Color(0.85, 0.9, 0.4, 0.8))
		if burnt < 0.5:  # чешуйки
			for s in [-1.0, 1.0]:
				var sp: Vector2 = segs[i] + side * s * r * 0.5
				draw_arc(sp, r * 0.32, dir.angle() + PI * 0.55, dir.angle() + PI * 1.45, 5, c.darkened(0.3), 1.2)
		Tex.blob(self, segs[i] + Vector2(-2.5, -3.5) * small, Vector2.ONE * r * 0.55, Color(1, 1, 1, 0.22 * (1.0 - burnt)))

	# Голова
	var dir := Vector2.from_angle(heading)
	if dash_t > 0.0:  # след рывка
		for k in 5:
			var col := Color(0.25, 0.22, 0.3, 0.4 - k * 0.07) if shadow_dash else Color(1, 0.3, 0.2, 0.35 - k * 0.06)
			Tex.blob(self, head_pos - dir * (18.0 + k * 16.0), Vector2.ONE * HEAD_RADIUS * (1.3 - k * 0.18), col)
	if spin_t > 0.0:  # вертушка
		var k := spin_t / 0.35
		draw_arc(head_pos, 120.0 * (1.2 - k * 0.4), anim_t * 20.0, anim_t * 20.0 + PI * 1.4, 24, Color(1, 1, 1, 0.8 * k), 10.0)
		draw_arc(head_pos, 120.0 * (1.2 - k * 0.4), anim_t * 20.0 + PI, anim_t * 20.0 + PI * 2.4, 24, Color(1, 0.9, 0.3, 0.6 * k), 6.0)
	var side := dir.orthogonal()
	var head_r := HEAD_RADIUS * (1.0 + bite_t * 0.8) * small

	# Язык
	if fmod(anim_t, 1.4) < 0.3 and alive:
		var base := head_pos + dir * head_r * 1.2
		var tip := base + dir * 14.0 * small
		draw_line(base, tip, Color(0.85, 0.1, 0.2), 2.5 * small)
		draw_line(tip, tip + dir.rotated(0.5) * 6.0 * small, Color(0.85, 0.1, 0.2), 2.0 * small)
		draw_line(tip, tip + dir.rotated(-0.5) * 6.0 * small, Color(0.85, 0.1, 0.2), 2.0 * small)

	var hc := Color(0.4, 0.86, 0.34).lerp(ash, burnt * 0.9)
	var snout := head_pos + dir * head_r * 0.45
	draw_circle(head_pos, head_r + 2.5, outline)
	draw_circle(snout, head_r * 0.78 + 2.5, outline)
	draw_circle(head_pos, head_r, hc.darkened(0.15))
	draw_circle(snout, head_r * 0.78, hc.darkened(0.15))
	draw_circle(head_pos + Vector2(-1.5, -2) * small, head_r * 0.85, hc)
	draw_circle(snout + Vector2(-1, -1.5) * small, head_r * 0.62, hc)
	Tex.blob(self, head_pos + Vector2(-4, -5) * small, Vector2.ONE * head_r * 0.6, Color(1, 1, 1, 0.3 * (1.0 - burnt)))
	for s in [-1.0, 1.0]:  # ноздри
		draw_circle(snout + dir * head_r * 0.55 + side * s * 3.5 * small, 1.4 * small, outline)
	for s in [-1.0, 1.0]:
		var eye: Vector2 = head_pos + dir * 4.0 * small + side * s * 7.5 * small
		draw_circle(eye, 5.8 * small, outline)
		draw_circle(eye, 5.0 * small, Color(0.98, 0.96, 0.8))
		if alive:
			draw_circle(eye + dir * 1.5 * small, 3.2 * small, Color(0.85, 0.65, 0.1))
			draw_line(eye + dir * 1.5 * small - side * 2.5 * small, eye + dir * 1.5 * small + side * 2.5 * small, Color.BLACK, 1.8 * small)
			draw_circle(eye + Vector2(-1.4, -1.6) * small, 1.2 * small, Color.WHITE)
		else:
			draw_line(eye - Vector2(3, 3) * small, eye + Vector2(3, 3) * small, Color.BLACK, 2.0)
			draw_line(eye - Vector2(3, -3) * small, eye + Vector2(3, -3) * small, Color.BLACK, 2.0)
		var out_a: float = (side * s).angle()
		draw_arc(eye, 6.4 * small, out_a - 1.1, out_a + 1.1, 6, outline, 1.8 * small)  # надбровная чешуя
	if exhausted and alive:  # капли пота
		for k in 2:
			var ph := fmod(anim_t * 1.5 + k * 0.5, 1.0)
			var sp: Vector2 = head_pos - side * (14.0 - k * 28.0) + Vector2(0, -18.0 + ph * 22.0)
			draw_circle(sp, 3.5, Color(0.5, 0.8, 1.0, 1.0 - ph))
	if stun_t > 0.0 and alive:  # оглушение: звёзды и спираль
		for i in 4:
			var a := anim_t * 6.0 + TAU * i / 4.0
			_draw_star(head_pos + Vector2(0, -26) + Vector2(cos(a) * 20.0, sin(a) * 7.0), 5.0, Color(0.6, 0.85, 1.0))
		var pts := PackedVector2Array()
		for k in 18:
			pts.append(head_pos + Vector2.from_angle(anim_t * 8.0 + k * 0.6) * (2.0 + k * 0.7))
		draw_polyline(pts, Color(0.3, 0.5, 1.0, 0.8), 2.0)
	if (shield > 0 or shield_flash > 0.0) and alive:  # щит-пузырь
		var pulse := 1.0 + 0.05 * sin(anim_t * 6.0)
		var a := 0.35 if shield > 0 else 0.0
		a = maxf(a, shield_flash * 0.8)
		Tex.blob(self, head_pos, Vector2.ONE * 34.0 * pulse, Color(0.5, 0.8, 1.0, a * 0.5))
		draw_arc(head_pos, 30.0 * pulse, 0, TAU, 32, Color(0.7, 0.9, 1.0, a + 0.2), 2.5)
		draw_arc(head_pos, 24.0 * pulse, -2.4, -1.6, 8, Color(1, 1, 1, a + 0.3), 2.5)


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2 + TAU * i / 10.0) * rr)
	draw_colored_polygon(pts, col)


func _seg_radius(i: int, n: int) -> float:
	var t := float(i) / float(maxi(n - 1, 1))
	return lerpf(BODY_RADIUS, BODY_RADIUS * 0.45, t * t)
