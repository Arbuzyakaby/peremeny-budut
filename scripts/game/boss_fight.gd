extends RefCounted
## Бой с Гигантской Яичницей: появление (падает сверху), сигналы босса (выстрелы, волны, укусы,
## фазы с рёвом, открытый желток, окна наказания) и победа, после которой начинается финал.

const Balance = preload("res://scripts/core/balance.gd")
const FriedEggBoss = preload("res://scripts/entities/fried_egg_boss.gd")

var g  # game.gd
var boss: FriedEggBoss
var yolk_hints := 0
var daze_hinted := {}


func _init(game) -> void:
	g = game


func begin() -> FriedEggBoss:
	g.hud.set_iron(true, heat_for(1))  # этап яичницы: таблички и лента из чугуна (2.4)
	g.arena.set_heat(heat_for(1))       # сковорода на огне: жар растёт с фазой
	g.hud.show_banner("ЯИЧНИЦА ПРИБЛИЖАЕТСЯ!", Color(1, 0.55, 0.25), 2.2)
	g.sfx.play_music("")
	g.sfx.play("phase")
	g.add_shake(6.0)
	boss = FriedEggBoss.new()
	boss.bounds = g.bounds
	boss.configure(g.cfg["boss_hp"], g.cfg["proj_speed"], g.cfg["yolk_time"], g.cfg["tempo"])
	boss.bite_damage = 2 if g.mods.get("jaws", false) else 1
	boss.z_index = 0
	boss.position = Vector2(640, -300)
	boss.shoot.connect(func(pos: Vector2, v: Vector2, kind: int) -> void: g.shots.spawn_drop(pos, v, kind))
	boss.shockwave.connect(_on_shockwave)
	boss.sound.connect(g.sfx.play)
	boss.bitten.connect(_on_bitten)
	boss.phase_changed.connect(_on_phase)
	boss.yolk_opened.connect(_on_yolk_opened)
	boss.dazed.connect(_on_dazed)
	boss.defeated.connect(_on_defeated)
	g.world.add_child(boss)
	var tw: Tween = g.create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(boss, "position", Vector2(640, 300), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_on_landed)
	tw.tween_interval(1.0)
	tw.tween_callback(g.on_boss_ready)
	return boss


func _on_landed() -> void:
	if g.state != g.State.BOSS_INTRO:  # змея погибла (бортик) или забег закрыт, пока яичница падала
		return
	g.add_shake(22.0)
	g.vibrate(120)
	g.sfx.play("slam")
	g.sfx.play_music("boss")
	g.fx.burst(boss.position, Color(1, 1, 0.9), 40)
	g.fx.burst(boss.position, Color(1, 0.8, 0.1), 25)
	g.hud.set_boss(true, boss.hp, boss.max_hp, 1)
	var snake = g.snake
	if snake.head_pos.distance_to(boss.position) < FriedEggBoss.WHITE_RADIUS:
		snake.push((snake.head_pos - boss.position).normalized() * 700.0)


## Накал чугуна табличек по фазе яичницы: 0,2 → 0,6 → 1,0.
static func heat_for(phase: int) -> float:
	return 0.2 + 0.4 * float(clampi(phase, 1, 3) - 1)


func _on_shockwave(pos: Vector2, gaps: int) -> void:
	g.shots.spawn_boss_wave(pos, gaps)
	g.add_shake(18.0)
	g.fx.burst(pos, Color(1, 0.95, 0.8), 30)


func _on_bitten(hp_left: int) -> void:
	g.add_score(Balance.YOLK_POINTS, boss.position + FriedEggBoss.YOLK_OFFSET + Vector2(0, -60))
	g.hud.set_boss(true, hp_left, boss.max_hp, boss.phase())
	g.add_shake(12.0)
	g.vibrate(40)
	g.sfx.play("bite", 0.9)
	g.fx.burst(boss.position + FriedEggBoss.YOLK_OFFSET, Color(1, 0.8, 0.1), 20)


func _on_phase(phase: int) -> void:
	g.sfx.play("phase")
	g.add_shake(16.0)
	g.vibrate(80)
	g.fx.burst(boss.position, Color(1, 1, 1), 30, 1.3)  # пар от рёва
	g.shots.cut_enemy_drops(boss.position, 1600.0, false, Color(1, 0.95, 0.8))  # рёв сдувает масло с поля
	g.hud.set_iron(true, heat_for(phase))
	g.arena.set_heat(heat_for(phase))
	if phase == 2:
		g.hud.show_banner("ЯИЧНИЦА ПОДГОРАЕТ! Прыгает и плюётся горящим маслом", Color(1, 0.55, 0.1))
	else:
		g.hud.show_banner("ЯИЧНИЦА ПРИГОРЕЛА! В ярости: быстрее и злее", Color(1, 0.25, 0.15))


## Окно наказания: таран в бортик или прыжок — яичница оглушена, желток открыт.
func _on_dazed(reason: String) -> void:
	g.add_shake(14.0 if reason == "wall" else 8.0)
	g.fx.burst(boss.position + FriedEggBoss.YOLK_OFFSET, Color(1, 0.9, 0.3), 16)
	if not daze_hinted.has(reason) and g.hints_on():
		daze_hinted[reason] = true
		var text := "КУСАЙ ЖЕЛТОК! Врезалась в бортик и оглушена" if reason == "wall" else "КУСАЙ ЖЕЛТОК! Увязла в сковороде"
		g.hud.show_banner(text, Color(1, 0.9, 0.2), 1.5)


func _on_yolk_opened() -> void:
	g.hud.shade_accent(1.0)  # один акцент на экран: желток на арене, табло — в тень
	if boss.act == FriedEggBoss.Act.DAZED:
		return  # у окна наказания своя подсказка
	if yolk_hints < 2 and g.hints_on():
		yolk_hints += 1
		g.hud.show_banner("ЖЕЛТОК ОТКРЫТ — КУСАЙ!", Color(1, 0.9, 0.2), 1.5)


func _on_defeated() -> void:
	print("boss defeated, score=", g.score)
	g.on_boss_defeated()
	g.add_score(Balance.BOSS_POINTS, boss.position + Vector2(0, -90), "ЯИЧНИЦА СЪЕДЕНА! ")
	g.hud.set_boss(true, 0, boss.max_hp, 3)
	g.add_shake(30.0)
	g.vibrate(200)
	g.sfx.play_music("")
	g.sfx.play("boss_down")
	g.create_tween().tween_method(g.arena.set_heat, g.arena.heat, 0.0, 1.6)  # сковорода остывает
	for i in 4:
		g.fx.burst(boss.position + Vector2.from_angle(i * TAU / 4) * 60.0, Color(1, 1, 0.95), 30)
	g.fx.burst(boss.position, Color(1, 0.75, 0.05), 60)
	var tw: Tween = g.create_tween()
	tw.tween_property(boss, "scale", Vector2(1.4, 1.4), 0.6)
	tw.parallel().tween_property(boss, "modulate:a", 0.0, 0.6)
	tw.tween_interval(1.0)
	tw.tween_callback(g.start_ending)
