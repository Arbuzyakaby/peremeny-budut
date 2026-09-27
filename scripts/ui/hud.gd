extends CanvasLayer
## Интерфейс-фасад. Собирает слои (игровые панели, тач-управление, субтитры, экраны меню,
## панель разработчика) и даёт игре простой API. Навигация по экранам — стек: «Назад» / Esc
## возвращает на предыдущий. Масштаб интерфейса и безопасная зона применяются здесь.

signal difficulty_chosen(index: int)
signal daily_chosen
signal retry_pressed
signal menu_pressed
signal records_reset
signal perk_chosen(id: String)
signal pause_changed(paused: bool)
signal skip_pressed
signal attack_pressed
signal settings_changed(key: String)
signal dev_toggled
signal back_unhandled  # «Назад» не нужен интерфейсу (например, пропустить финал)

const Design = preload("res://scripts/ui/design.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Skills = preload("res://scripts/core/skills.gd")
const Platform = preload("res://scripts/core/platform.gd")
const Tips = preload("res://scripts/core/tips.gd")
const HudOverlay = preload("res://scripts/ui/hud_overlay.gd")
const Captions = preload("res://scripts/ui/captions.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const MenuScreen = preload("res://scripts/ui/screens/menu_screen.gd")
const PauseScreen = preload("res://scripts/ui/screens/pause_screen.gd")
const EndScreen = preload("res://scripts/ui/screens/end_screen.gd")
const PerkScreen = preload("res://scripts/ui/screens/perk_screen.gd")
const SettingsScreen = preload("res://scripts/ui/screens/settings_screen.gd")
const SkillTreeScreen = preload("res://scripts/ui/screens/skill_tree_screen.gd")
const LoadingScreen = preload("res://scripts/ui/screens/loading_screen.gd")
const BestiaryScreen = preload("res://scripts/ui/screens/bestiary_screen.gd")
const ReplayScreen = preload("res://scripts/ui/screens/replay_screen.gd")

var sfx: Node  # проигрыватель звуков (sfx.gd), назначается игрой

var root: Control
var overlay: HudOverlay
var captions: Captions
var touch: TouchControls
var menu: MenuScreen
var pause_screen: PauseScreen
var end_screen: EndScreen
var perks: PerkScreen
var settings_screen: SettingsScreen
var skills_screen: SkillTreeScreen
var bestiary_screen: BestiaryScreen
var replay_screen: ReplayScreen
var replay: RefCounted  # replay.gd — назначается игрой
var loading: LoadingScreen
var dev_button: Button
var stack: Array = []  # открытые экраны, последний — сверху

var shot_frames: Array[int] = []  # отладка: снимки экрана на этих кадрах после загрузки (--shots=)
var shot_frame := 0
var pause_allowed := false
var pause_summary := ""
var cinematic := false
const SHADE := Color(0.4, 0.38, 0.42)  # табло в тени: золото гаснет почти до бронзы
var shade_tween: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	Design.sound_player = sfx

	overlay = HudOverlay.new()
	add_child(overlay)  # игровые панели — без масштаба интерфейса, по краям экрана
	touch = TouchControls.new()
	touch.attack_pressed.connect(attack_pressed.emit)
	touch.pause_pressed.connect(func() -> void:
		if pause_allowed:
			set_paused(true))
	add_child(touch)

	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Design.make_theme()
	add_child(root)
	captions = Captions.new()
	captions.skip_requested.connect(skip_pressed.emit)
	root.add_child(captions)

	menu = _screen(MenuScreen.new())
	menu.difficulty_chosen.connect(difficulty_chosen.emit)
	menu.skills_requested.connect(func() -> void: push(skills_screen))
	menu.settings_requested.connect(func() -> void: push(settings_screen))
	menu.quit_requested.connect(quit)
	menu.daily_requested.connect(daily_chosen.emit)
	menu.bestiary_requested.connect(func() -> void: push(bestiary_screen))
	pause_screen = _screen(PauseScreen.new())
	pause_screen.resume_requested.connect(set_paused.bind(false))
	pause_screen.settings_requested.connect(func() -> void: push(settings_screen))
	pause_screen.menu_requested.connect(menu_pressed.emit)
	end_screen = _screen(EndScreen.new())
	end_screen.retry_requested.connect(retry_pressed.emit)
	end_screen.menu_requested.connect(menu_pressed.emit)
	end_screen.replay_requested.connect(func() -> void:
		push(replay_screen)
		replay_screen.show_replay(replay))
	perks = _screen(PerkScreen.new())
	perks.perk_chosen.connect(func(id: String) -> void:
		stack.clear()
		perk_chosen.emit(id))
	settings_screen = _screen(SettingsScreen.new())
	settings_screen.records_reset.connect(records_reset.emit)
	settings_screen.setting_changed.connect(apply_setting)
	settings_screen.dev_mode_unlocked.connect(func() -> void:
		_update_dev_button()
		show_banner("Режим разработчика включён", Design.PLUM, 1.4))
	skills_screen = _screen(SkillTreeScreen.new())
	bestiary_screen = _screen(BestiaryScreen.new())
	replay_screen = _screen(ReplayScreen.new())

	dev_button = Design.button("", func() -> void: dev_toggled.emit(), "Ghost", Vector2(56, 44))
	dev_button.focus_mode = Control.FOCUS_NONE
	dev_button.text = "</>"
	dev_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	root.add_child(dev_button)
	_update_dev_button()

	get_viewport().size_changed.connect(layout)
	layout()


func _screen(s: Control) -> Control:
	root.add_child(s)
	s.build()
	s.closed.connect(pop)
	return s


## Раскладка: масштаб интерфейса, безопасная зона.
func layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var k := Settings.ui_scale()
	var safe := Platform.safe_margins(get_viewport())
	root.scale = Vector2(k, k)
	root.position = Vector2(safe.x, safe.y)
	root.size = (vp - Vector2(safe.x + safe.z, safe.y + safe.w)) / k
	overlay.safe = safe
	touch.safe = safe
	dev_button.position = Vector2(12, root.size.y - 56)
	for s in [menu, pause_screen, end_screen, perks, settings_screen, skills_screen, bestiary_screen, replay_screen]:
		s.fit()


## Применить изменённую настройку к интерфейсу.
func apply_setting(key: String) -> void:
	if key in ["ui_scale", "*"]:
		layout()
	if key in ["touch_mode", "*"]:
		_update_touch()
	settings_changed.emit(key)


func _update_dev_button() -> void:
	dev_button.visible = Settings.flag("dev_mode") and Platform.has_touchscreen()


# ---------------------------------------------------------------- навигация

func push(s: Control) -> void:
	if not stack.is_empty():
		stack.back().close()
	stack.append(s)
	s.open()


func pop() -> void:
	if stack.is_empty():
		return
	stack.pop_back().close()
	if not stack.is_empty():
		var top: Control = stack.back()
		top.visible = true
		top.focus_first()
		if top == menu:
			menu.update_scales(Skills.scales)
	elif get_tree().paused and pause_allowed:
		set_paused(false)


func close_all() -> void:
	for s in stack:
		s.close()
	stack.clear()


func is_screen_open() -> bool:
	return not stack.is_empty()


# ---------------------------------------------------------------- экраны

func show_loading(progress: float) -> void:
	if loading == null:
		loading = LoadingScreen.new()
		root.add_child(loading)
	loading.progress = progress


func hide_loading() -> void:
	if loading:
		var l := loading
		loading = null
		var tw := l.create_tween()
		tw.tween_property(l, "modulate:a", 0.0, Design.SLOW)
		tw.tween_callback(l.queue_free)


func show_menu(diffs: Array, bests: Array, selected: int) -> void:
	overlay.in_game = false
	touch.set_active(false)
	close_all()
	stack.append(menu)
	Skills.ensure_loaded()
	menu.show_menu(diffs, bests, selected, Skills.scales, Settings.touch_enabled())


func open_skills() -> void:
	push(skills_screen)


func show_game(diff_name: String, diff_color: Color, lives_max: int) -> void:
	close_all()
	overlay.reset_run(diff_name, diff_color, lives_max)
	_update_touch()


func show_end(win: bool, title: String, line: String, rows: Array) -> void:
	pause_allowed = false
	captions.hide_caption()
	touch.set_active(false)
	close_all()
	stack.append(end_screen)
	end_screen.show_end(win, title, line, rows, replay != null and not win and replay.has_data(),
		"" if win or replay == null else Tips.for_cause(replay.cause))


func show_perks(cards: Array, next_stage: String) -> void:
	touch.set_active(false)
	close_all()
	stack.append(perks)
	perks.show_perks(cards, next_stage, Settings.touch_enabled())


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if paused:
		touch.release_all()
		captions.hide_caption()
		close_all()
		stack.append(pause_screen)
		pause_screen.show_pause(pause_summary)
	else:
		close_all()
		Settings.save()
	_update_touch()
	pause_changed.emit(paused)


func _update_touch() -> void:
	var on := Settings.touch_enabled()
	touch.visible = on
	overlay.touch = on
	touch.set_active(on and overlay.in_game and not get_tree().paused and not cinematic and stack.is_empty())
	_update_dev_button()


func quit() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if back():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("mute"):
		if sfx:
			sfx.toggle_mute()
			if stack.is_empty():
				show_banner("Звук выключен" if sfx.is_muted() else "Звук включён", Design.STEEL, 0.8)


## «Назад» / Esc: закрыть верхний экран или поставить паузу. false — нажатие нужно игре
## (например, пропустить катсцену).
func back() -> bool:
	if not stack.is_empty():
		return stack.back().handle_back()
	if pause_allowed:
		set_paused(true)
		return true
	return false


# ---------------------------------------------------------------- данные для игры

func set_score(value: int) -> void:
	overlay.score_target = value


func set_goal(stage_index: int, done: int, total: int) -> void:
	overlay.stage = stage_index
	overlay.goal_done = done
	overlay.goal_total = total


func set_lives(value: int) -> void:
	overlay.set_lives(value)


func set_max_lives(value: int) -> void:
	overlay.max_lives = value


func lives() -> int:
	return overlay.lives


func set_boss(visible_bar: bool, hp: int = 0, max_hp: int = 1, phase: int = 1) -> void:
	overlay.set_boss(visible_bar, hp, max_hp, phase)


func set_ability(type: int, ability_title: String, count: int) -> void:
	overlay.set_ability(type, ability_title, count)
	touch.ability_type = type
	touch.ability_charges = count


## Состояние змеи на кадр: стамина, щит, голова на экране (для прозрачности панелей и схемы «палец»).
func track_snake(stamina: float, exhausted: bool, shield: int, head_screen: Vector2, play_time: float) -> void:
	overlay.stamina = stamina
	overlay.exhausted = exhausted
	overlay.shield = shield
	overlay.snake_screen = head_screen
	overlay.play_time = play_time
	touch.stamina = stamina
	touch.head_screen = head_screen
	touch.pause_rect = overlay.pause_slot()


func set_dev_run(on: bool) -> void:
	overlay.dev_run = on


## Табло уходят в тень на time секунд: лампы и золото желтка на них гаснут, потому что
## главный акцент теперь на арене (открытый желток яичницы). Подсказки и тач-кнопки не гаснут.
func shade_accent(time := 1.0) -> void:
	if shade_tween:
		shade_tween.kill()
	shade_tween = create_tween()
	shade_tween.tween_property(overlay, "modulate", SHADE, Design.FAST * 2.0)
	shade_tween.tween_interval(time)
	shade_tween.tween_property(overlay, "modulate", Color.WHITE, Design.SLOW)


func show_banner(text: String, color := Design.YOLK, duration := 2.0) -> void:
	captions.show_banner(text, color, duration)


## Субтитры финала (можно отключить в настройках).
func show_caption(speaker: String, text: String) -> void:
	captions.show_caption(speaker, text, false)


## Подсказка внизу экрана во время игры (не зависит от настройки субтитров).
func show_hint(text: String) -> void:
	captions.show_caption("", text, true)


func hide_caption() -> void:
	captions.hide_caption()


func show_prompt(text: String) -> void:
	captions.show_prompt(text)


func hide_prompt() -> void:
	captions.hide_prompt()


func show_title_card(text: String, color: Color) -> void:
	captions.show_title_card(text, color)


func hide_title_card(time := 1.2) -> void:
	captions.hide_title_card(time)


func roll_credits(text: String, duration: float) -> void:
	captions.roll_credits(text, duration)


func stop_credits() -> void:
	captions.stop_credits()


func set_cinematic(on: bool) -> void:
	cinematic = on
	if on:
		overlay.in_game = false
		overlay.boss_visible = false
	captions.skip_button.visible = on and Settings.touch_enabled()
	captions.set_bottom_margin(84.0 if on else 0.0)
	_update_touch()
	create_tween().tween_property(overlay, "cine", 1.0 if on else 0.0, 1.0)


func _on_system_back() -> void:
	if not back():
		back_unhandled.emit()


func _process(_delta: float) -> void:
	if shot_frames.is_empty():
		return
	shot_frame += 1
	if shot_frame in shot_frames:  # HUD обрабатывается и на паузе — снимок сработает везде
		var dir := ProjectSettings.globalize_path("user://shots")
		DirAccess.make_dir_recursive_absolute(dir)
		get_viewport().get_texture().get_image().save_png(dir.path_join("shot_%04d.png" % shot_frame))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:  # системная кнопка «Назад» на Android = Esc
		# не посреди уведомления: переход в меню перезагружает сцену, а это безопасно только
		# в обычном кадре (прямо из уведомления Android падал в потоке рендера)
		_on_system_back.call_deferred()
