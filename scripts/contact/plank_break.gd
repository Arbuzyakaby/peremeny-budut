extends Node2D
## Доска-выход в финале «Контакта» (v12.2). Половица у нижнего правого угла ящика не «исчезает и рисует дыру»,
## а живёт по-настоящему в три стадии:
##   1. НАГРЕВ (set_heat 0..1) — доску ведёт от жара: тёмный прогар, вздувшиеся пятна, тлеющие волосяные
##      трещины; дерево скрипит всё чаще, из щелей тянет дымок, разлом проступает по доске от края к краю;
##   2. ПЕРЕЛОМ (snap) — доска ломается поперёк по рваной линии с длинными язычками щепы (у одной половины —
##      язычок, у другой — ответная выемка). Обе половины прибиты по концам гвоздями и провисают вниз
##      на шарнирах: качаются, стукаются, чуть подпрыгивают и оседают. Сверху они укорачиваются и темнеют,
##      в щель уходят тёмная глубина и светлый торец соседней доски;
##   3. ЩЕПА — щепки и длинные лучины летят по дуге с тенью на полу, часть падает в щель, остальная
##      отскакивает и остаётся лежать; тлеющие искры, опилки и дымок; вылетает гвоздь; через секунду —
##      осадка: ещё одна лучина сползает в щель.
## Ничего не перерисовывается, пока доска цела и остыла: узел спит (active()).

const Tex = preload("res://scripts/gfx/tex.gd")

signal sound(sound_name: String, pitch: float, volume_db: float)

enum St { INTACT, BROKEN }

## Полоса доски в мировых координатах: волокна идут по X, как у пола (доски высотой 120 px).
const X0 := 1120.0        # гвозди левой половины
const X1 := 1262.0        # гвозди правой половины
const YC := 660.0
const HW := 34.0          # полуширина полосы: змея проходит свободно
const X_BREAK := 1200.0
const THETA_MAX := 1.2    # на сколько половина проваливается вниз (рад)
const HALF_G := 11.0      # падение половин (доля угла за секунду²)
const GRAV := 1300.0
const MAX_BITS := 90
const REST_LIFE := 14.0

const WOOD := Color(0.8, 0.63, 0.43)
const CHAR := Color(0.2, 0.11, 0.06)
const FRESH := Color(0.95, 0.83, 0.58)
const DEPTH := Color(0.02, 0.012, 0.01)

var state := St.INTACT
var heat := 0.0
var t := 0.0
var snap_t := 0.0
var scorch := 0.0                   # насколько доска обуглилась к моменту перелома
var rim_glow := 0.0                 # тление по краю излома
var profile: PackedVector2Array = PackedVector2Array()  # линия излома: (v, u), v от -HW до +HW
var blisters: Array = []            # вздувшиеся пятна: {p, r}
var hairlines: Array = []           # тлеющие волосяные трещины: {pts, from}
var fringe: Array = []              # лучины по длинным краям щели: {u, side, len, lean}
var grains: Array = []              # волокна: {v, tone}
var left_a := 0.0                   # провис половины (0..1 от THETA_MAX)
var right_a := 0.0
var left_av := 0.0
var right_av := 0.0
var left_max := 1.0
var right_max := 0.94
var right_delay := 0.05
var bits: Array = []                # щепки, лучины, гвоздь, опилки, дым, искры
var creak_cd := 1.4
var smoke_cd := 0.0
var tick_cd := 0.0
var rests := 0
var aftershock := -1.0
var rng := RandomNumberGenerator.new()
var top: Node2D                     # слой над сущностями: летящая щепа, пыль, дым, искры
var seed_value := 0
var wood := WOOD                    # цвет доски: подстраивается под пол, чтобы излом не выделялся светлым пятном
var tone := 1.0                     # яркость пола относительно светлой фанеры (0..1)


class TopLayer extends Node2D:
	var plank

	func _draw() -> void:
		if plank:
			plank._draw_top(self)


func _init() -> void:
	seed_value = randi()


func _ready() -> void:
	top = TopLayer.new()
	top.plank = self
	top.z_index = 7
	add_child(top)
	_build()


## Геометрия строится один раз: линия излома, волосяные трещины, вздутия, лучины по краям.
func _build() -> void:
	rng.seed = seed_value
	profile = PackedVector2Array()
	var v := -HW
	while v <= HW + 0.01:  # рваная линия поперёк волокон
		profile.append(Vector2(v, X_BREAK + rng.randf_range(-13.0, 13.0)))
		v += rng.randf_range(9.0, 15.0)
	profile[profile.size() - 1].x = HW
	# язычки щепы: у левой половины (вправо) и у правой (влево) — на другой стороне линия уходит выемкой
	var tongues := [[-0.55, 1.0], [0.05, -1.0], [0.6, 1.0]]
	for tg: Array in tongues:
		var tv: float = float(tg[0]) * HW + rng.randf_range(-4.0, 4.0)
		var idx := 0
		for i in profile.size():
			if absf(profile[i].x - tv) < absf(profile[idx].x - tv):
				idx = i
		var p: Vector2 = profile[idx]
		var len := rng.randf_range(28.0, 44.0) * float(tg[1])
		len = clampf(p.y + len, X0 + 16.0, X1 - 14.0) - p.y  # язычок не доходит до гвоздей
		var w := rng.randf_range(3.0, 5.0)
		profile.remove_at(idx)
		profile.insert(idx, Vector2(p.x - w, p.y))
		profile.insert(idx + 1, Vector2(p.x - 0.5, p.y + len))
		profile.insert(idx + 2, Vector2(p.x + w, p.y + len * 0.25))
	blisters.clear()
	for i in 16:
		blisters.append({"p": Vector2(rng.randf_range(X0 + 6.0, X1 - 6.0), YC + rng.randf_range(-HW, HW)), "r": rng.randf_range(2.5, 7.0)})
	hairlines.clear()
	for i in 6:  # тлеющие волосяные трещины вдоль волокон
		var y := YC + rng.randf_range(-HW + 4.0, HW - 4.0)
		var x := X_BREAK + rng.randf_range(-70.0, 30.0)
		var pts := PackedVector2Array([Vector2(x, y)])
		for k in rng.randi_range(4, 8):
			x += rng.randf_range(7.0, 15.0) * (1.0 if i % 2 == 0 else 1.0)
			y += rng.randf_range(-3.5, 3.5)
			pts.append(Vector2(x, clampf(y, YC - HW + 2.0, YC + HW - 2.0)))
		hairlines.append({"pts": pts, "from": rng.randf_range(0.1, 0.55)})
	fringe.clear()
	for i in 22:
		fringe.append({"u": rng.randf_range(X0 + 6.0, X1 - 10.0), "side": -1.0 if i % 2 == 0 else 1.0,
			"len": rng.randf_range(4.0, 15.0), "lean": rng.randf_range(-0.6, 0.6)})
	grains.clear()
	for i in 7:
		grains.append({"v": -HW + (i + 0.5) * 2.0 * HW / 7.0 + rng.randf_range(-2.0, 2.0), "tone": rng.randf_range(0.6, 1.0)})


# ---------------------------------------------------------------- состояние

func active() -> bool:
	if state == St.INTACT:
		return heat > 0.0
	return snap_t < 3.5 or _moving() or rim_glow > 0.02


func is_broken() -> bool:
	return state == St.BROKEN


## Подогнать цвет доски под пол вокруг (среднее по площадке): в тёмном ящике излом не должен светиться.
func set_floor_color(c: Color) -> void:
	wood = Color(c.r, c.g, c.b, 1.0)
	tone = clampf(c.get_luminance() / WOOD.get_luminance(), 0.2, 1.1)
	queue_redraw()


## Нагрев доски 0..1 (жар от пожара): чем горячее, тем чаще скрип, дым и тем дальше проступает разлом.
func set_heat(h: float) -> void:
	if state == St.BROKEN:
		return
	heat = clampf(h, 0.0, 1.0)
	queue_redraw()


## Ширина щели между половинами по волокнам (px): как далеко разошлись обломки.
func gap_width() -> float:
	if state != St.BROKEN:
		return 0.0
	var ul := X0 + (X_BREAK - X0) * cos(left_a * THETA_MAX)
	var ur := X1 - (X1 - X_BREAK) * cos(right_a * THETA_MAX)
	return maxf(ur - ul, 0.0)


## Доска ломается: половины срываются с места, летит щепа, звук и пыль.
func snap() -> void:
	if state == St.BROKEN:
		return
	state = St.BROKEN
	scorch = clampf(heat, 0.25, 1.0)
	snap_t = 0.0
	rim_glow = 1.0
	left_av = 1.6
	right_av = 1.2
	sound.emit("wood_snap", rng.randf_range(0.95, 1.05), 0.0)
	_burst(22, 7, 1.0)
	_dust(6, 5)
	for i in int(6 + 8 * scorch):
		_spark(Vector2(X_BREAK + rng.randf_range(-20.0, 20.0), YC + rng.randf_range(-HW, HW)))
	_nail()
	aftershock = 0.9
	queue_redraw()
	top.queue_redraw()


func _moving() -> bool:
	if absf(left_av) > 0.01 or absf(right_av) > 0.01:
		return true
	if left_a < left_max - 0.003 or right_a < right_max - 0.003:
		return true
	for b: Dictionary in bits:
		if b["k"] != "rest":
			return true
	return false


func update(delta: float) -> void:
	if not active():
		return
	t += delta
	if state == St.INTACT:
		_update_heat(delta)
	else:
		snap_t += delta
		rim_glow = maxf(rim_glow - delta * 0.28, 0.0)
		_update_halves(delta)
		_update_aftershock(delta)
	tick_cd = maxf(tick_cd - delta, 0.0)
	_update_bits(delta)
	queue_redraw()
	top.queue_redraw()


func _update_heat(delta: float) -> void:
	if heat <= 0.0:
		return
	creak_cd -= delta
	if creak_cd <= 0.0:
		creak_cd = lerpf(1.5, 0.35, heat) * rng.randf_range(0.7, 1.3)
		sound.emit("wood_creak", rng.randf_range(0.75, 1.25) + heat * 0.25, lerpf(-14.0, -5.0, heat))
	smoke_cd -= delta
	if smoke_cd <= 0.0 and heat > 0.2:
		smoke_cd = lerpf(0.5, 0.12, heat)
		var hl: Dictionary = hairlines[rng.randi() % hairlines.size()]
		var pts: PackedVector2Array = hl["pts"]
		_add({"k": "smoke", "p": pts[pts.size() >> 1] + Vector2(rng.randf_range(-6.0, 6.0), 0), "v": Vector2(rng.randf_range(-8.0, 14.0), -rng.randf_range(20.0, 40.0)),
			"life": rng.randf_range(1.0, 1.8), "max": 1.8, "size": rng.randf_range(10.0, 20.0), "h": 0.0, "vh": 0.0, "rot": 0.0, "spin": 0.0})


## Половины качаются на шарнирах: падают, стукаются об упор, подпрыгивают и оседают.
func _update_halves(delta: float) -> void:
	var hit_l := _swing(delta, true)
	var hit_r := false if snap_t < right_delay else _swing(delta, false)
	if hit_l or hit_r:
		var strength := clampf(maxf(hit_l_speed, hit_r_speed) / 2.0, 0.25, 1.0)
		sound.emit("doll_land", rng.randf_range(0.5, 0.7), lerpf(-14.0, -5.0, strength))
		_burst(int(2 + 4 * strength), 1, 0.5)
		_dust(1, 1)


var hit_l_speed := 0.0
var hit_r_speed := 0.0


func _swing(delta: float, is_left: bool) -> bool:
	var a := left_a if is_left else right_a
	var av := left_av if is_left else right_av
	var amax := left_max if is_left else right_max
	av += HALF_G * delta
	a += av * delta
	var hit := false
	if a >= amax:
		a = amax
		if av > 0.7:
			hit = true
			if is_left:
				hit_l_speed = av
			else:
				hit_r_speed = av
			av = -av * 0.3
		else:
			av = 0.0
	if is_left:
		left_a = a
		left_av = av
	else:
		right_a = a
		right_av = av
	return hit


## Осадка: доска ещё раз скрипит, и ещё одна лучина съезжает в щель.
func _update_aftershock(delta: float) -> void:
	if aftershock < 0.0:
		return
	aftershock -= delta
	if aftershock <= 0.0:
		aftershock = -1.0
		sound.emit("wood_creak", 0.7, -8.0)
		for i in 3:
			_add({"k": "sliver", "p": Vector2(X_BREAK + rng.randf_range(-24.0, 24.0), YC + rng.randf_range(-HW + 6.0, HW - 6.0)),
				"v": Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-20.0, 20.0)), "h": 8.0, "vh": 60.0, "rot": rng.randf() * TAU,
				"spin": rng.randf_range(-6.0, 6.0), "life": 6.0, "max": 6.0, "size": rng.randf_range(14.0, 26.0), "bounces": 2})
		_dust(2, 1)


# ---------------------------------------------------------------- щепа, пыль, дым

func _add(b: Dictionary) -> void:
	if bits.size() >= MAX_BITS:
		bits.pop_front()
	bits.append(b)


## Щепки и лучины из линии излома: летят вверх и в стороны, падают, отскакивают.
func _burst(chips: int, slivers: int, power: float) -> void:
	for i in chips + slivers:
		var long := i >= chips
		var pv: Vector2 = profile[rng.randi() % profile.size()]
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		_add({"k": "sliver" if long else "chip", "p": Vector2(pv.y + rng.randf_range(-6.0, 6.0), YC + pv.x),
			"v": Vector2(side * rng.randf_range(20.0, 190.0), rng.randf_range(-130.0, 110.0)) * power,
			"h": rng.randf_range(2.0, 12.0), "vh": rng.randf_range(200.0, 560.0) * (0.75 if long else 1.0) * power,
			"rot": rng.randf() * TAU, "spin": rng.randf_range(-16.0, 16.0), "life": REST_LIFE, "max": REST_LIFE,
			"size": rng.randf_range(14.0, 30.0) if long else rng.randf_range(4.0, 10.0), "bounces": 0,
			"burnt": rng.randf() < scorch * 0.7})


func _dust(n: int, smoke: int) -> void:
	for i in n:
		_add({"k": "dust", "p": Vector2(X_BREAK + rng.randf_range(-40.0, 40.0), YC + rng.randf_range(-HW, HW)),
			"v": Vector2(rng.randf_range(-45.0, 45.0), rng.randf_range(-40.0, 25.0)), "life": rng.randf_range(0.7, 1.4), "max": 1.4,
			"size": rng.randf_range(24.0, 48.0), "h": 0.0, "vh": 0.0, "rot": 0.0, "spin": 0.0})
	for i in smoke:
		_add({"k": "smoke", "p": Vector2(X_BREAK + rng.randf_range(-45.0, 45.0), YC + rng.randf_range(-HW, HW)),
			"v": Vector2(rng.randf_range(-14.0, 22.0), -rng.randf_range(24.0, 55.0)), "life": rng.randf_range(1.2, 2.4), "max": 2.4,
			"size": rng.randf_range(16.0, 30.0), "h": 0.0, "vh": 0.0, "rot": 0.0, "spin": 0.0})


func _spark(p: Vector2) -> void:
	_add({"k": "ember", "p": p, "v": Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-60.0, 40.0)), "h": 0.0,
		"vh": rng.randf_range(120.0, 340.0), "life": rng.randf_range(0.5, 1.3), "max": 1.3, "size": rng.randf_range(1.8, 3.4), "rot": 0.0, "spin": 0.0})


func _nail() -> void:  # гвоздь выскочил из левого края и улетел по дуге
	_add({"k": "nail", "p": Vector2(X0 + 10.0, YC + rng.randf_range(-HW + 8.0, HW - 8.0)), "v": Vector2(-rng.randf_range(60.0, 110.0), rng.randf_range(-80.0, 80.0)),
		"h": 6.0, "vh": 520.0, "rot": rng.randf() * TAU, "spin": 22.0, "life": REST_LIFE, "max": REST_LIFE, "size": 15.0, "bounces": 0})


func _in_gap(p: Vector2) -> bool:
	if absf(p.y - YC) > HW - 2.0:
		return false
	var ul := X0 + (X_BREAK - X0) * cos(left_a * THETA_MAX)
	var ur := X1 - (X1 - X_BREAK) * cos(right_a * THETA_MAX)
	return p.x > ul + 3.0 and p.x < ur - 3.0 and maxf(left_a, right_a) > 0.3


func _update_bits(delta: float) -> void:
	for b: Dictionary in bits:
		var k: String = b["k"]
		if k == "rest":  # осевшая щепа лежит до конца сцены
			continue
		b["life"] = float(b["life"]) - delta
		match k:
			"dust", "smoke":
				b["p"] += b["v"] * delta
				b["v"] *= exp(-delta * 1.4)
				b["size"] = float(b["size"]) + delta * (34.0 if k == "dust" else 18.0)
			"ember":
				b["p"] += b["v"] * delta
				b["h"] = float(b["h"]) + float(b["vh"]) * delta
				b["vh"] = float(b["vh"]) - 180.0 * delta
				b["v"] *= exp(-delta * 1.2)
			"chip", "sliver", "nail":
				_fall(b, delta)
	bits = bits.filter(func(b: Dictionary) -> bool: return float(b["life"]) > 0.0)


func _fall(b: Dictionary, delta: float) -> void:
	if b["k"] == "rest":
		return
	b["vh"] = float(b["vh"]) - GRAV * delta
	b["h"] = float(b["h"]) + float(b["vh"]) * delta
	b["p"] += b["v"] * delta
	b["rot"] = float(b["rot"]) + float(b["spin"]) * delta
	if float(b["h"]) > 0.0:
		return
	b["h"] = 0.0
	if _in_gap(b["p"]):  # упала в щель — тёмная глубина забирает
		b["life"] = 0.0
		_tick(-16.0, 0.7)
		return
	if float(b["vh"]) < -170.0 and int(b.get("bounces", 0)) < 2:
		b["vh"] = -float(b["vh"]) * 0.35
		b["v"] *= 0.6
		b["spin"] = float(b["spin"]) * 0.5
		b["bounces"] = int(b.get("bounces", 0)) + 1
		_tick(-15.0, 1.0)
		return
	b["vh"] = 0.0
	b["v"] = Vector2.ZERO
	b["spin"] = 0.0
	b["k_src"] = b["k"]
	b["k"] = "rest"
	b["life"] = REST_LIFE
	b["max"] = REST_LIFE
	rests += 1
	if rests > 40:  # старые обломки на полу убираем — на полу должно оставаться немного
		for i in bits.size():
			if bits[i]["k"] == "rest":
				bits.remove_at(i)
				rests -= 1
				break


## Стук щепки о пол — не чаще пары раз за 0,1 с, чтобы не забивать голоса.
func _tick(vol: float, pitch: float) -> void:
	if tick_cd > 0.0:
		return
	tick_cd = 0.09
	sound.emit("splinter", pitch * rng.randf_range(0.8, 1.3), vol)


# ---------------------------------------------------------------- рисунок

## Линия излома в этом месте доски: u (вдоль волокон) для поперечной координаты v.
func _b_at(v: float) -> float:
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		if v >= a.x and v <= b.x and b.x > a.x + 0.001:
			return lerpf(a.y, b.y, (v - a.x) / (b.x - a.x))
	return X_BREAK


func _wood(k_char: float) -> Color:
	return wood.lerp(CHAR.lerp(wood, 0.35), clampf(k_char, 0.0, 1.0))


## Светлое волокно на сломе: в тёмном ящике тоже темнее.
func _fresh() -> Color:
	return FRESH.darkened(0.5 * (1.0 - tone))


func _draw() -> void:
	if state == St.INTACT:
		_draw_heating()
	else:
		_draw_broken()
	for b: Dictionary in bits:  # осевшая щепа лежит на полу — под сущностями
		if b["k"] == "rest" or (float(b.get("h", 0.0)) < 1.0 and b["k"] in ["chip", "sliver", "nail"]):
			_draw_bit(self, b, true)


func _draw_heating() -> void:
	if heat <= 0.0:
		return
	var c := Vector2((X0 + X1) / 2.0, YC)
	Tex.blob(self, c + Vector2(0, 4), Vector2(150, 74), Color(0.08, 0.04, 0.015, 0.5 * heat))  # прогар
	for bl: Dictionary in blisters:  # вздувшиеся, обугленные пятна
		var p: Vector2 = bl["p"]
		draw_circle(p, float(bl["r"]) * (0.5 + 0.5 * heat), Color(0.13, 0.07, 0.03, 0.55 * heat))
	var pulse := 0.85 + 0.15 * sin(t * 9.0)
	Tex.blob(self, c, Vector2(120, 55), Color(1.0, 0.45, 0.1, 0.3 * heat * pulse))  # жар из щелей
	for hl: Dictionary in hairlines:  # волосяные трещины растут по мере нагрева
		var k := clampf((heat - float(hl["from"])) / 0.45, 0.0, 1.0)
		if k <= 0.0:
			continue
		var pts := _partial(hl["pts"], k)
		draw_polyline(pts, Color(0.06, 0.03, 0.015, 0.9), 3.6, true)
		draw_polyline(pts, Color(1.0, 0.55, 0.15, 0.95 * pulse), 1.8, true)
		Tex.blob(self, pts[pts.size() - 1], Vector2(9, 9), Color(1.0, 0.5, 0.1, 0.5 * pulse * k))
	var reveal := clampf((heat - 0.45) / 0.55, 0.0, 1.0)  # разлом проступает по доске от края к краю
	if reveal > 0.0:
		var line := PackedVector2Array()
		for p in profile:
			line.append(Vector2(p.y, YC + p.x))
		var part := _partial(line, reveal)
		draw_polyline(part, Color(0.05, 0.02, 0.01, 0.9), 4.2, true)
		draw_polyline(part, Color(1.0, 0.6, 0.2, 0.95 * pulse), 2.0, true)


## Начало ломаной длиной k (0..1) от всей: последний отрезок обрезается по доле.
func _partial(pts: PackedVector2Array, k: float) -> PackedVector2Array:
	var n := (pts.size() - 1) * k
	var whole := int(n)
	var out := PackedVector2Array()
	for i in mini(whole + 1, pts.size()):
		out.append(pts[i])
	if whole < pts.size() - 1:
		out.append(pts[whole].lerp(pts[whole + 1], n - whole))
	return out


func _draw_broken() -> void:
	var open := clampf(snap_t * 6.0, 0.0, 1.0)
	var hole := PackedVector2Array([Vector2(X0, YC - HW), Vector2(X1, YC - HW), Vector2(X1, YC + HW), Vector2(X0, YC + HW)])
	draw_colored_polygon(hole, Color(DEPTH, open))
	var mid := Vector2((X0 + X1) / 2.0, YC)
	Tex.blob(self, mid, Vector2(96, 44), Color(0.11, 0.065, 0.04, 0.55 * open))  # далёкий пол под доской
	# светлая стенка соседней доски: видна по нижнему краю щели и справа
	var wall_h := 11.0 * open
	draw_colored_polygon(PackedVector2Array([Vector2(X0, YC + HW), Vector2(X1, YC + HW), Vector2(X1, YC + HW - wall_h), Vector2(X0, YC + HW - wall_h)]),
		Color(0.55 * tone, 0.38 * tone, 0.22 * tone, 0.85))
	draw_line(Vector2(X0, YC + HW - 1.0), Vector2(X1, YC + HW - 1.0), Color(_fresh(), 0.75), 1.6)
	draw_colored_polygon(PackedVector2Array([Vector2(X1, YC - HW), Vector2(X1, YC + HW), Vector2(X1 - wall_h * 0.8, YC + HW - wall_h), Vector2(X1 - wall_h * 0.8, YC - HW)]),
		Color(0.4 * tone, 0.27 * tone, 0.15 * tone, 0.8))
	for f: Dictionary in fringe:  # рваные лучины по длинным краям щели
		var side: float = f["side"]
		var base := Vector2(float(f["u"]), YC + side * HW)
		var tip := base + Vector2(float(f["lean"]) * 8.0, -side * float(f["len"]) * open)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-2.5, 0), tip, base + Vector2(2.5, 0)]), Color(_fresh(), 0.9))
		draw_line(base, tip, Color(0.4, 0.26, 0.12, 0.7), 1.0)
	_draw_half(true)
	_draw_half(false)
	# контактная тень под падающими половинами
	Tex.blob(self, Vector2(X0 + 40.0, YC), Vector2(60, 38), Color(0, 0, 0, 0.3 * left_a))
	Tex.blob(self, Vector2(X1 - 30.0, YC), Vector2(50, 38), Color(0, 0, 0, 0.3 * right_a))


## Проекция точки половины доски на экран: шарнир на конце, вторая часть уходит вниз и сокращается по длине.
func _proj(u: float, v: float, hinge: float, a: float) -> Vector2:
	var th := a * THETA_MAX
	var s := cos(th)
	var d := absf(u - hinge) / 90.0 * sin(th)
	return Vector2(hinge + (u - hinge) * s, YC + v * (1.0 - 0.1 * d))


func _shade(u: float, hinge: float, a: float, base: Color) -> Color:
	var d := clampf(absf(u - hinge) / 90.0 * sin(a * THETA_MAX), 0.0, 1.0)
	return base.lerp(Color(0.03, 0.02, 0.015), d * 0.72)


func _half_poly(is_left: bool) -> PackedVector2Array:  # в координатах (u, v)
	var pts := PackedVector2Array()
	if is_left:
		pts.append(Vector2(X0, -HW))
		for p in profile:
			pts.append(Vector2(p.y, p.x))
		pts.append(Vector2(X0, HW))
	else:
		pts.append(Vector2(X1, HW))
		for i in range(profile.size() - 1, -1, -1):
			pts.append(Vector2(profile[i].y, profile[i].x))
		pts.append(Vector2(X1, -HW))
	return pts


func _draw_half(is_left: bool) -> void:
	var hinge := X0 if is_left else X1
	var a := left_a if is_left else right_a
	var base := _wood(scorch * 0.75)
	var poly := _half_poly(is_left)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for p in poly:
		pts.append(_proj(p.x, p.y, hinge, a))
		cols.append(_shade(p.x, hinge, a, base))
	draw_polygon(pts, cols)
	for g: Dictionary in grains:  # волокна вдоль доски
		var v: float = g["v"]
		var end := _b_at(v)
		end = end - 3.0 if is_left else end + 3.0
		if (is_left and end < X0 + 6.0) or (not is_left and end > X1 - 6.0):
			continue
		draw_line(_proj(hinge, v, hinge, a), _proj(end, v, hinge, a), Color(0.22, 0.12, 0.05, 0.3 * float(g["tone"])), 1.6)
	var edge := PackedVector2Array()  # край излома: обугленный снаружи, светлое волокно на сломе
	for p in profile:
		edge.append(_proj(p.y, p.x, hinge, a))
	draw_polyline(edge, Color(CHAR, 0.9), 5.0, true)
	draw_polyline(edge, Color(_fresh(), 0.95), 2.4, true)
	if rim_glow > 0.02:
		draw_polyline(edge, Color(1.0, 0.5, 0.12, 0.75 * rim_glow), 1.6, true)
	var sx := 1.0 if is_left else -1.0
	for vv in [-HW + 9.0, HW - 9.0]:  # шляпки гвоздей
		var np := _proj(hinge + sx * 11.0, vv, hinge, a)
		draw_circle(np, 2.8, Color(0.16, 0.16, 0.18))
		draw_circle(np + Vector2(-0.6, -0.6), 1.2, Color(0.55, 0.56, 0.6))


func _draw_top(ci: CanvasItem) -> void:
	for b: Dictionary in bits:
		var k: String = b["k"]
		if k == "rest" or (float(b.get("h", 0.0)) < 1.0 and k in ["chip", "sliver", "nail"]):
			continue
		_draw_bit(ci, b, false)


func _draw_bit(ci: CanvasItem, b: Dictionary, on_floor: bool) -> void:
	var k: String = b["k"]
	var p: Vector2 = b["p"]
	var life_k := clampf(float(b["life"]) / float(b["max"]), 0.0, 1.0)
	match k:
		"dust":
			Tex.blob(ci, p, Vector2.ONE * float(b["size"]), Color(0.78, 0.66, 0.48, 0.34 * life_k))
		"smoke":
			Tex.blob(ci, p, Vector2.ONE * float(b["size"]), Color(0.32, 0.31, 0.32, 0.3 * life_k))
		"ember":
			var at := p + Vector2(0, -float(b["h"]))
			var sz: float = b["size"]
			Tex.blob(ci, at, Vector2.ONE * sz * 3.5, Color(1.0, 0.5, 0.1, 0.35 * life_k))
			ci.draw_circle(at, sz * life_k, Color(1.0, 0.85, 0.4, life_k))
		_:
			var h := float(b.get("h", 0.0))
			var src: String = b.get("k_src", k)
			var alpha := 1.0
			var sz: float = b["size"]
			var dir := Vector2.from_angle(float(b["rot"]))
			if h > 0.5:  # тень на полу
				Tex.blob(ci, p + Vector2(4, 3), Vector2(sz * 0.5 + 3.0, sz * 0.22 + 2.0), Color(0, 0, 0, 0.3 * clampf(1.0 - h / 220.0, 0.2, 1.0)))
			var at := p + Vector2(0, -h)
			if src == "nail":
				ci.draw_line(at - dir * sz * 0.5, at + dir * sz * 0.5, Color(0.45, 0.46, 0.5, alpha), 2.0)
				ci.draw_circle(at + dir * sz * 0.5, 2.6, Color(0.6, 0.6, 0.64, alpha))
			elif src == "sliver":  # длинная лучина: светлая с обугленным концом
				ci.draw_line(at - dir * sz * 0.5, at + dir * sz * 0.5, Color(0.12, 0.07, 0.04, alpha), 5.0)
				ci.draw_line(at - dir * sz * 0.5, at + dir * sz * 0.5, Color(_fresh(), alpha), 3.0)
				ci.draw_line(at - dir * sz * 0.5, at - dir * sz * 0.2, Color(CHAR, alpha), 3.0)
			else:  # щепка: острый треугольник
				var n := dir.orthogonal()
				var tri := PackedVector2Array([at + dir * sz * 0.6, at - dir * sz * 0.4 + n * sz * 0.35, at - dir * sz * 0.4 - n * sz * 0.3])
				ci.draw_colored_polygon(tri, Color(CHAR if b.get("burnt", false) else _fresh(), alpha))
				ci.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.3, 0.18, 0.08, alpha), 1.2)
