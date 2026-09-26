extends Node
## Проигрывание звуков и музыки. Звуки синтезируются один раз и кэшируются в static-переменных,
## музыка генерируется в фоновом потоке, чтобы не тормозить запуск.

const Synth = preload("res://scripts/synth.gd")
const Settings = preload("res://scripts/settings.gd")

static var sounds: Dictionary = {}
static var music: Dictionary = {}
static var muted := false
static var _music_builder: RefCounted
static var _music_thread: Thread
static var _sad_started := false

var players: Array[AudioStreamPlayer] = []
var next_player := 0
var music_player: AudioStreamPlayer
var wanted_track := ""
var current_track := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	Settings.ensure_loaded()
	Settings.apply_audio()
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -11.0
	music_player.bus = "Music"
	add_child(music_player)
	if sounds.is_empty():
		sounds = Synth.new().build_sounds()
	if music.is_empty() and _music_thread == null:
		_music_builder = Synth.new()
		_music_thread = Thread.new()
		_music_thread.start(_music_builder.build_music)
	AudioServer.set_bus_mute(0, muted)


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
	if _music_thread == null and not music.is_empty() and not _sad_started:
		_sad_started = true  # грустную мелодию для финала строим вторым заходом
		_music_builder = Synth.new()
		_music_thread = Thread.new()
		_music_thread.start(_music_builder.build_sad_music)
	if wanted_track != current_track:
		if wanted_track == "":
			music_player.stop()
			current_track = ""
		elif music.has(wanted_track):
			music_player.stream = music[wanted_track]
			music_player.play()
			current_track = wanted_track


func play(sound_name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not sounds.has(sound_name):
		return
	var p := players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = sounds[sound_name]
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.volume_db = -4.0 + volume_db
	p.play()


func play_music(track: String) -> void:
	wanted_track = track


func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	return muted


func is_muted() -> bool:
	return muted


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:  # освобождаем кэш, чтобы не было утечек при выходе
		if _music_thread != null:
			_music_thread.wait_to_finish()
			_music_thread = null
		_music_builder = null
		sounds.clear()
		music.clear()
		_sad_started = false
