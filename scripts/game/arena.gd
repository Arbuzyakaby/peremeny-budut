extends Node2D
## Арена-ящик: стол вокруг (виден на широких экранах телефонов), процедурный пол этапа и
## деревянный бортик с фаской, внутренней тенью и гвоздями.

const Balance = preload("res://scripts/core/balance.gd")
const Tex = preload("res://scripts/gfx/tex.gd")

const TABLE := Color(0.16, 0.095, 0.055)

var floor_rect: ColorRect
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
	floor_rect = ColorRect.new()
	floor_rect.size = Balance.ARENA.size
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_rect.material = Tex.floor_material(Tex.Floor.WOOD)
	add_child(floor_rect)
	frame = Node2D.new()
	frame.draw.connect(_draw_frame)
	add_child(frame)


func set_floor(kind: int) -> void:
	floor_rect.material = Tex.floor_material(kind)


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
