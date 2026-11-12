extends Node
## Ejecutar la escena con --headless; usa los autoloads y el combate reales.

var passed := 0
var failures := 0
var _saved: Dictionary = {}
var _fight: Node
var _intro_script: Script
var _finished := false
var _deadline := 0
const ACTIONS := ["p1_right", "p1_attack", "p2_left", "p2_attack"]


func _ready() -> void:
	for key in ["mode", "p1_id", "p2_id", "stage_id", "difficulty_id"]:
		_saved[key] = Router.get(key)
	_saved["skip_intro"] = SaveData.skip_intro
	get_tree().current_scene = null
	Engine.time_scale = 3.0
	_deadline = Time.get_ticks_msec() + 240000
	run.call_deferred()


func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() >= _deadline:
		check(false, "el ejecutor termina antes de 240 s reales")
		finish()


func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures += 1
		printerr("FALLO INTRO: " + message)


## Todas las esperas usan reloj real, independiente de Engine.time_scale.
func until(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not _finished and Time.get_ticks_msec() < end:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func release_actions() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)


func intro_count(fight: Node) -> int:
	var count := 0
	for child in fight.get_children():
		if child.get_script() == _intro_script:
			count += 1
	return count


func unit_checks() -> void:
	# load(), sin depender del registro de class_name ni de constantes del ejecutor.
	var registry = load("res://scripts/fight/intros/cinematic_intros.gd")
	_intro_script = load("res://scripts/fight/intros/madara_edo_intro.gd")
	for case in [["kakashi", "madara_edo", 9], ["madara_edo", "kakashi", 4],
			["madara_edo", "madara_edo", 9]]:
		var choice: Dictionary = registry.pick(case[0], case[1], 4, 9)
		check(choice.get("index", -1) == case[2], "pick prioriza el índice correcto: %s" % str(case))
		check(choice.get("scene", "") == "res://scenes/intros/madara_edo_intro.tscn",
			"pick devuelve la escena de Madara")
	check(registry.pick("kakashi", "naruto", 4, 9) == {}, "pick sin Madara devuelve {}")
	for sound in ["musica", "viento", "humo", "sharingan", "chakra", "onda"]:
		check(_intro_script.cargar_sonido(sound) is AudioStream, "sonido disponible: " + sound)
	check(_intro_script.cargar_sonido("nada") == null, "sonido desconocido devuelve null")
	var definition := Catalog.fighter("madara_edo")
	var px: Vector2 = definition.get("sprite_head", Vector2(73, 15)) + Vector2(3, 2)
	var right: Vector2 = _intro_script.punto_del_sprite(definition, 180.0, 230.0, 1, px)
	var left: Vector2 = _intro_script.punto_del_sprite(definition, 180.0, 230.0, -1, px)
	check(right.y < 230.0 and left.y < 230.0, "el punto del sprite queda sobre los pies")
	check(not is_zero_approx(right.x - 180.0), "el punto elegido permite comprobar el reflejo")
	check(is_equal_approx(right.x - 180.0, 180.0 - left.x)
		and is_equal_approx(right.y, left.y), "facing -1 refleja x y conserva y")


func new_fight(mode := "versus", skip := false, enemy := "madara_edo") -> Node:
	Router.mode = mode
	Router.p1_id = "kakashi"
	Router.p2_id = enemy
	Router.stage_id = String(Catalog.STAGES[0]["id"])
	Router.difficulty_id = String(Catalog.DIFFICULTIES.keys()[0])
	SaveData.skip_intro = skip
	_fight = load("res://scenes/fight.tscn").instantiate()
	add_child(_fight)
	return _fight


func discard_fight() -> void:
	release_actions()
	if is_instance_valid(_fight):
		var old_id := _fight.get_instance_id()
		_fight.queue_free()
		check(await until(func() -> bool: return not is_instance_id_valid(old_id), 2.0),
			"el combate anterior se libera")
	_fight = null
	check(not _intro_script.activa, "activa queda libre tras liberar el combate")


func during_intro(fight: Node, label: String) -> void:
	var intro = fight._cinematic
	check(not fight._running, label + ": combate detenido")
	check(fight.sim.state == "ready", label + ": simulación ready")
	check(fight.cinematic_camera, label + ": cámara dirigida por la intro")
	check(fight.arena.cinematic.has(fight.sim.enemy.index), label + ": arena incluye a Madara")
	check(_intro_script.activa, label + ": activa == true")
	check(intro_count(fight) == 1, label + ": una sola intro en el combate")
	var counts := {"started": 0, "finished": 0, "time": 0.0}
	intro.intro_started.connect(func() -> void: counts.started += 1)
	intro.intro_finished.connect(func() -> void:
		counts.finished += 1
		counts.time = intro.tiempo)
	intro.set_meta("test_counts", counts)
	var children: int = intro.get_child_count()
	var effects: int = fight.arena.get_child_count()
	var time_before: float = intro.tiempo
	# Debe retornar inmediatamente por activa, sin reiniciar ni crear efectos.
	intro.play(intro._ctx.duplicate())
	check(counts.started == 0 and intro.get_child_count() == children
		and fight.arena.get_child_count() == effects and intro_count(fight) == 1,
		label + ": play repetido no crea ni inicia otra intro")
	var positions := Vector2(fight.sim.player.x, fight.sim.enemy.x)
	var frozen := true
	for action in ACTIONS:
		check(InputMap.has_action(action), "InputMap contiene " + action)
		if InputMap.has_action(action):
			Input.action_press(action)
	var end := Time.get_ticks_msec() + 300
	while not _finished and Time.get_ticks_msec() < end:
		frozen = frozen and Vector2(fight.sim.player.x, fight.sim.enemy.x).is_equal_approx(positions)
		frozen = frozen and not fight._running and fight.sim.state == "ready"
		frozen = frozen and fight.sim.player.attack_pose == 0.0 and fight.sim.enemy.attack_pose == 0.0
		await get_tree().process_frame
	release_actions()
	check(frozen, label + ": ambos luchadores inmóviles y sin ataques pese a las acciones")
	check(intro.tiempo > time_before, label + ": tiempo avanza sin reiniciarse")


func playable(fight: Node, label: String) -> void:
	check(fight._running and fight.sim.state == "playing", label + ": combate jugando")
	check(fight._cinematic == null and fight.arena.cinematic.is_empty(), label + ": intro y arena limpias")
	check(fight.camera.zoom.is_equal_approx(Vector2.ONE), label + ": zoom restaurado")
	check(not fight.cinematic_camera, label + ": control normal de cámara")
	check(not _intro_script.activa, label + ": activa == false")
	check(is_equal_approx(fight.hud.modulate.a, 1.0), label + ": HUD restaurado")
	# Consultar la simulación tras entradas reales; no habilitar controles a mano.
	var players := [[fight.sim.player, "p1_right", "p1_attack"]]
	if fight.sim.mode == "versus":
		players.append([fight.sim.enemy, "p2_left", "p2_attack"])
	for pair in players:
		var fighter = pair[0]
		var start_x: float = fighter.x
		Input.action_press(pair[1])
		var moved := await until(func() -> bool: return absf(fighter.x - start_x) > 0.1, 1.0)
		Input.action_release(pair[1])
		check(moved, label + ": se mueve " + String(pair[1]))
		# Pulsar en física conserva just_pressed para PlayerInput.poll().
		await get_tree().physics_frame
		Input.action_press(pair[2])
		var attacked := await until(func() -> bool:
			return fighter.attack_pose > 0.0 or fighter.has_pending_attack, 1.0)
		Input.action_release(pair[2])
		check(attacked, label + ": puede atacar " + String(pair[2]))
	release_actions()


func cinematic_fight(label: String, skip := false) -> void:
	print("CASO INTRO: " + label)
	var fight = new_fight()
	var found := await until(func() -> bool: return is_instance_valid(fight._cinematic), 30.0)
	check(found, label + ": aparece la intro tras el VS")
	if not found:
		await discard_fight()
		return
	await during_intro(fight, label)
	var intro = fight._cinematic
	var counts: Dictionary = intro.get_meta("test_counts")
	var started := Time.get_ticks_msec()
	if skip:
		intro.saltar()
	var running := await until(func() -> bool: return fight._running, 2.0 if skip else 30.0)
	check(running, label + ": jugable antes del límite de tiempo real")
	if skip:
		check(Time.get_ticks_msec() - started < 2000 and counts.time < 11.0,
			label + ": saltar termina en menos de 2 s sin esperar los 11 s")
	else:
		check(counts.time >= 11.0, label + ": completa los 11 s de la secuencia")
	check(counts.finished == 1, label + ": intro_finished se emite una sola vez")
	if running:
		await playable(fight, label)
	await discard_fight()


func without_intro(mode: String, skip: bool, enemy: String) -> void:
	var label := "%s / skip=%s / %s" % [mode, skip, enemy]
	print("CASO SIN INTRO: " + label)
	var fight = new_fight(mode, skip, enemy)
	var seen := false
	var end := Time.get_ticks_msec() + 30000
	while not _finished and Time.get_ticks_msec() < end:
		seen = seen or is_instance_valid(fight._cinematic) or intro_count(fight) > 0 or _intro_script.activa
		if fight._running:
			break
		await get_tree().process_frame
	check(not seen, label + ": nunca se crea una cinemática")
	check(fight._running and fight.sim.state == "playing", label + ": llega a jugar")
	if fight._running:
		await playable(fight, label)
	await discard_fight()


func run() -> void:
	unit_checks()
	await cinematic_fight("primer combate completo")
	await cinematic_fight("segundo combate tras liberar el primero")
	await cinematic_fight("saltar", true)
	await without_intro("training", false, "madara_edo")
	await without_intro("versus", true, "madara_edo")
	await without_intro("versus", false, "naruto")
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
	Engine.time_scale = 1.0
	Sfx.stop_music()
	for player in Sfx._players:
		player.stop()
	# Permitir que los nodos y las referencias del mezclador se liberen.
	await get_tree().create_timer(0.15, true, false, true).timeout
	print("%d comprobaciones correctas, %d fallos" % [passed, failures])
	get_tree().quit(1 if failures > 0 else 0)
