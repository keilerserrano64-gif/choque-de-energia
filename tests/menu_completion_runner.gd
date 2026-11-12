extends Node
## Regresiones de las revisiones #5/#6. También se ejecuta con render para probar el clic.
var passed := 0
var failures := 0
var _existed := false
var _backup := PackedByteArray()
var _old_item := ""
var _finished := false


func _ready() -> void:
	_existed = FileAccess.file_exists(SaveData.PATH)
	if _existed:
		_backup = FileAccess.get_file_as_bytes(SaveData.PATH)
	_old_item = SaveData.last_menu_item
	get_tree().current_scene = null
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		if not _finished:
			check(false, "la prueba termina antes del límite")
			finish())
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures += 1
		printerr("FALLO MENÚ: " + message)


func frames() -> void:
	for i in 3:
		await get_tree().process_frame


func settle() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Router.is_busy() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.01).timeout
	check(not Router.is_busy(), "termina la transición")
	await frames()


func pad(button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()


func focus_stays_inside(node: Node, panel: Control) -> void:
	if node is Control and node.focus_mode == Control.FOCUS_ALL and node.is_visible_in_tree():
		var inside := true
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var neighbor = node.find_valid_focus_neighbor(side)
			inside = inside and (neighbor == null or panel.is_ancestor_of(neighbor))
		for neighbor in [node.find_next_valid_focus(), node.find_prev_valid_focus()]:
			inside = inside and (neighbor == null or panel.is_ancestor_of(neighbor))
		check(inside, "el foco no sale del panel: " + String(node.get_path()))
	for child in node.get_children():
		focus_stays_inside(child, panel)


func screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join("choque_completion_" + label + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "captura " + label)


func run() -> void:
	Router.goto("title", 0.001)
	await settle()
	await get_tree().create_timer(1.8).timeout
	var title = get_tree().current_scene
	check(title.get_node("Version").text == "v" + String(ProjectSettings.get_setting("application/config/version")), "versión real en el título")
	await screenshot("title")
	var click := InputEventMouseButton.new()
	click.position = Vector2(480, 460)
	click.global_position = click.position
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await frames()
	check(title._leaving and Router.is_busy(), "un clic real inicia desde el título")
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await settle()
	var menu = get_tree().current_scene
	if menu.scene_file_path != Router.SCENES.menu:
		check(false, "el título llega al menú")
		finish()
		return
	menu.set_process(false)
	await get_tree().create_timer(0.6).timeout
	for button in menu._buttons:
		check(Rect2(0, 0, 960, 540).encloses(button.get_global_rect()), "botón dentro de pantalla: " + String(button.get_meta("item_id")))
	await screenshot("menu")
	for item_id in ["options", "store"]:
		var trigger: Button
		for button in menu._buttons:
			if button.get_meta("item_id") == item_id:
				trigger = button
		trigger.grab_focus()
		menu._choose(item_id)
		await get_tree().create_timer(0.2).timeout
		var panel: Control = menu.options_panel if item_id == "options" else menu.store_panel
		check(panel.visible, "abre " + item_id)
		for button in menu._buttons:
			check(button.disabled and button.focus_mode == Control.FOCUS_NONE, "botón del fondo desactivado: " + String(button.get_meta("item_id")))
		focus_stays_inside(panel, panel)
		menu._choose("cpu")
		menu._buttons[0].pressed.emit()
		check(not menu._leaving and not Router.is_busy() and panel.visible, "el fondo no puede iniciar un combate con " + item_id)
		if item_id == "store":
			await pad(JOY_BUTTON_DPAD_LEFT)
			check(panel.is_ancestor_of(get_viewport().gui_get_focus_owner()), "cruceta izquierda mantiene el foco en la tienda")
			for card in menu.store_panel._cards:
				for label_name in ["FighterName", "AwakeningName", "Status"]:
					var label: Label = card.get_node(label_name)
					check(card.get_global_rect().encloses(label.get_global_rect()), "texto dentro de la tarjeta: " + String(card.get_meta("fighter_id")) + "/" + label_name)
					check(label.get_line_count() * label.get_line_height() <= label.size.y + 1.0, "todas las líneas caben: " + label.text)
		await screenshot(item_id)
		await pad(JOY_BUTTON_B)
		check(not panel.visible and not menu._leaving, "B cierra solo " + item_id)
		check(get_viewport().gui_get_focus_owner() == trigger, "restaura foco tras " + item_id)
		for button in menu._buttons:
			check(not button.disabled and button.focus_mode == Control.FOCUS_ALL, "restaura botón: " + String(button.get_meta("item_id")))
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	SaveData.last_menu_item = _old_item
	if _existed:
		var file := FileAccess.open(SaveData.PATH, FileAccess.WRITE)
		check(file != null, "se puede restaurar el guardado")
		if file:
			file.store_buffer(_backup)
			file.close()
			check(FileAccess.get_file_as_bytes(SaveData.PATH) == _backup, "el guardado queda idéntico al original")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.PATH))
	Sfx._music.stop()
	for player in Sfx._players:
		player.stop()
	# El mezclador de audio libera sus referencias en un hilo distinto.
	await get_tree().create_timer(0.15).timeout
	await frames()
	print("%d comprobaciones de cierre correctas, %d fallos" % [passed, failures])
	get_tree().quit(1 if failures else 0)
