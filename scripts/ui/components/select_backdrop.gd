class_name SelectBackdrop
extends Control
## Fondo de la selección: collage diagonal con los colores de los escenarios
## y chispas de energía que suben despacio. `parallax` lo desplaza un poco.

var parallax := Vector2.ZERO
var _time := 0.0
var _sparks: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(46):
		_sparks.append(Vector4(rng.randf() * 960.0, rng.randf() * 540.0, 10.0 + rng.randf() * 30.0, rng.randf()))


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.BG)
	var offset := parallax * 0.4
	var stripe_w := 300.0
	for i in range(6):
		var stage: Dictionary = Catalog.STAGES[i % Catalog.STAGES.size()]
		var color := Catalog.color(String(stage["far"])).darkened(0.45)
		color.a = 0.55
		var x0 := -240.0 + i * stripe_w * 0.62 + offset.x
		var pts := PackedVector2Array([
			Vector2(x0, size.y + 20), Vector2(x0 + 160, -20 + offset.y),
			Vector2(x0 + 160 + stripe_w * 0.5, -20 + offset.y), Vector2(x0 + stripe_w * 0.5, size.y + 20),
		])
		draw_colored_polygon(pts, color)
		draw_line(pts[0], pts[1], Catalog.color(String(stage["trim"])) * Color(1, 1, 1, 0.25), 2.0)
	for s in _sparks:
		var spark: Vector4 = s
		var y := fposmod(spark.y - _time * spark.z, size.y + 20.0) - 10.0
		var x := spark.x + sin(_time * 0.8 + spark.w * 6.0) * 6.0 + offset.x * 0.6
		var a := 0.25 + 0.5 * absf(sin(_time * 2.0 + spark.w * 9.0))
		draw_rect(Rect2(x, y, 2, 2), Color(UiKit.ACCENT, a))
	# viñeta
	draw_rect(Rect2(0, 0, size.x, 70), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(0, size.y - 70, size.x, 70), Color(0, 0, 0, 0.35))
