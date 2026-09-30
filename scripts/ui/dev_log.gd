extends Logger
## Журнал ошибок для панели разработчика (v12.2): перехватывает ошибки и предупреждения движка и скриптов,
## чтобы их было видно прямо в игре, без консоли. Ставится один раз на процесс (DevLog.install()).

const MAX_LINES := 60

static var shared: Logger

var lines: PackedStringArray = PackedStringArray()
var errors := 0
var warnings := 0
var _mutex := Mutex.new()


static func install() -> Logger:
	if shared == null:
		shared = load("res://scripts/ui/dev_log.gd").new()
		OS.add_logger(shared)
	return shared


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
	var warn := error_type == Logger.ERROR_TYPE_WARNING
	_mutex.lock()
	if warn:
		warnings += 1
	else:
		errors += 1
	lines.append("%s %s:%d — %s" % ["⚠" if warn else "✖", file.get_file(), line, rationale if rationale != "" else code])
	if lines.size() > MAX_LINES:
		lines.remove_at(0)
	_mutex.unlock()


func snapshot() -> String:
	_mutex.lock()
	var text := "\n".join(lines)
	_mutex.unlock()
	return text


func clear() -> void:
	_mutex.lock()
	lines.clear()
	errors = 0
	warnings = 0
	_mutex.unlock()
