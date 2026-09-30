extends SceneTree
## Запуск автотестов из командной строки:
##   godot --headless --path . -s res://tests/run_tests.gd
##   godot --headless --path . -s res://tests/run_tests.gd -- --only=skills   (фильтр по имени)
##   godot --headless --path . -s res://tests/run_tests.gd -- --unit          (без интеграционных)
##   godot --headless --path . -s res://tests/run_tests.gd -- --seed=7        (другой посев случайности)
## Код выхода 0 — всё прошло, 1 — есть падения.

const TestRunner = preload("res://tests/test_runner.gd")
const Game = preload("res://scripts/game/game.gd")


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var only := ""
	var unit_only := false
	var base_seed := 0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.get_slice("=", 1)
		elif a == "--unit":
			unit_only = true
		elif a.begins_with("--seed="):
			base_seed = int(a.get_slice("=", 1))
	var paths := TestRunner.find_suites("res://tests/unit")
	if not unit_only:
		paths.append_array(TestRunner.find_suites("res://tests/integration"))
	var runner := TestRunner.new()
	runner.base_seed = base_seed
	var report: Dictionary = await runner.run(paths, root, only)
	print(report["text"])
	for i in 10:  # дать аудиосерверу отпустить звучавшие потоки
		await process_frame
	Game._on_quit()  # освободить static-кэши, чтобы не было утечек
	quit(0 if report["failed"] == 0 else 1)
