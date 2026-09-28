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
var floor_decor: Node2D         # рисунок поверх пола (детская у медведей) — запекается вместе с полом
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
	floor_decor = Node2D.new()
	floor_decor.draw.connect(_draw_decor)
	floor_view.add_child(floor_decor)
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
	floor_decor.queue_redraw()
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
	floor_decor.scale = Vector2.ONE * bake_scale
	floor_decor.queue_redraw()
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


## Детская под этапом медведей: вязаный коврик, кубики с буквами, заплатки со швом, клубок,
## пуговицы и солнечные пятна от окна. Рисунок плоский и приглушённый — это пол, а не препятствия.
## Раскладка постоянная (свой сид), чтобы арена узнавалась.
func _draw_decor() -> void:
	if floor_kind != Tex.Floor.WOOD:
		return
	var d := floor_decor
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var font := ThemeDB.fallback_font
	for k in 3:  # солнечные пятна от окна — наискось через пол
		var p := Vector2(260 + k * 330, 120 + k * 150)
		d.draw_colored_polygon(PackedVector2Array([p, p + Vector2(170, -30), p + Vector2(240, 150), p + Vector2(70, 180)]),
			Color(1, 0.9, 0.6, 0.05))
	var c := Vector2(640, 380)  # вязаный коврик: кольца петель разных цветов
	var rug := [Color(0.72, 0.36, 0.3), Color(0.9, 0.78, 0.55), Color(0.4, 0.55, 0.62), Color(0.85, 0.6, 0.35),
		Color(0.55, 0.38, 0.5), Color(0.9, 0.78, 0.55)]
	d.draw_set_transform(c, 0.0, Vector2(1.0, 0.62))
	d.draw_circle(Vector2(4, 8), 262.0, Color(0, 0, 0, 0.12))
	for i in rug.size():
		var r := 250.0 - i * 40.0
		d.draw_circle(Vector2.ZERO, r, Color(rug[i], 0.3))
		for s in int(r / 6.0):  # петли вязки по кругу
			var a := TAU * s / int(r / 6.0)
			d.draw_line(Vector2.from_angle(a) * (r - 14.0), Vector2.from_angle(a + 0.04) * (r - 3.0),
				Color(rug[i].darkened(0.3), 0.22), 2.0)
	d.draw_set_transform(Vector2.ZERO)
	for p: Vector2 in [Vector2(150, 150), Vector2(1130, 590), Vector2(1080, 140)]:  # заплатки с пунктирным швом
		var sz := Vector2(rng.randf_range(90, 130), rng.randf_range(70, 100))
		var rect := Rect2(p - sz / 2.0, sz)
		var col: Color = [Color(0.6, 0.45, 0.3), Color(0.45, 0.5, 0.35), Color(0.62, 0.4, 0.42)][rng.randi() % 3]
		d.draw_rect(rect, Color(col, 0.28))
		for k in 5:  # клетка ткани
			d.draw_line(rect.position + Vector2(sz.x * (k + 0.5) / 5.0, 0), rect.position + Vector2(sz.x * (k + 0.5) / 5.0, sz.y),
				Color(col.darkened(0.3), 0.18), 3.0)
		var seam := rect.grow(-6)
		var corners := [seam.position, Vector2(seam.end.x, seam.position.y), seam.end, Vector2(seam.position.x, seam.end.y)]
		for k in 4:
			d.draw_dashed_line(corners[k], corners[(k + 1) % 4], Color(0.95, 0.9, 0.8, 0.35), 2.0, 7.0)
	var letters := "АБВГДЕЖЗ"
	for i in 6:  # кубики с буквами: вид сверху, повёрнуты как попало
		var p: Vector2 = [Vector2(110, 560), Vector2(175, 610), Vector2(1170, 300), Vector2(470, 90), Vector2(820, 640),
			Vector2(1200, 420)][i]
		var rot := rng.randf_range(-0.6, 0.6)
		var col: Color = [Color(0.85, 0.3, 0.25), Color(0.3, 0.55, 0.85), Color(0.95, 0.75, 0.25), Color(0.4, 0.7, 0.4)][i % 4]
		d.draw_set_transform(p, rot)
		d.draw_rect(Rect2(-19, -15, 42, 42), Color(0, 0, 0, 0.18))
		d.draw_rect(Rect2(-21, -21, 42, 42), Color(col, 0.55))
		d.draw_rect(Rect2(-16, -16, 32, 32), Color(0.97, 0.93, 0.85, 0.5))
		d.draw_string(font, Vector2(-10, 10), letters[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(col.darkened(0.3), 0.8))
		d.draw_set_transform(Vector2.ZERO)
	var ball := Vector2(1010, 560)  # клубок и нитка, убежавшая по полу
	var thread := PackedVector2Array()
	for i in 40:
		thread.append(ball + Vector2(-i * 9.0, sin(i * 0.35) * 26.0 + i * 1.5))
	d.draw_polyline(thread, Color(0.75, 0.3, 0.35, 0.4), 2.5, true)
	d.draw_circle(ball + Vector2(3, 5), 24.0, Color(0, 0, 0, 0.2))
	d.draw_circle(ball, 23.0, Color(0.78, 0.32, 0.36, 0.7))
	for k in 5:
		d.draw_arc(ball, 20.0 - k * 3.0, k * 0.7, k * 0.7 + 2.4, 12, Color(0.95, 0.6, 0.6, 0.45), 1.5)
	for i in 7:  # оторванные пуговицы
		var p := Vector2(rng.randf_range(80, 1200), rng.randf_range(80, 640))
		if p.distance_to(c) < 200.0:
			continue
		var col := Color.from_hsv(rng.randf(), 0.5, 0.8, 0.55)
		d.draw_circle(p, 9.0, col)
		d.draw_arc(p, 6.5, 0, TAU, 14, Color(col.darkened(0.35), 0.8), 1.2)
		for h in 4:
			d.draw_circle(p + Vector2.from_angle(h * PI / 2 + 0.78) * 3.0, 1.2, Color(0, 0, 0, 0.45))
