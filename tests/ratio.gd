extends SceneTree
## Доля тестов от кода (v12.4): строки tests/**/*.gd против строк scripts/**/*.gd — так же, как `wc -l`.
##   godot --headless --path . -s res://tests/ratio.gd
## Раннер тестов печатает ту же строку в конце прогона (TestRunner.ratio_line()).

const TARGET := 0.4


func _initialize() -> void:
	print(line())
	quit(0)


static func line() -> String:
	var code := count_lines("res://scripts")
	var tests := count_lines("res://tests")
	if code == 0:  # в собранной игре исходников нет
		return ""
	var k := tests / float(code)
	return "Тесты: %d строк на %d строк кода — %.1f%% (цель %d%%)%s" % [tests, code, k * 100.0, int(TARGET * 100.0),
		"" if k >= TARGET else "  НИЖЕ ЦЕЛИ"]


## Строки всех .gd в папке и подпапках.
static func count_lines(dir: String) -> int:
	var total := 0
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	for f in d.get_files():
		if f.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(dir.path_join(f))
			if text != "":
				total += text.count("\n") + (0 if text.ends_with("\n") else 1)
	for sub in d.get_directories():
		total += count_lines(dir.path_join(sub))
	return total
