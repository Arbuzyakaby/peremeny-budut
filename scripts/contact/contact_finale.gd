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
	tracers.append({"a": from, "b": target, "life": 0.12})
	g.sfx.play("gunshot", randf_range(0.95, 1.05))
	g.add_shake(7.0)
	var tw := create_tween()
	tw.tween_interval(BULLET_TIME)
	tw.tween_callback(_impact.bind(target, victim))


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
	if hand.y > -500.0:
		_draw_hand()


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


## Рука учёного сверху: рукав халата от верхнего края, ладонь, пальцы; спичка или пистолет.
func _draw_hand() -> void:
	var h := hand
	var sleeve_top := Vector2(h.x + 160.0, -900.0)
	for pass_i in 2:
		var col := LINE if pass_i == 0 else COAT
		var w := 190.0 if pass_i == 0 else 168.0
		draw_line(sleeve_top, h + Vector2(40, -80), col, w)
	draw_line(h + Vector2(30, -110), h + Vector2(10, -40), Color(0.97, 0.97, 0.98), 150.0)  # манжета
	if holding == "gun":
		var barrel := h + Vector2(0, 150)
		draw_rect(Rect2(h + Vector2(-30, -10), Vector2(60, 170)), LINE)
		draw_rect(Rect2(h + Vector2(-22, 0), Vector2(44, 150)), Color(0.22, 0.23, 0.26))
		draw_rect(Rect2(h + Vector2(-8, 20), Vector2(8, 110)), Color(0.4, 0.42, 0.46))
		if muzzle > 0.0:
			Tex.blob(self, barrel + Vector2(0, 20), Vector2(90, 90) * muzzle, Color(1, 0.85, 0.4, 0.9 * muzzle))
			for k in 5:
				var d := Vector2.from_angle(PI / 2.0 + (k - 2) * 0.35)
				draw_line(barrel, barrel + d * 70.0 * muzzle, Color(1, 0.95, 0.6, muzzle), 6.0)
	draw_circle(h, 86.0, LINE)
	draw_circle(h, 76.0, SKIN)
	for k in 4:
		var f := h + Vector2.from_angle(PI * 0.3 + k * 0.42) * 76.0
		draw_circle(f, 30.0, LINE)
		draw_circle(f, 24.0, SKIN)
	var thumb := h + Vector2(-80, -20)
	draw_circle(thumb, 32.0, LINE)
	draw_circle(thumb, 26.0, SKIN)
	if holding == "match":
		_draw_match(h + Vector2(-40, 40), h + Vector2(-40, 110))


func _draw_match(from: Vector2, tip: Vector2) -> void:
	draw_line(from, tip, Color(0.85, 0.7, 0.45), 7.0)
	draw_circle(tip, 8.0, Color(0.7, 0.1, 0.1))
	var fl := 1.0 + 0.2 * sin(t * 25.0)
	Tex.blob(self, tip, Vector2(60, 60) * fl, Color(1, 0.6, 0.2, 0.35))
	draw_circle(tip, 12.0 * fl, Color(1, 0.55, 0.1, 0.9))
	draw_circle(tip, 6.0 * fl, Color(1, 0.95, 0.6))
