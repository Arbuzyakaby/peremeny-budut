extends RefCounted
## Древо навыков змеи и улучшения забега.
## - Постоянное дерево: 4 ветки по 5 узлов, у узлов ранги. Покупается за «чешуйки», которые змея
##   зарабатывает в забегах. Узел открывается, когда у предыдущего в ветке есть хотя бы 1 ранг.
##   Хранится в user://save.dat (секция [skills]) и живёт в static-переменных.
## - Мутации забега: перед каждым новым этапом игрок выбирает одну из трёх (с навыком — четырёх) карточек.
##   У мутаций редкость: обычные прибавляют проценты, редкие и легендарные меняют правила.
## Всё сводится в словарь модификаторов (mods), который применяют змея и игра.
## На Ультра-Хардкоре навыки и улучшения отключены.

const SaveData = preload("res://scripts/core/save_data.gd")

const BRANCHES := [
	{"name": "ТЕЛО", "color": Color(0.95, 0.45, 0.4)},
	{"name": "МАНЁВР", "color": Color(0.45, 0.8, 1.0)},
	{"name": "АТАКА", "color": Color(0.6, 1.0, 0.45)},
	{"name": "ДОБЫЧА", "color": Color(1.0, 0.8, 0.35)},
]
const ROWS := 5  # узлов в ветке

## Узлы по веткам сверху вниз. cost — цена первого ранга, дальше растёт кратно рангу.
const TREE := [
	{"id": "hide", "branch": 0, "name": "Толстая шкура", "desc": "+1 жизнь за ранг", "max": 2, "cost": 8},
	{"id": "lungs", "branch": 0, "name": "Выносливость", "desc": "+20% стамины за ранг", "max": 3, "cost": 6},
	{"id": "breath", "branch": 0, "name": "Второе дыхание", "desc": "+25% восстановления стамины за ранг", "max": 2, "cost": 10},
	{"id": "molt", "branch": 0, "name": "Линька", "desc": "Раз за забег сбросить шкуру и пережить смертельный удар", "max": 1, "cost": 35},
	{"id": "regrow", "branch": 0, "name": "Регенерация", "desc": "Каждый пройденный этап возвращает жизнь", "max": 1, "cost": 45},
	{"id": "flex", "branch": 1, "name": "Гибкость", "desc": "+12% скорости поворота за ранг", "max": 3, "cost": 5},
	{"id": "sprinter", "branch": 1, "name": "Спринтер", "desc": "+8% скорости спринта и −15% расхода за ранг", "max": 2, "cost": 9},
	{"id": "slick", "branch": 1, "name": "Скользкая чешуя", "desc": "+0.5 с неуязвимости после удара за ранг", "max": 2, "cost": 12},
	{"id": "steady", "branch": 1, "name": "Устойчивость", "desc": "Оглушение и замедление вдвое короче", "max": 1, "cost": 30},
	{"id": "tail", "branch": 1, "name": "Запасной хвост", "desc": "Забег начинается со щитом, который поглотит удар", "max": 1, "cost": 45},
	{"id": "hoard", "branch": 2, "name": "Запасливость", "desc": "+1 заряд каждой атаки за ранг", "max": 3, "cost": 6},
	{"id": "thrift", "branch": 2, "name": "Экономия", "desc": "Атаки тратят на 15% меньше стамины за ранг", "max": 2, "cost": 10},
	{"id": "fangs", "branch": 2, "name": "Острые зубы", "desc": "+50% урона атаками по яичнице за ранг", "max": 2, "cost": 12},
	{"id": "jaws", "branch": 2, "name": "Сильные челюсти", "desc": "Укус желтка снимает 2 деления", "max": 1, "cost": 40},
	{"id": "loot", "branch": 2, "name": "Трофеи", "desc": "Приёмы вилок и таблеток дают +1 заряд", "max": 1, "cost": 45},
	{"id": "greed", "branch": 3, "name": "Жадность", "desc": "+15% чешуек за забег за ранг", "max": 3, "cost": 7},
	{"id": "gloat", "branch": 3, "name": "Хвастовство", "desc": "+10% очков за ранг", "max": 3, "cost": 9},
	{"id": "nose", "branch": 3, "name": "Нюх на редкое", "desc": "Редкие и легендарные мутации выпадают чаще", "max": 2, "cost": 14},
	{"id": "lucky", "branch": 3, "name": "Четвёртая карта", "desc": "Выбор из четырёх мутаций вместо трёх", "max": 1, "cost": 30},
	{"id": "bounty", "branch": 3, "name": "Премия", "desc": "Победа над яичницей: +25 чешуек сверху", "max": 1, "cost": 50},
]

## Мутации забега (карточки между этапами). rarity: 0 — обычная, 1 — редкая, 2 — легендарная.
## unique — берётся один раз за забег.
const RARITY := [
	{"name": "ОБЫЧНАЯ", "weight": 70.0, "color": Color(0.75, 0.72, 0.66)},
	{"name": "РЕДКАЯ", "weight": 24.0, "color": Color(0.45, 0.75, 1.0)},
	{"name": "ЛЕГЕНДАРНАЯ", "weight": 6.0, "color": Color(1.0, 0.72, 0.25)},
]
const PERKS := [
	{"id": "heal", "name": "ВТОРОЕ СЕРДЦЕ", "desc": "Вернуть жизнь.
Если все жизни целы — +1 к максимуму", "color": Color(1, 0.45, 0.5), "rarity": 0},
	{"id": "tank", "name": "БОЛЬШИЕ ЛЁГКИЕ", "desc": "+25% стамины", "color": Color(0.5, 0.9, 0.5), "rarity": 0},
	{"id": "shield", "name": "ПАНЦИРЬ", "desc": "Щит, который
поглотит один удар", "color": Color(0.55, 0.8, 1), "rarity": 0},
	{"id": "sprint", "name": "РЕАКТИВНЫЙ ХВОСТ", "desc": "+15% скорости спринта", "color": Color(1, 0.75, 0.3), "rarity": 0},
	{"id": "charges", "name": "ЗАПАС АТАК", "desc": "+2 заряда каждой
новой атаки медведя", "color": Color(0.6, 1, 0.45), "rarity": 0},
	{"id": "resist", "name": "КРЕПКИЙ ЛОБ", "desc": "Оглушение и замедление
на 40% короче", "color": Color(0.7, 0.7, 1), "rarity": 0},
	{"id": "knockout", "name": "НОКАУТЁР", "desc": "Оглушённые медведи
дают тройные очки", "color": Color(1, 0.55, 0.9), "rarity": 0},
	{"id": "regen", "name": "ГОРЯЧАЯ КРОВЬ", "desc": "+30% восстановления
стамины", "color": Color(1, 0.6, 0.35), "rarity": 0},
	{"id": "flex", "name": "ГИБКИЙ ХРЕБЕТ", "desc": "+20% скорости поворота", "color": Color(0.45, 0.85, 1), "rarity": 0},
	{"id": "burst", "name": "ВЗРЫВНОЙ РЫВОК", "desc": "Начало спринта — ударная волна.
Не чаще раза в 4 с", "color": Color(0.5, 1, 0.9), "rarity": 1, "unique": true},
	{"id": "leech", "name": "ВАМПИР", "desc": "Каждый 12-й съеденный
или сломанный враг
возвращает жизнь", "color": Color(0.9, 0.25, 0.35), "rarity": 1, "unique": true},
	{"id": "hoarder", "name": "ЧЕШУЙЧАТАЯ", "desc": "+50% чешуек за забег", "color": Color(1, 0.85, 0.4), "rarity": 1, "unique": true},
	{"id": "forkmaster", "name": "ЖЕЛЕЗНЫЙ ЖЕЛУДОК", "desc": "Приём даёт каждая вилка
и таблетка, а не каждая 2-я", "color": Color(0.8, 0.8, 0.85), "rarity": 1, "unique": true},
	{"id": "berserk", "name": "БЕРСЕРК", "desc": "На последней жизни атаки
бесплатны и бьют яичницу
в полтора раза сильнее", "color": Color(1, 0.35, 0.2), "rarity": 2, "unique": true},
	{"id": "phoenix", "name": "ФЕНИКС", "desc": "Смертельный удар — второй шанс:
полная стамина и две жизни.
Один раз", "color": Color(1, 0.6, 0.15), "rarity": 2, "unique": true},
]

## Множитель чешуек по сложности (лёгкая, нормальная, сложная, ультра).
const SCALE_MULT := [1.0, 1.5, 2.0, 3.0]

static var ranks: Dictionary = {}
static var scales := 0
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	load_progress()


## Перечитать сохранение (тесты и сброс прогресса).
static func load_progress() -> void:
	_loaded = true
	var data := SaveData.read_section("skills")
	scales = int(data.get("scales", 0))
	ranks.clear()
	for n in TREE:
		ranks[n["id"]] = clampi(int(data.get(n["id"], 0)), 0, int(n["max"]))


static func save() -> void:
	var values := {"scales": scales}
	for n in TREE:
		values[n["id"]] = rank(n["id"])
	SaveData.write_section("skills", values)


static func node(id: String) -> Dictionary:
	for n in TREE:
		if n["id"] == id:
			return n
	return {}


static func rank(id: String) -> int:
	return ranks.get(id, 0)


static func index(id: String) -> int:
	for i in TREE.size():
		if TREE[i]["id"] == id:
			return i
	return -1


## Узел открыт: первый в ветке или у предыдущего есть ранг.
static func unlocked(id: String) -> bool:
	var i := index(id)
	if i < 0:
		return false
	var prev := i - 1
	if prev < 0 or TREE[prev]["branch"] != TREE[i]["branch"]:
		return true
	return rank(TREE[prev]["id"]) > 0


static func cost(id: String) -> int:
	var n := node(id)
	return int(n["cost"]) * (rank(id) + 1)


static func maxed(id: String) -> bool:
	return rank(id) >= int(node(id)["max"])


static func can_buy(id: String) -> bool:
	return unlocked(id) and not maxed(id) and scales >= cost(id)


static func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	scales -= cost(id)
	ranks[id] = rank(id) + 1
	save()
	return true


## Сбросить все навыки и вернуть потраченные чешуйки.
static func reset_all() -> void:
	for n in TREE:
		var r := rank(n["id"])
		for k in r:
			scales += int(n["cost"]) * (k + 1)
		ranks[n["id"]] = 0
	save()


static func add_scales(amount: int) -> void:
	scales += amount
	save()


static func perk(id: String) -> Dictionary:
	for p in PERKS:
		if p["id"] == id:
			return p
	return {}


## Чешуйки за забег: накопленные очки прогресса × множитель сложности.
## mult — навык «Жадность» и мутация «Чешуйчатая».
static func scales_for_run(progress: float, diff: int, mult := 1.0) -> int:
	return int(progress * SCALE_MULT[clampi(diff, 0, SCALE_MULT.size() - 1)] * mult + 0.0001)  # поправка на float: 24.9999 → 25


## Случайные карточки мутаций: без повторов в раздаче, уникальные уже взятые не выпадают.
## Вес карточки — вес её редкости; «Нюх на редкое» удваивает (утраивает) редкие и легендарные.
static func roll_perks(count := 3, taken := {}, nose := 0) -> Array:
	var pool := []
	for p in PERKS:
		if not (p.get("unique", false) and taken.get(p["id"], 0) > 0):
			pool.append(p)
	var out := []
	while out.size() < count and not pool.is_empty():
		var total := 0.0
		for p in pool:
			total += perk_weight(p, nose)
		var x := randf() * total
		var pick: Dictionary = pool[pool.size() - 1]
		for p in pool:
			x -= perk_weight(p, nose)
			if x <= 0.0:
				pick = p
				break
		out.append(pick)
		pool.erase(pick)
	return out


static func perk_weight(p: Dictionary, nose := 0) -> float:
	var r := int(p.get("rarity", 0))
	var w: float = RARITY[r]["weight"]
	return w * (1.0 + nose) if r > 0 else w


## Сколько карточек в раздаче (навык «Четвёртая карта»).
static func perk_cards() -> int:
	ensure_loaded()
	return 4 if rank("lucky") > 0 else 3


## Итоговые модификаторы: дерево + улучшения забега. disabled — Ультра-Хардкор.
static func mods(perks: Dictionary, disabled: bool) -> Dictionary:
	var m := {
		"lives": 0, "stamina_max": 1.0, "regen": 1.0, "drain": 1.0, "turn": 1.0, "sprint": 1.0,
		"invuln": 0.0, "resist": 1.0, "molt": false, "charges": 0, "cost": 1.0, "boss_dmg": 1.0,
		"jaws": false, "knockout": 2, "stage_heal": false, "start_shield": 0, "loot": 0, "scales_mult": 1.0,
		"score_mult": 1.0, "nose": 0, "bounty": 0, "burst": false, "leech": 0, "fork_every": 2, "berserk": false,
		"phoenix": false,
	}
	if disabled:
		return m
	ensure_loaded()
	m["lives"] = rank("hide")
	m["stamina_max"] = 1.0 + 0.2 * rank("lungs") + 0.25 * perks.get("tank", 0)
	m["regen"] = 1.0 + 0.25 * rank("breath") + 0.3 * perks.get("regen", 0)
	m["molt"] = rank("molt") > 0
	m["turn"] = 1.0 + 0.12 * rank("flex") + 0.2 * perks.get("flex", 0)
	m["sprint"] = 1.0 + 0.08 * rank("sprinter") + 0.15 * perks.get("sprint", 0)
	m["drain"] = pow(0.85, rank("sprinter"))
	m["invuln"] = 0.5 * rank("slick")
	m["resist"] = (0.5 if rank("steady") > 0 else 1.0) * pow(0.6, perks.get("resist", 0))
	m["charges"] = rank("hoard") + 2 * perks.get("charges", 0)
	m["cost"] = pow(0.85, rank("thrift"))
	m["boss_dmg"] = 1.0 + 0.5 * rank("fangs")
	m["jaws"] = rank("jaws") > 0
	m["knockout"] = 3 if perks.get("knockout", 0) > 0 else 2
	m["stage_heal"] = rank("regrow") > 0
	m["start_shield"] = rank("tail")
	m["loot"] = rank("loot")
	m["scales_mult"] = (1.0 + 0.15 * rank("greed")) * (1.5 if perks.get("hoarder", 0) > 0 else 1.0)
	m["score_mult"] = 1.0 + 0.1 * rank("gloat")
	m["nose"] = rank("nose")
	m["bounty"] = 25 if rank("bounty") > 0 else 0
	m["burst"] = perks.get("burst", 0) > 0
	m["leech"] = 12 if perks.get("leech", 0) > 0 else 0
	m["fork_every"] = 1 if perks.get("forkmaster", 0) > 0 else 2
	m["berserk"] = perks.get("berserk", 0) > 0
	m["phoenix"] = perks.get("phoenix", 0) > 0
	return m
