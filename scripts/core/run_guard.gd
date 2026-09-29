extends RefCounted
## Страж забега (v11.0): замечает то, что панель разработчика не отмечает сама, — правку счёта в памяти
## (сканеры вроде Cheat Engine), ускорение или замедление времени программой-«спидхаком» и смену
## Engine.time_scale в обход панели. Заметил — забег становится отладочным: рекорд и чешуйки не пишутся,
## а в итогах видна причина. Никаких блокировок и отправок: только честный счёт.
##
## - Счёт хранится ещё и в «тени»: score XOR случайный ключ плюс контрольная сумма. Чтобы подделать
##   рекорд, мало найти число в памяти — тень с ним не сойдётся.
## - Два независимых часа: монотонные (Time.get_ticks_usec — их подменяет спидхак) и системные часы
##   (Time.get_unix_time_from_system). Раз в WINDOW секунд сверяется скорость; расхождение больше
##   чем на SPEED_TOL два окна подряд — время подменено. Скачок системных часов больше CLOCK_JUMP
##   (перевели время, синхронизация) — просто новое начало отсчёта, это не чит.

const WINDOW := 5.0
const SPEED_TOL := 0.12
const CLOCK_JUMP := 30.0

var reason := ""          # непусто — забег нечестный (строка для итогов)
var _key := 0
var _shadow := 0
var _check := 0
var _mono0 := 0
var _wall0 := 0.0
var _strikes := 0


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_key = rng.randi() | (rng.randi() << 31)
	note_score(0)
	_restart_clocks()


func flagged() -> bool:
	return reason != ""


func flag(why: String) -> void:
	if reason == "":
		reason = why


## Счёт изменился законно (game.add_score_raw) — обновить тень.
func note_score(score: int) -> void:
	_shadow = score ^ _key
	_check = _hash(score)


## Совпадает ли счёт с тенью. Не совпал — отмечает забег.
func verify(score: int) -> bool:
	if (_shadow ^ _key) != score or _hash(score) != _check:
		flag("счёт изменён в памяти")
		return false
	return true


func _hash(v: int) -> int:
	return hash([v, _key, "peremeny-budut"])


## Каждый кадр боя: сверка часов и масштаба времени.
func tick(time_scale: float) -> void:
	if not is_equal_approx(time_scale, 1.0):
		flag("скорость времени изменена (%.2f×)" % time_scale)
	var mono := Time.get_ticks_usec()
	var wall := Time.get_unix_time_from_system()
	var d_wall := wall - _wall0
	if d_wall < 0.0 or d_wall > CLOCK_JUMP:  # часы перевели — это не чит, считаем заново
		_restart_clocks()
		return
	if d_wall < WINDOW:
		return
	check_rate((mono - _mono0) / 1_000_000.0, d_wall)
	_restart_clocks()


## Одно окно сверки: сколько прошло по монотонным часам и по системным.
func check_rate(d_mono: float, d_wall: float) -> void:
	var rate := d_mono / maxf(d_wall, 0.001)
	if absf(rate - 1.0) > SPEED_TOL:
		_strikes += 1
		if _strikes >= 2:
			flag("время игры идёт в %.2f раза %s настоящего" % [rate if rate > 1.0 else 1.0 / rate,
				"быстрее" if rate > 1.0 else "медленнее"])
	else:
		_strikes = 0


func _restart_clocks() -> void:
	_mono0 = Time.get_ticks_usec()
	_wall0 = Time.get_unix_time_from_system()
