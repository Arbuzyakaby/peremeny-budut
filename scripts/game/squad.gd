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
## v8.0:
## - РАССРЕДОТОЧЕНИЕ: стрелки (метатель, швея, ниндзя, хлопушка) расходятся по кругу вокруг змеи
##   на равные углы — снаряды летят с разных сторон, а не одной кучей;
## - УКЛОНЕНИЕ: враги «читают оружие змеи» — если у неё стрелковая атака (пуговицы, иглы, залп зубцов),
##   медведь на линии огня отскакивает вбок (дёргается перед этим — видно);
## - ОГОНЬ ПО ПОДХОДУ: когда желток яичницы открыт, стрелки целятся змее на путь к желтку;
## - МИЛОСЕРДИЕ: на последней жизни (если жизней было больше одной) клещи реже, обманщика и цепочек нет.
## v9.0, матрёшки:
## - ХОРОВОД: три и больше матрёшек встают в круг вокруг змеи, берутся за ленты и ведут хоровод —
##   круг медленно вращается и сжимается. Лента путает змею (замедляет). По курсу змеи в момент сбора
##   всегда оставлен просвет ≥ 120°, а укус танцующей рвёт хоровод;
## - РАЗБЕГ: две средние, выскочившие из большой, удирают в разные стороны — обеих сразу не догнать;
## - ЗАСЛОН: пока малышка переводит дух после прыжка, ближайшая матрёшка встаёт между ней и змеёй;
## - ДУЭТ (только Ультра): две малышки переглядываются («!!») и прыгают одновременно по бокам от курса
##   змеи — прямо по курсу безопасно.
## Окно обязательства: взятая роль держится не меньше COMMIT_TICKS тактов (0,5 с), раньше её снимает
## только срыв — враг погиб или оглушён, цель пропала, враг застрял. Подробности — docs/AI.md.
## На Лёгкой и Нормальной (coop = 0) ничего не делает.

const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Tips = preload("res://scripts/core/tips.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")

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
const SPREAD_RADIUS := 330.0     # рассредоточение: круг стрелков вокруг змеи
const DODGE_CONE := 0.3          # уклонение: полуугол линии огня, рад
const DODGE_RANGE := 520.0
const DODGE_STEP := 110.0        # на сколько отскакивает вбок
const DODGE_COOLDOWN := 2.5      # следующий отскок этого медведя — не раньше
const MERCY_PINCER := 1.5        # милосердие: пауза между клещами длиннее во столько раз
const RANGED_SNAKE_ATTACKS := [2, 4, 10]  # пуговицы, иглы, залп зубцов (типы из Balance.ABILITIES)
const RANGED_BEARS := [TeddyBear.Type.THROWER, TeddyBear.Type.SEAMSTRESS, TeddyBear.Type.NINJA, TeddyBear.Type.BOMBER]
## v9.0: матрёшки.
const KHOROVOD_RADIUS := 250.0   # круг собирается на таком радиусе вокруг змеи...
const KHOROVOD_MIN_R := 165.0    # ...и сжимается до такого
const KHOROVOD_GAP := 2.1        # просвет по курсу змеи ≈ 120° (не уже — выход должен быть)
const KHOROVOD_TIME := 6.0       # сколько длится хоровод
const KHOROVOD_SPIN := 0.28      # вращение, рад/с (на Ультра ×1,4)
const KHOROVOD_CD := 7.0
const KHOROVOD_REACH := 460.0    # дальше этого от змеи в хоровод не зовут
const KHOROVOD_IN_PLACE := 46.0  # ближе этого к своему месту — берётся за ленту
const KHOROVOD_GATHER := 2.5     # дольше этого круг не собирают: кто не успел — догоняет на ходу
const SCATTER_TIME := 1.1
const DUET_CD := 5.0
const DUET_LOOK := 0.35          # малышки переглядываются перед дуэтом
const DUET_SIDE := 75.0          # и прыгают на столько вбок от курса змеи

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
var mercy := false       # последняя жизнь — отряд давит мягче
## Хоровод матрёшек: танцующие по кругу, центр круга (стоит на месте), угол просвета, время.
var khorovod: Array = []
var kh_center := Vector2.ZERO
var kh_gap := 0.0        # направление просвета, рад (вращается вместе с кругом)
var kh_t := 0.0
var kh_gather := 0.0     # сколько ещё ждать, пока все встанут в круг
var kh_cd := 3.0
var duet_cd := 2.0
var stats := {"pincer": 0, "rescue": 0, "guard": 0, "crossfire": 0, "herd": 0, "chain": 0, "boss_guard": 0,
	"breakout": 0, "decoy": 0, "abort": 0, "spread": 0, "dodge": 0, "boss_fire": 0, "mercy": 0,
	"khorovod": 0, "khorovod_break": 0, "scatter": 0, "cover": 0, "duet": 0}


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
	for m in khorovod:
		if is_instance_valid(m):
			m.leave_dance()
	khorovod.clear()
	kh_cd = 2.0
	duet_cd = 2.0


func update(delta: float, snake: Snake, director) -> void:
	if level <= 0 or snake == null or not snake.alive:
		return
	d = director
	_think(delta, snake)
	d = null


func _think(delta: float, snake: Snake) -> void:
	pincer_cd -= delta
	decoy_cd -= delta
	kh_cd -= delta
	duet_cd -= delta
	_check_aborts(delta)
	_update_pincer(delta, snake)
	_update_khorovod(delta, snake)
	tick_t -= delta
	if tick_t > 0.0:
		return
	tick_t = TICK
	var was_mercy := mercy
	mercy = snake.lives <= 1 and snake.max_lives > 1
	if mercy and not was_mercy:
		stats["mercy"] += 1
	_age_roles()
	_plan_pincer(snake)
	_plan_support(snake)
	_plan_dodge(snake)
	_plan_crossfire(snake)
	_plan_boss_fire(snake)
	_plan_spread(snake)
	_plan_herding(snake)
	_plan_boss_guard(snake)
	_plan_khorovod(snake)
	_plan_doll_cover(snake)
	if level >= 2 and not mercy:
		_plan_chain(snake)
		_plan_decoy(snake)
		_plan_duet(snake)
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
		if r["role"] in ["crossfire", "boss_fire"]:
			n.lead_hint = Vector2.INF
		else:
			n.order = ""
			n.order_pos = Vector2.INF
			n.order_target = null
			n.feint = false
	elif n is Matryoshka:
		if not n.dancing:
			n.order_pos = Vector2.INF
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
	elif n is Matryoshka:
		if not d.dolls.has(n) or n.st != Matryoshka.St.ROAM or n.dancing:
			return true  # раскрыта, оглушена или ушла в хоровод
	elif not d.pills.has(n):
		return true
	if target != null and (not is_instance_valid(target) or not _on_field(target)):
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
		"boss_guard", "boss_fire":
			return d.g.boss == null or not d.g.boss.is_yolk_open()
		"cover":
			return not target.is_dazed()
	return false


## Цель роли ещё на поле: вилка или матрёшка (типизированные массивы не принимают чужой тип в has()).
func _on_field(target: Object) -> bool:
	if target is Fork:
		return d.forks.has(target)
	if target is Matryoshka:
		return d.dolls.has(target)
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
	if n is Matryoshka:
		return n.order_pos if r["role"] == "cover" else Vector2.INF
	if not n is TeddyBear:
		return Vector2.INF
	match r["role"]:
		"rescue":
			return (r["target"] as Node2D).position
		"guard", "boss_guard", "dodge":
			return n.order_pos
	return Vector2.INF  # точки обманщика и круга стрелков едут вместе со змеёй — застреванием не считается


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
	if mercy and randf() < 0.35:  # на последней жизни клещи собираются реже
		pincer_cd = 1.0
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
	pincer_cd = (4.5 if level >= 2 else 6.0) * (MERCY_PINCER if mercy else 1.0)


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


# ---------------------------------------------------------------- v8.0: рассредоточение, уклонение, огонь по подходу

## Стрелки без роли расходятся по кругу вокруг змеи на равные углы (порядок — по их текущему углу,
## чтобы никто не бежал через всю арену).
func _plan_spread(snake: Snake) -> void:
	var shooters: Array[TeddyBear] = []
	for b: TeddyBear in d.bears:
		if b.type in RANGED_BEARS and b.st == TeddyBear.St.ROAM and not b.has_grudge():
			var role := role_of(b)
			if role == "spread" or (role == "" and _can_take(b)):
				shooters.append(b)
	if shooters.size() < 2:
		for b in shooters:  # одному рассредоточиваться не с кем
			if role_of(b) == "spread":
				_release(b.get_instance_id())
		return
	var head := snake.head_pos
	shooters.sort_custom(func(a: TeddyBear, b: TeddyBear) -> bool:
		return (a.position - head).angle() < (b.position - head).angle())
	var start := (shooters[0].position - head).angle()
	var slots := spread_slots(head, start, shooters.size(), d.g.bounds)
	var fresh := false
	for i in shooters.size():
		var b := shooters[i]
		if role_of(b) != "spread":
			fresh = true
		if _assign(b, "spread"):
			b.order = "guard"
			b.order_pos = slots[i]
	if fresh:
		stats["spread"] += 1


## Точки круга стрелков: count штук на равных углах от angle0, внутри арены.
static func spread_slots(head: Vector2, angle0: float, count: int, bounds: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var inner := bounds.grow(-50.0)
	for i in count:
		var a := angle0 + TAU * i / count
		out.append((head + Vector2.from_angle(a) * SPREAD_RADIUS).clamp(inner.position, inner.end))
	return out


## Змея со стрелковой атакой: медведь на линии огня отскакивает вбок.
func _plan_dodge(snake: Snake) -> void:
	var ab = d.g.abilities
	if ab == null or not ab.type in RANGED_SNAKE_ATTACKS or ab.charges <= 0:
		return
	var head := snake.head_pos
	var aim := Vector2.from_angle(snake.heading)
	var inner: Rect2 = d.g.bounds.grow(-40.0)
	for b: TeddyBear in d.bears:
		if role_of(b) == "dodge" or not _can_take(b) or b.st != TeddyBear.St.ROAM or b.is_shielded():
			continue
		if not in_line_of_fire(head, aim, b.position):
			continue
		var side := aim.orthogonal()
		if side.dot(b.position - head) < 0.0:
			side = -side
		if _assign(b, "dodge"):
			b.order = "guard"
			b.order_pos = (b.position + side * DODGE_STEP).clamp(inner.position, inner.end)
			b.hit_flash = 0.4  # дёрнулся — видно, что сейчас отскочит
			role_cd[b.get_instance_id()] = DODGE_COOLDOWN + COMMIT_TICKS * TICK
			stats["dodge"] += 1
			_announce("dodge", Tips.DODGE_HINT)


## Точка на линии огня змеи: впереди, в узком конусе, не дальше DODGE_RANGE.
static func in_line_of_fire(head: Vector2, aim: Vector2, p: Vector2) -> bool:
	var to := p - head
	var dist := to.length()
	return dist > 1.0 and dist < DODGE_RANGE and absf(aim.angle_to(to)) < DODGE_CONE


## Желток открыт: стрелки целятся змее на путь к желтку.
func _plan_boss_fire(snake: Snake) -> void:
	var boss: FriedEggBoss = d.g.boss
	if boss == null or not boss.is_yolk_open():
		return
	var yolk := boss.position + FriedEggBoss.YOLK_OFFSET
	var head := snake.head_pos
	var lead := head + (yolk - head).normalized() * minf(140.0, head.distance_to(yolk) * 0.5)
	for b: TeddyBear in d.bears:
		if not b.type in RANGED_BEARS:
			continue
		var role := role_of(b)
		if role != "boss_fire" and not (role in ["", "spread"] and not is_committed(b)):
			continue
		if role != "boss_fire":
			if not _assign(b, "boss_fire"):
				continue
			b.attack_cd = minf(b.attack_cd, 0.5)
			stats["boss_fire"] += 1
		elif not is_committed(b):
			_assign(b, "boss_fire")
		b.lead_hint = lead


# ---------------------------------------------------------------- v9.0: матрёшки

## Хоровод водят большие и средние матрёшки: малышки не танцуют — они прыгают.
func _dancer_ok(m: Matryoshka) -> bool:
	return not m.is_last() and m.st == Matryoshka.St.ROAM and m.scatter_t <= 0.0 and m.spawn_k > 0.9


## Сейчас змею зажимают (клещи или хоровод) — музыка подмешивает напряжение.
func is_trapping() -> bool:
	return not pincer.is_empty() or not khorovod.is_empty()


func _plan_khorovod(snake: Snake) -> void:
	if not khorovod.is_empty() or kh_cd > 0.0:
		return
	if mercy and randf() < 0.4:
		kh_cd = 1.5
		return
	var ready: Array[Matryoshka] = []
	for m: Matryoshka in d.dolls:
		if _dancer_ok(m) and _can_take(m) and role_of(m) == "" \
				and m.position.distance_to(snake.head_pos) < KHOROVOD_REACH:
			ready.append(m)
	if ready.size() < 3:
		return
	var most := 5 if level >= 2 else 4
	ready.sort_custom(func(a: Matryoshka, b: Matryoshka) -> bool:
		return a.position.distance_to(snake.head_pos) < b.position.distance_to(snake.head_pos))
	var dancers := ready.slice(0, mini(most, ready.size()))
	var inner: Rect2 = d.g.bounds.grow(-KHOROVOD_MIN_R * 0.6)
	kh_center = snake.head_pos.clamp(inner.position, inner.end)
	kh_gap = snake.heading  # просвет — по курсу змеи
	# порядок по кругу: по углу от центра, начиная сразу за просветом
	dancers.sort_custom(func(a: Matryoshka, b: Matryoshka) -> bool:
		return wrapf((a.position - kh_center).angle() - kh_gap, 0.0, TAU) < wrapf((b.position - kh_center).angle() - kh_gap, 0.0, TAU))
	khorovod = dancers
	kh_t = KHOROVOD_TIME
	kh_gather = KHOROVOD_GATHER
	for m: Matryoshka in khorovod:
		m.order_pos = m.position
	stats["khorovod"] += 1
	_announce("khorovod", Tips.KHOROVOD_HINT)


## Места в хороводе: n точек на дуге круга радиуса r вокруг c, просвет gap_w с серединой в gap_dir.
static func khorovod_slots(c: Vector2, r: float, gap_dir: float, n: int, gap_w := KHOROVOD_GAP) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in n:
		var k := 0.5 if n == 1 else float(i) / (n - 1)
		var a := gap_dir + gap_w / 2.0 + (TAU - gap_w) * k
		out.append(c + Vector2.from_angle(a) * r)
	return out


func _update_khorovod(delta: float, snake: Snake) -> void:
	if khorovod.is_empty():
		return
	for m in khorovod:  # кто-то раскрыт, оглушён или сбит — хоровод рассыпается
		if not is_instance_valid(m) or not d.dolls.has(m) or m.st != Matryoshka.St.ROAM:
			break_khorovod()
			return
	var in_place := 0
	for m in khorovod:
		if m.dancing:
			in_place += 1
	kh_gather -= delta
	var assembled := in_place >= khorovod.size() - 1 or kh_gather <= 0.0
	if assembled:  # круг собран (или сбор затянулся): пошёл отсчёт, круг вращается и сжимается
		kh_t -= delta
	var left := snake.head_pos.distance_to(kh_center) > KHOROVOD_RADIUS + 60.0
	if kh_t <= 0.0 or (left and assembled):  # время вышло или змея ушла из круга — расходятся
		_end_khorovod(KHOROVOD_CD)
		return
	var k := 1.0 - kh_t / KHOROVOD_TIME
	var r := lerpf(KHOROVOD_RADIUS, KHOROVOD_MIN_R, clampf(k * 1.4, 0.0, 1.0))
	if assembled:
		kh_gap += KHOROVOD_SPIN * (1.4 if level >= 2 else 1.0) * delta
	var slots := khorovod_slots(kh_center, r, kh_gap, khorovod.size())
	var inner: Rect2 = d.g.bounds.grow(-24.0)
	for i in khorovod.size():
		var m: Matryoshka = khorovod[i]
		m.order_pos = slots[i].clamp(inner.position, inner.end)
		m.dancing = m.position.distance_to(slots[i]) < KHOROVOD_IN_PLACE
	for i in khorovod.size() - 1:  # ленты — между соседками; через просвет ленты нет
		var a: Matryoshka = khorovod[i]
		var b: Matryoshka = khorovod[i + 1]
		a.ribbon_to = b if a.dancing and b.dancing else null
	khorovod.back().ribbon_to = null


## Укус танцующей или ударная волна: хоровод рвётся, куклы на миг теряются.
func break_khorovod() -> void:
	if khorovod.is_empty():
		return
	stats["khorovod_break"] += 1
	_end_khorovod(KHOROVOD_CD * 0.8)


func _end_khorovod(cd: float) -> void:
	for m in khorovod:
		if is_instance_valid(m):
			m.leave_dance()
	khorovod.clear()
	kh_cd = cd


## Разбег: выскочившие из большой куклы бегут в разные стороны от змеи, не в угол.
func scatter(kids: Array, snake: Snake, bounds: Rect2) -> void:
	if level <= 0 or snake == null:
		return
	var runners: Array = kids.filter(func(m) -> bool: return not m.is_last())
	if runners.size() < 2:
		return
	var inner := bounds.grow(-90.0)
	for i in runners.size():
		var m: Matryoshka = runners[i]
		var away := (m.position - snake.head_pos).normalized()
		var dir := away.rotated((float(i) / (runners.size() - 1) - 0.5) * 2.4)
		var goal := m.position + dir * 220.0
		if not inner.has_point(goal):  # в угол не бежать: к середине поля
			dir = (dir + (inner.get_center() - m.position).normalized()).normalized()
		m.scatter_dir = dir
		m.scatter_t = SCATTER_TIME
	stats["scatter"] += 1


## Заслон: пока малышка переводит дух после прыжка, ближайшая свободная матрёшка встаёт между ней и змеёй.
func _plan_doll_cover(snake: Snake) -> void:
	var served := {}
	for r: Dictionary in roles.values():
		if r["role"] == "cover" and is_instance_valid(r["node"]):
			served[r["target"]] = true
			if not is_committed(r["node"]):
				_assign(r["node"], "cover", r["target"])
			r["node"].order_pos = guard_point(r["target"].position, snake.head_pos, 44.0)
	var free: Array[Matryoshka] = []
	for m: Matryoshka in d.dolls:
		if _dancer_ok(m) and not m.dancing and role_of(m) == "" and _can_take(m):
			free.append(m)
	for tiny: Matryoshka in d.dolls:
		if free.is_empty():
			return
		if not tiny.is_last() or not tiny.is_dazed() or served.has(tiny) \
				or tiny.position.distance_to(snake.head_pos) > 420.0:
			continue
		var best: Matryoshka = null
		for m in free:
			if best == null or m.position.distance_to(tiny.position) < best.position.distance_to(tiny.position):
				best = m
		if best.position.distance_to(tiny.position) > 360.0:
			continue
		free.erase(best)
		if _assign(best, "cover", tiny):
			best.order_pos = guard_point(tiny.position, snake.head_pos, 44.0)
			stats["cover"] += 1
			_announce()


## Дуэт (Ультра): две готовые малышки переглядываются и прыгают одновременно по бокам от курса змеи.
func _plan_duet(snake: Snake) -> void:
	if duet_cd > 0.0:
		return
	var ready: Array[Matryoshka] = []
	for m: Matryoshka in d.dolls:
		if m.is_last() and m.st == Matryoshka.St.ROAM and m.spawn_k > 0.9 and m.sync_jump < 0.0 \
				and m.attack_cd < 0.6 and m.position.distance_to(snake.head_pos) < Matryoshka.ATTACK_RANGE + 80.0:
			ready.append(m)
	if ready.size() < 2:
		return
	var side := Vector2.from_angle(snake.heading).orthogonal()
	for i in 2:
		var m: Matryoshka = ready[i]
		m.sync_jump = DUET_LOOK
		m.jump_offset = side * DUET_SIDE * (1.0 if i == 0 else -1.0)
		m.coop_tag = DUET_LOOK + 0.6
		m.attack_cd = 9.0  # сама не прыгает — ждёт напарницу
	duet_cd = DUET_CD
	stats["duet"] += 1
	_announce("duet", Tips.DUET_HINT)
