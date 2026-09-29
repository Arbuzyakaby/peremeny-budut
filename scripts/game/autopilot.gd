extends RefCounted
## Автопилот для записи видео и автотестов: змея сама охотится на цели этапа, бьёт желток,
## иногда пользуется атакой. Неуязвима, пока включён.

const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")


static func drive(g) -> void:
	var snake = g.snake
	snake.autopilot = true
	snake.auto_speed = 210.0
	snake.invuln = maxf(snake.invuln, 0.2)
	var best := Vector2(640, 360)
	var best_d := 99999.0
	for b in g.enemies.bears:
		if b.is_edible() and b.position.distance_to(snake.head_pos) < best_d:
			best_d = b.position.distance_to(snake.head_pos)
			best = b.position
	for f in g.enemies.forks:
		var p: Vector2 = f.position - f.facing() * 40.0  # заходим сзади
		if p.distance_to(snake.head_pos) < best_d:
			best_d = p.distance_to(snake.head_pos)
			best = p
	for p in g.enemies.pills:
		if p.is_edible() and p.position.distance_to(snake.head_pos) < best_d:
			best_d = p.position.distance_to(snake.head_pos)
			best = p.position
	for m in g.enemies.dolls:
		if m.can_bite() and m.position.distance_to(snake.head_pos) < best_d:
			best_d = m.position.distance_to(snake.head_pos)
			best = m.position
	if g.boss and g.in_boss_fight() and g.boss.is_yolk_open():
		best = g.boss.position + FriedEggBoss.YOLK_OFFSET
	snake.auto_target = best
	if g.abilities.type >= 0 and randf() < 0.01:
		g.abilities.use()
