extends RefCounted
## Пасхалки (v9.0). Каждая находится один раз и запоминается в user://save.dat, раздел [secrets].
## Сколько найдено — видно в журнале главного меню; что именно и где искать — только в панели
## разработчика (вкладка МИР, раздел «Пасхалки»), чтобы не портить сюрприз.

const SaveData = preload("res://scripts/core/save_data.gd")

const SECTION := "secrets"

## id, название (показывается при находке) и подсказка для панели разработчика.
const LIST := [
	{"id": "konami", "title": "Золотая змея", "hint": "В главном меню: ↑ ↑ ↓ ↓ ← → ← → B A"},
	{"id": "title", "title": "Шшш!", "hint": "Семь раз щёлкнуть по заголовку «ЗМЕЯ» в меню"},
	{"id": "egg_poke", "title": "Не трогай, я не дожарилась", "hint": "Пять раз ткнуть в яичницу, выглядывающую в меню"},
	{"id": "iddqd", "title": "Пункт 12-Б", "hint": "Набрать в главном меню iddqd"},
	{"id": "koschei", "title": "Кощеева смерть", "hint": "Редко: в съеденной малышке-матрёшке — яйцо, в яйце — игла"},
	{"id": "sleepy", "title": "Образец №47 уснул", "hint": "Простоять на паузе минуту"},
	{"id": "holiday", "title": "С Новым годом!", "hint": "Сыграть с 25 декабря по 7 января"},
	{"id": "contact", "title": "Контакт", "hint": "Досмотреть финал до конца… и пройти то, что будет после"},
]

static var _cache: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if not _loaded:
		load_progress()


static func load_progress() -> void:
	_cache = SaveData.read_section(SECTION)
	_loaded = true


static func is_found(id: String) -> bool:
	ensure_loaded()
	return bool(_cache.get(id, false))


## Отметить находку. true — найдена только что (впервые).
static func unlock(id: String, save := true) -> bool:
	ensure_loaded()
	if entry(id).is_empty() or is_found(id):
		return false
	_cache[id] = true
	if save:
		SaveData.write_section(SECTION, {id: true})
	return true


static func entry(id: String) -> Dictionary:
	for e: Dictionary in LIST:
		if e["id"] == id:
			return e
	return {}


static func found_count() -> int:
	ensure_loaded()
	var n := 0
	for e: Dictionary in LIST:
		if is_found(e["id"]):
			n += 1
	return n


static func total() -> int:
	return LIST.size()


## Новогодние каникулы: с 25 декабря по 7 января (date — как у Time.get_date_dict_from_system()).
static func is_holiday(date := {}) -> bool:
	var d: Dictionary = date if not date.is_empty() else Time.get_date_dict_from_system()
	return (int(d["month"]) == 12 and int(d["day"]) >= 25) or (int(d["month"]) == 1 and int(d["day"]) <= 7)


static func reset() -> void:
	SaveData.erase_section(SECTION)
	_cache = {}
	_loaded = false
