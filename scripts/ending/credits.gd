extends RefCounted
## Титры финала со статистикой забега.


static func text(game, choice_line: String) -> String:
	var mins := int(game.play_time) / 60
	var secs := int(game.play_time) % 60
	var lines := [
		"ЗМЕЯ ПРОТИВ ГИГАНТСКОЙ ЯИЧНИЦЫ", "версия %s" % ProjectSettings.get_setting("application/config/version", "5.0"), "",
		"ПРОТОКОЛ ЭКСПЕРИМЕНТА №47",
		"Сложность: %s" % game.cfg["name"],
		"Медведей съедено: %d" % game.bears_eaten,
		"Вилок сломано: %d" % game.forks_broken,
		"Таблеток съедено: %d" % game.pills_eaten,
		"Время: %d:%02d   •   Счёт: %d" % [mins, secs, game.score],
		choice_line, "",
		"В РОЛЯХ",
		"Змея — образец №47",
		"Гигантская Яичница — сама себя",
		"Учёный-бюрократ — пункт 12-Б",
		"Медведи, вилки и таблетки — массовка",
		"Змейка — образец №48", "",
		"Графика и звук сгенерированы кодом.",
		"Ни одной картинки. Ни одного аудиофайла.", "",
		"Перемены будут.",
	]
	return "\n".join(lines)
