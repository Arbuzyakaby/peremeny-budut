extends "res://scripts/ui/screens/screen.gd"
## Пауза: сводка забега и три действия. Выход в меню можно подтверждать (настройка confirm_quit).
## Пасхалка: простоишь на паузе минуту — образец №47 уснёт (под сводкой — «Zzz…»).

signal resume_requested
signal settings_requested
signal menu_requested
signal secret_found(id: String)

const SLEEP_TIME := 60.0

var info: Label
var sleep_label: Label
var menu_button: Button
var menu_armed := false
var idle := 0.0


func build() -> void:
	make_frame(Design.SPACE[3])
	title("ПАУЗА", "h1")
	info = Design.label("", "small", Design.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(info)
	sleep_label = Design.label("", "caption", Design.STEEL, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(sleep_label)
	content.add_child(Design.spacer(Design.SPACE[2]))
	first_focus = Design.button("ПРОДОЛЖИТЬ", resume_requested.emit, "Primary", Vector2(320, Design.TOUCH_MIN + 4))
	content.add_child(first_focus)
	content.add_child(Design.button("НАСТРОЙКИ", settings_requested.emit, "", Vector2(320, Design.TOUCH_MIN)))
	menu_button = Design.button("В МЕНЮ", _on_menu, "Ghost", Vector2(320, Design.TOUCH_MIN))
	content.add_child(menu_button)


func show_pause(summary: String) -> void:
	info.text = summary
	menu_armed = false
	menu_button.text = "В МЕНЮ"
	idle = 0.0
	sleep_label.text = ""
	open()


func _process(delta: float) -> void:
	if not visible:
		return
	idle += delta
	if idle >= SLEEP_TIME:
		sleep_label.text = "Образец №47 уснул. Z" + "z".repeat(int(idle) % 3 + 1) + "…"
		if idle - delta < SLEEP_TIME:
			secret_found.emit("sleepy")


func _input(event: InputEvent) -> void:
	if visible and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch):
		idle = 0.0  # кто-то трогает игру — не спим
		sleep_label.text = ""


func _on_menu() -> void:
	if Settings.flag("confirm_quit") and not menu_armed:
		menu_armed = true
		menu_button.text = "ЗАБЕГ ПРОПАДЁТ — ЖМИ ЕЩЁ РАЗ"
		Design.refuse(menu_button)
		return
	menu_requested.emit()


func handle_back() -> bool:
	resume_requested.emit()
	return true
