extends RefCounted
## Прогресс игрока: рекорды по сложностям ([best]), древо навыков ([skills]), картотека ([bestiary]),
## испытание дня ([daily]). Путь можно подменить (тесты пишут во временный файл, не трогая настоящее
## сохранение).
##
## С v8.1 файл зашифрован (user://save.dat): рекорды и чешуйки больше не поправить в блокноте.
## Старое текстовое сохранение user://save.cfg переносится один раз и остаётся рядом как save.cfg.old.
## Запись атомарная: сначала во временный файл, потом подмена — сбой посреди записи не портит прогресс.
## Файл, который не расшифровался (правка вручную, мусор), не читается: прогресс начинается заново.

const DEFAULT_PATH := "user://save.dat"
const LEGACY_PATH := "user://save.cfg"
## Ключ шифрования. Он в сборке, так что это защита от правки в текстовом редакторе, а не от взлома.
const KEY := "peremeny-budut/omelette/v8.1"

static var path := DEFAULT_PATH
static var legacy_path := LEGACY_PATH


static func load_file() -> ConfigFile:
	_migrate_legacy()
	var cf := ConfigFile.new()
	if FileAccess.file_exists(path) and cf.load_encrypted_pass(path, KEY) != OK:
		push_warning("save: не удалось прочитать %s — прогресс начнётся заново" % path)
		return ConfigFile.new()  # недочитанный файл мог оставить в cf часть секций
	return cf


## Записать сохранение: во временный файл, затем подменить настоящий.
static func save_file(cf: ConfigFile) -> Error:
	var tmp := path + ".tmp"
	var err := cf.save_encrypted_pass(tmp, KEY)
	if err != OK:
		push_warning("save: не удалось записать %s (%s)" % [tmp, error_string(err)])
		return err
	err = DirAccess.rename_absolute(tmp, path)  # на Windows rename заменяет существующий файл
	if err != OK:  # запасной путь: убрать старый и переименовать ещё раз
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp, path)
	return err


## Однократный перенос текстового сохранения (до v8.1) в зашифрованное.
static func _migrate_legacy() -> void:
	if legacy_path == "" or legacy_path == path or FileAccess.file_exists(path) or not FileAccess.file_exists(legacy_path):
		return
	var old := ConfigFile.new()
	if old.load(legacy_path) != OK:
		return
	if save_file(old) == OK:
		DirAccess.rename_absolute(legacy_path, legacy_path + ".old")


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
	var cf := load_file()
	if score <= int(cf.get_value("best", str(diff), 0)):
		return false
	cf.set_value("best", str(diff), score)
	save_file(cf)
	return true


static func reset_records() -> void:
	var cf := load_file()
	if cf.has_section("best"):
		cf.erase_section("best")
	save_file(cf)


static func erase_section(section: String) -> void:
	var cf := load_file()
	if cf.has_section(section):
		cf.erase_section(section)
	save_file(cf)


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
	save_file(cf)
