extends RefCounted
## Фон главного меню: змея-демо сама охотится на медведей всех видов и на матрёшек (раскрывает их
## и ест малышек), из угла подглядывает яичница. Пасхалка: пять тычков в яичницу — она обижается
## и прячется.

const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")

const EGG_POKES := 5

var g  # game.gd
var snake: Snake
var egg: FriedEggBoss
var t := 0.0
var pokes := 0
var hide_t := 0.0  # обиженная яичница прячется


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


func _add_bear() -> void:
	g.enemies.spawn_bear(randi() % 8).position.x = randf_range(560, 1220)


func _add_doll() -> void:
	var m: Matryoshka = g.enemies.spawn_doll(Matryoshka.Size.BIG, Vector2(randf_range(620, 1180), randf_range(120, 600)))
	m.speed *= 0.7


func update(delta: float) -> void:
	t += delta
	hide_t = maxf(hide_t - delta, 0.0)
	var target: Node2D = null
	for bear: TeddyBear in g.enemies.bears:
		bear.update(delta, null)
		if bear.is_edible() and (target == null or _closer(bear, target)):
			target = bear
	for m: Matryoshka in g.enemies.dolls:
		m.update(delta, Vector2(-9999, -9999), Vector2.ZERO, false)  # в меню малышки не нападают
		if m.can_bite() and (target == null or _closer(m, target)):
			target = m
	if target:
		snake.auto_target = target.position
		if target.position.distance_to(snake.head_pos) < Snake.HEAD_RADIUS + 20.0:
			_bite(target)
	snake.update(delta)
	var peek := 700.0 + sin(t * 0.7) * 70.0  # то выглядывает, то прячется
	egg.position.y = move_toward(egg.position.y, 900.0 if hide_t > 0.0 else peek, delta * (400.0 if hide_t > 0.0 else 200.0))
	egg.look_dir = (snake.head_pos - egg.position).normalized()
	egg.update(delta, null)


func _closer(a: Node2D, b: Node2D) -> bool:
	return a.position.distance_to(snake.head_pos) < b.position.distance_to(snake.head_pos)


func _bite(target: Node2D) -> void:
	if target is Matryoshka:
		var m: Matryoshka = target
		if m.is_last():
			g.enemies.dolls.erase(m)
			g.fx.burst(m.position, m.sarafan(), 10)
			m.queue_free()
		else:
			g.enemies.open_doll(m)
		g.sfx.play("doll_open", 1.1, -12.0)
		if g.enemies.dolls.is_empty():
			_add_doll()
	else:
		var bear: TeddyBear = target
		g.enemies.bears.erase(bear)
		g.fx.burst(bear.position, bear.fur, 12)
		bear.queue_free()
		g.sfx.play("eat", 1.2, -12.0)
		_add_bear()
	snake.grow(2)
	if snake.length > 46:
		snake.length = 14
	egg.flash = 0.6


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
	g.enemies.clear(false)
	snake.queue_free()
	egg.queue_free()
