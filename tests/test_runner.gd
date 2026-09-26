extends RefCounted
## Находит наборы tests/unit/test_*.gd и tests/integration/test_*.gd, запускает все методы test_*,
## собирает отчёт. Используется из командной строки (run_tests.gd) и из панели разработчика.

const TestCase = preload("res://tests/test_case.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")

var lines: Array[String] = []
var passed := 0
var failed := 0
var checks := 0


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


## Запустить наборы. only — подстрока имени набора или теста (пусто — все).
func run(paths: Array[String], parent: Node, only := "") -> Dictionary:
	TestCase.use_temp_storage()
	TestCase.ensure_actions()
	Sfx.build_now()
	var t0 := Time.get_ticks_msec()
	for path in paths:
		await _run_suite(path, parent, only)
	TestCase.restore_storage()
	var ms := Time.get_ticks_msec() - t0
	lines.append("")
	lines.append("%s  пройдено %d, упало %d, проверок %d, %.1f с" % [
		"OK" if failed == 0 else "ПРОВАЛ", passed, failed, checks, ms / 1000.0])
	return {"passed": passed, "failed": failed, "checks": checks, "text": "\n".join(lines)}


func _run_suite(path: String, parent: Node, only: String) -> void:
	var script: GDScript = load(path)
	if script == null:
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
	lines.append("• " + suite_name)
	await suite.before_all()
	for m in methods:
		var host := Node.new()
		host.name = "TestHost"
		parent.add_child(host)
		suite.host = host
		suite.current = m
		var before := suite.failures.size()
		await suite.before_each()
		await suite.call(m)
		await suite.after_each()
		host.queue_free()
		await suite.tree.process_frame
		suite.tree.paused = false
		Engine.time_scale = 1.0
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


## Только юнит-тесты — для панели разработчика в запущенной игре.
func run_unit(parent: Node) -> Dictionary:
	return await run(find_suites("res://tests/unit"), parent)
