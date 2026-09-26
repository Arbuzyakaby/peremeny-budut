extends RefCounted
## Атаки, которые змея перенимает у съеденных особых медведей: удар с разбега, пуговицы, вертушка,
## иглы, теневой рывок, хлопушка, заплатка. Обычный медведь вместо атаки возвращает стамину.

const Balance = preload("res://scripts/core/balance.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const OilDrop = preload("res://scripts/entities/oil_drop.gd")

var g  # game.gd
var type := -1
var charges := 0
var hinted := false
var dash_hit_boss := false
var infinite := false  # панель разработчика


func _init(game) -> void:
	g = game


func reset() -> void:
	type = -1
	charges = 0


func gain(bear_type: int) -> void:
	var snake: Snake = g.snake
	if not Balance.ABILITIES.has(bear_type):  # обычный медведь восстанавливает силы
		snake.stamina = minf(snake.stamina + 0.3, 1.0)
		return
	var info: Dictionary = Balance.ABILITIES[bear_type]
	var add := Combat.ability_charges(bear_type, g.mods)
	if bear_type == type:
		charges += add
	else:
		type = bear_type
		charges = add
		g.fx.popup(snake.head_pos + Vector2(0, -40), "НОВАЯ АТАКА: " + info["name"], Color(0.5, 1, 0.5))
	g.sfx.play("power")
	g.hud.set_ability(type, info["name"], charges)
	if not hinted and g.hints_on():
		hinted = true
		var how := "Кнопка АТАКА" if g.touch_on() else "Пробел / ЛКМ"
		g.hud.show_banner(how + " — атака съеденного медведя!", Color(0.5, 1, 0.5), 1.8)


func use() -> void:
	var snake: Snake = g.snake
	if type < 0 or charges <= 0 or not snake.alive or snake.is_stunned():
		return
	var info: Dictionary = Balance.ABILITIES[type]
	if not snake.spend(Combat.ability_cost(type, g.mods)):
		g.sfx.play("no_stamina")
		g.fx.popup(snake.head_pos + Vector2(0, -30), "Нет сил!", Color(0.6, 0.8, 1))
		return
	var dir := Vector2.from_angle(snake.heading)
	var muzzle := snake.head_pos + dir * 24.0
	match type:
		TeddyBear.Type.THROWER:
			g.shots.spawn_drop(muzzle, dir * 560.0, OilDrop.Kind.BUTTON).from_snake = true
			g.sfx.play("snake_shot")
		TeddyBear.Type.SEAMSTRESS:
			for i in 3:
				g.shots.spawn_drop(muzzle, dir.rotated((i - 1) * 0.14) * 650.0, OilDrop.Kind.NEEDLE).from_snake = true
			g.sfx.play("needle")
		TeddyBear.Type.BOXER:
			snake.dash(0.32)
			dash_hit_boss = false
			g.sfx.play("whoosh", 1.2)
		TeddyBear.Type.KARATE:
			snake.spin_t = 0.35
			g.sfx.play("spin")
			_spin()
		TeddyBear.Type.NINJA:
			snake.dash(0.24, Snake.DASH_SPEED * 1.3, true)
			dash_hit_boss = false
			g.fx.burst(snake.head_pos, Color(0.3, 0.3, 0.35), 18, 0.9)
			g.sfx.play("poof")
		TeddyBear.Type.BOMBER:
			var c: OilDrop = g.shots.spawn_drop(muzzle, dir * 520.0, OilDrop.Kind.CRACKER)
			c.from_snake = true
			c.fuse = 0.9
			g.sfx.play("fuse")
		TeddyBear.Type.MEDIC:
			if snake.heal():
				g.fx.popup(snake.head_pos + Vector2(0, -40), "+1 ЖИЗНЬ", Color(1, 0.5, 0.6))
			else:
				snake.shield += 1
				g.fx.popup(snake.head_pos + Vector2(0, -40), "ЩИТ!", Color(0.6, 0.85, 1))
			g.sfx.play("heal")
			g.fx.burst(snake.head_pos, Color(0.5, 1, 0.6), 14)
	if not infinite:
		charges -= 1
	var name: String = info["name"]
	if charges <= 0:
		type = -1
	g.hud.set_ability(type, name, charges)


## Вертушка: раскидывает врагов вокруг головы, сбивает вражеские снаряды, задевает яичницу.
func _spin() -> void:
	var head: Vector2 = g.snake.head_pos
	var r := Balance.SPIN_RADIUS
	for bear: TeddyBear in g.enemies.bears.duplicate():
		if bear.position.distance_to(head) < r:
			g.enemies.snake_hits_bear(bear, (bear.position - head).normalized() * 380.0)
	for f: Fork in g.enemies.forks.duplicate():
		if f.position.distance_to(head) < r:
			g.enemies.break_fork(f, "ВЕРТУШКА! ")
	for p: Pill in g.enemies.pills.duplicate():
		if not p.in_air() and p.position.distance_to(head) < r:
			g.enemies.eat_pill(p, "ВЕРТУШКА! ")
	g.shots.cut_enemy_drops(head, r, false, Color(1, 1, 0.8))
	var boss: FriedEggBoss = g.boss
	if boss and g.in_boss_fight() and head.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS + r * 0.8:
		if boss.take_chip(Combat.boss_chip("spin", g.mods)):
			g.fx.burst(boss.position + (head - boss.position).normalized() * FriedEggBoss.WHITE_RADIUS * 0.8, Color.WHITE, 12)
			g.sfx.play("kick")
	g.add_shake(6.0)


## Рывок (боксёр или ниндзя): сбивает медведей по пути, ломает вилки, таранит яичницу.
func update_dash() -> void:
	var snake: Snake = g.snake
	if not snake.is_dashing():
		return
	for bear: TeddyBear in g.enemies.bears.duplicate():
		if bear.position.distance_to(snake.head_pos) < Snake.HEAD_RADIUS + TeddyBear.RADIUS + 8.0:
			g.enemies.snake_hits_bear(bear, Vector2.from_angle(snake.heading) * 420.0)
	if snake.shadow_dash:  # теневой рывок проходит сквозь снаряды и режет их
		g.shots.cut_enemy_drops(snake.head_pos, 40.0, true, Color(0.4, 0.4, 0.45))
	var boss: FriedEggBoss = g.boss
	if boss and g.in_boss_fight() and not dash_hit_boss \
			and snake.head_pos.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS * 0.85:
		dash_hit_boss = true
		if boss.take_chip(Combat.boss_chip("dash", g.mods)):
			g.sfx.play("punch")
			g.add_shake(14.0)
			g.fx.burst(snake.head_pos, Color.WHITE, 14)
		snake.push((snake.head_pos - boss.position).normalized() * 600.0)
		snake.dash_t = 0.0
