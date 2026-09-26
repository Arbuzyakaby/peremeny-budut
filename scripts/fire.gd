extends Node2D
## Пожар на арене: расходится кругом от точки падения спички, выжигает пол,
## поднимает искры и дым.

const AREA := Rect2(0, 0, 1280, 720)

var origin := Vector2(640, 360)
var radius := 0.0
var speed := 260.0
var active := false
var t := 0.0
var flames: Array[Vector3] = []  # x, y, размер
var embers: CPUParticles2D
var smoke: CPUParticles2D


func start(at: Vector2) -> void:
	origin = at
	active = true
	flames.clear()
	for i in 230:
		flames.append(Vector3(randf_range(AREA.position.x + 10, AREA.end.x - 10),
			randf_range(AREA.position.y + 10, AREA.end.y - 10), randf_range(18.0, 40.0)))
	for i in 40:  # языки пламени по бортикам — торчат из ящика
		var x := randf_range(0, 1280)
		flames.append(Vector3(x, randf_range(4, 20), randf_range(35.0, 70.0)))
	flames.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	embers = _particles(160, 2.5, Vector2(0, -260), Vector2(4, 11),
		[Color(1, 0.9, 0.4, 1), Color(1, 0.45, 0.1, 0.9), Color(0.6, 0.1, 0.05, 0)])
	smoke = _particles(70, 5.0, Vector2(0, -110), Vector2(60, 140),
		[Color(0.25, 0.22, 0.2, 0), Color(0.18, 0.17, 0.16, 0.5), Color(0.1, 0.1, 0.1, 0)])
	smoke.z_index = 30


func fill_instantly() -> void:
	if not active:
		start(origin)
	radius = 2000.0
	embers.emitting = true
	smoke.emitting = true


func covers(p: Vector2) -> bool:
	return active and p.distance_to(origin) < radius - 25.0


func _particles(amount: int, life: float, gravity_vec: Vector2, size: Vector2, colors: Array) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = AREA.get_center()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = AREA.size / 2.0 - Vector2(20, 20)
	p.direction = Vector2.UP
	p.spread = 35.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 90.0
	p.gravity = gravity_vec
	var tex := GradientTexture2D.new()  # мягкий круглый спрайт
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	p.texture = tex
	p.scale_amount_min = size.x / 64.0 * 2.0
	p.scale_amount_max = size.y / 64.0 * 2.0
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
	if radius > 350.0 and not embers.emitting:
		embers.emitting = true
		smoke.emitting = true
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	# выжженный пол
	var cell := 20
	for x in range(0, 1280, cell):
		for y in range(0, 720, cell):
			var d := Vector2(x + cell / 2.0, y + cell / 2.0).distance_to(origin)
			if d < radius:
				draw_rect(Rect2(x, y, cell, cell), Color(0.12, 0.05, 0.02, clampf((radius - d) / 260.0, 0.0, 0.82)))
	# свечение фронта огня
	for f in flames:
		var d := Vector2(f.x, f.y).distance_to(origin)
		if d < radius:
			draw_circle(Vector2(f.x, f.y), f.z * 2.2, Color(1, 0.45, 0.1, 0.1))
	for i in flames.size():
		var f := flames[i]
		var p := Vector2(f.x, f.y)
		var d := p.distance_to(origin)
		if d >= radius:
			continue
		var grow := clampf((radius - d) / 110.0, 0.0, 1.0)
		var s := f.z * grow * (1.3 if radius - d < 180.0 else 1.0)
		if s < 2.0:
			continue
		_flame(p, s, i * 1.7)


func _flame(p: Vector2, s: float, ph: float) -> void:
	var h := s * 2.3 * (1.0 + 0.22 * sin(t * 10.0 + ph))
	var sway := sin(t * 7.0 + ph) * s * 0.3
	for layer in [[1.0, 1.0, Color(0.9, 0.22, 0.05, 0.92)], [0.68, 0.72, Color(1, 0.55, 0.1)], [0.38, 0.45, Color(1, 0.9, 0.45)]]:
		var w: float = s * 0.5 * layer[0]
		var hh: float = h * layer[1]
		var pts := PackedVector2Array()
		for k in 8:
			var a := deg_to_rad(-30.0 + 240.0 * k / 7.0)
			pts.append(p + Vector2(cos(a), sin(a)) * w)
		pts.append(p + Vector2(sway, -hh))
		draw_colored_polygon(pts, layer[2])
