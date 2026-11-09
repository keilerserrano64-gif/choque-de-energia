class_name PlayerInput
extends RefCounted
## Lee el InputMap de Godot para cada jugador y guarda las pulsaciones del
## cuadro hasta que CombatSim las consume (equivale a src/input.js).
##
## Acciones registradas por el autoload Controls: p1_left, p1_right, p1_jump,
## p1_down, p1_run, p1_attack (puño), p1_kick (patada), p1_heavy, p1_block, p1_special, p1_awaken
## (y lo mismo con p2_). En los modos contra la CPU y entrenamiento, el jugador 1
## puede usar también las teclas del jugador 2 (flechas, numpad), como en la versión web.

const ACTIONS := ["left", "right", "jump", "down", "run", "attack", "kick", "heavy", "block", "special", "awaken"]
const PRESS_ACTIONS := ["jump", "attack", "kick", "heavy", "special", "awaken"]

var _pressed: Dictionary = {}
var enabled := true


static func action_name(player_index: int, action: String) -> String:
	return "p%d_%s" % [player_index + 1, action]


## Llamar una vez por cuadro de física, antes de CombatSim.update().
func poll() -> void:
	if not enabled:
		return
	for player_index in range(2):
		for action in PRESS_ACTIONS:
			var action_id := action_name(player_index, action)
			if InputMap.has_action(action_id) and Input.is_action_just_pressed(action_id):
				_pressed[action_id] = true


func _sources(player_index: int, mode: String) -> Array:
	if mode == "versus":
		return [player_index]
	return [0, 1] if player_index == 0 else []


func is_down(player_index: int, action: String, mode: String) -> bool:
	if not enabled:
		return false
	for source in _sources(player_index, mode):
		var action_id := action_name(source, action)
		if InputMap.has_action(action_id) and Input.is_action_pressed(action_id):
			return true
	return false


func consume_press(player_index: int, action: String, mode: String) -> bool:
	var pressed := false
	for source in _sources(player_index, mode):
		var action_id := action_name(source, action)
		if _pressed.has(action_id):
			_pressed.erase(action_id)
			pressed = true
	return pressed


func clear_pressed() -> void:
	_pressed.clear()
