extends "res://tests/test_case.gd"
## Сверка кода с таблицами (v12.4): тест читает исходники scripts/ и проверяет, что всё, что код
## называет строкой, существует. Опечатка в имени звука молчит (звука просто нет), причина урона без
## совета показывает случайный совет, ключ картотеки с ошибкой не открывает карточку — такие
## ошибки не видны в игре, но видны здесь.

const Sfx = preload("res://scripts/audio/sfx.gd")
const Tips = preload("res://scripts/core/tips.gd")
const ReplayScreen = preload("res://scripts/ui/screens/replay_screen.gd")
const Balance = preload("res://scripts/core/balance.gd")

## Звуки, которые собираются не в sound_bank (имена — через переменную или составные).
const DYNAMIC_SOUNDS := []


static func _sources(dir := "res://scripts") -> Dictionary:
	var out := {}
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out[dir.path_join(f)] = FileAccess.get_file_as_string(dir.path_join(f))
	for sub in d.get_directories():
		out.merge(_sources(dir.path_join(sub)))
	return out


## Все совпадения первой группы регулярки во всех исходниках: {значение: "файл"}.
static func _find(pattern: String) -> Dictionary:
	var re := RegEx.new()
	re.compile(pattern)
	var out := {}
	var src := _sources()
	for path: String in src:
		for m in re.search_all(src[path]):
			out[m.get_string(1)] = path.get_file()
	return out


func test_every_played_sound_exists() -> void:
	Sfx.build_now()
	var played := _find("""(?:sfx\\.play|sfx\\.play_room|Design\\.play|sound\\.emit|\\.play)\\(\\s*"([a-z0-9_]+)\"""")
	assert_gt(played.size(), 40, "нашли вызовы звуков")
	for name: String in played:
		if name in DYNAMIC_SOUNDS or Sfx.music.has(name) or name == "":
			continue
		assert_true(Sfx.sounds.has(name), "звук «%s» из %s есть в банке" % [name, played[name]])


func test_every_damage_cause_has_a_tip_and_a_title() -> void:
	var causes := _find("""take_damage\\(\\s*[0-9a-z_.]+\\s*,\\s*"([a-z_]+)\"""")
	causes.merge(_find("""take_damage\\([^)]*"([a-z_]+)"\\s+if"""))
	assert_gt(causes.size(), 6, "нашли причины урона")
	causes.erase("dev")  # «убить змею» в панели разработчика — не игровая причина
	for cause: String in causes:
		assert_true(Tips.BY_CAUSE.has(cause), "у причины «%s» (%s) есть свой совет" % [cause, causes[cause]])
		assert_ne(ReplayScreen.cause_title(cause), "ПРИЧИНА НЕИЗВЕСТНА", "и заголовок повтора: " + cause)


func test_every_literal_bestiary_key_exists() -> void:
	var keys := _find("""(?:seen|beaten|unlock)\\(\\s*"([a-z_0-9]+)\"""")
	assert_gt(keys.size(), 1)
	for key: String in keys:
		if key == "contact" or key in ["konami", "title", "egg_poke", "iddqd", "koschei", "sleepy", "holiday"]:
			continue  # это пасхалки (Secrets.unlock), у них свой список
		assert_false(Bestiary.entry(key).is_empty(), "карточка «%s» из %s есть в картотеке" % [key, keys[key]])


func test_every_secret_unlocked_in_code_is_listed() -> void:
	var ids := _find("""found_secret\\(\\s*"([a-z_]+)\"""")
	ids.merge(_find("""secret_found\\.emit\\(\\s*"([a-z_]+)\""""))
	for id: String in ids:
		assert_false(Secrets.entry(id).is_empty(), "пасхалка «%s» из %s есть в списке" % [id, ids[id]])


func test_stage_music_and_floors_exist() -> void:
	Sfx.build_now()
	for i in Balance.STAGES.size():
		var st: Dictionary = Balance.STAGES[i]
		if i != Balance.BOSS_STAGE:  # яичницу объявляет табличка, а не подсказка
			assert_ne(String(st["hint"]), "", "у этапа «%s» есть подсказка" % st["name"])
		assert_ne(String(st["music"]), "", "у этапа «%s» есть музыка" % st["name"])


func test_no_leftover_debug_prints_in_new_code() -> void:
	# print() в релизе засоряет журнал телефона. Разрешены старые служебные строки итогов и босса.
	var allowed := ["run end:", "stage cleared:", "boss defeated", "SFX dumped"]  # последнее — аргумент --dump-sfx
	var src := _sources()
	var re := RegEx.new()
	re.compile("""\\bprint\\(\\s*"([^"]*)""")
	for path: String in src:
		for m in re.search_all(src[path]):
			var ok := false
			for a in allowed:
				if m.get_string(1).begins_with(a):
					ok = true
			assert_true(ok, "лишний print в %s: %s" % [path.get_file(), m.get_string(1)])
