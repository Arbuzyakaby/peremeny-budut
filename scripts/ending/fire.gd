extends Node2D
## Пожар на арене: расходится кругом от точки падения спички, выжигает пол, охватывает стенки
## ящика, поднимает искры и дым в комнату. extinguish() — тушение: пламя опадает, валит пар.

const Tex = preload("res://scripts/gfx/tex.gd")
const AREA := Rect2(0, 0, 1280, 720)

var origin := Vector2(640, 360)
var radius := 0.0
var speed := 260.0
var active := false
var strength := 1.0   # 1 — горит в полную силу, 0 — потушен
var t := 0.0
var flames: Array[Vector3] = []  # x, y, размер
var embers: CPUParticles2D
var smoke: CPUParticles2D
var steam: CPUParticles2D


func start(at: Vector2) -> void:
	origin = at
	active = true
	flames.clear()
	for i in 230:
		flames.append(Vector3(randf_range(AREA.position.x + 10, AREA.end.x - 10),
			randf_range(AREA.position.y + 10, AREA.end.y - 10), randf_range(18.0, 40.0)))
	for i in 46:  # языки пламени по бортикам — торчат из ящика
		flames.append(Vector3(randf_range(0, 1280), randf_range(0, 18), randf_range(35.0, 75.0)))
	for i in 24:  # и по боковым стенкам
		var x := randf_range(0, 20) if i % 2 == 0 else randf_range(1260, 1280)
		flames.append(Vector3(x, randf_range(20, 700), randf_range(30.0, 60.0)))
	flames.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	embers = _particles(180, 3.0, Vector2(0, -240), Vector2(4, 12),
		[Color(1, 0.95, 0.5, 1), Color(1, 0.45, 0.1, 0.9), Color(0.6, 0.1, 0.05, 0)], AREA.get_center(), AREA.size / 2.0)
	smoke = _particles(90, 8.0, Vector2(0, -90), Vector2(90, 220),
		[Color(0.25, 0.22, 0.2, 0), Color(0.16, 0.15, 0.14, 0.55), Color(0.1, 0.1, 0.1, 0)], Vector2(640, 250), Vector2(620, 300))
	smoke.z_index = 30
	steam = _particles(80, 4.0, Vector2(0, -120), Vector2(80, 180),
		[Color(0.95, 0.95, 1, 0), Color(0.9, 0.92, 0.95, 0.5), Color(1, 1, 1, 0)], AREA.get_center(), AREA.size / 2.0)
	steam.z_index = 31


func fill_instantly() -> void:
	if not active:
		start(origin)
	radius = 2000.0
	embers.emitting = true
	smoke.emitting = true


## Потушить за time секунд: пламя опадает, вместо дыма валит пар.
func extinguish(time: float) -> void:
	if not active:
		return
	steam.emitting = true
	var tw := create_tween()
	tw.tween_property(self, "strength", 0.0, time).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		embers.emitting = false
		smoke.emitting = false)
	tw.tween_interval(2.0)
	tw.tween_callback(func() -> void: steam.emitting = false)


func covers(p: Vector2) -> bool:
	return active and strength > 0.5 and p.distance_to(origin) < radius - 25.0


## Доля арены, охваченная огнём (для громкости треска).
func coverage() -> float:
	return clampf(radius / 900.0, 0.0, 1.0) * strength


func _particles(amount: int, life: float, gravity_vec: Vector2, size: Vector2, colors: Array,
		center: Vector2, extents: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = center
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = extents
	p.direction = Vector2.UP
	p.spread = 35.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 90.0
	p.gravity = gravity_vec
	p.texture = Tex.soft()
	p.scale_amount_min = size.x / 128.0 * 2.0
	p.scale_amount_max = size.y / 128.0 * 2.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, colors[0])
	ramp.set_color(1, colors[2])
	ramp.add_point(0.35, colors[1])
	p.color_ramp = ramp
	add_child(p)
	return p


func _process(delta: float) -> void:
	if not active:
		return
	t += delta
	speed += delta * 120.0
	radius += speed * delta
	if radius > 350.0 and not embers.emitting and strength > 0.5:
		embers.emitting = true
		smoke.emitting = true
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	# выжженный пол с тлеющими прожилками
	var cell := 20
	for x in range(0, 1280, cell):
		for y in range(0, 720, cell):
			var c := Vector2(x + cell / 2.0, y + cell / 2.0)
			var d := c.distance_to(origin)
			if d < radius:
				var k := clampf((radius - d) / 260.0, 0.0, 0.85)
				draw_rect(Rect2(x, y, cell, cell), Color(0.1, 0.05, 0.02, k))
				var glow := sin(x * 0.13 + y * 0.07 + t * 2.0) * 0.5 + 0.5
				if glow > 0.85 and k > 0.5:
					draw_rect(Rect2(x + 6, y + 6, 8, 8), Color(1, 0.35, 0.05, (glow - 0.85) * 4.0 * (0.3 + 0.7 * strength)))
	if strength <= 0.01:
		return
	# свечение фронта огня
	for f in flames:
		var d := Vector2(f.x, f.y).distance_to(origin)
		if d < radius:
			Tex.blob(self, Vector2(f.x, f.y - f.z * 0.6), Vector2.ONE * f.z * 2.6 * strength, Color(1, 0.45, 0.1, 0.16))
	for i in flames.size():
		var f := flames[i]
		var p := Vector2(f.x, f.y)
		var d := p.distance_to(origin)
		if d >= radius:
			continue
		var grow := clampf((radius - d) / 110.0, 0.0, 1.0)
		var s := f.z * grow * (1.3 if radius - d < 180.0 else 1.0) * strength
		if s < 2.0:
			continue
		_flame(p, s, i * 1.7)


func _flame(p: Vector2, s: float, ph: float) -> void:
	var h := s * 2.3 * (1.0 + 0.22 * sin(t * 10.0 + ph) + 0.1 * sin(t * 23.0 + ph * 2.0))
	var sway := sin(t * 7.0 + ph) * s * 0.3
	for layer in [[1.0, 1.0, Color(0.85, 0.18, 0.04, 0.9)], [0.72, 0.78, Color(1, 0.5, 0.08, 0.95)],
			[0.45, 0.52, Color(1, 0.82, 0.3)], [0.22, 0.28, Color(1, 0.97, 0.75)]]:
		var w: float = s * 0.5 * layer[0]
		var hh: float = h * layer[1]
		var pts := PackedVector2Array()
		for k in 8:
			var a := deg_to_rad(-30.0 + 240.0 * k / 7.0)
			pts.append(p + Vector2(cos(a), sin(a)) * w)
		pts.append(p + Vector2(-w * 0.6 + sway * 0.5, -hh * 0.55))
		pts.append(p + Vector2(sway, -hh))
		pts.append(p + Vector2(w * 0.6 + sway * 0.5, -hh * 0.55))
		draw_colored_polygon(pts, layer[2])
