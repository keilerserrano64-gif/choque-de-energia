extends Node
## Ejecutar como escena para cargar los autoloads reales.
var passed := 0
var failures := 0
var changes := 0
var _save_existed := false
var _save_backup := PackedByteArray()
var _old_item := ""
var _backup_ready := false

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures += 1
		printerr("FALLO UI: " + message)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(func() -> void: changes += 1)
	run.call_deferred()

func settle() -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not Router.is_busy():
			return true
	check(false, "Router termina la transición")
	return false

func key_event(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event

func pad_event(button: int, device := 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = device
	return event

func tap(event: InputEvent) -> void:
	event.pressed = true
	Input.parse_input_event(event)
	for i in 2:
		await get_tree().process_frame
	var release := event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	for i in 2:
		await get_tree().process_frame

func scene_is(key: String) -> bool:
	var scene := get_tree().current_scene
	var ok: bool = scene != null and scene.scene_file_path == Router.SCENES[key]
	check(ok, "escena esperada: " + key)
	return ok

func restore_save() -> void:
	if not _backup_ready:
		return
	_backup_ready = false
	SaveData.last_menu_item = _old_item
	if _save_existed:
		var file := FileAccess.open(SaveData.PATH, FileAccess.WRITE)
		file.store_buffer(_save_backup)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.PATH))

func finish() -> void:
	restore_save()
	# Dejar que el servidor de audio retire la reproducción antes de salir.
	Sfx.stop_music()
	for player in Sfx._players:
		player.stop()
	await get_tree().create_timer(0.15).timeout
	for i in 4:
		await get_tree().process_frame
	print("%d comprobaciones UI correctas, %d fallos" % [passed, failures])
	get_tree().quit(1 if failures else 0)

func _exit_tree() -> void:
	restore_save()

func run() -> void:
	# El runner sobrevive a change_scene; cada prueba usa escenas reales.
	get_tree().current_scene = null
	_save_existed = FileAccess.file_exists(SaveData.PATH)
	_save_backup = FileAccess.get_file_as_bytes(SaveData.PATH) if _save_existed else PackedByteArray()
	_old_item = SaveData.last_menu_item
	_backup_ready = true
	SaveData.last_menu_item = "training"
	Router.goto("title", 0.001)
	if not await settle() or not scene_is("title"):
		await finish()
		return
	var title = get_tree().current_scene
	check(title.scene_file_path == Router.SCENES.title, "ruta título")
	changes = 0
	title.start()
	title.start()
	check(Router.is_busy() and title._leaving, "start inicia una sola transición")
	Router.goto("fight", 0.001)
	await get_tree().create_timer(0.4).timeout
	var accept := InputEventKey.new()
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	var accept_release = accept.duplicate()
	accept_release.pressed = false
	Input.parse_input_event(accept_release)
	for button in [JOY_BUTTON_A, JOY_BUTTON_B]:
		var pad := InputEventJoypadButton.new()
		pad.device = 0
		pad.button_index = button
		pad.pressed = true
		Input.parse_input_event(pad)
		var pad_release = pad.duplicate()
		pad_release.pressed = false
		Input.parse_input_event(pad_release)
	if not await settle() or not scene_is("menu"):
		await finish()
		return
	check(changes == 1, "start repetido y goto ocupado cambian escena una vez")
	var menu = get_tree().current_scene
	check(menu.scene_file_path == Router.SCENES.menu, "título pasa al menú sin atravesar Enter")
	check(not menu._leaving, "Enter de transición no elige combate")
	menu.set_process(false)
	await get_tree().create_timer(0.7).timeout
	var focused := menu.get_viewport().gui_get_focus_owner()
	check(focused != null and focused.get_meta("item_id", "") == "training", "foco inicial persistente")
	for button in menu._buttons:
		check(button.is_visible_in_tree() and button.modulate.a > 0.99, "botón visible: " + String(button.get_meta("item_id")))
		check(Rect2(0, 0, 960, 540).encloses(button.get_global_rect()), "botón dentro de pantalla: " + String(button.get_meta("item_id")))
	await tap(pad_event(JOY_BUTTON_DPAD_DOWN))
	focused = get_viewport().gui_get_focus_owner()
	check(focused != null and focused.get_meta("item_id", "") == "options", "cruceta mueve el foco una opción")
	await tap(pad_event(JOY_BUTTON_A))
	check(menu.options_panel.visible and not menu._leaving, "A abre Opciones")
	menu._idle = 4.0
	menu._process(menu.IDLE_TIME + 1.0)
	check(menu._idle == 4.0 and not menu._leaving, "panel abierto suspende inactividad")
	var cancel := InputEventKey.new()
	cancel.physical_keycode = KEY_K
	cancel.pressed = true
	Input.parse_input_event(cancel)
	var cancel_release = cancel.duplicate()
	cancel_release.pressed = false
	Input.parse_input_event(cancel_release)
	await get_tree().process_frame
	check(not menu.options_panel.visible and not menu._leaving, "cancelar cierra Opciones antes del título")
	check(menu._idle == 0.0, "cerrar panel reinicia inactividad")
	focused = get_viewport().gui_get_focus_owner()
	check(focused != null and focused.get_meta("item_id", "") == "options", "Opciones devuelve el foco al botón de origen")
	await tap(pad_event(JOY_BUTTON_DPAD_DOWN))
	await tap(key_event(KEY_ENTER))
	check(menu.store_panel.visible and not menu._leaving, "Enter abre Tienda")
	await tap(pad_event(JOY_BUTTON_B))
	check(not menu.store_panel.visible and not menu._leaving, "B cierra Tienda antes del título")
	focused = get_viewport().gui_get_focus_owner()
	check(focused != null and focused.get_meta("item_id", "") == "store", "Tienda devuelve el foco al botón de origen")
	menu._idle = 8.0
	var motion := InputEventJoypadMotion.new()
	motion.axis_value = menu.STICK_DEADZONE - 0.01
	menu._input(motion)
	check(menu._idle == 8.0, "deriva del stick no cuenta")
	motion.axis_value = menu.STICK_DEADZONE
	menu._input(motion)
	check(menu._idle == 0.0, "stick real reinicia inactividad")
	menu._process(menu.IDLE_TIME - 0.1)
	check(not menu._leaving, "inactividad espera IDLE_TIME")
	menu._process(0.11)
	check(menu._leaving, "inactividad usa IDLE_TIME")
	if not await settle() or not scene_is("title"):
		await finish()
		return
	check(get_tree().current_scene.scene_file_path == Router.SCENES.title, "inactividad vuelve al título")
	await tap(pad_event(JOY_BUTTON_A, 1))
	if not await settle() or not scene_is("menu"):
		await finish()
		return
	check(not get_tree().current_scene._leaving, "A del segundo mando inicia sin activar el menú nuevo")
	menu = get_tree().current_scene
	menu.set_process(false)
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await get_tree().process_frame
	check(menu._leaving, "cancelar sin panel vuelve al título")
	if not await settle() or not scene_is("title"):
		await finish()
		return
	# Una escena que consulta Input en _process también debe ignorar el wipe.
	Router.goto("stage", 0.5)
	await get_tree().scene_changed
	if not scene_is("stage"):
		await finish()
		return
	var stage = get_tree().current_scene
	var selected: int = stage._selected
	check(Router.is_busy(), "escenario sigue destapándose")
	await tap(key_event(KEY_J))
	await tap(pad_event(JOY_BUTTON_A))
	await tap(pad_event(JOY_BUTTON_DPAD_RIGHT))
	check(not stage._done and stage._selected == selected, "teclado y mando no llegan a Input durante el wipe")
	if not await settle() or not scene_is("stage"):
		await finish()
		return
	check(not stage._done, "confirmar durante el wipe no deja una salida pendiente")
	await tap(pad_event(JOY_BUTTON_DPAD_RIGHT))
	check(stage._selected == (selected + 1) % stage._cards.size(), "mando vuelve a responder después del wipe")
	await finish()
