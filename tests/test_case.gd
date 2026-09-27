extends RefCounted
## Базовый класс набора тестов. Методы test_* запускает test_runner.gd; они могут быть асинхронными
## (await frames(n)). before_each/after_each вызываются вокруг каждого теста.
## Сохранения и настройки на время тестов перенаправлены во временную папку user://test/.

const SaveData = preload("res://scripts/core/save_data.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Skills = preload("res://scripts/core/skills.gd")
const Controls = preload("res://scripts/core/controls.gd")
const Bestiary = preload("res://scripts/core/bestiary.gd")
const Daily = preload("res://scripts/core/daily.gd")

const TMP := "user://test"

var tree: SceneTree
var host: Node  # сюда тесты добавляют узлы; очищается после каждого теста
var failures: Array[String] = []
var checks := 0
var current := ""


func before_all() -> void:
	pass


func after_all() -> void:
	pass


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# ---------------------------------------------------------------- проверки

func fail(msg: String) -> void:
	failures.append("%s: %s" % [current, msg])


func assert_true(cond: bool, msg := "ожидалось true") -> void:
	checks += 1
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg := "ожидалось false") -> void:
	assert_true(not cond, msg)


func assert_eq(actual: Variant, expected: Variant, msg := "") -> void:
	checks += 1
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		fail("%s ожидалось %s (%s), получено %s (%s)" % [msg, str(expected), type_string(typeof(expected)),
			str(actual), type_string(typeof(actual))])
	elif actual != expected:
		fail("%s ожидалось %s, получено %s" % [msg, str(expected), str(actual)])


func assert_near(actual: float, expected: float, eps := 0.001, msg := "") -> void:
	checks += 1
	if absf(actual - expected) > eps:
		fail("%s ожидалось ≈%s, получено %s" % [msg, str(expected), str(actual)])


func assert_between(v: float, lo: float, hi: float, msg := "") -> void:
	checks += 1
	if v < lo or v > hi:
		fail("%s значение %s вне [%s, %s]" % [msg, str(v), str(lo), str(hi)])


func assert_ne(actual: Variant, unexpected: Variant, msg := "") -> void:
	checks += 1
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		fail("%s не ожидалось %s" % [msg, str(unexpected)])


## Коллекция (массив, словарь, строка) содержит элемент.
func assert_has(container: Variant, item: Variant, msg := "") -> void:
	checks += 1
	var ok := false
	match typeof(container):
		TYPE_DICTIONARY:
			ok = (container as Dictionary).has(item)
		TYPE_STRING:
			ok = String(item) in String(container)
		_:
			ok = item in container
	if not ok:
		fail("%s нет %s" % [msg, str(item)])


func assert_len(container: Variant, n: int, msg := "") -> void:
	checks += 1
	var size: int = container.size() if typeof(container) != TYPE_STRING else String(container).length()
	if size != n:
		fail("%s длина %d, ожидалось %d" % [msg, size, n])


func assert_gt(v: float, lo: float, msg := "") -> void:
	checks += 1
	if not v > lo:
		fail("%s %s не больше %s" % [msg, str(v), str(lo)])


func _is_num(v: Variant) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT]


# ---------------------------------------------------------------- помощники

func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


## Нажать и отпустить клавишу по физическому коду (как настоящая клавиатура, в т.ч. на русской раскладке).
func press_key(physical: Key, ctrl := false, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = physical
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = pressed
		tree.root.push_input(ev)
		await tree.process_frame


## Кликнуть/протащить мышью по контролу (события в его локальных координатах, через _gui_input).
func mouse_button(c: Control, pos: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	c._gui_input(ev)


func mouse_move(c: Control, pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	c._gui_input(ev)


func action_event(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


## Добавить узел в дерево (удалится после теста).
func add(node: Node) -> Node:
	host.add_child(node)
	return node


## Перенаправить сохранения во временные файлы и начать с чистого листа.
static func use_temp_storage() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	SaveData.path = TMP + "/save.cfg"
	Settings.path = TMP + "/settings.cfg"
	for f in ["save.cfg", "settings.cfg"]:
		if FileAccess.file_exists(TMP + "/" + f):
			DirAccess.remove_absolute(TMP + "/" + f)
	Skills.load_progress()
	Settings.load_from_disk()
	Bestiary.load_progress()
	Daily.load_progress()


static func restore_storage() -> void:
	SaveData.path = SaveData.DEFAULT_PATH
	Settings.path = Settings.DEFAULT_PATH
	Skills.load_progress()
	Settings.load_from_disk()
	Bestiary.load_progress()
	Daily.load_progress()


## Убедиться, что есть игровые действия с настоящими клавишами (в тестах game.gd может не запускаться).
static func ensure_actions() -> void:
	Controls.setup()
