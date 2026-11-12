extends Node
class_name AnimadorProcedural
## Animación procedural para luchadores con sprites estáticos (Godot 4).
##
## Da vida a las poses que ya tienes SIN dibujar cuadros nuevos:
##   - Automático: respiración, rebote al caminar, estirarse en el aire,
##     agacharse al despegar y aplastarse al aterrizar.
##   - Por llamada: golpe(), patada(), recibir_golpe(), bloquear(), saltar(),
##     dash(), ko(), victoria(), reiniciar() y temblar().
##
## ADAPTACIÓN A CHOQUE DE ENERGÍA:
## En este juego los luchadores no son nodos con un Sprite2D: CombatSim calcula
## dónde está cada uno y FighterPainter los dibuja cada cuadro. Por eso este
## animador no mueve ningún sprite. Calcula desplazamiento, escala, rotación y
## color (variables "salida_*") y FighterPainter los aplica al dibujar la imagen.
##   - ArenaView crea un animador por cada luchador con imágenes y llama a
##     actualizar() cada cuadro.
##   - CombatSim avisa con anim_events de cuándo llamar a golpe(), patada(),
##     recibir_golpe(), bloquear(), dash(), ko(), victoria() y reiniciar().
##   - saltar() y aterrizar() se detectan solos con el estado de la simulación.
##   - Las distancias están en píxeles de la imagen del luchador (128x128) y
##     siempre "hacia delante" = +X: FighterPainter ya voltea al luchador.
##   - No hay pausa_impacto(): CombatSim ya congela el combate en cada golpe
##     (hit_stop_frames), y tocar Engine.time_scale rompería la cámara lenta del K.O.

@export_group("Respiración (guardia)")
@export var respiracion_fuerza := 0.02      ## Cuánto se estira al respirar (0.02 = 2 %).
@export var respiracion_velocidad := 2.4    ## Más alto = respira más rápido.

@export_group("Caminar")
@export var velocidad_minima_caminar := 20.0  ## Píxeles/seg (de la arena) para considerar que camina.
@export var rebote_altura := 3.0              ## Píxeles que sube en cada paso.
@export var rebote_velocidad := 14.0          ## Ritmo de los pasos.
@export var inclinacion_caminar := 4.0        ## Grados que se inclina al avanzar.

@export_group("Aire")
@export var estirar_en_aire := 0.10        ## Cuánto se estira al subir o caer.

@export_group("Efectos")
@export var color_estela := Color(0.3, 0.9, 1.0, 0.55)  ## Color de la estela del dash.
@export var color_bloqueo := Color(0.7, 1.6, 2.0)       ## Destello al bloquear.
@export var ko_elevar := 30.0     ## Sube el cuerpo tendido para que no atraviese el suelo (imágenes de 128 px).
@export var ko_aplanar := 0.6     ## Grosor del cuerpo tendido (1 = sin aplanar).

# Valores que animan los tweens (se suman a la animación automática).
var desp_accion := Vector2.ZERO
var escala_accion := Vector2.ONE
var rot_accion := 0.0  # en grados

## Resultado de cada cuadro, que lee FighterPainter.
var salida_desp := Vector2.ZERO
var salida_escala := Vector2.ONE
var salida_rot := 0.0  # en grados
var salida_color := Color.WHITE
## Copias que se desvanecen detrás del luchador durante el dash.
## Cada una: {x, y, facing, cuadro, tiempo, desp, escala, rot, vida}.
var estelas: Array = []
## ArenaView guarda aquí el último cuadro dibujado (lo usan las estelas).
var ultimo_cuadro: Dictionary = {}
var ultimo_tiempo := 0.0
## Luchador "fantasma" con el que se dibujan las estelas.
var fantasma: FighterState

const VIDA_ESTELA := 0.25
const AutoAnim2D := preload("res://scripts/data/auto_anim_2d.gd")

## Animaciones AutoAnim 2D del luchador (panel AutoAnim del editor): si una acción
## tiene una, se reproduce en lugar del movimiento fijo de este script.
var auto_anim_id := ""
var _clip: Dictionary = {}
var _clip_t := 0.0
var _auto_anim_contador := 0
var _clip_color := Color.WHITE

var _t := 0.0
var _pos_anterior := Vector2.INF
var _vel := Vector2.ZERO        # velocidad suavizada
var _en_suelo_antes := true
var _temblor_tiempo := 0.0
var _temblor_fuerza := 0.0
var _estela_tiempo := 0.0
var _estela_reloj := 0.0
var _sin_respirar := false      # durante el K.O.
var _tween: Tween
var _tween_color: Tween


func preparar(f: FighterState) -> void:
	fantasma = FighterState.new(f.id, f.x, f.facing)
	auto_anim_id = f.id


## Diccionario que FighterPainter aplica al dibujar (ver FighterPainter.procedural).
func salida() -> Dictionary:
	return {
		"desp": salida_desp, "escala": salida_escala, "rot": salida_rot,
		"color": salida_color * _clip_color, "ko": _sin_respirar,
	}


## Si el luchador tiene una animación AutoAnim para `accion`, la empieza y devuelve true.
func usar_auto_anim(accion: String, opciones: Dictionary = {}) -> bool:
	if auto_anim_id == "" or _sin_respirar:
		return false
	var parametros := opciones.duplicate()
	parametros["semilla"] = _auto_anim_contador
	_auto_anim_contador += 1
	var anim := AutoAnim2D.para_accion(auto_anim_id, accion, parametros)
	if anim.is_empty():
		return false
	if _tween and _tween.is_valid():
		_tween.kill()
	_clip = anim
	_clip_t = 0.0
	return true


func _parar_auto_anim() -> void:
	_clip = {}
	_clip_t = 0.0
	_clip_color = Color.WHITE


# ---------------------------------------------------------------------------
# Detección automática de movimiento (llamar cada cuadro)
# ---------------------------------------------------------------------------
func actualizar(f: FighterState, delta: float) -> void:
	if delta <= 0.0:
		return
	var pos := Vector2(f.x, f.y)
	if _pos_anterior == Vector2.INF:
		_pos_anterior = pos
	var v := (pos - _pos_anterior) / delta
	_pos_anterior = pos
	_vel = _vel.lerp(v, clampf(delta * 15.0, 0.0, 1.0))

	# Despegue y aterrizaje: se usa el estado de la simulación, que es exacto.
	if not f.knocked_down and not _sin_respirar:
		if _en_suelo_antes and not f.grounded and f.velocity_y < 0.0:
			if not usar_auto_anim("salto"):
				saltar()
		elif not _en_suelo_antes and f.grounded:
			if not usar_auto_anim("aterrizaje"):
				aterrizar()
	_en_suelo_antes = f.grounded

	_componer(f, delta)
	_actualizar_estelas(f, delta)


# ---------------------------------------------------------------------------
# Composición final cada cuadro
# ---------------------------------------------------------------------------
func _componer(f: FighterState, delta: float) -> void:
	_t += delta
	if not _clip.is_empty():
		_clip_t += delta
		if _clip_t >= float(_clip["duracion"]):
			_parar_auto_anim()
			desp_accion = Vector2.ZERO
			escala_accion = Vector2.ONE
			rot_accion = 0.0
		else:
			var s := AutoAnim2D.muestrear(_clip, _clip_t)
			desp_accion = s["desp"]
			escala_accion = s["escala"]
			rot_accion = float(s["rot"])
			_clip_color = s["color"]
	var off := Vector2.ZERO
	var esc := Vector2.ONE
	var rot := 0.0

	var en_aire := not f.grounded
	var vx_local := _vel.x * f.facing

	if not _sin_respirar:
		# Respiración: siempre activa, muy sutil.
		var resp := sin(_t * respiracion_velocidad)
		esc.y += resp * respiracion_fuerza
		esc.x -= resp * respiracion_fuerza * 0.5

		# Caminar: rebote e inclinación hacia donde avanza.
		if f.walking and absf(_vel.x) > velocidad_minima_caminar and not en_aire:
			off.y -= absf(sin(_t * rebote_velocidad)) * rebote_altura
			rot += inclinacion_caminar * signf(vx_local)

		# Aire: se estira según la velocidad vertical.
		if en_aire:
			var k := clampf(absf(f.velocity_y) / 800.0, 0.0, 1.0) * estirar_en_aire
			esc.y += k
			esc.x -= k * 0.6

	# Temblor (golpes, bloqueos).
	if _temblor_tiempo > 0.0:
		_temblor_tiempo -= delta
		off += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _temblor_fuerza

	salida_desp = (off + desp_accion).round()  # posiciones enteras = píxeles nítidos
	salida_escala = esc * escala_accion
	salida_rot = rot + rot_accion


func _actualizar_estelas(f: FighterState, delta: float) -> void:
	var vivas: Array = []
	for estela in estelas:
		var e: Dictionary = estela
		e["vida"] = float(e["vida"]) - delta
		if float(e["vida"]) > 0.0:
			vivas.append(e)
	estelas = vivas
	if _estela_tiempo > 0.0:
		_estela_tiempo -= delta
		_estela_reloj -= delta
		if _estela_reloj <= 0.0:
			_estela_reloj = 0.04
			_crear_estela(f)


func _nuevo_tween() -> Tween:
	_parar_auto_anim()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	return _tween


func _destello(color: Color, duracion: float) -> void:
	if _tween_color and _tween_color.is_valid():
		_tween_color.kill()
	salida_color = color
	_tween_color = create_tween()
	_tween_color.tween_property(self, "salida_color", Color.WHITE, duracion)


## Cambia desp/escala/rotación de la acción al mismo tiempo.
func _paso(t: Tween, desp: Vector2, escala: Vector2, rot: float, tiempo: float,
		trans := Tween.TRANS_QUAD, ease_tipo := Tween.EASE_OUT) -> void:
	t.tween_property(self, "desp_accion", desp, tiempo).set_trans(trans).set_ease(ease_tipo)
	t.parallel().tween_property(self, "escala_accion", escala, tiempo).set_trans(trans).set_ease(ease_tipo)
	t.parallel().tween_property(self, "rot_accion", rot, tiempo).set_trans(trans).set_ease(ease_tipo)


func _volver(t: Tween, tiempo: float) -> void:
	_paso(t, Vector2.ZERO, Vector2.ONE, 0.0, tiempo, Tween.TRANS_BACK, Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Acciones (las llama ArenaView cuando CombatSim avisa)
# ---------------------------------------------------------------------------

## Puñetazo: anticipación hacia atrás, embestida y regreso a la guardia.
func golpe() -> Tween:
	var t := _nuevo_tween()
	_paso(t, Vector2(-6, 0), Vector2(0.95, 1.04), -4, 0.07)                       # cargar
	_paso(t, Vector2(14, 0), Vector2(1.08, 0.95), 6, 0.05, Tween.TRANS_EXPO)      # impacto
	t.tween_interval(0.06)                                                        # mantener
	_volver(t, 0.18)
	return t


## Patada: se echa atrás para equilibrar y empuja hacia delante.
func patada() -> Tween:
	var t := _nuevo_tween()
	_paso(t, Vector2(-4, 0), Vector2(0.96, 1.03), -8, 0.08)
	_paso(t, Vector2(10, -2), Vector2(1.06, 0.96), -6, 0.05, Tween.TRANS_EXPO)
	t.tween_interval(0.08)
	_volver(t, 0.2)
	return t


## Recibir un golpe: destello blanco, retroceso, temblor y recuperación.
func recibir_golpe(fuerza := 1.0) -> Tween:
	_destello(Color(2.5, 2.5, 2.5), 0.12)
	temblar(0.15, 3.0 * fuerza)
	var t := _nuevo_tween()
	_paso(t, Vector2(-12 * fuerza, 0), Vector2(0.94, 1.05), -8, 0.06, Tween.TRANS_EXPO)
	t.tween_interval(0.05)
	_volver(t, 0.25)
	return t


## Bloquear: se encoge, destello cian y pequeño temblor.
func bloquear() -> Tween:
	_destello(color_bloqueo, 0.15)
	temblar(0.1, 2.0)
	var t := _nuevo_tween()
	_paso(t, Vector2(-4, 0), Vector2(1.03, 0.95), -3, 0.05)
	t.tween_interval(0.06)
	_volver(t, 0.15)
	return t


## Al despegar: se agacha y se estira (se llama sola).
func saltar() -> Tween:
	var t := _nuevo_tween()
	_paso(t, Vector2.ZERO, Vector2(1.12, 0.86), 0.0, 0.06)
	_paso(t, Vector2.ZERO, Vector2(0.92, 1.1), 0.0, 0.08)
	_paso(t, Vector2.ZERO, Vector2.ONE, 0.0, 0.2)
	return t


## Se llama sola al detectar el aterrizaje.
func aterrizar() -> Tween:
	if _sin_respirar:
		return null
	var t := _nuevo_tween()
	_paso(t, desp_accion, Vector2(1.15, 0.85), rot_accion, 0.05)
	_volver(t, 0.18)
	return t


## Impulso rápido con estela eléctrica (Salto de umbral / Arco de ruptura).
func dash(duracion := 0.25) -> Tween:
	_estela_tiempo = duracion
	_estela_reloj = 0.0
	var t := _nuevo_tween()
	_paso(t, Vector2.ZERO, Vector2(1.1, 0.92), 8, 0.05)
	t.tween_interval(maxf(duracion - 0.05, 0.0))
	_volver(t, 0.15)
	return t


## K.O.: sale despedido, cae de espaldas y rebota.
func ko() -> Tween:
	_sin_respirar = true
	_destello(Color(2.5, 2.5, 2.5), 0.2)
	temblar(0.2, 4.0)
	var tendido := Vector2(ko_aplanar, 1.0)
	var t := _nuevo_tween()
	_paso(t, Vector2(-10, -6), Vector2(0.95, 1.05), -20, 0.12, Tween.TRANS_EXPO)
	_paso(t, Vector2(-24, -ko_elevar), tendido, -90, 0.3, Tween.TRANS_QUAD, Tween.EASE_IN)
	_paso(t, Vector2(-26, -ko_elevar - 4), tendido, -84, 0.1)   # rebote
	_paso(t, Vector2(-27, -ko_elevar), tendido, -90, 0.12, Tween.TRANS_QUAD, Tween.EASE_IN)
	t.parallel().tween_property(self, "salida_color", Color.WHITE.darkened(0.25), 0.6)
	return t


## Victoria: pequeño salto de celebración y brillo.
func victoria() -> Tween:
	_destello(Color(1.8, 2.2, 2.5), 0.6)
	var t := _nuevo_tween()
	_paso(t, Vector2.ZERO, Vector2(1.1, 0.9), 0.0, 0.08)
	_paso(t, Vector2(0, -16), Vector2(0.92, 1.1), 0.0, 0.15)
	_paso(t, Vector2.ZERO, Vector2(1.12, 0.88), 0.0, 0.12, Tween.TRANS_QUAD, Tween.EASE_IN)
	_volver(t, 0.25)
	return t


## Devuelve todo a la normalidad (al empezar una ronda nueva).
func reiniciar() -> void:
	_parar_auto_anim()
	if _tween and _tween.is_valid():
		_tween.kill()
	if _tween_color and _tween_color.is_valid():
		_tween_color.kill()
	_sin_respirar = false
	_temblor_tiempo = 0.0
	_estela_tiempo = 0.0
	estelas.clear()
	desp_accion = Vector2.ZERO
	escala_accion = Vector2.ONE
	rot_accion = 0.0
	salida_color = Color.WHITE
	_pos_anterior = Vector2.INF
	_vel = Vector2.ZERO
	_en_suelo_antes = true


func temblar(duracion := 0.15, fuerza := 3.0) -> void:
	_temblor_tiempo = duracion
	_temblor_fuerza = fuerza


## Ejecuta una acción a partir de un evento de CombatSim.anim_events.
func ejecutar(evento: Dictionary, f: FighterState) -> void:
	var tipo := String(evento.get("tipo", ""))
	if AutoAnim2D.ACCIONES.has(tipo) and usar_auto_anim(tipo, {"fuerza": float(evento.get("fuerza", 1.0))}):
		# Animación del panel AutoAnim; el dash conserva su estela.
		if tipo == "dash":
			_estela_tiempo = float(_clip["duracion"])
			_estela_reloj = 0.0
			if evento.has("desde"):
				_estela_en_recorrido(float(evento["desde"]), f)
		return
	# El derribo ya se dibuja desde FighterState; sin clip no añade otro golpe.
	if tipo == "derribo":
		return
	var base := String(evento.get("base", AutoAnim2D.RESPALDO.get(tipo, tipo)))
	match base:
		"golpe":
			golpe()
		"patada":
			patada()
		"golpe_recibido":
			recibir_golpe(float(evento.get("fuerza", 1.0)))
		"bloqueo":
			bloquear()
		"dash":
			dash()
			if evento.has("desde"):
				_estela_en_recorrido(float(evento["desde"]), f)
		"ko":
			ko()
		"victoria":
			victoria()
		"reiniciar":
			reiniciar()


## En este juego el dash de Volt es un teletransporte (avanza de golpe), así que
## las copias se reparten por el camino recorrido; las más lejanas se apagan antes.
func _estela_en_recorrido(desde_x: float, f: FighterState) -> void:
	if ultimo_cuadro.is_empty():
		return
	var copias := 5
	for i in range(copias):
		var avance := float(i) / float(copias)
		estelas.append({
			"x": lerpf(desde_x, f.x, avance), "y": f.y, "facing": f.facing,
			"cuadro": ultimo_cuadro.duplicate(), "tiempo": ultimo_tiempo,
			"desp": Vector2.ZERO, "escala": Vector2(1.1, 0.92), "rot": 8.0,
			"vida": VIDA_ESTELA * (0.5 + 0.5 * avance),
		})


func _crear_estela(f: FighterState) -> void:
	if ultimo_cuadro.is_empty():
		return
	# Si está quieto, no se apilan copias en el mismo sitio.
	if not estelas.is_empty() and absf(float(estelas[-1]["x"]) - f.x) < 2.0:
		return
	estelas.append({
		"x": f.x, "y": f.y, "facing": f.facing, "cuadro": ultimo_cuadro.duplicate(),
		"tiempo": ultimo_tiempo, "desp": salida_desp, "escala": salida_escala,
		"rot": salida_rot, "vida": VIDA_ESTELA,
	})
