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
const Secrets = preload("res://scripts/core/secrets.gd")
const DevLog = preload("res://scripts/ui/dev_log.gd")

const TMP := "user://test"

var tree: SceneTree
var host: Node  # сюда тесты добавляют узлы; очищается после каждого теста
var failures: Array[String] = []
var checks := 0
var current := ""
var errors_expected := false  # тест сам вызывает ошибки (битые файлы и т. п.) — см. expect_errors()


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


func assert_lt(v: float, hi: float, msg := "") -> void:
	checks += 1
	if not v < hi:
		fail("%s %s не меньше %s" % [msg, str(v), str(hi)])


## Прямоугольник целиком внутри другого (с допуском в пиксель на округление раскладки).
func assert_rect_inside(inner: Rect2, outer: Rect2, msg := "") -> void:
	checks += 1
	var o := outer.grow(1.0)
	if not (o.encloses(inner)):
		fail("%s %s не внутри %s" % [msg, str(inner), str(outer)])


## Контрол виден игроку: сам и все предки видимы, он внутри экрана и не обрезан прокруткой.
func assert_on_screen(c: Control, msg := "") -> void:
	checks += 1
	if not c.is_visible_in_tree():
		fail("%s: %s скрыт" % [msg, c.name])
		return
	var r := c.get_global_rect()
	var screen := c.get_viewport().get_visible_rect().grow(1.0)
	if not screen.encloses(r):
		fail("%s: %s %s за краем экрана %s" % [msg, c.name, str(r), str(screen.size)])
		return
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer and not (p as Control).get_global_rect().grow(1.0).encloses(r):
			fail("%s: %s обрезан прокруткой" % [msg, c.name])
			return
		p = p.get_parent()


## Узел отрисовался без ошибок движка и скриптов: рисуем его вне очереди и сверяем журнал ошибок.
func assert_draws(ci: CanvasItem, msg := "") -> void:
	checks += 1
	var before := engine_errors()
	ci.queue_redraw()
	await tree.process_frame
	await tree.process_frame
	var after := engine_errors()
	if after > before:
		fail("%s: %s — %d ошибок при отрисовке" % [msg, ci.name, after - before])


## Сколько ошибок движка и скриптов накопил журнал с начала прогона.
func engine_errors() -> int:
	var lg = DevLog.shared
	return lg.errors if lg else 0


## Тест проверяет обработку ошибок и сам их вызывает — раннер не считает их провалом.
func expect_errors() -> void:
	errors_expected = true


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
	SaveData.path = TMP + "/save.dat"
	SaveData.legacy_path = ""  # не переносить настоящее старое сохранение игрока во временное
	Settings.path = TMP + "/settings.cfg"
	for f in ["save.dat", "save.dat.tmp", "save.cfg", "save.cfg.old", "settings.cfg"]:
		if FileAccess.file_exists(TMP + "/" + f):
			DirAccess.remove_absolute(TMP + "/" + f)
	Skills.load_progress()
	Settings.load_from_disk()
	Bestiary.load_progress()
	Daily.load_progress()
	Secrets.load_progress()


static func restore_storage() -> void:
	SaveData.path = SaveData.DEFAULT_PATH
	SaveData.legacy_path = SaveData.LEGACY_PATH
	Settings.path = Settings.DEFAULT_PATH
	Skills.load_progress()
	Settings.load_from_disk()
	Bestiary.load_progress()
	Daily.load_progress()
	Secrets.load_progress()


## Убедиться, что есть игровые действия с настоящими клавишами (в тестах game.gd может не запускаться).
static func ensure_actions() -> void:
	Controls.setup()
