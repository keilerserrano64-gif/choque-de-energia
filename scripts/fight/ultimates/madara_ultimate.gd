extends Node
## Definitivo de Madara Edo: «EL JUICIO DEL DIOS DE LA GUERRA · TENGAI SHINSEI» (≈26 s).
## Se lanza con H (despertar) cuando el despertar ya está activo. Orden fijo:
##   Susanoo Perfecto y tajo -> carcajada -> primer meteorito -> se revela el segundo ->
##   caen los dos -> Madara de pie entre las ruinas.
## La simulación queda congelada (CombatSim.ultimate_active, fight.gd deja de llamar a
## update), así que nadie se mueve ni ataca. Los tres golpes pasan por CombatSim.ultimate_hit()
## (usa hit(): respeta las reglas, sin duplicados). El K.O., si lo hay, lo declara la
## simulación al reanudar. Esc la acorta aplicando los golpes que falten.

signal ultimate_started
signal ultimate_finished
signal estado_cambiado(estado: Estado)

enum Estado {
	PREPARANDO_ATAQUE, ACTIVANDO_SUSANOO, ATACANDO_CON_SUSANOO, RIENDO_MADARA,
	INVOCANDO_METEORITOS, CAYENDO_PRIMER_METEORITO, CAYENDO_SEGUNDO_METEORITO,
	IMPACTO_FINAL, RECUPERANDO_COMBATE, TERMINADO,
}

const IntroMadara := preload("res://scripts/fight/intros/madara_edo_intro.gd")
const WorldFx := preload("res://scripts/fight/ultimates/ultimate_world_fx.gd")
const SusanooPainter := preload("res://scripts/fight/ultimates/susanoo_painter.gd")
const UltimateSheet := preload("res://scripts/fight/ultimates/ultimate_sheet.gd")
const UltimateSheetV2 := preload("res://scripts/fight/ultimates/ultimate_sheet_v2.gd")
const SheetSprite := preload("res://scripts/fight/intros/intro_sheet_sprite.gd")
const DIR := "res://assets/ultimates/madara_edo/"
## Sonido definitivo opcional (si lo añades en la carpeta) y el provisional generado.
const SONIDOS := {
	"musica": ["Ultimate_Music.ogg", "audio/musica_definitivo.wav"],
	"amenaza": ["Threat_SFX.ogg", "audio/amenaza.wav"],
	"susanoo": ["Susanoo_SFX.ogg", "audio/susanoo.wav"],
	"espada_alza": ["Sword_Raise_SFX.ogg", "audio/espada_alza.wav"],
	"espada_tajo": ["Sword_Slash_SFX.ogg", "audio/espada_tajo.wav"],
	"risa": ["Madara_Laugh.ogg", "audio/risa.wav"],
	"cielo": ["Sky_SFX.ogg", "audio/cielo.wav"],
	"meteoro": ["Meteor_Fall_SFX.ogg", "audio/meteoro_cae.wav"],
	"explosion1": ["Explosion1_SFX.ogg", "audio/explosion1.wav"],
	"explosion2": ["Explosion2_SFX.ogg", "audio/explosion2.wav"],
	"frase": ["Madara_Line.ogg", ""],
}
## Momentos clave (segundos de la escena).
const T_TAJO := 7.8
const T_IMPACTO_SUSANOO := 8.0
const T_IMPACTO_1 := 21.0
const T_IMPACTO_2 := 23.0
const T_FIN := 27.0
const AZUL := Color(0.32, 0.55, 1.0)
const MORADO := Color(0.58, 0.3, 1.0)

static var activa := false

# ---- Estado que leen los efectos ----
var estado: Estado = Estado.PREPARANDO_ATAQUE
var tiempo := 0.0
var oscuridad := 0.0
var rojo := 0.0
var nubes := 0.0
var chakra := 0.0
var brillo_ojos := 0.0
var barras := 0.0
var corte := 0.0
var risa := 0.0
var titulos := 0.0
var frase := 0.0
var humo_pantalla := 0.0
var destello := 0.0
var color_destello := Color.WHITE
var particulas: Array = []
var meteoritos: Array = []
var rocas: Array = []
var crateres: Array = []
var explosiones: Array = []
var ondas: Array = []
var centro := Vector2.ZERO
var ojo := Vector2.ZERO
var mira := 1.0
var cabeza_pantalla := Vector2(480, 200)

# ---- Control de luchadores y cámara ----
var madara_cuadro := ""
var madara_proc := {}
var rival_anim := ""          ## animación real del rival a mostrar ("fall" = tumbado, "hurt")
var rival_frames := 0.0
var rival_sprite := ""        ## imagen fija del rival (su cuadro "down" ya viene tumbado)
var rival_luz := 1.0
var zoom := 1.0
var foco := Vector2(480, 270)
var temblor := 0.0

var _ctx: Dictionary = {}
var _sim: CombatSim
var _arena: ArenaView
var _camara: Camera2D
var _madara: FighterState
var _rival: FighterState
var _lado := 1.0               ## dirección de Madara hacia el rival (+1 derecha)
var _susanoo: Node2D
var _grupo: CanvasGroup
## Hoja dibujada por el usuario (si está importada): Madara con su Susanoo cuadro a cuadro
## y planos de escena a pantalla completa para los meteoritos y los impactos.
var _hoja: Node2D
## Hoja v2 (la nueva del usuario, 30 s): capas -> nodo que dibuja sus cuadros.
var _v2 := false
var _v2m: Dictionary = {}
var _capas: Dictionary = {}
## Segundos de los tres golpes (las pruebas los leen).
var tiempos_golpes: Array = [T_IMPACTO_SUSANOO, T_IMPACTO_1, T_IMPACTO_2]
var _caida_v2: Dictionary = {}
## [aparecen los meteoritos, cae el primero, cae el segundo] (la hoja v2 los retrasa).
var _t_caida: Array = [15.5, T_IMPACTO_1, T_IMPACTO_2]
var _hoja_luz: Node2D          ## Susanoo de la hoja en modo luz, detrás de Madara
var _usa_hoja := false
## Sprites de efectos de la hoja ({nombre: {tex, ancla}}) y los que están en pantalla:
## [{nombre, pos, t, dur, escala, rot, delante, crece}].
var efx: Dictionary = {}
var sprites_fx: Array = []
var _manifiesto: Dictionary = {}
var escenas_tex: Texture2D
var escenas_cuadros: Array = []
var plano_tipo := ""          ## "personaje" o "escenas": de qué atlas sale el plano de cine
var plano_cuadro := -1
var personaje_tex: Texture2D
var personaje_cuadros: Array = []
var _escala_hoja := 1.0
var plano_alfa := 0.0
var tajo_pantalla := 0.0       ## tajo blanco que cruza la pantalla en el impacto del Susanoo
var retrato_tex: Texture2D
var logo_tex: Texture2D
var _fx_detras: Node2D
var _fx_delante: Node2D
var _overlay: Control
var _tweens: Array[Tween] = []
var _audio := {}
var _golpes_hechos := {}
var _saltar := false
var _terminada := false
var _ocultos: Array = []
var _caida := {}               ## trayectorias de los meteoritos


## contexto: {sim, arena, camera, fight, screen_fx, index, ocultar: [CanvasItem...]}
func play(contexto: Dictionary) -> void:
	if activa:
		push_warning("Definitivo de Madara: ya hay uno en marcha")
		return
	_ctx = contexto
	_sim = contexto.get("sim")
	_arena = contexto.get("arena")
	_camara = contexto.get("camera")
	if _sim == null or _arena == null or _camara == null:
		push_warning("Definitivo de Madara: faltan la simulación, la arena o la cámara")
		return
	_madara = _sim.fighter_by_index(int(contexto.get("index", 0)))
	if _madara == null:
		return
	_rival = _sim.opponent_of(_madara)
	activa = true
	_preparar()
	ultimate_started.emit()
	if _v2:
		await _secuencia_v2()
	else:
		await _secuencia()
	await _cerrar()
	activa = false
	ultimate_finished.emit()


func _exit_tree() -> void:
	if not _terminada:
		_aplicar_golpes_pendientes()
		_restaurar(false)
		# Al salir del combate se cancela el await de fight.gd que libera la simulacion.
		if _sim != null:
			_sim.end_ultimate()
		activa = false


func _cambiar(e: Estado) -> void:
	estado = e
	estado_cambiado.emit(e)


# ================================================================ Preparación

func _preparar() -> void:
	var d := _madara.definition
	_lado = 1.0 if _rival.x >= _madara.x else -1.0
	_madara.facing = int(_lado)
	_rival.facing = -int(_lado)
	mira = _lado
	centro = Vector2(_madara.x, CombatSim.FLOOR + _madara.y)
	ojo = IntroMadara.punto_del_sprite(d, _madara.x, centro.y, _madara.facing,
		(d.get("sprite_head", Vector2(73, 15)) as Vector2) + Vector2(3, 2))
	madara_cuadro = _cuadro(d, "idle", 0)
	foco = _camara.position
	zoom = _camara.zoom.x
	var fight: Node = _ctx.get("fight")
	if fight:
		fight.set("cinematic_camera", true)

	_fx_detras = WorldFx.new()
	_fx_detras.name = "DefinitivoFxDetras"
	_fx_detras.set("ctrl", self)
	_arena.add_child(_fx_detras)
	_arena.move_child(_fx_detras, 0)
	# Susanoo: en un CanvasGroup para que su transparencia sea uniforme, justo detrás de Madara.
	_grupo = CanvasGroup.new()
	_grupo.name = "SusanooGrupo"
	_grupo.self_modulate = Color(1, 1, 1, 0.82)
	_susanoo = SusanooPainter.new()
	_susanoo.position = Vector2(_madara.x - _lado * 12.0, CombatSim.FLOOR + 2.0)
	_susanoo.scale = Vector2(_lado, 1.0) * 0.85
	_susanoo.set("objetivo", absf(_rival.x - _susanoo.position.x) / 0.85)
	_grupo.add_child(_susanoo)
	_arena.add_child(_grupo)
	_arena.move_child(_grupo, _arena.get_children().find(_arena.fighter_layer(_madara.index)))
	if not _preparar_v2(d):
		_preparar_hoja(d)
	_fx_delante = WorldFx.new()
	_fx_delante.name = "DefinitivoFxDelante"
	_fx_delante.set("ctrl", self)
	_fx_delante.set("delante", true)
	_arena.add_child(_fx_delante)

	_overlay = $Cine/Overlay
	_overlay.set("ctrl", self)
	_overlay.call("preparar")
	for key in SONIDOS:
		_audio[key] = cargar_sonido(String(key))
	for item in _ctx.get("ocultar", []):
		if item is CanvasItem and (item as CanvasItem).visible:
			_ocultos.append(item)
			_tw().tween_property(item, "modulate:a", 0.0, 0.35)
	Sfx.stop_music()
	_preparar_meteoritos()
	_sincronizar()


## Hoja v2 (assets/fighters/madara_edo/definitivo_v2/): si está, manda sobre la anterior.
## Crea una capa por tipo de dibujo (ver ultimate_sheet_v2.gd). Devuelve true si la usa.
func _preparar_v2(d: Dictionary) -> bool:
	_v2m = UltimateSheetV2.leer_manifiesto()
	if _v2m.is_empty():
		return false
	var cabeza := IntroMadara.punto_del_sprite(d, _madara.x, centro.y, _madara.facing, d.get("sprite_head", Vector2(73, 15)) as Vector2)
	var alto := absf(centro.y - cabeza.y) * 1.12
	var escala := alto / maxf(float(_v2m.get("alto_figura", 50.0)), 1.0)
	var pies := Vector2(cabeza.x, centro.y)
	# Detrás de los luchadores: cielo y rocas que caen. Justo antes de la capa de Madara:
	# su Susanoo y él. Delante de todo: impactos y onda.
	var defs := [
		["susanoo", true, escala * 1.35, "madara"], ["aura", true, escala, "madara"], ["madara", false, escala, "madara"],
	]
	for def in defs:
		var n: Node2D = SheetSprite.new()
		n.name = "DefinitivoV2_" + String(def[0])
		n.set("luz", bool(def[1]))
		if not n.call("preparar", _v2m):
			n.free()
			for otro in _capas.values():
				(otro as Node).free()
			_capas.clear()
			return false
		n.set("mira", mira)
		n.set("escala", float(def[2]))
		n.set("cuadro", -1)
		n.position = pies
		_arena.add_child(n)
		match String(def[3]):
			"atras":
				_arena.move_child(n, 1)
			"madara":
				_arena.move_child(n, _fighter_index_capa())
		_capas[String(def[0])] = n
	_v2 = true
	_usa_hoja = true
	if _grupo:
		_grupo.visible = false
	tiempos_golpes = [UltimateSheetV2.GOLPES["susanoo"], UltimateSheetV2.GOLPES["meteoro1"], UltimateSheetV2.GOLPES["meteoro2"]]
	# Puntos de caída: el primero un poco más allá del rival, el segundo sobre él.
	var x1 := clampf(_rival.x + mira * 40.0, 40.0, 440.0)
	var x2 := clampf(_rival.x, 40.0, 440.0)
	_caida_v2 = {
		"fin_a": Vector2(x1, CombatSim.FLOOR + 2.0), "fin_b": Vector2(x2, CombatSim.FLOOR + 2.0),
		"inicio_a": Vector2(lerpf(x1, 240.0, 0.55) + mira * 30.0, 40.0), "inicio_b": Vector2(lerpf(x2, 240.0, 0.4) - mira * 20.0, 30.0),
		"cielo": Vector2(lerpf((x1 + x2) * 0.5, 240.0, 0.35), 150.0),
	}
	_t_caida = UltimateSheetV2.CAIDA.duplicate()
	# Rinnegan con sangre: plano de cine con los cuadros del atlas.
	personaje_tex = (_capas["madara"] as Node2D).get("atlas")
	personaje_cuadros = UltimateSheet.recortar_a_contenido(personaje_tex, _v2m.get("cuadros", []))
	for n3 in _capas.values():
		(n3 as Node2D).set("contenidos", personaje_cuadros)
	for clave in ["retrato", "logo"]:
		var ruta := String(_v2m.get(clave, ""))
		if ResourceLoader.exists(ruta):
			set(clave + "_tex", load(ruta))
	efx = UltimateSheet.leer_efectos()
	return true


func _fighter_index_capa() -> int:
	return _arena.get_children().find(_arena.fighter_layer(_madara.index))


## Pone el cuadro de cada capa de la hoja v2 y devuelve el alfa del sprite de combate.
func _sincronizar_v2() -> float:
	var fases: Dictionary = _v2m.get("fases", {})
	var fuera := _saltar or _terminada
	var t := tiempo
	var cuadros := {
		"madara": UltimateSheetV2.cuadro(fases, "madara", t),
		"susanoo": UltimateSheetV2.cuadro(fases, "susanoo", t),
	}
	for capa in cuadros:
		var n: Node2D = _capas.get(capa)
		if is_instance_valid(n):
			n.set("cuadro", -1 if fuera else int(cuadros[capa]))
	# El final se funde con el sprite de combate.
	var mezcla := clampf((t - 29.55) / 0.35, 0.0, 1.0)
	var madara_n: Node2D = _capas.get("madara")
	if is_instance_valid(madara_n):
		madara_n.set("alfa", 1.0 - mezcla)
		madara_n.set("ovalo", 1.0 if UltimateSheetV2.fase_de("madara", t) == "final" else 0.0)
		# El aura pintada en los cuadros de Madara se quita del sprite sólido y la pone
		# la capa "aura" como luz (así no queda el recuadro de la celda).
		madara_n.set("quitar_aura", 1.0)
		madara_n.set("lados", 1.0)
	var aura_n: Node2D = _capas.get("aura")
	if is_instance_valid(aura_n):
		aura_n.set("cuadro", -1 if fuera else int(cuadros["madara"]))
		aura_n.set("alfa", 1.0 - mezcla)
	var susanoo_n: Node2D = _capas.get("susanoo")
	if is_instance_valid(susanoo_n):
		susanoo_n.set("alfa", 1.0)
	# Planos de cine: la carcajada y el Rinnegan con sangre.
	var ojo_i := UltimateSheetV2.cuadro(fases, "plano", t)
	var k_ojo := UltimateSheetV2.avance("plano", t)
	plano_tipo = "personaje" if ojo_i >= 0 else ""
	plano_cuadro = ojo_i
	plano_alfa = 0.0 if (fuera or ojo_i < 0) else clampf(minf(k_ojo / 0.05, (1.0 - k_ojo) / 0.08), 0.0, 1.0)
	if fuera:
		return 1.0
	return mezcla if int(cuadros["madara"]) >= 0 else 1.0


## Usa la hoja del usuario (assets/fighters/madara_edo/definitivo/) si está importada.
func _preparar_hoja(d: Dictionary) -> void:
	_manifiesto = UltimateSheet.leer_manifiesto()
	if _manifiesto.is_empty():
		return
	var pj: Dictionary = _manifiesto["personaje"]
	_hoja = SheetSprite.new()
	_hoja.name = "DefinitivoHoja"
	if not _hoja.call("preparar", pj):
		_hoja.free()
		_hoja = null
		return
	_usa_hoja = true
	efx = UltimateSheet.leer_efectos()
	var cabeza := IntroMadara.punto_del_sprite(d, _madara.x, centro.y, _madara.facing, d.get("sprite_head", Vector2(73, 15)) as Vector2)
	var alto := absf(centro.y - cabeza.y) * 1.12
	_hoja.position = Vector2(cabeza.x, centro.y)
	_hoja.set("mira", mira)
	_hoja.set("escala", alto / maxf(float(pj.get("alto_figura", 90.0)), 1.0))
	_arena.add_child(_hoja)
	_arena.move_child(_hoja, _arena.get_children().find(_arena.fighter_layer(_madara.index)))
	# Susanoo: los mismos cuadros en modo luz, justo detrás de Madara.
	_hoja_luz = SheetSprite.new()
	_hoja_luz.name = "DefinitivoSusanooLuz"
	_hoja_luz.set("luz", true)
	_hoja_luz.call("preparar", pj)
	_hoja_luz.position = _hoja.position
	_hoja_luz.set("mira", mira)
	_hoja_luz.set("escala", _hoja.get("escala"))
	_hoja_luz.set("alfa", 0.0)
	_arena.add_child(_hoja_luz)
	_arena.move_child(_hoja_luz, _arena.get_children().find(_hoja))
	# El Susanoo de la hoja sustituye al dibujado con código.
	if _grupo:
		_grupo.visible = false
	personaje_tex = _hoja.get("atlas")
	personaje_cuadros = UltimateSheet.recortar_a_contenido(personaje_tex, pj.get("cuadros", []))
	_hoja.set("contenidos", personaje_cuadros)
	_escala_hoja = float(_hoja.get("escala"))
	var esc: Dictionary = _manifiesto.get("escenas", {})
	if ResourceLoader.exists(String(esc.get("atlas", ""))):
		escenas_tex = load(String(esc["atlas"]))
		escenas_cuadros = esc.get("cuadros", [])
	for clave in ["retrato", "logo"]:
		var ruta := String(_manifiesto.get(clave, ""))
		if ResourceLoader.exists(ruta):
			set(clave + "_tex", load(ruta))


static func cargar_sonido(clave: String) -> AudioStream:
	for nombre in SONIDOS.get(clave, []):
		if String(nombre) == "":
			continue
		var ruta: String = DIR + String(nombre)
		if ResourceLoader.exists(ruta):
			var s := load(ruta) as AudioStream
			if s:
				return s
	return null


static func _lista(definition: Dictionary, clave: String) -> Array:
	var v: Variant = (definition.get("sprites", {}) as Dictionary).get(clave)
	if v is Array:
		return v
	return [v] if v is String else []


static func _cuadro(definition: Dictionary, clave: String, i: int) -> String:
	var lista := _lista(definition, clave)
	if lista.is_empty():
		lista = _lista(definition, "idle")
	return String(lista[clampi(i, 0, lista.size() - 1)]) if not lista.is_empty() else ""


## Los dos meteoritos bajan desde el centro del cielo hacia el rival. El segundo empieza
## medio escondido detrás del primero (más arriba y hacia el centro) y, como cae más
## despacio al principio, se separa y se revela cuando la cámara se aleja.
func _preparar_meteoritos() -> void:
	var x1 := clampf(_rival.x + _lado * 45.0, 30.0, 450.0)
	var x2 := clampf(_rival.x, 30.0, 450.0)
	var suelo := CombatSim.FLOOR - 10.0
	var inicio1 := Vector2(lerpf(x1, 240.0, 0.45), -20.0)
	var inicio2 := inicio1 + Vector2(-_lado * 90.0, -30.0)
	_caida = {
		"inicio1": inicio1, "fin1": Vector2(x1, suelo),
		"inicio2": inicio2, "fin2": Vector2(x2, suelo - 6.0),
	}
	meteoritos = [
		# El segundo va primero en la lista: se dibuja detrás.
		{"pos": inicio2, "radio": 48.0, "dir": Vector2(-_lado, 1.6), "semilla": 913, "visible": false},
		{"pos": inicio1, "radio": 52.0, "dir": Vector2(-_lado, 1.6), "semilla": 271, "visible": false},
	]


# ================================================================ Secuencia

func _secuencia() -> void:
	var d := _madara.definition
	var cuerpo := _mundo(centro + Vector2(0, -36))
	var cara := _mundo(ojo + Vector2(-mira * 2.0, 2.0))
	var entre := _mundo(Vector2((_madara.x + _rival.x) * 0.5, CombatSim.FLOOR - 60.0))

	# ---- FASE 1 · PREPARANDO_ATAQUE (0-2 s): oscuridad, chakra, Rinnegan, temblor.
	_cambiar(Estado.PREPARANDO_ATAQUE)
	_sonar("musica")
	_sonar("amenaza")
	var t := _tw().set_parallel(true)
	t.tween_property(self, "barras", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "oscuridad", 0.7, 1.8)
	t.tween_property(self, "rival_luz", 0.45, 1.5)
	t.tween_property(self, "chakra", 0.6, 1.5)
	t.tween_property(self, "temblor", 1.0, 2.0)
	t.tween_property(self, "zoom", 1.5, 1.8).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", cuerpo, 1.8).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "brillo_ojos", 1.0, 0.6).set_delay(0.6)
	if not await _hasta(0.6): return
	madara_cuadro = _cuadro(d, "charge", 3)
	if not await _hasta(0.9): return
	t = _tw()
	t.tween_property(self, "corte", 1.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.65)
	t.tween_property(self, "corte", 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# ---- FASE 2 · ACTIVANDO_SUSANOO (2-6 s): aparece por etapas y la cámara se aleja.
	if not await _hasta(2.0): return
	_cambiar(Estado.ACTIVANDO_SUSANOO)
	_sonar("susanoo")
	madara_cuadro = _cuadro(d, "intro", 2)
	_pulso(MORADO, 0.3)
	t = _tw().set_parallel(true)
	t.tween_property(_susanoo, "aparicion", 1.0, 3.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "chakra", 1.0, 1.0)
	t.tween_property(self, "zoom", 1.0, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "foco", Vector2(480, 270), 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "temblor", 0.6, 1.0)
	if not await _hasta(5.2): return
	_onda(centro, AZUL, 160.0)

	# ---- FASE 3 · ATACANDO_CON_SUSANOO (6-10 s): alza la espada y tajo devastador.
	if not await _hasta(6.0): return
	_cambiar(Estado.ATACANDO_CON_SUSANOO)
	_sonar("espada_alza")
	t = _tw().set_parallel(true)
	t.tween_property(_susanoo, "alzar", 1.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_susanoo, "brillo", 1.0, 1.6)
	t.tween_property(self, "zoom", 1.12, 1.6).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", entre + Vector2(0, -30), 1.6).set_trans(Tween.TRANS_SINE)
	if not await _hasta(T_TAJO): return
	madara_cuadro = _cuadro(d, "special", 1)
	t = _tw()
	t.tween_property(_susanoo, "tajo", 1.0, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	if not await _hasta(T_IMPACTO_SUSANOO): return
	_impacto_susanoo()
	await _pausa_impacto(0.16)
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.25, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "foco", _mundo(Vector2(_rival.x, CombatSim.FLOOR - 40)), 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if not await _hasta(9.0): return
	madara_cuadro = _cuadro(d, "idle", 0)

	# ---- FASE 4 · RIENDO_MADARA (10-13 s): el Susanoo se desvanece y Madara se ríe.
	if not await _hasta(10.0): return
	_cambiar(Estado.RIENDO_MADARA)
	madara_cuadro = _cuadro(d, "victory", 0)
	_sonar("risa")
	t = _tw().set_parallel(true)
	t.tween_property(_susanoo, "aparicion", 0.0, 2.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "chakra", 0.35, 2.0)
	t.tween_property(self, "risa", 1.0, 0.3)
	t.tween_property(self, "zoom", 1.3 if _usa_hoja else 1.9, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "foco", (cuerpo if _usa_hoja else cara + Vector2(0, 30)), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "temblor", 0.0, 0.5)
	if not await _hasta(12.2): return
	t = _tw()
	t.tween_property(self, "risa", 0.0, 0.3)
	if not await _hasta(12.5): return
	madara_cuadro = _cuadro(d, "charge", 3)  # alza la mano hacia el cielo
	_chispas(ojo + Vector2(_lado * 8.0, -6.0), MORADO, 16, 60.0)

	# ---- FASE 5 · INVOCANDO_METEORITOS (13-16 s): cielo rojo, nubes, polvo, rocas que flotan.
	if not await _hasta(13.0): return
	_cambiar(Estado.INVOCANDO_METEORITOS)
	_sonar("cielo")
	_rocas_flotantes()
	if _rival.health > 0:
		rival_sprite = ""
		rival_anim = "hurt"  # aturdido, mira hacia el cielo
		rival_frames = 4.0
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.0, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "foco", Vector2(480, 270), 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "rojo", 1.0, 2.5)
	t.tween_property(self, "nubes", 1.0, 2.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "oscuridad", 0.85, 2.0)
	t.tween_property(self, "temblor", 1.2, 3.0)
	t.tween_property(self, "brillo_ojos", 0.6, 1.0)
	if not await _hasta(14.2): return
	madara_cuadro = _cuadro(d, "victory", 0)

	# ---- FASE 6 · CAYENDO_PRIMER_METEORITO (16-19 s): sale de entre las nubes.
	if not await _hasta(15.5): return
	for m in meteoritos:
		m["visible"] = true
	if not await _hasta(16.0): return
	_cambiar(Estado.CAYENDO_PRIMER_METEORITO)
	_sonar("meteoro", -3.0)
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.4, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "temblor", 1.8, 3.0)
	# La cámara sigue al primer meteorito (la sigue _sincronizar mientras dure este estado).

	# ---- FASE 7 · CAYENDO_SEGUNDO_METEORITO (19-21 s): pausa y se revela el segundo.
	if not await _hasta(19.0): return
	_cambiar(Estado.CAYENDO_SEGUNDO_METEORITO)
	var musica := get_node_or_null("Audio_musica") as AudioStreamPlayer
	if musica:
		var bajar := _tw()
		bajar.tween_property(musica, "volume_db", -30.0, 0.15)
		bajar.tween_interval(0.45)
		bajar.tween_property(musica, "volume_db", 0.0, 0.3)
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.0, 0.9).set_delay(0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "foco", Vector2(480, 270), 0.9).set_delay(0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not await _hasta(19.6): return
	_destello(Color(1.0, 0.5, 0.2), 0.35)
	_sonar("meteoro", 0.0)

	# ---- FASE 8 · IMPACTO_FINAL (21-24 s): primer impacto, cámara lenta, segundo impacto.
	if not await _hasta(T_IMPACTO_1): return
	_cambiar(Estado.IMPACTO_FINAL)
	_impacto_meteoro(0)
	if not await _hasta(22.7): return
	Engine.time_scale = 0.3  # cámara lenta antes del gran impacto
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.15, 0.3).set_trans(Tween.TRANS_SINE)
	if not await _hasta(T_IMPACTO_2): return
	Engine.time_scale = 1.0
	_impacto_meteoro(1)
	t = _tw().set_parallel(true)
	t.tween_property(self, "humo_pantalla", 1.0, 0.9).set_delay(0.2)
	t.tween_property(self, "zoom", 1.0, 0.6)
	if not await _hasta(24.0): return

	# ---- FASE 9 · RECUPERANDO_COMBATE (24-27 s): Madara de pie, Rinnegan y nombres.
	_cambiar(Estado.RECUPERANDO_COMBATE)
	for m in meteoritos:
		m["visible"] = false
	madara_cuadro = _cuadro(d, "idle", 0)
	madara_proc = {}
	_rival_tumbado()
	t = _tw().set_parallel(true)
	t.tween_property(self, "humo_pantalla", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "temblor", 0.0, 0.8)
	t.tween_property(self, "zoom", 1.35 if _usa_hoja else 2.0, 1.2).set_delay(0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "foco", cuerpo if _usa_hoja else cara + Vector2(0, 26), 1.2).set_delay(0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "brillo_ojos", 1.0, 0.6).set_delay(0.6)
	if not await _hasta(24.6): return
	if not _usa_hoja:  # con la hoja, el plano final y el retrato ya muestran el Rinnegan
		t = _tw()
		t.tween_property(self, "corte", 1.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_interval(0.55)
		t.tween_property(self, "corte", 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if not await _hasta(25.5): return
	_sonar("frase")
	t = _tw().set_parallel(true)
	t.tween_property(self, "titulos", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "frase", 1.0, 0.4).set_delay(0.4)
	if not await _hasta(26.4): return
	t = _tw().set_parallel(true)
	for prop in ["titulos", "frase", "barras", "oscuridad", "rojo", "nubes", "chakra", "brillo_ojos"]:
		t.tween_property(self, prop, 0.0, 0.6).set_delay(0.1)
	t.tween_property(self, "rival_luz", 1.0, 0.6)
	t.tween_property(self, "zoom", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", Vector2(480, 270), 0.6).set_trans(Tween.TRANS_SINE)
	await _hasta(T_FIN)


## Secuencia con la hoja v2 (≈30 s). Los cuadros los pone _sincronizar_v2 según el tiempo;
## aquí van la cámara, la luz, el sonido, los estados y los golpes.
func _secuencia_v2() -> void:
	var cuerpo := _mundo(centro + Vector2(0, -40))
	var entre := _mundo(Vector2((_madara.x + _rival.x) * 0.5, CombatSim.FLOOR - 70.0))
	var cielo := _mundo((_caida_v2["cielo"] as Vector2) + Vector2(0, -20))
	var golpes: Dictionary = UltimateSheetV2.GOLPES

	# ---- PREPARANDO_ATAQUE (0-3 s): Madara reúne su chakra.
	_cambiar(Estado.PREPARANDO_ATAQUE)
	_sonar("musica")
	_sonar("amenaza")
	var t := _tw().set_parallel(true)
	t.tween_property(self, "barras", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "oscuridad", 0.72, 2.0)
	t.tween_property(self, "rival_luz", 0.45, 1.8)
	t.tween_property(self, "chakra", 0.5, 2.0)
	t.tween_property(self, "temblor", 1.0, 2.5)
	t.tween_property(self, "zoom", 1.35, 2.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", cuerpo, 2.5).set_trans(Tween.TRANS_SINE)

	# ---- ACTIVANDO_SUSANOO (3-10,5 s): manifestación y Susanoo perfecto; la cámara se aleja.
	if not await _hasta(3.0): return
	_cambiar(Estado.ACTIVANDO_SUSANOO)
	_sonar("susanoo")
	_pulso(MORADO, 0.3)
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.0, 3.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "foco", Vector2(480, 270), 3.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "temblor", 0.5, 2.0)
	if not await _hasta(8.0): return
	_onda(centro, AZUL, 170.0)
	_pulso(AZUL, 0.3)

	# ---- ATACANDO_CON_SUSANOO (10,5-13,5 s): alza la espada y tajo devastador.
	if not await _hasta(10.5): return
	_cambiar(Estado.ATACANDO_CON_SUSANOO)
	_sonar("espada_alza")
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.12, 1.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", entre, 1.5).set_trans(Tween.TRANS_SINE)
	if not await _hasta(float(golpes["susanoo"])): return
	_impacto_susanoo()
	await _pausa_impacto(0.16)
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.22, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "foco", _mundo(Vector2(_rival.x, CombatSim.FLOOR - 40)), 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if not await _hasta(13.5): return
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", Vector2(480, 270), 1.2).set_trans(Tween.TRANS_SINE)

	# ---- RIENDO_MADARA (15-17 s): carcajada (sus propios cuadros).
	if not await _hasta(15.0): return
	_cambiar(Estado.RIENDO_MADARA)
	_sonar("risa")
	t = _tw().set_parallel(true)
	t.tween_property(self, "risa", 1.0, 0.3)
	t.tween_property(self, "zoom", 1.3, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "foco", cuerpo, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "temblor", 0.0, 0.5)
	if not await _hasta(16.7): return
	_tw().tween_property(self, "risa", 0.0, 0.3)

	# ---- INVOCANDO_METEORITOS (17-19,5 s): Rinnegan con sangre (plano) e invocación.
	if not await _hasta(17.0): return
	_cambiar(Estado.INVOCANDO_METEORITOS)
	_sonar("cielo")
	_rocas_flotantes()
	if _rival.health > 0:
		rival_sprite = ""
		rival_anim = "hurt"
		rival_frames = 4.0
	t = _tw().set_parallel(true)
	t.tween_property(self, "rojo", 1.0, 2.5)
	t.tween_property(self, "nubes", 0.8, 2.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "oscuridad", 0.85, 2.0)
	t.tween_property(self, "temblor", 1.2, 2.5)
	t.tween_property(self, "zoom", 1.0, 1.5).set_delay(1.4).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", Vector2(480, 270), 1.5).set_delay(1.4).set_trans(Tween.TRANS_SINE)

	# ---- CAYENDO_PRIMER_METEORITO (19,5-21,5 s): aparecen los dos en el cielo.
	if not await _hasta(19.5): return
	_cambiar(Estado.CAYENDO_PRIMER_METEORITO)
	for m in meteoritos:
		m["visible"] = true
	_destello(Color(1.0, 0.5, 0.25), 0.3)
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.2, 1.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", cielo, 1.2).set_trans(Tween.TRANS_SINE)

	# ---- CAYENDO_SEGUNDO_METEORITO (21,5-24 s): bajan uno detrás del otro.
	if not await _hasta(21.5): return
	_cambiar(Estado.CAYENDO_SEGUNDO_METEORITO)
	_sonar("meteoro", -2.0)
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", Vector2(480, 270), 1.6).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "temblor", 2.0, 2.4)
	if not await _hasta(22.3): return
	_sonar("meteoro", 0.0)

	# ---- IMPACTO_FINAL (24-28,5 s): primer impacto, cámara lenta, segundo y onda de choque.
	if not await _hasta(float(golpes["meteoro1"])): return
	_cambiar(Estado.IMPACTO_FINAL)
	_impacto_meteoro(0)
	if not await _hasta(float(golpes["meteoro2"]) - 0.35): return
	Engine.time_scale = 0.3
	if not await _hasta(float(golpes["meteoro2"])): return
	Engine.time_scale = 1.0
	_impacto_meteoro(1)
	_tw().tween_property(self, "humo_pantalla", 0.85, 0.6).set_delay(0.2)
	if not await _hasta(26.0): return
	_tw().tween_property(self, "humo_pantalla", 0.0, 1.2)
	if not await _hasta(26.5): return
	_sonar("explosion1", -6.0)
	for m in meteoritos:
		m["visible"] = false
	_onda(Vector2(_rival.x, CombatSim.FLOOR), Color(0.7, 0.4, 1.0), 360.0)
	_onda(Vector2(_rival.x, CombatSim.FLOOR), Color(1.0, 0.8, 1.0), 260.0, 0.15)
	_pulso(MORADO, 0.4)
	_shock(Vector2(_rival.x, CombatSim.FLOOR - 20), 1.0)
	temblor = 3.0
	_tw().tween_property(self, "temblor", 0.4, 1.8)

	# ---- RECUPERANDO_COMBATE (28,5-30 s): Madara con el Rinnegan y la sangre, títulos.
	if not await _hasta(28.5): return
	_cambiar(Estado.RECUPERANDO_COMBATE)
	t = _tw().set_parallel(true)
	t.tween_property(self, "zoom", 1.3, 0.8).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", cuerpo, 0.8).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "titulos", 1.0, 0.45).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "frase", 1.0, 0.4).set_delay(0.5)
	_sonar("frase")
	if not await _hasta(29.4): return
	t = _tw().set_parallel(true)
	for prop in ["titulos", "frase", "barras", "oscuridad", "rojo", "nubes", "chakra", "brillo_ojos", "temblor"]:
		t.tween_property(self, prop, 0.0, 0.5)
	t.tween_property(self, "rival_luz", 1.0, 0.5)
	t.tween_property(self, "zoom", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "foco", Vector2(480, 270), 0.5).set_trans(Tween.TRANS_SINE)
	await _hasta(UltimateSheetV2.DURACION)


## Impacto de un meteorito con la hoja v2 (la explosión la dibujan sus cuadros).
func _impacto_v2(cual: int) -> void:
	var grande := cual == 1
	var suelo: Vector2 = _caida_v2["fin_b" if grande else "fin_a"]
	_sonar("explosion2" if grande else "explosion1")
	if _golpe("meteoro2" if grande else "meteoro1"):
		_rival_tumbado()
	_destello(Color(1.0, 0.9, 0.7) if grande else Color(1.0, 0.6, 0.3), 0.9 if grande else 0.6)
	temblor = 7.0 if grande else 4.5
	_tw().tween_property(self, "temblor", 1.0, 1.4)
	_shock(suelo + Vector2(0, -30), 1.0)
	_pulso(Color(1.0, 0.45, 0.1), 0.5 if grande else 0.35)
	_escombros(suelo, 30 if grande else 18, 1.4 if grande else 1.0)
	crateres.append({"x": suelo.x, "ancho": 90.0 if grande else 60.0})
	for roca in rocas:
		roca["vel"] = Vector2(signf(float((roca["pos"] as Vector2).x) - suelo.x) * randf_range(60, 140), randf_range(-120, -40))


func _hasta(t: float) -> bool:
	while tiempo < t and not _saltar and is_inside_tree():
		await get_tree().process_frame
	return not _saltar and is_inside_tree()


## Pausa cinematográfica en un impacto (casi todo se congela un instante).
func _pausa_impacto(segundos: float) -> void:
	if _saltar or not is_inside_tree():
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(segundos, true, false, true).timeout
	Engine.time_scale = 1.0


# ================================================================ Golpes

func _golpe(id: String) -> bool:
	if _golpes_hechos.has(id):
		return false
	_golpes_hechos[id] = true
	var ok := false
	if _sim.has_method("ultimate_hit"):
		ok = bool(_sim.call("ultimate_hit", id))
	# Los sonidos y avisos del golpe los pone la escena; los de la simulación se descartan.
	_sim.consume_audio_events()
	_sim.consume_vfx_events()
	_sim.consume_callouts()
	# La simulación está congelada: sus chispas se quedarían fijas en pantalla.
	_sim.effects.clear()
	_sim.particles.clear()
	return ok


func _rival_tumbado() -> void:
	var tumbado := String((_rival.definition.get("sprites", {}) as Dictionary).get("down", ""))
	if tumbado != "":
		rival_sprite = tumbado
	else:
		rival_anim = "fall"
		rival_frames = 999.0


func _aplicar_golpes_pendientes() -> void:
	if _sim == null:
		return
	for id in ["susanoo", "meteoro1", "meteoro2"]:
		_golpe(id)


func _impacto_susanoo() -> void:
	_sonar("espada_tajo")
	tajo_pantalla = 0.01
	var corte_tw := _tw()
	corte_tw.tween_property(self, "tajo_pantalla", 1.0, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	corte_tw.tween_property(self, "tajo_pantalla", 0.0, 0.0)
	var donde := Vector2(_rival.x, CombatSim.FLOOR - 30.0)
	if _golpe("susanoo"):
		_rival_tumbado()
	_destello(Color(0.7, 0.8, 1.0), 0.7)
	temblor = 4.0
	_tw().tween_property(self, "temblor", 0.4, 1.0)
	_sprite_fx("tajo_azul", Vector2(_rival.x, CombatSim.FLOOR - 34.0), 0.5, 1.7, -0.25 * mira, true, 0.35)
	_onda(Vector2(_rival.x, CombatSim.FLOOR), AZUL, 230.0)
	_onda(Vector2(_rival.x, CombatSim.FLOOR), MORADO, 160.0, 0.08)
	_chispas(donde, AZUL, 30, 160.0)
	_chispas(donde, MORADO, 20, 120.0)
	_escombros(Vector2(_rival.x, CombatSim.FLOOR), 18, 1.0)
	_shock(donde, 1.0)
	_pulso(AZUL, 0.4)


func _impacto_meteoro(cual: int) -> void:
	var grande := cual == 1
	var m: Dictionary = meteoritos[1 - cual]
	m["visible"] = false
	var donde: Vector2 = _caida["fin2" if grande else "fin1"]
	var suelo := Vector2(donde.x, CombatSim.FLOOR)
	_sonar("explosion2" if grande else "explosion1")
	if _golpe("meteoro2" if grande else "meteoro1"):
		_rival_tumbado()
	explosiones.append({"pos": suelo, "t": tiempo, "escala": 1.6 if grande else 1.0, "semilla": 51 + cual * 7})
	var e := 1.5 if grande else 1.0
	_sprite_fx("explosion", suelo + Vector2(0, 2), 1.3, 2.2 * e, 0.0, true, 0.5)
	for k in range(3):
		_sprite_fx("humo_%d" % (k + 1), suelo + Vector2((k - 1) * 46.0 * e, -10.0), 2.6, 1.3 * e, 0.0, k == 1, 0.6, Vector2((k - 1) * 10.0, -14.0))
	_sprite_fx("escombros_%d" % (cual * 2 + 1), suelo + Vector2(-24.0 * e, 3), 99.0, 1.2 * e, 0.0, false, 0.0)
	_sprite_fx("escombros_%d" % (cual * 2 + 2), suelo + Vector2(26.0 * e, 3), 99.0, 1.2 * e, 0.0, false, 0.0)
	crateres.append({"x": suelo.x, "ancho": 95.0 if grande else 60.0})
	_onda(suelo, Color(1.0, 0.55, 0.2), 320.0 if grande else 240.0)
	_onda(suelo, Color(1.0, 0.85, 0.5), 200.0 if grande else 150.0, 0.1)
	_escombros(suelo, 40 if grande else 24, 1.6 if grande else 1.1)
	_destello(Color(1.0, 0.9, 0.7) if grande else Color(1.0, 0.6, 0.3), 1.0 if grande else 0.7)
	temblor = 7.0 if grande else 4.5
	_tw().tween_property(self, "temblor", 1.2 if not grande else 0.6, 1.4)
	_shock(suelo + Vector2(0, -30), 1.0)
	_pulso(Color(1.0, 0.45, 0.1), 0.55 if grande else 0.4)
	for roca in rocas:
		roca["vel"] = Vector2(signf(float((roca["pos"] as Vector2).x) - suelo.x) * randf_range(60, 140), randf_range(-120, -40))


# ================================================================ Cada cuadro

func _process(delta: float) -> void:
	if _madara == null or _terminada:
		return
	tiempo += delta
	_mover_meteoritos()
	_actualizar_particulas(delta)
	var vivos: Array = []
	for f in sprites_fx:
		if tiempo - float(f["t"]) < float(f["dur"]):
			vivos.append(f)
	sprites_fx = vivos
	_emitir(delta)
	if estado == Estado.RIENDO_MADARA and risa > 0.0:
		# Carcajada: hombros que saltan, cabeza hacia atrás y balanceo.
		var s := absf(sin(tiempo * 17.0))
		madara_proc = {"desp": Vector2(0, -s * 3.0 * risa), "escala": Vector2(1.0 + 0.02 * s, 1.0 - 0.035 * s),
			"rot": (-6.0 - 3.0 * sin(tiempo * 7.0)) * risa}
	elif estado != Estado.RIENDO_MADARA:
		madara_proc = {}
	if estado >= Estado.RECUPERANDO_COMBATE and humo_pantalla < 0.5:
		var idle := _lista(_madara.definition, "idle")
		if not idle.is_empty():
			madara_cuadro = String(idle[int(tiempo / 0.12) % idle.size()])
	_sincronizar()


func _mover_meteoritos() -> void:
	if _caida.is_empty() or meteoritos.size() < 2:
		return
	var t0 := float(_t_caida[0])
	var p1 := clampf((tiempo - t0) / (float(_t_caida[1]) - t0), 0.0, 1.0)
	var p2 := clampf((tiempo - t0) / (float(_t_caida[2]) - t0), 0.0, 1.0)
	var m1: Dictionary = meteoritos[1]
	var m2: Dictionary = meteoritos[0]
	m1["pos"] = (_caida["inicio1"] as Vector2).lerp(_caida["fin1"], pow(p1, 2.0))
	m2["pos"] = (_caida["inicio2"] as Vector2).lerp(_caida["fin2"], pow(p2, 1.6))
	m1["radio"] = lerpf(52.0, 80.0, p1)
	m2["radio"] = lerpf(48.0, 96.0, p2)  # el segundo es aún mayor
	m1["dir"] = (_caida["fin1"] as Vector2) - (_caida["inicio1"] as Vector2)
	m2["dir"] = (_caida["fin2"] as Vector2) - (_caida["inicio2"] as Vector2)


func _sincronizar() -> void:
	var alfa_m := 1.0
	if _v2:
		alfa_m = _sincronizar_v2()
	elif _usa_hoja and is_instance_valid(_hoja):
		var pj: Dictionary = _manifiesto["personaje"]
		var fases: Dictionary = pj.get("fases", {})
		var en_mundo := -1 if (_saltar or _terminada) else UltimateSheet.cuadro_personaje(fases, tiempo)
		# Al final, el dibujo de la hoja se funde con el sprite de combate.
		var final_mezcla := clampf((tiempo - 26.3) / 0.3, 0.0, 1.0)
		_hoja.set("cuadro", en_mundo)
		_hoja.set("alfa", 1.0 - final_mezcla)
		_hoja.set("ovalo", 1.0 if UltimateSheet.fase_mundo(tiempo) == "final" else 0.0)
		if is_instance_valid(_hoja_luz):
			_hoja_luz.set("cuadro", -1 if (_saltar or _terminada) else UltimateSheet.cuadro_luz(fases, tiempo))
			_hoja_luz.set("alfa", UltimateSheet.alfa_luz(tiempo))
			_hoja_luz.set("escala", _escala_hoja * 1.35)  # el Susanoo, bastante más grande que Madara
		_hoja.set("escala", _escala_hoja * float(UltimateSheet.ESCALA_FASE.get(UltimateSheet.fase_mundo(tiempo), 1.0)))
		# Mientras se ve el dibujo de la hoja en el escenario, el sprite de combate se oculta.
		alfa_m = final_mezcla if en_mundo >= 0 else 1.0
		var pl: Array = UltimateSheet.plano(_manifiesto, tiempo)
		plano_tipo = String(pl[0])
		plano_cuadro = int(pl[1])
		plano_alfa = 0.0 if (_saltar or _terminada) else float(pl[2])
	var anim_m := {"sprite": madara_cuadro, "tint": Color(1, 1, 1, alfa_m)}
	if not madara_proc.is_empty():
		anim_m["proc"] = madara_proc
	_arena.cinematic[_madara.index] = anim_m
	var anim_r := {"tint": Color(rival_luz, rival_luz, rival_luz * 1.1, 1.0)}
	if rival_sprite != "":
		anim_r["sprite"] = rival_sprite
	elif rival_anim != "":
		anim_r["anim"] = rival_anim
		anim_r["frames"] = rival_frames
	_arena.cinematic[_rival.index] = anim_r
	if estado == Estado.CAYENDO_PRIMER_METEORITO and meteoritos.size() > 1:
		# La cámara sigue al primer meteorito desde abajo (perspectiva de tamaño).
		var objetivo := _mundo((meteoritos[1]["pos"] as Vector2).lerp(Vector2(_rival.x, CombatSim.FLOOR - 40), 0.3))
		foco = foco.lerp(objetivo, 0.08)
	var z := maxf(zoom, 1.0)
	var mitad := Vector2(480, 270) / z
	_camara.zoom = Vector2(z, z)
	_camara.position = Vector2(clampf(foco.x, mitad.x, 960.0 - mitad.x), clampf(foco.y, mitad.y, 540.0 - mitad.y))
	_camara.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * temblor * 2.0 / z if temblor > 0.0 else Vector2.ZERO
	cabeza_pantalla = _arena.get_global_transform_with_canvas() * ojo


func _emitir(delta: float) -> void:
	# Chakra que sube alrededor de Madara.
	if chakra > 0.1 and randf() < chakra * 0.9:
		particulas.append({"pos": centro + Vector2(randf_range(-22, 22), randf_range(-70, 0)), "vel": Vector2(randf_range(-10, 10), randf_range(-70, -35)),
			"vida": 0.0, "max": randf_range(0.5, 1.1), "r": 1.0, "color": (AZUL if randf() < 0.55 else MORADO).lightened(0.3), "tipo": "chispa", "delante": randf() < 0.5})
	# Polvo que cae del cielo durante el Tengai Shinsei.
	if nubes > 0.2 and randf() < nubes * 1.2:
		particulas.append({"pos": Vector2(randf_range(-20, 500), -10), "vel": Vector2(randf_range(-6, 6), randf_range(25, 45)),
			"vida": 0.0, "max": 7.0, "r": 1.0, "color": Color(0.6, 0.45, 0.38, 0.7), "tipo": "polvo", "delante": randf() < 0.5})
	# Brasas que sueltan los meteoritos.
	for m in meteoritos:
		if bool(m["visible"]) and randf() < 0.8:
			var r := float(m["radio"])
			particulas.append({"pos": (m["pos"] as Vector2) + Vector2(randf_range(-r, r), randf_range(-r, r)) * 0.8,
				"vel": -(m["dir"] as Vector2).normalized() * randf_range(20, 60) + Vector2(randf_range(-15, 15), 0),
				"vida": 0.0, "max": randf_range(0.4, 0.9), "r": 2.0, "color": Color(1.0, 0.6, 0.2), "tipo": "chispa", "delante": false})
	# Rocas que flotan.
	for roca in rocas:
		var vel: Vector2 = roca.get("vel", Vector2.ZERO)
		if vel == Vector2.ZERO:
			roca["pos"] = (roca["pos"] as Vector2) + Vector2(sin(tiempo * 1.5 + float(roca["giro"])) * 4.0, -float(roca["sube"])) * delta
		else:
			roca["pos"] = (roca["pos"] as Vector2) + vel * delta
			roca["vel"] = vel + Vector2(0, 260) * delta
			roca["alfa"] = maxf(0.0, float(roca.get("alfa", 1.0)) - delta * 0.8)


func _actualizar_particulas(delta: float) -> void:
	var vivas: Array = []
	for p in particulas:
		p["vida"] += delta
		if p["vida"] >= p["max"]:
			continue
		p["pos"] += p["vel"] * delta
		match String(p["tipo"]):
			"roca":
				p["vel"].y += 300.0 * delta
			"humo":
				p["vel"] *= 1.0 - delta * 1.5
				p["r"] += delta * 5.0
			"chispa":
				p["vel"] *= 1.0 - delta * 1.2
		vivas.append(p)
	particulas = vivas


# ================================================================ Ayudas

func _tw() -> Tween:
	var tw := create_tween()
	_tweens.append(tw)
	return tw


func _mundo(p: Vector2) -> Vector2:
	return _arena.transform * p


func _sonar(clave: String, volumen := 0.0) -> void:
	var stream: AudioStream = _audio.get(clave)
	if stream == null or _saltar:
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


## Pone un sprite de efecto de la hoja (si está importado) en la arena.
## crece: cuánto aumenta de tamaño durante su vida; deriva: px/s.
func _sprite_fx(nombre: String, pos: Vector2, dur: float, escala: float, rot: float, delante: bool, crece: float, deriva := Vector2.ZERO) -> void:
	if not efx.has(nombre):
		return
	sprites_fx.append({"nombre": nombre, "pos": pos, "t": tiempo, "dur": dur, "escala": escala, "rot": rot,
		"delante": delante, "crece": crece, "deriva": deriva})


func _onda(pos: Vector2, color: Color, radio: float, retraso := 0.0) -> void:
	ondas.append({"pos": pos, "t": tiempo + retraso, "color": color, "radio": radio, "dur": 0.9})


func _chispas(en: Vector2, color: Color, cantidad: int, fuerza: float) -> void:
	for i in cantidad:
		var a := randf() * TAU
		particulas.append({"pos": en, "vel": Vector2(cos(a), sin(a)) * randf_range(0.3, 1.0) * fuerza,
			"vida": 0.0, "max": randf_range(0.3, 0.8), "r": 1.0, "color": color.lightened(0.25), "tipo": "chispa", "delante": true})


func _escombros(en: Vector2, cantidad: int, fuerza: float) -> void:
	for i in cantidad:
		particulas.append({"pos": en + Vector2(randf_range(-20, 20), -4), "vel": Vector2(randf_range(-150, 150), randf_range(-260, -90)) * fuerza,
			"vida": 0.0, "max": randf_range(0.8, 1.6), "r": randf_range(2.0, 4.0), "color": Color(0.36, 0.28, 0.24), "tipo": "roca", "delante": i % 2 == 0})
	for i in int(cantidad * 0.6):
		particulas.append({"pos": en + Vector2(randf_range(-40, 40), -randf_range(0, 20)), "vel": Vector2(randf_range(-60, 60), randf_range(-30, -5)) * fuerza,
			"vida": 0.0, "max": randf_range(1.0, 2.0), "r": randf_range(4.0, 8.0) * fuerza, "color": Color(0.3, 0.25, 0.23, 0.7), "tipo": "humo", "delante": i % 3 == 0})


func _rocas_flotantes() -> void:
	for i in range(14):
		rocas.append({"pos": Vector2(randf_range(20, 460), CombatSim.FLOOR - randf_range(0, 6)), "tam": randf_range(2.0, 5.0),
			"giro": randf_range(-2.0, 2.0), "sube": randf_range(6.0, 16.0), "alfa": 1.0})


func _shock(arena_pos: Vector2, fuerza: float) -> void:
	var fx: Variant = _ctx.get("screen_fx")
	if fx and is_instance_valid(fx):
		var uv := _arena.get_global_transform_with_canvas() * arena_pos
		fx.call("shockwave", uv / get_viewport().get_visible_rect().size, fuerza)


func _pulso(color: Color, cantidad: float) -> void:
	var fx: Variant = _ctx.get("screen_fx")
	if fx and is_instance_valid(fx):
		fx.call("pulse", color, cantidad)


func _destello(color: Color, fuerza: float) -> void:
	color_destello = color
	destello = fuerza
	_tw().tween_property(self, "destello", 0.0, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if _saltar or _terminada or _madara == null:
		return
	if InputMap.has_action("pause") and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		saltar()


## Acorta la técnica: aplica los golpes que falten y se desvanece.
func saltar() -> void:
	_saltar = true


# ================================================================ Cierre

func _cerrar() -> void:
	Engine.time_scale = 1.0
	for tw in _tweens:
		if tw and tw.is_valid():
			tw.kill()
	_tweens.clear()
	_aplicar_golpes_pendientes()
	if _saltar and is_inside_tree():
		var t := _tw().set_parallel(true)
		for prop in ["oscuridad", "rojo", "nubes", "chakra", "brillo_ojos", "barras", "corte", "risa", "titulos", "frase", "humo_pantalla", "destello", "temblor"]:
			t.tween_property(self, prop, 0.0, 0.3)
		t.tween_property(self, "rival_luz", 1.0, 0.3)
		t.tween_property(self, "zoom", 1.0, 0.3)
		t.tween_property(self, "foco", Vector2(480, 270), 0.3)
		if _susanoo:
			t.tween_property(_susanoo, "aparicion", 0.0, 0.3)
		for c in get_children():
			if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing:
				t.tween_property(c, "volume_db", -40.0, 0.3)
		await t.finished
	_restaurar()


func _restaurar(volver_musica := true) -> void:
	if _terminada:
		return
	_terminada = true
	Engine.time_scale = 1.0
	_cambiar(Estado.TERMINADO)
	if _arena and is_instance_valid(_arena):
		_arena.cinematic.clear()
	for n in [_fx_detras, _fx_delante, _grupo, _hoja, _hoja_luz] + _capas.values():
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
	if volver_musica:
		Sfx.play_music("battle")
