@tool
extends VBoxContainer
## Pestaña "IA" de AutoAnim: describe un movimiento con palabras y la IA (Claude, Codex,
## Ollama o el modo local sin IA) lo convierte en una Animation de Godot para el nodo
## seleccionado. Todo se puede deshacer con Ctrl+Z.

const Receta := preload("receta.gd")
const Constructor := preload("constructor.gd")
const ClienteIA := preload("cliente_ia.gd")
const AJUSTE := "auto_anim/ia/"

## Lo pone plugin.gd: get_undo_redo() del EditorPlugin.
var deshacer: EditorUndoRedoManager

@onready var proveedor: OptionButton = %Proveedor
@onready var modelo: LineEdit = %Modelo
@onready var nombre: LineEdit = %Nombre
@onready var descripcion: TextEdit = %Descripcion
@onready var duracion: SpinBox = %Duracion
@onready var relativo: CheckBox = %Relativo
@onready var bucle: CheckBox = %Bucle
@onready var generar: Button = %Generar
@onready var reproducir: Button = %Reproducir
@onready var aplicar_json: Button = %AplicarJson
@onready var estado: Label = %Estado
@onready var json: TextEdit = %Json
@onready var cliente: ClienteIA = %Cliente

## Nodo al que va la animación pedida (la selección puede cambiar mientras la IA piensa).
var _objetivo_id := 0
var _nombre_pedido := ""
var _reproduciendo: AnimationPlayer
var _reposo := {}
var _reposo_nodo: Node


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	proveedor.clear()
	for p in ClienteIA.PROVEEDORES:
		proveedor.add_item(String(ClienteIA.NOMBRES[p]))
	proveedor.item_selected.connect(_al_cambiar_proveedor)
	generar.pressed.connect(_generar)
	reproducir.pressed.connect(_reproducir)
	aplicar_json.pressed.connect(_aplicar_json)
	%VerAjustes.toggled.connect(func(on: bool) -> void: %Ajustes.visible = on)
	cliente.terminado.connect(_al_responder)
	for campo in [%RutaClaude, %RutaCodex, %UrlOllama, modelo]:
		(campo as LineEdit).text_changed.connect(func(_t: String) -> void: _guardar_ajustes())
	_cargar_ajustes()
	set_process(false)


func _process(_delta: float) -> void:
	if cliente.esta_ocupado():
		_estado("%s está pensando... %d s" % [ClienteIA.NOMBRES.get(_prov(), _prov()), int(cliente.segundos())])
	else:
		set_process(false)


func _exit_tree() -> void:
	_parar()


# ================================================================ Ajustes del editor (no van al proyecto)

func _ajustes() -> EditorSettings:
	return EditorInterface.get_editor_settings()


func _leer(clave: String, defecto: Variant) -> Variant:
	var s := _ajustes()
	return s.get_setting(AJUSTE + clave) if s.has_setting(AJUSTE + clave) else defecto


func _cargar_ajustes() -> void:
	var p := String(_leer("proveedor", "local"))
	var i := ClienteIA.PROVEEDORES.find(p)
	proveedor.select(maxi(i, 0))
	%RutaClaude.text = String(_leer("ruta_claude", "claude"))
	%RutaCodex.text = String(_leer("ruta_codex", "codex"))
	%UrlOllama.text = String(_leer("url_ollama", ClienteIA.URL_OLLAMA))
	_al_cambiar_proveedor(proveedor.selected, false)


func _guardar_ajustes() -> void:
	var s := _ajustes()
	s.set_setting(AJUSTE + "proveedor", _prov())
	s.set_setting(AJUSTE + "modelo_" + _prov(), modelo.text.strip_edges())
	s.set_setting(AJUSTE + "ruta_claude", %RutaClaude.text.strip_edges())
	s.set_setting(AJUSTE + "ruta_codex", %RutaCodex.text.strip_edges())
	s.set_setting(AJUSTE + "url_ollama", %UrlOllama.text.strip_edges())


func _prov() -> String:
	return String(ClienteIA.PROVEEDORES[clampi(proveedor.selected, 0, ClienteIA.PROVEEDORES.size() - 1)])


func _al_cambiar_proveedor(_idx: int, guardar := true) -> void:
	var p := _prov()
	modelo.set_block_signals(true)
	modelo.text = String(_leer("modelo_" + p, ClienteIA.MODELO_POR_DEFECTO[p]))
	modelo.set_block_signals(false)
	modelo.editable = p != "local"
	generar.text = "Generar (sin IA)" if p == "local" else "Generar con " + String(ClienteIA.NOMBRES[p]).get_slice(" (", 0)
	if guardar:
		_guardar_ajustes()


# ================================================================ Generar

func _estado(texto: String) -> void:
	estado.text = texto


func _nodo_seleccionado() -> Node:
	for n in EditorInterface.get_selection().get_selected_nodes():
		if Constructor.es_valido(n):
			return n
	return null


func _generar() -> void:
	if cliente.esta_ocupado():
		_estado("Espera: ya hay una petición en marcha.")
		return
	var raiz := EditorInterface.get_edited_scene_root()
	if raiz == null:
		_estado("Abre o crea una escena primero.")
		return
	var nom := nombre.text.strip_edges().validate_node_name().replace("/", "_")
	if nom.is_empty():
		_estado("Ponle un nombre a la animación (ej. salto).")
		return
	var nodo := _nodo_seleccionado()
	if nodo == null:
		nodo = Constructor.crear_forma_base(deshacer, raiz)
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(nodo)
		_estado("No había nada seleccionado: creé la estrella 'FormaIA'.")
	_parar()
	_objetivo_id = nodo.get_instance_id()
	_nombre_pedido = nom
	cliente.ruta_claude = %RutaClaude.text.strip_edges()
	cliente.ruta_codex = %RutaCodex.text.strip_edges()
	cliente.url_ollama = %UrlOllama.text.strip_edges()
	_guardar_ajustes()
	generar.disabled = true
	if _prov() != "local":
		_estado("Generando con %s..." % ClienteIA.NOMBRES[_prov()])
		set_process(true)
	cliente.pedir(_prov(), modelo.text.strip_edges(), descripcion.text, duracion.value)


func _al_responder(ok: bool, texto: String, error: String) -> void:
	generar.disabled = false
	set_process(false)
	if not ok:
		_estado("Error: " + error)
		return
	json.text = texto
	_construir(texto, instance_from_id(_objetivo_id) as Node, _nombre_pedido)


func _aplicar_json() -> void:
	var nodo := _nodo_seleccionado()
	if nodo == null:
		_estado("Selecciona el nodo al que aplicar el JSON.")
		return
	var nom := nombre.text.strip_edges().validate_node_name()
	if nom.is_empty():
		_estado("Ponle un nombre a la animación.")
		return
	_parar()
	_construir(json.text, nodo, nom)


func _construir(texto: String, nodo: Node, nom: String) -> void:
	if nodo == null or not is_instance_valid(nodo) or not nodo.is_inside_tree():
		_estado("El nodo ya no existe. Selecciónalo y pulsa 'Aplicar JSON'.")
		return
	var r: Dictionary = Receta.parsear(texto)
	if not bool(r.get("ok", false)):
		_estado("La respuesta no sirve: %s\nPuedes corregir el JSON y pulsar 'Aplicar JSON'." % r.get("error", "?"))
		return
	var receta: Dictionary = r["receta"]
	json.text = JSON.stringify(_receta_a_json(receta), "  ")
	var c := Constructor.new()
	var anim := c.construir(receta, nodo, relativo.button_pressed, bucle.button_pressed)
	if anim == null:
		_estado("Error: " + c.error)
		return
	var raiz := EditorInterface.get_edited_scene_root()
	var player := Constructor.instalar(deshacer, nodo, raiz, nom, anim)
	var texto_estado := "Animación lista: '%s/%s' en %s/%s (%d pistas, %.2f s%s). Ctrl+Z la deshace; guarda con Ctrl+S." % [
		Constructor.LIBRERIA, nom, nodo.name, Constructor.PLAYER, anim.get_track_count(), anim.length,
		", bucle" if anim.loop_mode != Animation.LOOP_NONE else ""]
	if not c.omitidas.is_empty():
		texto_estado += "\nOmitidas (el nodo no las tiene): " + ", ".join(c.omitidas)
	_estado(texto_estado)
	_reproducir_en(player, nodo, nom)


## Receta normalizada -> JSON legible (para mostrarla y poder retocarla).
static func _receta_a_json(receta: Dictionary) -> Dictionary:
	var pistas: Array = []
	for p in receta.get("pistas", []):
		var claves: Array = []
		for c in (p as Dictionary).get("claves", []):
			var v: Variant = (c as Dictionary)["valor"]
			match typeof(v):
				TYPE_VECTOR2:
					v = [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]
				TYPE_COLOR:
					v = [snappedf(v.r, 0.001), snappedf(v.g, 0.001), snappedf(v.b, 0.001), snappedf(v.a, 0.001)]
				TYPE_FLOAT:
					if String(p["propiedad"]) == "rotation":
						v = snappedf(rad_to_deg(v), 0.01)
			claves.append({"tiempo": snappedf(float(c["tiempo"]), 0.001), "valor": v})
		pistas.append({"propiedad": p["propiedad"], "claves": claves})
	return {"duracion": receta.get("duracion", 1.0), "loop": receta.get("loop", false), "pistas": pistas}


# ================================================================ Vista previa

func _reproducir() -> void:
	if _reproduciendo:
		_parar()
		_estado("Parado.")
		return
	var nodo := _nodo_seleccionado()
	if nodo == null:
		_estado("Selecciona el nodo animado.")
		return
	var player := Constructor.buscar_player(nodo, EditorInterface.get_edited_scene_root())
	var nom := nombre.text.strip_edges().validate_node_name()
	if player == null or not player.has_animation(Constructor.LIBRERIA + "/" + nom):
		_estado("Ese nodo no tiene la animación '%s/%s'. Genérala primero." % [Constructor.LIBRERIA, nom])
		return
	_reproducir_en(player, nodo, nom)


## Reproduce en el editor y al terminar devuelve el nodo a su reposo (no ensucia la escena).
func _reproducir_en(player: AnimationPlayer, nodo: Node, nom: String) -> void:
	_parar()
	_reposo_nodo = nodo
	_reposo = {}
	for prop in ["position", "rotation", "scale", "modulate"]:
		_reposo[prop] = nodo.get(prop)
	_reproduciendo = player
	if not player.animation_finished.is_connected(_al_terminar):
		player.animation_finished.connect(_al_terminar)
	player.play(Constructor.LIBRERIA + "/" + nom)
	reproducir.text = "Parar"


func _al_terminar(_anim: StringName) -> void:
	_parar()


func _parar() -> void:
	if _reproduciendo and is_instance_valid(_reproduciendo):
		_reproduciendo.stop()
		if _reproduciendo.animation_finished.is_connected(_al_terminar):
			_reproduciendo.animation_finished.disconnect(_al_terminar)
	_reproduciendo = null
	if _reposo_nodo and is_instance_valid(_reposo_nodo):
		for prop in _reposo.keys():
			_reposo_nodo.set(prop, _reposo[prop])
	_reposo_nodo = null
	_reposo = {}
	if reproducir:
		reproducir.text = "Reproducir"
