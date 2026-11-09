class_name StagePreview
extends Control
## Miniatura animada de un escenario, escalada para cubrir el control.

@export var stage_id := "brumaria":
	set(value):
		stage_id = value
		queue_redraw()
@export var animate := true
@export var show_ground := true

var _time := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if animate:
		_time += delta
		queue_redraw()


func _draw() -> void:
	var stage := Catalog.stage(stage_id)
	var k := maxf(size.x / StagePainter.WIDTH, size.y / 270.0)
	var offset := Vector2((size.x - StagePainter.WIDTH * k) / 2.0, size.y - 270.0 * k)
	draw_set_transform(offset, 0.0, Vector2(k, k))
	StagePainter.draw_background(self, stage, 270.0, _time)
	if show_ground:
		StagePainter.draw_ground(self, stage, 270.0, _time)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
