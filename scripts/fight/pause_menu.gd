class_name PauseMenu
extends Control
## Menú de pausa: continuar, reiniciar, lista de movimientos, opciones y salir.

signal resume_requested
signal restart_requested
signal quit_requested

var _buttons: Array[Button] = []
var _moves: Label
var _options: OptionsPanel
var _panel: PanelContainer


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.PANEL, UiKit.ACCENT, 2, 8))
	_panel.position = Vector2(60, 90)
	_panel.custom_minimum_size = Vector2(320, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	box.add_child(UiKit.label("PAUSA", 34, Color.WHITE, 8))
	for entry in [["CONTINUAR", "resume"], ["REINICIAR COMBATE", "restart"], ["OPCIONES", "options"], ["SALIR AL MENÚ", "quit"]]:
		var button := UiKit.make_button(String(entry[0]), UiKit.ACCENT, 18)
		button.custom_minimum_size = Vector2(290, 40)
		var action := String(entry[1])
		button.pressed.connect(func() -> void: _on_action(action))
		button.mouse_entered.connect(button.grab_focus)
		button.focus_entered.connect(func() -> void: Sfx.play("cursor"))
		box.add_child(button)
		_buttons.append(button)

	var moves_panel := PanelContainer.new()
	moves_panel.add_theme_stylebox_override("panel", UiKit.panel(Color(UiKit.PANEL, 0.95), UiKit.LINE, 2, 8))
	moves_panel.position = Vector2(420, 90)
	moves_panel.custom_minimum_size = Vector2(480, 0)
	add_child(moves_panel)
	_moves = UiKit.label("", 13, UiKit.TEXT)
	_moves.autowrap_mode = TextServer.AUTOWRAP_WORD
	_moves.custom_minimum_size = Vector2(450, 0)
	moves_panel.add_child(_moves)

	_options = OptionsPanel.new()
	add_child(_options)
	_options.closed.connect(func() -> void: _buttons[2].grab_focus())


func open(sim: CombatSim) -> void:
	_moves.text = _move_list(sim)
	visible = true
	get_tree().paused = true
	_buttons[0].grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


func _move_list(sim: CombatSim) -> String:
	var lines: Array[String] = ["LISTA DE MOVIMIENTOS", ""]
	for fighter in [sim.player, sim.enemy]:
		var f: FighterState = fighter
		var d := f.definition
		var punches := ComboData.chain_length(d, "punch")
		var kicks := ComboData.chain_length(d, "kick")
		lines.append("%s — %s" % [String(d["name"]).to_upper(), String(d["role"])])
		lines.append("  J×%d  Puños: %s" % [punches, _chain_text("punch", punches)])
		lines.append("  K×%d  Patadas: %s" % [kicks, _chain_text("kick", kicks)])
		var hint := String(d.get("technique_hint", ""))
		lines.append("  L  %s%s   ·   H  %s%s" % [String(d["technique"]), " (%s)" % hint if hint != "" else "",
			String(d["awakening"]), "" if f.awakening_available else " (bloqueado)"])
		lines.append("")
	lines.append("↓+J antiaéreo · ↓+K barrida · →+I pegado al rival: agarre")
	lines.append("Aire: J puño · K patada voladora · Cadena + I: lanzador o remate")
	lines.append("J,J,K,K mezcla puños y patadas sin romper el combo")
	lines.append("Golpe mientras el rival prepara el suyo: ¡CONTRAATAQUE! +25 %")
	lines.append("E cubrirse · Mayús correr · los combos largos hacen menos daño")
	return "\n".join(PackedStringArray(lines))


static func _chain_text(kind: String, length: int) -> String:
	var names := {
		"jab": "jab", "cross": "directo", "hook": "gancho", "uppercut": "uppercut",
		"kick_low": "baja", "kick_mid": "media", "kick_high": "alta", "kick_spin": "giratoria",
	}
	var parts: Array[String] = []
	for step in range(1, length + 1):
		parts.append(String(names[ComboData.strike_for(kind, length, step)]))
	return " → ".join(PackedStringArray(parts))


func _on_action(action: String) -> void:
	Sfx.play("confirm")
	match action:
		"resume":
			close()
			resume_requested.emit()
		"restart":
			close()
			restart_requested.emit()
		"options":
			_options.open()
		"quit":
			close()
			quit_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _options.visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		resume_requested.emit()
