extends SceneTree
## Pruebas de la lógica de combate (sin ventanas). Ejecuta desde la carpeta del proyecto:
##   godot --headless --path . -s res://tests/test_runner.gd
## (Abre antes el proyecto una vez en el editor para que Godot registre las clases.)

var passed := 0
var failures := 0


class FakeInput extends RefCounted:
	var down := {}
	var pressed := {}

	func _key(index, action) -> String:
		return "%d_%s" % [index, action]

	func is_down(index, action, _mode) -> bool:
		return down.has(_key(index, action))

	func consume_press(index, action, _mode) -> bool:
		var k := _key(index, action)
		if pressed.has(k):
			pressed.erase(k)
			return true
		return false

	func clear_pressed() -> void:
		pressed.clear()

	func press(index, action) -> void:
		pressed[_key(index, action)] = true


func _initialize() -> void:
	test_madara_definitivo_efectos()
	test_madara_definitivo_frames()
	test_madara_intro_frames()
	test_menu_contract()
	test_catalog()
	test_animations()
	test_hitstun()
	test_knockdown_locks_control()
	test_jump_crosses_over()
	test_blocking()
	test_heavy_attack()
	test_strong_attack_variants()
	test_heavy_kick_names()
	test_command_buffers()
	test_ai_repertoire()
	test_vfx_events()
	test_input_buffer()
	test_combo_branches()
	test_air_and_guard_states()
	test_anim_events()
	test_animador()
	test_auto_anim_2d()
	test_auto_anim_v31()
	test_auto_anim_revision_codex()
	test_auto_anim_receta_ia()
	test_calidad_luchadores()
	test_auto_anim_ia_constructor()
	test_sprite_sequences()
	test_best_of_three()
	test_timer()
	test_versus_controls()
	test_training()
	test_every_technique()
	test_combo_and_rewards()
	test_punch_and_kick_chains()
	test_mixed_chain()
	test_true_combos()
	test_proration()
	test_ai_combos()
	test_air_attacks()
	test_sweep_and_antiair()
	test_throw()
	test_counter_hit()
	test_knockdown_bounce()
	test_kakashi_kit()
	test_madara_ultimate()
	test_long_simulation()
	test_sprite_sheet()
	test_fighter_importer()
	print("\n%d comprobaciones correctas, %d fallos" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failures += 1
		printerr("FALLO: " + message)


func test_madara_definitivo_efectos() -> void:
	var path := "res://assets/fighters/madara_edo/definitivo/efectos/efectos.json"
	check(FileAccess.file_exists(path), "efectos Madara: existe manifiesto")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(data is Dictionary, "efectos Madara: manifiesto válido")
	if not data is Dictionary:
		return
	# La enumeración del encargo contiene 23 piezas: 6 + 9 + 4 + 4.
	var names := ["tajo_azul", "tajo_morado_1", "tajo_morado_2", "anillo_1", "anillo_2", "aura_morada", "explosion"]
	for group in [["roca", 6], ["meteoro", 3], ["humo", 3], ["escombros", 4]]:
		for i in range(1, int(group[1]) + 1):
			names.append("%s_%d" % [group[0], i])
	check(data.size() == names.size(), "efectos Madara: las 23 piezas enumeradas")
	for name in names:
		check(data.has(name), "efectos Madara: existe " + name)
		if not data.has(name):
			continue
		var entry: Dictionary = data[name]
		var texture := load(String(entry.png)) as Texture2D
		check(texture != null, "efectos Madara: Texture2D " + name)
		if texture == null:
			continue
		var im := texture.get_image()
		var size := im.get_size()
		check(size == Vector2i(int(entry.tam[0]), int(entry.tam[1])), "efectos Madara: tamaño " + name)
		for p in [Vector2i.ZERO, Vector2i(size.x - 1, 0), Vector2i(0, size.y - 1), size - Vector2i.ONE]:
			check(im.get_pixelv(p).a == 0.0, "efectos Madara: esquina transparente " + name)
		var bottom: bool = name == "explosion" or name == "aura_morada" or name.begins_with("escombros_")
		check(is_equal_approx(float(entry.ancla[0]), size.x / 2.0) and is_equal_approx(float(entry.ancla[1]), float(size.y) if bottom else size.y / 2.0), "efectos Madara: ancla " + name)
		if name.begins_with("roca_") or name.begins_with("meteoro_"):
			check(im.get_pixelv(size / 2).a > 0.95, "efectos Madara: centro opaco " + name)
		var used := im.get_used_rect()
		check(used.position == Vector2i.ONE and used.end == size - Vector2i.ONE, "efectos Madara: recorte ajustado " + name)


func test_madara_intro_frames() -> void:
	var path := "res://assets/fighters/madara_edo/intro/madara_edo_intro_frames.json"
	check(FileAccess.file_exists(path), "existe el manifiesto de la intro de Madara")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary, "se lee el manifiesto de la intro de Madara")
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	check(data.cuadros.size() == 48, "intro Madara: 48 cuadros")
	var expected := {"aparicion": 8, "materializacion": 8, "sello": 9, "chakra": 11, "presentacion": 12}
	var seen := {}
	for phase in expected:
		check(data.fases.has(phase) and data.fases[phase].size() == expected[phase], "intro Madara: cantidad de " + phase)
		for index in data.fases.get(phase, []):
			check(index >= 0 and index < data.cuadros.size() and not seen.has(index), "intro Madara: índice único y válido")
			seen[index] = true
			if index >= 0 and index < data.cuadros.size():
				check(data.cuadros[index].fase == phase, "intro Madara: fase del cuadro")
	var texture := load(String(data.atlas)) as Texture2D
	check(texture != null, "intro Madara: atlas carga como Texture2D")
	if texture == null:
		return
	var im := texture.get_image()
	var bounds := Rect2i(Vector2i.ZERO, im.get_size())
	var anchor := Vector2i(int(data.ancla[0]), int(data.ancla[1]))
	check(data.columnas == 8 and int(data.celda[0]) % 2 == 0 and int(data.celda[1]) % 2 == 0, "intro Madara: rejilla par de ocho columnas")
	check(data.alto_figura > 0 and data.mira in ["derecha", "izquierda"], "intro Madara: altura y orientación")
	for frame in data.cuadros:
		var r: Array = frame.rect
		var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		check(bounds.encloses(rect), "intro Madara: rectángulo dentro del atlas")
		if not bounds.encloses(rect):
			continue
		check(rect.size == Vector2i(int(data.celda[0]), int(data.celda[1])) and Rect2i(Vector2i.ZERO, rect.size).has_point(anchor), "intro Madara: celda y ancla válidas")
		for corner in [Vector2i.ZERO, Vector2i(rect.size.x - 1, 0), Vector2i(0, rect.size.y - 1), rect.size - Vector2i.ONE]:
			check(im.get_pixelv(rect.position + corner).a == 0.0, "intro Madara: esquina transparente")
		var opaque := false
		for y in range(anchor.y - 8, anchor.y + 9):
			for x in range(anchor.x - 20, anchor.x + 21):
				var p := rect.position + Vector2i(x, y)
				if rect.has_point(p) and im.get_pixelv(p).a > 0.95:
					opaque = true
		check(opaque, "intro Madara: píxeles opacos cerca de los pies")
	var eyes := load(String(data.ojos.atlas)) as Texture2D
	check(eyes != null and data.ojos.size() == 4, "intro Madara: atlas de tres ojos")
	if eyes != null:
		for name in ["cerrado", "despierta", "sharingan"]:
			check(data.ojos.has(name), "intro Madara: ojo " + name)
			if data.ojos.has(name):
				var r: Array = data.ojos[name]
				check(Rect2i(Vector2i.ZERO, eyes.get_size()).encloses(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))), "intro Madara: rectángulo de ojo válido")
	check(FileAccess.file_exists(String(data.retrato)) and load(String(data.retrato)) is Texture2D, "intro Madara: existe y carga el retrato")


func test_madara_definitivo_frames() -> void:
	var path := "res://assets/fighters/madara_edo/definitivo/madara_edo_definitivo.json"
	check(FileAccess.file_exists(path), "definitivo Madara: existe manifiesto")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary, "definitivo Madara: manifiesto válido")
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fuentes/mapa_madara_edo_definitivo.json"))
	for key in ["personaje", "escenas"]:
		check(data.has(key) and data[key] is Dictionary, "definitivo Madara: sección " + key)
		if not data.has(key) or not data[key] is Dictionary:
			continue
		var group: Dictionary = data[key]
		var texture := load(String(group.atlas)) as Texture2D
		check(texture != null, "definitivo Madara: carga atlas " + key)
		if texture == null:
			continue
		var im := texture.get_image()
		var bounds := Rect2i(Vector2i.ZERO, im.get_size())
		var size := Vector2i(int(group.celda[0]), int(group.celda[1]))
		check(size.x > 0 and size.y > 0 and group.columnas == 8, "definitivo Madara: celda y columnas")
		var seen := {}
		var total := 0
		for phase in map.fases:
			if (phase.tipo == "personaje") != (key == "personaje"):
				continue
			total += phase.celdas.size()
			check(group.fases.has(phase.nombre) and group.fases[phase.nombre].size() == phase.celdas.size(), "definitivo Madara: cantidad " + phase.nombre)
			var ordinal := 0
			for index in group.fases.get(phase.nombre, []):
				var valid: bool = index >= 0 and index < group.cuadros.size() and not seen.has(index)
				check(valid, "definitivo Madara: índice único válido")
				seen[index] = true
				if valid:
					check(group.cuadros[index].fase == phase.nombre and group.cuadros[index].i == ordinal, "definitivo Madara: orden del mapa")
				ordinal += 1
		check(total == group.cuadros.size() and seen.size() == total, "definitivo Madara: total de cuadros")
		var anchor := Vector2i.ZERO
		if key == "personaje":
			anchor = Vector2i(int(group.ancla[0]), int(group.ancla[1]))
			check(Rect2i(Vector2i.ZERO, size).has_point(anchor) and group.alto_figura > 0 and group.mira in ["derecha", "izquierda"], "definitivo Madara: ancla, altura y orientación")
		for frame in group.cuadros:
			var a: Array = frame.rect
			var r := Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
			check(bounds.encloses(r) and r.size == size, "definitivo Madara: rect dentro del atlas")
			if not bounds.encloses(r):
				continue
			if key == "personaje":
				for corner in [Vector2i.ZERO, Vector2i(size.x - 1, 0), Vector2i(0, size.y - 1), size - Vector2i.ONE]:
					check(im.get_pixelv(r.position + corner).a == 0, "definitivo Madara: esquina transparente")
				var opaque := false
				for y in range(maxi(0, anchor.y - 8), mini(size.y, anchor.y + 9)):
					for x in range(maxi(0, anchor.x - 20), mini(size.x, anchor.x + 21)):
						if im.get_pixelv(r.position + Vector2i(x, y)).a > 0.95:
							opaque = true
				check(opaque, "definitivo Madara: cuerpo cerca del ancla")
			else:
				check(im.get_pixelv(r.get_center()).a > 0.99, "definitivo Madara: escena opaca en centro")
	for key in ["retrato", "logo", "efectos"]:
		check(data.has(key) and FileAccess.file_exists(String(data[key])) and load(String(data[key])) is Texture2D, "definitivo Madara: recurso " + key)


func make_sim(p1: String = "kakashi", p2: String = "kakashi", mode: String = "cpu") -> Array:
	var input := FakeInput.new()
	var sim := CombatSim.new(input)
	sim.rng.seed = 1234
	sim.configure(p1, p2, "brumaria", "challenging", mode)
	sim.start()
	return [sim, input]


func step(sim: CombatSim, frames: int) -> void:
	for i in range(frames):
		sim.update(1.0 / 60.0)


func freeze_ai(sim: CombatSim) -> void:
	sim.enemy.ai_decision = 999.0
	sim.enemy.ai_jump_timer = 999.0


# ---------------------------------------------------------------------------

func test_catalog() -> void:
	check(Catalog.FIGHTERS.size() >= 1, "hay al menos un luchador")
	check(Catalog.STAGES.size() == 4, "hay cuatro escenarios")
	var ids := {}
	for f in Catalog.FIGHTERS:
		ids[f["id"]] = true
	check(ids.size() == Catalog.FIGHTERS.size(), "los identificadores son únicos")


func test_animations() -> void:
	for f in Catalog.FIGHTERS:
		var id := String(f["id"])
		var anims := FighterAnimations.for_fighter(id)
		for anim_name in ["idle", "walk", "run", "jump", "block", "charge", "special", "hurt", "fall", "getup", "victory", "intro"]:
			check(anims.has(anim_name), "%s tiene la animación %s" % [id, anim_name])
		var attacks := ["weak", "strong", "kick"] if id == "brasa" else ["light", "heavy", "finisher"]
		for attack in attacks:
			check(FighterAnimations.first_hitbox_frame(anims[attack]) > 0, "%s: %s tiene hitbox tras la anticipación" % [id, attack])


func test_hitstun() -> void:
	var data := make_sim()
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	freeze_ai(sim)
	sim.hit(sim.player, 1, 10, {"knockback": 80.0, "hit_stop": 0.0, "attacker": 1})
	sim.hit_stop_frames = 0.0
	input.press(0, "attack")
	step(sim, 1)
	check(not sim.player.has_pending_attack, "con hitstun no se puede atacar")
	step(sim, 20)
	input.press(0, "attack")
	step(sim, 1)
	check(sim.player.has_pending_attack, "tras el hitstun se vuelve a atacar")


func test_knockdown_locks_control() -> void:
	var data := make_sim()
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	freeze_ai(sim)
	sim.hit(sim.player, 1, 10, {"knockback": 0.0, "hit_stop": 0.0, "launch_y": -230.0, "attacker": 1})
	sim.hit_stop_frames = 0.0
	var x0 := sim.player.x
	input.down["0_left"] = true
	step(sim, 10)
	check(sim.player.knocked_down, "el lanzamiento derriba")
	check(absf(sim.player.x - x0) < 0.01, "derribado no se controla en el aire")


func test_jump_crosses_over() -> void:
	var data := make_sim("kakashi", "kakashi")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	sim.player.x = 150.0
	sim.enemy.x = 200.0
	input.down["0_right"] = true
	input.down["0_run"] = true
	input.press(0, "jump")
	var crossed := false
	for i in range(70):
		freeze_ai(sim)
		sim.enemy.x = 200.0
		step(sim, 1)
		if sim.player.x > sim.enemy.x:
			crossed = true
	check(crossed, "un salto alto permite cruzar al rival")


func test_blocking() -> void:
	var data := make_sim("kakashi", "kakashi")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	freeze_ai(sim)
	input.down["0_left"] = true  # el rival está a la derecha: atrás = izquierda
	step(sim, 1)
	check(not sim.player.blocking, "caminar hacia atrás ya no bloquea")
	input.down.erase("0_left")
	input.down["0_block"] = true
	step(sim, 1)
	check(sim.player.blocking, "mantener la tecla de cubrirse activa el bloqueo")
	var before := sim.player.health
	var connected := sim.hit(sim.player, -1, 20, {"hit_stop": 0.0, "attacker": 1})
	check(not connected and sim.player.health == before, "el bloqueo detiene el golpe")
	check(sim.consume_audio_events().has("block"), "el bloqueo suena")


func test_heavy_attack() -> void:
	for f in Catalog.FIGHTERS:
		var id := String(f["id"])
		var data := make_sim(id, "kakashi")
		var sim: CombatSim = data[0]
		var input: FakeInput = data[1]
		sim.enemy.x = sim.player.x + 62.0
		sim.enemy.special_cooldown = 99.0  # que no lo esquive con su técnica
		var before := sim.enemy.health
		freeze_ai(sim)
		input.press(0, "heavy")
		step(sim, 1)
		check(sim.player.attack_cooldown >= CombatSim.HEAVY_COOLDOWN - 0.02, "%s: el golpe fuerte tiene recuperación larga" % id)
		for i in range(40):
			freeze_ai(sim)
			step(sim, 1)
		check(sim.enemy.health < before, "%s: el golpe fuerte conecta" % id)
		check(sim.player.max_combo == 0, "%s: el golpe fuerte no cuenta como combo" % id)
		var shocks := sim.consume_vfx_events().filter(func(e: Dictionary) -> bool: return e["type"] == "shock")
		check(shocks.size() >= 1, "%s: el golpe fuerte lanza la onda de pantalla" % id)


func test_strong_attack_variants() -> void:
	for fighter in Catalog.FIGHTERS:
		var id := String(fighter["id"])
		for is_kick in [false, true]:
			var data := _close_fight(id)
			var sim: CombatSim = data[0]
			sim.enemy.special_cooldown = 99.0  # aislar la hitbox de la esquiva reactiva de Kakashi
			sim.consume_anim_events()
			var expected := "finisher" if is_kick else "heavy"
			var base := "patada" if is_kick else "golpe"
			sim.request_attack(sim.player, "heavy_kick" if is_kick else "heavy")
			check(sim.player.attack_animation == expected, "%s: fuerte separado usa %s" % [id, expected])
			check(sim.player.pending_heavy and sim.player.attack_index == 0, "%s: %s es un fuerte independiente" % [id, expected])
			check(is_equal_approx(sim.player.attack_windup, FighterAnimations.first_hitbox_frame(FighterAnimations.get_animation(id, expected)) / 60.0), "%s: tiempos propios de %s" % [id, expected])
			var events := sim.consume_anim_events()
			check(events.any(func(event: Dictionary) -> bool: return event["i"] == 0 and event["tipo"] == base and event.get("base") == base), "%s: %s emite %s con base correcta" % [id, expected, base])
			var health := sim.enemy.health
			for frame in 42:
				freeze_ai(sim)
				step(sim, 1)
			check(sim.enemy.health < health, "%s: %s conecta con el rival" % [id, expected])
			check(sim.player.max_combo == 0, "%s: %s no crea un combo ficticio" % [id, expected])
			# Un fuerte en cadena conserva el tipo del último golpe de la cadena.
			data = _close_fight(id)
			sim = data[0]
			var input: FakeInput = data[1]
			_do_chain(sim, input, "kick" if is_kick else "attack", 1)
			sim.consume_anim_events()
			sim.request_attack(sim.player, "heavy")
			for frame in 45:
				freeze_ai(sim)
				step(sim, 1)
				if not sim.player.pending_branch.is_empty():
					break
			check(not sim.player.pending_branch.is_empty() and sim.player.attack_animation == expected, "%s: rama de %s conserva %s" % [id, base, expected])
			check(_anim_types(sim, 0).has(base), "%s: rama emite %s" % [id, base])


func test_command_buffers() -> void:
	var cases := [
		{"action": "attack", "down": true, "saved": "low_attack", "animation": "uppercut"},
		{"action": "kick", "down": true, "saved": "sweep", "animation": "sweep"},
		{"action": "heavy", "down": true, "toward": true, "saved": "heavy_kick", "animation": "finisher"},
		{"action": "heavy", "toward": true, "saved": "throw", "animation": "throw"},
		{"action": "heavy", "saved": "heavy", "animation": "heavy"},
		{"action": "attack", "air": true, "down": true, "saved": "attack", "animation": "air_punch"},
		{"action": "kick", "air": true, "down": true, "saved": "kick", "animation": "air_kick"},
	]
	for index in [0, 1]:
		for frozen in [false, true]:
			for sample in cases:
				var data := make_sim("kakashi", "kakashi", "versus")
				var sim: CombatSim = data[0]
				var input: FakeInput = data[1]
				var f := sim.fighter_by_index(index)
				var target := sim.opponent_of(f)
				target.x = f.x + f.facing * 60.0
				f.attack_cooldown = 0.12
				if sample.get("air", false):
					f.grounded = false
					f.y = -50.0
				if sample.get("down", false):
					input.down["%d_down" % index] = true
				if sample.get("toward", false):
					input.down["%d_%s" % [index, "right" if f.facing > 0 else "left"]] = true
				if frozen:
					sim.hit_stop_frames = 2.0
				input.press(index, sample.action)
				step(sim, 1)
				var context := "J%d %s %s" % [index + 1, "hit-stop" if frozen else "normal", sample.saved]
				check(f.buffered_input == sample.saved, "conserva comando completo: " + context)
				input.down.clear()
				for frame in 25:
					step(sim, 1)
					if f.has_pending_attack:
						break
				check(f.attack_animation == sample.animation and f.has_pending_attack, "sale el comando después de soltar dirección: " + context)
	# Un agarre guardado vuelve al fuerte normal si el rival sale de alcance.
	var data := make_sim("kakashi", "kakashi", "versus")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	sim.enemy.x = sim.player.x + 60.0
	sim.player.attack_cooldown = 0.12
	input.down["0_right"] = true
	input.press(0, "heavy")
	step(sim, 1)
	input.down.clear()
	sim.enemy.x += 150.0
	step(sim, 10)
	check(sim.player.attack_animation == "heavy", "agarre en buffer fuera de alcance cae al puño fuerte")


func test_ai_repertoire() -> void:
	for difficulty in [0.8, 1.0, 1.3]:
		var data := make_sim()
		var sim: CombatSim = data[0]
		sim.enemy.difficulty = difficulty
		sim.enemy.x = sim.player.x + 62.0
		sim.rng.seed = 421
		var seen := {}
		for attempt in 120:
			sim._plan_ai_combo(sim.enemy, 62.0)
			if sim.enemy.ai_plan.size() == 1:
				seen[String(sim.enemy.ai_plan[0])] = true
		check(seen.has("heavy") and seen.has("heavy_kick") and seen.has("special") and seen.has("sweep"), "CPU nivel %s incluye ambos fuertes, técnica y barrida sueltos" % difficulty)
		var used_special := false
		for seed_value in 40:
			data = make_sim()
			sim = data[0]
			sim.rng.seed = seed_value
			sim.enemy.difficulty = difficulty
			sim.enemy.x = sim.player.x + 62.0
			sim.enemy.ai_decision = 0.0
			sim.enemy.ai_jump_timer = 999.0
			sim._move_enemy(1.0 / 60.0)
			used_special = used_special or sim.enemy.special_charge > 0.0
		check(used_special, "CPU nivel %s realmente usa técnica a corta distancia" % difficulty)
	for sample in [["heavy", "heavy"], ["heavy_kick", "finisher"], ["sweep", "sweep"], ["throw", "throw"]]:
		var data := make_sim()
		var sim: CombatSim = data[0]
		sim.enemy.x = sim.player.x + 62.0
		sim.enemy.ai_plan = [sample[0]]
		sim._run_ai_plan(sim.enemy, sim.player)
		check(sim.enemy.attack_animation == sample[1], "CPU ejecuta " + sample[0])
	var antiair := false
	var grabbed := false
	for seed_value in 20:
		var data := make_sim()
		var sim: CombatSim = data[0]
		sim.rng.seed = seed_value
		sim.enemy.x = sim.player.x + 62.0
		sim.enemy.ai_decision = 0.0
		sim.player.grounded = false
		sim.player.y = -50.0
		sim._ai_reactions(sim.enemy, sim.player, 62.0)
		antiair = antiair or sim.enemy.attack_animation == "uppercut"
		sim.player.grounded = true
		sim.player.guard_time = 1.0
		sim._plan_ai_combo(sim.enemy, 62.0)
		grabbed = grabbed or sim.enemy.ai_plan == ["throw"]
	check(antiair, "CPU mantiene el antiaéreo situacional")
	check(grabbed, "CPU mantiene el agarre contra la guardia")


func _anim_types(sim: CombatSim, index: int) -> Array:
	var types: Array = []
	for e in sim.consume_anim_events():
		if int(e["i"]) == index:
			types.append(String(e["tipo"]))
	return types


func test_anim_events() -> void:
	var data := make_sim("kakashi", "kakashi")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	freeze_ai(sim)
	check(_anim_types(sim, 0).has("reiniciar"), "al empezar la ronda el animador se reinicia")
	sim.enemy.x = sim.player.x + 62.0
	input.press(0, "attack")
	step(sim, 1)
	check(_anim_types(sim, 0).has("golpe"), "el golpe I avisa al animador (golpe)")
	sim.player.attack_cooldown = 0.0
	sim.player.attack_windup = 0.0
	sim.player.has_pending_attack = false
	input.press(0, "heavy")
	step(sim, 1)
	check(_anim_types(sim, 0).has("golpe"), "el golpe fuerte L avisa al animador (golpe)")
	sim.hit(sim.player, -1, 10, {"hit_stop": 0.0, "attacker": 1})
	check(_anim_types(sim, 0).has("golpe_recibido"), "recibir un golpe avisa al animador")
	sim.player.hurt_time = 0.0
	input.down["0_block"] = true
	step(sim, 1)
	sim.hit(sim.player, -1, 10, {"hit_stop": 0.0, "attacker": 1})
	check(_anim_types(sim, 0).has("bloqueo"), "bloquear un golpe avisa al animador")
	input.down.clear()
	sim.player.special_cooldown = 0.0
	sim.player.blocking = false
	sim.use_technique(sim.player, sim.enemy)
	step(sim, 12)
	check(_anim_types(sim, 0).has("dash"), "la técnica de Volt avisa al animador (dash)")
	sim.enemy.health = 0
	sim.hit_stop_frames = 0.0  # la técnica ahora conecta pegado al rival y deja pausa de impacto
	step(sim, 1)
	var end_events := sim.consume_anim_events()
	check(end_events.any(func(e: Dictionary) -> bool: return e["tipo"] == "ko" and int(e["i"]) == 1), "el K.O. avisa al animador del caído")
	check(end_events.any(func(e: Dictionary) -> bool: return e["tipo"] == "victoria" and int(e["i"]) == 0), "la victoria avisa al animador del ganador")


func test_animador() -> void:
	var animador := AnimadorProcedural.new()
	root.add_child(animador)
	var f := FighterState.new("kakashi", 200.0, 1)
	animador.preparar(f)
	animador.actualizar(f, 1.0 / 60.0)
	check(animador.golpe() is Tween, "el animador crea el tween del golpe")
	animador.ko()
	check(bool(animador.salida()["ko"]), "tras ko() el animador marca el K.O.")
	animador.reiniciar()
	check(not bool(animador.salida()["ko"]) and animador.desp_accion == Vector2.ZERO, "reiniciar() devuelve todo a la normalidad")
	animador.queue_free()


func test_auto_anim_2d() -> void:
	var auto := load("res://scripts/data/auto_anim_2d.gd")
	for estilo in auto.estilos():
		var anim: Dictionary = auto.generar(estilo, -1.0, 1.0)
		check(not anim.is_empty(), "AutoAnim 2D genera el estilo %s" % estilo)
		var inicio: Dictionary = auto.muestrear(anim, 0.0)
		var mitad: Dictionary = auto.muestrear(anim, float(anim["duracion"]) * 0.45)
		check(inicio.has("desp") and mitad.has("escala") and mitad.has("rot") and mitad.has("color"), "%s devuelve desp, escala, rot y color" % estilo)
		if not auto.es_loop(estilo):
			var fin: Dictionary = auto.muestrear(anim, float(anim["duracion"]))
			var gira := absf(fmod(float(fin["rot"]), 360.0)) < 0.01
			check((fin["desp"] as Vector2).is_zero_approx() and (fin["escala"] as Vector2).is_equal_approx(Vector2.ONE) and gira,
				"%s termina en la postura normal" % estilo)
	check(auto.generar("no_existe").is_empty(), "un estilo desconocido no genera nada")
	for accion in auto.RECOMENDADOS:
		check(auto.ACCIONES.has(accion) and auto.DURACIONES.has(auto.RECOMENDADOS[accion]), "la acción %s tiene un estilo recomendado válido" % accion)
	var golpe: Dictionary = auto.generar("golpe_seco", 0.3, 1.0)
	var impacto: Dictionary = auto.muestrear(golpe, 0.3 * 0.42)
	check((impacto["desp"] as Vector2).x > 10.0, "el golpe seco avanza hacia delante en el impacto")
	var doble: Dictionary = auto.muestrear(auto.generar("golpe_seco", 0.3, 2.0), 0.3 * 0.42)
	check((doble["desp"] as Vector2).x > (impacto["desp"] as Vector2).x * 1.9, "la intensidad multiplica el movimiento")

	# Guardar y cargar con un luchador de prueba que no existe en el juego.
	var id := "prueba_autoanim"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/fighters/" + id))
	var err: int = auto.guardar_config(id, {"golpe": {"estilo": "golpe_pesado", "duracion": 0.5, "intensidad": 1.5}, "malo": {"estilo": "golpe_seco"}})
	check(err == OK, "AutoAnim 2D guarda las animaciones del luchador")
	auto.olvidar_cache()
	var cargado: Dictionary = auto.config(id)
	check(cargado.has("golpe") and not cargado.has("malo"), "al cargar se ignoran las acciones desconocidas")
	check(float(auto.para_accion(id, "golpe")["duracion"]) == 0.5, "para_accion usa la duración guardada")
	check(auto.para_accion(id, "patada").is_empty(), "una acción sin animación devuelve vacío")

	# El animador del juego usa la animación guardada en vez de su tween fijo.
	var animador := AnimadorProcedural.new()
	root.add_child(animador)
	var f := FighterState.new("kakashi", 200.0, 1)
	animador.preparar(f)
	animador.auto_anim_id = id
	animador.ejecutar({"tipo": "golpe", "i": 0}, f)
	for n in 9:  # 0.15 s de 0.5: aún cargando hacia atrás (el impacto llega a 0.24 s)
		animador.actualizar(f, 1.0 / 60.0)
	check(animador.desp_accion.x < 0.0, "el animador sigue la animación AutoAnim (carga hacia atrás)")
	for n in 30:
		animador.actualizar(f, 1.0 / 60.0)
	check(animador.desp_accion == Vector2.ZERO and animador.salida()["color"] == Color.WHITE, "al terminar la animación AutoAnim vuelve a la normalidad")
	animador.ejecutar({"tipo": "patada", "i": 0}, f)
	check(animador.desp_accion == Vector2.ZERO, "sin animación AutoAnim la patada usa el movimiento original")
	animador.queue_free()
	auto.guardar_config(id, {})
	check(not FileAccess.file_exists(auto.ruta_config(id)), "quitar todas las acciones borra el archivo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://assets/fighters/" + id))
	auto.olvidar_cache()


func test_sprite_sequences() -> void:
	var importer := load("res://scripts/tools/fighter_importer.gd")
	check(importer.is_valid_pose("seq_jab") and importer.is_valid_pose("seq_run"), "el importador acepta secuencias seq_<animación>")
	check(not importer.is_valid_pose("seq_nada"), "el importador rechaza secuencias de animaciones que no existen")
	var definition := {"sprites": {"seq_jab": ["a", "b", "c", "d"]}}
	check(FighterPainter._sprite_path(definition, "seq_jab", 0.0, {"progress": 0.0}) == "a", "la secuencia empieza por su primer cuadro")
	check(FighterPainter._sprite_path(definition, "seq_jab", 0.0, {"progress": 0.6}) == "c", "la secuencia avanza con la animación")
	check(FighterPainter._sprite_path(definition, "seq_jab", 0.0, {"progress": 0.999}) == "d", "la secuencia termina en su último cuadro")
	var itachi := Catalog.fighter("itachi")
	for anim in ["run", "jab", "cross", "hook", "uppercut", "kick_high", "sweep", "special", "hurt"]:
		check(FighterPainter._sprite_available(itachi["sprites"], "seq_" + anim), "Itachi tiene la secuencia de %s" % anim)
	var data := make_sim("itachi", "kakashi")
	var sim: CombatSim = data[0]
	var arena: Node = load("res://scripts/render/arena_view.gd").new()
	arena.set("sim", sim)
	sim.state = "playing"
	sim.player.attack_animation = "jab"
	sim.player.attack_pose = FighterAnimations.duration(FighterAnimations.get_animation("itachi", "jab")) / 60.0
	var frame: Dictionary = arena.call("fighter_animation", sim.player)
	check(frame.get("name") == "jab" and float(frame.get("progress", -1.0)) < 0.05, "fighter_animation marca el avance al empezar el golpe")
	arena.free()


## Prepara a dos luchadores pegados y sin IA para probar golpes.
func _close_fight(p1: String = "kakashi", p2: String = "kakashi") -> Array:
	var data := make_sim(p1, p2)
	var sim: CombatSim = data[0]
	freeze_ai(sim)
	sim.enemy.x = sim.player.x + 62.0
	return data


func test_input_buffer() -> void:
	var data := _close_fight()
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	input.press(0, "attack")
	step(sim, 1)
	input.press(0, "attack")  # pulsado en mitad del primer golpe
	step(sim, 1)
	check(sim.player.buffered_input == "attack", "la pulsación durante un golpe se guarda en el buffer")
	for i in range(30):
		freeze_ai(sim)
		step(sim, 1)
	check(sim.player.attack_index >= 2, "el golpe guardado sale solo sin volver a pulsar")


func test_combo_branches() -> void:
	var data := _close_fight()
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	input.press(0, "attack")
	step(sim, 1)
	input.press(0, "heavy")  # I → L
	var launched := false
	for i in range(50):
		freeze_ai(sim)
		step(sim, 1)
		if sim.last_action == "¡LANZADOR!":
			launched = true
	check(launched, "I → L es el lanzador")
	check(sim.enemy.knocked_down or not sim.enemy.grounded or sim.enemy.getup_time > 0.0, "el lanzador levanta al rival")

	data = _close_fight()
	sim = data[0]
	input = data[1]
	var cross := false
	var presses := ["attack", "attack", "heavy"]
	for i in range(90):
		freeze_ai(sim)
		sim.enemy.x = sim.player.x + 62.0
		if i % 14 == 0 and not presses.is_empty():
			input.press(0, presses.pop_front())
		step(sim, 1)
		if sim.last_action == "¡REMATE CRUZADO!":
			cross = true
	check(cross, "I → I → L es el remate cruzado")
	check(ComboData.branch_for(Catalog.fighter("kakashi"), 0).is_empty(), "sin cadena no hay rama: L es el golpe fuerte suelto")


func test_air_and_guard_states() -> void:
	# Golpeado en el aire → derribado (StateDamagedOnAir → StateKnockedDown).
	var data := _close_fight()
	var sim: CombatSim = data[0]
	sim.enemy.grounded = false
	sim.enemy.y = -40.0
	sim.enemy.velocity_y = -100.0
	sim.hit(sim.enemy, 1, 8, {"hit_stop": 0.0, "attacker": 0})
	check(sim.enemy.knocked_down, "un golpe en el aire derriba al rival")
	var landed := false
	for i in range(90):
		freeze_ai(sim)
		step(sim, 1)
		if sim.enemy.getup_time > 0.0:
			landed = true
			break
	check(landed, "al caer, el derribado se levanta del suelo")
	var before := sim.enemy.health
	check(not sim.hit(sim.enemy, 1, 20, {"hit_stop": 0.0, "attacker": 0}) and sim.enemy.health == before, "no se puede golpear al que se está levantando")

	# Bloqueo en el aire (StateBlockingOnAir).
	data = _close_fight()
	sim = data[0]
	var input: FakeInput = data[1]
	sim.player.grounded = false
	sim.player.y = -50.0
	input.down["0_block"] = true
	step(sim, 1)
	check(sim.player.blocking, "se puede bloquear en el aire")

	# Guardia firme: bloquear un golpe cuerpo a cuerpo aturde al atacante (StateBlockingOnFloor).
	data = _close_fight()
	sim = data[0]
	input = data[1]
	input.down["0_block"] = true
	step(sim, 1)
	var hp := sim.player.health
	sim.hit(sim.player, -1, 15, {"hit_stop": 0.0, "attacker": 1, "melee": true})
	check(sim.player.health == hp, "el bloqueo no recibe daño")
	check(sim.enemy.hurt_time > 0.0, "bloquear un golpe cuerpo a cuerpo aturde al atacante")
	sim.enemy.hurt_time = 0.0
	sim.hit(sim.player, -1, 15, {"hit_stop": 0.0, "attacker": 1})
	check(sim.enemy.hurt_time == 0.0, "bloquear un proyectil no aturde a quien lo lanzó")


func test_vfx_events() -> void:
	var data := make_sim("kakashi", "kakashi")
	var sim: CombatSim = data[0]
	freeze_ai(sim)
	sim.hit(sim.enemy, 1, 5, {"hit_stop": 0.0, "attacker": 0})
	check(sim.consume_vfx_events().is_empty(), "un golpe ligero no activa los shaders de pantalla")
	sim.player.meter = 100.0
	sim.awaken(sim.player, true)
	var events := sim.consume_vfx_events()
	check(events.size() == 1 and events[0]["type"] == "awaken", "el despertar activa el shader de pantalla")
	sim.enemy.health = 0
	step(sim, 1)
	events = sim.consume_vfx_events()
	check(events.any(func(e: Dictionary) -> bool: return e["type"] == "ko"), "el K.O. activa el shader de pantalla")


func test_best_of_three() -> void:
	var data := make_sim()
	var sim: CombatSim = data[0]
	sim.enemy.health = 0
	step(sim, 1)
	check(sim.state == "round-finished" and sim.player_round_wins == 1, "gana la ronda 1")
	check(sim.next_round(), "pasa a la ronda 2")
	check(sim.player.health == 100 and sim.enemy.health == 100, "la vida se restaura")
	sim.enemy.health = 0
	step(sim, 1)
	check(sim.state == "finished" and sim.winner_index() == 0, "dos rondas ganan el combate")
	check(sim.reward >= 30, "la victoria da al menos 30 monedas")


func test_timer() -> void:
	var data := make_sim()
	var sim: CombatSim = data[0]
	freeze_ai(sim)
	sim.enemy.health = 60
	sim.round_time = 0.01
	step(sim, 2)
	check(sim.state == "round-finished" and sim.round_result == "player", "al acabarse el tiempo gana quien tiene más vida")


func test_versus_controls() -> void:
	var data := make_sim("kakashi", "kakashi", "versus")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	var x0 := sim.enemy.x
	step(sim, 30)
	check(absf(sim.enemy.x - x0) < 0.01, "en VS la IA no mueve al J2")
	input.down["1_left"] = true
	step(sim, 30)
	check(sim.enemy.x < x0 - 10.0, "el J2 se mueve con sus controles")
	check(is_equal_approx(sim.enemy.damage_multiplier, 1.0), "en VS no se aplica la dificultad de la CPU")


func test_training() -> void:
	var data := make_sim("kakashi", "kakashi", "training")
	var sim: CombatSim = data[0]
	sim.enemy.health = 1
	sim.hit(sim.enemy, 1, 50, {"hit_stop": 0.0})
	step(sim, 200)
	check(sim.state == "playing", "en entrenamiento nadie pierde")
	check(sim.enemy.health == 100, "la vida del muñeco se recarga")


func test_every_technique() -> void:
	for f in Catalog.FIGHTERS:
		var id := String(f["id"])
		var data := make_sim(id, "kakashi")
		var sim: CombatSim = data[0]
		freeze_ai(sim)
		sim.enemy.x = sim.player.x + 90.0
		var health_before := sim.enemy.health
		var self_before := sim.player.health
		sim.player.health = 60
		sim.use_technique(sim.player, sim.enemy)
		check(sim.player.special_charge > 0.0, "%s carga su técnica" % id)
		for i in range(40):
			freeze_ai(sim)
			step(sim, 1)
		var changed := sim.enemy.health < health_before or sim.player.guard_time > 0.0 \
			or sim.player.armor_time > 0.0 or sim.player.health > 60 or sim.player.decoy_time > 0.0 \
			or sim.effects.size() > 0 or sim.projectiles.size() > 0
		check(changed, "%s: la técnica produce un efecto" % id)
		check(self_before == 100, "estado inicial correcto")


func test_combo_and_rewards() -> void:
	var data := make_sim("kakashi", "kakashi")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	sim.enemy.x = sim.player.x + 62.0
	var hits := 0
	for i in range(90):
		freeze_ai(sim)
		if i % 14 == 0:
			input.press(0, "attack")
		step(sim, 1)
		hits = maxi(hits, sim.player.max_combo)
	check(hits >= 2, "Brasa encadena golpes en combo (máximo %d)" % hits)


func test_long_simulation() -> void:
	# Combate largo IA contra entrada pseudoaleatoria para cada luchador: no debe colgarse.
	for f in Catalog.FIGHTERS:
		var id := String(f["id"])
		var data := make_sim(id, "kakashi")
		var sim: CombatSim = data[0]
		var input: FakeInput = data[1]
		sim.player.awakening_available = true
		sim.enemy.awakening_available = true
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for frame in range(60 * 60):
			input.down.clear()
			if rng.randf() < 0.5:
				input.down["0_right"] = true
			if frame % 9 == 0:
				input.press(0, ["attack", "kick", "heavy", "special", "jump", "awaken"][rng.randi() % 6])
			if rng.randf() < 0.1:
				input.down["0_block"] = true
			sim.update(1.0 / 60.0)
			if sim.state == "round-finished":
				sim.next_round()
			if sim.state == "finished":
				break
		check(sim.player.health >= 0 and sim.enemy.health >= 0, "%s: simulación larga estable" % id)


# --- Puños, patadas y combos ------------------------------------------------

## Pulsa `action` `times` veces, cada vez en cuanto el golpe anterior se puede cancelar,
## y devuelve las animaciones que salieron.
func _do_chain(sim: CombatSim, input: FakeInput, action: String, times: int) -> Array:
	var used: Array = []
	for n in range(times):
		var guard := 0
		while sim._attack_busy(sim.player) and guard < 120:
			freeze_ai(sim)
			step(sim, 1)
			guard += 1
		input.press(0, action)
		freeze_ai(sim)
		step(sim, 1)
		used.append(sim.player.attack_animation)
	return used


func test_punch_and_kick_chains() -> void:
	var punches := ["jab", "cross", "hook", "uppercut"]
	var kicks := ["kick_low", "kick_mid", "kick_high", "kick_spin"]
	for f in Catalog.FIGHTERS:
		var id := String(f["id"])
		var anims := FighterAnimations.for_fighter(id)
		for anim_name in punches + kicks:
			check(anims.has(anim_name) and FighterAnimations.first_hitbox_frame(anims[anim_name]) > 0,
				"%s tiene el golpe %s con hitbox" % [id, anim_name])
		for kind in ["punch", "kick"]:
			var data := make_sim(id, "kakashi")
			var sim: CombatSim = data[0]
			var input: FakeInput = data[1]
			sim.enemy.x = sim.player.x + 64.0
			var length := ComboData.chain_length(sim.player.definition, kind)
			var used := _do_chain(sim, input, "kick" if kind == "kick" else "attack", length)
			var allowed: Array = kicks if kind == "kick" else punches
			var only_kind := used.all(func(a: String) -> bool: return allowed.has(a))
			check(only_kind, "%s: pulsar %s varias veces solo lanza %s (%s)" % [id, "J" if kind == "kick" else "I", "patadas" if kind == "kick" else "puños", used])
			check(used.back() == ("kick_spin" if kind == "kick" else "uppercut"), "%s: la cadena de %s termina en su remate" % [id, kind])
			check(used.size() == length and used.slice(0, length - 1).all(func(a: String) -> bool: return a != used.back()) or length == 2,
				"%s: los golpes de la cadena de %s cambian (%s)" % [id, kind, used])


func test_mixed_chain() -> void:
	var data := make_sim("kakashi", "kakashi")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	sim.enemy.x = sim.player.x + 64.0
	var used := _do_chain(sim, input, "attack", 2)
	used.append_array(_do_chain(sim, input, "kick", 2))
	check(used == ["jab", "cross", "kick_high", "kick_spin"], "I, I, J, J: dos puños y dos patadas siguiendo el combo (%s)" % [used])


func test_true_combos() -> void:
	for f in Catalog.FIGHTERS:
		var id := String(f["id"])
		for action in ["attack", "kick"]:
			var data := make_sim(id, "kakashi")
			var sim: CombatSim = data[0]
			var input: FakeInput = data[1]
			sim.enemy.x = sim.player.x + 64.0
			var length := ComboData.chain_length(sim.player.definition, "kick" if action == "kick" else "punch")
			_do_chain(sim, input, action, length)
			var best := sim.player.combo_hits
			for i in range(40):
				freeze_ai(sim)
				step(sim, 1)
				best = maxi(best, sim.player.combo_hits)
			check(best == length, "%s: la cadena de %s es un combo real (%d de %d golpes)" % [id, action, best, length])
			check(sim.player.combo_damage > 0, "%s: el combo suma su daño" % id)
	# Un golpe suelto tras recuperarse no continúa el combo.
	var data := make_sim()
	var sim: CombatSim = data[0]
	sim.hit(sim.enemy, 1, 10, {"attacker": 0, "hit_stop": 0.0})
	sim.enemy.hurt_time = 0.0
	sim.player.combo_display = 0.0
	sim.hit(sim.enemy, 1, 10, {"attacker": 0, "hit_stop": 0.0})
	check(sim.player.combo_hits == 1, "si el rival se recupera el combo vuelve a empezar")


func test_proration() -> void:
	check(ComboData.proration(1) == 1.0 and ComboData.proration(3) == 1.0, "los primeros golpes hacen daño completo")
	check(ComboData.proration(6) < ComboData.proration(4), "los combos largos reducen el daño")
	check(ComboData.proration(50) == ComboData.PRORATION_MIN, "la reducción tiene un mínimo")
	var data := make_sim()
	var sim: CombatSim = data[0]
	var hp := sim.enemy.health
	sim.hit(sim.enemy, 1, 20, {"attacker": 0, "hit_stop": 0.0})
	var first := hp - sim.enemy.health
	for i in range(8):
		sim.hit(sim.enemy, 1, 20, {"attacker": 0, "hit_stop": 0.0})
	hp = sim.enemy.health
	sim.hit(sim.enemy, 1, 20, {"attacker": 0, "hit_stop": 0.0})
	check(hp - sim.enemy.health < first, "el décimo golpe del combo hace menos daño que el primero")


func test_ai_combos() -> void:
	var seen := {}
	for seed_value in range(6):
		var data := make_sim("kakashi", "kakashi")
		var sim: CombatSim = data[0]
		sim.rng.seed = 99 + seed_value
		sim.enemy.x = sim.player.x + 70.0
		for i in range(600):
			sim.player.health = CombatSim.MAX_HEALTH
			step(sim, 1)
			if sim.enemy.attack_animation != "" and sim.enemy.attack_pose > 0.0:
				seen[sim.enemy.attack_animation] = true
			if sim.state != "playing":
				break
	var kicked := seen.keys().any(func(a: String) -> bool: return a.begins_with("kick_"))
	var punched := seen.keys().any(func(a: String) -> bool: return ["jab", "cross", "hook", "uppercut"].has(a))
	check(kicked and punched, "la CPU combina cadenas de puños y de patadas (%s)" % [seen.keys()])
	check(seen.has("uppercut") or seen.has("kick_spin") or seen.has("finisher"), "la CPU llega a rematar sus combos")


# --- Ataques aéreos, barrida, antiaéreo, agarre y contraataque ---------------

func test_air_attacks() -> void:
	for f in Catalog.FIGHTERS:
		var id := String(f["id"])
		var anims := FighterAnimations.for_fighter(id)
		for anim_name in ["sweep", "air_punch", "air_kick", "throw"]:
			check(anims.has(anim_name) and FighterAnimations.first_hitbox_frame(anims[anim_name]) > 0, "%s tiene %s" % [id, anim_name])
	var data := make_sim("kakashi", "kakashi")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	freeze_ai(sim)
	sim.enemy.x = sim.player.x + 90.0
	input.press(0, "jump")
	input.down["0_right"] = true
	step(sim, 14)
	input.press(0, "kick")
	step(sim, 1)
	check(sim.player.attack_animation == "air_kick" and not sim.player.grounded, "J en el aire lanza la patada voladora")
	var pose_before := sim.player.attack_pose
	sim.player.attack_cooldown = 0.0
	sim.player.attack_windup = 0.0
	sim.player.has_pending_attack = false
	input.press(0, "attack")
	step(sim, 1)
	check(sim.player.attack_animation == "air_kick", "solo un ataque aéreo por salto")
	input.down.clear()
	var connected := false
	for i in range(60):
		freeze_ai(sim)
		step(sim, 1)
		connected = connected or sim.enemy.hurt_time > 0.0
		if sim.player.grounded:
			break
	check(sim.player.grounded and not sim.player.air_attack_used, "al aterrizar se recupera el ataque aéreo")
	check(pose_before > 0.0, "la patada voladora tiene animación")
	# Salto con patada + combo en el suelo (jump-in).
	data = make_sim("kakashi", "kakashi")
	sim = data[0]
	input = data[1]
	freeze_ai(sim)
	sim.enemy.x = sim.player.x + 75.0
	input.press(0, "jump")
	step(sim, 18)
	input.press(0, "kick")
	var best := 0
	for i in range(80):
		freeze_ai(sim)
		step(sim, 1)
		if sim.player.grounded and not sim._attack_busy(sim.player):
			input.press(0, "attack")
		best = maxi(best, sim.player.combo_hits)
	check(best >= 2, "una patada voladora enlaza con puños al aterrizar (%d golpes)" % best)


func test_sweep_and_antiair() -> void:
	var data := make_sim("kakashi", "kakashi")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	freeze_ai(sim)
	sim.enemy.x = sim.player.x + 66.0
	input.down["0_down"] = true
	input.press(0, "kick")
	step(sim, 1)
	check(sim.player.attack_animation == "sweep", "↓ + J es la barrida")
	var knocked := false
	for i in range(30):
		freeze_ai(sim)
		step(sim, 1)
		knocked = knocked or sim.enemy.knocked_down
	check(knocked, "la barrida derriba al rival")
	data = make_sim("kakashi", "kakashi")
	sim = data[0]
	input = data[1]
	freeze_ai(sim)
	sim.enemy.x = sim.player.x + 64.0
	input.down["0_down"] = true
	input.press(0, "attack")
	step(sim, 1)
	check(sim.player.attack_animation == "uppercut", "↓ + I es el uppercut antiaéreo")


func test_throw() -> void:
	var data := make_sim("kakashi", "kakashi", "versus")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	sim.enemy.x = sim.player.x + 60.0
	input.down["1_block"] = true
	step(sim, 2)
	check(sim.enemy.blocking, "el rival se cubre")
	var before := sim.enemy.health
	input.down["0_right"] = true
	input.press(0, "heavy")
	step(sim, 1)
	check(sim.player.attack_animation == "throw", "→ + L pegado al rival es un agarre")
	for i in range(20):
		step(sim, 1)
	check(sim.enemy.health < before and sim.enemy.knocked_down, "el agarre atraviesa la guardia y derriba")
	data = make_sim("kakashi", "kakashi")
	sim = data[0]
	input = data[1]
	freeze_ai(sim)
	sim.enemy.x = sim.player.x + 160.0
	input.down["0_right"] = true
	input.press(0, "heavy")
	step(sim, 1)
	check(sim.player.attack_animation != "throw", "de lejos →+L es el golpe fuerte normal")


func test_counter_hit() -> void:
	var data := make_sim("kakashi", "kakashi")
	var sim: CombatSim = data[0]
	freeze_ai(sim)
	var hp := sim.enemy.health
	sim.hit(sim.enemy, 1, 20, {"attacker": 0, "hit_stop": 0.0})
	var normal := hp - sim.enemy.health
	sim.enemy.health = CombatSim.MAX_HEALTH
	sim.enemy.hurt_time = 0.0
	sim.enemy.knocked_down = false
	sim.player.combo_hits = 0
	sim.player.combo_display = 0.0
	sim.enemy.has_pending_attack = true
	sim.enemy.attack_windup = 0.1
	hp = sim.enemy.health
	sim.hit(sim.enemy, 1, 20, {"attacker": 0, "hit_stop": 0.0})
	check(hp - sim.enemy.health > normal, "el contraataque hace más daño (%d > %d)" % [hp - sim.enemy.health, normal])
	check(sim._last_hit_counter, "el golpe se marca como contraataque")


func test_knockdown_bounce() -> void:
	var data := make_sim("kakashi", "kakashi")
	var sim: CombatSim = data[0]
	freeze_ai(sim)
	sim.hit(sim.enemy, 1, 5, {"launch_y": -420.0, "hit_stop": 0.0, "attacker": 0})
	sim.hit_stop_frames = 0.0
	var bounced := false
	var landed := false
	for i in range(180):
		freeze_ai(sim)
		step(sim, 1)
		bounced = bounced or sim.enemy.bounced
		if bounced and sim.enemy.grounded:
			landed = true
			break
	check(bounced, "un derribo desde muy alto rebota en el suelo")
	check(landed and not sim.enemy.bounced, "tras el rebote cae y se puede levantar")
	check(sim.effects.any(func(e: Dictionary) -> bool: return e["type"] == "dust-cloud"), "el rebote levanta polvo")


# --- Kakashi (juego de Volt) -----------------------------------------------------------

func test_kakashi_kit() -> void:
	# Salto de umbral: conecta también pegado al rival y nunca lo atraviesa.
	for d in [62.0, 70.0, 100.0, 120.0]:
		var data := make_sim("kakashi", "kakashi")
		var sim: CombatSim = data[0]
		freeze_ai(sim)
		sim.player.x = 150.0
		sim.enemy.x = 150.0 + d
		var hp := sim.enemy.health
		sim.use_technique(sim.player, sim.enemy)
		for i in range(30):
			freeze_ai(sim)
			step(sim, 1)
		check(sim.enemy.health < hp, "Kakashi: Salto de umbral conecta a %d px" % d)
		check(sim.player.x < sim.enemy.x, "Kakashi: Salto de umbral no atraviesa al rival (%d px)" % d)
	# Lejos: recorre su distancia completa y no golpea.
	var far := make_sim("kakashi", "kakashi")
	var fsim: CombatSim = far[0]
	freeze_ai(fsim)
	fsim.player.x = 100.0
	fsim.enemy.x = 330.0
	var far_hp := fsim.enemy.health
	fsim.use_technique(fsim.player, fsim.enemy)
	for i in range(30):
		freeze_ai(fsim)
		step(fsim, 1)
	check(fsim.enemy.health == far_hp and fsim.player.x > 180.0, "Kakashi: de lejos el Salto de umbral solo acerca")
	# Atrás + técnica: esquiva hacia atrás y el primer golpe lo atraviesa.
	var back := make_sim("kakashi", "kakashi", "versus")
	var bsim: CombatSim = back[0]
	var input: FakeInput = back[1]
	bsim.player.x = 220.0
	bsim.enemy.x = 282.0
	input.down["0_left"] = true
	input.press(0, "special")
	step(bsim, 1)
	input.down.clear()
	step(bsim, 12)
	check(bsim.player.x < 160.0, "Kakashi: atrás + K esquiva hacia atrás (x = %d)" % bsim.player.x)
	check(bsim.player.phase_time > 0.0, "Kakashi: la esquiva da un instante intocable")
	var hp_before := bsim.player.health
	var connected := bsim.hit(bsim.player, -1, 20, {"attacker": 1, "hit_stop": 0.0})
	check(not connected and bsim.player.health == hp_before, "Kakashi: el golpe durante la esquiva no hace daño")
	# Arco de ruptura (despertar) también a quemarropa.
	var arc := make_sim("kakashi", "kakashi")
	var asim: CombatSim = arc[0]
	freeze_ai(asim)
	asim.player.x = 150.0
	asim.enemy.x = 212.0
	asim.player.awakening_time = 5.0
	var arc_hp := asim.enemy.health
	asim.use_technique(asim.player, asim.enemy)
	for i in range(10):
		freeze_ai(asim)
		step(asim, 1)
	check(asim.enemy.health < arc_hp, "Kakashi: Arco de ruptura conecta pegado al rival")
	# Sus golpes sin imagen propia se giran para leerse bien; los demás no.
	check(not FighterPainter._move_tweak("kick_low", "finisher_impact").is_empty(), "Kakashi: la patada baja se dibuja inclinada")
	check(not FighterPainter._move_tweak("uppercut", "heavy").is_empty(), "Kakashi: el uppercut se dibuja hacia arriba")
	check(FighterPainter._move_tweak("kick_low", "kick_low").is_empty(), "los luchadores con imagen propia no se giran")


func test_madara_ultimate() -> void:
	var data := make_sim("madara_edo", "kakashi", "versus")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	var requests: Array = []
	sim.ultimate_requested.connect(func(index: int) -> void: requests.append(index))
	check(sim.player.definition.get("ultimate") == "juicio-dios-guerra", "Madara Edo: identificador del definitivo")
	check(sim.player.definition.get("ultimate_name") == "El juicio del Dios de la Guerra", "Madara Edo: nombre del definitivo")
	for definition in Catalog.FIGHTERS:
		check(definition.has("ultimate") == (definition["id"] == "madara_edo"), "solo Madara Edo tiene definitivo: %s" % definition["id"])
	check(not sim.ultimate_hit("susanoo"), "sin definitivo activo no hay golpe")
	sim.player.awakening_available = true
	sim.player.meter = 100.0
	input.press(0, "awaken")
	step(sim, 1)
	check(sim.player.awakening_time > 0.0 and not sim.ultimate_active and requests.is_empty(), "H sin despertar activo activa el despertar normal")
	check(sim.player.meter == 0.0, "el despertar normal consume la energía")
	# Cada impedimento conserva las condiciones previas del combate.
	for property in ["health", "grounded", "hurt_time", "knocked_down", "getup_time", "special_charge", "awakening_time"]:
		var before: Variant = sim.player.get(property)
		var blocked: Variant = false if property == "grounded" else (true if property == "knocked_down" else (0 if property in ["health", "awakening_time"] else 1.0))
		sim.player.set(property, blocked)
		check(not sim.can_ultimate(sim.player) and not sim.request_ultimate(sim.player), "el definitivo respeta %s" % property)
		sim.player.set(property, before)
	sim.enemy.health = 0
	check(not sim.can_ultimate(sim.player), "no hay definitivo contra un rival sin vida")
	sim.enemy.health = CombatSim.MAX_HEALTH
	sim.state = "ready"
	check(not sim.can_ultimate(sim.player), "solo se pide el definitivo durante la pelea")
	sim.state = "playing"
	sim.enemy.definition = sim.enemy.definition.duplicate(true)
	sim.enemy.definition["defense"] = 1.0
	# La petición cancela movimientos, ataques, técnicas y proyectiles de ambos.
	for fighter in [sim.player, sim.enemy]:
		fighter.walking = true
		fighter.running = true
		fighter.attack_pose = 0.3
		fighter.attack_windup = 0.2
		fighter.has_pending_attack = true
		fighter.buffered_input = "heavy"
		fighter.buffer_time = 0.1
		fighter.knockback_velocity = 100.0
		fighter.pending_special = "solar-beam"
		fighter.ai_plan = ["attack"]
	sim.enemy.special_charge = 1.0
	sim.enemy.blocking = true
	sim.enemy.guard_time = 1.0
	sim.projectiles.append({"pending": true})
	sim.consume_audio_events()
	input.press(0, "awaken")
	step(sim, 1)
	check(sim.ultimate_active and sim.ultimate_owner == 0 and requests == [0], "H con despertar de Madara pide el definitivo y emite una señal")
	check(sim.player.awakening_time == 0.0, "el definitivo consume el despertar")
	check(sim.last_action == "EL JUICIO DEL DIOS DE LA GUERRA" and sim.consume_audio_events() == ["awaken"], "el definitivo anuncia su nombre y audio")
	for fighter in [sim.player, sim.enemy]:
		check(not fighter.walking and not fighter.running and fighter.knockback_velocity == 0.0 and fighter.velocity_y == 0.0, "el definitivo detiene al luchador %d" % fighter.index)
		check(fighter.attack_pose == 0.0 and fighter.attack_windup == 0.0 and not fighter.has_pending_attack and fighter.buffered_input == "" and fighter.special_charge == 0.0 and fighter.pending_special == "" and fighter.ai_plan.is_empty(), "el definitivo cancela pendientes del luchador %d" % fighter.index)
	check(sim.projectiles.is_empty() and sim.hit_stop_frames == 0.0, "el definitivo limpia proyectiles y hit stop")
	check(not sim.request_ultimate(sim.player) and requests == [0], "no se puede pedir dos veces el definitivo")
	sim.enemy.awakening_time = 5.0
	check(not sim.request_ultimate(sim.enemy), "el rival tampoco puede pedir otro definitivo durante la cinemática")
	var positions := [sim.player.x, sim.player.y, sim.enemy.x, sim.enemy.y]
	var remaining := sim.round_time
	input.down["0_right"] = true
	input.down["1_left"] = true
	input.press(0, "attack")
	sim.burst(sim.player.x, CombatSim.FLOOR, "#ffffff", 1)
	var particle_life := float(sim.particles.back()["life"])
	sim.update(0.1)
	check(positions == [sim.player.x, sim.player.y, sim.enemy.x, sim.enemy.y] and sim.round_time == remaining, "durante el definitivo update no mueve ni descuenta tiempo")
	check(sim.enemy.awakening_time == 5.0 and not sim.player.has_pending_attack and input.pressed.is_empty(), "durante el definitivo se congelan temporizadores y se descartan pulsaciones")
	check(sim.particles.is_empty() or float(sim.particles.back()["life"]) < particle_life, "las partículas siguen actualizándose durante el definitivo")
	input.down.clear()
	check(not sim.ultimate_hit("desconocido"), "un identificador de golpe desconocido no hace daño")
	var own_health := sim.player.health
	for hit_id in ["susanoo", "meteoro1", "meteoro2"]:
		check(sim.ultimate_hit(hit_id), "el golpe %s conecta" % hit_id)
		check(sim.enemy.knocked_down and not sim.enemy.grounded, "%s mantiene al rival derribado" % hit_id)
		var hp := sim.enemy.health
		check(not sim.ultimate_hit(hit_id) and sim.enemy.health == hp, "no se duplica el golpe %s" % hit_id)
		check(sim.player.health == own_health and sim.player.hit_flash == 0.0 and sim.player.hurt_time == 0.0, "%s no daña ni golpea a Madara" % hit_id)
	var total := CombatSim.MAX_HEALTH - sim.enemy.health
	check(total >= 45 and total <= 50 and total == 48, "el definitivo hace 48 de daño total contra defensa 1 (obtenido %d)" % total)
	check(sim.player.combo_hits == 3 and sim.player.combo_damage == total, "los tres golpes pasan por hit y su contador de combo")
	sim.player.attack_cooldown = 1.0
	sim.end_ultimate()
	check(not sim.ultimate_active and sim.ultimate_owner == -1 and sim._ultimate_done.is_empty() and sim.screen_shake == 0.0 and sim.hit_stop_frames == 0.0 and sim.player.attack_cooldown == 0.0, "end_ultimate limpia el estado y recuperación del dueño")
	step(sim, 120)
	check(sim.enemy.grounded and not sim.enemy.knocked_down and sim.enemy.getup_time == 0.0, "el rival vivo se levanta normalmente al reanudar")
	# Otro personaje conserva H y el despertar sin acceder a la API de Madara.
	var other := make_sim("kakashi", "kakashi", "versus")
	var other_sim: CombatSim = other[0]
	var other_input: FakeInput = other[1]
	other_sim.player.awakening_time = 5.0
	other_sim.player.meter = 100.0
	other_input.press(0, "awaken")
	step(other_sim, 1)
	check(not other_sim.ultimate_active and other_sim.player.awakening_time > 4.9 and other_sim.player.meter == 100.0, "H con despertar en otro luchador mantiene el comportamiento anterior")
	# hit() sigue respetando invulnerabilidad, esquivas y señuelos; no se reintenta.
	for immunity in ["getup_time", "phase_time", "decoy_time"]:
		var protected_data := make_sim("madara_edo", "kakashi", "versus")
		var protected_sim: CombatSim = protected_data[0]
		protected_sim.player.awakening_time = 5.0
		protected_sim.enemy.set(immunity, 1.0)
		check(protected_sim.request_ultimate(protected_sim.player), "el definitivo puede iniciarse contra %s" % immunity)
		check(not protected_sim.ultimate_hit("susanoo") and protected_sim.enemy.health == CombatSim.MAX_HEALTH, "el definitivo respeta %s" % immunity)
		protected_sim.enemy.set(immunity, 0.0)
		check(not protected_sim.ultimate_hit("susanoo"), "un golpe rechazado por %s no se repite" % immunity)
	# El K.O. se resuelve después de la cinemática, al volver a update().
	sim.reset_round()
	sim.player.awakening_time = 5.0
	sim.enemy.health = 1
	check(sim.request_ultimate(sim.player) and sim.ultimate_hit("susanoo"), "el definitivo alcanza a un rival con poca vida")
	check(sim.enemy.health == 0 and sim.state == "playing", "el golpe lleva la vida a cero sin terminar la ronda")
	check(not sim.ultimate_hit("meteoro1") and not sim._ultimate_done.has("meteoro1"), "no hace nada al golpear a un rival sin vida")
	sim.update(1.0)
	check(sim.state == "playing", "el K.O. espera mientras el definitivo está activo")
	sim.end_ultimate()
	step(sim, 1)
	check(sim.state == "round-finished" and sim.round_result == "player" and sim.player.health == CombatSim.MAX_HEALTH, "tras end_ultimate y update se resuelve el K.O. sin dañar a Madara")
	# La CPU puede pedirlo en su bloque de decisión, con semillas reproducibles.
	var cpu_requested := false
	for seed_value in range(32):
		var cpu_data := make_sim("kakashi", "madara_edo")
		var cpu: CombatSim = cpu_data[0]
		cpu.rng.seed = seed_value
		cpu.enemy.awakening_time = 5.0
		cpu.enemy.ai_decision = 0.0
		cpu._move_enemy(0.0)
		if cpu.ultimate_active:
			cpu_requested = cpu.ultimate_owner == 1 and cpu.enemy.awakening_time == 0.0
			var hp := cpu.player.health
			check(cpu.ultimate_hit("susanoo") and cpu.player.health < hp and cpu.enemy.health == CombatSim.MAX_HEALTH, "la API de golpes admite al dueño CPU")
			break
	check(cpu_requested, "la IA puede pedir el definitivo a menos de 260 píxeles")
	# Reiniciar durante un definitivo elimina también los golpes ya consumidos.
	sim.start()
	sim.player.awakening_time = 5.0
	sim.request_ultimate(sim.player)
	sim.ultimate_hit("susanoo")
	sim.reset_round()
	check(not sim.ultimate_active and sim.ultimate_owner == -1 and sim._ultimate_done.is_empty() and sim.screen_shake == 0.0 and sim.hit_stop_frames == 0.0, "reset_round limpia todo el definitivo")
	sim.player.awakening_time = 5.0
	check(sim.request_ultimate(sim.player) and sim.ultimate_hit("susanoo"), "tras reset_round vuelve a permitirse el mismo golpe")


func test_sprite_sheet() -> void:
	# Hoja sintética: fondo magenta y tres bloques de distinto alto en una fila,
	# más una mota de 2x2 que no debe contar como cuadro.
	var sheet := Image.create_empty(120, 60, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(1, 0, 1))
	sheet.fill_rect(Rect2i(5, 10, 20, 40), Color.RED)
	sheet.fill_rect(Rect2i(40, 20, 24, 30), Color.GREEN)
	sheet.fill_rect(Rect2i(66, 20, 4, 4), Color.GREEN)  # pieza suelta junto al segundo
	sheet.fill_rect(Rect2i(85, 5, 18, 45), Color.BLUE)
	sheet.fill_rect(Rect2i(110, 55, 2, 2), Color.WHITE)
	SpriteSheet.remove_background(sheet, SpriteSheet.guess_background(sheet))
	check(sheet.get_pixel(0, 0).a == 0.0, "hoja: el fondo queda transparente")
	var rects := SpriteSheet.detect_frames(sheet, 8, 2)
	check(rects.size() == 3, "hoja: detecta tres cuadros (y descarta la mota)")
	if rects.size() == 3:
		check(rects[0] == Rect2i(5, 10, 20, 40), "hoja: primer cuadro exacto")
		check(rects[1] == Rect2i(40, 20, 30, 30), "hoja: junta la pieza suelta con su cuadro")
		check(rects[2].position.x == 85, "hoja: orden de izquierda a derecha")
		var packed := SpriteSheet.pack_uniform(sheet, rects, 8)
		var cell: Vector2i = packed["cell"]
		var out: Image = packed["image"]
		check(out.get_size() == Vector2i(cell.x * 3, cell.y), "hoja: celdas iguales en una fila")
		# Los pies de cada cuadro quedan en el centro del borde inferior de su celda.
		for i in 3:
			var foot := SpriteSheet.feet_point(out, SpriteSheet.grid_rect(cell, 3, i))
			check(absf(foot.x - cell.x / 2.0) <= 1.0 and absf(foot.y - cell.y) <= 0.01,
				"hoja: pies centrados en la celda %d" % i)
	var ref := SpriteSheet.cell_ref("res://x.png", Vector2i(32, 48), 4, 5)
	check(ref == "res://x.png#32,48,32,48", "hoja: referencia de la celda 5")
	var parsed := SpriteSheet.parse_ref(ref)
	check(parsed[0] == "res://x.png" and parsed[1] == Rect2i(32, 48, 32, 48), "hoja: se lee la referencia")
	check(SpriteSheet.frame_texture("res://no_existe.png#0,0,8,8") == null, "hoja: hoja inexistente no rompe")
	# Hoja con celdas: fondo gris, celdas fucsia separadas por líneas de 1 px y un
	# bloque que cruza su celda de lado a lado (parte el fucsia en dos).
	var gray := Color8(207, 213, 221)
	var cells_sheet := Image.create_empty(200, 100, false, Image.FORMAT_RGBA8)
	cells_sheet.fill(gray)
	cells_sheet.fill_rect(Rect2i(0, 0, 60, 50), Color.MAGENTA)
	cells_sheet.fill_rect(Rect2i(61, 0, 60, 50), Color.MAGENTA)
	cells_sheet.fill_rect(Rect2i(140, 0, 60, 50), Color.MAGENTA)
	cells_sheet.fill_rect(Rect2i(20, 10, 15, 35), Color.BLUE)
	cells_sheet.fill_rect(Rect2i(80, 15, 20, 30), Color.RED)
	cells_sheet.fill_rect(Rect2i(140, 30, 60, 8), Color.GREEN)
	var colors := SpriteSheet.guess_cell_colors(cells_sheet)
	check(colors[0].is_equal_approx(Color.MAGENTA) and colors[1].is_equal_approx(gray), "celdas: adivina relleno y separador")
	var cells := SpriteSheet.detect_cells(cells_sheet, colors[1])
	check(cells.size() == 3, "celdas: encuentra las tres celdas sin unirlas")
	SpriteSheet.remove_colors(cells_sheet, colors)
	var framed := SpriteSheet.trim_all(cells_sheet, cells)
	var expected: Array[Rect2i] = [Rect2i(20, 10, 15, 35), Rect2i(80, 15, 20, 30), Rect2i(140, 30, 60, 8)]
	check(framed == expected, "celdas: cada cuadro se recorta a lo dibujado")


func test_fighter_importer() -> void:
	var imp: GDScript = load("res://scripts/tools/fighter_importer.gd")
	# Poses: nombres del juego, fases de golpe y alias.
	check(imp.is_valid_pose("finisher_impact") and imp.is_valid_pose("jab_anticipate")
		and imp.is_valid_pose("kick_low_impact"), "importador: reconoce poses y fases")
	check(not imp.is_valid_pose("kick") and not imp.is_valid_pose("jab_nada"), "importador: rechaza poses inventadas")
	var norm: Dictionary = imp.normalize_map({"idle": [0, 1], "kick": 2, "salto": [1], "nada": 1, "walk": [9], "_height": 60}, 4)
	check(norm["poses"].get("finisher") == [2] and norm["single"].get("finisher") == true, "importador: kick pasa a finisher")
	check(norm["poses"].has("jump"), "importador: salto pasa a jump")
	check((norm["errors"] as PackedStringArray).size() == 2, "importador: avisa de pose inventada y cuadro que no existe")
	check(norm["settings"].get("height") == 60, "importador: lee los ajustes que empiezan por _")
	check(not (imp.normalize_map({"walk": [0]}, 2)["errors"] as PackedStringArray).is_empty(), "importador: idle es obligatoria")
	# Repetidos y reflejos.
	var sheet := Image.create_empty(40, 10, false, Image.FORMAT_RGBA8)
	sheet.fill_rect(Rect2i(0, 0, 3, 10), Color.RED)
	sheet.fill_rect(Rect2i(3, 0, 2, 4), Color.BLUE)
	sheet.fill_rect(Rect2i(10, 0, 3, 10), Color.RED)
	sheet.fill_rect(Rect2i(13, 0, 2, 4), Color.BLUE)
	sheet.fill_rect(Rect2i(22, 0, 3, 10), Color.RED)
	sheet.fill_rect(Rect2i(20, 0, 2, 4), Color.BLUE)
	var rects: Array[Rect2i] = [Rect2i(0, 0, 5, 10), Rect2i(10, 0, 5, 10), Rect2i(20, 0, 5, 10)]
	var dups: Dictionary = imp.find_duplicates(sheet, rects)
	check(dups.get(1, {}).get("mirror") == false and dups[1]["of"] == 0, "importador: detecta copias")
	check(dups.get(2, {}).get("mirror") == true, "importador: detecta reflejos")
	check(imp.rows(rects) == [[0, 1, 2]], "importador: agrupa por filas")
	# Escritura en el catálogo: sustituir sprites y crear un luchador nuevo.
	var text := 'const FIGHTERS := [\n\t{\n\t\t"id": "uno", "name": "Uno", "speed": 1.0,\n\t\t"sprites": {\n\t\t\t"idle": "a.png", # viejo\n\t\t},\n\t\t"sprite_height": 50.0,  ## altura\n\t\t"sprite_scale": 2.0\n\t},\n]\n'
	var block := '\t\t"sprites": {\n\t\t\t"idle": "b.png",\n\t\t},\n\t\t"sprite_height": 60.0,'
	var replaced: Dictionary = imp.catalog_with_sprites(text, "uno", block)
	var out := String(replaced["text"])
	check(not replaced["created"] and out.contains('"idle": "b.png"') and not out.contains("a.png")
		and not out.contains("50.0") and out.contains('"sprite_scale": 2.0,'), "importador: sustituye los sprites y conserva el resto")
	var created: Dictionary = imp.catalog_with_sprites(out, "dos", block, "Dos", "uno")
	var out2 := String(created["text"])
	check(created["created"] and out2.contains('"id": "dos", "name": "Dos"') and out2.count('"id": "uno"') == 1,
		"importador: crea el luchador nuevo copiando la base")
	var script := GDScript.new()
	script.source_code = out2
	check(script.reload() == OK, "importador: el catálogo resultante compila")
	var styles := 'const ANIMATION_STYLES := {\n\t"uno": {"attack": "drive"},\n}\n'
	check(imp.animations_with_style(styles, "dos", "uno").contains('\t"dos": {"attack": "drive", "like": "uno"},'), "importador: copia el estilo de animación")
	check(imp.is_valid_id("kakashi_2") and not imp.is_valid_id("Kaka shi") and not imp.is_valid_id("2pac"), "importador: valida el id")
	check(imp.whole_numbers({"a": [1.0, 2.5]}) == {"a": [1, 2.5]}, "importador: guarda los números enteros sin decimales")
	# Retratos: todos los luchadores (con "idle" de una imagen o en lista) se pueden encuadrar.
	for f: Dictionary in Catalog.FIGHTERS:
		var offset: Vector2 = FighterPainter.portrait_head_offset(f)
		check(offset.is_finite(), "importador: el retrato de %s se encuadra" % f["id"])
	# Detector v2 (BitMap): junta por cercanía de píxeles, ignora huecos interiores.
	var fast_sheet := Image.create_empty(120, 60, false, Image.FORMAT_RGBA8)
	fast_sheet.fill_rect(Rect2i(5, 5, 30, 40), Color.RED)
	fast_sheet.fill_rect(Rect2i(15, 15, 8, 8), Color(0, 0, 0, 0))  # hueco dentro del primero
	fast_sheet.fill_rect(Rect2i(36, 10, 4, 4), Color.RED)  # pieza a 1 px del primero
	fast_sheet.fill_rect(Rect2i(70, 8, 30, 45), Color.BLUE)
	var joined: Array[Rect2i] = imp.detect_fast(fast_sheet, 8, 1)
	check(joined.size() == 2 and joined[0] == Rect2i(5, 5, 35, 40), "detector v2: junta la pieza cercana y no cuenta el hueco")
	var apart: Array[Rect2i] = imp.detect_fast(fast_sheet, 2, 0)
	check(apart.size() == 3, "detector v2: sin juntar, la pieza cercana va aparte")
	# Neblina: muchos píxeles casi transparentes.
	var hazy := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	hazy.fill(Color(1, 1, 1, 0.02))
	hazy.fill_rect(Rect2i(10, 10, 20, 20), Color.RED)
	check(imp._has_haze(hazy) and not imp._has_haze(fast_sheet), "importador: detecta la neblina transparente")
	# Hoja analizada reducida: los cuadros se recortan de la original a tamaño completo.
	var reduced: Dictionary = imp.analyze(fast_sheet, {"mode": "plain", "bg": "none", "detector": "v2", "scale": 0.5, "min": 4})
	var full_rects: Array[Rect2i] = reduced["rects"]
	var full_frames: Dictionary = imp.frame_images(reduced, [0, 1] as Array[int])
	check(full_rects.size() == 2 and (full_frames[1] as Image).get_size() == Vector2i(30, 45),
		"detector v2: el cuadro sale a tamaño completo aunque se analice al 50 %%")
	# Corrección a mano: mueve el cuadro dentro de su celda sin salirse.
	var shift_sheet := Image.create_empty(40, 20, false, Image.FORMAT_RGBA8)
	shift_sheet.fill_rect(Rect2i(2, 2, 6, 16), Color.RED)
	var plain_pack := SpriteSheet.pack_uniform(shift_sheet, [Rect2i(2, 2, 6, 16)] as Array[Rect2i], 1, 2)
	var moved_pack := SpriteSheet.pack_uniform(shift_sheet, [Rect2i(2, 2, 6, 16)] as Array[Rect2i], 1, 2, false, {0: Vector2i(1, -2)})
	var r0 := (plain_pack["image"] as Image).get_used_rect()
	var r1 := (moved_pack["image"] as Image).get_used_rect()
	check(r1.position == r0.position + Vector2i(1, -2), "hoja: la corrección _offset mueve el cuadro")
	# Clasificación: personaje (piel + ropa), efecto (otro color), texto (pocos colores, bajo).
	var cls := Image.create_empty(400, 120, false, Image.FORMAT_RGBA8)
	for k in 4:
		var x := 10 + k * 50
		cls.fill_rect(Rect2i(x, 20, 24, 30), Color8(230, 180, 140))
		cls.fill_rect(Rect2i(x, 50, 24, 40), Color8(40, 40, 90))
	cls.fill_rect(Rect2i(260, 30, 30, 50), Color8(60, 200, 255))  # efecto azul
	cls.fill_rect(Rect2i(320, 100, 40, 12), Color.WHITE)  # letrero
	var cls_rects: Array[Rect2i] = imp.detect_fast(cls, 4, 1)
	var cls_info: Dictionary = imp.classify(cls, cls_rects)
	var cls_kinds: Array = cls_info["kinds"]
	check(cls_kinds.count("personaje") == 4, "clasificación: reconoce los cuatro cuadros del personaje")
	check(cls_kinds.has("efecto") and cls_kinds.has("texto"), "clasificación: separa efectos y letreros")
	check((cls_info["groups"] as Array).size() == 1 and (cls_info["groups"][0] as Array).size() == 4,
		"clasificación: los cuadros seguidos forman una animación")
	var cls_draft: Dictionary = imp.draft_map_groups(cls_rects, cls_info, {})
	check(cls_draft.get("idle", []).size() == 4, "borrador: propone la animación de pie como idle")
	var effect_index: int = cls_kinds.find("efecto")
	var bad_map: Dictionary = imp.normalize_map({"idle": [0, 1], "jab": effect_index}, cls_rects.size())
	check(not imp.review_map(bad_map, cls_rects, cls_info).is_empty(), "revisión: avisa si una pose usa un efecto")
	# Fondo de damero (imita la transparencia): se detectan sus dos colores.
	var checker := Image.create_empty(96, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 96:
			checker.set_pixel(x, y, Color(0.8, 0.8, 0.8) if ((x / 8) + (y / 8)) % 2 == 0 else Color.WHITE)
	checker.fill_rect(Rect2i(30, 10, 20, 40), Color8(200, 60, 40))
	var bg_guess: Dictionary = imp.guess_backgrounds(checker)
	check(bg_guess["kind"] == "damero" and (bg_guess["colors"] as Array).size() == 2, "fondo: reconoce el damero de dos colores")
	var checker_analysis: Dictionary = imp.analyze(checker, {"mode": "plain", "detector": "v2", "min": 4})
	var checker_rects: Array = checker_analysis["rects"]
	check(checker_rects.size() == 1 and checker_rects[0] == Rect2i(30, 10, 20, 40), "fondo: quita el damero y deja el sprite exacto")
	# Halo: el borde del color del fondo se borra; el interior no.
	var halo := Image.create_empty(20, 20, false, Image.FORMAT_RGBA8)
	halo.fill_rect(Rect2i(4, 4, 12, 12), Color(0.97, 0.97, 0.97))
	halo.fill_rect(Rect2i(5, 5, 10, 10), Color8(200, 60, 40))
	imp.defringe(halo, [Color.WHITE], 0.04)
	check(halo.get_pixel(4, 4).a == 0.0 and halo.get_pixel(8, 8).a > 0.5, "halo: borra el borde claro y deja el dibujo")
	# Variante de color: misma silueta, otra paleta.
	var pal := Image.create_empty(100, 50, false, Image.FORMAT_RGBA8)
	pal.fill_rect(Rect2i(5, 5, 20, 40), Color8(200, 60, 40))
	pal.fill_rect(Rect2i(60, 5, 20, 40), Color8(40, 90, 200))
	var pal_rects: Array[Rect2i] = [Rect2i(5, 5, 20, 40), Rect2i(60, 5, 20, 40)]
	var pal_dups: Dictionary = imp.find_duplicates(pal, pal_rects)
	check(pal_dups.get(1, {}).get("recolor", false), "repetidos: reconoce una variante de color")
	# Borrador: propone andar y tumbado además del reposo.
	var proposal := {"idle": [0], "grupo_2": [1, 2, 3, 4, 5], "grupo_3": [6]}
	var proposal_hints := {"grupo_2": "desplazamiento: walk / run", "grupo_3": "tumbado: down / fall"}
	imp._propose_poses(proposal, proposal_hints)
	check(proposal.has("walk") and proposal.has("down") and not proposal.has("grupo_2"), "borrador: propone walk y down")


func test_auto_anim_v31() -> void:
	var auto := preload("res://scripts/data/auto_anim_2d.gd")
	for curva in auto.CURVAS:
		check(is_zero_approx(auto.aplicar_curva(curva, 0.0)), "curva %s empieza en 0" % curva)
		check(is_equal_approx(auto.aplicar_curva(curva, 1.0), 1.0), "curva %s termina en 1" % curva)
	for nombre in auto.PRESETS:
		var acciones: Dictionary = auto.preset(nombre)
		check(acciones.size() == auto.ACCIONES.size(), "preset %s incluye todas las acciones" % nombre)
		for accion in auto.ACCIONES:
			check(acciones.has(accion) and not auto.generar_desde(acciones[accion]).is_empty(),
				"preset %s genera %s" % [nombre, accion])
	var datos := {"estilo": "golpe_seco", "duracion": 0.4, "intensidad": 1.2,
		"variacion": 0.8, "capa": {"estilo": "sacudida", "intensidad": 0.6}}
	var clip: Dictionary = auto.generar_desde(datos, 1.5, 42)
	check(clip == auto.generar_desde(datos, 1.5, 42), "capa y variacion son reproducibles con la misma semilla")
	check(clip != auto.generar_desde(datos, 1.5, 43), "otra semilla cambia la variacion")
	var sin_capa := clip.duplicate(true)
	sin_capa.erase("capa")
	var t := 0.12
	var muestra: Dictionary = auto.muestrear(clip, t)
	var base: Dictionary = auto.muestrear(sin_capa, t)
	var capa: Dictionary = auto.muestrear(clip["capa"], t)
	check(muestra["desp"] == base["desp"] + capa["desp"]
		and is_equal_approx(muestra["rot"], base["rot"] + capa["rot"])
		and muestra["escala"] == base["escala"] * capa["escala"]
		and muestra["color"] == base["color"] * capa["color"], "muestrear compone la capa")
	var id := "prueba_autoanim_v31"
	# Configuracion en memoria: no modifica luchadores ni crea archivos.
	auto._configs[id] = {"patada": datos, "golpe": {"estilo": "golpe_pesado"},
		"golpe_recibido": {"estilo": "retroceso"}}
	check(auto.para_accion(id, "barrida", {"semilla": 42}) == auto.para_accion(id, "patada", {"semilla": 42}),
		"RESPALDO de barrida usa la patada guardada")
	check(auto.para_accion(id, "barrida", {"sin_respaldo": true}).is_empty(), "sin_respaldo exige animacion propia")
	var f := FighterState.new("kakashi", 200.0, 1)
	for accion in auto.RESPALDO:
		var a := AnimadorProcedural.new()
		var b := AnimadorProcedural.new()
		root.add_child(a)
		root.add_child(b)
		a.auto_anim_id = id
		b.auto_anim_id = id
		var evento := {"tipo": accion, "fuerza": 1.7}
		a.ejecutar(evento, f)
		b.ejecutar(evento, f)
		check(a._clip == auto.para_accion(id, accion, {"fuerza": 1.7, "semilla": 0}),
			"animador %s usa RESPALDO y fuerza" % accion)
		check(a._clip == b._clip, "animadores reproducen %s con semilla determinista" % accion)
		a.free()
		b.free()
		auto._configs[id][accion] = {"estilo": auto.RECOMENDADOS[accion]}
		a = AnimadorProcedural.new()
		root.add_child(a)
		a.auto_anim_id = id
		a.ejecutar(evento, f)
		check(a._clip.get("estilo") == auto.RECOMENDADOS[accion], "animador prefiere accion propia %s" % accion)
		a.free()
		auto._configs[id].erase(accion)
	for caso in [["barrida", "patada"], ["antiaereo", "golpe"], ["aereo", "patada"],
			["aereo", "golpe"], ["agarre", "golpe"]]:
		for explicita in [true, false]:
			if not explicita and caso == ["aereo", "golpe"]:
				continue
			var a := AnimadorProcedural.new()
			var b := AnimadorProcedural.new()
			root.add_child(a)
			root.add_child(b)
			var evento := {"tipo": caso[0]}
			if explicita:
				evento["base"] = caso[1]
			a.ejecutar(evento, f)
			b.ejecutar({"tipo": caso[1]}, f)
			var iguales := a._tween != null and b._tween != null
			for n in 30:
				a._tween.custom_step(0.01)
				b._tween.custom_step(0.01)
				iguales = iguales and a.desp_accion == b.desp_accion and a.escala_accion == b.escala_accion and a.rot_accion == b.rot_accion
			check(iguales, "sin AutoAnim %s conserva exactamente %s (base explicita: %s)" % [caso[0], caso[1], explicita])
			a.free()
			b.free()
	var a := AnimadorProcedural.new()
	root.add_child(a)
	a.recibir_golpe()
	var previo := a._tween
	a.ejecutar({"tipo": "derribo"}, f)
	check(a._tween == previo and a._clip.is_empty(), "derribo sin AutoAnim conserva el movimiento previo")
	a.free()
	auto._configs.erase(id)
	var data := make_sim()
	var sim: CombatSim = data[0]
	for caso in [["sweep", "barrida", "patada"], ["uppercut", "antiaereo", "golpe"],
			["air_punch", "aereo", "golpe"], ["air_kick", "aereo", "patada"], ["throw", "agarre", "golpe"]]:
		sim.consume_anim_events()
		sim._command_strike(sim.player, caso[0])
		var eventos := sim.consume_anim_events()
		check(eventos.size() == 1 and eventos[0]["tipo"] == caso[1] and eventos[0]["base"] == caso[2],
			"CombatSim emite %s con base %s" % [caso[1], caso[2]])
	for aire in [false, true]:
		sim.enemy.knocked_down = false
		sim.enemy.grounded = not aire
		sim.consume_anim_events()
		sim.hit(sim.enemy, 1, 1, {"launch_y": 0.0 if aire else -200.0, "hit_stop": 0.0})
		check(_anim_types(sim, 1).has("derribo"), "CombatSim emite derribo (golpe en aire: %s)" % aire)


## Hallazgos de la revisión de Codex (capas que no volvían a reposo y vista previa).
func test_auto_anim_revision_codex() -> void:
	var auto := preload("res://scripts/data/auto_anim_2d.gd")
	for capa in ["brinco", "rebote", "vibrar", "remolino"]:
		var clip: Dictionary = auto.generar_desde({"estilo": "golpe_seco", "capa": {"estilo": capa, "intensidad": 1.0}})
		check(is_equal_approx(float(clip["capa"]["duracion"]), float(clip["duracion"])), "la capa %s dura lo mismo que la acción" % capa)
		var fin: Dictionary = auto.muestrear(clip, float(clip["duracion"]))
		check((fin["desp"] as Vector2).length() < 0.01 and (fin["escala"] as Vector2).is_equal_approx(Vector2.ONE)
			and is_zero_approx(float(fin["rot"])), "con capa %s la acción acaba en reposo" % capa)
	var V := load("res://addons/auto_anim/vista_previa.gd")
	var v: Control = V.new()
	root.add_child(v)
	v.poner_animacion(auto.generar("golpe_seco"))
	v.ir_a(0.75)
	var avisos: Array = []
	v.tiempo_cambiado.connect(func(p: float) -> void: avisos.append(p))
	v.poner_animacion(auto.generar("golpe_pesado"))
	check(is_equal_approx(v.progreso(), 0.75) and not v.reproduciendo, "vista previa en pausa conserva el punto de la línea de tiempo")
	check(avisos.size() == 1 and is_equal_approx(float(avisos[0]), 0.75), "vista previa avisa al deslizador al cambiar la animación")
	v.free()


func test_auto_anim_receta_ia() -> void:
	var ia := preload("res://addons/auto_anim/ia/receta.gd")
	check(ia.limpiar("```json\n{\"pistas\": []}\n```") == '{"pistas": []}', "receta IA quita vallas json")
	check(ia.limpiar("  antes ```\n{}\n``` despues  ") == "{}", "receta IA quita vallas y texto alrededor")
	check(ia.limpiar("sin JSON") == "" and ia.limpiar("} antes {") == "", "receta IA sin llaves completas devuelve vacio")
	var respuesta := ia.parsear('Antes\n```json\n{"duration": 2, "loop": true, "tracks": [
		{"property": "rotation_degrees", "keys": [{"time": 0, "value": 180}]},
		{"property": "color", "keys": [{"time": 0, "value": [255, 128, 0, 128]}, {"time": 1, "value": "#ff0000"}]},
		{"property": "scale", "keys": [{"time": 0, "value": 2}]},
		{"property": "position", "keys": [{"time": 9, "value": [9, 9]}, {"time": 1, "value": [1, 1]}, {"time": -1, "value": {"x": 0, "y": 0}}, {"time": 1, "value": [2, 2]}]},
		{"propiedad": "posicion", "claves": [{"tiempo": 1, "valor": [3, 3]}]},
		{"property": "invalida", "keys": [{"time": 0, "value": 1}]},
		{"property": "rotation", "keys": [{"time": "1", "value": 90}, {"time": 1, "value": "90"}]}
	]}\n```\nDespues')
	check(respuesta["ok"] and respuesta["error"] == "", "receta IA acepta texto, vallas y alias ingleses")
	if not respuesta["ok"]:
		return
	var receta: Dictionary = respuesta["receta"]
	check(receta["duracion"] is float and is_equal_approx(receta["duracion"], 2.0) and receta["loop"], "receta IA normaliza duracion y loop")
	var pistas := {}
	for pista in receta["pistas"]:
		pistas[pista["propiedad"]] = pista["claves"]
	check(pistas.size() == 4 and not pistas.has("invalida"), "receta IA descarta pistas no soportadas y fusiona propiedades")
	check(pistas["rotation"].size() == 1 and is_equal_approx(pistas["rotation"][0]["valor"], PI), "receta IA convierte grados a radianes y descarta numeros como texto")
	check((pistas["modulate"][0]["valor"] as Color).is_equal_approx(Color(1, 128.0 / 255.0, 0, 128.0 / 255.0)), "receta IA convierte color y alfa de 0 a 255")
	check(pistas["modulate"][1]["valor"] == Color.RED, "receta IA acepta color hexadecimal")
	check(pistas["scale"][0]["valor"] == Vector2(2, 2), "receta IA convierte escala numerica")
	var posicion: Array = pistas["position"]
	check(posicion.size() == 3 and posicion[0]["tiempo"] == 0.0 and posicion[1]["tiempo"] == 1.0 and posicion[2]["tiempo"] == 2.0, "receta IA ordena y limita tiempos a la duracion")
	check(posicion[0]["valor"] == Vector2.ZERO and posicion[1]["valor"] == Vector2(3, 3), "receta IA convierte diccionarios y conserva la ultima clave fusionada")
	check(ia.convertir("scale", {"x": 2, "y": 3}) == Vector2(2, 3) and ia.convertir("scale", [3, 4]) == Vector2(3, 4), "receta IA acepta escala como diccionario y array")
	check(ia.convertir("modulate", [255, 0, 0]) == Color.RED and ia.convertir("modulate", [1, 0, 0, 0.5]) == Color(1, 0, 0, 0.5), "receta IA conserva alfa por defecto y color normalizado")
	check(ia.convertir("modulate", "red") == Color.RED and ia.convertir("modulate", "#ff000080").is_equal_approx(Color(1, 0, 0, 128.0 / 255.0)), "receta IA acepta nombre de color y hexadecimal con alfa")
	for caso in [["position", null], ["position", [1]], ["position", {"x": "1", "y": 2}], ["scale", true], ["rotation", "90"], ["modulate", [255, "0", 0]], ["modulate", "#xyzxyz"], ["modulate", "color_inexistente"], ["otra", 1]]:
		check(ia.convertir(caso[0], caso[1]) == null, "receta IA rechaza valor raro para %s: %s" % [caso[0], caso[1]])
	for propiedad in ["pos", "posicion", "escala", "rotacion"]:
		var valor: Variant = [1, 2] if propiedad in ["pos", "posicion"] else 2
		var alias := ia.parsear(JSON.stringify({"pistas": [{"propiedad": propiedad, "claves": [{"tiempo": 0, "valor": valor}]}]}))
		check(alias["ok"] and alias["receta"]["duracion"] == 1.0 and not alias["receta"]["loop"], "receta IA acepta alias %s y valores por defecto" % propiedad)
	for caso in [[0, 0.05], [99, 30.0], [null, 1.0], ["2", 1.0]]:
		var limitada := ia.parsear(JSON.stringify({"duracion": caso[0], "loop": "true", "pistas": [{"propiedad": "scale", "claves": [{"tiempo": 0, "valor": 1}]}]}))
		check(limitada["ok"] and is_equal_approx(limitada["receta"]["duracion"], caso[1]) and not limitada["receta"]["loop"], "receta IA valida duracion y loop: %s" % caso[0])
	for texto in ['{}', '{"pistas": null}', '{"pistas": [null, 1, [], {"propiedad": null}, {"propiedad": "scale", "claves": null}, {"propiedad": "position", "claves": [null, {}, {"tiempo": 0, "valor": null}]}]}']:
		var vacia := ia.parsear(texto)
		check(not vacia["ok"] and vacia["error"] == "La IA no devolvio pistas validas" and vacia["receta"].is_empty(), "receta IA descarta entradas raras sin pistas validas")
	for texto in ["null", "[]", "123", '"12"']:
		var rara := ia.parsear(texto)
		check(not rara["ok"] and rara["error"] is String and rara["receta"] is Dictionary, "receta IA siempre devuelve el contrato ante JSON no valido")
	var rota := ia.parsear("{\n\"pistas\": [}\n")
	check(not rota["ok"] and rota["error"].contains("linea 1") and rota["receta"].is_empty(), "receta IA informa JSON roto y linea del error")


func test_auto_anim_ia_constructor() -> void:
	var receta_s := preload("res://addons/auto_anim/ia/receta.gd")
	var C := preload("res://addons/auto_anim/ia/constructor.gd")
	var cliente := preload("res://addons/auto_anim/ia/cliente_ia.gd")
	var texto := "{\"duracion\": 1.0, \"loop\": false, \"pistas\": [" 		+ "{\"propiedad\": \"position\", \"claves\": [{\"tiempo\": 0.25, \"valor\": [0, -80]}, {\"tiempo\": 1.0, \"valor\": [0, 0]}]}," 		+ "{\"propiedad\": \"rotation\", \"claves\": [{\"tiempo\": 0, \"valor\": 0}, {\"tiempo\": 1.0, \"valor\": 360}]}," 		+ "{\"propiedad\": \"scale\", \"claves\": [{\"tiempo\": 0, \"valor\": [1, 1]}, {\"tiempo\": 0.5, \"valor\": [2, 0.5]}]}]}"
	var r: Dictionary = receta_s.parsear(texto)
	check(r["ok"], "IA: receta de ejemplo valida")
	var raiz := Node2D.new()
	var nodo := Node2D.new()
	nodo.name = "Heroe"
	nodo.position = Vector2(100, 50)
	nodo.scale = Vector2(2, 2)
	raiz.add_child(nodo)
	nodo.owner = raiz
	var c = C.new()
	var anim: Animation = c.construir(r["receta"], nodo, true, false)
	check(anim != null and anim.get_track_count() == 3, "IA: construye una pista por propiedad")
	var tp := anim.find_track(NodePath(".:position"), Animation.TYPE_VALUE)
	check(tp >= 0 and anim.track_get_interpolation_type(tp) == Animation.INTERPOLATION_CUBIC, "IA: pistas con interpolacion cubica")
	check(anim.track_get_key_count(tp) == 3 and anim.track_get_key_value(tp, 0) == Vector2(100, 50), "IA: arranca desde el reposo si la IA no empieza en 0")
	check(anim.track_get_key_value(tp, 1) == Vector2(100, -30), "IA: posicion relativa al reposo")
	var tr := anim.find_track(NodePath(".:rotation"), Animation.TYPE_VALUE)
	check(is_equal_approx(float(anim.track_get_key_value(tr, 1)), TAU), "IA: 360 grados = una vuelta")
	var ts := anim.find_track(NodePath(".:scale"), Animation.TYPE_VALUE)
	check(anim.track_get_key_value(ts, 1) == Vector2(4, 1), "IA: escala multiplica la actual")
	check(anim.loop_mode == Animation.LOOP_NONE and c.construir(r["receta"], nodo, true, true).loop_mode == Animation.LOOP_LINEAR, "IA: forzar bucle")
	var absoluta: Animation = c.construir(r["receta"], nodo, false, false)
	check(absoluta.track_get_key_value(absoluta.find_track(NodePath(".:position"), Animation.TYPE_VALUE), 1) == Vector2(0, -80), "IA: modo absoluto")
	var suelto := Node.new()
	check(c.construir(r["receta"], suelto) == null and not c.error.is_empty(), "IA: rechaza nodos que no son 2D")
	suelto.free()

	# Instalar con deshacer/rehacer.
	var ur := UndoRedo.new()
	var player: AnimationPlayer = C.instalar(ur, nodo, raiz, "salto", anim)
	check(C.buscar_player(nodo, raiz) == player and player.owner == raiz and player.has_animation("ia/salto"), "IA: crea AnimIA con la libreria ia")
	ur.undo()
	check(C.buscar_player(nodo, raiz) == null, "IA: Ctrl+Z quita el AnimationPlayer creado")
	ur.redo()
	check(C.buscar_player(nodo, raiz) == player and player.has_animation("ia/salto"), "IA: rehacer lo devuelve")
	var otra: Animation = c.construir(r["receta"], nodo, false, true)
	C.instalar(ur, nodo, raiz, "salto", otra)
	check(player.get_animation("ia/salto") == otra and player.get_animation_library("ia").get_animation_list().size() == 1, "IA: mismo nombre reemplaza la animacion")
	ur.undo()
	check(player.get_animation("ia/salto") == anim, "IA: deshacer el reemplazo devuelve la anterior")
	ur.free()
	var estrella: Polygon2D = C.crear_forma_base(null, raiz)
	check(estrella.owner == raiz and estrella.polygon.size() == 10, "IA: forma base si no hay seleccion")
	raiz.free()

	# Modo local sin IA.
	var frase: Dictionary = receta_s.parsear(cliente.receta_local("salto alto con giro de 360 grados y caida suave", 1.2))
	var props := {}
	if frase["ok"]:
		for p in frase["receta"]["pistas"]:
			props[p["propiedad"]] = p["claves"]
	check(frase["ok"] and props.has("position") and props.has("rotation") and props.has("scale"), "IA local: salto con giro")
	check(frase["ok"] and is_equal_approx(float(props["rotation"].back()["valor"]), TAU) and is_equal_approx(float(frase["receta"]["duracion"]), 1.2), "IA local: 360 grados y duracion pedida")
	var lat: Dictionary = receta_s.parsear(cliente.receta_local("latido rojo en bucle", 0.8))
	check(lat["ok"] and lat["receta"]["loop"] and lat["receta"]["pistas"].any(func(p): return p["propiedad"] == "modulate"), "IA local: latido rojo en bucle")
	var rojo: Color = lat["receta"]["pistas"].filter(func(p): return p["propiedad"] == "modulate")[0]["claves"][1]["valor"]
	check(rojo.r > 1.0 and rojo.g < 1.0, "IA local: el brillo rojo no se toma como 0..255")
	var reb: Dictionary = receta_s.parsear(cliente.receta_local("rebota 2 veces", 1.0))
	check(reb["ok"] and reb["receta"]["pistas"][0]["claves"].size() == 5, "IA local: rebota N veces")
	for frase_rara in ["", "xyz", "gira 2 vueltas a la izquierda", "tiembla fuerte", "entra desde la izquierda", "desaparece", "flota"]:
		check(receta_s.parsear(cliente.receta_local(frase_rara, 1.0))["ok"], "IA local: siempre da una receta valida (" + frase_rara + ")")

	# Comandos de Claude y Codex, y Ollama.
	var cc: String = cliente.comando("claude", "haiku", "claude")
	check(cc.begins_with("claude -p --model haiku") and cc.contains("--tools \"\"") and cc.contains("< prompt.txt > salida.txt"), "IA: comando de Claude Code")
	var cx: String = cliente.comando("codex", "", "C:/Mis cosas/codex.cmd")
	check(cx.begins_with("\"C:/Mis cosas/codex.cmd\" exec") and cx.contains("model_reasoning_effort=low") and cx.contains("-o salida.txt - < prompt.txt"), "IA: comando de Codex")
	var po: Dictionary = cliente.peticion_ollama("", "salto", 1.0)
	check(po["model"] == "llama3.2" and po["format"] == "json" and not po["stream"] and po["messages"].size() == 2, "IA: peticion a Ollama")
	check(cliente.extraer_ollama({"message": {"content": "{}"}}) == "{}" and cliente.extraer_ollama(null) == "", "IA: lee la respuesta de Ollama")
	check(cliente.prompt_completo("salto", 1.5).contains("1.50 segundos") and cliente.prompt_completo("salto", 1.5).contains("UNICAMENTE"), "IA: prompt con reglas y duracion")
	check(load("res://addons/auto_anim/ia/panel_ia.tscn") is PackedScene, "IA: el panel carga")


func test_calidad_luchadores() -> void:
	var calidad := load("res://scripts/tools/calidad_luchador.gd")
	# Scale2x con tolerancia: duplica, respeta un borde recto y redondea una escalera.
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 4:
		img.set_pixel(0, y, Color.RED)  # columna recta
	img.set_pixel(2, 2, Color.BLUE)
	img.set_pixel(3, 2, Color.BLUE)
	img.set_pixel(3, 1, Color.BLUE)    # escalera en diagonal
	var hd: Image = calidad.escalar_2x(img)
	check(hd.get_width() == 8 and hd.get_height() == 8, "calidad: Scale2x duplica el tamaño")
	var recta := true
	for y in 8:
		recta = recta and hd.get_pixel(0, y) == Color.RED and hd.get_pixel(1, y) == Color.RED and hd.get_pixel(2, y).a == 0.0
	check(recta, "calidad: un borde recto sigue recto y del mismo grosor")
	check(hd.get_pixel(5, 3) == Color.BLUE, "calidad: la escalera se redondea (rellena el hueco de la diagonal)")
	check(hd.get_pixel(3, 7).a == 0.0 and hd.get_pixel(7, 7).a == 0.0, "calidad: sin manchas fuera del dibujo")
	# El pintor encuentra la hoja HD de cada luchador y escala la región del cuadro.
	var id := "itachi"
	var hoja := "res://assets/fighters/%s/%s_sheet.png" % [id, id]
	if FileAccess.file_exists(hoja.get_basename() + "_hd.json"):
		var ref := hoja + "#0,0,126,75"
		var tex := FighterPainter.textura_hd(ref)
		check(tex is AtlasTexture, "calidad: hay cuadro HD para " + id)
		if tex is AtlasTexture:
			var f := float((JSON.parse_string(FileAccess.get_file_as_string(hoja.get_basename() + "_hd.json")) as Dictionary)["factor"])
			check((tex as AtlasTexture).region.is_equal_approx(Rect2(0, 0, 126 * f, 75 * f)), "calidad: región HD = región normal x factor")
		FighterPainter.calidad_hd = false
		check(FighterPainter.textura_hd(ref) == null, "calidad: se puede apagar la HD")
		FighterPainter.calidad_hd = true
		check(FighterPainter.ajuste(ref) is Vector2, "calidad: se leen los ajustes de estabilización")
	check(FighterPainter.textura_hd("res://no/existe.png#0,0,1,1") == null, "calidad: sin hoja HD se usa la normal")


func test_menu_contract() -> void:
	var router_script = load("res://scripts/autoload/router.gd")
	var router = router_script.new()
	for key in ["title", "menu", "select", "stage", "fight"]:
		check(router.SCENES.has(key), "Router: ruta " + key)
		check(ResourceLoader.exists(router.SCENES[key]), "Router: escena existe " + key)
	check(not router.is_busy(), "Router comienza libre")
	router.goto("invalid_route")
	check(not router.is_busy(), "Router ignora rutas invalidas")
	check(ProjectSettings.get_setting("application/run/main_scene") == router.SCENES.title, "arranque en titulo")
	router.free()
	var controls = load("res://scripts/autoload/controls.gd").new()
	controls._ready()
	for code in [KEY_ENTER, KEY_J]:
		check(InputMap.event_is_action(controls._key(code), "ui_accept"), "aceptar teclado %s" % code)
	check(not InputMap.event_is_action(controls._key(KEY_SPACE), "ui_accept"), "Espacio (saltar) no confirma menús")
	for code in [KEY_ESCAPE, KEY_K, KEY_BACKSPACE]:
		check(InputMap.event_is_action(controls._key(code), "ui_cancel"), "cancelar teclado %s" % code)
	check(not InputMap.event_is_action(controls._key(KEY_L), "ui_cancel"), "L (fuerte) no cancela menús")
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B], ["pause", JOY_BUTTON_START]]:
		for device in [0, 1]:
			var event := InputEventJoypadButton.new()
			event.device = device
			event.button_index = pair[1]
			check(InputMap.event_is_action(event, pair[0]), "mando %s %s" % [device, pair[0]])
	for pair in [["pause", KEY_ESCAPE], ["pause", KEY_P], ["p1_kick", KEY_J], ["p1_attack", KEY_I], ["p1_jump", KEY_SPACE], ["p1_special", KEY_K], ["p1_heavy", KEY_L]]:
		check(InputMap.event_is_action(controls._key(pair[1]), pair[0]), "conserva " + pair[0])
	for pair in [["attack", KEY_I], ["kick", KEY_J], ["special", KEY_K], ["heavy", KEY_L]]:
		for action in ["attack", "kick", "special", "heavy"]:
			check(InputMap.event_is_action(controls._key(pair[1]), "p1_" + action) == (action == pair[0]), "tecla remapeada sin duplicar acciones: %s/%s" % [pair[1], action])
	for pair in [["attack", KEY_KP_1], ["kick", KEY_KP_6], ["special", KEY_KP_2], ["heavy", KEY_KP_4]]:
		check(InputMap.event_is_action(controls._key(pair[1]), "p2_" + pair[0]), "J2 conserva la acción " + pair[0])
	for device in [0, 1]:
		for pair in [["attack", JOY_BUTTON_X], ["kick", JOY_BUTTON_A], ["special", JOY_BUTTON_B]]:
			var button := InputEventJoypadButton.new()
			button.device = device
			button.button_index = pair[1]
			check(InputMap.event_is_action(button, "p%d_%s" % [device + 1, pair[0]]), "mando conserva %d/%s" % [device, pair[0]])
		var trigger := InputEventJoypadMotion.new()
		trigger.device = device
		trigger.axis = JOY_AXIS_TRIGGER_RIGHT
		trigger.axis_value = 1.0
		check(InputMap.event_is_action(trigger, "p%d_heavy" % [device + 1]), "RT conserva fuerte J%d" % [device + 1])
	check(InputMap.event_is_action(controls._key(KEY_J), "p1_menu_accept") and not InputMap.event_is_action(controls._key(KEY_I), "p1_menu_accept"), "selección J1 confirma con J y no depende del puño I")
	check(InputMap.event_is_action(controls._key(KEY_K), "p1_menu_cancel"), "selección J1 cancela con K")
	controls.free()
	# Restaurar los bytes originales del progreso, incluso si antes no existia.
	var save_script = load("res://scripts/autoload/save_data.gd")
	var data = save_script.new()
	var existed := FileAccess.file_exists(data.PATH)
	var original := FileAccess.get_file_as_bytes(data.PATH) if existed else PackedByteArray()
	check(data.last_menu_item == "", "ultima opcion comienza vacia")
	for id in data.MENU_ITEMS:
		data.remember_menu_item(id)
		var restored = save_script.new()
		restored.load_data()
		check(restored.last_menu_item == id, "persiste opcion " + id)
		restored.free()
	data.remember_menu_item("invalid")
	check(data.last_menu_item == "quit", "rechaza opcion desconocida")
	var file := FileAccess.open(data.PATH, FileAccess.WRITE)
	file.store_string('{"last_menu_item": "invalid"}')
	file.close()
	data.load_data()
	check(data.last_menu_item == "", "descarta opcion guardada invalida")
	file = FileAccess.open(data.PATH, FileAccess.WRITE)
	file.store_string('{}')
	file.close()
	data.load_data()
	check(data.last_menu_item == "", "partida antigua sin opcion")
	if existed:
		file = FileAccess.open(data.PATH, FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
	else:
		DirAccess.remove_absolute(data.PATH)
	data.free()


## ↓+L: Itachi anuncia su técnica de espada; el resto, «patada fuerte».
func test_heavy_kick_names() -> void:
	for caso in [["itachi", "¡TORBELLINO DE ESPADA!"], ["ban", "¡PATADA FUERTE!"]]:
		var data := _close_fight(String(caso[0]))
		var sim: CombatSim = data[0]
		sim.enemy.special_cooldown = 99.0
		sim.last_action = ""
		sim.request_attack(sim.player, "heavy_kick")
		for frame in 42:
			freeze_ai(sim)
			step(sim, 1)
			if sim.last_action != "":
				break
		check(sim.last_action == caso[1], "%s: ↓+L anuncia %s (sale %s)" % [caso[0], caso[1], sim.last_action])
	check(String(Catalog.fighter("itachi").get("heavy_kick_name", "")) == "Torbellino de espada" and not Catalog.fighter("ban").has("heavy_kick_name"), "solo Itachi cambia el nombre de ↓+L (lista de movimientos de la pausa)")
