extends RefCounted
## Повтор гибели: кольцевой буфер снимков последних секунд забега (змея, враги, снаряды, яичница).
## Пишется 30 раз в секунду, после гибели экран итогов показывает его замедленно — с подсветкой
## того, что нанесло удар, и советом (core/tips.gd). Снимки — лёгкие словари без ссылок на узлы.

const SECONDS := 3.0
const RATE := 30.0
const CAPACITY := int(SECONDS * RATE)

var frames: Array[Dictionary] = []
var acc := 0.0
var cause := ""
var source := Vector2.INF  # где было то, что ударило (для подсветки)


func clear() -> void:
	frames.clear()
	acc = 0.0
	cause = ""
	source = Vector2.INF


func has_data() -> bool:
	return frames.size() >= 10


func duration() -> float:
	return frames.size() / RATE


## Записать кадр, если пора (g — game.gd).
func record(g, delta: float) -> void:
	acc += delta
	if acc < 1.0 / RATE:
		return
	acc = fmod(acc, 1.0 / RATE)
	push(snapshot(g))


func push(frame: Dictionary) -> void:
	frames.append(frame)
	if frames.size() > CAPACITY:
		frames.pop_front()


static func snapshot(g) -> Dictionary:
	var snake = g.snake
	var segs: PackedVector2Array = snake.get_segments() if snake else PackedVector2Array()
	var body := PackedVector2Array()
	for i in range(0, segs.size(), 2):  # прорежено вдвое — для схемы хватает
		body.append(segs[i])
	var enemies: Array = []
	for b in g.enemies.bears:
		enemies.append(["bear", b.position, 0.0, b.st])
	for f in g.enemies.forks:
		enemies.append(["fork", f.position, f.rotation, f.st])
	for p in g.enemies.pills:
		enemies.append(["pill", p.position, p.height, p.st])
	for m in g.enemies.dolls:
		enemies.append(["doll", m.position, m.height, m.radius()])
	var drops: Array = []
	for d in g.shots.drops:
		if d.is_missed():  # промах уже безвреден — на «камере наблюдения» только то, что может ударить
			continue
		drops.append([d.position, d.kind, d.from_snake])
	var waves: Array = []
	for w in g.shots.waves:
		waves.append([w.position, w.radius])
	return {
		"head": snake.head_pos if snake else Vector2.ZERO,
		"heading": snake.heading if snake else 0.0,
		"body": body,
		"hurt": snake.invuln > 0.0 if snake else false,
		"enemies": enemies,
		"drops": drops,
		"waves": waves,
		"boss": g.boss.position if g.boss else Vector2.INF,
	}


## Змея погибла: запомнить причину и найти, что было ближе всего к голове в последнем кадре.
func finish(death_cause: String) -> void:
	cause = death_cause
	source = Vector2.INF
	if frames.is_empty():
		return
	var last: Dictionary = frames.back()
	var head: Vector2 = last["head"]
	var best := 260.0
	for e: Array in last["enemies"]:
		var dist := head.distance_to(e[1])
		if dist < best:
			best = dist
			source = e[1]
	for d: Array in last["drops"]:
		if not d[2] and head.distance_to(d[0]) < best:
			best = head.distance_to(d[0])
			source = d[0]
	if last["boss"] != Vector2.INF and head.distance_to(last["boss"]) < best + 60.0:
		source = last["boss"]
	if cause in ["wall", "self"]:
		source = head


## Кадр по времени воспроизведения t (секунды от начала записи).
func frame_at(t: float) -> Dictionary:
	if frames.is_empty():
		return {}
	return frames[clampi(int(t * RATE), 0, frames.size() - 1)]
