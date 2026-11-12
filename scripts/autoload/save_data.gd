extends Node
## Autoload "SaveData": monedas, despertares desbloqueados y opciones.
## Se guarda en user://choque_save.json (en Windows: %APPDATA%/Godot/app_userdata/...).

signal changed

const MENU_ITEMS := ["arcade", "versus", "cpu", "training", "options", "store", "quit"]

const PATH := "user://choque_save.json"

var last_menu_item := ""
var coins := 0
var unlocked_forms: Array[String] = []
var music_volume := 60
var effects_volume := 80
var announcer := true
var skip_intro := false
var fullscreen := false
var show_hitboxes := true
var calidad_hd := true  ## luchadores en alta calidad (hojas _hd generadas por calidad_luchador.gd)
var screen_effects := true  ## shaders de pantalla en los golpes pesados (ondas, destellos)
var arcade_clears := 0


func _ready() -> void:
	load_data()
	apply_display()


func load_data() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var text := FileAccess.get_file_as_string(PATH)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("No se pudo leer el progreso guardado. Se usará una partida nueva.")
		return
	var data: Dictionary = parsed
	var menu_item = data.get("last_menu_item", "")
	last_menu_item = menu_item if menu_item is String and MENU_ITEMS.has(menu_item) else ""
	coins = clampi(int(data.get("coins", 0)), 0, 1000000)
	unlocked_forms.clear()
	var forms = data.get("unlocked_forms", [])
	if forms is Array:
		for id in forms:
			var fighter_id := String(id)
			if Catalog.has_fighter(fighter_id) and not unlocked_forms.has(fighter_id):
				unlocked_forms.append(fighter_id)
	music_volume = clampi(int(data.get("music_volume", music_volume)), 0, 100)
	effects_volume = clampi(int(data.get("effects_volume", effects_volume)), 0, 100)
	announcer = bool(data.get("announcer", announcer))
	skip_intro = bool(data.get("skip_intro", skip_intro))
	fullscreen = bool(data.get("fullscreen", fullscreen))
	show_hitboxes = bool(data.get("show_hitboxes", show_hitboxes))
	screen_effects = bool(data.get("screen_effects", screen_effects))
	calidad_hd = bool(data.get("calidad_hd", calidad_hd))
	FighterPainter.calidad_hd = calidad_hd
	arcade_clears = maxi(0, int(data.get("arcade_clears", 0)))


func save() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("No se pudo guardar el progreso: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({
		"last_menu_item": last_menu_item,
		"coins": coins,
		"unlocked_forms": unlocked_forms,
		"music_volume": music_volume,
		"effects_volume": effects_volume,
		"announcer": announcer,
		"skip_intro": skip_intro,
		"fullscreen": fullscreen,
		"show_hitboxes": show_hitboxes,
		"screen_effects": screen_effects,
		"calidad_hd": calidad_hd,
		"arcade_clears": arcade_clears,
	}, "\t"))
	changed.emit()


## Recuerda únicamente opciones conocidas del menú.
func remember_menu_item(id: String) -> void:
	if not MENU_ITEMS.has(id) or last_menu_item == id:
		return
	last_menu_item = id
	save()


func is_unlocked(fighter_id: String) -> bool:
	return unlocked_forms.has(fighter_id)


## Compra el despertar de un luchador. Devuelve false si faltan monedas.
func unlock(fighter_id: String) -> bool:
	if is_unlocked(fighter_id):
		return true
	if coins < Catalog.FORM_COST:
		return false
	coins -= Catalog.FORM_COST
	unlocked_forms.append(fighter_id)
	save()
	return true


func add_coins(amount: int) -> void:
	coins = clampi(coins + amount, 0, 1000000)
	save()


func apply_display() -> void:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
