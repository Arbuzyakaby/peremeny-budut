extends Node
## Финальная катсцена после победы над яичницей. Грустная музыка, камера отдаляется — арена
## оказывается ящиком на столе учёного-бюрократа. Сцены:
## 1. учёный входит и зачитывает протокол с результатами забега;
## 2. камера проезжает по полкам с образцами прошлых экспериментов (медведь, вилка, таблетка);
## 3. учёный пишет в протоколе, достаёт спичку — выбор игрока:
##    ЛКМ — бросить спичку самому; ничего не делать — гром, учёный вздрагивает и роняет спичку;
## 4. пожар охватывает ящик, змея сгорает;
## 5. учёный тушит огнетушителем, ставит штамп «УТИЛИЗИРОВАНО», гасит лампу и уходит;
## 6. в темноте в пепле блестит яйцо — из него вылупляется маленькая змейка. «ПЕРЕМЕНЫ БУДУТ».
## 7. титры со статистикой забега. Esc — пропустить.

signal finished

const Lab = preload("res://scripts/lab.gd")
const Fire = preload("res://scripts/fire.gd")
const Snake = preload("res://scripts/snake.gd")
const Hud = preload("res://scripts/hud.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Tex = preload("res://scripts/tex.gd")

const ZOOM_OUT := Vector2(0.25, 0.25)
const CAM_POS := Vector2(1600, 60)
const SHELF_POS := Vector2(-450, -330)
const SHELF_ZOOM := Vector2(0.42, 0.42)
const HAND_OVER := Vector2(1000, -260)  # рука со спичкой над ящиком
const CHOICE_TIME := 7.0
const SCIENTIST := "УЧЁНЫЙ-БЮРОКРАТ"
const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 0.0;
uniform float dark = 0.0;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * (1.0 + blur * 2.5);
	vec3 c = vec3(0.0);
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			c += textureLod(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px, blur).rgb;
		}
	}
	c /= 25.0;
	float gray = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(gray), dark * 0.5);
	float vig = distance(SCREEN_UV, vec2(0.5));
	c *= 1.0 - dark * (0.7 + vig * 0.6);
	COLOR = vec4(c, 1.0);
}
"""

var game  # game.gd (без типа, чтобы не было циклического preload)
var camera: Camera2D
var snake: Snake
var hud: Hud
var sfx: Sfx
var lab: Lab
var fire: Fire
var blur_mat: ShaderMaterial
var blur_rect: ColorRect
var darkness: CanvasModulate
var foam: CPUParticles2D
var hatch_node: Node2D
var baby: Snake
var tw: Tween
var tw_end: Tween
var impact := Vector2(640, 360)
var step_t := 0.0
var snake_burnt := false
var done := false
var waiting_choice := false
var choice_t := 0.0
var tick_t := 0.0
var choice := ""  # "throw" — бросил игрок, "thunder" — уронил от грома
var egg_pos := Vector2(640, 360)
var egg_k := 0.0      # 0 — нет, 1 — яйцо лежит
var egg_glint := 0.0
var egg_crack := 0.0  # 0..1 — трещины, 1 — скорлупа раскрылась
var t := 0.0
var in_dark := false


func start(g) -> void:
	game = g
	camera = g.camera
	snake = g.snake
	hud = g.hud
	sfx = g.sfx
	lab = Lab.new()
	lab.z_index = -10
	g.add_child(lab)
	fire = Fire.new()
	fire.z_index = 6
	g.world.add_child(fire)
	darkness = CanvasModulate.new()
	darkness.color = Color.WHITE
	g.add_child(darkness)
	hatch_node = Node2D.new()
	hatch_node.z_index = 7
	hatch_node.draw.connect(_draw_hatch)
	g.world.add_child(hatch_node)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	blur_rect = ColorRect.new()
	blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	blur_mat = ShaderMaterial.new()
	blur_mat.shader = sh
	blur_rect.material = blur_mat
	blur_rect.visible = false
	layer.add_child(blur_rect)

	snake.invuln = 0.0
	snake.stun_t = 0.0
	snake.autopilot = true
	snake.auto_speed = 80.0
	hud.set_cinematic(true)
	sfx.play_music("sad")

	tw = create_tween()
	tw.tween_interval(0.8)
	tw.tween_callback(hud.show_caption.bind("", "Яичница повержена. Змея наконец-то свободна..."))
	tw.tween_interval(2.2)
	tw.tween_property(camera, "zoom", ZOOM_OUT, 6.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(camera, "position", CAM_POS, 6.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_callback(hud.show_caption.bind("", "...или нет?")).set_delay(3.2)
	# учёный подходит к столу
	tw.tween_callback(func() -> void:
		hud.hide_caption()
		lab.walking = true)
	tw.tween_property(lab, "sx", Lab.STAND_X, 3.0)
	tw.parallel().tween_property(lab, "hand", Vector2(Lab.STAND_X - 560, 700), 3.0)
	tw.tween_callback(func() -> void: lab.walking = false)
	tw.tween_interval(0.5)
	# протокол с результатами забега
	tw.tween_callback(_say.bind("Эксперимент №47 завершён. Результаты внесены в протокол.", 2.6))
	tw.tween_interval(3.3)
	tw.tween_callback(_say.bind(_stats_line(), 3.2))
	tw.tween_interval(4.0)
	if g.cfg.get("no_skills", false):
		tw.tween_callback(_say.bind("Без единой поблажки. Любопытно. Но не по регламенту.", 2.6))
		tw.tween_interval(3.3)
	# проезд по полкам с образцами прошлых экспериментов
	tw.tween_callback(func() -> void:
		lab.look = SHELF_POS
		hud.show_caption("", "На полках — образцы прошлых экспериментов: №21, №44, №45, №46..."))
	tw.tween_property(camera, "position", SHELF_POS, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(camera, "zoom", SHELF_ZOOM, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_say.bind("Медведи. Вилки. Таблетки. Все прошли через этот ящик.", 2.8))
	tw.tween_interval(3.4)
	tw.tween_callback(hud.hide_caption)
	tw.tween_property(camera, "position", CAM_POS, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(camera, "zoom", ZOOM_OUT, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# пишет в протоколе
	tw.tween_callback(func() -> void:
		lab.look = Vector2(Lab.STAND_X + 400, 700)
		lab.writing = true
		sfx.play("scribble")
		_say("Подпись. Дата. Печать — после процедуры.", 2.6))
	tw.tween_interval(1.4)
	tw.tween_callback(sfx.play.bind("scribble", 1.1))
	tw.tween_interval(1.8)
	tw.tween_callback(func() -> void:
		lab.writing = false
		lab.look = Vector2(640, 360))
	tw.tween_callback(_say.bind("Согласно пункту 12-Б, образец подлежит утилизации.", 2.6))
	tw.tween_interval(3.3)
	tw.tween_callback(func() -> void:
		_say("Приступаю.", 0.8)
		lab.match_state = Lab.Match.HELD)
	tw.tween_property(lab, "hand", HAND_OVER, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		lab.match_state = Lab.Match.LIT
		sfx.play("match"))
	tw.tween_interval(1.0)
	tw.tween_callback(_begin_choice)


func _stats_line() -> String:
	return "Образец прошёл все этапы: медведей — %d, вилок — %d, таблеток — %d. И яичница." % [
		game.bears_eaten, game.forks_broken, game.pills_eaten]


func _say(text: String, talk_time: float) -> void:
	hud.show_caption(SCIENTIST, text)
	lab.talk = talk_time


# ---------------------------------------------------------------- выбор

func _begin_choice() -> void:
	waiting_choice = true
	choice_t = CHOICE_TIME
	tick_t = 0.0
	lab.tremble = true
	hud.show_prompt("ЛКМ — бросить спичку")
	hud.show_caption("", "...или ничего не делать")


## Игрок нажал ЛКМ во время выбора.
func choose_throw() -> void:
	if not waiting_choice:
		return
	_end_choice("throw")
	var t2 := create_tween()
	t2.tween_property(lab, "hand", HAND_OVER + Vector2(40, -120), 0.18).set_ease(Tween.EASE_OUT)
	t2.tween_property(lab, "hand", HAND_OVER + Vector2(-60, 160), 0.14).set_ease(Tween.EASE_IN)
	t2.tween_callback(_release_match.bind(0.55, "whoosh"))


## Время вышло — гром, учёный вздрагивает и роняет спичку.
func _thunder_drop() -> void:
	_end_choice("thunder")
	lab.flash = 1.0
	sfx.play("thunder", 1.0, 3.0)
	game.shake = 45.0
	lab.look = Vector2(640, -700)  # оглядывается на окно
	var t2 := create_tween()
	t2.tween_property(lab, "startle", 1.0, 0.08)
	t2.tween_callback(func() -> void: _say("Ай!", 0.6))
	t2.tween_callback(_release_match.bind(0.9, ""))
	t2.tween_interval(0.6)
	t2.tween_property(lab, "startle", 0.0, 1.2)


func _end_choice(what: String) -> void:
	waiting_choice = false
	choice = what
	lab.tremble = false
	hud.hide_prompt()
	hud.hide_caption()


func _release_match(fall_time: float, snd: String) -> void:
	var from := lab.match_tip()
	impact = Vector2(clampf(from.x, 150.0, 1130.0), clampf(snake.head_pos.y + 180.0, 200.0, 560.0))
	if impact.distance_to(snake.head_pos) < 150.0:
		impact.y = 700.0 - impact.y
	lab.match_state = Lab.Match.FLYING
	if snd != "":
		sfx.play(snd, 0.7)
	var t2 := create_tween()
	t2.tween_method(_fly_match.bind(from), 0.0, 1.0, fall_time)
	t2.tween_callback(_ignite)


func _fly_match(k: float, from: Vector2) -> void:
	lab.match_pos = from.lerp(impact, k * k)  # падает с ускорением
	lab.match_rot = -PI / 2 + k * TAU * 1.25


func _ignite() -> void:
	lab.match_state = Lab.Match.GONE
	fire.start(impact)
	sfx.play("ignite")
	sfx.play_ambient("fire", -14.0)
	game.shake = 50.0
	snake.auto_speed = 330.0
	create_tween().tween_property(lab, "glow", 1.0, 2.0)
	var t2 := create_tween()
	t2.tween_property(lab, "hand", Vector2(Lab.STAND_X - 560, 700), 1.2).set_trans(Tween.TRANS_SINE)
	t2.tween_interval(6.0)  # на случай, если змея как-то избежит огня
	t2.tween_callback(_burn_snake)


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	egg_glint = maxf(egg_glint - delta * 0.8, 0.0)
	if baby:
		baby.update(delta)
	if egg_k > 0.0:
		hatch_node.queue_redraw()
	if foam and lab:
		foam.position = lab.nozzle()
	if lab and lab.walking:
		step_t -= delta
		if step_t <= 0.0:
			step_t = PI / 7.0
			sfx.play("step", randf_range(0.9, 1.05), -2.0)
	if in_dark:
		tick_t -= delta
		if tick_t <= 0.0:
			tick_t = 1.0
			sfx.play("tick", 0.5, -6.0)  # в темноте тикают часы
	if waiting_choice:
		choice_t -= delta
		tick_t -= delta
		if tick_t <= 0.0:
			tick_t = 1.0
			sfx.play("tick", 0.5, 2.0)  # тикают часы
		if choice_t <= 0.0:
			_thunder_drop()
		return
	if fire == null or not fire.active:
		return
	sfx.set_ambient_volume(lerpf(-20.0, -3.0, fire.coverage()))
	if not snake_burnt:
		lab.look = snake.head_pos
		# змея в панике убегает от огня
		var away := (snake.head_pos - fire.origin).normalized()
		snake.auto_target = (snake.head_pos + away.rotated(sin(fire.t * 3.0) * 0.8) * 300.0).clamp(
			Vector2(60, 60), Vector2(1220, 660))
		if fire.covers(snake.head_pos):
			_burn_snake()


func _burn_snake() -> void:
	if snake_burnt:
		return
	snake_burnt = true
	snake.alive = false
	egg_pos = snake.head_pos.clamp(Vector2(120, 140), Vector2(1160, 600))
	sfx.play("burn")
	sfx.play("lose", 0.8, -6.0)
	create_tween().tween_property(snake, "burnt", 1.0, 1.5)
	if tw:
		tw.kill()
	var last_words := "Внесу в отчёт: утилизация проведена успешно."
	if choice == "thunder":
		last_words = "...Что ж. В отчёте укажу, что так и планировалось."
	tw_end = create_tween()
	tw_end.tween_interval(1.8)
	tw_end.tween_callback(_say.bind(last_words, 2.6))
	tw_end.tween_interval(3.4)
	tw_end.tween_callback(hud.show_caption.bind("", "Как ни поступи — ничего нельзя было изменить."))
	tw_end.tween_interval(2.6)
	# тушит огнетушителем
	tw_end.tween_callback(func() -> void:
		lab.holding = Lab.Hold.EXTINGUISHER
		_say("Технику безопасности никто не отменял.", 2.0))
	tw_end.tween_property(lab, "hand", HAND_OVER + Vector2(120, -60), 1.2).set_trans(Tween.TRANS_SINE)
	tw_end.tween_callback(_spray)
	tw_end.tween_interval(3.0)
	tw_end.tween_callback(func() -> void:
		lab.spraying = false
		foam.emitting = false
		hud.hide_caption())
	tw_end.tween_property(lab, "hand", Vector2(Lab.STAND_X - 560, 700), 1.2).set_trans(Tween.TRANS_SINE)
	# штамп на протоколе
	tw_end.tween_callback(func() -> void:
		lab.holding = Lab.Hold.MATCH
		lab.look = Vector2(1770, 600))
	tw_end.tween_interval(0.4)
	tw_end.tween_callback(func() -> void:
		sfx.play("stamp")
		game.shake = 14.0
		_say("Утилизировано.", 1.2))
	tw_end.tween_property(lab, "stamped", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	tw_end.tween_interval(2.2)
	# гасит лампу и уходит
	tw_end.tween_callback(func() -> void:
		hud.hide_caption()
		sfx.play("lamp_click")
		lab.lights = 0.0
		in_dark = true
		tick_t = 0.6)
	tw_end.tween_property(darkness, "color", Color(0.26, 0.28, 0.42), 0.25)
	tw_end.tween_interval(1.2)
	tw_end.tween_callback(func() -> void: lab.walking = true)
	tw_end.tween_property(lab, "sx", Lab.OUTSIDE_X + 200.0, 4.0)
	tw_end.parallel().tween_property(lab, "hand", Vector2(Lab.OUTSIDE_X - 360, 700), 4.0)
	tw_end.tween_callback(func() -> void: lab.walking = false)
	tw_end.tween_interval(1.0)
	# камера спускается к ящику — в пепле что-то блестит
	tw_end.tween_property(camera, "position", egg_pos, 4.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_end.parallel().tween_property(camera, "zoom", Vector2(3.6, 3.6), 4.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_end.parallel().tween_property(darkness, "color", Color(0.45, 0.5, 0.68), 4.5)  # лунный свет из окна
	tw_end.parallel().tween_property(self, "egg_k", 1.0, 1.0).set_delay(1.5)
	tw_end.tween_callback(_glint)
	tw_end.tween_interval(1.6)
	tw_end.tween_callback(_glint)
	tw_end.tween_interval(1.4)
	tw_end.tween_callback(sfx.play.bind("hatch"))
	tw_end.tween_property(self, "egg_crack", 0.7, 0.9)
	tw_end.tween_interval(0.5)
	tw_end.tween_property(self, "egg_crack", 1.0, 0.25)
	tw_end.tween_callback(_hatch)
	tw_end.tween_interval(2.4)
	tw_end.tween_callback(func() -> void:
		sfx.play("win", 0.5, -4.0)
		hud.show_title_card("ПЕРЕМЕНЫ БУДУТ", Color(0.55, 1, 0.5)))
	tw_end.tween_interval(4.5)
	tw_end.tween_callback(hud.hide_title_card)
	# титры
	tw_end.tween_callback(func() -> void:
		blur_rect.visible = true
		hud.roll_credits(_credits(), 16.0))
	tw_end.tween_method(_set_blur, 0.0, 0.7, 2.5)
	tw_end.tween_interval(14.0)
	tw_end.tween_method(_set_blur, 0.7, 1.0, 1.0)
	tw_end.tween_interval(0.4)
	tw_end.tween_callback(_finish)


func _spray() -> void:
	lab.spraying = true
	sfx.play("extinguisher")
	foam = CPUParticles2D.new()
	foam.z_as_relative = false
	foam.z_index = 41
	foam.position = lab.nozzle()
	foam.amount = 160
	foam.lifetime = 1.3
	foam.direction = (fire.origin - foam.position).normalized()
	foam.spread = 14.0
	foam.initial_velocity_min = 900.0
	foam.initial_velocity_max = 1400.0
	foam.damping_min = 300.0
	foam.damping_max = 500.0
	foam.gravity = Vector2(0, 500)
	foam.texture = Tex.soft()
	foam.scale_amount_min = 0.6
	foam.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.95))
	ramp.set_color(1, Color(0.9, 0.93, 1, 0))
	foam.color_ramp = ramp
	game.add_child(foam)
	foam.emitting = true
	fire.extinguish(2.4)
	sfx.stop_ambient(2.6)
	create_tween().tween_property(lab, "glow", 0.0, 2.4)


func _glint() -> void:
	egg_glint = 1.0
	sfx.play("scale", 0.8, -6.0)


func _hatch() -> void:
	baby = Snake.new()
	baby.small = 0.45
	baby.length = 6
	baby.autopilot = true
	baby.auto_speed = 22.0
	baby.bounds = Rect2(egg_pos - Vector2(70, 45), Vector2(140, 90))
	baby.reset(egg_pos + Vector2(0, 6))
	baby.auto_target = egg_pos + Vector2(40, -10)
	baby.z_index = 8
	game.world.add_child(baby)


func _draw_hatch() -> void:
	if egg_k <= 0.0:
		return
	var c := egg_pos
	var k := egg_k
	Tex.blob(hatch_node, c + Vector2(0, 6), Vector2(34, 16) * k, Color(0, 0, 0, 0.5))
	if egg_crack < 1.0:
		var wob := sin(t * 18.0) * 0.12 * egg_crack
		hatch_node.draw_set_transform(c, wob, Vector2(k, k))
		_egg_shape(Vector2.ZERO, 1.0)
		for i in int(egg_crack * 6.0):  # трещины
			var a := -1.2 + i * 0.5
			var p0 := Vector2(cos(a) * 9.0, -6.0 + sin(a) * 4.0)
			hatch_node.draw_polyline(PackedVector2Array([p0, p0 + Vector2(3, 4), p0 + Vector2(-1, 8)]), Color(0.2, 0.25, 0.15), 1.2)
		hatch_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:  # половинки скорлупы
		for s in [-1.0, 1.0]:
			hatch_node.draw_set_transform(c + Vector2(s * 16, 6), s * 0.9, Vector2.ONE * 0.8)
			var half := PackedVector2Array()
			for i in 9:
				var a := PI * i / 8.0
				half.append(Vector2(cos(a) * 12.0, sin(a) * 14.0))
			for i in range(1, 4):  # зубчатый край скорлупы
				half.append(Vector2(-12.0 + i * 6.0, -3.0 if i % 2 == 1 else 1.0))
			hatch_node.draw_colored_polygon(half, Color(0.85, 0.95, 0.8))
			hatch_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if egg_glint > 0.0:  # блик в темноте
		var g := egg_glint
		var p := c + Vector2(-6, -12)
		Tex.blob(hatch_node, p, Vector2.ONE * 26.0 * g, Color(1, 1, 0.8, 0.7 * g))
		hatch_node.draw_line(p - Vector2(18, 0) * g, p + Vector2(18, 0) * g, Color(1, 1, 1, g), 2.0)
		hatch_node.draw_line(p - Vector2(0, 18) * g, p + Vector2(0, 18) * g, Color(1, 1, 1, g), 2.0)


func _egg_shape(o: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		var r := 1.0 + 0.18 * sin(a)  # к низу шире
		pts.append(o + Vector2(cos(a) * 13.0 * s, sin(a) * 17.0 * s * r))
	hatch_node.draw_colored_polygon(pts, Color(0.15, 0.25, 0.12))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(o + (p - o) * 0.88)
	hatch_node.draw_colored_polygon(inner, Color(0.75, 0.92, 0.65))
	for i in 7:  # крапинки
		hatch_node.draw_circle(o + Vector2(sin(i * 2.3) * 7.0, cos(i * 1.7) * 10.0), 1.6, Color(0.35, 0.6, 0.3))
	Tex.blob(hatch_node, o + Vector2(-4, -7), Vector2(5, 7), Color(1, 1, 1, 0.7))


func _credits() -> String:
	var mins := int(game.play_time) / 60
	var secs := int(game.play_time) % 60
	var lines := [
		"ЗМЕЯ ПРОТИВ ГИГАНТСКОЙ ЯИЧНИЦЫ", "версия %s" % ProjectSettings.get_setting("application/config/version", "5.0"), "",
		"ПРОТОКОЛ ЭКСПЕРИМЕНТА №47",
		"Сложность: %s" % game.cfg["name"],
		"Медведей съедено: %d" % game.bears_eaten,
		"Вилок сломано: %d" % game.forks_broken,
		"Таблеток съедено: %d" % game.pills_eaten,
		"Время: %d:%02d   •   Счёт: %d" % [mins, secs, game.score],
		choice_text(), "",
		"В РОЛЯХ",
		"Змея — образец №47",
		"Гигантская Яичница — сама себя",
		"Учёный-бюрократ — пункт 12-Б",
		"Медведи, вилки и таблетки — массовка",
		"Змейка — образец №48", "",
		"Графика и звук сгенерированы кодом.",
		"Ни одной картинки. Ни одного аудиофайла.", "",
		"Перемены будут.",
	]
	return "\n".join(lines)


func _set_blur(k: float) -> void:
	blur_mat.set_shader_parameter("blur", k * 4.5)
	blur_mat.set_shader_parameter("dark", k * 0.8)


func choice_text() -> String:
	match choice:
		"throw":
			return "Спичку бросил ты."
		"thunder":
			return "Ты ничего не сделал — спичку уронил гром."
	return ""


func skip() -> void:
	if done:
		return
	if tw:
		tw.kill()
	if tw_end:
		tw_end.kill()
	waiting_choice = false
	hud.hide_prompt()
	hud.stop_credits()
	sfx.stop_ambient(0.5)
	camera.zoom = ZOOM_OUT
	camera.position = CAM_POS
	lab.walking = false
	lab.writing = false
	lab.sx = Lab.STAND_X
	lab.tremble = false
	lab.match_state = Lab.Match.GONE
	lab.hand = Vector2(Lab.STAND_X - 560, 700)
	lab.glow = 1.0
	fire.fill_instantly()
	snake.alive = false
	snake.burnt = 1.0
	snake_burnt = true
	blur_rect.visible = true
	_set_blur(1.0)
	hud.hide_caption()
	_finish()


func _finish() -> void:
	if done:
		return
	done = true
	finished.emit()
