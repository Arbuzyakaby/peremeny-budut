extends RefCounted
## Мирный кооперативный ИИ технического режима «Контакт» (v10.0). Боевой отряд (game/squad.gd) загоняет
## змею в клещи и хороводы; этот — сводит её с врагами. Работает только в «Контакте», обычный режим
## его не видит. Роли (каждая держится не меньше COMMIT секунд, как в боевом отряде):
##   FOLLOW — убеждённые идут колонной за змеёй по следу головы, в шахматном порядке;
##   HERALD — до двух убеждённых (сородичи — первыми) идут к неубеждённому и стоят рядом:
##            пока вестник рядом, доверие неубеждённого растёт;
##   LEAD   — неубеждённый, которому доверия хватило, сам подходит к змее — поговорить.
## Неубеждённые насторожены: пятятся от змеи и не бьют. Спокойная змея (без спринта) рядом —
## тоже потихоньку внушает доверие; неудачный знак — пугает (scared).
## Каждой записи отряда ставится want — скорость, с которой её сущность сделает calm_update.

const Gesture = preload("res://scripts/contact/gesture.gd")

const COMMIT := 1.5
const MAX_HERALDS := 2
const HERALD_RANGE := 95.0
const HERALD_TRUST := 0.16     # доверия в секунду от каждого вестника рядом
const CALM_TRUST := 0.04       # в секунду, пока спокойная змея рядом
const CALM_RANGE := 260.0
const LEAD_TRUST := 0.6
const LEAD_DIST := 150.0
const WARY_DIST := 230.0
const FOLLOW_GAP := 42.0
const FOLLOW_START := 70.0
const FOLLOW_MAX := 250.0
const SEPARATION := 36.0

var roles := {}  # instance_id убеждённого → {"role", "target", "t"}
var t := 0.0


func reset() -> void:
	roles.clear()


## entries — записи режима: {node, kind, convinced, trust, scared, speed, protected}; history — след
## головы (новые точки первыми); talking — с кем змея сейчас говорит (стоит на месте).
func update(delta: float, head: Vector2, snake_calm: bool, history: PackedVector2Array, entries: Array,
		talking: Node2D) -> void:
	t += delta
	var followers: Array = []
	var wary: Array = []
	for e: Dictionary in entries:
		if not is_instance_valid(e["node"]):
			continue
		if e["convinced"]:
			followers.append(e)
		else:
			wary.append(e)
	_assign_heralds(delta, followers, wary, head)
	var slot := 0
	for e: Dictionary in followers:
		var r: Dictionary = roles.get(e["node"].get_instance_id(), {})
		if r.get("role", "") == "herald" and is_instance_valid(r["target"]):
			e["want"] = _herald_want(e, r["target"], head, delta)
		else:
			e["want"] = _follow_want(e, slot, history, head)
			slot += 1
	for e: Dictionary in wary:
		e["want"] = _wary_want(e, head, snake_calm, talking, delta)
	_separate(entries)


## Кто из убеждённых пойдёт вестником и к кому. Цель — неубеждённый, ближайший к змее.
func _assign_heralds(delta: float, followers: Array, wary: Array, head: Vector2) -> void:
	var alive := {}
	for e: Dictionary in followers:
		alive[e["node"].get_instance_id()] = true
	for id in roles.keys():  # убеждённых больше нет (сгорели) — роли снять
		if not alive.has(id):
			roles.erase(id)
	var target: Node2D = null
	var best := INF
	for e: Dictionary in wary:
		var d: float = e["node"].position.distance_to(head)
		if d < best:
			best = d
			target = e["node"]
	var target_kind := ""
	for e: Dictionary in wary:
		if e["node"] == target:
			target_kind = e["kind"]
	var heralds := 0
	for id in roles.keys():
		var r: Dictionary = roles[id]
		r["t"] = float(r["t"]) + delta
		if r["role"] == "herald":
			var stale: bool = not is_instance_valid(r["target"]) or r["target"] != target
			if stale and float(r["t"]) >= COMMIT:
				roles.erase(id)
			else:
				heralds += 1
	if target == null:
		return
	var free := followers.filter(func(e: Dictionary) -> bool: return not roles.has(e["node"].get_instance_id()))
	free.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: int = 0 if a["kind"] == target_kind else 1
		var kb: int = 0 if b["kind"] == target_kind else 1
		if ka != kb:
			return ka < kb
		return a["node"].position.distance_to(target.position) < b["node"].position.distance_to(target.position))
	for e: Dictionary in free:
		if heralds >= MAX_HERALDS:
			break
		if e["kind"] == "egg":  # яичница слишком большая — вестником не ходит
			continue
		roles[e["node"].get_instance_id()] = {"role": "herald", "target": target, "t": 0.0}
		heralds += 1


func is_herald(node: Node2D) -> bool:
	return roles.get(node.get_instance_id(), {}).get("role", "") == "herald"


## Место в колонне: точка следа головы на расстоянии FOLLOW_START + k·FOLLOW_GAP, в шахматном порядке.
static func slot_pos(k: int, history: PackedVector2Array, head: Vector2) -> Vector2:
	var d := FOLLOW_START + k * FOLLOW_GAP
	if history.size() < 2:
		return head + Vector2(0, d)
	var p: Vector2 = Gesture.point_at(history, d)
	var ahead: Vector2 = Gesture.point_at(history, maxf(d - 12.0, 0.0))
	var side := (ahead - p).normalized().orthogonal() if ahead != p else Vector2.RIGHT
	return p + side * (22.0 if k % 2 == 0 else -22.0)


func _follow_want(e: Dictionary, k: int, history: PackedVector2Array, head: Vector2) -> Vector2:
	var node: Node2D = e["node"]
	var goal := slot_pos(k, history, head)
	var to := goal - node.position
	if to.length() < 8.0:
		return Vector2.ZERO
	return to.normalized() * minf(to.length() * 3.0, FOLLOW_MAX)


func _herald_want(e: Dictionary, target: Node2D, head: Vector2, _delta: float) -> Vector2:
	var node: Node2D = e["node"]
	var away := (target.position - head).normalized() if target.position != head else Vector2.RIGHT
	var side := 0.9 if node.get_instance_id() % 2 == 0 else -0.9
	var goal := target.position + away.rotated(side) * 70.0
	var to := goal - node.position
	if to.length() < 10.0:
		return Vector2.ZERO
	return to.normalized() * minf(to.length() * 3.0, FOLLOW_MAX)


func _wary_want(e: Dictionary, head: Vector2, snake_calm: bool, talking: Node2D, delta: float) -> Vector2:
	var node: Node2D = e["node"]
	var speed: float = e["speed"]
	e["scared"] = maxf(float(e.get("scared", 0.0)) - delta, 0.0)
	var to_head := head - node.position
	var d := to_head.length()
	# доверие: вестники рядом и спокойная змея неподалёку
	for id in roles:
		var r: Dictionary = roles[id]
		if r["role"] == "herald" and r["target"] == node:
			var h: Node2D = instance_from_id(id) as Node2D
			if h and h.position.distance_to(node.position) < HERALD_RANGE:
				e["trust"] = minf(float(e["trust"]) + HERALD_TRUST * delta, 1.0)
	if snake_calm and d < CALM_RANGE:
		e["trust"] = minf(float(e["trust"]) + CALM_TRUST * delta, 1.0)
	if node == talking:
		return Vector2.ZERO
	var away := -to_head.normalized() if d > 0.01 else Vector2.RIGHT
	if float(e["scared"]) > 0.0:
		return (away + _wall_push(node)).normalized() * speed * 1.7
	if float(e["trust"]) >= LEAD_TRUST:  # доверяет — сам подходит поговорить
		var goal := head - to_head.normalized() * LEAD_DIST
		var to := goal - node.position
		return to.normalized() * minf(to.length() * 2.0, speed * 1.4) if to.length() > 12.0 else Vector2.ZERO
	if d < WARY_DIST:  # насторожен: пятится, но не бьёт
		return (away + _wall_push(node) * 1.3).normalized() * speed * 1.3
	# бродит сам по себе, поглядывая на змею
	var ph: float = t * 0.5 + float(node.get_instance_id() % 97)
	return Vector2.from_angle(ph + sin(ph * 1.7)) * speed * 0.45 + _wall_push(node) * speed


## Отталкивание от бортиков (0..~1.5 по каждой оси).
static func _wall_push(node: Node2D) -> Vector2:
	var b: Rect2 = node.get("bounds") if node.get("bounds") != null else Rect2(0, 0, 1280, 720)
	var m := 110.0
	var p := node.position
	var out := Vector2.ZERO
	out.x += clampf((b.position.x + m - p.x) / m, 0.0, 1.0) - clampf((p.x - (b.end.x - m)) / m, 0.0, 1.0)
	out.y += clampf((b.position.y + m - p.y) / m, 0.0, 1.0) - clampf((p.y - (b.end.y - m)) / m, 0.0, 1.0)
	return out * 1.5


## Соседи не стоят друг в друге: скорости слегка разводят (яичницу не двигают — она большая).
static func _separate(entries: Array) -> void:
	for i in entries.size():
		var a: Dictionary = entries[i]
		if not is_instance_valid(a["node"]):
			continue
		for j in range(i + 1, entries.size()):
			var b: Dictionary = entries[j]
			if not is_instance_valid(b["node"]):
				continue
			var gap := SEPARATION
			if a["kind"] == "egg" or b["kind"] == "egg":
				gap = 170.0
			var off: Vector2 = b["node"].position - a["node"].position
			var dist := off.length()
			if dist < gap and dist > 0.01:
				var push := off / dist * (gap - dist) * 4.0
				if a["kind"] != "egg":
					a["want"] = a.get("want", Vector2.ZERO) - push
				if b["kind"] != "egg":
					b["want"] = b.get("want", Vector2.ZERO) + push
