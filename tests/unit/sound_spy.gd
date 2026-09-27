extends Node
## Подставной проигрыватель звуков для тестов: запоминает, какие звуки просил интерфейс.

var played: Array[String] = []


func play(sound_name: String, _pitch := 1.0, _db := 0.0) -> void:
	played.append(sound_name)


func count(sound_name: String) -> int:
	return played.count(sound_name)
