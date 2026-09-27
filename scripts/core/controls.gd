extends RefCounted
## Раскладка управления: клавиатура и мышь. Сенсорное управление — ui/touch_controls.gd.


static func setup() -> void:
	_add_action("turn_left", [KEY_LEFT, KEY_A])
	_add_action("turn_right", [KEY_RIGHT, KEY_D])
	_add_action("sprint", [KEY_SHIFT])
	_add_action("ability", [KEY_SPACE, KEY_F])
	if InputMap.action_get_events("ability").size() == 2:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("ability", mb)
	_add_action("pause", [KEY_ESCAPE, KEY_P])
	_add_action("mute", [KEY_M])
	_add_action("dev_panel", [KEY_F1, KEY_QUOTELEFT])
	# На ноутбуках F1 часто занят яркостью/звуком, а ` — это «ё» на русской раскладке (физическая клавиша
	# та же, поэтому всё равно срабатывает). Запасной вариант, который есть на любой клавиатуре:
	if InputMap.action_get_events("dev_panel").size() == 2:
		var combo := InputEventKey.new()
		combo.physical_keycode = KEY_D
		combo.ctrl_pressed = true
		combo.shift_pressed = true
		InputMap.action_add_event("dev_panel", combo)


static func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
