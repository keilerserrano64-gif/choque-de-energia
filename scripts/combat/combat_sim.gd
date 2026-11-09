class_name CombatSim
extends RefCounted
## Simulación del combate: física, golpes, técnicas, IA, rondas y recompensas.
## Es una traducción fiel de src/game.js (versión con menú, VS, bloqueo,
## hitstun, temporizador de 99 s y mejor de 3). No depende de nodos, así que se
## puede probar sin abrir ninguna escena (ver tests/test_runner.gd).
##
## Coordenadas: arena lógica de 480 px de ancho; el suelo está en y = 204.

signal round_finished(result: String)
signal match_finished

const WIDTH := 480.0
const FLOOR := 204.0
const ARENA_LEFT := 22.0
const ARENA_RIGHT := WIDTH - 22.0
const MAX_HEALTH := 100
const DAMAGE_SCALE := 0.75
const GRAVITY := 960.0
const BODY_GAP := 20.0
const ROUND_DURATION := 99.0
const SOLAR_CHARGE_TIME := 15.0 / 60.0
const SHARD_CHARGE_TIME := 20.0 / 60.0
const HEAVY_COOLDOWN := 0.6  ## recuperación mínima del golpe fuerte (s)
## Salto de umbral de Volt: alcance de la embestida, alcance del golpe y esquiva hacia atrás.
const VOLT_STEP_RANGE := 88.0
const VOLT_STEP_HIT_RANGE := 125.0
const VOLT_STEP_BACK := 84.0
const VOLT_DODGE_TIME := 0.3
const HEAVY_DAMAGE_FACTOR := 0.85  ## el golpe fuerte hace el 85 % del daño del remate
const SPECIAL_CHARGE_FRAMES := {
	"volt-step": 8, "arc-lunge": 1, "marea-guard": 12, "prism-lance": 12,
	"mirror-step": 10, "fault-ring": 16, "luma-heal": 14,
}
const MODES := ["cpu", "versus", "training"]

## Objeto de entrada con is_down(i, accion, modo), consume_press(i, accion, modo)
## y clear_pressed(). En el juego es PlayerInput; en las pruebas, uno falso.
var input = null
var mode := "cpu"
var player_id := "brasa"
var enemy_id := "onix"
var stage_id := "brumaria"
var difficulty_id := "challenging"
var player: FighterState
var enemy: FighterState
var projectiles: Array = []
var particles: Array = []
var effects: Array = []
var state := "ready"  ## ready | playing | round-finished | finished
var elapsed := 0.0
var screen_shake := 0.0
var hit_stop_frames := 0.0
var armor_flash := 0.0
var last_action := ""
var last_action_time := 0.0
var reward := 0
var highest_combo := 0
var round_number := 0
var player_round_wins := 0
var enemy_round_wins := 0
var round_result := ""
var round_time := ROUND_DURATION
var audio_events: Array[String] = []
## Momentos para los shaders de pantalla: {"type": "shock"|"awaken"|"ko", "x", "y", "strength", "color"}.
## Fight los recoge con consume_vfx_events(); aquí solo se anotan, sin depender de nodos.
var vfx_events: Array = []
## Acciones para AnimadorProcedural: {"i": índice del luchador, "tipo": "golpe"|"patada"|
## "golpe_recibido"|"bloqueo"|"dash"|"ko"|"victoria"|"reiniciar", ...}. Las recoge ArenaView.
var anim_events: Array = []
const MAX_ANIM_EVENTS := 64
var training_idle := 0.0
var _last_hit_counter := false  ## el último golpe que entró fue un contraataque
## Anuncios grandes para el HUD: {"text", "color"} (primer golpe, combos enormes).
var callouts: Array = []
var _first_hit_done := false
var rng := RandomNumberGenerator.new()


func _init(input_source = null) -> void:
	input = input_source
	rng.randomize()
	initialize_fighters()


# --- Configuración y rondas -------------------------------------------------

func initialize_fighters() -> void:
	var level := Catalog.difficulty(difficulty_id)
	player = FighterState.new(player_id, 120.0, 1)
	player.index = 0
	var enemy_damage: float = 1.0 if mode == "versus" else float(level["damage"])
	enemy = FighterState.new(enemy_id, 360.0, -1, enemy_damage)
	enemy.index = 1
	if mode != "versus":
		enemy.speed_multiplier = float(level["speed"])
		enemy.reaction_multiplier = float(level["reaction"])


func configure(p_player_id: String, p_enemy_id: String, p_stage_id: String, p_difficulty_id: String, p_mode: String = "cpu") -> void:
	player_id = Catalog.fighter(p_player_id)["id"]
	enemy_id = Catalog.fighter(p_enemy_id)["id"]
	stage_id = Catalog.stage(p_stage_id)["id"]
	difficulty_id = p_difficulty_id if Catalog.DIFFICULTIES.has(p_difficulty_id) else "challenging"
	if not MODES.has(p_mode):
		push_error("Modo de juego desconocido: %s" % p_mode)
		p_mode = "cpu"
	mode = p_mode
	initialize_fighters()
	state = "ready"


func start() -> void:
	round_number = 1
	player_round_wins = 0
	enemy_round_wins = 0
	round_result = ""
	highest_combo = 0
	reward = 0
	audio_events.clear()
	reset_round()
	state = "playing"


func restart() -> void:
	start()


func reset_round() -> void:
	var player_awakening := player.awakening_available if player else false
	var enemy_awakening := enemy.awakening_available if enemy else false
	initialize_fighters()
	player.awakening_available = player_awakening
	enemy.awakening_available = enemy_awakening
	projectiles.clear()
	particles.clear()
	effects.clear()
	vfx_events.clear()
	anim_events.clear()
	callouts.clear()
	_first_hit_done = false
	queue_anim(player, "reiniciar")
	queue_anim(enemy, "reiniciar")
	elapsed = 0.0
	screen_shake = 0.0
	hit_stop_frames = 0.0
	armor_flash = 0.0
	last_action = ""
	round_time = ROUND_DURATION
	training_idle = 0.0


func next_round() -> bool:
	if state != "round-finished" or round_number >= 3 or player_round_wins >= 2 or enemy_round_wins >= 2:
		return false
	round_number += 1
	round_result = ""
	reset_round()
	state = "playing"
	return true


func consume_audio_events() -> Array:
	var events: Array = []
	for kind in audio_events:
		events.append(kind)
	audio_events.clear()
	return events


func queue_audio(kind: String) -> void:
	audio_events.append(kind)


## Voz del luchador: anota "voice|<lado>|<luchador>|<frase>|<retraso>" para Sfx.
## Los gritos de golpe y de dolor tienen probabilidad y un pequeño enfriamiento
## para que no hable en cada cuadro; técnicas, despertar, K.O. y victoria siempre suenan.
const VOICE_ALWAYS := ["special", "awaken", "ko", "victory", "intro", "heavy"]


func queue_voice(f: FighterState, line: String, chance: float = 1.0, delay: float = 0.0) -> void:
	if f == null:
		return
	var important := VOICE_ALWAYS.has(line)
	if not important and (f.voice_cooldown > 0.0 or rng.randf() > chance):
		return
	f.voice_cooldown = 0.5 if not important else 0.35
	audio_events.append("voice|%d|%s|%s|%.2f" % [f.index, f.id, line, delay])


func consume_callouts() -> Array:
	var list := callouts.duplicate()
	callouts.clear()
	return list


func consume_vfx_events() -> Array:
	var events := vfx_events.duplicate()
	vfx_events.clear()
	return events


func queue_vfx(kind: String, x: float, y: float, strength: float, color: String) -> void:
	vfx_events.append({"type": kind, "x": x, "y": y, "strength": strength, "color": color})


func consume_anim_events() -> Array:
	var events := anim_events.duplicate()
	anim_events.clear()
	return events


func queue_anim(f: FighterState, tipo: String, extra: Dictionary = {}) -> void:
	var event := extra.duplicate()
	event["i"] = f.index
	event["tipo"] = tipo
	anim_events.append(event)
	if anim_events.size() > MAX_ANIM_EVENTS:  # nadie los recoge (p. ej. en las pruebas)
		anim_events.pop_front()


func finish_round(result: String) -> void:
	if state != "playing":
		return
	round_result = result
	if result == "player":
		player_round_wins += 1
	elif result == "enemy":
		enemy_round_wins += 1
	var match_done := round_number >= 3 or player_round_wins >= 2 or enemy_round_wins >= 2
	state = "finished" if match_done else "round-finished"
	if match_done:
		var draw := player_round_wins == enemy_round_wins
		var base_reward := 15 if draw else (30 if player_round_wins > enemy_round_wins else 10)
		reward = base_reward + int(highest_combo / 5) * 2
	if result == "draw":
		last_action = "RONDA EMPATADA"
	elif result == "player":
		last_action = "¡RONDA PARA TI!" if mode != "versus" else "¡RONDA PARA J1!"
	else:
		last_action = "RONDA PARA EL RIVAL" if mode != "versus" else "¡RONDA PARA J2!"
	last_action_time = 4.0
	queue_audio("ko")
	if player.health <= 0 or enemy.health <= 0:
		var fallen := player if player.health <= 0 else enemy
		queue_vfx("ko", fallen.x, FLOOR - 38.0 + fallen.y, 1.0, String(fallen.definition["accent"]))
	for fighter in [player, enemy]:
		var f: FighterState = fighter
		if f.health <= 0:
			queue_anim(f, "ko")
			queue_voice(f, "ko", 1.0)
	if result == "player" or result == "enemy":
		queue_voice(player if result == "player" else enemy, "victory", 1.0, 1.4)
	if result == "player":
		queue_anim(player, "victoria")
	elif result == "enemy":
		queue_anim(enemy, "victoria")
	round_finished.emit(result)
	if match_done:
		match_finished.emit()


# --- Bucle principal --------------------------------------------------------

func update(dt: float) -> void:
	if hit_stop_frames > 0.0:
		hit_stop_frames = maxf(0.0, hit_stop_frames - dt * 60.0)
		_buffer_frozen_presses()
		_clear_input()
		return

	elapsed += dt
	_update_particles(dt)
	_update_effects(dt)
	screen_shake = maxf(0.0, screen_shake - dt * 30.0)
	armor_flash = maxf(0.0, armor_flash - dt)
	last_action_time = maxf(0.0, last_action_time - dt)

	if state != "playing":
		_clear_input()
		return

	if mode != "training":
		round_time = maxf(0.0, round_time - dt)
	_update_fighter_timers(player, dt)
	_update_fighter_timers(enemy, dt)
	_move_controlled_fighter(player, enemy, 0, dt)
	_move_enemy(dt)
	_face_opponents()
	_update_attacks(dt)
	_update_specials(dt)
	_update_projectiles(dt)
	_keep_apart()

	if mode == "training":
		_training_upkeep(dt)
	elif player.health <= 0 or enemy.health <= 0:
		var result := "draw"
		if player.health > 0:
			result = "player"
		elif enemy.health > 0:
			result = "enemy"
		finish_round(result)
	elif round_time <= 0.0:
		var result := "draw"
		if player.health > enemy.health:
			result = "player"
		elif enemy.health > player.health:
			result = "enemy"
		finish_round(result)
	_clear_input()


func _clear_input() -> void:
	if input:
		input.clear_pressed()


func _is_down(index: int, action: String) -> bool:
	return input != null and input.is_down(index, action, mode)


func _consume_press(index: int, action: String) -> bool:
	return input != null and input.consume_press(index, action, mode)


func _training_upkeep(dt: float) -> void:
	# En entrenamiento nadie pierde: la vida y la energía se recargan solas.
	player.meter = 100.0 if player.awakening_time <= 0.0 and player.awakening_available else player.meter
	if enemy.hurt_time > 0.0 or player.health < MAX_HEALTH and player.hurt_time > 0.0:
		training_idle = 0.0
	else:
		training_idle += dt
	if training_idle > 1.4:
		player.health = MAX_HEALTH
		enemy.health = MAX_HEALTH
	player.health = maxi(player.health, 1)
	enemy.health = maxi(enemy.health, 1)


func _update_fighter_timers(f: FighterState, dt: float) -> void:
	f.attack_cooldown = maxf(0.0, f.attack_cooldown - dt)
	f.special_cooldown = maxf(0.0, f.special_cooldown - dt)
	f.hit_flash = maxf(0.0, f.hit_flash - dt)
	f.white_flash = maxf(0.0, f.white_flash - dt)
	f.hurt_time = maxf(0.0, f.hurt_time - dt)
	f.attack_pose = maxf(0.0, f.attack_pose - dt)
	f.special_pose_time = maxf(0.0, f.special_pose_time - dt)
	f.getup_time = maxf(0.0, f.getup_time - dt)
	f.knockdown_time = f.knockdown_time + dt if f.knocked_down else 0.0
	f.guard_time = maxf(0.0, f.guard_time - dt)
	if f.guard_time == 0.0:
		f.blocking = false
	f.decoy_time = maxf(0.0, f.decoy_time - dt)
	f.combo_timer = maxf(0.0, f.combo_timer - dt)
	f.combo_display = maxf(0.0, f.combo_display - dt)
	f.voice_cooldown = maxf(0.0, f.voice_cooldown - dt)
	var foe := opponent_of(f)
	if f.combo_hits > 0 and foe.hurt_time <= 0.0 and not foe.knocked_down and f.combo_display <= 0.0:
		f.combo_hits = 0
		f.combo_damage = 0
	f.awakening_time = maxf(0.0, f.awakening_time - dt)
	f.phase_time = maxf(0.0, f.phase_time - dt)
	f.armor_time = maxf(0.0, f.armor_time - dt)


func opponent_of(f: FighterState) -> FighterState:
	return enemy if f == player else player


func fighter_by_index(i: int) -> FighterState:
	return player if i == 0 else enemy


# --- Movimiento -------------------------------------------------------------

func _move_controlled_fighter(f: FighterState, target: FighterState, index: int, dt: float) -> void:
	if f.hurt_time > 0.0 or f.knocked_down or f.getup_time > 0.0:
		f.walking = false
		f.running = false
		f.blocking = false
		_apply_knockback(f, dt)
		_apply_gravity(f, dt)
		return
	if f.special_charge > 0.0:
		f.walking = false
		f.blocking = false
		_apply_knockback(f, dt)
		_apply_gravity(f, dt)
		return
	var left := _is_down(index, "left")
	var right := _is_down(index, "right")
	# Cubrirse tiene su propia tecla (E): caminar hacia atrás ya no bloquea.
	# También se puede bloquear en el aire (como StateBlockingOnAir): se cae en vertical.
	var guarding := _is_down(index, "block")
	f.blocking = guarding and f.attack_pose <= 0.0 and f.attack_windup <= 0.0 and f.getup_time <= 0.0
	if f.blocking:
		f.guard_time = 0.06
		f.walking = false
		f.running = false
		f.attack_pose = 0.0
		f.has_pending_attack = false
		_apply_knockback(f, dt)
		_apply_gravity(f, dt)
		return
	f.running = _is_down(index, "run") and left != right

	if left != right:
		var run_boost: float = float(f.stat("run_multiplier", 1.25)) if f.running else 1.0
		f.x += (1.0 if right else -1.0) * move_speed(f) * run_boost * dt
		f.walking = true
		_emit_footsteps(f, dt)
	else:
		f.walking = false
		f.running = false
		f.step_timer = 0.0

	if _consume_press(index, "jump"):
		jump(f)
	# Comandos: ↓+J uppercut antiaéreo, ↓+K barrida, →+I agarre (cerca del rival).
	var crouching := _is_down(index, "down")
	var toward := (right and f.facing > 0) or (left and f.facing < 0)
	if _consume_press(index, "attack"):
		request_attack(f, "low_attack" if crouching and f.grounded else "attack")
	if _consume_press(index, "kick"):
		request_attack(f, "sweep" if crouching and f.grounded else "kick")
	if _consume_press(index, "heavy"):
		request_attack(f, "throw" if toward and can_throw(f, target) else "heavy")
	if _consume_press(index, "special"):
		# Atrás + técnica: algunas técnicas cambian (Volt esquiva hacia atrás).
		f.special_back = (left and f.facing > 0) or (right and f.facing < 0)
		use_technique(f, target)
	if _consume_press(index, "awaken"):
		awaken(f, f.awakening_available)

	_apply_knockback(f, dt)
	_apply_gravity(f, dt)
	f.x = clamp_x(f.x)


func _move_enemy(dt: float) -> void:
	if mode == "versus":
		_move_controlled_fighter(enemy, player, 1, dt)
		return
	var f := enemy
	if mode == "training":
		f.walking = false
		f.running = false
		_apply_knockback(f, dt)
		_apply_gravity(f, dt)
		f.x = clamp_x(f.x)
		return
	var target := player
	var distance := target.x - f.x
	var absolute_distance := absf(distance)
	var minimum_distance := minimum_fighter_distance(f, target)
	f.facing = 1 if distance >= 0.0 else -1
	f.ai_decision -= dt
	f.ai_jump_timer -= dt

	if f.special_charge > 0.0:
		f.walking = false
		f.blocking = false
		_apply_knockback(f, dt)
		_apply_gravity(f, dt)
		return

	if f.hurt_time > 0.0 or f.knocked_down or f.getup_time > 0.0:
		f.walking = false
		f.running = false
		f.blocking = false
		_apply_knockback(f, dt)
		_apply_gravity(f, dt)
		return

	var threatened := f.difficulty > 1.0 and f.ai_decision <= 0.0 and target.has_pending_attack and target.attack_windup < 0.12
	f.blocking = threatened and f.grounded and f.attack_pose <= 0.0
	if f.blocking:
		f.guard_time = 0.06
		f.ai_decision = 0.45 * f.reaction_multiplier
		f.walking = false
		_apply_knockback(f, dt)
		_apply_gravity(f, dt)
		return

	if absolute_distance > minimum_distance:
		f.x += signf(distance) * move_speed(f) * 0.73 * dt
		f.walking = true
		_emit_footsteps(f, dt)
	else:
		f.walking = false
		f.step_timer = 0.0
	if absolute_distance < minimum_distance:
		f.x += signf(distance) * move_speed(f) * 0.4 * dt

	_apply_knockback(f, dt)
	_apply_gravity(f, dt)
	f.x = clamp_x(f.x)

	if _ai_reactions(f, target, absolute_distance):
		return
	if _run_ai_plan(f, target):
		return
	if f.special_charge > 0.0 or f.ai_decision > 0.0:
		return
	f.ai_decision = (0.32 + rng.randf() * 0.38) * f.reaction_multiplier
	if f.health <= 34 and f.awakening_time <= 0.0 and f.meter >= 100.0:
		awaken(f, f.awakening_available)
	if absolute_distance < 100.0 and f.grounded:
		_plan_ai_combo(f, absolute_distance)
		_run_ai_plan(f, target)
	elif f.special_cooldown <= 0.0 and absolute_distance < 245.0 and (f.id != "luma" or f.health < 76):
		use_technique(f, target)
	elif f.grounded and f.ai_jump_timer <= 0.0 and absolute_distance > 75.0:
		jump(f)
		f.ai_jump_timer = 1.4 + rng.randf() * 1.3


## La CPU elige un combo entero (puños, patadas o mezcla que remata con I) y lo
## ejecuta golpe a golpe. En Desafío y Experto confirma: si el primer golpe no entra
## (bloqueado o esquivado) abandona el resto para no quedar vendida.
func _plan_ai_combo(f: FighterState, distance: float) -> void:
	var punches := ComboData.chain_length(f.definition, "punch")
	var kicks := ComboData.chain_length(f.definition, "kick")
	var plans: Array = []
	# Si el jugador se cubre mucho, la CPU lo agarra.
	if f.difficulty >= 1.0 and opponent_of(f).guard_time > 0.0 and rng.randf() < 0.6:
		f.ai_plan = ["throw"]
		return
	if distance > 82.0:
		plans.append(_repeat("kick", kicks))  # las patadas llegan más lejos
		plans.append(["kick", "kick", "heavy"])
	else:
		plans.append(_repeat("attack", punches))
		plans.append(_repeat("kick", kicks))
		plans.append(["attack", "heavy"])
		plans.append(["attack", "attack", "heavy"])
		plans.append(["attack", "attack", "kick", "kick"])
		plans.append(["sweep"])
		plans.append(["attack", "attack", "sweep"])
	var plan: Array = plans[rng.randi() % plans.size()]
	# En el nivel más fácil la CPU suele quedarse a medias.
	if f.difficulty < 1.0 and plan.size() > 2 and rng.randf() < 0.5:
		plan = plan.slice(0, 2)
	f.ai_plan = plan.duplicate()


func _repeat(action: String, times: int) -> Array:
	var result: Array = []
	for i in range(times):
		result.append(action)
	return result


## Reacciones rápidas de la CPU: uppercut antiaéreo si el jugador le salta encima
## y patada voladora cuando ella misma cae cerca del jugador.
func _ai_reactions(f: FighterState, target: FighterState, distance: float) -> bool:
	if _attack_busy(f) or f.hurt_time > 0.0 or f.knocked_down:
		return false
	if not f.grounded:
		if not f.air_attack_used and f.velocity_y > 0.0 and distance < 88.0:
			request_attack(f, "kick" if rng.randf() < 0.7 else "attack")
			return true
		return false
	var smart := f.difficulty >= 1.0
	if smart and f.id == "volt" and f.special_cooldown <= 0.0 and target.has_pending_attack \
			and target.attack_windup > 0.04 and distance < 90.0 and rng.randf() < 0.3:
		f.special_back = true
		use_technique(f, target)
		return true
	if smart and not target.grounded and target.velocity_y > -120.0 and distance < 80.0 and f.ai_decision <= 0.0:
		f.ai_decision = 0.5 * f.reaction_multiplier
		if rng.randf() < 0.55 * (f.difficulty / f.reaction_multiplier):
			request_attack(f, "low_attack")
			return true
	return false


## Lanza el siguiente golpe del combo pensado. Devuelve true si la CPU está ocupada con él.
func _run_ai_plan(f: FighterState, target: FighterState) -> bool:
	if f.ai_plan.is_empty():
		return false
	if f.hurt_time > 0.0 or f.knocked_down or not f.grounded:
		f.ai_plan.clear()
		return false
	if _attack_busy(f):
		return true
	var confirming := f.difficulty >= 1.0 and f.attack_index > 0
	if confirming and target.hurt_time <= 0.0 and not target.knocked_down:
		f.ai_plan.clear()  # el golpe anterior no entró: no sigue el combo
		return false
	var action := String(f.ai_plan.pop_front())
	if action == "throw" and not can_throw(f, target):
		action = "attack"
	request_attack(f, action)
	return true


func move_speed(f: FighterState) -> float:
	var boost := 1.0
	if f.awakening_time > 0.0:
		boost = 1.42 if f.id == "volt" else 1.28
	return float(f.definition["speed"]) * 0.46 * boost * f.speed_multiplier


func minimum_fighter_distance(first: FighterState, second: FighterState) -> float:
	return float(first.definition["pushbox_half_width"]) + float(second.definition["pushbox_half_width"]) + BODY_GAP


func _apply_knockback(f: FighterState, dt: float) -> void:
	if absf(f.knockback_velocity) < 1.0:
		f.knockback_velocity = 0.0
		return
	f.x = clamp_x(f.x + f.knockback_velocity * dt)
	f.knockback_velocity *= exp(-7.5 * dt)


func _emit_footsteps(f: FighterState, dt: float) -> void:
	f.step_timer -= dt
	var interval := 0.26 if f.id == "onix" else 0.105
	if f.step_timer > 0.0 or not f.grounded:
		return
	f.step_timer = interval
	var color := "#ff8b38" if f.id == "brasa" else "#c6a37b"
	burst(f.x - f.facing * 12, FLOOR - 2, color, 2 if f.id == "brasa" else 4)
	if f.running:
		# Nubecillas de polvo detrás de los pies al correr.
		add_effect({"type": "dust-cloud", "x": f.x - f.facing * 14.0, "y": FLOOR - 1.0, "size": 0.45,
			"life": 0.22, "max_life": 0.22, "color": "#cfc3a8"})
	if f.id == "onix":
		screen_shake = maxf(screen_shake, 0.45)


func jump(f: FighterState) -> void:
	if not f.grounded or f.hurt_time > 0.0 or f.knocked_down or f.getup_time > 0.0 or f.blocking:
		return
	f.velocity_y = -390.0
	f.grounded = false
	queue_audio("jump")


func _apply_gravity(f: FighterState, dt: float) -> void:
	if f.grounded:
		return
	f.velocity_y += GRAVITY * dt
	f.y += f.velocity_y * dt
	if f.y >= 0.0 and f.knocked_down and not f.bounced and f.velocity_y > 300.0:
		# Rebote al caer derribado desde muy alto: sube un poco y vuelve a caer.
		f.bounced = true
		f.y = 0.0
		f.velocity_y = -minf(f.velocity_y * 0.32, 150.0)
		burst(f.x, FLOOR - 2, "#d6c5a0", 8)
		add_effect({"type": "dust-cloud", "x": f.x, "y": FLOOR - 1.0, "size": 1.4, "life": 0.4, "max_life": 0.4, "color": "#d9cdb4"})
		screen_shake = maxf(screen_shake, 3.0)
		return
	if f.y >= 0.0:
		if f.velocity_y > 130.0:
			burst(f.x, FLOOR - 2, "#c6a37b" if f.id == "onix" else "#d6c5a0", 6)
			var heavy_fall := f.knocked_down or f.velocity_y > 420.0
			add_effect({"type": "dust-cloud", "x": f.x, "y": FLOOR - 1.0, "size": 1.6 if heavy_fall else 1.0,
				"life": 0.45 if heavy_fall else 0.3, "max_life": 0.45 if heavy_fall else 0.3, "color": "#d9cdb4"})
			if heavy_fall:
				screen_shake = maxf(screen_shake, 2.5)
		f.y = 0.0
		f.velocity_y = 0.0
		f.grounded = true
		f.juggle_count = 0
		f.air_attack_used = false
		f.bounced = false
		if f.attack_animation.begins_with("air_") and f.attack_pose > 0.0:
			# Al aterrizar se corta el ataque aéreo (se puede encadenar en el suelo).
			f.attack_pose = 0.0
			f.has_pending_attack = false
			f.attack_cooldown = minf(f.attack_cooldown, 0.05)
		if f.knocked_down:
			f.knocked_down = false
			f.getup_time = FighterAnimations.duration(FighterAnimations.get_animation(f.id, "getup")) / 60.0


# --- Golpes -----------------------------------------------------------------

## Golpe J: cadena de puños (jab → directo → gancho → uppercut).
func melee(attacker: FighterState, _defender: FighterState = null) -> void:
	request_attack(attacker, "attack")


## Golpe K: cadena de patadas (baja → media → alta → giratoria).
func kick(attacker: FighterState, _defender: FighterState = null) -> void:
	request_attack(attacker, "kick")


## Golpe I: cierra la cadena con una rama (lanzador, remate cruzado) o, sin
## cadena abierta, es el golpe fuerte suelto.
func heavy_attack(attacker: FighterState, _defender: FighterState = null) -> void:
	request_attack(attacker, "heavy")


## Punto de entrada de los golpes (J = "attack", K = "kick", I = "heavy").
## Si el luchador aún está en mitad de otro golpe, la pulsación se guarda
## (buffer de entrada) y sale sola en cuanto el golpe se pueda cancelar.
func request_attack(f: FighterState, input: String) -> void:
	if f.hurt_time > 0.0 or f.knocked_down or f.getup_time > 0.0 or f.blocking:
		return
	if not f.grounded and f.air_attack_used and (input == "attack" or input == "kick"):
		return
	if _attack_busy(f):
		f.buffered_input = input
		f.buffer_time = ComboData.BUFFER_TIME
		return
	_start_attack(f, input)


## Ocupado = aún no se puede cancelar el golpe actual: no ha golpeado todavía
## o no ha pasado su recuperación mínima (attack_cooldown de catalog.gd).
func _attack_busy(f: FighterState) -> bool:
	return f.attack_cooldown > 0.0 or f.attack_windup > 0.0 or f.has_pending_attack


func _start_attack(f: FighterState, input: String) -> void:
	f.buffered_input = ""
	f.buffer_time = 0.0
	if not f.grounded and (input == "attack" or input == "kick" or input == "low_attack"):
		if f.air_attack_used:
			return
		f.air_attack_used = true
		_command_strike(f, "air_kick" if input == "kick" else "air_punch")
		return
	match input:
		"low_attack":
			_command_strike(f, "uppercut")
			return
		"sweep":
			_command_strike(f, "sweep")
			return
		"throw":
			if can_throw(f, opponent_of(f)):
				_command_strike(f, "throw")
				return
			input = "heavy"
	if input == "heavy":
		var chain_step := f.attack_index if f.combo_timer > 0.0 else 0
		var branch := ComboData.branch_for(f.definition, chain_step)
		if chain_step >= 1 and chain_step < ComboData.chain_length(f.definition, f.chain_kind) and not branch.is_empty():
			_branch_finisher(f, chain_step, branch)
		else:
			_standalone_heavy(f)
	else:
		_chain_attack(f, "kick" if input == "kick" else "punch")


## Durante la pausa de impacto (hit stop) el combate está congelado. Antes se
## perdían las pulsaciones hechas en esos cuadros; ahora J e I van al buffer.
func _buffer_frozen_presses() -> void:
	if state != "playing":
		return
	var controlled := [0, 1] if mode == "versus" else [0]
	for index in controlled:
		var f := fighter_by_index(index)
		for action in ["attack", "kick", "heavy"]:
			if _consume_press(index, action):
				f.buffered_input = action
				f.buffer_time = ComboData.BUFFER_TIME


## Lanza los golpes guardados en el buffer cuando ya se pueden cancelar.
func _release_buffered_attacks(dt: float) -> void:
	for fighter in [player, enemy]:
		var f: FighterState = fighter
		if f.buffered_input == "":
			continue
		f.buffer_time = maxf(0.0, f.buffer_time - dt)
		if f.buffer_time <= 0.0 or f.hurt_time > 0.0 or f.knocked_down or f.getup_time > 0.0 or f.blocking:
			f.buffered_input = ""
			continue
		if not _attack_busy(f):
			_start_attack(f, f.buffered_input)


func _chain_attack(attacker: FighterState, kind: String = "punch") -> void:
	var combo_length := ComboData.chain_length(attacker.definition, kind)
	var continuing := attacker.combo_timer > 0.0 and attacker.attack_index > 0
	var combo := attacker.attack_index + 1 if continuing else 1
	if combo > combo_length:
		combo = 1
	var hit_index := combo
	var animation_name := ComboData.strike_for(kind, combo_length, hit_index)
	var strike: Dictionary = ComboData.STRIKES[animation_name]
	attacker.attack_cooldown = float(attacker.stat("attack_cooldown", 0.3))
	if strike.get("finisher", false):
		attacker.attack_cooldown *= 1.4
	var animation := FighterAnimations.get_animation(attacker.id, animation_name)
	attacker.attack_windup = FighterAnimations.first_hitbox_frame(animation) / 60.0
	attacker.attack_animation = animation_name
	attacker.attack_pose = FighterAnimations.duration(animation) / 60.0
	attacker.has_pending_attack = true
	attacker.pending_hit_index = hit_index
	attacker.pending_combo_length = combo_length
	attacker.pending_heavy = false
	attacker.pending_branch = {}
	attacker.pending_strike = animation_name
	attacker.chain_kind = kind
	attacker.attack_index = hit_index
	attacker.combo_timer = 0.9
	# Paso adelante para que la cadena no se quede corta al empujar al rival.
	var target := opponent_of(attacker)
	if absf(target.x - attacker.x) > minimum_fighter_distance(attacker, target) + 4.0:
		attacker.knockback_velocity = attacker.facing * float(strike.get("lunge", 60.0))
	queue_anim(attacker, "patada" if kind == "kick" else "golpe")
	var finisher: bool = strike.get("finisher", false)
	queue_voice(attacker, "heavy" if finisher else kind, 1.0 if finisher else (0.3 if hit_index == 1 else 0.5))


## Golpe de comando (barrida, uppercut antiaéreo, ataques aéreos, agarre).
## No sigue la cadena: después se vuelve a empezar desde el primer golpe.
func _command_strike(attacker: FighterState, animation_name: String) -> void:
	var strike := ComboData.strike_data(animation_name)
	var animation := FighterAnimations.get_animation(attacker.id, animation_name)
	attacker.attack_cooldown = float(attacker.stat("attack_cooldown", 0.3)) * (1.6 if animation_name == "throw" or animation_name == "sweep" else 1.2)
	attacker.attack_windup = FighterAnimations.first_hitbox_frame(animation) / 60.0
	attacker.attack_animation = animation_name
	attacker.attack_pose = FighterAnimations.duration(animation) / 60.0
	attacker.has_pending_attack = true
	attacker.pending_hit_index = 1
	attacker.pending_combo_length = 1 if strike.get("finisher", false) else 2
	attacker.pending_heavy = false
	attacker.pending_branch = {}
	attacker.pending_strike = animation_name
	attacker.chain_kind = String(strike.get("kind", "punch"))
	attacker.attack_index = 0
	attacker.combo_timer = 0.0
	var target := opponent_of(attacker)
	if attacker.grounded and strike.has("lunge") and absf(target.x - attacker.x) > minimum_fighter_distance(attacker, target) + 4.0:
		attacker.knockback_velocity = attacker.facing * float(strike["lunge"])
	queue_anim(attacker, "patada" if strike.get("kind", "") == "kick" else "golpe")
	var important := animation_name == "throw" or animation_name == "uppercut" or animation_name == "sweep"
	queue_voice(attacker, "heavy" if important else String(strike.get("kind", "punch")), 1.0 if important else 0.5)


## El agarre solo funciona pegado al rival, los dos en el suelo y con el rival libre.
func can_throw(f: FighterState, target: FighterState) -> bool:
	return f.grounded and target.grounded and not target.knocked_down and target.getup_time <= 0.0 \
		and target.hurt_time <= 0.0 and absf(target.x - f.x) <= minimum_fighter_distance(f, target) + ComboData.THROW_RANGE


## I en mitad de una cadena: la remata con la rama que toque (ComboData.BRANCHES).
func _branch_finisher(attacker: FighterState, chain_step: int, branch: Dictionary) -> void:
	var animation_name := "kick" if attacker.id == "brasa" else "finisher"
	var animation := FighterAnimations.get_animation(attacker.id, animation_name)
	attacker.attack_cooldown = float(attacker.stat("attack_cooldown", 0.3)) * 1.5
	attacker.attack_windup = FighterAnimations.first_hitbox_frame(animation) / 60.0
	attacker.attack_animation = animation_name
	attacker.attack_pose = FighterAnimations.duration(animation) / 60.0
	attacker.has_pending_attack = true
	attacker.pending_hit_index = chain_step + 1
	attacker.pending_combo_length = chain_step + 1
	attacker.pending_heavy = false
	attacker.pending_branch = branch
	attacker.pending_strike = ""
	attacker.attack_index = 0
	attacker.combo_timer = 0.0
	queue_anim(attacker, "patada")
	queue_voice(attacker, "heavy", 1.0)


## Golpe fuerte (tecla I sin cadena): un solo golpe con la fuerza y el empuje del
## remate del combo, pero más lento de recuperar y sin encadenar. Reinicia el combo.
func _standalone_heavy(attacker: FighterState) -> void:
	var combo_length := int(attacker.definition["combo_length"])
	var animation_name := "kick" if attacker.id == "brasa" else "finisher"
	var animation := FighterAnimations.get_animation(attacker.id, animation_name)
	attacker.attack_cooldown = maxf(HEAVY_COOLDOWN, float(attacker.stat("attack_cooldown", 0.3)) * 2.0)
	attacker.attack_windup = FighterAnimations.first_hitbox_frame(animation) / 60.0
	attacker.attack_animation = animation_name
	attacker.attack_pose = FighterAnimations.duration(animation) / 60.0
	attacker.has_pending_attack = true
	attacker.pending_hit_index = combo_length
	attacker.pending_combo_length = combo_length
	attacker.pending_heavy = true
	attacker.pending_branch = {}
	attacker.pending_strike = ""
	attacker.attack_index = 0
	attacker.combo_timer = 0.0
	queue_anim(attacker, "patada")
	queue_voice(attacker, "heavy", 0.7)


func _update_attacks(dt: float) -> void:
	_release_buffered_attacks(dt)
	for attacker in [player, enemy]:
		var a: FighterState = attacker
		if not a.has_pending_attack:
			continue
		a.attack_windup = maxf(0.0, a.attack_windup - dt)
		if a.attack_windup > 0.0:
			continue
		var target := opponent_of(a)
		if a.pending_strike == "throw":
			a.has_pending_attack = false
			a.pending_strike = ""
			_resolve_throw(a, target)
			continue
		var hit_index := a.pending_hit_index
		var combo_length := a.pending_combo_length
		var is_heavy := a.pending_heavy
		var branch := a.pending_branch
		var strike_name := a.pending_strike
		a.has_pending_attack = false
		a.pending_heavy = false
		a.pending_branch = {}
		a.pending_strike = ""
		var direction := int(signf(target.x - a.x))
		if direction == 0:
			direction = a.facing
		var distance := absf(a.x - target.x)
		var vertical_distance := absf(a.y - target.y)
		var hitbox: Dictionary = {}
		if a.attack_animation != "":
			var anim := FighterAnimations.get_animation(a.id, a.attack_animation)
			var frame := FighterAnimations.frame_at(anim, FighterAnimations.duration(anim) - a.attack_pose * 60.0)
			if frame.has("hitbox"):
				hitbox = frame["hitbox"]
		var horizontal_offset := (target.x - a.x) * direction
		var target_scale := float(target.definition["sprite_scale"])
		var attacker_scale := float(a.definition["sprite_scale"])
		var target_half_width := float(target.definition["pushbox_half_width"])
		var target_half_height := 42.0 * target_scale
		var within_hitbox := false
		if not hitbox.is_empty():
			var hx := float(hitbox["x"])
			var hy := float(hitbox["y"])
			var hw := float(hitbox["w"])
			var hh := float(hitbox["h"])
			var hitbox_center_y := a.y - (hy + hh / 2.0) * attacker_scale
			var target_center_y := target.y - 42.0
			within_hitbox = horizontal_offset + target_half_width >= hx * attacker_scale \
				and horizontal_offset - target_half_width <= (hx + hw) * attacker_scale \
				and absf(target_center_y * target_scale - hitbox_center_y) <= target_half_height + hh * attacker_scale
		var out_of_range := (not within_hitbox) if not hitbox.is_empty() else (distance > 91.0 or vertical_distance > 88.0)
		if direction != a.facing or out_of_range:
			continue

		var is_onix := a.id == "onix" and strike_name == ""
		var is_brasa_finisher := a.id == "brasa" and hit_index == 3 and strike_name == ""
		var is_finisher := hit_index == combo_length
		var damage_scale := 1.0
		var knockback := 78.0
		var hit_stop := 4.0
		var launch_y := 0.0
		var hitstun := 0.22
		var strike: Dictionary = ComboData.strike_data(strike_name)
		if not strike.is_empty():
			# Golpe de las cadenas de puños o patadas (ComboData.STRIKES).
			damage_scale = float(strike["damage"]) * ComboData.CHAIN_DAMAGE_SCALE
			knockback = float(strike.get("knockback", 60.0))
			hit_stop = float(strike.get("hit_stop", 4.0))
			launch_y = float(strike.get("launch", 0.0))
			if strike.get("finisher", false):
				# El remate usa la fuerza de remate del luchador (no se suma chain_power).
				damage_scale *= float(a.definition["finisher_damage"])
				knockback = float(a.definition["finisher_knockback"]) + float(strike.get("knockback_bonus", 0.0))
				hit_stop = maxf(hit_stop, float(a.definition["finisher_hit_stop"]))
				if strike["kind"] == "kick":
					launch_y = minf(float(a.definition.get("finisher_launch", 0.0)), -60.0)
			else:
				damage_scale *= float(a.stat("chain_power", 1.0))
			# El aturdimiento cubre la recuperación del atacante: la cadena es un combo real.
			hitstun = float(strike.get("hitstun", 0.3)) + float(a.stat("attack_cooldown", 0.3)) * 0.6
		elif not branch.is_empty():
			# Rama del árbol de combos: parte del remate del luchador y aplica sus cambios.
			damage_scale = float(a.definition["finisher_damage"]) * float(branch.get("damage", 1.0))
			knockback = float(branch.get("knockback", float(a.definition["finisher_knockback"]) + float(branch.get("knockback_bonus", 0.0))))
			hit_stop = float(branch.get("hit_stop", a.definition["finisher_hit_stop"]))
			launch_y = float(branch.get("launch", a.definition.get("finisher_launch", 0.0)))
		elif is_brasa_finisher:
			damage_scale = 1.35
			knockback = 154.0
			hit_stop = 8.0
			launch_y = -230.0
		elif is_finisher:
			damage_scale = float(a.definition["finisher_damage"])
			knockback = float(a.definition["finisher_knockback"])
			hit_stop = float(a.definition["finisher_hit_stop"])
			launch_y = float(a.definition.get("finisher_launch", 0.0))
		elif is_onix:
			damage_scale = 1.55
			knockback = 126.0
			hit_stop = 7.0
			launch_y = -115.0 if hit_index == 2 else 0.0
		if is_heavy:
			# Algo menos de daño que el remate del combo, para que encadenar siga valiendo la pena.
			damage_scale *= HEAVY_DAMAGE_FACTOR
		var awakened_bonus := 1.4 if a.awakening_time > 0.0 else 1.0
		var base := float(a.definition["damage"]) * damage_scale * awakened_bonus * a.damage_multiplier
		# Chispa en el punto real del golpe: altura de la hitbox, pegada al cuerpo del rival.
		var spark_y := FLOOR - 40.0 + target.y
		if not hitbox.is_empty():
			var hb_center := a.y - (float(hitbox["y"]) + float(hitbox["h"]) / 2.0) * attacker_scale
			spark_y = clampf(FLOOR + hb_center, FLOOR - 72.0 + target.y, FLOOR - 8.0 + target.y)
		var strike_kind := String(strike.get("kind", "kick" if a.attack_animation.contains("kick") or a.attack_animation == "finisher" else "punch"))
		var connected := hit(target, direction, roundi(base), {
			"spark_y": spark_y, "strike_kind": strike_kind,
			"knockback": knockback, "hit_stop": hit_stop, "launch_y": launch_y,
			"attacker": a.index, "sound": "heavy_hit" if hit_index >= 2 else "hit",
			"heavy": is_finisher or is_heavy,
			"melee": true,
			"hitstun": hitstun,
		})
		if not connected:
			continue
		var counter_text := "¡CONTRAATAQUE! · " if _last_hit_counter else ""
		if is_heavy:
			last_action = "¡GOLPE FUERTE!"
			last_action_time = 0.6
			continue
		a.combo = hit_index
		a.max_combo = maxi(a.max_combo, hit_index)
		if a == player:
			highest_combo = maxi(highest_combo, hit_index)
		if not branch.is_empty():
			last_action = String(branch.get("text", a.definition["finisher_text"]))
		elif not strike.is_empty():
			if strike.get("finisher", false):
				last_action = String(strike["text"]) if strike["kind"] == "punch" else String(a.definition["finisher_text"])
			elif a.combo_hits > 1:
				last_action = "%d GOLPES · %s" % [a.combo_hits, String(strike["text"]).trim_prefix("¡").trim_suffix("!")]
			else:
				last_action = String(strike["text"])
		elif is_brasa_finisher:
			last_action = "¡PATADA ALTA!"
		elif is_onix and hit_index == 2:
			last_action = "¡GOLPE DE ROCA!"
		elif is_finisher:
			last_action = String(a.definition["finisher_text"])
		elif hit_index > 1:
			last_action = "%d GOLPES · COMBO" % hit_index
		else:
			last_action = "¡IMPACTO!"
		last_action = counter_text + last_action
		last_action_time = 0.6


## Agarre: no se puede bloquear. Si el rival ya no está a tiro (saltó, se alejó o
## lo golpearon antes), falla y deja al atacante vendido un momento.
func _resolve_throw(a: FighterState, target: FighterState) -> void:
	if not can_throw(a, target) or target.decoy_time > 0.0:
		last_action = "AGARRE FALLIDO"
		last_action_time = 0.5
		a.attack_cooldown = maxf(a.attack_cooldown, 0.35)
		return
	var strike: Dictionary = ComboData.COMMAND_STRIKES["throw"]
	var awakened_bonus := 1.4 if a.awakening_time > 0.0 else 1.0
	var base := float(a.definition["damage"]) * float(strike["damage"]) * awakened_bonus * a.damage_multiplier
	var direction := a.facing
	var connected := hit(target, direction, roundi(base), {
		"knockback": float(strike["knockback"]), "hit_stop": float(strike["hit_stop"]), "launch_y": float(strike["launch"]),
		"attacker": a.index, "sound": "heavy_hit", "heavy": true, "unblockable": true, "hitstun": float(strike["hitstun"]),
	})
	if connected:
		burst(target.x, FLOOR - 40.0 + target.y, "#ffffff", 10)
		screen_shake = maxf(screen_shake, 5.0)
		last_action = String(strike["text"])
		last_action_time = 0.8


# --- Técnicas ---------------------------------------------------------------

func use_technique(attacker: FighterState, _defender: FighterState = null) -> void:
	if attacker.special_cooldown > 0.0 or attacker.hurt_time > 0.0 or attacker.knocked_down \
			or attacker.getup_time > 0.0 or attacker.blocking:
		return
	attacker.special_cooldown = float(attacker.definition["cooldown"])
	queue_audio("special")
	attacker.attack_pose = 0.26
	attacker.attack_animation = ""
	attacker.meter = maxf(0.0, attacker.meter - (12.0 if attacker.awakening_time > 0.0 else 0.0))
	var move := "arc-lunge" if attacker.id == "volt" and attacker.awakening_time > 0.0 else String(attacker.definition["special"])
	if move != "volt-step":
		attacker.special_back = false
	attacker.special_charge = special_charge_duration(move)
	attacker.pending_special = move
	attacker.attack_pose = attacker.special_charge
	attacker.attack_animation = "charge"
	attacker.has_pending_attack = false
	attacker.attack_windup = 0.0
	if move == "solar-beam":
		last_action = "CARGANDO HILO SOLAR…"
	elif move == "shard-fan":
		last_action = "CARGANDO FRAGMENTOS…"
	else:
		last_action = "CARGANDO %s…" % String(attacker.definition["technique"]).to_upper()
	last_action_time = attacker.special_charge


func special_charge_duration(move: String) -> float:
	if move == "solar-beam":
		return SOLAR_CHARGE_TIME
	if move == "shard-fan":
		return SHARD_CHARGE_TIME
	return float(SPECIAL_CHARGE_FRAMES.get(move, 1)) / 60.0


func launch_projectile(attacker: FighterState, speed: float, damage: float, type: String, delay: float = 0.0) -> Dictionary:
	var awakened := 1.3 if attacker.awakening_time > 0.0 else 1.0
	var projectile := {
		"x": attacker.x + attacker.facing * 14.0,
		"y": FLOOR - 40.0 + attacker.y,
		"velocity_x": attacker.facing * speed,
		"velocity_y": 0.0,
		"owner": attacker.index,
		"target": 1 - attacker.index,
		"damage": roundi(damage * attacker.damage_multiplier * awakened),
		"life": 1.7,
		"delay": delay,
		"type": type,
		"color": String(attacker.definition["accent"]),
		"gravity": 0.0,
	}
	projectiles.append(projectile)
	return projectile


func _update_specials(dt: float) -> void:
	for fighter in [player, enemy]:
		var f: FighterState = fighter
		if f.special_charge <= 0.0:
			continue
		var target := opponent_of(f)
		var move := f.pending_special if f.pending_special != "" else String(f.definition["special"])
		var accent := String(f.definition["accent"])
		f.running = false
		var charge_progress := 1.0 - f.special_charge / special_charge_duration(move)
		var particles_per_frame := mini(5, 1 + int(floorf(charge_progress * (4.0 if move == "solar-beam" else 3.0))))
		burst(f.x + f.facing * 17.0, FLOOR - (46.0 if move == "solar-beam" else 38.0) + f.y, accent, particles_per_frame)
		f.special_charge = maxf(0.0, f.special_charge - dt)
		if f.special_charge > 0.0:
			continue
		f.pending_special = ""
		f.special_pose_time = FighterAnimations.duration(FighterAnimations.get_animation(f.id, "special")) / 60.0
		_release_special(f, target, move, accent)


func _release_special(f: FighterState, target: FighterState, move: String, accent: String) -> void:
	match move:
		"solar-beam":
			var distance := (target.x - f.x) * f.facing
			add_effect({
				"type": "solar-beam", "x": f.x + f.facing * 14.0,
				"end_x": f.x + f.facing * minf(maxf(distance, 78.0), 250.0),
				"y": FLOOR - 43.0 + f.y, "facing": f.facing, "life": 0.32, "max_life": 0.32, "color": accent,
			})
			if distance > minimum_fighter_distance(f, target) and distance < 260.0 and absf(target.y - f.y) < 68.0:
				hit(target, f.facing, roundi(25.0 * f.damage_multiplier), {"knockback": 430.0, "hit_stop": 10.0, "white_flash": true, "sound": "heavy_hit"})
				burst(target.x, FLOOR - 38.0 + target.y, "#ffffff", 10)
			screen_shake = maxf(screen_shake, 7.0)
			last_action = "¡HILO SOLAR!"
			last_action_time = 0.9
		"shard-fan":
			var shard_speeds := [174.0, 218.0, 262.0]
			var vertical_speeds := [-30.0, -94.0, -30.0]
			for i in range(3):
				var shard := launch_projectile(f, shard_speeds[i], 9.0, "rock-shard", i * 0.075)
				shard["velocity_y"] = vertical_speeds[i]
				shard["gravity"] = 260.0
				shard["hit_stop"] = 3.0
				shard["knockback"] = 34.0
			add_effect({"type": "shard-burst", "x": f.x + f.facing * 20.0, "y": FLOOR - 43.0 + f.y, "facing": f.facing, "life": 0.42, "max_life": 0.42, "color": accent})
			last_action = "¡FRAGMENTO ESTELAR!"
			last_action_time = 0.9
		"volt-step":
			_release_volt_step(f, target, accent)
		"arc-lunge":
			var start_x := f.x
			var distance := (target.x - start_x) * f.facing
			var travel := minf(maxf(distance - minimum_fighter_distance(f, target), 0.0), 122.0)
			f.x = clamp_x(start_x + f.facing * travel)
			queue_anim(f, "dash", {"desde": start_x})
			for trail_offset in [0.0, 20.0, 40.0]:
				add_effect({"type": "volt-afterimage", "x": start_x + f.facing * trail_offset, "y": FLOOR - 38.0 + f.y, "life": 0.24, "max_life": 0.24, "color": accent})
			# También conecta pegado al rival (antes fallaba a quemarropa).
			var can_reach := distance >= minimum_fighter_distance(f, target) - 10.0 and distance < 206.0 and absf(target.y - f.y) < 76.0
			if can_reach:
				hit(target, f.facing, roundi(27.0 * f.damage_multiplier), {"knockback": 238.0, "hit_stop": 9.0, "white_flash": true, "attacker": f.index, "sound": "heavy_hit"})
				burst(target.x, FLOOR - 39.0 + target.y, "#eaffff", 12)
				add_effect({"type": "volt-impact", "x": target.x, "y": FLOOR - 38.0 + target.y, "life": 0.32, "max_life": 0.32, "color": accent})
			screen_shake = maxf(screen_shake, 5.2)
			last_action = "¡ARCO DE RUPTURA!"
			last_action_time = 0.9
		"marea-guard":
			f.guard_time = 2.8
			add_effect({"type": "marea-guard", "x": f.x, "y": FLOOR - 37.0 + f.y, "life": 0.65, "max_life": 0.65, "color": accent})
			for i in range(8):
				var angle := TAU * i / 8.0
				burst(f.x + cos(angle) * 24.0, FLOOR - 37.0 + f.y + sin(angle) * 17.0, accent, 2)
			last_action = "¡MURO DE NÁCAR!"
			last_action_time = 0.8
		"prism-lance":
			var distance := (target.x - f.x) * f.facing
			var end_x := f.x + f.facing * minf(maxf(distance, 70.0), 286.0)
			add_effect({"type": "prism-lance", "x": f.x + f.facing * 15.0, "end_x": end_x, "y": FLOOR - 44.0 + f.y, "life": 0.3, "max_life": 0.3, "color": accent})
			if distance > minimum_fighter_distance(f, target) and distance < 292.0 and absf(target.y - f.y) < 72.0:
				hit(target, f.facing, roundi(22.0 * f.damage_multiplier), {"knockback": 184.0, "hit_stop": 7.0, "white_flash": true, "attacker": f.index})
			for i in range(5):
				burst(f.x + f.facing * (32.0 + i * 18.0), FLOOR - 43.0 + f.y, "#ffffff" if i % 2 == 1 else accent, 2)
			screen_shake = maxf(screen_shake, 4.5)
			last_action = "¡LANZA PRISMÁTICA!"
			last_action_time = 0.8
		"mirror-step":
			var old_x := f.x
			var distance := absf(target.x - old_x)
			f.decoy_time = 2.5
			f.x = clamp_x(target.x - f.facing * minimum_fighter_distance(f, target))
			burst(old_x, FLOOR - 38.0 + f.y, accent, 8)
			burst(f.x, FLOOR - 38.0 + f.y, "#fff0fa", 8)
			add_effect({"type": "mirror-step", "x": old_x, "end_x": f.x, "y": FLOOR - 38.0 + f.y, "life": 0.34, "max_life": 0.34, "color": accent})
			if distance < 220.0 and absf(target.y - f.y) < 72.0:
				hit(target, f.facing, roundi(16.0 * f.damage_multiplier), {"knockback": 116.0, "hit_stop": 5.0, "attacker": f.index})
			last_action = "¡DOBLE REFLEJO!"
			last_action_time = 0.8
		"fault-ring":
			f.armor_time = 0.95
			add_effect({"type": "fault-ring", "x": f.x, "y": FLOOR - 3.0, "life": 0.52, "max_life": 0.52, "color": accent})
			for i in range(10):
				burst(f.x + (rng.randf() - 0.5) * 38.0, FLOOR - 3.0, accent, 2)
			var distance := absf(target.x - f.x)
			if distance < 150.0 and absf(target.y - f.y) < 76.0:
				hit(target, f.facing, roundi(24.0 * f.damage_multiplier), {"knockback": 208.0, "hit_stop": 9.0, "launch_y": -74.0, "attacker": f.index, "sound": "heavy_hit"})
			screen_shake = maxf(screen_shake, 6.0)
			last_action = "¡ANILLO DE FALLA!"
			last_action_time = 0.9
		"luma-heal":
			var recovered := mini(28, MAX_HEALTH - f.health)
			f.health += recovered
			f.meter = minf(100.0, f.meter + 20.0)
			f.hit_flash = 0.0
			f.hurt_time = 0.0
			f.guard_time = 0.5
			for i in range(3):
				add_effect({"type": "luma-pulse", "x": f.x, "y": FLOOR - 36.0 + f.y, "ring": i, "life": 0.55 + i * 0.12, "max_life": 0.55 + i * 0.12, "color": accent})
			burst(f.x, FLOOR - 39.0 + f.y, "#eaffd1", 18)
			last_action = "¡SUTURA DE LUZ! +%d" % recovered
			last_action_time = 0.9
		_:
			push_error("Técnica desconocida: %s" % move)
	queue_voice(f, "special", 1.0)


## Salto de umbral (Volt):
##   hacia delante: embestida eléctrica que frena justo delante del rival (nunca lo
##   atraviesa) y le golpea si está a tiro, también pegado a él;
##   manteniendo atrás: esquiva hacia atrás; el primer golpe que le llegue en ese
##   instante lo atraviesa sin hacer daño.
func _release_volt_step(f: FighterState, target: FighterState, accent: String) -> void:
	var start_x := f.x
	var minimum := minimum_fighter_distance(f, target)
	var distance := (target.x - start_x) * f.facing
	if f.special_back:
		f.special_back = false
		f.x = clamp_x(start_x - f.facing * VOLT_STEP_BACK)
		f.phase_time = maxf(f.phase_time, VOLT_DODGE_TIME)
		f.knockback_velocity = 0.0
		queue_anim(f, "dash", {"desde": start_x})
		for trail_offset in [0.0, 15.0, 30.0]:
			add_effect({"type": "volt-afterimage", "x": start_x - f.facing * trail_offset, "y": FLOOR - 38.0 + f.y, "life": 0.2, "max_life": 0.2, "color": accent})
		last_action = "¡SALTO ATRÁS!"
		last_action_time = 0.6
		return
	var in_front := distance > -8.0
	var travel := VOLT_STEP_RANGE
	if in_front and distance < VOLT_STEP_RANGE + minimum:
		travel = clampf(distance - minimum, 0.0, VOLT_STEP_RANGE)
	f.x = clamp_x(start_x + f.facing * travel)
	queue_anim(f, "dash", {"desde": start_x})
	for trail_offset in [0.0, 15.0, 30.0]:
		add_effect({"type": "volt-afterimage", "x": start_x + f.facing * minf(trail_offset, travel), "y": FLOOR - 38.0 + f.y, "life": 0.2, "max_life": 0.2, "color": accent})
	if in_front and distance >= minimum - 10.0 and distance < VOLT_STEP_HIT_RANGE and absf(target.y - f.y) < 70.0:
		hit(target, f.facing, roundi(19.0 * f.damage_multiplier), {"knockback": 156.0, "hit_stop": 6.0, "attacker": f.index})
	screen_shake = maxf(screen_shake, 3.8)
	last_action = "¡PASO RELÁMPAGO!"
	last_action_time = 0.8


func _update_projectiles(dt: float) -> void:
	var alive: Array = []
	for projectile in projectiles:
		var p: Dictionary = projectile
		if float(p["delay"]) > 0.0:
			p["delay"] = float(p["delay"]) - dt
			if float(p["delay"]) > 0.0:
				alive.append(p)
				continue
		p["x"] = float(p["x"]) + float(p["velocity_x"]) * dt
		p["y"] = float(p["y"]) + float(p["velocity_y"]) * dt
		p["velocity_y"] = float(p["velocity_y"]) + float(p["gravity"]) * dt
		p["life"] = float(p["life"]) - dt
		var px := float(p["x"])
		var py := float(p["y"])
		if float(p["life"]) <= 0.0 or px < 0.0 or px > WIDTH:
			continue
		if p["type"] == "rock-shard" and py >= FLOOR - 4.0:
			burst(px, FLOOR - 1.0, "#c6a37b", 5)
			add_effect({"type": "dust", "x": px, "y": FLOOR - 2.0, "life": 0.28, "max_life": 0.28, "color": "#c6a37b"})
			continue
		var target := fighter_by_index(int(p["target"]))
		var vertical_distance := absf((FLOOR - 32.0 + target.y) - py)
		if absf(px - target.x) < 22.0 and vertical_distance < 37.0:
			hit(target, int(signf(float(p["velocity_x"]))), int(p["damage"]), {
				"knockback": float(p.get("knockback", 66.0)), "hit_stop": float(p.get("hit_stop", 4.0)), "attacker": int(p["owner"]),
			})
			add_effect({"type": "impact", "x": px, "y": py, "life": 0.24, "max_life": 0.24, "color": p["color"]})
			continue
		alive.append(p)
	projectiles = alive


## Aplica un impacto. Devuelve false si fue esquivado, bloqueado o absorbido.
func hit(target: FighterState, direction: int, damage: int, options: Dictionary = {}) -> bool:
	var accent := String(target.definition["accent"])
	var hit_stop_option := float(options.get("hit_stop", -1.0))
	# Mientras se levanta del suelo no se le puede golpear (como StateKnockedDown).
	if target.getup_time > 0.0:
		return false
	if target.id == "volt" and target.phase_time > 0.0:
		target.phase_time = 0.0
		add_effect({"type": "volt-phase", "x": target.x, "y": FLOOR - 38.0 + target.y, "life": 0.28, "max_life": 0.28, "color": accent})
		burst(target.x, FLOOR - 38.0 + target.y, "#efffff", 8)
		last_action = "¡ENFOQUE VECTORIAL!" if target.awakening_time > 0.0 else "¡ESQUIVA RELÁMPAGO!"
		last_action_time = 0.7
		queue_audio("block")
		return false
	if target.decoy_time > 0.0:
		target.decoy_time = 0.0
		add_effect({"type": "impact", "x": target.x, "y": FLOOR - 40.0, "life": 0.28, "max_life": 0.28, "color": accent})
		last_action = "EL SEÑUELO ABSORBE EL GOLPE"
		last_action_time = 0.65
		return false
	_last_hit_counter = false
	if target.blocking and target.guard_time > 0.0 and not options.get("unblockable", false):
		target.guard_time = 0.06
		queue_anim(target, "bloqueo")
		hit_stop_frames = maxf(hit_stop_frames, hit_stop_option if hit_stop_option >= 0.0 else 3.0)
		add_effect({"type": "armor", "x": target.x, "y": FLOOR - 38.0 + target.y, "life": 0.16, "max_life": 0.16, "color": target.definition["trim"]})
		add_effect({"type": "spark-block", "x": target.x - direction * 14.0, "y": float(options.get("spark_y", FLOOR - 42.0 + target.y)),
			"dir": -direction, "life": 0.18, "max_life": 0.18, "color": "#9fe8ff"})
		queue_audio("block")
		# Guardia firme (como StateBlockingOnFloor): el golpe cuerpo a cuerpo bloqueado
		# deja al atacante aturdido un momento y lo empuja hacia atrás, sin daño.
		var blocked_index := int(options.get("attacker", -1))
		if options.get("melee", false) and blocked_index >= 0:
			var blocked := fighter_by_index(blocked_index)
			var stun := ComboData.GUARD_STUN_HEAVY if options.get("heavy", false) else ComboData.GUARD_STUN_LIGHT
			blocked.hurt_time = maxf(blocked.hurt_time, stun)
			blocked.hit_direction = -direction
			blocked.knockback_velocity = -direction * ComboData.GUARD_PUSHBACK
			blocked.attack_pose = 0.0
			blocked.has_pending_attack = false
			blocked.buffered_input = ""
			blocked.attack_index = 0
			blocked.combo_timer = 0.0
			last_action = "¡GUARDIA FIRME!"
			last_action_time = 0.6
		return false
	var onix_armor := target.id == "onix" and target.special_charge > 0.0 and damage <= 12
	var pedernal_armor := target.id == "pedernal" and (target.special_charge > 0.0 or target.armor_time > 0.0) and damage <= 16
	if onix_armor or pedernal_armor:
		armor_flash = 0.12
		hit_stop_frames = maxf(hit_stop_frames, hit_stop_option if hit_stop_option >= 0.0 else 3.0)
		add_effect({"type": "armor", "x": target.x, "y": FLOOR - 38.0 + target.y, "life": 0.18, "max_life": 0.18, "color": "#b8bec8"})
		if onix_armor:
			queue_audio("block")
			return false
	var mitigation := (0.36 if target.guard_time > 0.0 else 1.0) * (0.2 if pedernal_armor else 1.0)
	var defense := float(target.definition.get("defense", 1.0))
	# Contador de combo: el golpe suma si el rival aún no se había recuperado.
	var combo_attacker_index := int(options.get("attacker", -1))
	var combo_scale := 1.0
	if combo_attacker_index >= 0 and combo_attacker_index != target.index:
		var combo_owner := fighter_by_index(combo_attacker_index)
		var still_stunned := target.hurt_time > 0.0 or target.knocked_down
		combo_owner.combo_hits = combo_owner.combo_hits + 1 if still_stunned and combo_owner.combo_hits > 0 else 1
		if combo_owner.combo_hits == 1:
			combo_owner.combo_damage = 0
		combo_scale = ComboData.proration(combo_owner.combo_hits)
		if not _first_hit_done and mode != "training":
			_first_hit_done = true
			callouts.append({"text": "¡PRIMER GOLPE!", "color": "#ffd36e"})
		match combo_owner.combo_hits:
			5:
				callouts.append({"text": "¡GRAN COMBO!", "color": "#ffb347"})
			8:
				callouts.append({"text": "¡COMBO BRUTAL!", "color": "#ff6a3d"})
			12:
				callouts.append({"text": "¡COMBO LEGENDARIO!", "color": "#ff3df0"})
		combo_owner.combo_display = ComboData.COMBO_DISPLAY_TIME
	# Contraataque: el rival estaba preparando su propio golpe cuerpo a cuerpo.
	var counter_hit := combo_attacker_index >= 0 and target.has_pending_attack and target.attack_windup > 0.0 \
		and not (target.hurt_time > 0.0 or target.knocked_down)
	if counter_hit:
		combo_scale *= ComboData.COUNTER_DAMAGE
		_last_hit_counter = true
		queue_vfx("shock", target.x, FLOOR - 38.0 + target.y, 0.7, "#ffe066")
		add_effect({"type": "impact", "x": target.x, "y": FLOOR - 42.0 + target.y, "life": 0.3, "max_life": 0.3, "color": "#ffe066"})
	var received := maxi(1, roundi(damage * DAMAGE_SCALE * mitigation * combo_scale / defense))
	if combo_attacker_index >= 0 and combo_attacker_index != target.index:
		var dealer := fighter_by_index(combo_attacker_index)
		dealer.combo_damage += mini(received, target.health)
		if dealer == player:
			highest_combo = maxi(highest_combo, dealer.combo_hits)
	target.health = maxi(0, target.health - received)
	target.meter = minf(100.0, target.meter + received * 1.25)
	target.hit_flash = 0.16
	target.white_flash = 0.12 if options.get("white_flash", false) else 0.0
	target.hurt_time = float(options.get("hitstun", 0.22)) + (ComboData.COUNTER_HITSTUN if counter_hit else 0.0)
	target.attack_pose = 0.0
	target.attack_windup = 0.0
	target.has_pending_attack = false
	target.attack_index = 0
	target.combo_timer = 0.0
	target.hit_direction = direction
	target.knockback_velocity = direction * float(options.get("knockback", 76.0))
	queue_audio(String(options.get("sound", "hit")))
	var heavy_hit: bool = options.get("heavy", false) or hit_stop_option >= 7.0
	queue_anim(target, "golpe_recibido", {"fuerza": 1.5 if heavy_hit else 1.0})
	if target.health > 0:
		queue_voice(target, "hurt", 0.9 if heavy_hit else 0.35)
	var launch_y := float(options.get("launch_y", 0.0))
	var airborne_before := not target.grounded
	if airborne_before:
		target.juggle_count += 1
	if launch_y != 0.0:
		# Malabares: cada golpe en el aire lanza menos, hasta que el rival cae sin remedio.
		var juggle_factor := maxf(0.0, 1.0 - target.juggle_count * 0.22) if airborne_before else 1.0
		target.velocity_y = minf(target.velocity_y, launch_y * juggle_factor) if airborne_before else launch_y
		target.grounded = false
		target.knocked_down = true
		target.knockdown_time = 0.0
	elif airborne_before and target.knocked_down:
		# Golpe a un rival que ya está en el aire: lo mantiene arriba un poco (malabar).
		if target.juggle_count <= ComboData.MAX_JUGGLE:
			target.velocity_y = minf(target.velocity_y, -150.0 + target.juggle_count * 25.0)
	elif not target.grounded and not target.knocked_down:
		# Golpeado en el aire (como StateDamagedOnAir): pierde el control, cae y
		# queda derribado al tocar el suelo.
		target.velocity_y = minf(target.velocity_y, -80.0)
		target.knocked_down = true
		target.knockdown_time = 0.0
	burst(target.x, FLOOR - 36.0 + target.y, "#ff382f" if target.id == "brasa" else accent, 7)
	_add_hit_spark(target, direction, options, heavy_hit or launch_y != 0.0)
	var attacker_index := int(options.get("attacker", -1))
	var attacker: FighterState = null
	if attacker_index >= 0:
		attacker = fighter_by_index(attacker_index)
	if attacker and attacker.id == "brasa":
		add_effect({"type": "hit-spark", "x": target.x, "y": FLOOR - 38.0 + target.y, "life": 0.08, "max_life": 0.08, "color": "#fff3a6"})
	if target.id == "onix":
		burst(target.x, FLOOR - 30.0 + target.y, "#d4c2a0", 5)
	if target.id == "marea" and target.guard_time > 0.0 and attacker:
		attacker.health = maxi(0, attacker.health - 3)
		attacker.hit_flash = 0.12
		burst(attacker.x, FLOOR - 35.0 + attacker.y, accent, 7)
		add_effect({"type": "marea-counter", "x": attacker.x, "y": FLOOR - 36.0 + attacker.y, "life": 0.3, "max_life": 0.3, "color": accent})
		last_action = "¡CONTRAOLA!"
		last_action_time = 0.6
	# Golpe pesado (remate, golpe fuerte, técnica que lanza): onda expansiva en pantalla.
	# 1.0 = los más brutales (con "impact frame"), 0.7 = pesados normales.
	if options.get("heavy", false) or hit_stop_option >= 7.0 or launch_y != 0.0:
		var power := 1.0 if (hit_stop_option >= 8.0 or launch_y <= -150.0) else 0.7
		var energy := String(attacker.definition["accent"]) if attacker else accent
		queue_vfx("shock", target.x, FLOOR - 38.0 + target.y, power, energy)
	var shake := 2.5
	if hit_stop_option >= 8.0:
		shake = 7.0
	elif target.id == "onix":
		shake = 4.6
	screen_shake = maxf(screen_shake, shake)
	var default_stop := 6.0 if target.id == "onix" else 4.0
	hit_stop_frames = maxf(hit_stop_frames, hit_stop_option if hit_stop_option >= 0.0 else default_stop)
	if target.definition["special"] == "shard-fan" and target.special_charge > 0.0 and damage > 12:
		target.special_charge = 0.0
	return true


func awaken(f: FighterState, unlocked: bool) -> bool:
	if not unlocked or f.meter < 100.0 or f.awakening_time > 0.0:
		return false
	f.meter = 0.0
	f.awakening_time = 8.0
	var accent := String(f.definition["accent"])
	if f.id == "volt":
		f.phase_time = 0.65
		add_effect({"type": "volt-transform", "x": f.x, "y": FLOOR - 38.0 + f.y, "life": 0.9, "max_life": 0.9, "color": accent})
	f.attack_cooldown = 0.0
	burst(f.x, FLOOR - 42.0 + f.y, accent, 18)
	queue_vfx("awaken", f.x, FLOOR - 42.0 + f.y, 1.0, accent)
	screen_shake = 6.0
	last_action = "%s · DESPERTAR" % String(f.definition["awakening"]).to_upper()
	last_action_time = 1.7
	queue_audio("awaken")
	queue_voice(f, "awaken", 1.0)
	return true


# --- Partículas y efectos ---------------------------------------------------

## Chispa de impacto según el golpe: estrella para el puño, media luna para la
## patada y estallido con anillo para los golpes pesados (remates, agarres, lanzadores).
func _add_hit_spark(target: FighterState, direction: int, options: Dictionary, heavy: bool) -> void:
	var attacker_index := int(options.get("attacker", -1))
	var color := "#fff3a6"
	if attacker_index >= 0:
		color = String(fighter_by_index(attacker_index).definition["accent"])
	var kind := String(options.get("strike_kind", "punch"))
	var spark_type := "spark-heavy" if heavy else ("spark-kick" if kind == "kick" else "spark-punch")
	var life := 0.28 if heavy else (0.2 if kind == "kick" else 0.15)
	add_effect({
		"type": spark_type, "x": target.x - direction * 10.0, "y": float(options.get("spark_y", FLOOR - 40.0 + target.y)),
		"dir": direction, "life": life, "max_life": life, "color": color,
	})


func burst(x: float, y: float, color: String, count: int) -> void:
	for i in range(count):
		var angle := rng.randf() * TAU
		var speed := 25.0 + rng.randf() * 105.0
		particles.append({
			"x": roundf(x), "y": roundf(y),
			"velocity_x": cos(angle) * speed, "velocity_y": sin(angle) * speed,
			"life": 0.18 + rng.randf() * 0.28, "max_life": 0.46, "color": color,
		})


func add_effect(effect: Dictionary) -> void:
	if not effect.has("max_life"):
		effect["max_life"] = effect["life"]
	effects.append(effect)


func _update_particles(dt: float) -> void:
	var alive: Array = []
	for particle in particles:
		var p: Dictionary = particle
		p["x"] = float(p["x"]) + float(p["velocity_x"]) * dt
		p["y"] = float(p["y"]) + float(p["velocity_y"]) * dt
		p["velocity_y"] = float(p["velocity_y"]) + 65.0 * dt
		p["life"] = float(p["life"]) - dt
		if float(p["life"]) > 0.0:
			alive.append(p)
	particles = alive


func _update_effects(dt: float) -> void:
	var alive: Array = []
	for effect in effects:
		var e: Dictionary = effect
		e["life"] = float(e["life"]) - dt
		if e["type"] == "solar-beam" and float(e["life"]) <= 0.12 and not e.get("sparked", false):
			burst(float(e["end_x"]), float(e["y"]), String(e["color"]), 12)
			e["sparked"] = true
		if float(e["life"]) > 0.0:
			alive.append(e)
	effects = alive


func _keep_apart() -> void:
	player.x = clamp_x(player.x)
	enemy.x = clamp_x(enemy.x)
	if absf(player.y - enemy.y) >= 52.0:
		return  # un salto alto permite cruzar por encima del rival
	var distance := enemy.x - player.x
	var minimum := minimum_fighter_distance(player, enemy)
	if absf(distance) >= minimum:
		return
	var direction := 1 if distance >= 0.0 else -1
	var overlap := minimum - absf(distance)
	var left_fighter := player if direction > 0 else enemy
	var right_fighter := enemy if direction > 0 else player
	var left_shift := minf(overlap / 2.0, left_fighter.x - ARENA_LEFT)
	var right_shift := minf(overlap / 2.0, ARENA_RIGHT - right_fighter.x)
	left_fighter.x -= left_shift
	right_fighter.x += right_shift
	overlap -= left_shift + right_shift
	if overlap > 0.0:
		var extra_left := minf(overlap, left_fighter.x - ARENA_LEFT)
		left_fighter.x -= extra_left
		right_fighter.x += minf(overlap - extra_left, ARENA_RIGHT - right_fighter.x)
	if left_fighter.knockback_velocity > 0.0:
		left_fighter.knockback_velocity = 0.0
	if right_fighter.knockback_velocity < 0.0:
		right_fighter.knockback_velocity = 0.0


func _face_opponents() -> void:
	var direction := 1 if enemy.x >= player.x else -1
	player.facing = direction
	enemy.facing = -direction


func clamp_x(value: float) -> float:
	return clampf(value, ARENA_LEFT, ARENA_RIGHT)


## Nombre del ganador del combate o de la ronda ("" si hay empate o sigue).
func winner_name() -> String:
	if state == "finished":
		if player_round_wins == enemy_round_wins:
			return ""
		return player.display_name() if player_round_wins > enemy_round_wins else enemy.display_name()
	if enemy.health <= 0:
		return player.display_name()
	if player.health <= 0:
		return enemy.display_name()
	return ""


## 0 si gana el jugador 1, 1 si gana el rival, -1 si hay empate.
func winner_index() -> int:
	if player_round_wins == enemy_round_wins:
		return -1
	return 0 if player_round_wins > enemy_round_wins else 1


func stage() -> Dictionary:
	return Catalog.stage(stage_id)
