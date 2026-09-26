extends Node2D
## Главный узел игры: состояния и этапы забега, счёт, итоги. Всю работу делают помощники:
## EnemyDirector (враги), Projectiles (снаряды и волны), Abilities (атаки змеи), BossFight (яичница),
## MenuDemo (фон меню), Fx (частицы и надписи), Arena (ящик), Hud (интерфейс).
## Этапы: 0 — медведи, 1 — ржавые вилки, 2 — прыгающие таблетки, 3 — гигантская яичница.
## Отладка (аргументы после `--`): --stage=N, --diff=N, --ending, --autopilot, --dump-sfx, --skills,
## --perks, --touch (сенсорный режим на ПК), --dev (открыть панель разработчика).

const Balance = preload("res://scripts/core/balance.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Controls = preload("res://scripts/core/controls.gd")
const RunReport = preload("res://scripts/game/run_report.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Skills = preload("res://scripts/core/skills.gd")
const SaveData = preload("res://scripts/core/save_data.gd")
const Platform = preload("res://scripts/core/platform.gd")
const Snake = preload("res://scripts/entities/snake.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const Design = preload("res://scripts/ui/design.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const DevPanel = preload("res://scripts/ui/dev_panel.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")
const Tex = preload("res://scripts/gfx/tex.gd")
const Ending = preload("res://scripts/ending/ending.gd")
const Arena = preload("res://scripts/game/arena.gd")
const Fx = preload("res://scripts/game/fx.gd")
const EnemyDirector = preload("res://scripts/game/enemy_director.gd")
const Projectiles = preload("res://scripts/game/projectiles.gd")
const Abilities = preload("res://scripts/game/abilities.gd")
const BossFight = preload("res://scripts/game/boss_fight.gd")
const MenuDemo = preload("res://scripts/game/menu_demo.gd")
const Autopilot = preload("res://scripts/game/autopilot.gd")

enum State { LOADING, MENU, LEVEL, PERK, BOSS_INTRO, BOSS, OUTRO, CUTSCENE, WIN, GAME_OVER }

## Переживают перезагрузку сцены: выбранная сложность и «сразу начать заново».
static var difficulty := 1
static var auto_start := false

var state := State.LOADING
var cfg: Dictionary = Balance.DIFFICULTIES[1]
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
var bounds := Balance.ARENA.grow(-Balance.WALL)
var shake := 0.0
## Отладочный забег (аргументы, автопилот, читы): рекорды и чешуйки не сохраняются.
var debug_run := false
var autopilot := false

var world: Node2D
var arena: Arena
var camera: Camera2D
var hud: Hud
var sfx: Sfx
var dev_panel: DevPanel
var snake: Snake
var boss: FriedEggBoss
var ending: Ending
var fx: Fx
var enemies: EnemyDirector
var shots: Projectiles
var abilities: Abilities
var boss_fight: BossFight
var menu_demo: MenuDemo
var hint_tween: Tween
var args := {"stage": -1, "ending": false, "skills": false, "perks": false, "dev": false}
var shot_frames: Array[int] = []  # --shots=30,90: снимки экрана на этих кадрах (проверка раскладки)


func _ready() -> void:
	randomize()
	_parse_args()
	var root := get_tree().root
	if not root.tree_exiting.is_connected(_on_quit):
		root.tree_exiting.connect(_on_quit)
	Settings.ensure_loaded()
	Skills.ensure_loaded()
	Controls.setup()
	camera = Camera2D.new()
	camera.position = Balance.ARENA.get_center()
	add_child(camera)
	arena = Arena.new()
	add_child(arena)
	world = Node2D.new()
	add_child(world)
	fx = Fx.new(world)
	enemies = EnemyDirector.new(self)
	shots = Projectiles.new(self)
	abilities = Abilities.new(self)
	boss_fight = BossFight.new(self)
	sfx = Sfx.new()
	add_child(sfx)
	hud = Hud.new()
	hud.sfx = sfx
	add_child(hud)
	hud.difficulty_chosen.connect(start_game)
	hud.retry_pressed.connect(restart.bind(true))
	hud.menu_pressed.connect(restart.bind(false))
	hud.records_reset.connect(_reset_records)
	hud.perk_chosen.connect(_on_perk)
	hud.attack_pressed.connect(_try_attack)
	hud.skip_pressed.connect(_skip_ending)
	hud.dev_toggled.connect(func() -> void: dev_panel.toggle())
	hud.back_unhandled.connect(func() -> void:  # «Назад» в финале — пропустить
		if state == State.CUTSCENE:
			_skip_ending())
	dev_panel = DevPanel.new()
	dev_panel.game = self
	add_child(dev_panel)

	if "--dump-sfx" in OS.get_cmdline_user_args():
		var dir := ProjectSettings.globalize_path("user://sfx_dump")
		sfx.dump(dir)
		print("SFX dumped to ", dir)
		get_tree().quit()
		return
	if not Sfx.is_ready():  # первый запуск: ждём синтез звуков
		hud.show_loading(0.0)
		while not Sfx.is_ready():
			await get_tree().process_frame
			hud.show_loading(Sfx.progress())
		hud.hide_loading()
	_boot()


func _boot() -> void:
	sfx.play_music("level")
	if auto_start or args["stage"] >= 0 or args["ending"]:
		auto_start = false
		start_game(difficulty)
	else:
		show_menu()
		if args["skills"]:
			hud.open_skills()
		elif args["perks"]:
			hud.show_perks(Skills.roll_perks(), Balance.STAGES[1]["name"])
		elif args.get("settings", false):
			hud.push(hud.settings_screen)
			hud.settings_screen.tabs.select(args.get("tab", 0))
			hud.settings_screen._show_tab(args.get("tab", 0))
	if args["dev"]:
		dev_panel.toggle()
	_open_for_debug(args.get("open", ""))
	if not shot_frames.is_empty():
		hud.shot_frames = shot_frames


## Отладка раскладки: сразу открыть нужный экран (аргумент --open=...).
func _open_for_debug(what: String) -> void:
	match what:
		"pause":
			hud.set_paused(true)
		"end", "win":
			score = 1234
			_end(what == "win")
		"perks":
			hud.show_perks(Skills.roll_perks(), Balance.STAGES[1]["name"])
		"skills":
			hud.open_skills()
		"settings":
			hud.push(hud.settings_screen)
		"restart":  # проверка перезагрузки сцены: итоги → меню → итоги …
			_end(false)
			get_tree().create_timer(0.5).timeout.connect(restart.bind(false))


## Выход из игры: освободить static-кэши звуков, текстур и шрифтов (иначе утечки при выходе).
static func _on_quit() -> void:
	Sfx.release_all()
	Tex.clear_cache()
	Design.clear_cache()


func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			args["stage"] = clampi(int(a.get_slice("=", 1)), 0, Balance.BOSS_STAGE)
		elif a.begins_with("--diff="):
			difficulty = clampi(int(a.get_slice("=", 1)), 0, Balance.DIFFICULTIES.size() - 1)
		elif a == "--autopilot":
			autopilot = true
		elif a == "--touch":  # мобильный режим на ПК: мышь притворяется пальцем
			Platform.force_touch = true
			Platform.force_mobile = true
			Input.emulate_touch_from_mouse = true
		elif a.begins_with("--open="):  # открыть экран для скриншота: pause, end, win, perks, skills, settings
			args["open"] = a.get_slice("=", 1)
		elif a.begins_with("--shots="):
			for n in a.get_slice("=", 1).split(","):
				shot_frames.append(int(n))
		elif a.begins_with("--settings-tab="):
			args["settings"] = true
			args["tab"] = int(a.get_slice("=", 1))
		elif a in ["--ending", "--skills", "--perks", "--dev", "--settings"]:
			args[a.trim_prefix("--")] = true
	debug_run = autopilot or args["stage"] >= 0 or args["ending"]


# ---------------------------------------------------------------- меню и старт

func show_menu() -> void:
	state = State.MENU
	menu_demo = MenuDemo.new(self)
	hud.show_menu(Balance.DIFFICULTIES, SaveData.bests(Balance.DIFFICULTIES.size()), difficulty)


func start_game(diff: int) -> void:
	difficulty = diff
	cfg = Balance.difficulty(diff)
	if menu_demo:
		menu_demo.clear()
		menu_demo = null
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
	hud.set_ability(-1, "", 0)
	hud.set_dev_run(debug_run)
	if args["ending"]:
		state = State.OUTRO
		bears_eaten = cfg["bears"]
		forks_broken = cfg["forks"]
		pills_eaten = cfg["pills"]
		arena.set_floor(Balance.STAGES[Balance.BOSS_STAGE]["floor"])
		start_ending()
		return
	enter_stage(maxi(args["stage"], 0))


func restart(retry: bool) -> void:
	if get_tree().current_scene == null:  # игра встроена в тест — перезагружать нечего
		return
	auto_start = retry
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene.call_deferred()


func enter_stage(i: int) -> void:
	stage = i
	goal_done = 0
	var st: Dictionary = Balance.STAGES[i]
	arena.set_floor(st["floor"])
	if i == Balance.BOSS_STAGE:
		goal_total = 0
		hud.set_goal(i, 0, 0)
		_begin_boss()
		return
	goal_total = Balance.goal(cfg, i)
	hud.set_goal(i, 0, goal_total)
	sfx.play_music(st["music"])
	hud.show_banner("ЭТАП %d: %s" % [i + 1, st["name"]], Color(1, 0.9, 0.5), 1.6)
	hint(st["hint"], 4.0)
	state = State.LEVEL
	enemies.spawn_for_stage(i, goal_total)


## Подсказка внизу экрана (можно отключить в настройках).
func hint(text: String, time: float) -> void:
	if text == "" or not hints_on():
		return
	hud.show_hint(text)
	if hint_tween:
		hint_tween.kill()
	hint_tween = create_tween()
	hint_tween.tween_interval(time)
	hint_tween.tween_callback(hud.hide_caption)


func hints_on() -> bool:
	return Settings.flag("hints")


func touch_on() -> bool:
	return Settings.touch_enabled()


## Идёт этап с целью kind_stage (цели засчитываются только на своём этапе).
func is_goal_stage(kind_stage: int) -> bool:
	return state == State.LEVEL and stage == kind_stage


func in_boss_fight() -> bool:
	return state == State.BOSS


## Цель этапа выполнена на единицу.
func goal_progress(kind_stage: int) -> void:
	if not is_goal_stage(kind_stage):
		return
	goal_done += 1
	run_scales += Balance.SCALES_PER_GOAL
	hud.set_goal(stage, goal_done, goal_total)
	if goal_done >= goal_total:
		_stage_cleared()


func _stage_cleared() -> void:
	print("stage cleared: ", Balance.STAGES[stage]["name"], " score=", score)
	state = State.PERK
	run_scales += Balance.SCALES_PER_STAGE
	add_score(Balance.STAGE_POINTS, snake.head_pos + Vector2(0, -50), "ЭТАП ПРОЙДЕН! ")
	sfx.play("stage_clear")
	sfx.play("scale")
	vibrate(60)
	hud.show_banner("ЭТАП ПРОЙДЕН!", Color(0.6, 1, 0.5), 1.2)
	_clear_field()
	snake.stun_t = 0.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	if cfg["no_skills"]:
		tw.tween_callback(func() -> void: enter_stage(stage + 1))
	elif autopilot:  # отладка: улучшение выбирается само
		tw.tween_callback(func() -> void: _on_perk(Skills.roll_perks()[0]["id"]))
	else:
		tw.tween_callback(func() -> void:
			get_tree().paused = true
			hud.show_perks(Skills.roll_perks(), Balance.STAGES[stage + 1]["name"]))


func _on_perk(id: String) -> void:
	perks[id] = perks.get(id, 0) + 1
	get_tree().paused = false
	match id:
		"heal":
			if not snake.heal():
				snake.max_lives += 1
				snake.lives += 1
				hud.set_max_lives(snake.max_lives)
				hud.set_lives(snake.lives)
		"shield":
			snake.shield += 1
			sfx.play("shield")
	mods = Skills.mods(perks, cfg["no_skills"])
	snake.apply_mods(mods)
	fx.popup(snake.head_pos + Vector2(0, -40), Skills.perk(id)["name"], Color(0.6, 1, 0.6))
	enter_stage(stage + 1)


func _clear_field() -> void:
	enemies.clear()
	shots.clear()


func _begin_boss() -> void:
	state = State.BOSS_INTRO
	_clear_field()
	boss = boss_fight.begin()


## Яичница приземлилась и готова к бою.
func on_boss_ready() -> void:
	if state == State.BOSS_INTRO:
		state = State.BOSS
		boss.active = true


func on_boss_defeated() -> void:
	_clear_field()
	run_scales += Balance.SCALES_PER_BOSS
	state = State.OUTRO


func start_ending() -> void:
	state = State.CUTSCENE
	hud.set_boss(false)
	ending = Ending.new()
	add_child(ending)
	ending.finished.connect(func() -> void:
		hud.set_cinematic(false)
		_end(true))
	ending.start(self)


var _skip_armed := false


func _skip_ending() -> void:
	if state != State.CUTSCENE or ending == null:
		return
	if Settings.flag("confirm_skip") and not _skip_armed:
		_skip_armed = true
		hud.show_banner("Ещё раз — пропустить финал", Design.MUTED, 1.2)
		return
	ending.skip()


func _try_attack() -> void:
	if state in [State.LEVEL, State.BOSS] and not get_tree().paused:
		abilities.use()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_panel"):
		dev_panel.toggle()
		get_viewport().set_input_as_handled()
		return
	if state == State.CUTSCENE and ending:
		if event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			_skip_ending()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			ending.choose_throw()  # тап по экрану на телефоне — тоже бросок
		elif event is InputEventScreenTouch and event.pressed:
			ending.choose_throw()
	elif event.is_action_pressed("ability"):
		# эмулированный из касания клик — не атака: для атаки есть кнопка
		if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_try_attack()


func _end(win: bool) -> void:
	state = State.WIN if win else State.GAME_OVER
	if boss:
		boss.active = false
	shots.clear()
	if not win:
		sfx.play_music("")
		sfx.play("lose")
		vibrate(300)
	var best := SaveData.best(difficulty)
	var record := not debug_run and SaveData.submit_score(difficulty, score)
	if record:
		best = score
	scales_gained = Skills.scales_for_run(run_scales, difficulty)
	print("run end: win=%s stage=%d score=%d scales=+%d" % [win, stage, score, scales_gained])
	if scales_gained > 0 and not debug_run:
		Skills.add_scales(scales_gained)
	var rows := RunReport.rows(self, win, record, best)
	var line := RunReport.headline(win)
	hud.show_end(win, "КОНЕЦ" if win else "", line, rows)


# ---------------------------------------------------------------- цикл

func _process(delta: float) -> void:
	shake = maxf(shake - delta * 40.0, 0.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * Settings.num("shake")
	var fighting := state in [State.LEVEL, State.BOSS]
	if snake:
		var head_screen := get_viewport().get_canvas_transform() * snake.head_pos
		hud.track_snake(snake.stamina, snake.exhausted, snake.shield, head_screen, play_time)
		hud.pause_allowed = state in [State.LEVEL, State.BOSS_INTRO, State.BOSS]
		hud.pause_summary = "%s  •  этап %d: %s  •  счёт %d" % [cfg["name"], stage + 1, Balance.STAGES[stage]["short"], score]
		snake.touch_steer = hud.touch.steer if hud.touch.active else Vector2.ZERO
		snake.touch_sprint = hud.touch.active and hud.touch.sprint_held
	if state in [State.LEVEL, State.BOSS_INTRO, State.BOSS]:
		play_time += delta
	if autopilot and snake and fighting:
		Autopilot.drive(self)

	match state:
		State.MENU:
			if menu_demo:
				menu_demo.update(delta)
		State.WIN, State.GAME_OVER, State.OUTRO, State.BOSS_INTRO, State.CUTSCENE:
			if snake:
				snake.update(delta)
			if boss:
				boss.update(delta, snake)
		State.LEVEL, State.BOSS:
			snake.update(delta)
			abilities.update_dash()
			if state == State.BOSS:
				boss.update(delta, snake)
				enemies.update_reinforcements(delta)
			else:
				enemies.update_helpers(delta)
			enemies.update_bears(delta, snake, true)
			enemies.update_forks(delta, snake)
			enemies.update_pills(delta, snake)
			shots.update_drops(delta)
			shots.update_waves(delta)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			if Settings.flag("pause_unfocused") and hud and hud.pause_allowed and not get_tree().paused:
				hud.set_paused(true)
			if Settings.flag("mute_unfocused") and sfx:
				sfx.set_suspended(true)
			Settings.save()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			if sfx:
				sfx.set_suspended(false)


# ---------------------------------------------------------------- очки, эффекты, сигналы

## Очки с множителем сложности.
func add_score(base_points: int, pos: Vector2, prefix := "") -> void:
	add_score_raw(Combat.points(base_points, cfg), pos, prefix)


func add_score_raw(points: int, pos: Vector2, prefix := "") -> void:
	score += points
	hud.set_score(score)
	fx.popup(pos, "%s+%d" % [prefix, points], Color(1, 0.95, 0.4) if prefix == "" else Color(1, 0.5, 0.9), true)


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


func vibrate(ms: int) -> void:
	Platform.vibrate(ms, Settings.flag("vibration"))


func _on_snake_damaged(lives_left: int) -> void:
	var healed := lives_left >= hud.lives()
	hud.set_lives(lives_left)
	if healed:
		return
	shake = 14.0
	sfx.play("hurt")
	vibrate(90)


func _on_snake_died() -> void:
	fx.burst(snake.head_pos, Color(0.4, 0.85, 0.35), 30)
	_end(false)


func _reset_records() -> void:
	SaveData.reset_records()
	menu_demo_refresh()


func menu_demo_refresh() -> void:
	if state == State.MENU:
		hud.menu.set_data(Balance.DIFFICULTIES, SaveData.bests(Balance.DIFFICULTIES.size()), difficulty,
			Skills.scales, touch_on())


## Пометить забег отладочным (любое читерство из панели разработчика).
func mark_debug_run() -> void:
	if not debug_run:
		debug_run = true
		hud.set_dev_run(true)
