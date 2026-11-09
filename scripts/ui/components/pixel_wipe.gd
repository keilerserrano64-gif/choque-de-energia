class_name PixelWipe
extends Control
## Transición en pixel art entre pantallas: una cuadrícula de bloques que crecen en
## diagonal hasta tapar la pantalla y luego se encogen en el mismo orden.
## `progress` = 0 (no se ve nada) … 1 (pantalla tapada).

const CELL := 40.0
const SPREAD := 0.55  ## qué parte de la animación ocupa el desfase en diagonal

@export var color := Color(0.03, 0.035, 0.06)
@export var accent := Color(0.35, 0.85, 1.0)

var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		visible = progress > 0.0
		queue_redraw()
## true mientras se destapa: los bloques se encogen empezando por la otra esquina.
var revealing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _draw() -> void:
	# Tamaño real de la pantalla (el nodo vive en una CanvasLayer y puede medir 0 al empezar).
	var area := get_viewport_rect().size
	var cols := int(ceilf(area.x / CELL)) + 1
	var rows := int(ceilf(area.y / CELL)) + 1
	var total := float(cols + rows)
	for row in range(rows):
		for col in range(cols):
			var order := float(col + row) / total
			if revealing:
				order = 1.0 - order
			# Cada bloque crece en su turno; el resto del tiempo está lleno o vacío.
			var local := clampf((progress * (1.0 + SPREAD) - order * SPREAD), 0.0, 1.0)
			if local <= 0.0:
				continue
			var s := roundf(CELL * local / 4.0) * 4.0
			var cx := col * CELL + CELL / 2.0
			var cy := row * CELL + CELL / 2.0
			draw_rect(Rect2(cx - s / 2.0, cy - s / 2.0, s, s), color)
			if local < 1.0 and s > 8.0:
				# Borde brillante mientras el bloque está creciendo.
				draw_rect(Rect2(cx - s / 2.0, cy - s / 2.0, s, 2), accent)
				draw_rect(Rect2(cx - s / 2.0, cy + s / 2.0 - 2, s, 2), accent.darkened(0.4))
