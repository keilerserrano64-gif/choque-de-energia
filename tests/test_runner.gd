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
	test_catalog()
	test_animations()
	test_hitstun()
	test_knockdown_locks_control()
	test_jump_crosses_over()
	test_blocking()
	test_heavy_attack()
	test_vfx_events()
	test_input_buffer()
	test_combo_branches()
	test_air_and_guard_states()
	test_anim_events()
	test_animador()
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
	test_voices()
	test_ai_combos()
	test_air_attacks()
	test_sweep_and_antiair()
	test_throw()
	test_counter_hit()
	test_knockdown_bounce()
	test_volt_comfort()
	test_long_simulation()
	test_sprite_sheet()
	print("\n%d comprobaciones correctas, %d fallos" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failures += 1
		printerr("FALLO: " + message)


func make_sim(p1: String = "brasa", p2: String = "onix", mode: String = "cpu") -> Array:
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
	check(Catalog.FIGHTERS.size() == 8, "hay ocho luchadores")
	check(Catalog.STAGES.size() == 4, "hay cuatro escenarios")
	var ids := {}
	for f in Catalog.FIGHTERS:
		ids[f["id"]] = true
	check(ids.size() == 8, "los identificadores son únicos")


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
	var data := make_sim("volt", "onix")
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
	var data := make_sim("brasa", "pedernal")
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
		var data := make_sim(id, "pedernal" if id != "pedernal" else "brasa")
		var sim: CombatSim = data[0]
		var input: FakeInput = data[1]
		sim.enemy.x = sim.player.x + 62.0
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


func _anim_types(sim: CombatSim, index: int) -> Array:
	var types: Array = []
	for e in sim.consume_anim_events():
		if int(e["i"]) == index:
			types.append(String(e["tipo"]))
	return types


func test_anim_events() -> void:
	var data := make_sim("volt", "brasa")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	freeze_ai(sim)
	check(_anim_types(sim, 0).has("reiniciar"), "al empezar la ronda el animador se reinicia")
	sim.enemy.x = sim.player.x + 62.0
	input.press(0, "attack")
	step(sim, 1)
	check(_anim_types(sim, 0).has("golpe"), "el golpe J avisa al animador (golpe)")
	sim.player.attack_cooldown = 0.0
	sim.player.attack_windup = 0.0
	sim.player.has_pending_attack = false
	input.press(0, "heavy")
	step(sim, 1)
	check(_anim_types(sim, 0).has("patada"), "el golpe fuerte I avisa al animador (patada)")
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
	var f := FighterState.new("volt", 200.0, 1)
	animador.preparar(f)
	animador.actualizar(f, 1.0 / 60.0)
	check(animador.golpe() is Tween, "el animador crea el tween del golpe")
	animador.ko()
	check(bool(animador.salida()["ko"]), "tras ko() el animador marca el K.O.")
	animador.reiniciar()
	check(not bool(animador.salida()["ko"]) and animador.desp_accion == Vector2.ZERO, "reiniciar() devuelve todo a la normalidad")
	animador.queue_free()


## Prepara a dos luchadores pegados y sin IA para probar golpes.
func _close_fight(p1: String = "volt", p2: String = "brasa") -> Array:
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
	input.press(0, "heavy")  # J → I
	var launched := false
	for i in range(50):
		freeze_ai(sim)
		step(sim, 1)
		if sim.last_action == "¡LANZADOR!":
			launched = true
	check(launched, "J → I es el lanzador")
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
	check(cross, "J → J → I es el remate cruzado")
	check(ComboData.branch_for(Catalog.fighter("volt"), 0).is_empty(), "sin cadena no hay rama: I es el golpe fuerte suelto")


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
	var data := make_sim("volt", "brasa")
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
	var data := make_sim("brasa", "volt", "versus")
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
	var data := make_sim("brasa", "luma", "training")
	var sim: CombatSim = data[0]
	sim.enemy.health = 1
	sim.hit(sim.enemy, 1, 50, {"hit_stop": 0.0})
	step(sim, 200)
	check(sim.state == "playing", "en entrenamiento nadie pierde")
	check(sim.enemy.health == 100, "la vida del muñeco se recarga")


func test_every_technique() -> void:
	for f in Catalog.FIGHTERS:
		var id := String(f["id"])
		var data := make_sim(id, "brasa" if id != "brasa" else "onix")
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
	var data := make_sim("brasa", "pedernal")
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
		var data := make_sim(id, "onix" if id != "onix" else "luma")
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


# --- Puños, patadas, combos y voces ------------------------------------------

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
			var data := make_sim(id, "pedernal" if id != "pedernal" else "brasa")
			var sim: CombatSim = data[0]
			var input: FakeInput = data[1]
			sim.enemy.x = sim.player.x + 64.0
			var length := ComboData.chain_length(sim.player.definition, kind)
			var used := _do_chain(sim, input, "kick" if kind == "kick" else "attack", length)
			var allowed: Array = kicks if kind == "kick" else punches
			var only_kind := used.all(func(a: String) -> bool: return allowed.has(a))
			check(only_kind, "%s: pulsar %s varias veces solo lanza %s (%s)" % [id, "K" if kind == "kick" else "J", "patadas" if kind == "kick" else "puños", used])
			check(used.back() == ("kick_spin" if kind == "kick" else "uppercut"), "%s: la cadena de %s termina en su remate" % [id, kind])
			check(used.size() == length and used.slice(0, length - 1).all(func(a: String) -> bool: return a != used.back()) or length == 2,
				"%s: los golpes de la cadena de %s cambian (%s)" % [id, kind, used])


func test_mixed_chain() -> void:
	var data := make_sim("volt", "pedernal")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	sim.enemy.x = sim.player.x + 64.0
	var used := _do_chain(sim, input, "attack", 2)
	used.append_array(_do_chain(sim, input, "kick", 2))
	check(used == ["jab", "cross", "kick_high", "kick_spin"], "J, J, K, K: dos puños y dos patadas siguiendo el combo (%s)" % [used])


func test_true_combos() -> void:
	for f in Catalog.FIGHTERS:
		var id := String(f["id"])
		for action in ["attack", "kick"]:
			var data := make_sim(id, "luma" if id != "luma" else "brasa")
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


func test_voices() -> void:
	for f in Catalog.FIGHTERS:
		var id := String(f["id"])
		for line in Catalog.VOICE_LINES:
			check(ResourceLoader.exists("res://assets/voices/%s/%s_0.wav" % [id, line]), "%s tiene la voz %s" % [id, line])
	var data := make_sim("cobalto", "espejo")
	var sim: CombatSim = data[0]
	freeze_ai(sim)
	sim.use_technique(sim.player, sim.enemy)
	step(sim, 20)
	var events := sim.consume_audio_events()
	check(events.has("voice|0|cobalto|special|0.00"), "la técnica dice su nombre con la voz del luchador")
	sim.enemy.health = 0
	step(sim, 1)
	events = sim.consume_audio_events()
	check(events.any(func(e: String) -> bool: return e.begins_with("voice|1|espejo|ko")), "el K.O. tiene su grito")
	check(events.any(func(e: String) -> bool: return e.begins_with("voice|0|cobalto|victory")), "el ganador dice su frase de victoria")


func test_ai_combos() -> void:
	var seen := {}
	for seed_value in range(6):
		var data := make_sim("brasa", "volt")
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
	var data := make_sim("brasa", "pedernal")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	freeze_ai(sim)
	sim.enemy.x = sim.player.x + 90.0
	input.press(0, "jump")
	input.down["0_right"] = true
	step(sim, 14)
	input.press(0, "kick")
	step(sim, 1)
	check(sim.player.attack_animation == "air_kick" and not sim.player.grounded, "K en el aire lanza la patada voladora")
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
	data = make_sim("volt", "pedernal")
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
	var data := make_sim("marea", "cobalto")
	var sim: CombatSim = data[0]
	var input: FakeInput = data[1]
	freeze_ai(sim)
	sim.enemy.x = sim.player.x + 66.0
	input.down["0_down"] = true
	input.press(0, "kick")
	step(sim, 1)
	check(sim.player.attack_animation == "sweep", "↓ + K es la barrida")
	var knocked := false
	for i in range(30):
		freeze_ai(sim)
		step(sim, 1)
		knocked = knocked or sim.enemy.knocked_down
	check(knocked, "la barrida derriba al rival")
	data = make_sim("marea", "cobalto")
	sim = data[0]
	input = data[1]
	freeze_ai(sim)
	sim.enemy.x = sim.player.x + 64.0
	input.down["0_down"] = true
	input.press(0, "attack")
	step(sim, 1)
	check(sim.player.attack_animation == "uppercut", "↓ + J es el uppercut antiaéreo")


func test_throw() -> void:
	var data := make_sim("pedernal", "luma", "versus")
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
	check(sim.player.attack_animation == "throw", "→ + I pegado al rival es un agarre")
	for i in range(20):
		step(sim, 1)
	check(sim.enemy.health < before and sim.enemy.knocked_down, "el agarre atraviesa la guardia y derriba")
	data = make_sim("pedernal", "luma")
	sim = data[0]
	input = data[1]
	freeze_ai(sim)
	sim.enemy.x = sim.player.x + 160.0
	input.down["0_right"] = true
	input.press(0, "heavy")
	step(sim, 1)
	check(sim.player.attack_animation != "throw", "de lejos →+I es el golpe fuerte normal")


func test_counter_hit() -> void:
	var data := make_sim("brasa", "pedernal")
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
	var data := make_sim("brasa", "onix")
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


# --- Volt más cómodo -----------------------------------------------------------

func test_volt_comfort() -> void:
	# Salto de umbral: conecta también pegado al rival y nunca lo atraviesa.
	for d in [62.0, 70.0, 100.0, 120.0]:
		var data := make_sim("volt", "luma")
		var sim: CombatSim = data[0]
		freeze_ai(sim)
		sim.player.x = 150.0
		sim.enemy.x = 150.0 + d
		var hp := sim.enemy.health
		sim.use_technique(sim.player, sim.enemy)
		for i in range(30):
			freeze_ai(sim)
			step(sim, 1)
		check(sim.enemy.health < hp, "Volt: Salto de umbral conecta a %d px" % d)
		check(sim.player.x < sim.enemy.x, "Volt: Salto de umbral no atraviesa al rival (%d px)" % d)
	# Lejos: recorre su distancia completa y no golpea.
	var far := make_sim("volt", "luma")
	var fsim: CombatSim = far[0]
	freeze_ai(fsim)
	fsim.player.x = 100.0
	fsim.enemy.x = 330.0
	var far_hp := fsim.enemy.health
	fsim.use_technique(fsim.player, fsim.enemy)
	for i in range(30):
		freeze_ai(fsim)
		step(fsim, 1)
	check(fsim.enemy.health == far_hp and fsim.player.x > 180.0, "Volt: de lejos el Salto de umbral solo acerca")
	# Atrás + técnica: esquiva hacia atrás y el primer golpe lo atraviesa.
	var back := make_sim("volt", "luma", "versus")
	var bsim: CombatSim = back[0]
	var input: FakeInput = back[1]
	bsim.player.x = 220.0
	bsim.enemy.x = 282.0
	input.down["0_left"] = true
	input.press(0, "special")
	step(bsim, 1)
	input.down.clear()
	step(bsim, 12)
	check(bsim.player.x < 160.0, "Volt: atrás + L esquiva hacia atrás (x = %d)" % bsim.player.x)
	check(bsim.player.phase_time > 0.0, "Volt: la esquiva da un instante intocable")
	var hp_before := bsim.player.health
	var connected := bsim.hit(bsim.player, -1, 20, {"attacker": 1, "hit_stop": 0.0})
	check(not connected and bsim.player.health == hp_before, "Volt: el golpe durante la esquiva no hace daño")
	# Arco de ruptura (despertar) también a quemarropa.
	var arc := make_sim("volt", "luma")
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
	check(asim.enemy.health < arc_hp, "Volt: Arco de ruptura conecta pegado al rival")
	# Sus golpes sin imagen propia se giran para leerse bien; los demás no.
	check(not FighterPainter._move_tweak("kick_low", "finisher_impact").is_empty(), "Volt: la patada baja se dibuja inclinada")
	check(not FighterPainter._move_tweak("uppercut", "heavy").is_empty(), "Volt: el uppercut se dibuja hacia arriba")
	check(FighterPainter._move_tweak("kick_low", "kick_low").is_empty(), "los luchadores con imagen propia no se giran")


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
