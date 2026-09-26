extends Node2D
## Главный скрипт: арена, состояния игры, сложность, спавн, столкновения, звук.

const Snake = preload("res://scripts/snake.gd")
const TeddyBear = preload("res://scripts/teddy_bear.gd")
const FriedEggBoss = preload("res://scripts/fried_egg_boss.gd")
const OilDrop = preload("res://scripts/oil_drop.gd")
const Shockwave = preload("res://scripts/shockwave.gd")
const Hud = preload("res://scripts/hud.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Settings = preload("res://scripts/settings.gd")
const Ending = preload("res://scripts/ending.gd")

const ARENA := Rect2(0, 0, 1280, 720)
const WALL := 24.0
const BEARS_ON_FIELD := 5
const SAVE_PATH := "user://save.cfg"
## Поставь true, чтобы сразу начинать с босса (для отладки).
const DEBUG_SKIP_TO_BOSS := false
## Поставь true, чтобы сразу смотреть финальную катсцену (для отладки).
const DEBUG_SKIP_TO_ENDING := false

const DIFFICULTIES := [
	{
		"name": "ЛЁГКАЯ", "color": Color(0.4, 0.85, 0.4),
		"lives": 5, "bears": 10, "bear_speed": 0.85, "bear_aggr": 0.6,
		"boss_hp": 9, "proj_speed": 0.8, "yolk_time": 1.35, "tempo": 1.3, "score_mult": 1,
		"desc": "5 жизней • 10 медведей\nМедведи почти не дерутся, каратисты бьют вполсилы",
	},
	{
		"name": "НОРМАЛЬНАЯ", "color": Color(1, 0.8, 0.25),
		"lives": 3, "bears": 15, "bear_speed": 1.0, "bear_aggr": 1.0,
		"boss_hp": 12, "proj_speed": 1.0, "yolk_time": 1.0, "tempo": 1.0, "score_mult": 2,
		"desc": "3 жизни • 15 медведей\nБоксёры, каратисты, швеи с иглами, яичница в полную силу",
	},
	{
		"name": "СЛОЖНАЯ", "color": Color(1, 0.35, 0.3),
		"lives": 2, "bears": 20, "bear_speed": 1.2, "bear_aggr": 1.5,
		"boss_hp": 15, "proj_speed": 1.25, "yolk_time": 0.75, "tempo": 0.75, "score_mult": 3,
		"desc": "2 жизни • 20 медведей\nЗлые медведи, веера игл, бешеная яичница",
	},
]

## Атаки, которые змея перенимает у съеденных медведей (ключ — тип медведя).
const ABILITIES := {
	1: {"name": "УДАР С РАЗБЕГА", "charges": 3, "cost": 0.25},
	2: {"name": "ПУГОВИЦЫ", "charges": 8, "cost": 0.08},
	3: {"name": "ВЕРТУШКА", "charges": 3, "cost": 0.3},
	4: {"name": "ИГЛЫ", "charges": 5, "cost": 0.15},
}
const BEAR_POINTS := [10, 20, 15, 25, 20]
const SPIN_RADIUS := 130.0

enum State { MENU, LEVEL, BOSS_INTRO, BOSS, OUTRO, CUTSCENE, WIN, GAME_OVER }

## Переживают перезагрузку сцены: выбранная сложность и «сразу начать заново».
static var difficulty := 1
static var auto_start := false

var state := State.MENU
var cfg: Dictionary = DIFFICULTIES[1]
var score := 0
var bears_eaten := 0
var bears_goal := 15
var play_time := 0.0
var bounds := ARENA.grow(-WALL)

var world: Node2D
var camera: Camera2D
var hud: Hud
var sfx: Sfx
var snake: Snake
var boss: FriedEggBoss
var bears: Array[TeddyBear] = []
var drops: Array[OilDrop] = []
var waves: Array[Shockwave] = []
var shake := 0.0
var yolk_hints := 0
var friendly_hits := 0
var ending: Ending
var ability := -1
var charges := 0
var ability_hinted := false
var dash_hit_boss := false
var reinforce_t := 6.0
var reinforce_hinted := false
var demo_snake: Snake  # змея в меню, которая сама охотится на медведей
var menu_egg: FriedEggBoss
var menu_t := 0.0


func _ready() -> void:
	randomize()
	Settings.ensure_loaded()
	_setup_input()
	camera = Camera2D.new()
	camera.position = ARENA.get_center()
	add_child(camera)
	world = Node2D.new()
	add_child(world)
	sfx = Sfx.new()
	add_child(sfx)
	hud = Hud.new()
	hud.sfx = sfx
	add_child(hud)
	hud.difficulty_chosen.connect(_start_game)
	hud.retry_pressed.connect(_restart.bind(true))
	hud.menu_pressed.connect(_restart.bind(false))
	hud.records_reset.connect(_reset_records)
	sfx.play_music("level")

	if auto_start:
		auto_start = false
		_start_game(difficulty)
	else:
		_setup_menu_demo()
		hud.show_menu(DIFFICULTIES, [_load_best(0), _load_best(1), _load_best(2)], difficulty)


func _setup_input() -> void:
	_add_action("turn_left", [KEY_LEFT, KEY_A])
	_add_action("turn_right", [KEY_RIGHT, KEY_D])
	_add_action("sprint", [KEY_SHIFT])
	_add_action("ability", [KEY_SPACE, KEY_F])
	if InputMap.action_get_events("ability").size() == 2:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("ability", mb)
	_add_action("pause", [KEY_ESCAPE, KEY_P])
	_add_action("mute", [KEY_M])


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- состояния

# ---------------------------------------------------------------- меню

## Фон меню: змея-демо сама охотится на медведей всех видов, из угла подглядывает яичница.
func _setup_menu_demo() -> void:
	for i in 7:
		_spawn_bear(randi() % 5)
		bears.back().position.x = randf_range(560, 1220)
	demo_snake = Snake.new()
	demo_snake.bounds = bounds
	demo_snake.z_index = 2
	demo_snake.autopilot = true
	demo_snake.auto_speed = 190.0
	demo_snake.reset(Vector2(900, 600))
	world.add_child(demo_snake)
	menu_egg = FriedEggBoss.new()
	menu_egg.z_index = 3
	menu_egg.scale = Vector2(0.8, 0.8)
	menu_egg.position = Vector2(1150, 820)
	world.add_child(menu_egg)


func _update_menu_demo(delta: float) -> void:
	menu_t += delta
	var nearest: TeddyBear = null
	for bear in bears:
		bear.update(delta, null)
		if nearest == null or bear.position.distance_to(demo_snake.head_pos) < nearest.position.distance_to(demo_snake.head_pos):
			nearest = bear
	if nearest:
		demo_snake.auto_target = nearest.position
		if nearest.position.distance_to(demo_snake.head_pos) < Snake.HEAD_RADIUS + TeddyBear.RADIUS:
			bears.erase(nearest)
			_burst(nearest.position, nearest.fur, 12)
			nearest.queue_free()
			sfx.play("eat", 1.2, -12.0)
			demo_snake.grow(2)
			if demo_snake.length > 46:
				demo_snake.length = 14
			menu_egg.flash = 0.6
			_spawn_bear(randi() % 5)
			bears.back().position.x = randf_range(560, 1220)
	demo_snake.update(delta)
	menu_egg.position.y = 700.0 + sin(menu_t * 0.7) * 70.0  # то выглядывает, то прячется
	menu_egg.look_dir = (demo_snake.head_pos - menu_egg.position).normalized()
	menu_egg.update(delta, null)


func _clear_menu_demo() -> void:
	for bear in bears:
		bear.queue_free()
	bears.clear()
	if demo_snake:
		demo_snake.queue_free()
		demo_snake = null
	if menu_egg:
		menu_egg.queue_free()
		menu_egg = null


# ---------------------------------------------------------------- состояния

func _start_game(diff: int) -> void:
	difficulty = diff
	cfg = DIFFICULTIES[diff]
	bears_goal = cfg["bears"]
	_clear_menu_demo()

	snake = Snake.new()
	snake.bounds = bounds
	snake.z_index = 2
	snake.lives = cfg["lives"]
	snake.reset(Vector2(640, 520))
	snake.damaged.connect(_on_snake_damaged)
	snake.died.connect(_on_snake_died)
	world.add_child(snake)

	hud.show_game(cfg["name"], cfg["color"], cfg["lives"])
	hud.set_score(0)
	hud.set_bears(0, bears_goal)
	hud.pause_allowed = true
	hud.set_ability(-1, "", 0)
	hud.show_banner("Съешь %d медведей!" % bears_goal, Color(1, 0.9, 0.5), 1.5)
	state = State.LEVEL
	if DEBUG_SKIP_TO_ENDING:
		state = State.OUTRO
		_start_ending()
		return
	if DEBUG_SKIP_TO_BOSS:
		bears_eaten = bears_goal
		_begin_boss()
		return
	for i in BEARS_ON_FIELD:
		_spawn_bear(_pick_bear_type())


func _restart(retry: bool) -> void:
	auto_start = retry
	get_tree().paused = false
	get_tree().reload_current_scene()


func _begin_boss() -> void:
	state = State.BOSS_INTRO
	hud.set_bears(0, 0)
	for bear in bears:
		_burst(bear.position, Color(0.7, 0.5, 0.3), 12)
		bear.queue_free()
	bears.clear()
	_clear_drops()
	hud.show_banner("ГИГАНТСКАЯ ЯИЧНИЦА ПРИБЛИЖАЕТСЯ!", Color(1, 0.55, 0.25), 2.2)
	sfx.play_music("")
	sfx.play("phase")
	shake = 6.0

	boss = FriedEggBoss.new()
	boss.bounds = bounds
	boss.configure(cfg["boss_hp"], cfg["proj_speed"], cfg["yolk_time"], cfg["tempo"])
	boss.z_index = 0
	boss.position = Vector2(640, -300)
	boss.shoot.connect(_on_boss_shoot)
	boss.shockwave.connect(_on_boss_shockwave)
	boss.sound.connect(sfx.play)
	boss.bitten.connect(_on_boss_bitten)
	boss.phase_changed.connect(_on_boss_phase)
	boss.yolk_opened.connect(_on_yolk_opened)
	boss.defeated.connect(_on_boss_defeated)
	world.add_child(boss)

	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(boss, "position", Vector2(640, 300), 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_on_boss_landed)
	tw.tween_interval(1.0)
	tw.tween_callback(func() -> void:
		if state == State.BOSS_INTRO:
			state = State.BOSS
			boss.active = true)


func _on_boss_landed() -> void:
	shake = 22.0
	sfx.play("slam")
	sfx.play_music("boss")
	_burst(boss.position, Color(1, 1, 0.9), 40)
	_burst(boss.position, Color(1, 0.8, 0.1), 25)
	hud.set_boss(true, boss.hp, boss.max_hp, 1)
	if snake.head_pos.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS:
		snake.push((snake.head_pos - boss.position).normalized() * 700.0)


func _start_ending() -> void:
	state = State.CUTSCENE
	hud.set_boss(false)
	ending = Ending.new()
	add_child(ending)
	ending.finished.connect(_on_ending_finished)
	ending.start(self)


func _on_ending_finished() -> void:
	hud.set_cinematic(false)
	_end(true)


func _unhandled_input(event: InputEvent) -> void:
	if state == State.CUTSCENE and ending:
		if event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			ending.skip()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			ending.choose_throw()
	elif state in [State.LEVEL, State.BOSS] and event.is_action_pressed("ability"):
		_use_ability()


func _end(win: bool) -> void:
	state = State.WIN if win else State.GAME_OVER
	if boss:
		boss.active = false
	_clear_drops()
	if not win:
		sfx.play_music("")
		sfx.play("lose")
	var best := _load_best(difficulty)
	var record := score > best
	if record:
		_save_best(difficulty, score)
		best = score
	var mins := int(play_time) / 60
	var secs := int(play_time) % 60
	var lines := []
	lines.append("Змея одолела яичницу... но не своего создателя." if win else "Не сдавайся — яичница ждёт!")
	lines.append("")
	lines.append("Сложность: %s" % cfg["name"])
	lines.append("Съедено медведей: %d" % bears_eaten)
	if friendly_hits > 0:
		lines.append("Медведи подрались между собой: %d раз" % friendly_hits)
	if win and ending:
		lines.append(ending.choice_text())
	lines.append("Время: %d:%02d" % [mins, secs])
	lines.append("Счёт: %d%s" % [score, "   — НОВЫЙ РЕКОРД!" if record else ""])
	lines.append("Рекорд: %d" % best)
	hud.show_end(win, "\n".join(lines), "КОНЕЦ" if win else "")


# ---------------------------------------------------------------- цикл

func _process(delta: float) -> void:
	shake = maxf(shake - delta * 40.0, 0.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * Settings.shake
	if snake:
		hud.stamina = snake.stamina
		hud.exhausted = snake.exhausted
		hud.snake_head = snake.head_pos
		hud.pause_allowed = state in [State.LEVEL, State.BOSS_INTRO, State.BOSS]
	if state in [State.LEVEL, State.BOSS_INTRO, State.BOSS]:
		play_time += delta

	match state:
		State.MENU:
			if demo_snake:
				_update_menu_demo(delta)
		State.WIN, State.GAME_OVER, State.OUTRO, State.BOSS_INTRO, State.CUTSCENE:
			if snake:
				snake.update(delta)
			if boss:
				boss.update(delta, snake)
		State.LEVEL:
			snake.update(delta)
			_update_dash()
			_update_bears(delta)
			_update_drops(delta)
		State.BOSS:
			snake.update(delta)
			_update_dash()
			boss.update(delta, snake)
			_update_reinforcements(delta)
			_update_bears(delta)
			_update_drops(delta)
			_update_waves(delta)


func _update_bears(delta: float) -> void:
	for bear: TeddyBear in bears.duplicate():
		bear.update(delta, snake)
		if state in [State.LEVEL, State.BOSS] and bear.is_edible() \
				and bear.position.distance_to(snake.head_pos) < Snake.HEAD_RADIUS + TeddyBear.RADIUS:
			_eat_bear(bear)
	# таран: боксёр в рывке или разозлённый медведь сбивают других медведей
	for a: TeddyBear in bears.duplicate():
		if not is_instance_valid(a) or not a.is_ramming():
			continue
		for b: TeddyBear in bears:
			if b != a and a.position.distance_to(b.position) < TeddyBear.RADIUS * 2.0 + 4.0:
				var dir := (b.position - a.position).normalized()
				if _friendly_hit(b, a, dir * 320.0):
					a.on_ram_hit()
					break


## Медведь попал по своему. Возвращает true, если удар засчитан.
func _friendly_hit(victim: TeddyBear, attacker: Node2D, push_vel: Vector2) -> bool:
	if not victim.hit_by_friend(attacker, push_vel):
		return false
	friendly_hits += 1
	_add_score(5 * int(cfg["score_mult"]), victim.position, "ФРЕНДЛИ ФАЕР! ")
	_burst(victim.position, Color(1, 0.95, 0.6), 8)
	shake = maxf(shake, 5.0)
	if friendly_hits == 1:
		hud.show_banner("Медведи дерутся между собой!", Color(1, 0.6, 0.9), 1.6)
	return true


func _eat_bear(bear: TeddyBear) -> void:
	bears.erase(bear)
	for other in bears:  # обидчика съели — мстить некому
		if other.grudge == bear:
			other.grudge = null
	_burst(bear.position, bear.fur, 14)
	_burst(bear.position, bear.bow_color, 6)
	var points: int = BEAR_POINTS[bear.type]
	var mult: int = cfg["score_mult"]
	var bonus := bear.is_dizzy()
	if bonus:
		points *= 2
	_add_score(points * mult, bear.position, "НОКАУТ! " if bonus else "")
	bear.queue_free()
	snake.grow(3)
	_gain_ability(bear.type)
	if state != State.LEVEL:  # подкрепление в бою с яичницей — только атака и очки
		sfx.play("eat")
		return
	bears_eaten += 1
	sfx.play("eat", 1.0 + 0.02 * bears_eaten)
	hud.set_bears(bears_eaten, bears_goal)
	if bears_eaten >= bears_goal:
		_begin_boss()
	elif bears_eaten + bears.size() < bears_goal:
		_spawn_bear(_pick_bear_type())


func _pick_bear_type() -> int:
	var a: float = cfg["bear_aggr"]
	var progress := float(bears_eaten) / bears_goal
	var weights := [
		[TeddyBear.Type.BOXER, (0.12 + progress * 0.25) * a],
		[TeddyBear.Type.THROWER, (0.06 + progress * 0.18) * a],
		[TeddyBear.Type.SEAMSTRESS, (0.04 + progress * 0.18) * a],
		[TeddyBear.Type.KARATE, (0.0 + progress * 0.25) * a],
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


func _spawn_bear(type: int) -> void:
	var pos := Vector2.ZERO
	var avoid := snake.head_pos if snake else Vector2(-9999, -9999)
	for attempt in 20:
		pos = Vector2(randf_range(bounds.position.x + 40, bounds.end.x - 40),
			randf_range(bounds.position.y + 40, bounds.end.y - 40))
		if pos.distance_to(avoid) > 240.0:
			break
	var bear := TeddyBear.new()
	bear.z_index = 1
	var speed_mult: float = cfg["bear_speed"]
	bear.setup(pos, (55.0 + bears_eaten * 5.0) * speed_mult, bounds, type, cfg["bear_aggr"])
	bear.throw_button.connect(_on_bear_throw.bind(bear))
	bear.sound.connect(sfx.play)
	world.add_child(bear)
	bears.append(bear)


func _spawn_drop(pos: Vector2, velocity: Vector2, kind: int) -> OilDrop:
	var d := OilDrop.new()
	d.z_index = 3
	d.setup(pos, velocity, kind)
	world.add_child(d)
	drops.append(d)
	return d


func _on_bear_throw(pos: Vector2, velocity: Vector2, needle: bool, bear: TeddyBear) -> void:
	_spawn_drop(pos, velocity, OilDrop.Kind.NEEDLE if needle else OilDrop.Kind.BUTTON).thrower = bear


# ---------------------------------------------------------------- атаки змеи

func _gain_ability(type: int) -> void:
	if not ABILITIES.has(type):  # обычный медведь восстанавливает силы
		snake.stamina = minf(snake.stamina + 0.3, 1.0)
		return
	var info: Dictionary = ABILITIES[type]
	if type == ability:
		charges += info["charges"]
	else:
		ability = type
		charges = info["charges"]
		_popup(snake.head_pos + Vector2(0, -40), "НОВАЯ АТАКА: " + info["name"], Color(0.5, 1, 0.5))
	sfx.play("power")
	hud.set_ability(ability, info["name"], charges)
	if not ability_hinted:
		ability_hinted = true
		hud.show_banner("Пробел / ЛКМ — атака съеденного медведя!", Color(0.5, 1, 0.5), 1.8)


func _use_ability() -> void:
	if ability < 0 or charges <= 0 or not snake.alive:
		return
	var info: Dictionary = ABILITIES[ability]
	if not snake.spend(info["cost"]):
		sfx.play("no_stamina")
		_popup(snake.head_pos + Vector2(0, -30), "Нет сил!", Color(0.6, 0.8, 1))
		return
	var dir := Vector2.from_angle(snake.heading)
	var muzzle := snake.head_pos + dir * 24.0
	match ability:
		TeddyBear.Type.THROWER:
			_spawn_drop(muzzle, dir * 560.0, OilDrop.Kind.BUTTON).from_snake = true
			sfx.play("snake_shot")
		TeddyBear.Type.SEAMSTRESS:
			for i in 3:
				_spawn_drop(muzzle, dir.rotated((i - 1) * 0.14) * 650.0, OilDrop.Kind.NEEDLE).from_snake = true
			sfx.play("needle")
		TeddyBear.Type.BOXER:
			snake.dash(0.32)
			dash_hit_boss = false
			sfx.play("whoosh", 1.2)
		TeddyBear.Type.KARATE:
			snake.spin_t = 0.35
			sfx.play("spin")
			_spin_attack()
	charges -= 1
	if charges <= 0:
		ability = -1
	hud.set_ability(ability, info["name"], charges)


## Вертушка: раскидывает медведей вокруг головы, сбивает вражеские снаряды, задевает яичницу.
func _spin_attack() -> void:
	var head := snake.head_pos
	for bear: TeddyBear in bears.duplicate():
		if bear.position.distance_to(head) < SPIN_RADIUS:
			_snake_hits_bear(bear, (bear.position - head).normalized() * 380.0)
	for d: OilDrop in drops.duplicate():
		if not d.from_snake and d.position.distance_to(head) < SPIN_RADIUS:
			_burst(d.position, Color(1, 1, 0.8), 4)
			drops.erase(d)
			d.queue_free()
	if boss and state == State.BOSS and head.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS + SPIN_RADIUS * 0.8:
		if boss.take_chip(0.5):
			_burst(boss.position + (head - boss.position).normalized() * FriedEggBoss.WHITE_RADIUS * 0.8, Color.WHITE, 12)
			sfx.play("kick")
	shake = maxf(shake, 6.0)


## Удар с разбега (боксёр): сбивает медведей по пути и таранит яичницу.
func _update_dash() -> void:
	if not snake.is_dashing():
		return
	for bear: TeddyBear in bears.duplicate():
		if bear.position.distance_to(snake.head_pos) < Snake.HEAD_RADIUS + TeddyBear.RADIUS + 8.0:
			_snake_hits_bear(bear, Vector2.from_angle(snake.heading) * 420.0)
	if boss and state == State.BOSS and not dash_hit_boss \
			and snake.head_pos.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS * 0.85:
		dash_hit_boss = true
		if boss.take_chip(0.6):
			sfx.play("punch")
			shake = 14.0
			_burst(snake.head_pos, Color.WHITE, 14)
		snake.push((snake.head_pos - boss.position).normalized() * 600.0)
		snake.dash_t = 0.0


func _snake_hits_bear(bear: TeddyBear, push_vel: Vector2) -> void:
	if bear.hit_by_friend(null, push_vel):
		_add_score(5 * int(cfg["score_mult"]), bear.position, "БАЦ! ")
		_burst(bear.position, Color(0.6, 1, 0.6), 8)


## Во время боя с яичницей иногда прибегает медведь — съешь его, чтобы получить атаку.
func _update_reinforcements(delta: float) -> void:
	reinforce_t -= delta
	if reinforce_t > 0.0 or not bears.is_empty():
		return
	reinforce_t = 9.0
	_spawn_bear([TeddyBear.Type.BOXER, TeddyBear.Type.THROWER, TeddyBear.Type.KARATE,
		TeddyBear.Type.SEAMSTRESS].pick_random())
	var bear: TeddyBear = bears.back()
	_popup(bear.position + Vector2(0, -30), "ПОДКРЕПЛЕНИЕ!", Color(1, 0.8, 0.5))
	if not reinforce_hinted:
		reinforce_hinted = true
		hud.show_banner("Съешь медведя — его атака ранит яичницу!", Color(0.5, 1, 0.5), 1.8)


func _update_snake_shot(d: OilDrop) -> bool:
	for bear: TeddyBear in bears:
		if bear.position.distance_to(d.position) < OilDrop.RADIUS + TeddyBear.RADIUS:
			_snake_hits_bear(bear, d.vel.normalized() * 260.0)
			return true
	if boss and state == State.BOSS and boss.height < 20.0 \
			and d.position.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS * 0.9:
		var amount := 0.25 if d.kind == OilDrop.Kind.BUTTON else 0.18
		var yolk := boss.position + FriedEggBoss.YOLK_OFFSET
		if boss.is_yolk_open() and d.position.distance_to(yolk) < FriedEggBoss.YOLK_RADIUS + 14.0:
			amount *= 3.0
		if boss.take_chip(amount):
			sfx.play("splat", 1.3)
		_burst(d.position, Color(1, 0.95, 0.7), 6)
		return true
	return false


func _update_drops(delta: float) -> void:
	for d: OilDrop in drops.duplicate():
		d.update(delta, snake.head_pos)
		if d.from_snake:
			if _update_snake_shot(d) or d.life <= 0.0 or not ARENA.has_point(d.position):
				drops.erase(d)
				d.queue_free()
			continue
		var hit := snake.alive and d.position.distance_to(snake.head_pos) < OilDrop.RADIUS + Snake.HEAD_RADIUS * 0.8
		if hit:
			if d.kind == OilDrop.Kind.WHITE:
				snake.slow(2.5)
				sfx.play("splat", 0.8)
			else:
				if snake.take_damage() and d.kind == OilDrop.Kind.NEEDLE:
					snake.slow(1.2)  # иголка пришивает
			_burst(d.position, Color(1, 0.85, 0.3) if d.kind != OilDrop.Kind.WHITE else Color.WHITE, 6)
		elif d.kind == OilDrop.Kind.BUTTON or d.kind == OilDrop.Kind.NEEDLE:  # френдли фаер: попали в другого медведя
			for bear: TeddyBear in bears:
				if bear != d.thrower and bear.position.distance_to(d.position) < OilDrop.RADIUS + TeddyBear.RADIUS:
					var thrower: Node2D = d.thrower if is_instance_valid(d.thrower) else null
					_friendly_hit(bear, thrower, d.vel.normalized() * 240.0)
					hit = true
					break
		if hit or d.life <= 0.0 or not ARENA.has_point(d.position):
			drops.erase(d)
			d.queue_free()


func _update_waves(delta: float) -> void:
	for w: Shockwave in waves.duplicate():
		w.update(delta)
		if w.hits(snake.head_pos):
			w.hit_done = true
			if snake.take_damage():
				snake.push((snake.head_pos - w.position).normalized() * 500.0)
		if w.finished():
			waves.erase(w)
			w.queue_free()


func _clear_drops() -> void:
	for d in drops:
		d.queue_free()
	drops.clear()
	for w in waves:
		w.queue_free()
	waves.clear()


func _add_score(points: int, pos: Vector2, prefix := "") -> void:
	score += points
	hud.set_score(score)
	_popup(pos, "%s+%d" % [prefix, points], Color(1, 0.95, 0.4) if prefix == "" else Color(1, 0.5, 0.9))


# ---------------------------------------------------------------- сигналы

func _on_snake_damaged(lives_left: int) -> void:
	hud.set_lives(lives_left)
	shake = 14.0
	sfx.play("hurt")


func _on_snake_died() -> void:
	_burst(snake.head_pos, Color(0.4, 0.85, 0.35), 30)
	_end(false)


func _on_boss_shoot(pos: Vector2, velocity: Vector2, kind: int) -> void:
	_spawn_drop(pos, velocity, kind)


func _on_boss_shockwave(pos: Vector2, gaps: int) -> void:
	var w := Shockwave.new()
	w.z_index = 1
	w.setup(pos, gaps)
	world.add_child(w)
	waves.append(w)
	shake = 18.0
	_burst(pos, Color(1, 0.95, 0.8), 30)


func _on_boss_bitten(hp_left: int) -> void:
	_add_score(100 * int(cfg["score_mult"]), boss.position + FriedEggBoss.YOLK_OFFSET + Vector2(0, -60))
	hud.set_boss(true, hp_left, boss.max_hp, boss.phase())
	shake = 12.0
	sfx.play("bite", 0.9)
	_burst(boss.position + FriedEggBoss.YOLK_OFFSET, Color(1, 0.8, 0.1), 20)


func _on_boss_phase(phase: int) -> void:
	sfx.play("phase")
	shake = 16.0
	if phase == 2:
		hud.show_banner("Яичница злится! Новые атаки!", Color(1, 0.55, 0.1))
	else:
		hud.show_banner("ЯИЧНИЦА В ЯРОСТИ!", Color(1, 0.25, 0.15))


func _on_yolk_opened() -> void:
	if yolk_hints < 2:
		yolk_hints += 1
		hud.show_banner("Желток открыт — КУСАЙ ЕГО!", Color(1, 0.9, 0.2), 1.5)


func _on_boss_defeated() -> void:
	for bear in bears:
		_burst(bear.position, bear.fur, 10)
		bear.queue_free()
	bears.clear()
	_add_score(1000 * int(cfg["score_mult"]), boss.position + Vector2(0, -90), "ЯИЧНИЦА СЪЕДЕНА! ")
	hud.set_boss(true, 0, boss.max_hp, 3)
	_clear_drops()
	shake = 30.0
	state = State.OUTRO
	sfx.play_music("")
	sfx.play("boss_down")
	for i in 4:
		_burst(boss.position + Vector2.from_angle(i * TAU / 4) * 60.0, Color(1, 1, 0.95), 30)
	_burst(boss.position, Color(1, 0.75, 0.05), 60)
	var tw := create_tween()
	tw.tween_property(boss, "scale", Vector2(1.4, 1.4), 0.6)
	tw.parallel().tween_property(boss, "modulate:a", 0.0, 0.6)
	tw.tween_interval(1.0)
	tw.tween_callback(_start_ending)


# ---------------------------------------------------------------- сохранение

func _load_best(i: int) -> int:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return 0
	return cf.get_value("best", str(i), 0)


func _reset_records() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	if cf.has_section("best"):
		cf.erase_section("best")
	cf.save(SAVE_PATH)
	hud.set_best_scores([0, 0, 0])


func _save_best(i: int, value: int) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("best", str(i), value)
	cf.save(SAVE_PATH)


# ---------------------------------------------------------------- эффекты и фон

func _popup(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	var ls := LabelSettings.new()
	ls.font_size = 24
	ls.font_color = color
	ls.outline_size = 6
	ls.outline_color = Color(0.15, 0.05, 0.0)
	label.label_settings = ls
	label.z_index = 5
	label.size = Vector2(400, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos - Vector2(200, 30)
	world.add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", label.position.y - 50.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tw.tween_callback(label.queue_free)


func _burst(pos: Vector2, color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 4
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.7
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 250)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	p.color = color
	p.finished.connect(p.queue_free)
	world.add_child(p)
	p.emitting = true


func _draw() -> void:
	var tile := 64
	for x in range(0, int(ARENA.size.x), tile):
		for y in range(0, int(ARENA.size.y), tile):
			var even := (x / tile + y / tile) % 2 == 0
			draw_rect(Rect2(x, y, tile, tile), Color(0.96, 0.93, 0.85) if even else Color(0.82, 0.9, 0.93))
	for x in range(0, int(ARENA.size.x), tile):
		draw_line(Vector2(x, 0), Vector2(x, ARENA.size.y), Color(0.7, 0.7, 0.7, 0.35), 2.0)
	for y in range(0, int(ARENA.size.y), tile):
		draw_line(Vector2(0, y), Vector2(ARENA.size.x, y), Color(0.7, 0.7, 0.7, 0.35), 2.0)
	# деревянный бортик
	draw_rect(ARENA.grow(-WALL / 2), Color(0.5, 0.3, 0.15), false, WALL)
	draw_rect(bounds, Color(0.3, 0.17, 0.08), false, 3.0)
