extends Node2D
## Пожар в ящике. Физика — клеточная симуляция горения (fire_sim.gd): теплопроводность, конвекция,
## излучение пламени, кислород, топливо, плавление, уголь и зола. Картинка — шейдер (FIRE_SHADER):
## языки пламени поднимаются над горящими клетками и окрашены по температуре (кривая абсолютно
## чёрного тела), дерево обугливается с трещинами «крокодиловой кожи» и тлеет, бумага сгорает до
## светлой золы, пластик плавится и стекает блестящей лужей, металл раскаляется докрасна и остывает,
## над огнём дрожит марево. После тушения остаются уголь и зола — навсегда.
## Искры, дым и пар — лёгкие вторичные частицы. API прежний: start / fill_instantly / extinguish /
## covers / coverage и поля origin, radius, strength, t, active.

const Tex = preload("res://scripts/gfx/tex.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Platform = preload("res://scripts/core/platform.gd")
const FireSim = preload("res://scripts/ending/fire_sim.gd")
const AREA := Rect2(0, 0, 1280, 720)
const SIM_RATE := 12.0

const FIRE_SHADER := """
shader_type canvas_item;
uniform sampler2D data_tex : filter_linear;      // R — температура, G — уголь, B — зола, A — расплав
uniform sampler2D info_tex : filter_linear;      // R — материал ×32 (читается texelFetch), G — пена, B — копоть
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 cells = vec2(96.0, 54.0);
uniform float max_t = 1400.0;
uniform bool haze = true;
%s
// цвет раскалённого тела по температуре в °C (приближение кривой абсолютно чёрного тела):
// тёмно-красный → оранжевый → жёлтый → бело-жёлтый; к 1350 °C (почти max_t) — уже бело-жёлтый
vec3 bb_hue(float t) {
	float k = clamp((t - 450.0) / 900.0, 0.0, 1.0);
	vec3 c = mix(vec3(0.45, 0.02, 0.0), vec3(1.0, 0.3, 0.02), smoothstep(0.0, 0.3, k));
	c = mix(c, vec3(1.0, 0.72, 0.22), smoothstep(0.3, 0.65, k));
	return mix(c, vec3(1.0, 0.95, 0.82), smoothstep(0.65, 1.0, k));
}
vec3 blackbody(float t) {  // оттенок × яркость свечения
	return bb_hue(t) * (0.5 + 1.1 * clamp((t - 450.0) / 900.0, 0.0, 1.0));
}
void fragment() {
	vec2 px = UV * vec2(1280.0, 720.0);
	vec4 d = texture(data_tex, UV);
	float temp = d.r * max_t;
	float burnt = d.g;
	float ash = d.b;
	float melt = d.a;
	ivec2 cell_i = clamp(ivec2(UV * cells), ivec2(0), ivec2(cells) - 1);
	float mat = floor(texelFetch(info_tex, cell_i, 0).r * 255.0 / 32.0 + 0.5);
	float foam = texture(info_tex, UV).g;
	float n = fbm(px * 0.03);
	float n2 = fbm(px * 0.11 + 7.0);
	vec4 col = vec4(0.0);
	float soot = texture(info_tex, UV).b;
	// уголь: неровный фронт обугливания, почти чёрный и непрозрачный — ящик после огня выглядит сломанным
	float char_a = smoothstep(0.04, 0.45, burnt + (n - 0.5) * 0.4);
	vec3 charc = vec3(0.045, 0.034, 0.026) * (0.6 + 0.6 * n2);
	// трещины корки: у дерева — «крокодиловая кожа» вдоль волокон, у масляной плёнки — мелкая сетка
	vec2 q = mat == 1.0 ? px * vec2(0.06, 0.12) + n * 3.0 : px * vec2(0.09, 0.09) + n * 4.0;
	float cr = min(abs(fract(q.x + vnoise(q * 0.7) * 0.8) - 0.5), abs(fract(q.y * 0.6 + vnoise(q * 0.5) * 0.6) - 0.5));
	charc *= 0.45 + 0.7 * smoothstep(0.02, 0.12, cr);
	// копоть: закопчённое, но не сгоревшее (рядом с огнём, металл, скорлупа) — тёмный налёт
	col = vec4(charc, max(char_a * 0.97, smoothstep(0.2, 1.0, soot) * 0.5));
	// зола: тёмно-серая с хлопьями светлее — контрастна и к углю, и к полу; у бумаги хлопья светлее
	float ash_a = smoothstep(0.08, 0.7, ash + (n2 - 0.5) * 0.35);
	float flake = smoothstep(0.5, 0.72, n2);
	vec3 ashc = mix(vec3(0.17, 0.16, 0.15), vec3(0.46, 0.44, 0.41), flake);          // дерево, ткань
	if (mat == 2.0) ashc = mix(vec3(0.26, 0.25, 0.24), vec3(0.7, 0.68, 0.64), flake); // бумага
	if (mat == 5.0 || mat == 3.0) {                                                  // масло и пластик — сажа
		ashc = mix(vec3(0.05, 0.045, 0.04), vec3(0.24, 0.22, 0.2), smoothstep(0.6, 0.8, n2));
	}
	col.rgb = mix(col.rgb, ashc, ash_a * 0.9);
	col.a = max(col.a, ash_a * 0.95);
	// тление: раскалённый уголь светится в трещинах
	float glow = smoothstep(420.0, 850.0, temp) * char_a;
	float embers = glow * (0.35 + 0.65 * smoothstep(0.5, 0.78, n2 + 0.18 * sin(TIME * 2.3 + n * 11.0)));
	col.rgb += blackbody(temp) * embers;
	col.a = max(col.a, embers * 0.9);
	// металл не горит: его накал и окалину рисуют сами обломки (fire.gd::_draw_debris) — по их форме
	if (mat == 4.0 || mat == 7.0) {
		col.a *= 0.3;
	}
	// расплавленный пластик: тёмная глянцевая лужа с бликом и пузырями
	if (melt > 0.05) {
		float m = smoothstep(0.08, 0.5, melt + (n - 0.5) * 0.3);
		vec3 pc = vec3(0.1, 0.08, 0.1) + vec3(0.25, 0.22, 0.26) * pow(max(0.0, sin(px.x * 0.05 + px.y * 0.02 + n * 6.0)), 18.0);
		pc += blackbody(temp) * smoothstep(500.0, 900.0, temp) * 0.6;
		float bubble = smoothstep(0.93, 0.97, vnoise(px * 0.25 + vec2(0.0, TIME * 0.5))) * smoothstep(300.0, 500.0, temp);
		pc += vec3(0.3) * bubble;
		col = mix(col, vec4(pc, 0.95), m);
	}
	// пламя: над каждой горячей клеткой поднимается язык (тем ниже и тусклее, чем дальше от клетки);
	// форму режет быстрый вытянутый вверх шум — языки, просветы, срывающиеся «лоскуты»
	float flame = 0.0;
	float ft = 0.0;
	vec2 cell = 1.0 / cells;
	for (int k = 0; k < 8; k++) {
		float fk = float(k);
		vec2 off = vec2((vnoise(vec2(px.y * 0.025 - TIME * 2.4, fk * 1.7)) - 0.5) * cell.x * 1.4, cell.y * fk * 0.65);
		float tk = texture(data_tex, UV + off).r * max_t;
		float heat = smoothstep(360.0, 950.0, tk) * (1.0 - fk / 8.5);
		if (heat > flame) { flame = heat; ft = tk; }
	}
	float rise = TIME * 3.4;
	float n1 = fbm(vec2(px.x * 0.07, px.y * 0.019 + rise));
	float n3 = vnoise(vec2(px.x * 0.16, px.y * 0.05 + rise * 2.3));
	float shape = flame * (0.15 + 1.0 * n1 + 0.45 * n3);
	float tongue = smoothstep(0.42, 0.85, shape);
	vec3 fc = mix(vec3(0.5, 0.05, 0.02), vec3(1.0, 0.42, 0.05), smoothstep(0.48, 0.82, shape));
	fc = mix(fc, vec3(1.0, 0.78, 0.3), smoothstep(0.82, 1.0, shape));
	fc = mix(fc, vec3(1.0, 0.95, 0.8), smoothstep(1.02, 1.25, shape));
	// пик: у самых горячих клеток сердцевина языка уходит в бело-жёлтый (как blackbody при max_t)
	fc = mix(fc, bb_hue(ft), smoothstep(1000.0, 1300.0, ft) * smoothstep(0.7, 1.0, shape));
	fc *= 0.85 + 0.35 * smoothstep(700.0, 1100.0, ft);
	col.rgb = mix(col.rgb, fc, tongue * 0.9);
	col.a = max(col.a, tongue * 0.85);
	// пена огнетушителя: белые пузыри
	if (foam > 0.02) {
		float bub = fbm(px * 0.06 + vec2(0.0, TIME * 0.2));
		float b = smoothstep(0.2, 0.5, foam * 0.9 + (bub - 0.5) * 0.6);
		vec3 fcol = vec3(0.88, 0.91, 0.95) * (0.82 + 0.25 * bub) + 0.08 * smoothstep(0.6, 0.8, fbm(px * 0.12));
		col = mix(col, vec4(fcol, 0.9), b);
	}
	// марево над горячим: смещаем то, что под огнём
	float haze_k = haze ? smoothstep(150.0, 700.0, temp) : 0.0;
	if (haze_k > 0.01) {
		vec2 wob = vec2(vnoise(px * 0.05 + vec2(0.0, TIME * 4.0)) - 0.5, vnoise(px * 0.05 + vec2(9.0, TIME * 3.3)) - 0.5);
		vec3 behind = texture(screen_tex, SCREEN_UV + wob * 0.006 * haze_k).rgb;
		col.rgb = mix(behind, col.rgb, col.a);
		col.a = max(col.a, haze_k);
	}
	COLOR = col;
}
"""

## Обломки битвы на дне ящика: разные материалы горят по-разному. [вид, позиция, размер, поворот]
## Это «эталонная» раскладка: в каждом ране обломки меняются местами и чуть сдвигаются от сида
## (build_layout), а под каждой половинкой капсулы лежит затравка — обрывок протокола (вид "scrap",
## бумага): вспыхивает первым и гарантированно доводит пластик до плавления.
const DEBRIS := [
	["paper", Vector2(220, 170), Vector2(70, 50), 0.3], ["paper", Vector2(1010, 560), Vector2(64, 46), -0.5],
	["paper", Vector2(760, 150), Vector2(56, 40), 0.9],
	["plastic", Vector2(380, 520), Vector2(22, 0), 0.0], ["plastic", Vector2(940, 260), Vector2(20, 0), 0.0],
	["plastic", Vector2(620, 610), Vector2(18, 0), 0.0], ["plastic", Vector2(1120, 380), Vector2(20, 0), 0.0],
	["metal", Vector2(470, 300), Vector2(90, 0), 0.6], ["metal", Vector2(860, 470), Vector2(80, 0), -0.9],
	["metal", Vector2(180, 430), Vector2(70, 0), 2.1],
	["fabric", Vector2(560, 210), Vector2(26, 0), 0.0], ["fabric", Vector2(1080, 170), Vector2(22, 0), 0.0],
	["fabric", Vector2(300, 620), Vector2(24, 0), 0.0],
	["shell", Vector2(700, 420), Vector2(26, 0), 0.4], ["shell", Vector2(420, 120), Vector2(22, 0), 2.0],
]
const DEBRIS_JITTER := 20.0            # сдвиг обломков от сида (после перемешивания мест), px
const SCRAP_SIZE := Vector2(34, 18)    # затравка под пластиком
const SCRAP_GAP := 12.0                # зазор между капсулой и затравкой, px
const MAT_OF := {"paper": FireSim.Mat.PAPER, "scrap": FireSim.Mat.PAPER, "plastic": FireSim.Mat.PLASTIC,
	"metal": FireSim.Mat.METAL, "fabric": FireSim.Mat.FABRIC, "shell": FireSim.Mat.SHELL}

var origin := Vector2(640, 360)
var radius := 0.0
var active := false
var strength := 1.0   # 1 — горит в полную силу, 0 — потушен
var t := 0.0
var seed_value := 0   # сид раскладки и вариаций (ending.gd задаёт случайный до add_child)
var layout: Array = []  # обломки этого рана (как DEBRIS, но сдвинутые, плюс затравки)
## Чистый ящик без обломков битвы — игровой пожар «Контакта» (v10.0): горит масло и бортики.
var plain := false
var sim: FireSim
var rect: ColorRect
var data_img: Image
var info_img: Image
var data_tex: ImageTexture
var info_tex: ImageTexture
var _data := PackedByteArray()
var _info := PackedByteArray()
var _acc := 0.0
var _foam_t := -1.0
var _foam_time := 2.4
var debris: Node2D
var embers: CPUParticles2D
var smoke: CPUParticles2D
var steam: CPUParticles2D


func _ready() -> void:
	if sim != null:
		return
	var low := Platform.is_mobile()
	sim = FireSim.new(64 if low else 96, 36 if low else 54, AREA)
	if plain:
		_fill_layout(sim, [])
		sim.vary(seed_value)
	else:
		layout = build_layout(sim, seed_value)
	debris = Node2D.new()  # обломки лежат под змеёй, огонь — над ней
	debris.z_index = -5
	debris.draw.connect(_draw_debris)
	add_child(debris)


## Карта материалов: пол — масляная плёнка на чугунной сковороде, бортики — дерево, обломки битвы
## (от сида: места обломков перемешаны между собой и чуть сдвинуты, повороты свои) и затравки под
## пластиком; затем sim.vary(seed). Возвращает раскладку обломков. Статическая — тесты строят ящик без узла.
static func build_layout(s_sim: FireSim, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var spots: Array[Vector2] = []
	for d: Array in DEBRIS:
		spots.append(d[1])
	for i in range(spots.size() - 1, 0, -1):  # перемешивание Фишера–Йетса от сида (Array.shuffle — от общего ГСЧ)
		var j := rng.randi_range(0, i)
		var tmp := spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	var out: Array = []
	var scraps: Array = []
	for k in DEBRIS.size():
		var d: Array = DEBRIS[k]
		var p: Vector2 = spots[k] + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * DEBRIS_JITTER
		p = p.clamp(Vector2(70, 70), Vector2(1210, 620 if d[0] == "plastic" else 650))
		out.append([d[0], p, d[2], float(d[3]) + rng.randf_range(-0.4, 0.4)])
		if d[0] == "plastic":  # затравка чуть ниже капсулы: пламя идёт вверх — прямо на пластик
			var sp := p + Vector2(rng.randf_range(-8, 8), d[2].x + SCRAP_GAP + SCRAP_SIZE.y / 2.0)
			scraps.append(["scrap", sp, SCRAP_SIZE, rng.randf_range(-0.3, 0.3)])
	out.append_array(scraps)  # затравки — последними, чтобы их не перекрыл соседний обломок
	_fill_layout(s_sim, out)
	s_sim.vary(seed_value)
	return out


static func _fill_layout(sim: FireSim, items: Array) -> void:
	sim.fill_rect(AREA, FireSim.Mat.OIL)
	for r in [Rect2(0, 0, 1280, 24), Rect2(0, 696, 1280, 24), Rect2(0, 0, 24, 720), Rect2(1256, 0, 24, 720)]:
		sim.fill_rect(r, FireSim.Mat.WOOD)
	for d: Array in items:
		var p: Vector2 = d[1]
		var s: Vector2 = d[2]
		match d[0]:
			"paper", "scrap":
				sim.fill_rect(Rect2(p - s / 2.0, s), FireSim.Mat.PAPER)
			"plastic":
				sim.fill_circle(p, s.x, FireSim.Mat.PLASTIC)
			"metal":
				var dir := Vector2.from_angle(d[3]) * s.x / 2.0
				sim.fill_line(p - dir, p + dir, 10.0, FireSim.Mat.METAL)
			"fabric":
				sim.fill_circle(p, s.x, FireSim.Mat.FABRIC)
			"shell":
				sim.fill_circle(p, s.x * 0.7, FireSim.Mat.SHELL)


func start(at: Vector2) -> void:
	if sim == null:
		_ready()
	origin = at
	active = true
	sim.ignite(at, 42.0, 950.0)
	_make_render()
	var pm := Settings.particle_mult()
	embers = _particles(int(140 * pm), 2.6, Vector2(0, -240), Vector2(4, 11),
		[Color(1, 0.95, 0.5, 1), Color(1, 0.45, 0.1, 0.9), Color(0.6, 0.1, 0.05, 0)], AREA.get_center(), AREA.size / 2.0)
	smoke = _particles(int(70 * pm), 7.0, Vector2(0, -80), Vector2(90, 220),
		[Color(0.25, 0.22, 0.2, 0), Color(0.14, 0.13, 0.12, 0.5), Color(0.1, 0.1, 0.1, 0)], Vector2(640, 250), Vector2(620, 300))
	smoke.z_index = 30
	steam = _particles(int(80 * pm), 4.0, Vector2(0, -120), Vector2(80, 180),
		[Color(0.95, 0.95, 1, 0), Color(0.9, 0.92, 0.95, 0.5), Color(1, 1, 1, 0)], AREA.get_center(), AREA.size / 2.0)
	steam.z_index = 31
	_upload()


func _make_render() -> void:
	if rect:
		return
	sim.pack(_data, _info)
	data_img = Image.create_from_data(sim.w, sim.h, false, Image.FORMAT_RGBA8, _data)
	info_img = Image.create_from_data(sim.w, sim.h, false, Image.FORMAT_RGB8, _info)
	data_tex = ImageTexture.create_from_image(data_img)
	info_tex = ImageTexture.create_from_image(info_img)
	var sh := Shader.new()
	sh.code = FIRE_SHADER % Tex.NOISE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("data_tex", data_tex)
	m.set_shader_parameter("info_tex", info_tex)
	m.set_shader_parameter("cells", Vector2(sim.w, sim.h))
	m.set_shader_parameter("max_t", FireSim.MAX_T)
	m.set_shader_parameter("haze", not Platform.is_mobile())
	rect = ColorRect.new()
	rect.size = AREA.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = m
	add_child(rect)


func _upload() -> void:
	if rect == null:
		return
	sim.pack(_data, _info)
	data_img.set_data(sim.w, sim.h, false, Image.FORMAT_RGBA8, _data)
	info_img.set_data(sim.w, sim.h, false, Image.FORMAT_RGB8, _info)
	data_tex.update(data_img)
	info_tex.update(info_img)


## Пропуск финала: пожар мгновенно догорел, осталась зола.
func fill_instantly() -> void:
	if not active:
		start(origin)
	sim.burn_out()
	radius = 2000.0
	_upload()


## Потушить за time секунд: пена наступает от учёного (справа), огонь опадает, валит пар.
func extinguish(time: float) -> void:
	if not active:
		return
	_foam_t = 0.0
	_foam_time = time
	steam.emitting = true
	var tw := create_tween()
	tw.tween_property(self, "strength", 0.0, time).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		embers.emitting = false
		smoke.emitting = false)
	tw.tween_interval(2.0)
	tw.tween_callback(func() -> void: steam.emitting = false)


## Эта точка в огне (змея сгорает, если голова здесь).
func covers(p: Vector2) -> bool:
	return active and strength > 0.5 and sim.temp_at(p) > 380.0


## Доля ящика, охваченная огнём (для громкости треска).
func coverage() -> float:
	if not active:
		return 0.0
	return clampf(sim.burning_fraction() * 2.2, 0.0, 1.0) * strength


## Сколько клеток сгорело — строка «Сожжено клеток» в протоколе (титрах).
func burnt_cells() -> int:
	return sim.burnt_cells() if sim else 0


## Сколько осталось золы и угля (для тестов и яйца «в пепле»).
func ash_amount() -> float:
	var s := 0.0
	for a in sim.ash:
		s += a
	return s / sim.ash.size()


func _particles(amount: int, life: float, gravity_vec: Vector2, size: Vector2, colors: Array,
		center: Vector2, extents: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = center
	p.amount = maxi(amount, 4)
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
	if _foam_t >= 0.0 and _foam_t <= _foam_time + 0.6:  # пена наступает справа налево и держится за фронтом
		_foam_t += delta
		var k := clampf(_foam_t / _foam_time, 0.0, 1.0)
		var front := lerpf(1400.0, -200.0, k)
		sim.add_foam(Vector2(front, 360.0 + sin(t * 5.0) * 200.0), 260.0, delta * 3.0)
		sim.add_foam_rect(Rect2(front + 120.0, -20.0, 1400.0, 760.0), delta * 1.6)
	_acc += delta
	if _acc >= 1.0 / SIM_RATE:
		sim.step(minf(_acc, 0.25))
		_acc = 0.0
		_update_radius()
		_upload()
		debris.queue_redraw()
	var hot := coverage()
	if hot > 0.25 and strength > 0.5 and not embers.emitting:
		embers.emitting = true
		smoke.emitting = true


## Радиус охвата от точки поджига (для старого кода и отладки).
func _update_radius() -> void:
	var r := 0.0
	var cs := sim.cell_size()
	for i in sim.w * sim.h:
		if sim.charred[i] > 0.05 or sim.temp[i] > 380.0:
			r = maxf(r, sim.cell_center(i).distance_to(origin) + cs.x)
	radius = maxf(radius, r)


## Цвет раскалённого металла по температуре — как blackbody() в шейдере.
static func glow_color(temp: float) -> Color:
	var k := clampf((temp - 450.0) / 900.0, 0.0, 1.0)
	var c := Color(0.45, 0.02, 0.0).lerp(Color(1.0, 0.3, 0.02), smoothstep(0.0, 0.3, k))
	c = c.lerp(Color(1.0, 0.72, 0.22), smoothstep(0.3, 0.65, k))
	return c.lerp(Color(1.0, 0.95, 0.82), smoothstep(0.65, 1.0, k))


## Обломки битвы на дне ящика. Каждый ведёт себя по своему материалу: бумага желтеет, сворачивается
## и исчезает, пластик оседает и растекается, клок плюша сгорает, металл краснеет и светится,
## скорлупа коптится. Копоть и окалина (sim.scorch) после огня остаются. Уголь, золу и лужи
## расплава поверх рисует шейдер.
func _draw_debris() -> void:
	var ci := debris
	for d: Array in layout:
		var p: Vector2 = d[1]
		var s: Vector2 = d[2]
		var rot: float = d[3]
		var i := sim.index_at(p)
		var temp := sim.temp[i]
		var burnt := sim.charred[i]
		var scorch := sim.scorch[i]
		match d[0]:
			"paper", "scrap":  # листок протокола (или его обрывок): желтеет от жара, сворачивается и сгорает
				if burnt > 0.95:
					continue
				var curl := 1.0 - burnt * 0.7
				var tan := clampf((temp - 120.0) / 200.0, 0.0, 1.0)
				ci.draw_set_transform(p, rot + burnt * 0.6, Vector2(curl, curl * (1.0 - burnt * 0.3)))
				ci.draw_rect(Rect2(-s / 2.0 + Vector2(2, 3), s), Color(0, 0, 0, 0.25 * curl))
				ci.draw_rect(Rect2(-s / 2.0, s), Color(0.95, 0.91, 0.8).lerp(Color(0.62, 0.42, 0.18), tan))
				for k in 4:
					var y := -s.y / 2.0 + 10.0 + k * 9.0
					if y > s.y / 2.0 - 4.0:
						break
					ci.draw_line(Vector2(-s.x / 2.0 + 6, y), Vector2(s.x / 2.0 - 6, y), Color(0.4, 0.45, 0.6, 0.5 * curl), 1.0)
				if burnt > 0.05:  # тлеющий край
					ci.draw_rect(Rect2(-s / 2.0, s), glow_color(maxf(temp, 700.0)), false, 2.5)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"plastic":  # половинка капсулы: оседает и растекается при плавлении
				var m := sim.melt[i]
				var sq := Vector2(1.0 + m * 0.8, 1.0 - m * 0.6)
				ci.draw_set_transform(p + Vector2(0, m * 6.0), 0.0, sq)
				ci.draw_circle(Vector2(2, 3), s.x, Color(0, 0, 0, 0.25))
				ci.draw_circle(Vector2.ZERO, s.x, Color(0.9, 0.22, 0.25).lerp(Color(0.25, 0.08, 0.1), burnt))
				ci.draw_circle(Vector2(-s.x * 0.3, -s.x * 0.3), s.x * 0.35, Color(1, 1, 1, 0.4 * (1.0 - m)))
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"metal":  # обломок вилки: окалина и накал по температуре
				var dir := Vector2.from_angle(rot) * s.x / 2.0
				var hot := smoothstep(480.0, 760.0, temp)
				var scale_k := maxf(clampf((temp - 200.0) / 300.0, 0.0, 1.0), scorch)  # окалина остаётся
				var base := Color(0.72, 0.5, 0.32).lerp(Color(0.2, 0.17, 0.17), scale_k)
				ci.draw_line(p - dir + Vector2(2, 3), p + dir + Vector2(2, 3), Color(0, 0, 0, 0.3), 9.0)
				ci.draw_line(p - dir, p + dir, Color(0.3, 0.26, 0.25).lerp(glow_color(temp), hot * 0.8), 8.0)
				ci.draw_line(p - dir, p + dir, base.lerp(glow_color(temp), hot), 4.0)
				if hot > 0.1:
					ci.draw_line(p - dir, p + dir, Color(glow_color(temp), 0.25 * hot), 16.0)
			"fabric":  # клок плюша с набивкой — сгорает быстро
				if burnt > 0.9:
					continue
				var k2 := 1.0 - burnt
				ci.draw_circle(p, s.x * k2, Color(0.66, 0.44, 0.24).lerp(Color(0.1, 0.07, 0.05), burnt))
				for k in 5:
					ci.draw_circle(p + Vector2.from_angle(k * 1.3) * s.x * 0.5 * k2, s.x * 0.35 * k2,
						Color(0.96, 0.94, 0.9).lerp(Color(0.2, 0.18, 0.16), burnt))
			"shell":  # скорлупа — не горит, только коптится
				var soot := clampf(maxf((temp - 150.0) / 500.0, scorch), 0.0, 0.85)  # копоть не отмывается
				ci.draw_set_transform(p, rot, Vector2.ONE)
				ci.draw_colored_polygon(PackedVector2Array([Vector2(-s.x, 0), Vector2(-s.x * 0.4, -s.x * 0.7),
					Vector2(s.x * 0.6, -s.x * 0.5), Vector2(s.x, 0.2 * s.x), Vector2(0, s.x * 0.4)]),
					Color(0.98, 0.96, 0.9).lerp(Color(0.18, 0.16, 0.14), soot))
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
