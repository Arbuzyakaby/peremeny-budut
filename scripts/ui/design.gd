extends RefCounted
## Дизайн-язык «Ящик экспериментов» 2.0 — единственный источник цветов, шрифтов, отступов, радиусов,
## материалов, теней и анимаций интерфейса. Описание и правила — docs/DESIGN.md.
## Идея: интерфейс — панель лабораторного прибора, вмонтированная в деревянный ящик. Никаких плоских
## «цифровых» заливок: у каждой кнопки, тумблера и крутилки есть материал (бакелит, латунь, хром,
## эмаль, лакированное дерево), фаска, тень, ход при нажатии и свой механический звук.

const Settings = preload("res://scripts/core/settings.gd")
const PhysicalBox = preload("res://scripts/ui/widgets/physical_box.gd")
const Materials = preload("res://scripts/ui/materials.gd")

# ---------------------------------------------------------------- цвета

## Поверхности: от фона к приподнятым элементам.
const SURFACE_0 := Color(0.063, 0.039, 0.024)        # подложка, затемнение
const SURFACE_1 := Color(0.114, 0.075, 0.047, 0.95)  # панель
const SURFACE_2 := Color(0.165, 0.110, 0.071)        # карточка, кнопка
const SURFACE_3 := Color(0.227, 0.153, 0.098)        # наведение
const LINE := Color(0.353, 0.247, 0.153)             # тонкая рамка
const LINE_STRONG := Color(0.541, 0.392, 0.251)      # рамка активного
const INK := Color(0.078, 0.039, 0.02)               # обводка текста, текст на латуни
## Текст.
const CREAM := Color(1.0, 0.953, 0.875)              # основной
const MUTED := Color(0.804, 0.729, 0.62)             # вторичный
const FAINT := Color(0.55, 0.478, 0.388)             # подписи, неактивное
## Смысловые акценты.
const YOLK := Color(1.0, 0.79, 0.235)                # главный акцент, фокус, выбор, лампы
const YOLK_DEEP := Color(0.898, 0.604, 0.071)
const MINT := Color(0.482, 0.878, 0.541)             # успех, лечение, «хорошо»
const TOMATO := Color(1.0, 0.353, 0.271)             # опасность, урон
const STEEL := Color(0.498, 0.722, 1.0)              # информация, оглушение, щит
const RUST := Color(0.753, 0.396, 0.173)
const PLUM := Color(0.831, 0.42, 1.0)                # ультра-хардкор, редкое
const BRASS := Color(0.86, 0.64, 0.25)               # оправы, петли, заклёпки
## Акценты этапов: фанера, медь ящика для вилок, аптека, чугун с золотом.
const STAGE_ACCENTS := [Color(0.851, 0.627, 0.4), Color(0.85, 0.42, 0.16), Color(0.373, 0.831, 0.769), YOLK]
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
const KEY_TRAVEL := 4.0  # ход клавиши, px

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
	"readout": [16, "mono", 0],    # цифры в окошке счётчика: значения крутилок и фейдеров
	"hud": [18, "heavy", 5],       # поверх игрового поля — с обводкой
	"hud_big": [34, "heavy", 7],
	"banner": [44, "heavy", 10],
}

# ---------------------------------------------------------------- движение

const FAST := 0.08     # наведение, нажатие (80 мс — на грани восприятия, отклик не «лагает»)
const BASE := 0.2      # появление элементов, тумблер
const SLOW := 0.35     # панели и экраны
const SCENIC := 0.6    # заголовки и сцены
const STAGGER := 0.04  # задержка между элементами списка

static var _fonts: Dictionary = {}
static var _knobs: Dictionary = {}
static var _styles: Dictionary = {}
## Проигрыватель звуков интерфейса (sfx.gd). Назначается HUD.
static var sound_player: Node
## «Паника» интерфейса 0..1: в финале её поднимает пожар (доля горящего). Лампы и нити накала
## мигают чаще, табло подрагивают, снизу панелей идёт отблеск огня. 0 — спокойный прибор.
static var panic := 0.0


# ---------------------------------------------------------------- шрифты

static func clear_cache() -> void:
	_fonts.clear()
	_knobs.clear()
	_styles.clear()
	Materials.clear_cache()
	sound_player = null
	panic = 0.0


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

## Плоская плашка — только для служебного (графики панели разработчика, HUD-свечения). Всё, что
## нажимается или изображает предмет, — через key(), well(), plank(), plate(), card_style().
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
## В 2.0 это лакированная доска (на уровнях 2–3 — на винтах); border, отличный от LINE, — цветная
## кромка смысла (например, фиолетовая у панели разработчика).
static func elevated(bg: Color, border: Color, radius: int, level: int, pad := Vector2(SPACE[6], SPACE[5])) -> StyleBox:
	var s := plank(Color(0, 0, 0, 0) if border == LINE else border, radius, pad, level >= 2)
	s.shadow = level > 0
	if bg.a < 0.9:
		s.grain = 0.06
	return s


## Панель-доска: тёмное лакированное дерево на винтах.
static func plank(accent := Color(0, 0, 0, 0), radius := RADIUS_LG, pad := Vector2(SPACE[6], SPACE[5]), screws := true) -> PhysicalBox:
	var s := PhysicalBox.new()
	s.mode = PhysicalBox.Mode.PANEL
	s.kind = Materials.Kind.WOOD
	s.radius = radius
	s.depth = 0.0
	s.grain = 0.09
	s.accent = accent
	s.screws = screws
	s.set_pads(pad)
	return s


## Клавиша из материала. state: normal, hover, pressed, hover_pressed, disabled.
static func key(material: int, tint := Color(0, 0, 0, 0), state := "normal", radius := RADIUS_MD, travel := KEY_TRAVEL,
		pad := Vector2(SPACE[5], SPACE[3])) -> PhysicalBox:
	var s := PhysicalBox.new()
	s.mode = PhysicalBox.Mode.KEY
	s.kind = material
	s.tint = tint
	s.radius = radius
	s.depth = travel
	s.pressed = state in ["pressed", "hover_pressed"]
	s.hover = state in ["hover", "hover_pressed"]
	s.disabled = state == "disabled"
	s.grain = 0.07 if material in [Materials.Kind.BAKELITE, Materials.Kind.RUBBER] else 0.08
	s.set_pads(pad)
	return s


## Утопленная ниша: дорожка фейдера, окно шкалы, гнездо переключателя.
static func well(radius := RADIUS_MD, pad := Vector2(4, 4), accent := Color(0, 0, 0, 0)) -> PhysicalBox:
	var s := PhysicalBox.new()
	s.mode = PhysicalBox.Mode.INSET
	s.kind = Materials.Kind.RUBBER
	s.radius = radius
	s.depth = 0.0
	s.accent = accent
	s.set_pads(pad)
	return s


## Карточка-клавиша со смыслом (сложность, улучшение, узел древа): бакелит, цветная кромка и лампа.
static func card_style(color: Color, state := "normal", radius := RADIUS_MD, pad := Vector2(SPACE[4], SPACE[3])) -> PhysicalBox:
	var s := key(Materials.Kind.BAKELITE, Color(0, 0, 0, 0), state, radius, KEY_TRAVEL, pad)
	s.accent = Color(color, 0.55) if state == "normal" else color
	s.lamp = Color(color, 0.35) if state == "normal" else color
	if state == "disabled":
		s.accent = Color(color, 0.2)
		s.lamp = Color(0, 0, 0, 0)
	return s


## Эмалевая табличка в латунной оправе, без хода: бейджи, таблички HUD.
static func plate(color: Color, pad := Vector2(SPACE[3], 3), radius := RADIUS_SM) -> PhysicalBox:
	var s := key(Materials.Kind.ENAMEL, color.darkened(0.55), "normal", radius, 1.0, pad)
	s.accent = Color(BRASS, 0.9)
	s.shadow = false
	return s


static func panel_style() -> StyleBox:
	return plank(Color(0, 0, 0, 0), RADIUS_LG, Vector2(SPACE[7] - 8, SPACE[6]))


## Фокус: латунная окантовка грани с нитью накала цвета желтка — внутри клавиши, не за её краем.
## travel — ход клавиши: окантовка обходит лицевую грань, а не боковину.
static func focus_ring(radius := RADIUS_MD, travel := KEY_TRAVEL) -> StyleBox:
	var s := PhysicalBox.new()
	s.mode = PhysicalBox.Mode.FOCUS
	s.radius = radius
	s.depth = travel
	s.accent = YOLK
	s.shadow = false
	return s


## Фокус круглого контрола (крутилка, галетник): латунное кольцо с нитью накала вокруг ручки.
static func draw_focus_circle(ci: CanvasItem, c: Vector2, r: float) -> void:
	var pal: Array = Materials.palette(Materials.Kind.BRASS)
	ci.draw_arc(c, r, 0, TAU, 48, Color(0, 0, 0, 0.55), 4.0, true)
	ci.draw_arc(c, r, PI, TAU, 24, pal[0], 1.6, true)
	ci.draw_arc(c, r, 0, PI, 24, pal[2], 1.6, true)
	ci.draw_arc(c, r - 2.6, 0, TAU, 48, Color(YOLK, 0.95), 1.8, true)
	ci.draw_arc(c, r - 4.4, 0, TAU, 48, Color(YOLK, 0.3), 1.6, true)


## Кэш стилей, которые рисуются каждый кадр (HUD): не плодить объекты.
static func cached(id: String, make: Callable) -> StyleBox:
	if not _styles.has(id):
		_styles[id] = make.call()
	return _styles[id]


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

## Тема Godot из материалов дизайн-языка (сборка — в theme_factory.gd; загружается по запросу,
## чтобы не было циклического preload: фабрика сама пользуется этим модулем).
static func make_theme() -> Theme:
	return load("res://scripts/ui/theme_factory.gd").build()


## Латунная ручка-бегунок (иконка HSlider): радиальный блик, тёмная кромка, риска.
static func knob_texture(d: int, lit: bool) -> ImageTexture:
	var id := "%d_%s" % [d, lit]
	if _knobs.has(id):
		return _knobs[id]
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) / 2.0
	var pal: Array = Materials.palette(Materials.Kind.BRASS)
	for y in d:
		for x in d:
			var p := Vector2(x + 0.5, y + 0.5)
			var dist := p.distance_to(c)
			var a := clampf(c.x - dist, 0.0, 1.0)
			var light := clampf(1.0 - p.distance_to(c - Vector2(d, d) * 0.18) / d, 0.0, 1.0)
			var col: Color = (pal[2] as Color).lerp(pal[0], clampf(light * 1.2, 0.0, 1.0))
			if lit:
				col = col.lightened(0.15)
			if dist > c.x - 2.0:
				col = (pal[2] as Color).darkened(0.3)
			if absf(p.x - c.x) < 1.0 and p.y < c.y - 2.0 and p.y > 3.0:  # риска
				col = Color(0.2, 0.12, 0.04)
			img.set_pixel(x, y, Color(col, a))
	var tex := ImageTexture.create_from_image(img)
	_knobs[id] = tex
	return tex


# ---------------------------------------------------------------- компоненты

## Кнопка-клавиша. variant: "" (бакелит), "Primary" (латунь), "Ghost" (резина), "Danger" (эмаль под
## откидной крышкой — см. set_cover), "Card" (карточка). Звук: глухой «тук» при нажатии, щелчок при отпускании.
static func button(text: String, on_press: Callable, variant := "", min_size := Vector2(0, TOUCH_MIN)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	if variant != "":
		b.theme_type_variation = variant + "Button"
	if variant == "Danger":
		_add_cover(b)
	b.button_down.connect(play.bind("ui_key_down"))
	b.pressed.connect(func() -> void:
		play("ui_select")
		press_bounce(b)
		on_press.call())
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus())
	b.focus_entered.connect(play.bind("ui_move"))
	return b


## Отдача клавиши после нажатия: ход вниз показывает сама грань (PhysicalBox), здесь — лёгкий
## упругий отскок корпуса, чтобы нажатие с клавиатуры и с телефона тоже ощущалось.
static func press_bounce(c: Control) -> void:
	if Settings.flag("reduced_motion") or not c.is_inside_tree():
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(0.975, 0.965), FAST * 0.4)
	tw.tween_property(c, "scale", Vector2.ONE, FAST * 1.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


const REFUSE_TIME := 0.15  # вспышка отказа
const REFUSE_SHAKE := 3.0  # px


## Видимый отказ «нельзя»: дребезг реле, контрол дёргается вбок на 3 px и возвращается, лицо на
## 150 мс вспыхивает томатным. Без картинки игрок решит, что клик не дошёл, и нажмёт ещё раз.
## «Меньше анимации» оставляет только вспышку.
static func refuse(c: CanvasItem) -> void:
	play("ui_error")
	if c == null or not c.is_inside_tree():
		return
	var base_mod: Color = c.get_meta("refuse_mod", c.modulate)  # повторный отказ — от исходного цвета
	c.set_meta("refuse_mod", base_mod)
	var tw := c.create_tween()
	c.modulate = base_mod * Color(danger().lightened(0.35), 1.0)
	tw.tween_property(c, "modulate", base_mod, REFUSE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: c.remove_meta("refuse_mod"))
	if Settings.flag("reduced_motion") or not (c is Control):
		return
	var ctl := c as Control
	var x: float = ctl.get_meta("refuse_x", ctl.position.x)
	ctl.set_meta("refuse_x", x)
	var sh := ctl.create_tween()
	for dx in [REFUSE_SHAKE, -REFUSE_SHAKE * 0.8, REFUSE_SHAKE * 0.4, 0.0]:
		sh.tween_property(ctl, "position:x", x + dx, REFUSE_TIME / 4.0)
	sh.tween_callback(func() -> void: ctl.remove_meta("refuse_x"))


## Откидная прозрачная крышка над опасной клавишей: закрыта — клавиша под стеклом, открыта —
## откинута вверх. Экран открывает её первым нажатием (подтверждение) и закрывает после действия.
static func _add_cover(b: Button) -> void:
	var cover := Control.new()
	cover.name = "Cover"
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_meta("open", 0.0)
	cover.draw.connect(_draw_cover.bind(cover))
	b.add_child(cover)


static func _draw_cover(cover: Control) -> void:
	var k: float = cover.get_meta("open")
	var r := Rect2(Vector2(-3, -3), cover.size + Vector2(6, 2))
	if k < 0.5:  # крышка опущена: стекло с бликом
		var h := r.size.y * (1.0 - k * 2.0)
		var glass := Rect2(r.position, Vector2(r.size.x, h))
		cover.draw_rect(glass, Color(1, 0.55, 0.45, 0.14))
		cover.draw_rect(glass, Color(1, 0.8, 0.75, 0.45), false, 1.5)
		cover.draw_line(glass.position + Vector2(10, 6), glass.position + Vector2(glass.size.x * 0.4, 6), Color(1, 1, 1, 0.35), 2.0)
	else:  # откинута: видно ребро над клавишей
		var h2 := 10.0 * (k - 0.5) * 2.0
		cover.draw_rect(Rect2(r.position - Vector2(0, h2), Vector2(r.size.x, h2)), Color(1, 0.6, 0.5, 0.3))
		cover.draw_line(r.position - Vector2(0, h2), Vector2(r.end.x, r.position.y - h2), Color(1, 0.85, 0.8, 0.6), 1.5)
	for x in [14.0, r.size.x - 14.0]:  # латунные петли
		cover.draw_rect(Rect2(r.position + Vector2(x - 5, -2), Vector2(10, 5)), BRASS)


## Открыть или закрыть крышку опасной клавиши (со звуком и анимацией).
static func set_cover(b: Button, open: bool) -> void:
	var cover := b.get_node_or_null("Cover") as Control
	if cover == null:
		return
	var to := 1.0 if open else 0.0
	if is_equal_approx(float(cover.get_meta("open")), to):
		return
	play("ui_cover")
	if Settings.flag("reduced_motion") or not cover.is_inside_tree():
		cover.set_meta("open", to)
		cover.queue_redraw()
		return
	cover.create_tween().tween_method(func(k: float) -> void:
		cover.set_meta("open", k)
		cover.queue_redraw(), float(cover.get_meta("open")), to, BASE)


static func cover_open(b: Button) -> bool:
	var cover := b.get_node_or_null("Cover") as Control
	return cover != null and float(cover.get_meta("open")) > 0.5


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


## Надпись капсом над группой (overline).
static func section(text: String, color := YOLK) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", SPACE[1])
	v.add_child(label(text, "overline", color))
	return v


## Бейдж — эмалевая табличка в латунной оправе: сложность, DEV, статус.
static func chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", plate(color, Vector2(SPACE[3], 3)))
	p.add_child(label(text, "caption", color.lightened(0.35)))
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


## Полоса прогресса — стеклянная трубка-индикатор в латунной оправе с «жидкостью» цвета col:
## стамина, HP, загрузка. ghost — «призрак» потерянного значения.
static func draw_bar(ci: CanvasItem, r: Rect2, value: float, col: Color, ghost := -1.0) -> void:
	var rad := int(r.size.y / 2.0)
	ci.draw_style_box(cached("tube_rim_%d" % rad, func() -> StyleBox:
		var s := key(Materials.Kind.BRASS, Color(0, 0, 0, 0), "normal", rad + 3, 0.0, Vector2.ZERO)
		s.shadow = false
		return s), r.grow(3))
	ci.draw_style_box(cached("tube_well_%d" % rad, func() -> StyleBox: return well(rad, Vector2.ZERO)), r)
	if ghost > value:
		var g := Rect2(r.position, Vector2(maxf(r.size.x * clampf(ghost, 0.0, 1.0), r.size.y), r.size.y))
		ci.draw_style_box(box(Color(CREAM, 0.55), Color.TRANSPARENT, rad, 0, Vector2.ZERO), g)
	if value > 0.0:
		var fr := Rect2(r.position, Vector2(maxf(r.size.x * clampf(value, 0.0, 1.0), r.size.y), r.size.y))
		ci.draw_style_box(box(col.darkened(0.2), Color.TRANSPARENT, rad, 0, Vector2.ZERO), fr)
		var core := Rect2(fr.position + Vector2(0, r.size.y * 0.22), Vector2(fr.size.x, r.size.y * 0.42))
		ci.draw_style_box(box(col.lightened(0.18), Color.TRANSPARENT, int(core.size.y / 2.0), 0, Vector2.ZERO), core)
		ci.draw_line(Vector2(fr.end.x - 1.5, fr.position.y + 2), Vector2(fr.end.x - 1.5, fr.end.y - 2),
			Color(col.lightened(0.5), 0.9), 2.0)  # мениск
	# стекло: блик сверху и отсвет снизу
	var sheen := Rect2(r.position + Vector2(rad * 0.6, 2), Vector2(maxf(r.size.x - rad * 1.2, 0.0), maxf(r.size.y * 0.22, 1.5)))
	ci.draw_rect(sheen, Color(1, 1, 1, 0.32))
	ci.draw_line(Vector2(r.position.x + rad, r.end.y - 1.5), Vector2(r.end.x - rad, r.end.y - 1.5), Color(1, 1, 1, 0.1), 1.0)
