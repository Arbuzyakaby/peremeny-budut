extends Node2D
## Арена-ящик: стол вокруг (виден на широких экранах телефонов), процедурный пол этапа и
## деревянный бортик с фаской, внутренней тенью и гвоздями.
## Пол статичен, а его шейдер тяжёлый (шум fbm на каждом пикселе), поэтому он рисуется один раз
## во внеэкранный SubViewport, а на экран идёт готовая текстура. Перерисовка — только при смене этапа
## и при заметном росте окна (чтобы пол оставался чётким на 1440p/4K).

const Balance = preload("res://scripts/core/balance.gd")
const Tex = preload("res://scripts/gfx/tex.gd")

const TABLE := Color(0.16, 0.095, 0.055)
const MAX_BAKE_SCALE := 2.0  # 2560×1440 — выше смысла нет, а видеопамяти жалко

var floor_rect: TextureRect     # готовый пол на экране
var floor_view: SubViewport     # здесь пол рисуется шейдером — один раз
var floor_src: ColorRect        # полотно с шейдером пола внутри floor_view
var floor_kind := -1
var bake_scale := 0.0
var frame: Node2D
var bounds := Balance.ARENA.grow(-Balance.WALL)


func _ready() -> void:
	var table := ColorRect.new()  # стол под ящиком — заполняет поля на экранах шире 16:9
	table.position = Vector2(-1600, -1200)
	table.size = Balance.ARENA.size + Vector2(3200, 2400)
	table.color = TABLE
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.z_index = -20
	add_child(table)
	var shadow := Node2D.new()  # мягкая тень ящика на столе
	shadow.z_index = -19
	shadow.draw.connect(func() -> void:
		for k in 8:
			shadow.draw_rect(Balance.ARENA.grow(4.0 + k * 5.0), Color(0, 0, 0, 0.1 - k * 0.012), false, 5.0))
	add_child(shadow)
	floor_view = SubViewport.new()
	floor_view.disable_3d = true
	floor_view.transparent_bg = false
	floor_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(floor_view)
	floor_src = ColorRect.new()
	floor_src.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_view.add_child(floor_src)
	floor_rect = TextureRect.new()
	floor_rect.size = Balance.ARENA.size
	floor_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	floor_rect.stretch_mode = TextureRect.STRETCH_SCALE
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_rect.texture = floor_view.get_texture()
	add_child(floor_rect)
	set_floor(Tex.Floor.WOOD)
	get_viewport().size_changed.connect(_rebake_if_sharper)
	frame = Node2D.new()
	frame.draw.connect(_draw_frame)
	add_child(frame)


func set_floor(kind: int) -> void:
	if kind == floor_kind and bake_scale > 0.0:
		return
	floor_kind = kind
	floor_src.material = Tex.floor_material(kind)
	_bake()


## Во сколько раз экран крупнее арены 1280×720 (режим растяжения canvas_items): в таком масштабе и печём.
func wanted_scale() -> float:
	var win := get_tree().root.size if is_inside_tree() else Vector2i(1280, 720)
	var k := minf(win.x / Balance.ARENA.size.x, win.y / Balance.ARENA.size.y)
	return clampf(ceilf(k * 4.0) / 4.0, 1.0, MAX_BAKE_SCALE)  # шагами по 0,25 — не перепекать на каждый пиксель


func _bake() -> void:
	bake_scale = wanted_scale()
	var px := Vector2i((Balance.ARENA.size * bake_scale).round())
	floor_view.size = px
	floor_src.size = Vector2(px)
	floor_view.render_target_update_mode = SubViewport.UPDATE_ONCE


## Окно выросло (развернули на весь экран) — перепечь пол крупнее; уменьшение не трогаем.
func _rebake_if_sharper() -> void:
	if wanted_scale() > bake_scale:
		_bake()


## Деревянный бортик ящика: волокна, фаска, внутренняя тень, гвозди.
func _draw_frame() -> void:
	var arena := Balance.ARENA
	var wall := Balance.WALL
	for k in 7:  # тень бортика на полу
		frame.draw_rect(bounds.grow(-k * 3.0 - 1.5), Color(0, 0, 0, 0.07 - k * 0.009), false, 3.0)
	var wood := Color(0.52, 0.32, 0.16)
	frame.draw_rect(arena.grow(-wall / 2), wood, false, wall)
	for i in 5:  # волокна вдоль досок
		var off := 3.0 + i * 4.5
		var col := wood.darkened(0.12 + 0.06 * (i % 2)) if i % 2 == 0 else wood.lightened(0.06)
		frame.draw_rect(arena.grow(-off), col, false, 1.2)
	frame.draw_rect(arena.grow(-1.5), Color(0.72, 0.5, 0.28), false, 3.0)  # светлая кромка снаружи
	frame.draw_rect(bounds.grow(1.5), Color(0.25, 0.14, 0.06), false, 3.0)  # тёмная кромка внутри
	for c in [Vector2(12, 12), Vector2(1268, 12), Vector2(12, 708), Vector2(1268, 708),
			Vector2(640, 12), Vector2(640, 708), Vector2(12, 360), Vector2(1268, 360)]:  # гвозди
		frame.draw_circle(c + Vector2(1, 1.5), 4.5, Color(0, 0, 0, 0.35))
		frame.draw_circle(c, 4.0, Color(0.5, 0.5, 0.52))
		frame.draw_circle(c + Vector2(-1.2, -1.2), 1.6, Color(0.9, 0.9, 0.92))
