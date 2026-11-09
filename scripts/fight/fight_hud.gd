class_name FightHud
extends Control
## HUD del combate: retratos, vida con daño retardado, energía, rondas,
## temporizador, contador de combo, mensajes y anuncios grandes.

const BAR_WIDTH := 330.0
const METER_WIDTH := 250.0

var sim: CombatSim
var _bars: Array[HealthBar] = []
var _meter_fill: Array[ColorRect] = []
var _meter_text: Array[Label] = []
var _names: Array[Label] = []
var _combo: Array[Label] = []
var _combo_damage: Array[Label] = []
var _combo_value: Array[int] = [0, 0]
var _portraits: Array[FighterPortrait] = []
var _timer: Label
var _round: Label
var _toast: Label
var _announce: Label
var _training: Label
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in range(2):
		_build_side(side)
	var clock := Panel.new()
	clock.add_theme_stylebox_override("panel", UiKit.panel(Color(0.04, 0.05, 0.08, 0.9), UiKit.GOLD, 2, 6))
	clock.position = Vector2(446, 8)
	clock.size = Vector2(68, 50)
	add_child(clock)
	_timer = UiKit.label("99", 32, Color.WHITE, 6)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.position = Vector2(0, 2)
	_timer.size = Vector2(68, 44)
	clock.add_child(_timer)
	_round = UiKit.label("RONDA 1", 12, UiKit.GOLD, 4)
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round.position = Vector2(400, 60)
	_round.size = Vector2(160, 16)
	add_child(_round)
	_toast = UiKit.label("", 18, Color.WHITE, 8, Color("#0b0e18"))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(180, 96)
	_toast.size = Vector2(600, 26)
	add_child(_toast)
	_announce = UiKit.label("", 72, UiKit.GOLD, 18, Color("#2a0a00"))
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_announce.position = Vector2(0, 180)
	_announce.size = Vector2(960, 120)
	_announce.pivot_offset = Vector2(480, 60)
	_announce.modulate.a = 0.0
	add_child(_announce)
	_training = UiKit.label("", 14, UiKit.ACCENT, 4)
	_training.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_training.position = Vector2(0, 514)
	_training.size = Vector2(960, 20)
	add_child(_training)


func _build_side(side: int) -> void:
	var left := side == 0
	var accent := UiKit.P1_COLOR if left else UiKit.P2_COLOR
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", UiKit.panel(accent.darkened(0.6), accent, 3, 4))
	frame.position = Vector2(14, 10) if left else Vector2(892, 10)
	frame.size = Vector2(54, 54)
	frame.clip_contents = true
	add_child(frame)
	var portrait := FighterPortrait.new()
	portrait.crop = FighterPortrait.Crop.HEAD
	portrait.animation = "idle"
	portrait.facing = 1 if left else -1
	portrait.position = Vector2(3, 3)
	portrait.size = Vector2(48, 48)
	frame.add_child(portrait)
	_portraits.append(portrait)

	var bar := HealthBar.new()
	bar.mirrored = not left
	bar.fill_color = Color("#3f8cff") if left else Color("#ff8a3a")
	bar.position = Vector2(74, 30) if left else Vector2(886 - BAR_WIDTH, 30)
	bar.size = Vector2(BAR_WIDTH, 22)
	add_child(bar)
	_bars.append(bar)

	var name_label := UiKit.label("", 18, Color.WHITE, 6)
	name_label.position = Vector2(74, 6) if left else Vector2(886 - BAR_WIDTH, 6)
	name_label.size = Vector2(BAR_WIDTH, 22)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	add_child(name_label)
	_names.append(name_label)

	var meter_bg := ColorRect.new()
	meter_bg.color = Color("#0a0d15")
	meter_bg.position = Vector2(74, 56) if left else Vector2(886 - METER_WIDTH, 56)
	meter_bg.size = Vector2(METER_WIDTH, 9)
	add_child(meter_bg)
	var fill := ColorRect.new()
	fill.color = Color("#ffd36e")
	fill.position = Vector2(1, 1)
	fill.size = Vector2(0, 7)
	meter_bg.add_child(fill)
	_meter_fill.append(fill)
	var meter_text := UiKit.label("ENERGÍA", 11, UiKit.MUTED, 4)
	meter_text.position = Vector2(74, 66) if left else Vector2(886 - METER_WIDTH, 66)
	meter_text.size = Vector2(METER_WIDTH, 14)
	meter_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	add_child(meter_text)
	_meter_text.append(meter_text)

	var combo := UiKit.label("", 40, UiKit.GOLD, 12, Color("#2a0a00"))
	combo.position = Vector2(20, 150) if left else Vector2(700, 150)
	combo.size = Vector2(240, 100)
	combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	combo.modulate.a = 0.0
	add_child(combo)
	_combo.append(combo)
	# Daño total del combo, en pequeño debajo del contador.
	var damage := UiKit.label("", 18, UiKit.TEXT, 6, Color("#2a0a00"))
	damage.position = Vector2(22, 198) if left else Vector2(698, 198)
	damage.size = Vector2(240, 24)
	damage.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	combo.modulate.a = 0.0
	add_child(damage)
	_combo_damage.append(damage)


func setup(combat: CombatSim) -> void:
	sim = combat
	var fighters := [sim.player, sim.enemy]
	for side in range(2):
		var f: FighterState = fighters[side]
		var who := ""
		if sim.mode == "versus":
			who = "J1 · " if side == 0 else "J2 · "
		elif side == 1:
			who = "MUÑECO · " if sim.mode == "training" else "CPU · "
		_names[side].text = who + f.display_name().to_upper()
		_portraits[side].fighter_id = f.id
		_bars[side].set_value_instant(f.health)
	if sim.mode == "training":
		_training.text = "ENTRENAMIENTO · J puños · K patadas · J/K + I remate · L técnica · rojo = hitbox · ESC pausa"
	else:
		_training.text = "ESC  PAUSA"


func _process(delta: float) -> void:
	if sim == null:
		return
	_time += delta
	var fighters := [sim.player, sim.enemy]
	for side in range(2):
		var f: FighterState = fighters[side]
		_bars[side].set_value(f.health)
		var fraction := clampf(f.meter / 100.0, 0.0, 1.0)
		var width := (METER_WIDTH - 2.0) * fraction
		var fill := _meter_fill[side]
		if f.awakening_time > 0.0:
			width = (METER_WIDTH - 2.0) * clampf(f.awakening_time / 8.0, 0.0, 1.0)
			fill.color = Catalog.color(String(f.definition["accent"]))
			_meter_text[side].text = "%s · DESPERTAR" % String(f.definition["awakening"]).to_upper()
			_meter_text[side].add_theme_color_override("font_color", fill.color)
		elif fraction >= 1.0 and f.awakening_available:
			fill.color = UiKit.GOLD if fmod(_time, 0.4) < 0.2 else Color.WHITE
			var key := "H" if side == 0 else ("NUM3" if sim.mode == "versus" else "")
			_meter_text[side].text = "¡DESPERTAR LISTO! %s" % key
			_meter_text[side].add_theme_color_override("font_color", UiKit.GOLD)
		else:
			fill.color = Color("#ffd36e") if f.awakening_available else Color("#8e9ab8")
			_meter_text[side].text = "ENERGÍA" if f.awakening_available else "ENERGÍA · DESPERTAR BLOQUEADO"
			_meter_text[side].add_theme_color_override("font_color", UiKit.MUTED)
		fill.size.x = width
		if side == 1:
			fill.position.x = METER_WIDTH - 1.0 - width
		_update_combo(side, f, delta)
	if sim.mode == "training":
		_timer.text = "--"
	else:
		_timer.text = str(ceili(sim.round_time))
		_timer.add_theme_color_override("font_color", Color("#ff5a4f") if sim.round_time <= 10.0 else Color.WHITE)
	_round.text = "RONDA FINAL" if sim.round_number >= 3 else "RONDA %d" % maxi(1, sim.round_number)
	_toast.text = sim.last_action if (sim.last_action_time > 0.0 and sim.state == "playing") else ""
	queue_redraw()


## Rombos de rondas ganadas junto al nombre de cada luchador.
func _draw() -> void:
	if sim == null or sim.mode == "training":
		return
	var wins := [sim.player_round_wins, sim.enemy_round_wins]
	for side in range(2):
		var won: int = wins[side]
		for j in range(2):
			var cx := 74.0 + BAR_WIDTH - 10.0 - j * 22.0 if side == 0 else 886.0 - BAR_WIDTH + 10.0 + j * 22.0
			var center := Vector2(cx, 17)
			var diamond := PackedVector2Array([center + Vector2(0, -8), center + Vector2(8, 0), center + Vector2(0, 8), center + Vector2(-8, 0)])
			if j < won:
				draw_colored_polygon(diamond, UiKit.GOLD)
			else:
				draw_colored_polygon(diamond, Color(0, 0, 0, 0.5))
			var outline := diamond.duplicate()
			outline.append(diamond[0])
			draw_polyline(outline, UiKit.GOLD, 2.0)


## Contador de combo real: golpes seguidos sin que el rival se recupere y su daño total.
func _update_combo(side: int, f: FighterState, delta: float) -> void:
	var label := _combo[side]
	if f.combo_hits >= 2 and f.combo_display > 0.0 and f.combo_hits != _combo_value[side]:
		_combo_value[side] = f.combo_hits
		label.text = "%d GOLPES" % f.combo_hits
		_combo_damage[side].text = "%d DE DAÑO" % f.combo_damage
		label.modulate.a = 1.0
		var hot := f.combo_hits >= 6
		label.add_theme_color_override("font_color", Color("#ff6a3d") if hot else UiKit.GOLD)
		label.pivot_offset = Vector2(0 if side == 0 else 240, 50)
		label.scale = Vector2(1.45, 1.45) if hot else Vector2(1.3, 1.3)
	if f.combo_display <= 0.0 or f.combo_hits < 2:
		_combo_value[side] = 0
		label.modulate.a = maxf(0.0, label.modulate.a - delta * 3.0)
	label.scale = label.scale.lerp(Vector2.ONE, minf(1.0, delta * 12.0))
	_combo_damage[side].modulate.a = label.modulate.a


## Muestra un texto grande en el centro ("RONDA 1", "¡PELEA!", "K.O."...).
func announce(text: String, color: Color = UiKit.GOLD, hold: float = 0.8) -> void:
	_announce.text = text
	_announce.add_theme_color_override("font_color", color)
	_announce.scale = Vector2(2.2, 2.2)
	_announce.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_announce, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_announce, "modulate:a", 1.0, 0.12)
	tween.chain().tween_interval(hold)
	tween.chain().tween_property(_announce, "modulate:a", 0.0, 0.2)
