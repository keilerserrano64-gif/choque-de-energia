extends Node
## Autoload "Controls": registra las acciones de teclado y mando al iniciar.
## Si prefieres editarlas desde Proyecto > Configuración > Mapa de entrada,
## crea allí una acción con el mismo nombre: este script no la sobrescribe.
##
## J1: W saltar (o Espacio) · A/D mover · S abajo · Mayús correr
##     J puño (combo de puños) · K patada (combo de patadas) · I golpe fuerte
##     E cubrirse (mantener) · L técnica · H despertar
## J2: ←/→ mover · ↑ saltar · ↓ abajo · Numpad 0 o Ñ correr
##     Numpad 1 o "," puño · Numpad 6 o "M" patada · Numpad 4 o "´" golpe fuerte
##     Numpad 5 o "Ç" cubrirse · Numpad 2 o "." técnica · Numpad 3 o "-" despertar
## Mandos: el primero controla a J1 y el segundo a J2
##     Cruceta/stick mover · ↑ saltar · X puño · A patada · RT golpe fuerte · LB cubrirse
##     B técnica · Y despertar · RB correr
## Las teclas usan la posición física (como en un teclado QWERTY), así que funcionan
## igual con la distribución española o la inglesa.

const P1_KEYS := {
	"left": [KEY_A], "right": [KEY_D], "jump": [KEY_W, KEY_SPACE], "down": [KEY_S],
	"run": [KEY_SHIFT], "attack": [KEY_J], "kick": [KEY_K], "heavy": [KEY_I], "block": [KEY_E],
	"special": [KEY_L], "awaken": [KEY_H],
}
const P2_KEYS := {
	"left": [KEY_LEFT], "right": [KEY_RIGHT], "jump": [KEY_UP], "down": [KEY_DOWN],
	"run": [KEY_KP_0, KEY_SEMICOLON], "attack": [KEY_KP_1, KEY_COMMA], "kick": [KEY_KP_6, KEY_M],
	"heavy": [KEY_KP_4, KEY_APOSTROPHE], "block": [KEY_KP_5, KEY_BACKSLASH],
	"special": [KEY_KP_2, KEY_PERIOD], "awaken": [KEY_KP_3, KEY_SLASH],
}
const PAD_BUTTONS := {
	"left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT],
	"jump": [JOY_BUTTON_DPAD_UP], "down": [JOY_BUTTON_DPAD_DOWN],
	"run": [JOY_BUTTON_RIGHT_SHOULDER], "attack": [JOY_BUTTON_X], "kick": [JOY_BUTTON_A],
	"block": [JOY_BUTTON_LEFT_SHOULDER],
	"special": [JOY_BUTTON_B], "awaken": [JOY_BUTTON_Y],
}
const PAD_AXES := {
	"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
	"jump": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0],
	"heavy": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}
const EXTRA_UI := {
	"ui_up": [KEY_W], "ui_down": [KEY_S], "ui_left": [KEY_A], "ui_right": [KEY_D],
	"ui_accept": [KEY_J], "ui_cancel": [KEY_L, KEY_BACKSPACE],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_player(0, P1_KEYS)
	_register_player(1, P2_KEYS)
	_register_keys("pause", [KEY_ESCAPE, KEY_P])
	_add_button("pause", JOY_BUTTON_START, -1)
	for action in EXTRA_UI:
		if InputMap.has_action(action):
			for keycode in EXTRA_UI[action]:
				InputMap.action_add_event(action, _key(keycode))
	# Espacio es "saltar": se quita de ui_accept para que no confirme en los menús a la vez.
	if InputMap.has_action("ui_accept"):
		for event in InputMap.action_get_events("ui_accept"):
			if event is InputEventKey:
				var key_event: InputEventKey = event
				if key_event.keycode == KEY_SPACE or key_event.physical_keycode == KEY_SPACE:
					InputMap.action_erase_event("ui_accept", event)


func _register_player(index: int, keys: Dictionary) -> void:
	for action in keys:
		var action_id := "p%d_%s" % [index + 1, action]
		if InputMap.has_action(action_id):
			continue
		InputMap.add_action(action_id, 0.45)
		for keycode in keys[action]:
			InputMap.action_add_event(action_id, _key(keycode))
		for button in PAD_BUTTONS.get(action, []):
			_add_button(action_id, button, index)
		if PAD_AXES.has(action):
			var axis_data: Array = PAD_AXES[action]
			var motion := InputEventJoypadMotion.new()
			motion.device = index
			motion.axis = axis_data[0]
			motion.axis_value = axis_data[1]
			InputMap.action_add_event(action_id, motion)


func _register_keys(action_id: String, keycodes: Array) -> void:
	if not InputMap.has_action(action_id):
		InputMap.add_action(action_id)
	for keycode in keycodes:
		InputMap.action_add_event(action_id, _key(keycode))


func _add_button(action_id: String, button: int, device: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = device
	InputMap.action_add_event(action_id, event)


func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


## Texto corto con la tecla principal de una acción (para mostrar en la UI).
func key_label(action_id: String) -> String:
	if not InputMap.has_action(action_id):
		return "?"
	for event in InputMap.action_get_events(action_id):
		if event is InputEventKey:
			var key_event: InputEventKey = event
			var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
			return OS.get_keycode_string(code)
	return "?"
