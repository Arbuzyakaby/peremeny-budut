extends Node
## Проигрывание звуков и музыки. Звуки синтезируются один раз и кэшируются в static-переменных,
## музыка (и фон пожара) генерируются по одному треку в фоновом потоке, чтобы не тормозить запуск.
## Плееры не обрывают звучащие звуки: берётся свободный, иначе самый давний.

const Synth = preload("res://scripts/synth.gd")
const Settings = preload("res://scripts/settings.gd")

const VOICES := 20
const COOLDOWN_MS := 40
## Мелодичные звуки проигрываются без случайного сдвига высоты — иначе фальшивят.
const NO_JITTER := ["win", "lose", "power", "ui_move", "ui_select", "yolk", "heal", "perk", "stage_clear",
	"scale", "tick"]

static var sounds: Dictionary = {}
static var music: Dictionary = {}
static var muted := false
static var _music_builder: RefCounted
static var _music_thread: Thread
static var _building := ""

var players: Array[AudioStreamPlayer] = []
var started: Array[int] = []
var last_played: Dictionary = {}
var music_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer
var ambient_tween: Tween
var wanted_ambient := ""
var ambient_db := -8.0
var wanted_track := ""
var current_track := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	Settings.ensure_loaded()
	Settings.apply_audio()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		p.bus = "SFX"
		add_child(p)
		players.append(p)
		started.append(0)
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -11.0
	music_player.bus = "Music"
	add_child(music_player)
	ambient_player = AudioStreamPlayer.new()
	ambient_player.volume_db = -60.0
	ambient_player.bus = "SFX"
	add_child(ambient_player)
	if sounds.is_empty():
		sounds = Synth.new().build_sounds()
	AudioServer.set_bus_mute(0, muted)
	# корень дерева уходит только при выходе из игры: дожидаемся фонового потока, иначе падение
	var root := get_tree().root
	if not root.tree_exiting.is_connected(join_builder):
		root.tree_exiting.connect(join_builder)


## Дождаться фонового построения музыки (при выходе из игры).
static func join_builder() -> void:
	if _music_thread != null:
		_music_thread.wait_to_finish()
		_music_thread = null
	_music_builder = null


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _process(_delta: float) -> void:
	if _music_thread != null and not _music_thread.is_alive():
		music.merge(_music_thread.wait_to_finish())
		_music_thread = null
		_music_builder = null
	if _music_thread == null:
		for track: String in Synth.TRACKS:
			if not music.has(track):
				_building = track
				_music_builder = Synth.new()
				_music_thread = Thread.new()
				_music_thread.start(_music_builder.build_track.bind(track))
				break
	if wanted_track != current_track:
		if wanted_track == "":
			music_player.stop()
			current_track = ""
		elif music.has(wanted_track):
			music_player.stream = music[wanted_track]
			music_player.play()
			current_track = wanted_track
	if wanted_ambient != "" and not ambient_player.playing and music.has(wanted_ambient):
		ambient_player.stream = music[wanted_ambient]
		ambient_player.volume_db = -40.0
		ambient_player.play()
		_fade_ambient(ambient_db, 1.2)


func play(sound_name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not sounds.has(sound_name):
		return
	var now := Time.get_ticks_msec()
	if now - int(last_played.get(sound_name, -1000)) < COOLDOWN_MS:
		return
	last_played[sound_name] = now
	var idx := -1
	var oldest := 0
	for i in players.size():
		if not players[i].playing:
			idx = i
			break
		if started[i] < started[oldest]:
			oldest = i
	if idx < 0:
		idx = oldest
	var p := players[idx]
	started[idx] = now
	p.stream = sounds[sound_name]
	p.pitch_scale = pitch * (1.0 if sound_name in NO_JITTER else randf_range(0.95, 1.05))
	p.volume_db = -4.0 + volume_db
	p.play()


## Зацикленный фон (например, пожар) с плавным появлением.
func play_ambient(track: String, volume_db := -8.0) -> void:
	wanted_ambient = track
	ambient_db = volume_db
	if ambient_player.playing:
		_fade_ambient(volume_db, 0.6)


func set_ambient_volume(volume_db: float) -> void:
	ambient_db = volume_db
	if ambient_player.playing and (ambient_tween == null or not ambient_tween.is_running()):
		ambient_player.volume_db = volume_db


func stop_ambient(fade := 1.5) -> void:
	wanted_ambient = ""
	if not ambient_player.playing:
		return
	_fade_ambient(-60.0, fade)
	ambient_tween.tween_callback(ambient_player.stop)


func _fade_ambient(db: float, time: float) -> void:
	if ambient_tween:
		ambient_tween.kill()
	ambient_tween = create_tween()
	ambient_tween.tween_property(ambient_player, "volume_db", db, time)


func play_music(track: String) -> void:
	wanted_track = track


func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	return muted


func is_muted() -> bool:
	return muted


## Отладка: записать все звуки в WAV для анализа (запуск с `-- --dump-sfx`).
func dump(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for k: String in sounds:
		(sounds[k] as AudioStreamWAV).save_to_wav(dir.path_join(k + ".wav"))
	var fire := Synth.new().build_fire_loop()
	fire.save_to_wav(dir.path_join("fire_loop.wav"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:  # освобождаем кэш, чтобы не было утечек при выходе
		join_builder()
		sounds.clear()
		music.clear()
