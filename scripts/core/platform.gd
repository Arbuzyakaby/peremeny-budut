extends RefCounted
## Всё, что зависит от устройства: телефон или ПК, сенсорный экран, безопасная зона (вырез камеры),
## вибрация. Флаг `-- --touch` включает мобильный режим на ПК для проверки.

static var force_touch := false
static var force_mobile := false


static func is_mobile() -> bool:
	return force_mobile or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


static func has_touchscreen() -> bool:
	if force_touch:
		return true
	return DisplayServer.get_name() != "headless" and DisplayServer.is_touchscreen_available()


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Отступы безопасной зоны в координатах вьюпорта: x — слева, y — сверху, z — справа, w — снизу.
static func safe_margins(vp: Viewport) -> Vector4:
	if is_headless() or not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0:
		return Vector4.ZERO
	var vis := vp.get_visible_rect().size
	var k := vis / Vector2(win)
	return Vector4(
		maxf(safe.position.x, 0.0) * k.x,
		maxf(safe.position.y, 0.0) * k.y,
		maxf(win.x - safe.end.x, 0.0) * k.x,
		maxf(win.y - safe.end.y, 0.0) * k.y)


## Короткая вибрация (только телефон и только если включена в настройках).
static func vibrate(ms: int, enabled: bool) -> void:
	if enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


static func renderer_name() -> String:
	return str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))


static func describe() -> String:
	var kind := "телефон" if is_mobile() else "ПК"
	return "%s • %s • %s" % [OS.get_name(), kind, renderer_name()]
