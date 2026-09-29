extends RefCounted
## Эффекты мира: всплывающие надписи и облачка частиц. Количество частиц зависит от настройки
## качества; всплывающие очки можно отключить.

const Design = preload("res://scripts/ui/design.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Tex = preload("res://scripts/gfx/tex.gd")

## Поле, в котором живут всплывающие надписи (арена 1280×720).
const POPUP_AREA := Rect2(0, 0, 1280, 720)

var world: Node2D
## Кривая размера и градиент частиц одинаковы у всех облачков: создаём один раз, а не на каждый взрыв.
static var _scale_curve: Curve
static var _ramp: Gradient


func _init(world_node: Node2D) -> void:
	world = world_node


static func clear_cache() -> void:
	_scale_curve = null
	_ramp = null


## Всплывающая надпись над точкой мира. score — это очки (их можно выключить в настройках).
func popup(pos: Vector2, text: String, color: Color, score := false) -> void:
	if score and not Settings.flag("score_popups"):
		return
	var label := Label.new()
	label.text = text
	var ls := Design.label_settings("hud", color)
	ls.font_size = 22
	ls.outline_size = 7
	label.label_settings = ls
	label.z_index = 5
	# надпись у бортика не должна уходить за край поля: центр сдвигается внутрь на полширины текста
	var w := ls.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ls.font_size).x + ls.outline_size * 2.0
	var half := maxf(200.0, w / 2.0 + 8.0)
	pos.x = clampf(pos.x, w / 2.0 + 12.0, POPUP_AREA.end.x - w / 2.0 - 12.0) if w + 24.0 < POPUP_AREA.size.x else POPUP_AREA.get_center().x
	pos.y = clampf(pos.y, POPUP_AREA.position.y + 60.0, POPUP_AREA.end.y)
	label.size = Vector2(half * 2.0, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos - Vector2(half, 30)
	label.pivot_offset = Vector2(half, 20)
	label.scale = Vector2(0.6, 0.6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "position:y", label.position.y - 50.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.5)
	tw.tween_callback(label.queue_free)


## Облачко частиц: мягкие круглые пылинки, уменьшаются и тают.
func burst(pos: Vector2, color: Color, amount: int, size := 1.0) -> void:
	var n := maxi(int(round(amount * Settings.particle_mult())), 2)
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 4
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = n
	p.lifetime = 0.75
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 280.0
	p.damping_min = 120.0
	p.damping_max = 260.0
	p.gravity = Vector2(0, 250)
	p.texture = Tex.soft()
	p.scale_amount_min = 0.09 * size
	p.scale_amount_max = 0.17 * size
	if _scale_curve == null:
		_scale_curve = Curve.new()
		_scale_curve.add_point(Vector2(0, 1))
		_scale_curve.add_point(Vector2(1, 0.2))
		_ramp = Gradient.new()
		_ramp.set_color(0, Color(1.3, 1.3, 1.3, 1))
		_ramp.set_color(1, Color(1, 1, 1, 0))
	p.scale_amount_curve = _scale_curve
	p.color_ramp = _ramp
	p.color = color
	p.finished.connect(p.queue_free)
	world.add_child(p)
	p.emitting = true
