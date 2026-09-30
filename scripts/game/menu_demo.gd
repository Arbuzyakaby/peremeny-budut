extends RefCounted
## Фон главного меню — «Вакханалия» (v12.2). Змея-демо сама охотится на всё, что бегает по ящику: медведей всех
## видов, матрёшек (раскрывает и ест малышек), таблетки и вилки (ломает сбоку — в лоб не лезет). Из угла
## подглядывает яичница. Пока змея ест, вокруг идёт своя жизнь: медведи дерутся между собой (боксёры таранят,
## метатели кидаются пуговицами, хлопушечники взрывают), вилки колют и запускают зубцы, таблетки прыгают
## и гремят ударной волной, яичница в ярости плюётся маслом.
## Раз в 6–10 секунд случается событие вакханалии (EVENTS): свалка, вилочный шквал, таблеточный пролёт,
## дождь матрёшек, ярость яичницы, хлопушки, мирный хоровод из «Контакта», фейерверк. Серия укусов подряд —
## комбо. Всё это без очков и без урона: демо-змея не ранится, а звук приглушён — меню остаётся меню.
## Пасхалка: пять тычков в яичницу — она обижается и прячется.

const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const FizzPuddle = preload("res://scripts/entities/fizz_puddle.gd")
const OilDrop = preload("res://scripts/entities/oil_drop.gd")
const Shockwave = preload("res://scripts/entities/shockwave.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Projectiles = preload("res://scripts/game/projectiles.gd")

const EGG_POKES := 5
const MAX_BEARS := 12
const MAX_DOLLS := 5
const MAX_FORKS := 3
const MAX_PILLS := 5
const MAX_DROPS := 24
const COMBO_WINDOW := 2.6
const EVENT_EVERY := Vector2(6.0, 10.0)
const QUIET := -13.0        # звуки демо тише музыки меню
const LEFT_EDGE := 560.0    # левее — доска-пульт меню: сюда враги не рождаются

## Все события вакханалии: id → подпись над полем.
const EVENTS := {
	"brawl": "МЕДВЕЖЬЯ СВАЛКА!",
	"forks": "ВИЛОЧНЫЙ ШКВАЛ!",
	"pills": "ТАБЛЕТОЧНЫЙ ПРОЛЁТ!",
	"dolls": "ДОЖДЬ ИЗ МАТРЁШЕК!",
	"egg_rage": "ЯИЧНИЦА В ЯРОСТИ!",
	"crackers": "ХЛОПУШКИ!",
	"peace": "МИРНЫЙ ХОРОВОД!",
	"salute": "ФЕЙЕРВЕРК!",
}
const EVENT_COLORS := {
	"brawl": Color(1, 0.6, 0.45), "forks": Color(0.8, 0.85, 1), "pills": Color(0.6, 0.9, 1), "dolls": Color(1, 0.7, 0.4),
	"egg_rage": Color(1, 0.5, 0.3), "crackers": Color(1, 0.85, 0.3), "peace": Color(0.6, 1, 0.65), "salute": Color(1, 0.7, 0.95),
}

var g  # game.gd
var snake: Snake
var egg: FriedEggBoss
var t := 0.0
var pokes := 0
var hide_t := 0.0  # обиженная яичница прячется
var combo := 0
var combo_t := 0.0
var best_combo := 0
var eaten := 0
var events_run := 0
var last_event := ""
var event_cd := 4.0
var brawl_cd := 3.0
var sprint_t := 0.0
var sprint_cd := 4.0
var peace: Array = []              # мирный хоровод: медведи (TeddyBear), идущие за змеёй
var peace_t := 0.0
var hearts: Node2D                 # слой над сущностями: сердечки хоровода
var refill_cd := 0.0


class HeartLayer extends Node2D:
	var demo

	func _process(_delta: float) -> void:
		if demo and not demo.peace.is_empty():
			queue_redraw()

	func _draw() -> void:
		if demo == null:
			return
		for b: TeddyBear in demo.peace:
			if is_instance_valid(b):
				var bob := sin(demo.t * 4.0 + b.get_instance_id() % 7) * 3.0
				Icons.heart(self, b.position + Vector2(0, -44.0 + bob), 8.0, Color(1, 0.45, 0.6, 0.95))


func _init(game) -> void:
	g = game
	for i in 7:
		_add_bear()
	for i in 2:
		_add_doll()
	snake = Snake.new()
	snake.bounds = g.bounds
	snake.z_index = 2
	snake.autopilot = true
	snake.auto_speed = 190.0
	snake.reset(Vector2(900, 600))
	g.world.add_child(snake)
	egg = FriedEggBoss.new()
	egg.z_index = 3
	egg.scale = Vector2(0.8, 0.8)
	egg.position = Vector2(1150, 820)
	g.world.add_child(egg)
	hearts = HeartLayer.new()
	hearts.demo = self
	hearts.z_index = 6
	g.world.add_child(hearts)
	_add_fork(Vector2(900, 200))
	_add_pill()
	_add_pill()


# ---------------------------------------------------------------- рождение

func _spot(margin := 60.0) -> Vector2:
	return Vector2(randf_range(LEFT_EDGE, 1220.0), randf_range(margin, 640.0))


func _add_bear(type := -1) -> TeddyBear:
	if g.enemies.bears.size() >= MAX_BEARS:
		return null
	var bear: TeddyBear = g.enemies.spawn_bear(randi() % 8 if type < 0 else type)
	bear.position = Vector2(randf_range(LEFT_EDGE, 1220.0), bear.position.y)
	bear.sound.disconnect(g.sfx.play)  # драки в меню — вполголоса
	bear.sound.connect(func(n: String) -> void: g.sfx.play(n, 1.0, QUIET))
	return bear


func _add_doll(at := Vector2.INF) -> Matryoshka:
	if g.enemies.dolls.size() >= MAX_DOLLS:
		return null
	var m: Matryoshka = g.enemies.spawn_doll(Matryoshka.Size.BIG, _spot(120.0) if at == Vector2.INF else at)
	m.speed *= 0.7
	return m


func _add_fork(at := Vector2.INF, kind := -1) -> Fork:
	if g.enemies.forks.size() >= MAX_FORKS:
		return null
	var f := Fork.new()
	f.z_index = 1
	f.setup(_spot() if at == Vector2.INF else at, g.bounds, 1.0, 1.0, 1.0, randi() % 3 if kind < 0 else kind)
	f.sound.connect(func(n: String) -> void: g.sfx.play(n, 1.0, QUIET))
	f.attack.connect(_on_fork_attack.bind(f))
	g.world.add_child(f)
	g.enemies.forks.append(f)
	return f


func _add_pill(at := Vector2.INF, kind := -1) -> Pill:
	if g.enemies.pills.size() >= MAX_PILLS:
		return null
	var p := Pill.new()
	p.z_index = 3
	p.setup(_spot(80.0) if at == Vector2.INF else at, g.bounds, 1.0, 1.0,
		_demo_pill_kind() if kind < 0 else kind)
	p.sound.connect(func(n: String) -> void: g.sfx.play(n, 1.0, QUIET))
	p.landed.connect(_on_pill_landed.bind(p))
	p.fizzed.connect(_on_fizzed.bind(p))
	g.world.add_child(p)
	g.enemies.pills.append(p)
	return p


# ---------------------------------------------------------------- кадр

func update(delta: float) -> void:
	t += delta
	hide_t = maxf(hide_t - delta, 0.0)
	combo_t = maxf(combo_t - delta, 0.0)
	if combo_t <= 0.0:
		combo = 0
	event_cd -= delta
	if event_cd <= 0.0:
		event_cd = randf_range(EVENT_EVERY.x, EVENT_EVERY.y)
		_random_event()
	_update_peace(delta)
	_random_grudges(delta)
	_update_bears(delta)
	_update_dolls(delta)
	_update_forks(delta)
	_update_pills(delta)
	_update_drops(delta)
	_update_waves(delta)
	_refill(delta)
	_update_hero(delta)
	_update_egg(delta)


func _closer(a: Node2D, b: Node2D) -> bool:
	return a.position.distance_to(snake.head_pos) < b.position.distance_to(snake.head_pos)


func _nearest_bear(from: Vector2, skip: Node2D = null) -> TeddyBear:
	var best: TeddyBear = null
	for b: TeddyBear in g.enemies.bears:
		if b != skip and is_instance_valid(b) and not peace.has(b) and (best == null or b.position.distance_to(from) < best.position.distance_to(from)):
			best = b
	return best


func _update_bears(delta: float) -> void:
	for bear: TeddyBear in g.enemies.bears.duplicate():
		if bear.is_queued_for_deletion() or peace.has(bear):
			continue
		bear.update(delta, null)
	for a: TeddyBear in g.enemies.bears.duplicate():  # таран: боксёр в рывке сбивает других медведей
		if not is_instance_valid(a) or a.is_queued_for_deletion() or not a.is_ramming():
			continue
		for b: TeddyBear in g.enemies.bears:
			if b != a and a.position.distance_to(b.position) < TeddyBear.RADIUS * 2.0 + 4.0:
				if _friendly_hit(b, a, (b.position - a.position).normalized() * 320.0):
					a.on_ram_hit()
					break


## Раз в несколько секунд кто-то заводит обиду на соседа — свалка тлеет всегда, а не только по событию.
func _random_grudges(delta: float) -> void:
	brawl_cd -= delta
	if brawl_cd > 0.0:
		return
	brawl_cd = randf_range(3.0, 6.0)
	var bears: Array = g.enemies.bears.filter(func(b: TeddyBear) -> bool: return not peace.has(b) and not b.has_grudge())
	if bears.size() < 2:
		return
	var a: TeddyBear = bears.pick_random()
	var b := _nearest_bear(a.position, a)
	if b:
		_grudge(a, b)


func _grudge(a: TeddyBear, b: TeddyBear) -> void:
	a.grudge = b
	a.grudge_t = 7.0
	a.attack_cd = 0.2


## Удар по медведю в демо: отброс, вскрик и «БАМ», без очков и баннера «враги дерутся между собой».
func _friendly_hit(victim: TeddyBear, attacker: Node2D, push_vel: Vector2) -> bool:
	if not victim.hit_by_friend(attacker, push_vel):
		return false
	g.fx.burst(victim.position, Color(1, 0.95, 0.6), 8)
	if randf() < 0.5:
		g.fx.popup(victim.position + Vector2(0, -40), ["БАМ!", "ХРЯСЬ!", "БУМ!", "ОЙ!", "ТРАХ!"].pick_random(), Color(1, 0.85, 0.5))
	g.add_shake(2.0)
	return true


func _update_dolls(delta: float) -> void:
	for m: Matryoshka in g.enemies.dolls:
		m.update(delta, Vector2(-9999, -9999), Vector2.ZERO, false)  # в меню малышки не нападают


func _update_forks(delta: float) -> void:
	for f: Fork in g.enemies.forks.duplicate():
		if not is_instance_valid(f) or f.is_queued_for_deletion():
			continue
		# вилки колют то змею, то ближайшего медведя — так и у медведей есть повод для драки
		var mark := snake.head_pos
		if f.get_instance_id() % 2 == 0 and not g.enemies.bears.is_empty():
			var nb := _nearest_bear(f.position)
			if nb:
				mark = nb.position
		f.update(delta, mark, true)
		if not is_instance_valid(f):
			continue
		if f.t > 26.0 and g.enemies.forks.size() > 1:  # засиделась — ломается сама
			_break_fork(f, "ЖИЗНЬ ПРОШЛА!")
			continue
		if f.is_sprinting() or f.is_whirling():
			for b: TeddyBear in g.enemies.bears:
				if f.touches(b.position, TeddyBear.RADIUS):
					_friendly_hit(b, null, f.facing() * 300.0)
		if f.touches(snake.head_pos, Snake.HEAD_RADIUS) and not snake.is_hopping():
			if f.hurts(snake.head_pos):  # в лоб змее не лезть: отскакивает без урона
				snake.push((snake.head_pos - f.position).normalized() * 480.0)
				f.bounce()
				g.fx.popup(snake.head_pos + Vector2(0, -34), ["ЧУТЬ НЕ!", "МИМО!", "ОЙ-ОЙ!"].pick_random(), Color(1, 0.7, 0.55))
			else:
				_break_fork(f, "СБОКУ!")


func _on_fork_attack(kind: String, data: Dictionary, f: Fork) -> void:
	if not is_instance_valid(f):
		return
	match kind:
		"tines":
			for d: Vector2 in data["dirs"]:
				g.shots.spawn_drop(data["from"], d * 430.0, OilDrop.Kind.TINE).thrower = f
		"pogo":
			var at: Vector2 = data["at"]
			var r: float = data["radius"]
			g.add_shake(3.0)
			g.fx.burst(at, Color(0.55, 0.36, 0.2), 12, 0.9)
			for b: TeddyBear in g.enemies.bears:
				if b.position.distance_to(at) < r + TeddyBear.RADIUS:
					_friendly_hit(b, null, (b.position - at).normalized() * 300.0)


func _break_fork(f: Fork, label: String) -> void:
	if not g.enemies.forks.has(f):
		return
	g.enemies.forks.erase(f)
	g.fx.burst(f.position, Color(0.62, 0.32, 0.14), 14)
	g.fx.burst(f.position, Color(0.8, 0.8, 0.85), 8)
	g.sfx.play("clang", 1.0, QUIET)
	g.fx.popup(f.position + Vector2(0, -34), label, Color(0.8, 0.9, 1))
	f.queue_free()
	_score_bite()
	snake.grow(1)


func _update_pills(delta: float) -> void:
	var head_vel := Vector2.from_angle(snake.heading) * Snake.BASE_SPEED
	for p: Pill in g.enemies.pills.duplicate():
		if p.is_queued_for_deletion():
			continue
		p.update(delta, snake.head_pos, head_vel, true)
	g.enemies.update_puddles(delta, snake)


static func _demo_pill_kind() -> int:
	var r := randf()
	if r < 0.2:
		return Pill.Kind.FIZZ
	return Pill.Kind.TABLET if r < 0.45 else Pill.Kind.CAPSULE


## Шипучка в демо растекается лужей тихо, без подсказки.
func _on_fizzed(pos: Vector2, p: Pill) -> void:
	if not is_instance_valid(p):
		return
	var d := FizzPuddle.new()
	d.setup(pos, p.cols[0], p.cols[2])
	g.world.add_child(d)
	g.world.move_child(d, 0)
	g.enemies.puddles.append(d)
	while g.enemies.puddles.size() > FizzPuddle.MAX_ON_FIELD:
		g.enemies.puddles.pop_front().queue_free()


## Таблетка приземлилась: капсула давит медведей под собой, шайба бьёт волной, которая оглушает всех вокруг.
func _on_pill_landed(pos: Vector2, p: Pill) -> void:
	if not is_instance_valid(p) or not g.enemies.pills.has(p):
		return
	g.fx.burst(pos, p.cols[0], 6, 0.8)
	for b: TeddyBear in g.enemies.bears:
		if b.position.distance_to(pos) < Pill.CRUSH_RADIUS + TeddyBear.RADIUS:
			_friendly_hit(b, null, (b.position - pos).normalized() * 320.0)
	if p.kind == Pill.Kind.TABLET:
		g.shots.spawn_stun_wave(pos, 240.0)
		g.sfx.play("stun", 1.0, QUIET)
		for m: Matryoshka in g.enemies.dolls:
			if m.position.distance_to(pos) < 240.0:
				m.daze(1.2)


func _update_drops(delta: float) -> void:
	var drops: Array = g.shots.drops
	while drops.size() > MAX_DROPS:
		g.shots.remove_drop(drops[0])
	for d: OilDrop in drops.duplicate():
		if d.is_queued_for_deletion():
			continue
		d.update(delta, snake.head_pos)
		if d.is_missed():  # промах лежит на полу и никого не ранит
			if d.miss_done():
				g.shots.remove_drop(d)
			continue
		if d.kind == OilDrop.Kind.CRACKER:
			if d.should_explode():
				_boom(d.position)
				g.shots.remove_drop(d)
			continue
		var hit := false
		var thrower: Node2D = d.thrower if is_instance_valid(d.thrower) else null
		for bear: TeddyBear in g.enemies.bears:
			if bear != thrower and bear.position.distance_to(d.position) < OilDrop.RADIUS + TeddyBear.RADIUS:
				_friendly_hit(bear, thrower, d.vel.normalized() * 240.0)
				hit = true
				break
		if not hit and d.position.distance_to(snake.head_pos) < OilDrop.RADIUS + Snake.HEAD_RADIUS * 0.8:
			g.fx.burst(d.position, Color(1, 0.85, 0.3), 5)
			g.fx.popup(snake.head_pos + Vector2(0, -34), "МИМО!", Color(1, 0.8, 0.5))
			hit = true
		if hit:
			g.shots.remove_drop(d)
		elif g.shots._missed(d):
			g.shots._end_flight(d)


func _boom(pos: Vector2) -> void:
	g.sfx.play("boom", 1.0, -9.0)
	g.add_shake(4.0)
	for c in Projectiles.CONFETTI:
		g.fx.burst(pos, c, 8, 1.2)
	g.fx.burst(pos, Color(1, 0.95, 0.8), 14, 1.4)
	for b: TeddyBear in g.enemies.bears.duplicate():
		if b.position.distance_to(pos) < OilDrop.BLAST_RADIUS + TeddyBear.RADIUS:
			_friendly_hit(b, null, (b.position - pos).normalized() * 380.0)
	for f: Fork in g.enemies.forks:
		if f.position.distance_to(pos) < OilDrop.BLAST_RADIUS + 20.0:
			f.bounce()
	for m: Matryoshka in g.enemies.dolls:
		if m.position.distance_to(pos) < OilDrop.BLAST_RADIUS + m.radius():
			m.daze(1.0)
	if snake.head_pos.distance_to(pos) < OilDrop.BLAST_RADIUS:
		snake.push((snake.head_pos - pos).normalized() * 420.0)


## Кольца ударных волн: бьют медведей на своём пути — таблеточные и яичницыны.
func _update_waves(delta: float) -> void:
	for w: Shockwave in g.shots.waves.duplicate():
		if w.is_queued_for_deletion():
			continue
		w.update(delta)
		for b: TeddyBear in g.enemies.bears:
			if absf(b.position.distance_to(w.position) - w.radius) < Shockwave.THICKNESS + TeddyBear.RADIUS * 0.5:
				_friendly_hit(b, null, (b.position - w.position).normalized() * 340.0)
		if w.finished():
			g.shots.waves.erase(w)
			w.queue_free()


## Поле не должно пустеть: съеденное и сломанное вскоре рождается заново.
func _refill(delta: float) -> void:
	refill_cd -= delta
	if refill_cd > 0.0:
		return
	refill_cd = 1.2
	if g.enemies.bears.size() < 7:
		_add_bear()
	if g.enemies.dolls.is_empty():
		_add_doll()
	if g.enemies.pills.size() < 2:
		_add_pill()
	if g.enemies.forks.is_empty():
		_add_fork()


# ---------------------------------------------------------------- змея-демо и яичница

func _update_hero(delta: float) -> void:
	var target: Node2D = null
	for bear: TeddyBear in g.enemies.bears:
		if bear.is_edible() and not peace.has(bear) and (target == null or _closer(bear, target)):
			target = bear
	for m: Matryoshka in g.enemies.dolls:
		if m.can_bite() and (target == null or _closer(m, target)):
			target = m
	for p: Pill in g.enemies.pills:
		if p.is_edible() and (target == null or _closer(p, target)):
			target = p
	for f: Fork in g.enemies.forks:  # вилку — только сбоку или пока она беспомощна
		if (f.is_vulnerable() or f.st == Fork.St.BALD) and (target == null or _closer(f, target)):
			target = f
	if target:
		snake.auto_target = target.position
		if target.position.distance_to(snake.head_pos) < Snake.HEAD_RADIUS + _reach(target):
			_bite(target)
	# рывок: змея прибавляет ходу, когда добыча близко
	sprint_cd -= delta
	if sprint_t > 0.0:
		sprint_t -= delta
		if sprint_t <= 0.0:
			snake.auto_speed = 190.0
	elif sprint_cd <= 0.0 and target and target.position.distance_to(snake.head_pos) < 520.0:
		sprint_cd = randf_range(5.0, 8.0)
		sprint_t = 0.7
		snake.auto_speed = 340.0
		g.fx.popup(snake.head_pos + Vector2(0, -36), "РЫВОК!", Color(0.7, 1, 0.75))
		g.sfx.play("whoosh", 1.0, QUIET)
	snake.update(delta)


func _reach(target: Node2D) -> float:
	if target is Pill:
		return Pill.RADIUS
	if target is Fork:
		return 18.0
	return 20.0


func _update_egg(delta: float) -> void:
	var peek := 700.0 + sin(t * 0.7) * 70.0  # то выглядывает, то прячется
	egg.position.y = move_toward(egg.position.y, 900.0 if hide_t > 0.0 else peek, delta * (400.0 if hide_t > 0.0 else 200.0))
	egg.look_dir = (snake.head_pos - egg.position).normalized()
	egg.update(delta, null)


## Укус демо-змеи: съесть, сломать или раскрыть. Очков нет.
func _bite(target: Node2D) -> void:
	if target is Matryoshka:
		var m: Matryoshka = target
		if m.is_last():
			g.enemies.dolls.erase(m)
			g.fx.burst(m.position, m.sarafan(), 10)
			m.queue_free()
		else:
			g.enemies.open_doll(m)
		g.sfx.play("doll_open", 1.1, QUIET + 1.0)
		if g.enemies.dolls.is_empty():
			_add_doll()
	elif target is Pill:
		var p: Pill = target
		g.enemies.pills.erase(p)
		g.fx.burst(p.position, p.cols[0], 12)
		g.fx.burst(p.position, p.cols[1], 8)
		g.sfx.play("eat", 1.3, QUIET + 1.0)
		p.queue_free()
	elif target is Fork:
		_break_fork(target as Fork, "ЗАСТРЯЛА!")
		return
	else:
		var bear: TeddyBear = target
		g.enemies.bears.erase(bear)
		peace.erase(bear)
		for other: TeddyBear in g.enemies.bears:  # обидчика съели — мстить некому
			if other.grudge == bear:
				other.grudge = null
		g.fx.burst(bear.position, bear.fur, 12)
		bear.queue_free()
		g.sfx.play("eat", 1.2, QUIET + 1.0)
		_add_bear()
	snake.grow(2)
	if snake.length > 46:  # длинная змея линяет: хвост осыпается
		var segs := snake.get_segments()
		if segs.size() > 0:
			g.fx.burst(segs[segs.size() - 1], Color(0.4, 0.85, 0.35), 10)
		snake.length = 14
	egg.flash = 0.6
	_score_bite()


## Серия укусов подряд — комбо: с третьего звена — надпись, на кратных пяти — салют.
func _score_bite() -> void:
	eaten += 1
	combo += 1
	combo_t = COMBO_WINDOW
	best_combo = maxi(best_combo, combo)
	if combo >= 3:
		g.fx.popup(snake.head_pos + Vector2(0, -60), "КОМБО ×%d!" % combo, Color(1, 0.85, 0.35))
	if combo % 5 == 0:
		_salute()


# ---------------------------------------------------------------- события вакханалии

func _random_event() -> void:
	var pool: Array = EVENTS.keys().filter(func(e: String) -> bool: return e != last_event)
	run_event(pool.pick_random())


## Запустить событие по id (случайное по таймеру, из панели разработчика — по кнопке). false — нет такого.
func run_event(id: String) -> bool:
	if not EVENTS.has(id):
		return false
	last_event = id
	events_run += 1
	g.fx.popup(Vector2(900, 100), EVENTS[id], EVENT_COLORS[id])
	g.sfx.play("warn", 0.9, QUIET)
	match id:
		"brawl":
			_ev_brawl()
		"forks":
			_ev_forks()
		"pills":
			_ev_pills()
		"dolls":
			_ev_dolls()
		"egg_rage":
			_ev_egg_rage()
		"crackers":
			_ev_crackers()
		"peace":
			_ev_peace()
		"salute":
			_salute()
	return true


## Кольцо обид: каждый медведь мстит следующему.
func _ev_brawl() -> void:
	var ring: Array = g.enemies.bears.filter(func(b: TeddyBear) -> bool: return not peace.has(b))
	ring.shuffle()
	ring = ring.slice(0, 5)
	for i in ring.size():
		_grudge(ring[i], ring[(i + 1) % ring.size()])


func _ev_forks() -> void:
	for i in MAX_FORKS:
		var side := 1.0 if i % 2 == 0 else -1.0
		var f := _add_fork(Vector2(clampf(900.0 + side * 240.0 * (i + 1) / 2.0, LEFT_EDGE + 40.0, 1220.0), 40.0 if i % 2 == 0 else 680.0))
		if f:
			f.attack_cd = 0.3 + i * 0.4


func _ev_pills() -> void:
	for i in 4:
		var p := _add_pill(Vector2(randf_range(LEFT_EDGE, 1220.0), 50.0), Pill.Kind.TABLET if i % 2 == 1 else Pill.Kind.CAPSULE)
		if p:
			p.st_t = 0.2 * i


func _ev_dolls() -> void:
	for i in 3:
		_add_doll(Vector2(randf_range(700.0, 1200.0), 60.0 + i * 30.0))


## Яичница плюётся маслом по кругу и бьёт сковородной волной.
func _ev_egg_rage() -> void:
	hide_t = 0.0
	egg.flash = 1.0
	g.sfx.play("roar", 1.0, QUIET)
	g.add_shake(4.0)
	for i in 10:
		g.shots.spawn_drop(egg.position + Vector2(0, -120), Vector2.from_angle(-PI + PI * (i + 0.5) / 10.0) * 320.0, OilDrop.Kind.OIL)
	g.shots.spawn_boss_wave(egg.position + Vector2(0, -80), 3)
	g.fx.popup(egg.position + Vector2(-90, -190), "ШКВОРЧИТ!", Color(1, 0.75, 0.4))


## Двое хлопушечников берут на прицел обидчиков — по полю летят и рвутся хлопушки.
func _ev_crackers() -> void:
	for i in 2:
		var bomber := _add_bear(TeddyBear.Type.BOMBER)
		if bomber == null:  # поле забито — превращаем уже существующих
			for b: TeddyBear in g.enemies.bears:
				if b.type != TeddyBear.Type.BOMBER:
					bomber = b
					b.type = TeddyBear.Type.BOMBER
					break
		if bomber == null:
			continue
		var victim := _nearest_bear(bomber.position, bomber)
		if victim:
			bomber.grudge = victim
			bomber.grudge_t = 8.0
			bomber.attack_cd = 0.3


## Технический режим «Контакт» в гостях: пара медведей мирно идёт за змеёй хороводом, над головами — сердечки.
func _ev_peace() -> void:
	peace.clear()
	for b: TeddyBear in g.enemies.bears:
		if peace.size() < 4 and not b.has_grudge() and not b.is_shielded():
			peace.append(b)
	peace_t = 8.0
	for b: TeddyBear in peace:
		b.grudge = null
	g.sfx.play("hiss", 1.0, QUIET)


func _update_peace(delta: float) -> void:
	if peace.is_empty():
		return
	peace_t -= delta
	peace = peace.filter(func(b: TeddyBear) -> bool: return is_instance_valid(b) and not b.is_queued_for_deletion())
	var segs: PackedVector2Array = snake.get_segments()
	for i in peace.size():
		var goal: Vector2 = segs[mini(6 + i * 4, segs.size() - 1)] if segs.size() > 0 else snake.head_pos
		var b: TeddyBear = peace[i]
		var to: Vector2 = goal - b.position
		var want := to.normalized() * minf(to.length() * 2.5, 200.0) if to.length() > 12.0 else Vector2.ZERO
		b.calm_update(delta, want)
	if peace_t <= 0.0:
		g.fx.popup(snake.head_pos + Vector2(0, -50), "ХОРОВОД РАСПАЛСЯ", Color(0.75, 1, 0.8))
		peace.clear()


## Салют: несколько разноцветных вспышек над ящиком.
func _salute() -> void:
	for i in 5:
		var at := Vector2(randf_range(LEFT_EDGE + 40.0, 1220.0), randf_range(90.0, 420.0))
		var col: Color = Projectiles.CONFETTI.pick_random()
		g.fx.burst(at, col, 14, 1.3)
		g.fx.burst(at, Color(1, 0.95, 0.8), 8, 1.0)
	g.sfx.play("power", 1.2, QUIET)
	g.sfx.play("boom", 1.6, QUIET - 4.0)
	egg.flash = 0.8


# ---------------------------------------------------------------- пасхалка и уборка

## Тычок мышью или пальцем в мировой точке: попали в яичницу — считаем. Возвращает true, если попали.
func poke(world_pos: Vector2) -> bool:
	if hide_t > 0.0 or world_pos.distance_to(egg.position) > FriedEggBoss.WHITE_RADIUS * egg.scale.x:
		return false
	pokes += 1
	egg.flash = 0.8
	g.sfx.play("splat", 1.4, -8.0)
	if pokes >= EGG_POKES:
		pokes = 0
		hide_t = 3.5
		g.fx.popup(egg.position + Vector2(-120, -170), "НЕ ТРОГАЙ, Я НЕ ДОЖАРИЛАСЬ!", Color(1, 0.85, 0.4))
		g.found_secret("egg_poke")
	return true


func clear() -> void:
	peace.clear()
	g.enemies.clear(false)
	g.shots.clear()
	hearts.queue_free()
	snake.queue_free()
	egg.queue_free()
