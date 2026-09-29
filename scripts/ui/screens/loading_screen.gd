extends Control
## Экран загрузки при первом запуске: пока в фоне синтезируются звуки (на телефоне это заметно).
## Внизу — случайный совет (core/tips.gd), меняется каждые 4 секунды.

const Design = preload("res://scripts/ui/design.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Tips = preload("res://scripts/core/tips.gd")

var progress := 0.0
var shown := 0.0
var t := 0.0
var status := "Синтезируем звуки"
var tip := Tips.random_tip()
var tip_t := 4.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	t += delta
	tip_t -= delta
	if tip_t <= 0.0:
		tip_t = 4.0
		tip = Tips.random_tip()
	shown = move_toward(shown, progress, delta * 2.5)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Design.SURFACE_0)
	var c := size / 2.0
	var font := Design.font("heavy")
	var title := "ЗМЕЯ"
	var fs := 84
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(font, c + Vector2(-w / 2.0, -20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color(0.05, 0.2, 0.05))
	draw_string(font, c + Vector2(-w / 2.0, -20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.45, 0.9, 0.4))
	var bar := Rect2(c + Vector2(-180, 24), Vector2(360, 10))
	Design.draw_bar(self, bar, shown, Design.YOLK)
	var dots := ".".repeat(int(t * 3.0) % 4)
	var body := Design.font("body")
	var tw := body.get_string_size(status + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(body, c + Vector2(-tw / 2.0, 66), status + dots, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Design.MUTED)
	for i in 4:  # четыре иконки врагов «подпрыгивают» по очереди
		var k := maxf(sin(t * 5.0 - i * 0.9), 0.0)
		Icons.stage(self, c + Vector2(-60 + i * 40, 110 - k * 8.0), i, 0.9)
	var line := "СОВЕТ: " + tip
	var lw := minf(body.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, size.x - 48.0)
	draw_string(body, Vector2((size.x - lw) / 2.0, size.y - 40.0), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 48.0, 16,
		Color(Design.CREAM, 0.8))
