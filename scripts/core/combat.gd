extends RefCounted
## Чистые боевые расчёты без сцены — их проверяют юнит-тесты.

const Balance = preload("res://scripts/core/balance.gd")


## Урон атакой змеи по яичнице с учётом навыка «Острые зубы».
static func boss_chip(kind: String, mods: Dictionary) -> float:
	return float(Balance.BOSS_CHIP[kind]) * float(mods.get("boss_dmg", 1.0))


## Урон снаряда змеи (kind — "button", "needle" или "tine"); в открытый желток — втрое больше.
static func shot_chip(kind: String, into_yolk: bool, mods: Dictionary) -> float:
	var amount := boss_chip(kind, mods)
	return amount * (Balance.YOLK_SHOT_MULT if into_yolk else 1.0)


## Очки с учётом множителя сложности.
static func points(base: int, diff: Dictionary) -> int:
	return base * int(diff["score_mult"])


## Очки за медведя: оглушённый — вдвое (с улучшением «Нокаутёр» — втрое).
static func bear_points(type: int, dizzy: bool, diff: Dictionary, mods: Dictionary) -> int:
	var p: int = Balance.BEAR_POINTS[type]
	if dizzy:
		p *= int(mods.get("knockout", 2))
	return points(p, diff)


## Сколько атак даёт съеденный медведь (с навыком «Запасливость» и улучшением «Запас атак»).
## «Запасливость» и «Запас атак» — только для медвежьих атак: вилки и таблетки дают ровно свои 1–2.
static func ability_charges(type: int, mods: Dictionary) -> int:
	var info: Dictionary = Balance.ABILITIES[type]
	var bonus := int(mods.get("charges", 0)) if info["source"] == "bear" else 0
	return int(info["charges"]) + bonus


## Сколько зарядов атаки можно накопить (с навыками — чуть больше).
static func ability_max(type: int, mods: Dictionary) -> int:
	var info: Dictionary = Balance.ABILITIES[type]
	return int(info["max"]) + (int(mods.get("charges", 0)) if info["source"] == "bear" else 0)


static func ability_cost(type: int, mods: Dictionary) -> float:
	return float(Balance.ABILITIES[type]["cost"]) * float(mods.get("cost", 1.0))
