extends RefCounted
## Картотека врагов: карточка открывается, когда враг (или приём вилки) впервые появляется на поле.
## Хранится в user://save.dat, раздел [bestiary]. Отладочные забеги карточки не открывают.
## v12.4: у карточки есть дело — сколько раз встречен и побеждён, на каком этапе впервые, и метка
## «НОВОЕ», пока карточку не открыли в картотеке. Старые сохранения (просто true) переводятся сами.
## Счётчики копятся в памяти и пишутся на диск в flush() — в конце забега, а не на каждого медведя.

const SaveData = preload("res://scripts/core/save_data.gd")

const SECTION := "bestiary"

## Вкладки картотеки: подпись и группы карточек (ENTRIES.group), которые на ней видны. Первая — все.
const TABS := [
	{"name": "ВСЕ", "groups": []},
	{"name": "МЕДВЕДИ", "groups": ["МЕДВЕДИ"]},
	{"name": "ВИЛКИ", "groups": ["ВИЛКИ", "ПРИЁМЫ ВИЛОК"]},
	{"name": "ТАБЛЕТКИ", "groups": ["ТАБЛЕТКИ"]},
	{"name": "МАТРЁШКИ", "groups": ["МАТРЁШКИ"]},
	{"name": "ПРОЧЕЕ", "groups": ["БОСС", "ДОСЬЕ"]},
]
## Где встречается группа — подсказка на пустой карточке.
const WHERE := {"МЕДВЕДИ": "на этапе «Медведи» и дальше помощниками", "ВИЛКИ": "на этапе «Вилки»",
	"ПРИЁМЫ ВИЛОК": "на этапе «Вилки» — смотри, чем вилка бьёт", "ТАБЛЕТКИ": "на этапе «Таблетки», шипучки — ближе к концу",
	"МАТРЁШКИ": "в тереме матрёшек", "БОСС": "в конце забега", "ДОСЬЕ": "после победы над яичницей"}

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
	{"key": "pill_2", "icon": "pill", "arg": 2, "title": "Шипучка", "group": "ТАБЛЕТКИ",
		"text": "Растворимая. Скачет серией из трёх коротких прыжков, а потом растекается шипящей лужей.",
		"weak": "Волны нет, прыжки низкие. После серии — долгая пауза.",
		"tip": "Пена вязкая: в луже змея ползёт медленнее. Обходи её и кусай шипучку, пока она отдыхает."},
	{"key": "doll_2", "icon": "doll", "arg": 2, "title": "Большая матрёшка", "group": "МАТРЁШКИ",
		"text": "Переваливается с боку на бок и неторопливо уходит. Укус раскрывает её — внутри две средние.",
		"weak": "Медленная. Оглушённую раскрыть выгоднее.",
		"tip": "На Сложной и Ультра водит хоровод: лента путает, выход — просвет по курсу."},
	{"key": "doll_1", "icon": "doll", "arg": 1, "title": "Средняя матрёшка", "group": "МАТРЁШКИ",
		"text": "Удирает зигзагом, в угол не бежит. Внутри — малышка.", "weak": "Вдоль бортика её легко догнать.",
		"tip": "Две средние бегут в разные стороны — выбери одну и не мечись."},
	{"key": "doll_0", "icon": "doll", "arg": 0, "title": "Малышка-юла", "group": "МАТРЁШКИ",
		"text": "Последняя, цельная, без шва. Не убегает — раскручивается и несётся волчком, отскакивая от бортика.",
		"weak": "Докрутившись, шатается — зелёная кромка. Пока крутится — не укусить.",
		"tip": "Полоса на полу — дорожка юлы: шагни вбок, а не назад. Съешь последнюю малышку — набор собран. Даёт прыжок малышки."},
	{"key": "boss", "icon": "egg", "arg": 0, "title": "Гигантская Яичница", "group": "БОСС",
		"text": "Три фазы. Читает твою манеру: кружишь — бьёт наперерез, держишься далеко — прыгает и плюётся горящим маслом.",
		"weak": "Открытый желток. Таран в бортик и серия прыжков — окна: желток открыт.",
		"tip": "Уведи таран в бортик. Снаряды в желток бьют втрое сильнее."},
	{"key": "scientist", "icon": "scientist", "arg": 0, "title": "Учёный-бюрократ", "group": "ДОСЬЕ",
		"text": "Ведёт эксперимент №47 строго по регламенту: пункт 12-Б, протокол, подпись. Носит халат поверх костюма и спички в кармане.",
		"weak": "Регламент. Всё, чего нет в инструкции, для него не существует — в том числе щель в тумбе.",
		"tip": "Досье открывается после победы над яичницей. Держись от спичек подальше."},
]

static var _cache: Dictionary = {}  # key → {"met", "beaten", "stage", "new"}
static var _loaded := false
static var _dirty := false


static func ensure_loaded() -> void:
	if not _loaded:
		load_progress()


static func load_progress() -> void:
	_cache = {}
	var raw := SaveData.read_section(SECTION)
	for key: String in raw:
		_cache[key] = _record(raw[key])
	_loaded = true
	_dirty = false


## Запись карточки из сохранения: старое true (до 12.4) — открыта, счётчики неизвестны.
static func _record(v: Variant) -> Dictionary:
	var r := {"met": 1, "beaten": 0, "stage": -1, "new": false}
	if typeof(v) == TYPE_DICTIONARY:
		for k: String in r:
			if (v as Dictionary).has(k):
				r[k] = v[k]
		r["met"] = maxi(int(r["met"]), 1)
		r["beaten"] = maxi(int(r["beaten"]), 0)
	return r


static func is_known(key: String) -> bool:
	ensure_loaded()
	return _cache.has(key)


## Открыть карточку. true — открыта только что (впервые). stage — на каком этапе встретили.
static func unlock(key: String, save := true, stage := -1) -> bool:
	ensure_loaded()
	if entry(key).is_empty() or is_known(key):
		return false
	_cache[key] = {"met": 1, "beaten": 0, "stage": stage, "new": true}
	_dirty = true
	if save:
		flush()
	return true


## Враг снова на поле (карточка уже открыта) — счётчик встреч.
static func note_met(key: String) -> void:
	ensure_loaded()
	if _cache.has(key):
		_cache[key]["met"] = int(_cache[key]["met"]) + 1
		_dirty = true


## Враг побеждён: съеден, сломан, раскрыт.
static func note_beaten(key: String) -> void:
	ensure_loaded()
	if _cache.has(key):
		_cache[key]["beaten"] = int(_cache[key]["beaten"]) + 1
		_dirty = true


static func stats(key: String) -> Dictionary:
	ensure_loaded()
	return _cache.get(key, {})


static func is_new(key: String) -> bool:
	return bool(stats(key).get("new", false))


## Карточку открыли в картотеке — метка «НОВОЕ» гаснет.
static func mark_read(key: String) -> void:
	ensure_loaded()
	if is_new(key):
		_cache[key]["new"] = false
		_dirty = true
		flush()


static func new_count() -> int:
	var n := 0
	for e: Dictionary in ENTRIES:
		if is_new(e["key"]):
			n += 1
	return n


## Записать накопленное на диск (одной записью).
static func flush() -> void:
	if not _dirty:
		return
	SaveData.write_section(SECTION, _cache)
	_dirty = false


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


## Карточки вкладки (индексы в ENTRIES).
static func tab_entries(tab: int) -> Array[int]:
	var groups: Array = TABS[clampi(tab, 0, TABS.size() - 1)]["groups"]
	var out: Array[int] = []
	for i in ENTRIES.size():
		if groups.is_empty() or ENTRIES[i]["group"] in groups:
			out.append(i)
	return out


## [открыто, всего] на вкладке.
static func tab_progress(tab: int) -> Vector2i:
	var ids := tab_entries(tab)
	var known := 0
	for i in ids:
		if is_known(ENTRIES[i]["key"]):
			known += 1
	return Vector2i(known, ids.size())


static func where_text(e: Dictionary) -> String:
	return "Встречается " + String(WHERE.get(e["group"], "где-то в эксперименте")) + "."


static func reset() -> void:
	SaveData.erase_section(SECTION)
	load_progress()
