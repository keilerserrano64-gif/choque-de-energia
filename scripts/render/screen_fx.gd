class_name ScreenFx
extends ColorRect
## Capa de pantalla completa con screen_fx.gdshader. Fight la avisa de los golpes
## pesados, despertares y K.O.; aquí se animan los parámetros del shader.
## El nodo se oculta cuando no hay ningún efecto activo, así que fuera de esos
## momentos no cuesta nada de GPU.

const SHADER := preload("res://shaders/screen_fx.gdshader")
const SHOCK_DURATION := 0.42  ## segundos que tarda la onda en abrirse
const SHOCK_MAX_RADIUS := 0.5  ## radio final de la onda (en anchos de pantalla)
const KO_HOLD := 1.4  ## segundos que dura el K.O. a tope antes de desvanecerse

var _shader_material: ShaderMaterial
var _shock_time := -1.0
var _shock_strength := 0.0
var _impact_time := 0.0
var _aberration := 0.0
var _tint_amount := 0.0
var _ko := 0.0
var _ko_hold := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = SHADER
	material = _shader_material
	visible = false


## Onda expansiva desde `uv` (coordenadas de pantalla 0..1). strength 0..1.
func shockwave(uv: Vector2, strength: float) -> void:
	if not SaveData.screen_effects:
		return
	_shock_time = 0.0
	_shock_strength = clampf(strength, 0.0, 1.0)
	_shader_material.set_shader_parameter("shock_center", uv)
	_aberration = maxf(_aberration, 0.012 * strength)


## Unos cuadros de imagen a dos tonos, como en el anime, para los golpes más fuertes.
func impact_frame(color: Color, duration: float = 0.07) -> void:
	if not SaveData.screen_effects:
		return
	_impact_time = maxf(_impact_time, duration)
	_shader_material.set_shader_parameter("impact_color", color)


## Tinte de color y separación cromática breves (despertar).
func pulse(color: Color, amount: float) -> void:
	if not SaveData.screen_effects:
		return
	_shader_material.set_shader_parameter("tint", color)
	_tint_amount = maxf(_tint_amount, amount)
	_aberration = maxf(_aberration, 0.014)


## K.O.: la imagen pierde color y se oscurecen los bordes; luego vuelve sola.
func knockout() -> void:
	if not SaveData.screen_effects:
		return
	_ko = 1.0
	_ko_hold = KO_HOLD
	_aberration = maxf(_aberration, 0.016)


func clear() -> void:
	_shock_time = -1.0
	_impact_time = 0.0
	_aberration = 0.0
	_tint_amount = 0.0
	_ko = 0.0
	_ko_hold = 0.0
	visible = false


func _process(delta: float) -> void:
	var active := false
	var shock_strength := 0.0
	if _shock_time >= 0.0:
		_shock_time += delta
		var progress := _shock_time / SHOCK_DURATION
		if progress >= 1.0:
			_shock_time = -1.0
		else:
			# La onda se abre rápido al principio y pierde fuerza al crecer.
			var eased := 1.0 - pow(1.0 - progress, 2.0)
			_shader_material.set_shader_parameter("shock_radius", eased * SHOCK_MAX_RADIUS)
			shock_strength = _shock_strength * (1.0 - progress)
			active = true
	_impact_time = maxf(0.0, _impact_time - delta)
	_aberration = move_toward(_aberration, 0.0, delta * 0.045)
	_tint_amount = move_toward(_tint_amount, 0.0, delta * 0.7)
	if _ko_hold > 0.0:
		_ko_hold -= delta
	else:
		_ko = move_toward(_ko, 0.0, delta * 1.5)

	var impact := 0.85 if _impact_time > 0.0 else 0.0
	_shader_material.set_shader_parameter("shock_strength", shock_strength)
	_shader_material.set_shader_parameter("aberration", _aberration)
	_shader_material.set_shader_parameter("impact", impact)
	_shader_material.set_shader_parameter("tint_amount", _tint_amount)
	_shader_material.set_shader_parameter("desaturate", _ko * 0.75)
	_shader_material.set_shader_parameter("vignette", _ko)
	if size.y > 0.0:
		_shader_material.set_shader_parameter("aspect", size.x / size.y)
	active = active or impact > 0.0 or _aberration > 0.0 or _tint_amount > 0.0 or _ko > 0.0
	visible = active
