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

const DEV_TAPS := 7

var tabs: Segmented
var pages: Dictionary = {}  # id вкладки -> VBoxContainer
var controls: Dictionary = {}  # key -> контрол (для обновления после сброса)
var value_labels: Dictionary = {}  # key -> подпись значения у крутилки/фейдера
var reset_records_button: Button
var reset_settings_button: Button
var version_button: Button
var records_armed := false
var settings_armed := false
var dev_taps := 0
var current_tab := 0


func build() -> void:
	make_frame(Design.SPACE[3])
	title("НАСТРОЙКИ", "h1")
	var names: Array = []
	for tab: Dictionary in Settings.TABS:
		names.append(tab["name"])
	tabs = Segmented.new()
	tabs.setup(names, 0, 0.0)
	tabs.changed.connect(_show_tab)
	var tabs_center := CenterContainer.new()
	tabs_center.add_child(tabs)
	content.add_child(tabs_center)
	var stack := Design.vbox(0)  # страницы вкладок, видна одна
	content.add_child(stack)
	for tab: Dictionary in Settings.TABS:
		var page := Design.vbox(Design.SPACE[1])
		page.custom_minimum_size = Vector2(680, 0)
		stack.add_child(page)
		pages[tab["id"]] = page
	for s: Dictionary in Settings.SCHEMA:
		if s["tab"] == "" or not Settings.visible_here(s):
			continue
		_add_row(pages[s["tab"]], s)
	content.add_child(HSeparator.new())
	var row := Design.hbox(Design.SPACE[3])
	content.add_child(row)
	reset_settings_button = Design.button("СБРОС НАСТРОЕК", _on_reset_settings, "Ghost", Vector2(210, Design.TOUCH_MIN))
	row.add_child(reset_settings_button)
	reset_records_button = Design.button("СБРОС РЕКОРДОВ", _on_reset_records, "Danger", Vector2(210, Design.TOUCH_MIN))
	row.add_child(reset_records_button)
	var done := Design.button("ГОТОВО", closed.emit, "Primary", Vector2(210, Design.TOUCH_MIN))
	row.add_child(done)
	version_button = Design.button("", _on_version_tap, "Ghost", Vector2(0, 36))
	version_button.add_theme_font_size_override("font_size", 13)
	version_button.focus_mode = Control.FOCUS_NONE
	content.add_child(version_button)
	_show_tab(0)


func _add_row(page: VBoxContainer, s: Dictionary) -> void:
	var key: String = s["key"]
	var row := Design.hbox(Design.SPACE[4], BoxContainer.ALIGNMENT_BEGIN)
	row.custom_minimum_size = Vector2(0, Design.TOUCH_MIN)
	var l := Design.label(s["label"], "body", Design.CREAM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
			var box := Design.hbox(Design.SPACE[3], BoxContainer.ALIGNMENT_END)
			var ctl: Range = RotaryKnob.new() if s["tab"] == "sound" else Fader.new()
			ctl.min_value = s.get("min", 0.0)
			ctl.max_value = s.get("max", 1.0)
			ctl.step = s.get("step", 0.05)
			ctl.set_value_no_signal(Settings.num(key))
			if ctl is RotaryKnob:
				ctl.default_value = float(s["default"])
			var value := Design.label(_fmt(key, ctl.value), "h3", Design.YOLK, HORIZONTAL_ALIGNMENT_RIGHT)
			value.custom_minimum_size = Vector2(64, 0)
			value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			ctl.value_changed.connect(func(v: float) -> void:
				value.text = _fmt(key, v)
				_apply(key, v))
			box.add_child(ctl)
			box.add_child(value)
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
	if key == "sfx" and Time.get_ticks_msec() - _last_probe > 150:  # проба громкости
		_last_probe = Time.get_ticks_msec()
		Design.play("eat")
	setting_changed.emit(key)


func _show_tab(i: int) -> void:
	current_tab = i
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


func _update_version() -> void:
	var v := "v" + str(ProjectSettings.get_setting("application/config/version", "6.0"))
	version_button.text = v + ("  •  режим разработчика включён — F1 или кнопка </>" if Settings.flag("dev_mode") else "")


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
