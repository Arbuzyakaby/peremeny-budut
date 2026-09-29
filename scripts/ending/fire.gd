extends Node2D
## Пожар в ящике. Физика — клеточная симуляция горения (fire_sim.gd): теплопроводность, конвекция,
## излучение пламени, топливо, пиролиз, пилотное и самовоспламенение, плавление, уголь и зола;
## с v11.0 над дном — газы (gas_sim.gd): кислород, CO₂, CO, сажа, белый пиролизный дым, облако
## огнетушителя, течение к основанию пламени. Картинка — шейдер (FIRE_SHADER):
## - языки пламени высотой по Хескестаду (L = 0,235·Q^0,4 − 1,02·D) пульсируют с частотой 1,5/√D;
##   у основания — синяя зона (свечение радикалов CH* и C₂*), выше — жёлтое свечение сажи по кривой
##   абсолютно чёрного тела; коптящее пламя (пластик, масло) — темнее и рыжее;
## - дым столбами: сажа (чёрный) и смолы пиролиза (белый, валит до вспышки), непрозрачность — по закону
##   Бугера — Ламберта — Бера (T = e^(−τ), τ = K·ρ·L, K сажи = 8,7 м²/г), снизу подсвечен пламенем;
## - углекислотный огнетушитель: белое стелющееся облако (туман в холодной струе) и снег сухого льда;
## дерево обугливается с трещинами «крокодиловой кожи» и тлеет, бумага сгорает до светлой золы, пластик
## плавится и стекает блестящей лужей, металл раскаляется докрасна и остывает, над огнём дрожит марево.
## После тушения остаются уголь и зола — навсегда. API прежний: start / fill_instantly / extinguish /
## covers / coverage и поля origin, radius, strength, t, active.

const Tex = preload("res://scripts/gfx/tex.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Platform = preload("res://scripts/core/platform.gd")
const FireSim = preload("res://scripts/ending/fire_sim.gd")
const GasSim = preload("res://scripts/ending/gas_sim.gd")
const AREA := Rect2(0, 0, 1280, 720)
## Откуда бьёт струя огнетушителя (учёный стоит справа сверху) — относительно точки прицела.
const SPRAY_FROM := Vector2(420, -380)
const SIM_RATE := 12.0

const FIRE_SHADER := """
shader_type canvas_item;
uniform sampler2D data_tex : filter_linear;      // R — температура, G — уголь, B — зола, A — расплав
uniform sampler2D info_tex : filter_linear;      // R — материал ×32 (читается texelFetch), G — снег/пена, B — копоть, A — горит пламенем
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D gas_a : filter_linear;         // R — τ сажи, G — τ белого дыма, B — τ тумана, A — высота пламени
uniform sampler2D gas_b : filter_linear;         // R — кислород, G — тепловыделение, B — CO₂, A — температура газа
uniform vec2 cells = vec2(96.0, 54.0);
uniform float max_t = 1400.0;
uniform bool haze = true;
uniform float puff_phase = 0.0;                  // фаза пульсаций 1,5/√D (копится на процессоре — без скачков)
uniform float rise_t = 0.0;                      // «время» подъёма языков, тоже накопленное
// слой a поверх слоя b (обычное «over» с непремноженной альфой)
vec4 over(vec4 a, vec4 b) {
	float oa = a.a + b.a * (1.0 - a.a);
	vec3 rgb = (a.rgb * a.a + b.rgb * b.a * (1.0 - a.a)) / max(oa, 0.0001);
	return vec4(rgb, oa);
}
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
	// пламя (v11.0): языки поднимаются только над клетками, которые горят пламенем (info.a), — остывающий
	// уголь светится сам (тление выше), но языков не даёт. Высота языка — по Хескестаду (gas_a.a);
	// форма — турбулентный шум с искажением координат, уходящий вверх; цвет — свечение сажи:
	// красная кромка → оранжевое тело → жёлто-белая сердцевина. Вокруг — отсвет на дне.
	float flame = 0.0;
	float ft = 0.0;
	float fbase = 9.0;   // на сколько клеток выше основания своего языка эта точка
	float fsoot = 0.0;
	vec2 cell = 1.0 / cells;
	float puff = 0.93 + 0.08 * sin(puff_phase + n * 3.0);
	for (int k = 0; k < 14; k++) {
		float fk = float(k);
		vec2 off = vec2(0.0, cell.y * fk * 0.6);
		float burning = texture(info_tex, UV + off).a;
		if (burning < 0.02) {
			continue;
		}
		float tk = texture(data_tex, UV + off).r * max_t;
		vec4 ga = texture(gas_a, UV + off);
		// высота языка по Хескестаду (A: 0..0,5 м) в клетках экрана (вид 3/4 укорачивает вертикаль втрое)
		float reach = max(ga.a * 10.5, 3.0) * puff;
		float heat = burning * smoothstep(300.0, 900.0, tk) * clamp(1.0 - fk * 0.6 / reach, 0.0, 1.0);
		if (heat > flame) { flame = heat; ft = tk; fbase = fk * 0.6; fsoot = ga.r; }
	}
	float rise = rise_t;
	vec2 fq = vec2(px.x * 0.022, px.y * 0.009 + rise * 0.8);
	vec2 fwarp = vec2(fbm(fq + vec2(1.7, 9.2)), fbm(fq + vec2(8.3, 2.8)));
	float turb = fbm(fq * 1.9 + fwarp * 1.7 + vec2(0.0, rise * 0.5));
	// отдельные языки: узкие вертикальные пряди, которые к верхушке пламени расходятся и рвутся
	float strands = vnoise(vec2(px.x * 0.055 + fwarp.x * 2.0, px.y * 0.006 + rise * 0.7));
	float top_k = smoothstep(0.15, 0.75, 1.0 - flame);
	float fi = flame * (0.45 + 0.9 * turb) * mix(1.0, 0.25 + 1.1 * strands, top_k) - (1.0 - flame) * 0.12;
	fi = clamp(fi, 0.0, 1.4);
	float tongue = smoothstep(0.16, 0.42, fi);
	vec3 fc = mix(vec3(0.9, 0.2, 0.03), vec3(1.0, 0.5, 0.07), smoothstep(0.2, 0.55, fi));
	fc = mix(fc, vec3(1.0, 0.8, 0.32), smoothstep(0.55, 0.9, fi));
	fc = mix(fc, vec3(1.0, 0.96, 0.84), smoothstep(1.05, 1.35, fi));
	// у самых горячих клеток сердцевина уходит в бело-жёлтый (как blackbody при max_t)
	fc = mix(fc, bb_hue(ft), smoothstep(1050.0, 1350.0, ft) * smoothstep(0.8, 1.2, fi) * 0.5);
	// коптящее пламя (много сажи: пластик, масло) — рыжее
	fc = mix(fc, fc * vec3(0.95, 0.7, 0.5), smoothstep(0.1, 0.6, fsoot) * 0.6);
	vec4 gb = texture(gas_b, UV);
	// голубая кайма у основания крупных языков: свечение радикалов CH* (431 нм) и C₂* (516 нм)
	float blue = tongue * smoothstep(0.55, 0.9, flame) * (1.0 - smoothstep(0.0, 0.7, fbase)) * smoothstep(0.35, 0.9, gb.r) * (1.0 - smoothstep(0.0, 0.3, fsoot));
	fc = mix(fc, vec3(0.45, 0.6, 1.0), blue * 0.18);
	// отсвет пламени на дне и соседних предметах
	vec3 glow_c = vec3(1.0, 0.45, 0.1) * flame * 0.35;
	col.rgb = mix(col.rgb, col.rgb + glow_c, col.a);
	col = over(vec4(1.0, 0.5, 0.12, flame * 0.22 * (1.0 - tongue)), col);
	col = over(vec4(fc, tongue * 0.95), col);
	// снег сухого льда (углекислотный огнетушитель): белые кристаллы с искрой, тает (сублимирует) от жара
	if (foam > 0.02) {
		float grain = fbm(px * 0.09 + vec2(0.0, TIME * 0.05));
		float b = smoothstep(0.15, 0.5, foam * 0.9 + (grain - 0.5) * 0.7);
		float spark = smoothstep(0.93, 0.99, vnoise(px * 0.8)) * (0.6 + 0.4 * sin(TIME * 7.0 + px.x));
		vec3 fcol = vec3(0.9, 0.93, 0.97) * (0.8 + 0.25 * grain) + vec3(0.6) * spark;
		col = mix(col, vec4(fcol, 0.92), b);
	}
	// дым: над клеткой поднимается столб (в виде 3/4 — вверх по экрану); сажа чёрная, смолы пиролиза белые.
	// Непрозрачность — закон Бугера — Ламберта — Бера: T = exp(−τ)
	float tau_s = 0.0;
	float tau_w = 0.0;
	float lit = 0.0;
	for (int j = 0; j < 7; j++) {
		float fj = float(j);
		float up = fj * 0.018;
		vec2 warp = (vec2(fbm(px * 0.006 + vec2(fj, TIME * 0.25)), fbm(px * 0.006 + vec2(TIME * 0.2, fj))) - 0.5) * 0.03;
		vec4 g = texture(gas_a, UV + vec2(0.0, up) + warp);
		float billow = 0.5 + 0.8 * fbm(px * 0.009 + vec2(fj * 3.1, TIME * 0.3));
		float fade = 1.0 - fj / 8.0;
		tau_s += g.r * 4.0 * billow * fade * 0.12;
		tau_w += g.g * 4.0 * billow * fade * 0.08;
		lit = max(lit, texture(gas_b, UV + vec2(0.0, up)).g * fade);
	}
	float tau = tau_s + tau_w;
	if (tau > 0.01) {
		vec3 sc = (vec3(0.07, 0.06, 0.055) * tau_s + vec3(0.78, 0.76, 0.72) * tau_w) / tau;
		sc += vec3(1.0, 0.45, 0.12) * lit * 0.15;  // снизу дым подсвечен пламенем
		col = over(vec4(sc, (1.0 - exp(-tau)) * 0.6), col);  // дым полупрозрачный — огонь под ним виден
	}
	// облако углекислотного огнетушителя: холодный туман стелется по дну и клубится
	vec4 g0 = texture(gas_a, UV);
	if (g0.b > 0.004) {
		float roll = fbm(px * 0.02 + vec2(TIME * 0.3, -TIME * 0.12));
		col = over(vec4(0.93, 0.95, 0.98, (1.0 - exp(-g0.b * 4.0 * (0.4 + 1.2 * roll))) * 0.95), col);
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
var gas: GasSim
var rect: ColorRect
var data_img: Image
var info_img: Image
var data_tex: ImageTexture
var info_tex: ImageTexture
var _data := PackedByteArray()
var _info := PackedByteArray()
var _ga := PackedByteArray()
var _gb := PackedByteArray()
var ga_img: Image
var gb_img: Image
var ga_tex: ImageTexture
var gb_tex: ImageTexture
var _acc := 0.0
var _foam_t := -1.0
var _puff_target := 3.0
var _puff := 3.0        # частота пульсаций, плавно догоняет цель
var _puff_phase := 0.0
var _rise := 0.0
var _foam_time := 2.4
## Огнетушитель: сначала проход струёй справа налево (_foam_time), затем струя наводится на оставшиеся
## очаги — как учат на пожарно-техническом минимуме: «бить в основание пламени», — пока пламя не погаснет
## (и ещё SPRAY_HOLD с) или не кончится заряд.
var spraying := false
var aim := Vector2(1250, 360)
var _hold := 0.0
const SPRAY_HOLD := 0.6
var _rng := RandomNumberGenerator.new()  # выбор очагов (от сида пожара — повторяемо)
const DWELL := 0.7         # с — сколько держать струю на очаге (сбить пламя и охладить)
var _dwell := 0.0
var _spot := Vector2(640, 360)
const AIM_SPEED := 1200.0  # px/с — как быстро учёный переводит раструб
var debris: Node2D
## Противопожарное полотно (кошма) поверх ящика: 0 — нет, 1 — накрыт. Воздух сверху перекрыт (gas.sealed).
var blanket := 0.0
var blanket_node: Node2D
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
	gas = GasSim.new(sim)
	sim.gas_coupled = true
	sim.gas_ref = weakref(gas)
	add_to_group("fire_box")  # Audio Rebound слушает пол и воздух ящика
	debris = Node2D.new()  # обломки лежат под змеёй, огонь — над ней
	debris.z_index = -5
	debris.draw.connect(_draw_debris)
	add_child(debris)
	blanket_node = Node2D.new()
	blanket_node.z_index = 40
	blanket_node.draw.connect(_draw_blanket)
	add_child(blanket_node)


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
	# дым над ящиком выше, чем видит шейдер: редкие клубы, уходящие к потолку лаборатории
	smoke = _particles(int(30 * pm), 7.0, Vector2(0, -80), Vector2(90, 220),
		[Color(0.25, 0.22, 0.2, 0), Color(0.14, 0.13, 0.12, 0.35), Color(0.1, 0.1, 0.1, 0)], Vector2(640, 150), Vector2(620, 160))
	smoke.z_index = 30
	# облако CO₂: холодное и тяжёлое — не всплывает, а оседает и растекается по дну
	steam = _particles(int(80 * pm), 4.0, Vector2(0, 40), Vector2(90, 200),
		[Color(0.95, 0.96, 1, 0), Color(0.92, 0.94, 0.97, 0.55), Color(1, 1, 1, 0)], AREA.get_center(), AREA.size / 2.0)
	steam.spread = 180.0
	steam.initial_velocity_min = 10.0
	steam.initial_velocity_max = 60.0
	steam.z_index = 31
	_upload()


func _make_render() -> void:
	if rect:
		return
	sim.pack(_data, _info)
	data_img = Image.create_from_data(sim.w, sim.h, false, Image.FORMAT_RGBA8, _data)
	info_img = Image.create_from_data(sim.w, sim.h, false, Image.FORMAT_RGBA8, _info)
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
	gas.pack(_ga, _gb)
	ga_img = Image.create_from_data(gas.w, gas.h, false, Image.FORMAT_RGBA8, _ga)
	gb_img = Image.create_from_data(gas.w, gas.h, false, Image.FORMAT_RGBA8, _gb)
	ga_tex = ImageTexture.create_from_image(ga_img)
	gb_tex = ImageTexture.create_from_image(gb_img)
	m.set_shader_parameter("gas_a", ga_tex)
	m.set_shader_parameter("gas_b", gb_tex)
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
	info_img.set_data(sim.w, sim.h, false, Image.FORMAT_RGBA8, _info)
	data_tex.update(data_img)
	info_tex.update(info_img)
	gas.pack(_ga, _gb)
	ga_img.set_data(gas.w, gas.h, false, Image.FORMAT_RGBA8, _ga)
	gb_img.set_data(gas.w, gas.h, false, Image.FORMAT_RGBA8, _gb)
	ga_tex.update(ga_img)
	gb_tex.update(gb_img)
	_puff_target = puff_hz()


## Пропуск финала: пожар мгновенно догорел, осталась зола.
func fill_instantly() -> void:
	if not active:
		start(origin)
	sim.burn_out()
	radius = 2000.0
	_upload()


## Потушить за time секунд углекислотным огнетушителем: учёный ведёт струю справа налево по огню,
## CO₂ вытесняет кислород (пламя гаснет по критерию Бейлера), снег сухого льда охлаждает, облако стелется.
func extinguish(time: float) -> void:
	if not active:
		return
	_foam_t = 0.0
	_foam_time = time
	steam.emitting = true
	spraying = true
	_hold = SPRAY_HOLD
	aim = Vector2(1250, 360)
	_rng.seed = seed_value * 31 + 7
	_spot = aim
	_dwell = 0.0
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
	if spraying:
		_update_spray(delta)
	# фаза и подъём копятся по кадрам: смена частоты меняет скорость, а не перескакивает фазу
	_puff = move_toward(_puff, _puff_target, delta * 0.5)
	_puff_phase = fmod(_puff_phase + delta * TAU * _puff, TAU * 1000.0)
	_rise += delta * 3.4
	if rect:
		var mat := rect.material as ShaderMaterial
		mat.set_shader_parameter("puff_phase", _puff_phase)
		mat.set_shader_parameter("rise_t", _rise)
	_acc += delta
	if _acc >= 1.0 / SIM_RATE:
		var dt := minf(_acc, 0.25)
		sim.step(dt)
		gas.step(dt)
		_acc = 0.0
		_update_radius()
		_upload()
		debris.queue_redraw()
	var hot := coverage()
	if hot > 0.25 and strength > 0.5 and not embers.emitting:
		embers.emitting = true
		smoke.emitting = true


func _update_spray(delta: float) -> void:
	_foam_t += delta
	# учёный бьёт в основание пламени — туда, где горит, очаг за очагом: следующий очаг — один из
	# ближайших горящих участков (кто первым попался на глаза), а не точка заранее заданной кривой.
	# На погашенном месте струю держат DWELL с — пока оно не остынет, иначе уголь вспыхнет снова от соседей;
	# в первые _foam_time секунд руку переводят быстрее — сбить пламя по всему фронту.
	_dwell -= delta
	if _dwell <= 0.0:
		var spots: Array = []
		for c in gas.w * gas.h:
			if gas.hrr[c] > 1.0:
				var p := sim.area.position + (Vector2(c % gas.w, c / gas.w) + Vector2(0.5, 0.5)) * sim.area.size / Vector2(gas.w, gas.h)
				spots.append([p.distance_squared_to(aim), p])
		if not spots.is_empty():
			spots.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
			var pick: Array = spots[_rng.randi_range(0, mini(7, spots.size() - 1))]
			_spot = pick[1] + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20))
		_dwell = DWELL * (0.5 if _foam_t <= _foam_time else 1.0) * _rng.randf_range(0.7, 1.3)
	if sim.burning_cells > 0:
		_hold = SPRAY_HOLD
	else:
		_hold -= delta
	aim = aim.move_toward(_spot, AIM_SPEED * delta)
	gas.start_spray(aim + SPRAY_FROM, aim)
	if _hold <= 0.0 or float(gas.spray["left"]) <= 0.0:
		stop_extinguisher()


## Накрыть ящик кошмой (on) или снять её. Воздух перекрывается сразу, полотно ложится за time секунд.
func cover(on: bool, time := 0.6) -> void:
	if gas:
		gas.sealed = 1.0 if on else 0.0
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		blanket = k
		blanket_node.queue_redraw(), blanket, 1.0 if on else 0.0, time)


## Кошма — плотное серо-бежевое полотно с провисшими складками, обшитым краем и нашивкой.
func _draw_blanket() -> void:
	if blanket <= 0.01:
		return
	var a := blanket
	var r := AREA.grow(10.0)
	r.size.y *= a  # ложится сверху вниз
	blanket_node.draw_rect(r.grow(4.0), Color(0, 0, 0, 0.3 * a))
	blanket_node.draw_rect(r, Color(0.62, 0.58, 0.5, a))
	for i in 9:  # складки: провисает между бортиками
		var x := r.position.x + r.size.x * (i + 0.5) / 9.0
		blanket_node.draw_line(Vector2(x, r.position.y), Vector2(x + sin(i * 1.7) * 30.0, r.end.y),
			Color(0.45, 0.42, 0.36, 0.5 * a), 10.0)
		blanket_node.draw_line(Vector2(x + 14.0, r.position.y), Vector2(x + 14.0 + sin(i * 1.7) * 30.0, r.end.y),
			Color(0.75, 0.71, 0.63, 0.35 * a), 4.0)
	blanket_node.draw_rect(r, Color(0.35, 0.3, 0.25, a), false, 8.0)  # обшитый край
	if a > 0.95:
		var tag := Rect2(r.get_center() - Vector2(90, 30), Vector2(180, 60))
		blanket_node.draw_rect(tag, Color(0.85, 0.15, 0.12, a))
		blanket_node.draw_string(ThemeDB.fallback_font, tag.position + Vector2(18, 42), "КОШМА", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 34, Color(1, 1, 1, a))


## Учёный отпустил рычаг.
func stop_extinguisher() -> void:
	spraying = false
	if gas:
		gas.stop_spray()


## Сколько CO₂ осталось в баллоне, кг.
func co2_left() -> float:
	return float(gas.spray["left"]) if gas else 0.0


## Частота пульсаций пламени, Гц: 1,5/√D по эквивалентному диаметру всего очага.
func puff_hz() -> float:
	var n := 0
	for c in gas.w * gas.h:
		if gas.hrr[c] > 1.0:
			n += 1
	if n == 0:
		return 3.0
	return clampf(GasSim.puffing_hz(sqrt(4.0 * n * gas.dx * gas.dx / PI)), 1.0, 8.0)


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
