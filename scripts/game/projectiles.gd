extends RefCounted
## Снаряды и ударные волны: пуговицы, иглы, сюрикены, хлопушки, масло яичницы; волны яичницы
## (урон) и таблеток (оглушение). Френдли фаер снарядами, взрывы хлопушек, выстрелы змеи.

const Balance = preload("res://scripts/core/balance.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const OilDrop = preload("res://scripts/entities/oil_drop.gd")
const Shockwave = preload("res://scripts/entities/shockwave.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")

const INNER := Rect2(24, 24, 1232, 672)  # внутри бортиков: сюда падают промахнувшиеся снаряды
const CONFETTI := [Color(0.95, 0.3, 0.5), Color(0.3, 0.7, 0.95), Color(0.6, 0.9, 0.3), Color(1, 0.85, 0.3)]

var g  # game.gd
var drops: Array[OilDrop] = []
var waves: Array[Shockwave] = []
var stun_hinted := false


func _init(game) -> void:
	g = game


func clear() -> void:
	for d in drops:
		d.queue_free()
	drops.clear()
	for w in waves:
		w.queue_free()
	waves.clear()


func spawn_drop(pos: Vector2, velocity: Vector2, kind: int) -> OilDrop:
	var d := OilDrop.new()
	d.z_index = 3
	d.setup(pos, velocity, kind)
	g.world.add_child(d)
	drops.append(d)
	return d


func remove_drop(d: OilDrop) -> void:
	drops.erase(d)
	d.queue_free()


func spawn_boss_wave(pos: Vector2, gaps: int) -> void:
	var w := Shockwave.new()
	w.z_index = 1
	w.setup(pos, gaps)
	g.world.add_child(w)
	waves.append(w)


func spawn_stun_wave(pos: Vector2, reach: float) -> void:
	var w := Shockwave.new()
	w.z_index = 1
	w.setup_stun(pos, reach)
	g.world.add_child(w)
	waves.append(w)


## Взрыв хлопушки: задевает всех в радиусе. Хлопушка змеи змею не ранит.
func explode(pos: Vector2, from_snake: bool) -> void:
	var snake: Snake = g.snake
	g.sfx.play("boom")
	g.add_shake(13.0)
	g.vibrate(50)
	for c in CONFETTI:
		g.fx.burst(pos, c, 10, 1.2)
	g.fx.burst(pos, Color(1, 0.95, 0.8), 18, 1.4)
	var r := OilDrop.BLAST_RADIUS
	if not from_snake and snake.alive and snake.head_pos.distance_to(pos) < r:
		if snake.take_damage(1, "blast"):
			g.fx.popup(snake.head_pos + Vector2(0, -30), "БАБАХ!", Color(1, 0.6, 0.3))
		snake.push((snake.head_pos - pos).normalized() * 520.0)
	for b: TeddyBear in g.enemies.bears.duplicate():
		if b.position.distance_to(pos) < r + TeddyBear.RADIUS:
			var v := (b.position - pos).normalized() * 380.0
			if from_snake:
				g.enemies.snake_hits_bear(b, v)
			else:
				g.enemies.friendly_hit(b, null, v)
	for f: Fork in g.enemies.forks.duplicate():
		if f.position.distance_to(pos) < r + 20.0:
			if from_snake:
				g.enemies.break_fork(f, "БАБАХ! ")
			else:
				f.bounce()
	if not from_snake:
		return
	for p: Pill in g.enemies.pills.duplicate():
		if not p.in_air() and p.position.distance_to(pos) < r + Pill.RADIUS:
			g.enemies.eat_pill(p, "БАБАХ! ")
	for m: Matryoshka in g.enemies.dolls.duplicate():
		if m.position.distance_to(pos) < r + m.radius():
			g.enemies.snake_hits_doll(m, "БАБАХ! ")
	var boss: FriedEggBoss = g.boss
	if boss and g.in_boss_fight() and pos.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS + r * 0.6:
		if boss.take_chip(Combat.boss_chip("cracker", g.mods)):
			g.sfx.play("splat", 1.1)


static func _cause_of(d: OilDrop) -> String:
	match d.kind:
		OilDrop.Kind.OIL, OilDrop.Kind.PEPPER:
			return "oil"
		OilDrop.Kind.TINE:
			return "tine"
	return "shot"


static func _chip_kind(d: OilDrop) -> String:
	match d.kind:
		OilDrop.Kind.BUTTON:
			return "button"
		OilDrop.Kind.TINE:
			return "tine"
	return "needle"


## Волна змеи (ударная волна таблетки): только картинка — оглушение раздаёт abilities.gd, змею не задевает.
func spawn_snake_wave(pos: Vector2, reach: float) -> void:
	var w := Shockwave.new()
	w.z_index = 1
	w.setup_stun(pos, reach)
	w.friendly = true
	g.world.add_child(w)
	waves.append(w)


## Выстрел змеи во что-то попал? true — снаряд израсходован.
func _snake_shot_hits(d: OilDrop) -> bool:
	for bear: TeddyBear in g.enemies.bears:
		if bear.position.distance_to(d.position) < OilDrop.RADIUS + TeddyBear.RADIUS:
			if d.kind != OilDrop.Kind.CRACKER:
				g.enemies.snake_hits_bear(bear, d.vel.normalized() * 260.0)
			return true
	for f: Fork in g.enemies.forks:
		if f.touches(d.position, OilDrop.RADIUS):
			if d.kind == OilDrop.Kind.CRACKER:
				return true
			if f.hurts(d.position):  # в лоб — отскакивает от зубцов (и от вертушки)
				g.fx.burst(d.position, Color(0.8, 0.8, 0.85), 5)
				g.sfx.play("clang", 1.6, -8.0)
			else:
				g.enemies.break_fork(f, "МЕТКО! ")
			return true
	for p: Pill in g.enemies.pills:
		if not p.in_air() and p.position.distance_to(d.position) < OilDrop.RADIUS + Pill.RADIUS:
			if d.kind != OilDrop.Kind.CRACKER:
				g.enemies.eat_pill(p, "МЕТКО! ")
			return true
	for m: Matryoshka in g.enemies.dolls:
		if m.can_bite() and m.position.distance_to(d.position) < OilDrop.RADIUS + m.radius():
			if d.kind != OilDrop.Kind.CRACKER:
				g.enemies.snake_hits_doll(m, "МЕТКО! ")
			return true
	var boss: FriedEggBoss = g.boss
	if boss and g.in_boss_fight() and boss.height < 20.0 \
			and d.position.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS * 0.9:
		if d.kind == OilDrop.Kind.CRACKER:
			return true
		var yolk := boss.position + FriedEggBoss.YOLK_OFFSET
		var into_yolk := boss.is_yolk_open() and d.position.distance_to(yolk) < FriedEggBoss.YOLK_RADIUS + 14.0
		if boss.take_chip(Combat.shot_chip(_chip_kind(d), into_yolk, g.mods)):
			g.sfx.play("splat", 1.3)
		g.fx.burst(d.position, Color(1, 0.95, 0.7), 6)
		return true
	return false


func update_drops(delta: float) -> void:
	var snake: Snake = g.snake
	for d: OilDrop in drops.duplicate():
		if d.is_queued_for_deletion():  # поле очищено в этом же кадре (этап пройден, яичница съедена)
			continue
		d.update(delta, snake.head_pos)
		if d.is_missed():  # промах лежит на полу и никого не ранит
			if d.miss_done():
				remove_drop(d)
			continue
		if d.from_snake:
			var contact := _snake_shot_hits(d)
			if d.kind == OilDrop.Kind.CRACKER and (contact or d.should_explode()):
				explode(d.position, true)
				remove_drop(d)
			elif contact:
				remove_drop(d)
			elif _missed(d):
				_end_flight(d)
			continue
		if d.kind == OilDrop.Kind.CRACKER:
			var touched := snake.alive and not snake.is_hopping() and d.position.distance_to(snake.head_pos) < OilDrop.RADIUS + Snake.HEAD_RADIUS
			if d.should_explode() or touched:
				explode(d.position, false)
				remove_drop(d)
			continue
		# в прыжке малышки змея над полем: снаряды пролетают под ней, а не тратятся о неё (v12.0)
		var hit := snake.alive and not snake.is_hopping() and d.position.distance_to(snake.head_pos) < OilDrop.RADIUS + Snake.HEAD_RADIUS * 0.8
		if hit:
			if d.kind == OilDrop.Kind.WHITE:
				snake.slow(2.5)
				g.sfx.play("splat", 0.8)
			elif snake.take_damage(1, _cause_of(d)) and d.kind == OilDrop.Kind.NEEDLE:
				snake.slow(1.2)  # иголка пришивает
			g.fx.burst(d.position, Color(1, 0.85, 0.3) if d.kind != OilDrop.Kind.WHITE else Color.WHITE, 6)
		elif d.kind in [OilDrop.Kind.BUTTON, OilDrop.Kind.NEEDLE, OilDrop.Kind.SHURIKEN, OilDrop.Kind.TINE]:  # френдли фаер
			for bear: TeddyBear in g.enemies.bears:
				if bear != d.thrower and bear.position.distance_to(d.position) < OilDrop.RADIUS + TeddyBear.RADIUS:
					var thrower: Node2D = d.thrower if is_instance_valid(d.thrower) else null
					g.enemies.friendly_hit(bear, thrower, d.vel.normalized() * 240.0)
					hit = true
					break
		if hit:
			remove_drop(d)
		elif _missed(d):
			_end_flight(d)


## Снаряд пролетел мимо: выдохся или долетел до бортика (тот, что остаётся на полу, — уже у бортика).
func _missed(d: OilDrop) -> bool:
	if d.life <= 0.0:
		return true
	if OilDrop.misses_visibly(d.kind):
		return not INNER.has_point(d.position)
	return not Balance.ARENA.has_point(d.position)


## Промах: зубец втыкается, пуговица падает и катится; остальное просто исчезает.
func _end_flight(d: OilDrop) -> void:
	if OilDrop.misses_visibly(d.kind):
		d.begin_miss(INNER)
	else:
		remove_drop(d)


func update_waves(delta: float) -> void:
	var snake: Snake = g.snake
	for w: Shockwave in waves.duplicate():
		if w.is_queued_for_deletion():
			continue
		w.update(delta)
		if not w.friendly and not snake.is_hopping() and w.hits(snake.head_pos):  # волну можно перепрыгнуть
			w.hit_done = true
			if w.stun:
				if snake.stun(1.3):
					g.sfx.play("stun")
					g.vibrate(80)
					g.fx.popup(snake.head_pos + Vector2(0, -30), "ОГЛУШЕНА!", Color(0.6, 0.8, 1))
					if not stun_hinted:
						stun_hinted = true
						g.hint("Волну таблетки можно пережить в рывке или просто держаться подальше", 3.0)
			elif snake.take_damage(1, "wave"):
				snake.push((snake.head_pos - w.position).normalized() * 500.0)
		if w.finished():
			waves.erase(w)
			w.queue_free()


## Вертушка и теневой рывок сбивают вражеские снаряды рядом с головой.
func cut_enemy_drops(center: Vector2, radius: float, keep_crackers: bool, col: Color) -> void:
	for d: OilDrop in drops.duplicate():
		if d.from_snake or d.is_missed() or (keep_crackers and d.kind == OilDrop.Kind.CRACKER):
			continue
		if d.position.distance_to(center) < radius:
			g.fx.burst(d.position, col, 4)
			remove_drop(d)
