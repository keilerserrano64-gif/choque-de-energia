extends Node
## Integracion del definitivo con la escena real. Ejecutar con --headless --max-fps 30.
## No escribe el guardado; restaura las opciones y las entradas al terminar.

const AUDIO := {
	"amenaza": 2.0, "susanoo": 3.5, "espada_alza": 1.5, "espada_tajo": 1.0,
	"risa": 3.0, "cielo": 3.0, "meteoro_cae": 2.5, "explosion1": 2.0,
	"explosion2": 3.0, "musica_definitivo": 25.0,
}
const HELD_ACTIONS := ["p1_right", "p1_attack", "p2_left", "p2_attack"]
const SHEET_PATH := "res://assets/fighters/madara_edo/definitivo/madara_edo_definitivo.json"
const CHARACTER_PHASES := ["preparacion", "susanoo", "tajo", "risa", "invocacion", "final"]
const SCENE_PHASES := ["meteoro1", "meteoro2", "impactos"]
## Hoja v2 (la de 30 s): fases que deben verse (en el escenario o como plano de cine).
const V2_PHASES := ["preparacion", "manifestacion", "perfecto", "ataque", "desvanecimiento", "risa", "rinnegan", "invocacion", "final"]

var passed := 0
var failures := 0
var _saved: Dictionary = {}
var _fight: Node
var _finished := false
var _deadline := 0


func _ready() -> void:
	for key in ["mode", "p1_id", "p2_id", "stage_id", "difficulty_id"]:
		_saved[key] = Router.get(key)
	_saved["skip_intro"] = SaveData.skip_intro
	_saved["time_scale"] = Engine.time_scale
	get_tree().current_scene = null
	Engine.time_scale = 3.0
	_deadline = Time.get_ticks_msec() + 210000
	run.call_deferred()


func _process(_delta: float) -> void:
	# Acelera los tramos normales del test, conservando las pausas de impacto reales.
	if not _finished and is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 3.0
	if not _finished and Time.get_ticks_msec() >= _deadline:
		check(false, "la integracion termina antes de 210 segundos reales")
		finish()


func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures += 1
		printerr("FALLO DEFINITIVO: " + message)


func until(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not _finished and Time.get_ticks_msec() < end:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func release_actions() -> void:
	for action in HELD_ACTIONS:
		Input.action_release(action)
	for keycode in [KEY_H, KEY_KP_3]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = false
		Input.parse_input_event(event)


func tap_awaken(index: int) -> void:
	# Pasa por InputMap, PlayerInput y CombatSim, sin inyectar su buffer privado.
	await get_tree().physics_frame
	var event := InputEventKey.new()
	event.keycode = KEY_H if index == 0 else KEY_KP_3
	event.physical_keycode = event.keycode
	event.pressed = true
	check(InputMap.event_is_action(event, "p%d_awaken" % (index + 1)),
		"la tecla de despertar corresponde a J%d" % (index + 1))
	Input.parse_input_event(event)
	# La tecla tiene que seguir pulsada cuando PlayerInput la lea en el siguiente paso de
	# física (si se suelta antes, is_action_just_pressed ya no la ve). Se suelta después.
	await get_tree().physics_frame
	await get_tree().physics_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


func audio_checks() -> void:
	for name in AUDIO:
		var path := "res://assets/ultimates/madara_edo/audio/%s.wav" % name
		var stream := load(path) as AudioStream
		check(stream != null, "Godot carga el sonido " + String(name))
		if stream:
			check(absf(stream.get_length() - float(AUDIO[name])) < 0.02,
				"duracion del sonido " + String(name))


func sheet_checks() -> void:
	check(FileAccess.file_exists(SHEET_PATH), "existe el manifiesto del definitivo v2")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHEET_PATH))
	check(parsed is Dictionary, "el manifiesto del definitivo es valido")
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	for pair in [["personaje", CHARACTER_PHASES], ["escenas", SCENE_PHASES]]:
		var group: Dictionary = data.get(pair[0], {})
		var texture := load(String(group.get("atlas", ""))) as Texture2D
		check(texture != null, "carga el atlas de " + String(pair[0]))
		var frames: Array = group.get("cuadros", [])
		var phases: Dictionary = group.get("fases", {})
		var seen := {}
		for phase in pair[1]:
			var indices: Array = phases.get(phase, [])
			check(not indices.is_empty(), "hay cuadros para " + String(phase))
			for value in indices:
				var index := int(value)
				check(index >= 0 and index < frames.size() and not seen.has(index),
					"indice de cuadro unico y valido: " + String(phase))
				seen[index] = true
		check(seen.size() == frames.size(), "todos los cuadros pertenecen a una fase")
		if texture:
			var bounds := Rect2i(Vector2i.ZERO, texture.get_size())
			var image := texture.get_image()
			for frame in frames:
				var r: Array = frame.get("rect", [])
				check(r.size() == 4, "rectangulo de cuadro con cuatro componentes")
				if r.size() == 4:
					var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
					check(bounds.encloses(rect),
						"cuadro dentro del atlas " + String(pair[0]))
					if pair[0] == "escenas" and bounds.encloses(rect):
						var used := image.get_region(rect).get_used_rect()
						check(used.size.x >= int(rect.size.y * 0.75),
							"el plano conserva anchura de escena: %s/%s" % [frame.fase, frame.i])
					elif pair[0] == "personaje" and bounds.encloses(rect) and frame.fase in ["preparacion", "risa"]:
						var used := image.get_region(rect).get_used_rect()
						check(used.size.y >= (40 if frame.fase == "preparacion" else 30),
							"se conserva la parte superior del personaje: %s/%s" % [frame.fase, frame.i])
	var plan = load("res://scripts/fight/ultimates/ultimate_sheet.gd")
	check(plan.cuadro_personaje({}, 8.0) == -1,
		"sin fases de hoja no se selecciona un cuadro de personaje")
	check(plan.plano({}, 20.0) == ["", -1, 0.0],
		"sin escenas de hoja no se selecciona un plano")
	for second in [0.0, 10.0, 21.1, 22.9, 25.6, 27.0]:
		check(plan.plano(data, second) == ["", -1, 0.0],
			"el plano no tapa el combate fuera de sus cortes: " + str(second))


func fixture(index: int, target_health := CombatSim.MAX_HEALTH) -> bool:
	Router.mode = "versus"
	Router.p1_id = "madara_edo" if index == 0 else "naruto"
	Router.p2_id = "naruto" if index == 0 else "madara_edo"
	Router.stage_id = String(Catalog.STAGES[0]["id"])
	Router.difficulty_id = "challenging"
	SaveData.skip_intro = true
	_fight = load("res://scenes/fight.tscn").instantiate()
	add_child(_fight)
	var ready := await until(func() -> bool: return bool(_fight.get("_running")), 8.0)
	check(ready, "el combate J%d queda jugable" % (index + 1))
	if not ready:
		return false
	var owner: FighterState = _fight.sim.fighter_by_index(index)
	_fight.sim.opponent_of(owner).health = target_health
	owner.awakening_available = true
	owner.meter = 100.0
	await tap_awaken(index)
	check(owner.awakening_time > 0.0 and not _fight.sim.ultimate_active,
		"la primera pulsacion despierta a J%d" % (index + 1))
	await tap_awaken(index)
	var active := await until(func() -> bool: return _fight.sim.ultimate_active, 2.0)
	check(active, "la segunda pulsacion activa el definitivo J%d" % (index + 1))
	if active:
		check(_fight.sim.ultimate_owner == index, "el definitivo pertenece al jugador correcto")
		check(is_zero_approx(owner.awakening_time), "el definitivo consume el despertar")
	return active


func controller() -> Node:
	for child in _fight.get_children():
		if String(child.scene_file_path).begins_with("res://scenes/ultimates/"):
			return child
	return null


func discard() -> void:
	release_actions()
	if is_instance_valid(_fight):
		var sim: CombatSim = _fight.sim
		_fight.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		check(not sim.ultimate_active and sim.ultimate_owner == -1,
			"salir del combate libera el estado del definitivo")
		check(not load("res://scripts/fight/ultimates/madara_ultimate.gd").activa,
			"salir libera el bloqueo global del definitivo")
	_fight = null


func full_sequence(index: int, knockout := false) -> void:
	var label := "J%d%s" % [index + 1, " con KO" if knockout else ""]
	print("CASO DEFINITIVO: " + label)
	if not await fixture(index, 5 if knockout else CombatSim.MAX_HEALTH):
		await discard()
		return
	var scene := controller()
	check(scene != null, label + ": se instancia la escena cinematica real")
	if scene == null:
		await discard()
		return
	check(bool(scene.get("_usa_hoja")), label + ": usa la hoja del usuario")
	var v2 := bool(scene.get("_v2"))
	var capas: Dictionary = scene.get("_capas") if v2 else {}
	var sheet: Node2D = capas.get("madara") if v2 else scene.get("_hoja")
	check(is_instance_valid(sheet), label + ": existe el dibujante de la hoja")
	if is_instance_valid(sheet):
		check(is_equal_approx(float(sheet.get("mira")), 1.0 if index == 0 else -1.0),
			label + ": la hoja mira al rival")
		check(float(sheet.get("escala")) > 0.0, label + ": escala de personaje positiva")
	# v3: el Susanoo de la hoja se dibuja en una capa aparte en «modo luz» (aditiva) tras Madara.
	var luz: Node2D = capas.get("susanoo") if v2 else scene.get("_hoja_luz")
	check(is_instance_valid(luz) and bool(luz.get("luz")), label + ": existe la capa de luz del Susanoo")
	if v2:
		var aura: Node2D = capas.get("aura")
		check(is_instance_valid(aura) and bool(aura.get("luz")), label + ": existe la capa de luz del aura")
	check(scene.get("efx") is Dictionary and (scene.get("efx") as Dictionary).has("meteoro_3"),
		label + ": sprites de efectos de la hoja cargados")
	if not v2:
		check(scene.get("escenas_tex") is Texture2D, label + ": hay atlas de planos de escena")
	var meteors_seen := false
	var golpes: Array = scene.get("tiempos_golpes")
	check(scene.get("retrato_tex") is Texture2D and scene.get("logo_tex") is Texture2D,
		label + ": retrato y logo disponibles")
	var character_seen := {}
	var scenes_seen := {}
	var sheet_valid := true
	var panels_valid := true
	var hit_times: Array[float] = []
	var sim: CombatSim = _fight.sim
	var owner := sim.fighter_by_index(index)
	var target := sim.opponent_of(owner)
	var health_changes: Array[int] = []
	var last_health := target.health
	var timer := sim.round_time
	var positions := Vector2(sim.player.x, sim.enemy.x)
	var frozen := true
	var round_results: Array[String] = []
	sim.round_finished.connect(func(result: String) -> void: round_results.append(result))
	for action in HELD_ACTIONS:
		Input.action_press(action)
	var end := Time.get_ticks_msec() + 45000
	while sim.ultimate_active and not _finished and Time.get_ticks_msec() < end:
		# La escena se libera un cuadro antes de que el combate cierre el definitivo.
		if not is_instance_valid(scene):
			await get_tree().process_frame
			continue
		frozen = frozen and is_equal_approx(sim.round_time, timer)
		frozen = frozen and Vector2(sim.player.x, sim.enemy.x).is_equal_approx(positions)
		frozen = frozen and round_results.is_empty()
		if target.health != last_health:
			health_changes.append(target.health)
			hit_times.append(float(scene.get("tiempo")))
			last_health = target.health
		var manifest: Dictionary = scene.get("_v2m") if v2 else scene.get("_manifiesto")
		for m in scene.get("meteoritos"):
			meteors_seen = meteors_seen or bool(m["visible"])
		if v2:
			var frames_v2: Array = manifest.get("cuadros", [])
			for capa in capas:
				var nodo: Node2D = capas[capa]
				if not is_instance_valid(nodo):
					continue
				var f2 := int(nodo.get("cuadro"))
				sheet_valid = sheet_valid and (f2 == -1 or (f2 >= 0 and f2 < frames_v2.size()))
				if f2 >= 0 and f2 < frames_v2.size():
					character_seen[frames_v2[f2].fase] = true
			if float(scene.get("plano_alfa")) > 0.01:
				var f3 := int(scene.get("plano_cuadro"))
				panels_valid = panels_valid and String(scene.get("plano_tipo")) == "personaje" and f3 >= 0 and f3 < frames_v2.size()
				if f3 >= 0 and f3 < frames_v2.size():
					character_seen[frames_v2[f3].fase] = true
		elif is_instance_valid(sheet):
			var frame := int(sheet.get("cuadro"))
			var frames: Array = manifest.get("personaje", {}).get("cuadros", [])
			# v3: Madara (sólido) en el escenario en todas sus fases; el Susanoo y el tajo,
			# en la capa de luz. Los planos de cine quedan para los paneles de escena.
			sheet_valid = sheet_valid and (frame == -1 or (frame >= 0 and frame < frames.size()))
			if frame >= 0 and frame < frames.size():
				character_seen[frames[frame].fase] = true
			if is_instance_valid(luz) and float(luz.get("alfa")) > 0.01:
				var f_luz := int(luz.get("cuadro"))
				sheet_valid = sheet_valid and (f_luz == -1 or (f_luz >= 0 and f_luz < frames.size()))
				if f_luz >= 0 and f_luz < frames.size():
					character_seen[frames[f_luz].fase] = true
		if not v2 and float(scene.get("plano_alfa")) > 0.01:
			var frame := int(scene.get("plano_cuadro"))
			var kind := String(scene.get("plano_tipo"))
			var frames: Array = manifest.get(kind, {}).get("cuadros", [])
			panels_valid = panels_valid and kind in ["personaje", "escenas"] and frame >= 0 and frame < frames.size()
			if frame >= 0 and frame < frames.size():
				if kind == "personaje":
					character_seen[frames[frame].fase] = true
				else:
					scenes_seen[frames[frame].fase] = true
		await get_tree().process_frame
	release_actions()
	check(not sim.ultimate_active, label + ": el definitivo termina antes del limite")
	check(frozen, label + ": reloj, posiciones y fin de ronda esperan a la cinematica")
	check(owner.health == CombatSim.MAX_HEALTH, label + ": el atacante no recibe golpes del input bloqueado")
	check(target.health == (0 if knockout else 52), label + ": el dano pasa por hit una vez por impacto")
	check(health_changes.size() == (1 if knockout else 3), label + ": numero correcto de impactos de salud")
	check(sheet_valid and panels_valid, label + ": los cuadros dibujados pertenecen a sus atlas")
	for phase in (V2_PHASES if v2 else CHARACTER_PHASES):
		check(character_seen.has(phase), label + ": se muestra la fase " + String(phase))
	if v2:
		check(meteors_seen, label + ": caen los meteoritos")
	else:
		for phase in SCENE_PHASES:
			check(scenes_seen.has(phase), label + ": se muestra el plano " + String(phase))
	var expected_times := [golpes[0]] if knockout else golpes
	for n in range(mini(hit_times.size(), expected_times.size())):
		check(absf(hit_times[n] - float(expected_times[n])) < 0.65,
			label + ": impacto sincronizado en segundo " + str(expected_times[n]))
	check(sim.ultimate_owner == -1, label + ": se libera el propietario")
	await get_tree().process_frame
	await get_tree().process_frame
	check(controller() == null, label + ": se libera la escena del definitivo")
	check(not is_instance_valid(sheet), label + ": se libera el nodo de la hoja")
	check(not is_instance_valid(luz), label + ": se libera la capa de luz del Susanoo")
	for capa in capas:
		check(not is_instance_valid(capas[capa]), label + ": se libera la capa " + String(capa))
	check(_fight.arena.cinematic.is_empty(), label + ": se restauran los luchadores")
	check(not _fight.cinematic_camera, label + ": camara de combate restaurada")
	check(is_equal_approx(_fight.hud.modulate.a, 1.0), label + ": HUD restaurado")
	check(not get_tree().paused, label + ": juego sin pausa residual")
	if knockout:
		var resolved := await until(func() -> bool: return not round_results.is_empty(), 3.0)
		check(resolved and round_results == ["player"], "el KO se resuelve una sola vez para Madara")
	else:
		check(sim.state == "playing" and _fight._running, label + ": se reanuda el combate")
		check(_fight.camera.zoom.is_equal_approx(Vector2.ONE), label + ": zoom restaurado")
		check(Sfx.get("_current_track") == "battle", label + ": vuelve la musica de combate")
		var start_x := owner.x
		var action := "p%d_%s" % [index + 1, "left" if index == 0 else "right"]
		Input.action_press(action)
		var moved := await until(func() -> bool: return absf(owner.x - start_x) > 0.1, 2.0)
		Input.action_release(action)
		check(moved, label + ": vuelve el control del luchador")
	await discard()


func abort_sequence() -> void:
	print("CASO DEFINITIVO: salir durante la cinematica")
	if await fixture(0):
		await get_tree().create_timer(0.7).timeout
		check(_fight.sim.ultimate_active, "la salida se prueba a media secuencia")
	await discard()


func skip_sequence() -> void:
	print("CASO DEFINITIVO: saltar la cinematica con hoja")
	if not await fixture(0):
		await discard()
		return
	var scene := controller()
	var sim: CombatSim = _fight.sim
	if scene:
		scene.call("saltar")
	var ended := await until(func() -> bool: return not sim.ultimate_active, 4.0)
	check(ended, "saltar termina la cinematica sin bloqueo")
	check(sim.enemy.health == 52, "saltar aplica los tres impactos pendientes una sola vez")
	await get_tree().process_frame
	await get_tree().process_frame
	check(controller() == null and _fight.arena.cinematic.is_empty(),
		"saltar limpia escena y reemplazos de luchadores")
	check(not _fight.cinematic_camera and is_equal_approx(_fight.hud.modulate.a, 1.0),
		"saltar restaura camara y HUD")
	await discard()


func run() -> void:
	audio_checks()
	sheet_checks()
	if "--assets-only" in OS.get_cmdline_user_args():
		finish()
		return
	await full_sequence(0)
	await full_sequence(1)
	await skip_sequence()
	await abort_sequence()
	# Tambien verifica que salir no deja un bloqueo global para el combate siguiente.
	await full_sequence(0, true)
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	release_actions()
	if is_instance_valid(_fight):
		_fight.queue_free()
	for key in ["mode", "p1_id", "p2_id", "stage_id", "difficulty_id"]:
		Router.set(key, _saved[key])
	SaveData.skip_intro = _saved.skip_intro
	Engine.time_scale = float(_saved.time_scale)
	Sfx.stop_music()
	await get_tree().process_frame
	print("DEFINITIVO: %d comprobaciones correctas, %d fallos" % [passed, failures])
	get_tree().quit(1 if failures else 0)
