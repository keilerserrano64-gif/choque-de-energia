@tool
extends EditorPlugin
## AutoAnim 2D: genera animaciones automáticas en Godot 4 para juegos 2D.
##  - Personaje: animaciones de los luchadores de Choque de Energía (golpe, patada,
##    recibir golpe, bloqueo, salto, aterrizaje, dash, técnica y victoria). Se guardan en
##    assets/fighters/<id>/<id>_autoanim.tres y el juego las usa solas.
##  - Efectos:   mueve cualquier Node2D, Sprite2D o Control (embestida, giro, rebote...).
##  - Escenario: objetos, luces 2D, plataformas, temblor de cámara y día/noche.
## Versión 3D anterior: choque_de_energia_godot/respaldo_autoanim_3d.

const U = preload("util.gd")
const AutoAnim2D := preload("res://scripts/data/auto_anim_2d.gd")
const CatalogScript := preload("res://scripts/data/catalog.gd")
const GenEfectos = preload("gen_efectos.gd")
const GenEscenario = preload("gen_escenario.gd")
const VistaPrevia = preload("vista_previa.gd")
const PanelIA = preload("ia/panel_ia.tscn")

var dock: VBoxContainer
var estado: Label

# Pestaña Personaje
var p_luchador: OptionButton
var p_accion: OptionButton
var p_estilo: OptionButton
var p_dur: SpinBox
var p_inten: SpinBox
var p_var: SpinBox
var p_capa: OptionButton
var p_capa_inten: SpinBox
var p_preset: OptionButton
var p_destino: OptionButton
var p_vista: VistaPrevia
var p_tiempo: HSlider
var p_play: Button
var p_vel: OptionButton
var p_lista: Label
var _presets: Array = []
var _moviendo_slider := false
var _ids: Array = []
var _acciones: Array = []
var _cargando := false

# Pestañas Efectos y Escenario
var ui := {}
var check_izq: CheckBox


# ================================================================ Interfaz

func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "AutoAnim"

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 420)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_child(tabs)

	_crear_personaje(tabs)
	var efectos := _crear_pestana(tabs, "Efectos", _duraciones_efectos(),
		"Selecciona uno o varios Node2D, Sprite2D o Control. Mueve, gira, escala y tiñe el nodo.", true)
	check_izq = CheckBox.new()
	check_izq.text = "Mi nodo mira a la izquierda"
	check_izq.tooltip_text = "Márcalo si la embestida va hacia atrás"
	efectos.add_child(check_izq)
	_crear_pestana(tabs, "Escenario", GenEscenario.DURACIONES,
		"Selecciona objetos 2D, luces 2D, un CanvasModulate (día/noche) o una Camera2D (temblor).", false)
	# Pestaña IA: describe el movimiento con palabras (Claude, Codex, Ollama o local sin IA).
	var panel_ia: Control = PanelIA.instantiate()
	panel_ia.set("deshacer", get_undo_redo())
	tabs.add_child(panel_ia)

	estado = Label.new()
	estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	estado.text = "Listo."
	dock.add_child(estado)

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	_elegir_luchador(0)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


func _crear_personaje(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Personaje"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var caja := VBoxContainer.new()
	caja.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(caja)
	_ayuda(caja, "Elige luchador, acción y estilo. «Guardar» lo aplica en el juego.")

	p_luchador = OptionButton.new()
	for f in CatalogScript.FIGHTERS:
		var d: Dictionary = f
		if d.has("sprites"):
			_ids.append(String(d["id"]))
			p_luchador.add_item(String(d["name"]))
	p_luchador.item_selected.connect(_elegir_luchador)
	_fila(caja, "Luchador", p_luchador)

	p_accion = OptionButton.new()
	for accion in AutoAnim2D.ACCIONES:
		_acciones.append(accion)
		p_accion.add_item(String(AutoAnim2D.ACCIONES[accion]))
	p_accion.item_selected.connect(func(_i: int) -> void: _cargar_accion())
	_fila(caja, "Acción", p_accion)

	p_estilo = OptionButton.new()
	for e in AutoAnim2D.estilos():
		p_estilo.add_item(e)
	p_estilo.item_selected.connect(func(_i: int) -> void:
		if not _cargando:
			_cargando = true
			p_dur.value = float(AutoAnim2D.DURACIONES[_estilo()])
			_cargando = false
		_actualizar_vista())
	_fila(caja, "Estilo", p_estilo)

	p_dur = _crear_spin(caja, "Duración (s)", 0.05, 5.0, 0.01, 0.3)
	p_inten = _crear_spin(caja, "Intensidad", 0.1, 3.0, 0.1, 1.0)
	p_var = _crear_spin(caja, "Variación", 0.0, 1.0, 0.05, 0.0)
	p_var.tooltip_text = "0 = siempre igual. Más alto = cada golpe sale un poco distinto (más vivo)."
	p_dur.value_changed.connect(func(_v: float) -> void: _actualizar_vista())
	p_inten.value_changed.connect(func(_v: float) -> void: _actualizar_vista())
	p_var.value_changed.connect(func(_v: float) -> void: _actualizar_vista())

	p_capa = OptionButton.new()
	p_capa.add_item("(ninguna)")
	for e in AutoAnim2D.estilos():
		p_capa.add_item(e)
	p_capa.tooltip_text = "Segundo estilo que se suma encima (p. ej. golpe_pesado + sacudida)"
	p_capa.item_selected.connect(func(_i: int) -> void: _actualizar_vista())
	_fila(caja, "Capa", p_capa)
	p_capa_inten = _crear_spin(caja, "Intensidad capa", 0.1, 3.0, 0.1, 0.5)
	p_capa_inten.value_changed.connect(func(_v: float) -> void: _actualizar_vista())

	p_vista = VistaPrevia.new()
	p_vista.generador = _anim_del_panel
	p_vista.tiempo_cambiado.connect(func(p: float) -> void:
		_moviendo_slider = true
		p_tiempo.set_value_no_signal(p)
		_moviendo_slider = false)
	caja.add_child(p_vista)

	var reproduccion := HBoxContainer.new()
	caja.add_child(reproduccion)
	p_play = Button.new()
	p_play.text = "❚❚"
	p_play.tooltip_text = "Pausar / reproducir"
	p_play.pressed.connect(func() -> void:
		p_vista.reproduciendo = not p_vista.reproduciendo
		p_play.text = "❚❚" if p_vista.reproduciendo else "▶")
	reproduccion.add_child(p_play)
	p_tiempo = HSlider.new()
	p_tiempo.min_value = 0.0
	p_tiempo.max_value = 1.0
	p_tiempo.step = 0.005
	p_tiempo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_tiempo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p_tiempo.tooltip_text = "Arrastra para ver la animación cuadro a cuadro"
	p_tiempo.value_changed.connect(func(v: float) -> void:
		if not _moviendo_slider:
			p_vista.ir_a(v)
			p_play.text = "▶")
	reproduccion.add_child(p_tiempo)
	p_vel = OptionButton.new()
	for v in ["1x", "0.5x", "0.25x"]:
		p_vel.add_item(v)
	p_vel.tooltip_text = "Cámara lenta"
	p_vel.item_selected.connect(func(i: int) -> void: p_vista.velocidad = [1.0, 0.5, 0.25][i])
	reproduccion.add_child(p_vel)

	var opciones := HBoxContainer.new()
	caja.add_child(opciones)
	var c_pose := CheckBox.new()
	c_pose.text = "Pose de la acción"
	c_pose.button_pressed = true
	c_pose.tooltip_text = "Muestra la imagen de la acción (jab, barrida...) y su secuencia si existe"
	c_pose.toggled.connect(func(on: bool) -> void:
		p_vista.usar_pose = on
		p_vista.poner_accion(_accion()))
	opciones.add_child(c_pose)
	var c_fant := CheckBox.new()
	c_fant.text = "Fantasmas"
	c_fant.tooltip_text = "Dibuja posiciones anteriores para ver el recorrido"
	c_fant.toggled.connect(func(on: bool) -> void: p_vista.fantasmas = on)
	opciones.add_child(c_fant)

	var botones := HBoxContainer.new()
	caja.add_child(botones)
	_boton(botones, "Guardar", "Usa este estilo para la acción elegida", _guardar_accion)
	_boton(botones, "Generar TODAS", "Pone el estilo recomendado en todas las acciones", _generar_todas)
	var botones2 := HBoxContainer.new()
	caja.add_child(botones2)
	_boton(botones2, "Quitar acción", "Vuelve al movimiento original del juego en esta acción", _quitar_accion)
	_boton(botones2, "Quitar todas", "Vuelve al movimiento original en todas las acciones", _quitar_todas)

	caja.add_child(HSeparator.new())
	p_preset = OptionButton.new()
	for nombre in AutoAnim2D.PRESETS:
		_presets.append(nombre)
		p_preset.add_item(String(AutoAnim2D.PRESETS[nombre]["nombre"]))
	_fila(caja, "Preset", p_preset)
	var botones3 := HBoxContainer.new()
	caja.add_child(botones3)
	_boton(botones3, "Aplicar preset", "Pone en TODAS las acciones el juego de estilos del preset (personalidad del luchador)", _aplicar_preset)

	p_destino = OptionButton.new()
	for k in _ids.size():
		p_destino.add_item(p_luchador.get_item_text(k))
	_fila(caja, "Copiar a", p_destino)
	var botones4 := HBoxContainer.new()
	caja.add_child(botones4)
	_boton(botones4, "Copiar animaciones", "Copia todas las animaciones de este luchador al elegido en «Copiar a»", _copiar_a)

	p_lista = Label.new()
	p_lista.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(p_lista)


func _crear_pestana(tabs: TabContainer, nombre: String, duraciones: Dictionary, ayuda: String, con_todas: bool) -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.name = nombre
	tabs.add_child(caja)
	_ayuda(caja, ayuda)

	var op := OptionButton.new()
	for t in duraciones.keys():
		op.add_item(t)
	caja.add_child(op)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.modulate = Color(1, 1, 1, 0.7)
	caja.add_child(info)

	var dur := _crear_spin(caja, "Duración (s)", 0.05, 600.0, 0.05, 1.0)
	var inten := _crear_spin(caja, "Intensidad", 0.1, 5.0, 0.1, 1.0)
	var al_elegir := func(idx: int) -> void:
		var t := op.get_item_text(idx)
		dur.value = duraciones[t]
		info.text = String(GenEscenario.AYUDA.get(t, "")) if nombre == "Escenario" else ""
	op.item_selected.connect(al_elegir)
	al_elegir.call(0)

	var b := Button.new()
	b.text = "Generar"
	b.pressed.connect(_generar.bind(nombre, false))
	caja.add_child(b)
	if con_todas:
		var b2 := Button.new()
		b2.text = "Generar TODAS"
		b2.pressed.connect(_generar.bind(nombre, true))
		caja.add_child(b2)

	ui[nombre] = {"op": op, "dur": dur, "inten": inten, "duraciones": duraciones}
	return caja


func _duraciones_efectos() -> Dictionary:
	return AutoAnim2D.DURACIONES.duplicate()


func _ayuda(caja: Control, texto: String) -> void:
	var lbl := Label.new()
	lbl.text = texto
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(lbl)


func _fila(caja: Control, texto: String, control: Control) -> void:
	var fila := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = texto
	lbl.custom_minimum_size = Vector2(70, 0)
	fila.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(control)
	caja.add_child(fila)


func _boton(caja: Control, texto: String, ayuda: String, accion: Callable) -> void:
	var b := Button.new()
	b.text = texto
	b.tooltip_text = ayuda
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(accion)
	caja.add_child(b)


func _crear_spin(caja: Control, texto: String, minimo: float, maximo: float, paso: float, valor: float) -> SpinBox:
	var fila := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = texto
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = minimo
	spin.max_value = maximo
	spin.step = paso
	spin.value = valor
	fila.add_child(spin)
	caja.add_child(fila)
	return spin


func _estado(texto: String) -> void:
	estado.text = texto
	print("[AutoAnim] ", texto)


# ================================================================ Personaje

func _id() -> String:
	return String(_ids[p_luchador.selected]) if p_luchador.selected >= 0 and p_luchador.selected < _ids.size() else ""


func _accion() -> String:
	return String(_acciones[p_accion.selected])


func _estilo() -> String:
	return p_estilo.get_item_text(p_estilo.selected)


func _elegir_luchador(_idx: int) -> void:
	if _ids.is_empty():
		_estado("No hay luchadores con imágenes en el catálogo.")
		return
	for f in CatalogScript.FIGHTERS:
		if String(f["id"]) == _id():
			p_vista.mostrar_luchador(f)
	AutoAnim2D.olvidar_cache()
	_cargar_accion()


## Muestra lo guardado para la acción (o el estilo recomendado si no hay nada).
func _cargar_accion() -> void:
	var guardado: Dictionary = AutoAnim2D.config(_id()).get(_accion(), {})
	var estilo := String(guardado.get("estilo", AutoAnim2D.RECOMENDADOS.get(_accion(), "golpe_seco")))
	_cargando = true
	_seleccionar(p_estilo, estilo)
	p_dur.value = float(guardado.get("duracion", AutoAnim2D.DURACIONES[estilo]))
	p_inten.value = float(guardado.get("intensidad", 1.0))
	p_var.value = float(guardado.get("variacion", 0.0))
	var capa: Dictionary = guardado.get("capa", {})
	p_capa.select(0)
	if not capa.is_empty():
		_seleccionar(p_capa, String(capa.get("estilo", "")))
		p_capa_inten.value = float(capa.get("intensidad", 0.5))
	_cargando = false
	p_vista.poner_accion(_accion())
	_actualizar_vista()
	_actualizar_lista()


func _seleccionar(op: OptionButton, texto: String) -> void:
	for k in op.item_count:
		if op.get_item_text(k) == texto:
			op.select(k)


## Lo que hay ahora en el panel, con el formato que se guarda en <id>_autoanim.tres.
func _datos_del_panel() -> Dictionary:
	var datos := {"estilo": _estilo(), "duracion": snappedf(p_dur.value, 0.01), "intensidad": snappedf(p_inten.value, 0.1)}
	if p_var.value > 0.0:
		datos["variacion"] = snappedf(p_var.value, 0.05)
	if p_capa.selected > 0:
		datos["capa"] = {"estilo": p_capa.get_item_text(p_capa.selected), "intensidad": snappedf(p_capa_inten.value, 0.1)}
	return datos


func _anim_del_panel() -> Dictionary:
	return AutoAnim2D.generar_desde(_datos_del_panel())


func _actualizar_vista() -> void:
	if _cargando or p_vista == null:
		return
	p_vista.poner_animacion(_anim_del_panel())


func _actualizar_lista() -> void:
	var acciones := AutoAnim2D.config(_id())
	if acciones.is_empty():
		p_lista.text = "Sin animaciones AutoAnim: usa los movimientos originales del juego."
		return
	var lineas := PackedStringArray(["Guardadas:"])
	for accion in AutoAnim2D.ACCIONES:
		if acciones.has(accion):
			var d: Dictionary = acciones[accion]
			var extra := ""
			if d.get("capa") is Dictionary:
				extra += " + " + String(d["capa"].get("estilo", ""))
			if float(d.get("variacion", 0.0)) > 0.0:
				extra += " ~%d%%" % roundi(float(d["variacion"]) * 100.0)
			lineas.append("· %s → %s%s (%.2f s, x%.1f)" % [AutoAnim2D.ACCIONES[accion], d["estilo"], extra, float(d["duracion"]), float(d["intensidad"])])
		elif AutoAnim2D.RESPALDO.has(accion) and acciones.has(AutoAnim2D.RESPALDO[accion]):
			lineas.append("· %s → (usa %s)" % [AutoAnim2D.ACCIONES[accion], AutoAnim2D.ACCIONES[AutoAnim2D.RESPALDO[accion]]])
	p_lista.text = "\n".join(lineas)


func _guardar(acciones: Dictionary, mensaje: String) -> void:
	var err := AutoAnim2D.guardar_config(_id(), acciones)
	if err != OK:
		_estado("No se pudo guardar %s (error %d)." % [AutoAnim2D.ruta_config(_id()), err])
		return
	EditorInterface.get_resource_filesystem().scan()
	_actualizar_lista()
	_estado(mensaje)


func _guardar_accion() -> void:
	var acciones := AutoAnim2D.config(_id()).duplicate(true)
	acciones[_accion()] = _datos_del_panel()
	_guardar(acciones, "%s: «%s» usará %s. Pulsa F5 para verlo." % [p_luchador.get_item_text(p_luchador.selected), AutoAnim2D.ACCIONES[_accion()], _estilo()])


func _generar_todas() -> void:
	var acciones := {}
	for accion in AutoAnim2D.RECOMENDADOS:
		var e := String(AutoAnim2D.RECOMENDADOS[accion])
		acciones[accion] = {"estilo": e, "duracion": AutoAnim2D.DURACIONES[e], "intensidad": snappedf(p_inten.value, 0.1)}
	_guardar(acciones, "%s: %d acciones con su estilo recomendado." % [p_luchador.get_item_text(p_luchador.selected), acciones.size()])
	_cargar_accion()


func _quitar_accion() -> void:
	var acciones := AutoAnim2D.config(_id()).duplicate(true)
	acciones.erase(_accion())
	var mensaje := "«%s» vuelve al movimiento original." % AutoAnim2D.ACCIONES[_accion()]
	var respaldo := String(AutoAnim2D.RESPALDO.get(_accion(), ""))
	if respaldo != "" and acciones.has(respaldo):
		mensaje = "«%s» ya no tiene animación propia: usará la de «%s»." % [AutoAnim2D.ACCIONES[_accion()], AutoAnim2D.ACCIONES[respaldo]]
	_guardar(acciones, mensaje)
	_cargar_accion()


func _quitar_todas() -> void:
	_guardar({}, "%s vuelve a sus movimientos originales." % p_luchador.get_item_text(p_luchador.selected))
	_cargar_accion()


func _aplicar_preset() -> void:
	if p_preset.selected < 0:
		return
	var nombre := String(_presets[p_preset.selected])
	_guardar(AutoAnim2D.preset(nombre), "%s: preset «%s» en %d acciones. Pulsa F5 para verlo." % [
		p_luchador.get_item_text(p_luchador.selected), AutoAnim2D.PRESETS[nombre]["nombre"], AutoAnim2D.ACCIONES.size()])
	_cargar_accion()


func _copiar_a() -> void:
	var k := p_destino.selected
	if k < 0 or k >= _ids.size():
		return
	var destino := String(_ids[k])
	if destino == _id():
		_estado("Elige en «Copiar a» un luchador distinto.")
		return
	var acciones := AutoAnim2D.config(_id())
	if acciones.is_empty():
		_estado("Este luchador no tiene animaciones que copiar.")
		return
	var err := AutoAnim2D.guardar_config(destino, acciones.duplicate(true))
	if err != OK:
		_estado("No se pudo copiar a %s (error %d)." % [destino, err])
		return
	EditorInterface.get_resource_filesystem().scan()
	_estado("Copiadas %d animaciones a %s." % [acciones.size(), p_destino.get_item_text(k)])


# ================================================================ Efectos y Escenario

func _generar(pestana: String, todas: bool) -> void:
	var c: Dictionary = ui[pestana]
	var op: OptionButton = c["op"]
	var duraciones: Dictionary = c["duraciones"]
	var tipos: Array = duraciones.keys() if todas else [op.get_item_text(op.selected)]
	var dur_manual: float = (c["dur"] as SpinBox).value
	var inten: float = (c["inten"] as SpinBox).value

	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		_estado("Primero selecciona un nodo en el árbol de la escena.")
		return
	if pestana == "Efectos":
		_gen_efectos(sel, tipos, todas, dur_manual, inten, duraciones)
	else:
		_gen_escenario(sel, tipos[0], dur_manual, inten)


func _gen_efectos(nodos: Array, tipos: Array, todas: bool, dur: float, inten: float, durs: Dictionary) -> void:
	var gen := GenEfectos.new()
	var hechos := 0
	var errores: PackedStringArray = []
	for n in nodos:
		if not GenEfectos.es_valido(n):
			errores.append("%s (no es 2D)" % n.name)
			continue
		var player: AnimationPlayer = U.buscar_o_crear_player(n, "AnimEfectos")
		for t in tipos:
			var d: float = durs[t] if todas else dur
			var anim: Animation = gen.generar(n, t, d, inten, check_izq.button_pressed)
			if anim:
				U.guardar(player, "efectos", t, anim)
			else:
				errores.append(gen.error)
		hechos += 1
	var texto := "Creadas %d animaciones en 'AnimEfectos' (efectos/...) de %d nodo(s). Guarda con Ctrl+S." % [tipos.size(), hechos]
	if not errores.is_empty():
		texto += "\nOmitidos: " + ", ".join(errores)
	_estado(texto)


func _gen_escenario(nodos: Array, tipo: String, dur: float, inten: float) -> void:
	var gen := GenEscenario.new()
	var hechos := 0
	var errores: PackedStringArray = []
	for n in nodos:
		var anim: Animation = gen.generar(n, tipo, dur, inten)
		if anim == null:
			errores.append(gen.error)
			continue
		var player: AnimationPlayer = U.buscar_o_crear_player(n, "AnimEscenario")
		U.guardar(player, "escenario", tipo, anim)
		if gen.es_loop(tipo):
			player.autoplay = "escenario/" + tipo
		hechos += 1
	var texto := "'%s' aplicado a %d objeto(s)." % [tipo, hechos]
	if hechos > 0:
		if gen.es_loop(tipo):
			texto += " Se reproduce sola al iniciar el juego."
		else:
			texto += " Actívala con $AnimEscenario.play(\"escenario/%s\")." % tipo
	if not errores.is_empty():
		texto += "\nOmitidos: " + ", ".join(errores)
	_estado(texto + " Guarda con Ctrl+S.")
