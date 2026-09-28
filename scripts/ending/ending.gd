extends Node
## Финальная катсцена после победы над яичницей. Грустная музыка, камера отдаляется — арена
## оказывается ящиком на столе учёного-бюрократа. Сцены:
## 1. учёный входит и зачитывает протокол с результатами забега;
## 2. камера проезжает по полкам с образцами прошлых экспериментов (медведь, вилка, таблетка);
## 3. учёный пишет в протоколе, достаёт спичку — выбор игрока:
##    ЛКМ — бросить спичку самому; ничего не делать — гром, учёный вздрагивает и роняет спичку;
## 4. пожар охватывает ящик, змея сгорает (первая вспышка — событие: тишина, белый экран, удар;
##    треск и паника интерфейса следуют за силой огня);
## 5. учёный тушит огнетушителем, ставит штамп «УТИЛИЗИРОВАНО», гасит лампу и уходит;
## 6. в темноте в пепле блестит яйцо — из него вылупляется маленькая змейка. «ПЕРЕМЕНЫ БУДУТ».
## 7. титры со статистикой забега. Esc — пропустить.

signal finished

const Lab = preload("res://scripts/ending/lab.gd")
const Fire = preload("res://scripts/ending/fire.gd")
const Snake = preload("res://scripts/entities/snake.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")
const Tex = preload("res://scripts/gfx/tex.gd")
const Hatch = preload("res://scripts/ending/hatch.gd")
const Credits = preload("res://scripts/ending/credits.gd")
const Design = preload("res://scripts/ui/design.gd")
const Settings = preload("res://scripts/core/settings.gd")

## Первое возгорание — событие: HUSH тишины (sfx.hush), затем белая вспышка, «ignite» в полную силу
## и тряска; музыка молчит ещё MUSIC_GAP после вспышки.
const HUSH := 0.2
const HUSH_MARGIN := 0.03  # удар — через кадр-два после конца тишины: атака не попадает под -80 дБ
const MUSIC_GAP := 0.1
const IGNITE_DB := 2.0
const IGNITE_SHAKE := 50.0
## Треск пожара: частота и громкость растут с долей огня (fire.coverage()) — в обе стороны.
const CRACKLE_RATE := Vector2(0.7, 14.0)   # щелчков в секунду: огонёк … весь ящик
const CRACKLE_DB := Vector2(-18.0, 0.0)    # громкость: огонёк … весь ящик
const PANIC_GAIN := 1.4                    # Design.panic = coverage × PANIC_GAIN (до 1)

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
var hatch_node: Hatch
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
var t := 0.0
var in_dark := false
var tw_flare: Tween
var crackle_t := 0.0
var crackles := 0  # сколько раз трещало (тесты)


func start(g) -> void:
	game = g
	camera = g.camera
	snake = g.snake
	hud = g.hud
	sfx = g.sfx
	lab = Lab.new()
	lab.z_index = -10
	lab.tally = [g.bears_eaten, g.forks_broken, g.pills_eaten]  # итоги забега — мелом на доске
	g.add_child(lab)
	fire = Fire.new()
	fire.seed_value = randi()  # каждый пожар свой: раскладка обломков, прогрев углов, запас топлива
	fire.z_index = 6
	g.world.add_child(fire)
	darkness = CanvasModulate.new()
	darkness.color = Color.WHITE
	g.add_child(darkness)
	hatch_node = Hatch.new()
	hatch_node.z_index = 7
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


## Спичка упала: кинопауза тишины, затем вспышка (_flare).
func _ignite() -> void:
	lab.match_state = Lab.Match.GONE
	sfx.hush(HUSH)
	sfx.music_player.stream_paused = true
	tw_flare = create_tween()
	tw_flare.tween_interval(HUSH)
	tw_flare.tween_callback(_end_hush)
	tw_flare.tween_interval(HUSH_MARGIN)
	tw_flare.tween_callback(_flare)
	tw_flare.tween_interval(MUSIC_GAP)
	tw_flare.tween_callback(func() -> void: sfx.music_player.stream_paused = false)


## Страховка: таймер sfx.hush() может сработать чуть раньше, чем разрешает его проверка по часам, —
## тогда тишина не снимается. hush(0) снимает её на следующем кадре; если всё уже звучит — ничего.
func _end_hush() -> void:
	if sfx.is_hushed():
		sfx.hush(0.0)


## Первая вспышка: белый экран (мягче при «меньше анимации» и без вспышек урона — решает
## hud_overlay.flash), удар «ignite» в полную силу, тряска.
func _flare() -> void:
	if done:
		return
	fire.start(impact)
	hud.overlay.flash(1.0)
	sfx.play("ignite", 1.0, IGNITE_DB)
	sfx.play_ambient("fire", -14.0)
	game.shake = IGNITE_SHAKE * (0.3 if Settings.flag("reduced_motion") else 1.0)
	crackle_t = 0.0
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
	if baby:
		baby.update(delta)
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
	var cov := fire.coverage()
	sfx.set_ambient_volume(lerpf(-20.0, -3.0, cov))
	# треск: огонёк — редкие тихие щелчки, весь ящик — плотный громкий треск
	crackle_t -= delta
	if cov > 0.005 and crackle_t <= 0.0:
		crackle_t = randf_range(0.6, 1.4) / crackle_rate(cov)
		sfx.play("crackle", randf_range(0.85, 1.2), crackle_db(cov))
		crackles += 1
	# интерфейс паникует вместе с пожаром и успокаивается, когда огонь потушен
	Design.panic = move_toward(Design.panic, panic_level(cov), delta * 2.5)
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
	hatch_node.egg_pos = snake.head_pos.clamp(Vector2(120, 140), Vector2(1160, 600))
	sfx.play("burn")
	sfx.play("lose", 0.8, -6.0)
	create_tween().tween_property(snake, "burnt", 1.0, 1.5)
	# шейдер обугливания: фронт бежит по телу, тлеющая кромка, потом седая зола
	var burn_mat := Tex.material(Tex.Mat.PLASTIC, 3.0)
	snake.material = burn_mat
	create_tween().tween_method(func(k: float) -> void: burn_mat.set_shader_parameter("burn", k), 0.0, 1.55, 3.5)
	sfx.play("melt", 1.0, -6.0)
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
	tw_end.tween_property(camera, "position", hatch_node.egg_pos, 4.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_end.parallel().tween_property(camera, "zoom", Vector2(3.6, 3.6), 4.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_end.parallel().tween_property(darkness, "color", Color(0.45, 0.5, 0.68), 4.5)  # лунный свет из окна
	tw_end.parallel().tween_property(hatch_node, "egg_k", 1.0, 1.0).set_delay(1.5)
	tw_end.tween_callback(_glint)
	tw_end.tween_interval(1.6)
	tw_end.tween_callback(_glint)
	tw_end.tween_interval(1.4)
	tw_end.tween_callback(sfx.play.bind("hatch"))
	tw_end.tween_property(hatch_node, "egg_crack", 0.7, 0.9)
	tw_end.tween_interval(0.5)
	tw_end.tween_property(hatch_node, "egg_crack", 1.0, 0.25)
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
		hud.roll_credits(Credits.text(game, choice_text(), fire.burnt_cells()), 16.0))
	tw_end.tween_method(_set_blur, 0.0, 0.7, 2.5)
	tw_end.tween_interval(14.0)
	tw_end.tween_method(_set_blur, 0.7, 1.0, 1.0)
	tw_end.tween_interval(0.4)
	tw_end.tween_callback(_finish)


func _spray() -> void:
	lab.spraying = true
	sfx.play("extinguisher")
	sfx.duck(-4.0, 0.5)  # струя не тонет в треске: шина Ambient (петля огня, треск, горение) — тише
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
	hatch_node.egg_glint = 1.0
	sfx.play("scale", 0.8, -6.0)


func _hatch() -> void:
	baby = Snake.new()
	baby.small = 0.45
	baby.length = 6
	baby.autopilot = true
	baby.auto_speed = 22.0
	baby.bounds = Rect2(hatch_node.egg_pos - Vector2(70, 45), Vector2(140, 90))
	baby.reset(hatch_node.egg_pos + Vector2(0, 6))
	baby.auto_target = hatch_node.egg_pos + Vector2(40, -10)
	baby.z_index = 8
	game.world.add_child(baby)


func _set_blur(k: float) -> void:
	blur_mat.set_shader_parameter("blur", k * 4.5)
	blur_mat.set_shader_parameter("dark", k * 0.8)


## Щелчков треска в секунду при доле огня cov (0..1).
static func crackle_rate(cov: float) -> float:
	return lerpf(CRACKLE_RATE.x, CRACKLE_RATE.y, clampf(cov, 0.0, 1.0))


## Громкость щелчка треска (дБ) при доле огня cov.
static func crackle_db(cov: float) -> float:
	return lerpf(CRACKLE_DB.x, CRACKLE_DB.y, sqrt(clampf(cov, 0.0, 1.0)))


## Уровень паники интерфейса при доле огня cov.
static func panic_level(cov: float) -> float:
	return clampf(cov * PANIC_GAIN, 0.0, 1.0)


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
	if tw_flare:
		tw_flare.kill()
	_end_hush()  # пропуск посреди кинопаузы — звук должен вернуться
	sfx.music_player.stream_paused = false
	Design.panic = 0.0
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
	Design.panic = 0.0
	finished.emit()


func _exit_tree() -> void:
	Design.panic = 0.0  # выход в меню посреди пожара — интерфейс не должен остаться в панике
	if is_instance_valid(sfx) and sfx.music_player:
		sfx.music_player.stream_paused = false
