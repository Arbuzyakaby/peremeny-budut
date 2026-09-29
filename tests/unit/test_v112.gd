extends "res://tests/test_case.gd"
## v11.2: звуки лаборатории собраны заново (44,1 кГц, дождь за окном — петля), рука с пистолетом
## в «Контакте» стреляет с отдачей, гильзой и дымком, гроза за окном — свет раньше звука.

const Sfx = preload("res://scripts/audio/sfx.gd")
const Foley = preload("res://scripts/audio/foley.gd")
const ContactFinale = preload("res://scripts/contact/contact_finale.gd")
const Ending = preload("res://scripts/ending/ending.gd")


func test_lab_sounds_are_rebuilt_at_44khz() -> void:
	Sfx.build_now()
	for name: String in Foley.NAMES:
		assert_true(Sfx.sounds.has(name), name + " есть в банке")
		assert_eq(int((Sfx.sounds[name] as AudioStreamWAV).mix_rate), Foley.RATE, name + ": 44,1 кГц — с верхней октавой")
	var rain: AudioStreamWAV = Sfx.sounds["rain"]
	assert_eq(rain.loop_mode, AudioStreamWAV.LOOP_FORWARD, "дождь — бесшовная петля")
	assert_gt(float(rain.data.size()) / 2.0 / rain.mix_rate, 5.0, "длинная — не приедается")
	assert_eq(int((Sfx.sounds["bite"] as AudioStreamWAV).mix_rate), 22050, "игровые звуки не тронуты")


func test_gun_recoil_casing_and_smoke() -> void:
	var f := ContactFinale.new()
	add(f)
	f.hand = Vector2(640, -30)
	f._recoil()
	assert_near(f.recoil, 1.0, 1e-6, "затвор откатился")
	assert_eq(f.casings.size(), 1, "вылетела гильза")
	assert_eq(f.puffs.size(), 1, "из ствола дымок")
	assert_gt(float(f.casings[0]["v"].x), 0.0, "гильза летит вправо — из окна выброса")


func test_storm_light_comes_before_sound() -> void:
	var km := 1.0
	assert_near(km * 1000.0 / Ending.SOUND_SPEED, 2.9, 0.05, "молния в километре — гром через ~3 с")
	assert_true(Ending.STORM_EVERY.x >= 8.0, "гроза редкая — не отвлекает")
