extends RefCounted
## Титры финала со статистикой забега. В протоколе — и сколько клеток ящика сгорело.


## burnt — сожжённых клеток ящика (fire.burnt_cells()); −1 — строку не показывать.
static func text(game, choice_line: String, burnt := -1) -> String:
	var mins := int(game.play_time) / 60
	var secs := int(game.play_time) % 60
	var lines := [
		"ЗМЕЯ ПРОТИВ ГИГАНТСКОЙ ЯИЧНИЦЫ", "версия %s" % ProjectSettings.get_setting("application/config/version", "5.0"), "",
		"ПРОТОКОЛ ЭКСПЕРИМЕНТА №47",
		"Сложность: %s" % game.cfg["name"],
		"Медведей съедено: %d" % game.bears_eaten,
		"Вилок сломано: %d" % game.forks_broken,
		"Таблеток съедено: %d" % game.pills_eaten,
		"Матрёшек собрано: %d наб." % game.dolls_done,
		"Время: %d:%02d   •   Счёт: %d" % [mins, secs, game.score],
	]
	if burnt >= 0:
		lines.append(burnt_line(burnt))
	lines.append_array([
		choice_line, "",
		"В РОЛЯХ",
		"Змея — образец №47",
		"Гигантская Яичница — сама себя",
		"Учёный-бюрократ — пункт 12-Б",
		"Медведи, вилки, таблетки и матрёшки — массовка",
		"Змейка — образец №48", "",
		"Графика и звук сгенерированы кодом.",
		"Ни одной картинки. Ни одного аудиофайла.", "",
		"Перемены будут.",
	])
	return "\n".join(lines)


## «Сожжено: 1 клетка / 3 клетки / 25 клеток».
static func burnt_line(n: int) -> String:
	var word := "клеток"
	if n % 10 == 1 and n % 100 != 11:
		word = "клетка"
	elif n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
		word = "клетки"
	return "Сожжено: %d %s" % [n, word]
