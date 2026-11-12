extends Node
## Intro cinematográfica de Madara Edo (≈11 s) antes del primer asalto.
##   Fase 1 (0-2 s)  oscuridad, viento, polvo y temblor ligero.
##   Fase 2 (2-4 s)  humo; Madara aparece (silueta -> armadura) y la cámara se acerca.
##   Fase 3 (4-6 s)  primer plano: sello de mano, brillo rojo en los ojos y corte del Sharingan.
##   Fase 4 (6-9 s)  aura de chakra azul y morada, ondas, sacudida y música que crece.
##   Fase 5 (9-11 s) nombre «MADARA UCHIHA», pose de combate y la cámara vuelve.
## Después fight.gd anuncia «RONDA 1» y «¡PELEA!» como siempre y devuelve el control.
##
## No toca la simulación: el combate está en el estado "ready" (nadie se mueve ni ataca)
## mientras dura. Solo usa ArenaView.cinematic (cuadro y tinte), la cámara y capas propias.
## Se puede saltar con Aceptar / Pausa.

signal intro_started
signal intro_finished

const WorldFx := preload("res://scripts/fight/intros/intro_world_fx.gd")
const SheetSprite := preload("res://scripts/fight/intros/intro_sheet_sprite.gd")
## Cuadros de la hoja de la intro por fase: [fase, inicio, fin] (segundos). Entre fases se
## mantiene el último cuadro. Al final se funde con el sprite de combate (MEZCLA).
const PLAN_HOJA := [["aparicion", 0.15, 2.0], ["materializacion", 2.0, 4.0], ["sello", 4.0, 5.6],
	["chakra", 6.0, 9.0], ["presentacion", 9.0, 10.6]]
const MEZCLA := [10.62, 10.82]
const DIR := "res://assets/intros/madara_edo/"
## Sonidos: primero el archivo definitivo si lo añades; si no, el provisional generado.
const SONIDOS := {
	"musica": ["Intro_Music.ogg", "audio/musica_intro.wav"],
	"viento": ["Wind_SFX.ogg", "audio/viento.wav"],
	"humo": ["Smoke_SFX.ogg", "audio/humo.wav"],
	"sharingan": ["Sharingan_SFX.ogg", "audio/sharingan.wav"],
	"chakra": ["Chakra_SFX.ogg", "audio/chakra.wav"],
	"onda": ["Wave_SFX.ogg", "audio/onda.wav"],
}
const DURACION := 11.0
const ROJO := Color(0.86, 0.08, 0.1)
const AZUL := Color(0.32, 0.55, 1.0)
const MORADO := Color(0.58, 0.25, 0.95)

## Solo una intro a la vez en todo el juego.
static var activa := false

# ---- Estado que leen los efectos (intro_world_fx.gd e intro_overlay.gd) ----
var oscuridad := 0.0
var luz := 0.0                ## resplandor detrás de Madara
var polvo := 0.0
var aura := 0.0
var brillo_ojos := 0.0
var rayos := 0.0
var barras := 0.0             ## franjas negras de cine
var corte := 0.0              ## corte del Sharingan (0 oculto, 1 dentro)
var sharingan := 0.0          ## 0 ojo normal -> 1 Sharingan activado
var giro_tomoe := 0.0
var destello := 0.0
var color_destello := Color.WHITE
var tarjeta := 0.0            ## nombre y subtítulo
var tiempo := 0.0
var particulas: Array = []    ## {pos, vel, vida, max, r, color, tipo, delante}
var anillos: Array = []       ## {t, color}
var centro := Vector2.ZERO    ## pies de Madara (coordenadas de la arena 480x270)
var ojo := Vector2.ZERO       ## ojos de Madara (coordenadas de la arena)
var mira := 1.0

# ---- Control de Madara, el rival y la cámara ----
var madara_alpha := 0.0
var rival_luz := 1.0
var cuadro := ""
var zoom := 1.0
var foco := Vector2(480, 270)  ## centro de la cámara (coordenadas del mundo)
var temblor := 0.0

var _ctx: Dictionary = {}
var _sim: CombatSim
var _arena: ArenaView
var _camara: Camera2D
var _madara: FighterState
var _rival: FighterState
var _fx_detras: Node2D
var _fx_delante: Node2D
var _overlay: Control
var _tweens: Array[Tween] = []
var _saltar := false
var _terminada := false
var _ocultos: Array = []
var _audio := {}
var _idle: Array = []
## Hoja de la intro dibujada por el usuario (si está importada): cuadros, ojos y retrato.
var _hoja: Node2D
var _usa_hoja := false
var ojos_tex: Texture2D
var ojos_rects := {}
var retrato_tex: Texture2D
var _alto := 76.0  ## altura del personaje en la arena (coronilla -> pies)


## contexto: {sim, arena, camera, fight, hud, screen_fx, index, ocultar: [CanvasItem...]}
func play(contexto: Dictionary) -> void:
	if activa:
		push_warning("Intro de Madara: ya hay una intro en marcha")
		return
	_ctx = contexto
	_sim = contexto.get("sim")
	_arena = contexto.get("arena")
	_camara = contexto.get("camera")
	if _sim == null or _arena == null or _camara == null:
		push_warning("Intro de Madara: faltan la simulación, la arena o la cámara")
		return
	var index := int(contexto.get("index", 1))
	_madara = _sim.fighter_by_index(index)
	_rival = _sim.player if _madara == _sim.enemy else _sim.enemy
	if _madara == null:
		return
	activa = true
	_preparar()
	intro_started.emit()
	await _secuencia()
	await _cerrar()
	activa = false
	intro_finished.emit()


func _exit_tree() -> void:
	# Si la escena se cierra a media intro, no dejar nada a medias.
	if not _terminada:
		_restaurar(false)
		activa = false


# ================================================================ Preparación

func _preparar() -> void:
	var d := _madara.definition
	# Antes del primer cuadro de combate la simulación aún no los ha orientado: que se miren
	# (es lo mismo que hará CombatSim en su primera actualización).
	if _rival and _rival != _madara and not is_equal_approx(_rival.x, _madara.x):
		_madara.facing = 1 if _rival.x > _madara.x else -1
		_rival.facing = -_madara.facing
	mira = float(_madara.facing)
	centro = Vector2(_madara.x, CombatSim.FLOOR + _madara.y)
	ojo = punto_del_sprite(d, _madara.x, CombatSim.FLOOR + _madara.y, _madara.facing,
		(d.get("sprite_head", Vector2(73, 15)) as Vector2) + Vector2(3, 2))
	_idle = _lista(d, "idle")
	cuadro = _cuadro(d, "intro", 0)
	foco = _camara.position
	zoom = _camara.zoom.x
	var fight: Node = _ctx.get("fight")
	if fight:
		fight.set("cinematic_camera", true)

	_fx_detras = WorldFx.new()
	_fx_detras.name = "IntroFxDetras"
	_fx_detras.set("ctrl", self)
	_fx_detras.set("delante", false)
	_arena.add_child(_fx_detras)
	_arena.move_child(_fx_detras, 0)  # tras el escenario, antes de los luchadores
	_fx_delante = WorldFx.new()
	_fx_delante.name = "IntroFxDelante"
	_fx_delante.set("ctrl", self)
	_fx_delante.set("delante", true)
	_arena.add_child(_fx_delante)
	_preparar_hoja(d)

	_overlay = $Cine/Overlay
	_overlay.set("ctrl", self)
	_overlay.call("preparar", String(d.get("name", "Madara")))

	for key in SONIDOS:
		_audio[key] = cargar_sonido(String(key))
	for item in _ctx.get("ocultar", []):
		if item is CanvasItem and (item as CanvasItem).visible:
			_ocultos.append(item)
			var tw := _tw()
			tw.tween_property(item, "modulate:a", 0.0, 0.4)
	Sfx.stop_music()
	_sincronizar()


## Usa la hoja del usuario (assets/fighters/madara_edo/intro/) si está importada.
func _preparar_hoja(d: Dictionary) -> void:
	var cabeza := punto_del_sprite(d, _madara.x, centro.y, _madara.facing, d.get("sprite_head", Vector2(73, 15)) as Vector2)
	_alto = absf(centro.y - cabeza.y) * 1.12
	var m := SheetSprite.leer_manifiesto()
	if m.is_empty():
		return
	_hoja = SheetSprite.new()
	_hoja.name = "IntroHoja"
	if not _hoja.call("preparar", m):
		_hoja.free()
		_hoja = null
		return
	_usa_hoja = true
	# Misma x que la cabeza del sprite de combate, para que el fundido final no se vea doble.
	_hoja.position = Vector2(cabeza.x, centro.y)
	_hoja.set("mira", mira)
	_hoja.set("escala", _alto / maxf(float(m.get("alto_figura", 90.0)), 1.0))
	_hoja.set("alfa", 0.0)
	_arena.add_child(_hoja)
	# En el sitio de la capa de Madara: delante del fondo y detrás de los efectos delanteros.
	_arena.move_child(_hoja, _arena.get_children().find(_arena.fighter_layer(_madara.index)))
	ojo = centro + Vector2(mira * 2.0, -_alto * 0.88)
	var ojos: Dictionary = m.get("ojos", {})
	if ResourceLoader.exists(String(ojos.get("atlas", ""))):
		ojos_tex = load(String(ojos["atlas"]))
		ojos_rects = ojos
	if ResourceLoader.exists(String(m.get("retrato", ""))):
		retrato_tex = load(String(m["retrato"]))


## Cuadro de la hoja que toca en el segundo t (índice del atlas, o -1).
func cuadro_hoja(t: float) -> int:
	if _hoja == null:
		return -1
	var elegido := -1
	for paso in PLAN_HOJA:
		var fase := String(paso[0])
		var n: int = _hoja.call("cuantos", fase)
		if n <= 0 or t < float(paso[1]):
			continue
		var k := clampf((t - float(paso[1])) / (float(paso[2]) - float(paso[1])), 0.0, 0.9999)
		elegido = _hoja.call("indice", fase, int(k * n))
	return elegido


## Carga un sonido de la intro (el definitivo si existe; si no, el provisional). null si no hay.
static func cargar_sonido(clave: String) -> AudioStream:
	for nombre in SONIDOS.get(clave, []):
		var ruta: String = DIR + String(nombre)
		if ResourceLoader.exists(ruta):
			var s := load(ruta) as AudioStream
			if s:
				return s
	return null


## Convierte un punto de la imagen del luchador (píxeles del cuadro) a la arena.
static func punto_del_sprite(definition: Dictionary, x: float, foot: float, facing: int, px: Vector2) -> Vector2:
	var anchor: Variant = definition.get("sprite_anchor", Vector2(73, 89))
	if anchor is Dictionary:
		anchor = (anchor as Dictionary).get("idle", Vector2(73, 89))
	var alto := 89.0
	var idle: Array = _lista(definition, "idle")
	if not idle.is_empty():
		var partes := String(idle[0]).get_slice("#", 1).split(",")
		if partes.size() == 4:
			alto = float(partes[3])
	var upp := float(definition.get("sprite_height", 60.0)) / alto
	var escala := float(definition.get("sprite_scale", 1.0))
	var rel := (px - (anchor as Vector2)) * upp * escala
	return Vector2(x + rel.x * facing, foot + rel.y)


static func _lista(definition: Dictionary, clave: String) -> Array:
	var sprites: Dictionary = definition.get("sprites", {})
	var v: Variant = sprites.get(clave)
	if v is Array:
		return v
	if v is String:
		return [v]
	return []


## Cuadro i de una animación del catálogo (si no existe, el primero de idle).
static func _cuadro(definition: Dictionary, clave: String, i: int) -> String:
	var lista := _lista(definition, clave)
	if lista.is_empty():
		lista = _lista(definition, "idle")
	if lista.is_empty():
		return ""
	return String(lista[clampi(i, 0, lista.size() - 1)])


# ================================================================ Secuencia

func _secuencia() -> void:
	var d := _madara.definition
	var cuerpo := _mundo(centro + Vector2(0, -_alto * 0.48))
	var cara := _mundo(ojo + Vector2(-mira * 2.0, 2.0))

	# ---- FASE 1: oscuridad y suspenso (0-2 s)
	_sonar("musica")
	_sonar("viento", -4.0)
	var t := _tw().set_parallel(true)
	t.tween_property(self, "barras", 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "oscuridad", 0.72, 2.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "rival_luz", 0.3, 1.6)
	t.tween_property(self, "polvo", 1.0, 1.2)
	t.tween_property(self, "temblor", 1.2, 1.5)
	t.tween_property(self, "zoom", 1.1, 2.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", foco.lerp(cuerpo, 0.25), 2.0).set_trans(Tween.TRANS_SINE)
	if not await _hasta(2.0): return

	# ---- FASE 2: aparición entre el humo (2-4 s)
	_sonar("humo")
	_humo(centro, 14 if _usa_hoja else 60)
	temblor = 0.6
	t = _tw().set_parallel(true)
	t.tween_property(self, "madara_alpha", 1.0, 0.7).set_delay(0.15)
	t.tween_property(self, "luz", 0.55, 1.2)
	t.tween_property(self, "zoom", 1.75, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "foco", cuerpo, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not await _hasta(2.75): return
	cuadro = _cuadro(d, "intro", 1)
	if not await _hasta(3.3): return
	cuadro = _cuadro(d, "intro", 2)  # armadura roja, brazos cruzados
	if not _usa_hoja:
		_humo(centro, 16)

	# ---- FASE 3: Sharingan (4-6 s)
	if not await _hasta(4.0): return
	cuadro = _cuadro(d, "charge", 3)  # sello de mano junto a la cara
	temblor = 0.0
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 3.4, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "foco", cara, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "oscuridad", 0.85, 0.4)
	t.tween_property(self, "brillo_ojos", 1.0, 0.5).set_delay(0.3)
	if not await _hasta(4.5): return
	_sonar("sharingan")
	t = _tw().set_parallel(true)
	t.tween_property(self, "corte", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "sharingan", 1.0, 0.8).set_delay(0.3)
	t.tween_property(self, "giro_tomoe", TAU * 2.0, 0.85).set_delay(0.15).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if not await _hasta(5.0): return
	_pulso(ROJO, 0.35)
	_chispas(ojo, ROJO, 14, 30.0)
	if not await _hasta(5.65): return
	_destello(Color(1.0, 0.2, 0.15), 0.6)
	t = _tw()
	t.tween_property(self, "corte", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# ---- FASE 4: liberación del chakra (6-9 s)
	if not await _hasta(6.0): return
	cuadro = _cuadro(d, "special", 0)  # se agacha reuniendo chakra
	_sonar("chakra")
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.6, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "foco", cuerpo + Vector2(0, -10), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "aura", 0.25 if _usa_hoja else 0.55, 0.9)
	t.tween_property(self, "brillo_ojos", 0.7, 0.9)
	t.tween_property(self, "oscuridad", 0.7, 0.9)
	t.tween_property(self, "temblor", 1.5, 0.9)
	if not await _hasta(6.9): return
	cuadro = _cuadro(d, "intro", 2)  # se yergue: estallido de chakra
	_estallido(1.0)
	t = _tw().set_parallel(true)
	t.tween_property(self, "aura", 0.45 if _usa_hoja else 1.0, 0.25)
	t.tween_property(self, "rayos", 1.0, 0.3)
	t.tween_property(self, "luz", 1.0, 0.3)
	t.tween_property(self, "zoom", 1.35, 1.8).set_trans(Tween.TRANS_SINE)
	if not await _hasta(7.6): return
	_estallido(0.7)
	if not await _hasta(8.3): return
	_estallido(0.85)

	# ---- FASE 5: presentación y transición (9-11 s)
	if not await _hasta(9.0): return
	_destello(Color.WHITE, 0.75)
	cuadro = _cuadro(d, "intro", 3)
	temblor = 0.0
	t = _tw().set_parallel(true)
	t.tween_property(self, "tarjeta", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "rayos", 0.0, 0.6)
	t.tween_property(self, "aura", 0.0, 1.4).set_delay(0.4)
	t.tween_property(self, "brillo_ojos", 0.0, 1.0).set_delay(0.6)
	t.tween_property(self, "luz", 0.0, 1.3).set_delay(0.4)
	t.tween_property(self, "oscuridad", 0.0, 1.3).set_delay(0.5)
	t.tween_property(self, "rival_luz", 1.0, 1.0).set_delay(0.8)
	t.tween_property(self, "polvo", 0.0, 1.0).set_delay(0.5)
	t.tween_property(self, "zoom", 1.0, 1.2).set_delay(0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "foco", Vector2(480, 270), 1.2).set_delay(0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not await _hasta(9.3): return
	cuadro = _cuadro(d, "intro", 4)
	if not await _hasta(9.6): return
	cuadro = _cuadro(d, "intro", 5)  # posición de combate
	if not await _hasta(10.2): return
	t = _tw().set_parallel(true)
	t.tween_property(self, "tarjeta", 0.0, 0.35).set_delay(0.2)
	t.tween_property(self, "barras", 0.0, 0.5).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await _hasta(DURACION)


## Espera hasta el segundo t de la intro. Devuelve false si el jugador la saltó.
func _hasta(t: float) -> bool:
	while tiempo < t and not _saltar and is_inside_tree():
		await get_tree().process_frame
	return not _saltar and is_inside_tree()


func _cerrar() -> void:
	for tw in _tweens:
		if tw and tw.is_valid():
			tw.kill()
	_tweens.clear()
	if _saltar and is_inside_tree():
		# Salida rápida: todo se desvanece a la vez.
		var t := _tw().set_parallel(true)
		for prop in ["oscuridad", "luz", "polvo", "aura", "brillo_ojos", "rayos", "barras", "corte", "tarjeta", "destello", "temblor"]:
			t.tween_property(self, prop, 0.0, 0.3)
		t.tween_property(self, "madara_alpha", 1.0, 0.2)
		t.tween_property(self, "rival_luz", 1.0, 0.3)
		t.tween_property(self, "zoom", 1.0, 0.3)
		t.tween_property(self, "foco", Vector2(480, 270), 0.3)
		for key in _audio:
			var p := get_node_or_null("Audio_" + String(key)) as AudioStreamPlayer
			if p and p.playing:
				t.tween_property(p, "volume_db", -40.0, 0.3)
		await t.finished
	_restaurar()


## Devuelve todo como estaba: cámara, luchadores, HUD, música. Se llama siempre una vez.
func _restaurar(volver_musica := true) -> void:
	if _terminada:
		return
	_terminada = true
	if _arena and is_instance_valid(_arena):
		_arena.cinematic.clear()
	for n in [_fx_detras, _fx_delante, _hoja]:
		if n and is_instance_valid(n):
			n.queue_free()
	if _camara and is_instance_valid(_camara):
		_camara.zoom = Vector2.ONE
		_camara.position = Vector2(480, 270)
		_camara.offset = Vector2.ZERO
	var fight: Node = _ctx.get("fight")
	if fight and is_instance_valid(fight):
		fight.set("cinematic_camera", false)
	for item in _ocultos:
		if is_instance_valid(item):
			(item as CanvasItem).modulate.a = 1.0
	_ocultos.clear()
	for c in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
	particulas.clear()
	anillos.clear()
	if volver_musica:
		Sfx.play_music("battle")


# ================================================================ Cada cuadro

func _process(delta: float) -> void:
	if _madara == null or _terminada:
		return
	tiempo += delta
	_actualizar_particulas(delta)
	if polvo > 0.0 and randf() < polvo * 0.7:
		var lado := -1.0 if randf() < 0.5 else 1.0
		particulas.append({"pos": Vector2(-10.0 if lado > 0 else 490.0, randf_range(120.0, CombatSim.FLOOR + 4.0)),
			"vel": Vector2(lado * randf_range(40.0, 90.0), randf_range(-6.0, 2.0)), "vida": 0.0, "max": randf_range(4.0, 7.0),
			"r": 1.0, "color": Color(0.62, 0.55, 0.5, 0.55), "tipo": "polvo", "delante": randf() < 0.5})
	if aura > 0.2 and randf() < aura:
		var col := AZUL if randf() < 0.55 else MORADO
		particulas.append({"pos": centro + Vector2(randf_range(-18, 18), randf_range(-60, 0)), "vel": Vector2(randf_range(-8, 8), randf_range(-60, -30)),
			"vida": 0.0, "max": randf_range(0.5, 1.0), "r": 1.0, "color": col.lightened(0.3), "tipo": "chispa", "delante": randf() < 0.6})
	_sincronizar()


func _sincronizar() -> void:
	if _madara == null:
		return
	if madara_alpha > 0.5 and tiempo >= 10.0 and not _idle.is_empty():
		var ft := float((_madara.definition.get("sprite_frame_time", {}) as Dictionary).get("idle", 0.12))
		cuadro = String(_idle[int(tiempo / maxf(ft, 0.05)) % _idle.size()])
	var alfa_juego := madara_alpha
	if _usa_hoja and is_instance_valid(_hoja):
		var mezcla := clampf((tiempo - float(MEZCLA[0])) / (float(MEZCLA[1]) - float(MEZCLA[0])), 0.0, 1.0)
		if _saltar or _terminada:
			mezcla = 1.0
		_hoja.set("cuadro", cuadro_hoja(tiempo))
		_hoja.set("alfa", clampf(tiempo / 0.3, 0.0, 1.0) * (1.0 - mezcla))
		alfa_juego = mezcla
	_arena.cinematic[_madara.index] = {"sprite": cuadro, "tint": Color(1, 1, 1, alfa_juego)}
	if _rival and _rival != _madara:
		_arena.cinematic[_rival.index] = {"tint": Color(rival_luz, rival_luz, rival_luz * 1.15, 1.0)}
	var z := maxf(zoom, 1.0)
	var mitad := Vector2(480, 270) / z
	_camara.zoom = Vector2(z, z)
	_camara.position = Vector2(clampf(foco.x, mitad.x, 960.0 - mitad.x), clampf(foco.y, mitad.y, 540.0 - mitad.y))
	_camara.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * temblor * 2.0 / z if temblor > 0.0 else Vector2.ZERO


func _actualizar_particulas(delta: float) -> void:
	var vivas: Array = []
	for p in particulas:
		p["vida"] += delta
		if p["vida"] >= p["max"]:
			continue
		p["pos"] += p["vel"] * delta
		match String(p["tipo"]):
			"humo":
				p["vel"] *= 1.0 - delta * 1.6
				p["vel"].y -= 6.0 * delta
				p["r"] += delta * 6.0
			"chispa":
				p["vel"].x += sin(tiempo * 9.0 + p["pos"].y) * 30.0 * delta
			"polvo":
				p["vel"].y += sin(tiempo * 2.0 + p["pos"].x * 0.05) * 4.0 * delta
		vivas.append(p)
	particulas = vivas
	var quedan: Array = []
	for a in anillos:
		if tiempo - float(a["t"]) < 1.0:
			quedan.append(a)
	anillos = quedan


func _unhandled_input(event: InputEvent) -> void:
	if _saltar or _terminada or _madara == null:
		return
	for accion in ["ui_accept", "pause", "p1_menu_accept"]:
		if InputMap.has_action(accion) and event.is_action_pressed(accion):
			get_viewport().set_input_as_handled()
			saltar()
			return


## Termina la intro ya (fundido corto). La usa el botón de saltar y las pruebas.
func saltar() -> void:
	_saltar = true


# ================================================================ Ayudas

func _tw() -> Tween:
	var tw := create_tween()
	_tweens.append(tw)
	return tw


## Punto de la arena (480x270) -> mundo (la arena está escalada x2).
func _mundo(p: Vector2) -> Vector2:
	return _arena.transform * p


func _sonar(clave: String, volumen := 0.0) -> void:
	var stream: AudioStream = _audio.get(clave)
	if stream == null:
		return
	var nombre := "Audio_" + clave
	var p := get_node_or_null(nombre) as AudioStreamPlayer
	if p == null:
		p = AudioStreamPlayer.new()
		p.name = nombre
		p.bus = "Music" if clave == "musica" else "SFX"
		add_child(p)
	p.stream = stream
	p.volume_db = volumen
	p.play()


func _humo(en: Vector2, cantidad: int) -> void:
	for i in cantidad:
		var a := randf() * TAU
		var dist := randf_range(2.0, 20.0)
		var tono := randf_range(0.07, 0.16)
		particulas.append({"pos": en + Vector2(cos(a) * dist, -randf_range(0.0, 60.0)),
			"vel": Vector2(cos(a) * randf_range(15.0, 45.0), randf_range(-18.0, 4.0)),
			"vida": 0.0, "max": randf_range(0.9, 1.7), "r": randf_range(3.0, 6.5),
			"color": Color(tono, tono * 0.85, tono * 1.2, 0.7), "tipo": "humo", "delante": i % 4 == 0})


func _chispas(en: Vector2, color: Color, cantidad: int, fuerza: float) -> void:
	for i in cantidad:
		var a := randf() * TAU
		particulas.append({"pos": en, "vel": Vector2(cos(a), sin(a)) * randf_range(0.4, 1.0) * fuerza,
			"vida": 0.0, "max": randf_range(0.3, 0.7), "r": 1.0, "color": color.lightened(0.2), "tipo": "chispa", "delante": true})


func _estallido(fuerza: float) -> void:
	_sonar("onda", -2.0 + fuerza * 2.0)
	anillos.append({"t": tiempo, "color": AZUL if anillos.size() % 2 == 0 else MORADO})
	temblor = 2.5 * fuerza
	var t := _tw()
	t.tween_property(self, "temblor", 1.0, 0.45)
	_chispas(centro + Vector2(0, -30), AZUL, int(18 * fuerza), 120.0)
	_chispas(centro + Vector2(0, -30), MORADO, int(12 * fuerza), 90.0)
	var fx: Variant = _ctx.get("screen_fx")
	if fx and is_instance_valid(fx):
		var uv := _arena.get_global_transform_with_canvas() * (centro + Vector2(0, -30))
		fx.call("shockwave", uv / get_viewport().get_visible_rect().size, 0.6 * fuerza)
	_pulso(MORADO, 0.25 * fuerza)


func _pulso(color: Color, cantidad: float) -> void:
	var fx: Variant = _ctx.get("screen_fx")
	if fx and is_instance_valid(fx):
		fx.call("pulse", color, cantidad)


func _destello(color: Color, fuerza: float) -> void:
	color_destello = color
	destello = fuerza
	var t := _tw()
	t.tween_property(self, "destello", 0.0, 0.35)
