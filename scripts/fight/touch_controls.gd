class_name TouchControls
extends Node2D
## Botones táctiles para móviles (solo aparecen en pantallas táctiles).
## Usan TouchScreenButton, que activa directamente las acciones p1_* del
## InputMap, así que el combate no necesita código especial para el táctil.

const BUTTONS := [
	{"action": "p1_left", "label": "<", "pos": Vector2(80, 452), "radius": 44.0, "passby": true},
	{"action": "p1_right", "label": ">", "pos": Vector2(190, 452), "radius": 44.0, "passby": true},
	{"action": "p1_run", "label": ">>", "pos": Vector2(135, 365), "radius": 30.0, "passby": true},
	{"action": "p1_down", "label": "v", "pos": Vector2(135, 515), "radius": 28.0, "passby": true},
	{"action": "p1_jump", "label": "^", "pos": Vector2(770, 360), "radius": 38.0, "passby": false},
	{"action": "p1_block", "label": "E", "pos": Vector2(245, 365), "radius": 30.0, "passby": true},
	{"action": "p1_attack", "label": "PU", "pos": Vector2(700, 470), "radius": 40.0, "passby": false},
	{"action": "p1_kick", "label": "PA", "pos": Vector2(800, 470), "radius": 40.0, "passby": false},
	{"action": "p1_heavy", "label": "I", "pos": Vector2(640, 395), "radius": 32.0, "passby": false},
	{"action": "p1_special", "label": "L", "pos": Vector2(890, 410), "radius": 38.0, "passby": false},
	{"action": "p1_awaken", "label": "H", "pos": Vector2(880, 320), "radius": 32.0, "passby": false},
	{"action": "pause", "label": "II", "pos": Vector2(480, 110), "radius": 22.0, "passby": false},
]


class Glyph extends Node2D:
	var text := ""
	var radius := 40.0
	var button: TouchScreenButton

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var pressed := button != null and button.is_pressed()
		var fill := Color(0.4, 0.85, 1.0, 0.45) if pressed else Color(0.06, 0.08, 0.13, 0.45)
		draw_circle(Vector2.ZERO, radius, fill)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(0.75, 0.9, 1.0, 0.7), 3.0)
		var font := ThemeDB.fallback_font
		var font_size := int(radius * 0.8)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(-width / 2.0, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.9))


func _ready() -> void:
	visible = DisplayServer.is_touchscreen_available()
	if not visible:
		return
	for data in BUTTONS:
		var button := TouchScreenButton.new()
		var shape := CircleShape2D.new()
		shape.radius = float(data["radius"])
		button.shape = shape
		button.shape_centered = true
		button.action = String(data["action"])
		button.passby_press = bool(data["passby"])
		button.visibility_mode = TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY
		button.position = data["pos"]
		add_child(button)
		var glyph := Glyph.new()
		glyph.text = String(data["label"])
		glyph.radius = float(data["radius"])
		glyph.button = button
		button.add_child(glyph)
