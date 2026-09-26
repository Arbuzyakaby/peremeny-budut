extends Node2D
## Главный скрипт: арена, этапы, сложность, спавн, столкновения, атаки змеи, навыки, звук.
## Этапы: 0 — медведи, 1 — ржавые вилки, 2 — прыгающие таблетки, 3 — гигантская яичница
## (ей на помощь приходят медведи, вилки и таблетки).
## Отладка без правки кода (аргументы после `--`): --stage=N, --diff=N, --ending, --autopilot, --dump-sfx,
## --skills (открыть древо навыков), --perks (показать выбор улучшений).

const Snake = preload("res://scripts/snake.gd")
const TeddyBear = preload("res://scripts/teddy_bear.gd")
const Fork = preload("res://scripts/fork.gd")
const Pill = preload("res://scripts/pill.gd")
const FriedEggBoss = preload("res://scripts/fried_egg_boss.gd")
const OilDrop = preload("res://scripts/oil_drop.gd")
const Shockwave = preload("res://scripts/shockwave.gd")
const Hud = preload("res://scripts/hud.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Settings = preload("res://scripts/settings.gd")
const Skills = preload("res://scripts/skills.gd")
const Tex = preload("res://scripts/tex.gd")
const Ending = preload("res://scripts/ending.gd")

const ARENA := Rect2(0, 0, 1280, 720)
const WALL := 24.0
const BEARS_ON_FIELD := 5
const SAVE_PATH := "user://save.cfg"

const DIFFICULTIES := [
	{
		"name": "ЛЁГКАЯ", "color": Color(0.4, 0.85, 0.4),
		"lives": 5, "bears": 10, "forks": 5, "pills": 5, "bear_speed": 0.85, "bear_aggr": 0.6,
		"boss_hp": 9, "proj_speed": 0.8, "yolk_time": 1.35, "tempo": 1.3, "score_mult": 1, "no_skills": false,
		"desc": "5 жизней • 10 медведей, 5 вилок, 5 таблеток\nВраги неторопливые, яичница добрая",
	},
	{
		"name": "НОРМАЛЬНАЯ", "color": Color(1, 0.8, 0.25),
		"lives": 3, "bears": 15, "forks": 7, "pills": 7, "bear_speed": 1.0, "bear_aggr": 1.0,
		"boss_hp": 12, "proj_speed": 1.0, "yolk_time": 1.0, "tempo": 1.0, "score_mult": 2, "no_skills": false,
		"desc": "3 жизни • 15 медведей, 7 вилок, 7 таблеток\nВсе враги и яичница в полную силу",
	},
	{
		"name": "СЛОЖНАЯ", "color": Color(1, 0.35, 0.3),
		"lives": 2, "bears": 20, "forks": 9, "pills": 9, "bear_speed": 1.2, "bear_aggr": 1.5,
		"boss_hp": 15, "proj_speed": 1.25, "yolk_time": 0.75, "tempo": 0.75, "score_mult": 3, "no_skills": false,
		"desc": "2 жизни • 20 медведей, 9 вилок, 9 таблеток\nЗлые медведи, быстрые вилки, бешеная яичница",
	},
	{
		"name": "УЛЬТРА-ХАРДКОР", "color": Color(0.85, 0.3, 1.0),
		"lives": 1, "bears": 25, "forks": 12, "pills": 12, "bear_speed": 1.35, "bear_aggr": 2.0,
		"boss_hp": 18, "proj_speed": 1.45, "yolk_time": 0.6, "tempo": 0.6, "score_mult": 5, "no_skills": true,
		"desc": "1 жизнь • 25 медведей, 12 вилок, 12 таблеток\nНавыки и улучшения ОТКЛЮЧЕНЫ. Очки ×5",
	},
]

## Этапы забега.
const STAGES := [
	{"name": "МЕДВЕДИ", "music": "level", "floor": Tex.Floor.WOOD, "key": "bears",
		"hint": "Съешь плюшевых медведей — каждый особый медведь даёт свою атаку"},
	{"name": "РЖАВЫЕ ВИЛКИ", "music": "forks", "floor": Tex.Floor.TRAY, "key": "forks",
		"hint": "Вилки спринтуют на тебя. НЕ БЕЙ В ЛОБ — зубцы! Кусай сбоку или сзади"},
	{"name": "ПРЫГАЮЩИЕ ТАБЛЕТКИ", "music": "pills", "floor": Tex.Floor.TILES, "key": "pills",
		"hint": "Таблетки давят сверху, а волна оглушает. Ешь их, пока они на земле"},
	{"name": "ГИГАНТСКАЯ ЯИЧНИЦА", "music": "boss", "floor": Tex.Floor.PAN, "key": "",
		"hint": ""},
]

## Атаки, которые змея перенимает у съеденных медведей (ключ — тип медведя).
const ABILITIES := {
	1: {"name": "УДАР С РАЗБЕГА", "charges": 3, "cost": 0.25},
	2: {"name": "ПУГОВИЦЫ", "charges": 8, "cost": 0.08},
	3: {"name": "ВЕРТУШКА", "charges": 3, "cost": 0.3},
	4: {"name": "ИГЛЫ", "charges": 5, "cost": 0.15},
	5: {"name": "ТЕНЕВОЙ РЫВОК", "charges": 3, "cost": 0.2},
	6: {"name": "ХЛОПУШКА", "charges": 4, "cost": 0.15},
	7: {"name": "ЗАПЛАТКА", "charges": 1, "cost": 0.3},
}
const BEAR_POINTS := [10, 20, 15, 25, 20, 30, 25, 20]
const FORK_POINTS := 30
const PILL_POINTS := 25
const SPIN_RADIUS := 130.0

enum State { MENU, LEVEL, PERK, BOSS_INTRO, BOSS, OUTRO, CUTSCENE, WIN, GAME_OVER }

## Переживают перезагрузку сцены: выбранная сложность и «сразу начать заново».
static var difficulty := 1
static var auto_start := false

var state := State.MENU
var cfg: Dictionary = DIFFICULTIES[1]
var stage := 0
var goal_done := 0
var goal_total := 0
var score := 0
var bears_eaten := 0
var forks_broken := 0
var pills_eaten := 0
var play_time := 0.0
var run_scales := 0.0
var scales_gained := 0
var perks: Dictionary = {}
var mods: Dictionary = {}
var bounds := ARENA.grow(-WALL)

var world: Node2D
var floor_rect: ColorRect
var frame: Node2D
var camera: Camera2D
var hud: Hud
var sfx: Sfx
var snake: Snake
var boss: FriedEggBoss
var bears: Array[TeddyBear] = []
var forks: Array[Fork] = []
var pills: Array[Pill] = []
var drops: Array[OilDrop] = []
var waves: Array[Shockwave] = []
var shake := 0.0
var yolk_hints := 0
var friendly_hits := 0
var ending: Ending
var ability := -1
var charges := 0
var ability_hinted := false
var fork_hinted := false
var stun_hinted := false
var dash_hit_boss := false
var reinforce_t := 6.0
var reinforce_kind := 0
var reinforce_hinted := false
var helper_t := 5.0
var demo_snake: Snake  # змея в меню, которая сама охотится на медведей
var menu_egg: FriedEggBoss
var menu_t := 0.0
var hint_tween: Tween

# отладка
var dbg_stage := -1
var dbg_ending := false
var dbg_autopilot := false


func _ready() -> void:
	randomize()
	Settings.ensure_loaded()
	Skills.ensure_loaded()
	_setup_input()
	_parse_args()
	camera = Camera2D.new()
	camera.position = ARENA.get_center()
	add_child(camera)
	floor_rect = ColorRect.new()
	floor_rect.size = ARENA.size
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_rect.material = Tex.floor_material(Tex.Floor.WOOD)
	add_child(floor_rect)
	frame = Node2D.new()
	frame.draw.connect(_draw_frame)
	add_child(frame)
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
	hud.perk_chosen.connect(_on_perk)
	sfx.play_music("level")

	if "--dump-sfx" in OS.get_cmdline_user_args():
		sfx.dump(ProjectSettings.globalize_path("user://sfx_dump"))
		print("SFX dumped to ", ProjectSettings.globalize_path("user://sfx_dump"))
		get_tree().quit()
		return
	if auto_start or dbg_stage >= 0 or dbg_ending:
		auto_start = false
		_start_game(difficulty)
	else:
		_setup_menu_demo()
		hud.show_menu(DIFFICULTIES, [_load_best(0), _load_best(1), _load_best(2), _load_best(3)], difficulty)
		if "--skills" in OS.get_cmdline_user_args():
			hud._open_skills()
		elif "--perks" in OS.get_cmdline_user_args():
			hud.show_perks(Skills.roll_perks(), STAGES[1]["name"])


func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			dbg_stage = clampi(int(a.get_slice("=", 1)), 0, 3)
		elif a.begins_with("--diff="):
			difficulty = clampi(int(a.get_slice("=", 1)), 0, 3)
		elif a == "--ending":
			dbg_ending = true
		elif a == "--autopilot":
			dbg_autopilot = true


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


# ---------------------------------------------------------------- меню

## Фон меню: змея-демо сама охотится на медведей всех видов, из угла подглядывает яичница.
func _setup_menu_demo() -> void:
	for i in 7:
		_spawn_bear(randi() % 8)
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
		if not bear.is_edible():
			continue
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
			_spawn_bear(randi() % 8)
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
	_clear_menu_demo()
	mods = Skills.mods(perks, cfg["no_skills"])

	snake = Snake.new()
	snake.bounds = bounds
	snake.z_index = 2
	snake.max_lives = cfg["lives"] + mods["lives"]
	snake.lives = snake.max_lives
	snake.apply_mods(mods)
	snake.reset(Vector2(640, 520))
	snake.damaged.connect(_on_snake_damaged)
	snake.died.connect(_on_snake_died)
	world.add_child(snake)

	hud.show_game(cfg["name"], cfg["color"], snake.max_lives)
	hud.set_score(0)
	hud.pause_allowed = true
	hud.set_ability(-1, "", 0)
	if dbg_ending:
		state = State.OUTRO
		bears_eaten = cfg["bears"]
		forks_broken = cfg["forks"]
		pills_eaten = cfg["pills"]
		_set_floor(3)
		_start_ending()
		return
	_enter_stage(maxi(dbg_stage, 0))


func _restart(retry: bool) -> void:
	auto_start = retry
	get_tree().paused = false
	get_tree().reload_current_scene()


func _set_floor(i: int) -> void:
	floor_rect.material = Tex.floor_material(STAGES[i]["floor"])


func _enter_stage(i: int) -> void:
	stage = i
	goal_done = 0
	var st: Dictionary = STAGES[i]
	_set_floor(i)
	if i == 3:
		goal_total = 0
		hud.set_goal(3, 0, 0)
		_begin_boss()
		return
	goal_total = cfg[st["key"]]
	hud.set_goal(i, 0, goal_total)
	sfx.play_music(st["music"])
	hud.show_banner("ЭТАП %d: %s" % [i + 1, st["name"]], Color(1, 0.9, 0.5), 1.6)
	_hint(st["hint"], 4.0)
	state = State.LEVEL
	helper_t = 4.0
	match i:
		0:
			for k in BEARS_ON_FIELD:
				_spawn_bear(_pick_bear_type())
		1:
			for k in mini(3, goal_total):
				_spawn_fork()
		2:
			for k in mini(3, goal_total):
				_spawn_pill()


## Подсказка внизу экрана.
func _hint(text: String, time: float) -> void:
	if text == "":
		return
	hud.show_caption("", text)
	if hint_tween:
		hint_tween.kill()
	hint_tween = create_tween()
	hint_tween.tween_interval(time)
	hint_tween.tween_callback(hud.hide_caption)


## Цель этапа выполнена на единицу.
func _goal_progress(kind_stage: int) -> void:
	if state != State.LEVEL or stage != kind_stage:
		return
	goal_done += 1
	run_scales += 1.0
	hud.set_goal(stage, goal_done, goal_total)
	if goal_done >= goal_total:
		_stage_cleared()


func _stage_cleared() -> void:
	print("stage cleared: ", STAGES[stage]["name"], " score=", score)
	state = State.PERK
	hud.pause_allowed = false
	run_scales += 10.0
	_add_score(200 * int(cfg["score_mult"]), snake.head_pos + Vector2(0, -50), "ЭТАП ПРОЙДЕН! ")
	sfx.play("stage_clear")
	sfx.play("scale")
	hud.show_banner("ЭТАП ПРОЙДЕН!", Color(0.6, 1, 0.5), 1.2)
	_clear_field()
	snake.stun_t = 0.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	if cfg["no_skills"]:
		tw.tween_callback(func() -> void: _enter_stage(stage + 1))
	elif dbg_autopilot:  # отладка: улучшение выбирается само
		tw.tween_callback(func() -> void: _on_perk(Skills.roll_perks()[0]["id"]))
	else:
		tw.tween_callback(func() -> void:
			get_tree().paused = true
			hud.show_perks(Skills.roll_perks(), STAGES[stage + 1]["name"]))


func _on_perk(id: String) -> void:
	perks[id] = perks.get(id, 0) + 1
	get_tree().paused = false
	match id:
		"heal":
			if not snake.heal():
				snake.max_lives += 1
				snake.lives += 1
				hud.max_lives = snake.max_lives
				hud.set_lives(snake.lives)
		"shield":
			snake.shield += 1
			sfx.play("shield")
	mods = Skills.mods(perks, cfg["no_skills"])
	snake.apply_mods(mods)
	_popup(snake.head_pos + Vector2(0, -40), Skills.perk(id)["name"], Color(0.6, 1, 0.6))
	_enter_stage(stage + 1)


## Убрать всех врагов и снаряды с поля (между этапами).
func _clear_field() -> void:
	for bear in bears:
		_burst(bear.position, bear.fur, 10)
		bear.queue_free()
	bears.clear()
	for f in forks:
		_burst(f.position, Color(0.6, 0.35, 0.2), 10)
		f.queue_free()
	forks.clear()
	for p in pills:
		_burst(p.position, p.cols[0], 10)
		p.queue_free()
	pills.clear()
	_clear_drops()


func _begin_boss() -> void:
	state = State.BOSS_INTRO
	_clear_field()
	hud.show_banner("ГИГАНТСКАЯ ЯИЧНИЦА ПРИБЛИЖАЕТСЯ!", Color(1, 0.55, 0.25), 2.2)
	sfx.play_music("")
	sfx.play("phase")
	shake = 6.0

	boss = FriedEggBoss.new()
	boss.bounds = bounds
	boss.configure(cfg["boss_hp"], cfg["proj_speed"], cfg["yolk_time"], cfg["tempo"])
	boss.bite_damage = 2 if mods.get("jaws", false) else 1
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
	var debug_run := dbg_autopilot or dbg_stage >= 0 or dbg_ending  # отладочные забеги не сохраняются
	var best := _load_best(difficulty)
	var record := score > best and not debug_run
	if record:
		_save_best(difficulty, score)
		best = score
	scales_gained = int(run_scales * Skills.SCALE_MULT[difficulty])
	print("run end: win=%s stage=%d score=%d scales=+%d" % [win, stage, score, scales_gained])
	if scales_gained > 0 and not debug_run:
		Skills.add_scales(scales_gained)
	var mins := int(play_time) / 60
	var secs := int(play_time) % 60
	var lines := []
	lines.append("Змея одолела яичницу... но не своего создателя." if win else "Не сдавайся — яичница ждёт!")
	lines.append("")
	lines.append("Сложность: %s   •   Дошла до этапа: %s" % [cfg["name"], STAGES[stage]["name"]])
	lines.append("Медведей: %d   •   Вилок: %d   •   Таблеток: %d" % [bears_eaten, forks_broken, pills_eaten])
	if friendly_hits > 0:
		lines.append("Враги подрались между собой: %d раз" % friendly_hits)
	if win and ending:
		lines.append(ending.choice_text())
	lines.append("Время: %d:%02d" % [mins, secs])
	lines.append("Счёт: %d%s   •   Рекорд: %d" % [score, "   — НОВЫЙ РЕКОРД!" if record else "", best])
	lines.append("Чешуйки: +%d (всего %d)" % [scales_gained, Skills.scales])
	hud.show_end(win, "\n".join(lines), "КОНЕЦ" if win else "")


# ---------------------------------------------------------------- цикл

func _process(delta: float) -> void:
	shake = maxf(shake - delta * 40.0, 0.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * Settings.shake
	if snake:
		hud.stamina = snake.stamina
		hud.exhausted = snake.exhausted
		hud.snake_head = snake.head_pos
		hud.shield = snake.shield
		hud.pause_allowed = state in [State.LEVEL, State.BOSS_INTRO, State.BOSS]
	if state in [State.LEVEL, State.BOSS_INTRO, State.BOSS]:
		play_time += delta
	if dbg_autopilot and snake and state in [State.LEVEL, State.BOSS]:
		_debug_autopilot()

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
			_update_helpers(delta)
			_update_bears(delta)
			_update_forks(delta)
			_update_pills(delta)
			_update_drops(delta)
			_update_waves(delta)
		State.BOSS:
			snake.update(delta)
			_update_dash()
			boss.update(delta, snake)
			_update_reinforcements(delta)
			_update_bears(delta)
			_update_forks(delta)
			_update_pills(delta)
			_update_drops(delta)
			_update_waves(delta)


## Отладка: змея сама охотится на цели этапа (для записи видео Movie Maker).
func _debug_autopilot() -> void:
	snake.autopilot = true
	snake.auto_speed = 210.0
	snake.invuln = maxf(snake.invuln, 0.2)
	var best := Vector2(640, 360)
	var best_d := 99999.0
	for b in bears:
		if b.is_edible() and b.position.distance_to(snake.head_pos) < best_d:
			best_d = b.position.distance_to(snake.head_pos)
			best = b.position
	for f in forks:
		var p := f.position - f.facing() * 40.0
		if p.distance_to(snake.head_pos) < best_d:
			best_d = p.distance_to(snake.head_pos)
			best = p
	for p in pills:
		if p.is_edible() and p.position.distance_to(snake.head_pos) < best_d:
			best_d = p.position.distance_to(snake.head_pos)
			best = p.position
	if boss and state == State.BOSS and boss.is_yolk_open():
		best = boss.position + FriedEggBoss.YOLK_OFFSET
	snake.auto_target = best
	if ability >= 0 and randf() < 0.01:
		_use_ability()


# ---------------------------------------------------------------- медведи

func _update_bears(delta: float) -> void:
	for bear: TeddyBear in bears.duplicate():
		bear.update(delta, snake)
		if not (state in [State.LEVEL, State.BOSS]) or not snake.alive:
			continue
		if bear.position.distance_to(snake.head_pos) < Snake.HEAD_RADIUS + TeddyBear.RADIUS:
			if bear.is_shielded():  # пузырь медсестры: отскакиваем
				bear.pop_shield()
				snake.push((snake.head_pos - bear.position).normalized() * 420.0)
				_burst(bear.position, Color(0.6, 1, 0.8), 10)
			elif bear.is_edible():
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


## Враг попал по медведю. Возвращает true, если удар засчитан.
func _friendly_hit(victim: TeddyBear, attacker: Node2D, push_vel: Vector2) -> bool:
	if not victim.hit_by_friend(attacker, push_vel):
		return false
	friendly_hits += 1
	_add_score(5 * int(cfg["score_mult"]), victim.position, "ФРЕНДЛИ ФАЕР! ")
	_burst(victim.position, Color(1, 0.95, 0.6), 8)
	shake = maxf(shake, 5.0)
	if friendly_hits == 1:
		hud.show_banner("Враги дерутся между собой!", Color(1, 0.6, 0.9), 1.6)
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
		points *= int(mods.get("knockout", 2))
	_add_score(points * mult, bear.position, "НОКАУТ! " if bonus else "")
	bear.queue_free()
	snake.grow(3)
	_gain_ability(bear.type)
	if state != State.LEVEL or stage != 0:  # помощники на других этапах — только атака и очки
		sfx.play("eat")
		return
	bears_eaten += 1
	sfx.play("eat", 1.0 + 0.02 * bears_eaten)
	_goal_progress(0)
	if state == State.LEVEL and goal_done + bears.size() < goal_total:
		_spawn_bear(_pick_bear_type())


func _pick_bear_type() -> int:
	var a: float = cfg["bear_aggr"]
	var progress := float(goal_done) / maxf(goal_total, 1.0)
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


func _spawn_pos(margin := 40.0) -> Vector2:
	var pos := Vector2.ZERO
	var avoid := snake.head_pos if snake else Vector2(-9999, -9999)
	for attempt in 20:
		pos = Vector2(randf_range(bounds.position.x + margin, bounds.end.x - margin),
			randf_range(bounds.position.y + margin, bounds.end.y - margin))
		if pos.distance_to(avoid) > 260.0 and (boss == null or pos.distance_to(boss.position) > 200.0):
			break
	return pos


func _spawn_bear(type: int) -> void:
	var bear := TeddyBear.new()
	bear.z_index = 1
	var speed_mult: float = cfg["bear_speed"]
	bear.setup(_spawn_pos(), (55.0 + goal_done * 4.0) * speed_mult, bounds, type, cfg["bear_aggr"])
	bear.throw_item.connect(_on_bear_throw.bind(bear))
	bear.sound.connect(sfx.play)
	bear.puff.connect(_on_puff)
	bear.allies = bears
	world.add_child(bear)
	bears.append(bear)


func _on_bear_throw(pos: Vector2, velocity: Vector2, kind: int, bear: TeddyBear) -> void:
	_spawn_drop(pos, velocity, kind).thrower = bear


func _on_puff(pos: Vector2) -> void:
	_burst(pos, Color(0.35, 0.35, 0.4), 16, 0.9)


## На этапах вилок и таблеток по полю бродят пара медведей — источник атак.
func _update_helpers(delta: float) -> void:
	if stage == 0:
		return
	helper_t -= delta
	if helper_t <= 0.0 and bears.size() < 2:
		helper_t = 7.0
		_spawn_bear([TeddyBear.Type.NORMAL, TeddyBear.Type.BOXER, TeddyBear.Type.THROWER, TeddyBear.Type.KARATE,
			TeddyBear.Type.SEAMSTRESS, TeddyBear.Type.NINJA, TeddyBear.Type.BOMBER, TeddyBear.Type.MEDIC].pick_random())


# ---------------------------------------------------------------- вилки

func _spawn_fork() -> void:
	var f := Fork.new()
	f.z_index = 1
	f.setup(_spawn_pos(60.0), bounds, cfg["bear_speed"], cfg["bear_aggr"], cfg["tempo"])
	f.sound.connect(sfx.play)
	world.add_child(f)
	forks.append(f)


func _update_forks(delta: float) -> void:
	for f: Fork in forks.duplicate():
		f.update(delta, snake.head_pos, snake.alive)
		if not is_instance_valid(f):
			continue
		if snake.alive and f.touches(snake.head_pos, Snake.HEAD_RADIUS):
			if snake.is_dashing():
				_break_fork(f, "ТАРАН! ")
				continue
			if f.hits_tines(snake.head_pos):
				if snake.take_damage():
					sfx.play("punch")
					_popup(snake.head_pos + Vector2(0, -30), "ЗУБЦЫ! Бей сбоку!", Color(1, 0.5, 0.4))
					_burst(snake.head_pos, Color(1, 0.3, 0.2), 10)
				snake.push((snake.head_pos - f.position).normalized() * 520.0)
				f.bounce()
				if not fork_hinted:
					fork_hinted = true
					_hint("Вилку нельзя атаковать в лоб — заходи сбоку или сзади!", 3.0)
			else:
				_break_fork(f, "СБОКУ! " if f.st != Fork.St.STUCK else "ЗАСТРЯЛА! ")
				continue
		if not f.is_sprinting():
			continue
		for b: TeddyBear in bears:  # вилка в спринте сбивает медведей
			if f.touches(b.position, TeddyBear.RADIUS):
				_friendly_hit(b, null, f.facing() * 300.0)
		if boss and state == State.BOSS and not f.hit_boss and boss.height < 20.0 \
				and f.position.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS * 0.85:
			f.hit_boss = true
			if boss.take_chip(0.5 * mods.get("boss_dmg", 1.0)):
				_popup(f.position + Vector2(0, -30), "ВИЛКА В ЯИЧНИЦЕ!", Color(1, 0.9, 0.5))
				_burst(f.position, Color.WHITE, 12)
				sfx.play("splat", 0.8)
				shake = maxf(shake, 8.0)
			f.bounce()


func _break_fork(f: Fork, prefix := "") -> void:
	forks.erase(f)
	_burst(f.position, Color(0.62, 0.32, 0.14), 16)
	_burst(f.position, Color(0.8, 0.8, 0.85), 8)
	sfx.play("clang")
	shake = maxf(shake, 6.0)
	_add_score(FORK_POINTS * int(cfg["score_mult"]), f.position, prefix)
	f.queue_free()
	snake.grow(1)
	if state == State.LEVEL and stage == 1:
		forks_broken += 1
		_goal_progress(1)
		if state == State.LEVEL and goal_done + forks.size() < goal_total:
			_spawn_fork()


# ---------------------------------------------------------------- таблетки

func _spawn_pill() -> void:
	var p := Pill.new()
	p.z_index = 3
	p.setup(_spawn_pos(50.0), bounds, cfg["tempo"], cfg["bear_aggr"])
	p.sound.connect(sfx.play)
	p.landed.connect(_on_pill_landed.bind(p))
	world.add_child(p)
	pills.append(p)


func _update_pills(delta: float) -> void:
	var head_vel := Vector2.from_angle(snake.heading) * Snake.BASE_SPEED
	for p: Pill in pills.duplicate():
		p.update(delta, snake.head_pos, head_vel, snake.alive)
		if snake.alive and p.is_edible() and p.position.distance_to(snake.head_pos) < Pill.RADIUS + Snake.HEAD_RADIUS:
			_eat_pill(p)


func _eat_pill(p: Pill, prefix := "") -> void:
	if not pills.has(p):
		return
	pills.erase(p)
	_burst(p.position, p.cols[0], 12)
	_burst(p.position, p.cols[1], 8)
	sfx.play("eat", 1.3)
	_add_score(PILL_POINTS * int(cfg["score_mult"]), p.position, prefix)
	p.queue_free()
	snake.grow(2)
	snake.stamina = minf(snake.stamina + 0.2, 1.0)
	if state == State.LEVEL and stage == 2:
		pills_eaten += 1
		_goal_progress(2)
		if state == State.LEVEL and goal_done + pills.size() < goal_total:
			_spawn_pill()


func _on_pill_landed(pos: Vector2, p: Pill) -> void:
	if not is_instance_valid(p) or not pills.has(p):
		return
	shake = maxf(shake, 9.0)
	_burst(pos, Color(0.9, 0.9, 0.95), 14, 0.8)
	if snake.alive and snake.head_pos.distance_to(pos) < Pill.CRUSH_RADIUS + Snake.HEAD_RADIUS * 0.5:
		if snake.take_damage():
			_popup(snake.head_pos + Vector2(0, -30), "РАЗДАВИЛО!", Color(1, 0.5, 0.4))
			sfx.play("hurt")
		snake.push((snake.head_pos - pos).normalized() * 450.0)
	for b: TeddyBear in bears:  # давит и медведей
		if b.position.distance_to(pos) < Pill.CRUSH_RADIUS + TeddyBear.RADIUS:
			_friendly_hit(b, null, (b.position - pos).normalized() * 300.0)
	var w := Shockwave.new()
	w.z_index = 1
	w.setup_stun(pos, 200.0 + 40.0 * float(cfg["bear_aggr"]))
	world.add_child(w)
	waves.append(w)


# ---------------------------------------------------------------- снаряды

func _spawn_drop(pos: Vector2, velocity: Vector2, kind: int) -> OilDrop:
	var d := OilDrop.new()
	d.z_index = 3
	d.setup(pos, velocity, kind)
	world.add_child(d)
	drops.append(d)
	return d


func _remove_drop(d: OilDrop) -> void:
	drops.erase(d)
	d.queue_free()


## Взрыв хлопушки: задевает всех в радиусе. Хлопушка змеи змею не ранит.
func _explode(pos: Vector2, from_snake: bool) -> void:
	sfx.play("boom")
	shake = maxf(shake, 13.0)
	for c in [Color(0.95, 0.3, 0.5), Color(0.3, 0.7, 0.95), Color(0.6, 0.9, 0.3), Color(1, 0.85, 0.3)]:
		_burst(pos, c, 10, 1.2)
	_burst(pos, Color(1, 0.95, 0.8), 18, 1.4)
	var r := OilDrop.BLAST_RADIUS
	if not from_snake and snake.alive and snake.head_pos.distance_to(pos) < r:
		if snake.take_damage():
			_popup(snake.head_pos + Vector2(0, -30), "БАБАХ!", Color(1, 0.6, 0.3))
		snake.push((snake.head_pos - pos).normalized() * 520.0)
	for b: TeddyBear in bears.duplicate():
		if b.position.distance_to(pos) < r + TeddyBear.RADIUS:
			var v := (b.position - pos).normalized() * 380.0
			if from_snake:
				_snake_hits_bear(b, v)
			else:
				_friendly_hit(b, null, v)
	for f: Fork in forks.duplicate():
		if f.position.distance_to(pos) < r + 20.0:
			if from_snake:
				_break_fork(f, "БАБАХ! ")
			else:
				f.bounce()
	if from_snake:
		for p: Pill in pills.duplicate():
			if not p.in_air() and p.position.distance_to(pos) < r + Pill.RADIUS:
				_eat_pill(p, "БАБАХ! ")
		if boss and state == State.BOSS and pos.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS + r * 0.6:
			if boss.take_chip(0.8 * mods.get("boss_dmg", 1.0)):
				sfx.play("splat", 1.1)


func _update_snake_shot(d: OilDrop) -> bool:
	for bear: TeddyBear in bears:
		if bear.position.distance_to(d.position) < OilDrop.RADIUS + TeddyBear.RADIUS:
			if d.kind == OilDrop.Kind.CRACKER:
				return true
			_snake_hits_bear(bear, d.vel.normalized() * 260.0)
			return true
	for f: Fork in forks:
		if f.touches(d.position, OilDrop.RADIUS):
			if d.kind == OilDrop.Kind.CRACKER:
				return true
			if f.hits_tines(d.position):  # в лоб — отскакивает от зубцов
				_burst(d.position, Color(0.8, 0.8, 0.85), 5)
				sfx.play("clang", 1.6, -8.0)
			else:
				_break_fork(f, "МЕТКО! ")
			return true
	for p: Pill in pills:
		if not p.in_air() and p.position.distance_to(d.position) < OilDrop.RADIUS + Pill.RADIUS:
			if d.kind != OilDrop.Kind.CRACKER:
				_eat_pill(p, "МЕТКО! ")
			return true
	if boss and state == State.BOSS and boss.height < 20.0 \
			and d.position.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS * 0.9:
		if d.kind == OilDrop.Kind.CRACKER:
			return true
		var amount := 0.25 if d.kind == OilDrop.Kind.BUTTON else 0.18
		var yolk := boss.position + FriedEggBoss.YOLK_OFFSET
		if boss.is_yolk_open() and d.position.distance_to(yolk) < FriedEggBoss.YOLK_RADIUS + 14.0:
			amount *= 3.0
		if boss.take_chip(amount * mods.get("boss_dmg", 1.0)):
			sfx.play("splat", 1.3)
		_burst(d.position, Color(1, 0.95, 0.7), 6)
		return true
	return false


func _update_drops(delta: float) -> void:
	for d: OilDrop in drops.duplicate():
		d.update(delta, snake.head_pos)
		if d.from_snake:
			var contact := _update_snake_shot(d)
			if d.kind == OilDrop.Kind.CRACKER and (contact or d.should_explode()):
				_explode(d.position, true)
				_remove_drop(d)
			elif contact or d.life <= 0.0 or not ARENA.has_point(d.position):
				_remove_drop(d)
			continue
		if d.kind == OilDrop.Kind.CRACKER:
			var touched := snake.alive and d.position.distance_to(snake.head_pos) < OilDrop.RADIUS + Snake.HEAD_RADIUS
			if d.should_explode() or touched:
				_explode(d.position, false)
				_remove_drop(d)
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
		elif d.kind in [OilDrop.Kind.BUTTON, OilDrop.Kind.NEEDLE, OilDrop.Kind.SHURIKEN]:  # френдли фаер
			for bear: TeddyBear in bears:
				if bear != d.thrower and bear.position.distance_to(d.position) < OilDrop.RADIUS + TeddyBear.RADIUS:
					var thrower: Node2D = d.thrower if is_instance_valid(d.thrower) else null
					_friendly_hit(bear, thrower, d.vel.normalized() * 240.0)
					hit = true
					break
		if hit or d.life <= 0.0 or not ARENA.has_point(d.position):
			_remove_drop(d)


func _update_waves(delta: float) -> void:
	for w: Shockwave in waves.duplicate():
		w.update(delta)
		if w.hits(snake.head_pos):
			w.hit_done = true
			if w.stun:
				if snake.stun(1.3):
					sfx.play("stun")
					_popup(snake.head_pos + Vector2(0, -30), "ОГЛУШЕНА!", Color(0.6, 0.8, 1))
					if not stun_hinted:
						stun_hinted = true
						_hint("Волну таблетки можно пережить в рывке или просто держаться подальше", 3.0)
			elif snake.take_damage():
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


# ---------------------------------------------------------------- атаки змеи

func _gain_ability(type: int) -> void:
	if not ABILITIES.has(type):  # обычный медведь восстанавливает силы
		snake.stamina = minf(snake.stamina + 0.3, 1.0)
		return
	var info: Dictionary = ABILITIES[type]
	var add: int = info["charges"] + int(mods.get("charges", 0))
	if type == ability:
		charges += add
	else:
		ability = type
		charges = add
		_popup(snake.head_pos + Vector2(0, -40), "НОВАЯ АТАКА: " + info["name"], Color(0.5, 1, 0.5))
	sfx.play("power")
	hud.set_ability(ability, info["name"], charges)
	if not ability_hinted:
		ability_hinted = true
		hud.show_banner("Пробел / ЛКМ — атака съеденного медведя!", Color(0.5, 1, 0.5), 1.8)


func _use_ability() -> void:
	if ability < 0 or charges <= 0 or not snake.alive or snake.is_stunned():
		return
	var info: Dictionary = ABILITIES[ability]
	if not snake.spend(info["cost"] * mods.get("cost", 1.0)):
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
		TeddyBear.Type.NINJA:
			snake.dash(0.24, Snake.DASH_SPEED * 1.3, true)
			dash_hit_boss = false
			_burst(snake.head_pos, Color(0.3, 0.3, 0.35), 18, 0.9)
			sfx.play("poof")
		TeddyBear.Type.BOMBER:
			var c := _spawn_drop(muzzle, dir * 520.0, OilDrop.Kind.CRACKER)
			c.from_snake = true
			c.fuse = 0.9
			sfx.play("fuse")
		TeddyBear.Type.MEDIC:
			if snake.heal():
				_popup(snake.head_pos + Vector2(0, -40), "+1 ЖИЗНЬ", Color(1, 0.5, 0.6))
			else:
				snake.shield += 1
				_popup(snake.head_pos + Vector2(0, -40), "ЩИТ!", Color(0.6, 0.85, 1))
			sfx.play("heal")
			_burst(snake.head_pos, Color(0.5, 1, 0.6), 14)
	charges -= 1
	if charges <= 0:
		ability = -1
	hud.set_ability(ability, info["name"], charges)


## Вертушка: раскидывает врагов вокруг головы, сбивает вражеские снаряды, задевает яичницу.
func _spin_attack() -> void:
	var head := snake.head_pos
	for bear: TeddyBear in bears.duplicate():
		if bear.position.distance_to(head) < SPIN_RADIUS:
			_snake_hits_bear(bear, (bear.position - head).normalized() * 380.0)
	for f: Fork in forks.duplicate():
		if f.position.distance_to(head) < SPIN_RADIUS:
			_break_fork(f, "ВЕРТУШКА! ")
	for p: Pill in pills.duplicate():
		if not p.in_air() and p.position.distance_to(head) < SPIN_RADIUS:
			_eat_pill(p, "ВЕРТУШКА! ")
	for d: OilDrop in drops.duplicate():
		if not d.from_snake and d.position.distance_to(head) < SPIN_RADIUS:
			_burst(d.position, Color(1, 1, 0.8), 4)
			_remove_drop(d)
	if boss and state == State.BOSS and head.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS + SPIN_RADIUS * 0.8:
		if boss.take_chip(0.5 * mods.get("boss_dmg", 1.0)):
			_burst(boss.position + (head - boss.position).normalized() * FriedEggBoss.WHITE_RADIUS * 0.8, Color.WHITE, 12)
			sfx.play("kick")
	shake = maxf(shake, 6.0)


## Рывок (боксёр или ниндзя): сбивает медведей по пути, ломает вилки, таранит яичницу.
func _update_dash() -> void:
	if not snake.is_dashing():
		return
	for bear: TeddyBear in bears.duplicate():
		if bear.position.distance_to(snake.head_pos) < Snake.HEAD_RADIUS + TeddyBear.RADIUS + 8.0:
			_snake_hits_bear(bear, Vector2.from_angle(snake.heading) * 420.0)
	if snake.shadow_dash:
		for d: OilDrop in drops.duplicate():  # теневой рывок проходит сквозь снаряды и режет их
			if not d.from_snake and d.kind != OilDrop.Kind.CRACKER and d.position.distance_to(snake.head_pos) < 40.0:
				_burst(d.position, Color(0.4, 0.4, 0.45), 4)
				_remove_drop(d)
	if boss and state == State.BOSS and not dash_hit_boss \
			and snake.head_pos.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS * 0.85:
		dash_hit_boss = true
		if boss.take_chip(0.6 * mods.get("boss_dmg", 1.0)):
			sfx.play("punch")
			shake = 14.0
			_burst(snake.head_pos, Color.WHITE, 14)
		snake.push((snake.head_pos - boss.position).normalized() * 600.0)
		snake.dash_t = 0.0


func _snake_hits_bear(bear: TeddyBear, push_vel: Vector2) -> void:
	if bear.hit_by_friend(null, push_vel):
		_add_score(5 * int(cfg["score_mult"]), bear.position, "БАЦ! ")
		_burst(bear.position, Color(0.6, 1, 0.6), 8)


## Во время боя с яичницей на помощь ей по очереди приходят медведи, вилки и таблетки.
func _update_reinforcements(delta: float) -> void:
	reinforce_t -= delta
	if reinforce_t > 0.0 or bears.size() + forks.size() + pills.size() >= 3:
		return
	reinforce_t = 7.5 * clampf(cfg["tempo"], 0.6, 1.3)
	var pos := Vector2.ZERO
	match reinforce_kind % 3:
		0:
			_spawn_bear([TeddyBear.Type.BOXER, TeddyBear.Type.THROWER, TeddyBear.Type.KARATE, TeddyBear.Type.SEAMSTRESS,
				TeddyBear.Type.NINJA, TeddyBear.Type.BOMBER, TeddyBear.Type.MEDIC].pick_random())
			pos = bears.back().position
		1:
			_spawn_fork()
			pos = forks.back().position
		2:
			_spawn_pill()
			pos = pills.back().position
	reinforce_kind += 1
	_popup(pos + Vector2(0, -30), "НА ПОМОЩЬ ЯИЧНИЦЕ!", Color(1, 0.8, 0.5))
	if not reinforce_hinted:
		reinforce_hinted = true
		hud.show_banner("На помощь яичнице идут медведи, вилки и таблетки!", Color(1, 0.7, 0.4), 2.0)
		_hint("Съешь медведя — его атака ранит яичницу. Вилку в спринте можно направить в неё!", 4.0)


func _add_score(points: int, pos: Vector2, prefix := "") -> void:
	score += points
	hud.set_score(score)
	_popup(pos, "%s+%d" % [prefix, points], Color(1, 0.95, 0.4) if prefix == "" else Color(1, 0.5, 0.9))


# ---------------------------------------------------------------- сигналы

func _on_snake_damaged(lives_left: int) -> void:
	var healed := lives_left >= hud.lives
	hud.set_lives(lives_left)
	if healed:
		return
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
	print("boss defeated, score=", score)
	_clear_field()
	run_scales += 30.0
	_add_score(1000 * int(cfg["score_mult"]), boss.position + Vector2(0, -90), "ЯИЧНИЦА СЪЕДЕНА! ")
	hud.set_boss(true, 0, boss.max_hp, 3)
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
	hud.set_best_scores([0, 0, 0, 0])


func _save_best(i: int, value: int) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("best", str(i), value)
	cf.save(SAVE_PATH)


# ---------------------------------------------------------------- эффекты и арена

func _popup(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	var ls := LabelSettings.new()
	ls.font = hud.title_font
	ls.font_size = 22
	ls.font_color = color
	ls.outline_size = 7
	ls.outline_color = Color(0.15, 0.05, 0.0)
	ls.shadow_size = 3
	ls.shadow_color = Color(0, 0, 0, 0.35)
	ls.shadow_offset = Vector2(2, 3)
	label.label_settings = ls
	label.z_index = 5
	label.size = Vector2(400, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos - Vector2(200, 30)
	label.pivot_offset = Vector2(200, 20)
	label.scale = Vector2(0.6, 0.6)
	world.add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "position:y", label.position.y - 50.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.5)
	tw.tween_callback(label.queue_free)


## Облачко частиц: мягкие круглые пылинки, уменьшаются и тают.
func _burst(pos: Vector2, color: Color, amount: int, size := 1.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 4
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.75
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 280.0
	p.damping_min = 120.0
	p.damping_max = 260.0
	p.gravity = Vector2(0, 250)
	p.texture = Tex.soft()
	p.scale_amount_min = 0.09 * size
	p.scale_amount_max = 0.17 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.3, 1.3, 1.3, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.color = color
	p.finished.connect(p.queue_free)
	world.add_child(p)
	p.emitting = true


## Деревянный бортик ящика: волокна, фаска, внутренняя тень, гвозди.
func _draw_frame() -> void:
	for k in 7:  # тень бортика на полу
		frame.draw_rect(bounds.grow(-k * 3.0 - 1.5), Color(0, 0, 0, 0.07 - k * 0.009), false, 3.0)
	var wood := Color(0.52, 0.32, 0.16)
	frame.draw_rect(ARENA.grow(-WALL / 2), wood, false, WALL)
	for i in 5:  # волокна вдоль досок
		var off := 3.0 + i * 4.5
		var col := wood.darkened(0.12 + 0.06 * (i % 2)) if i % 2 == 0 else wood.lightened(0.06)
		frame.draw_rect(ARENA.grow(-off), col, false, 1.2)
	frame.draw_rect(ARENA.grow(-1.5), Color(0.72, 0.5, 0.28), false, 3.0)  # светлая кромка снаружи
	frame.draw_rect(bounds.grow(1.5), Color(0.25, 0.14, 0.06), false, 3.0)  # тёмная кромка внутри
	for c in [Vector2(12, 12), Vector2(1268, 12), Vector2(12, 708), Vector2(1268, 708),
			Vector2(640, 12), Vector2(640, 708), Vector2(12, 360), Vector2(1268, 360)]:  # гвозди
		frame.draw_circle(c + Vector2(1, 1.5), 4.5, Color(0, 0, 0, 0.35))
		frame.draw_circle(c, 4.0, Color(0.5, 0.5, 0.52))
		frame.draw_circle(c + Vector2(-1.2, -1.2), 1.6, Color(0.9, 0.9, 0.92))
