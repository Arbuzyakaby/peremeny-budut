extends RefCounted
## Дисковый кэш синтезированного звука (v12.1). Звуки и музыку игра строит в коде — около 11 секунд работы
## процессора на компьютере и в разы дольше на телефоне. Готовый PCM 16 бит (~12 МБ) кладём в user://audio_cache/,
## и со второго запуска игра читает файлы вместо синтеза. Кэш привязан к номеру версии игры: обновление
## пересобирает его один раз. В редакторе и в тестах он выключен (звук всегда свежий) — включается в
## выпущенных сборках или аргументом --audio-cache.

const MAGIC := 0x53464341  # "ACFS"
const SCHEMA := 1

## Папка кэша и принудительное включение — меняются только в тестах.
static var dir := "user://audio_cache"
static var force := false


static func enabled() -> bool:
	return force or OS.has_feature("template") or OS.get_cmdline_user_args().has("--audio-cache")


static func _path(group: String) -> String:
	var ver := str(ProjectSettings.get_setting("application/config/version", "0"))
	return "%s/%s_v%s_s%d.bin" % [dir, group, ver, SCHEMA]


## Прочитать группу (sounds или имя трека) из кэша. Пустой словарь — кэша нет или он повреждён.
static func load_group(group: String) -> Dictionary:
	if not enabled():
		return {}
	var path := _path(group)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var out := {}
	if f.get_32() != MAGIC:
		return {}
	var count := f.get_32()
	for i in count:
		if f.eof_reached():
			return {}
		var key := f.get_pascal_string()
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.stereo = false
		s.mix_rate = f.get_32()
		s.loop_mode = f.get_8() as AudioStreamWAV.LoopMode
		s.loop_begin = f.get_32()
		s.loop_end = f.get_32()
		var n := f.get_32()
		if n <= 0 or n > f.get_length() - f.get_position():
			return {}
		s.data = f.get_buffer(n)
		if s.data.size() != n:
			return {}
		out[key] = s
	if f.get_position() != f.get_length():  # хвост лишний — файл не наш
		return {}
	return out


## Записать группу. Пишем во временный файл и переименовываем: оборванная запись не станет «кэшем».
static func save_group(group: String, streams: Dictionary) -> void:
	if not enabled() or streams.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var path := _path(group)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_32(MAGIC)
	f.store_32(streams.size())
	for key: String in streams:
		var s := streams[key] as AudioStreamWAV
		f.store_pascal_string(key)
		f.store_32(s.mix_rate)
		f.store_8(s.loop_mode)
		f.store_32(s.loop_begin)
		f.store_32(s.loop_end)
		f.store_32(s.data.size())
		f.store_buffer(s.data)
	var ok := f.get_error() == OK
	f.close()
	if not ok:
		DirAccess.remove_absolute(tmp)
		return
	DirAccess.rename_absolute(tmp, path)
	_drop_stale(path.get_file())


## Убрать кэш прошлых версий игры.
static func _drop_stale(keep_file: String) -> void:
	var suffix := keep_file.get_slice("_v", 1)  # "12.1_s1.bin"
	for name in DirAccess.get_files_at(dir):
		if not name.ends_with(suffix) and name.ends_with(".bin"):
			DirAccess.remove_absolute(dir.path_join(name))
