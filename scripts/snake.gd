extends Node2D
## Змея со свободным движением. Рисуется в мировых координатах (сам узел стоит в (0, 0)).

signal damaged(lives_left: int)
signal died

const Settings = preload("res://scripts/settings.gd")

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
var invuln := 0.0
var slow_timer := 0.0
var stamina := 1.0
var exhausted := false
var sprinting := false
var dash_t := 0.0   # удар с разбега (способность боксёра)
var spin_t := 0.0   # вертушка (способность каратиста)
var knockback := Vector2.ZERO
var use_mouse := false
var alive := true
var anim_t := 0.0
var bite_t := 0.0
## Катсцена: змея ползает сама, без урона.
var autopilot := false
var auto_speed := 90.0
var auto_target := Vector2(640, 360)
var burnt := 0.0  # 0..1 — обугливание


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
	bite_t = maxf(bite_t - delta, 0.0)
	modulate.a = 0.35 if invuln > 0.0 and int(invuln * 12.0) % 2 == 0 else 1.0
	queue_redraw()
	if not alive:
		return
	if autopilot:
		_autopilot(delta)
		return

	# Поворот: клавиши или мышь
	var turn := Input.get_axis("turn_left", "turn_right")
	if turn != 0.0:
		use_mouse = false
		heading += turn * TURN_SPEED * delta
	elif use_mouse:
		var to_mouse := get_global_mouse_position() - head_pos
		if to_mouse.length() > 24.0:
			heading = rotate_toward(heading, to_mouse.angle(), TURN_SPEED * delta)

	# Скорость: спринт тратит стамину; при нуле змея выдыхается и ползёт медленнее
	var speed := BASE_SPEED
	sprinting = Input.is_action_pressed("sprint") and not exhausted and stamina > 0.0
	if sprinting:
		speed = SPRINT_SPEED
		stamina = maxf(stamina - delta * STAMINA_DRAIN, 0.0)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = minf(stamina + delta * STAMINA_REGEN * (0.7 if exhausted else 1.0), 1.0)
		if exhausted and stamina >= EXHAUST_RECOVER:
			exhausted = false
	if exhausted:
		speed *= 0.8
	if slow_timer > 0.0:
		speed *= 0.5
	spin_t = maxf(spin_t - delta, 0.0)
	if dash_t > 0.0:
		dash_t -= delta
		speed = DASH_SPEED

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
	head_pos += Vector2.from_angle(heading) * auto_speed * delta
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
	if stamina < amount:
		return false
	stamina -= amount
	if stamina <= 0.01:
		exhausted = true
	return true


func dash(time: float) -> void:
	dash_t = time
	invuln = maxf(invuln, time + 0.1)


func is_dashing() -> bool:
	return dash_t > 0.0


func grow(amount: int) -> void:
	length += amount
	bite_t = 0.25


func slow(time: float) -> void:
	slow_timer = maxf(slow_timer, time)


func push(force: Vector2) -> void:
	knockback = force
	heading = force.angle()


## Возвращает true, если урон действительно прошёл (не было неуязвимости).
func take_damage(amount := 1) -> bool:
	if invuln > 0.0 or not alive:
		return false
	lives = maxi(lives - amount, 0)
	invuln = INVULN_TIME
	damaged.emit(lives)
	if lives <= 0:
		alive = false
		died.emit()
	return true


func _draw() -> void:
	var segs := get_segments()
	var n := segs.size()
	var slowed := slow_timer > 0.0
	var ash := Color(0.13, 0.1, 0.08)
	# Контур
	for i in range(n - 1, 0, -1):
		draw_circle(segs[i], _seg_radius(i, n) + 2.5, Color(0.08, 0.3, 0.1).lerp(Color.BLACK, burnt))
	# Заливка с полосками
	for i in range(n - 1, 0, -1):
		var c := Color(0.35, 0.8, 0.3) if (i / 3) % 2 == 0 else Color(0.25, 0.65, 0.22)
		if slowed:
			c = c.lerp(Color.WHITE, 0.45)
		draw_circle(segs[i], _seg_radius(i, n), c.lerp(ash, burnt * 0.9))
		draw_circle(segs[i] + Vector2(-2, -3), _seg_radius(i, n) * 0.35, Color(1, 1, 1, 0.18))

	# Голова
	var dir := Vector2.from_angle(heading)
	if dash_t > 0.0:  # след рывка
		for k in 4:
			draw_circle(head_pos - dir * (18.0 + k * 16.0), HEAD_RADIUS * (0.9 - k * 0.18), Color(1, 0.3, 0.2, 0.35 - k * 0.07))
	if spin_t > 0.0:  # вертушка
		var k := spin_t / 0.35
		draw_arc(head_pos, 120.0 * (1.2 - k * 0.4), anim_t * 20.0, anim_t * 20.0 + PI * 1.4, 24, Color(1, 1, 1, 0.8 * k), 10.0)
		draw_arc(head_pos, 120.0 * (1.2 - k * 0.4), anim_t * 20.0 + PI, anim_t * 20.0 + PI * 2.4, 24, Color(1, 0.9, 0.3, 0.6 * k), 6.0)
	var side := dir.orthogonal()
	var head_r := HEAD_RADIUS * (1.0 + bite_t * 0.8)

	# Язык
	if fmod(anim_t, 1.4) < 0.3 and alive:
		var base := head_pos + dir * head_r
		var tip := base + dir * 14.0
		draw_line(base, tip, Color(0.85, 0.1, 0.2), 2.5)
		draw_line(tip, tip + dir.rotated(0.5) * 6.0, Color(0.85, 0.1, 0.2), 2.0)
		draw_line(tip, tip + dir.rotated(-0.5) * 6.0, Color(0.85, 0.1, 0.2), 2.0)

	draw_circle(head_pos, head_r + 2.5, Color(0.08, 0.3, 0.1).lerp(Color.BLACK, burnt))
	draw_circle(head_pos, head_r, Color(0.4, 0.88, 0.35).lerp(ash, burnt * 0.9))
	for s in [-1.0, 1.0]:
		var eye: Vector2 = head_pos + dir * 5.0 + side * s * 7.0
		draw_circle(eye, 5.0, Color.WHITE)
		if alive:
			draw_circle(eye + dir * 1.5, 2.6, Color.BLACK)
		else:
			draw_line(eye - Vector2(3, 3), eye + Vector2(3, 3), Color.BLACK, 2.0)
			draw_line(eye - Vector2(3, -3), eye + Vector2(3, -3), Color.BLACK, 2.0)
	if exhausted and alive:  # капли пота
		for k in 2:
			var ph := fmod(anim_t * 1.5 + k * 0.5, 1.0)
			var sp: Vector2 = head_pos - side * (14.0 - k * 28.0) + Vector2(0, -18.0 + ph * 22.0)
			draw_circle(sp, 3.5, Color(0.5, 0.8, 1.0, 1.0 - ph))


func _seg_radius(i: int, n: int) -> float:
	var t := float(i) / float(maxi(n - 1, 1))
	return lerpf(BODY_RADIUS, BODY_RADIUS * 0.45, t * t)
