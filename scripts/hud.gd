extends CanvasLayer
## Интерфейс: игровые панели (счёт, медведи, жизни, рывок, HP босса), меню выбора сложности,
## настройки, пауза, киношные полосы с субтитрами для финала и экран итогов.

signal difficulty_chosen(index: int)
signal retry_pressed
signal menu_pressed
signal records_reset

const Settings = preload("res://scripts/settings.gd")

const GOLD := Color(1, 0.82, 0.3)
const PANEL_BG := Color(0.13, 0.08, 0.05, 0.9)
const PHASE_COLORS := [Color(1, 0.8, 0.15), Color(1, 0.55, 0.1), Color(0.95, 0.25, 0.1)]
const TIPS := [
	"Shift — спринт, но следи за стаминой!",
	"Съешь медведя-боксёра — получишь удар с разбега.",
	"Каратист даёт вертушку: она сбивает даже снаряды.",
	"Пуговицы и иглы можно метать прямо в яичницу!",
	"Стравливай медведей — пусть попадают друг в друга.",
	"Оглушённый медведь приносит двойные очки.",
	"Каратисты бьют больно — держи дистанцию.",
	"Иглы швей пришивают змею — она замедляется.",
]

var sfx: Node  # проигрыватель звуков (sfx.gd), назначается игрой

var title_font: SystemFont
var body_font: SystemFont
var root: Control
var overlay: Control
var game_ui: Control
var score_label: Label
var diff_label: Label
var bears_label: Label
var banner: Label
var dim: ColorRect
var menu_box: CenterContainer
var end_box: CenterContainer
var pause_box: CenterContainer
var settings_box: CenterContainer
var settings_return: CenterContainer
var settings_first: Control
var reset_button: Button
var reset_armed := false
var caption_box: VBoxContainer
var speaker_label: Label
var caption_label: Label
var caption_tween: Tween
var skip_label: Label
var fps_label: Label
var version_label: Label
var cinematic := false
var cine := 0.0
var menu_title: Label
var desc_label: Label
var end_title: Label
var end_stats: Label
var diff_buttons: Array[Button] = []
var end_first_button: Button
var pause_first_button: Button
var banner_tween: Tween

var difficulties: Array = []
var best_scores: Array = []

var t := 0.0
var in_game := false
var pause_allowed := false
var lives := 3
var max_lives := 3
var heart_anim := 0.0
var stamina := 1.0
var exhausted := false
var ability_type := -1
var ability_name := ""
var ability_charges := 0
var ability_flash := 0.0
var prompt_label: Label
var title_art: Control
var menu_panel: Control
var tip_label: Label
var tip_index := 0
var tip_t := 0.0
var menu_intro := 0.0
var menu_fade: Array[Control] = []
var bears_eaten := 0
var bears_total := 0
var score_target := 0
var score_shown := 0.0
var boss_visible := false
var boss_hp := 0
var boss_max := 1
var boss_phase := 1
var boss_hp_shown := 0.0
var boss_hp_ghost := 0.0
var boss_flash := 0.0
var hurt_flash := 0.0
var snake_head := Vector2(-999, -999)  # чтобы панели становились прозрачными, когда змея под ними


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["Segoe UI Black", "Arial Black", "Segoe UI", "Arial"])
	title_font.font_weight = 900
	body_font = SystemFont.new()
	body_font.font_names = PackedStringArray(["Segoe UI", "Arial"])
	body_font.font_weight = 600

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	overlay = _full_rect(Control.new())
	overlay.draw.connect(_on_overlay_draw)
	root.add_child(overlay)

	game_ui = _full_rect(Control.new())
	root.add_child(game_ui)
	var cap := _label("СЧЁТ", 15, GOLD, true)
	cap.position = Vector2(36, 22)
	game_ui.add_child(cap)
	score_label = _label("0", 34, Color.WHITE, true)
	score_label.position = Vector2(34, 36)
	game_ui.add_child(score_label)
	diff_label = _label("", 15, Color.WHITE, true)
	diff_label.position = Vector2(196, 22)
	diff_label.size = Vector2(140, 22)
	diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	game_ui.add_child(diff_label)
	bears_label = _label("", 18, Color(1, 0.92, 0.75), true)
	bears_label.position = Vector2(284, 86)
	game_ui.add_child(bears_label)

	banner = _label("", 44, Color(1, 0.55, 0.25), true)
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 150
	banner.offset_bottom = 215
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.pivot_offset = Vector2(640, 32)
	banner.modulate.a = 0.0
	root.add_child(banner)

	dim = ColorRect.new()
	_full_rect(dim)
	dim.color = Color(0.05, 0.03, 0.02, 0.55)
	root.add_child(dim)

	_build_caption()
	_build_menu()
	_build_end()
	_build_pause()
	_build_settings()
	_show_only(null)
	game_ui.visible = false


# ---------------------------------------------------------------- построение

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = body_font
	th.default_font_size = 22
	th.set_stylebox("panel", "PanelContainer", _panel_style(PANEL_BG, GOLD, 20, 4))
	th.set_stylebox("normal", "Button", _box(Color(0.3, 0.2, 0.12), Color(0.55, 0.38, 0.2), 14, 3))
	th.set_stylebox("hover", "Button", _box(Color(0.42, 0.28, 0.15), GOLD, 14, 3))
	th.set_stylebox("pressed", "Button", _box(Color(0.22, 0.14, 0.08), GOLD, 14, 3))
	var focus := _box(Color(0, 0, 0, 0), Color(1, 0.95, 0.6), 16, 4)
	focus.draw_center = false
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	th.set_stylebox("focus", "Button", focus)
	th.set_font("font", "Button", title_font)
	th.set_font_size("font_size", "Button", 24)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		th.set_color(c, "Button", Color.WHITE)
	# ползунки и переключатели настроек
	var track := _box(Color(0.08, 0.05, 0.03), Color(0.55, 0.38, 0.2), 8, 2)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	th.set_stylebox("slider", "HSlider", track)
	var fill := _box(GOLD.darkened(0.15), GOLD, 8, 0)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_stylebox("focus", "HSlider", focus)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		th.set_stylebox(st, "CheckButton", empty)
	th.set_stylebox("focus", "CheckButton", focus)
	return th


func _box(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _panel_style(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var s := _box(bg, border, radius, border_w)
	s.content_margin_left = 44
	s.content_margin_right = 44
	s.content_margin_top = 32
	s.content_margin_bottom = 32
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 6)
	return s


func _full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _label(text: String, size: int, color: Color, heavy := false) -> Label:
	var label := Label.new()
	label.text = text
	var settings := LabelSettings.new()
	settings.font = title_font if heavy else body_font
	settings.font_size = size
	settings.font_color = color
	settings.outline_size = maxi(size / 5, 4)
	settings.outline_color = Color(0.1, 0.05, 0.02, 0.9)
	label.label_settings = settings
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel(parent_center: CenterContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent_center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	return box


func _center_box() -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	return c


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(210, 60)
	b.pressed.connect(func() -> void:
		_sound("ui_select")
		on_press.call())
	b.mouse_entered.connect(b.grab_focus)
	b.focus_entered.connect(_sound.bind("ui_move"))
	return b


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _build_caption() -> void:
	caption_box = VBoxContainer.new()
	caption_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption_box.offset_top = -80
	caption_box.offset_bottom = -6
	caption_box.alignment = BoxContainer.ALIGNMENT_CENTER
	caption_box.add_theme_constant_override("separation", 0)
	caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_box.modulate.a = 0.0
	root.add_child(caption_box)
	speaker_label = _centered(_label("", 17, Color(1, 0.5, 0.35), true))
	caption_box.add_child(speaker_label)
	caption_label = _centered(_label("", 27, Color(1, 0.96, 0.9)))
	caption_box.add_child(caption_label)
	prompt_label = _label("", 30, GOLD, true)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_left = -500
	prompt_label.offset_right = 500
	prompt_label.offset_top = -150
	prompt_label.offset_bottom = -100
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.pivot_offset = Vector2(500, 25)
	prompt_label.visible = false
	root.add_child(prompt_label)
	skip_label = _label("Esc — пропустить", 15, Color(1, 1, 1, 0.55))
	skip_label.position = Vector2(1110, 28)
	skip_label.visible = false
	root.add_child(skip_label)
	fps_label = _label("", 15, Color(0.7, 1, 0.7))
	fps_label.position = Vector2(606, 6)
	root.add_child(fps_label)
	version_label = _label("v" + str(ProjectSettings.get_setting("application/config/version", "4.0")), 16,
		Color(1, 1, 1, 0.6))
	version_label.position = Vector2(1200, 690)
	root.add_child(version_label)


func _build_menu() -> void:
	menu_box = _center_box()
	menu_box.anchor_right = 0.5  # меню слева, справа — живая демо-арена
	menu_panel = PanelContainer.new()
	menu_box.add_child(menu_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	menu_panel.add_child(box)
	title_art = Control.new()
	title_art.custom_minimum_size = Vector2(440, 128)
	title_art.draw.connect(_draw_title_art)
	box.add_child(title_art)
	menu_title = _centered(_label("против ГИГАНТСКОЙ ЯИЧНИЦЫ", 27, Color(1, 0.85, 0.25), true))
	menu_title.pivot_offset = Vector2(220, 20)
	box.add_child(menu_title)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	box.add_child(sep)
	var choose := _centered(_label("ВЫБЕРИ СЛОЖНОСТЬ", 18, GOLD, true))
	box.add_child(choose)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for i in 3:
		var b := _button("", difficulty_chosen.emit.bind(i))
		b.custom_minimum_size = Vector2(140, 54)
		b.add_theme_font_size_override("font_size", 19)
		b.focus_entered.connect(_show_desc.bind(i))
		row.add_child(b)
		diff_buttons.append(b)
		menu_fade.append(b)
	desc_label = _centered(_label("", 18, Color(1, 0.95, 0.88)))
	desc_label.custom_minimum_size = Vector2(0, 80)
	box.add_child(desc_label)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 14)
	box.add_child(row2)
	var settings_b := _button("НАСТРОЙКИ", _open_settings.bind(menu_box))
	settings_b.custom_minimum_size = Vector2(190, 48)
	row2.add_child(settings_b)
	var quit_b := _button("ВЫХОД", _quit)
	quit_b.custom_minimum_size = Vector2(190, 48)
	row2.add_child(quit_b)
	menu_fade.append(settings_b)
	menu_fade.append(quit_b)
	var controls := _centered(_label(
		"← → / A D / мышь — поворот   •   Shift — спринт\nПробел / ЛКМ — атака съеденного медведя   •   Esc — пауза",
		15, Color(0.85, 0.8, 0.72)))
	box.add_child(controls)
	menu_fade.append(controls)
	tip_label = _label("", 19, Color(1, 0.95, 0.8), true)
	tip_label.position = Vector2(640, 26)
	tip_label.size = Vector2(610, 30)
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(tip_label)


## Заголовок «ЗМЕЯ»: буквы падают по очереди, потом прыгают волной и переливаются;
## под ними ползёт змейка с языком.
func _draw_title_art() -> void:
	var c := title_art
	var text := "ЗМЕЯ"
	var fs := 96
	var widths: Array[float] = []
	var total := 0.0
	for ch in text:
		var w := title_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w + 6.0)
		total += w + 6.0
	var x := (c.size.x - total) / 2.0
	var x0 := x
	for i in text.length():
		var k := clampf((menu_intro - 0.3 - i * 0.12) / 0.45, 0.0, 1.0)
		if k <= 0.0:
			x += widths[i]
			continue
		var drop := -170.0 * pow(1.0 - k, 2.0)
		var bounce := sin(t * 3.2 - i * 0.8) * 7.0 * k
		var col := Color.from_hsv(0.29 + 0.05 * sin(t * 2.0 + i), 0.72, 0.97, k)
		c.draw_set_transform(Vector2(x + widths[i] / 2.0, 92.0 + drop + bounce), sin(t * 2.4 + i * 1.3) * 0.07, Vector2.ONE)
		var off := Vector2(-widths[i] / 2.0 + 3.0, 0)
		c.draw_string_outline(title_font, off + Vector2(4, 5), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color(0, 0, 0, 0.35 * k))
		c.draw_string_outline(title_font, off, text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color(0.05, 0.2, 0.05, k))
		c.draw_string(title_font, off, text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		c.draw_string(title_font, off + Vector2(0, -3), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.12 * k))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		x += widths[i]
	# змейка-подчёркивание
	var k := clampf((menu_intro - 0.9) / 0.6, 0.0, 1.0)
	if k <= 0.0:
		return
	var pts := PackedVector2Array()
	var len := total * k
	for i in 40:
		var px := x0 + len * i / 39.0
		pts.append(Vector2(px, 112.0 + sin(px * 0.045 - t * 6.0) * 5.0))
	c.draw_polyline(pts, Color(0.08, 0.3, 0.1), 13.0)
	c.draw_polyline(pts, Color(0.4, 0.88, 0.35), 9.0)
	var head := pts[pts.size() - 1]
	c.draw_circle(head, 9.0, Color(0.08, 0.3, 0.1))
	c.draw_circle(head, 7.0, Color(0.45, 0.92, 0.4))
	c.draw_circle(head + Vector2(2, -3), 2.2, Color.WHITE)
	c.draw_circle(head + Vector2(2.6, -3), 1.1, Color.BLACK)
	if fmod(t, 1.6) < 0.35:
		c.draw_line(head + Vector2(8, 0), head + Vector2(18, 0), Color(0.85, 0.1, 0.2), 2.0)
		c.draw_line(head + Vector2(18, 0), head + Vector2(22, -3), Color(0.85, 0.1, 0.2), 1.5)
		c.draw_line(head + Vector2(18, 0), head + Vector2(22, 3), Color(0.85, 0.1, 0.2), 1.5)


func _build_end() -> void:
	end_box = _center_box()
	var box := _panel(end_box)
	end_title = _centered(_label("", 64, GOLD, true))
	box.add_child(end_title)
	end_stats = _centered(_label("", 24, Color.WHITE))
	box.add_child(end_stats)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	end_first_button = _button("ЕЩЁ РАЗ", retry_pressed.emit)
	row.add_child(end_first_button)
	row.add_child(_button("В МЕНЮ", menu_pressed.emit))


func _build_pause() -> void:
	pause_box = _center_box()
	var box := _panel(pause_box)
	box.add_child(_centered(_label("ПАУЗА", 60, GOLD, true)))
	pause_first_button = _button("ПРОДОЛЖИТЬ", _set_paused.bind(false))
	box.add_child(pause_first_button)
	box.add_child(_button("НАСТРОЙКИ", _open_settings.bind(pause_box)))
	box.add_child(_button("В МЕНЮ", menu_pressed.emit))


func _build_settings() -> void:
	settings_box = _center_box()
	var box := _panel(settings_box)
	box.add_child(_centered(_label("НАСТРОЙКИ", 52, GOLD, true)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	_section(grid, "ЗВУК")
	settings_first = _slider_row(grid, "Общая громкость", "master")
	_slider_row(grid, "Музыка", "music")
	_slider_row(grid, "Звуковые эффекты", "sfx")
	_section(grid, "ИГРА")
	_slider_row(grid, "Тряска экрана", "shake")
	_check_row(grid, "Поворот за мышью", "mouse_control")
	_check_row(grid, "Показывать FPS", "show_fps")
	_section(grid, "ЭКРАН")
	_check_row(grid, "Полный экран", "fullscreen")
	_check_row(grid, "Вертикальная синхронизация", "vsync")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	reset_button = _button("СБРОСИТЬ РЕКОРДЫ", _on_reset_pressed)
	reset_button.custom_minimum_size = Vector2(330, 54)
	row.add_child(reset_button)
	var back := _button("НАЗАД", _close_settings)
	back.custom_minimum_size = Vector2(210, 54)
	row.add_child(back)


func _section(grid: GridContainer, text: String) -> void:
	grid.add_child(_label(text, 16, GOLD, true))
	grid.add_child(Control.new())


func _slider_row(grid: GridContainer, text: String, key: String) -> HSlider:
	grid.add_child(_label(text, 21, Color(1, 0.95, 0.88)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	grid.add_child(row)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(260, 30)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = _get_setting(key)
	row.add_child(slider)
	var value := _label("", 19, Color.WHITE, true)
	value.custom_minimum_size = Vector2(64, 0)
	value.text = _percent(slider.value)
	row.add_child(value)
	slider.value_changed.connect(func(v: float) -> void:
		value.text = _percent(v)
		_set_setting(key, v))
	slider.focus_entered.connect(_sound.bind("ui_move"))
	return slider


func _percent(v: float) -> String:
	return str(roundi(v * 100.0)) + "%"


func _check_row(grid: GridContainer, text: String, key: String) -> CheckButton:
	grid.add_child(_label(text, 21, Color(1, 0.95, 0.88)))
	var check := CheckButton.new()
	check.button_pressed = _get_setting(key)
	check.text = "ВКЛ" if check.button_pressed else "ВЫКЛ"
	check.add_theme_font_override("font", title_font)
	check.add_theme_font_size_override("font_size", 19)
	check.toggled.connect(func(on: bool) -> void:
		check.text = "ВКЛ" if on else "ВЫКЛ"
		_sound("ui_select")
		_set_setting(key, on))
	check.focus_entered.connect(_sound.bind("ui_move"))
	grid.add_child(check)
	return check


func _get_setting(key: String) -> Variant:
	match key:
		"master": return Settings.master
		"music": return Settings.music
		"sfx": return Settings.sfx
		"shake": return Settings.shake
		"mouse_control": return Settings.mouse_control
		"show_fps": return Settings.show_fps
		"fullscreen": return Settings.fullscreen
		"vsync": return Settings.vsync
	return null


func _set_setting(key: String, v: Variant) -> void:
	match key:
		"master": Settings.master = v
		"music": Settings.music = v
		"sfx":
			Settings.sfx = v
			_sound("eat")  # проба громкости
		"shake": Settings.shake = v
		"mouse_control": Settings.mouse_control = v
		"show_fps": Settings.show_fps = v
		"fullscreen": Settings.fullscreen = v
		"vsync": Settings.vsync = v
	Settings.apply_audio()
	if key == "fullscreen" or key == "vsync":
		Settings.apply_video()


func _open_settings(from: CenterContainer) -> void:
	settings_return = from
	reset_armed = false
	reset_button.text = "СБРОСИТЬ РЕКОРДЫ"
	_show_only(settings_box)
	settings_first.grab_focus.call_deferred()


func _close_settings() -> void:
	Settings.save()
	_show_only(settings_return)
	if settings_return == menu_box:
		diff_buttons[1].grab_focus.call_deferred()
	elif settings_return == pause_box:
		pause_first_button.grab_focus.call_deferred()


func _on_reset_pressed() -> void:
	if not reset_armed:
		reset_armed = true
		reset_button.text = "ТОЧНО? ЖМИ ЕЩЁ РАЗ"
		return
	reset_armed = false
	reset_button.text = "РЕКОРДЫ СБРОШЕНЫ"
	records_reset.emit()


func set_best_scores(bests: Array) -> void:
	best_scores = bests


func _quit() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()


# ---------------------------------------------------------------- показ экранов

func _show_only(which: CenterContainer) -> void:
	for c in [menu_box, end_box, pause_box, settings_box]:
		c.visible = c == which
	dim.visible = which != null and which != menu_box  # в меню видна живая демо-арена


func show_menu(diffs: Array, bests: Array, selected: int) -> void:
	difficulties = diffs
	best_scores = bests
	in_game = false
	game_ui.visible = false
	for i in diff_buttons.size():
		var d: Dictionary = diffs[i]
		var b := diff_buttons[i]
		b.text = d["name"]
		var col: Color = d["color"]
		b.add_theme_stylebox_override("normal", _box(col.darkened(0.55), col, 14, 3))
		b.add_theme_stylebox_override("hover", _box(col.darkened(0.3), Color.WHITE, 14, 3))
		b.add_theme_stylebox_override("pressed", _box(col.darkened(0.7), Color.WHITE, 14, 3))
	_show_only(menu_box)
	diff_buttons[selected].grab_focus.call_deferred()
	_show_desc(selected)
	# вступительная анимация: панель выезжает, буквы падают, кнопки проявляются
	menu_intro = 0.0
	menu_box.position.x = -700.0
	var tw := create_tween()
	tw.tween_property(menu_box, "position:x", 24.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in menu_fade.size():
		var c := menu_fade[i]
		c.modulate.a = 0.0
		create_tween().tween_property(c, "modulate:a", 1.0, 0.3).set_delay(0.9 + i * 0.08)
	tip_index = randi() % TIPS.size()
	_next_tip()


func _next_tip() -> void:
	tip_index = (tip_index + 1) % TIPS.size()
	tip_t = 4.5
	tip_label.text = "СОВЕТ: " + TIPS[tip_index]
	tip_label.modulate.a = 0.0
	create_tween().tween_property(tip_label, "modulate:a", 1.0, 0.4)


func _show_desc(i: int) -> void:
	if difficulties.is_empty():
		return
	var d: Dictionary = difficulties[i]
	var best: int = best_scores[i]
	desc_label.text = "%s\nРекорд: %d" % [d["desc"], best]
	desc_label.label_settings.font_color = (d["color"] as Color).lightened(0.4)


func show_game(diff_name: String, diff_color: Color, lives_max: int) -> void:
	_show_only(null)
	in_game = true
	game_ui.visible = true
	max_lives = lives_max
	lives = lives_max
	diff_label.text = diff_name
	diff_label.label_settings.font_color = diff_color
	score_shown = 0.0
	score_target = 0


func show_end(win: bool, stats: String, title := "") -> void:
	pause_allowed = false
	end_title.text = title if title != "" else ("ПОБЕДА!" if win else "ЗМЕЯ ПОВЕРЖЕНА")
	end_title.label_settings.font_color = Color(0.5, 1, 0.45) if win else Color(1, 0.4, 0.3)
	if title != "":
		end_title.label_settings.font_color = Color(1, 0.55, 0.3)
	end_stats.text = stats
	_show_only(end_box)
	end_first_button.grab_focus.call_deferred()


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if paused:
		_show_only(pause_box)
		pause_first_button.grab_focus.call_deferred()
	else:
		_show_only(null)


func _toggle_mute() -> void:
	if sfx:
		sfx.toggle_mute()
	if not pause_box.visible and not settings_box.visible:
		show_banner("Звук выключен" if _is_muted() else "Звук включён", Color(0.8, 0.9, 1), 0.8)


func _is_muted() -> bool:
	return sfx != null and sfx.is_muted()


func _sound(sound_name: String) -> void:
	if sfx:
		sfx.play(sound_name)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if settings_box.visible:
			_close_settings()
		elif pause_box.visible:
			_set_paused(false)
		elif pause_allowed:
			_set_paused(true)
		else:
			return  # Esc нужен игре (например, пропустить катсцену)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("mute"):
		_toggle_mute()


# ---------------------------------------------------------------- данные

func set_ability(type: int, ability_title: String, count: int) -> void:
	if type != ability_type or count > ability_charges:
		ability_flash = 1.0
	ability_type = type
	ability_name = ability_title
	ability_charges = count


func show_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = true
	prompt_label.modulate.a = 0.0
	create_tween().tween_property(prompt_label, "modulate:a", 1.0, 0.4)


func hide_prompt() -> void:
	prompt_label.visible = false


func set_cinematic(on: bool) -> void:
	cinematic = on
	if on:
		in_game = false
		game_ui.visible = false
		boss_visible = false
	skip_label.visible = on
	create_tween().tween_property(self, "cine", 1.0 if on else 0.0, 1.0)


func show_caption(speaker: String, text: String) -> void:
	speaker_label.text = speaker
	speaker_label.visible = speaker != ""
	caption_label.text = text
	if caption_tween:
		caption_tween.kill()
	caption_box.modulate.a = 0.0
	caption_tween = create_tween()
	caption_tween.tween_property(caption_box, "modulate:a", 1.0, 0.35)


func hide_caption() -> void:
	if caption_tween:
		caption_tween.kill()
	caption_tween = create_tween()
	caption_tween.tween_property(caption_box, "modulate:a", 0.0, 0.4)


func set_score(value: int) -> void:
	score_target = value


func set_bears(eaten: int, total: int) -> void:
	bears_eaten = eaten
	bears_total = total
	bears_label.text = "%d/%d" % [eaten, total] if total > 0 else ""


func set_lives(value: int) -> void:
	if value < lives:
		heart_anim = 1.0
		hurt_flash = 1.0
	lives = value


func set_boss(visible_bar: bool, hp: int = 0, max_hp: int = 1, phase: int = 1) -> void:
	if visible_bar and not boss_visible:
		boss_hp_shown = 0.0
		boss_hp_ghost = 0.0
	elif hp < boss_hp:
		boss_flash = 1.0
	boss_visible = visible_bar
	boss_hp = hp
	boss_max = max_hp
	boss_phase = phase


func show_banner(text: String, color := Color(1, 0.55, 0.25), duration := 2.0) -> void:
	if banner_tween:
		banner_tween.kill()
	banner.text = text
	banner.label_settings.font_color = color
	banner.modulate.a = 0.0
	banner.scale = Vector2(1.6, 1.6)
	banner_tween = create_tween()
	banner_tween.tween_property(banner, "modulate:a", 1.0, 0.15)
	banner_tween.parallel().tween_property(banner, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_tween.tween_interval(duration)
	banner_tween.tween_property(banner, "modulate:a", 0.0, 0.4)


func _process(delta: float) -> void:
	t += delta
	heart_anim = maxf(heart_anim - delta * 2.0, 0.0)
	hurt_flash = maxf(hurt_flash - delta * 3.0, 0.0)
	boss_flash = maxf(boss_flash - delta * 3.0, 0.0)
	score_shown = move_toward(score_shown, score_target, maxf(delta * 600.0, absf(score_target - score_shown) * delta * 6.0))
	score_label.text = str(int(score_shown))
	boss_hp_shown = move_toward(boss_hp_shown, boss_hp, delta * 8.0)
	boss_hp_ghost = move_toward(boss_hp_ghost, boss_hp_shown, delta * (1.5 if boss_hp_ghost > boss_hp_shown else 20.0))
	ability_flash = maxf(ability_flash - delta * 2.0, 0.0)
	if menu_box.visible:
		menu_intro += delta
		menu_title.rotation = sin(t * 2.0) * 0.03
		menu_title.scale = Vector2.ONE * (1.0 + 0.04 * sin(t * 3.0))
		title_art.queue_redraw()
		tip_t -= delta
		if tip_t <= 0.0:
			_next_tip()
	tip_label.visible = menu_box.visible
	if prompt_label.visible:
		prompt_label.scale = Vector2.ONE * (1.0 + 0.05 * sin(t * 6.0))
	fps_label.visible = Settings.show_fps
	if fps_label.visible:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	version_label.visible = menu_box.visible or (settings_box.visible and settings_return == menu_box)
	var covered := false
	if in_game:
		for r in _panel_rects():
			if r.grow(30).has_point(snake_head):
				covered = true
	var a := 0.35 if covered else 1.0
	overlay.modulate.a = move_toward(overlay.modulate.a, a, delta * 4.0)
	game_ui.modulate.a = overlay.modulate.a
	overlay.queue_redraw()


func _panel_rects() -> Array[Rect2]:
	var w := maxi(max_lives, 3) * 40 + 36
	var rects: Array[Rect2] = [Rect2(16, 14, 340, 116), Rect2(1280 - 16 - w, 14, w, 84)]
	if ability_type >= 0:
		rects.append(Rect2(1280 - 16 - 270, 106, 270, 58))
	if boss_visible:
		rects.append(Rect2(250, 634, 780, 70))
	return rects


# ---------------------------------------------------------------- рисование

func _on_overlay_draw() -> void:
	if hurt_flash > 0.0:
		overlay.draw_rect(Rect2(0, 0, 1280, 720), Color(0.9, 0.05, 0.05, 0.2 * hurt_flash))
	if cine > 0.0:  # киношные полосы
		overlay.draw_rect(Rect2(0, 0, 1280, 84 * cine), Color.BLACK)
		overlay.draw_rect(Rect2(0, 720 - 84 * cine, 1280, 84 * cine), Color.BLACK)
	if not in_game:
		return

	var panel := _box(PANEL_BG, Color(0.55, 0.38, 0.2), 16, 3)
	# Слева: счёт и медведи
	overlay.draw_style_box(panel, Rect2(16, 14, 340, 116 if bears_total > 0 else 82))
	if bears_total > 0:
		_draw_bear_icon(Vector2(46, 101))
		_draw_bar(Rect2(66, 94, 208, 14), float(bears_eaten) / bears_total, Color(0.75, 0.5, 0.28), Color(0.95, 0.75, 0.5))

	# Справа: жизни и рывок
	var w := maxi(max_lives, 3) * 40 + 36
	var x0 := 1280.0 - 16.0 - w
	overlay.draw_style_box(panel, Rect2(x0, 14, w, 84))
	for i in max_lives:
		var c := Vector2(x0 + 38 + i * 40, 44)
		var alive := i < lives
		var s := 12.0
		if alive and lives == 1:
			s *= 1.0 + 0.12 * sin(t * 9.0)
		_draw_heart(c, s + 3.0, Color(0.15, 0.02, 0.05))
		_draw_heart(c, s, Color(0.95, 0.15, 0.25) if alive else Color(0.35, 0.3, 0.3, 0.7))
		if alive:
			overlay.draw_circle(c + Vector2(-s * 0.55, -s * 0.35), s * 0.2, Color(1, 1, 1, 0.5))
		elif i == lives and heart_anim > 0.0:  # только что потерянное сердце улетает
			_draw_heart(c + Vector2(0, -20.0 * (1.0 - heart_anim)), s * (1.0 + (1.0 - heart_anim)),
				Color(1, 0.2, 0.3, heart_anim))
	# стамина: при истощении мигает красным
	var st_col := Color(0.3, 0.8, 0.35)
	var st_top := Color(0.6, 1, 0.6)
	if exhausted:
		st_col = Color(0.9, 0.2, 0.15) if int(t * 6.0) % 2 == 0 else Color(0.6, 0.12, 0.1)
		st_top = Color(1, 0.5, 0.4)
	_draw_bar(Rect2(x0 + 20, 74, w - 40, 10), stamina, st_col, st_top)
	if ability_type >= 0:
		_draw_ability_panel()

	if boss_visible:
		_draw_boss_bar()


func _draw_ability_panel() -> void:
	var r := Rect2(1280 - 16 - 270, 106, 270, 58)
	var border := Color(0.55, 0.38, 0.2).lerp(Color(0.5, 1, 0.5), ability_flash)
	overlay.draw_style_box(_box(PANEL_BG, border, 14, 3), r)
	_draw_ability_icon(r.position + Vector2(32, 30), ability_type)
	var font := title_font
	overlay.draw_string_outline(font, r.position + Vector2(60, 26), ability_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0.1, 0.05, 0.02))
	overlay.draw_string(font, r.position + Vector2(60, 26), ability_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.6, 1, 0.6))
	overlay.draw_string(body_font, r.position + Vector2(60, 48), "Пробел / ЛКМ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.8, 0.72))
	var cnt := "×%d" % ability_charges
	overlay.draw_string_outline(font, r.position + Vector2(196, 44), cnt, HORIZONTAL_ALIGNMENT_RIGHT, 60, 26, 5, Color(0.1, 0.05, 0.02))
	overlay.draw_string(font, r.position + Vector2(196, 44), cnt, HORIZONTAL_ALIGNMENT_RIGHT, 60, 26, Color.WHITE)


func _draw_ability_icon(c: Vector2, type: int) -> void:
	_draw_bear_icon(c)
	match type:
		1:  # боксёр — перчатка
			overlay.draw_circle(c + Vector2(10, 7), 6.0, Color(0.55, 0.05, 0.05))
			overlay.draw_circle(c + Vector2(10, 7), 5.0, Color(0.92, 0.15, 0.12))
		2:  # метатель — пуговица
			overlay.draw_circle(c + Vector2(10, 8), 6.0, Color(0.2, 0.35, 0.7))
			overlay.draw_circle(c + Vector2(10, 8), 5.0, Color(0.3, 0.55, 0.95))
		3:  # каратист — чёрная повязка
			overlay.draw_line(c + Vector2(-9, -5), c + Vector2(9, -5), Color(0.08, 0.08, 0.08), 3.0)
			overlay.draw_line(c + Vector2(-9, -5), c + Vector2(-14, 0), Color(0.08, 0.08, 0.08), 2.0)
		4:  # швея — иголка
			overlay.draw_line(c + Vector2(4, 14), c + Vector2(16, 0), Color(0.85, 0.87, 0.92), 2.0)
			overlay.draw_circle(c + Vector2(4, 14), 3.5, Color(0.95, 0.8, 0.2))


func _draw_boss_bar() -> void:
	var font := title_font
	var frame := Rect2(250, 634, 780, 70)
	overlay.draw_style_box(_box(PANEL_BG, PHASE_COLORS[boss_phase - 1], 16, 3), frame)
	overlay.draw_string_outline(font, Vector2(274, 660), "ГИГАНТСКАЯ ЯИЧНИЦА", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0.1, 0.05, 0.02))
	overlay.draw_string(font, Vector2(274, 660), "ГИГАНТСКАЯ ЯИЧНИЦА", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.92, 0.6))
	var phase_text := "ФАЗА %d" % boss_phase
	overlay.draw_string(font, Vector2(806, 660), phase_text, HORIZONTAL_ALIGNMENT_RIGHT, 200, 18, PHASE_COLORS[boss_phase - 1])
	var bar := Rect2(272, 670, 736, 20)
	overlay.draw_rect(bar.grow(2), Color(0.05, 0.02, 0.01))
	overlay.draw_rect(bar, Color(0.25, 0.12, 0.08))
	var ghost := bar
	ghost.size.x *= clampf(boss_hp_ghost / boss_max, 0.0, 1.0)
	overlay.draw_rect(ghost, Color(1, 0.95, 0.85, 0.8))
	var fill := bar
	fill.size.x *= clampf(boss_hp_shown / boss_max, 0.0, 1.0)
	var col: Color = PHASE_COLORS[boss_phase - 1]
	overlay.draw_rect(fill, col.lerp(Color.WHITE, boss_flash * 0.7))
	overlay.draw_rect(Rect2(fill.position, Vector2(fill.size.x, 6)), Color(1, 1, 1, 0.3))
	for k in [1.0 / 3.0, 2.0 / 3.0]:
		var x: float = bar.position.x + bar.size.x * k
		overlay.draw_line(Vector2(x, bar.position.y - 2), Vector2(x, bar.end.y + 2), Color(0.05, 0.02, 0.01), 3.0)


func _draw_bar(r: Rect2, value: float, col: Color, top: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.03, 0.02, 0.85)
	bg.set_corner_radius_all(int(r.size.y / 2))
	overlay.draw_style_box(bg, r.grow(2))
	if value <= 0.0:
		return
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(int(r.size.y / 2))
	var fr := Rect2(r.position, Vector2(maxf(r.size.x * clampf(value, 0.0, 1.0), r.size.y), r.size.y))
	overlay.draw_style_box(fill, fr)
	overlay.draw_rect(Rect2(fr.position + Vector2(r.size.y / 2, 2), Vector2(maxf(fr.size.x - r.size.y, 0), 3)), top)


func _draw_bear_icon(c: Vector2) -> void:
	var fur := Color(0.72, 0.5, 0.3)
	for s in [-1.0, 1.0]:
		overlay.draw_circle(c + Vector2(s * 8, -8), 5.0, fur.darkened(0.3))
	overlay.draw_circle(c, 10.0, fur)
	overlay.draw_circle(c + Vector2(0, 3), 4.5, fur.lightened(0.35))
	overlay.draw_circle(c + Vector2(0, 1.5), 1.8, Color(0.15, 0.08, 0.05))
	for s in [-1.0, 1.0]:
		overlay.draw_circle(c + Vector2(s * 4, -3), 1.6, Color.BLACK)


func _draw_heart(c: Vector2, s: float, col: Color) -> void:
	overlay.draw_circle(c + Vector2(-s * 0.5, -s * 0.2), s * 0.55, col)
	overlay.draw_circle(c + Vector2(s * 0.5, -s * 0.2), s * 0.55, col)
	overlay.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-s * 1.03, 0), c + Vector2(s * 1.03, 0), c + Vector2(0, s * 1.1)]), col)
