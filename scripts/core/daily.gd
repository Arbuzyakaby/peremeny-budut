extends RefCounted
## Ежедневное испытание: раз в день один и тот же для всех забег на Нормальной сложности
## с двумя модификаторами дня (с v8.2), очки множатся. Серия дней подряд даёт бонусные чешуйки. Сид и модификатор выводятся из даты, рекорд дня хранится отдельно
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
	{"id": "pills", "name": "ТАБЛЕТОЧНЫЙ ДОЖДЬ", "desc": "Таблеток вдвое больше. Очки ×1.4",
		"mul": {"pills": 2.0}, "score": 1.4},
	{"id": "tough_egg", "name": "КРЕПКАЯ ЯИЧНИЦА", "desc": "У яичницы в полтора раза больше делений. Очки ×1.5",
		"mul": {"boss_hp": 1.5}, "score": 1.5},
	{"id": "short_yolk", "name": "СКУПОЙ ЖЕЛТОК", "desc": "Желток открыт на 30% меньше. Очки ×1.4",
		"mul": {"yolk_time": 0.7}, "score": 1.4},
	{"id": "breathless", "name": "ОДЫШКА", "desc": "Стамины на 40% меньше. Очки ×1.4",
		"snake": {"stamina_max": 0.6}, "score": 1.4},
	{"id": "snipers", "name": "СНАЙПЕРЫ", "desc": "Снаряды врагов летят в полтора раза быстрее. Очки ×1.4",
		"mul": {"proj_speed": 1.5}, "score": 1.4},
	{"id": "horde", "name": "ОРДА", "desc": "Медведей на 60% больше. Очки ×1.3",
		"mul": {"bears": 1.6}, "score": 1.3},
]
const STREAK_SECTION := "daily_streak"
const STREAK_SCALES := 2      # чешуек за каждый день серии
const STREAK_CAP := 7         # серия дальше не дорожает

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


## Два разных модификатора дня: первый — modifier_for, второй выводится из того же сида.
static func pair_for(key: String) -> Array:
	var h := seed_for(key)
	var a := h % MODIFIERS.size()
	var b := (a + 1 + (h / MODIFIERS.size()) % (MODIFIERS.size() - 1)) % MODIFIERS.size()
	return [MODIFIERS[a], MODIFIERS[b]]


## Свести несколько модификаторов в один: множители перемножаются, очки тоже.
static func combine(list: Array) -> Dictionary:
	var out := {"id": "", "name": "", "desc": "", "mul": {}, "set": {}, "snake": {}, "dark": false, "score": 1.0,
		"parts": list}
	var ids := []
	var names := []
	var descs := []
	for m: Dictionary in list:
		ids.append(m["id"])
		names.append(m["name"])
		descs.append(m["desc"])
		for group in ["mul", "snake"]:
			for k: String in m.get(group, {}):
				out[group][k] = float(out[group].get(k, 1.0)) * float(m[group][k])
		for k: String in m.get("set", {}):
			out["set"][k] = m["set"][k]
		out["dark"] = out["dark"] or m.get("dark", false)
		out["score"] = float(out["score"]) * float(m.get("score", 1.0))
	out["id"] = "+".join(ids)
	out["name"] = " + ".join(names)
	out["desc"] = "
".join(descs)
	return out


static func today() -> Dictionary:
	return combine(pair_for(day_key()))


## Ключ вчерашнего дня (для серии).
static func prev_key(key: String) -> String:
	var parts := key.split("-")
	var unix := Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]),
		"day": int(parts[2]), "hour": 12, "minute": 0, "second": 0})
	return day_key(Time.get_date_dict_from_unix_time(unix - 86400))


## Серия: сколько дней подряд сыграно испытание (сегодняшний или вчерашний день продолжают её).
static func streak(key := "") -> int:
	if key == "":
		key = day_key()
	var st := SaveData.read_section(STREAK_SECTION)
	var last := String(st.get("last", ""))
	return int(st.get("streak", 0)) if last == key or last == prev_key(key) else 0


static func best_streak() -> int:
	return int(SaveData.read_section(STREAK_SECTION).get("best", 0))


## Отметить сыгранный день. Возвращает бонус чешуек: только за первый забег дня, по длине серии.
static func register_play(key: String) -> int:
	var st := SaveData.read_section(STREAK_SECTION)
	var last := String(st.get("last", ""))
	if last == key:
		return 0
	var n := int(st.get("streak", 0)) + 1 if last == prev_key(key) else 1
	SaveData.write_section(STREAK_SECTION, {"last": key, "streak": n, "best": maxi(n, int(st.get("best", 0)))})
	return streak_bonus(n)


static func streak_bonus(n: int) -> int:
	return mini(n, STREAK_CAP) * STREAK_SCALES


## Таблица сложности с модификатором дня (копия, исходная не меняется).
static func apply(cfg: Dictionary, mod: Dictionary) -> Dictionary:
	var out := cfg.duplicate()
	for k: String in mod.get("mul", {}):
		var v: float = float(out[k]) * float(mod["mul"][k])
		out[k] = maxi(1, roundi(v)) if typeof(cfg[k]) == TYPE_INT else v
	out["score_mult"] = maxi(1, roundi(float(cfg["score_mult"]) * float(mod.get("score", 1.0))))
	for k: String in mod.get("set", {}):
		out[k] = mod["set"][k]
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
