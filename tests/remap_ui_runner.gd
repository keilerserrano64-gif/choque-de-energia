extends Node
## Prueba entradas reales de teclado y mando tras separar menú y combate.
var passed := 0
var failures := 0
var backup := PackedByteArray()
var existed := false
var old_item := ""
var finished := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	existed = FileAccess.file_exists(SaveData.PATH)
	if existed:
		backup = FileAccess.get_file_as_bytes(SaveData.PATH)
	old_item = SaveData.last_menu_item
	get_tree().current_scene = null
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		if not finished:
			check(false, "la prueba termina a tiempo")
			finish())
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures += 1
		printerr("FALLO SELECCIÓN: " + message)


func settle() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Router.is_busy() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.01).timeout
	check(not Router.is_busy(), "termina transición")


func tap(code: int, device: int = -1) -> void:
	var event: InputEvent
	if device < 0:
		event = InputEventKey.new()
		event.physical_keycode = code
	else:
		event = InputEventJoypadButton.new()
		event.button_index = code
		event.device = device
	event.pressed = true
	Input.parse_input_event(event)
	for i in 3:
		await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	for i in 3:
		await get_tree().process_frame


func select_scene(mode: String) -> Control:
	Router.begin(mode)
	Router.goto("select", 0.001)
	await settle()
	await get_tree().create_timer(1.2).timeout
	var scene = get_tree().current_scene
	check(scene.scene_file_path == Router.SCENES.select, "escena de luchadores")
	return scene


func wait_for_scene(key: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		var scene := get_tree().current_scene
		if scene and scene.scene_file_path == Router.SCENES[key] and not Router.is_busy():
			return true
		await get_tree().create_timer(0.01).timeout
	return false


func run() -> void:
	var scene = await select_scene("cpu")
	await tap(KEY_I)
	check(scene.phase == 0 and not scene.locked[0], "I (puño) no confirma selección")
	await tap(KEY_J)
	check(scene.phase == 1 and scene.locked[0], "J confirma J1")
	await tap(KEY_K)
	check(scene.phase == 0 and not scene.locked[0] and not Router.is_busy(), "K vuelve a J1 sin salir al menú")
	await tap(KEY_K)
	await settle()
	check(get_tree().current_scene.scene_file_path == Router.SCENES.menu, "K desde J1 vuelve al menú")
	scene = await select_scene("versus")
	await tap(KEY_I)
	check(not scene.locked[0] and not scene.locked[1], "I tampoco confirma en VS")
	await tap(KEY_J)
	check(scene.locked[0] and not scene.locked[1], "J confirma solo J1 en VS")
	await tap(KEY_K)
	check(not scene.locked[0], "K desbloquea J1 en VS")
	await tap(KEY_KP_1)
	check(scene.locked[1] and not scene.locked[0], "Num1 confirma solo J2")
	await tap(KEY_KP_2)
	check(not scene.locked[1], "Num2 desbloquea J2")
	for device in [0, 1]:
		await tap(JOY_BUTTON_A, device)
		check(scene.locked[device] and not scene.locked[1 - device], "A confirma solo el mando %d" % device)
		await tap(JOY_BUTTON_B, device)
		check(not scene.locked[device] and not Router.is_busy(), "B desbloquea solo el mando %d" % device)
	Router.goto("stage", 0.001)
	await settle()
	scene = get_tree().current_scene
	await tap(KEY_I)
	check(not scene._done and not Router.is_busy(), "I no confirma escenario")
	await tap(KEY_K)
	await settle()
	check(get_tree().current_scene.scene_file_path == Router.SCENES.select, "K vuelve del escenario a luchadores")
	Router.goto("stage", 0.001)
	await settle()
	scene = get_tree().current_scene
	await tap(KEY_J)
	check(scene._done, "J confirma escenario")
	var in_fight := await wait_for_scene("fight")
	check(in_fight, "escenario llega al combate")
	if not in_fight:
		await finish()
		return
	# PlayerInput debe consumir acciones de combate, sin depender de las del menú.
	var fight = get_tree().current_scene
	fight.set_process(false)
	fight.set_physics_process(false)
	var player_input := PlayerInput.new()
	for pair in [[KEY_I, "attack"], [KEY_J, "kick"], [KEY_K, "special"], [KEY_L, "heavy"]]:
		# poll se comprueba con una pulsación mantenida en cuadros separados.
		var event := InputEventKey.new()
		event.physical_keycode = pair[0]
		event.pressed = true
		Input.parse_input_event(event)
		var received := false
		for i in 3:
			player_input.poll()
			received = player_input.consume_press(0, pair[1], "versus") or received
			await get_tree().process_frame
		check(received, "PlayerInput recibe " + pair[1])
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		await get_tree().process_frame
	await finish()


func finish() -> void:
	if finished:
		return
	finished = true
	SaveData.last_menu_item = old_item
	if existed:
		var file := FileAccess.open(SaveData.PATH, FileAccess.WRITE)
		check(file != null, "restaura guardado")
		if file:
			file.store_buffer(backup)
			file.close()
			check(FileAccess.get_file_as_bytes(SaveData.PATH) == backup, "guardado idéntico")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.PATH))
	Sfx.stop_music()
	for player in Sfx._players:
		player.stop()
	await get_tree().create_timer(0.15).timeout
	print("%d comprobaciones de selección correctas, %d fallos" % [passed, failures])
	get_tree().quit(1 if failures else 0)
