class_name HealthBar
extends Control
## Barra de vida estilo arcade con "daño retardado": la parte blanca baja
## despacio después de cada golpe para que se lea cuánto se perdió.

@export var mirrored := false
@export var fill_color := Color("#3f8cff")
@export var max_value := 100.0

var value := 100.0
var _delayed := 100.0
var _hold := 0.0
var _blink := 0.0


func set_value_instant(v: float) -> void:
	value = v
	_delayed = v
	queue_redraw()


func set_value(v: float) -> void:
	if v < value:
		_hold = 0.45
	value = v
	if _delayed < value:
		_delayed = value


func _process(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
	elif _delayed > value:
		_delayed = maxf(value, _delayed - delta * 60.0)
	_blink += delta
	queue_redraw()


func _bar_rect(fraction: float) -> Rect2:
	var inner := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	var w := inner.size.x * clampf(fraction, 0.0, 1.0)
	if mirrored:
		return Rect2(inner.position.x + inner.size.x - w, inner.position.y, w, inner.size.y)
	return Rect2(inner.position, Vector2(w, inner.size.y))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0a0d15"))
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color("#2a3348"), false, 2.0)
	var delayed_color := Color("#fff4d6") if _hold > 0.0 else Color("#ff5a4f")
	draw_rect(_bar_rect(_delayed / max_value), delayed_color)
	var color := fill_color
	var fraction := value / max_value
	if fraction <= 0.25:
		color = Color("#ffcf4a") if fmod(_blink, 0.5) < 0.25 else Color("#ff8a3a")
	var bar := _bar_rect(fraction)
	draw_rect(bar, color)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x, maxf(2.0, bar.size.y * 0.3))), Color(1, 1, 1, 0.25))
	# marcas cada 10 %
	for i in range(1, 10):
		var x := 3.0 + (size.x - 6.0) * i / 10.0
		draw_line(Vector2(x, 3), Vector2(x, size.y - 3), Color(0, 0, 0, 0.25), 1.0)
