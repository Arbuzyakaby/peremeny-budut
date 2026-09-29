extends Control
## Текст поверх игры: объявления, субтитры и подсказки внизу, приглашение к действию,
## большой титр финала, титры и кнопка «Пропустить».
## Дизайн-язык 2.4: объявление (баннер) — табличка на винтах с кромкой смысла, в игре — сверху между
## табло, чтобы не закрывать арену; длинный текст — заголовок и строка пояснения («ЗАГОЛОВОК! пояснение»
## делится по «!» или «—»). Подсказки и субтитры лежат на ленте подсказки и не наезжают на табло яичницы.
## В панике (Design.panic — пожар финала) субтитры дрожат на 1–2 px, а имя говорящего мигает, как
## лампа на плохом контакте, — тем чаще, чем сильнее огонь. С «меньше анимации» — неподвижно.

signal skip_requested

const Design = preload("res://scripts/ui/design.gd")
const Settings = preload("res://scripts/core/settings.gd")

const SUBTITLE_SIZES := [21, 26, 32]
const BANNER_SIZE := 28          # заголовок таблички
const BANNER_MIN_SIZE := 18      # длинный заголовок — мельче, а не в две строки
const BANNER_MAX_WIDTH := 540.0  # в игре табличка помещается между табло (левое кончается на 356)
const BANNER_TOP := 24.0         # в игре: табличка сверху, между табло
const BANNER_TOP_TOUCH := 104.0  # на сенсорном экране сверху табло яичницы — табличка под ним

var banner_plate: PanelContainer
var banner: Label
var banner_sub: Label
var banner_tween: Tween
var banner_in_game := false  # где стоит табличка: в игре — сверху, в меню — по центру
var banner_touch := false
var caption_max_width := 1e9  # на телефоне лента не заходит под стик и кнопки
var banner_free_width := 1e9  # сколько места между табло (в единицах этого слоя) — табличка не шире
var iron := false            # этап яичницы: таблички и лента — из чугуна (2.4)
var heat := 0.0
var caption_plate: PanelContainer
var caption_box: VBoxContainer
var speaker_label: Label
var caption_label: Label
var caption_tween: Tween
var caption_is_hint := false
var prompt_label: Label
var title_card: Label
var credits_label: Label
var credits_tween: Tween
var skip_button: Button
var t := 0.0
var bottom_margin := 0.0
var _jit := Vector2.ZERO  # текущий сдвиг субтитров от паники
var _relayout := 0        # сколько кадров ещё досчитывать размер табличек после смены текста


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	banner_plate = PanelContainer.new()
	banner_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_plate.modulate.a = 0.0
	banner_plate.visible = false
	add_child(banner_plate)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 0)
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_plate.add_child(bv)
	banner = Design.label("", "h2", Design.YOLK, HORIZONTAL_ALIGNMENT_CENTER)
	banner.label_settings.font_size = BANNER_SIZE
	banner.label_settings.outline_size = 4
	banner.label_settings.outline_color = Color(Design.INK, 0.85)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(banner)
	banner_sub = Design.label("", "small", Design.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_sub.visible = false
	bv.add_child(banner_sub)

	caption_plate = PanelContainer.new()  # лента подсказки (2.4): по ширине текста, внизу по центру
	caption_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_plate.modulate.a = 0.0
	add_child(caption_plate)
	caption_box = VBoxContainer.new()
	caption_box.alignment = BoxContainer.ALIGNMENT_END
	caption_box.add_theme_constant_override("separation", 0)
	caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_plate.add_child(caption_box)
	speaker_label = Design.label("", "overline", Design.TOMATO.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER)
	speaker_label.label_settings = Design.label_settings("hud", Design.TOMATO.lightened(0.2))
	speaker_label.label_settings.font_size = 16
	caption_box.add_child(speaker_label)
	caption_label = Design.label("", "hud", Design.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	caption_label.label_settings.font = Design.font("body")
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_box.add_child(caption_label)

	prompt_label = Design.label("", "hud_big", Design.YOLK, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_label.label_settings.font_size = 30
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_left = -500
	prompt_label.offset_right = 500
	prompt_label.offset_top = -160
	prompt_label.offset_bottom = -110
	prompt_label.pivot_offset = Vector2(500, 25)
	prompt_label.visible = false
	add_child(prompt_label)

	title_card = Design.label("", "display", Design.MINT, HORIZONTAL_ALIGNMENT_CENTER)
	title_card.label_settings = Design.label_settings("banner", Design.MINT)
	title_card.label_settings.font_size = 88
	title_card.set_anchors_preset(Control.PRESET_CENTER)
	title_card.offset_left = -700
	title_card.offset_right = 700
	title_card.offset_top = 150
	title_card.offset_bottom = 290
	title_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_card.pivot_offset = Vector2(700, 70)
	title_card.modulate.a = 0.0
	add_child(title_card)

	credits_label = Design.label("", "hud", Design.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	credits_label.label_settings.font_size = 24
	credits_label.label_settings.font = Design.font("body")
	credits_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	credits_label.visible = false
	add_child(credits_label)

	skip_button = Design.button("ПРОПУСТИТЬ  ›", skip_requested.emit, "Ghost", Vector2(180, Design.TOUCH_MIN))
	skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip_button.offset_left = -200
	skip_button.offset_right = -20
	skip_button.offset_top = 96
	skip_button.offset_bottom = 96 + Design.TOUCH_MIN
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.visible = false
	add_child(skip_button)


## Отступ ленты подсказки снизу: безопасная зона, киношные полосы, табло яичницы.
func set_bottom_margin(px: float) -> void:
	bottom_margin = px
	_jit = Vector2.ZERO
	_layout_caption()


## Где стоит табличка объявления: в игре — сверху между табло (на телефоне — под табло яичницы),
## в меню и на экранах — по центру. iron — этап яичницы (чугун, раскалённый на heat_k).
func set_banner_place(in_game: bool, touch: bool, on_iron := false, heat_k := 0.0) -> void:
	banner_in_game = in_game
	banner_touch = touch
	var restyle := on_iron != iron or not is_equal_approx(heat_k, heat)
	iron = on_iron
	heat = heat_k
	if restyle and caption_plate.get_theme_stylebox("panel") != null:
		_style_caption(speaker_label.visible)
	_layout_banner()


## «ЗАГОЛОВОК! пояснение» или «Заголовок — пояснение» → [заголовок, пояснение]. Короткий текст не делится.
static func split_banner(text: String) -> PackedStringArray:
	if text.length() <= 26:
		return PackedStringArray([text, ""])
	for sep in ["! ", " — "]:
		var i := text.find(sep)
		if i > 0 and i < text.length() - sep.length():
			var head := text.substr(0, i + (1 if sep == "! " else 0))
			return PackedStringArray([head, text.substr(i + sep.length())])
	return PackedStringArray([text, ""])


func show_banner(text: String, color := Design.YOLK, duration := 2.0) -> void:
	if banner_tween:
		banner_tween.kill()
	var parts := split_banner(text)
	banner.text = parts[0]
	banner.label_settings.font_color = color
	banner_sub.text = parts[1]
	banner_sub.visible = parts[1] != ""
	banner_plate.add_theme_stylebox_override("panel", Design.announce(color, iron, heat))
	banner_plate.visible = true
	_layout_banner()
	banner_plate.modulate.a = 0.0
	banner_tween = create_tween()
	banner_tween.tween_property(banner_plate, "modulate:a", 1.0, Design.BASE * 0.75)
	if not Settings.flag("reduced_motion"):  # табличку «вешают»: падает на место с лёгким перелётом
		banner_plate.pivot_offset = banner_plate.size / 2.0
		banner_plate.scale = Vector2(1.12, 1.12)
		banner_tween.parallel().tween_property(banner_plate, "scale", Vector2.ONE, Design.SLOW * 0.8) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_tween.tween_interval(duration)
	banner_tween.tween_property(banner_plate, "modulate:a", 0.0, 0.4)
	banner_tween.tween_callback(func() -> void: banner_plate.visible = false)


## Убрать табличку сразу (пауза, итоги): иначе она выглядывает из-за экрана.
func hide_banner() -> void:
	if banner_tween:
		banner_tween.kill()
	banner_plate.modulate.a = 0.0
	banner_plate.visible = false


func is_banner_shown() -> bool:
	return banner_plate.visible and banner_plate.modulate.a > 0.01


## Заголовок таблички — в одну строку: длинный мельче. Табличка — по ширине текста.
func _layout_banner() -> void:
	if banner_plate == null or size.x <= 0.0:
		return
	var max_w := minf(minf(BANNER_MAX_WIDTH, banner_free_width), size.x - 2.0 * Design.SPACE[5]) if banner_in_game 		else minf(760.0, size.x - 64.0)
	var inner := max_w - Design.SPACE[6] * 2.0
	var f := banner.label_settings.font
	var fs := BANNER_SIZE
	while fs > BANNER_MIN_SIZE and f.get_string_size(banner.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > inner:
		fs -= 1
	banner.label_settings.font_size = fs
	var title_w := f.get_string_size(banner.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var sub_w := 0.0
	if banner_sub.visible:
		sub_w = banner_sub.label_settings.font.get_string_size(banner_sub.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			banner_sub.label_settings.font_size).x
	var w := clampf(maxf(title_w, sub_w) + Design.SPACE[6] * 2.0 + 8.0, 220.0, max_w)
	var text_w := w - Design.SPACE[6] * 2.0
	# у текста с переносом минимальная высота считается по его текущей ширине: сначала ширина, потом высота
	for l: Label in [banner, banner_sub]:
		l.custom_minimum_size.x = text_w  # даже мельче не влез — перенос, а не вылет за табличку
		l.size.x = text_w
	banner_plate.size = Vector2(w, 0)
	banner_plate.reset_size()
	banner_plate.size = Vector2(w, banner_plate.get_combined_minimum_size().y)
	var top := (BANNER_TOP_TOUCH if banner_touch else BANNER_TOP) if banner_in_game else size.y * 0.3
	banner_plate.position = Vector2((size.x - w) / 2.0, top)
	_relayout = 2


## Субтитр (speaker не пустой) или подсказка (speaker пустой).
func show_caption(speaker: String, text: String, is_hint := false) -> void:
	caption_is_hint = is_hint
	if not is_hint and not Settings.flag("subtitles"):
		return
	speaker_label.text = speaker
	speaker_label.visible = speaker != ""
	caption_label.text = text
	caption_label.label_settings.font_size = SUBTITLE_SIZES[Settings.choice("subtitle_size")]
	_style_caption(speaker != "")
	_layout_caption()
	if caption_tween:
		caption_tween.kill()
	caption_plate.modulate.a = 0.0
	caption_tween = create_tween()
	caption_tween.tween_property(caption_plate, "modulate:a", 1.0, 0.35)


## Лампа ленты: подсказка — сталь «совет», реплика персонажа — томат, как имя говорящего.
func _style_caption(speaking: bool) -> void:
	var s := Design.strip(Design.TOMATO if speaking else Design.STEEL)
	if iron:
		s.kind = Design.Materials.Kind.CAST_IRON
		s.heat = heat
	caption_plate.add_theme_stylebox_override("panel", s)


## Лента — по ширине текста, по центру, над нижним отступом; длинный текст переносится.
func _layout_caption() -> void:
	if caption_plate == null or size.x <= 0.0:
		return
	var max_w := minf(minf(size.x - 2.0 * Design.SPACE[6], 1100.0), caption_max_width)
	var pad := Design.SPACE[6] * 2.0 + 2.0
	var f := caption_label.label_settings.font
	var tw := f.get_string_size(caption_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_label.label_settings.font_size).x
	var text_w := minf(tw + 4.0, max_w - pad)
	if tw + 4.0 > max_w - pad:  # в две строки и больше — строки поровну, а не одно слово на второй
		var lines := ceilf((tw + 4.0) / (max_w - pad))
		text_w = minf((tw + 4.0) / lines * 1.08 + 24.0, max_w - pad)
	caption_label.custom_minimum_size.x = text_w
	caption_label.size.x = text_w  # перенос считается по этой ширине, а не по прошлой
	speaker_label.size.x = text_w
	caption_plate.size = Vector2.ZERO
	caption_plate.reset_size()
	var sz := caption_plate.get_combined_minimum_size()
	caption_plate.size = sz
	_relayout = 2
	caption_plate.position = Vector2((size.x - sz.x) / 2.0, size.y - 10.0 - bottom_margin - sz.y) + _jit


func hide_caption() -> void:
	if caption_tween:
		caption_tween.kill()
	caption_tween = create_tween()
	caption_tween.tween_property(caption_plate, "modulate:a", 0.0, 0.4)


func is_caption_shown() -> bool:
	return caption_plate.modulate.a > 0.01


func show_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = true
	prompt_label.modulate.a = 0.0
	create_tween().tween_property(prompt_label, "modulate:a", 1.0, 0.4)


func hide_prompt() -> void:
	prompt_label.visible = false


func show_title_card(text: String, color: Color) -> void:
	title_card.text = text
	title_card.label_settings.font_color = color
	title_card.modulate.a = 0.0
	title_card.scale = Vector2(0.85, 0.85)
	var tw := create_tween()
	tw.tween_property(title_card, "modulate:a", 1.0, 1.6)
	tw.parallel().tween_property(title_card, "scale", Vector2.ONE, 4.0).set_ease(Tween.EASE_OUT)


func hide_title_card(time := 1.2) -> void:
	create_tween().tween_property(title_card, "modulate:a", 0.0, time)


## Титры ползут снизу вверх.
func roll_credits(text: String, duration: float) -> void:
	credits_label.text = text
	credits_label.visible = true
	credits_label.modulate.a = 1.0
	credits_label.position.y = size.y
	var h := (text.count("\n") + 1) * 36.0 + 100.0
	if credits_tween:
		credits_tween.kill()
	credits_tween = create_tween()
	credits_tween.tween_property(credits_label, "position:y", -h, duration)
	credits_tween.tween_callback(func() -> void: credits_label.visible = false)


func stop_credits() -> void:
	if credits_tween:
		credits_tween.kill()
	credits_label.visible = false
	title_card.modulate.a = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_banner()
		_layout_caption()


func _process(delta: float) -> void:
	t += delta
	if _relayout > 0:  # контейнер разложил текст — досчитать высоту табличек по настоящей ширине строк
		_relayout -= 1
		var n := _relayout
		_layout_banner()
		_layout_caption()
		_relayout = n
	if prompt_label.visible and not Settings.flag("reduced_motion"):
		prompt_label.scale = Vector2.ONE * (1.0 + 0.05 * sin(t * 6.0))
	_apply_panic()


## Паника: дрожь субтитров и мигание имени говорящего. Частота мигания растёт с паникой (4 → 22 Гц).
func _apply_panic() -> void:
	var p := Design.panic
	var j := Vector2.ZERO
	var lamp := 1.0
	if p > 0.05 and not Settings.flag("reduced_motion"):
		var k := floorf(t * 20.0)
		j = Vector2(sin(k * 12.9898), sin(k * 78.233)).sign() * roundf(1.0 + p)
		var hz := lerpf(4.0, 22.0, p)
		if sin(t * hz * TAU) * sin(t * 3.1) > 0.55 - 0.3 * p:
			lamp = 1.0 - 0.55 * p
	if j != _jit:
		caption_plate.position += j - _jit
		_jit = j
	speaker_label.modulate.a = lamp

