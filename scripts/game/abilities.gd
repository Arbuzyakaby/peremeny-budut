extends RefCounted
## Атаки, которые змея перенимает у побеждённых врагов.
## - Особые медведи (1–7): удар с разбега, пуговицы, вертушка, иглы, теневой рывок, хлопушка, заплатка.
##   Обычный медведь вместо атаки возвращает стамину.
## - Вилки (v8.0): столовая — залп зубцов (недалеко), десертная — короткий выпад, вилы — укол в пол
##   перед головой. Таблетки — ударная волна, которая оглушает врагов вокруг и сбивает снаряды.
##   Атаку даёт каждая Balance.FORK_PILL_EVERY-я вилка или таблетка и только в пустой слот (или в ту же
##   атаку): медвежья атака не пропадает оттого, что змея ест таблетки.
## Между атаками — пауза Balance.ABILITY_COOLDOWN, заряды копятся не выше Combat.ability_max.

const Balance = preload("res://scripts/core/balance.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const OilDrop = preload("res://scripts/entities/oil_drop.gd")

enum { TINES = 10, LUNGE = 11, POGO = 12, WAVE = 13 }

var g  # game.gd
var type := -1
var charges := 0
var hinted := false
var hinted_sources := {}
var dash_hit_boss := false
var dash_kind := "dash"  # чем таранит текущий рывок: "dash" (медведи) или "lunge" (выпад вилки)
var infinite := false  # панель разработчика
var cooldown := 0.0
var fork_kills := 0    # к следующей атаке вилки
var pill_kills := 0    # к следующей атаке таблетки


func _init(game) -> void:
	g = game


func reset() -> void:
	type = -1
	charges = 0
	cooldown = 0.0
	fork_kills = 0
	pill_kills = 0


## Съеден медведь: его атака (особый) или стамина (обычный).
func gain_bear(bear_type: int) -> void:
	if not Balance.ABILITIES.has(bear_type):  # обычный медведь восстанавливает силы
		var snake: Snake = g.snake
		snake.stamina = minf(snake.stamina + 0.3, 1.0)
		return
	gain(bear_type)


## Сломана вилка вида kind: каждая FORK_PILL_EVERY-я даёт атаку этого вида.
func gain_fork(kind: int) -> void:
	fork_kills += 1
	if fork_kills >= Balance.FORK_PILL_EVERY:
		if _slot_free_for(Balance.FORK_ABILITY[clampi(kind, 0, 2)]):
			fork_kills = 0
			gain(Balance.FORK_ABILITY[clampi(kind, 0, 2)])


## Съедена таблетка: каждая FORK_PILL_EVERY-я даёт ударную волну.
func gain_pill() -> void:
	pill_kills += 1
	if pill_kills >= Balance.FORK_PILL_EVERY and _slot_free_for(Balance.PILL_ABILITY):
		pill_kills = 0
		gain(Balance.PILL_ABILITY)


## Слот пуст или в нём та же атака и есть куда копить.
func _slot_free_for(t: int) -> bool:
	if type < 0 or charges <= 0:
		return true
	return type == t and charges < Combat.ability_max(t, g.mods)


## Выдать атаку t (медвежью — всегда, заменяя текущую; так было и до v8.0).
func gain(t: int) -> void:
	var snake: Snake = g.snake
	var info: Dictionary = Balance.ABILITIES[t]
	var add := Combat.ability_charges(t, g.mods)
	if t == type:
		charges = mini(charges + add, Combat.ability_max(t, g.mods))
	else:
		type = t
		charges = add
		g.fx.popup(snake.head_pos + Vector2(0, -40), "НОВАЯ АТАКА: " + info["name"], Color(0.5, 1, 0.5))
	g.sfx.play("power")
	g.hud.set_ability(type, info["name"], charges)
	var src: String = info["source"]
	if not g.hints_on():
		return
	var how := "Кнопка АТАКА" if g.touch_on() else "Пробел / ЛКМ"
	if not hinted:
		hinted = true
		hinted_sources[src] = true
		g.hud.show_banner(how + " — атака съеденного врага!", Color(0.5, 1, 0.5), 1.8)
	elif not hinted_sources.has(src):
		hinted_sources[src] = true
		var text := "Каждая 2-я вилка даёт её приём" if src == "fork" else "Каждая 2-я таблетка даёт ударную волну"
		g.hint(text + " — если слот атаки пуст", 3.0)


func update(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	update_dash()


func use() -> void:
	var snake: Snake = g.snake
	if type < 0 or charges <= 0 or not snake.alive or snake.is_stunned() or cooldown > 0.0:
		return
	var info: Dictionary = Balance.ABILITIES[type]
	if not snake.spend(Combat.ability_cost(type, g.mods)):
		g.sfx.play("no_stamina")
		g.fx.popup(snake.head_pos + Vector2(0, -30), "Нет сил!", Color(0.6, 0.8, 1))
		return
	cooldown = Balance.ABILITY_COOLDOWN
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
			snake.dash(0.28)
			dash_hit_boss = false
			dash_kind = "dash"
			g.sfx.play("whoosh", 1.2)
		TeddyBear.Type.KARATE:
			snake.spin_t = 0.35
			g.sfx.play("spin")
			_spin()
		TeddyBear.Type.NINJA:
			snake.dash(0.22, Snake.DASH_SPEED * 1.25, true)
			dash_hit_boss = false
			dash_kind = "dash"
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
		TINES:
			for i in 3:
				var d: OilDrop = g.shots.spawn_drop(muzzle, dir.rotated((i - 1) * 0.18) * 520.0, OilDrop.Kind.TINE)
				d.from_snake = true
				d.life = Balance.TINE_RANGE
			g.sfx.play("fork_volley")
		LUNGE:
			snake.dash(0.17, Snake.DASH_SPEED * 1.1)
			dash_hit_boss = false
			dash_kind = "lunge"
			g.sfx.play("fork_dash")
		POGO:
			_pogo(snake.head_pos + dir * Balance.POGO_REACH)
		WAVE:
			_pill_wave(snake.head_pos)
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
	_chip_boss_near(head, r * 0.8, "spin", "kick")
	g.add_shake(6.0)


## Укол вилами: удар в пол перед головой — ломает вилки и сбивает медведей в небольшом круге.
func _pogo(at: Vector2) -> void:
	var r := Balance.POGO_RADIUS
	g.sfx.play("fork_pogo")
	g.add_shake(8.0)
	g.fx.burst(at, Color(0.55, 0.36, 0.2), 16, 0.9)
	for bear: TeddyBear in g.enemies.bears.duplicate():
		if bear.position.distance_to(at) < r + TeddyBear.RADIUS:
			g.enemies.snake_hits_bear(bear, (bear.position - at).normalized() * 320.0)
	for f: Fork in g.enemies.forks.duplicate():
		if f.position.distance_to(at) < r + 16.0:
			g.enemies.break_fork(f, "УКОЛ! ")
	for p: Pill in g.enemies.pills.duplicate():
		if not p.in_air() and p.position.distance_to(at) < r + Pill.RADIUS:
			g.enemies.eat_pill(p, "УКОЛ! ")
	var boss: FriedEggBoss = g.boss
	if boss and g.in_boss_fight() and at.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS + r * 0.5:
		if boss.take_chip(Combat.boss_chip("pogo", g.mods)):
			g.sfx.play("splat", 0.9)


## Ударная волна таблетки: оглушает медведей и вилки вокруг, сбивает вражеские снаряды. Яичницу не ранит.
func _pill_wave(at: Vector2) -> void:
	var r := Balance.PILL_WAVE_REACH
	g.shots.spawn_snake_wave(at, r)
	g.sfx.play("pill_land", 1.2)
	g.add_shake(7.0)
	for bear: TeddyBear in g.enemies.bears.duplicate():
		if bear.position.distance_to(at) < r:
			g.enemies.snake_hits_bear(bear, (bear.position - at).normalized() * 220.0)
	for f: Fork in g.enemies.forks:
		if f.position.distance_to(at) < r and f.st != Fork.St.DIZZY:
			f.st = Fork.St.DIZZY
			f.st_t = Balance.PILL_WAVE_STUN
			f.vel = (f.position - at).normalized() * 160.0
			f.leave_pincer()
	g.shots.cut_enemy_drops(at, r * 0.8, false, Color(0.7, 1, 0.95))


func _chip_boss_near(head: Vector2, reach: float, kind: String, snd: String) -> void:
	var boss: FriedEggBoss = g.boss
	if boss and g.in_boss_fight() and head.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS + reach:
		if boss.take_chip(Combat.boss_chip(kind, g.mods)):
			g.fx.burst(boss.position + (head - boss.position).normalized() * FriedEggBoss.WHITE_RADIUS * 0.8, Color.WHITE, 12)
			g.sfx.play(snd)


## Рывок (боксёр, ниндзя, выпад вилки): сбивает медведей по пути, ломает вилки, таранит яичницу.
func update_dash() -> void:
	var snake: Snake = g.snake
	if snake == null or not snake.is_dashing():
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
		if boss.take_chip(Combat.boss_chip(dash_kind, g.mods)):
			g.sfx.play("punch")
			g.add_shake(14.0)
			g.fx.burst(snake.head_pos, Color.WHITE, 14)
		snake.push((snake.head_pos - boss.position).normalized() * 600.0)
		snake.dash_t = 0.0

