extends RefCounted
## Настройки игры: хранятся в user://settings.cfg, живут в static-переменных
## (переживают перезагрузку сцены). Громкости — линейные 0..1.

const PATH := "user://settings.cfg"

static var master := 0.8
static var music := 0.7
static var sfx := 0.8
static var shake := 1.0
static var fullscreen := false
static var vsync := true
static var mouse_control := true
static var show_fps := false
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		master = cf.get_value("audio", "master", master)
		music = cf.get_value("audio", "music", music)
		sfx = cf.get_value("audio", "sfx", sfx)
		shake = cf.get_value("game", "shake", shake)
		mouse_control = cf.get_value("game", "mouse_control", mouse_control)
		show_fps = cf.get_value("game", "show_fps", show_fps)
		fullscreen = cf.get_value("video", "fullscreen", fullscreen)
		vsync = cf.get_value("video", "vsync", vsync)
	apply_video()


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "music", music)
	cf.set_value("audio", "sfx", sfx)
	cf.set_value("game", "shake", shake)
	cf.set_value("game", "mouse_control", mouse_control)
	cf.set_value("game", "show_fps", show_fps)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("video", "vsync", vsync)
	cf.save(PATH)


## Громкость шин. Шины Music и SFX создаёт sfx.gd.
static func apply_audio() -> void:
	_set_bus("Master", master)
	_set_bus("Music", music)
	_set_bus("SFX", sfx)


static func _set_bus(bus_name: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value, 0.0001)))
	if bus_name != "Master":  # Master глушится ещё и клавишей M — её не трогаем
		AudioServer.set_bus_mute(idx, value <= 0.001)


static func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
