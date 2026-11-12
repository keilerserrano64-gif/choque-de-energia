@tool
extends RefCounted
## Constructor de animaciones 2D a partir de una receta normalizada (ver receta.gd):
##   {"duracion": float, "loop": bool, "pistas": [{"propiedad", "claves": [{"tiempo", "valor"}]}]}
## Crea el recurso Animation con interpolación cúbica y lo instala en un AnimationPlayer
## con Deshacer/Rehacer (Ctrl+Z) del editor. No usa EditorInterface: el panel le pasa
## el gestor de deshacer y la raíz de la escena (así se puede probar sin editor).

const PLAYER := "AnimIA"
const LIBRERIA := "ia"

var error := ""
## Propiedades de la receta que el nodo no tiene (se omiten, no es un error).
var omitidas: PackedStringArray = []


static func es_valido(nodo: Node) -> bool:
	return nodo is Node2D or nodo is Control


## Valor de reposo del nodo para una propiedad.
static func reposo(nodo: Node, propiedad: String) -> Variant:
	match propiedad:
		"position":
			return nodo.get("position") as Vector2
		"rotation":
			return float(nodo.get("rotation"))
		"scale":
			return nodo.get("scale") as Vector2
		"modulate":
			return (nodo as CanvasItem).modulate
	return null


## relativo = true: position se suma a la posición actual, rotation se suma al giro actual,
## scale multiplica la escala actual y modulate multiplica el color actual.
static func valor_final(nodo: Node, propiedad: String, valor: Variant, relativo: bool) -> Variant:
	if not relativo:
		return valor
	var base: Variant = reposo(nodo, propiedad)
	match propiedad:
		"position":
			return (base as Vector2) + (valor as Vector2)
		"rotation":
			return float(base) + float(valor)
		"scale":
			return (base as Vector2) * (valor as Vector2)
		"modulate":
			return (base as Color) * (valor as Color)
	return valor


## Valor "neutro" de la receta: el que deja la propiedad en reposo (modo relativo).
static func neutro(propiedad: String) -> Variant:
	match propiedad:
		"position":
			return Vector2.ZERO
		"rotation":
			return 0.0
		"scale":
			return Vector2.ONE
		"modulate":
			return Color.WHITE
	return null


func construir(receta: Dictionary, nodo: Node, relativo := true, forzar_loop := false) -> Animation:
	error = ""
	omitidas = []
	if nodo == null or not es_valido(nodo):
		error = "Selecciona un Node2D, Polygon2D, Line2D, Sprite2D o Control."
		return null
	var pistas: Array = receta.get("pistas", [])
	if pistas.is_empty():
		error = "La receta no trae pistas."
		return null
	var anim := Animation.new()
	anim.length = maxf(float(receta.get("duracion", 1.0)), 0.05)
	var loop := forzar_loop or bool(receta.get("loop", false))
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for p in pistas:
		var prop := String((p as Dictionary).get("propiedad", ""))
		var claves: Array = (p as Dictionary).get("claves", [])
		if reposo(nodo, prop) == null or claves.is_empty():
			omitidas.append(prop)
			continue
		var pista := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(pista, NodePath(".:" + prop))
		anim.value_track_set_update_mode(pista, Animation.UPDATE_CONTINUOUS)
		anim.track_set_interpolation_type(pista, Animation.INTERPOLATION_CUBIC)
		# Las animaciones en bucle vuelven solas al principio; las demás no.
		anim.track_set_interpolation_loop_wrap(pista, loop)
		# Si la IA no empieza en 0, se arranca desde el reposo para que no salte.
		var primera: Dictionary = claves[0]
		if float(primera.get("tiempo", 0.0)) > 0.0001:
			var v0: Variant = valor_final(nodo, prop, neutro(prop), relativo) if relativo else reposo(nodo, prop)
			anim.track_insert_key(pista, 0.0, v0)
		for c in claves:
			var t := clampf(float((c as Dictionary).get("tiempo", 0.0)), 0.0, anim.length)
			anim.track_insert_key(pista, t, valor_final(nodo, prop, (c as Dictionary)["valor"], relativo))
	if anim.get_track_count() == 0:
		error = "Ninguna pista sirve para %s (%s)." % [nodo.name, ", ".join(omitidas)]
		return null
	return anim


## Busca el AnimationPlayer "AnimIA" hijo del nodo (o null).
static func buscar_player(nodo: Node, raiz: Node) -> AnimationPlayer:
	for n in nodo.get_children():
		if n is AnimationPlayer and String(n.name) == PLAYER and (raiz == null or n.owner == raiz):
			return n as AnimationPlayer
	return null


## Instala la animación con Deshacer/Rehacer. Si ya existe una con ese nombre la reemplaza
## (Ctrl+Z devuelve la anterior). Si no hay AnimationPlayer lo crea.
## deshacer: EditorUndoRedoManager (o UndoRedo en pruebas; null = sin deshacer).
## Devuelve el AnimationPlayer usado.
static func instalar(deshacer: Object, nodo: Node, raiz: Node, nombre: String, anim: Animation) -> AnimationPlayer:
	var player := buscar_player(nodo, raiz)
	var nuevo_player := player == null
	if nuevo_player:
		player = AnimationPlayer.new()
		player.name = PLAYER
	var lib: AnimationLibrary = player.get_animation_library(LIBRERIA) if player.has_animation_library(LIBRERIA) else null
	var nueva_lib := lib == null
	if nueva_lib:
		lib = AnimationLibrary.new()
	var anterior: Animation = lib.get_animation(nombre) if lib.has_animation(nombre) else null

	if deshacer == null:
		if nuevo_player:
			nodo.add_child(player)
			player.owner = raiz
		if nueva_lib:
			player.add_animation_library(LIBRERIA, lib)
		if anterior:
			lib.remove_animation(nombre)
		lib.add_animation(nombre, anim)
		return player

	# backward_undo_ops = true: al deshacer, los pasos se ejecutan al revés del orden en que se
	# añaden. Por eso cada paso lleva su inverso justo al lado.
	if deshacer is EditorUndoRedoManager:
		deshacer.create_action("AutoAnim IA: " + nombre, UndoRedo.MERGE_DISABLE, raiz if raiz else nodo, true)
	else:
		deshacer.create_action("AutoAnim IA: " + nombre, UndoRedo.MERGE_DISABLE, true)
	if nuevo_player:
		_hacer(deshacer, nodo, "add_child", [player, true])
		deshacer.add_do_property(player, "owner", raiz)
		deshacer.add_do_reference(player)
		_deshacer(deshacer, nodo, "remove_child", [player])
	if nueva_lib:
		_hacer(deshacer, player, "add_animation_library", [LIBRERIA, lib])
		_deshacer(deshacer, player, "remove_animation_library", [LIBRERIA])
	if anterior:
		_hacer(deshacer, lib, "remove_animation", [nombre])
		_deshacer(deshacer, lib, "add_animation", [nombre, anterior])
	_hacer(deshacer, lib, "add_animation", [nombre, anim])
	_deshacer(deshacer, lib, "remove_animation", [nombre])
	deshacer.commit_action()
	return player


## Forma de prueba para cuando no hay nada seleccionado: un Polygon2D (estrella) en la raíz.
static func forma_base(nombre := "FormaIA") -> Polygon2D:
	var poli := Polygon2D.new()
	poli.name = nombre
	var puntos := PackedVector2Array()
	for i in 10:
		var r := 40.0 if i % 2 == 0 else 18.0
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		puntos.append(Vector2(cos(a), sin(a)) * r)
	poli.polygon = puntos
	poli.color = Color(1.0, 0.78, 0.25)
	return poli


static func crear_forma_base(deshacer: Object, raiz: Node) -> Polygon2D:
	var poli := forma_base()
	poli.position = Vector2(240, 160)
	if deshacer == null:
		raiz.add_child(poli, true)
		poli.owner = raiz
		return poli
	if deshacer is EditorUndoRedoManager:
		deshacer.create_action("AutoAnim IA: forma base", UndoRedo.MERGE_DISABLE, raiz, true)
	else:
		deshacer.create_action("AutoAnim IA: forma base", UndoRedo.MERGE_DISABLE, true)
	_hacer(deshacer, raiz, "add_child", [poli, true])
	deshacer.add_do_property(poli, "owner", raiz)
	deshacer.add_do_reference(poli)
	_deshacer(deshacer, raiz, "remove_child", [poli])
	deshacer.commit_action()
	return poli


## EditorUndoRedoManager recibe (objeto, método, args...); UndoRedo (pruebas) recibe un Callable.
static func _hacer(deshacer: Object, obj: Object, metodo: String, args: Array) -> void:
	if deshacer is UndoRedo:
		deshacer.add_do_method(Callable(obj, metodo).bindv(args))
	else:
		deshacer.callv("add_do_method", [obj, metodo] + args)


static func _deshacer(deshacer: Object, obj: Object, metodo: String, args: Array) -> void:
	if deshacer is UndoRedo:
		deshacer.add_undo_method(Callable(obj, metodo).bindv(args))
	else:
		deshacer.callv("add_undo_method", [obj, metodo] + args)
