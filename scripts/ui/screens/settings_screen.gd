extends "res://scripts/ui/screens/screen.gd"
## Настройки: вкладки ЗВУК · ЭКРАН · ИГРА · УПРАВЛЕНИЕ · ДОСТУПНОСТЬ. Строки строятся по
## Settings.SCHEMA приборными контролами: рычажный тумблер (вкл/выкл), крутилка (громкости),
## фейдер (прочие числа), галетный переключатель (варианты). Внизу — сбросы (опасный — под
## откидной крышкой) и номер версии (7 нажатий на версию включают режим разработчика).

signal records_reset
signal setting_changed(key: String)
signal dev_mode_unlocked

const Segmented = preload("res://scripts/ui/widgets/segmented.gd")
const ToggleSwitch = preload("res://scripts/ui/widgets/toggle_switch.gd")
const RotaryKnob = preload("res://scripts/ui/widgets/rotary_knob.gd")
const Fader = preload("res://scripts/ui/widgets/fader.gd")
const RotarySwitch = preload("res://scripts/ui/widgets/rotary_switch.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const Platform = preload("res://scripts/core/platform.gd")

const DEV_TAPS := 7

var tabs: Segmented
var pages: Dictionary = {}  # id вкладки -> HBoxContainer (две колонки строк)
var controls: Dictionary = {}  # key -> контрол (для обновления после сброса)
var value_labels: Dictionary = {}  # key -> подпись значения у крутилки/фейдера
var reset_records_button: Button
var reset_settings_button: Button
var version_button: Button
var records_armed := false
var settings_armed := false
var dev_taps := 0
var current_tab := 0
var preview: TouchControls  # живая витрина сенсорных кнопок за панелью (вкладка УПРАВЛЕНИЕ)
var _shake_tween: Tween


const COLUMN_W := 380.0  # ширина одной колонки пульта
const FADER_W := 136.0


## Компактный пульт (v7.2): шапка с латунной табличкой версии, клавиши-вкладки на всю ширину,
## строки — в утопленной приборной нише двумя колонками с гравированными разделителями.
## Самая длинная вкладка (9 строк) помещается без прокрутки на 100% масштаба.
func build() -> void:
	preview = TouchControls.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview)  # раньше панели: панель рисуется поверх, кнопки выглядывают по краям экрана
	preview.start_preview()
	preview.visible = false
	resized.connect(_fit_preview)
	make_frame(Design.SPACE[3], Design.plank(Color(0, 0, 0, 0), Design.RADIUS_LG, Vector2(Design.SPACE[5], Design.SPACE[4])))
	var head := Design.hbox(Design.SPACE[3], BoxContainer.ALIGNMENT_BEGIN)
	content.add_child(head)
	var t := Design.label("НАСТРОЙКИ", "h2", Design.YOLK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	version_button = Design.button("", _on_version_tap, "Ghost", Vector2(0, 36))
	version_button.add_theme_font_size_override("font_size", Design.size_of("caption"))
	version_button.focus_mode = Control.FOCUS_NONE
	version_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(version_button)
	var names: Array = []
	for tab: Dictionary in Settings.TABS:
		names.append(tab["name"])
	tabs = Segmented.new()
	tabs.setup(names, 0, 0.0, true)
	for b in tabs.buttons:
		b.add_theme_font_size_override("font_size", Design.size_of("caption"))
	tabs.changed.connect(_show_tab)
	content.add_child(tabs)
	var bay := PanelContainer.new()  # приборная ниша, в ней видна одна страница
	bay.add_theme_stylebox_override("panel", Design.well(Design.RADIUS_MD, Vector2(Design.SPACE[4], Design.SPACE[2])))
	content.add_child(bay)
	var stack := Design.vbox(0)
	bay.add_child(stack)
	var rows: Dictionary = {}  # id вкладки -> строки схемы
	for tab: Dictionary in Settings.TABS:
		rows[tab["id"]] = []
	for s: Dictionary in Settings.SCHEMA:
		if s["tab"] != "" and Settings.visible_here(s):
			rows[s["tab"]].append(s)
	for tab: Dictionary in Settings.TABS:
		var page := Design.hbox(Design.SPACE[5], BoxContainer.ALIGNMENT_BEGIN)
		stack.add_child(page)
		pages[tab["id"]] = page
		var list: Array = rows[tab["id"]]
		var half := ceili(list.size() / 2.0)  # колонки заполняются сверху вниз
		for c in 2:
			var col := Design.vbox(0)
			col.custom_minimum_size = Vector2(COLUMN_W, 0)
			col.alignment = BoxContainer.ALIGNMENT_BEGIN
			page.add_child(col)
			for i in range(c * half, mini((c + 1) * half, list.size())):
				if i > c * half:
					col.add_child(_engraving())
				_add_row(col, list[i])
	var foot := Design.hbox(Design.SPACE[3], BoxContainer.ALIGNMENT_BEGIN)
	content.add_child(foot)
	reset_settings_button = Design.button("СБРОС НАСТРОЕК", _on_reset_settings, "Ghost", Vector2(196, Design.TOUCH_MIN))
	foot.add_child(reset_settings_button)
	reset_records_button = Design.button("СБРОС РЕКОРДОВ", _on_reset_records, "Danger", Vector2(196, Design.TOUCH_MIN))
	foot.add_child(reset_records_button)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var done := Design.button("ГОТОВО", closed.emit, "Primary", Vector2(176, Design.TOUCH_MIN))
	foot.add_child(done)
	for b in [reset_settings_button, reset_records_button, done]:
		b.add_theme_font_size_override("font_size", Design.size_of("small"))
	_show_tab(0)


## Гравированная риска между строками: тёмная борозда и светлая кромка под ней.
func _engraving() -> Control:
	var line := Control.new()
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func() -> void:
		line.draw_line(Vector2(0, 0.5), Vector2(line.size.x, 0.5), Color(0, 0, 0, 0.45), 1.0)
		line.draw_line(Vector2(0, 1.5), Vector2(line.size.x, 1.5), Color(Design.CREAM, 0.06), 1.0))
	return line


func _add_row(page: VBoxContainer, s: Dictionary) -> void:
	var key: String = s["key"]
	var row := Design.hbox(Design.SPACE[3], BoxContainer.ALIGNMENT_BEGIN)
	row.custom_minimum_size = Vector2(0, Design.TOUCH_MIN)
	var l := Design.label(s["label"], "small", Design.CREAM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD  # переносить только по словам — не «Чувствительнос-ть»
	l.custom_minimum_size.x = 120.0
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	match s["kind"]:
		Settings.Kind.BOOL:
			var sw := ToggleSwitch.new()
			sw.set_on(Settings.flag(key))
			sw.toggled.connect(func(on: bool) -> void: _apply(key, on))
			row.add_child(sw)
			controls[key] = sw
		Settings.Kind.FLOAT:
			var box := Design.hbox(Design.SPACE[2], BoxContainer.ALIGNMENT_END)
			var ctl: Range = RotaryKnob.new() if s["tab"] == "sound" else Fader.new()
			if ctl is Fader:
				ctl.custom_minimum_size.x = FADER_W
			ctl.min_value = s.get("min", 0.0)
			ctl.max_value = s.get("max", 1.0)
			ctl.step = s.get("step", 0.05)
			ctl.set_value_no_signal(Settings.num(key))
			if ctl is RotaryKnob:
				ctl.default_value = float(s["default"])
			var value := Design.label(_fmt(key, ctl.value), "readout", Design.YOLK, HORIZONTAL_ALIGNMENT_RIGHT)
			value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			var window := PanelContainer.new()  # окошко счётчика: цифры под стеклом
			window.add_theme_stylebox_override("panel", Design.well(Design.RADIUS_SM, Vector2(Design.SPACE[2], 2)))
			window.custom_minimum_size = Vector2(58, 28)
			window.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			window.add_child(value)
			ctl.value_changed.connect(func(v: float) -> void:
				value.text = _fmt(key, v)
				_apply(key, v))
			box.add_child(ctl)
			box.add_child(window)
			row.add_child(box)
			controls[key] = ctl
			value_labels[key] = value
		Settings.Kind.ENUM:
			var sw := RotarySwitch.new()
			sw.setup(s["options"], Settings.choice(key))
			sw.changed.connect(func(i: int) -> void: _apply(key, i))
			row.add_child(sw)
			controls[key] = sw
	page.add_child(row)


func _fmt(key: String, v: float) -> String:
	if key == "turn_sensitivity":
		return "×%.2f" % v
	return str(roundi(v * 100.0)) + "%"


var _last_probe := 0


func _apply(key: String, v: Variant) -> void:
	Settings.set_value(key, v)
	_probe(key, v)
	_update_preview()
	setting_changed.emit(key)


## Настройка отзывается сразу: громкость — звуком, вибрация — толчком, тряска — качнувшейся панелью.
func _probe(key: String, v: Variant) -> void:
	if key in ["master", "sfx", "ambient"] and Time.get_ticks_msec() - _last_probe > 150:
		_last_probe = Time.get_ticks_msec()
		Design.play("crackle" if key == "ambient" else "eat")
	elif key == "vibration" and v:
		Platform.vibrate(40, true)
	elif key == "shake" and not Settings.flag("reduced_motion"):
		_shake_panel(float(v))


func _shake_panel(k: float) -> void:
	if panel == null or k <= 0.0:
		return
	if _shake_tween:
		_shake_tween.kill()
	panel.pivot_offset = panel.size / 2.0
	_shake_tween = create_tween()  # покачивание, а не сдвиг: контейнер возвращает сдвинутую панель на место
	for i in 4:
		_shake_tween.tween_property(panel, "rotation", (-1.0 if i % 2 == 0 else 1.0) * 0.012 * k * (1.0 - i * 0.22), 0.04)
	_shake_tween.tween_property(panel, "rotation", 0.0, 0.05)


## Витрина видна на вкладке УПРАВЛЕНИЕ, пока сенсорное управление не выключено совсем.
func _update_preview() -> void:
	if preview == null:
		return
	preview.visible = visible and Settings.TABS[current_tab]["id"] == "controls" and Settings.choice("touch_mode") != 2
	_fit_preview()


## Витрина живёт в координатах экрана, а не масштабируемого интерфейса: кнопки стоят там же, что и в забеге.
func _fit_preview() -> void:
	if preview == null or not is_inside_tree():
		return
	var k := maxf(get_global_transform().get_scale().x, 0.01)
	preview.scale = Vector2.ONE / k
	preview.position = Vector2.ZERO
	preview.size = size * k


func _show_tab(i: int) -> void:
	current_tab = i
	_update_preview()
	var id: String = Settings.TABS[i]["id"]
	for k: String in pages:
		pages[k].visible = k == id
	fit.call_deferred()
	if scroll:
		scroll.scroll_vertical = 0


func open() -> void:
	records_armed = false
	settings_armed = false
	reset_records_button.text = "СБРОС РЕКОРДОВ"
	reset_settings_button.text = "СБРОС НАСТРОЕК"
	dev_taps = 0
	_update_version()
	first_focus = tabs.buttons[current_tab]
	super()
	_update_preview()


func _update_version() -> void:
	var v := "v" + str(ProjectSettings.get_setting("application/config/version", "6.0"))
	version_button.text = v + ("  •  DEV: F1 или </>" if Settings.flag("dev_mode") else "")


## Обновить контролы после сброса настроек.
func refresh() -> void:
	for key: String in controls:
		var c: Control = controls[key]
		if c is ToggleSwitch:
			c.set_on(Settings.flag(key))
		elif c is Range:
			var r := c as Range
			r.set_value_no_signal(Settings.num(key))
			r.set("last_detent", r.call("detent_index"))
			r.queue_redraw()
			(value_labels[key] as Label).text = _fmt(key, Settings.num(key))
		elif c.has_method("select"):
			c.select(Settings.choice(key))


func _on_reset_settings() -> void:
	if not settings_armed:
		settings_armed = true
		reset_settings_button.text = "ТОЧНО? ЖМИ ЕЩЁ"
		return
	settings_armed = false
	var dev: bool = Settings.flag("dev_mode")
	Settings.reset_to_defaults()
	Settings.values["dev_mode"] = dev
	Settings.apply_audio()
	Settings.apply_video()
	refresh()
	_update_preview()
	reset_settings_button.text = "НАСТРОЙКИ СБРОШЕНЫ"
	setting_changed.emit("*")


func _on_reset_records() -> void:
	if not records_armed:  # первое нажатие откидывает крышку
		records_armed = true
		reset_records_button.text = "ТОЧНО? ЖМИ ЕЩЁ"
		Design.set_cover(reset_records_button, true)
		return
	records_armed = false
	reset_records_button.text = "РЕКОРДЫ СБРОШЕНЫ"
	Design.set_cover(reset_records_button, false)
	records_reset.emit()


func _on_version_tap() -> void:
	if Settings.flag("dev_mode"):
		return
	dev_taps += 1
	if dev_taps >= DEV_TAPS:
		Settings.set_value("dev_mode", true)
		Settings.save()
		_update_version()
		dev_mode_unlocked.emit()
	elif dev_taps >= 3:
		version_button.text = "ещё %d — и ты разработчик" % (DEV_TAPS - dev_taps)


func close() -> void:
	Settings.save()
	super()
	_update_preview()
