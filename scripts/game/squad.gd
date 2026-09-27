extends RefCounted
## Кооперативный ИИ врагов на Сложной (coop = 1) и Ультра-Хардкоре (coop = 2). Раз в четверть секунды
## смотрит на поле целиком и раздаёт приказы:
## - КЛЕЩИ: две вилки (на Ультра — три) расходятся по бокам от змеи и бьют выпадом одновременно;
## - СПАСЕНИЕ: ближайший медведь бежит к застрявшей вилке и выдёргивает её быстрее;
## - ПРИКРЫТИЕ: медведь встаёт между змеёй и беззащитной вилкой (оглушённой, беззубой);
## - ПЕРЕКРЁСТНЫЙ ОГОНЬ: метатели целятся туда, куда змею отбросит выпад вилки;
## - ЗАГОН: таблетки прыгают со стороны, противоположной вилкам, — змея бежит прямо на зубцы;
## - ЩИТ ЯИЧНИЦЫ: когда желток открыт, медведи-подкрепления заслоняют его собой;
## - ЦЕПОЧКА (только Ультра): когда один медведь атакует, соседи подхватывают атаку следом.
## На Лёгкой и Нормальной (coop = 0) ничего не делает.

const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Tips = preload("res://scripts/core/tips.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")

const TICK := 0.25
const PINCER_RADIUS := 250.0
const PINCER_TIMEOUT := 2.6

var d  # enemy_director.gd — только на время update(): постоянная ссылка дала бы цикл и утечку
var level := 0
var tick_t := 0.0
var pincer: Array = []   # вилки, которые сейчас заходят в клещи
var pincer_t := 0.0
var pincer_cd := 2.0
var hinted := false
var stats := {"pincer": 0, "rescue": 0, "guard": 0, "crossfire": 0, "herd": 0, "chain": 0, "boss_guard": 0}


func reset() -> void:
	pincer.clear()
	pincer_t = 0.0
	pincer_cd = 2.0
	tick_t = 0.0


func update(delta: float, snake: Snake, director) -> void:
	if level <= 0 or snake == null or not snake.alive:
		return
	d = director
	_think(delta, snake)
	d = null


func _think(delta: float, snake: Snake) -> void:
	pincer_cd -= delta
	_update_pincer(delta, snake)
	tick_t -= delta
	if tick_t > 0.0:
		return
	tick_t = TICK
	_clear_orders()
	_plan_pincer(snake)
	_plan_support(snake)
	_plan_crossfire(snake)
	_plan_herding(snake)
	_plan_boss_guard(snake)
	if level >= 2:
		_plan_chain(snake)


func _announce() -> void:
	if not hinted:
		hinted = true
		d.g.hint(Tips.COOP_HINT, 4.0)


func _clear_orders() -> void:
	for b: TeddyBear in d.bears:
		b.order = ""
		b.order_pos = Vector2.INF
		b.order_target = null
		b.lead_hint = Vector2.INF
	for p in d.pills:
		p.aim_offset = Vector2.ZERO


# ---------------------------------------------------------------- клещи

func _plan_pincer(snake: Snake) -> void:
	if not pincer.is_empty() or pincer_cd > 0.0:
		return
	var need := 3 if level >= 2 and d.forks.size() >= 3 else 2
	var ready: Array[Fork] = []
	for f: Fork in d.forks:
		if f.st == Fork.St.ROAM and f.attack_cd < 0.8 and f.spawn_k > 0.9:
			ready.append(f)
	if ready.size() < need:
		return
	ready.sort_custom(func(a: Fork, b: Fork) -> bool:
		return a.position.distance_to(snake.head_pos) < b.position.distance_to(snake.head_pos))
	pincer = ready.slice(0, need)
	pincer_t = PINCER_TIMEOUT * (0.75 if level >= 2 else 1.0)
	stats["pincer"] += 1
	_announce()


## Точки вокруг головы: две по бокам от курса змеи или три через 120°.
func pincer_slots(head: Vector2, heading: float, count: int, bounds: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var inner := bounds.grow(-60.0)
	for i in count:
		var a := heading + PI / 2.0 + TAU * i / count
		out.append((head + Vector2.from_angle(a) * PINCER_RADIUS).clamp(inner.position, inner.end))
	return out


func _update_pincer(delta: float, snake: Snake) -> void:
	if pincer.is_empty():
		return
	pincer = pincer.filter(func(f) -> bool: return is_instance_valid(f) and d.forks.has(f))
	if pincer.size() < 2:
		_release_pincer()
		return
	pincer_t -= delta
	var slots := pincer_slots(snake.head_pos, snake.heading, pincer.size(), d.g.bounds)
	var in_place := true
	for i in pincer.size():
		var f: Fork = pincer[i]
		if f.st != Fork.St.ROAM:  # что-то сбило вилку с позиции
			_release_pincer()
			return
		f.slot = slots[i]
		f.coop_tag = 0.6
		if f.position.distance_to(slots[i]) > 70.0:
			in_place = false
	if in_place or pincer_t <= 0.0:
		for f: Fork in pincer:
			f.slot = Vector2.INF
			f.coop_tag = 1.2
			f.begin_attack(Fork.Atk.LUNGE, snake.head_pos)
		pincer.clear()
		pincer_cd = 4.5 if level >= 2 else 6.0


func _release_pincer() -> void:
	for f in pincer:
		if is_instance_valid(f):
			f.slot = Vector2.INF
	pincer.clear()
	pincer_cd = 2.0


# ---------------------------------------------------------------- спасение и прикрытие

func _free_bears() -> Array[TeddyBear]:
	var out: Array[TeddyBear] = []
	for b: TeddyBear in d.bears:
		if b.st == TeddyBear.St.ROAM and b.type != TeddyBear.Type.MEDIC and not b.has_grudge():
			out.append(b)
	return out


func _nearest(bears: Array[TeddyBear], to: Vector2) -> TeddyBear:
	var best: TeddyBear = null
	var best_d := 1e9
	for b in bears:
		var dist := b.position.distance_to(to)
		if dist < best_d:
			best_d = dist
			best = b
	return best


func _plan_support(snake: Snake) -> void:
	var free := _free_bears()
	for f: Fork in d.forks:
		if free.is_empty():
			return
		if f.st in [Fork.St.STUCK, Fork.St.POGO_STUCK]:
			var b := _nearest(free, f.position)
			free.erase(b)
			b.order = "rescue"
			b.order_target = f
			stats["rescue"] += 1
			_announce()
			if b.position.distance_to(f.position) < TeddyBear.RADIUS + 34.0:
				f.rescued = 0.5
		elif f.st in [Fork.St.DIZZY, Fork.St.BALD] and f.position.distance_to(snake.head_pos) < 420.0:
			var b := _nearest(free, f.position)
			free.erase(b)
			b.order = "guard"
			b.order_pos = guard_point(f.position, snake.head_pos)
			stats["guard"] += 1
			_announce()


## Точка между змеёй и тем, кого прикрываем.
static func guard_point(protect: Vector2, head: Vector2, gap := 48.0) -> Vector2:
	return protect + (head - protect).normalized() * gap


# ---------------------------------------------------------------- огонь и загон

func _plan_crossfire(snake: Snake) -> void:
	var aiming: Fork = null
	for f: Fork in d.forks:
		if f.st in [Fork.St.AIM, Fork.St.SPRINT]:
			aiming = f
			break
	if aiming == null:
		return
	var lead := snake.head_pos + aiming.facing() * 110.0
	for b: TeddyBear in d.bears:
		if b.type in [TeddyBear.Type.THROWER, TeddyBear.Type.SEAMSTRESS, TeddyBear.Type.NINJA, TeddyBear.Type.BOMBER]:
			b.lead_hint = lead
			b.attack_cd = minf(b.attack_cd, 0.4)
			stats["crossfire"] += 1


func _plan_herding(snake: Snake) -> void:
	if d.forks.is_empty() or d.pills.is_empty():
		return
	var center := Vector2.ZERO
	for f: Fork in d.forks:
		center += f.position
	center /= d.forks.size()
	var away := (snake.head_pos - center).normalized()  # прыгнуть со стороны, противоположной вилкам
	for p in d.pills:
		p.aim_offset = away * 90.0
	stats["herd"] += 1


func _plan_boss_guard(snake: Snake) -> void:
	var boss: FriedEggBoss = d.g.boss
	if boss == null or not boss.is_yolk_open():
		return
	var yolk := boss.position + FriedEggBoss.YOLK_OFFSET
	var free := _free_bears()
	var n := 0
	for b in free:
		var spread := (n - (free.size() - 1) / 2.0) * 0.5
		b.order = "guard"
		b.order_pos = yolk + (snake.head_pos - yolk).normalized().rotated(spread) * (FriedEggBoss.YOLK_RADIUS + 40.0)
		n += 1
	if n > 0:
		stats["boss_guard"] += 1
		_announce()


func _plan_chain(snake: Snake) -> void:
	var leader := false
	for b: TeddyBear in d.bears:
		if b.st in [TeddyBear.St.WINDUP, TeddyBear.St.AIM]:
			leader = true
			break
	if not leader:
		return
	for b: TeddyBear in d.bears:
		if b.st == TeddyBear.St.ROAM and b.attack_cd > 0.8 and b.position.distance_to(snake.head_pos) < 380.0:
			b.attack_cd = randf_range(0.45, 0.8)
			stats["chain"] += 1
