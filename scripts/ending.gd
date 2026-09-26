extends Node
## Финальная катсцена после победы над яичницей: грустная музыка, камера отдаляется — арена
## оказывается ящиком на столе учёного-бюрократа. Он подходит, зачитывает протокол и заносит
## зажжённую спичку над ящиком. Дальше выбор игрока:
## - ЛКМ — бросить спичку самому;
## - ничего не делать — за окном гремит гром, учёный вздрагивает и роняет спичку.
## Итог один и тот же: ничего изменить нельзя. Экран темнеет и размывается. Esc — пропустить.

signal finished

const Lab = preload("res://scripts/lab.gd")
const Fire = preload("res://scripts/fire.gd")
const Snake = preload("res://scripts/snake.gd")
const Hud = preload("res://scripts/hud.gd")
const Sfx = preload("res://scripts/sfx.gd")

const ZOOM_OUT := Vector2(0.25, 0.25)
const CAM_POS := Vector2(1600, 60)
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
var tw: Tween
var tw_end: Tween
var impact := Vector2(640, 360)
var crackle_t := 0.0
var step_t := 0.0
var snake_burnt := false
var done := false
var waiting_choice := false
var choice_t := 0.0
var tick_t := 0.0
var choice := ""  # "throw" — бросил игрок, "thunder" — уронил от грома


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
	tw.tween_callback(_say.bind("Эксперимент №47 завершён. Результаты внесены в протокол.", 2.6))
	tw.tween_interval(3.3)
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
	sfx.play("thunder", 0.85, 4.0)
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
	if lab and lab.walking:
		step_t -= delta
		if step_t <= 0.0:
			step_t = PI / 7.0
			sfx.play("step", randf_range(0.9, 1.05), -2.0)
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
	lab.look = snake.head_pos
	crackle_t -= delta
	if crackle_t <= 0.0:
		crackle_t = randf_range(0.15, 0.45)
		sfx.play("crackle", randf_range(0.7, 1.3), -8.0)
	if not snake_burnt:
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
	tw_end.tween_interval(1.2)
	tw_end.tween_callback(func() -> void: blur_rect.visible = true)
	tw_end.tween_method(_set_blur, 0.0, 1.0, 3.5)
	tw_end.tween_callback(hud.hide_caption)
	tw_end.tween_interval(0.6)
	tw_end.tween_callback(_finish)


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
	camera.zoom = ZOOM_OUT
	camera.position = CAM_POS
	lab.walking = false
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
