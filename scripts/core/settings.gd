extends RefCounted
## Настройки игры. Все ключи описаны одной таблицей SCHEMA: вкладка, тип, значение по умолчанию,
## диапазон и подпись. Экран настроек строится по ней же. Значения живут в static-переменных
## (переживают перезагрузку сцены) и хранятся в user://settings.cfg.

const Platform = preload("res://scripts/core/platform.gd")

const DEFAULT_PATH := "user://settings.cfg"
## Версия формата файла. 2 (v7.2): у масштаба интерфейса появилось положение 80%, индексы сдвинулись.
const FORMAT := 2
const UI_SCALES := [0.8, 0.9, 1.0, 1.15, 1.3]

enum Kind { BOOL, FLOAT, ENUM }

const TABS := [
	{"id": "sound", "name": "ЗВУК"},
	{"id": "screen", "name": "ЭКРАН"},
	{"id": "game", "name": "ИГРА"},
	{"id": "controls", "name": "УПРАВЛЕНИЕ"},
	{"id": "access", "name": "ДОСТУПНОСТЬ"},
]

## only: "mobile" / "desktop" — строка видна только на этой платформе.
## mobile — значение по умолчанию на телефоне, если отличается.
const SCHEMA := [
	{"key": "master", "tab": "sound", "kind": Kind.FLOAT, "default": 0.8, "label": "Общая громкость"},
	{"key": "music", "tab": "sound", "kind": Kind.FLOAT, "default": 0.7, "label": "Музыка"},
	{"key": "sfx", "tab": "sound", "kind": Kind.FLOAT, "default": 0.8, "label": "Звуковые эффекты"},
	{"key": "ambient", "tab": "sound", "kind": Kind.FLOAT, "default": 0.8, "label": "Фоновые звуки (огонь, дождь)"},
	{"key": "mute_unfocused", "tab": "sound", "kind": Kind.BOOL, "default": true, "label": "Тишина, когда игра свёрнута"},
	{"key": "vibration", "tab": "sound", "kind": Kind.BOOL, "default": true, "label": "Вибрация", "only": "mobile"},

	{"key": "fullscreen", "tab": "screen", "kind": Kind.BOOL, "default": false, "label": "Полный экран", "only": "desktop"},
	{"key": "vsync", "tab": "screen", "kind": Kind.BOOL, "default": true, "label": "Вертикальная синхронизация", "only": "desktop"},
	{"key": "fps_limit", "tab": "screen", "kind": Kind.ENUM, "default": 3, "mobile": 1,
		"options": ["30", "60", "120", "БЕЗ"], "label": "Лимит кадров"},
	{"key": "show_fps", "tab": "screen", "kind": Kind.BOOL, "default": false, "label": "Показывать FPS"},
	{"key": "particles", "tab": "screen", "kind": Kind.ENUM, "default": 2, "mobile": 1,
		"options": ["НИЗКО", "СРЕДНЕ", "ВЫСОКО"], "label": "Частицы"},
	{"key": "antialias", "tab": "screen", "kind": Kind.BOOL, "default": false, "label": "Сглаживание (MSAA)"},
	{"key": "ui_scale", "tab": "screen", "kind": Kind.ENUM, "default": 2, "mobile": 3,
		"options": ["80%", "90%", "100%", "115%", "130%"], "label": "Масштаб интерфейса"},
	{"key": "vignette", "tab": "screen", "kind": Kind.BOOL, "default": true, "label": "Виньетка по краям"},

	{"key": "hints", "tab": "game", "kind": Kind.BOOL, "default": true, "label": "Подсказки и обучение"},
	{"key": "score_popups", "tab": "game", "kind": Kind.BOOL, "default": true, "label": "Всплывающие очки"},
	{"key": "show_timer", "tab": "game", "kind": Kind.BOOL, "default": false, "label": "Таймер забега"},
	{"key": "subtitles", "tab": "game", "kind": Kind.BOOL, "default": true, "label": "Субтитры в финале"},
	{"key": "subtitle_size", "tab": "game", "kind": Kind.ENUM, "default": 1, "mobile": 2,
		"options": ["МЕЛКИЕ", "СРЕДНИЕ", "КРУПНЫЕ"], "label": "Размер субтитров"},
	{"key": "confirm_skip", "tab": "game", "kind": Kind.BOOL, "default": false, "label": "Подтверждать пропуск финала"},
	{"key": "pause_unfocused", "tab": "game", "kind": Kind.BOOL, "default": true, "label": "Пауза при сворачивании"},
	{"key": "confirm_quit", "tab": "game", "kind": Kind.BOOL, "default": true, "label": "Подтверждать выход из забега"},

	{"key": "mouse_control", "tab": "controls", "kind": Kind.BOOL, "default": true, "label": "Поворот за мышью", "only": "desktop"},
	{"key": "turn_sensitivity", "tab": "controls", "kind": Kind.FLOAT, "default": 1.0, "min": 0.6, "max": 1.4,
		"step": 0.05, "label": "Чувствительность поворота"},
	{"key": "touch_mode", "tab": "controls", "kind": Kind.ENUM, "default": 0,
		"options": ["АВТО", "ВКЛ", "ВЫКЛ"], "label": "Сенсорное управление"},
	{"key": "touch_scheme", "tab": "controls", "kind": Kind.ENUM, "default": 0,
		"options": ["ДЖОЙСТИК", "ПАЛЕЦ"], "label": "Схема: джойстик или палец ведёт змею"},
	{"key": "stick_floating", "tab": "controls", "kind": Kind.BOOL, "default": true, "label": "Плавающий джойстик"},
	{"key": "button_size", "tab": "controls", "kind": Kind.ENUM, "default": 1,
		"options": ["S", "M", "L"], "label": "Размер сенсорных кнопок"},
	{"key": "button_opacity", "tab": "controls", "kind": Kind.FLOAT, "default": 0.75, "min": 0.25, "max": 1.0,
		"step": 0.05, "label": "Прозрачность кнопок"},
	{"key": "left_handed", "tab": "controls", "kind": Kind.BOOL, "default": false, "label": "Для левши (кнопки слева)"},
	{"key": "double_tap_attack", "tab": "controls", "kind": Kind.BOOL, "default": true, "label": "Атака двойным тапом"},

	{"key": "shake", "tab": "access", "kind": Kind.FLOAT, "default": 1.0, "label": "Тряска экрана"},
	{"key": "hurt_flash", "tab": "access", "kind": Kind.BOOL, "default": true, "label": "Красная вспышка при уроне"},
	{"key": "reduced_motion", "tab": "access", "kind": Kind.BOOL, "default": false, "label": "Меньше анимации"},
	{"key": "high_contrast", "tab": "access", "kind": Kind.BOOL, "default": false, "label": "Контрастные предупреждения атак"},
	{"key": "colorblind", "tab": "access", "kind": Kind.BOOL, "default": false, "label": "Палитра для дальтоников"},

	{"key": "dev_mode", "tab": "", "kind": Kind.BOOL, "default": false, "label": "Режим разработчика"},
]

static var path := DEFAULT_PATH
static var values: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	load_from_disk()
	apply_video()


static func load_from_disk() -> void:
	_loaded = true
	reset_to_defaults()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	for s: Dictionary in SCHEMA:
		var key: String = s["key"]
		for section in cf.get_sections():  # ищем во всех секциях — так читаются и старые файлы (v5)
			if cf.has_section_key(section, key):
				var v: Variant = cf.get_value(section, key)
				if key == "ui_scale" and int(cf.get_value("meta", "format", 1)) < 2 and (v is int or v is float):
					v = int(v) + 1  # файл до v7.2: 0 было 90%, теперь 0 — это 80%
				values[key] = sanitize(key, v)
				break


static func save() -> void:
	var cf := ConfigFile.new()
	for s: Dictionary in SCHEMA:
		var section: String = s["tab"] if s["tab"] != "" else "dev"
		cf.set_value(section, s["key"], values[s["key"]])
	cf.set_value("meta", "format", FORMAT)
	cf.save(path)


static func reset_to_defaults() -> void:
	values.clear()
	for s: Dictionary in SCHEMA:
		values[s["key"]] = default_of(s)


static func spec(key: String) -> Dictionary:
	for s: Dictionary in SCHEMA:
		if s["key"] == key:
			return s
	return {}


static func default_of(s: Dictionary) -> Variant:
	if Platform.is_mobile() and s.has("mobile"):
		return s["mobile"]
	return s["default"]


## Привести значение к типу и диапазону ключа (защита от испорченного файла).
static func sanitize(key: String, v: Variant) -> Variant:
	var s := spec(key)
	if s.is_empty():
		return v
	match s["kind"]:
		Kind.BOOL:
			return bool(v) if v is bool or v is int else s["default"]
		Kind.FLOAT:
			if not (v is float or v is int):
				return s["default"]
			return clampf(float(v), float(s.get("min", 0.0)), float(s.get("max", 1.0)))
		Kind.ENUM:
			if not (v is int or v is float):
				return s["default"]
			return clampi(int(v), 0, (s["options"] as Array).size() - 1)
	return v


## Строка видна на текущей платформе.
static func visible_here(s: Dictionary) -> bool:
	match s.get("only", ""):
		"mobile":
			return Platform.is_mobile()
		"desktop":
			return not Platform.is_mobile()
	return true


static func get_value(key: String) -> Variant:
	ensure_loaded()
	return values.get(key, spec(key).get("default"))


static func flag(key: String) -> bool:
	return bool(get_value(key))


static func num(key: String) -> float:
	return float(get_value(key))


static func choice(key: String) -> int:
	return int(get_value(key))


static func set_value(key: String, v: Variant) -> void:
	ensure_loaded()
	values[key] = sanitize(key, v)
	match key:
		"master", "music", "sfx", "ambient":
			apply_audio()
		"fullscreen", "vsync", "fps_limit", "antialias":
			apply_video()


# ---------------------------------------------------------------- производные значения

static func particle_mult() -> float:
	return [0.35, 0.65, 1.0][choice("particles")]


static func ui_scale() -> float:
	return UI_SCALES[choice("ui_scale")]


static func touch_enabled() -> bool:
	match choice("touch_mode"):
		1:
			return true
		2:
			return false
	return Platform.has_touchscreen()


# ---------------------------------------------------------------- применение

## Громкость шин. Шины Music, SFX и Ambient создаёт sfx.gd.
static func apply_audio() -> void:
	_set_bus("Master", num("master"))
	_set_bus("Music", num("music"))
	_set_bus("SFX", num("sfx"))
	_set_bus("Ambient", num("ambient"))


static func _set_bus(bus_name: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value, 0.0001)))
	if bus_name != "Master":  # Master глушится ещё и клавишей M — её не трогаем
		AudioServer.set_bus_mute(idx, value <= 0.001)


static func apply_video() -> void:
	Engine.max_fps = [30, 60, 120, 0][choice("fps_limit")]
	if Platform.is_headless():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.msaa_2d = Viewport.MSAA_4X if flag("antialias") else Viewport.MSAA_DISABLED
	if Platform.is_mobile():
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if flag("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if flag("vsync") else DisplayServer.VSYNC_DISABLED)
