extends RefCounted
## Скрытый технический режим «Контакт» (v10.0). Открывается после финала: образец №48 (змейка из
## яйца) пересажен в чистый ящик, и курсор в фальшивом меню сам нажимает «НОВАЯ ИГРА».
## Этапы те же — медведи, вилки, таблетки, матрёшки, яичница, — но никто никого не ест.
## Змея подползает к врагу, встаёт на дыбы (атака), шипит и рисует на полу его знак (gesture.gd):
## игрок обводит контур мышью, пальцем или ведёт кисть стрелками. Точно — змея прорисовывает знак
## телом, враг убеждён и идёт следом; мимо — враг пугается. Убеждённые переходят на следующий этап
## вместе со змеёй и помогают: мирный отряд (peace_squad.gd) ведёт их вестниками к сородичам.
## Неубеждённые насторожены, но не бьют; смерти в режиме нет. Когда убеждена и яичница — финал
## (contact_finale.gd): все выбираются из ящика, учёный поджигает его и стреляет; выживают змея и
## медведь-швея (hideout.gd).

const Balance = preload("res://scripts/core/balance.gd")
const Design = preload("res://scripts/ui/design.gd")
const SaveData = preload("res://scripts/core/save_data.gd")
const Gesture = preload("res://scripts/contact/gesture.gd")
const PeaceSquad = preload("res://scripts/contact/peace_squad.gd")
const FloorPaint = preload("res://scripts/contact/floor_paint.gd")
const ContactView = preload("res://scripts/contact/contact_view.gd")
const ContactFinale = preload("res://scripts/contact/contact_finale.gd")
const Hideout = preload("res://scripts/contact/hideout.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")

enum Phase { ROAM, TRACE, PAINT, HISS, BETWEEN, FINALE, HIDEOUT, DONE }

const KINDS := ["bear", "fork", "pill", "doll", "egg"]
const TALK_RADIUS := 150.0
const EGG_TALK_RADIUS := 270.0
const FIGURE_HALF := 115.0
const EGG_FIGURE_HALF := 150.0
const TRACE_TIME := 10.0
const KEY_SPEED := 230.0         # кисть на клавиатуре бежит по контуру сама…
const KEY_DRIFT := Vector2(90.0, 60.0)  # …и её сносит (px/с, две синусоиды) — держи стрелками
const KEY_STEER := 170.0
const KEY_MAX_OFF := 90.0
const PAINT_SPEED := 480.0
const HISS_TIME := 0.9
const BETWEEN_TIME := 2.4
const FAIL_TRUST := 0.2
const FAIL_SCARE := 1.6
const COLORS := {
	"bear": Color(1.0, 0.5, 0.6), "fork": Color(0.55, 0.8, 1.0), "pill": Color(1.0, 0.85, 0.3),
	"doll": Color(1.0, 0.55, 0.25), "egg": Color(1.0, 0.95, 0.6),
}
const CONVINCED := {
	"bear": ["МЕДВЕДЬ ПОНЯЛ!", "ОБНИМАШКИ!", "ПЛЮШЕВЫЙ МИР!"],
	"fork": ["ВИЛКА ЗА НАС!", "ЗУБЦЫ ВНИЗ!", "БЕЗ УКОЛОВ!"],
	"pill": ["ТАБЛЕТКА ЗА НАС!", "БЕЗ ПРЫЖКОВ!", "ДОЗА ДРУЖБЫ!"],
	"doll": ["МАТРЁШКА ЗА НАС!", "ВСЕ ВНУТРИ СОГЛАСНЫ!", "ХОРОВОД МИРА!"],
	"egg": ["ЯИЧНИЦА ЗА НАС!"],
}
const STAGE_LINES := [
	"Медведи насторожены. Подползи к медведю и встань на дыбы — нарисуй ему СЕРДЦЕ.",
	"Вилки косятся. Медведи помогут: вестники идут к вилкам первыми. Вилке — ВОЛНА.",
	"Таблетки прыгают в стороны. Таблетке — знак БЕСКОНЕЧНОСТИ.",
	"Матрёшки держатся вместе. Матрёшке — СПИРАЛЬ.",
	"Яичница. Вся компания с тобой. Нарисуй ей СОЛНЦЕ.",
]

var g  # game.gd
var stage := 0
var phase := Phase.ROAM
var entries: Array = []   # {node, kind, convinced, trust, scared, speed, protected, r, want}
var peace := PeaceSquad.new()
var view: ContactView
var paint: FloorPaint
var finale: ContactFinale
var hideout: Hideout
var goal := 0
var done := 0
var t := 0.0
var history := PackedVector2Array()
var candidate: Dictionary = {}
var talking: Dictionary = {}
var tmpl := PackedVector2Array()
var trace := PackedVector2Array()
var trace_mode := ""      # mouse, touch, keys, auto
var trace_t := 0.0
var live: Dictionary = {}  # последняя оценка обводки (для рисунка: сколько обведено)
var live_t := 0.0
var key_s := 0.0
var key_off := 0.0
var paint_path := PackedVector2Array()
var paint_s := 0.0
var paint_from := 0.0     # сколько пути — подход к началу знака (не рисуется)
var phase_t := 0.0
var fails := 0
var counts := {"bear": 0, "fork": 0, "pill": 0, "doll": 0, "egg": 0}
var prompt_on := false
var egg: FriedEggBoss


func _init(game) -> void:
	g = game


func start() -> void:
	paint = FloorPaint.new()
	g.world.add_child(paint)
	view = ContactView.new()
	view.contact = self
	view.z_index = 20
	g.world.add_child(view)
	g.sfx.play_music("menu")
	enter_stage(0)


func enter_stage(i: int) -> void:
	stage = i
	done = 0
	phase = Phase.ROAM
	g.stage = i
	var st: Dictionary = Balance.STAGES[i]
	g.arena.set_floor(st["floor"])
	if i == Balance.BOSS_STAGE:
		goal = 1
		_spawn_egg()
	else:
		goal = Balance.CONTACT_GOALS[i]
		_spawn_stage(i)
	g.hud.set_goal(i, 0, goal)
	g.hud.show_banner("КОНТАКТ %d/%d: %s" % [i + 1, Balance.STAGE_COUNT, st["name"]], COLORS[KINDS[i]], 2.0)
	g.hint(STAGE_LINES[i], 5.0)


func _spawn_stage(i: int) -> void:
	var e = g.enemies
	match i:
		0:
			var types := [TeddyBear.Type.SEAMSTRESS, TeddyBear.Type.NORMAL, TeddyBear.Type.BOXER, TeddyBear.Type.THROWER,
				TeddyBear.Type.MEDIC, TeddyBear.Type.KARATE, TeddyBear.Type.NINJA, TeddyBear.Type.BOMBER]
			for k in goal:
				var b: TeddyBear = e.spawn_bear(types[k % types.size()])
				var keep: bool = b.type == TeddyBear.Type.SEAMSTRESS and seamstress().is_empty()  # выживет одна швея
				_add(b, "bear", maxf(b.speed, 60.0), keep, TeddyBear.RADIUS)
		1:
			var kinds := [Fork.Kind.TABLE, Fork.Kind.DESSERT, Fork.Kind.PITCH, Fork.Kind.TABLE]
			for k in goal:
				_add(e.spawn_fork(Vector2.INF, kinds[k % kinds.size()]), "fork", 90.0, false, 30.0)
		2:
			for k in goal:
				_add(e.spawn_pill(Vector2.INF, [Pill.Kind.CAPSULE, Pill.Kind.TABLET, Pill.Kind.FIZZ][k % 3]), "pill", 110.0, false, Pill.RADIUS)
		Balance.DOLL_STAGE:
			for k in goal:
				var m: Matryoshka = e.spawn_doll(Matryoshka.Size.BIG)
				_add(m, "doll", maxf(m.speed, 50.0), false, m.radius())


func _spawn_egg() -> void:
	egg = FriedEggBoss.new()
	egg.bounds = g.bounds
	egg.configure(1, 1.0, 1.0, 1.0)
	egg.active = false
	egg.z_index = 0
	egg.position = Vector2(640, -300)
	g.world.add_child(egg)
	g.boss = egg
	g.sfx.play("phase")
	var tw: Tween = g.create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(egg, "position", Vector2(640, 260), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		g.add_shake(16.0)
		g.sfx.play("slam")
		g.fx.burst(egg.position, Color(1, 1, 0.9), 30)
		_add(egg, "egg", 70.0, false, FriedEggBoss.WHITE_RADIUS))


func _add(node: Node2D, kind: String, speed: float, protected: bool, r: float) -> void:
	entries.append({"node": node, "kind": kind, "convinced": false, "trust": 0.0, "scared": 0.0, "speed": speed,
		"protected": protected, "r": r, "want": Vector2.ZERO})


# ---------------------------------------------------------------- цикл

func update(delta: float) -> void:
	t += delta
	phase_t += delta
	var snake = g.snake
	if phase == Phase.HIDEOUT or phase == Phase.DONE:
		return
	if history.is_empty() or history[0].distance_to(snake.head_pos) > 12.0:
		history.insert(0, snake.head_pos)
		if history.size() > 400:
			history.resize(400)
	match phase:
		Phase.ROAM, Phase.BETWEEN:
			snake.rear = move_toward(snake.rear, 0.0, delta * 4.0)
			if g.autopilot:
				_autodrive()
			snake.update(delta)
			if phase == Phase.ROAM:
				_find_candidate()
				if g.autopilot and not candidate.is_empty():
					talk("auto")
			elif phase_t >= BETWEEN_TIME:
				if stage + 1 < Balance.STAGE_COUNT:
					enter_stage(stage + 1)
				else:
					start_finale()
		Phase.TRACE:
			_face(snake)
			snake.rear = move_toward(snake.rear, 1.0, delta * 5.0)
			snake.update(delta)
			_update_trace(delta)
		Phase.PAINT:
			snake.rear = 0.0
			_update_paint(delta)
		Phase.HISS:
			_face(snake)
			snake.rear = move_toward(snake.rear, 1.0, delta * 6.0)
			snake.update(delta)
			if phase_t >= HISS_TIME:
				convince(talking)
		Phase.FINALE:
			snake.rear = move_toward(snake.rear, 0.0, delta * 4.0)
			if g.autopilot:
				snake.autopilot = true
				snake.auto_speed = 260.0
				snake.auto_target = finale.autopilot_target()
			if not finale.controls_snake():
				snake.update(delta)
			finale.update(delta)
			move_entities(delta)
			view.queue_redraw()
			return
	var calm: bool = not snake.sprinting
	peace.update(delta, snake.head_pos, calm, history, entries, talking.get("node"))
	move_entities(delta)
	_update_prompt()
	view.queue_redraw()


## Каждая сущность делает мирный шаг со своей скоростью want (яичницу двигаем сами).
func move_entities(delta: float) -> void:
	for e: Dictionary in entries:
		var node: Node2D = e["node"]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var want: Vector2 = e.get("want", Vector2.ZERO)
		match e["kind"]:
			"bear":
				node.calm_update(delta, want)
			"fork":
				var look: Vector2 = g.snake.head_pos if not e["convinced"] else Vector2.INF
				node.calm_update(delta, want, look)
			"pill", "doll":
				node.calm_update(delta, want)
			"egg":
				var b: FriedEggBoss = node
				b.update(delta, g.snake)  # неактивная — только анимация
				var inner: Rect2 = g.bounds.grow(-FriedEggBoss.WHITE_RADIUS * 0.6)
				b.position = (b.position + want * delta).clamp(inner.position, inner.end)
				b.look_dir = (g.snake.head_pos - b.position).normalized()
	entries = entries.filter(func(e: Dictionary) -> bool: return is_instance_valid(e["node"]))


## Автопилот (отладка и тесты): ползти к ближайшему неубеждённому.
func _autodrive() -> void:
	var snake = g.snake
	snake.autopilot = true
	snake.auto_speed = 240.0
	var best := INF
	for e: Dictionary in entries:
		if e["convinced"]:
			continue
		var d: float = e["node"].position.distance_to(snake.head_pos)
		if d < best:
			best = d
			snake.auto_target = e["node"].position
	if best == INF:
		snake.auto_target = g.bounds.get_center()


func _face(snake) -> void:
	var node: Node2D = talking.get("node")
	if is_instance_valid(node):
		snake.heading = rotate_toward(snake.heading, (node.position - snake.head_pos).angle(), 0.2)


## Ближайший неубеждённый, с которым можно заговорить.
func _find_candidate() -> void:
	candidate = {}
	var head: Vector2 = g.snake.head_pos
	var best := INF
	for e: Dictionary in entries:
		if e["convinced"] or not is_instance_valid(e["node"]):
			continue
		var reach := EGG_TALK_RADIUS if e["kind"] == "egg" else TALK_RADIUS
		var d: float = e["node"].position.distance_to(head)
		if d < reach and d < best:
			best = d
			candidate = e


func _update_prompt() -> void:
	var want := phase == Phase.ROAM and not candidate.is_empty()
	if want == prompt_on:
		return
	prompt_on = want
	if want:
		g.hud.show_prompt("Кнопка атаки — заговорить" if g.touch_on() else "ПРОБЕЛ / ЛКМ — встать на дыбы и заговорить")
	else:
		g.hud.hide_prompt()


# ---------------------------------------------------------------- разговор: обводка знака

## Атака в «Контакте» — встать на дыбы и заговорить. via: mouse, touch, keys, auto.
func talk(via: String) -> void:
	if phase != Phase.ROAM:
		return
	_find_candidate()
	if candidate.is_empty():
		g.fx.popup(g.snake.head_pos + Vector2(0, -40), "ШШ? РЯДОМ НИКОГО", Design.MUTED)
		return
	talking = candidate
	var node: Node2D = talking["node"]
	var head: Vector2 = g.snake.head_pos
	var half := EGG_FIGURE_HALF if talking["kind"] == "egg" else FIGURE_HALF
	var center := head.lerp(node.position, 0.5)
	if talking["kind"] == "egg":
		center = head.lerp(node.position, 0.25)
	var room: Rect2 = g.bounds.grow(-half - 18.0)
	tmpl = Gesture.template(talking["kind"], center.clamp(room.position, room.end), half)
	trace = PackedVector2Array()
	trace_mode = "auto" if g.autopilot else via
	trace_t = 0.0
	live = {}
	key_s = 0.0
	key_off = 0.0
	phase = Phase.TRACE
	phase_t = 0.0
	g.snake.hiss_t = 0.6
	g.sfx.play("hiss", 1.1, -4.0)
	g.hud.hide_prompt()
	prompt_on = false
	match trace_mode:
		"mouse":
			g.hud.show_prompt("Обведи знак мышью: зажми ЛКМ и веди по контуру")
		"touch":
			g.hud.show_prompt("Обведи знак пальцем по контуру")
		"keys":
			g.hud.show_prompt("Кисть бежит сама — держи её на контуре стрелками ← →")


func _update_trace(delta: float) -> void:
	trace_t += delta
	match trace_mode:
		"auto":
			var n := int(clampf(trace_t / 1.0, 0.0, 1.0) * (tmpl.size() - 1))
			trace = tmpl.slice(0, n + 1)
			if trace_t >= 1.05:
				_finish_trace()
				return
		"keys":
			var total := Gesture.length(tmpl)
			key_s = minf(key_s + KEY_SPEED * delta, total)
			var drift := KEY_DRIFT.x * sin(trace_t * 1.7 + 0.6) + KEY_DRIFT.y * sin(trace_t * 3.1)
			var axis := Input.get_axis("turn_left", "turn_right")
			key_off = clampf(key_off + (drift - axis * KEY_STEER) * delta, -KEY_MAX_OFF, KEY_MAX_OFF)
			trace.append(brush_pos())
			if key_s >= total:
				_finish_trace()
				return
	live_t -= delta
	if live_t <= 0.0 and trace.size() > 4:
		live_t = 0.2
		live = Gesture.score(trace, tmpl, tol())
		if trace_mode in ["mouse", "touch"] and live["ok"] and float(live["coverage"]) >= 0.97:
			_finish_trace()
			return
	if trace_t >= TRACE_TIME:
		_finish_trace()


## Кисть на клавиатуре: точка контура плюс снос поперёк (влево от хода — плюс).
func brush_pos() -> Vector2:
	var p := Gesture.point_at(tmpl, key_s)
	var ahead := Gesture.point_at(tmpl, key_s + 6.0)
	var tan := (ahead - p).normalized() if ahead != p else Vector2.RIGHT
	return p + tan.orthogonal() * key_off


func tol() -> float:
	return Gesture.tol_for(g.difficulty)


## Точка обводки от мыши или пальца (мировые координаты).
func add_trace_point(p: Vector2) -> void:
	if phase != Phase.TRACE or trace_mode not in ["mouse", "touch"]:
		return
	if trace.is_empty() or trace[trace.size() - 1].distance_to(p) > 2.0:
		trace.append(p)


## Отпустили кнопку или палец: хватит длины — оценить, иначе начать заново.
func end_stroke() -> void:
	if phase != Phase.TRACE or trace_mode not in ["mouse", "touch"]:
		return
	if Gesture.length(trace) >= Gesture.length(tmpl) * 0.5:
		_finish_trace()
	else:
		trace = PackedVector2Array()
		live = {}


func _finish_trace() -> void:
	var res := Gesture.score(trace, tmpl, tol())
	g.hud.hide_prompt()
	if res["ok"] or trace_mode == "auto":
		_start_paint()
		return
	fails += 1
	var node: Node2D = talking["node"]
	talking["trust"] = maxf(float(talking["trust"]) - FAIL_TRUST, 0.0)
	talking["scared"] = FAIL_SCARE
	g.sfx.play("bonk", 0.8)
	g.fx.popup(node.position + Vector2(0, -40), "НЕ ПОНЯЛ… (%d%%)" % int(float(res["coverage"]) * 100.0), Color(1, 0.6, 0.5))
	if fails == 2:
		g.hint("Веди точно по светящемуся контуру: засчитывается, когда обведено почти всё.", 4.0)
	talking = {}
	trace = PackedVector2Array()
	phase = Phase.ROAM
	phase_t = 0.0


## Змея прорисовывает знак телом: подползает к началу контура и ползёт по нему, оставляя борозду.
func _start_paint() -> void:
	var head: Vector2 = g.snake.head_pos
	var path := tmpl.duplicate()
	var closed := path[0].distance_to(path[path.size() - 1]) < 4.0
	var nearest := 0
	for i in path.size():
		if path[i].distance_to(head) < path[nearest].distance_to(head):
			nearest = i
	if closed:  # замкнутый знак начинаем с ближайшей точки
		var rotated := path.slice(nearest)
		rotated.append_array(path.slice(1, nearest + 1))
		path = rotated
	elif head.distance_to(path[path.size() - 1]) < head.distance_to(path[0]):
		path.reverse()
	paint_path = PackedVector2Array([head])
	paint_path.append_array(path)
	paint_from = head.distance_to(path[0])
	paint_s = 0.0
	paint.begin(COLORS[talking["kind"]])
	g.snake.autopilot = false
	g.snake.rear = 0.0
	phase = Phase.PAINT
	phase_t = 0.0
	g.sfx.play("scribble", 1.4, -8.0)


func _update_paint(delta: float) -> void:
	paint_s += PAINT_SPEED * delta
	var p := Gesture.point_at(paint_path, paint_s)
	g.snake.glide_to(p, delta)
	if paint_s >= paint_from:
		paint.extend(p)
	if paint_s >= Gesture.length(paint_path):
		phase = Phase.HISS
		phase_t = 0.0
		g.snake.hiss_t = HISS_TIME + 0.3
		g.sfx.play("hiss", 1.0)
		g.fx.popup(g.snake.head_pos + Vector2(0, -44), "Ш-Ш-Ш-Ш!", Color(0.7, 1, 0.6))


## Враг убеждён: идёт следом за змеёй.
func convince(e: Dictionary) -> void:
	if e.is_empty() or e["convinced"]:
		return
	e["convinced"] = true
	e["trust"] = 1.0
	var node: Node2D = e["node"]
	var kind: String = e["kind"]
	counts[kind] = int(counts[kind]) + 1
	done += 1
	talking = {}
	phase = Phase.ROAM
	phase_t = 0.0
	g.snake.hiss_t = 0.0
	g.hud.set_goal(stage, done, goal)
	g.fx.burst(node.position, COLORS[kind], 18)
	g.fx.popup(node.position + Vector2(0, -e["r"] - 24.0), (CONVINCED[kind] as Array).pick_random(), COLORS[kind])
	g.sfx.play("scale")
	g.sfx.play("secret", 0.8, -8.0)
	g.vibrate(40)
	if kind == "egg":
		g.sfx.play("win", 0.8, -4.0)
	if done >= goal:
		_stage_done()


func _stage_done() -> void:
	phase = Phase.BETWEEN
	phase_t = 0.0
	g.sfx.play("stage_clear")
	var lines := ["ВСЕ МЕДВЕДИ С ТОБОЙ!", "ВИЛКИ ПЕРЕШЛИ НА НАШУ СТОРОНУ!", "ТАБЛЕТКИ ЗА НАС!", "МАТРЁШКИ ЗА НАС!",
		"ЯИЧНИЦА С НАМИ!"]
	g.hud.show_banner(lines[stage], Color(0.6, 1, 0.5), 1.8)


# ---------------------------------------------------------------- финал

func start_finale() -> void:
	phase = Phase.FINALE
	phase_t = 0.0
	g.hud.hide_prompt()
	prompt_on = false
	finale = ContactFinale.new()
	finale.contact = self
	finale.g = g
	finale.z_index = 30
	g.world.add_child(finale)
	finale.begin()


## Убрать сущность с поля (сгорела или подстрелена в финале).
func kill(e: Dictionary, how: String) -> void:
	var node: Node2D = e["node"]
	if not is_instance_valid(node) or node.is_queued_for_deletion() or e.get("dead", false):
		return
	e["dead"] = true
	entries.erase(e)
	match e["kind"]:
		"bear":
			g.enemies.bears.erase(node)
		"fork":
			g.enemies.forks.erase(node)
		"pill":
			g.enemies.pills.erase(node)
		"doll":
			g.enemies.dolls.erase(node)
	if node == egg:
		g.boss = null
	g.fx.burst(node.position, Color(0.15, 0.12, 0.1) if how == "fire" else Color(1, 0.85, 0.5), 14 if e["kind"] != "egg" else 40)
	var tw: Tween = node.create_tween()
	tw.tween_property(node, "modulate", Color(0.2, 0.16, 0.14, 1.0) if how == "fire" else Color(1, 1, 1, 1), 0.25)
	tw.tween_property(node, "scale", Vector2(1.1, 0.2) if how == "fire" else Vector2(0.2, 0.2), 0.35)
	tw.parallel().tween_property(node, "modulate:a", 0.0, 0.35)
	tw.tween_callback(node.queue_free)


func survivors() -> Array:
	return entries.filter(func(e: Dictionary) -> bool: return is_instance_valid(e["node"]) and not e.get("dead", false))


func seamstress() -> Dictionary:
	for e: Dictionary in entries:
		if e["protected"] and not e.get("dead", false):
			return e
	return {}


func start_hideout() -> void:
	phase = Phase.HIDEOUT
	hideout = Hideout.new()
	g.add_child(hideout)
	hideout.finished.connect(finish)
	hideout.start(g, self)


func in_cutscene() -> bool:
	return phase == Phase.HIDEOUT


func skip() -> void:
	if hideout:
		hideout.skip()


func finish() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	if not g.debug_run:
		var old: Dictionary = SaveData.read_section("contact")
		SaveData.write_section("contact", {"runs": int(old.get("runs", 0)) + 1,
			"convinced": int(old.get("convinced", 0)) + convinced_total()})
	g.found_secret("contact")
	g.contact_done(self)


func convinced_total() -> int:
	var n := 0
	for k in counts:
		n += int(counts[k])
	return n


## Отладка (--contact-finale, панель разработчика): все убеждены, сразу к финалу.
func debug_skip_to_finale() -> void:
	for e: Dictionary in entries:
		e["node"].queue_free()
	entries.clear()
	g.enemies.bears.clear()
	g.enemies.forks.clear()
	g.enemies.pills.clear()
	g.enemies.dolls.clear()
	for i in Balance.BOSS_STAGE:
		stage = i
		goal = Balance.CONTACT_GOALS[i]
		_spawn_stage(i)
	for e: Dictionary in entries:
		e["convinced"] = true
		e["trust"] = 1.0
		counts[e["kind"]] = int(counts[e["kind"]]) + 1
	stage = Balance.BOSS_STAGE
	g.stage = stage
	goal = 1
	done = 0
	g.arena.set_floor(Balance.STAGES[stage]["floor"])
	_spawn_egg()
	egg.position = Vector2(640, 260)
	g.get_tree().create_timer(2.0).timeout.connect(func() -> void:
		for e: Dictionary in entries:
			if e["kind"] == "egg":
				convince(e))
