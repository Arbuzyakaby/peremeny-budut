extends "res://tests/test_case.gd"
## Раскладка управления: все действия, физические коды клавиш (работают на любой раскладке),
## три способа открыть панель разработчика, повторная настройка ничего не дублирует.

const ACTIONS := ["turn_left", "turn_right", "sprint", "ability", "pause", "mute", "dev_panel"]


func before_all() -> void:
	Controls.setup()


func _keys(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(ev)
	return out


func _physical(action: String) -> Array:
	return _keys(action).map(func(ev: InputEventKey) -> int: return ev.physical_keycode)


func test_all_actions_exist() -> void:
	for a in ACTIONS:
		assert_true(InputMap.has_action(a), a)
		assert_gt(InputMap.action_get_events(a).size(), 0, a + ": есть привязки")


func test_movement_and_pause_keys() -> void:
	assert_has(_physical("turn_left"), KEY_LEFT)
	assert_has(_physical("turn_left"), KEY_A)
	assert_has(_physical("turn_right"), KEY_RIGHT)
	assert_has(_physical("turn_right"), KEY_D)
	assert_has(_physical("pause"), KEY_ESCAPE)
	assert_has(_physical("pause"), KEY_P)
	assert_has(_physical("mute"), KEY_M)
	assert_has(_physical("sprint"), KEY_SHIFT)


func test_bindings_use_physical_keycodes() -> void:
	for a in ACTIONS:
		for ev: InputEventKey in _keys(a):
			assert_ne(int(ev.physical_keycode), 0, a + ": физический код")
			assert_eq(int(ev.keycode), 0, a + ": без привязки к раскладке")


func test_ability_has_mouse_button() -> void:
	var has_mouse := false
	for ev in InputMap.action_get_events("ability"):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			has_mouse = true
	assert_true(has_mouse, "атака — ЛКМ")
	assert_has(_physical("ability"), KEY_SPACE)
	assert_has(_physical("ability"), KEY_F)


func test_dev_panel_three_ways() -> void:
	assert_has(_physical("dev_panel"), KEY_F1)
	assert_has(_physical("dev_panel"), KEY_QUOTELEFT)  # на русской раскладке это «ё»
	var combo := false
	for ev: InputEventKey in _keys("dev_panel"):
		if ev.physical_keycode == KEY_D and ev.ctrl_pressed and ev.shift_pressed:
			combo = true
	assert_true(combo, "Ctrl+Shift+D")


func test_plain_d_does_not_open_dev_panel() -> void:
	var plain := InputEventKey.new()
	plain.physical_keycode = KEY_D
	plain.pressed = true
	assert_false(InputMap.event_is_action(plain, "dev_panel"), "просто D — поворот, не панель")
	assert_true(InputMap.event_is_action(plain, "turn_right"))
	var combo := plain.duplicate() as InputEventKey
	combo.ctrl_pressed = true
	combo.shift_pressed = true
	assert_true(InputMap.event_is_action(combo, "dev_panel"), "Ctrl+Shift+D — панель")


func test_setup_is_idempotent() -> void:
	var before := {}
	for a in ACTIONS:
		before[a] = InputMap.action_get_events(a).size()
	Controls.setup()
	Controls.setup()
	for a in ACTIONS:
		assert_eq(InputMap.action_get_events(a).size(), before[a], a + ": без дублей")
