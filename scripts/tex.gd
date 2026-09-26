extends RefCounted
## Процедурные текстуры: шейдеры пола для каждого этапа, шейдер «материала» (мех, ржавчина,
## белок, пластик) для объектов, нарисованных через draw_*, и мягкие круглые спрайты для теней,
## свечения и частиц. Всё кэшируется в static-переменных и живёт между перезагрузками сцены.

enum Floor { WOOD, TRAY, TILES, PAN }
enum Mat { FUR, RUST, EGG, PLASTIC, CLOTH }

const NOISE := """
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * vnoise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
"""

const FLOOR_SHADER := """
shader_type canvas_item;
uniform int kind = 0;
%s
void fragment() {
	vec2 px = UV * vec2(1280.0, 720.0);
	vec3 c;
	if (kind == 0) {
		// фанера: доски с волокнами и сучками
		float pid = floor(px.y / 120.0);
		vec2 q = px + vec2(hash(vec2(pid, 1.0)) * 900.0, 0.0);
		float g = fbm(vec2(q.x * 0.004, q.y * 0.045));
		float grain = sin(q.y * 0.09 + g * 16.0 + fbm(q * 0.012) * 4.0) * 0.5 + 0.5;
		c = mix(vec3(0.87, 0.72, 0.52), vec3(0.72, 0.53, 0.33), grain * 0.55 + g * 0.35);
		float kx = floor(q.x / 520.0);
		vec2 kc = vec2((kx + 0.2 + 0.6 * hash(vec2(pid, kx))) * 520.0, pid * 120.0 + 30.0 + 60.0 * hash(vec2(kx, pid + 7.0)));
		vec2 knot = (q - kc) * vec2(0.55, 1.0);
		float kd = length(knot) + fbm(q * 0.05) * 6.0;
		float has_knot = step(0.72, hash(vec2(pid * 3.1, kx * 1.7)));
		c = mix(c, vec3(0.5, 0.33, 0.18), smoothstep(20.0, 5.0, kd) * has_knot);
		c = mix(c, c * 0.85, smoothstep(34.0, 20.0, kd) * has_knot * 0.6);
		c *= 0.92 + 0.12 * hash(vec2(pid, 3.0));
		float seam = mod(px.y, 120.0);
		c *= 1.0 - 0.3 * smoothstep(3.0, 0.0, seam) - 0.1 * smoothstep(6.0, 3.0, 120.0 - seam);
		c += (vnoise(px * 0.9) - 0.5) * 0.035;
	} else if (kind == 1) {
		// поцарапанный стальной поднос с пятнами ржавчины
		float brush = fbm(vec2(px.x * 0.002, px.y * 0.8));
		c = vec3(0.6, 0.63, 0.66) + (brush - 0.5) * 0.14;
		// редкие прямые царапины
		float sc = 0.0;
		for (int k = 0; k < 3; k++) {
			float fk = float(k);
			vec2 dir = normalize(vec2(cos(fk * 2.1 + 0.4), sin(fk * 2.1 + 0.4)));
			float lane = dot(px, vec2(-dir.y, dir.x)) / 9.0;
			float id = floor(lane);
			float along = dot(px, dir);
			float on = step(0.93, hash(vec2(id, fk))) * step(0.5, vnoise(vec2(along * 0.01, id + fk * 13.0)));
			sc += on * smoothstep(0.5, 0.0, abs(fract(lane) - 0.5)) ;
		}
		c += sc * 0.07;
		c = mix(c, vec3(0.42, 0.46, 0.52), 0.25);
		float rust = smoothstep(0.6, 0.78, fbm(px * 0.006 + 7.0));
		c = mix(c, mix(vec3(0.55, 0.28, 0.12), vec3(0.4, 0.2, 0.1), vnoise(px * 0.2)), rust * 0.6);
		c *= 0.88 + 0.18 * (1.0 - UV.y);
		c += 0.06 * smoothstep(0.35, 0.0, abs(UV.x - UV.y * 0.6 - 0.2));
	} else if (kind == 2) {
		// аптечная кафельная плитка
		vec2 t = mod(px, 80.0);
		vec2 id = floor(px / 80.0);
		float grout = min(min(t.x, 80.0 - t.x), min(t.y, 80.0 - t.y));
		vec3 tile = mix(vec3(0.9, 0.95, 0.97), vec3(0.82, 0.92, 0.95), hash(id));
		if (mod(id.x + id.y, 2.0) < 1.0) tile = mix(tile, vec3(0.74, 0.87, 0.9), 0.55);
		tile += (fbm(px * 0.05 + id) - 0.5) * 0.05;
		tile += 0.08 * smoothstep(40.0, 0.0, t.x + t.y - 20.0);
		tile -= 0.05 * smoothstep(60.0, 80.0, max(t.x, t.y));
		c = mix(vec3(0.55, 0.62, 0.65), tile, smoothstep(1.5, 3.5, grout));
		c = mix(c, vec3(0.62, 0.7, 0.72), smoothstep(0.62, 0.8, fbm(px * 0.004 + 2.0)) * 0.35);
	} else {
		// чугунная сковорода: концентрические следы, масляные разводы, блик
		vec2 cen = vec2(640.0, 360.0);
		vec2 dv = px - cen;
		float d = length(dv);
		float n = fbm(px * 0.06);
		c = vec3(0.17, 0.16, 0.16) + (n - 0.5) * 0.1;
		c += 0.025 * sin(d * 0.21 + n * 3.0);
		float oil = smoothstep(0.55, 0.78, fbm(px * 0.004 + 3.0));
		c = mix(c, vec3(0.62, 0.48, 0.16), oil * 0.3);
		c += 0.12 * exp(-pow((d - 330.0) / 70.0, 2.0)) * pow(0.5 + 0.5 * sin(atan(dv.y, dv.x) * 1.0 + 2.2), 3.0);
		c += 0.06 * smoothstep(0.7, 0.9, vnoise(px * 0.08)) * oil;
	}
	vec2 v = UV - 0.5;
	c *= 1.0 - dot(v, v) * 0.6;
	COLOR = vec4(c, 1.0);
}
"""

const MAT_SHADER := """
shader_type canvas_item;
uniform int mode = 0;
uniform float seed = 0.0;
varying vec2 lp;
%s
void vertex() { lp = VERTEX + vec2(seed * 37.0, seed * 91.0); }
void fragment() {
	vec4 c = COLOR;
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = mx - mn;
	if (mode == 0) {
		// мех: вытянутые ворсинки + крупная неровность плюша
		float strands = vnoise(lp * vec2(0.8, 0.25)) * 0.55 + vnoise(lp * vec2(0.3, 1.0) + 4.0) * 0.45;
		float lumps = fbm(lp * 0.12);
		c.rgb *= 0.86 + 0.2 * strands + 0.1 * (lumps - 0.5);
	} else if (mode == 1) {
		// ржавый металл: пятна ржавчины на серых частях и царапины
		float r = smoothstep(0.45, 0.7, fbm(lp * 0.09));
		float pits = smoothstep(0.75, 0.9, vnoise(lp * 0.8));
		vec3 rust = mix(vec3(0.62, 0.3, 0.12), vec3(0.38, 0.17, 0.07), vnoise(lp * 0.5));
		float grey = 1.0 - smoothstep(0.08, 0.25, sat);
		c.rgb = mix(c.rgb, rust, (r * 0.85 + pits * 0.5) * grey);
		c.rgb += grey * pow(abs(sin(lp.x * 0.9 + fbm(lp * 0.2) * 5.0)), 40.0) * 0.12 * (1.0 - r);
	} else if (mode == 2) {
		// белок и желток: мягкая неоднородность, пузырьки
		float n = fbm(lp * 0.035);
		c.rgb *= 0.95 + 0.08 * n;
		c.rgb += 0.05 * smoothstep(0.78, 0.9, vnoise(lp * 0.3)) * (1.0 - sat);
	} else if (mode == 3) {
		// глянцевый пластик / лак: мелкая крапинка
		c.rgb *= 0.97 + 0.06 * vnoise(lp * 1.3);
	} else {
		// ткань: переплетение нитей
		float weave = sin(lp.x * 2.2) * sin(lp.y * 2.2);
		c.rgb *= 0.95 + 0.05 * weave + 0.04 * vnoise(lp * 0.4);
	}
	COLOR = c;
}
"""

static var _floor_shader: Shader
static var _mat_shader: Shader
static var _floors: Dictionary = {}
static var _soft: GradientTexture2D
static var _ring: GradientTexture2D


static func floor_material(kind: int) -> ShaderMaterial:
	if not _floors.has(kind):
		if _floor_shader == null:
			_floor_shader = Shader.new()
			_floor_shader.code = FLOOR_SHADER % NOISE
		var m := ShaderMaterial.new()
		m.shader = _floor_shader
		m.set_shader_parameter("kind", kind)
		_floors[kind] = m
	return _floors[kind]


## Материал для узла, рисующего себя через draw_*. seed разводит узор у одинаковых объектов.
static func material(mode: int, seed := 0.0) -> ShaderMaterial:
	if _mat_shader == null:
		_mat_shader = Shader.new()
		_mat_shader.code = MAT_SHADER % NOISE
	var m := ShaderMaterial.new()
	m.shader = _mat_shader
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("seed", seed)
	return m


## Мягкий круг: белый в центре, прозрачный по краю — тени, свечение, дым, частицы.
static func soft() -> GradientTexture2D:
	if _soft == null:
		_soft = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)], [0.0, 0.45, 1.0])
	return _soft


## Мягкое кольцо — для ударных волн и ореолов.
static func ring() -> GradientTexture2D:
	if _ring == null:
		_ring = _radial([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.7, 0.86, 1.0])
	return _ring


static func _radial(colors: Array, offsets: Array) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	tex.gradient = g
	return tex


## Нарисовать мягкое пятно (тень/свечение) на холсте узла.
static func blob(ci: CanvasItem, center: Vector2, radius: Vector2, col: Color) -> void:
	ci.draw_texture_rect(soft(), Rect2(center - radius, radius * 2.0), false, col)
