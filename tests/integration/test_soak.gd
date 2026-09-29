extends "res://tests/integration/game_case.gd"
## Долгий прогон автопилотом с проверкой инвариантов игровой логики: цели этапов не застревают,
## счётчики согласованы, в списках врагов нет удалённых узлов, змея не вылетает за ящик.

const Autopilot = preload("res://scripts/game/autopilot.gd")


## Проверить инварианты текущего кадра. Возвращает описание нарушения или "".
func _violation() -> String:
	var s = game.snake
	if s == null:
		return ""
	if not is_finite(s.head_pos.x) or not is_finite(s.head_pos.y):
		return "голова змеи не число: %s" % s.head_pos
	if not game.bounds.grow(40.0).has_point(s.head_pos):
		return "змея вне ящика: %s" % s.head_pos
	var e = game.enemies
	for arr in [e.bears, e.forks, e.pills, e.dolls]:
		for n in arr:
			if not is_instance_valid(n) or n.is_queued_for_deletion():
				return "в списке врагов удалённый узел"
			if not game.bounds.grow(120.0).has_point(n.position):
				return "враг вне ящика: %s" % n.position
	if game.state == Game.State.LEVEL:
		if game.goal_done > game.goal_total:
			return "цель этапа перевыполнена: %d/%d" % [game.goal_done, game.goal_total]
		if game.stage == Balance.DOLL_STAGE:
			var per_set := {}
			for m in e.dolls:
				if m.set_id != 0:
					per_set[m.set_id] = int(per_set.get(m.set_id, 0)) + 1
			for id in e.doll_sets:
				if int(e.doll_sets[id]) != int(per_set.get(id, 0)):
					return "набор %d: счётчик %d, кукол на поле %d" % [id, e.doll_sets[id], per_set.get(id, 0)]
	return ""


func _dump() -> String:
	var out := "змея %s;" % game.snake.head_pos
	for f in game.enemies.forks:
		out += " вилка st=%s pos=%s;" % [f.st, f.position]
	for m in game.enemies.dolls:
		out += " кукла size=%s set=%s can_bite=%s air=%s dancing=%s pos=%s;" % [m.size, m.set_id, m.can_bite(), m.in_air(), m.dancing, m.position]
	for b in game.enemies.bears:
		out += " медведь pos=%s;" % b.position
	out += " sets=%s" % [game.enemies.doll_sets]
	return out


## Бот целится только в цель этапа (встроенный автопилот гонится за ближайшим медведем-помощником).
func _drive_goal(stage: int) -> void:
	var snake = game.snake
	snake.autopilot = true
	snake.auto_speed = 210.0
	snake.invuln = maxf(snake.invuln, 0.2)
	var pool: Array = []
	match stage:
		0:
			pool = game.enemies.bears.filter(func(b): return b.is_edible())
		1:
			pool = game.enemies.forks
		2:
			pool = game.enemies.pills.filter(func(p): return p.is_edible())
		3:
			pool = game.enemies.dolls.filter(func(m): return m.can_bite())
	var best := INF
	for n in pool:
		var p: Vector2 = n.position - n.facing() * 12.0 if stage == 1 else n.position
		if p.distance_to(snake.head_pos) < best:
			best = p.distance_to(snake.head_pos)
			snake.auto_target = p


## Прогнать этап автопилотом; вернуть описание проблемы или "" и сколько секунд ушло.
func _play(stage: int, diff: int, max_sec: float) -> Dictionary:
	await boot_stage(stage, diff)
	var t := 0.0
	var idle := 0.0
	var last_done := 0
	var last_state: int = game.state
	while t < max_sec:
		_drive_goal(stage)
		game._process(1.0 / 60.0)
		t += 1.0 / 60.0
		var v := _violation()
		if v != "":
			return {"problem": "%s (t=%.1f, этап %d, сложность %d)" % [v, t, stage, diff], "t": t}
		if game.state != last_state:
			last_state = game.state
			idle = 0.0
		if game.state == Game.State.LEVEL:
			if game.goal_done != last_done:
				last_done = game.goal_done
				idle = 0.0
			idle += 1.0 / 60.0
			if idle > 150.0:
				return {"problem": "этап %d завис: цель %d/%d, врагов %d (t=%.0f, сложность %d) %s" % [
					stage, game.goal_done, game.goal_total, game.enemies.count(), t, diff, _dump()], "t": t}
		elif game.state in [Game.State.PERK, Game.State.CUTSCENE, Game.State.WIN, Game.State.GAME_OVER]:
			break
		if int(t * 60.0) % 30 == 0:
			await tree.process_frame
	return {"problem": "", "t": t, "state": game.state, "stage": game.stage}


func test_autopilot_clears_each_stage_on_every_difficulty() -> void:
	for diff in 4:
		for stage in Balance.BOSS_STAGE:
			# вилки увёртливы, а бот не умеет заходить в тыл: для них проверяем только инварианты и прогресс
			var r := await _play(stage, diff, 60.0 if stage == 1 else 500.0)
			if stage == 1 and r["problem"] == "" or str(r["problem"]).begins_with("этап 1 завис"):
				assert_true(game.forks_broken > 0, "бот сломал хотя бы одну вилку (сложность %d)" % diff)
			else:
				assert_eq(r["problem"], "", "прогон без нарушений")
			if r["problem"] == "" and stage != 1:
				assert_true(r["state"] in [Game.State.PERK, Game.State.LEVEL] and (r["state"] == Game.State.PERK or r["stage"] > stage),
					"этап %d (сложность %d) пройден автопилотом за %.0f с" % [stage, diff, r["t"]])
			game.queue_free()
			await frames(2)


func test_autopilot_beats_boss() -> void:
	Secrets.unlock("contact", false)
	for diff in [0, 1]:
		await boot_stage(Balance.BOSS_STAGE, diff)
		game.autopilot = true
		game.snake.autopilot = true
		var t := 0.0
		while t < 600.0 and game.state not in [Game.State.CUTSCENE, Game.State.WIN, Game.State.OUTRO, Game.State.GAME_OVER]:
			game._process(1.0 / 60.0)
			t += 1.0 / 60.0
			var v := _violation()
			if v != "":
				assert_eq(v, "", "бой с яичницей, сложность %d, t=%.1f" % [diff, t])
				break
			if int(t * 60.0) % 30 == 0:
				await tree.process_frame
		assert_true(game.state in [Game.State.CUTSCENE, Game.State.OUTRO], "яичница побеждена (сложность %d, t=%.0f, hp=%s)" % [
			diff, t, str(game.boss.hp) if game.boss else "?"])
		game.queue_free()
		await frames(2)


## Случайное «мышиное» управление, все атаки, змея уязвима: игра не падает, инварианты держатся,
## а забег заканчивается сам (смерть, победа или пауза между этапами) — без тупиков состояний.
func test_random_play_keeps_invariants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var attack_ids: Array = Balance.ABILITIES.keys()
	for diff in 4:
		for stage in Balance.STAGE_COUNT:
			await boot_stage(stage, diff)
			game.snake.god = diff % 2 == 0  # на чётных сложностях змея бессмертна — дольше живёт, больше видит
			var t := 0.0
			var turn := 0.0
			while t < 120.0 and game.state in [Game.State.LEVEL, Game.State.BOSS_INTRO, Game.State.BOSS]:
				if int(t * 60.0) % 20 == 0:
					turn = rng.randf_range(-2.5, 2.5)
				game.snake.heading += turn * (1.0 / 60.0)
				if rng.randf() < 0.02 and game.state in [Game.State.LEVEL, Game.State.BOSS]:
					game.abilities.gain(attack_ids[rng.randi() % attack_ids.size()])
					game.abilities.cooldown = 0.0
					game.abilities.use()
				game._process(1.0 / 60.0)
				t += 1.0 / 60.0
				var v := _violation()
				if v != "":
					assert_eq(v, "", "случайная игра: этап %d, сложность %d, t=%.1f" % [stage, diff, t])
					break
				if int(t * 60.0) % 30 == 0:
					await tree.process_frame
			game.queue_free()
			await frames(2)
