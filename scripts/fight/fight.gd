extends Node2D
## Escena de combate: conecta CombatSim con la arena, la cámara, el HUD, la
## pausa y la pantalla de resultado. La lógica corre a 60 cuadros fijos por
## segundo en _physics_process (Proyecto > Física > Ticks por segundo = 60).

const SCREEN_CENTER := Vector2(480, 270)

@onready var arena: ArenaView = %Arena
@onready var camera: Camera2D = %Camera
@onready var hud: FightHud = %Hud
@onready var pause_menu: PauseMenu = %PauseMenu
@onready var result_panel: ResultPanel = %ResultPanel
@onready var screen_fx: ScreenFx = %ScreenFx

var sim: CombatSim
var controls := PlayerInput.new()
var _running := false
var _sequence := false
var _zoom := 1.0
var _vs_shown := false
var _vs_layer: CanvasLayer


func _ready() -> void:
	sim = CombatSim.new(controls)
	sim.configure(Router.p1_id, Router.p2_id, Router.stage_id, Router.difficulty_id, Router.sim_mode())
	_apply_awakenings()
	arena.sim = sim
	arena.show_hitboxes = Router.mode == "training" and SaveData.show_hitboxes
	sim.round_finished.connect(_on_round_finished)
	pause_menu.resume_requested.connect(_on_resume)
	pause_menu.restart_requested.connect(func() -> void: Router.goto("fight"))
	pause_menu.quit_requested.connect(func() -> void: Router.goto("menu"))
	Sfx.play_music("battle")
	sim.start()
	hud.setup(sim)
	_round_intro()


func _apply_awakenings() -> void:
	var p1_unlocked := SaveData.is_unlocked(sim.player.id)
	var p2_unlocked := SaveData.is_unlocked(sim.enemy.id)
	match Router.mode:
		"training":
			sim.player.awakening_available = true
			sim.enemy.awakening_available = false
		"arcade":
			sim.player.awakening_available = p1_unlocked
			# los dos últimos rivales del arcade siempre pueden despertar
			sim.enemy.awakening_available = Router.arcade_index >= Router.arcade_total() - 2
		_:
			sim.player.awakening_available = p1_unlocked
			sim.enemy.awakening_available = p2_unlocked


func _round_intro() -> void:
	screen_fx.clear()
	_sequence = true
	_running = false
	sim.state = "ready"
	# Presentación «VS» antes del primer asalto (no en entrenamiento).
	if not _vs_shown and Router.mode != "training":
		_vs_shown = true
		_vs_layer = CanvasLayer.new()
		_vs_layer.layer = 40
		add_child(_vs_layer)
		var splash := VsSplash.new()
		_vs_layer.add_child(splash)
		await splash.play(sim, SaveData.skip_intro)
		_vs_layer.queue_free()
	if Router.mode == "training":
		hud.announce("ENTRENAMIENTO", UiKit.ACCENT, 0.6)
		await get_tree().create_timer(0.7).timeout
	else:
		var short := SaveData.skip_intro
		var title := "RONDA FINAL" if sim.round_number >= 3 else "RONDA %d" % sim.round_number
		hud.announce(title, Color.WHITE, 0.35 if short else 0.75)
		Sfx.play("announce")
		# Frase de presentación: el J1 en la primera ronda y su rival en la segunda.
		if not short and sim.round_number <= 2:
			var speaker := sim.player if sim.round_number == 1 else sim.enemy
			Sfx.play_voice(speaker.index, speaker.id, "intro", 0.15)
		await get_tree().create_timer(0.55 if short else 1.1).timeout
		hud.announce("¡PELEA!", UiKit.GOLD, 0.35)
		Sfx.play("confirm")
	controls.clear_pressed()
	sim.state = "playing"
	_running = true
	_sequence = false


func _physics_process(delta: float) -> void:
	if _running:
		controls.poll()
		sim.update(delta)
		for kind in sim.consume_audio_events():
			var key := String(kind)
			if key.begins_with("voice|"):
				Sfx.play_voice_event(key)
			else:
				Sfx.play(key, 0.07 if key.contains("hit") or key == "block" else 0.0)
		_play_vfx_events()
		for callout in sim.consume_callouts():
			var c: Dictionary = callout
			hud.announce(String(c["text"]), Color(String(c["color"])), 0.3)
	_update_camera(delta)


## Pasa los golpes pesados, despertares y K.O. de la simulación al shader de pantalla.
func _play_vfx_events() -> void:
	for event in sim.consume_vfx_events():
		var e: Dictionary = event
		var uv := _arena_to_screen_uv(float(e["x"]), float(e["y"]))
		var color := Catalog.color(String(e["color"]))
		var strength := float(e["strength"])
		match String(e["type"]):
			"shock":
				screen_fx.shockwave(uv, strength)
				if strength >= 1.0:
					screen_fx.impact_frame(color)
			"awaken":
				screen_fx.shockwave(uv, 0.8)
				screen_fx.pulse(color, 0.35)
			"ko":
				screen_fx.shockwave(uv, 1.0)
				screen_fx.impact_frame(color, 0.1)
				screen_fx.knockout()


## Convierte un punto de la arena lógica (480x270) a coordenadas 0..1 de pantalla,
## teniendo en cuenta la escala x2 de la arena y el zoom de la cámara.
func _arena_to_screen_uv(x: float, y: float) -> Vector2:
	var on_screen := arena.get_global_transform_with_canvas() * Vector2(x, y)
	return on_screen / get_viewport().get_visible_rect().size


func _update_camera(delta: float) -> void:
	var shake := sim.screen_shake
	if shake > 0.0:
		camera.offset = Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)) * shake * 2.0
	else:
		camera.offset = Vector2.ZERO
	var awakened := sim.player.awakening_time > 0.0 or sim.enemy.awakening_time > 0.0
	var finishing := sim.state == "round-finished" or sim.state == "finished"
	var target := 1.0
	if finishing:
		target = 1.12
	elif awakened:
		target = 1.055
	_zoom = lerpf(_zoom, target, minf(1.0, delta * 6.0))
	camera.zoom = Vector2(_zoom, _zoom)
	# acerca la cámara sin mover el suelo; al terminar la ronda se centra en los luchadores
	var anchor := Vector2(480, CombatSim.FLOOR * 2.0)
	if finishing:
		anchor.x = (sim.player.x + sim.enemy.x)
	var desired := anchor - (anchor - SCREEN_CENTER) / _zoom
	var half_view := SCREEN_CENTER / _zoom
	desired.x = clampf(desired.x, half_view.x, 960.0 - half_view.x)
	desired.y = clampf(desired.y, half_view.y, 540.0 - half_view.y)
	camera.position = desired


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _running and not _sequence and sim.state == "playing":
		get_viewport().set_input_as_handled()
		Sfx.play("cursor")
		pause_menu.open(sim)


func _on_resume() -> void:
	controls.clear_pressed()


func _on_round_finished(result: String) -> void:
	_sequence = true
	var knocked_out := sim.player.health <= 0 or sim.enemy.health <= 0
	var verdict := "TIEMPO"
	if knocked_out:
		verdict = "DOBLE K.O." if result == "draw" else "K.O."
	elif result == "draw":
		verdict = "EMPATE"
	if knocked_out:
		Engine.time_scale = 0.3
	hud.announce(verdict, Color("#ff5a4f") if knocked_out else Color.WHITE, 0.9)
	await get_tree().create_timer(0.9, true, false, true).timeout
	Engine.time_scale = 1.0
	var detail := "RONDA EMPATADA"
	if result == "player":
		detail = "¡RONDA PARA J1!" if sim.mode == "versus" else "¡RONDA PARA TI!"
		Sfx.play("win")
	elif result == "enemy":
		detail = "¡RONDA PARA J2!" if sim.mode == "versus" else "RONDA PARA EL RIVAL"
	var winner: FighterState = sim.player if result == "player" else (sim.enemy if result == "enemy" else null)
	if winner != null and winner.health >= CombatSim.MAX_HEALTH:
		detail = "¡PERFECTO! · " + detail
	hud.announce(detail, UiKit.GOLD, 0.8)
	await get_tree().create_timer(1.4).timeout
	if sim.state == "finished":
		_show_result()
	elif sim.next_round():
		_round_intro()


func _show_result() -> void:
	_running = false
	var winner := sim.winner_index()
	var p1_name := sim.player.display_name().to_upper()
	var p2_name := sim.enemy.display_name().to_upper()
	var score := "%d – %d" % [sim.player_round_wins, sim.enemy_round_wins]
	var winner_id := ""
	if winner == 0:
		winner_id = sim.player.id
	elif winner == 1:
		winner_id = sim.enemy.id
	var rematch := func() -> void: Router.goto("fight")
	var change := func() -> void: Router.goto("select")
	var menu := func() -> void: Router.goto("menu")

	match Router.mode:
		"versus":
			var title := "EMPATE" if winner < 0 else ("¡GANA J1!" if winner == 0 else "¡GANA J2!")
			var subtitle := "%s vs %s · %s" % [p1_name, p2_name, score]
			if winner >= 0:
				Sfx.play("win")
			result_panel.show_result(title, subtitle, "En modo VS no se ganan monedas.", winner_id,
				[["REVANCHA", rematch], ["CAMBIAR LUCHADORES", change], ["MENÚ PRINCIPAL", menu]])
		"arcade":
			SaveData.add_coins(sim.reward)
			if winner == 0:
				Sfx.play("win")
				var rival_number := Router.arcade_index + 1
				if Router.arcade_advance():
					var next_name := String(Catalog.fighter(Router.p2_id)["name"]).to_upper()
					result_panel.show_result("¡VICTORIA!", "Rival %d de %d superado · %s" % [rival_number, Router.arcade_total(), score],
						"+%d monedas · Próximo rival: %s (%s)" % [sim.reward, next_name, String(Catalog.difficulty(Router.difficulty_id)["name"])],
						winner_id, [["SIGUIENTE COMBATE", rematch], ["MENÚ PRINCIPAL", menu]])
				else:
					SaveData.arcade_clears += 1
					SaveData.add_coins(100)
					result_panel.show_result("¡ARCADE COMPLETADO!", "%s venció a los siete rivales" % p1_name,
						"+%d monedas del combate y +100 de premio · Arcades completados: %d" % [sim.reward, SaveData.arcade_clears],
						winner_id, [["JUGAR OTRA VEZ", change], ["MENÚ PRINCIPAL", menu]])
			else:
				Router.arcade_continues += 1
				var title_lost := "EMPATE" if winner < 0 else "DERROTA"
				result_panel.show_result(title_lost, "%s vs %s · %s" % [p1_name, p2_name, score],
					"+%d monedas · Puedes continuar contra el mismo rival." % sim.reward, winner_id,
					[["CONTINUAR", rematch], ["MENÚ PRINCIPAL", menu]])
		_:
			SaveData.add_coins(sim.reward)
			var title_cpu := "EMPATE" if winner < 0 else ("¡VICTORIA!" if winner == 0 else "DERROTA")
			if winner == 0:
				Sfx.play("win")
			result_panel.show_result(title_cpu, "%s vs %s · %s" % [p1_name, p2_name, score],
				"+%d monedas · Total: %d · Mejor combo: %d golpes" % [sim.reward, SaveData.coins, sim.highest_combo],
				winner_id, [["REVANCHA", rematch], ["CAMBIAR LUCHADORES", change], ["MENÚ PRINCIPAL", menu]])
