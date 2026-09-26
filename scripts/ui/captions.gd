extends Control
## Текст поверх игры: баннер по центру, субтитры и подсказки внизу, приглашение к действию,
## большой титр финала, титры и кнопка «Пропустить».

signal skip_requested

const Design = preload("res://scripts/ui/design.gd")
const Settings = preload("res://scripts/core/settings.gd")

const SUBTITLE_SIZES := [21, 26, 32]

var banner: Label
var banner_tween: Tween
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


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	banner = Design.label("", "banner", Design.YOLK, HORIZONTAL_ALIGNMENT_CENTER)
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 150
	banner.offset_bottom = 215
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.modulate.a = 0.0
	add_child(banner)

	caption_box = VBoxContainer.new()
	caption_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption_box.offset_top = -96
	caption_box.offset_bottom = -8
	caption_box.alignment = BoxContainer.ALIGNMENT_END
	caption_box.add_theme_constant_override("separation", 0)
	caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_box.modulate.a = 0.0
	add_child(caption_box)
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


## Учесть безопасную зону и киношные полосы.
func set_bottom_margin(px: float) -> void:
	bottom_margin = px
	caption_box.offset_bottom = -8 - px
	caption_box.offset_top = -120 - px


func show_banner(text: String, color := Design.YOLK, duration := 2.0) -> void:
	if banner_tween:
		banner_tween.kill()
	banner.text = text
	banner.label_settings.font_color = color
	banner.modulate.a = 0.0
	banner.pivot_offset = banner.size / 2.0
	banner_tween = create_tween()
	banner_tween.tween_property(banner, "modulate:a", 1.0, 0.15)
	if not Settings.flag("reduced_motion"):
		banner.scale = Vector2(1.5, 1.5)
		banner_tween.parallel().tween_property(banner, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_tween.tween_interval(duration)
	banner_tween.tween_property(banner, "modulate:a", 0.0, 0.4)


## Субтитр (speaker не пустой) или подсказка (speaker пустой).
func show_caption(speaker: String, text: String, is_hint := false) -> void:
	caption_is_hint = is_hint
	if not is_hint and not Settings.flag("subtitles"):
		return
	speaker_label.text = speaker
	speaker_label.visible = speaker != ""
	caption_label.text = text
	caption_label.label_settings.font_size = SUBTITLE_SIZES[Settings.choice("subtitle_size")]
	if caption_tween:
		caption_tween.kill()
	caption_box.modulate.a = 0.0
	caption_tween = create_tween()
	caption_tween.tween_property(caption_box, "modulate:a", 1.0, 0.35)


func hide_caption() -> void:
	if caption_tween:
		caption_tween.kill()
	caption_tween = create_tween()
	caption_tween.tween_property(caption_box, "modulate:a", 0.0, 0.4)


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


func _process(delta: float) -> void:
	t += delta
	if prompt_label.visible and not Settings.flag("reduced_motion"):
		prompt_label.scale = Vector2.ONE * (1.0 + 0.05 * sin(t * 6.0))
