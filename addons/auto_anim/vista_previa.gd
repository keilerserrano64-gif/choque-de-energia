@tool
extends Control
## Vista previa del panel AutoAnim: dibuja al luchador con la animación aplicada.
##  - Usa la pose real de la acción (jab, sweep, throw...) y, si el luchador tiene la
##    secuencia "seq_<pose>", la reproduce cuadro a cuadro como en el juego.
##  - Se puede pausar, arrastrar por la línea de tiempo, ir en cámara lenta y ver
##    "fantasmas" (posiciones anteriores) para juzgar el recorrido.
##  - Abajo, una gráfica de la curva: desplazamiento X (naranja), Y (verde) y giro (azul).

const AutoAnim2D := preload("res://scripts/data/auto_anim_2d.gd")
const SpriteSheetScript := preload("res://scripts/data/sprite_sheet.gd")

const PAUSA := 0.35
const ALTO_GRAFICA := 46.0

## Poses que se prueban para cada acción (la primera que tenga el luchador).
const POSES := {
	"golpe": ["jab", "light", "cross"],
	"patada": ["kick_mid", "finisher", "kick_high", "heavy"],
	"golpe_recibido": ["hurt"],
	"bloqueo": ["block"],
	"salto": ["jump"],
	"aterrizaje": ["stance", "idle"],
	"dash": ["run", "walk"],
	"especial": ["special", "charge", "heavy"],
	"victoria": ["victory", "intro"],
	"barrida": ["sweep", "kick_low"],
	"antiaereo": ["uppercut", "heavy"],
	"aereo": ["air_kick", "air_punch", "jump"],
	"agarre": ["throw", "cross"],
	"derribo": ["fall", "down", "hurt"],
}

signal tiempo_cambiado(progreso: float)

var reproduciendo := true
var velocidad := 1.0
var fantasmas := false
var usar_pose := true

var ancla := Vector2.ZERO  ## pies del luchador dentro de la imagen
var animacion: Dictionary = {}
## Para regenerar la animación en cada repetición (variación aleatoria).
var generador: Callable

var _sprites: Dictionary = {}
var _quieto: Array = []   # cuadros de la pose de reposo
var _cuadros: Array = []  # cuadros de la pose de la acción
var _t := 0.0
var _escala_ref := 1.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 240)
	clip_contents = true
	# Dibujo nítido como en el combate: con el zoom de la vista previa (no entero) y los giros
	# y estiramientos de la animación, el filtro «vecino más cercano» deformaba los píxeles.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fighter_fx.gdshader")
	material = mat
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Carga las imágenes de un luchador del catálogo.
func mostrar_luchador(definicion: Dictionary) -> void:
	_sprites = definicion.get("sprites", {})
	_quieto = _cuadros_de(["stance", "idle"])
	var a: Variant = definicion.get("sprite_anchor", null)
	var tex: Texture2D = _quieto[0] if not _quieto.is_empty() else null
	ancla = a if a is Vector2 else (Vector2(tex.get_width() * 0.5, tex.get_height()) if tex else Vector2.ZERO)
	_escala_ref = float(tex.get_height()) if tex else 1.0
	_cuadros = _quieto
	queue_redraw()


## Elige la pose que se ve durante la animación según la acción.
func poner_accion(accion: String) -> void:
	_cuadros = _cuadros_de(POSES.get(accion, [])) if usar_pose else []
	if _cuadros.is_empty():
		_cuadros = _quieto
	queue_redraw()


## Cambia la animación. En pausa conserva el punto de la línea de tiempo (así al
## tocar intensidad o capa se ve el cambio en el mismo cuadro); reproduciendo, empieza de cero.
func poner_animacion(anim: Dictionary) -> void:
	var prog := progreso()
	animacion = anim
	_t = 0.0 if reproduciendo or anim.is_empty() else prog * float(anim["duracion"])
	tiempo_cambiado.emit(progreso())
	queue_redraw()


## Mueve la reproducción a un punto (0..1) de la animación y la pausa.
func ir_a(progreso: float) -> void:
	if animacion.is_empty():
		return
	reproduciendo = false
	_t = clampf(progreso, 0.0, 1.0) * float(animacion["duracion"])
	queue_redraw()


func progreso() -> float:
	if animacion.is_empty():
		return 0.0
	return clampf(_t / float(animacion["duracion"]), 0.0, 1.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or animacion.is_empty():
		return
	if reproduciendo:
		_t += delta * velocidad
		var dur := float(animacion["duracion"])
		var ciclo := dur + (0.0 if bool(animacion.get("loop", false)) else PAUSA)
		if _t >= ciclo:
			_t = fmod(_t, ciclo)
			if generador.is_valid():  # nueva variación en cada repetición
				animacion = generador.call()
		tiempo_cambiado.emit(progreso())
	queue_redraw()


# ------------------------------------------------------------------ dibujo

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.11, 0.15))
	var alto_escena := size.y - ALTO_GRAFICA
	var suelo := alto_escena - 16.0
	draw_line(Vector2(0, suelo), Vector2(size.x, suelo), Color(0.35, 0.38, 0.45), 2.0)
	if _quieto.is_empty():
		draw_string(get_theme_default_font(), Vector2(10, 24), "Sin imagen", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		return
	var zoom := clampf((alto_escena - 46.0) / maxf(_escala_ref, 1.0), 0.4, 4.0)
	var pies := Vector2(size.x * 0.5, suelo)
	var dur := float(animacion.get("duracion", 1.0))
	var en_anim := not animacion.is_empty() and _t <= dur

	if fantasmas and en_anim:
		for n in range(4, 0, -1):
			var tf := _t - n * dur * 0.08
			if tf > 0.0:
				_dibujar_luchador(pies, zoom, tf, 0.12 + 0.05 * (4 - n))
	_dibujar_luchador(pies, zoom, _t if en_anim else dur, 1.0)
	_dibujar_grafica(Rect2(0, alto_escena, size.x, ALTO_GRAFICA))


func _dibujar_luchador(pies: Vector2, zoom: float, tiempo: float, alfa: float) -> void:
	var muestra := AutoAnim2D.NEUTRO
	var dur := float(animacion.get("duracion", 1.0))
	var activa := not animacion.is_empty() and tiempo < dur
	if not animacion.is_empty():
		muestra = AutoAnim2D.muestrear(animacion, minf(tiempo, dur))
	var cuadros := _cuadros if activa else _quieto
	var idx := clampi(int(tiempo / dur * cuadros.size()), 0, cuadros.size() - 1) if activa else 0
	var tex: Texture2D = cuadros[idx]
	var desp: Vector2 = muestra["desp"]
	var xf := Transform2D(0.0, pies + desp * zoom) \
		* Transform2D(deg_to_rad(float(muestra["rot"])), Vector2.ZERO) \
		* Transform2D(0.0, (muestra["escala"] as Vector2) * zoom, 0.0, Vector2.ZERO)
	draw_set_transform_matrix(xf)
	var color: Color = muestra["color"]
	color.a *= alfa
	draw_texture(tex, -ancla, color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _dibujar_grafica(r: Rect2) -> void:
	draw_rect(r, Color(0.07, 0.08, 0.1))
	if animacion.is_empty():
		return
	var dur := float(animacion["duracion"])
	var pasos := 60
	var puntos := [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	var maximo := 1.0
	var valores: Array = []
	for n in pasos + 1:
		var s := AutoAnim2D.muestrear(animacion, dur * n / pasos)
		var v := Vector3((s["desp"] as Vector2).x, (s["desp"] as Vector2).y, float(s["rot"]) * 0.5)
		valores.append(v)
		maximo = maxf(maximo, maxf(absf(v.x), maxf(absf(v.y), absf(v.z))))
	var medio := r.position.y + r.size.y * 0.5
	var alto := r.size.y * 0.42 / maximo
	for n in valores.size():
		var x := r.position.x + 6.0 + (r.size.x - 12.0) * n / pasos
		var v: Vector3 = valores[n]
		puntos[0].append(Vector2(x, medio - v.x * alto))
		puntos[1].append(Vector2(x, medio - v.y * alto))
		puntos[2].append(Vector2(x, medio - v.z * alto))
	draw_line(Vector2(r.position.x, medio), Vector2(r.end.x, medio), Color(1, 1, 1, 0.12))
	var colores := [Color(1.0, 0.6, 0.25), Color(0.45, 0.9, 0.45), Color(0.45, 0.65, 1.0)]
	for k in 3:
		draw_polyline(puntos[k], colores[k], 1.5, true)
	var cursor := r.position.x + 6.0 + (r.size.x - 12.0) * progreso()
	draw_line(Vector2(cursor, r.position.y), Vector2(cursor, r.end.y), Color(1, 1, 1, 0.7), 1.0)


# ------------------------------------------------------------------ imágenes

## Cuadros (texturas) de la primera pose disponible; prefiere la secuencia seq_<pose>.
func _cuadros_de(poses: Array) -> Array:
	for pose in poses:
		for clave in ["seq_" + String(pose), String(pose)]:
			if not _sprites.has(clave):
				continue
			var lista: Array = []
			var valor: Variant = _sprites[clave]
			var refs: Array = valor if valor is Array else [valor]
			for ref in refs:
				var tex := _textura(String(ref))
				if tex != null:
					lista.append(tex)
			if not lista.is_empty():
				return lista
	return []


func _textura(ref: String) -> Texture2D:
	if SpriteSheetScript.is_ref(ref):
		return SpriteSheetScript.frame_texture(ref)
	if ResourceLoader.exists(ref):
		return load(ref) as Texture2D
	return null
