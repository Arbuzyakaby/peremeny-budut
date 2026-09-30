extends SceneTree
## Замер производительности: godot --path . -s res://tests/bench.gd [-- --stage=N --sec=8]
## Нужно окно (не --headless): показывает время кадра, CPU-часть игры и число вызовов отрисовки.

const Game = preload("res://scripts/game/game.gd")

var _stage := -1
var _sec := 8.0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			_stage = int(a.get_slice("=", 1))
		elif a == "--raw":
			_stage = -2
		elif a.begins_with("--sec="):
			_sec = float(a.get_slice("=", 1))
	_main.call_deferred()


func _main() -> void:
	var stages := [_stage] if _stage != -1 else [0, 1, 2, 3, 4]
	for st in stages:
		await _run(st)
	Game._on_quit()
	quit(0)


func _run(stage: int) -> void:
	Game.auto_start = false
	Game.difficulty = 1
	var tb := Time.get_ticks_usec()
	var mem0 := OS.get_static_memory_usage()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var boot_frames := 0
	while game.state == Game.State.LOADING and boot_frames < 200000 and Time.get_ticks_usec() - tb < 60000000:
		await process_frame
		boot_frames += 1
	print("  загрузка до меню: %.0f мс, %d кадров, память +%.1f МБ, узлов %d" % [
		(Time.get_ticks_usec() - tb) / 1000.0, boot_frames, (OS.get_static_memory_usage() - mem0) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	for i in 60:
		await process_frame
	if stage >= 0:
		game.args["stage"] = stage
		game.debug_run = true
		game.start_game(1)
		game.snake.autopilot = true
		game.snake.invuln = 1e9
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--hidescript="):
			var want := a.get_slice("=", 1)
			var st2: Array = [game]
			var hid := 0
			while not st2.is_empty():
				var nd2: Node = st2.pop_back()
				var sc2 = nd2.get_script()
				if nd2 is CanvasItem and sc2 and sc2.resource_path.get_file() == want:
					nd2.visible = false
					hid += 1
				else:
					st2.append_array(nd2.get_children())
			print("hidden ", hid)
		if a.begins_with("--hide="):
			var nm := a.get_slice("=", 1)
			var nd: Node = game.get_child(int(nm)) if nm.is_valid_int() else game.find_child(nm, true, false)
			print("hide ", nm, " -> ", nd)
			if nd:
				nd.visible = false
	if OS.get_cmdline_user_args().has("--tree"):
		for c in game.get_children():
			for g in c.get_children():
				print("     sub ", g.name, " ", g.get_script().resource_path.get_file() if g.get_script() else g.get_class(), " kids=", g.get_child_count())
			print("  child ", c.name, " ", c.get_class(), " kids=", c.get_child_count(), " vis=", c.get("visible"))
	var frames := 0
	var t_all := 0.0
	var worst := 0.0
	var proc := 0.0
	var draws := 0.0
	var objs := 0.0
	var prims := 0.0
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var gpu := 0.0
	var cpu := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	while (Time.get_ticks_usec() - t0) < _sec * 1e6:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		if frames > 30:
			t_all += dt
			worst = maxf(worst, dt)
			proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			objs += Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		frames += 1
	var n := maxf(frames - 30, 1)
	var cnt := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		var sc = nd.get_script()
		var key: String = (sc.resource_path.get_file() if sc else nd.get_class())
		if nd is CanvasItem and (nd as CanvasItem).visible == false:
			key += "(hidden)"
		cnt[key] = cnt.get(key, 0) + 1
		stack.append_array(nd.get_children())
	var arr := cnt.keys()
	arr.sort_custom(func(x, y): return cnt[x] > cnt[y])
	var s := ""
	for k in arr.slice(0, 14):
		s += " %s=%d" % [k, cnt[k]]
	print("  узлы:", s)
	print("этап %d: кадр %.2f мс (худший %.1f), render cpu %.2f gpu %.2f мс, draw calls %.0f, примитивов %.0f, узлов %.0f, fps %.0f" % [
		stage, t_all / n, worst, cpu / n, gpu / n, draws / n, prims / n, objs / n, Engine.get_frames_per_second()])
	game.queue_free()
	for i in 5:
		await process_frame
