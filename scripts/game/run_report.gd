extends RefCounted
## Строки экрана итогов: сложность, этап, враги, время, счёт, рекорд, чешуйки.

const Balance = preload("res://scripts/core/balance.gd")
const Skills = preload("res://scripts/core/skills.gd")


static func rows(g, win: bool, record: bool, best: int) -> Array:
	var secs := int(g.play_time)
	var rows := [
		["Сложность", g.cfg["name"]],
		["Дошла до этапа", Balance.STAGES[g.stage]["name"]],
		["Медведи / вилки / таблетки", "%d / %d / %d" % [g.bears_eaten, g.forks_broken, g.pills_eaten]],
	]
	if g.enemies.friendly_hits > 0:
		rows.append(["Враги подрались", "%d раз" % g.enemies.friendly_hits])
	if win and g.ending:
		rows.append(["Спичка", g.ending.choice_text()])
	rows.append(["Время", "%d:%02d" % [secs / 60, secs % 60]])
	rows.append(["Счёт", "%d%s" % [g.score, "  — НОВЫЙ РЕКОРД!" if record else ""], record])
	rows.append(["Рекорд", str(best)])
	rows.append(["Чешуйки", "+%d  (всего %d)" % [g.scales_gained, Skills.scales], g.scales_gained > 0])
	if g.debug_run:
		rows.append(["Отладочный забег", "результат не сохранён"])
	return rows


static func headline(win: bool) -> String:
	return "Змея одолела яичницу... но не своего создателя." if win else "Не сдавайся — яичница ждёт!"
