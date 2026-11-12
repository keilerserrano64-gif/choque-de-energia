extends Control
## Capa de pantalla de la intro: franjas de cine, corte del Sharingan (ojo en primer
## plano con los tres tomoe), destellos y la tarjeta con el nombre. Se adapta al tamaño
## de la ventana (no supone 960x540). El estado lo pone el controlador (ctrl).

const TITULO := "MADARA UCHIHA"
const SUBTITULO := "EL FANTASMA DEL CLAN UCHIHA"
const BARRA := 0.12  ## alto de cada franja negra (fracción de la pantalla)

var ctrl: Object
var _titulo: Label
var _subtitulo: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func preparar(_nombre: String) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel art nítido (ojos y retrato de la hoja)
	_titulo = UiKit.label(TITULO, 58, Color.WHITE, 14, Color("#3a0508"))
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo.add_theme_constant_override("shadow_offset_x", 4)
	_titulo.add_theme_constant_override("shadow_offset_y", 4)
	_titulo.add_theme_color_override("font_shadow_color", Color(0.85, 0.08, 0.1, 0.8))
	add_child(_titulo)
	_subtitulo = UiKit.label(SUBTITULO, 20, Color("#ff9a7a"), 6, Color("#140306"))
	_subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_subtitulo)
	_colocar(0.0)


func _process(_delta: float) -> void:
	if ctrl == null:
		return
	_colocar(float(ctrl.get("tarjeta")))
	queue_redraw()


func _pantalla() -> Vector2:
	return get_viewport_rect().size


func _colocar(k: float) -> void:
	if _titulo == null:
		return
	var s := _pantalla()
	_titulo.size = Vector2(s.x, 80)
	_subtitulo.size = Vector2(s.x, 30)
	# Entra desde la izquierda y frena (el tween ya trae el rebote).
	var dx := (1.0 - k) * -s.x * 0.6
	_titulo.position = Vector2(dx, s.y * 0.64)
	_subtitulo.position = Vector2(-dx, s.y * 0.64 + 76)
	# Con el retrato de la hoja (ya trae el logo «MADARA UCHIHA · EDO TENSEI») sobra el título de texto.
	var con_retrato := ctrl != null and ctrl.get("retrato_tex") != null
	_titulo.modulate.a = 0.0 if con_retrato else clampf(k, 0.0, 1.0)
	_subtitulo.modulate.a = clampf(k * 1.4 - 0.4, 0.0, 1.0)


func _draw() -> void:
	if ctrl == null:
		return
	var s := _pantalla()
	var t := float(ctrl.get("tiempo"))
	_franja_nombre(s, float(ctrl.get("tarjeta")), t)
	_retrato(s, float(ctrl.get("tarjeta")))
	_corte_sharingan(s, float(ctrl.get("corte")), float(ctrl.get("sharingan")), float(ctrl.get("giro_tomoe")), t)
	var b := float(ctrl.get("barras"))
	if b > 0.0:
		var alto := roundf(s.y * BARRA * b)
		draw_rect(Rect2(0, 0, s.x, alto), Color.BLACK)
		draw_rect(Rect2(0, s.y - alto, s.x, alto), Color.BLACK)
	var d := float(ctrl.get("destello"))
	if d > 0.0:
		var col: Color = ctrl.get("color_destello")
		draw_rect(Rect2(Vector2.ZERO, s), Color(col, d))


## Pincelada roja detrás del nombre.
func _franja_nombre(s: Vector2, k: float, t: float) -> void:
	if k <= 0.0:
		return
	var y := s.y * 0.64 - 6
	var ancho := s.x * clampf(k, 0.0, 1.0)
	var pts := PackedVector2Array([Vector2(s.x * 0.5 - ancho * 0.5 + 30, y), Vector2(s.x * 0.5 + ancho * 0.5 + 30, y),
		Vector2(s.x * 0.5 + ancho * 0.5 - 30, y + 118), Vector2(s.x * 0.5 - ancho * 0.5 - 30, y + 118)])
	draw_colored_polygon(pts, Color(0.35, 0.02, 0.05, 0.82 * clampf(k, 0.0, 1.0)))
	# Bordes en escalones y líneas de velocidad.
	draw_rect(Rect2(s.x * 0.5 - ancho * 0.5, y + 2, ancho, 3), Color(0.95, 0.2, 0.15, 0.9 * k))
	draw_rect(Rect2(s.x * 0.5 - ancho * 0.5, y + 112, ancho, 3), Color(0.95, 0.2, 0.15, 0.9 * k))
	for i in range(10):
		var lx := fmod(t * (700.0 + i * 90.0) + i * 211.0, s.x + 200.0) - 100.0
		draw_rect(Rect2(lx, y + 12 + i * 10, 40 + (i % 3) * 30, 2), Color(1, 0.6, 0.5, 0.18 * k))


## Corte horizontal con el ojo de Madara en primer plano y el Sharingan activándose.
func _corte_sharingan(s: Vector2, k: float, act: float, giro: float, t: float) -> void:
	if k <= 0.0:
		return
	var alto := s.y * 0.34
	var cy := s.y * 0.5
	# La franja se abre desde el centro.
	var h := alto * k
	var rect := Rect2(0, cy - h * 0.5, s.x, h)
	draw_rect(rect, Color(0.07, 0.01, 0.02))
	for i in range(14):
		var ly := cy - h * 0.5 + fmod(i * 37.0, maxf(h, 1.0))
		var lx := fmod(t * (900.0 + i * 70.0) + i * 160.0, s.x + 300.0) - 150.0
		draw_rect(Rect2(lx, ly, 80 + (i % 4) * 40, 2), Color(0.8, 0.1, 0.1, 0.25))
	draw_rect(Rect2(0, cy - h * 0.5, s.x, 3), Color(0.9, 0.15, 0.1))
	draw_rect(Rect2(0, cy + h * 0.5 - 3, s.x, 3), Color(0.9, 0.15, 0.1))
	if k < 0.6:
		return
	var a := clampf((k - 0.6) / 0.4, 0.0, 1.0)
	if ctrl.get("ojos_tex") != null:
		_ojo_de_la_hoja(s, cy, h, act, a, t)
		return
	var e := Vector2(s.x * 0.5, cy + alto * 0.06)
	var w := alto * 1.2
	var eh := alto * 0.3
	# Piel pálida de lado a lado, con sombra bajo la ceja y en los bordes.
	var arriba := cy - h * 0.5 + 3
	draw_rect(Rect2(0, arriba, s.x, h - 6), Color(0.83, 0.7, 0.62, a))
	draw_rect(Rect2(0, arriba, s.x, h * 0.2), Color(0.6, 0.45, 0.42, a))
	for i in range(4):
		var borde := s.x * (0.08 + 0.05 * i)
		draw_rect(Rect2(0, arriba, borde, h - 6), Color(0.25, 0.12, 0.12, a * 0.18))
		draw_rect(Rect2(s.x - borde, arriba, borde, h - 6), Color(0.25, 0.12, 0.12, a * 0.18))
	# Ceja.
	draw_colored_polygon(PackedVector2Array([e + Vector2(-w * 0.62, -eh * 1.55), e + Vector2(w * 0.55, -eh * 1.85),
		e + Vector2(w * 0.6, -eh * 1.55), e + Vector2(-w * 0.6, -eh * 1.3)]), Color(0.05, 0.03, 0.04, a))
	# Mechones de pelo negro que caen sobre la cara.
	for i in range(4):
		var x0 := s.x * (0.02 + i * 0.06) + sin(t * 3.0 + i) * 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(x0, arriba), Vector2(x0 + 38 + i * 6, arriba),
			Vector2(x0 + 14 + i * 3, arriba + (h - 6) * (0.5 + 0.08 * (i % 3)))]), Color(0.03, 0.03, 0.05, a))
	for i in range(2):
		var x1 := s.x * (0.86 + i * 0.06)
		draw_colored_polygon(PackedVector2Array([Vector2(x1, arriba), Vector2(x1 + 50, arriba),
			Vector2(x1 + 30, arriba + (h - 6) * (0.45 + 0.1 * i))]), Color(0.03, 0.03, 0.05, a))
	# Forma del ojo (almendra) y blanco.
	var ojo := PackedVector2Array()
	for i in range(25):
		var u := float(i) / 24.0
		ojo.append(e + Vector2(lerpf(-w * 0.5, w * 0.5, u), -sin(u * PI) * eh * (1.0 + 0.15 * (1.0 - u))))
	for i in range(25):
		var u := 1.0 - float(i) / 24.0
		ojo.append(e + Vector2(lerpf(-w * 0.5, w * 0.5, u), sin(u * PI) * eh * 0.75))
	draw_colored_polygon(ojo, Color(0.93, 0.9, 0.86, a))
	# Iris: negro -> rojo al activarse, con el anillo y los tres tomoe.
	var r := eh * 0.95
	var iris := Color(0.12, 0.09, 0.1).lerp(Color(0.82, 0.05, 0.08), act)
	draw_circle(e, r, Color(0.04, 0.02, 0.02, a))
	draw_circle(e, r * 0.92, Color(iris, a))
	draw_circle(e, r * 0.6, Color(iris.lightened(0.12 * act), a))
	if act > 0.0:
		draw_arc(e, r * 0.55, 0.0, TAU, 48, Color(0.05, 0.0, 0.0, a * act), maxf(2.0, r * 0.05))
		for i in range(3):
			var ang := giro + TAU * i / 3.0
			_tomoe(e, r * 0.55, ang, r * 0.16, Color(0.05, 0.0, 0.0, a * act))
	draw_circle(e, r * 0.16, Color(0.02, 0.0, 0.0, a))
	# Brillo y párpado superior grueso (pestañas).
	draw_circle(e + Vector2(-r * 0.35, -r * 0.38), r * 0.1, Color(1, 1, 1, a * 0.85))
	draw_polyline(ojo.slice(0, 25), Color(0.03, 0.02, 0.03, a), maxf(4.0, eh * 0.14))
	draw_polyline(ojo.slice(25), Color(0.25, 0.12, 0.12, a), 2.0)
	# Halo rojo pulsante del Sharingan.
	if act > 0.5:
		var p := 0.5 + 0.5 * sin(t * 20.0)
		draw_arc(e, r * (1.05 + 0.08 * p), 0.0, TAU, 48, Color(1, 0.15, 0.1, a * (act - 0.5) * 0.9), 3.0)
	# Bordes de la franja por encima de la piel.
	draw_rect(Rect2(0, cy - h * 0.5, s.x, 3), Color(0.9, 0.15, 0.1))
	draw_rect(Rect2(0, cy + h * 0.5 - 3, s.x, 3), Color(0.9, 0.15, 0.1))


## Un tomoe: cabeza redonda sobre el anillo y cola en coma que se afina hacia atrás.
func _tomoe(c: Vector2, radio: float, ang: float, tam: float, col: Color) -> void:
	for j in range(7):
		var k := float(j) / 6.0
		var a := ang - k * 0.75
		var r := radio + k * tam * 0.6
		draw_circle(c + Vector2.from_angle(a) * r, tam * (1.0 - k * 0.8), col)


## Primer plano del ojo dibujado en la hoja: cerrado -> se abre -> Sharingan.
func _ojo_de_la_hoja(s: Vector2, cy: float, h: float, act: float, a: float, t: float) -> void:
	var tex: Texture2D = ctrl.get("ojos_tex")
	var rects: Dictionary = ctrl.get("ojos_rects")
	var clave := "cerrado" if act < 0.34 else ("despierta" if act < 0.67 else "sharingan")
	var r: Array = rects.get(clave, rects.get("sharingan", [0, 0, tex.get_width(), tex.get_height()]))
	var src := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	# Recorta un poco arriba y abajo y llena el alto de la franja manteniendo la proporción.
	src = src.grow_individual(0, -src.size.y * 0.08, 0, -src.size.y * 0.08)
	var alto := h - 6.0
	var ancho := alto * src.size.x / src.size.y
	var dest := Rect2(s.x * 0.5 - ancho * 0.5, cy - alto * 0.5, ancho, alto)
	draw_texture_rect_region(tex, dest, src, Color(1, 1, 1, a))
	# Bordes oscuros a los lados para fundir la imagen con la franja.
	for i in range(4):
		var b := 6.0 + i * 6.0
		draw_rect(Rect2(dest.position.x, dest.position.y, b, alto), Color(0.07, 0.01, 0.02, 0.25 * a))
		draw_rect(Rect2(dest.end.x - b, dest.position.y, b, alto), Color(0.07, 0.01, 0.02, 0.25 * a))
	if clave == "sharingan":
		var p := 0.5 + 0.5 * sin(t * 20.0)
		draw_rect(dest, Color(1.0, 0.1, 0.05, 0.08 * p * a))
	draw_rect(Rect2(0, cy - h * 0.5, s.x, 3), Color(0.9, 0.15, 0.1))
	draw_rect(Rect2(0, cy + h * 0.5 - 3, s.x, 3), Color(0.9, 0.15, 0.1))


## Retrato con el logo de la hoja, que entra por la derecha en la presentación.
func _retrato(s: Vector2, k: float) -> void:
	var tex: Texture2D = ctrl.get("retrato_tex")
	if tex == null or k <= 0.0:
		return
	var alto := s.y * 0.5
	var ancho := alto * tex.get_width() / float(tex.get_height())
	var x := s.x - ancho - s.x * 0.04 + (1.0 - clampf(k, 0.0, 1.0)) * s.x * 0.5
	var y := s.y * 0.64 - alto + 8.0
	draw_texture_rect(tex, Rect2(x, y, ancho, alto), false, Color(1, 1, 1, clampf(k, 0.0, 1.0)))
