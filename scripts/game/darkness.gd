extends ColorRect
## Модификатор испытания «Темнота»: лампа над ящиком погасла, видно только пятно света вокруг
## головы змеи (с мягким краем и лёгким мерцанием, как от фонарика).

const SHADER := """
shader_type canvas_item;
uniform vec2 center = vec2(640.0, 360.0);
uniform float radius = 190.0;
void fragment() {
	vec2 px = UV * vec2(1280.0, 720.0);
	float d = distance(px, center);
	float flicker = 1.0 + 0.03 * sin(TIME * 11.0) + 0.02 * sin(TIME * 23.0);
	float dark = smoothstep(radius * 0.45 * flicker, radius * flicker, d);
	COLOR = vec4(0.01, 0.005, 0.0, dark * 0.95);
}
"""

var radius := 190.0


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("radius", radius)
	material = m


func follow(head: Vector2) -> void:
	(material as ShaderMaterial).set_shader_parameter("center", head)
