extends RefCounted
## Картотека врагов: карточка открывается, когда враг (или приём вилки) впервые появляется на поле.
## Хранится в user://save.cfg, раздел [bestiary]. Отладочные забеги карточки не открывают.

const SaveData = preload("res://scripts/core/save_data.gd")

const SECTION := "bestiary"

## Порядок карточек в картотеке. icon — что рисует экран (см. bestiary_screen.gd), arg — вариант.
const ENTRIES := [
	{"key": "bear_0", "icon": "bear", "arg": 0, "title": "Плюшевый медведь", "group": "МЕДВЕДИ",
		"text": "Бродит без цели и убегает от змеи.", "weak": "Съедается с любой стороны.",
		"tip": "Лёгкая добыча. На Ультра бывает обманщиком: картонные звёзды — приманка под удар."},
	{"key": "bear_1", "icon": "bear", "arg": 1, "title": "Боксёр", "group": "МЕДВЕДИ",
		"text": "Приседает и бросается рывком по прямой.", "weak": "После промаха кружится голова.",
		"tip": "Сойди с линии рывка и кусай оглушённого. Даёт удар с разбега."},
	{"key": "bear_2", "icon": "bear", "arg": 2, "title": "Метатель", "group": "МЕДВЕДИ",
		"text": "Кидает пуговицы с упреждением.", "weak": "Пока целится, стоит на месте.",
		"tip": "Резко меняй курс. Даёт выстрел пуговицами."},
	{"key": "bear_3", "icon": "bear", "arg": 3, "title": "Каратист", "group": "МЕДВЕДИ",
		"text": "Кружит вокруг и бьёт ногой на два урона.", "weak": "Замах перед ударом.",
		"tip": "Жди замаха и заходи сбоку. Даёт вертушку."},
	{"key": "bear_4", "icon": "bear", "arg": 4, "title": "Швея", "group": "МЕДВЕДИ",
		"text": "Стреляет веером иголок, иголка пришивает — замедляет.", "weak": "Долго прицеливается.",
		"tip": "Уходи поперёк веера. Даёт иглы."},
	{"key": "bear_5", "icon": "bear", "arg": 5, "title": "Ниндзя", "group": "МЕДВЕДИ",
		"text": "Исчезает в дыму и появляется сбоку, кидает сюрикены.", "weak": "После броска виден.",
		"tip": "Дым — сигнал сменить курс. Даёт теневой рывок."},
	{"key": "bear_6", "icon": "bear", "arg": 6, "title": "Хлопушка", "group": "МЕДВЕДИ",
		"text": "Катит хлопушки, которые взрываются.", "weak": "Взрыв задевает и медведей.",
		"tip": "Подставь соседей под взрыв. Даёт хлопушку."},
	{"key": "bear_7", "icon": "bear", "arg": 7, "title": "Медсестра", "group": "МЕДВЕДИ",
		"text": "Ставит союзникам пузырь-щит.", "weak": "Сама без щита.",
		"tip": "Съешь её первой. Даёт заплатку — щит для змеи."},
	{"key": "fork_0", "icon": "fork", "arg": 0, "title": "Столовая вилка", "group": "ВИЛКИ",
		"text": "Сталь в рыжей ржавчине. Все четыре приёма.", "weak": "Бок, ручка, спина.",
		"tip": "Никогда не бей в лоб — там зубцы."},
	{"key": "fork_1", "icon": "fork", "arg": 1, "title": "Десертная вилка", "group": "ВИЛКИ",
		"text": "Латунная, мелкая и шустрая. Любит вертушку.", "weak": "Три зубца — узкий веер.",
		"tip": "После вертушки кружится — лучший момент."},
	{"key": "fork_2", "icon": "fork", "arg": 2, "title": "Вилы", "group": "ВИЛКИ",
		"text": "Тяжёлая бронза с патиной. Прыгает и колет сверху.", "weak": "Медленная, застревает в полу.",
		"tip": "Уйди из красного круга и кусай воткнутую."},
	{"key": "fork_atk_0", "icon": "fork_atk", "arg": 0, "title": "Приём: Выпад", "group": "ПРИЁМЫ ВИЛОК",
		"text": "Пунктир — линия рывка. Врезавшись в бортик, вилка застревает.", "weak": "Застрявшая вилка.",
		"tip": "Шаг в сторону — и кусай, пока она дёргается в бортике."},
	{"key": "fork_atk_1", "icon": "fork_atk", "arg": 1, "title": "Приём: Залп зубцов", "group": "ПРИЁМЫ ВИЛОК",
		"text": "Жёлтый веер — сейчас полетят зубцы.", "weak": "Потом вилка беззубая.",
		"tip": "Беззубую можно бить даже в лоб."},
	{"key": "fork_atk_2", "icon": "fork_atk", "arg": 2, "title": "Приём: Вертушка", "group": "ПРИЁМЫ ВИЛОК",
		"text": "Крутится и едет на змею, режет со всех сторон.", "weak": "Головокружение после.",
		"tip": "Отступи. Рывок сбивает вертушку."},
	{"key": "fork_atk_3", "icon": "fork_atk", "arg": 3, "title": "Приём: Прыжок-укол", "group": "ПРИЁМЫ ВИЛОК",
		"text": "Прыгает, втыкается зубцами в красный круг.", "weak": "Застревает в полу.",
		"tip": "В прыжке вилка неуязвима — жди приземления."},
	{"key": "pill", "icon": "pill", "arg": 0, "title": "Прыгающая таблетка", "group": "ТАБЛЕТКИ",
		"text": "Капсула. Прыгает на змею высоко и далеко, давит, волна оглушает.", "weak": "На земле съедобна.",
		"tip": "Тень показывает место приземления."},
	{"key": "pill_1", "icon": "pill", "arg": 1, "title": "Таблетка-шайба", "group": "ТАБЛЕТКИ",
		"text": "Катится на ребре к змее и прыгает низко, но часто.", "weak": "Прыжок короче, после него — пауза.",
		"tip": "Не жди её на месте: отойди на пару корпусов и лови после приземления."},
	{"key": "boss", "icon": "egg", "arg": 0, "title": "Гигантская Яичница", "group": "БОСС",
		"text": "Три фазы. Читает твою манеру: кружишь — бьёт наперерез, держишься далеко — прыгает и плюётся горящим маслом.",
		"weak": "Открытый желток. Таран в бортик и серия прыжков — окна: желток открыт.",
		"tip": "Уведи таран в бортик. Снаряды в желток бьют втрое сильнее."},
]

static var _cache: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if not _loaded:
		load_progress()


static func load_progress() -> void:
	_cache = SaveData.read_section(SECTION)
	_loaded = true


static func is_known(key: String) -> bool:
	ensure_loaded()
	return bool(_cache.get(key, false))


## Открыть карточку. true — открыта только что (впервые).
static func unlock(key: String, save := true) -> bool:
	ensure_loaded()
	if entry(key).is_empty() or is_known(key):
		return false
	_cache[key] = true
	if save:
		SaveData.write_section(SECTION, {key: true})
	return true


static func entry(key: String) -> Dictionary:
	for e: Dictionary in ENTRIES:
		if e["key"] == key:
			return e
	return {}


static func known_count() -> int:
	ensure_loaded()
	var n := 0
	for e: Dictionary in ENTRIES:
		if is_known(e["key"]):
			n += 1
	return n


static func total() -> int:
	return ENTRIES.size()


static func reset() -> void:
	var cf := SaveData.load_file()
	if cf.has_section(SECTION):
		cf.erase_section(SECTION)
	cf.save(SaveData.path)
	load_progress()
