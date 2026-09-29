extends Control
## Игровые панели поверх арены: слева — счёт, цель этапа и дорожка этапов; справа — жизни, щит,
## стамина и текущая атака; полоса HP яичницы (снизу, а на сенсорном экране — сверху, чтобы не
## мешать кнопкам). Плюс вспышка урона, виньетка, киношные полосы, таймер, FPS и бейдж DEV.
## Панели становятся полупрозрачными, когда под ними ползёт змея.
## Пожар финала: белая вспышка первого возгорания (flash) и паника (Design.panic) — полосы и табло
## подрагивают на 1–2 px, снизу идёт тёплый отблеск огня; с «меньше анимации» — только ровный отблеск.

const Design = preload("res://scripts/ui/design.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Tex = preload("res://scripts/gfx/tex.gd")

const PAD := 16.0

var in_game := false
var touch := false
var diff_name := ""
var diff_color := Design.YOLK
var score_target := 0
var score_shown := 0.0
var stage := 0
var goal_done := 0
var goal_total := 0
var lives := 3
var max_lives := 3
var heart_anim := 0.0
var shield := 0
var stamina := 1.0
var exhausted := false
var ability_type := -1
var ability_name := ""
var ability_charges := 0
var ability_flash := 0.0
## Названия фаз яичницы (как FriedEggBoss.PHASE_NAMES — без preload сущности в интерфейс).
const BOSS_PHASES := ["ШКВОРЧИТ", "ПОДГОРАЕТ", "ПРИГОРЕЛА"]
## Источник атаки по её типу (как Balance.ABILITIES[type]["source"]).
const ABILITY_SOURCE := {10: "fork", 11: "fork", 12: "fork", 13: "pill", 14: "doll"}
var boss_visible := false
var boss_hp := 0
var boss_max := 1
var boss_phase := 1
var boss_hp_shown := 0.0
var boss_hp_ghost := 0.0
var boss_flash := 0.0
var hurt_flash := 0.0
var white_flash := 0.0
var cine := 0.0
var play_time := 0.0
var dev_run := false
var snake_screen := Vector2(-999, -999)  # голова змеи в координатах экрана
var safe := Vector4.ZERO                 # отступы безопасной зоны
var t := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reset_run(name_text: String, color: Color, lives_max: int) -> void:
	in_game = true
	diff_name = name_text
	diff_color = color
	max_lives = lives_max
	lives = lives_max
	score_shown = 0.0
	score_target = 0
	ability_type = -1
	boss_visible = false
	dev_run = false


func set_lives(value: int) -> void:
	if value < lives:
		heart_anim = 1.0
		if Settings.flag("hurt_flash"):
			hurt_flash = 1.0
	lives = value


## Белая вспышка экрана (первое возгорание в финале). С «меньше анимации» или без вспышек урона —
## приглушённая: засветка, а не удар по глазам.
func flash(amount := 1.0) -> void:
	var calm := Settings.flag("reduced_motion") or not Settings.flag("hurt_flash")
	white_flash = maxf(white_flash, amount * (0.35 if calm else 0.85))


## Сдвиг «дрожи» от паники: 1–2 px, меняется ~20 раз в секунду; при «меньше анимации» — ноль.
func panic_jitter() -> Vector2:
	var p := Design.panic
	if p < 0.05 or Settings.flag("reduced_motion"):
		return Vector2.ZERO
	var k := floorf(t * 20.0)
	return Vector2(sin(k * 12.9898), sin(k * 78.233)).sign() * roundf(1.0 + p) * float(fmod(k, 3.0) < 2.0)


func set_ability(type: int, title_text: String, count: int) -> void:
	if type != ability_type or count > ability_charges:
		ability_flash = 1.0
	ability_type = type
	ability_name = title_text
	ability_charges = count


func set_boss(visible_bar: bool, hp: int, max_hp: int, phase: int) -> void:
	if visible_bar and not boss_visible:
		boss_hp_shown = 0.0
		boss_hp_ghost = 0.0
	elif hp < boss_hp:
		boss_flash = 1.0
	boss_visible = visible_bar
	boss_hp = hp
	boss_max = maxi(max_hp, 1)
	boss_phase = clampi(phase, 1, 3)


func _process(delta: float) -> void:
	t += delta
	heart_anim = maxf(heart_anim - delta * 2.0, 0.0)
	hurt_flash = maxf(hurt_flash - delta * 3.0, 0.0)
	white_flash = maxf(white_flash - delta * 2.2, 0.0)
	boss_flash = maxf(boss_flash - delta * 3.0, 0.0)
	ability_flash = maxf(ability_flash - delta * 2.0, 0.0)
	score_shown = move_toward(score_shown, score_target, maxf(delta * 600.0, absf(score_target - score_shown) * delta * 6.0))
	boss_hp_shown = move_toward(boss_hp_shown, boss_hp, delta * 8.0)
	boss_hp_ghost = move_toward(boss_hp_ghost, boss_hp_shown, delta * (1.5 if boss_hp_ghost > boss_hp_shown else 20.0))
	var covered := false
	if in_game:
		for r in panel_rects():
			if r.grow(30).has_point(snake_screen):
				covered = true
	modulate.a = move_toward(modulate.a, 0.35 if covered else 1.0, delta * 4.0)
	queue_redraw()


# ---------------------------------------------------------------- раскладка

func _left_rect() -> Rect2:
	return Rect2(PAD + safe.x, PAD + safe.y, 340, 150)


func _right_width() -> float:
	return maxi(max_lives, 3) * 40 + 36 + (40 if shield > 0 else 0)


func _right_rect() -> Rect2:
	var w := _right_width()
	return Rect2(size.x - PAD - safe.z - w, PAD + safe.y, w, 84)


func _ability_rect() -> Rect2:
	return Rect2(size.x - PAD - safe.z - 290, PAD + safe.y + 92, 290, 72)


## Место под кнопку паузы на сенсорном экране — слева от панели жизней.
func pause_slot() -> Rect2:
	var r := _right_rect()
	return Rect2(r.position.x - PAD - 56, r.position.y + 14, 56, 56)


func _boss_rect() -> Rect2:
	if touch:  # сверху, между панелями — внизу кнопки
		var left := _left_rect().end.x + PAD
		var right := pause_slot().position.x - PAD
		var w := clampf(right - left, 320.0, 720.0)
		return Rect2((left + right - w) / 2.0, PAD + safe.y, w, 70)
	var w2 := minf(780.0, size.x - 2 * (PAD + 24.0))
	return Rect2((size.x - w2) / 2.0, size.y - 86 - safe.w, w2, 70)


func panel_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = [_left_rect(), _right_rect()]
	if ability_type >= 0:
		rects.append(_ability_rect())
	if boss_visible:
		rects.append(_boss_rect())
	return rects


# ---------------------------------------------------------------- рисование

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if in_game and Settings.flag("vignette"):
		draw_texture_rect(Tex.vignette(), full, false, Color(1, 1, 1, 0.55))
	if hurt_flash > 0.0:
		draw_rect(full, Color(0.9, 0.05, 0.05, 0.2 * hurt_flash))
	var jit := panic_jitter()
	if cine > 0.0:  # киношные полосы (в панике подрагивают)
		draw_rect(Rect2(jit.x - 2, jit.y - 2, size.x + 4, 84 * cine + 2), Color.BLACK)
		draw_rect(Rect2(jit.x - 2, size.y - 84 * cine + jit.y, size.x + 4, 84 * cine + 2), Color.BLACK)
	if Design.panic > 0.01:
		_draw_fire_glow(full)
	if Settings.flag("show_fps"):
		var fps := "FPS %d" % Engine.get_frames_per_second()
		_text(Vector2(size.x / 2.0 - 30, 20 + safe.y), fps, "mono", 14, Design.MINT)
	if in_game:
		var panel := Design.cached("hud_plank", func() -> StyleBox:  # табло — доска на винтах
			return Design.plank(Color(0, 0, 0, 0), Design.RADIUS_LG - 6, Vector2(Design.SPACE[5], Design.SPACE[3])))
		draw_set_transform(jit)
		_draw_left(panel)
		_draw_right(panel)
		if ability_type >= 0:
			_draw_ability()
		if boss_visible:
			_draw_boss_bar()
		draw_set_transform(Vector2.ZERO)
	if white_flash > 0.0:
		draw_rect(full, Color(1, 0.98, 0.92, white_flash))


## Тёплый отблеск огня снизу экрана: сила — Design.panic, мерцает как пламя (ровный при «меньше анимации»).
func _draw_fire_glow(full: Rect2) -> void:
	var p := Design.panic
	var fl := 1.0
	if not Settings.flag("reduced_motion"):
		fl = 0.75 + 0.25 * sin(t * 13.0) * sin(t * 5.7 + 1.3)
	var bottom := full.size.y - 84.0 * cine  # отблеск встаёт над нижней полосой, полоса лишь чуть теплеет
	var h := full.size.y * (0.28 + 0.12 * p)
	var hot := Color(1.0, 0.42, 0.1, 0.34 * p * fl)
	var clear := Color(1.0, 0.55, 0.15, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0, bottom - h), Vector2(full.size.x, bottom - h),
		Vector2(full.size.x, bottom), Vector2(0, bottom)]), PackedColorArray([clear, clear, hot, hot]))
	if cine > 0.0:
		draw_rect(Rect2(0, bottom, full.size.x, full.size.y - bottom), Color(hot, hot.a * 0.25))


func _draw_left(panel: StyleBox) -> void:
	var r := _left_rect()
	draw_style_box(panel, r)
	var o := r.position
	_text(o + Vector2(20, 26), "СЧЁТ", "heavy", 13, Design.YOLK)
	_text(o + Vector2(18, 62), str(int(score_shown)), "heavy", 32, Design.CREAM, 6)
	var chip_w := Design.font("heavy").get_string_size(diff_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 20
	var chip := Rect2(o + Vector2(r.size.x - chip_w - 16, 12), Vector2(chip_w, 22))
	draw_style_box(Design.cached("hud_chip_" + diff_name, func() -> StyleBox: return Design.plate(diff_color, Vector2.ZERO)), chip)
	_text(chip.position + Vector2(10, 16), diff_name, "heavy", 12, diff_color.lightened(0.3))
	if dev_run:
		var dev := Rect2(chip.position - Vector2(52, 0), Vector2(44, 22))
		draw_style_box(Design.cached("hud_dev", func() -> StyleBox: return Design.plate(Design.PLUM, Vector2.ZERO)), dev)
		_text(dev.position + Vector2(9, 16), "DEV", "heavy", 12, Design.PLUM)
	if Settings.flag("show_timer"):
		var secs := int(play_time)
		_text(o + Vector2(r.size.x - 86, 62), "%d:%02d" % [secs / 60, secs % 60], "mono", 18, Design.MUTED)
	if goal_total > 0:
		Icons.stage(self, o + Vector2(30, 87), stage)
		Design.draw_bar(self, Rect2(o + Vector2(50, 80), Vector2(208, 14)), float(goal_done) / goal_total,
			Design.STAGE_ACCENTS[stage])
		_text(o + Vector2(268, 93), "%d/%d" % [goal_done, goal_total], "heavy", 17, Design.CREAM, 4)
	else:
		_text(o + Vector2(18, 94), "ПОБЕДИ ЯИЧНИЦУ!", "heavy", 17, Design.YOLK, 4)
	_draw_stage_track(o + Vector2(30, 126))


func _draw_stage_track(origin: Vector2) -> void:
	Design.draw_route(self, origin, stage, 70.0, t)


func _draw_right(panel: StyleBox) -> void:
	var r := _right_rect()
	draw_style_box(panel, r)
	for i in max_lives:
		var c := r.position + Vector2(38 + i * 40, 30)
		var alive := i < lives
		var s := 12.0
		if alive and lives == 1:
			s *= 1.0 + 0.12 * sin(t * 9.0)
		Icons.heart(self, c, s + 3.0, Color(0.15, 0.02, 0.05))
		Icons.heart(self, c, s, Color(0.95, 0.15, 0.25) if alive else Color(0.35, 0.3, 0.3, 0.7))
		if alive:
			draw_circle(c + Vector2(-s * 0.55, -s * 0.35), s * 0.2, Color(1, 1, 1, 0.5))
		elif i == lives and heart_anim > 0.0:  # только что потерянное сердце улетает
			Icons.heart(self, c + Vector2(0, -20.0 * (1.0 - heart_anim)), s * (2.0 - heart_anim), Color(1, 0.2, 0.3, heart_anim))
	if shield > 0:
		var c := r.position + Vector2(38 + max_lives * 40, 30)
		Icons.shield(self, c, 14.0)
		if shield > 1:
			_text(c + Vector2(8, 16), "×%d" % shield, "heavy", 14, Color.WHITE, 3)
	var st_col := Design.MINT
	if exhausted:
		st_col = Design.TOMATO if int(t * 6.0) % 2 == 0 else Design.TOMATO.darkened(0.4)
	Design.draw_bar(self, Rect2(r.position + Vector2(20, 60), Vector2(r.size.x - 40, 10)), stamina, st_col)


## Табличка атаки (2.2): иконка, название, гравировка источника (медведь, вилка, таблетка — цветом
## его этапа) и заряды лампами вместо «×N».
func _draw_ability() -> void:
	var r := _ability_rect()
	var src: String = ABILITY_SOURCE.get(ability_type, "bear")
	var src_col: Color = Design.SOURCE_COLORS[src]
	draw_style_box(Design.cached("hud_ability", func() -> StyleBox:
		return Design.plank(Color(0, 0, 0, 0), Design.RADIUS_MD, Vector2.ZERO, false)), r)
	draw_line(r.position + Vector2(10, 8), r.position + Vector2(10, r.size.y - 8), src_col, 3.0)  # кромка источника
	if ability_flash > 0.01:
		draw_style_box(Design.box(Color.TRANSPARENT, Color(Design.MINT, ability_flash), Design.RADIUS_MD, 2, Vector2.ZERO), r)
	Icons.ability(self, r.position + Vector2(34, 30), ability_type, t)
	_text(r.position + Vector2(62, 24), ability_name, "heavy", 16, Design.MINT, 4)
	_text(r.position + Vector2(62, 44), Design.SOURCE_NAMES[src], "heavy", 11, src_col.lightened(0.15))
	_text(r.position + Vector2(62, 62), "кнопка АТАКА" if touch else "Пробел / ЛКМ", "body", 12, Design.MUTED)
	var shown := mini(ability_charges, 8)  # заряды — лампами справа внизу, под названием им не тесно
	Design.draw_lamps(self, r.position + Vector2(r.size.x - 18 - (shown - 1) * 13.0, 54), maxi(ability_charges, 1),
		ability_charges, Design.MINT, 4.5, 13.0)


func _draw_boss_bar() -> void:
	var frame := _boss_rect()
	var col: Color = Design.PHASE_COLORS[boss_phase - 1]
	draw_style_box(Design.cached("hud_boss", func() -> StyleBox:
		return Design.plank(Color(0, 0, 0, 0), Design.RADIUS_MD, Vector2.ZERO, true)), frame)
	draw_style_box(Design.box(Color.TRANSPARENT, Color(col, 0.8), Design.RADIUS_MD, 2, Vector2.ZERO), frame)
	_text(frame.position + Vector2(22, 26), "ГИГАНТСКАЯ ЯИЧНИЦА", "heavy", 18, Design.CREAM, 4)
	var f := Design.font("heavy")
	draw_string(f, frame.position + Vector2(frame.size.x - 222, 26), "ФАЗА %d · %s" % [boss_phase, BOSS_PHASES[boss_phase - 1]], HORIZONTAL_ALIGNMENT_RIGHT,
		200, 16, col)
	var bar := Rect2(frame.position + Vector2(22, 38), Vector2(frame.size.x - 44, 18))
	draw_rect(bar.grow(2), Design.INK)
	draw_rect(bar, Color(0.25, 0.12, 0.08))
	var ghost := bar
	ghost.size.x *= clampf(boss_hp_ghost / boss_max, 0.0, 1.0)
	draw_rect(ghost, Color(1, 0.95, 0.85, 0.8))
	var fill := bar
	fill.size.x *= clampf(boss_hp_shown / boss_max, 0.0, 1.0)
	draw_rect(fill, col.lerp(Color.WHITE, boss_flash * 0.7))
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, 5)), Color(1, 1, 1, 0.3))
	for k in [1.0 / 3.0, 2.0 / 3.0]:
		var x: float = bar.position.x + bar.size.x * k
		draw_line(Vector2(x, bar.position.y - 2), Vector2(x, bar.end.y + 2), Design.INK, 3.0)


func _text(pos: Vector2, text: String, weight: String, fs: int, col: Color, outline := 0) -> void:
	var f := Design.font(weight)
	if outline > 0:
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(Design.INK, 0.9))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
