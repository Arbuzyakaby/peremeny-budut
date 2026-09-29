extends RefCounted
## Враги на поле: медведи, вилки, таблетки, матрёшки (v9.0). Спавн, обновление, столкновения со змеёй
## и между собой (френдли фаер), цели этапа, помощники на этапах 2–4 и подкрепления яичнице.
## Матрёшки собираются наборами: набор — большая кукла и всё, что из неё выскочит; цель этапа — наборы.

const Balance = preload("res://scripts/core/balance.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const OilDrop = preload("res://scripts/entities/oil_drop.gd")
const Tips = preload("res://scripts/core/tips.gd")
const Squad = preload("res://scripts/game/squad.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const DollShell = preload("res://scripts/entities/doll_shell.gd")

## Кощеева игла (пасхалка): так редко в малышке находится яйцо, а в яйце — игла.
const KOSCHEI_CHANCE := 0.03
const RIBBON_SLOW := 0.9      # лента хоровода путает змею на столько секунд
const RIBBON_REACH := 11.0

const SPECIAL_BEARS := [TeddyBear.Type.BOXER, TeddyBear.Type.THROWER, TeddyBear.Type.KARATE, TeddyBear.Type.SEAMSTRESS,
	TeddyBear.Type.NINJA, TeddyBear.Type.BOMBER, TeddyBear.Type.MEDIC]

var g  # game.gd (без типа — чтобы не было циклического preload)
var bears: Array[TeddyBear] = []
var forks: Array[Fork] = []
var pills: Array[Pill] = []
var dolls: Array[Matryoshka] = []
var doll_sets := {}           # номер набора → сколько кукол этого набора ещё на поле
var doll_set_id := 0
var doll_paint := 0
var ribbon_cd := 0.0
var doll_hinted := {}
var coop_override := -1       # панель разработчика: уровень отряда вручную (−1 — как в сложности)
var friendly_hits := 0
var fork_hinted := false
var fork_atk_hinted := {}
var helper_t := 5.0
var reinforce_t := 6.0
var reinforce_kind := 0
var reinforce_hinted := false
var squad: Squad


func _init(game) -> void:
	g = game
	squad = Squad.new()


## Кооператив врагов (только Сложная и Ультра — см. squad.gd).
func update_squad(delta: float, snake: Snake) -> void:
	squad.level = coop_override if coop_override >= 0 else int(g.cfg.get("coop", 0))
	squad.update(delta, snake, self)


func count() -> int:
	return bears.size() + forks.size() + pills.size() + dolls.size()


## Убрать всех врагов с поля (между этапами).
func clear(with_fx := true) -> void:
	for b in bears:
		if with_fx:
			g.fx.burst(b.position, b.fur, 10)
		b.queue_free()
	bears.clear()
	for f in forks:
		if with_fx:
			g.fx.burst(f.position, Color(0.6, 0.35, 0.2), 10)
		f.queue_free()
	forks.clear()
	for p in pills:
		if with_fx:
			g.fx.burst(p.position, p.cols[0], 10)
		p.queue_free()
	pills.clear()
	for m in dolls:
		if with_fx:
			g.fx.burst(m.position, m.sarafan(), 10)
		m.queue_free()
	dolls.clear()
	doll_sets.clear()
	squad.reset()


func spawn_for_stage(stage: int, goal_total: int) -> void:
	helper_t = 4.0
	match stage:
		0:
			for k in Balance.BEARS_ON_FIELD:
				spawn_bear(pick_bear_type())
		1:
			for k in mini(3, goal_total):
				spawn_fork()
		2:
			for k in mini(3, goal_total):
				spawn_pill()
		Balance.DOLL_STAGE:
			for k in mini(Balance.DOLL_SETS_ON_FIELD, goal_total):
				spawn_doll_set()


func spawn_pos(margin := 40.0) -> Vector2:
	var pos := Vector2.ZERO
	var b: Rect2 = g.bounds
	var avoid: Vector2 = g.snake.head_pos if g.snake else Vector2(-9999, -9999)
	for attempt in 20:
		pos = Vector2(randf_range(b.position.x + margin, b.end.x - margin), randf_range(b.position.y + margin, b.end.y - margin))
		if pos.distance_to(avoid) > 260.0 and (g.boss == null or pos.distance_to(g.boss.position) > 200.0):
			break
	return pos


# ---------------------------------------------------------------- медведи

func pick_bear_type() -> int:
	var a: float = g.cfg["bear_aggr"]
	var progress := float(g.goal_done) / maxf(g.goal_total, 1.0)
	var weights := [
		[TeddyBear.Type.BOXER, (0.1 + progress * 0.2) * a],
		[TeddyBear.Type.THROWER, (0.06 + progress * 0.14) * a],
		[TeddyBear.Type.SEAMSTRESS, (0.03 + progress * 0.14) * a],
		[TeddyBear.Type.KARATE, (0.0 + progress * 0.2) * a],
		[TeddyBear.Type.NINJA, (0.0 + progress * 0.16) * a],
		[TeddyBear.Type.BOMBER, (0.02 + progress * 0.14) * a],
		[TeddyBear.Type.MEDIC, (0.03 + progress * 0.1) * a],
	]
	var total := 0.0
	for w in weights:
		total += w[1]
	var squash := 0.85 / total if total > 0.85 else 1.0  # обычных медведей всегда хоть немного
	var r := randf()
	for w in weights:
		r -= w[1] * squash
		if r < 0.0:
			return w[0]
	return TeddyBear.Type.NORMAL


func spawn_bear(type: int, at := Vector2.INF) -> TeddyBear:
	var bear := TeddyBear.new()
	bear.z_index = 1
	var speed_mult: float = g.cfg["bear_speed"]
	var pos := spawn_pos() if at == Vector2.INF else at
	bear.setup(pos, (55.0 + g.goal_done * 4.0) * speed_mult, g.bounds, type, g.cfg["bear_aggr"])
	bear.throw_item.connect(func(p: Vector2, v: Vector2, kind: int) -> void: g.shots.spawn_drop(p, v, kind).thrower = bear)
	bear.sound.connect(g.sfx.play)
	bear.puff.connect(func(p: Vector2) -> void: g.fx.burst(p, Color(0.35, 0.35, 0.4), 16, 0.9))
	bear.allies = bears
	g.world.add_child(bear)
	bears.append(bear)
	g.seen("bear_%d" % type)
	return bear


func update_bears(delta: float, snake: Snake, fighting: bool) -> void:
	for bear: TeddyBear in bears.duplicate():
		if bear.is_queued_for_deletion():  # съеден или поле очищено (этап пройден) в этом же кадре
			continue
		bear.update(delta, snake)
		if not fighting or not snake.alive or snake.is_hopping():
			continue
		if bear.position.distance_to(snake.head_pos) < Snake.HEAD_RADIUS + TeddyBear.RADIUS:
			if bear.is_shielded():  # пузырь медсестры: отскакиваем
				bear.pop_shield()
				snake.push((snake.head_pos - bear.position).normalized() * 420.0)
				g.fx.burst(bear.position, Color(0.6, 1, 0.8), 10)
			elif bear.is_edible():
				eat_bear(bear)
	# таран: боксёр в рывке или разозлённый медведь сбивают других медведей
	for a: TeddyBear in bears.duplicate():
		if not is_instance_valid(a) or a.is_queued_for_deletion() or not a.is_ramming():
			continue
		for b: TeddyBear in bears:
			if b != a and a.position.distance_to(b.position) < TeddyBear.RADIUS * 2.0 + 4.0:
				if friendly_hit(b, a, (b.position - a.position).normalized() * 320.0):
					a.on_ram_hit()
					break


## Враг попал по медведю. Возвращает true, если удар засчитан.
func friendly_hit(victim: TeddyBear, attacker: Node2D, push_vel: Vector2) -> bool:
	if not victim.hit_by_friend(attacker, push_vel):
		return false
	friendly_hits += 1
	g.add_score(Balance.FRIENDLY_POINTS, victim.position, "ФРЕНДЛИ ФАЕР! ")
	g.fx.burst(victim.position, Color(1, 0.95, 0.6), 8)
	g.add_shake(5.0)
	if friendly_hits == 1:
		g.hud.show_banner("Враги дерутся между собой!", Color(1, 0.6, 0.9), 1.6)
	return true


## Змея сбила медведя атакой.
func snake_hits_bear(bear: TeddyBear, push_vel: Vector2) -> void:
	if not bears.has(bear):  # уже убран с поля — очков за него нет
		return
	if bear.hit_by_friend(null, push_vel):
		g.add_score(Balance.FRIENDLY_POINTS, bear.position, "БАЦ! ")
		g.fx.burst(bear.position, Color(0.6, 1, 0.6), 8)


func eat_bear(bear: TeddyBear) -> void:
	if not bears.has(bear):  # второй раз того же медведя не съесть (и после очистки поля — тоже)
		return
	bears.erase(bear)
	for other in bears:  # обидчика съели — мстить некому
		if other.grudge == bear:
			other.grudge = null
	g.fx.burst(bear.position, bear.fur, 14)
	g.fx.burst(bear.position, bear.bow_color, 6)
	var dizzy := bear.is_dizzy()
	var pts := Combat.bear_points(bear.type, dizzy, g.cfg, g.mods)
	g.add_score_raw(pts, bear.position, "НОКАУТ! " if dizzy else "")
	bear.queue_free()
	g.snake.grow(3)
	g.abilities.gain_bear(bear.type)
	if not g.is_goal_stage(0):  # помощники на других этапах — только атака и очки
		g.sfx.play("eat")
		return
	g.bears_eaten += 1
	g.sfx.play("eat", 1.0 + 0.02 * g.bears_eaten)
	g.goal_progress(0)
	if g.is_goal_stage(0) and g.goal_done + bears.size() < g.goal_total:
		spawn_bear(pick_bear_type())


## На этапах вилок и таблеток по полю бродят пара медведей — источник атак.
func update_helpers(delta: float) -> void:
	if g.stage == 0:
		return
	helper_t -= delta
	if helper_t <= 0.0 and bears.size() < Balance.HELPERS_MAX:
		helper_t = Balance.HELPER_INTERVAL
		spawn_bear(([TeddyBear.Type.NORMAL] + SPECIAL_BEARS).pick_random())


## Во время боя с яичницей на помощь ей по очереди приходят медведи, вилки и таблетки.
func update_reinforcements(delta: float) -> void:
	reinforce_t -= delta
	if reinforce_t > 0.0 or count() >= Balance.REINFORCE_MAX:
		return
	reinforce_t = Balance.REINFORCE_INTERVAL * clampf(g.cfg["tempo"], 0.6, 1.3)
	var pos := Vector2.ZERO
	match reinforce_kind % 4:
		0:
			pos = spawn_bear(SPECIAL_BEARS.pick_random()).position
		1:
			pos = spawn_fork().position
		2:
			pos = spawn_pill().position
		3:
			pos = spawn_doll(Matryoshka.Size.MIDDLE).position
	reinforce_kind += 1
	g.fx.popup(pos + Vector2(0, -30), "НА ПОМОЩЬ ЯИЧНИЦЕ!", Color(1, 0.8, 0.5))
	if not reinforce_hinted:
		reinforce_hinted = true
		g.hud.show_banner("На помощь яичнице идут медведи, вилки, таблетки и матрёшки!", Color(1, 0.7, 0.4), 2.0)
		g.hint("Съешь медведя — его атака ранит яичницу. Вилку в спринте можно направить в неё!", 4.0)


# ---------------------------------------------------------------- вилки

## Вид следующей вилки: сначала в основном столовые, к концу этапа — больше десертных и вил.
func pick_fork_kind() -> int:
	var progress := float(g.goal_done) / maxf(g.goal_total, 1.0)
	var a: float = g.cfg["bear_aggr"]
	var r := randf()
	if r < (0.12 + 0.2 * progress) * a:
		return Fork.Kind.DESSERT
	if r < (0.22 + 0.35 * progress) * a:
		return Fork.Kind.PITCH
	return Fork.Kind.TABLE


func spawn_fork(at := Vector2.INF, kind := -1) -> Fork:
	var f := Fork.new()
	f.z_index = 1
	f.setup(spawn_pos(60.0) if at == Vector2.INF else at, g.bounds, g.cfg["bear_speed"], g.cfg["bear_aggr"], g.cfg["tempo"],
		pick_fork_kind() if kind < 0 else kind)
	f.sound.connect(g.sfx.play)
	f.attack.connect(_on_fork_attack.bind(f))
	g.world.add_child(f)
	forks.append(f)
	g.seen("fork_%d" % f.kind)
	return f


func _on_fork_attack(kind: String, data: Dictionary, f: Fork) -> void:
	if not is_instance_valid(f):
		return
	match kind:
		"start":
			var atk: int = data["atk"]
			g.seen("fork_atk_%d" % atk)
			if not fork_atk_hinted.has(atk) and atk != Fork.Atk.LUNGE:
				fork_atk_hinted[atk] = true
				g.hint(Tips.FORK_ATTACK_HINTS[atk], 3.5)
		"tines":
			for d: Vector2 in data["dirs"]:
				var drop: OilDrop = g.shots.spawn_drop(data["from"], d * 430.0 * float(g.cfg["proj_speed"]), OilDrop.Kind.TINE)
				drop.thrower = f
		"pogo":
			var at: Vector2 = data["at"]
			var r: float = data["radius"]
			var snake: Snake = g.snake
			g.add_shake(8.0)
			g.fx.burst(at, Color(0.55, 0.36, 0.2), 14, 0.9)
			g.vibrate(30)
			if snake.alive and snake.head_pos.distance_to(at) < r + Snake.HEAD_RADIUS * 0.5:
				if snake.take_damage(1, "fork_pogo"):
					g.fx.popup(snake.head_pos + Vector2(0, -30), "НАКОЛОЛА!", Color(1, 0.5, 0.4))
					g.sfx.play("punch")
				snake.push((snake.head_pos - at).normalized() * 460.0)
			for b: TeddyBear in bears:
				if b.position.distance_to(at) < r + TeddyBear.RADIUS:
					friendly_hit(b, null, (b.position - at).normalized() * 300.0)


func update_forks(delta: float, snake: Snake) -> void:
	for f: Fork in forks.duplicate():
		if not is_instance_valid(f) or f.is_queued_for_deletion():
			continue
		f.update(delta, snake.head_pos, snake.alive)
		if not is_instance_valid(f):
			continue
		if snake.alive and not snake.is_hopping() and f.touches(snake.head_pos, Snake.HEAD_RADIUS):
			if f.is_pincer_windup() and snake.sprinting and not snake.is_dashing():
				pincer_breakout(f, snake)
				continue
			if snake.is_dashing():
				if f.is_whirling():  # рывок сбивает вертушку, но не ломает
					f.st = Fork.St.DIZZY
					f.st_t = 1.8
					f.vel = (f.position - snake.head_pos).normalized() * 200.0
					g.sfx.play("clang", 0.8)
					g.fx.popup(f.position + Vector2(0, -30), "СБИЛА!", Color(0.7, 0.9, 1))
				else:
					break_fork(f, "ТАРАН! ")
				continue
			if f.hurts(snake.head_pos):
				if snake.take_damage(1, "fork_whirl" if f.is_whirling() else "fork_tines"):
					g.sfx.play("punch")
					g.fx.popup(snake.head_pos + Vector2(0, -30), "ВЕРТУШКА!" if f.is_whirling() else "ЗУБЦЫ! Бей сбоку!",
						Color(1, 0.5, 0.4))
					g.fx.burst(snake.head_pos, Color(1, 0.3, 0.2), 10)
				snake.push((snake.head_pos - f.position).normalized() * 520.0)
				if not f.is_whirling():
					f.bounce()
				if not fork_hinted:
					fork_hinted = true
					g.hint("Вилку нельзя атаковать в лоб — заходи сбоку или сзади!", 3.0)
			else:
				var prefix := "СБОКУ! "
				match f.st:
					Fork.St.STUCK, Fork.St.POGO_STUCK:
						prefix = "ЗАСТРЯЛА! "
					Fork.St.DIZZY:
						prefix = "ГОЛОВОКРУЖЕНИЕ! "
					Fork.St.BALD:
						prefix = "БЕЗЗУБАЯ! "
				break_fork(f, prefix)
				continue
		if not (f.is_sprinting() or f.is_whirling()):
			continue
		for b: TeddyBear in bears:  # вилка в спринте сбивает медведей
			if f.touches(b.position, TeddyBear.RADIUS):
				friendly_hit(b, null, f.facing() * 300.0)
		var boss: FriedEggBoss = g.boss
		if boss and g.in_boss_fight() and not f.hit_boss and boss.height < 20.0 \
				and f.position.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS * 0.85:
			f.hit_boss = true
			if boss.take_chip(Combat.boss_chip("fork", g.mods)):
				g.fx.popup(f.position + Vector2(0, -30), "ВИЛКА В ЯИЧНИЦЕ!", Color(1, 0.9, 0.5))
				g.fx.burst(f.position, Color.WHITE, 12)
				g.sfx.play("splat", 0.8)
				g.add_shake(8.0)
			f.bounce()


## Прорыв из клещей: змея в спринте проходит сквозь вилку, пока та замахивается. Цена — стамина,
## вилка отлетает оглушённой, остальные вилки клещей теряют синхрон.
func pincer_breakout(f: Fork, snake: Snake) -> void:
	var cost := Squad.BREAKOUT_STAMINA / snake.stamina_max
	snake.stamina = maxf(snake.stamina - cost, 0.0)
	if snake.stamina <= 0.01:
		snake.exhausted = true
	snake.invuln = maxf(snake.invuln, 0.4)  # проскочить сквозь зубцы
	squad.breakout(f, forks)
	f.knock_back(snake.head_pos)
	g.fx.popup(f.position + Vector2(0, -30), "ПРОРЫВ!", Color(0.7, 0.9, 1))
	g.fx.burst(f.position, Color(0.8, 0.8, 0.85), 10)
	g.add_shake(5.0)
	g.vibrate(30)


func break_fork(f: Fork, prefix := "") -> void:
	if not forks.has(f):  # уже сломана или поле очищено — не считать дважды
		return
	if f.pincer_id != 0:  # сломали вилку клещей — клещи разваливаются
		squad.breakout(f, forks)
	forks.erase(f)
	g.fx.burst(f.position, Color(0.62, 0.32, 0.14), 16)
	g.fx.burst(f.position, Color(0.8, 0.8, 0.85), 8)
	g.sfx.play("clang")
	g.add_shake(6.0)
	g.add_score(Balance.FORK_POINTS, f.position, prefix)
	f.queue_free()
	g.snake.grow(1)
	g.abilities.gain_fork(f.kind)
	if g.is_goal_stage(1):
		g.forks_broken += 1
		g.goal_progress(1)
		if g.is_goal_stage(1) and g.goal_done + forks.size() < g.goal_total:
			spawn_fork()


# ---------------------------------------------------------------- таблетки

## kind < 0 — случайный вид: шайб тем больше, чем ближе конец этапа (от 25 до 50 %).
func spawn_pill(at := Vector2.INF, kind := -1) -> Pill:
	var p := Pill.new()
	p.z_index = 3
	if kind < 0:
		var progress := float(g.goal_done) / maxf(g.goal_total, 1.0)
		kind = Pill.Kind.TABLET if randf() < 0.25 + 0.25 * progress else Pill.Kind.CAPSULE
	p.setup(spawn_pos(50.0) if at == Vector2.INF else at, g.bounds, g.cfg["tempo"], g.cfg["bear_aggr"], kind)
	p.sound.connect(g.sfx.play)
	p.landed.connect(_on_pill_landed.bind(p))
	g.world.add_child(p)
	pills.append(p)
	g.seen(p.bestiary_key())
	return p


func update_pills(delta: float, snake: Snake) -> void:
	var head_vel := Vector2.from_angle(snake.heading) * Snake.BASE_SPEED
	for p: Pill in pills.duplicate():
		if p.is_queued_for_deletion():
			continue
		p.update(delta, snake.head_pos, head_vel, snake.alive)
		if snake.alive and not snake.is_hopping() and p.is_edible() and p.position.distance_to(snake.head_pos) < Pill.RADIUS + Snake.HEAD_RADIUS:
			eat_pill(p)


func eat_pill(p: Pill, prefix := "") -> void:
	if not pills.has(p):
		return
	pills.erase(p)
	g.fx.burst(p.position, p.cols[0], 12)
	g.fx.burst(p.position, p.cols[1], 8)
	g.sfx.play("eat", 1.3)
	g.add_score(Balance.PILL_POINTS, p.position, prefix)
	p.queue_free()
	g.snake.grow(2)
	g.snake.stamina = minf(g.snake.stamina + 0.2, 1.0)
	g.abilities.gain_pill()
	if g.is_goal_stage(2):
		g.pills_eaten += 1
		g.goal_progress(2)
		if g.is_goal_stage(2) and g.goal_done + pills.size() < g.goal_total:
			spawn_pill()


func _on_pill_landed(pos: Vector2, p: Pill) -> void:
	if not is_instance_valid(p) or not pills.has(p):
		return
	var snake: Snake = g.snake
	g.add_shake(9.0)
	g.fx.burst(pos, Color(0.9, 0.9, 0.95), 14, 0.8)
	g.vibrate(40)
	if snake.alive and snake.head_pos.distance_to(pos) < Pill.CRUSH_RADIUS + Snake.HEAD_RADIUS * 0.5:
		if snake.take_damage(1, "pill"):
			g.fx.popup(snake.head_pos + Vector2(0, -30), "РАЗДАВИЛО!", Color(1, 0.5, 0.4))
			g.sfx.play("hurt")
		snake.push((snake.head_pos - pos).normalized() * 450.0)
	for b: TeddyBear in bears:  # давит и медведей
		if b.position.distance_to(pos) < Pill.CRUSH_RADIUS + TeddyBear.RADIUS:
			friendly_hit(b, null, (b.position - pos).normalized() * 300.0)
	g.shots.spawn_stun_wave(pos, 200.0 + 40.0 * float(g.cfg["bear_aggr"]))


# ---------------------------------------------------------------- матрёшки (v9.0)

## Новый набор: большая матрёшка со своей росписью.
func spawn_doll_set(at := Vector2.INF) -> Matryoshka:
	doll_set_id += 1
	doll_paint += 1
	doll_sets[doll_set_id] = 1
	return spawn_doll(Matryoshka.Size.BIG, at, doll_set_id, doll_paint)


## Одна кукла. set_id = 0 — сама по себе (подкрепление яичнице), такой набор не считается.
func spawn_doll(size: int, at := Vector2.INF, set_id := 0, paint := -1) -> Matryoshka:
	var m := Matryoshka.new()
	m.z_index = 2
	m.setup(spawn_pos(60.0) if at == Vector2.INF else at, g.bounds, size, g.cfg["tempo"], g.cfg["bear_aggr"],
		g.cfg["bear_speed"])
	m.set_id = set_id
	m.paint = paint if paint >= 0 else randi() % Matryoshka.SARAFANS.size()
	m.sound.connect(g.sfx.play)
	m.landed.connect(_on_doll_landed.bind(m))
	g.world.add_child(m)
	dolls.append(m)
	g.seen(m.bestiary_key())
	return m


func update_dolls(delta: float, snake: Snake) -> void:
	ribbon_cd = maxf(ribbon_cd - delta, 0.0)
	var head_vel := Vector2.from_angle(snake.heading) * Snake.BASE_SPEED
	for m: Matryoshka in dolls.duplicate():
		if m.is_queued_for_deletion():
			continue
		m.update(delta, snake.head_pos, head_vel, snake.alive)
		if snake.alive and not snake.is_hopping() and m.can_bite() and m.position.distance_to(snake.head_pos) < m.radius() + Snake.HEAD_RADIUS:
			bite_doll(m, "НОКАУТ! " if m.is_dazed() and not m.is_last() else "")
	_separate_dolls()
	if snake.alive and ribbon_cd <= 0.0 and not snake.is_dashing():
		_check_ribbons(snake)


## Матрёшки не стоят друг в друге: соседки мягко расталкиваются (кроме прыгающих).
func _separate_dolls() -> void:
	for i in dolls.size():
		var a := dolls[i]
		if a.in_air():
			continue
		for j in range(i + 1, dolls.size()):
			var b := dolls[j]
			if b.in_air():
				continue
			var gap := a.radius() + b.radius() + 4.0
			var off := b.position - a.position
			var dist := off.length()
			if dist < gap and dist > 0.01:
				var push := off / dist * (gap - dist) * 0.5
				a.position -= push
				b.position += push


## Лента хоровода путает змею: замедление, а не урон. Выход — просвет или укус танцующей.
func _check_ribbons(snake: Snake) -> void:
	for m: Matryoshka in dolls:
		if not m.dancing or not is_instance_valid(m.ribbon_to):
			continue
		var a := m.position
		var b: Vector2 = m.ribbon_to.position
		var closest := Geometry2D.get_closest_point_to_segment(snake.head_pos, a, b)
		if closest.distance_to(snake.head_pos) < RIBBON_REACH + Snake.HEAD_RADIUS * 0.5 \
				and closest.distance_to(a) > m.radius() and closest.distance_to(b) > 12.0:
			ribbon_cd = 1.2
			snake.slow(RIBBON_SLOW)
			g.fx.popup(snake.head_pos + Vector2(0, -30), "ЛЕНТА!", Color(1, 0.55, 0.45))
			g.sfx.play("ribbon")
			if not doll_hinted.has("ribbon"):
				doll_hinted["ribbon"] = true
				g.hint(Tips.RIBBON_HINT, 3.5)
			return


## Укус (или атака змеи) по матрёшке: малышку съесть, остальных — раскрыть.
func bite_doll(m: Matryoshka, prefix := "") -> void:
	if m.is_last():
		eat_doll(m, prefix)
	else:
		open_doll(m, prefix)


## Раскрыть матрёшку: скорлупки разлетаются, изнутри выскакивают следующие куклы.
func open_doll(m: Matryoshka, prefix := "") -> void:
	if not dolls.has(m) or m.is_last():
		return
	dolls.erase(m)
	var dir := Vector2.from_angle(randf() * TAU)
	if g.snake:
		dir = (m.position - g.snake.head_pos).normalized()
	for top in [true, false]:
		var sh := DollShell.new()
		sh.setup(m.position, top, m.sarafan(), m.scarf(), float(m.spec()["scale"]), dir.rotated(-0.9 if top else 0.9))
		g.world.add_child(sh)
	g.fx.burst(m.position, Matryoshka.GOLD, 8)
	g.fx.burst(m.position, m.sarafan(), 10)
	g.sfx.play("doll_open")
	if g.state != g.State.MENU:  # в меню матрёшек раскрывает демо-змея — без очков и тряски
		g.add_shake(4.0)
		g.add_score(Balance.DOLL_OPEN_POINTS, m.position, prefix)
	var inner := Matryoshka.Size.MIDDLE if m.size == Matryoshka.Size.BIG else Matryoshka.Size.TINY
	var n := 2 if m.size == Matryoshka.Size.BIG else 1  # большая делится надвое
	var kids: Array[Matryoshka] = []
	for i in n:
		var kid := spawn_doll(inner, m.position, m.set_id, m.paint)
		kid.pop_out(dir.rotated(0.0 if n == 1 else (-0.8 if i == 0 else 0.8)))
		kids.append(kid)
	if m.set_id != 0 and doll_sets.has(m.set_id):
		doll_sets[m.set_id] = int(doll_sets[m.set_id]) - 1 + n
	m.queue_free()
	if g.state != g.State.MENU:
		g.opened_dolls += 1
	if g.snake:
		g.snake.grow(1)
		squad.scatter(kids, g.snake, g.bounds)
	if n == 2 and not doll_hinted.has("split"):
		doll_hinted["split"] = true
		g.hint(Tips.DOLL_SPLIT_HINT, 3.5)
	elif inner == Matryoshka.Size.TINY and not doll_hinted.has("tiny"):
		doll_hinted["tiny"] = true
		g.hint(Tips.DOLL_TINY_HINT, 3.5)


## Съесть малышку. Последняя малышка набора собирает набор — это и есть цель этапа.
func eat_doll(m: Matryoshka, prefix := "") -> void:
	if not dolls.has(m):
		return
	dolls.erase(m)
	g.fx.burst(m.position, m.sarafan(), 12)
	g.fx.burst(m.position, Matryoshka.GOLD, 6)
	g.sfx.play("eat", 1.4)
	g.add_score(Balance.DOLL_POINTS, m.position, prefix)
	m.queue_free()
	g.snake.grow(2)
	g.abilities.gain_doll()
	if not g.debug_run and randf() < KOSCHEI_CHANCE:
		koschei(m.position)
	if m.set_id == 0 or not doll_sets.has(m.set_id):
		return
	doll_sets[m.set_id] = int(doll_sets[m.set_id]) - 1
	if int(doll_sets[m.set_id]) > 0:
		return
	doll_sets.erase(m.set_id)
	g.add_score(Balance.DOLL_SET_POINTS, m.position + Vector2(0, -30), "НАБОР СОБРАН! ")
	g.sfx.play("scale")
	if g.is_goal_stage(Balance.DOLL_STAGE):
		g.dolls_done += 1
		g.goal_progress(Balance.DOLL_STAGE)
		if g.is_goal_stage(Balance.DOLL_STAGE) and g.goal_done + doll_sets.size() < g.goal_total:
			spawn_doll_set()


## Пасхалка «Кощеева смерть»: в малышке — яйцо, в яйце — игла. Змея получает иглы и премию.
func koschei(pos: Vector2) -> void:
	g.fx.popup(pos + Vector2(0, -60), "В МАЛЫШКЕ — ЯЙЦО, В ЯЙЦЕ — ИГЛА!", Color(1, 0.85, 0.4))
	g.add_score(200, pos + Vector2(0, -30), "КОЩЕЕВА СМЕРТЬ! ")
	g.abilities.gain(4)  # иглы швеи
	g.found_secret("koschei")


## Малышка приземлилась: давит змею, медведей и раскрывает других матрёшек под собой.
func _on_doll_landed(pos: Vector2, m: Matryoshka) -> void:
	if not is_instance_valid(m) or not dolls.has(m):
		return
	var snake: Snake = g.snake
	g.add_shake(6.0)
	g.fx.burst(pos, Color(0.95, 0.8, 0.6), 10, 0.8)
	g.vibrate(25)
	if snake.alive and snake.head_pos.distance_to(pos) < Matryoshka.CRUSH_RADIUS + Snake.HEAD_RADIUS * 0.5:
		if snake.take_damage(1, "doll"):
			g.fx.popup(snake.head_pos + Vector2(0, -30), "ПРИДАВИЛА!", Color(1, 0.5, 0.4))
			g.sfx.play("hurt")
		snake.push((snake.head_pos - pos).normalized() * 380.0)
	for b: TeddyBear in bears:
		if b.position.distance_to(pos) < Matryoshka.CRUSH_RADIUS + TeddyBear.RADIUS:
			friendly_hit(b, null, (b.position - pos).normalized() * 280.0)
	for other: Matryoshka in dolls.duplicate():
		if other != m and not other.is_last() and other.can_bite() \
				and other.position.distance_to(pos) < Matryoshka.CRUSH_RADIUS + other.radius():
			friendly_hits += 1
			open_doll(other, "ФРЕНДЛИ ФАЕР! ")


## Атака змеи по матрёшке (вертушка, укол, взрыв, снаряд, рывок). false — не задела (в воздухе).
func snake_hits_doll(m: Matryoshka, prefix: String) -> bool:
	if not dolls.has(m) or not m.can_bite():
		return false
	bite_doll(m, prefix)
	return true


## Ударная волна змеи: матрёшки переводят дух.
func daze_dolls(at: Vector2, r: float, time: float) -> void:
	for m: Matryoshka in dolls:
		if m.position.distance_to(at) < r:
			m.daze(time)
