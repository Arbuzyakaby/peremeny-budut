extends "res://tests/integration/game_case.gd"
## Части HUD по отдельности: табличка объявления (деление на заголовок и пояснение, ширина по тексту,
## место в игре и в меню), лента субтитров и подсказок (выключенные субтитры, перенос, отступ снизу),
## табло (сердца, вспышки, счёт догоняет, полоса яичницы и её «призрак», дрожь паники), заголовок меню.

const Captions = preload("res://scripts/ui/captions.gd")
const HudOverlay = preload("res://scripts/ui/hud_overlay.gd")
const TitleArt = preload("res://scripts/ui/widgets/title_art.gd")
const Design = preload("res://scripts/ui/design.gd")


func _captions() -> Captions:
	var c := Captions.new()
	var box: Control = add(Control.new())
	box.size = Vector2(1280, 720)
	box.add_child(c)
	c.size = Vector2(1280, 720)
	await frames(1)
	return c


# ---------------------------------------------------------------- табличка

func test_split_banner_rules() -> void:
	assert_eq(Captions.split_banner("КОРОТКО!"), PackedStringArray(["КОРОТКО!", ""]), "короткое не делится")
	assert_eq(Captions.split_banner("НОВАЯ АТАКА! Пробел — атака съеденного врага"),
		PackedStringArray(["НОВАЯ АТАКА!", "Пробел — атака съеденного врага"]), "по «! » — заголовок с восклицанием")
	assert_eq(Captions.split_banner("Враги дерутся между собой — это тебе на руку"),
		PackedStringArray(["Враги дерутся между собой", "это тебе на руку"]), "по тире")
	var long := "ОЧЕНЬ ДЛИННЫЙ ЗАГОЛОВОК БЕЗ ЗНАКОВ РАЗДЕЛА"
	assert_eq(Captions.split_banner(long)[1], "", "нечем делить — целиком")


func test_banner_width_follows_text_and_fits() -> void:
	var c := await _captions()
	c.set_banner_place(true, false)
	c.show_banner("ОК")
	await frames(1)
	var short_w := c.banner_plate.size.x
	c.show_banner("ЯИЧНИЦА ПРИГОРЕЛА! В ярости: быстрее и злее, чем прежде, и плюётся маслом")
	await frames(1)
	assert_gt(c.banner_plate.size.x, short_w, "длиннее текст — шире табличка")
	assert_true(c.banner_plate.size.x <= Captions.BANNER_MAX_WIDTH + 0.5, "но не шире места между табло")
	assert_true(c.banner_sub.visible, "пояснение отдельной строкой")
	assert_true(c.banner.label_settings.font_size >= Captions.BANNER_MIN_SIZE)
	assert_near(c.banner_plate.position.y, Captions.BANNER_TOP, 0.5, "в игре — сверху")
	c.set_banner_place(true, true)
	assert_near(c.banner_plate.position.y, Captions.BANNER_TOP_TOUCH, 0.5, "на телефоне — под табло яичницы")
	c.set_banner_place(false, false)
	assert_near(c.banner_plate.position.y, 720 * 0.3, 0.5, "в меню — выше центра")
	assert_near(c.banner_plate.position.x + c.banner_plate.size.x / 2.0, 640.0, 1.0, "по центру")


func test_banner_hides_on_demand() -> void:
	var c := await _captions()
	c.show_banner("ЭТАП ПРОЙДЕН!")
	await frames(3)
	assert_true(c.is_banner_shown())
	c.hide_banner()
	assert_false(c.is_banner_shown(), "пауза и итоги убирают табличку сразу")


# ---------------------------------------------------------------- лента

func test_subtitles_can_be_off_but_hints_stay() -> void:
	var c := await _captions()
	Settings.set_value("subtitles", false)
	c.show_caption("УЧЁНЫЙ-БЮРОКРАТ", "Регламент.")
	await frames(2)
	assert_false(c.is_caption_shown(), "реплики без субтитров не показываются")
	c.show_caption("", "Кусай желток!", true)
	await frames(25)
	assert_true(c.is_caption_shown(), "подсказки — всегда")
	assert_false(c.speaker_label.visible, "у подсказки нет имени")
	Settings.set_value("subtitles", true)


func test_caption_wraps_evenly_and_respects_bottom_margin() -> void:
	var c := await _captions()
	c.show_caption("УЧЁНЫЙ-БЮРОКРАТ", "Образец прошёл все этапы: медведей — 8, вилок — 5, таблеток — 7, матрёшек — 4 наб. И яичница. Всё записано в протокол по пункту 12-Б.")
	await frames(2)
	assert_gt(c.caption_label.get_line_count(), 1, "длинная реплика — в несколько строк")
	assert_true(c.caption_plate.size.x <= 1100.0 + 1.0, "лента не шире 1100")
	var bottom := c.caption_plate.position.y + c.caption_plate.size.y
	c.set_bottom_margin(120.0)
	await frames(1)
	var bottom2 := c.caption_plate.position.y + c.caption_plate.size.y
	assert_near(bottom - bottom2, 120.0, 1.0, "лента поднимается над кнопками телефона")
	for size_i in Captions.SUBTITLE_SIZES.size():
		Settings.set_value("subtitle_size", size_i)
		c.show_caption("Я", "Текст")
		assert_eq(c.caption_label.label_settings.font_size, Captions.SUBTITLE_SIZES[size_i], "размер субтитров из настроек")
	Settings.set_value("subtitle_size", 1)


# ---------------------------------------------------------------- табло

func test_overlay_hearts_flash_only_when_hurt() -> void:
	var o: HudOverlay = add(HudOverlay.new())
	Settings.set_value("hurt_flash", true)
	o.reset_run("НОРМАЛЬНАЯ", Design.YOLK, 3)
	assert_eq(o.lives, 3)
	o.set_lives(3)
	assert_eq(o.heart_anim, 0.0, "жизней столько же — сердце не дёргается")
	o.set_lives(2)
	assert_eq(o.heart_anim, 1.0, "потеряла жизнь — сердце вздрагивает")
	assert_eq(o.hurt_flash, 1.0, "и край экрана вспыхивает")
	o._process(1.0)
	assert_eq(o.hurt_flash, 0.0, "вспышка гаснет")
	Settings.set_value("hurt_flash", false)
	o.set_lives(1)
	assert_eq(o.hurt_flash, 0.0, "вспышки урона выключены")
	Settings.set_value("hurt_flash", true)


func test_overlay_white_flash_is_softer_when_calm() -> void:
	var o: HudOverlay = add(HudOverlay.new())
	Settings.set_value("reduced_motion", false)
	o.flash(1.0)
	assert_near(o.white_flash, 0.85, 0.001)
	o.white_flash = 0.0
	Settings.set_value("reduced_motion", true)
	o.flash(1.0)
	assert_near(o.white_flash, 0.35, 0.001, "«меньше анимации» — засветка, а не удар по глазам")
	Settings.set_value("reduced_motion", false)


func test_overlay_score_counts_up_smoothly() -> void:
	var o: HudOverlay = add(HudOverlay.new())
	o.reset_run("", Design.YOLK, 3)
	o.score_target = 1000
	o._process(0.1)
	assert_between(o.score_shown, 1.0, 999.0, "счёт догоняет, а не прыгает")
	for i in 60:
		o._process(0.05)
	assert_eq(o.score_shown, 1000.0, "и догоняет")


func test_overlay_boss_bar_has_a_ghost() -> void:
	var o: HudOverlay = add(HudOverlay.new())
	o.set_boss(true, 10, 10, 1)
	assert_eq(o.boss_hp_shown, 0.0, "полоса наполняется при появлении")
	for i in 40:
		o._process(0.05)
	assert_near(o.boss_hp_shown, 10.0, 0.01)
	o.set_boss(true, 7, 10, 2)
	assert_eq(o.boss_flash, 1.0, "укус — полоса вспыхивает")
	o._process(0.2)
	assert_lt(o.boss_hp_shown, 10.0)
	assert_gt(o.boss_hp_ghost, o.boss_hp_shown, "«призрак» отстаёт — видно, сколько откусили")
	o.set_boss(true, 7, 10, 9)
	assert_eq(o.boss_phase, 3, "фаза не больше трёх")
	await assert_draws(o, "табло с яичницей")


func test_overlay_ability_flashes_on_new_charge() -> void:
	var o: HudOverlay = add(HudOverlay.new())
	o.set_ability(13, "УДАРНАЯ ВОЛНА", 1)
	assert_eq(o.ability_flash, 1.0, "новый приём — вспышка")
	o.ability_flash = 0.0
	o.set_ability(13, "УДАРНАЯ ВОЛНА", 1)
	assert_eq(o.ability_flash, 0.0, "то же самое — без вспышки")
	o.set_ability(13, "УДАРНАЯ ВОЛНА", 2)
	assert_eq(o.ability_flash, 1.0, "заряд прибавился — вспышка")
	assert_eq(HudOverlay.ABILITY_SOURCE[14], "doll", "у прыжка малышки — табличка матрёшки")


func test_panic_jitter_is_small_and_off_when_calm() -> void:
	var o: HudOverlay = add(HudOverlay.new())
	Design.panic = 0.0
	assert_eq(o.panic_jitter(), Vector2.ZERO, "без паники — ровно")
	Design.panic = 1.0
	Settings.set_value("reduced_motion", false)
	for i in 30:
		o.t = i * 0.05
		var j := o.panic_jitter()
		assert_true(absf(j.x) <= 2.0 and absf(j.y) <= 2.0, "дрожь — не больше 2 px")
	Settings.set_value("reduced_motion", true)
	assert_eq(o.panic_jitter(), Vector2.ZERO, "«меньше анимации» — без дрожи")
	Settings.set_value("reduced_motion", false)
	Design.panic = 0.0


# ---------------------------------------------------------------- заголовок меню

func test_title_art_pokes_and_hisses() -> void:
	var a: TitleArt = add(TitleArt.new())
	a.size = Vector2(900, 200)
	a.poke()
	assert_gt(a.jump, 0.0, "щелчок — буквы подпрыгивают")
	a.hiss()
	assert_gt(a.hiss_k, 0.0, "пасхалка — шипит")
	await assert_draws(a, "заголовок в шипении")
	for i in 120:
		a._process(0.05)
	assert_lt(a.jump, 0.01, "подпрыгивание затихает")
