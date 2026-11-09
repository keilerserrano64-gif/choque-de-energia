extends CanvasLayer
## Autoload "Router": guarda la configuración del combate y cambia de escena
## con un fundido. Flujo: menú → selección → escenario → combate → resultado.

const SCENES := {
	"menu": "res://scenes/main_menu.tscn",
	"select": "res://scenes/character_select.tscn",
	"stage": "res://scenes/stage_select.tscn",
	"fight": "res://scenes/fight.tscn",
}
const MODE_NAMES := {
	"arcade": "ARCADE", "versus": "VS", "cpu": "VS CPU", "training": "ENTRENAMIENTO",
}

## arcade | versus | cpu | training
var mode := "cpu"
var p1_id := "brasa"
var p2_id := "onix"
var stage_id := "brumaria"
var difficulty_id := "challenging"
var arcade_ladder: Array[String] = []
var arcade_index := 0
var arcade_continues := 0

var _wipe: PixelWipe
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Transición pixelada: bloques que tapan la pantalla en diagonal y luego se retiran.
	_wipe = PixelWipe.new()
	add_child(_wipe)


func goto(scene_key: String, fade_time: float = 0.22) -> void:
	if _busy or not SCENES.has(scene_key):
		return
	_busy = true
	_wipe.mouse_filter = Control.MOUSE_FILTER_STOP
	_wipe.revealing = false
	_wipe.progress = 0.0
	var tween := create_tween()
	tween.tween_property(_wipe, "progress", 1.0, fade_time * 1.6)
	await tween.finished
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(SCENES[scene_key])
	await get_tree().process_frame
	_wipe.revealing = true
	var tween_out := create_tween()
	tween_out.tween_property(_wipe, "progress", 0.0, fade_time * 1.6)
	await tween_out.finished
	_wipe.revealing = false
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func begin(new_mode: String) -> void:
	mode = new_mode
	arcade_ladder.clear()
	arcade_index = 0
	arcade_continues = 0
	if mode == "training":
		difficulty_id = "standard"


## Modo que entiende CombatSim.
func sim_mode() -> String:
	if mode == "versus":
		return "versus"
	if mode == "training":
		return "training"
	return "cpu"


func is_cpu_mode() -> bool:
	return mode == "arcade" or mode == "cpu" or mode == "training"


func mode_label() -> String:
	return String(MODE_NAMES.get(mode, "VS CPU"))


# --- Arcade: escalera de siete rivales con dificultad creciente ---------------

func start_arcade(player_id: String) -> void:
	p1_id = player_id
	arcade_ladder.clear()
	for fighter in Catalog.FIGHTERS:
		if fighter["id"] != player_id:
			arcade_ladder.append(String(fighter["id"]))
	arcade_ladder.shuffle()
	arcade_index = 0
	arcade_continues = 0
	_prepare_arcade_fight()


func _prepare_arcade_fight() -> void:
	p2_id = arcade_ladder[arcade_index]
	stage_id = String(Catalog.STAGES[arcade_index % Catalog.STAGES.size()]["id"])
	if arcade_index < 2:
		difficulty_id = "standard"
	elif arcade_index < 5:
		difficulty_id = "challenging"
	else:
		difficulty_id = "expert"


## Pasa al siguiente rival. Devuelve false si ya no quedan (arcade completado).
func arcade_advance() -> bool:
	if arcade_index + 1 >= arcade_ladder.size():
		return false
	arcade_index += 1
	_prepare_arcade_fight()
	return true


func arcade_total() -> int:
	return arcade_ladder.size()
