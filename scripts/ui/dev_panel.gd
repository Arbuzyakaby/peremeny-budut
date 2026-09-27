extends CanvasLayer
## Панель разработчика (F1, ` или Ctrl+Shift+D; на телефоне — кнопка </> после 7 нажатий на версию в настройках).
## Вкладки: ИНФО (производительность и состояние), ЧИТЫ, МИР (этапы, спавн, время), ОТЛАДКА
## (хитбоксы, безопасная зона, звуки), UI-КИТ (витрина дизайн-языка), ТЕСТЫ (юнит-тесты в игре).
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

const WIDTH := 460.0
const TABS := ["ИНФО", "ЧИТЫ", "МИР", "ДЕБАГ", "UI", "ТЕСТЫ"]
const BEAR_NAMES := ["Обычный", "Боксёр", "Метатель", "Каратист", "Швея", "Ниндзя", "Хлопушка", "Медсестра"]
const TEST_RUNNER := "res://tests/test_runner.gd"

var game  # game.gd
var panel: PanelContainer
var pages: Array[Control] = []
var info_label: Label
var graph: Control
var frame_ms: Array[float] = []
var test_output: Label
var sound_grid: GridContainer
var overlay: DevOverlay
var open := false
var info_t := 0.0


func _ready() -> void:
	layer = 20
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
	var t := Design.label("ПАНЕЛЬ РАЗРАБОТЧИКА", "h3", Design.PLUM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Design.button("×", toggle, "Ghost", Vector2(44, 40))
	close.focus_mode = Control.FOCUS_NONE
	head.add_child(close)
	col.add_child(head)
	var tabs := Segmented.new()
	tabs.setup(TABS, 0)
	tabs.changed.connect(_show_page)
	col.add_child(tabs)
	for b in tabs.buttons:  # компактные сегменты: тема уже применена, раз узел в дереве
		b.add_theme_font_size_override("font_size", 12)
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var sb := b.get_theme_stylebox(st).duplicate() as StyleBox
			sb.content_margin_left = 17  # слева — место под лампу нажатой клавиши
			sb.content_margin_right = 9
			b.add_theme_stylebox_override(st, sb)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var stack := Design.vbox(0)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	for builder in [_build_info, _build_cheats, _build_world, _build_debug, _build_kit, _build_tests]:
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
	for k in pages.size():
		pages[k].visible = k == i
	if i == 3:
		_fill_sounds()


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


func _btn(text: String, cb: Callable, variant := "") -> Button:
	var b := Design.button(text, cb, variant, Vector2(0, 44))
	b.add_theme_font_size_override("font_size", 14)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _grid(parent: Control, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", Design.SPACE[2])
	g.add_theme_constant_override("v_separation", Design.SPACE[2])
	parent.add_child(g)
	return g


func _cheat() -> void:
	game.mark_debug_run()


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
	var lines := [
		"FPS            %d   (кадр %.1f мс)" % [Engine.get_frames_per_second(), frame_ms.back() if frame_ms.size() > 0 else 0.0],
		"Узлы / объекты %d / %d" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT)],
		"Память         %.1f МБ" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		"Отрисовок      %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"Состояние      %s" % game.State.keys()[game.state],
		"Этап / цель    %d  •  %d/%d" % [game.stage + 1, game.goal_done, game.goal_total],
		"Сложность      %s" % game.cfg["name"],
		"Враги / снаряды %d / %d" % [game.enemies.count(), game.shots.drops.size()],
		"Голоса звука   %d / %d" % [game.sfx.busy_voices(), game.sfx.VOICES],
		"Скорость       ×%.2f" % Engine.time_scale,
		"Платформа      %s" % Platform.describe(),
		"Экран          %dx%d  •  UI ×%.2f" % [vp.x, vp.y, Settings.ui_scale()],
		"Безопасная зона %s" % str(Platform.safe_margins(get_viewport())),
		"Тач            %s" % ("да" if Settings.touch_enabled() else "нет"),
		"Отладочный забег %s" % ("да" if game.debug_run else "нет"),
	]
	info_label.text = "\n".join(lines)


# ---------------------------------------------------------------- ЧИТЫ

func _build_cheats(p: VBoxContainer) -> void:
	p.add_child(Design.label("ЗМЕЯ", "overline", Design.YOLK))
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
	var g := _grid(p, 2)
	g.add_child(_btn("+1 ЖИЗНЬ", func() -> void:
		if game.snake:
			_cheat()
			if not game.snake.heal():
				game.snake.max_lives += 1
				game.snake.lives += 1
				game.hud.set_max_lives(game.snake.max_lives)
				game.hud.set_lives(game.snake.lives)))
	g.add_child(_btn("+100 ЧЕШУЕК", func() -> void:
		Skills.add_scales(100)
		game.hud.show_banner("+100 чешуек", Design.MINT, 0.8)))
	p.add_child(Design.label("ВЫДАТЬ АТАКУ", "overline", Design.YOLK))
	var ab := _grid(p, 2)
	for type in Balance.ABILITIES:
		ab.add_child(_btn(Balance.ABILITIES[type]["name"], func() -> void:
			if game.snake:
				_cheat()
				game.abilities.gain(type)))
	p.add_child(Design.label("ПРОГРЕСС", "overline", Design.YOLK))
	var g2 := _grid(p, 2)
	g2.add_child(_btn("ПОБЕДИТЬ ЭТАП", _win_stage, "Primary"))
	g2.add_child(_btn("ЯИЧНИЦЕ 1 HP", func() -> void:
		if game.boss:
			_cheat()
			game.boss.dev_set_hp(1)))


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
	p.add_child(Design.label("ПЕРЕЙТИ К ЭТАПУ", "overline", Design.YOLK))
	var st := _grid(p, 2)
	for i in Balance.STAGES.size():
		st.add_child(_btn("%d. %s" % [i + 1, Balance.STAGES[i]["short"]], _jump.bind(i)))
	p.add_child(Design.label("СОЗДАТЬ", "overline", Design.YOLK))
	var sp := _grid(p, 2)
	for i in BEAR_NAMES.size():
		sp.add_child(_btn("Медведь: " + BEAR_NAMES[i], _spawn.bind("bear", i)))
	for k in Fork.KINDS:
		sp.add_child(_btn("Вилка: " + String(Fork.KINDS[k]["name"]), _spawn.bind("fork", k)))
	sp.add_child(_btn("Таблетка", _spawn.bind("pill", 0)))
	p.add_child(Design.label("ПРИЁМЫ ВИЛОК (ближайшая к змее)", "overline", Design.YOLK))
	var atk := _grid(p, 2)
	for a in Fork.ATTACK_NAMES.size():
		atk.add_child(_btn(Fork.ATTACK_NAMES[a], _fork_attack.bind(a)))
	var g := _grid(p, 2)
	g.add_child(_btn("ОЧИСТИТЬ ПОЛЕ", func() -> void:
		if _in_run():
			game.enemies.clear()
			game.shots.clear()))
	g.add_child(_btn("ФИНАЛ", func() -> void:
		game.args["ending"] = true
		game.debug_run = true
		if game.state == game.State.MENU:
			game.start_game(game.difficulty)
		elif _in_run():
			game.enemies.clear()
			game.shots.clear()
			game.state = game.State.OUTRO
			game.start_ending()
		toggle()))
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


func _jump(i: int) -> void:
	game.debug_run = true
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
	match kind:
		"bear":
			game.enemies.spawn_bear(type)
		"fork":
			game.enemies.spawn_fork(Vector2.INF, type)
		"pill":
			game.enemies.spawn_pill()


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


# ---------------------------------------------------------------- ОТЛАДКА

func _build_debug(p: VBoxContainer) -> void:
	_toggle(p, "Хитбоксы и радиусы", false, func(on: bool) -> void: overlay.hitboxes = on)
	_toggle(p, "Безопасная зона и сетка", false, func(on: bool) -> void: overlay.safe_grid = on)
	_toggle(p, "Показывать FPS", Settings.flag("show_fps"), func(on: bool) -> void: Settings.set_value("show_fps", on))
	_toggle(p, "Сенсорное управление на ПК", Settings.choice("touch_mode") == 1, func(on: bool) -> void:
		Settings.set_value("touch_mode", 1 if on else 0)
		game.hud.apply_setting("touch_mode"))
	p.add_child(Design.label("ЗВУКИ", "overline", Design.YOLK))
	sound_grid = _grid(p, 3)


## Кнопки звуков строятся при первом показе вкладки — к этому времени звуки уже синтезированы.
func _fill_sounds() -> void:
	if sound_grid.get_child_count() > 0:
		return
	var names: Array = game.sfx.sounds.keys()
	names.sort()
	for n: String in names:
		var b := _btn(n, game.sfx.play.bind(n))
		b.add_theme_font_size_override("font_size", 11)
		b.custom_minimum_size.y = 34
		sound_grid.add_child(b)


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
	info_t -= delta
	if info_t <= 0.0 and pages[0].visible:
		info_t = 0.25
		_update_info()
		graph.queue_redraw()
