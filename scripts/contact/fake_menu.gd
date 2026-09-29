extends Node
## Фальшивое главное меню (v10.0): после пересадки образца №48 игрока выбрасывает в меню — но вместо
## карточек сложностей одна кнопка «НОВАЯ ИГРА», и курсор сам едет к ней и нажимает. Ввод игрока
## перехвачен. После щелчка — помехи и надпись «ТЕХНИЧЕСКИЙ РЕЖИМ «КОНТАКТ»», затем done.

signal done

const Balance = preload("res://scripts/core/balance.gd")
const SaveData = preload("res://scripts/core/save_data.gd")
const Design = preload("res://scripts/ui/design.gd")
const Settings = preload("res://scripts/core/settings.gd")

const TITLE := "ТЕХНИЧЕСКИЙ РЕЖИМ «КОНТАКТ»"

var g
var layer: CanvasLayer
var blocker: Control
var cursor := Vector2.ZERO
var pressed := 0.0
var noise := 0.0
var typed := 0.0
var t := 0.0
var tw: Tween
var finished := false


func start(game) -> void:
	g = game
	g.hud.show_menu(Balance.DIFFICULTIES, SaveData.bests(Balance.DIFFICULTIES.size()), g.difficulty)
	var menu = g.hud.menu
	menu.glitch_single("НОВАЯ ИГРА")
	menu.set_process_input(false)  # коды меню не набираются: ввод не наш
	layer = CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	blocker = Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.focus_mode = Control.FOCUS_ALL
	blocker.draw.connect(_draw_overlay)
	layer.add_child(blocker)
	blocker.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN  # курсором управляет не игрок
	var vp: Vector2 = blocker.get_viewport_rect().size
	cursor = vp * Vector2(0.86, 0.92)
	tw = create_tween()
	tw.tween_interval(1.5)
	tw.tween_method(_move_cursor.bind(cursor), 0.0, 1.0, 1.7)
	tw.tween_callback(func() -> void:
		var b: Button = g.hud.menu.glitch_button
		if is_instance_valid(b):
			b.grab_focus()
		g.sfx.play("ui_move"))
	tw.tween_interval(0.6)
	tw.tween_callback(_click)
	tw.tween_property(self, "pressed", 0.0, 0.18)
	tw.tween_interval(0.35)
	tw.tween_callback(func() -> void:
		noise = 1.0
		g.sfx.play("phase", 1.3, -6.0)
		g.sfx.play_music(""))
	tw.tween_property(self, "typed", 1.0, 1.4)
	tw.tween_interval(1.2)
	tw.tween_callback(_done)


func _target() -> Vector2:
	var b: Button = g.hud.menu.glitch_button
	if is_instance_valid(b) and b.is_visible_in_tree():
		return b.get_global_rect().get_center() + Vector2(24, 10)
	return blocker.get_viewport_rect().size / 2.0


## Курсор едет к кнопке не по линейке — чуть дугой, с доводкой, как рука человека.
func _move_cursor(k: float, from: Vector2) -> void:
	var to := _target()
	var e := k * k * (3.0 - 2.0 * k)
	var bend := Vector2(-80.0, -60.0) * sin(k * PI)
	cursor = from.lerp(to, e) + bend


func _click() -> void:
	pressed = 1.0
	g.sfx.play("ui_select")
	var b: Button = g.hud.menu.glitch_button
	if is_instance_valid(b):
		var tw2 := b.create_tween()
		tw2.tween_property(b, "scale", Vector2(0.96, 0.96), 0.06)
		tw2.tween_property(b, "scale", Vector2.ONE, 0.12)


func _done() -> void:
	if finished:
		return
	finished = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	done.emit()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	t += delta
	noise = maxf(noise - delta * 0.35, 0.0) if typed >= 1.0 else noise
	if blocker:
		blocker.queue_redraw()


func _draw_overlay() -> void:
	var size := blocker.size
	if noise > 0.0:  # помехи: полосы и сдвиги
		blocker.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.55 * noise))
		if not Settings.flag("reduced_motion"):
			var rng := RandomNumberGenerator.new()
			rng.seed = int(t * 20.0)
			for i in 14:
				var y := rng.randf() * size.y
				var h := rng.randf_range(2.0, 18.0)
				blocker.draw_rect(Rect2(rng.randf_range(-80, 40), y, size.x + 120.0, h),
					Color(rng.randf_range(0.4, 1.0), 1.0, rng.randf_range(0.5, 1.0), 0.12 * noise))
		var n := int(TITLE.length() * typed)
		var text := TITLE.substr(0, n) + ("_" if int(t * 3.0) % 2 == 0 else "")
		var f := Design.font("mono")
		var w := f.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var at := Vector2((size.x - w) / 2.0, size.y / 2.0)
		blocker.draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.6, 1, 0.6, minf(noise * 2.0, 1.0)))
		if typed >= 1.0:
			blocker.draw_string(f, at + Vector2(0, 36), "образец №48  •  протокол не предусмотрен", HORIZONTAL_ALIGNMENT_LEFT,
				-1, 16, Color(0.6, 1, 0.6, 0.6 * noise))
	# курсор-стрелка
	var c := cursor + Vector2(0, pressed * 2.0)
	var s := 1.0 - 0.12 * pressed
	var arrow := PackedVector2Array([Vector2(0, 0), Vector2(0, 26), Vector2(7, 20), Vector2(12, 31), Vector2(17, 29),
		Vector2(12, 18), Vector2(20, 18)])
	for i in arrow.size():
		arrow[i] = c + arrow[i] * s
	var shadow := arrow.duplicate()
	for i in shadow.size():
		shadow[i] += Vector2(2, 3)
	blocker.draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	blocker.draw_colored_polygon(arrow, Color.WHITE)
	arrow.append(arrow[0])
	blocker.draw_polyline(arrow, Color.BLACK, 1.5)
