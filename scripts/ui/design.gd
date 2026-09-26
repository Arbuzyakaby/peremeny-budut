extends RefCounted
## Дизайн-язык «Ящик экспериментов» — единственный источник цветов, шрифтов, отступов, радиусов,
## теней и анимаций интерфейса. Описание и правила — docs/DESIGN.md.
## Идея: премиальная игрушечная мастерская в лаборатории. Тёплое тёмное дерево, кремовая бумага
## протокола, золото желтка — главный акцент.

const Settings = preload("res://scripts/core/settings.gd")

# ---------------------------------------------------------------- цвета

## Поверхности: от фона к приподнятым элементам.
const SURFACE_0 := Color(0.063, 0.039, 0.024)        # подложка, затемнение
const SURFACE_1 := Color(0.114, 0.075, 0.047, 0.95)  # панель
const SURFACE_2 := Color(0.165, 0.110, 0.071)        # карточка, кнопка
const SURFACE_3 := Color(0.227, 0.153, 0.098)        # наведение
const LINE := Color(0.353, 0.247, 0.153)             # тонкая рамка
const LINE_STRONG := Color(0.541, 0.392, 0.251)      # рамка активного
const INK := Color(0.078, 0.039, 0.02)               # обводка текста, текст на золоте
## Текст.
const CREAM := Color(1.0, 0.953, 0.875)              # основной
const MUTED := Color(0.804, 0.729, 0.62)             # вторичный
const FAINT := Color(0.55, 0.478, 0.388)             # подписи, неактивное
## Смысловые акценты.
const YOLK := Color(1.0, 0.79, 0.235)                # главный акцент, фокус, выбор
const YOLK_DEEP := Color(0.898, 0.604, 0.071)
const MINT := Color(0.482, 0.878, 0.541)             # успех, лечение, «хорошо»
const TOMATO := Color(1.0, 0.353, 0.271)             # опасность, урон
const STEEL := Color(0.498, 0.722, 1.0)              # информация, оглушение, щит
const RUST := Color(0.753, 0.396, 0.173)
const PLUM := Color(0.831, 0.42, 1.0)                # ультра-хардкор, редкое
## Акценты этапов: фанера, ржавчина, аптека, чугун с золотом.
const STAGE_ACCENTS := [Color(0.851, 0.627, 0.4), Color(0.753, 0.396, 0.173), Color(0.373, 0.831, 0.769), YOLK]
## Фазы яичницы.
const PHASE_COLORS := [Color(1, 0.8, 0.15), Color(1, 0.55, 0.1), Color(0.95, 0.25, 0.1)]

# ---------------------------------------------------------------- размеры

const SPACE := [0, 4, 8, 12, 16, 24, 32, 48]  # шкала отступов: SPACE[4] = 16
const RADIUS_SM := 8
const RADIUS_MD := 14
const RADIUS_LG := 22
const RADIUS_PILL := 999
const BORDER := 2
const TOUCH_MIN := 52.0  # минимальная высота нажимаемого элемента (≈ 48dp)

## Типографика: роль → [размер, вес (heavy/bold/body/mono), обводка].
const TYPE := {
	"display": [72, "heavy", 0],
	"h1": [44, "heavy", 0],
	"h2": [30, "heavy", 0],
	"h3": [22, "bold", 0],
	"body": [20, "body", 0],
	"small": [16, "body", 0],
	"caption": [14, "bold", 0],
	"overline": [13, "heavy", 0],  # надписи капсом над группами
	"number": [30, "heavy", 0],
	"hud": [18, "heavy", 5],       # поверх игрового поля — с обводкой
	"hud_big": [34, "heavy", 7],
	"banner": [44, "heavy", 10],
}

# ---------------------------------------------------------------- движение

const FAST := 0.12     # наведение, нажатие
const BASE := 0.2      # появление элементов
const SLOW := 0.35     # панели и экраны
const SCENIC := 0.6    # заголовки и сцены
const STAGGER := 0.04  # задержка между элементами списка

static var _fonts: Dictionary = {}
## Проигрыватель звуков интерфейса (sfx.gd). Назначается HUD.
static var sound_player: Node


# ---------------------------------------------------------------- шрифты

static func clear_cache() -> void:
	_fonts.clear()
	sound_player = null


static func font(weight: String) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var f := SystemFont.new()
	match weight:
		"heavy":
			f.font_names = PackedStringArray(["Segoe UI Black", "Arial Black", "Roboto Black", "Roboto", "sans-serif"])
			f.font_weight = 900
		"bold":
			f.font_names = PackedStringArray(["Segoe UI Semibold", "Segoe UI", "Roboto Medium", "Roboto", "sans-serif"])
			f.font_weight = 700
		"mono":
			f.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Roboto Mono", "Droid Sans Mono", "monospace"])
			f.font_weight = 600
		_:
			f.font_names = PackedStringArray(["Segoe UI", "Roboto", "Arial", "sans-serif"])
			f.font_weight = 600
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_fonts[weight] = f
	return f


static func size_of(role: String) -> int:
	return TYPE.get(role, TYPE["body"])[0]


static func font_of(role: String) -> Font:
	return font(TYPE.get(role, TYPE["body"])[1])


static func label_settings(role: String, color := CREAM) -> LabelSettings:
	var t: Array = TYPE.get(role, TYPE["body"])
	var ls := LabelSettings.new()
	ls.font = font(t[1])
	ls.font_size = t[0]
	ls.font_color = color
	if t[2] > 0:
		ls.outline_size = t[2]
		ls.outline_color = Color(INK, 0.92)
		ls.shadow_size = 2
		ls.shadow_color = Color(0, 0, 0, 0.35)
		ls.shadow_offset = Vector2(1, 2)
	if role in ["display", "h1"]:  # тиснение: мягкая тень под заголовком
		ls.shadow_size = 6
		ls.shadow_color = Color(0, 0, 0, 0.45)
		ls.shadow_offset = Vector2(0, 4)
	return ls


static func label(text: String, role := "body", color := CREAM, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = label_settings(role, color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- поверхности

static func box(bg: Color, border := Color.TRANSPARENT, radius := RADIUS_MD, border_w := BORDER,
		pad := Vector2(SPACE[5], SPACE[3])) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.corner_detail = 10
	s.anti_aliasing_size = 1.0
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	return s


## Приподнятая поверхность: 1 — карточка, 2 — панель, 3 — диалог поверх всего.
static func elevated(bg: Color, border: Color, radius: int, level: int, pad := Vector2(SPACE[6], SPACE[5])) -> StyleBoxFlat:
	var s := box(bg, border, radius, BORDER, pad)
	s.shadow_color = Color(0, 0, 0, [0.0, 0.25, 0.42, 0.55][clampi(level, 0, 3)])
	s.shadow_size = [0, 6, 16, 28][clampi(level, 0, 3)]
	s.shadow_offset = Vector2(0, [0, 3, 8, 12][clampi(level, 0, 3)])
	return s


static func panel_style() -> StyleBoxFlat:
	return elevated(SURFACE_1, LINE, RADIUS_LG, 2, Vector2(SPACE[7] - 8, SPACE[6]))


static func focus_ring(radius := RADIUS_MD + 3) -> StyleBoxFlat:
	var s := box(Color.TRANSPARENT, YOLK, radius, 3, Vector2.ZERO)
	s.draw_center = false
	s.set_expand_margin_all(4)
	return s


## Цвет с учётом режима дальтоника: опасность, предупреждение, безопасно.
static func danger() -> Color:
	return Color(1.0, 0.62, 0.0) if Settings.flag("colorblind") else TOMATO


static func warn() -> Color:
	return Color(1.0, 0.92, 0.3) if Settings.flag("colorblind") else Color(1, 0.7, 0.1)


static func safe() -> Color:
	return STEEL if Settings.flag("colorblind") else MINT


## Толщина линий предупреждений (режим высокой контрастности делает их жирнее).
static func telegraph_width(base: float) -> float:
	return base * (1.8 if Settings.flag("high_contrast") else 1.0)


# ---------------------------------------------------------------- тема

static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = font("body")
	th.default_font_size = size_of("body")
	th.set_stylebox("panel", "PanelContainer", panel_style())
	th.set_stylebox("panel", "Panel", panel_style())
	_button_styles(th, "Button", SURFACE_2, LINE, SURFACE_3, YOLK, CREAM, CREAM)
	_button_styles(th, "PrimaryButton", YOLK, YOLK_DEEP, YOLK.lightened(0.18), Color(1, 0.95, 0.75), INK, INK)
	_button_styles(th, "GhostButton", Color.TRANSPARENT, Color.TRANSPARENT, Color(1, 1, 1, 0.06), LINE, MUTED, CREAM)
	_button_styles(th, "DangerButton", TOMATO.darkened(0.72), TOMATO.darkened(0.3), TOMATO.darkened(0.55), TOMATO, CREAM, CREAM)
	_button_styles(th, "SegmentButton", Color.TRANSPARENT, Color.TRANSPARENT, Color(1, 1, 1, 0.06), Color.TRANSPARENT, MUTED, CREAM)
	for v in ["PrimaryButton", "GhostButton", "DangerButton", "SegmentButton"]:
		th.set_type_variation(v, "Button")
	# выбранный сегмент — золотая плашка
	var seg_on := box(YOLK, Color.TRANSPARENT, RADIUS_PILL, 0, Vector2(SPACE[4], SPACE[2]))
	th.set_stylebox("pressed", "SegmentButton", seg_on)
	th.set_stylebox("hover_pressed", "SegmentButton", seg_on)
	th.set_color("font_pressed_color", "SegmentButton", INK)
	th.set_color("font_hover_pressed_color", "SegmentButton", INK)
	th.set_font("font", "SegmentButton", font("heavy"))
	th.set_font_size("font_size", "SegmentButton", 15)
	for st in ["normal", "hover", "focus", "disabled"]:
		var sb := th.get_stylebox(st, "SegmentButton") as StyleBoxFlat
		if sb:
			sb.set_corner_radius_all(RADIUS_PILL)
			sb.content_margin_left = SPACE[4]
			sb.content_margin_right = SPACE[4]
			sb.content_margin_top = SPACE[2]
			sb.content_margin_bottom = SPACE[2]
	# ползунок
	var track := box(SURFACE_0, LINE, RADIUS_PILL, 1, Vector2(0, 4))
	th.set_stylebox("slider", "HSlider", track)
	var fill := box(YOLK_DEEP, Color.TRANSPARENT, RADIUS_PILL, 0, Vector2(0, 4))
	th.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := box(YOLK, Color.TRANSPARENT, RADIUS_PILL, 0, Vector2(0, 4))
	th.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	th.set_stylebox("focus", "HSlider", focus_ring(RADIUS_PILL))
	th.set_icon("grabber", "HSlider", _knob_texture(22, CREAM))
	th.set_icon("grabber_highlight", "HSlider", _knob_texture(24, Color.WHITE))
	# прокрутка — тонкая полоса
	var bar := box(Color(1, 1, 1, 0.04), Color.TRANSPARENT, RADIUS_PILL, 0, Vector2(3, 3))
	var grab := box(LINE_STRONG, Color.TRANSPARENT, RADIUS_PILL, 0, Vector2(3, 3))
	var grab_hi := box(YOLK_DEEP, Color.TRANSPARENT, RADIUS_PILL, 0, Vector2(3, 3))
	th.set_stylebox("scroll", "VScrollBar", bar)
	th.set_stylebox("grabber", "VScrollBar", grab)
	th.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	th.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
	th.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var sep := StyleBoxLine.new()
	sep.color = Color(LINE, 0.8)
	sep.thickness = 1
	th.set_stylebox("separator", "HSeparator", sep)
	th.set_constant("separation", "HSeparator", SPACE[4])
	th.set_color("font_color", "Label", CREAM)
	th.set_font("font", "TooltipLabel", font("body"))
	return th


static func _button_styles(th: Theme, type: String, bg: Color, border: Color, bg_hover: Color, border_hover: Color,
		text: Color, text_hover: Color) -> void:
	var pad := Vector2(SPACE[5], SPACE[3])
	th.set_stylebox("normal", type, box(bg, border, RADIUS_MD, BORDER, pad))
	th.set_stylebox("hover", type, box(bg_hover, border_hover, RADIUS_MD, BORDER, pad))
	th.set_stylebox("pressed", type, box(bg.darkened(0.15) if bg.a > 0.0 else Color(0, 0, 0, 0.15), border_hover, RADIUS_MD, BORDER, pad))
	th.set_stylebox("hover_pressed", type, box(bg_hover, border_hover, RADIUS_MD, BORDER, pad))
	th.set_stylebox("disabled", type, box(Color(bg, bg.a * 0.4), Color(border, border.a * 0.4), RADIUS_MD, BORDER, pad))
	th.set_stylebox("focus", type, focus_ring())
	th.set_font("font", type, font("heavy"))
	th.set_font_size("font_size", type, 19)
	th.set_color("font_color", type, text)
	th.set_color("font_focus_color", type, text_hover)
	th.set_color("font_hover_color", type, text_hover)
	th.set_color("font_pressed_color", type, text_hover)
	th.set_color("font_hover_pressed_color", type, text_hover)
	th.set_color("font_disabled_color", type, Color(text, 0.4))


static func _knob_texture(d: int, col: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) / 2.0
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(c.x - dist, 0.0, 1.0)
			var shade := col if dist < c.x - 2.5 else col.darkened(0.35)
			img.set_pixel(x, y, Color(shade, a))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- компоненты

## Кнопка. variant: "" (обычная), "Primary", "Ghost", "Danger".
static func button(text: String, on_press: Callable, variant := "", min_size := Vector2(0, TOUCH_MIN)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	if variant != "":
		b.theme_type_variation = variant + "Button"
	b.pressed.connect(func() -> void:
		play("ui_select")
		press_bounce(b)
		on_press.call())
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus())
	b.focus_entered.connect(play.bind("ui_move"))
	return b


## Короткое «пружинящее» нажатие.
static func press_bounce(c: Control) -> void:
	if Settings.flag("reduced_motion") or not c.is_inside_tree():
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(0.95, 0.95), FAST * 0.5)
	tw.tween_property(c, "scale", Vector2.ONE, FAST * 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Плавное появление: прозрачность и небольшой подъём снизу.
static func appear(c: CanvasItem, delay := 0.0, rise := 14.0) -> void:
	if Settings.flag("reduced_motion"):
		c.modulate.a = 1.0
		return
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, BASE)
	if c is Control and rise != 0.0:
		var ctl := c as Control
		var to := ctl.position.y
		ctl.position.y = to + rise
		tw.parallel().tween_property(ctl, "position:y", to, SLOW).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Надпись капсом над группой (overline) и тонкая линия.
static func section(text: String, color := YOLK) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", SPACE[1])
	v.add_child(label(text, "overline", color))
	return v


## Бейдж-«таблетка»: сложность, DEV, статус.
static func chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(color, 0.16), Color(color, 0.7), RADIUS_PILL, 1, Vector2(SPACE[3], 2)))
	p.add_child(label(text, "caption", color))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hbox(gap := SPACE[4], align := BoxContainer.ALIGNMENT_CENTER) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.alignment = align
	return h


static func vbox(gap := SPACE[3]) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


static func play(sound_name: String) -> void:
	if is_instance_valid(sound_player):
		sound_player.play(sound_name)


## Нарисовать полосу прогресса: стамина, HP, загрузка.
static func draw_bar(ci: CanvasItem, r: Rect2, value: float, col: Color, ghost := -1.0) -> void:
	var rad := int(r.size.y / 2.0)
	var bg := box(Color(0.02, 0.01, 0.0, 0.55), Color(LINE, 0.8), rad, 1, Vector2.ZERO)
	ci.draw_style_box(bg, r.grow(2))
	if ghost > value:
		var g := Rect2(r.position, Vector2(maxf(r.size.x * clampf(ghost, 0.0, 1.0), r.size.y), r.size.y))
		ci.draw_style_box(box(Color(CREAM, 0.7), Color.TRANSPARENT, rad, 0, Vector2.ZERO), g)
	if value <= 0.0:
		return
	var fr := Rect2(r.position, Vector2(maxf(r.size.x * clampf(value, 0.0, 1.0), r.size.y), r.size.y))
	ci.draw_style_box(box(col, Color.TRANSPARENT, rad, 0, Vector2.ZERO), fr)
	var sheen := Rect2(fr.position + Vector2(rad * 0.6, 2), Vector2(maxf(fr.size.x - rad * 1.2, 0.0), maxf(r.size.y * 0.28, 1.5)))
	ci.draw_rect(sheen, Color(1, 1, 1, 0.3))
