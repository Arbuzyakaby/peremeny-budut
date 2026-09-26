extends "res://tests/test_case.gd"
## Общие помощники интеграционных тестов: поднять главную сцену и дождаться нужного состояния.

const Game = preload("res://scripts/game/game.gd")
const MAIN := "res://scenes/main.tscn"

var game: Game


func before_each() -> void:
	use_temp_storage()
	Game.auto_start = false
	Game.difficulty = 1


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0
	if is_instance_valid(game):
		game.queue_free()
	game = null
	await frames(2)


## Главная сцена в меню.
func boot() -> Game:
	game = load(MAIN).instantiate()
	host.add_child(game)
	await wait_state(Game.State.MENU, 30)
	return game


## Сразу забег с этапа stage (отладочный — ничего не сохраняет).
func boot_stage(stage: int, diff := 1) -> Game:
	await boot()
	game.args["stage"] = stage
	game.debug_run = true
	game.start_game(diff)
	await frames(2)
	return game


func wait_state(state: int, max_frames: int) -> bool:
	for i in max_frames:
		if game.state == state:
			return true
		await tree.process_frame
	return game.state == state


## Ждать условия не дольше max_sec реального времени (твины и таймеры идут в реальном времени).
func wait_until(cond: Callable, max_sec := 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < max_sec * 1000.0:
		await tree.process_frame
	return cond.call()


## Прокрутить игру: n кадров по 1/60 с (быстрее реального времени).
func step(n: int) -> void:
	for i in n:
		game._process(1.0 / 60.0)
		if i % 20 == 0:
			await tree.process_frame
