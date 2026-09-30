extends RefCounted
## Статистика одного забега для расширенных итогов (v12.3): серия очков, полученные удары, приёмы,
## самая длинная змея, время по этапам и прозвище забега. Игра только сообщает события —
## считает и придумывает прозвище этот класс, поэтому его можно проверить без игры.

const SaveData = preload("res://scripts/core/save_data.gd")

const COMBO_GAP := 3.0       # между очковыми событиями не больше стольких секунд — серия не рвётся
const COMBO_MIN := 3         # серия короче трёх в итогах не показывается
const SAVE_SECTION := "stats"

var combo := 0
var best_combo := 0
var hits := 0                # полученные удары
var abilities := 0           # применённые приёмы
var peak_length := 0
var flawless := 0            # этапов без единого удара
var stage_times: Array[float] = []   # секунды на каждом пройденном этапе
var stage_ids: Array[int] = []       # и номера этих этапов (забег может начаться не с первого)
var beaten := {}             # v12.4: ключ картотеки → сколько раз побеждён за забег («любимое блюдо»)

var _last_score_t := -99.0
var _stage_start := 0.0
var _stage_hits := 0


func reset() -> void:
	combo = 0
	best_combo = 0
	hits = 0
	abilities = 0
	peak_length = 0
	flawless = 0
	stage_times.clear()
	stage_ids.clear()
	beaten.clear()
	_last_score_t = -99.0
	_stage_start = 0.0
	_stage_hits = 0


## Очковое событие (укус, нокаут, удар по яичнице...). t — время забега в секундах.
func on_score(t: float) -> void:
	combo = combo + 1 if t - _last_score_t <= COMBO_GAP else 1
	_last_score_t = t
	best_combo = maxi(best_combo, combo)


func on_hit() -> void:
	hits += 1
	_stage_hits += 1
	combo = 0  # удар рвёт серию


## Враг побеждён (ключ картотеки: bear_3, pill_2, doll_0…).
func on_beaten(key: String) -> void:
	beaten[key] = int(beaten.get(key, 0)) + 1


## Любимое блюдо забега: кого побеждали чаще всего. [ключ, сколько] или [] — если меньше трёх побед.
## При равенстве — тот, кто в картотеке раньше (порядок ключей стабилен).
func favorite(order: Array) -> Array:
	var best := ""
	var n := 0
	for key: String in order:
		var c := int(beaten.get(key, 0))
		if c > n:
			best = key
			n = c
	return [best, n] if n >= 3 else []


func on_ability() -> void:
	abilities += 1


func note_length(n: int) -> void:
	peak_length = maxi(peak_length, n)


func stage_begin(t: float) -> void:
	_stage_start = t
	_stage_hits = 0


## Этап номер stage пройден в момент t.
func stage_end(t: float, stage: int) -> void:
	stage_times.append(maxf(t - _stage_start, 0.0))
	stage_ids.append(stage)
	if _stage_hits == 0:
		flawless += 1


## Позиция самого быстрого пройденного этапа в stage_times (-1 — ни одного).
func fastest_stage() -> int:
	var best := -1
	for i in stage_times.size():
		if best < 0 or stage_times[i] < stage_times[best]:
			best = i
	return best


## Прозвище забега по самым заметным чертам. Порядок важен: сначала самое редкое.
func nickname(win: bool) -> String:
	if win and hits == 0:
		return "Неприкосновенная"
	if best_combo >= 12:
		return "Мясорубка"
	if flawless >= 3:
		return "Чистая работа"
	if abilities >= 15:
		return "Арсенал на ножках"
	if win and hits >= 8:
		return "Живучая до неприличия"
	if peak_length >= 60:
		return "Длинная история"
	return "Ползучая" if not win else "Просто молодец"


## Лучшая серия за всё время: сохраняется отдельно от рекордов очков. Возвращает true, если побита.
static func submit_best_combo(n: int) -> bool:
	if n < COMBO_MIN:
		return false
	var old: int = int(SaveData.read_section(SAVE_SECTION).get("best_combo", 0))
	if n <= old:
		return false
	SaveData.write_section(SAVE_SECTION, {"best_combo": n})
	return true


static func saved_best_combo() -> int:
	return int(SaveData.read_section(SAVE_SECTION).get("best_combo", 0))
