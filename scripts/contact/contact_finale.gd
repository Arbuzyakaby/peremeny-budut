extends Node2D
## Финал «Контакта» (v10.0) — игровой, от лица змеи, а не катсценой. Фазы:
##   CLIMB — вся компания лезет к верхнему борту ящика, выбираться;
##   HAND  — над ящиком нависает тень, опускается рука учёного с горящей спичкой;
##   FIRE  — спичка падает у борта, огонь (fire.gd, чистый ящик — plain) бежит по маслу вниз;
##           кого накрыл огонь — сгорает (кроме швеи); змею огонь не жжёт, но отбрасывает;
##           от жара трескается доска в углу — выход;
##   GUN   — рука возвращается с пистолетом: выстрелы по змее (мимо — отбрасывает) и по отряду;
##   OUT   — змея в щели: последний залп, выживают только змея и медведь-швея → hideout.gd.
## Смерти для змеи нет: только толчки, замедление и паника вокруг.

const Tex = preload("res://scripts/gfx/tex.gd")
const Fire = preload("res://scripts/ending/fire.gd")
const Design = preload("res://scripts/ui/design.gd")

enum Ph { CLIMB, HAND, FIRE, GUN, OUT, DONE }

const SCIENTIST := "УЧЁНЫЙ-БЮРОКРАТ"
const EXIT := Vector2(1212, 652)
const EXIT_RADIUS := 64.0
const EGG_EDGE := 120.0      # яичница горит, если огонь дошёл до края белка
const CLIMB_MIN := 2.5
const CLIMB_MAX := 7.0
const HAND_TIME := 2.6
const GUN_AT := 2.0           # после вспышки: рука возвращается с пистолетом
const CRACK_AT := 4.6         # после вспышки: от жара трескается доска в углу — выход (уже под пулями)
const SHOT_EVERY := Vector2(0.5, 0.8)
const BULLET_TIME := 0.09
const SKIN := Color(0.93, 0.8, 0.7)
const COAT := Color(0.93, 0.94, 0.92)
const LINE := Color(0.14, 0.14, 0.17)

var contact  # contact_mode.gd
var g        # game.gd
var ph := Ph.CLIMB
var ph_t := 0.0
var t := 0.0
var fire: Fire
var hand := Vector2(640, -520)  # кисть руки сверху (мировые координаты, ящик 0..1280 × 0..720)
var holding := "match"
var shadow := 0.0
var exit_open := 0.0
var muzzle := 0.0
var shot_cd := 0.0
var shots := 0
var tracers: Array = []   # {a, b, life}
var recoil := 0.0         # 1 — сразу после выстрела: затвор откатился, руку подбросило
var casings: Array = []   # стреляные гильзы: {p, v, rot, spin, life}
var puffs: Array = []     # дымок из ствола: {p, life}
var match_fall := -1.0
var match_from := Vector2.ZERO
var match_to := Vector2(640, 96)
var out_t := 0.0
var fire_t := 0.0


func begin() -> void:
	g.hud.show_banner("ВСЕ ЗАОДНО. ПОРА ВЫБИРАТЬСЯ!", Color(0.6, 1, 0.5), 2.0)
	g.hint("Веди всех к верхнему борту — выбираемся из ящика!", 4.0)
	g.sfx.play_music("")
	_to(Ph.CLIMB)


func _to(p: int) -> void:
	ph = p as Ph
	ph_t = 0.0


## Змея уходит в щель сама — управление у игрока забрано.
func controls_snake() -> bool:
	return ph in [Ph.OUT, Ph.DONE]


func autopilot_target() -> Vector2:
	if exit_open > 0.5:
		return EXIT
	if ph == Ph.CLIMB:
		return Vector2(640, 150)
	return Vector2(900, 560)


func update(delta: float) -> void:
	t += delta
	ph_t += delta
	muzzle = maxf(muzzle - delta * 8.0, 0.0)
	recoil = maxf(recoil - delta * 6.0, 0.0)
	for c: Dictionary in casings:  # гильза летит вправо, катится по дну и замирает
		c["p"] += c["v"] * delta
		c["v"] *= exp(-delta * 3.0)
		c["rot"] += c["spin"] * delta
		c["spin"] *= exp(-delta * 2.0)
		c["life"] -= delta
	casings = casings.filter(func(c: Dictionary) -> bool: return float(c["life"]) > 0.0)
	for pf: Dictionary in puffs:
		pf["p"] += Vector2(sin(t * 3.0 + pf["life"] * 5.0) * 12.0, -40.0) * delta
		pf["life"] -= delta
	puffs = puffs.filter(func(pf: Dictionary) -> bool: return float(pf["life"]) > 0.0)
	for tr: Dictionary in tracers:
		tr["life"] = float(tr["life"]) - delta
	tracers = tracers.filter(func(tr: Dictionary) -> bool: return float(tr["life"]) > 0.0)
	var snake = g.snake
	match ph:
		Ph.CLIMB:
			_wants_climb()
			if (ph_t > CLIMB_MIN and snake.head_pos.y < 240.0) or ph_t > CLIMB_MAX:
				_to(Ph.HAND)
				g.hud.show_caption(SCIENTIST, "Образцы… сговорились?! Пункт 12-Б. Немедленно.")
				g.sfx.play("match")
				g.add_shake(6.0)
		Ph.HAND:
			shadow = move_toward(shadow, 1.0, delta / 1.2)
			hand = hand.lerp(Vector2(640, -40), 1.0 - exp(-delta * 2.2))
			_wants_panic(0.6)
			if ph_t > HAND_TIME and match_fall < 0.0:
				match_fall = 0.0
				match_from = hand + Vector2(-40, 70)
				holding = ""
			if match_fall >= 0.0:
				match_fall += delta / 0.45
				if match_fall >= 1.0:
					_ignite()
		Ph.FIRE, Ph.GUN:
			fire_t += delta
			_wants_panic(1.0)
			_burn_check()
			_snake_in_fire(delta)
			if fire_t > CRACK_AT and exit_open == 0.0:
				_crack()
			if ph == Ph.FIRE:
				hand = hand.lerp(Vector2(640, -560), 1.0 - exp(-delta * 3.0))
				if fire_t > GUN_AT:
					_to(Ph.GUN)
					holding = "gun"
					shot_cd = 0.4
					g.hud.show_caption(SCIENTIST, "Ни один образец не покинет ящик!")
			else:
				hand = hand.lerp(Vector2(clampf(snake.head_pos.x * 0.7 + 190.0, 200.0, 1080.0), -30.0), 1.0 - exp(-delta * 2.5))
				shot_cd -= delta
				if shot_cd <= 0.0:
					shot_cd = randf_range(SHOT_EVERY.x, SHOT_EVERY.y)
					_shoot()
			if exit_open > 0.0:
				exit_open = minf(exit_open + delta * 2.0, 1.0)
			if exit_open >= 1.0 and snake.head_pos.distance_to(EXIT) < EXIT_RADIUS:
				_escape()
		Ph.OUT:
			out_t += delta
			snake.glide_to(snake.head_pos.lerp(EXIT + Vector2(60, 40), 1.0 - exp(-delta * 4.0)), delta)
			snake.modulate.a = maxf(1.0 - out_t * 1.5, 0.0)
			var s: Dictionary = contact.seamstress()
			if not s.is_empty():
				s["want"] = (EXIT + Vector2(50, 30) - s["node"].position) * 4.0
				s["node"].modulate.a = maxf(1.0 - maxf(out_t - 0.3, 0.0) * 1.5, 0.0)
			if out_t > 1.6:
				_to(Ph.DONE)
				contact.start_hideout()
	queue_redraw()


# ---------------------------------------------------------------- движение компании

func _wants_climb() -> void:
	var list: Array = contact.survivors()
	var n := maxi(list.size(), 1)
	for i in list.size():
		var e: Dictionary = list[i]
		var node: Node2D = e["node"]
		var goal := Vector2(160.0 + 960.0 * (i + 0.5) / n, 70.0 + (i % 3) * 36.0)
		if e["kind"] == "egg":
			goal = Vector2(640, 210)
		if e["protected"]:
			goal = g.snake.head_pos + Vector2(0, 50)
		var to: Vector2 = goal - node.position
		e["want"] = to.normalized() * minf(to.length() * 2.5, 230.0) if to.length() > 8.0 else Vector2.ZERO


## Паника: разбегаются от огня и руки; швея держится у хвоста змеи.
func _wants_panic(k: float) -> void:
	var from := fire.origin if fire else hand
	for e: Dictionary in contact.survivors():
		var node: Node2D = e["node"]
		if e["protected"]:
			var segs: PackedVector2Array = g.snake.get_segments()
			var goal: Vector2 = segs[mini(6, segs.size() - 1)] if segs.size() > 0 else g.snake.head_pos
			var to := goal - node.position
			e["want"] = to.normalized() * minf(to.length() * 5.0, 330.0) if to.length() > 6.0 else Vector2.ZERO
			continue
		var away: Vector2 = (node.position - from).normalized()
		var wob := Vector2.from_angle(t * 3.0 + node.get_instance_id() % 13) * 0.6
		var spd := 160.0 if e["kind"] != "egg" else 60.0
		e["want"] = (away + wob).normalized() * spd * k


func _burn_check() -> void:
	if fire == null:
		return
	for e: Dictionary in contact.survivors():
		if e["protected"]:
			continue
		var node: Node2D = e["node"]
		var hit: bool = fire.covers(node.position)
		if e["kind"] == "egg":  # край белка в огне — горит вся
			hit = hit or fire.covers(node.position + Vector2(0, -EGG_EDGE))
		if hit:
			g.sfx.play("burn", randf_range(0.9, 1.2), -6.0)
			contact.kill(e, "fire")



func _snake_in_fire(delta: float) -> void:
	var snake = g.snake
	if fire and fire.covers(snake.head_pos):
		snake.slow(0.4)
		snake.knockback = snake.knockback.move_toward((EXIT - snake.head_pos).normalized() * 260.0, 1600.0 * delta)
		snake.invuln = 0.2  # мигает


func _ignite() -> void:
	match_fall = -1.0
	_to(Ph.FIRE)
	g.hud.hide_caption()
	fire = Fire.new()
	fire.plain = true
	fire.seed_value = randi()
	fire.z_index = 6 - 30  # под рукой и трассерами, но над полом (узел финала — z 30)
	add_child(fire)
	fire.start(match_to)
	g.hud.overlay.flash(0.7)
	g.sfx.play("ignite", 1.0, 1.0)
	g.sfx.play_ambient("fire", -12.0)
	g.sfx.play_music("fire")
	g.add_shake(30.0)
	g.vibrate(120)


func _crack() -> void:
	exit_open = 0.01
	g.sfx.play("clang", 0.6)
	g.sfx.play("fork_thud", 0.8)
	g.add_shake(10.0)
	g.fx.burst(EXIT, Color(0.45, 0.27, 0.13), 20)
	g.fx.popup(EXIT + Vector2(-120, -50), "ДОСКА ТРЕСНУЛА!", Color(1, 0.8, 0.4))
	g.hint("Выход — щель в углу ящика! Туда!", 4.0)


func _shoot() -> void:
	shots += 1
	var from := hand + Vector2(0, 150)
	var snake = g.snake
	var target: Vector2 = snake.head_pos + Vector2.from_angle(snake.heading) * 60.0
	var victim: Dictionary = {}
	if shots % 3 == 0:  # каждый третий — по отряду
		var list: Array = contact.survivors().filter(func(e: Dictionary) -> bool: return not e["protected"] and e["kind"] != "egg")
		if not list.is_empty():
			victim = list.pick_random()
			target = victim["node"].position
	if victim.is_empty():
		target += Vector2.from_angle(randf() * TAU) * randf_range(34.0, 80.0)  # мимо змеи — впритирку
	target = target.clamp(g.bounds.position, g.bounds.end)
	muzzle = 1.0
	_recoil()
	tracers.append({"a": from, "b": target, "life": 0.12})
	g.sfx.play("gunshot", randf_range(0.95, 1.05))
	g.add_shake(7.0)
	var tw := create_tween()
	tw.tween_interval(BULLET_TIME)
	tw.tween_callback(_impact.bind(target, victim))


## Отдача: затвор назад, рука вверх, гильза вылетает вправо из окна выброса, из ствола — дымок.
func _recoil() -> void:
	recoil = 1.0
	casings.append({"p": hand + Vector2(20, 70), "v": Vector2(randf_range(260, 420), randf_range(-120, 60)),
		"rot": randf() * TAU, "spin": randf_range(-18, 18), "life": 2.5})
	puffs.append({"p": hand + Vector2(0, 160), "life": 1.2})


func _impact(at: Vector2, victim: Dictionary) -> void:
	var snake = g.snake
	contact.paint.add_mark(at)
	g.fx.burst(at, Color(1, 0.85, 0.5), 8, 0.6)
	g.sfx.play("ricochet", randf_range(0.9, 1.2), -4.0)
	if not victim.is_empty() and not victim.get("dead", false):
		contact.kill(victim, "shot")
	if snake.head_pos.distance_to(at) < 90.0:
		snake.push((snake.head_pos - at).normalized() * 380.0)
		g.fx.popup(snake.head_pos + Vector2(0, -36), ["МИМО!", "ЕЛЕ-ЕЛЕ!", "ВПРИТИРКУ!"].pick_random(), Color(1, 0.7, 0.5))
		g.vibrate(40)


func _escape() -> void:
	_to(Ph.OUT)
	g.hud.hide_caption()
	g.hud.hide_prompt()
	g.snake.autopilot = false
	g.snake.rear = 0.0
	g.sfx.play("gunshot", 0.9)
	muzzle = 1.0
	_recoil()
	for e: Dictionary in contact.survivors():  # последний залп и пламя: никого, кроме швеи
		if e["protected"]:
			continue
		var p: Vector2 = e["node"].position
		tracers.append({"a": hand + Vector2(0, 150), "b": p, "life": 0.3})
		contact.kill(e, "fire" if fire and fire.covers(p) else "shot")


# ---------------------------------------------------------------- рисунок

func _draw() -> void:
	if shadow > 0.0:  # тень учёного над ящиком
		Tex.blob(self, Vector2(hand.x + 120.0, 80.0), Vector2(900, 520) * (0.6 + 0.4 * shadow), Color(0, 0, 0, 0.35 * shadow))
	if exit_open > 0.0:
		_draw_exit()
	for tr: Dictionary in tracers:
		var k: float = float(tr["life"]) / 0.12
		draw_line(tr["a"], tr["b"], Color(1, 0.95, 0.7, 0.8 * k), 5.0)
		draw_line(tr["a"], tr["b"], Color(1, 1, 1, k), 2.0)
	if match_fall >= 0.0:
		var p := match_from.lerp(match_to, match_fall * match_fall)
		var dir := Vector2.from_angle(match_fall * TAU * 1.3 - PI / 2.0)
		_draw_match(p - dir * 36.0, p)
	for c: Dictionary in casings:  # латунные гильзы на дне
		var d := Vector2.from_angle(c["rot"]) * 9.0
		draw_line(c["p"] - d, c["p"] + d, LINE, 10.0)
		draw_line(c["p"] - d, c["p"] + d, Color(0.85, 0.66, 0.28), 6.0)
		draw_circle(c["p"] + d, 3.0, Color(0.95, 0.8, 0.45))
	if hand.y > -500.0:
		_draw_hand()
	for pf: Dictionary in puffs:  # пороховой дымок
		var k: float = float(pf["life"]) / 1.2
		Tex.blob(self, pf["p"], Vector2.ONE * (30.0 + 60.0 * (1.0 - k)), Color(0.75, 0.75, 0.78, 0.35 * k))


func _draw_exit() -> void:
	var k := exit_open
	var c := EXIT + Vector2(22, 22)
	var hole := PackedVector2Array([c + Vector2(-70, 10) * k, c + Vector2(-30, -40) * k, c + Vector2(10, -70) * k,
		c + Vector2(30, -20) * k, c + Vector2(40, 40), c + Vector2(-20, 40)])
	draw_colored_polygon(hole, Color(0.03, 0.02, 0.02))
	draw_polyline(hole, Color(0.55, 0.35, 0.16), 4.0)
	for i in 4:  # щепки
		var a := c + Vector2(-60 + i * 22, -10 - i * 14) * k
		draw_line(a, a + Vector2(14, -6), Color(0.62, 0.42, 0.2), 4.0)
	if k >= 1.0 and ph != Ph.DONE:  # стрелка-подсказка
		var bob := sin(t * 6.0) * 8.0
		var tip := EXIT + Vector2(-70 - bob, -70 - bob)
		draw_line(tip + Vector2(-60, -60), tip, Color(1, 0.9, 0.3), 8.0)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(14, 14), tip + Vector2(-20, 4), tip + Vector2(4, -20)]),
			Color(1, 0.9, 0.3))


## Рука учёного сверху (v11.2 — подробно): рукав халата со складками и пуговицей на манжете, из-под него —
## манжета рубашки и часы на запястье; кисть с костяшками, ногтями и светотенью. В руке спичка или
## пистолет Макарова: затвор с насечками, целик и мушка, окно выброса, курок, флажок предохранителя,
## спусковая скоба. Выстрел: затвор откатывается, руку подбрасывает, вылетает гильза, из ствола — дымок.
func _draw_hand() -> void:
	var h := hand + Vector2(0, -18.0 * recoil)
	_draw_sleeve(h)
	if holding == "gun":
		_draw_pistol(h)
	_draw_palm(h, holding == "gun")
	if holding == "match":
		_draw_match(h + Vector2(-40, 40), h + Vector2(-40, 110))


## Многоугольник с обводкой в стиле игры: сначала контур толщиной w, потом заливка.
func _poly(pts: PackedVector2Array, fill: Color, w := 6.0) -> void:
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, LINE, w, true)


## Скруглённый «палец»: от a до b толщиной r, с обводкой.
func _capsule(a: Vector2, b: Vector2, r: float, fill: Color) -> void:
	draw_line(a, b, LINE, r * 2.0 + 8.0)
	draw_circle(a, r + 4.0, LINE)
	draw_circle(b, r + 4.0, LINE)
	draw_line(a, b, fill, r * 2.0)
	draw_circle(a, r, fill)
	draw_circle(b, r, fill)


func _draw_sleeve(h: Vector2) -> void:
	var top := Vector2(h.x + 170.0, -900.0)
	var wrist := h + Vector2(40, -95)
	var dir := (wrist - top).normalized()
	var n := dir.orthogonal()
	_poly(PackedVector2Array([top + n * 100.0, wrist + n * 86.0, wrist - n * 86.0, top - n * 100.0]), COAT, 8.0)
	var shade := COAT.darkened(0.14)
	draw_colored_polygon(PackedVector2Array([top - n * 96.0, wrist - n * 82.0, wrist - n * 40.0, top - n * 44.0]),
		Color(shade, 0.7))  # теневая сторона рукава
	for k in 5:  # складки ткани у локтя и запястья
		var at := top.lerp(wrist, 0.45 + k * 0.1)
		var bend := n * (30.0 + 12.0 * sin(k * 2.1))
		draw_polyline(PackedVector2Array([at - n * 70.0, at - bend * 0.3 + dir * 18.0, at + n * 60.0]), shade, 4.0, true)
	draw_line(top + n * 20.0, wrist + n * 14.0, Color(shade, 0.8), 3.0)  # шов
	var cuff_a := wrist - dir * 40.0
	_poly(PackedVector2Array([cuff_a + n * 92.0, wrist + n * 90.0, wrist - n * 90.0, cuff_a - n * 92.0]), COAT.lightened(0.02), 6.0)
	draw_circle(cuff_a.lerp(wrist, 0.5) + n * 60.0, 9.0, LINE)  # пуговица
	draw_circle(cuff_a.lerp(wrist, 0.5) + n * 60.0, 6.0, Color(0.85, 0.82, 0.72))
	# манжета рубашки и часы на запястье
	var shirt := wrist + dir * 14.0
	_poly(PackedVector2Array([shirt - dir * 16.0 + n * 72.0, shirt + dir * 6.0 + n * 70.0, shirt + dir * 6.0 - n * 70.0,
		shirt - dir * 16.0 - n * 72.0]), Color(0.72, 0.8, 0.9), 5.0)
	var watch := shirt + dir * 22.0 - n * 18.0
	draw_line(watch + n * 60.0, watch - n * 56.0, LINE, 26.0)
	draw_line(watch + n * 58.0, watch - n * 54.0, Color(0.36, 0.22, 0.13), 18.0)  # ремешок
	draw_circle(watch, 26.0, LINE)
	draw_circle(watch, 21.0, Color(0.78, 0.75, 0.68))  # корпус
	draw_circle(watch, 16.0, Color(0.96, 0.95, 0.9))    # циферблат
	draw_line(watch, watch + Vector2.from_angle(t * 0.5) * 11.0, LINE, 2.5)
	draw_line(watch, watch + Vector2.from_angle(t * 6.0) * 14.0, Color(0.7, 0.1, 0.1), 1.5)


## Кисть сверху: тыльная сторона ладони, костяшки, пальцы. С пистолетом пальцы обхватили рукоять,
## указательный лёг на спуск, большой — вдоль затвора; со спичкой — щепоть.
func _draw_palm(h: Vector2, gun: bool) -> void:
	var skin_d := SKIN.darkened(0.12)
	var back := PackedVector2Array()
	for v in [Vector2(-72, -62), Vector2(-20, -80), Vector2(52, -74), Vector2(86, -20), Vector2(84, 40),
			Vector2(54, 74), Vector2(-4, 82), Vector2(-56, 70), Vector2(-86, 18)]:
		back.append(h + v)
	_poly(back, SKIN, 6.0)
	draw_colored_polygon(PackedVector2Array([h + Vector2(40, -60), h + Vector2(84, -18), h + Vector2(82, 38),
		h + Vector2(52, 70), h + Vector2(30, 20)]), Color(skin_d, 0.55))  # теневая сторона кисти
	for k in 3:  # сухожилия на тыльной стороне
		var x := -30.0 + k * 26.0
		draw_line(h + Vector2(x * 0.6, -60), h + Vector2(x, 44), Color(skin_d, 0.5), 3.0)
	var knuckles := [Vector2(-48, 58), Vector2(-14, 66), Vector2(20, 64), Vector2(52, 54)]
	if gun:
		for k in 3:  # средний, безымянный, мизинец — обхватили рукоять (видны согнутые фаланги)
			var kn: Vector2 = h + knuckles[k + 1]
			_capsule(kn, kn + Vector2(-8.0 - k * 2.0, 26.0), 17.0 - k * 1.5, SKIN)
			draw_arc(kn + Vector2(-4, 12), 9.0, 0.3, 2.6, 8, Color(skin_d, 0.9), 2.0)  # складка сгиба
		var idx: Vector2 = h + knuckles[0]
		_capsule(idx, idx + Vector2(20, 50), 15.0, SKIN)  # указательный — на спусковой крючок
		_nail(idx + Vector2(20, 50), Vector2(0.37, 1.0))
		_capsule(h + Vector2(-84, -6), h + Vector2(-36, 78), 18.0, SKIN)  # большой — вдоль затвора
		_nail(h + Vector2(-36, 78), Vector2(0.52, 0.85))
	else:
		for k in 4:  # щепоть: пальцы сведены к спичке
			var kn: Vector2 = h + knuckles[k]
			var tip := kn + (h + Vector2(-40, 70) - kn) * 0.5 + Vector2(0, 26)
			_capsule(kn, tip, 16.0 - k * 1.2, SKIN)
			_nail(tip, (tip - kn).normalized())
		_capsule(h + Vector2(-84, -6), h + Vector2(-52, 52), 18.0, SKIN)
		_nail(h + Vector2(-52, 52), Vector2(0.48, 0.88))
	for kn in knuckles:  # костяшки
		draw_arc(h + kn + Vector2(0, -6), 10.0, PI * 1.1, PI * 1.9, 8, Color(skin_d, 0.9), 2.5)


func _nail(at: Vector2, dir: Vector2) -> void:
	var n := dir.orthogonal()
	var c := at - dir * 4.0
	draw_colored_polygon(PackedVector2Array([c + n * 7.0, c + dir * 8.0 + n * 5.0, c + dir * 8.0 - n * 5.0, c - n * 7.0]),
		Color(0.98, 0.86, 0.82))


## Пистолет Макарова сверху, стволом вниз (к ящику). Дульный срез — в hand + (0, 150).
func _draw_pistol(h: Vector2) -> void:
	var steel := Color(0.19, 0.2, 0.23)
	var hi := Color(0.42, 0.44, 0.5)
	var slide_back := 14.0 * recoil  # затвор откатился
	var y0 := -44.0 - slide_back
	var y1 := 150.0 - slide_back
	# спусковая скоба и рама под затвором
	draw_arc(h + Vector2(14, 104), 26.0, -0.4, PI + 0.4, 16, LINE, 10.0)
	draw_arc(h + Vector2(14, 104), 26.0, -0.4, PI + 0.4, 16, steel, 5.0)
	var slide := PackedVector2Array([h + Vector2(-22, y0 + 6), h + Vector2(-16, y0), h + Vector2(16, y0),
		h + Vector2(22, y0 + 6), h + Vector2(22, y1 - 10), h + Vector2(14, y1), h + Vector2(-14, y1), h + Vector2(-22, y1 - 10)])
	_poly(slide, steel, 6.0)
	draw_line(h + Vector2(-8, y0 + 10), h + Vector2(-8, y1 - 12), hi, 4.0)  # блик по верху затвора
	draw_line(h + Vector2(12, y0 + 10), h + Vector2(12, y1 - 12), Color(0.1, 0.1, 0.12), 3.0)
	for k in 7:  # насечки на затворе
		var y := y0 + 12.0 + k * 6.0
		draw_line(h + Vector2(-20, y), h + Vector2(20, y), Color(0.08, 0.08, 0.1), 2.0)
	draw_rect(Rect2(h + Vector2(-6, y0 + 2), Vector2(12, 8)), Color(0.08, 0.08, 0.1))  # целик
	draw_rect(Rect2(h + Vector2(-3, y1 - 14), Vector2(6, 8)), Color(0.08, 0.08, 0.1))  # мушка
	draw_rect(Rect2(h + Vector2(8, y0 + 70), Vector2(12, 30)), Color(0.55, 0.57, 0.6))  # окно выброса
	draw_circle(h + Vector2(0, y1 - 2), 7.0, Color(0.03, 0.03, 0.04))  # канал ствола
	# курок и флажок предохранителя — у заднего среза
	_poly(PackedVector2Array([h + Vector2(-9, -44), h + Vector2(9, -44), h + Vector2(6, -62), h + Vector2(-6, -62)]), steel, 4.0)
	_poly(PackedVector2Array([h + Vector2(-22, y0 + 20), h + Vector2(-36, y0 + 14), h + Vector2(-38, y0 + 24),
		h + Vector2(-22, y0 + 30)]), steel, 4.0)
	if muzzle > 0.0:  # вспышка: звезда пороховых газов и горячее ядро
		var m := h + Vector2(0, 150)
		Tex.blob(self, m + Vector2(0, 24), Vector2(110, 110) * muzzle, Color(1, 0.8, 0.35, 0.8 * muzzle))
		var star := PackedVector2Array()
		for k in 16:
			var a := PI / 2.0 + TAU * k / 16.0
			var r := (74.0 if k % 2 == 0 else 26.0) * muzzle * (1.2 if k == 0 else 1.0)
			star.append(m + Vector2(0, 16) + Vector2.from_angle(a) * r)
		draw_colored_polygon(star, Color(1, 0.9, 0.5, muzzle))
		draw_circle(m + Vector2(0, 16), 20.0 * muzzle, Color(1, 1, 0.9, muzzle))


func _draw_match(from: Vector2, tip: Vector2) -> void:
	draw_line(from, tip, Color(0.85, 0.7, 0.45), 7.0)
	draw_circle(tip, 8.0, Color(0.7, 0.1, 0.1))
	var fl := 1.0 + 0.2 * sin(t * 25.0)
	Tex.blob(self, tip, Vector2(60, 60) * fl, Color(1, 0.6, 0.2, 0.35))
	draw_circle(tip, 12.0 * fl, Color(1, 0.55, 0.1, 0.9))
	draw_circle(tip, 6.0 * fl, Color(1, 0.95, 0.6))
