extends RefCounted
## Прогресс игрока в user://save.cfg: рекорды по сложностям ([best]) и древо навыков ([skills]).
## Путь можно подменить (тесты пишут во временный файл, не трогая настоящее сохранение).

const DEFAULT_PATH := "user://save.cfg"

static var path := DEFAULT_PATH


static func load_file() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(path)  # нет файла — пустой конфиг
	return cf


static func best(diff: int) -> int:
	return int(load_file().get_value("best", str(diff), 0))


static func bests(count: int) -> Array[int]:
	var cf := load_file()
	var out: Array[int] = []
	for i in count:
		out.append(int(cf.get_value("best", str(i), 0)))
	return out


## Записать результат. Возвращает true, если это новый рекорд.
static func submit_score(diff: int, score: int) -> bool:
	if score <= best(diff):
		return false
	var cf := load_file()
	cf.set_value("best", str(diff), score)
	cf.save(path)
	return true


static func reset_records() -> void:
	var cf := load_file()
	if cf.has_section("best"):
		cf.erase_section("best")
	cf.save(path)


static func read_section(section: String) -> Dictionary:
	var cf := load_file()
	var out := {}
	if cf.has_section(section):
		for key in cf.get_section_keys(section):
			out[key] = cf.get_value(section, key)
	return out


static func write_section(section: String, values: Dictionary) -> void:
	var cf := load_file()
	for key: String in values:
		cf.set_value(section, key, values[key])
	cf.save(path)
