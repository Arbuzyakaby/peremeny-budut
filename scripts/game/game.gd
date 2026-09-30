extends Node2D
## Главный узел игры: состояния и этапы забега, счёт, итоги. Всю работу делают помощники:
## EnemyDirector (враги), Projectiles (снаряды и волны), Abilities (атаки змеи), BossFight (яичница),
## MenuDemo (фон меню), Fx (частицы и надписи), Arena (ящик), Hud (интерфейс).
## Этапы: 0 — медведи, 1 — ржавые вилки, 2 — прыгающие таблетки, 3 — терем матрёшек (v9.0),
## 4 — гигантская яичница. После финала (v10.0) — фальшивое меню и технический режим «Контакт»
## (scripts/contact/): та же сцена, без перезагрузки; итоги обычного забега записываются до него.
## Отладка (аргументы после `--`): --stage=N, --diff=N, --ending, --autopilot, --dump-sfx, --skills,
## --perks, --touch (сенсорный режим на ПК), --dev (открыть панель разработчика), --contact,
## --contact-finale, --fake-menu.

const Balance = preload("res://scripts/core/balance.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Controls = preload("res://scripts/core/controls.gd")
const RunReport = preload("res://scripts/game/run_report.gd")
const RunStats = preload("res://scripts/game/run_stats.gd")
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
const Bestiary = preload("res://scripts/core/bestiary.gd")
const Daily = preload("res://scripts/core/daily.gd")
const Replay = preload("res://scripts/game/replay.gd")
const Darkness = preload("res://scripts/game/darkness.gd")
const Secrets = preload("res://scripts/core/secrets.gd")
const RunGuard = preload("res://scripts/core/run_guard.gd")
const ContactMode = preload("res://scripts/contact/contact_mode.gd")
const FakeMenu = preload("res://scripts/contact/fake_menu.gd")

enum State { LOADING, MENU, LEVEL, PERK, BOSS_INTRO, BOSS, OUTRO, CUTSCENE, WIN, GAME_OVER, FAKE_MENU, CONTACT }

## Самый длинный шаг симуляции за кадр. Перетаскивание окна, сворачивание или фризы дают кадр
## в секунды — без ограничения змея за один шаг улетает в бортик или проскакивает сквозь снаряды.
const MAX_STEP := 1.0 / 20.0
## Аргументы отладки. В выпущенной сборке (не из редактора) их нет: из ярлыка с `--stage=4` или `--perks`
## получался забег с середины или мутация в меню (v11.0). --touch и --diff безвредны и остаются.
const DEBUG_ARGS := ["--stage=", "--autopilot", "--open=", "--shots=", "--settings-tab=", "--ending", "--skills",
	"--perks", "--dev", "--settings", "--contact", "--contact-finale", "--fake-menu", "--dump-sfx"]
## Сколько секунд ждать второго нажатия «пропустить финал».
const SKIP_CONFIRM_TIME := 2.0

## Переживают перезагрузку сцены: выбранная сложность и «сразу начать заново».
static var difficulty := 1
static var auto_start := false
## Забег — ежедневное испытание (переживает «ещё раз», сбрасывается выбором обычной сложности).
static var daily_mode := false

var state := State.LOADING
var cfg: Dictionary = Balance.DIFFICULTIES[1]
var stage := 0
var goal_done := 0
var goal_total := 0
var score := 0
var bears_eaten := 0
var forks_broken := 0
var pills_eaten := 0
var dolls_done := 0     # собранных наборов матрёшек
var opened_dolls := 0   # раскрытых матрёшек (большие и средние)
var play_time := 0.0
var run_scales := 0.0
var streak_bonus := 0  # чешуйки за серию испытаний дня в этом забеге
var scales_gained := 0
var perks: Dictionary = {}
var mods: Dictionary = {}
var bounds := Balance.ARENA.grow(-Balance.WALL)
var shake := 0.0
## Отладочный забег (аргументы, автопилот, читы): рекорды и чешуйки не сохраняются.
var debug_run := false
var autopilot := false
## Панель разработчика: враги замерли (не двигаются и не атакуют), змея и боссы живут как обычно.
var freeze_enemies := false
## Страж забега (v11.0): правка счёта в памяти, спидхак, чужой масштаб времени — см. run_guard.gd.
var guard := RunGuard.new()

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
var daily: Dictionary = {}   # модификатор испытания дня (пусто — обычный забег)
var replay := Replay.new()   # последние секунды — для повтора гибели
var stats := RunStats.new()  # серия, удары, приёмы, время по этапам — для итогов (v12.3)
var new_best_combo := false  # серия этого забега побила личный рекорд
var darkness: Darkness
var args := {"stage": -1, "ending": false, "skills": false, "perks": false, "dev": false, "contact": false,
	"contact-finale": false, "fake-menu": false}
var contact: ContactMode
var fake_menu: FakeMenu
var contact_report := {}  # итоги обычного забега перед «Контактом» (строки экрана итогов)
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
	hud.difficulty_chosen.connect(func(i: int) -> void:
		if state != State.MENU:  # двойное нажатие — забег уже начат
			return
		daily_mode = false
		start_game(i))
	hud.daily_chosen.connect(start_daily)
	hud.replay = replay
	hud.pause_summary_fn = pause_summary  # строка паузы собирается, когда пауза открыта, а не каждый кадр
	hud.retry_pressed.connect(restart.bind(true))
	hud.menu_pressed.connect(restart.bind(false))
	hud.records_reset.connect(_reset_records)
	hud.perk_chosen.connect(_on_perk)
	hud.attack_pressed.connect(_try_attack.bind("touch"))
	hud.contact_chosen.connect(func() -> void:
		if state == State.MENU:
			start_contact())
	hud.skip_pressed.connect(_skip_ending)
	hud.dev_toggled.connect(func() -> void: dev_panel.toggle())
	hud.secret_found.connect(found_secret)
	hud.back_unhandled.connect(func() -> void:  # «Назад» в финале — пропустить
		if state == State.CUTSCENE:
			_skip_ending())
	dev_panel = DevPanel.new()
	dev_panel.game = self
	add_child(dev_panel)

	if "--dump-sfx" in OS.get_cmdline_user_args() and debug_args_allowed():
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
	if args["contact"] or args["contact-finale"]:
		start_contact()
		if args["contact-finale"]:
			contact.debug_skip_to_finale()
	elif args["fake-menu"]:
		show_fake_menu()
	elif auto_start or args["stage"] >= 0 or args["ending"]:
		auto_start = false
		start_game(difficulty)
	else:
		show_menu()
		if args["skills"]:
			hud.open_skills()
		elif args["perks"]:
			hud.show_perks(Skills.roll_perks(Skills.perk_cards()), Balance.STAGES[1]["name"])
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
			hud.show_perks(Skills.roll_perks(Skills.perk_cards()), Balance.STAGES[1]["name"])
		"skills":
			hud.open_skills()
		"settings":
			hud.push(hud.settings_screen)
		"bestiary":
			for k in ["bear_0", "bear_3", "fork_0", "fork_2", "fork_atk_1", "pill", "doll_2", "doll_0"]:
				Bestiary.unlock(k, false)
			hud.push(hud.bestiary_screen)
			hud.bestiary_screen._select(3)
		"restart":  # проверка перезагрузки сцены: итоги → меню → итоги …
			_end(false)
			get_tree().create_timer(0.5).timeout.connect(restart.bind(false))


## Выход из игры: освободить static-кэши звуков, текстур и шрифтов (иначе утечки при выходе).
static func _on_quit() -> void:
	Sfx.release_all()
	Tex.clear_cache()
	Design.clear_cache()
	Fx.clear_cache()


## В выпущенной сборке аргументы отладки не работают.
static func debug_args_allowed() -> bool:
	return OS.is_debug_build()


static func is_debug_arg(a: String) -> bool:
	for p: String in DEBUG_ARGS:
		if a == p or (p.ends_with("=") and a.begins_with(p)):
			return true
	return false


func _parse_args(user_args := OS.get_cmdline_user_args(), allow_debug := debug_args_allowed()) -> void:
	for a: String in user_args:
		if not allow_debug and is_debug_arg(a):
			continue
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
		elif a.begins_with("--open="):  # экран для скриншота: pause, end, win, perks, skills, settings, bestiary
			args["open"] = a.get_slice("=", 1)
		elif a.begins_with("--shots="):
			for n in a.get_slice("=", 1).split(","):
				shot_frames.append(int(n))
		elif a.begins_with("--settings-tab="):
			args["settings"] = true
			args["tab"] = int(a.get_slice("=", 1))
		elif a in ["--ending", "--skills", "--perks", "--dev", "--settings", "--contact", "--contact-finale", "--fake-menu"]:
			args[a.trim_prefix("--")] = true
	# --open=end/win/restart завершают забег с выдуманным счётом — это тоже отладка, не рекорд
	debug_run = autopilot or args["stage"] >= 0 or args["ending"] or args.get("open", "") in ["end", "win", "restart"] \
		or args["contact"] or args["contact-finale"] or args["fake-menu"] or args["perks"]


# ---------------------------------------------------------------- меню и старт

func show_menu() -> void:
	sfx.play_music("menu")
	state = State.MENU
	daily_mode = false
	menu_demo = MenuDemo.new(self)
	hud.show_menu(Balance.DIFFICULTIES, SaveData.bests(Balance.DIFFICULTIES.size()), difficulty)


## Ежедневное испытание: Нормальная сложность, модификатор и сид дня.
func start_daily() -> void:
	if state != State.MENU:
		return
	daily_mode = true
	start_game(Daily.BASE_DIFFICULTY)


func start_game(diff: int) -> void:
	difficulty = diff
	cfg = Balance.difficulty(diff)
	daily = {}
	if daily_mode:
		daily = Daily.today()
		cfg = Daily.apply(cfg, daily)
		seed(Daily.seed_for(Daily.day_key()))
	replay.clear()
	stats.reset()
	new_best_combo = false
	guard = RunGuard.new()
	if not is_equal_approx(Engine.time_scale, 1.0):  # время замедлили до забега — забег не в счёт
		guard.flag("скорость времени изменена (%.2f×)" % Engine.time_scale)
	if menu_demo:
		menu_demo.clear()
		menu_demo = null
	mods = Skills.mods(perks, cfg["no_skills"])
	snake = Snake.new()
	snake.bounds = bounds
	snake.z_index = 2
	snake.max_lives = cfg["lives"] + mods["lives"]
	snake.lives = snake.max_lives
	_apply_snake_mods()
	snake.shield += int(mods["start_shield"])  # навык «Запасной хвост»
	if daily.get("dark", false):
		darkness = Darkness.new()
		world.add_child(darkness)
	snake.reset(Vector2(640, 520))
	snake.hat = Secrets.is_holiday()
	if snake.hat:
		found_secret("holiday")
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
		dolls_done = cfg["dolls"]
		arena.set_floor(Balance.STAGES[Balance.BOSS_STAGE]["floor"])
		start_ending()
		return
	enter_stage(maxi(args["stage"], 0))


var _restarting := false


func restart(retry: bool) -> void:
	if get_tree().current_scene == null:  # игра встроена в тест — перезагружать нечего
		return
	if _restarting:  # двойное нажатие «Ещё раз» / «В меню» — сцена уже перезагружается
		return
	_restarting = true
	auto_start = retry
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene.call_deferred()


func enter_stage(i: int) -> void:
	stage = i
	stats.stage_begin(play_time)
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
	if text == "" or not hints_on() or state == State.MENU:
		return
	hud.show_hint(text)
	if hint_tween:
		hint_tween.kill()
	hint_tween = create_tween()
	hint_tween.tween_interval(time)
	hint_tween.tween_callback(hud.hide_caption)


## Враг впервые на поле — открыть его карточку в картотеке (отладочные забеги не в счёт).
func seen(key: String) -> void:
	if debug_run or state == State.MENU:
		return
	if Bestiary.unlock(key):
		var e := Bestiary.entry(key)
		fx.popup(Vector2(640, 96), "В КАРТОТЕКЕ: " + String(e["title"]).to_upper(), Design.STEEL)


## Строка на табличке паузы: сложность, этап, счёт.
func pause_summary() -> String:
	return "%s  •  этап %d: %s  •  счёт %d" % [cfg["name"], stage + 1, Balance.STAGES[stage]["short"], score]


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
	stats.stage_end(play_time, stage)
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
	# прыжок или рывок, начатые в последний миг этапа, не переносятся на следующий: иначе змея
	# «приземляется» уже на новом поле и давит только что появившихся врагов
	snake.hop_t = 0.0
	snake.small = 1.0
	snake.dash_t = 0.0
	snake.shadow_dash = false
	abilities.hop_land_t = -1.0
	if mods.get("stage_heal", false) and snake.heal():  # навык «Регенерация»
		fx.popup(snake.head_pos + Vector2(0, -70), "РЕГЕНЕРАЦИЯ: +1 ЖИЗНЬ", Color(1, 0.5, 0.5))
	var tw := create_tween()
	tw.tween_interval(1.6)
	if cfg["no_skills"]:
		tw.tween_callback(func() -> void: enter_stage(stage + 1))
	elif autopilot:  # отладка: улучшение выбирается само
		tw.tween_callback(func() -> void: _on_perk(Skills.roll_perks(1, perks, mods["nose"])[0]["id"]))
	else:
		tw.tween_callback(func() -> void:
			get_tree().paused = true
			hud.show_perks(Skills.roll_perks(Skills.perk_cards(), perks, mods["nose"]), Balance.STAGES[stage + 1]["name"]))


func _on_perk(id: String) -> void:
	if snake == null or state == State.MENU:  # карточки, открытые из меню (отладка), ничего не дают
		get_tree().paused = false
		return
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
	_apply_snake_mods()
	update_berserk()
	fx.popup(snake.head_pos + Vector2(0, -40), Skills.perk(id)["name"], Color(0.6, 1, 0.6))
	enter_stage(stage + 1)


## Навыки и мутации на змею, а поверх них — модификатор дня (иначе «Гололёд» и «Одышка» пропадут
## после первой же мутации: apply_mods перезаписывает поворот и стамину).
func _apply_snake_mods() -> void:
	snake.apply_mods(mods)
	for k: String in daily.get("snake", {}):
		snake.set(k, float(snake.get(k)) * float(daily["snake"][k]))


func _clear_field() -> void:
	enemies.clear()
	shots.clear()


func _begin_boss() -> void:
	state = State.BOSS_INTRO
	_clear_field()
	seen("boss")
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
	snake.safe = true  # победа: до финала змею уже ничто не ранит (раньше можно было разбиться о бортик)


func start_ending() -> void:
	state = State.CUTSCENE
	hud.set_boss(false)
	arena.set_pan_rim(false)  # в лаборатории это снова деревянный ящик на столе
	arena.set_heat(0.0)
	ending = Ending.new()
	add_child(ending)
	ending.finished.connect(_on_ending_finished)
	ending.start(self)


func _on_ending_finished() -> void:
	hud.set_cinematic(false)
	if ending.to_contact:
		_to_contact()
	else:
		_end(true)


var _skip_armed_ms := -1


func _skip_ending() -> void:
	if state == State.CONTACT and contact and contact.in_cutscene():
		contact.skip()
		return
	if state != State.CUTSCENE or ending == null:
		return
	var now := Time.get_ticks_msec()
	var armed := _skip_armed_ms >= 0 and now - _skip_armed_ms <= int(SKIP_CONFIRM_TIME * 1000.0)
	if Settings.flag("confirm_skip") and not armed:  # подтверждение живёт 2 с, а не до конца финала
		_skip_armed_ms = now
		hud.show_banner("Ещё раз — пропустить финал", Design.MUTED, 1.2)
		return
	ending.skip()


## Атака. В «Контакте» — встать на дыбы и заговорить; via — чем нажали (mouse, touch, keys).
func _try_attack(via := "keys") -> void:
	if get_tree().paused:
		return
	if state in [State.LEVEL, State.BOSS]:
		abilities.use()
	elif state == State.CONTACT and contact:
		contact.talk(via)


func _unhandled_input(event: InputEvent) -> void:
	# Панель разработчика слушает клавиши сама (dev_panel.gd::_input): этот узел на паузе не получает ввод.
	if state == State.MENU and menu_demo:  # пасхалка: тычки в яичницу, выглядывающую из угла
		var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		var tap: bool = click or (event is InputEventScreenTouch and event.pressed)
		if tap and menu_demo.poke(get_canvas_transform().affine_inverse() * (event.position as Vector2)):
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
	elif state == State.CONTACT and contact and contact.in_cutscene():
		if event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			_skip_ending()
	elif event.is_action_pressed("ability"):
		# эмулированный из касания клик — не атака: для атаки есть кнопка
		if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_try_attack("mouse" if event is InputEventMouseButton else "keys")


func _end(win: bool) -> void:
	if state in [State.WIN, State.GAME_OVER]:  # итоги уже подведены: второй раз рекорд не пишем
		return
	var res := _commit_run(win)
	hud.show_end(win, "КОНЕЦ" if win else "", res["line"], res["rows"])


## Подвести итоги забега: рекорд, чешуйки, серия испытаний. Возвращает строки экрана итогов.
func _commit_run(win: bool) -> Dictionary:
	state = State.WIN if win else State.GAME_OVER
	if boss:
		boss.active = false
	shots.clear()
	if not win:
		sfx.play_music("")
		sfx.play("lose")
		vibrate(300)
	_check_guard()
	if win and stage == Balance.BOSS_STAGE:
		stats.stage_end(play_time, stage)
	stats.note_length(snake.length if snake else 0)
	new_best_combo = not debug_run and RunStats.submit_best_combo(stats.best_combo)
	var best := SaveData.best(difficulty)
	var record := false
	if daily_mode:  # у испытания дня свой рекорд
		best = Daily.best(Daily.day_key())
		record = not debug_run and Daily.submit(Daily.day_key(), score)
	else:
		record = not debug_run and SaveData.submit_score(difficulty, score)
	if record:
		best = score
	if win:
		# навык «Премия» — ровно +25: сложность и «Жадность»/«Чешуйчатая» её не раздувают
		run_scales += float(mods.get("bounty", 0)) / (Skills.SCALE_MULT[clampi(difficulty, 0, 3)] * float(mods.get("scales_mult", 1.0)))
	scales_gained = Skills.scales_for_run(run_scales, difficulty, float(mods.get("scales_mult", 1.0)))
	print("run end: win=%s stage=%d score=%d scales=+%d" % [win, stage, score, scales_gained])
	streak_bonus = 0
	if daily_mode and not debug_run and score > 0:  # серия испытаний: бонус за первый забег дня
		streak_bonus = Daily.register_play(Daily.day_key())
		scales_gained += streak_bonus
	if scales_gained > 0 and not debug_run:
		Skills.add_scales(scales_gained)
	return {"rows": RunReport.rows(self, win, record, best), "line": RunReport.headline(win)}


# ---------------------------------------------------------------- «Контакт» (v10.0)

## Финал закончился пересадкой: итоги забега записаны, сцена очищена — фальшивое меню.
func _to_contact() -> void:
	contact_report = _commit_run(true)
	ending.cleanup()
	ending = null
	show_fake_menu()


## Убрать с поля всё от прошлого забега: змею, врагов, снаряды, яичницу, камеру — на место.
func _clear_world() -> void:
	enemies.clear(false)
	shots.clear()
	if snake:
		snake.queue_free()
		snake = null
	if boss:
		boss.queue_free()
		boss = null
	if darkness:
		darkness.queue_free()
		darkness = null
	camera.position = Balance.ARENA.get_center()
	camera.zoom = Vector2.ONE
	shake = 0.0


func show_fake_menu() -> void:
	_clear_world()
	state = State.FAKE_MENU
	arena.set_floor(Balance.STAGES[0]["floor"])
	sfx.play_music("menu")
	fake_menu = FakeMenu.new()
	add_child(fake_menu)
	fake_menu.done.connect(start_contact)
	fake_menu.start(self)


## Технический режим «Контакт»: новая змейка (образец №48), никаких навыков и жизней — смерти нет.
func start_contact() -> void:
	if fake_menu:
		fake_menu.queue_free()
		fake_menu = null
	if menu_demo:
		menu_demo.clear()
		menu_demo = null
	_clear_world()
	state = State.CONTACT
	arena.set_pan_rim(false)  # «Контакт» идёт в деревянном ящике: в финале трескается доска, а не чугун
	cfg = Balance.difficulty(difficulty)
	daily = {}
	daily_mode = false
	perks = {}
	mods = Skills.mods(perks, true)
	stage = 0
	play_time = 0.0
	snake = Snake.new()
	snake.bounds = bounds
	snake.z_index = 2
	snake.small = 0.85
	snake.length = 10
	snake.max_lives = 1
	snake.lives = 1
	snake.safe = true
	snake.reset(Vector2(640, 560))
	world.add_child(snake)
	hud.show_game("КОНТАКТ", Design.PLUM, 0)
	hud.set_score(0)
	hud.set_ability(-1, "", 0)
	hud.set_dev_run(debug_run)
	contact = ContactMode.new(self)
	contact.start()


## «Контакт» пройден: экран итогов — строки прошлого забега (если был) и строки режима.
func contact_done(c: ContactMode) -> void:
	state = State.WIN
	hud.set_cinematic(false)
	var secs := int(play_time)
	var rows: Array = [
		["Технический режим", "КОНТАКТ"],
		["Убеждено", "%d  (медведей %d, вилок %d, таблеток %d, матрёшек %d, яичница)" % [c.convinced_total(),
			c.counts["bear"], c.counts["fork"], c.counts["pill"], c.counts["doll"]]],
		["Выжили", "змея и медведь-швея"],
		["Время в «Контакте»", "%d:%02d" % [secs / 60, secs % 60]],
	]
	if not contact_report.is_empty():
		rows = contact_report["rows"] + rows
	hud.show_end(true, "КОНТАКТ", "Образец №48 договорился со всеми… кроме своего создателя.", rows)


# ---------------------------------------------------------------- цикл

func _process(delta: float) -> void:
	delta = minf(delta, MAX_STEP * Engine.time_scale)
	shake = maxf(shake - delta * 40.0, 0.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * Settings.num("shake")
	var fighting := state in [State.LEVEL, State.BOSS]
	if snake:
		var head_screen := get_viewport().get_canvas_transform() * snake.head_pos
		hud.track_snake(snake.stamina, snake.exhausted, snake.shield, head_screen, play_time)
		hud.pause_allowed = state in [State.LEVEL, State.BOSS_INTRO, State.BOSS] \
			or (state == State.CONTACT and contact != null and not contact.in_cutscene())
		stats.note_length(snake.length)
		snake.touch_steer = hud.touch.steer if hud.touch.active else Vector2.ZERO
		snake.touch_sprint = hud.touch.active and hud.touch.sprint_held
	if state in [State.LEVEL, State.BOSS_INTRO, State.BOSS, State.CONTACT]:
		play_time += delta
		if snake and snake.alive:
			replay.record(self, delta)
	if darkness and snake:
		darkness.follow(snake.head_pos)
	if snake and fighting:
		var yolk := boss != null and boss.is_yolk_open()
		sfx.set_intensity(music_intensity(state == State.BOSS, boss.phase() if boss else 1, snake.lives,
			snake.max_lives, enemies.squad.is_trapping(), yolk, float(goal_done) / maxf(goal_total, 1.0)))
	if autopilot and snake and fighting:
		Autopilot.drive(self)
	if fighting and not debug_run:
		guard.tick(Engine.time_scale)
		if guard.flagged():
			_check_guard()

	match state:
		State.MENU:
			if menu_demo:
				menu_demo.update(delta)
		State.CONTACT:
			if contact:
				contact.update(delta)
		State.WIN, State.GAME_OVER, State.OUTRO, State.BOSS_INTRO, State.CUTSCENE:
			if snake:
				snake.update(delta)
			if boss:
				boss.update(delta, snake)
		State.LEVEL, State.BOSS:
			snake.update(delta)
			abilities.update(delta)
			if state == State.BOSS:
				boss.update(delta, snake)
				enemies.update_reinforcements(delta)
			else:
				enemies.update_helpers(delta)
			if not freeze_enemies:
				enemies.update_bears(delta, snake, true)
				enemies.update_forks(delta, snake)
				enemies.update_pills(delta, snake)
				enemies.update_dolls(delta, snake)
				enemies.update_squad(delta, snake)
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


## Музыка 2.0: насколько подмешать слой напряжения. На этапе — растёт к концу этапа, при последней
## жизни и когда вилки заходят в клещи; в бою с яичницей — по фазе, а открытый желток — на полную.
static func music_intensity(boss_fight: bool, phase: int, lives: int, max_lives: int, pincer: bool,
		yolk_open: bool, progress: float) -> float:
	var k := 0.0
	if boss_fight:
		k = [0.35, 0.65, 0.9][clampi(phase, 1, 3) - 1]
		if yolk_open:
			k = 1.0
	else:
		k = 0.3 * clampf(progress, 0.0, 1.0)
		if pincer:
			k += 0.35
	if lives <= 1 and max_lives > 1:
		k += 0.45
	return clampf(k, 0.0, 1.0)


# ---------------------------------------------------------------- очки, эффекты, сигналы

## Очки с множителем сложности.
func add_score(base_points: int, pos: Vector2, prefix := "") -> void:
	add_score_raw(roundi(Combat.points(base_points, cfg) * float(mods.get("score_mult", 1.0))), pos, prefix)


func add_score_raw(points: int, pos: Vector2, prefix := "") -> void:
	guard.verify(score)  # счёт до прибавки должен совпадать с тенью
	stats.on_score(play_time)
	score += points
	guard.note_score(score)
	hud.set_score(score)
	fx.popup(pos, "%s+%d" % [prefix, points], Color(1, 0.95, 0.4) if prefix == "" else Color(1, 0.5, 0.9), true)


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


func vibrate(ms: int) -> void:
	Platform.vibrate(ms, Settings.flag("vibration"))


## Мутация «Берсерк» включается на последней жизни и гаснет, когда жизнь вернули.
func update_berserk() -> void:
	var on: bool = mods.get("berserk", false) and snake != null and snake.lives == 1
	if on and not mods.get("berserk_on", false) and snake.alive:
		fx.popup(snake.head_pos + Vector2(0, -60), "БЕРСЕРК!", Color(1, 0.35, 0.2))
	mods["berserk_on"] = on


func _on_snake_damaged(lives_left: int) -> void:
	var healed := lives_left >= hud.lives()
	hud.set_lives(lives_left)
	update_berserk()
	if healed:
		return
	stats.on_hit()
	shake = 14.0
	sfx.play("hurt")
	vibrate(90)


func _on_snake_died() -> void:
	replay.push(Replay.snapshot(self))
	replay.finish(snake.last_cause)
	fx.burst(snake.head_pos, Color(0.4, 0.85, 0.35), 30)
	_end(false)


func _reset_records() -> void:
	SaveData.reset_records()
	menu_demo_refresh()


func menu_demo_refresh() -> void:
	if state == State.MENU:
		hud.menu.set_data(Balance.DIFFICULTIES, SaveData.bests(Balance.DIFFICULTIES.size()), difficulty,
			Skills.scales, touch_on())


## Найдена пасхалка: табличка сверху и звонок. Второй раз ничего не происходит.
func found_secret(id: String) -> void:
	if not Secrets.unlock(id):
		return
	var e := Secrets.entry(id)
	hud.show_banner("ПАСХАЛКА: %s  (%d/%d)" % [e["title"], Secrets.found_count(), Secrets.total()], Design.PLUM, 2.0)
	sfx.play("secret")
	if state == State.MENU:  # журнал в меню считает пасхалки
		hud.menu.update_scales(Skills.scales)


## Страж забега что-то заметил — забег не в счёт (рекорд и чешуйки не пишутся), причина — в итогах.
func _check_guard() -> void:
	if debug_run:
		return
	guard.verify(score)
	if guard.flagged():
		mark_debug_run()
		push_warning("забег не засчитан: " + guard.reason)


## Пометить забег отладочным (любое читерство из панели разработчика).
func mark_debug_run() -> void:
	debug_run = true
	hud.set_dev_run(true)
