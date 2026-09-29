extends RefCounted
## Материалы дизайн-языка 2.0: процедурные текстуры поверхностей (шум — волокна дерева, крап бакелита,
## шлифовка латуни, накатка) и палитры материалов. Текстуры — NoiseTexture2D с градиентом: считаются
## движком в фоне и кэшируются, одинаково работают на Forward+ и Compatibility.

## LACQUER (2.3) — киноварь под толстым лаком с золотой каймой, как у матрёшек и хохломы.
enum Kind { BAKELITE, BRASS, CHROME, WOOD, ENAMEL, PAPER, VELVET, RUBBER, LACQUER }

## Палитра: [светлый край/блик, основной, тень/кромка]. Цвет смысла (золото, томат) подмешивается сверху.
const PALETTE := {
	Kind.BAKELITE: [Color(0.36, 0.25, 0.17), Color(0.2, 0.13, 0.085), Color(0.07, 0.045, 0.03)],
	Kind.BRASS: [Color(1.0, 0.9, 0.58), Color(0.86, 0.64, 0.25), Color(0.42, 0.27, 0.08)],
	Kind.CHROME: [Color(0.98, 0.98, 1.0), Color(0.66, 0.68, 0.72), Color(0.25, 0.26, 0.3)],
	Kind.WOOD: [Color(0.4, 0.26, 0.15), Color(0.23, 0.14, 0.08), Color(0.09, 0.055, 0.03)],
	Kind.ENAMEL: [Color(1.0, 0.5, 0.42), Color(0.78, 0.2, 0.16), Color(0.36, 0.07, 0.05)],
	Kind.PAPER: [Color(1.0, 0.98, 0.92), Color(0.95, 0.9, 0.78), Color(0.7, 0.62, 0.48)],
	Kind.VELVET: [Color(0.3, 0.07, 0.09), Color(0.18, 0.04, 0.06), Color(0.07, 0.01, 0.02)],
	Kind.RUBBER: [Color(0.22, 0.2, 0.19), Color(0.12, 0.11, 0.1), Color(0.04, 0.035, 0.03)],
	Kind.LACQUER: [Color(0.98, 0.42, 0.32), Color(0.72, 0.1, 0.07), Color(0.28, 0.03, 0.02)],
}
## Золотая кайма лака (2.3).
const LACQUER_GOLD := Color(0.98, 0.78, 0.28)

static var _textures: Dictionary = {}


static func palette(kind: int) -> Array:
	return PALETTE.get(kind, PALETTE[Kind.BAKELITE])


## Текстура поверхности материала (серая, накладывается поверх цвета с малой непрозрачностью).
static func texture(kind: int) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var n := FastNoiseLite.new()
	n.seed = 7 + kind * 13
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	match kind:
		Kind.WOOD:  # волокна: сильно вытянутый шум с искажением
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n.frequency = 0.012
			n.fractal_octaves = 4
			n.domain_warp_enabled = true
			n.domain_warp_amplitude = 30.0
			tex.width = 512
			tex.height = 64
		Kind.BRASS, Kind.CHROME:  # шлифовка: мелкий шум, растягивается вдоль
			n.noise_type = FastNoiseLite.TYPE_VALUE
			n.frequency = 0.35
			n.fractal_octaves = 2
			tex.width = 512
			tex.height = 32
		Kind.BAKELITE:  # мелкий крап наполнителя
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.frequency = 0.32
			n.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
		Kind.RUBBER:  # матовая шероховатость
			n.noise_type = FastNoiseLite.TYPE_VALUE
			n.frequency = 0.6
		Kind.LACQUER:  # лак: едва заметные наплывы
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n.frequency = 0.02
			n.fractal_octaves = 2
		Kind.PAPER, Kind.VELVET:  # волокна бумаги / ворс
			n.noise_type = FastNoiseLite.TYPE_PERLIN
			n.frequency = 0.08
			n.fractal_octaves = 5
		_:
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX
			n.frequency = 0.05
	tex.noise = n
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0, 0, 0))
	ramp.set_color(1, Color(1, 1, 1))
	tex.color_ramp = ramp
	_textures[kind] = tex
	return tex


static func clear_cache() -> void:
	_textures.clear()
