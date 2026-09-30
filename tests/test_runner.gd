extends RefCounted
## Находит наборы tests/unit/test_*.gd и tests/integration/test_*.gd, запускает все методы test_*,
## собирает отчёт. Используется из командной строки (run_tests.gd) и из панели разработчика.
##
## v12.4: перед каждым тестом случайность засевается от имени теста — падение повторяется при перезапуске
## (`--seed=N` меняет посев всего прогона). Ошибка движка или скрипта во время теста — провал, если тест не
## объявил expect_errors(). В конце — самые медленные тесты, время наборов и доля тестов от кода.

const TestCase = preload("res://tests/test_case.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")
const DevLog = preload("res://scripts/ui/dev_log.gd")
const Ratio = preload("res://tests/ratio.gd")

const SLOWEST := 5

var lines: Array[String] = []
var passed := 0
var failed := 0
var checks := 0
var base_seed := 0
var timings: Array = []  # [мс, "набор.тест"]


static func find_suites(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var name := f.trim_suffix(".remap")
		if name.begins_with("test_") and name.ends_with(".gd"):
			out.append(dir.path_join(name))
	out.sort()
	return out


## Посев для теста: одинаковый от прогона к прогону, разный у разных тестов.
static func seed_for(suite_name: String, test_name: String, base := 0) -> int:
	return hash(suite_name + "." + test_name) ^ base


## Запустить наборы. only — подстрока имени набора или теста (пусто — все).
func run(paths: Array[String], parent: Node, only := "") -> Dictionary:
	DevLog.install()
	TestCase.use_temp_storage()
	TestCase.ensure_actions()
	Sfx.build_now()
	var t0 := Time.get_ticks_msec()
	for path in paths:
		await _run_suite(path, parent, only)
	TestCase.restore_storage()
	var ms := Time.get_ticks_msec() - t0
	_append_slowest()
	var ratio := Ratio.line()
	if ratio != "" and only == "":
		lines.append(ratio)
	lines.append("")
	lines.append("%s  пройдено %d, упало %d, проверок %d, %.1f с" % [
		"OK" if failed == 0 else "ПРОВАЛ", passed, failed, checks, ms / 1000.0])
	return {"passed": passed, "failed": failed, "checks": checks, "text": "\n".join(lines)}


func _run_suite(path: String, parent: Node, only: String) -> void:
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():  # ошибка разбора — это провал, а не «0 тестов»
		failed += 1
		lines.append("✗ %s — не загрузился" % path)
		return
	var suite: TestCase = script.new()
	suite.tree = parent.get_tree()
	var suite_name := path.get_file().trim_suffix(".gd")
	var methods: Array[String] = []
	for m in script.get_script_method_list():
		var n: String = m["name"]
		if n.begins_with("test_") and not n in methods:
			if only == "" or only in suite_name or only in n:
				methods.append(n)
	if methods.is_empty():
		return
	var header := lines.size()
	lines.append("• " + suite_name)
	var suite_t0 := Time.get_ticks_msec()
	await suite.before_all()
	for m in methods:
		var host := Node.new()
		host.name = "TestHost"
		parent.add_child(host)
		suite.host = host
		suite.current = m
		suite.errors_expected = false
		seed(seed_for(suite_name, m, base_seed))
		var before := suite.failures.size()
		var errors_before := suite.engine_errors()
		var t0 := Time.get_ticks_msec()
		await suite.before_each()
		await suite.call(m)
		await suite.after_each()
		host.queue_free()
		await suite.tree.process_frame
		suite.tree.paused = false
		Engine.time_scale = 1.0
		timings.append([Time.get_ticks_msec() - t0, suite_name + "." + m])
		var new_errors := suite.engine_errors() - errors_before
		if new_errors > 0 and not suite.errors_expected:
			suite.fail("%d ошибок движка во время теста: %s" % [new_errors, " | ".join(_errors_only(DevLog.shared.lines))])
		if suite.failures.size() == before:
			passed += 1
			lines.append("    ✓ " + m)
		else:
			failed += 1
			lines.append("    ✗ " + m)
			for f in suite.failures.slice(before):
				lines.append("        " + f)
	await suite.after_all()
	checks += suite.checks
	lines[header] += "  (%.1f с)" % ((Time.get_ticks_msec() - suite_t0) / 1000.0)


static func _errors_only(log_lines: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for l in log_lines:
		if l.begins_with("✖"):
			out.append(l)
	return out.slice(-3)


func _append_slowest() -> void:
	if timings.size() < SLOWEST * 2:
		return
	timings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	lines.append("")
	lines.append("Самые медленные:")
	for t: Array in timings.slice(0, SLOWEST):
		lines.append("    %5.1f с  %s" % [t[0] / 1000.0, t[1]])


## Только юнит-тесты — для панели разработчика в запущенной игре.
func run_unit(parent: Node) -> Dictionary:
	return await run(find_suites("res://tests/unit"), parent)
