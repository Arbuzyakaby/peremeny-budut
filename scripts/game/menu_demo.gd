extends RefCounted
## Фон главного меню: змея-демо сама охотится на медведей всех видов, из угла подглядывает яичница.

const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")

var g  # game.gd
var snake: Snake
var egg: FriedEggBoss
var t := 0.0


func _init(game) -> void:
	g = game
	for i in 7:
		_add_bear()
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


func update(delta: float) -> void:
	t += delta
	var nearest: TeddyBear = null
	for bear: TeddyBear in g.enemies.bears:
		bear.update(delta, null)
		if not bear.is_edible():
			continue
		if nearest == null or bear.position.distance_to(snake.head_pos) < nearest.position.distance_to(snake.head_pos):
			nearest = bear
	if nearest:
		snake.auto_target = nearest.position
		if nearest.position.distance_to(snake.head_pos) < Snake.HEAD_RADIUS + TeddyBear.RADIUS:
			g.enemies.bears.erase(nearest)
			g.fx.burst(nearest.position, nearest.fur, 12)
			nearest.queue_free()
			g.sfx.play("eat", 1.2, -12.0)
			snake.grow(2)
			if snake.length > 46:
				snake.length = 14
			egg.flash = 0.6
			_add_bear()
	snake.update(delta)
	egg.position.y = 700.0 + sin(t * 0.7) * 70.0  # то выглядывает, то прячется
	egg.look_dir = (snake.head_pos - egg.position).normalized()
	egg.update(delta, null)


func clear() -> void:
	g.enemies.clear(false)
	snake.queue_free()
	egg.queue_free()
