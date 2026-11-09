class_name BookPage
extends Control
## Página del "libro" de selección, dibujada con perspectiva: el borde
## exterior es más bajo que el lomo para que parezca un libro abierto.

@export var side := -1  ## -1 = página izquierda, 1 = página derecha
@export var page_color := Color("#1d3f8f")
@export var title := "ALBA"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var lift := 16.0
	var points: PackedVector2Array
	if side < 0:
		points = PackedVector2Array([Vector2(0, lift), Vector2(w, 0), Vector2(w, h), Vector2(0, h - lift)])
	else:
		points = PackedVector2Array([Vector2(0, 0), Vector2(w, lift), Vector2(w, h - lift), Vector2(0, h)])
	# canto de las hojas
	var edge := PackedVector2Array()
	for p in points:
		edge.append(p + Vector2(side * 6, 6))
	draw_colored_polygon(edge, Color("#e9e1cf"))
	draw_colored_polygon(points, page_color)
	# sombra hacia el lomo
	for i in range(8):
		var t := i / 8.0
		var x := w - 6.0 * (i + 1) if side < 0 else 6.0 * i
		draw_rect(Rect2(x, 0, 6, h), Color(0, 0, 0, 0.22 * (1.0 - t)))
	# tramas decorativas
	for i in range(6):
		var y := 30.0 + i * (h - 60.0) / 5.0
		draw_line(Vector2(14, y), Vector2(w - 14, y), Color(1, 1, 1, 0.04), 2.0)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color("#0a0c14"), 3.0)
	# título de la página
	var font := ThemeDB.fallback_font
	var title_size := 22
	var text_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var tx := (w - text_width) / 2.0
	draw_rect(Rect2(tx - 12, 14, text_width + 24, 30), Color(0, 0, 0, 0.35))
	draw_string_outline(font, Vector2(tx, 37), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, 6, Color("#0a0c14"))
	draw_string(font, Vector2(tx, 37), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color.WHITE)
