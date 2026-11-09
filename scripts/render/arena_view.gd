class_name ArenaView
extends Node2D
## Dibuja el escenario, los luchadores, proyectiles, efectos y partículas de un
## CombatSim (equivale a Renderer.render() de src/renderer.js).
## El nodo trabaja en coordenadas lógicas de 480x270; la escena de combate lo
## escala x2 para que los píxeles se vean nítidos.

const HEIGHT := 270.0
const FLOOR := CombatSim.FLOOR
const WIDTH := CombatSim.WIDTH

const FIGHTER_SHADER := preload("res://shaders/fighter_fx.gdshader")

var sim: CombatSim
var state_elapsed := 0.0
var background_time := 0.0
var show_hitboxes := false
var _previous_state := ""
var _enemy_layer: DrawLayer
var _player_layer: DrawLayer
var _fx_layer: DrawLayer
## AnimadorProcedural de cada luchador con imágenes (índice 0 = J1, 1 = rival).
var _animadores: Dictionary = {}


## Capa de dibujo hija. Cada luchador tiene la suya para poder aplicarle su propio
## shader (fighter_fx.gdshader) sin afectar al escenario ni a los efectos.
## Orden: escenario (este nodo) → rival → jugador → efectos.
class DrawLayer extends Node2D:
	var painter: Callable

	func _draw() -> void:
		painter.call(self)


func _ready() -> void:
	_enemy_layer = _make_layer(func(ci: CanvasItem) -> void: _draw_fighter(ci, sim.enemy), true)
	_player_layer = _make_layer(func(ci: CanvasItem) -> void: _draw_fighter(ci, sim.player), true)
	_fx_layer = _make_layer(_draw_overlay, false)


func _make_layer(painter: Callable, with_shader: bool) -> DrawLayer:
	var layer := DrawLayer.new()
	layer.painter = func(ci: CanvasItem) -> void:
		if sim != null:
			painter.call(ci)
			FighterPainter.alpha = 1.0
	if with_shader:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = FIGHTER_SHADER
		layer.material = shader_material
	add_child(layer)
	return layer


## Luz de cada escenario sobre los luchadores (multiplica su color).
const STAGE_LIGHT := {
	"harbor": Color(0.9, 0.95, 1.08), "arena": Color(1.08, 0.98, 0.9),
	"cliffs": Color(0.98, 1.02, 1.06), "warzone": Color(1.1, 0.9, 0.86),
}


func _process(delta: float) -> void:
	if sim == null:
		return
	var light: Color = STAGE_LIGHT.get(String(sim.stage().get("decor", "")), Color.WHITE)
	_enemy_layer.modulate = light
	_player_layer.modulate = light
	if sim.state == _previous_state:
		state_elapsed += minf(delta, 1.0 / 30.0)
	else:
		state_elapsed = 0.0
		_previous_state = sim.state
	background_time += delta
	_update_animadores(delta)
	_update_fighter_shader(_enemy_layer, sim.enemy)
	_update_fighter_shader(_player_layer, sim.player)
	queue_redraw()
	_enemy_layer.queue_redraw()
	_player_layer.queue_redraw()
	_fx_layer.queue_redraw()


## Crea los animadores la primera vez, les pasa las acciones de la simulación
## (golpe, patada, bloqueo, K.O.…) y actualiza la parte automática (respirar, caminar…).
func _update_animadores(delta: float) -> void:
	if _animadores.is_empty():
		for fighter in [sim.player, sim.enemy]:
			var f: FighterState = fighter
			if FighterPainter.has_sprites(f.definition):
				var animador := AnimadorProcedural.new()
				animador.name = "Animador%d" % (f.index + 1)
				animador.preparar(f)
				add_child(animador)
				_animadores[f.index] = animador
	for event in sim.consume_anim_events():
		var e: Dictionary = event
		var index := int(e["i"])
		if _animadores.has(index):
			_animadores[index].ejecutar(e, sim.fighter_by_index(index))
	for index in _animadores:
		_animadores[index].actualizar(sim.fighter_by_index(index), delta)


## Intensidad del shader del luchador según lo que esté haciendo:
##   glow  → venas de energía y contorno eléctrico (despertar, carga de técnica, remates)
##   surge → destello en el instante del remate o del lanzamiento de la técnica
func _update_fighter_shader(layer: DrawLayer, f: FighterState) -> void:
	var shader_material := layer.material as ShaderMaterial
	var pose := String(fighter_animation(f).get("pose", ""))
	var heavy_move := f.attack_animation == "finisher" or f.attack_animation == "kick" \
		or f.attack_animation == "heavy" or f.attack_animation == "uppercut" \
		or f.attack_animation == "kick_spin" or f.special_pose_time > 0.0
	var striking := pose == "smear" or pose == "impact" or pose == "special-launch" or pose == "special-impact"
	var glow := 0.0
	if f.awakening_time > 0.0:
		glow = 1.0
	elif f.special_charge > 0.0:
		glow = 0.75
	elif heavy_move and f.attack_pose > 0.0:
		glow = 0.6
	var surge := 0.0
	if heavy_move and striking:
		surge = 0.55 if pose == "smear" or pose == "special-launch" else 0.3
	shader_material.set_shader_parameter("glow", glow)
	shader_material.set_shader_parameter("surge", surge)
	shader_material.set_shader_parameter("glow_color", Catalog.color(String(f.definition["accent"])))


func _draw() -> void:
	if sim == null:
		return
	FighterPainter.alpha = 1.0
	var stage_data := sim.stage()
	StagePainter.draw_background(self, stage_data, HEIGHT, background_time)
	StagePainter.draw_ground(self, stage_data, HEIGHT, background_time)
	FighterPainter.alpha = 1.0


## Proyectiles, efectos, partículas y cajas de depuración, por encima de los luchadores.
func _draw_overlay(ci: CanvasItem) -> void:
	_draw_projectiles(ci)
	_draw_effects(ci)
	_draw_particles(ci)
	if show_hitboxes:
		_draw_debug_boxes(ci)
	if sim.armor_flash > 0.0:
		FighterPainter.box(ci, 0, 0, WIDTH, HEIGHT, Color(0.76, 0.78, 0.8, sim.armor_flash / 0.12 * 0.42))


## Elige la animación y el cuadro de cada luchador (fighterAnimation()).
func fighter_animation(f: FighterState) -> Dictionary:
	var anim_name := "idle"
	var elapsed_frames := sim.elapsed * 60.0 if sim.state == "playing" else state_elapsed * 60.0
	var anims := FighterAnimations.for_fighter(f.id)
	var match_over := sim.state == "finished" or sim.state == "round-finished"
	var round_winner := sim.winner_name() if sim.state == "round-finished" else ""
	if match_over and f.health <= 0:
		anim_name = "fall"
		elapsed_frames = state_elapsed * 60.0
	elif sim.state == "finished" and sim.winner_name() == f.display_name():
		anim_name = "victory"
	elif sim.state == "round-finished" and round_winner == f.display_name():
		anim_name = "victory"
	elif sim.state == "ready":
		anim_name = "intro"
	elif f.special_charge > 0.0:
		anim_name = "charge"
	elif f.knocked_down:
		anim_name = "fall"
		elapsed_frames = f.knockdown_time * 60.0
	elif f.getup_time > 0.0:
		anim_name = "getup"
		elapsed_frames = FighterAnimations.duration(anims[anim_name]) - f.getup_time * 60.0
	elif f.special_pose_time > 0.0:
		anim_name = "special"
		elapsed_frames = FighterAnimations.duration(anims[anim_name]) - f.special_pose_time * 60.0
	elif f.hurt_time > 0.0:
		anim_name = "hurt"
		elapsed_frames = FighterAnimations.duration(anims[anim_name]) - f.hurt_time * 60.0
	elif f.guard_time > 0.0:
		anim_name = "block"
	elif not f.grounded and not (f.attack_pose > 0.0 and f.attack_animation.begins_with("air_")):
		anim_name = "jump"
		elapsed_frames = 0.0 if f.velocity_y < -70.0 else (8.0 if f.velocity_y > 70.0 else 4.0)
	elif f.attack_pose > 0.0:
		anim_name = f.attack_animation
		if anim_name == "" or not anims.has(anim_name):
			anim_name = "weak" if f.id == "brasa" else "light"
		elapsed_frames = FighterAnimations.duration(anims[anim_name]) - f.attack_pose * 60.0
	elif f.walking:
		anim_name = "run" if f.running else "walk"
	var frame := FighterAnimations.frame_at(anims[anim_name], elapsed_frames)
	frame["name"] = anim_name
	return frame


func _draw_fighter(ci: CanvasItem, f: FighterState) -> void:
	var definition := f.definition
	var accent := Catalog.color(String(definition["accent"]))
	var trim := Catalog.color(String(definition["trim"]))
	var x := roundf(f.x)
	var frame := fighter_animation(f)
	var foot := roundf(FLOOR + f.y)
	var t := sim.elapsed
	var base := Transform2D.IDENTITY
	_draw_shadow(ci, x, f)

	if f.guard_time > 0.0:
		var frame_color := trim
		FighterPainter.box(ci, x - 25, foot - 69, 50, 3, frame_color)
		FighterPainter.box(ci, x - 29, foot - 64, 3, 46, frame_color)
		FighterPainter.box(ci, x + 26, foot - 64, 3, 46, frame_color)
		FighterPainter.box(ci, x - 22, foot - 16, 44, 3, frame_color)

	if f.special_charge > 0.0:
		_draw_charge_effects(ci, f, x, foot, frame)

	if f.armor_time > 0.0:
		ci.draw_rect(Rect2(x - 25, foot - 18, 50, 9), accent, false, 2.0)

	if f.decoy_time > 0.0:
		FighterPainter.alpha = 0.32
		FighterPainter.draw_body(ci, base, x + 30, foot, f, accent, frame, t)
		FighterPainter.alpha = 1.0

	var flash := Catalog.color(String(definition["color"]))
	if f.white_flash > 0.0:
		flash = Color.WHITE
	elif f.hit_flash > 0.0:
		flash = Catalog.color("#ff272b") if f.id == "brasa" else Catalog.color("#f2e7d2")
	_draw_charge_aura(ci, f, x, foot, frame)
	if f.id == "volt" and f.awakening_time > 0.0:
		FighterPainter.draw_volt_armor(ci, x, foot, t)
	elif f.awakening_time > 0.0:
		_draw_awakening_flames(ci, f, x, foot, t, accent)
	var victorious := sim.state == "finished" and sim.winner_name() == f.display_name()
	var animador: AnimadorProcedural = _animadores.get(f.index)
	if animador == null and _leaves_trail(f, frame):
		# Estela de dos copias que se desvanecen detrás del remate.
		for k in range(2):
			FighterPainter.alpha = 0.28 - k * 0.12
			FighterPainter.draw_body(ci, base, x - f.facing * (7.0 + k * 7.0), foot + (3.0 + k * 3.0 if f.attack_animation == "uppercut" else 0.0), f, accent, frame, t)
		FighterPainter.alpha = 1.0
	if animador:
		animador.ultimo_cuadro = frame
		animador.ultimo_tiempo = t
		_draw_estelas(ci, animador, base)
		FighterPainter.procedural = animador.salida()
	FighterPainter.draw_body(ci, base, x, foot, f, flash, frame, t, victorious)
	FighterPainter.procedural = {}

	if f.special_charge > 0.0 and f.id == "brasa":
		var hand_x := x + f.facing * 39
		var hand_y := foot - 67
		var pulse := roundf(2.0 + sin(t * 25.0) * 1.5)
		FighterPainter.box(ci, hand_x - pulse, hand_y - pulse, pulse * 2 + 1, pulse * 2 + 1, Catalog.color("#fff8c7"))
		FighterPainter.box(ci, hand_x - 8, hand_y - 8, 17, 1, Color(1.0, 215 / 255.0, 74 / 255.0, 0.68))
	if f.id == "volt" and f.awakening_time > 0.0:
		var pulse_v := sin(t * 24.0)
		FighterPainter.alpha = 0.38 + absf(pulse_v) * 0.24
		FighterPainter.ellipse(ci, Vector2(x, foot - 34), 24 + roundf((pulse_v + 1.0) * 2.0), 39, Catalog.color("#d6fff5"), 2.0)
		for arc in range(2):
			var side := -1.0 if arc == 0 else 1.0
			var spread := roundf((pulse_v + 1.0) * 4.0)
			FighterPainter.box(ci, x + side * (19 + spread), foot - 49, 3, 10, accent)
			FighterPainter.box(ci, x + side * (15 + spread), foot - 43, 4, 3, Catalog.color("#efffff"))
			FighterPainter.box(ci, x + side * (12 + spread), foot - 39, 4, 7, accent)
		FighterPainter.alpha = 1.0


const TRAIL_ATTACKS := ["uppercut", "kick_spin", "kick_high", "air_kick", "sweep", "finisher", "kick", "throw"]


func _leaves_trail(f: FighterState, frame: Dictionary) -> bool:
	var pose := String(frame.get("pose", ""))
	return f.attack_pose > 0.0 and TRAIL_ATTACKS.has(f.attack_animation) and (pose == "smear" or pose == "impact" and frame.get("smear", false))


## Llamas de energía en pixel art alrededor del luchador durante el despertar.
func _draw_awakening_flames(ci: CanvasItem, f: FighterState, x: float, foot: float, t: float, accent: Color) -> void:
	var height := 62.0 * float(f.definition["sprite_scale"]) / 1.5
	var core := accent.lightened(0.45)
	for i in range(20):
		var side := -1.0 if i % 2 == 0 else 1.0
		var phase := fmod(t * (1.4 + (i % 3) * 0.35) + i * 0.29, 1.0)
		var lx := x + side * (17.0 + (i % 5) * 2.5 - phase * 7.0)
		var ly := foot - phase * height * 1.1
		var size := roundf(6.0 * (1.0 - phase) + 2.0)
		FighterPainter.alpha = 0.9 * (1.0 - phase * 0.8)
		FighterPainter.box(ci, lx - size / 2.0, ly - size, size, size * 2.0, accent)
		FighterPainter.box(ci, lx - 0.5, ly - size * 0.5, 1, size, core)
	# Base brillante a los pies.
	var pulse := 0.5 + 0.5 * sin(t * 10.0)
	FighterPainter.alpha = 0.35 + 0.2 * pulse
	FighterPainter.box(ci, x - 20, foot - 3, 40, 3, accent)
	FighterPainter.box(ci, x - 12, foot - 5, 24, 2, core)
	FighterPainter.alpha = 1.0


## Sombra ovalada en pixel art: más pequeña y clara cuanto más alto está el luchador.
func _draw_shadow(ci: CanvasItem, x: float, f: FighterState) -> void:
	var height := clampf(-f.y / 110.0, 0.0, 1.0)
	var w := roundf(40.0 * (1.0 - height * 0.45))
	var a := 0.5 * (1.0 - height * 0.5)
	var shade := Color(10 / 255.0, 12 / 255.0, 17 / 255.0, a)
	FighterPainter.box(ci, x - w / 2.0 + 4, FLOOR + 1, w - 8, 1, shade)
	FighterPainter.box(ci, x - w / 2.0, FLOOR + 2, w, 3, shade)
	FighterPainter.box(ci, x - w / 2.0 + 4, FLOOR + 5, w - 8, 1, shade)


## Copias del luchador que se desvanecen detrás de él durante el dash.
func _draw_estelas(ci: CanvasItem, animador: AnimadorProcedural, base: Transform2D) -> void:
	var ghost := animador.fantasma
	for estela in animador.estelas:
		var e: Dictionary = estela
		var color := animador.color_estela
		FighterPainter.alpha = clampf(float(e["vida"]) / AnimadorProcedural.VIDA_ESTELA, 0.0, 1.0)
		ghost.facing = int(e["facing"])
		FighterPainter.procedural = {"desp": e["desp"], "escala": e["escala"], "rot": e["rot"], "color": color, "ko": false}
		FighterPainter.draw_body(ci, base, roundf(float(e["x"])), roundf(FLOOR + float(e["y"])), ghost,
			color, e["cuadro"], float(e["tiempo"]))
	FighterPainter.procedural = {}
	FighterPainter.alpha = 1.0


func _draw_charge_effects(ci: CanvasItem, f: FighterState, x: float, foot: float, frame: Dictionary) -> void:
	var accent := Catalog.color(String(f.definition["accent"]))
	var t := sim.elapsed
	if f.id == "onix":
		var orbit := t * 7.0
		for i in range(4):
			var angle := orbit + i * PI / 2.0
			var fx := roundf(x + cos(angle) * 29.0)
			var fy := roundf(foot - 47.0 + sin(angle) * 25.0)
			FighterPainter.box(ci, fx - 3, fy - 4, 7, 7, accent)
			FighterPainter.box(ci, fx - 1, fy - 2, 3, 3, Catalog.color("#f4e3bf"))
		return
	var duration := sim.special_charge_duration(String(f.definition["special"]))
	var charge_pulse := 1 + roundi((1.0 - f.special_charge / duration) * 3.0)
	match f.id:
		"volt":
			for i in range(4):
				var x_offset := roundf(sin(t * 28.0 + i * 2.0) * (9.0 + i * 3.0))
				FighterPainter.box(ci, x + x_offset, foot - 27 - i * 8, 2, 8, Catalog.color("#f4fcff") if i % 2 == 1 else accent)
		"marea":
			for i in range(8):
				var angle := t * 2.8 + TAU * i / 8.0
				FighterPainter.box(ci, x + cos(angle) * 26.0, foot - 37 + sin(angle) * 18.0, 3, 5, accent)
		"cobalto":
			for i in range(charge_pulse + 1):
				FighterPainter.box(ci, x + f.facing * (16 + i * 5), foot - 42 - (i % 2) * 5, 5, 5, Catalog.color("#fffaff") if i % 2 == 1 else accent)
		"espejo":
			FighterPainter.alpha = 0.5
			FighterPainter.draw_body(ci, Transform2D.IDENTITY, x - f.facing * (8 + charge_pulse * 2), foot, f, accent, frame, t)
			FighterPainter.alpha = 1.0
		"pedernal":
			for i in range(charge_pulse + 1):
				var offset := (i - charge_pulse / 2.0) * 8.0
				FighterPainter.box(ci, x + offset, FLOOR - 5 - (i % 2) * 7, 5, 5, accent)
		"luma":
			FighterPainter.alpha = 0.18 + charge_pulse * 0.07
			FighterPainter.box(ci, x - 25, foot - 56, 50, 50, accent)
			FighterPainter.alpha = 1.0
			for i in range(6):
				var angle := t * 2.0 + i * PI / 3.0
				FighterPainter.box(ci, x + cos(angle) * 24.0, foot - 39 + sin(angle) * 18.0, 3, 3, Catalog.color("#efffd6"))


func _draw_charge_aura(ci: CanvasItem, f: FighterState, x: float, foot: float, frame: Dictionary) -> void:
	if frame.get("pose", "") != "charge":
		return
	var scale_factor := float(f.definition["sprite_scale"])
	var aura := float(frame.get("aura", 1))
	var radius := (29.0 if f.id == "onix" else 22.0) + aura * 3.0
	FighterPainter.alpha = 0.2 + aura * 0.08
	FighterPainter.ellipse(ci, Vector2(x, foot - 39.0 * scale_factor), radius * scale_factor, 34.0 * scale_factor + aura * 2.0, Catalog.color(String(f.definition["accent"])), 2.0)
	FighterPainter.alpha = 1.0


func _draw_projectiles(ci: CanvasItem) -> void:
	for projectile in sim.projectiles:
		var p: Dictionary = projectile
		var x := roundf(float(p["x"]))
		var y := roundf(float(p["y"]) - (22.0 if float(p["delay"]) > 0.0 else 0.0))
		var color := Catalog.color(String(p["color"]))
		if p["type"] == "rock-shard":
			FighterPainter.box(ci, x - 5, y - 5, 10, 10, Catalog.color("#292d36"))
			FighterPainter.box(ci, x - 3, y - 4, 6, 7, color)
			FighterPainter.box(ci, x - 1, y - 4, 2, 3, Catalog.color("#f2e4c6"))
			continue
		var size := 6.0
		FighterPainter.box(ci, x - size - 2, y - size - 2, size * 2 + 4, size * 2 + 4, Color(1, 1, 1, 0.35))
		FighterPainter.box(ci, x - size, y - size, size * 2, size * 2, color)
		FighterPainter.box(ci, x - ceilf(size / 2), y - ceilf(size / 2), size, size, Catalog.color("#fff5db"))


func _draw_effects(ci: CanvasItem) -> void:
	for effect in sim.effects:
		var e: Dictionary = effect
		var life := float(e["life"])
		var max_life := float(e.get("max_life", life))
		var strength := maxf(0.0, life / 0.62)
		var spread := roundf((1.0 - strength) * 35.0)
		var ex := float(e["x"])
		var ey := float(e["y"])
		var color := Catalog.color(String(e["color"]))
		var type := String(e["type"])
		match type:
			"solar-beam":
				var progress := 1.0 - life / max_life
				var width := roundf(12.0 + 19.0 * minf(progress * 8.0, 1.0))
				var end_x := float(e["end_x"])
				var start := minf(ex, end_x)
				var length := absf(end_x - ex)
				var core := Catalog.color("#fff4b7")
				FighterPainter.alpha = minf(1.0, life / 0.12)
				FighterPainter.box(ci, start, ey - width / 2.0, 10, width, core)
				var offset := 8.0
				while offset < length - 8.0:
					FighterPainter.box(ci, start + offset, ey - width / 2.0, minf(14.0, length - offset), width, color)
					FighterPainter.box(ci, start + offset, ey - 3, minf(14.0, length - offset), 6, core)
					offset += 12.0
				FighterPainter.box(ci, maxf(start, start + length - 12.0), ey - width, 12, width * 2.0, color)
				FighterPainter.box(ci, maxf(start, start + length - 8.0), ey - width / 2.0, 8, width, Color.WHITE)
			"volt-afterimage":
				FighterPainter.alpha = strength
				FighterPainter.box(ci, ex - 11, ey - 26, 22, 3, color)
				FighterPainter.box(ci, ex - 7, ey - 20, 17, 3, Catalog.color("#f4fcff"))
			"volt-focus", "volt-phase", "volt-transform":
				var transform_progress := 1.0 - life / max_life if type == "volt-transform" else 0.0
				var radius := 14.0 + spread * 0.7
				if type == "volt-transform":
					radius = 18.0 + transform_progress * 38.0
				elif type == "volt-focus":
					radius = 20.0 + spread
				FighterPainter.alpha = strength * 0.85
				var rx := radius * 1.4 if type == "volt-transform" else radius
				var ry := radius * 2.1 if type == "volt-transform" else radius * 1.35
				FighterPainter.ellipse(ci, Vector2(ex, ey), rx, ry, color, 3.0)
				for i in range(4):
					var edge_x := ex + (1.0 if i % 2 == 1 else -1.0) * (radius - 2.0)
					FighterPainter.box(ci, edge_x, ey - 18 + i * 8, 4, 7, Catalog.color("#f4fcff") if i % 2 == 1 else color)
			"volt-impact":
				FighterPainter.alpha = strength
				FighterPainter.box(ci, ex - 18, ey - 3, 36, 6, Catalog.color("#efffff"))
				FighterPainter.box(ci, ex - 3, ey - 18, 6, 36, color)
				FighterPainter.box(ci, ex - 11, ey - 11, 22, 22, Color.WHITE)
			"marea-guard":
				FighterPainter.alpha = strength * 0.75
				FighterPainter.ellipse(ci, Vector2(ex, ey), 22.0 + spread * 0.3, 22.0 + spread * 0.3, color, 2.0)
			"prism-lance":
				var end_x2 := float(e["end_x"])
				var start2 := minf(ex, end_x2)
				var length2 := absf(end_x2 - ex)
				var width2 := 8.0 + roundf((1.0 - strength) * 8.0)
				FighterPainter.alpha = strength
				FighterPainter.box(ci, start2, ey - width2 / 2.0, length2, width2, color)
				FighterPainter.box(ci, start2, ey - 3, length2, 6, Catalog.color("#fffaff"))
				for i in range(7):
					FighterPainter.box(ci, start2 + i * (length2 / 7.0), ey - width2, 3, width2 * 2.0, Catalog.color("#fffaff") if i % 2 == 1 else color)
			"mirror-step":
				FighterPainter.alpha = strength * 0.6
				FighterPainter.box(ci, ex - 9, ey - 29, 18, 3, color)
				FighterPainter.box(ci, float(e["end_x"]) - 9, ey - 21, 18, 3, Catalog.color("#fff0fa"))
			"fault-ring":
				var ring_radius := 12.0 + (1.0 - strength) * 66.0
				FighterPainter.ellipse(ci, Vector2(ex, ey), ring_radius, ring_radius * 0.24, color, 3.0)
				for i in range(5):
					FighterPainter.box(ci, ex + cos(i * 1.2) * ring_radius, ey - 5, 3, 8, Catalog.color("#d4c2a0"))
			"luma-pulse":
				var pulse_radius := 8.0 + (1.0 - strength) * 40.0 + float(e.get("ring", 0)) * 5.0
				FighterPainter.alpha = strength * 0.75
				FighterPainter.ellipse(ci, Vector2(ex, ey), pulse_radius, pulse_radius, color, 2.0)
			"hit-spark":
				FighterPainter.alpha = minf(1.0, life / 0.04)
				FighterPainter.box(ci, ex - 12, ey - 2, 24, 4, Color.WHITE)
				FighterPainter.box(ci, ex - 2, ey - 12, 4, 24, color)
				FighterPainter.box(ci, ex - 8, ey - 8, 16, 16, Catalog.color("#fff3a6"))
			"impact":
				var w := 14.0 + spread
				FighterPainter.box(ci, ex - w / 2.0, ey - 2, w, 3, color)
				FighterPainter.box(ci, ex - w / 2.0 + 5, ey - 7, w - 10, 3, Catalog.color("#fff3ce"))
			"shard-burst":
				var facing := float(e.get("facing", 1))
				for i in range(4):
					var sx := ex + facing * (spread + i * 5)
					var lift := absf(2 - i) * 4.0
					FighterPainter.box(ci, sx, ey - 7 - lift, 7, 7, color)
					FighterPainter.box(ci, sx + 2, ey - 6 - lift, 2, 3, Catalog.color("#fff0d0"))
			"armor":
				FighterPainter.box(ci, ex - 19, ey - 16, 38, 3, Catalog.color("#d7dbe0"))
				FighterPainter.box(ci, ex - 17, ey + 13, 34, 3, Catalog.color("#aeb4be"))
			"dust":
				FighterPainter.box(ci, ex - spread, ey - 2, 14 + spread, 3, color)
			"spark-punch", "spark-kick", "spark-heavy", "spark-block":
				_draw_spark(ci, type, ex, ey, 1.0 - life / max_life, float(e.get("dir", 1)), color)
			"dust-cloud":
				var p := 1.0 - life / max_life
				var size := float(e.get("size", 1.0))
				FighterPainter.alpha = (1.0 - p) * 0.7
				for side: float in [-1.0, 1.0]:
					for k in range(3):
						var r := roundf((3.0 + k * 1.5) * size * (0.6 + p))
						var px := ex + side * (8.0 + k * 9.0 + p * 18.0) * size
						var py := ey - r - k * 1.0 - p * 4.0
						FighterPainter.box(ci, px - r, py, r * 2.0, r, color)
						FighterPainter.box(ci, px - r + 1, py - r * 0.5, r * 2.0 - 2, r * 0.5, color.lightened(0.15))
			_:
				FighterPainter.box(ci, ex - 12, ey - 3, 24, 4, color)
				FighterPainter.box(ci, ex - 5, ey - 9, 10, 4, Catalog.color("#fff4d2"))
		FighterPainter.alpha = 1.0


## Chispas de impacto en pixel art. `p` va de 0 (golpe) a 1 (desaparece).
func _draw_spark(ci: CanvasItem, type: String, ex: float, ey: float, p: float, dir: float, color: Color) -> void:
	var white := Color.WHITE
	match type:
		"spark-punch":
			# Estrella de 8 puntas que se abre y se apaga.
			FighterPainter.alpha = 1.0 - p * 0.8
			var core := roundf(6.0 * (1.0 - p))
			FighterPainter.box(ci, ex - core / 2.0, ey - core / 2.0, core, core, white)
			for i in range(8):
				var ang := i * PI / 4.0
				var reach := 1.0 if i % 2 == 0 else 0.6
				for k in range(3):
					var dist := (4.0 + k * 4.0 + p * 10.0) * reach
					FighterPainter.box(ci, ex + cos(ang) * dist - 1, ey + sin(ang) * dist - 1, 2, 2, white if k == 0 else color)
		"spark-kick":
			# Media luna en la dirección del golpe.
			FighterPainter.alpha = 1.0 - p * 0.85
			var radius := 11.0 + p * 16.0
			for i in range(11):
				var ang := lerpf(-1.2, 1.2, i / 10.0)
				var px := ex - dir * cos(ang) * radius * 0.6
				var py := ey + sin(ang) * radius
				var thick := 4.0 if absf(i - 5) < 2 else (3.0 if absf(i - 5) < 4 else 2.0)
				FighterPainter.box(ci, px - 1, py - 1, thick, thick, white if absf(i - 5) < 3 else color)
				FighterPainter.box(ci, px - dir * 3.0 - 1, py - 1, 2, 2, color)
			FighterPainter.box(ci, ex - 2, ey - 2, roundf(5.0 * (1.0 - p)), roundf(5.0 * (1.0 - p)), white)
		"spark-heavy":
			# Destello en cruz + anillo de píxeles + rayos largos.
			FighterPainter.alpha = 1.0 - p * 0.7
			if p < 0.3:
				FighterPainter.box(ci, ex - 16, ey - 2, 32, 4, white)
				FighterPainter.box(ci, ex - 2, ey - 16, 4, 32, white)
				FighterPainter.box(ci, ex - 6, ey - 6, 12, 12, color.lightened(0.5))
			var ring := 6.0 + p * 28.0
			for i in range(14):
				var ang := i * TAU / 14.0
				FighterPainter.box(ci, ex + cos(ang) * ring - 1, ey + sin(ang) * ring * 0.8 - 1, 3, 3, color if i % 2 == 0 else white)
			for i in range(4):
				var ang := PI / 4.0 + i * PI / 2.0
				var dist := 10.0 + p * 30.0
				FighterPainter.box(ci, ex + cos(ang) * dist - 2, ey + sin(ang) * dist - 2, 4, 4, white)
		"spark-block":
			# Escudo hexagonal que se ilumina delante de quien bloquea.
			FighterPainter.alpha = 1.0 - p
			var h := 14.0 + p * 6.0
			for i in range(7):
				var y := ey - h + i * (h * 2.0 / 6.0)
				var bulge := roundf((3.0 - absf(i - 3)) * 1.5)
				FighterPainter.box(ci, ex + dir * bulge - 1, y - 1, 3, 4, white if i % 2 == 0 else color)
			FighterPainter.box(ci, ex + dir * 6.0 - 1, ey - 2, 3, 4, color)


func _draw_particles(ci: CanvasItem) -> void:
	for particle in sim.particles:
		var p: Dictionary = particle
		var color := Catalog.color(String(p["color"]))
		color.a = clampf(float(p["life"]) / 0.2, 0.0, 1.0)
		FighterPainter.box(ci, float(p["x"]), float(p["y"]), 3, 3, color)


## Muestra pushboxes (verde) y hitboxes activas (rojo) en el modo entrenamiento.
func _draw_debug_boxes(ci: CanvasItem) -> void:
	for fighter in [sim.player, sim.enemy]:
		var f: FighterState = fighter
		var half := float(f.definition["pushbox_half_width"])
		var scale_factor := float(f.definition["sprite_scale"])
		ci.draw_rect(Rect2(f.x - half, FLOOR + f.y - 42.0 * scale_factor, half * 2.0, 42.0 * scale_factor), Color(0.3, 1, 0.5, 0.8), false, 1.0)
		if f.attack_animation == "" or f.attack_pose <= 0.0:
			continue
		var anim := FighterAnimations.get_animation(f.id, f.attack_animation)
		var frame := FighterAnimations.frame_at(anim, FighterAnimations.duration(anim) - f.attack_pose * 60.0)
		if not frame.has("hitbox"):
			continue
		var hb: Dictionary = frame["hitbox"]
		var hx := float(hb["x"]) * scale_factor
		var hw := float(hb["w"]) * scale_factor
		var top := FLOOR + f.y - (float(hb["y"]) + float(hb["h"])) * scale_factor
		var left := f.x + hx if f.facing > 0 else f.x - hx - hw
		ci.draw_rect(Rect2(left, top, hw, float(hb["h"]) * scale_factor), Color(1, 0.25, 0.3, 0.85), false, 1.0)
