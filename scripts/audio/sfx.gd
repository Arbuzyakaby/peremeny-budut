extends Node
## Проигрывание звуков и музыки. Всё синтезируется в фоновом потоке и кэшируется в static-переменных
## (переживает перезагрузку сцены): сначала звуки (экран загрузки ждёт их), затем по одному треку
## музыки. Плееры не обрывают звучащие звуки: берётся свободный, иначе самый давний.
## Шина ограничивает голоса: один звук — не больше MAX_SAME голосов разом, всего — не больше
## BURST_MAX новых звуков за BURST_MS (важные — вне очереди). Повторяющиеся звуки звучат с разбросом
## высоты и громкости. duck() приглушает огонь под огнетушителем, hush() — пауза тишины перед вспышкой.

signal sounds_ready

const SoundBank = preload("res://scripts/audio/sound_bank.gd")
const SynthMusic = preload("res://scripts/audio/synth_music.gd")
const Settings = preload("res://scripts/core/settings.gd")

const VOICES := 20
const COOLDOWN_MS := 40
const MAX_SAME := 2   # одного звука одновременно — не больше двух голосов
const BURST_MAX := 4  # новых звуков за окно BURST_MS — лишние отбрасываются
const BURST_MS := 100
## Мелодичные звуки проигрываются без случайного сдвига высоты — иначе фальшивят.
const NO_JITTER := ["win", "lose", "power", "ui_move", "ui_select", "ui_toggle", "ui_back", "ui_error", "yolk",
	"heal", "perk", "stage_clear", "scale", "tick", "ui_key_down", "ui_lever", "ui_rotary", "ui_cover", "secret"]
## Мелкие механические щелчки прибора — разброс ±5%, как у настоящего храповика.
const WIDE_JITTER := ["ui_detent", "ui_fader"]
const JITTER := 0.03    # остальные повторяющиеся звуки (шаги, укусы, приземления, удары) — ±3%
const JITTER_DB := 1.0  # и ±1 дБ громкости
## Не отбрасываются ограничителем: события, которые игрок обязан услышать.
const PRIORITY := ["win", "lose", "ignite", "extinguisher", "boss_down", "stage_clear", "hurt", "thunder",
	"hatch", "phase", "yolk", "perk", "match", "burn", "secret"]
## Звуки огня идут через шину Ambient — их вместе с петлёй пожара приглушает duck().
const FIRE_SOUNDS := ["crackle", "burn"]
## Музыка 2.0: громкость основы и слоя напряжения (при intensity = 1 слой звучит как основа).
const MUSIC_DB := -11.0
const HI_SILENT_DB := -60.0
const INTENSITY_RATE := 0.8  # насколько быстро слой догоняет цель, 1/с

static var sounds: Dictionary = {}
static var music: Dictionary = {}
static var muted := false
static var _builder: RefCounted
static var _thread: Thread
static var _building := ""  # "sounds" или имя трека

var players: Array[AudioStreamPlayer] = []
var started: Array[int] = []
var last_played: Dictionary = {}
var music_player: AudioStreamPlayer
## Слой напряжения (музыка 2.0): играет синхронно с основой, громкость — по set_intensity().
var music_hi: AudioStreamPlayer
var intensity := 0.0         # цель 0..1
var intensity_shown := 0.0   # плавно догоняет цель
var ambient_player: AudioStreamPlayer
var ambient_tween: Tween
var wanted_ambient := ""
var ambient_db := -8.0
var wanted_track := ""
var current_track := ""
var voice_names: Array[String] = []  # какой звук играет в каждом голосе
var recent: Array[int] = []          # время запуска последних звуков (для ограничителя)
var dropped := 0                     # сколько звуков отбросил ограничитель (панель разработчика, тесты)
var duck_tween: Tween
var hush_id := 0  # номер последней паузы тишины


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Ambient"]:
		_ensure_bus(bus)
	Settings.ensure_loaded()
	Settings.apply_audio()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		p.bus = "SFX"
		add_child(p)
		players.append(p)
		started.append(0)
		voice_names.append("")
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = MUSIC_DB
	music_player.bus = "Music"
	add_child(music_player)
	music_hi = AudioStreamPlayer.new()
	music_hi.volume_db = HI_SILENT_DB
	music_hi.bus = "Music"
	add_child(music_hi)
	ambient_player = AudioStreamPlayer.new()
	ambient_player.volume_db = -60.0
	ambient_player.bus = "Ambient"
	add_child(ambient_player)
	AudioServer.set_bus_mute(0, muted)


static func is_ready() -> bool:
	return not sounds.is_empty()


## Доля готовности звуков 0..1 (для экрана загрузки).
static func progress() -> float:
	if is_ready():
		return 1.0
	if _building == "sounds" and _builder:
		return clampf(float(_builder.built_count) / SoundBank.SOUND_COUNT, 0.0, 0.99)
	return 0.0


## Построить звуки сразу, в этом потоке (тесты, выгрузка WAV).
static func build_now() -> void:
	join_builder()
	if sounds.is_empty():
		sounds = SoundBank.new().build_sounds()


## Дождаться фонового построения (при выходе из игры).
static func join_builder() -> void:
	if _thread != null:
		var result: Variant = _thread.wait_to_finish()
		_store(result)
		_thread = null
	_builder = null
	_building = ""


static func _store(result: Variant) -> void:
	if not (result is Dictionary):
		return
	if _building == "sounds":
		sounds = result
	else:
		music.merge(result)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


## Усилитель шины для ducking и тишины: громкость самой шины принадлежит настройкам, её не трогаем.
static func _amp(bus_name: String) -> AudioEffectAmplify:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return null
	for i in AudioServer.get_bus_effect_count(idx):
		var e := AudioServer.get_bus_effect(idx, i)
		if e is AudioEffectAmplify:
			return e
	var amp := AudioEffectAmplify.new()
	AudioServer.add_bus_effect(idx, amp)
	return amp


func _process(delta: float) -> void:
	intensity_shown = move_toward(intensity_shown, intensity, delta * INTENSITY_RATE)
	music_hi.volume_db = hi_db(intensity_shown)
	if _thread != null and not _thread.is_alive():
		var was_sounds := _building == "sounds"
		join_builder()
		if was_sounds:
			sounds_ready.emit()
	if _thread == null:
		_start_next_job()
	_update_music()


func _start_next_job() -> void:
	if sounds.is_empty():
		_building = "sounds"
		_builder = SoundBank.new()
		_thread = Thread.new()
		_thread.start(_builder.build_sounds)
		return
	for track: String in SynthMusic.TRACKS:
		if not music.has(track):
			_building = track
			_builder = SynthMusic.new()
			_thread = Thread.new()
			_thread.start(_builder.build_track.bind(track))
			return


func _update_music() -> void:
	if wanted_track != current_track:
		if wanted_track == "":
			music_player.stop()
			music_hi.stop()
			current_track = ""
		elif music.has(wanted_track):
			music_player.stream = music[wanted_track]
			music_player.play()
			var hi := wanted_track + SynthMusic.HI_SUFFIX
			if music.has(hi):  # слои одной длины: запускаем вместе — и они не разъедутся
				music_hi.stream = music[hi]
				music_hi.play()
			else:
				music_hi.stop()
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
	if not _burst_allows(sound_name, now):
		dropped += 1
		return
	last_played[sound_name] = now
	var idx := pick_voice(sound_name)
	var p := players[idx]
	started[idx] = now
	voice_names[idx] = sound_name
	p.stream = sounds[sound_name]
	p.bus = "Ambient" if sound_name in FIRE_SOUNDS else "SFX"
	p.pitch_scale = pitch * jitter_of(sound_name)
	var vol_jitter := 0.0 if sound_name in NO_JITTER else randf_range(-JITTER_DB, JITTER_DB)
	p.volume_db = -4.0 + volume_db + vol_jitter
	p.play()


## Случайный множитель высоты: мелодичные — ровно, щелчки прибора — ±5%, остальные — ±3%.
static func jitter_of(sound_name: String) -> float:
	if sound_name in NO_JITTER:
		return 1.0
	var j := 0.05 if sound_name in WIDE_JITTER else JITTER
	return randf_range(1.0 - j, 1.0 + j)


## Ограничитель плотности: не больше BURST_MAX новых звуков за BURST_MS. Важные и звуки
## интерфейса проходят всегда.
func _burst_allows(sound_name: String, now: int) -> bool:
	while not recent.is_empty() and now - recent[0] >= BURST_MS:
		recent.pop_front()
	if sound_name in PRIORITY or sound_name.begins_with("ui_"):
		return true
	if recent.size() >= BURST_MAX:
		return false
	recent.append(now)
	return true


## Голос для звука: если этот звук уже звучит MAX_SAME раз — перезапускается самый давний из них
## (пять таблеток, упавших разом, — два приземления, а не каша); иначе свободный, иначе самый давний.
func pick_voice(sound_name := "") -> int:
	if sound_name != "":
		var same := -1
		var n := 0
		for i in players.size():
			if players[i].playing and voice_names[i] == sound_name:
				n += 1
				if same < 0 or started[i] < started[same]:
					same = i
		if n >= MAX_SAME:
			return same
	var oldest := 0
	for i in players.size():
		if not players[i].playing:
			return i
		if started[i] < started[oldest]:
			oldest = i
	return oldest


## Сколько голосов сейчас играют этот звук.
func voices_of(sound_name: String) -> int:
	var n := 0
	for i in players.size():
		if players[i].playing and voice_names[i] == sound_name:
			n += 1
	return n


## Ducking: приглушить огонь (петля пожара, треск, горение) на db, подержать hold секунд и вернуть
## за release. Вызывается вместе с огнетушителем, чтобы струя не тонула в треске.
func duck(db := -4.0, hold := 0.5, release := 0.4) -> void:
	var amp := _amp("Ambient")
	if amp == null:
		return
	if duck_tween:
		duck_tween.kill()
	amp.volume_db = db
	duck_tween = create_tween()
	duck_tween.tween_interval(hold)
	duck_tween.tween_method(func(v: float) -> void: amp.volume_db = v, db, 0.0, release)


func duck_db() -> float:
	var amp := _amp("Ambient")
	return amp.volume_db if amp else 0.0


## Полная тишина на time секунд — ни музыки, ни шагов, ни интерфейса (кинопауза перед вспышкой).
## Работает через усилитель на Master и не трогает переключатель M.
func hush(time := 0.2) -> void:
	var amp := _amp("Master")
	if amp == null:
		return
	hush_id += 1
	if time <= 0.0:  # снять тишину сразу
		amp.volume_db = 0.0
		return
	amp.volume_db = -80.0
	var id := hush_id
	# снимает тишину таймер последнего вызова (сверка по номеру, а не по часам: таймер бывает на кадр раньше)
	get_tree().create_timer(time, true, false, true).timeout.connect(func() -> void:
		if id == hush_id:
			amp.volume_db = 0.0)


func is_hushed() -> bool:
	var amp := _amp("Master")
	return amp != null and amp.volume_db < -40.0


## Сколько голосов звучит (панель разработчика).
func busy_voices() -> int:
	var n := 0
	for p in players:
		if p.playing:
			n += 1
	return n


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
	if track != wanted_track:
		intensity = 0.0
		intensity_shown = 0.0
	wanted_track = track


## Музыка 2.0: насколько подмешан слой напряжения (0 — только основа, 1 — полный).
func set_intensity(k: float) -> void:
	intensity = clampf(k, 0.0, 1.0)


## Громкость слоя напряжения при уровне k: тишина → как основа (по кривой, чтобы слой вступал заметно).
static func hi_db(k: float) -> float:
	if k <= 0.01:
		return HI_SILENT_DB
	return lerpf(-30.0, MUSIC_DB - 1.0, sqrt(clampf(k, 0.0, 1.0)))


func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	return muted


func is_muted() -> bool:
	return muted


## Временно заглушить всё (игра свёрнута), не трогая переключатель M.
func set_suspended(on: bool) -> void:
	AudioServer.set_bus_mute(0, on or muted)


## Отладка: записать все звуки в WAV для анализа (запуск с `-- --dump-sfx`).
func dump(dir: String) -> void:
	build_now()
	DirAccess.make_dir_recursive_absolute(dir)
	for k: String in sounds:
		(sounds[k] as AudioStreamWAV).save_to_wav(dir.path_join(k + ".wav"))
	SynthMusic.new().build_fire_loop().save_to_wav(dir.path_join("fire_loop.wav"))


## Освободить кэш при выходе — чтобы не было утечек.
static func release_all() -> void:
	join_builder()
	sounds.clear()
	music.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		release_all()
