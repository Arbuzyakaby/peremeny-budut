extends RefCounted
## Игровой баланс: сложности, этапы, атаки змеи, очки. Только данные — логика живёт в game/.

const Tex = preload("res://scripts/gfx/tex.gd")

const ARENA := Rect2(0, 0, 1280, 720)
const WALL := 24.0
const BEARS_ON_FIELD := 5
const HELPERS_MAX := 2          # медведей-помощников на этапах вилок и таблеток
const HELPER_INTERVAL := 7.0
const REINFORCE_MAX := 3        # помощников яичницы одновременно
const REINFORCE_INTERVAL := 7.5
const SPIN_RADIUS := 130.0
const STAGE_COUNT := 5
const BOSS_STAGE := 4
const DOLL_STAGE := 3
## Технический режим «Контакт» (v10.0): сколько врагов убедить на этапах медведей, вилок, таблеток и
## матрёшек (ровно столько их и выходит на поле); на пятом — одна яичница.
const CONTACT_GOALS := [5, 4, 4, 3]
const DOLL_SETS_ON_FIELD := 2  # сколько больших матрёшек раскрывается одновременно

const DIFFICULTIES := [
	{
		"name": "ЛЁГКАЯ", "color": Color(0.4, 0.85, 0.4),
		"lives": 5, "bears": 10, "forks": 5, "pills": 5, "dolls": 3, "bear_speed": 0.85, "bear_aggr": 0.6,
		"boss_hp": 9, "proj_speed": 0.8, "yolk_time": 1.35, "tempo": 1.3, "score_mult": 1, "no_skills": false, "coop": 0,
		"desc": "5 жизней • 10 медведей, 5 вилок, 5 таблеток, 3 матрёшки\nВраги неторопливые, яичница добрая",
	},
	{
		"name": "НОРМАЛЬНАЯ", "color": Color(1, 0.8, 0.25),
		"lives": 3, "bears": 15, "forks": 7, "pills": 7, "dolls": 4, "bear_speed": 1.0, "bear_aggr": 1.0,
		"boss_hp": 12, "proj_speed": 1.0, "yolk_time": 1.0, "tempo": 1.0, "score_mult": 2, "no_skills": false, "coop": 0,
		"desc": "3 жизни • 15 медведей, 7 вилок, 7 таблеток, 4 матрёшки\nВсе враги и яичница в полную силу",
	},
	{
		"name": "СЛОЖНАЯ", "color": Color(1, 0.35, 0.3),
		"lives": 2, "bears": 20, "forks": 9, "pills": 9, "dolls": 5, "bear_speed": 1.2, "bear_aggr": 1.5,
		"boss_hp": 15, "proj_speed": 1.25, "yolk_time": 0.75, "tempo": 0.75, "score_mult": 3, "no_skills": false, "coop": 1,
		"desc": "2 жизни • 20 медведей, 9 вилок, 9 таблеток, 5 матрёшек\nВраги помогают друг другу, яичница бешеная",
	},
	{
		"name": "УЛЬТРА-ХАРДКОР", "color": Color(0.85, 0.3, 1.0),
		"lives": 1, "bears": 25, "forks": 12, "pills": 12, "dolls": 6, "bear_speed": 1.35, "bear_aggr": 2.0,
		"boss_hp": 18, "proj_speed": 1.45, "yolk_time": 0.6, "tempo": 0.6, "score_mult": 5, "no_skills": true, "coop": 2,
		"desc": "1 жизнь • 25 медведей, 12 вилок, 12 таблеток, 6 матрёшек\nНавыки ОТКЛЮЧЕНЫ, враги нападают стаей. Очки ×5",
	},
]

## Этапы забега. key — ключ цели в таблице сложности.
const STAGES := [
	{"name": "МЕДВЕДИ", "short": "МЕДВЕДИ", "music": "level", "floor": Tex.Floor.WOOD, "key": "bears",
		"hint": "Съешь плюшевых медведей — каждый особый медведь даёт свою атаку"},
	{"name": "РЖАВЫЕ ВИЛКИ", "short": "ВИЛКИ", "music": "forks", "floor": Tex.Floor.DRAWER, "key": "forks",
		"hint": "Вилки колют, стреляют зубцами, крутятся и прыгают. НЕ БЕЙ В ЛОБ — кусай сбоку или сзади"},
	{"name": "ПРЫГАЮЩИЕ ТАБЛЕТКИ", "short": "ТАБЛЕТКИ", "music": "pills", "floor": Tex.Floor.TILES, "key": "pills",
		"hint": "Таблетки давят сверху, а волна оглушает. Ешь их, пока они на земле"},
	{"name": "ТЕРЕМ МАТРЁШЕК", "short": "МАТРЁШКИ", "music": "dolls", "floor": Tex.Floor.TEREM, "key": "dolls",
		"hint": "Укус раскрывает матрёшку. Большая делится надвое, малышка крутится юлой — уйди с её дорожки и съешь её"},
	{"name": "ГИГАНТСКАЯ ЯИЧНИЦА", "short": "ЯИЧНИЦА", "music": "boss", "floor": Tex.Floor.PAN, "key": "",
		"hint": ""},
]

## Атаки, которые змея перенимает (ключ — тип атаки). 1–7 — у съеденных особых медведей (тип медведя
## из teddy_bear.gd), 10–13 — у сломанных вилок и съеденных таблеток (v8.0), 14 — у съеденных малышек-матрёшек (v9.0).
## v8.0: медвежьи атаки ослаблены — меньше зарядов, дороже по стамине, слабее по яичнице (BOSS_CHIP);
## атаки вилок и таблеток ещё скромнее: 1–2 заряда, выдаются за каждую FORK_PILL_EVERY-ю вилку или
## таблетку и только в пустой слот (или в ту же атаку), не больше max зарядов.
const ABILITIES := {
	1: {"name": "УДАР С РАЗБЕГА", "charges": 2, "cost": 0.3, "source": "bear", "max": 6},
	2: {"name": "ПУГОВИЦЫ", "charges": 6, "cost": 0.1, "source": "bear", "max": 12},
	3: {"name": "ВЕРТУШКА", "charges": 2, "cost": 0.35, "source": "bear", "max": 6},
	4: {"name": "ИГЛЫ", "charges": 4, "cost": 0.18, "source": "bear", "max": 10},
	5: {"name": "ТЕНЕВОЙ РЫВОК", "charges": 2, "cost": 0.25, "source": "bear", "max": 6},
	6: {"name": "ХЛОПУШКА", "charges": 3, "cost": 0.2, "source": "bear", "max": 8},
	7: {"name": "ЗАПЛАТКА", "charges": 1, "cost": 0.4, "source": "bear", "max": 2},
	10: {"name": "ЗАЛП ЗУБЦОВ", "charges": 2, "cost": 0.22, "source": "fork", "max": 4},
	11: {"name": "ВЫПАД", "charges": 2, "cost": 0.3, "source": "fork", "max": 4},
	12: {"name": "УКОЛ ВИЛАМИ", "charges": 1, "cost": 0.3, "source": "fork", "max": 2},
	13: {"name": "УДАРНАЯ ВОЛНА", "charges": 1, "cost": 0.3, "source": "pill", "max": 2},
	14: {"name": "ПРЫЖОК МАЛЫШКИ", "charges": 2, "cost": 0.28, "source": "doll", "max": 4},
}
## Атака от вилки по её виду (Fork.Kind: столовая, десертная, вилы) и от таблетки.
const FORK_ABILITY := [10, 11, 12]
const PILL_ABILITY := 13
const DOLL_ABILITY := 14
const FORK_PILL_EVERY := 2      # атаку даёт каждая 2-я сломанная вилка / съеденная таблетка
const ABILITY_COOLDOWN := 0.3   # между атаками, с (нельзя «пулемётить» пуговицами)
const TINE_RANGE := 0.55        # залп зубцов змеи летит недалеко (секунды жизни зубца)
const POGO_REACH := 70.0        # укол вилами: точка удара впереди головы
const POGO_RADIUS := 78.0
const PILL_WAVE_REACH := 180.0  # ударная волна таблетки: радиус оглушения
const PILL_WAVE_STUN := 1.4
const HOP_TIME := 0.32          # прыжок малышки: столько змея в воздухе (неуязвима)
const HOP_RADIUS := 84.0        # и такой круг давит при приземлении

## Очки (умножаются на score_mult сложности).
const BEAR_POINTS := [10, 20, 15, 25, 20, 30, 25, 20]
const FORK_POINTS := 30
const PILL_POINTS := 25
const DOLL_OPEN_POINTS := 10    # раскрыть большую или среднюю матрёшку
const DOLL_POINTS := 20         # съесть малышку
const DOLL_SET_POINTS := 40     # весь набор собран
const FRIENDLY_POINTS := 5
const STAGE_POINTS := 200
const YOLK_POINTS := 100
const BOSS_POINTS := 1000

## Чешуйки за забег (до множителя сложности из skills.gd).
const SCALES_PER_GOAL := 1.0
const SCALES_PER_STAGE := 10.0
const SCALES_PER_BOSS := 30.0

## Урон по яичнице разными атаками (в «делениях», до множителя навыков).
const BOSS_CHIP := {
	"fork": 0.5, "cracker": 0.6, "spin": 0.4, "dash": 0.45, "button": 0.2, "needle": 0.14,
	"tine": 0.12, "lunge": 0.3, "pogo": 0.35, "hop": 0.4,
}
const YOLK_SHOT_MULT := 3.0


static func difficulty(i: int) -> Dictionary:
	return DIFFICULTIES[clampi(i, 0, DIFFICULTIES.size() - 1)]


static func goal(diff: Dictionary, stage: int) -> int:
	var key: String = STAGES[stage]["key"]
	return int(diff[key]) if key != "" else 0
