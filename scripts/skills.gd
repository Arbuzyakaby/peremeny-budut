extends RefCounted
## Древо навыков змеи и улучшения забега.
## - Постоянное дерево: 3 ветки по 4 узла, у узлов ранги. Покупается за «чешуйки», которые змея
##   зарабатывает в забегах. Узел открывается, когда у предыдущего в ветке есть хотя бы 1 ранг.
##   Хранится в user://save.cfg (секция [skills]) и живёт в static-переменных.
## - Улучшения забега: перед каждым новым этапом игрок выбирает одну из трёх карточек.
## Всё сводится в словарь модификаторов (mods), который применяют змея и игра.
## На Ультра-Хардкоре навыки и улучшения отключены.

const SAVE_PATH := "user://save.cfg"

const BRANCHES := [
	{"name": "ТЕЛО", "color": Color(0.95, 0.45, 0.4)},
	{"name": "МАНЁВР", "color": Color(0.45, 0.8, 1.0)},
	{"name": "АТАКА", "color": Color(0.6, 1.0, 0.45)},
]

## Узлы по веткам сверху вниз. cost — цена первого ранга, дальше растёт кратно рангу.
const TREE := [
	{"id": "hide", "branch": 0, "name": "Толстая шкура", "desc": "+1 жизнь за ранг", "max": 2, "cost": 8},
	{"id": "lungs", "branch": 0, "name": "Выносливость", "desc": "+20% стамины за ранг", "max": 3, "cost": 6},
	{"id": "breath", "branch": 0, "name": "Второе дыхание", "desc": "+25% восстановления стамины за ранг", "max": 2, "cost": 10},
	{"id": "molt", "branch": 0, "name": "Линька", "desc": "Раз за забег сбросить шкуру и пережить смертельный удар", "max": 1, "cost": 35},
	{"id": "flex", "branch": 1, "name": "Гибкость", "desc": "+12% скорости поворота за ранг", "max": 3, "cost": 5},
	{"id": "sprinter", "branch": 1, "name": "Спринтер", "desc": "+8% скорости спринта и −15% расхода за ранг", "max": 2, "cost": 9},
	{"id": "slick", "branch": 1, "name": "Скользкая чешуя", "desc": "+0.5 с неуязвимости после удара за ранг", "max": 2, "cost": 12},
	{"id": "steady", "branch": 1, "name": "Устойчивость", "desc": "Оглушение и замедление вдвое короче", "max": 1, "cost": 30},
	{"id": "hoard", "branch": 2, "name": "Запасливость", "desc": "+1 заряд каждой атаки за ранг", "max": 3, "cost": 6},
	{"id": "thrift", "branch": 2, "name": "Экономия", "desc": "Атаки тратят на 15% меньше стамины за ранг", "max": 2, "cost": 10},
	{"id": "fangs", "branch": 2, "name": "Острые зубы", "desc": "+50% урона атаками по яичнице за ранг", "max": 2, "cost": 12},
	{"id": "jaws", "branch": 2, "name": "Сильные челюсти", "desc": "Укус желтка снимает 2 деления", "max": 1, "cost": 40},
]

## Улучшения забега (карточки между этапами).
const PERKS := [
	{"id": "heal", "name": "ВТОРОЕ СЕРДЦЕ", "desc": "Вернуть жизнь.\nЕсли всё целы — +1 к максимуму", "color": Color(1, 0.45, 0.5)},
	{"id": "tank", "name": "БОЛЬШИЕ ЛЁГКИЕ", "desc": "+25% стамины", "color": Color(0.5, 0.9, 0.5)},
	{"id": "shield", "name": "ПАНЦИРЬ", "desc": "Щит, который\nпоглотит один удар", "color": Color(0.55, 0.8, 1)},
	{"id": "sprint", "name": "РЕАКТИВНЫЙ ХВОСТ", "desc": "+15% скорости спринта", "color": Color(1, 0.75, 0.3)},
	{"id": "charges", "name": "ЗАПАС АТАК", "desc": "+2 заряда каждой\nновой атаки", "color": Color(0.6, 1, 0.45)},
	{"id": "resist", "name": "КРЕПКИЙ ЛОБ", "desc": "Оглушение и замедление\nна 40% короче", "color": Color(0.7, 0.7, 1)},
	{"id": "knockout", "name": "НОКАУТЁР", "desc": "Оглушённые медведи\nдают тройные очки", "color": Color(1, 0.55, 0.9)},
	{"id": "regen", "name": "ГОРЯЧАЯ КРОВЬ", "desc": "+30% восстановления\nстамины", "color": Color(1, 0.6, 0.35)},
	{"id": "flex", "name": "ГИБКИЙ ХРЕБЕТ", "desc": "+20% скорости поворота", "color": Color(0.45, 0.85, 1)},
]

## Множитель чешуек по сложности (лёгкая, нормальная, сложная, ультра).
const SCALE_MULT := [1.0, 1.5, 2.0, 3.0]

static var ranks: Dictionary = {}
static var scales := 0
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	scales = cf.get_value("skills", "scales", 0)
	for node in TREE:
		ranks[node["id"]] = cf.get_value("skills", node["id"], 0)


static func save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("skills", "scales", scales)
	for node in TREE:
		cf.set_value("skills", node["id"], rank(node["id"]))
	cf.save(SAVE_PATH)


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


## Три случайные карточки улучшений.
static func roll_perks(count := 3) -> Array:
	var pool := PERKS.duplicate()
	pool.shuffle()
	return pool.slice(0, count)


## Итоговые модификаторы: дерево + улучшения забега. disabled — Ультра-Хардкор.
static func mods(perks: Dictionary, disabled: bool) -> Dictionary:
	var m := {
		"lives": 0, "stamina_max": 1.0, "regen": 1.0, "drain": 1.0, "turn": 1.0, "sprint": 1.0,
		"invuln": 0.0, "resist": 1.0, "molt": false, "charges": 0, "cost": 1.0, "boss_dmg": 1.0,
		"jaws": false, "knockout": 2,
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
	return m
