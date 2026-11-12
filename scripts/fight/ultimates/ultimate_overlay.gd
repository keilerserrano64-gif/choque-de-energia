extends Control
## Capa de pantalla del definitivo de Madara: franjas de cine, corte del Rinnegan,
## carcajadas «¡JA!», humo que cubre la pantalla, títulos y la frase final.
## Se adapta al tamaño de la ventana. El estado lo pone el controlador (ctrl).

const TITULO := "EL JUICIO DEL DIOS DE LA GUERRA"
const TECNICA := "TENGAI SHINSEI"
const NOMBRE := "MADARA UCHIHA"
const FRASE := "«¿Esto es todo lo que tenéis?»"
const BARRA := 0.12

var ctrl: Object
var _titulo: Label
var _tecnica: Label
var _nombre: Label
var _frase: Label
var _risas: Array[Label] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func preparar() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # planos, logo y retrato de la hoja nítidos
	_titulo = _etiqueta(TITULO, 34, Color.WHITE, 10, Color("#1a0630"))
	_tecnica = _etiqueta(TECNICA, 60, Color("#ffb35a"), 14, Color("#3a0a02"))
	_nombre = _etiqueta(NOMBRE, 24, Color("#c9b3ff"), 6, Color("#0c0418"))
	_frase = _etiqueta(FRASE, 22, Color("#f2e6ff"), 6, Color("#000000"))
	for i in range(5):
		var l := UiKit.label("¡JA!", 34 + i * 4, Color("#e8dcff"), 10, Color("#2a0a3a"))
		l.pivot_offset = Vector2(40, 22)
		l.modulate.a = 0.0
		add_child(l)
		_risas.append(l)


func _etiqueta(texto: String, tam: int, color: Color, borde: int, color_borde: Color) -> Label:
	var l := UiKit.label(texto, tam, color, borde, color_borde)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	add_child(l)
	return l


func _process(_delta: float) -> void:
	if ctrl == null or _titulo == null:
		return
	var s := get_viewport_rect().size
	var k := float(ctrl.get("titulos"))
	for l in [_titulo, _tecnica, _nombre, _frase]:
		(l as Label).size = Vector2(s.x, 70)
	_tecnica.position = Vector2((1.0 - k) * -s.x * 0.5, s.y * 0.58)
	_titulo.position = Vector2((1.0 - k) * s.x * 0.5, s.y * 0.58 - 40)
	_nombre.position = Vector2(0, s.y * 0.58 + 70)
	# Con el logo y el retrato de la hoja sobran «TENGAI SHINSEI» y «MADARA UCHIHA» en texto.
	var con_logo := ctrl.get("logo_tex") != null
	var con_retrato := ctrl.get("retrato_tex") != null
	_tecnica.modulate.a = 0.0 if con_logo else clampf(k, 0.0, 1.0)
	_titulo.modulate.a = clampf(k * 1.3 - 0.3, 0.0, 1.0)
	_nombre.modulate.a = 0.0 if con_retrato else clampf(k * 1.6 - 0.6, 0.0, 1.0)
	_frase.position = Vector2(0, s.y * (1.0 - BARRA) - 46)
	_frase.modulate.a = clampf(float(ctrl.get("frase")), 0.0, 1.0)
	# Carcajadas que brotan alrededor de Madara.
	var risa := float(ctrl.get("risa"))
	var cabeza: Vector2 = ctrl.get("cabeza_pantalla")
	var t := float(ctrl.get("tiempo"))
	for i in _risas.size():
		var l := _risas[i]
		var fase := fmod(t * 1.6 + i * 0.2, 1.0)
		var lado := -1.0 if i % 2 == 0 else 1.0
		l.position = cabeza + Vector2(lado * (50.0 + i * 18.0) - 40.0, -60.0 - fase * 80.0 - i * 10.0)
		l.rotation = lado * (0.15 + 0.1 * sin(t * 9.0 + i))
		l.scale = Vector2.ONE * (0.8 + 0.4 * (1.0 - fase))
		l.modulate.a = risa * clampf(1.0 - fase, 0.0, 1.0) * clampf(fase * 5.0, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if ctrl == null:
		return
	var s := get_viewport_rect().size
	var t := float(ctrl.get("tiempo"))
	_plano_escena(s)
	_tajo_pantalla(s, float(ctrl.get("tajo_pantalla")))
	_humo_pantalla(s, float(ctrl.get("humo_pantalla")), t)
	_franja_titulos(s, float(ctrl.get("titulos")), t)
	_logo_y_retrato(s, float(ctrl.get("titulos")))
	var fr := float(ctrl.get("frase"))
	if fr > 0.0:
		draw_rect(Rect2(s.x * 0.2, s.y * (1.0 - BARRA) - 48, s.x * 0.6, 40), Color(0, 0, 0, 0.65 * fr))
	_corte_rinnegan(s, float(ctrl.get("corte")), t)
	var b := float(ctrl.get("barras"))
	if b > 0.0:
		var alto := roundf(s.y * BARRA * b)
		draw_rect(Rect2(0, 0, s.x, alto), Color.BLACK)
		draw_rect(Rect2(0, s.y - alto, s.x, alto), Color.BLACK)
	var d := float(ctrl.get("destello"))
	if d > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(ctrl.get("color_destello") as Color, d))


## Humo de la segunda explosión que tapa la pantalla y luego se disipa.
func _humo_pantalla(s: Vector2, a: float, t: float) -> void:
	if a <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.2, 0.16, 0.15, a * 0.85))
	for i in range(26):
		var x := fmod(i * 97.0 + t * (14.0 + i % 4 * 6.0), s.x + 200.0) - 100.0
		var y := s.y * (0.15 + float((i * 37) % 70) / 100.0) - t * 4.0 * (i % 3)
		var r := 70.0 + (i % 5) * 26.0
		draw_circle(Vector2(x, y), r, Color(0.28, 0.22, 0.2, a * 0.5))
		draw_circle(Vector2(x - r * 0.2, y - r * 0.25), r * 0.6, Color(0.36, 0.3, 0.27, a * 0.35))


func _franja_titulos(s: Vector2, k: float, t: float) -> void:
	if k <= 0.0:
		return
	var y := s.y * 0.58 - 46
	var ancho := s.x * clampf(k, 0.0, 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.5 - ancho * 0.5 + 40, y), Vector2(s.x * 0.5 + ancho * 0.5 + 40, y),
		Vector2(s.x * 0.5 + ancho * 0.5 - 40, y + 156), Vector2(s.x * 0.5 - ancho * 0.5 - 40, y + 156)]), Color(0.14, 0.03, 0.22, 0.85 * k))
	draw_rect(Rect2(s.x * 0.5 - ancho * 0.5, y + 2, ancho, 3), Color(1.0, 0.55, 0.2, k))
	draw_rect(Rect2(s.x * 0.5 - ancho * 0.5, y + 150, ancho, 3), Color(0.6, 0.4, 1.0, k))
	for i in range(10):
		var lx := fmod(t * (650.0 + i * 80.0) + i * 211.0, s.x + 200.0) - 100.0
		draw_rect(Rect2(lx, y + 14 + i * 13, 50 + (i % 3) * 30, 2), Color(0.8, 0.6, 1.0, 0.16 * k))


## Corte horizontal con el ojo de Madara: Rinnegan (iris lila con anillos concéntricos).
func _corte_rinnegan(s: Vector2, k: float, t: float) -> void:
	if k <= 0.0:
		return
	var alto := s.y * 0.34
	var cy := s.y * 0.5
	var h := alto * k
	var arriba := cy - h * 0.5 + 3
	draw_rect(Rect2(0, cy - h * 0.5, s.x, h), Color(0.05, 0.02, 0.08))
	if k >= 0.6:
		var a := clampf((k - 0.6) / 0.4, 0.0, 1.0)
		draw_rect(Rect2(0, arriba, s.x, h - 6), Color(0.83, 0.7, 0.62, a))
		draw_rect(Rect2(0, arriba, s.x, h * 0.2), Color(0.6, 0.45, 0.42, a))
		for i in range(4):
			var borde := s.x * (0.08 + 0.05 * i)
			draw_rect(Rect2(0, arriba, borde, h - 6), Color(0.2, 0.1, 0.18, a * 0.18))
			draw_rect(Rect2(s.x - borde, arriba, borde, h - 6), Color(0.2, 0.1, 0.18, a * 0.18))
		var e := Vector2(s.x * 0.5, cy + alto * 0.06)
		var w := alto * 1.2
		var eh := alto * 0.3
		draw_colored_polygon(PackedVector2Array([e + Vector2(-w * 0.62, -eh * 1.55), e + Vector2(w * 0.55, -eh * 1.85),
			e + Vector2(w * 0.6, -eh * 1.55), e + Vector2(-w * 0.6, -eh * 1.3)]), Color(0.05, 0.03, 0.04, a))
		for i in range(4):
			var x0 := s.x * (0.02 + i * 0.06) + sin(t * 3.0 + i) * 2.0
			draw_colored_polygon(PackedVector2Array([Vector2(x0, arriba), Vector2(x0 + 38 + i * 6, arriba),
				Vector2(x0 + 14 + i * 3, arriba + (h - 6) * (0.5 + 0.08 * (i % 3)))]), Color(0.03, 0.03, 0.05, a))
		var ojo := PackedVector2Array()
		for i in range(25):
			var u := float(i) / 24.0
			ojo.append(e + Vector2(lerpf(-w * 0.5, w * 0.5, u), -sin(u * PI) * eh * (1.0 + 0.15 * (1.0 - u))))
		for i in range(25):
			var u := 1.0 - float(i) / 24.0
			ojo.append(e + Vector2(lerpf(-w * 0.5, w * 0.5, u), sin(u * PI) * eh * 0.75))
		draw_colored_polygon(ojo, Color(0.93, 0.9, 0.86, a))
		var r := eh * 0.95
		draw_circle(e, r, Color(0.62, 0.5, 0.82, a))
		draw_circle(e, r * 0.7, Color(0.72, 0.6, 0.9, a))
		# Anillos concéntricos del Rinnegan que «laten» hacia fuera.
		for i in range(5):
			var rr := r * (0.22 + i * 0.19) + sin(t * 4.0) * 1.5
			draw_arc(e, rr, 0.0, TAU, 48, Color(0.08, 0.04, 0.12, a), maxf(2.0, r * 0.045))
		draw_circle(e, r * 0.1, Color(0.06, 0.02, 0.1, a))
		draw_circle(e + Vector2(-r * 0.35, -r * 0.38), r * 0.09, Color(1, 1, 1, a * 0.85))
		draw_polyline(ojo.slice(0, 25), Color(0.03, 0.02, 0.03, a), maxf(4.0, eh * 0.14))
		draw_polyline(ojo.slice(25), Color(0.25, 0.12, 0.12, a), 2.0)
		var p := 0.5 + 0.5 * sin(t * 16.0)
		draw_arc(e, r * (1.05 + 0.08 * p), 0.0, TAU, 48, Color(0.75, 0.5, 1.0, a * 0.7), 3.0)
	draw_rect(Rect2(0, cy - h * 0.5, s.x, 3), Color(0.65, 0.4, 1.0))
	draw_rect(Rect2(0, cy + h * 0.5 - 3, s.x, 3), Color(0.65, 0.4, 1.0))


## Plano de cine con los cuadros de la hoja: paneles de escena (meteoritos, impactos)
## recortados para llenar la franja, y cuadros de Madara con su Susanoo enteros y centrados.
func _plano_escena(s: Vector2) -> void:
	var tipo := String(ctrl.get("plano_tipo"))
	var i := int(ctrl.get("plano_cuadro"))
	var a := float(ctrl.get("plano_alfa"))
	var tex: Texture2D = ctrl.get("escenas_tex") if tipo == "escenas" else ctrl.get("personaje_tex")
	var cuadros: Array = ctrl.get("escenas_cuadros") if tipo == "escenas" else ctrl.get("personaje_cuadros")
	if tex == null or i < 0 or i >= cuadros.size() or a <= 0.0:
		return
	var r: Array = (cuadros[i] as Dictionary)["rect"]
	var src := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	# Los dibujos son pequeños (~60-110 px): franja de cine ancha en vez de pantalla completa.
	var banda := Rect2(0, s.y * 0.2, s.x, s.y * 0.6)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.0, 0.06, a * 0.9))
	draw_rect(banda, Color(0.07, 0.02, 0.12, a))
	# Escala ENTERA que quepa en la franja: píxeles nítidos y el dibujo completo, sin recortes.
	var escala := maxf(floorf(minf(banda.size.x / src.size.x, banda.size.y / src.size.y)), 1.0)
	var dest := Rect2(Vector2.ZERO, src.size * escala)
	dest.position = (banda.position + (banda.size - dest.size) * 0.5).round()
	if tipo != "escenas":
		# Líneas de velocidad a los lados del cuadro.
		var t := float(ctrl.get("tiempo"))
		for k in range(12):
			var y := banda.position.y + fmod(k * 41.0, banda.size.y)
			var lx := fmod(t * (700.0 + k * 60.0) + k * 173.0, s.x + 200.0) - 100.0
			draw_rect(Rect2(lx, y, 60 + (k % 3) * 30, 2), Color(0.6, 0.45, 1.0, 0.2 * a))
	draw_texture_rect_region(tex, dest, src, Color(1, 1, 1, a))
	draw_rect(Rect2(0, banda.position.y - 3, s.x, 3), Color(1.0, 0.55, 0.2, a))
	draw_rect(Rect2(0, banda.end.y, s.x, 3), Color(0.6, 0.4, 1.0, a))


## Tajo del Susanoo: una línea blanca y azul que cruza la pantalla en diagonal.
func _tajo_pantalla(s: Vector2, k: float) -> void:
	if k <= 0.0:
		return
	var desde := Vector2(-s.x * 0.1, s.y * 0.2)
	var hasta := Vector2(s.x * 1.1, s.y * 0.85)
	var punta := desde.lerp(hasta, k)
	var cola := desde.lerp(hasta, maxf(0.0, k - 0.45))
	var n := (hasta - desde).orthogonal().normalized()
	draw_colored_polygon(PackedVector2Array([cola, punta + n * 3.0, punta, punta - n * 3.0]), Color(0.6, 0.8, 1.0, 0.5))
	draw_colored_polygon(PackedVector2Array([cola + n * 14.0, punta, cola - n * 14.0]), Color(0.45, 0.6, 1.0, 0.35))
	draw_line(cola, punta, Color(1, 1, 1, 0.95), 5.0)


## Logo «TENGAI SHINSEI» y retrato de la hoja en la presentación final.
func _logo_y_retrato(s: Vector2, k: float) -> void:
	if k <= 0.0:
		return
	var a := clampf(k, 0.0, 1.0)
	var retrato: Texture2D = ctrl.get("retrato_tex")
	if retrato:
		var alto := s.y * 0.46
		var ancho := alto * retrato.get_width() / float(retrato.get_height())
		draw_texture_rect(retrato, Rect2(s.x - ancho - s.x * 0.03 + (1.0 - a) * s.x * 0.4, s.y * 0.58 - 46 - alto + 6, ancho, alto), false, Color(1, 1, 1, a))
	var logo: Texture2D = ctrl.get("logo_tex")
	if logo:
		var alto2 := 92.0
		var ancho2 := alto2 * logo.get_width() / float(logo.get_height())
		draw_texture_rect(logo, Rect2(s.x * 0.5 - ancho2 * 0.5 - (1.0 - a) * s.x * 0.4, s.y * 0.58 - 4, ancho2, alto2), false, Color(1, 1, 1, a))
