extends RefCounted
## Кооперативный ИИ врагов на Сложной (coop = 1) и Ультра-Хардкоре (coop = 2). Раз в четверть секунды
## (такт отряда) смотрит на поле целиком и раздаёт роли:
## - КЛЕЩИ: две вилки (на Ультра — три) расходятся вокруг змеи, 0,3 с смотрят друг на друга и бьют
##   выпадом одновременно. По курсу змеи всегда остаётся просвет, а вилку можно прорвать спринтом;
## - СПАСЕНИЕ: ближайший медведь бежит с поднятой лапой к застрявшей вилке и выдёргивает её быстрее;
## - ПРИКРЫТИЕ: медведь встаёт между змеёй и беззащитной вилкой (оглушённой, беззубой);
## - ПЕРЕКРЁСТНЫЙ ОГОНЬ: метатели целятся туда, куда змею отбросит выпад вилки;
## - ЗАГОН: таблетки меняют оттенок и прыгают со стороны, противоположной вилкам, — змея бежит на зубцы;
## - ЩИТ ЯИЧНИЦЫ: когда желток открыт, медведи-подкрепления заслоняют его собой;
## - ЦЕПОЧКА (только Ультра): когда один медведь атакует, соседи подхватывают атаку следом;
## - ОБМАНЩИК (только Ультра): медведь садится на линию настоящей атаки и изображает оглушение —
##   приманивает змею под зубцы.
## Окно обязательства: взятая роль держится не меньше COMMIT_TICKS тактов (0,5 с), раньше её снимает
## только срыв — враг погиб или оглушён, цель пропала, враг застрял. Подробности — docs/AI.md.
## На Лёгкой и Нормальной (coop = 0) ничего не делает.

const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Tips = preload("res://scripts/core/tips.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")

const TICK := 0.25
const COMMIT_TICKS := 2          # окно обязательства: 2 такта = 0,5 с
const STALL_TICKS := 3           # столько тактов подряд без продвижения к цели — «застрял»
const STALL_COOLDOWN := 1.5      # после застревания роль этому врагу не дают столько секунд
const PINCER_RADIUS := 250.0
const PINCER_TIMEOUT := 2.6
const PINCER_LOOK := 0.3         # вилки смотрят друг на друга перед ударом
const PINCER_GAP := 2.6          # просвет по курсу змеи в тройных клещах (≈150°); в парных — пол-круга
const BREAKOUT_STAMINA := 0.3    # цена прорыва сквозь вилку в клещах
const DECOY_CD := 6.0
const DECOY_LURE := 140.0        # обманщик садится на линию атаки на таком расстоянии от головы
const DECOY_REACH := 420.0       # дальше этого от точки приманки медведя не зовут

var d  # enemy_director.gd — только на время update(): постоянная ссылка дала бы цикл и утечку
var level := 0
var tick_t := 0.0
var pincer: Array = []   # вилки, которые сейчас заходят в клещи
var pincer_t := 0.0
var pincer_cd := 2.0
var pincer_look_t := 0.0 # >0 — вилки уже на местах и переглядываются
var pincer_id := 0
var decoy_cd := 0.0
## Роли по instance_id: {"node", "role", "target", "ticks", "stall", "last_d"}.
var roles := {}
var role_cd := {}        # instance_id → секунды, пока роль не дают (после застревания)
var hinted := {}
var stats := {"pincer": 0, "rescue": 0, "guard": 0, "crossfire": 0, "herd": 0, "chain": 0, "boss_guard": 0,
	"breakout": 0, "decoy": 0, "abort": 0}


func reset() -> void:
	for r: Dictionary in roles.values():
		_clear_role_fields(r)
	roles.clear()
	role_cd.clear()
	for f in pincer:
		if is_instance_valid(f):
			f.slot = Vector2.INF
			f.leave_pincer()
	pincer.clear()
	pincer_t = 0.0
	pincer_cd = 2.0
	pincer_look_t = 0.0
	decoy_cd = 0.0
	tick_t = 0.0


func update(delta: float, snake: Snake, director) -> void:
	if level <= 0 or snake == null or not snake.alive:
		return
	d = director
	_think(delta, snake)
	d = null


func _think(delta: float, snake: Snake) -> void:
	pincer_cd -= delta
	decoy_cd -= delta
	_check_aborts(delta)
	_update_pincer(delta, snake)
	tick_t -= delta
	if tick_t > 0.0:
		return
	tick_t = TICK
	_age_roles()
	_plan_pincer(snake)
	_plan_support(snake)
	_plan_crossfire(snake)
	_plan_herding(snake)
	_plan_boss_guard(snake)
	if level >= 2:
		_plan_chain(snake)
		_plan_decoy(snake)
	_drop_stale()


func _announce(key := "coop", text := Tips.COOP_HINT) -> void:
	if hinted.has(key):
		return
	hinted[key] = true
	hinted["coop"] = true
	d.g.hint(text, 4.0)


# ---------------------------------------------------------------- роли и окно обязательства

## Текущая роль врага ("" — сам по себе).
func role_of(node: Object) -> String:
	var r: Dictionary = roles.get(node.get_instance_id(), {})
	return r.get("role", "")


## Роль ещё в окне обязательства: план её не трогает.
func is_committed(node: Object) -> bool:
	var r: Dictionary = roles.get(node.get_instance_id(), {})
	return int(r.get("ticks", 0)) > 0


func _can_take(node: Object) -> bool:
	return not is_committed(node) and float(role_cd.get(node.get_instance_id(), 0.0)) <= 0.0


## Дать роль (или продлить ту же). Смена роли — только вне окна обязательства.
func _assign(node: Object, role: String, target: Object = null) -> bool:
	var id := node.get_instance_id()
	var r: Dictionary = roles.get(id, {})
	if not r.is_empty() and r["role"] == role and r["target"] == target:
		r["ticks"] = COMMIT_TICKS
		return true
	if not _can_take(node):
		return false
	if not r.is_empty():
		_clear_role_fields(r)
	roles[id] = {"node": node, "role": role, "target": target, "ticks": COMMIT_TICKS, "stall": 0, "last_d": INF}
	return true


func _release(id: int) -> void:
	var r: Dictionary = roles.get(id, {})
	if r.is_empty():
		return
	_clear_role_fields(r)
	roles.erase(id)


func _clear_role_fields(r: Dictionary) -> void:
	var n = r["node"]
	if not is_instance_valid(n):
		return
	if n is TeddyBear:
		if r["role"] == "crossfire":
			n.lead_hint = Vector2.INF
		else:
			n.order = ""
			n.order_pos = Vector2.INF
			n.order_target = null
			n.feint = false
	elif n.get("aim_offset") != null:  # таблетка
		n.aim_offset = Vector2.ZERO
		n.herd = false


## Срыв роли — проверяется каждый кадр, а не раз в такт: снимает роль сразу.
func _check_aborts(delta: float) -> void:
	for id in role_cd.keys():
		role_cd[id] = float(role_cd[id]) - delta
		if role_cd[id] <= 0.0:
			role_cd.erase(id)
	for id in roles.keys():
		if _aborted(roles[id]):
			stats["abort"] += 1
			_release(id)


func _aborted(r: Dictionary) -> bool:
	var n = r["node"]
	if not is_instance_valid(n):
		return true
	var target = r["target"]
	var role: String = r["role"]
	if n is TeddyBear:
		if not d.bears.has(n) or n.st == TeddyBear.St.DIZZY or n.has_grudge():
			return true  # погиб, оглушён или ушёл мстить
	elif not d.pills.has(n):
		return true
	if target != null and (not is_instance_valid(target) or not d.forks.has(target)):
		return true  # цель пропала
	match role:
		"rescue":
			return not target.st in [Fork.St.STUCK, Fork.St.POGO_STUCK]
		"guard":
			return not target.st in [Fork.St.DIZZY, Fork.St.BALD]
		"crossfire":
			return not target.st in [Fork.St.AIM, Fork.St.SPRINT]
		"decoy":
			return not (pincer.has(target) or target.st in [Fork.St.AIM, Fork.St.SPRINT])
		"herd":
			return d.forks.is_empty()
		"boss_guard":
			return d.g.boss == null or not d.g.boss.is_yolk_open()
	return false


## Начало такта: окно обязательства уменьшается, застрявшие теряют роль.
func _age_roles() -> void:
	for id in roles.keys():
		var r: Dictionary = roles[id]
		r["ticks"] = int(r["ticks"]) - 1
		var goal := _goal_of(r)
		if goal == Vector2.INF:
			continue
		var dist: float = r["node"].position.distance_to(goal)
		if dist > 30.0 and float(r["last_d"]) - dist < 3.0:
			r["stall"] = int(r["stall"]) + 1
		else:
			r["stall"] = 0
		r["last_d"] = dist
		if int(r["stall"]) >= STALL_TICKS:
			stats["abort"] += 1
			role_cd[id] = STALL_COOLDOWN
			_release(id)


func _goal_of(r: Dictionary) -> Vector2:
	var n = r["node"]
	if not n is TeddyBear:
		return Vector2.INF
	match r["role"]:
		"rescue":
			return (r["target"] as Node2D).position
		"guard", "boss_guard":
			return n.order_pos
	return Vector2.INF  # точка обманщика едет вместе со змеёй — застреванием не считается


## Конец такта: роли, у которых кончилось окно и которые план не продлил, снимаются.
func _drop_stale() -> void:
	for id in roles.keys():
		if int(roles[id]["ticks"]) <= 0:
			_release(id)


func _bears_with(role: String) -> Array[TeddyBear]:
	var out: Array[TeddyBear] = []
	for r: Dictionary in roles.values():
		if r["role"] == role and is_instance_valid(r["node"]):
			out.append(r["node"])
	return out


func _role_target(node: Object) -> Object:
	var r: Dictionary = roles.get(node.get_instance_id(), {})
	return r.get("target", null)


# ---------------------------------------------------------------- клещи

func _plan_pincer(snake: Snake) -> void:
	if not pincer.is_empty() or pincer_cd > 0.0:
		return
	var need := 3 if level >= 2 and d.forks.size() >= 3 else 2
	var ready: Array[Fork] = []
	for f: Fork in d.forks:
		if f.st == Fork.St.ROAM and f.attack_cd < 0.8 and f.spawn_k > 0.9 and f.pincer_id == 0:
			ready.append(f)
	if ready.size() < need:
		return
	ready.sort_custom(func(a: Fork, b: Fork) -> bool:
		return a.position.distance_to(snake.head_pos) < b.position.distance_to(snake.head_pos))
	pincer = ready.slice(0, need)
	pincer_t = PINCER_TIMEOUT * (0.75 if level >= 2 else 1.0)
	pincer_look_t = 0.0
	pincer_id += 1
	for i in pincer.size():
		pincer[i].pincer_id = pincer_id
		pincer[i].pincer_lead = i == 0
	stats["pincer"] += 1
	_announce("pincer", Tips.PINCER_HINT)


## Ширина просвета по курсу змеи, радианы.
static func pincer_gap(count: int) -> float:
	return PI if count <= 2 else PINCER_GAP


## Точки вокруг головы. Спереди по курсу — просвет pincer_gap: две вилки встают по бокам,
## три — по бокам чуть впереди и сзади. Клещи никогда не замыкаются полностью.
func pincer_slots(head: Vector2, heading: float, count: int, bounds: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var inner := bounds.grow(-60.0)
	var gap := pincer_gap(count)
	for i in count:
		var k := 0.5 if count == 1 else float(i) / (count - 1)
		var a := heading + gap / 2.0 + (TAU - gap) * k
		out.append((head + Vector2.from_angle(a) * PINCER_RADIUS).clamp(inner.position, inner.end))
	return out


func _update_pincer(delta: float, snake: Snake) -> void:
	if pincer.is_empty():
		return
	pincer = pincer.filter(func(f) -> bool: return is_instance_valid(f) and d.forks.has(f))
	if pincer.size() < 2:
		_release_pincer()
		return
	var n := pincer.size()
	var slots := pincer_slots(snake.head_pos, snake.heading, n, d.g.bounds)
	var half := (TAU - pincer_gap(n)) / (2.0 * n)
	var in_place := true
	for i in n:
		var f: Fork = pincer[i]
		if f.st != Fork.St.ROAM:  # что-то сбило вилку с позиции — срыв
			_release_pincer()
			return
		f.slot = slots[i]
		f.pincer_half = half
		f.pincer_gap_dir = Vector2.from_angle(snake.heading)
		if level >= 2:
			f.coop_tag = 0.6  # «!!» — только на Ультра
		if f.position.distance_to(slots[i]) > 70.0:
			in_place = false
	if pincer_look_t > 0.0:
		pincer_look_t -= delta
		if pincer_look_t <= 0.0:
			_strike(snake)
		return
	pincer_t -= delta
	if in_place or pincer_t <= 0.0:  # телеграф: вилки поворачиваются друг к другу и кивают
		pincer_look_t = PINCER_LOOK
		for i in n:
			pincer[i].look_at_mate(pincer[(i + 1) % n].position, PINCER_LOOK)


func _strike(snake: Snake) -> void:
	for f: Fork in pincer:
		f.slot = Vector2.INF
		if level >= 2:
			f.coop_tag = 1.2
		f.begin_attack(Fork.Atk.LUNGE, snake.head_pos)
	pincer.clear()
	pincer_look_t = 0.0
	pincer_cd = 4.5 if level >= 2 else 6.0


func _release_pincer() -> void:
	for f in pincer:
		if is_instance_valid(f):
			f.slot = Vector2.INF
			f.leave_pincer()
	pincer.clear()
	pincer_look_t = 0.0
	pincer_cd = 2.0


## Змея прорвалась сквозь вилку в клещах (директор уже отбросил её): остальные теряют синхрон.
func breakout(broken: Fork, forks: Array) -> void:
	var pid := broken.pincer_id
	if pid == 0:
		return
	for f in forks:
		if f != broken and is_instance_valid(f) and f.pincer_id == pid:
			f.collapse()
	if not pincer.is_empty() and pincer[0].pincer_id == pid:
		for f in pincer:
			if is_instance_valid(f):
				f.slot = Vector2.INF
		pincer.clear()
		pincer_look_t = 0.0
	pincer_cd = maxf(pincer_cd, 4.0)
	stats["breakout"] += 1


# ---------------------------------------------------------------- спасение и прикрытие

func _free_bears() -> Array[TeddyBear]:
	var out: Array[TeddyBear] = []
	for b: TeddyBear in d.bears:
		if b.st == TeddyBear.St.ROAM and b.type != TeddyBear.Type.MEDIC and not b.has_grudge() and _can_take(b):
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
	var served := {}
	for b in _bears_with("rescue") + _bears_with("guard"):
		var f: Fork = _role_target(b)
		if not is_committed(b) and _support_role(f, snake) != role_of(b):
			continue  # окно кончилось, помощь больше не нужна — роль снимется в конце такта
		served[f] = true
		if not is_committed(b):
			_assign(b, role_of(b), f)  # окно кончилось, а помощь всё ещё нужна — продлить
		_refresh_support(b, f, snake)
	var free := _free_bears()
	for f: Fork in d.forks:
		if free.is_empty():
			return
		if served.has(f):
			continue
		var role := _support_role(f, snake)
		if role == "":
			continue
		var b := _nearest(free, f.position)
		free.erase(b)
		if _assign(b, role, f):
			b.order = role
			b.order_target = f
			stats[role] += 1
			_refresh_support(b, f, snake)
			_announce()


## Какая помощь нужна вилке: "rescue" — застряла, "guard" — беззащитна рядом со змеёй, "" — никакой.
func _support_role(f: Fork, snake: Snake) -> String:
	if f.st in [Fork.St.STUCK, Fork.St.POGO_STUCK]:
		return "rescue"
	if f.st in [Fork.St.DIZZY, Fork.St.BALD] and f.position.distance_to(snake.head_pos) < 420.0:
		return "guard"
	return ""


func _refresh_support(b: TeddyBear, f: Fork, snake: Snake) -> void:
	if b.order == "rescue":
		if b.position.distance_to(f.position) < TeddyBear.RADIUS + 34.0:
			f.rescued = 0.5
	else:
		b.order_pos = guard_point(f.position, snake.head_pos)


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
	for b: TeddyBear in d.bears:
		if not b.type in [TeddyBear.Type.THROWER, TeddyBear.Type.SEAMSTRESS, TeddyBear.Type.NINJA, TeddyBear.Type.BOMBER]:
			continue
		var r: Dictionary = roles.get(b.get_instance_id(), {})
		var mine: Fork = r.get("target") if r.get("role", "") == "crossfire" else null
		if mine == null and aiming == null:
			continue
		if mine == null:
			if not _assign(b, "crossfire", aiming):
				continue
			mine = aiming
			b.attack_cd = minf(b.attack_cd, 0.4)
			stats["crossfire"] += 1
		elif not is_committed(b):
			_assign(b, "crossfire", mine)
		b.lead_hint = snake.head_pos + mine.facing() * 110.0


func _plan_herding(snake: Snake) -> void:
	if d.forks.is_empty() or d.pills.is_empty():
		return
	var center := Vector2.ZERO
	for f: Fork in d.forks:
		center += f.position
	center /= d.forks.size()
	var away := (snake.head_pos - center).normalized()  # прыгнуть со стороны, противоположной вилкам
	var fresh := false
	for p in d.pills:
		if role_of(p) != "herd":
			fresh = true
		if _assign(p, "herd"):
			p.aim_offset = away * 90.0
			p.herd = true
	if fresh:
		stats["herd"] += 1


func _plan_boss_guard(snake: Snake) -> void:
	var boss: FriedEggBoss = d.g.boss
	if boss == null or not boss.is_yolk_open():
		return
	var yolk := boss.position + FriedEggBoss.YOLK_OFFSET
	var guards := _bears_with("boss_guard")
	var fresh := 0
	for b in _free_bears():
		if not guards.has(b):
			guards.append(b)
			fresh += 1
	var n := 0
	for b in guards:
		if not _assign(b, "boss_guard"):
			continue
		var spread := (n - (guards.size() - 1) / 2.0) * 0.5
		b.order = "guard"
		b.order_pos = yolk + (snake.head_pos - yolk).normalized().rotated(spread) * (FriedEggBoss.YOLK_RADIUS + 40.0)
		n += 1
	if fresh > 0:
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


# ---------------------------------------------------------------- обманщик (только Ультра)

## Настоящая атака, от которой обманщик уводит змею: клещи или одиночный выпад. [вилка, точка приманки].
func _threat(snake: Snake) -> Array:
	if not pincer.is_empty():  # приманка сбоку, прямо перед зубцами первой вилки клещей
		var f: Fork = pincer[0]
		var to: Vector2 = (f.slot if f.slot != Vector2.INF else f.position) - snake.head_pos
		return [f, snake.head_pos + to.normalized() * DECOY_LURE]
	for f: Fork in d.forks:
		if f.st == Fork.St.AIM:  # приманка на продолжении линии выпада за головой
			return [f, snake.head_pos + f.facing() * DECOY_LURE]
	return []


func _plan_decoy(snake: Snake) -> void:
	var threat := _threat(snake)
	var current := _bears_with("decoy")
	if threat.is_empty():
		return
	var inner: Rect2 = d.g.bounds.grow(-40.0)
	var lure: Vector2 = (threat[1] as Vector2).clamp(inner.position, inner.end)
	for b in current:  # уже сидит на линии — обновить точку
		if not is_committed(b):
			_assign(b, "decoy", _role_target(b))
		b.order_pos = lure
	if not current.is_empty() or decoy_cd > 0.0:
		return
	var candidates := _free_bears()
	var b := _nearest(candidates, lure)
	if b == null or b.position.distance_to(lure) > DECOY_REACH:
		return
	if _assign(b, "decoy", threat[0]):
		b.order = "decoy"
		b.order_pos = lure
		decoy_cd = DECOY_CD
		stats["decoy"] += 1
		_announce("decoy", Tips.DECOY_HINT)
