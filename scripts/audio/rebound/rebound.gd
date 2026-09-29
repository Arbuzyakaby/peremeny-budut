extends Node
## Audio Rebound (v11.0) — акустика игры: звук отражается от стенок ящика, пола, врагов и стен лаборатории,
## и каждый материал поглощает свои частоты. Физика — в acoustics.gd (формулы и таблица материалов)
## и tracer.gd (трассировка лучей); этот узел собирает сцену, трассирует её в фоновом потоке и настраивает
## шину World, через которую звучат игровые эффекты.
##
## Две сцены:
## - ЯЩИК (BOX) — слушатель у головы змеи, источники вокруг неё на 30 см. Ящик 1,54 × 0,84 × 0,35 м
##   (1 px = 1,25 мм) с открытым верхом: пол своего материала на каждом этапе (коврик детской, бархат ящика
##   для приборов, аптечная плитка, лак терема, чугун сковороды), фанерные бортики, враги — препятствия.
##   Звук, ушедший через верх, попадает в лабораторию и возвращается её поздним хвостом (связанные объёмы:
##   хвост = 16π·κ·E_уш / A_лаб, где κ — доля проёма в поглощении ящика);
## - ЛАБОРАТОРИЯ (LAB) — финал, камера отъехала: слушатель рядом с учёным, источник — ящик на столе.
##   Комната 6 × 4,5 × 3 м: линолеум, штукатурка, окно, дверь, полки с образцами. Реверберация — Эйринг.
## В финале и в «Контакте» пол ящика меняется от пожара: уголь и зола пористые и глушат высокие частоты,
## снег углекислотного огнетушителя тоже; горячий воздух ускоряет звук, углекислый газ — замедляет.
##
## Что слышно (шина World → SFX), v11.0 после прослушивания:
## - в игре — только окраска тембра: шестиполосный эквалайзер (AudioEffectEQ6) по тому, сколько энергии
##   отражения приносят в каждой октаве. Ящик открыт сверху, стенки близко — отдельного эха и гула там
##   физически почти нет, отражения лишь чуть «подкрашивают» звук: плитка звонче, бархат и коврик глуше.
##   Эквалайзер только срезает (ни одна полоса не выше 0 дБ) — с отражениями не громче, чем без них;
##   меняется медленно (не больше EQ_RATE дБ/с) — без щелчков;
## - в финале, когда камера в лаборатории, — тихий хвост комнаты (AudioEffectReverb, размер из T60 Эйринга).
##   Его параметры ставятся один раз при входе в сцену, а не каждый кадр.
## Настройка «Audio Rebound» (Звук) обходит эффекты шины. Подробно — docs/AUDIO_REBOUND.md.

const Acoustics = preload("res://scripts/audio/rebound/acoustics.gd")
const Tracer = preload("res://scripts/audio/rebound/tracer.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Platform = preload("res://scripts/core/platform.gd")
const Tex = preload("res://scripts/gfx/tex.gd")

enum Mode { BOX, LAB }

const BUS := "World"
const PX_M := 0.00125                     # метров в пикселе арены
const INNER := Rect2(24, 24, 1232, 672)   # внутренность ящика (без бортиков), px
const BOX_H := 0.35                       # высота бортиков, м
const EAR_Z := 0.03                       # слух змеи — у самого пола
const SRC_R := 0.3                        # источники — на таком расстоянии вокруг головы
const UPDATE_T := 1.0                    # как часто перетрассировать сцену, с
const GRID := Vector2i(32, 18)            # сетка материалов пола
const MAX_OBSTACLES := 16
## Лаборатория: размеры, поверхности (площадь, материал) для Эйринга и грани для трассировки ранних отражений.
const LAB_SIZE := Vector3(6.0, 4.5, 3.0)
const LAB_SURFACES := [[27.0, "linoleum"], [27.0, "plaster"], [43.0, "plaster"], [12.0, "shelves"], [6.0, "glass"],
	[2.0, "door"]]
const LAB_FACES := ["shelves", "plaster", "glass", "plaster", "linoleum", "plaster"]
const LAB_SOURCE := Vector3(3.6, 2.2, 0.95)    # ящик на столе
const LAB_LISTENER := Vector3(4.7, 2.9, 1.6)   # голова учёного (и камеры)
## Freeverb внутри AudioEffectReverb: гребёнки по 1116…1617 отсчётов при 44,1 кГц (в среднем 31,4 мс),
## обратная связь g = 0,7 + 0,28·room_size. T60 гребёнки = −3·D / lg g — отсюда обратный пересчёт.
const COMB_D := 0.0314
## Отражения в ящике приходят через 1–5 мс — слух сливает их с прямым звуком (эффект предшествования),
## а задержка с такими временами дала бы металлическую «гребёнку». Поэтому ранние отражения ящика не
## играются отдельными эхо: они только окрашивают хвост (демпфирование, уровень). Хвост — тихий.
const WET_GAIN := 0.15
const WET_MAX_LAB := 0.12  # финал: хвост лаборатории — слышен, но не гудит
const EQ_DEPTH := 6.0      # окраска тембра не глубже стольких дБ
const EQ_RATE := 1.5       # дБ/с — как быстро меняется окраска (медленно: без щелчков)
## Полосы AudioEffectEQ6, Гц.
const EQ_BANDS := [32.0, 100.0, 320.0, 1000.0, 3200.0, 10000.0]
## Материал пола этапа (основной) и пятна поверх него: [вид, прямоугольник или эллипс px, материал].
const FLOOR_BASE := {Tex.Floor.WOOD: "wood_floor", Tex.Floor.TRAY: "steel", Tex.Floor.TILES: "tile",
	Tex.Floor.PAN: "cast_iron_oil", Tex.Floor.DRAWER: "velvet", Tex.Floor.TEREM: "lacquer"}
const FLOOR_PATCHES := {
	Tex.Floor.WOOD: [["ellipse", Rect2(378, 218, 524, 324), "rug"], ["rect", Rect2(95, 107, 110, 86), "textile"],
		["rect", Rect2(1075, 547, 110, 86), "textile"], ["rect", Rect2(1025, 97, 110, 86), "textile"]],
	Tex.Floor.TEREM: [["rect", Rect2(360, 598, 560, 58), "textile"]],
	Tex.Floor.DRAWER: [["rect", Rect2(24, 24, 22, 672), "lacquer"], ["rect", Rect2(330, 24, 22, 672), "lacquer"],
		["rect", Rect2(640, 24, 22, 672), "lacquer"], ["rect", Rect2(950, 24, 22, 672), "lacquer"],
		["rect", Rect2(24, 350, 1232, 22), "lacquer"]],
}

var game  # game.gd (без типа — нет циклического preload); может быть null в тестах
var mode := Mode.BOX
var enabled := true
var floor_kind := Tex.Floor.WOOD
var listener_px := Vector2(640, 360)
## Последний разбор: для панели разработчика и тестов.
var last := {}
var target := {}   # параметры шины, к которым идём
var current := {}  # что стоит сейчас
var traces := 0
var _t := 0.0
var _task := -1
var _box: Array = [null]  # сюда фоновая задача кладёт результат
var _scene := {}
var _floor_cache := {}
var eq: AudioEffectEQ6
var reverb: AudioEffectReverb
var _lab_on := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	apply_setting()


## Шина World: игровые эффекты → окраска тембра → (в финале) хвост лаборатории → SFX.
func _ensure_bus() -> void:
	var idx := AudioServer.get_bus_index(BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_send(idx, "SFX")
	while AudioServer.get_bus_effect_count(idx) > 0:  # старая раскладка шины (задержки) — убрать
		AudioServer.remove_bus_effect(idx, 0)
	AudioServer.set_bus_volume_db(idx, 0.0)
	eq = AudioEffectEQ6.new()
	AudioServer.add_bus_effect(idx, eq)
	reverb = AudioEffectReverb.new()
	reverb.dry = 1.0
	reverb.wet = 0.0
	reverb.spread = 1.0
	AudioServer.add_bus_effect(idx, reverb)


## Включить или обойти отражения по настройке «Audio Rebound».
func apply_setting() -> void:
	enabled = Settings.flag("rebound")
	set_bypass(not enabled)


static func set_bypass(on: bool) -> void:
	var idx := AudioServer.get_bus_index(BUS)
	if idx < 0:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		AudioServer.set_bus_effect_enabled(idx, i, not on)


func _process(delta: float) -> void:
	if game != null:
		_follow_game()
	_t -= delta
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _box[0] != null:
			_accept(_box[0], _scene)
	if enabled and _task < 0 and _t <= 0.0:
		_t = UPDATE_T
		_scene = build_scene()
		var scene := _scene
		var box := _box
		box[0] = null
		_task = WorkerThreadPool.add_task(func() -> void: box[0] = Tracer.trace(scene), false, "Audio Rebound")
	if not target.is_empty():
		_approach(delta)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Где слушатель и какая сцена — по состоянию игры.
func _follow_game() -> void:
	var cam: Camera2D = game.camera
	mode = Mode.LAB if game.state == game.State.CUTSCENE and cam and cam.zoom.x < 0.7 else Mode.BOX
	if game.snake and is_instance_valid(game.snake):
		listener_px = game.snake.head_pos
	else:
		listener_px = INNER.get_center()
	if game.arena:
		floor_kind = game.arena.floor_kind


# ---------------------------------------------------------------- сцена

## Сцена для трассировки по текущему состоянию (вызывается в основном потоке).
func build_scene(rays := -1) -> Dictionary:
	var n := rays if rays > 0 else (256 if Platform.is_mobile() else 640)
	if mode == Mode.LAB:
		return lab_scene(n)
	var fire = _fire_sim()
	var air := _box_air(fire)
	return box_scene(listener_px, floor_grid(floor_kind, fire), _obstacles(), n, traces + 1, air["temp"], air["gas"])


## Ящик с открытым верхом, слушатель у головы змеи, четыре источника вокруг.
static func box_scene(head_px: Vector2, floor_map: Dictionary, spheres: Array, rays := 160, seed_value := 1,
		temp_c := 20.0, gas: Dictionary = Acoustics.GAS["air"]) -> Dictionary:
	var size := Vector3(INNER.size.x * PX_M, INNER.size.y * PX_M, BOX_H)
	var ear := to_box(head_px, EAR_Z)
	var sources: Array = []
	for k in 4:
		var p := ear + Vector3(cos(k * PI / 2.0 + 0.4), sin(k * PI / 2.0 + 0.4), 0.0) * SRC_R
		p = p.clamp(Vector3(0.02, 0.02, 0.05), size - Vector3(0.02, 0.02, 0.05))
		p.z = 0.05
		sources.append(p)
	return {"size": size, "faces": ["plywood", "plywood", "plywood", "plywood", "wood_floor", "open"],
		"floor": floor_map, "spheres": spheres, "listener": ear.clamp(Vector3(0.01, 0.01, 0.01), size - Vector3(0.01, 0.01, 0.01)),
		"sources": sources, "rays": maxi(rays / 4, 8), "seed": seed_value, "t_max": 0.08, "bin": 0.0005,
		"receiver_r": 0.09, "temp_c": temp_c, "gas": gas, "mode": Mode.BOX}


static func lab_scene(rays := 160) -> Dictionary:
	return {"size": LAB_SIZE, "faces": LAB_FACES, "spheres": [], "listener": LAB_LISTENER, "sources": [LAB_SOURCE],
		"rays": rays, "seed": 7, "t_max": 0.08, "bin": 0.0005, "receiver_r": 0.35, "temp_c": 20.0,
		"gas": Acoustics.GAS["air"], "mode": Mode.LAB}


static func to_box(px: Vector2, z: float) -> Vector3:
	return Vector3((px.x - INNER.position.x) * PX_M, (px.y - INNER.position.y) * PX_M, z)


## Сетка материалов пола: основной материал этапа, пятна (коврик, половик, перегородки), поверх —
## следы пожара из fire_sim: снег огнетушителя, зола, уголь.
func floor_grid(kind: int, fire = null) -> Dictionary:
	var base: Dictionary = _floor_cache.get(kind, {})
	if base.is_empty():
		base = static_floor(kind)
		_floor_cache[kind] = base
	if fire == null:
		return base
	var out := base.duplicate(true)
	var pal: Array = out["palette"]
	for m in ["frost", "ash", "char"]:
		if not pal.has(m):
			pal.append(m)
	var cells: PackedByteArray = out["cells"]
	for gy in GRID.y:
		for gx in GRID.x:
			var p := INNER.position + (Vector2(gx, gy) + Vector2(0.5, 0.5)) * INNER.size / Vector2(GRID)
			var i: int = fire.index_at(p)
			var m := ""
			if fire.foam[i] > 0.3:
				m = "frost"
			elif fire.ash[i] > 0.5:
				m = "ash"
			elif fire.charred[i] > 0.5:
				m = "char"
			if m != "":
				cells[gy * GRID.x + gx] = pal.find(m)
	out["cells"] = cells
	return out


static func static_floor(kind: int) -> Dictionary:
	var pal: Array[String] = [String(FLOOR_BASE.get(kind, "wood_floor"))]
	var cells := PackedByteArray()
	cells.resize(GRID.x * GRID.y)
	for gy in GRID.y:
		for gx in GRID.x:
			var p := INNER.position + (Vector2(gx, gy) + Vector2(0.5, 0.5)) * INNER.size / Vector2(GRID)
			var m := 0
			for patch: Array in FLOOR_PATCHES.get(kind, []):
				var r: Rect2 = patch[1]
				var inside := r.has_point(p)
				if patch[0] == "ellipse":
					var q := (p - r.get_center()) / (r.size / 2.0)
					inside = q.length_squared() <= 1.0
				if inside:
					var mat := String(patch[2])
					if not pal.has(mat):
						pal.append(mat)
					m = pal.find(mat)
			cells[gy * GRID.x + gx] = m
	return {"w": GRID.x, "h": GRID.y, "cells": cells, "palette": pal}


## Враги как препятствия: [центр в метрах, радиус, материал]. Плоские (яичница, вилки, таблетки) —
## сферический сегмент: центр сферы под полом, над полом торчит только «горбик» высотой h.
func _obstacles() -> Array:
	var out: Array = []
	if game == null or game.enemies == null:
		return out
	var ear := listener_px
	var items: Array = []
	for b in game.enemies.bears:
		if is_instance_valid(b):
			items.append([b.position, 18.0, 0.0, "plush"])
	for f in game.enemies.forks:
		if is_instance_valid(f):
			items.append([f.position, 22.0, 6.0, "steel"])
	for p in game.enemies.pills:
		if is_instance_valid(p):
			items.append([p.position, 26.0, 16.0, "plastic"])
	for m in game.enemies.dolls:
		if is_instance_valid(m):
			items.append([m.position, float(m.radius()), 0.0, "lacquer"])
	if game.boss and is_instance_valid(game.boss):
		items.append([game.boss.position, 150.0, 30.0, "egg_white"])
	items.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[0] as Vector2).distance_squared_to(ear) < (b[0] as Vector2).distance_squared_to(ear))
	for it: Array in items.slice(0, MAX_OBSTACLES):
		out.append(obstacle(it[0], it[1], it[2], it[3]))
	return out


## Препятствие: круг радиуса r_px на полу. cap_px = 0 — шар (медведь, матрёшка), иначе сферический сегмент
## высотой cap_px с тем же радиусом основания.
static func obstacle(pos_px: Vector2, r_px: float, cap_px: float, mat: String) -> Array:
	var a := r_px * PX_M
	if cap_px <= 0.0:
		return [to_box(pos_px, a), a, mat]
	var h := minf(cap_px * PX_M, a)
	var r := (a * a + h * h) / (2.0 * h)  # радиус сферы по основанию a и высоте сегмента h
	return [to_box(pos_px, h - r), r, mat]


func _fire_sim():
	var f := get_tree().get_first_node_in_group("fire_box") if is_inside_tree() else null
	if f == null or not f.get("active") or f.get("sim") == null:
		return null
	return f.sim


## Воздух в ящике: средняя температура над полом (из пожара) и примесь углекислого газа (из огнетушителя).
func _box_air(fire) -> Dictionary:
	if fire == null:
		return {"temp": 20.0, "gas": Acoustics.GAS["air"]}
	var t := 0.0
	var step := 7
	var n := 0
	for i in range(0, fire.temp.size(), step):
		t += fire.temp[i]
		n += 1
	var air_t := 20.0 + (t / maxf(n, 1.0) - 20.0) * 0.5  # воздух у пола прогрет примерно вполовину от поверхности
	var co2: float = fire.gas_co2_mean() if fire.has_method("gas_co2_mean") else 0.0
	return {"temp": clampf(air_t, -40.0, 900.0), "gas": Acoustics.mixture({"air": 1.0 - co2, "co2": co2})}


# ---------------------------------------------------------------- отклик → шина

## Посчитать сразу (тесты, панель разработчика). Возвращает параметры шины.
func compute_now(scene: Dictionary) -> Dictionary:
	_accept(Tracer.trace(scene), scene)
	current = target.duplicate(true)
	_apply(current)
	return target


func _accept(res: Dictionary, scene: Dictionary) -> void:
	traces += 1
	var box_mode := int(scene.get("mode", Mode.BOX)) == Mode.BOX
	var tail := room_tail(res, scene) if box_mode else lab_tail(res, scene)
	var full := Tracer.analyze(res, tail)
	var early := Tracer.analyze(res, {}, false)
	target = bus_params(full, early, tail, scene)
	last = {"mode": "ящик" if box_mode else "лаборатория", "t30": _band(full, "t30"), "edt": _band(full, "edt"),
		"c50": _band(full, "c50"), "t60_room": tail["t60"], "taps": full["taps"], "rays": res["rays"],
		"hits": res["hits"], "c": res["c"], "escape": res["escape"], "direct": res["direct"], "tail": tail,
		"floor": scene.get("floor", {}).get("palette", [])}


static func _band(a: Dictionary, key: String) -> Array:
	var out: Array = []
	for b: Dictionary in a["bands"]:
		out.append(b[key])
	return out


## Поздний хвост лаборатории для звука из ящика (связанные объёмы).
## Энергия, ушедшая через верх (escape), заполняет комнату; обратно через проём приходит доля
## κ = S_проёма / (S_проёма + A_стенок ящика); интеграл хвоста у слушателя 16π·κ·E / A'_лаб.
static func room_tail(res: Dictionary, scene: Dictionary) -> Dictionary:
	var size: Vector3 = scene["size"]
	var s_open := size.x * size.y
	var box_walls: Array = [[size.x * size.y, "wood_floor"], [2.0 * (size.x + size.y) * size.z, "plywood"]]
	var energy: Array = []
	var t60: Array = []
	var c := Acoustics.speed_of_sound(20.0)
	var v := LAB_SIZE.x * LAB_SIZE.y * LAB_SIZE.z
	for b in Acoustics.NB:
		var m := Acoustics.air_m(b)
		var a_room := Acoustics.absorption_area(LAB_SURFACES, b, v, m) + 0.3 * s_open
		var kappa := s_open / (s_open + Acoustics.absorption_area(box_walls, b))
		energy.append(16.0 * PI * kappa * float(res["escape"][b]) / a_room)
		t60.append(Acoustics.eyring(v, LAB_SURFACES, b, m, c))
	var mfp := Acoustics.mean_free_path(v, Acoustics.total_area(LAB_SURFACES))
	return {"energy": energy, "t60": t60, "start": float(res["direct_t"]) + size.z / float(res["c"]) + mfp / c}


## Хвост самой лаборатории: диффузное поле 16π/A' (слушатель в той же комнате).
static func lab_tail(res: Dictionary, scene: Dictionary) -> Dictionary:
	var size: Vector3 = scene["size"]
	var v := size.x * size.y * size.z
	var c := float(res["c"])
	var energy: Array = []
	var t60: Array = []
	for b in Acoustics.NB:
		var m := Acoustics.air_m(b)
		energy.append(16.0 * PI / Acoustics.absorption_area(LAB_SURFACES, b, v, m))
		t60.append(Acoustics.eyring(v, LAB_SURFACES, b, m, c))
	var mfp := Acoustics.mean_free_path(v, Acoustics.total_area(LAB_SURFACES))
	return {"energy": energy, "t60": t60, "start": float(res["direct_t"]) + mfp / c}


## Параметры шины из разбора отклика: окраска тембра по октавам и (в лаборатории) хвост.
static func bus_params(full: Dictionary, early: Dictionary, tail: Dictionary, scene: Dictionary) -> Dictionary:
	var direct := maxf(float(full["direct"]), 1e-9)
	var box_mode := int(scene.get("mode", Mode.BOX)) == Mode.BOX
	var p := {}
	# тембр отражений: спектр энергии, которую приносят отражения (ящик) или хвост (лаборатория),
	# относительно самой громкой октавы — эквалайзер повторяет этот спектр (только срезы)
	var level := PackedFloat32Array()
	for b in Acoustics.NB:
		var e := float(early["bands"][b]["early"]) if box_mode else float(tail["energy"][b])
		level.append(Acoustics.db(e + 1e-9))
	var top := -INF
	for v in level:
		top = maxf(top, v)
	var gains := PackedFloat32Array()
	for b in Acoustics.NB:
		gains.append(clampf(level[b] - top, -EQ_DEPTH, 0.0))
	p["eq_octaves"] = gains
	p["eq"] = eq_for_bands(gains)
	p["reverb_on"] = not box_mode
	var t60: Array = tail["t60"]
	var t_mid := float(t60[Acoustics.MID])
	var g := pow(10.0, -3.0 * COMB_D / maxf(t_mid, 0.01))
	p["room_size"] = clampf((g - 0.7) / 0.28, 0.0, 1.0)
	p["damping"] = clampf(1.0 - float(t60[5]) / maxf(float(t60[2]), 1e-3), 0.0, 1.0)
	p["hipass"] = clampf(1.0 - float(t60[0]) / maxf(float(t60[2]), 1e-3), 0.0, 0.8)
	p["predelay_msec"] = clampf((float(tail["start"]) - float(full["direct_t"])) * 1000.0, 1.0, 400.0)
	p["wet"] = 0.0 if box_mode else clampf(sqrt(float(tail["energy"][Acoustics.MID]) / direct) * WET_GAIN, 0.0, WET_MAX_LAB)
	p["t60"] = t_mid
	var edt_box := float(early["bands"][Acoustics.MID]["edt"])
	p["flutter_ms"] = 0.0
	if box_mode and edt_box > 0.0:  # период порхающего эха — для панели разработчика (слышно его нет)
		var size: Vector3 = scene["size"]
		var c := Acoustics.speed_of_sound(float(scene.get("temp_c", 20.0)), scene.get("gas", Acoustics.GAS["air"]))
		p["flutter_ms"] = 2.0 * minf(size.x, size.y) / c * 1000.0
	return p


## Усиления полос EQ6 (32…10 000 Гц) по октавам 125…4000 Гц: линейно по логарифму частоты,
## за краями — как у крайней октавы.
static func eq_for_bands(octaves: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f: float in EQ_BANDS:
		var x := log(f / 125.0) / log(2.0)  # в октавах от 125 Гц
		var i := clampi(int(floor(x)), 0, Acoustics.NB - 2)
		var k := clampf(x - i, 0.0, 1.0)
		out.append(lerpf(octaves[i], octaves[i + 1], k))
	return out


## Окраска идёт к цели медленно; хвост комнаты ставится один раз при смене сцены.
func _approach(delta: float) -> void:
	var want: PackedFloat32Array = target.get("eq", PackedFloat32Array())
	var cur: PackedFloat32Array = current.get("eq", PackedFloat32Array([0, 0, 0, 0, 0, 0]))
	for b in mini(want.size(), cur.size()):
		cur[b] = move_toward(cur[b], want[b], EQ_RATE * delta)
	current["eq"] = cur
	_apply_eq(cur)
	var lab: bool = target.get("reverb_on", false)
	if lab != _lab_on:
		_lab_on = lab
		_apply_reverb(target)


func _apply(p: Dictionary) -> void:
	_apply_eq(p.get("eq", PackedFloat32Array()))
	_lab_on = p.get("reverb_on", false)
	_apply_reverb(p)


func _apply_eq(gains: PackedFloat32Array) -> void:
	if eq == null:
		return
	for b in mini(gains.size(), 6):
		if absf(eq.get_band_gain_db(b) - gains[b]) > 0.05:
			eq.set_band_gain_db(b, gains[b])


func _apply_reverb(p: Dictionary) -> void:
	if reverb == null:
		return
	for key in ["room_size", "damping", "hipass", "predelay_msec"]:
		if p.has(key):
			reverb.set(key, p[key])
	reverb.wet = float(p.get("wet", 0.0)) if p.get("reverb_on", false) else 0.0


## Строка для панели разработчика.
func summary() -> String:
	if last.is_empty():
		return "Audio Rebound: ещё не считал"
	return "Audio Rebound: %s, T30 %.2f с, EDT %.3f с, C50 %+.1f дБ, c = %.0f м/с, лучей %d (попали %d)" % [
		last["mode"], float(last["t30"][Acoustics.MID]), float(last["edt"][Acoustics.MID]),
		float(last["c50"][Acoustics.MID]), float(last["c"]), int(last["rays"]), int(last["hits"])]
