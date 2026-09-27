extends Node2D
## Прыгающая таблетка-капсула. Стоит на месте, приседает и прыгает на змею по дуге.
## В воздухе неуязвима (видна метка приземления), при приземлении давит всех под собой
## и поднимает ударную волну, оглушающую змею. На земле её можно съесть.

signal landed(pos: Vector2)
signal sound(sound_name: String)

const Tex = preload("res://scripts/gfx/tex.gd")
const Design = preload("res://scripts/ui/design.gd")

enum St { IDLE, CROUCH, JUMP }

const RADIUS := 26.0
const JUMP_HEIGHT := 190.0
const CRUSH_RADIUS := 40.0
const COLORS := [
	[Color(0.92, 0.2, 0.22), Color(0.97, 0.95, 0.9)],
	[Color(0.25, 0.45, 0.92), Color(0.98, 0.85, 0.25)],
	[Color(0.3, 0.75, 0.4), Color(0.97, 0.95, 0.9)],
	[Color(0.75, 0.35, 0.85), Color(0.95, 0.7, 0.8)],
]

var st := St.IDLE
var st_t := 1.0
var bounds := Rect2(0, 0, 1280, 720)
var tempo := 1.0
var aggr := 1.0
var height := 0.0
var jump_from := Vector2.ZERO
var jump_to := Vector2.ZERO
var air_time := 0.85
var angle := 0.0
var cols: Array = COLORS[0]
var t := 0.0
var squash := 0.0
var spawn_k := 0.0
var aim_offset := Vector2.ZERO  # кооператив (squad.gd): прыгнуть так, чтобы загнать змею к вилкам


func setup(pos: Vector2, area: Rect2, idle_tempo: float, aggression: float) -> void:
	position = pos
	bounds = area
	tempo = idle_tempo
	aggr = aggression
	angle = randf_range(-0.6, 0.6)
	cols = COLORS.pick_random()
	st_t = randf_range(0.6, 1.4) * tempo
	material = Tex.material(Tex.Mat.PLASTIC, randf() * 10.0)
	create_tween().tween_property(self, "spawn_k", 1.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## На земле — можно съесть.
func is_edible() -> bool:
	return st != St.JUMP and spawn_k > 0.9


func in_air() -> bool:
	return st == St.JUMP


func update(delta: float, head: Vector2, head_vel: Vector2, snake_alive: bool) -> void:
	t += delta
	st_t -= delta
	squash = maxf(squash - delta * 3.0, 0.0)
	match st:
		St.IDLE:
			if st_t <= 0.0 and snake_alive:
				st = St.CROUCH
				st_t = 0.35 * clampf(tempo, 0.6, 1.3)
		St.CROUCH:
			if st_t <= 0.0:
				st = St.JUMP
				air_time = 0.85 * clampf(tempo, 0.7, 1.2)
				st_t = air_time
				jump_from = position
				var lead := head + head_vel * air_time * clampf(0.35 * aggr, 0.2, 0.8) + aim_offset
				var inner := bounds.grow(-RADIUS - 10.0)
				var hop := lead - position
				if hop.length() > 420.0:  # за один прыжок не дальше 420
					hop = hop.normalized() * 420.0
				jump_to = (position + hop).clamp(inner.position, inner.end)
				sound.emit("pill_hop")
		St.JUMP:
			var k := clampf(1.0 - st_t / air_time, 0.0, 1.0)
			position = jump_from.lerp(jump_to, k)
			height = sin(k * PI) * JUMP_HEIGHT
			angle += delta * 7.0
			if st_t <= 0.0:
				height = 0.0
				position = jump_to
				st = St.IDLE
				st_t = randf_range(0.8, 1.2) * tempo
				squash = 1.0
				landed.emit(position)
				sound.emit("pill_land")
	queue_redraw()


func _draw() -> void:
	var s := spawn_k
	if st == St.JUMP:  # метка приземления
		var target := jump_to - position
		var k := 1.0 - st_t / air_time
		var pulse := 0.5 + 0.5 * sin(t * 20.0)
		Tex.blob(self, target, Vector2.ONE * CRUSH_RADIUS * 1.2, Color(0.3, 0.5, 1.0, 0.18 + 0.2 * k))
		var mark := Design.warn() if Design.Settings.flag("high_contrast") else Color(0.35, 0.6, 1.0)
		draw_arc(target, CRUSH_RADIUS, 0, TAU, 32, Color(mark, 0.5 + 0.4 * pulse), Design.telegraph_width(3.0))
		draw_arc(target, CRUSH_RADIUS * (1.0 - k * 0.7), 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
	var shadow_k := 1.0 - height / (JUMP_HEIGHT * 1.5)
	Tex.blob(self, Vector2(3, 8), Vector2(30, 16) * shadow_k * s, Color(0, 0, 0, 0.28 * shadow_k))

	var sc := Vector2.ONE * s * 1.25
	match st:
		St.CROUCH:
			var k := 1.0 - st_t / 0.35
			sc *= Vector2(1.0 + 0.25 * k, 1.0 - 0.3 * k)
			sc += Vector2(randf_range(-0.03, 0.03), 0)
		St.JUMP:
			sc *= Vector2(0.88, 1.15)
	if squash > 0.0:
		sc *= Vector2(1.0 + 0.35 * squash, 1.0 - 0.3 * squash)
	var a := angle if st == St.JUMP else angle + sin(t * 3.0) * 0.05
	draw_set_transform(Vector2(0, -height - 4.0), a, sc)
	var half := 22.0
	var r := 11.0
	var outline := Color(0.15, 0.1, 0.12)
	draw_circle(Vector2(-half + r, 0), r + 1.8, outline)
	draw_circle(Vector2(half - r, 0), r + 1.8, outline)
	draw_rect(Rect2(-half + r, -r - 1.8, (half - r) * 2.0, (r + 1.8) * 2.0), outline)
	# две половинки капсулы
	draw_circle(Vector2(-half + r, 0), r, cols[0])
	draw_rect(Rect2(-half + r, -r, half - r, r * 2.0), cols[0])
	draw_circle(Vector2(half - r, 0), r, cols[1])
	draw_rect(Rect2(0, -r, half - r, r * 2.0), cols[1])
	draw_line(Vector2(0, -r), Vector2(0, r), outline.lerp(Color.WHITE, 0.4), 1.5)  # шов
	# объём: тень снизу, блик сверху
	draw_rect(Rect2(-half + r, r * 0.35, (half - r) * 2.0, r * 0.65), Color(0, 0, 0, 0.12))
	draw_line(Vector2(-half + r - 2, -r * 0.55), Vector2(half - r + 2, -r * 0.55), Color(1, 1, 1, 0.6), 3.0)
	draw_circle(Vector2(-half + r - 3, -r * 0.35), 2.2, Color(1, 1, 1, 0.8))
	# тиснение «мг»
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(3, 4), "мг", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, cols[1].darkened(0.3))
	# лицо: злые глазки, в прыжке — оскал
	var face := Vector2(-half + r, -1)
	for side in [-1.0, 1.0]:
		var e: Vector2 = face + Vector2(side * 3.5, -1)
		draw_circle(e, 2.2, Color.WHITE)
		draw_circle(e + Vector2(0.4, 0.5), 1.2, Color.BLACK)
		draw_line(e + Vector2(-side * 2.8, -3.8), e + Vector2(side * 1.8, -2.6), outline, 1.3)
	if st == St.JUMP or st == St.CROUCH:
		draw_rect(Rect2(face + Vector2(-3, 3), Vector2(6, 2.5)), outline)
	else:
		draw_line(face + Vector2(-2.5, 4), face + Vector2(2.5, 4), outline, 1.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
