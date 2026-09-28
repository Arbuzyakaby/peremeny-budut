extends RefCounted
## Ежедневное испытание: раз в день один и тот же для всех забег на Нормальной сложности
## с модификатором дня. Сид и модификатор выводятся из даты, рекорд дня хранится отдельно
## (user://save.dat, раздел [daily]). Чешуйки начисляются как обычно.

const SaveData = preload("res://scripts/core/save_data.gd")

const SECTION := "daily"
const BASE_DIFFICULTY := 1

## Модификаторы. apply — изменения таблицы сложности (множители *, прибавки +, замены =).
const MODIFIERS := [
	{"id": "speed", "name": "УСКОРЕНИЕ", "desc": "Враги на 40% быстрее и злее. Очки ×1.5",
		"mul": {"bear_speed": 1.4, "tempo": 0.72, "proj_speed": 1.3}, "score": 1.5},
	{"id": "one_life", "name": "ОДНА ЖИЗНЬ", "desc": "Всего одна жизнь, навыки работают. Очки ×2",
		"set": {"lives": 1}, "score": 2.0},
	{"id": "ice", "name": "ГОЛОЛЁД", "desc": "Змея поворачивает на треть медленнее. Очки ×1.5",
		"snake": {"turn_mult": 0.66}, "score": 1.5},
	{"id": "dark", "name": "ТЕМНОТА", "desc": "Лампа погасла — видно только вокруг змеи. Очки ×1.7",
		"dark": true, "score": 1.7},
	{"id": "forks", "name": "ВИЛОЧНОЕ НАШЕСТВИЕ", "desc": "Вилок вдвое больше, медведей меньше. Очки ×1.5",
		"mul": {"forks": 2.0, "bears": 0.6}, "score": 1.5},
]

static var _cache: Dictionary = {}
static var _loaded := false


## Ключ дня: "2026-09-27". date — словарь как у Time.get_date_dict_from_system().
static func day_key(date := {}) -> String:
	var d: Dictionary = date if not date.is_empty() else Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


## Детерминированный сид дня (одинаковый на всех устройствах).
static func seed_for(key: String) -> int:
	var h := 2166136261
	for i in key.length():
		h = ((h ^ key.unicode_at(i)) * 16777619) & 0x7fffffff
	return h


static func modifier_for(key: String) -> Dictionary:
	return MODIFIERS[seed_for(key) % MODIFIERS.size()]


static func today() -> Dictionary:
	return modifier_for(day_key())


## Таблица сложности с модификатором дня (копия, исходная не меняется).
static func apply(cfg: Dictionary, mod: Dictionary) -> Dictionary:
	var out := cfg.duplicate()
	for k: String in mod.get("mul", {}):
		var v: float = float(out[k]) * float(mod["mul"][k])
		out[k] = maxi(1, roundi(v)) if typeof(cfg[k]) == TYPE_INT else v
	for k: String in mod.get("set", {}):
		out[k] = mod["set"][k]
	out["score_mult"] = maxi(1, roundi(float(cfg["score_mult"]) * float(mod.get("score", 1.0))))
	out["name"] = "ИСПЫТАНИЕ: " + String(mod["name"])
	out["daily"] = mod["id"]
	return out


static func load_progress() -> void:
	_cache = SaveData.read_section(SECTION)
	_loaded = true


static func best(key: String) -> int:
	if not _loaded:
		load_progress()
	return int(_cache.get(key, 0))


## Записать результат дня. true — новый рекорд дня.
static func submit(key: String, score: int) -> bool:
	if score <= best(key):
		return false
	_cache[key] = score
	SaveData.write_section(SECTION, {key: score})
	return true


## Сколько дней испытание пройдено с ненулевым счётом (для экрана меню).
static func days_played() -> int:
	if not _loaded:
		load_progress()
	var n := 0
	for k in _cache:
		if int(_cache[k]) > 0:
			n += 1
	return n
