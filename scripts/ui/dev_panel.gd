extends CanvasLayer
## Панель разработчика 2.0 (v9.0) (F1, ` или Ctrl+Shift+D; на телефоне — кнопка </> после 7 нажатий на
## версию в настройках). В шапке — табличка версии и лампа «отладочный забег», под ней — маршрут забега.
## Вкладки: ИНФО (производительность и состояние), ЧИТЫ, МИР (этапы, спавн врагов и матрёшек, время,
## пасхалки), ИИ (кооператив: уровень отряда, приёмы по кнопке, роли над врагами, счётчики),
## ДЕБАГ (хитбоксы, безопасная зона, пауза времени с шагом кадра, журнал ошибок, звуки), UI (витрина
## дизайн-языка), ТЕСТЫ (юнит-тесты в игре). С v12.2: заморозка врагов, длина и здоровье змеи, пачки спавна,
## фазы яичницы, проверка эффектов, события вакханалии в меню, снимок экрана и отчёт в буфер обмена.
## Любой чит помечает забег отладочным — рекорды и чешуйки не сохраняются.

const Design = preload("res://scripts/ui/design.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Skills = preload("res://scripts/core/skills.gd")
const Platform = preload("res://scripts/core/platform.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Segmented = preload("res://scripts/ui/widgets/segmented.gd")
const ToggleSwitch = preload("res://scripts/ui/widgets/toggle_switch.gd")
const DevOverlay = preload("res://scripts/ui/dev_overlay.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Fader = preload("res://scripts/ui/widgets/fader.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const Snake = preload("res://scripts/entities/snake.gd")
const Secrets = preload("res://scripts/core/secrets.gd")
const MenuDemo = preload("res://scripts/game/menu_demo.gd")
const DevLog = preload("res://scripts/ui/dev_log.gd")

const WIDTH := 500.0
const TABS := ["ИНФО", "ЧИТЫ", "МИР", "ИИ", "ДЕБАГ", "UI", "ТЕСТЫ"]
const PAGE_AI := 3
const PAGE_DEBUG := 4
## Уровни отряда для переключателя на вкладке ИИ (−1 — как у сложности).
const COOP_LEVELS := [-1, 0, 1, 2]
const BEAR_NAMES := ["Обычный", "Боксёр", "Метатель", "Каратист", "Швея", "Ниндзя", "Хлопушка", "Медсестра"]
const TEST_RUNNER := "res://tests/test_runner.gd"
## Сколько врагов создаёт кнопка спавна.
const SPAWN_COUNTS := [1, 3, 5, 10]
## Звуки финала — отдельной группой в превью.
const ENDING_SOUNDS := ["match", "ignite", "burn", "crackle", "thunder", "step", "scribble", "stamp", "extinguisher",
	"lamp_click", "hatch", "melt"]

var game  # game.gd
var panel: PanelContainer
var pages: Array[Control] = []
var info_label: Label
var graph: Control
var frame_ms: Array[float] = []
var test_output: Label
var sound_grid: VBoxContainer
var overlay: DevOverlay
var open := false
var info_t := 0.0
var ai_label: Label
var roles_label: Label
var secrets_box: VBoxContainer
var run_lamp: Control
var route: Control
var tabs: Segmented
var t := 0.0
var spawn_count := 1
var log_label: Label
var log_t := 0.0
var time_paused := false
var saved_scale := 1.0


func _ready() -> void:
	layer = 20
	DevLog.install()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Design.make_theme()
	add_child(root)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Design.elevated(Color(Design.SURFACE_1, 0.97), Design.PLUM.darkened(0.2),
		Design.RADIUS_LG, 3, Vector2(Design.SPACE[4], Design.SPACE[4])))
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -WIDTH - 12
	panel.offset_right = -12
	panel.offset_top = 12
	panel.offset_bottom = -12
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # если содержимое шире — растём влево
	root.add_child(panel)
	var col := Design.vbox(Design.SPACE[3])
	panel.add_child(col)
	var head := Design.hbox(Design.SPACE[2], BoxContainer.ALIGNMENT_BEGIN)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(28, 28)
	ic.draw.connect(func() -> void: Icons.code(ic, Vector2(14, 14), Design.PLUM, 1.0))
	head.add_child(ic)
	var title := Design.label("ПАНЕЛЬ РАЗРАБОТЧИКА", "h3", Design.PLUM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	run_lamp = Control.new()  # лампа «отладочный забег»: горит сливовым, когда рекорды не пишутся
	run_lamp.custom_minimum_size = Vector2(22, 22)
	run_lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	run_lamp.tooltip_text = "Отладочный забег: рекорды и чешуйки не сохраняются"
	run_lamp.draw.connect(func() -> void:
		var on: bool = game.debug_run
		Design.draw_lamps(run_lamp, Vector2(11, 11), 1, 1 if on else 0, Design.PLUM, 6.0))
	head.add_child(run_lamp)
	var ver := Design.chip("v" + str(ProjectSettings.get_setting("application/config/version", "")), Design.PLUM)
	ver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ver)
	var close := Design.button("×", toggle, "Ghost", Vector2(40, 40))
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(close)
	col.add_child(head)
	route = Control.new()  # маршрут забега: где мы сейчас
	route.custom_minimum_size = Vector2(0, 40)
	route.draw.connect(func() -> void:
		var step := 72.0
		var x0 := (route.size.x - step * (Balance.STAGE_COUNT - 1)) / 2.0
		var cur: int = game.stage if game.state not in [game.State.MENU, game.State.LOADING] else -1
		Design.draw_route(route, Vector2(x0, 20), cur, step, t, 0.85))
	col.add_child(route)
	tabs = Segmented.new()
	tabs.setup(TABS, 0, 0.0, true)
	tabs.changed.connect(_show_page)
	col.add_child(tabs)
	for b in tabs.buttons:  # компактные сегменты: тема уже применена, раз узел в дереве
		b.add_theme_font_size_override("font_size", 11)
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var sb := b.get_theme_stylebox(st).duplicate() as StyleBox
			sb.content_margin_left = 13  # слева — место под лампу нажатой клавиши
			sb.content_margin_right = 4
			b.add_theme_stylebox_override(st, sb)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var gutter := MarginContainer.new()  # справа — место под полосу прокрутки, клавиши её не касаются
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", Design.SPACE[4])
	scroll.add_child(gutter)
	var stack := Design.vbox(0)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(stack)
	for builder in [_build_info, _build_cheats, _build_world, _build_ai, _build_debug, _build_kit, _build_tests]:
		var page := Design.vbox(Design.SPACE[2])
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(page)
		builder.call(page)
		pages.append(page)
	_show_page(0)
	overlay = DevOverlay.new()
	overlay.game = game
	overlay.z_index = 50
	game.world.add_child.call_deferred(overlay)
	panel.visible = false


## Горячие клавиши ловим здесь, а не в game.gd: панель работает всегда (PROCESS_MODE_ALWAYS), в том числе
## на паузе и на выборе улучшений, когда главный узел ввод не получает. _input, а не _unhandled_input —
## чтобы клавишу не перехватил элемент интерфейса в фокусе.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_action_pressed("dev_panel"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	open = not open
	panel.visible = open
	Design.play("ui_select" if open else "ui_back")
	if open and not Settings.flag("reduced_motion"):
		panel.modulate.a = 0.0
		create_tween().tween_property(panel, "modulate:a", 1.0, Design.BASE)


func _show_page(i: int) -> void:
	if tabs:
		tabs.select(i)  # вкладку могли открыть из кода (тесты, снимки) — клавиша тоже утоплена
	for k in pages.size():
		pages[k].visible = k == i
	if i == PAGE_DEBUG:
		_fill_sounds()
	if i == 2:
		_fill_secrets()


# ---------------------------------------------------------------- строительные блоки

func _row(parent: Control, text: String, control: Control) -> void:
	var h := Design.hbox(Design.SPACE[3], BoxContainer.ALIGNMENT_BEGIN)
	var l := Design.label(text, "small", Design.CREAM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(control)
	parent.add_child(h)


func _toggle(parent: Control, text: String, on: bool, cb: Callable) -> void:
	var sw := ToggleSwitch.new()
	sw.set_on(on)
	sw.toggled.connect(cb)
	_row(parent, text, sw)


## Компактная клавиша панели: ниже и мельче обычной, с малым ходом; длинный текст — с многоточием.
func _btn(text: String, cb: Callable, variant := "") -> Button:
	var b := Design.button(text.to_upper(), cb, variant, Vector2(0, 40))
	b.add_theme_font_size_override("font_size", 13)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.clip_text = true
	b.tooltip_text = text
	if variant == "":  # бакелитовая клавиша поменьше: ход 3 px, поля уже
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, Design.cached("dev_key_" + st, func() -> StyleBox:
				return Design.key(Design.Materials.Kind.BAKELITE, Color(0, 0, 0, 0), st, Design.RADIUS_SM, 3.0,
					Vector2(Design.SPACE[2], Design.SPACE[2]))))
		b.add_theme_stylebox_override("focus", Design.cached("dev_key_focus", func() -> StyleBox:
			return Design.focus_ring(Design.RADIUS_SM, 3.0)))
	return b


func _section(parent: Control, text: String) -> void:
	var l := Design.label(text, "overline", Design.YOLK)
	parent.add_child(Design.spacer(Design.SPACE[1]))
	parent.add_child(l)


func _grid(parent: Control, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", Design.SPACE[2])
	g.add_theme_constant_override("v_separation", Design.SPACE[2])
	parent.add_child(g)
	return g


func _cheat() -> void:
	game.mark_debug_run()


## Чит на чешуйки меняет сохранение навсегда, поэтому он есть только в отладочной сборке (редактор, тесты).
static func scales_cheat_allowed() -> bool:
	return OS.is_debug_build()


func _in_run() -> bool:
	return game.snake != null and game.state in [game.State.LEVEL, game.State.BOSS, game.State.BOSS_INTRO, game.State.PERK]


# ---------------------------------------------------------------- ИНФО

func _build_info(p: VBoxContainer) -> void:
	p.add_child(Design.label("ПРОИЗВОДИТЕЛЬНОСТЬ", "overline", Design.YOLK))
	graph = Control.new()
	graph.custom_minimum_size = Vector2(0, 70)
	graph.draw.connect(_draw_graph)
	p.add_child(graph)
	info_label = Design.label("", "small", Design.CREAM)
	info_label.label_settings.font = Design.font("mono")
	info_label.label_settings.font_size = 13
	p.add_child(info_label)
	var ig := _grid(p, 3)
	ig.add_child(_btn("КОПИРОВАТЬ ОТЧЁТ", copy_report))
	ig.add_child(_btn("СНИМОК ЭКРАНА", screenshot))
	ig.add_child(_btn("ПАПКА ДАННЫХ", func() -> void: OS.shell_open(ProjectSettings.globalize_path("user://"))))


func _draw_graph() -> void:
	var r := Rect2(Vector2.ZERO, graph.size)
	graph.draw_style_box(Design.box(Design.SURFACE_0, Design.LINE, Design.RADIUS_SM, 1, Vector2.ZERO), r)
	var y16 := r.size.y * (1.0 - 16.7 / 40.0)
	graph.draw_line(Vector2(0, y16), Vector2(r.size.x, y16), Color(Design.MINT, 0.4), 1.0)
	if frame_ms.size() < 2:
		return
	var pts := PackedVector2Array()
	for i in frame_ms.size():
		var x := r.size.x * i / 119.0
		pts.append(Vector2(x, r.size.y * (1.0 - clampf(frame_ms[i] / 40.0, 0.0, 1.0))))
	graph.draw_polyline(pts, Design.YOLK, 1.5)


func _update_info() -> void:
	var vp := get_viewport().get_visible_rect().size
	var lines: Array = [
		"FPS            %d   (кадр %.1f мс)" % [Engine.get_frames_per_second(), frame_ms.back() if frame_ms.size() > 0 else 0.0],
		"Узлы / объекты %d / %d" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT)],
		"Память         %.1f МБ" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		"Отрисовок      %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"Состояние      %s" % game.State.keys()[game.state],
		"Этап / цель    %d  •  %d/%d" % [game.stage + 1, game.goal_done, game.goal_total],
		"Сложность      %s" % game.cfg["name"],
		"Враги / снаряды %d / %d" % [game.enemies.count(), game.shots.drops.size()],
		"Матрёшки       %d на поле  •  наборов %d  •  раскрыто %d" % [game.enemies.dolls.size(),
			game.enemies.doll_sets.size(), game.opened_dolls],
		"Отряд          уровень %d%s  •  ролей %d" % [game.enemies.squad.level,
			" (вручную)" if game.enemies.coop_override >= 0 else "", game.enemies.squad.roles.size()],
		"Пасхалки       %d / %d" % [Secrets.found_count(), Secrets.total()],
		"Голоса звука   %d / %d  •  отброшено %d" % [game.sfx.busy_voices(), game.sfx.VOICES, game.sfx.dropped],
		"Скорость       ×%.2f" % Engine.time_scale,
		"Платформа      %s" % Platform.describe(),
		"Экран          %dx%d  •  UI ×%.2f" % [vp.x, vp.y, Settings.ui_scale()],
		"Безопасная зона %s" % str(Platform.safe_margins(get_viewport())),
		"Тач            %s" % ("да" if Settings.touch_enabled() else "нет"),
		"Отладочный забег %s" % ("да" if game.debug_run else "нет"),
	]
	lines.append_array(_extra_info())
	info_label.text = "\n".join(lines)


## Строки состояния змеи, яичницы, кадра и демо меню — дополняют список на вкладке ИНФО.
func _extra_info() -> Array:
	var out: Array = []
	var s = game.snake
	if s != null and is_instance_valid(s):
		out.append("Змея           длина %d  •  жизни %d/%d  •  стамина %d%%" % [s.length, s.lives, s.max_lives, int(s.stamina * 100.0)])
	if game.boss != null and is_instance_valid(game.boss):
		out.append("Яичница        HP %d/%d  •  фаза %d" % [game.boss.hp, game.boss.max_hp, game.boss.phase()])
	out.append("Время забега   %.1f с  •  счёт %d" % [game.play_time, game.score])
	if frame_ms.size() > 10:
		var sorted := frame_ms.duplicate()
		sorted.sort()
		var avg := 0.0
		for v in frame_ms:
			avg += v
		avg /= frame_ms.size()
		out.append("Кадр           средний %.1f  •  максимум %.1f  •  1%% худших %.1f мс" % [avg, sorted.back(), sorted[int(sorted.size() * 0.99)]])
	if game.menu_demo != null:
		out.append("Демо меню      событий %d  •  съедено %d  •  комбо %d (рекорд %d)" % [game.menu_demo.events_run, game.menu_demo.eaten,
			game.menu_demo.combo, game.menu_demo.best_combo])
	var lg = DevLog.shared
	if lg != null:
		out.append("Журнал         ошибок %d  •  предупреждений %d" % [lg.errors, lg.warnings])
	out.append("Заморозка врагов %s  •  пауза времени %s" % ["да" if game.freeze_enemies else "нет", "да" if time_paused else "нет"])
	return out


## Текст вкладки ИНФО — в буфер обмена (для отчёта об ошибке).
func copy_report() -> String:
	_update_info()
	var text := "Змея против Гигантской Яичницы v%s\n%s" % [ProjectSettings.get_setting("application/config/version", ""), info_label.text]
	DisplayServer.clipboard_set(text)
	game.hint("Отчёт скопирован в буфер обмена", 2.0)
	return text


## Снимок экрана без самой панели — в user://shots/. Возвращает путь.
func screenshot() -> String:
	var dir := ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("dev_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
	var was := panel.visible
	panel.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	panel.visible = was
	game.hint("Снимок: " + path, 3.0)
	return path


# ---------------------------------------------------------------- ЧИТЫ

func _build_cheats(p: VBoxContainer) -> void:
	_section(p, "ЗМЕЯ")
	_toggle(p, "Бессмертие", false, func(on: bool) -> void:
		_cheat()
		if game.snake:
			game.snake.god = on)
	_toggle(p, "Бесконечная стамина", false, func(on: bool) -> void:
		_cheat()
		if game.snake:
			game.snake.endless_stamina = on)
	_toggle(p, "Бесконечные заряды атак", false, func(on: bool) -> void:
		_cheat()
		game.abilities.infinite = on)
	_toggle(p, "Золотая змея (как по коду Konami)", Snake.golden, func(on: bool) -> void:
		Snake.golden = on)
	_toggle(p, "Новогодняя шапка", false, func(on: bool) -> void:
		if game.snake:
			game.snake.hat = on)
	var g := _grid(p, 2)
	g.add_child(_btn("+1 ЖИЗНЬ", func() -> void:
		if game.snake:
			_cheat()
			if not game.snake.heal():
				game.snake.max_lives += 1
				game.snake.lives += 1
				game.hud.set_max_lives(game.snake.max_lives)
				game.hud.set_lives(game.snake.lives)))
	var scales_btn := _btn("+100 ЧЕШУЕК", func() -> void:
		if not scales_cheat_allowed():
			return
		_cheat()
		Skills.add_scales(100)
		game.hud.show_banner("+100 чешуек", Design.MINT, 0.8))
	if not scales_cheat_allowed():  # чешуйки — постоянный прогресс: в выпущенной сборке их не накрутить
		scales_btn.disabled = true
		scales_btn.tooltip_text = "Только в сборке из редактора"
	g.add_child(scales_btn)
	_toggle(p, "Заморозить врагов", game.freeze_enemies, func(on: bool) -> void:
		_cheat()
		game.freeze_enemies = on)
	var sg := _grid(p, 2)
	sg.add_child(_btn("ПОЛНОЕ ЗДОРОВЬЕ", func() -> void:
		if game.snake:
			_cheat()
			game.snake.lives = game.snake.max_lives
			game.hud.set_lives(game.snake.lives)))
	sg.add_child(_btn("СТАМИНА 100%", func() -> void:
		if game.snake:
			_cheat()
			game.snake.stamina = game.snake.stamina_max
			game.snake.exhausted = false))
	sg.add_child(_btn("+10 ДЛИНЫ", func() -> void:
		if game.snake:
			_cheat()
			game.snake.grow(10)))
	sg.add_child(_btn("−5 ДЛИНЫ", func() -> void:
		if game.snake:
			_cheat()
			game.snake.length = maxi(game.snake.length - 5, 4)))
	sg.add_child(_btn("СБРОС ПЕРЕЗАРЯДКИ", func() -> void:
		if _in_run():
			_cheat()
			game.abilities.cooldown = 0.0))
	sg.add_child(_btn("+1000 ОЧКОВ", func() -> void:
		if _in_run():
			_cheat()
			game.add_score_raw(1000, game.snake.head_pos, "", false)))
	sg.add_child(_btn("ВЫБОР УЛУЧШЕНИЙ", func() -> void:
		if _in_run():
			_cheat()
			game.hud.show_perks(Skills.roll_perks(Skills.perk_cards()), "ПРОВЕРКА")))
	sg.add_child(_btn("УБИТЬ ЗМЕЮ", func() -> void:
		if _in_run():
			_cheat()
			var s = game.snake
			s.god = false
			s.safe = false
			s.invuln = 0.0
			s.shield = 0
			s.extra_life = false
			s.phoenix = false
			s.take_damage(99, "dev")))
	_section(p, "ВЫДАТЬ АТАКУ")
	var ab := _grid(p, 2)
	for type in Balance.ABILITIES:
		ab.add_child(_btn(Balance.ABILITIES[type]["name"], func() -> void:
			if game.snake:
				_cheat()
				game.abilities.gain(type)))
	_section(p, "ПРОГРЕСС")
	var g2 := _grid(p, 2)
	g2.add_child(_btn("ПОБЕДИТЬ ЭТАП", _win_stage, "Primary"))
	g2.add_child(_btn("ЯИЧНИЦЕ 1 HP", func() -> void:
		if game.boss:
			_cheat()
			game.boss.dev_set_hp(1)))
	for ph in 3:  # фазы яичницы: 1 — полное HP, 2 — две трети, 3 — треть
		g2.add_child(_btn("ЯИЧНИЦА: ФАЗА %d" % (ph + 1), func() -> void:
			if game.boss:
				_cheat()
				game.boss.dev_set_hp(int(ceil(game.boss.max_hp * (3 - ph) / 3.0)))))
	g2.add_child(_btn("◀ ЭТАП", func() -> void: _step_stage(-1)))
	g2.add_child(_btn("ЭТАП ▶", func() -> void: _step_stage(1)))


func _win_stage() -> void:
	if not _in_run():
		return
	_cheat()
	if game.state == game.State.LEVEL:
		game.goal_done = game.goal_total - 1
		game.goal_progress(game.stage)
	elif game.boss and game.state == game.State.BOSS:
		game.boss.dev_set_hp(0)


# ---------------------------------------------------------------- МИР

func _build_world(p: VBoxContainer) -> void:
	_section(p, "СКОЛЬКО СОЗДАВАТЬ ЗА НАЖАТИЕ")
	var cnt := Segmented.new()
	cnt.setup(["×1", "×3", "×5", "×10"], 0, 0.0, true)
	cnt.changed.connect(func(i: int) -> void: spawn_count = SPAWN_COUNTS[i])
	p.add_child(cnt)
	for b in cnt.buttons:
		b.add_theme_font_size_override("font_size", 11)
	_section(p, "ПЕРЕЙТИ К ЭТАПУ")
	var st := _grid(p, 2)
	for i in Balance.STAGES.size():
		st.add_child(_btn("%d. %s" % [i + 1, Balance.STAGES[i]["short"]], _jump.bind(i)))
	_section(p, "СОЗДАТЬ МЕДВЕДЯ")
	var sp := _grid(p, 3)
	for i in BEAR_NAMES.size():
		sp.add_child(_btn(BEAR_NAMES[i], _spawn.bind("bear", i)))
	_section(p, "СОЗДАТЬ ВИЛКУ И ТАБЛЕТКУ")
	var sp2 := _grid(p, 3)
	for k in Fork.KINDS:
		sp2.add_child(_btn(String(Fork.KINDS[k]["name"]), _spawn.bind("fork", k)))
	for k in Pill.KINDS.size():
		sp2.add_child(_btn(String(Pill.KINDS[k]["name"]), _spawn.bind("pill", k)))
	_section(p, "СОЗДАТЬ МАТРЁШКУ")
	var sp3 := _grid(p, 4)
	sp3.add_child(_btn("Набор", _spawn.bind("set", 0), "Primary"))
	for k in range(Matryoshka.SIZES.size() - 1, -1, -1):
		sp3.add_child(_btn(String(Matryoshka.SIZES[k]["name"]), _spawn.bind("doll", k)))
	_section(p, "12.4: ЮЛА И ШИПУЧКА")
	var sp4 := _grid(p, 2)
	sp4.add_child(_btn("Юла — сейчас", _doll_spin))
	sp4.add_child(_btn("Лужа у змеи", _fizz_puddle))
	_section(p, "ПРИЁМЫ ВИЛОК — БЛИЖАЙШАЯ К ЗМЕЕ")
	var atk := _grid(p, 2)
	for a in Fork.ATTACK_NAMES.size():
		atk.add_child(_btn(Fork.ATTACK_NAMES[a], _fork_attack.bind(a)))
	_section(p, "ПОЛЕ")
	var g := _grid(p, 2)
	g.add_child(_btn("ОЧИСТИТЬ ПОЛЕ", func() -> void:
		if _in_run():
			_cheat()  # убрать всех врагов с поля — тоже чит (до v11.0 забег оставался честным)
			game.enemies.clear()
			game.shots.clear()))
	g.add_child(_btn("ФИНАЛ", func() -> void:
		game.args["ending"] = true
		_cheat()
		if game.state == game.State.MENU:
			game.start_game(game.difficulty)
		elif _in_run():
			game.enemies.clear()
			game.shots.clear()
			game.state = game.State.OUTRO
			game.start_ending()
		toggle()))
	g.add_child(_btn("КОНТАКТ", func() -> void:  # технический режим v10.0 с начала
		_cheat()
		game.start_contact()
		toggle()))
	g.add_child(_btn("ФИНАЛ КОНТАКТА", func() -> void:  # все убеждены — сразу к пожару в ящике
		_cheat()
		game.start_contact()
		game.contact.debug_skip_to_finale()
		toggle()))
	g.add_child(_btn("ДОСКА В КОНТАКТЕ: ТРЕСНУТЬ", _crack_plank))
	_toggle(p, "Автопилот", game.autopilot, func(on: bool) -> void:
		_cheat()
		game.autopilot = on
		if game.snake and not on:
			game.snake.autopilot = false)
	var speed := Fader.new()
	speed.min_value = 0.25
	speed.max_value = 3.0
	speed.step = 0.25
	speed.value = 1.0
	speed.custom_minimum_size = Vector2(180, 36)
	speed.value_changed.connect(func(v: float) -> void:
		if v != 1.0:
			_cheat()
		Engine.time_scale = v)
	_row(p, "Скорость времени", speed)
	_section(p, "ПРОВЕРКА ЭФФЕКТОВ")
	var fxg := _grid(p, 3)
	fxg.add_child(_btn("Подсказка", func() -> void: game.hint("Так выглядит подсказка внизу экрана", 3.0)))
	fxg.add_child(_btn("Табличка", func() -> void: game.hud.show_banner("ПРОВЕРКА ТАБЛИЧКИ", Design.YOLK, 1.5)))
	fxg.add_child(_btn("Реплика", func() -> void: game.hud.show_caption("УЧЁНЫЙ-БЮРОКРАТ", "Пункт 12-Б. Немедленно.")))
	fxg.add_child(_btn("Вспышка", func() -> void: game.hud.overlay.flash(0.8)))
	fxg.add_child(_btn("Тряска", func() -> void: game.add_shake(20.0)))
	fxg.add_child(_btn("Всплывашка", func() -> void: game.fx.popup(Vector2(640, 360), "ПРОВЕРКА!", Design.MINT)))
	fxg.add_child(_btn("Конфетти", func() -> void:
		for c: Color in [Color(0.95, 0.3, 0.5), Color(0.3, 0.7, 0.95), Color(0.6, 0.9, 0.3), Color(1, 0.85, 0.3)]:
			game.fx.burst(Vector2(randf_range(300, 980), randf_range(200, 500)), c, 14, 1.3)))
	fxg.add_child(_btn("Вибро", func() -> void: game.vibrate(120)))
	_section(p, "ВАКХАНАЛИЯ В МЕНЮ")
	var dg := _grid(p, 2)
	for id: String in MenuDemo.EVENTS:
		dg.add_child(_btn(String(MenuDemo.EVENTS[id]).trim_suffix("!"), func() -> void:
			if game.menu_demo:
				game.menu_demo.run_event(id)))
	_section(p, "ПАСХАЛКИ")
	secrets_box = Design.vbox(Design.SPACE[1])
	p.add_child(secrets_box)
	var sg := _grid(p, 2)
	sg.add_child(_btn("КОЩЕЕВА ИГЛА СЕЙЧАС", func() -> void:
		if _in_run():
			_cheat()
			game.enemies.koschei(game.snake.head_pos)
			_fill_secrets()))
	sg.add_child(_btn("ЗАБЫТЬ ПАСХАЛКИ", func() -> void:
		Secrets.reset()
		_fill_secrets()))


func _jump(i: int) -> void:
	_cheat()
	if game.state == game.State.MENU:
		game.args["stage"] = i
		game.start_game(game.difficulty)
		return
	if not _in_run():
		return
	_cheat()
	get_tree().paused = false
	game.hud.close_all()
	game.enemies.clear()
	game.shots.clear()
	if game.boss and i != Balance.BOSS_STAGE:
		game.boss.queue_free()
		game.boss = null
		game.hud.set_boss(false)
	if game.boss and i == Balance.BOSS_STAGE:
		return
	game.enter_stage(i)


func _spawn(kind: String, type: int) -> void:
	if not _in_run():
		return
	_cheat()
	for i in spawn_count:
		match kind:
			"bear":
				game.enemies.spawn_bear(type)
			"fork":
				game.enemies.spawn_fork(Vector2.INF, type)
			"pill":
				game.enemies.spawn_pill(Vector2.INF, type)
			"doll":
				game.enemies.spawn_doll(type)
			"set":
				game.enemies.spawn_doll_set()


## Этап на шаг вперёд или назад (в пределах маршрута).
func _step_stage(d: int) -> void:
	var cur: int = game.stage if game.state not in [game.State.MENU, game.State.LOADING] else 0
	_jump(clampi(cur + d, 0, Balance.STAGES.size() - 1))


## Доска в углу ящика ломается сейчас: если финала «Контакта» ещё нет — запускаем его и ждём начала.
func _crack_plank() -> void:
	_cheat()
	if game.state != game.State.CONTACT or game.contact == null:
		game.start_contact()
		game.contact.debug_skip_to_finale()
	toggle()
	for i in 1800:  # до 30 секунд ждём, пока финал начнётся
		if game.contact != null and game.contact.finale != null:
			game.contact.finale.debug_crack()
			return
		await get_tree().process_frame


## Список пасхалок: найденные — со штампом-галочкой, остальные — с подсказкой, где искать.
func _fill_secrets() -> void:
	for c in secrets_box.get_children():
		c.queue_free()
	for e: Dictionary in Secrets.LIST:
		var found := Secrets.is_found(e["id"])
		var l := Design.label("%s  %s — %s" % ["✔" if found else "·", e["title"], e["hint"]], "caption",
			Design.MINT if found else Design.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		secrets_box.add_child(l)


# ---------------------------------------------------------------- ИИ

func _build_ai(p: VBoxContainer) -> void:
	_section(p, "УРОВЕНЬ ОТРЯДА")
	var lv := Segmented.new()
	lv.setup(["КАК В СЛОЖНОСТИ", "0", "1", "2"], 0, 0.0, true)
	lv.changed.connect(func(i: int) -> void:
		if COOP_LEVELS[i] >= 0:
			_cheat()
		game.enemies.coop_override = COOP_LEVELS[i])
	p.add_child(lv)
	for b in lv.buttons:
		b.add_theme_font_size_override("font_size", 11)
	var note := Design.label("0 — каждый сам по себе, 1 — Сложная (клещи, хоровод, заслоны), 2 — Ультра (тройные клещи, обманщик, дуэт малышек).",
		"caption", Design.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(note)
	_toggle(p, "Роли и хоровод над врагами", false, func(on: bool) -> void: overlay.roles = on)
	_section(p, "ПРИЁМЫ ПО КНОПКЕ")
	var g := _grid(p, 2)
	g.add_child(_btn("КЛЕЩИ СЕЙЧАС", _force_ai.bind("pincer")))
	g.add_child(_btn("ХОРОВОД СЕЙЧАС", _force_ai.bind("khorovod")))
	g.add_child(_btn("ДУЭТ МАЛЫШЕК", _force_ai.bind("duet")))
	g.add_child(_btn("СБРОСИТЬ ОТРЯД", _force_ai.bind("reset")))
	_section(p, "СЧЁТЧИКИ")
	ai_label = Design.label("", "small", Design.CREAM)
	ai_label.label_settings.font = Design.font("mono")
	ai_label.label_settings.font_size = 12
	p.add_child(ai_label)
	_section(p, "РОЛИ СЕЙЧАС")
	roles_label = Design.label("", "small", Design.CREAM)
	roles_label.label_settings.font = Design.font("mono")
	roles_label.label_settings.font_size = 12
	roles_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(roles_label)


## Заставить отряд провести приём: нужные враги создаются, если их нет, уровень поднимается до нужного.
func _force_ai(what: String) -> void:
	if not _in_run():
		return
	_cheat()
	var e = game.enemies
	var sq = e.squad
	var head: Vector2 = game.snake.head_pos
	match what:
		"pincer":
			e.coop_override = maxi(e.coop_override, 1)
			while e.forks.size() < 2:
				e.spawn_fork(head + Vector2.from_angle(randf() * TAU) * 300.0)
			for f in e.forks:
				f.spawn_k = 1.0
				f.attack_cd = 0.0
			sq.pincer_cd = 0.0
		"khorovod":
			e.coop_override = maxi(e.coop_override, 1)
			var n := 0
			for m in e.dolls:  # в хоровод зовут только тех, кто рядом
				if not m.is_last() and m.position.distance_to(head) < sq.KHOROVOD_REACH - 40.0:
					n += 1
			for i in maxi(4 - n, 0):
				e.spawn_doll(Matryoshka.Size.MIDDLE, (head + Vector2.from_angle(i * 1.6) * 230.0).clamp(game.bounds.position + Vector2(40, 40), game.bounds.end - Vector2(40, 40)))
			for m in e.dolls:
				m.spawn_k = 1.0
			sq.kh_cd = 0.0
		"duet":
			e.coop_override = 2
			var tinies := 0
			for m in e.dolls:
				if m.is_last():
					tinies += 1
					m.attack_cd = 0.0
					m.spawn_k = 1.0
			for i in maxi(2 - tinies, 0):
				var m = e.spawn_doll(Matryoshka.Size.TINY, head + Vector2(-160 + i * 320, 80))
				m.spawn_k = 1.0
				m.attack_cd = 0.0
			sq.duet_cd = 0.0
		"reset":
			sq.reset()
	sq.tick_t = 0.0


func _update_ai() -> void:
	var sq = game.enemies.squad
	var keys: Array = sq.stats.keys()
	var lines := PackedStringArray()
	for i in range(0, keys.size(), 2):
		var a := "%-12s %3d" % [keys[i], sq.stats[keys[i]]]
		var b := "%-12s %3d" % [keys[i + 1], sq.stats[keys[i + 1]]] if i + 1 < keys.size() else ""
		lines.append(a + "   " + b)
	ai_label.text = "\n".join(lines)
	var roles := PackedStringArray()
	for r: Dictionary in sq.roles.values():
		if is_instance_valid(r["node"]):
			roles.append("%s → %s" % [_who(r["node"]), r["role"]])
	if not sq.pincer.is_empty():
		roles.append("клещи: %d вилки" % sq.pincer.size())
	if not sq.khorovod.is_empty():
		roles.append("хоровод: %d матрёшки, осталось %.1f с" % [sq.khorovod.size(), sq.kh_t])
	roles_label.text = "\n".join(roles) if not roles.is_empty() else "никто ни с кем не сговаривается"


func _who(n: Object) -> String:
	if n is Matryoshka:
		return "матрёшка (%s)" % String(n.spec()["name"]).to_lower()
	if n is Pill:
		return "таблетка"
	if n.get("type") != null:
		return "медведь (%s)" % BEAR_NAMES[n.type].to_lower()
	return "враг"


## Заставить вилку провести приём (если вилок нет — создать столовую).
func _fork_attack(a: int) -> void:
	if not _in_run():
		return
	_cheat()
	var forks: Array = game.enemies.forks
	if forks.is_empty():
		game.enemies.spawn_fork()
	var head: Vector2 = game.snake.head_pos
	var best: Fork = forks[0]
	for f: Fork in forks:
		if f.position.distance_to(head) < best.position.distance_to(head):
			best = f
	best.begin_attack(a, head)


## Ближайшая малышка раскручивается юлой на змею (нет малышки — появится). Проверить полосу и отскок.
func _doll_spin() -> void:
	if not _in_run():
		return
	_cheat()
	var head: Vector2 = game.snake.head_pos
	var best: Matryoshka = null
	for m: Matryoshka in game.enemies.dolls:
		if m.is_last() and (best == null or m.position.distance_to(head) < best.position.distance_to(head)):
			best = m
	if best == null:
		best = game.enemies.spawn_doll(Matryoshka.Size.TINY, head + Vector2(220, 0).rotated(randf() * TAU))
	best.spawn_k = 1.0
	best.st = Matryoshka.St.ROAM
	best.crouch(head, Vector2.ZERO)


## Шипящая лужа прямо под змеёй — проверить замедление.
func _fizz_puddle() -> void:
	if not _in_run():
		return
	_cheat()
	var p: Pill = game.enemies.spawn_pill(game.snake.head_pos + Vector2(300, 0), Pill.Kind.FIZZ)
	game.enemies.spawn_puddle(game.snake.head_pos, p)


# ---------------------------------------------------------------- ОТЛАДКА

func _build_debug(p: VBoxContainer) -> void:
	_toggle(p, "Хитбоксы и радиусы", false, func(on: bool) -> void: overlay.hitboxes = on)
	_toggle(p, "Безопасная зона и сетка", false, func(on: bool) -> void: overlay.safe_grid = on)
	_toggle(p, "Показывать FPS", Settings.flag("show_fps"), func(on: bool) -> void: Settings.set_value("show_fps", on))
	_toggle(p, "Сенсорное управление на ПК", Settings.choice("touch_mode") == 1, func(on: bool) -> void:
		Settings.set_value("touch_mode", 1 if on else 0)
		game.hud.apply_setting("touch_mode"))
	_toggle(p, "Пауза времени", false, func(on: bool) -> void:
		_cheat()
		time_paused = on
		if on:
			saved_scale = Engine.time_scale if Engine.time_scale > 0.0 else 1.0
			Engine.time_scale = 0.0
		else:
			Engine.time_scale = saved_scale)
	var tg := _grid(p, 2)
	tg.add_child(_btn("+1 КАДР", step_frame))
	tg.add_child(_btn("+10 КАДРОВ", func() -> void:
		for i in 10:
			await step_frame()))
	_section(p, "ЖУРНАЛ ОШИБОК")
	log_label = Design.label("", "small", Design.CREAM)
	log_label.label_settings.font = Design.font("mono")
	log_label.label_settings.font_size = 11
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(log_label)
	var lgrid := _grid(p, 2)
	lgrid.add_child(_btn("ОБНОВИТЬ", _update_log))
	lgrid.add_child(_btn("ОЧИСТИТЬ ЖУРНАЛ", func() -> void:
		DevLog.shared.clear()
		_update_log()))
	sound_grid = Design.vbox(Design.SPACE[2])
	p.add_child(sound_grid)


## Один кадр при паузе времени: масштаб на миг возвращается к 1.
func step_frame() -> void:
	if not time_paused:
		return
	Engine.time_scale = 1.0
	await get_tree().process_frame
	if time_paused:
		Engine.time_scale = 0.0


func _update_log() -> void:
	var lg = DevLog.shared
	var text: String = lg.snapshot() if lg != null else ""
	log_label.text = text if text != "" else "Пусто — ошибок и предупреждений не было."


## Кнопки звуков строятся при первом показе вкладки — к этому времени звуки уже синтезированы.
func _fill_sounds() -> void:
	if sound_grid.get_child_count() > 0:
		return
	var names: Array = game.sfx.sounds.keys()
	names.sort()
	var groups := {"ЗВУКИ: ИНТЕРФЕЙС": [], "ЗВУКИ: ИГРА": [], "ЗВУКИ: ФИНАЛ": []}
	for n: String in names:
		if n.begins_with("ui_"):
			groups["ЗВУКИ: ИНТЕРФЕЙС"].append(n)
		elif n in ENDING_SOUNDS:
			groups["ЗВУКИ: ФИНАЛ"].append(n)
		else:
			groups["ЗВУКИ: ИГРА"].append(n)
	for title: String in groups:
		_section(sound_grid, title)
		var grid := _grid(sound_grid, 3)
		for n: String in groups[title]:
			var b := _btn(n.trim_prefix("ui_").replace("_", " "), game.sfx.play.bind(n))
			b.tooltip_text = n
			b.add_theme_font_size_override("font_size", 11)
			b.custom_minimum_size.y = 36
			grid.add_child(b)


# ---------------------------------------------------------------- UI-КИТ

func _build_kit(p: VBoxContainer) -> void:
	UiKit.build(p)


# ---------------------------------------------------------------- ТЕСТЫ

func _build_tests(p: VBoxContainer) -> void:
	p.add_child(Design.label("Юнит-тесты запускаются прямо в игре. Полный набор с интеграционными — из командной строки: godot --headless -s res://tests/run_tests.gd",
		"small", Design.MUTED))
	(p.get_child(0) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(_btn("ЗАПУСТИТЬ ЮНИТ-ТЕСТЫ", _run_tests, "Primary"))
	test_output = Design.label("", "small", Design.CREAM)
	test_output.label_settings.font = Design.font("mono")
	test_output.label_settings.font_size = 12
	test_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(test_output)


func _run_tests() -> void:
	if not ResourceLoader.exists(TEST_RUNNER):
		test_output.text = "Тестов нет в этой сборке — они исключены из экспорта. Запусти игру из исходников."
		return
	var runner: Object = load(TEST_RUNNER).new()
	var report: Dictionary = await runner.run_unit(self)
	test_output.text = report["text"]
	test_output.label_settings.font_color = Design.MINT if report["failed"] == 0 else Design.TOMATO


func _process(delta: float) -> void:
	if not open:
		return
	frame_ms.append(delta * 1000.0 / maxf(Engine.time_scale, 0.01))
	if frame_ms.size() > 120:
		frame_ms.pop_front()
	t += delta
	route.queue_redraw()
	run_lamp.queue_redraw()
	info_t -= delta
	if info_t <= 0.0 and pages[0].visible:
		info_t = 0.25
		_update_info()
		graph.queue_redraw()
	elif info_t <= 0.0 and pages[PAGE_DEBUG].visible:
		info_t = 0.5
		_update_log()
	elif info_t <= 0.0 and pages[PAGE_AI].visible:
		info_t = 0.25
		_update_ai()
