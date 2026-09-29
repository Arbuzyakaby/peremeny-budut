extends RefCounted
## Строки экрана итогов: сложность, этап, враги, спичка и сожжённое в финале, время, счёт, рекорд, чешуйки.

const Balance = preload("res://scripts/core/balance.gd")
const Skills = preload("res://scripts/core/skills.gd")
const Credits = preload("res://scripts/ending/credits.gd")
const Daily = preload("res://scripts/core/daily.gd")
const Design = preload("res://scripts/ui/design.gd")


static func rows(g, win: bool, record: bool, best: int) -> Array:
	var secs := int(g.play_time)
	var rows := [
		["Сложность", g.cfg["name"]],
		["Дошла до этапа", Balance.STAGES[g.stage]["name"]],
		["Медведи / вилки / таблетки / матрёшки", "%d / %d / %d / %d" % [g.bears_eaten, g.forks_broken, g.pills_eaten,
			g.dolls_done]],
	]
	if g.daily_mode and not g.daily.is_empty():  # испытание дня — не просто «Нормальная»
		rows.insert(1, ["Испытание дня", String(g.daily.get("name", ""))])
	if g.enemies.friendly_hits > 0:
		rows.append(["Враги подрались", "%d раз" % g.enemies.friendly_hits])
	if win and g.ending:
		rows.append(["Спичка", g.ending.choice_text()])
		var burnt: int = g.ending.fire.burnt_cells() if is_instance_valid(g.ending.fire) else 0
		if burnt > 0:  # зола остаётся навсегда — и в итогах тоже, даже если финал пропустили
			rows.append(["Ящик", Credits.burnt_line(burnt)])
	rows.append(["Время", "%d:%02d" % [secs / 60, secs % 60]])
	rows.append(["Счёт", "%d%s" % [g.score, "  — НОВЫЙ РЕКОРД!" if record else ""], record])
	rows.append(["Рекорд", str(best)])
	if g.streak_bonus > 0:
		rows.append(["Серия испытаний", "%s подряд: +%s" % [Design.plural(Daily.streak(), "день", "дня", "дней"), Design.scales_text(g.streak_bonus)], true])
	rows.append(["Чешуйки", "+%d  (всего %d)" % [g.scales_gained, Skills.scales], g.scales_gained > 0])
	if g.debug_run and g.guard.flagged():
		rows.append(["Забег не засчитан", g.guard.reason])
	elif g.debug_run:
		rows.append(["Отладочный забег", "результат не сохранён"])
	return rows


static func headline(win: bool) -> String:
	return "Змея одолела яичницу... но не своего создателя." if win else "Не сдавайся — яичница ждёт!"
