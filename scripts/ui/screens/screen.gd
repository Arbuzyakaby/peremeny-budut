extends Control
## Базовый экран интерфейса: затемнение, панель по центру и прокрутка, если панель не влезает
## (телефон, крупный масштаб интерфейса). Наследники строят содержимое в build() и задают first_focus.

signal closed

const Design = preload("res://scripts/ui/design.gd")
const Settings = preload("res://scripts/core/settings.gd")

var dim_background := true
var center: CenterContainer
var panel: PanelContainer
var scroll: ScrollContainer
var content: VBoxContainer
var gutter: MarginContainer  # отступ справа под полосу прокрутки
var first_focus: Control


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if dim_background else Control.MOUSE_FILTER_IGNORE
	resized.connect(fit)


## Каркас: панель по центру, внутри прокручиваемая колонка.
func make_frame(gap := Design.SPACE[3], panel_style: StyleBox = null) -> VBoxContainer:
	center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	if panel_style:
		panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	gutter = MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gutter)
	content = Design.vbox(gap)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(content)
	content.minimum_size_changed.connect(fit)
	return content


## Высота прокрутки: вся колонка, но не больше экрана.
func fit() -> void:
	if scroll == null or not is_inside_tree():
		return
	var st := panel.get_theme_stylebox("panel")
	var chrome := st.get_minimum_size().y if st else 0.0
	var avail := size.y - chrome - Design.SPACE[5] * 2.0
	var need := content.get_combined_minimum_size()
	var h := minf(need.y, maxf(avail, 160.0))
	var bar := 18 if need.y > h + 1.0 else 0
	gutter.add_theme_constant_override("margin_right", bar)
	scroll.custom_minimum_size = Vector2(need.x + bar, h)


func open() -> void:
	visible = true
	fit()
	fit.call_deferred()
	if panel:
		panel.pivot_offset = panel.size / 2.0
		if not Settings.flag("reduced_motion"):
			panel.modulate.a = 0.0
			panel.scale = Vector2(0.97, 0.97)
			var tw := create_tween().set_parallel()
			tw.tween_property(panel, "modulate:a", 1.0, Design.BASE)
			tw.tween_property(panel, "scale", Vector2.ONE, Design.SLOW).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	focus_first()


func focus_first() -> void:
	if first_focus and not Settings.touch_enabled():
		first_focus.grab_focus.call_deferred()


func close() -> void:
	visible = false


## Кнопка «Назад» / Esc. true — экран обработал нажатие сам.
func handle_back() -> bool:
	closed.emit()
	return true


func _draw() -> void:
	if dim_background:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Design.SURFACE_0, 0.62))


## Заголовок экрана по центру.
func title(text: String, role := "h1", color := Design.YOLK) -> Label:
	var l := Design.label(text, role, color, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(l)
	return l
