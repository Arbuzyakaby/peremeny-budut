extends Control
## Портрет для картотеки (v12.4): не значок HUD, а настоящий враг — тот же узел, что бегает по полю
## (медведь нужного вида, вилка, таблетка, матрёшка, яичница), в позе покоя и в масштабе клетки.
## Приёмы вилок и досье учёного рисуются значками. Неизвестный — чёрный силуэт с «?».
## live — портрет на листе дела: чуть дышит (покачивается); в сетке карточек — неподвижен.

const Design = preload("res://scripts/ui/design.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")

## Сколько места занимает враг в своих координатах (по большей стороне) — для масштаба.
const EXTENT := {"bear": 48.0, "fork": 120.0, "pill": 52.0, "doll": 56.0, "egg": 330.0}
const FAR := Rect2(-5000, -5000, 10000, 10000)  # «поле» портрета: враг никуда не упрётся

var entry: Dictionary = {}
var known := false
var live := false
var holder: Node2D   # сюда кладётся враг
var overlay: Control # поверх врага: значок или «?»
var actor: Node2D    # сам враг (null — значок)
var t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder = Node2D.new()
	add_child(holder)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	resized.connect(_place)


func show_entry(e: Dictionary, is_known: bool) -> void:
	if e == entry and is_known == known and (actor != null or not _has_actor(e)):
		return
	entry = e
	known = is_known
	if actor:
		actor.queue_free()
		actor = null
	if is_inside_tree():
		_build()
	overlay.queue_redraw()


func _ready() -> void:
	if not entry.is_empty() and actor == null:
		_build()
	set_process(live)


static func _has_actor(e: Dictionary) -> bool:
	return String(e.get("icon", "")) in ["bear", "fork", "pill", "doll", "egg"]


func _build() -> void:
	var icon := String(entry.get("icon", ""))
	var arg := int(entry.get("arg", 0))
	match icon:
		"bear":
			var b := TeddyBear.new()
			holder.add_child(b)
			b.setup(Vector2.ZERO, 0.0, FAR, arg, 1.0)
			b.vel = Vector2.ZERO
			b.rotation = 0.0
			actor = b
		"fork":
			var f := Fork.new()
			holder.add_child(f)
			f.setup(Vector2.ZERO, FAR, 0.0, 1.0, 1.0, arg)
			f.rotation = -PI / 2.0 - 0.5  # наискось, зубцами вверх
			actor = f
		"pill":
			var p := Pill.new()
			holder.add_child(p)
			p.setup(Vector2.ZERO, FAR, 1.0, 1.0, arg)
			p.spawn_k = 1.0
			p.angle = -0.3
			actor = p
		"doll":
			var m := Matryoshka.new()
			holder.add_child(m)
			m.setup(Vector2.ZERO, FAR, arg, 1.0, 1.0)
			m.spawn_k = 1.0
			m.paint = 0
			m.rock = 0.0
			actor = m
		"egg":
			var egg := FriedEggBoss.new()
			holder.add_child(egg)
			egg.configure(10, 1.0, 1.0, 1.0)
			actor = egg
	if actor:
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.z_index = 0
		actor.z_as_relative = true
	holder.modulate = Color.WHITE if known else Color(0.05, 0.03, 0.02, 0.55)
	_place()
	if actor:  # враги «вырастают» твином появления, а перерисовываются только из update(): дорисовать
		get_tree().create_timer(0.45, true).timeout.connect(func() -> void:
			if is_instance_valid(actor):
				actor.queue_redraw())


## Враг по центру клетки, масштаб — чтобы влез с полями.
func _place() -> void:
	if holder == null:
		return
	var icon := String(entry.get("icon", ""))
	var ext: float = EXTENT.get(icon, 40.0)
	var k := minf(size.x, size.y) * 0.8 / ext
	holder.position = size / 2.0 + Vector2(0, size.y * 0.06)
	holder.scale = Vector2.ONE * k


func _process(delta: float) -> void:
	t += delta
	if holder:
		holder.rotation = sin(t * 1.7) * 0.04
		holder.position.y = size.y / 2.0 + size.y * 0.06 + sin(t * 2.3) * size.y * 0.012


func _draw_overlay() -> void:
	var c := size / 2.0
	var s := minf(size.x, size.y) / 40.0
	var o := overlay
	if actor == null and not entry.is_empty():  # значок: приём вилки, досье
		if known:
			match String(entry["icon"]):
				"fork_atk":
					Icons.fork_attack(o, c, int(entry["arg"]), Design.warn(), s)
				"scientist":
					Icons.scientist(o, c, s * 0.8)
		else:
			o.draw_circle(c, 14.0 * s, Color(0, 0, 0, 0.35))
	if not known:
		var f := Design.font("heavy")
		var fs := int(22 * s)
		var w := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		o.draw_string(f, c + Vector2(-w / 2.0, fs * 0.35), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Design.FAINT, 0.95))
