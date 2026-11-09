class_name FighterPortrait
extends Control
## Retrato animado de un luchador dibujado con FighterPainter.
## Úsalo en cualquier escena: añade un Control, asígnale este script y elige
## el luchador en el inspector (se anima al ejecutar la escena).

enum Crop { FULL, BUST, HEAD }

@export var fighter_id := "brasa":
	set(value):
		fighter_id = value
		_rebuild()
@export var animation := "intro"
@export var crop: Crop = Crop.FULL
@export var facing := 1:
	set(value):
		facing = value
		if _state:
			_state.facing = facing
@export var animate := true
@export var awakened := false
@export var flash := 0.0

var _state: FighterState
var _time := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild()


func _rebuild() -> void:
	if not Catalog.has_fighter(fighter_id):
		return
	_state = FighterState.new(fighter_id, 0.0, facing)
	queue_redraw()


func _process(delta: float) -> void:
	if animate:
		_time += delta
	flash = maxf(0.0, flash - delta)
	queue_redraw()


func _draw() -> void:
	if _state == null:
		return
	_state.awakening_time = 1.0 if awakened else 0.0
	_state.white_flash = flash
	var sprite_scale := float(_state.definition["sprite_scale"])
	var k := 1.0
	var foot := Vector2(size.x / 2.0, size.y * 0.95)
	match crop:
		Crop.FULL:
			k = size.y * 0.86 / (60.0 * sprite_scale)
		Crop.BUST:
			k = size.y * 1.55 / (58.0 * sprite_scale)
			foot = Vector2(size.x / 2.0, size.y * 1.6)
		Crop.HEAD:
			k = size.y * 2.6 / (58.0 * sprite_scale)
			foot = Vector2(size.x / 2.0 + 2.0 * k * facing, size.y * 2.35)
	if crop != Crop.FULL:
		# Los luchadores con imágenes tienen la cara en otro sitio: se recentra.
		var head := FighterPainter.portrait_head_offset(_state.definition) * k * sprite_scale
		foot -= Vector2(head.x * facing, head.y)
	var base := Transform2D(0.0, Vector2(k, k), 0.0, foot)
	var anim := FighterAnimations.get_animation(_state.id, animation)
	var frame := FighterAnimations.frame_at(anim, _time * 60.0)
	frame["name"] = animation
	var body := Catalog.color(String(_state.definition["color"]))
	FighterPainter.draw_body(self, base, 0.0, 0.0, _state, body, frame, _time, animation == "victory")
	draw_set_transform_matrix(Transform2D.IDENTITY)
	FighterPainter.alpha = 1.0
