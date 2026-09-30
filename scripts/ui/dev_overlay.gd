extends Node2D
## Отладочный слой поверх мира: хитбоксы и радиусы (змея, медведи, вилки, таблетки, матрёшки,
## яичница, снаряды), сетка с безопасной зоной экрана и (v9.0) роли отряда над врагами — подпись
## роли, линия к цели, круг хоровода с просветом.

const Snake = preload("res://scripts/entities/snake.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")
const OilDrop = preload("res://scripts/entities/oil_drop.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Platform = preload("res://scripts/core/platform.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")
const Squad = preload("res://scripts/game/squad.gd")
const Design = preload("res://scripts/ui/design.gd")

const HIT := Color(1, 0.2, 0.9, 0.9)
const SOFT := Color(0.3, 0.9, 1, 0.7)

var game
var hitboxes := false
var safe_grid := false
var roles := false


func _process(_delta: float) -> void:
	visible = hitboxes or safe_grid or roles
	if visible:
		queue_redraw()


func _draw() -> void:
	if hitboxes:
		_draw_hitboxes()
	if safe_grid:
		_draw_grid()
	if roles:
		_draw_roles()


## Роли отряда: подпись над врагом, линия к цели, хоровод — круг и просвет.
func _draw_roles() -> void:
	var sq = game.enemies.squad
	var font := Design.font("mono")
	for r: Dictionary in sq.roles.values():
		var n = r["node"]
		if not is_instance_valid(n):
			continue
		draw_string_outline(font, n.position + Vector2(-30, -34), r["role"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
		draw_string(font, n.position + Vector2(-30, -34), r["role"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Design.PLUM)
		var target = r["target"]
		if target != null and is_instance_valid(target):
			draw_dashed_line(n.position, target.position, Color(Design.PLUM, 0.7), 2.0, 8.0)
	for f in sq.pincer:
		if is_instance_valid(f):
			draw_string(font, f.position + Vector2(-24, -40), "клещи", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Design.TOMATO)
	if not sq.khorovod.is_empty():
		var gap_w := Squad.KHOROVOD_GAP
		draw_arc(sq.kh_center, Squad.KHOROVOD_RADIUS, sq.kh_gap + gap_w / 2.0, sq.kh_gap + TAU - gap_w / 2.0, 64,
			Color(Design.PLUM, 0.6), 2.0)
		draw_line(sq.kh_center, sq.kh_center + Vector2.from_angle(sq.kh_gap) * Squad.KHOROVOD_RADIUS, Design.safe(), 2.0)
		draw_string(font, sq.kh_center + Vector2(-40, 4), "хоровод %.1f" % sq.kh_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Design.PLUM)


func _draw_hitboxes() -> void:
	var s: Snake = game.snake
	if s:
		draw_arc(s.head_pos, Snake.HEAD_RADIUS, 0, TAU, 24, HIT, 2.0)
		draw_line(s.head_pos, s.head_pos + Vector2.from_angle(s.heading) * 40.0, HIT, 2.0)
		var segs := s.get_segments()
		for i in range(Snake.SELF_HIT_SKIP, segs.size()):
			draw_arc(segs[i], Snake.BODY_RADIUS * 1.2, 0, TAU, 10, Color(HIT, 0.35), 1.0)
		if s.spin_t > 0.0:
			draw_arc(s.head_pos, Balance.SPIN_RADIUS, 0, TAU, 40, SOFT, 2.0)
	for b in game.enemies.bears:
		draw_arc(b.position, TeddyBear.RADIUS, 0, TAU, 20, HIT if b.is_edible() else SOFT, 2.0)
	for f in game.enemies.forks:
		var dir: Vector2 = f.facing()
		var side := dir.orthogonal()
		var tip: Vector2 = f.position + dir * f.TIP * f.SIZE
		var from: Vector2 = f.position + dir * f.TINES_FROM * f.SIZE
		draw_line(f.position + dir * f.TAIL * f.SIZE, tip, HIT, 2.0)
		draw_polyline(PackedVector2Array([from + side * 20.0, tip, from - side * 20.0]), Color(1, 0.3, 0.2), 3.0)
	for p in game.enemies.pills:
		draw_arc(p.position, Pill.RADIUS, 0, TAU, 20, HIT if p.is_edible() else SOFT, 2.0)
		draw_arc(p.position, Pill.CRUSH_RADIUS, 0, TAU, 20, Color(1, 0.6, 0.2, 0.5), 1.0)
	for m in game.enemies.dolls:
		draw_arc(m.position, m.radius(), 0, TAU, 20, HIT if m.can_bite() else SOFT, 2.0)
		if m.st in [Matryoshka.St.CROUCH, Matryoshka.St.SPIN] and m.spin_path.size() > 1:
			draw_polyline(m.spin_path, Color(1, 0.6, 0.2, 0.7), 1.5)  # путь юлы
	for d in game.shots.drops:
		draw_arc(d.position, OilDrop.RADIUS, 0, TAU, 12, Color(1, 1, 0.3, 0.9), 1.5)
	var boss: FriedEggBoss = game.boss
	if boss:
		draw_arc(boss.position, FriedEggBoss.WHITE_RADIUS, 0, TAU, 48, SOFT, 2.0)
		draw_arc(boss.position + FriedEggBoss.YOLK_OFFSET, FriedEggBoss.YOLK_RADIUS, 0, TAU, 32, HIT, 2.0)
	draw_rect(game.bounds, Color(0.3, 1, 0.3, 0.6), false, 2.0)


func _draw_grid() -> void:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var vis := get_viewport().get_visible_rect().size
	var tl := inv * Vector2.ZERO
	var br := inv * vis
	for x in range(int(tl.x / 80.0) * 80, int(br.x), 80):
		draw_line(Vector2(x, tl.y), Vector2(x, br.y), Color(1, 1, 1, 0.08), 1.0)
	for y in range(int(tl.y / 80.0) * 80, int(br.y), 80):
		draw_line(Vector2(tl.x, y), Vector2(br.x, y), Color(1, 1, 1, 0.08), 1.0)
	var m := Platform.safe_margins(get_viewport())
	var safe := Rect2(inv * Vector2(m.x, m.y), (vis - Vector2(m.x + m.z, m.y + m.w)) * inv.get_scale())
	draw_rect(safe, Color(0.3, 1, 0.5, 0.8), false, 3.0)
	draw_rect(Rect2(tl, br - tl), Color(1, 0.8, 0.2, 0.8), false, 2.0)
