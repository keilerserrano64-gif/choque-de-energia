extends Control
## Importador visual de luchadores.
##
## Ábrelo con tools\importar.bat (sin nada más) o, en el editor, abre
## tools/importador/importador.tscn y pulsa F6.
##   1. Elige la hoja y pulsa "Analizar": salen los cuadros numerados.
##   2. Escribe el id del luchador (y su nombre si es nuevo).
##   3. Elige una pose en la lista y haz clic en sus cuadros, en orden. Clic derecho
##      quita. La animación se ve abajo a la izquierda.
##   4. "Aplicar al juego" escribe todo (hoja, catálogo y estilo).

const Importer := preload("res://scripts/tools/fighter_importer.gd")
const MODES := [["auto", "Automático"], ["cells", "Celdas de color"], ["plain", "Fondo liso"], ["grid", "Rejilla fija"]]
const C_TEXT := Color(0.88, 0.9, 0.95)
const C_DIM := Color(0.6, 0.64, 0.72)
const C_OK := Color(0.45, 0.95, 0.55)
const C_WARN := Color(1.0, 0.8, 0.35)
const C_ERR := Color(1.0, 0.45, 0.45)

var image: Image
var rects: Array[Rect2i] = []
var duplicates := {}
## Clasificación de piezas (Importer.classify): tipo de cada cuadro y grupos de animación.
var info := {}
var analysis := {}
var map := {}  ## pose -> Array[int]
var frame_times := {}  ## pose -> segundos por cuadro
var current_pose := "idle"

var sheet_edit: LineEdit
var mode_option: OptionButton
var grid_edit: LineEdit
var tolerance_spin: SpinBox
var flip_check: CheckBox
var auto_check: CheckBox
var advanced: VBoxContainer
## Opciones avanzadas de texto: clave -> LineEdit (vacío = automático / por defecto).
var adv_edits := {}
var connect_check: CheckBox
var split_check: CheckBox
## Detector de la importación: "v2" en las nuevas; las guardadas conservan el suyo.
var detector := "v2"
var id_edit: LineEdit
var name_edit: LineEdit
var base_option: OptionButton
var pose_list: ItemList
var pose_desc: Label
var frames_label: Label
var time_spin: SpinBox
var custom_edit: LineEdit
var status: RichTextLabel
var sheet_view: SheetView
var preview: AnimPreview
var zoom_slider: HSlider
var file_dialog: FileDialog


func _ready() -> void:
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	if not window.mode in [Window.MODE_MAXIMIZED, Window.MODE_FULLSCREEN]:
		window.size = Vector2i(1440, 880)
		window.move_to_center()
	window.title = "Importador de luchadores · Choque de Energía"
	_build_ui()
	_fill_pose_list()
	_select_pose("idle")
	_log("Elige una hoja de sprites y pulsa [b]Analizar hoja[/b]. Con un id que ya se importó, pulsa [b]Cargar guardado[/b].", C_TEXT)
	# Arranque con argumentos: -- --fighter id  o  -- --sheet hoja.png
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		if args[i] == "--sheet":
			sheet_edit.text = args[i + 1]
		elif args[i] == "--fighter":
			id_edit.text = args[i + 1]
	if id_edit.text != "" and not Importer.load_config(id_edit.text).is_empty():
		_load_saved()
	elif sheet_edit.text != "":
		_analyze()


# --- Interfaz -------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 360
	add_child(split)

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 360
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.add_child(left)
	left_scroll.add_child(margin)

	var title := Label.new()
	title.text = "Importador de luchadores"
	title.add_theme_font_size_override("font_size", 20)
	left.add_child(title)

	_section(left, "1. Hoja de sprites")
	var row := HBoxContainer.new()
	sheet_edit = LineEdit.new()
	sheet_edit.placeholder_text = "hoja.png (ruta o relativa al proyecto)"
	sheet_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_edit.text_submitted.connect(func(_t: String) -> void: _analyze())
	row.add_child(sheet_edit)
	row.add_child(_button("Abrir…", _open_dialog))
	left.add_child(row)
	mode_option = OptionButton.new()
	for m: Array in MODES:
		mode_option.add_item(m[1])
	mode_option.item_selected.connect(func(_i: int) -> void: grid_edit.get_parent().visible = _mode() == "grid")
	left.add_child(_labeled("Modo", mode_option))
	grid_edit = LineEdit.new()
	grid_edit.placeholder_text = "64x64"
	grid_edit.tooltip_text = "Tamaño de cada celda de la rejilla, en píxeles."
	var grid_row := _labeled("Celda", grid_edit)
	grid_row.visible = false
	left.add_child(grid_row)
	tolerance_spin = SpinBox.new()
	tolerance_spin.min_value = 0.0
	tolerance_spin.max_value = 0.5
	tolerance_spin.step = 0.01
	tolerance_spin.value = 0.04
	tolerance_spin.tooltip_text = "Cuánto se puede parecer un color al del fondo para borrarlo."
	left.add_child(_labeled("Tolerancia", tolerance_spin))
	flip_check = CheckBox.new()
	flip_check.text = "Girar la hoja (el personaje mira a la izquierda)"
	left.add_child(flip_check)
	auto_check = CheckBox.new()
	auto_check.text = "Ajustes automáticos (hojas enormes, neblina, sprites apretados)"
	auto_check.button_pressed = true
	auto_check.tooltip_text = "Decide solo lo que dejes vacío en Opciones avanzadas."
	left.add_child(auto_check)
	var adv_toggle := CheckButton.new()
	adv_toggle.text = "Opciones avanzadas"
	left.add_child(adv_toggle)
	advanced = VBoxContainer.new()
	advanced.visible = false
	adv_toggle.toggled.connect(func(on: bool) -> void: advanced.visible = on)
	left.add_child(advanced)
	for item: Array in [
		["bg", "Fondo", "auto, none o #rrggbb"],
		["crop", "Recortar", "bordes: 2 o izq,arriba,der,abajo"],
		["scale", "Reducir", "auto (0.5 = mitad)"],
		["alpha", "Transparencia", "auto (128 borra la neblina)"],
		["gap", "Juntar piezas", "auto (2; -1 = no juntar)"],
		["lines", "Borrar líneas", "largo mínimo, p. ej. 20"],
		["min", "Tamaño mínimo", "8 píxeles"],
	]:
		var edit := LineEdit.new()
		edit.placeholder_text = item[2]
		edit.tooltip_text = item[2]
		adv_edits[item[0]] = edit
		advanced.add_child(_labeled(item[1], edit))
	connect_check = CheckBox.new()
	connect_check.text = "No unir píxeles que solo se tocan en diagonal"
	advanced.add_child(connect_check)
	split_check = CheckBox.new()
	split_check.text = "Separar sprites pegados (cuadros muy anchos)"
	advanced.add_child(split_check)
	left.add_child(_button("Analizar hoja", _analyze))

	_section(left, "2. Luchador")
	id_edit = LineEdit.new()
	id_edit.placeholder_text = "id: minúsculas, sin espacios"
	left.add_child(_labeled("Id", id_edit))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "nombre en el juego (opcional)"
	left.add_child(_labeled("Nombre", name_edit))
	base_option = OptionButton.new()
	base_option.tooltip_text = "Si el luchador es nuevo, copia las estadísticas y el estilo de este."
	for f: Dictionary in Catalog.FIGHTERS:
		base_option.add_item(String(f["id"]))
		if f["id"] == Importer.DEFAULT_BASE:
			base_option.select(base_option.item_count - 1)
	left.add_child(_labeled("Base", base_option))
	left.add_child(_button("Cargar guardado", _load_saved))

	_section(left, "3. Poses (elige una y haz clic en sus cuadros)")
	pose_list = ItemList.new()
	pose_list.custom_minimum_size.y = 230
	pose_list.item_selected.connect(func(i: int) -> void: _select_pose(String(pose_list.get_item_metadata(i))))
	left.add_child(pose_list)
	pose_desc = Label.new()
	pose_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pose_desc.add_theme_color_override("font_color", C_DIM)
	left.add_child(pose_desc)
	frames_label = Label.new()
	frames_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(frames_label)
	var edit_row := HBoxContainer.new()
	edit_row.add_child(_button("Quitar último", _remove_last))
	edit_row.add_child(_button("Vaciar pose", _clear_pose))
	left.add_child(edit_row)
	time_spin = SpinBox.new()
	time_spin.min_value = 0.02
	time_spin.max_value = 1.0
	time_spin.step = 0.01
	time_spin.value = 0.1
	time_spin.value_changed.connect(_on_time_changed)
	left.add_child(_labeled("Seg./cuadro", time_spin))
	var custom_row := HBoxContainer.new()
	custom_edit = LineEdit.new()
	custom_edit.placeholder_text = "otra pose: jab_anticipate, cross_impact…"
	custom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_edit.text_submitted.connect(func(_t: String) -> void: _add_custom_pose())
	custom_row.add_child(custom_edit)
	custom_row.add_child(_button("Añadir", _add_custom_pose))
	left.add_child(custom_row)
	preview = AnimPreview.new()
	preview.custom_minimum_size = Vector2(320, 220)
	left.add_child(preview)

	_section(left, "4. Guardar")
	var save_row := HBoxContainer.new()
	save_row.add_child(_button("Guardar mapa", _save_map))
	var apply_button := _button("Aplicar al juego", _apply)
	apply_button.add_theme_color_override("font_color", C_OK)
	save_row.add_child(apply_button)
	left.add_child(save_row)
	status = RichTextLabel.new()
	status.bbcode_enabled = true
	status.fit_content = true
	status.scroll_active = false
	status.selection_enabled = true
	status.custom_minimum_size.y = 80
	left.add_child(status)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var bar := HBoxContainer.new()
	var zoom_label := Label.new()
	zoom_label.text = "  Zoom"
	bar.add_child(zoom_label)
	zoom_slider = HSlider.new()
	zoom_slider.min_value = 1
	zoom_slider.max_value = 6
	zoom_slider.step = 0.5
	zoom_slider.value = 2
	zoom_slider.custom_minimum_size = Vector2(180, 24)
	zoom_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zoom_slider.value_changed.connect(func(v: float) -> void: sheet_view.set_zoom(v))
	bar.add_child(zoom_slider)
	var hint := Label.new()
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.clip_text = true
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.text = "   Clic: añadir  ·  Mayús + clic: animación entera  ·  Clic derecho: quitar  ·  Ctrl + rueda: zoom  ·  Verde = en la pose, azul = en otra, gris = repetido, oscuro = no es el personaje"
	hint.add_theme_color_override("font_color", C_DIM)
	bar.add_child(hint)
	right.add_child(bar)
	var sheet_scroll := ScrollContainer.new()
	sheet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sheet_scroll)
	sheet_view = SheetView.new()
	sheet_view.frame_clicked.connect(_on_frame_clicked)
	sheet_view.zoom_requested.connect(func(step: float) -> void: zoom_slider.value += step)
	sheet_scroll.add_child(sheet_view)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Imágenes"])
	file_dialog.current_dir = ProjectSettings.globalize_path("res://")
	file_dialog.size = Vector2i(900, 600)
	file_dialog.file_selected.connect(func(path: String) -> void:
		sheet_edit.text = _project_relative(path)
		_analyze())
	add_child(file_dialog)


func _section(parent: Control, text: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", C_WARN)
	parent.add_child(label)


func _labeled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 90
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b


func _log(text: String, color: Color = C_TEXT, clear := true) -> void:
	if clear:
		status.clear()
	status.push_color(color)
	status.append_text(text + "\n")
	status.pop()


func _mode() -> String:
	return String(MODES[mode_option.selected][0])


func _project_relative(path: String) -> String:
	var root := ProjectSettings.globalize_path("res://")
	return path.substr(root.length()) if path.begins_with(root) else path


func _open_dialog() -> void:
	file_dialog.popup_centered()


# --- Hoja -------------------------------------------------------------------------

func _options() -> Dictionary:
	var options := {"mode": _mode()}
	# 0.04 = automático (con el detector v2 la tolerancia se calcula según el fondo).
	if not is_equal_approx(tolerance_spin.value, 0.04):
		options["tolerance"] = snappedf(tolerance_spin.value, 0.001)
	if _mode() == "grid":
		options["grid"] = grid_edit.text.strip_edges()
	if not auto_check.button_pressed:
		options["auto"] = false
	options["detector"] = detector
	options["jpeg"] = sheet_edit.text.strip_edges().get_extension().to_lower() in ["jpg", "jpeg"]
	for key in adv_edits:
		var text := String((adv_edits[key] as LineEdit).text).strip_edges()
		if text == "" or text == "auto":
			continue
		options[key] = text if key in ["bg", "crop"] else (float(text) if key == "scale" else int(text))
	if connect_check.button_pressed:
		options["connect"] = 4
	if split_check.button_pressed:
		options["split"] = true
	return options


func _analyze() -> void:
	var path := sheet_edit.text.strip_edges()
	if path == "":
		_log("Primero elige una hoja (botón Abrir…).", C_WARN)
		return
	var source := Image.load_from_file(Importer.resolve_path(path))
	if source == null:
		_log("No se pudo abrir la hoja: %s" % path, C_ERR)
		return
	analysis = Importer.analyze(source, _options())
	if String(analysis["error"]) != "":
		_log(analysis["error"], C_ERR)
		return
	image = analysis["image"]
	rects = analysis["rects"]
	if flip_check.button_pressed:
		rects = Importer.flip_sheet(image, rects)
		analysis["rects"] = rects
		analysis["flipped"] = true
	duplicates = Importer.find_duplicates(image, rects)
	# Quita del mapa los números que ya no existen en esta hoja.
	for key in map.keys():
		var kept: Array = (map[key] as Array).filter(func(i: int) -> bool: return i < rects.size())
		if kept.is_empty():
			map.erase(key)
		else:
			map[key] = kept
	info = Importer.classify(image, rects, duplicates)
	sheet_view.setup(image, rects, duplicates)
	sheet_view.kinds = info["kinds"]
	sheet_view.group_of = info["group_of"]
	preview.setup(image, rects)
	# Hoja nueva sin mapa: el primer grupo de pie se propone como reposo.
	if map.is_empty():
		var draft := Importer.draft_map_groups(rects, info, duplicates)
		for key in draft:
			if Importer.is_valid_pose(String(key)) and draft[key] is Array:
				map[key] = Array(draft[key])
	_refresh()
	var counts: Dictionary = info["counts"]
	_log("%s · %d cuadros: %d del personaje en %d animaciones, %d efectos/textos/otros (atenuados)." % [
		analysis["info"], rects.size(), int(counts.get("personaje", 0)), (info["groups"] as Array).size(),
		rects.size() - int(counts.get("personaje", 0))], C_OK)
	_log("Mayús + clic añade la animación entera. Propuestas automáticas: %s (revísalas)." % ", ".join(PackedStringArray(map.keys())), C_TEXT, false)


# --- Poses ------------------------------------------------------------------------

func _pose_keys() -> Array:
	var keys: Array = Importer.POSES.keys()
	for key in map:
		if not keys.has(key):
			keys.append(key)
	return keys


func _fill_pose_list() -> void:
	var selected := current_pose
	pose_list.clear()
	for key: String in _pose_keys():
		var count := (map[key] as Array).size() if map.has(key) else 0
		var text := ("● " if count > 0 else "○ ") + key + (" (%d)" % count if count > 0 else "")
		var i := pose_list.add_item(text)
		pose_list.set_item_metadata(i, key)
		pose_list.set_item_tooltip(i, String(Importer.POSES.get(key, "Imagen de una fase de un golpe.")))
		if count > 0:
			pose_list.set_item_custom_fg_color(i, C_OK)
		if key == selected:
			pose_list.select(i)


func _select_pose(key: String) -> void:
	current_pose = key
	for i in pose_list.item_count:
		if pose_list.get_item_metadata(i) == key:
			pose_list.select(i)
			pose_list.ensure_current_is_visible()
	pose_desc.text =String(Importer.POSES.get(key, "Imagen de una fase de un golpe (<golpe>_<fase>)."))
	time_spin.set_value_no_signal(float(frame_times.get(key, Importer.DEFAULT_FRAME_TIME.get(key, 0.1))))
	_refresh_pose()


func _refresh() -> void:
	_fill_pose_list()
	_refresh_pose()


func _refresh_pose() -> void:
	var frames: Array = map.get(current_pose, [])
	frames_label.text = "%s: %s" % [current_pose, ", ".join(frames.map(func(i: int) -> String: return str(i))) if not frames.is_empty() else "(sin cuadros: haz clic en la hoja)"]
	var used := {}
	for key in map:
		for i: int in map[key]:
			used[i] = true
	if sheet_view != null:
		sheet_view.selected = frames
		sheet_view.used = used
		sheet_view.queue_redraw()
	if preview != null:
		preview.play(current_pose, frames, time_spin.value)


func _on_frame_clicked(index: int, button: int, whole_group := false) -> void:
	var frames: Array = map.get(current_pose, [])
	var group_of: Dictionary = info.get("group_of", {})
	if whole_group and group_of.has(index):
		var group: Array = info["groups"][group_of[index]]
		for i: int in group:
			if button == MOUSE_BUTTON_LEFT and not duplicates.has(i):
				frames.append(i)
			elif button == MOUSE_BUTTON_RIGHT:
				frames.erase(i)
		_log("Animación G%d (%d cuadros) %s \"%s\"." % [group_of[index] + 1, group.size(),
			"añadida a" if button == MOUSE_BUTTON_LEFT else "quitada de", current_pose], C_OK)
	elif button == MOUSE_BUTTON_LEFT:
		frames.append(index)
		var kinds: Array = info.get("kinds", [])
		if index < kinds.size() and kinds[index] != "personaje":
			_log("El cuadro %d parece %s, no el personaje." % [index, Importer.KIND_NAMES.get(kinds[index], kinds[index])], C_WARN)
		if duplicates.has(index):
			var dup: Dictionary = duplicates[index]
			_log("El cuadro %d es %s del %d: vale, pero puedes usar el original." % [
				index, Importer.duplicate_text(dup), dup["of"]], C_WARN)
	elif button == MOUSE_BUTTON_RIGHT:
		var at := frames.rfind(index)
		if at >= 0:
			frames.remove_at(at)
	if frames.is_empty():
		map.erase(current_pose)
	else:
		map[current_pose] = frames
	_refresh()


func _remove_last() -> void:
	var frames: Array = map.get(current_pose, [])
	if not frames.is_empty():
		frames.pop_back()
		if frames.is_empty():
			map.erase(current_pose)
	_refresh()


func _clear_pose() -> void:
	map.erase(current_pose)
	_refresh()


func _on_time_changed(value: float) -> void:
	frame_times[current_pose] = value
	preview.frame_time = value


func _add_custom_pose() -> void:
	var key := custom_edit.text.strip_edges().to_lower()
	if key == "":
		return
	if not Importer.is_valid_pose(key):
		var alias := String(Importer.ALIASES.get(key, ""))
		if alias == "":
			_log("\"%s\" no es una pose del juego. Mira la lista o usa <golpe>_<fase> (jab_anticipate, cross_impact…)." % key, C_ERR)
			return
		key = alias
	custom_edit.text = ""
	current_pose = key
	_fill_pose_list()
	_select_pose(key)


# --- Guardar y aplicar ------------------------------------------------------------

## Mapa en el formato del JSON: una pose de un cuadro se escribe como número.
func _map_json() -> Dictionary:
	var out := {}
	for key in map:
		var frames: Array = map[key]
		out[key] = frames[0] if frames.size() == 1 else frames.duplicate()
	var times := {}
	for key in frame_times:
		if map.has(key) and (map[key] as Array).size() > 1:
			times[key] = snappedf(frame_times[key], 0.01)
	if not times.is_empty():
		out["_frame_time"] = times
	return out


func _id() -> String:
	return id_edit.text.strip_edges().to_lower()


func _config() -> Dictionary:
	return {"sheet": sheet_edit.text.strip_edges(), "options": _options(), "map": _map_json(),
		"base": base_option.get_item_text(base_option.selected), "flip": flip_check.button_pressed,
		"name": name_edit.text.strip_edges()}


func _save_map() -> void:
	var id := _id()
	if not Importer.is_valid_id(id):
		_log("Escribe un id válido (minúsculas, números y _, empezando por letra).", C_ERR)
		return
	var path := ProjectSettings.globalize_path("%s/%s_mapa.json" % [Importer.OUT_DIR, id])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(Importer.whole_numbers(_map_json()), "  ", false) + "\n")
	file.close()
	Importer.save_config(id, _config())
	_log("Mapa guardado en %s y en %s." % [path, Importer.config_path(id)], C_OK)


func _load_saved() -> void:
	var id := _id()
	var config := Importer.load_config(id)
	if config.is_empty():
		_log("No hay importación guardada de \"%s\" (%s)." % [id, Importer.config_path(id)], C_WARN)
		return
	sheet_edit.text = String(config.get("sheet", ""))
	name_edit.text = String(config.get("name", ""))
	flip_check.button_pressed = bool(config.get("flip", false))
	var options: Dictionary = config.get("options", {})
	for m in MODES.size():
		if MODES[m][0] == String(options.get("mode", "auto")):
			mode_option.select(m)
	grid_edit.text = String(options.get("grid", ""))
	grid_edit.get_parent().visible = _mode() == "grid"
	tolerance_spin.value = float(options.get("tolerance", 0.04))
	auto_check.button_pressed = not options.has("auto") or bool(options["auto"])
	detector = String(options.get("detector", "legacy"))
	for key in adv_edits:
		(adv_edits[key] as LineEdit).text = str(options[key]) if options.has(key) else ""
	connect_check.button_pressed = int(options.get("connect", 8)) == 4
	split_check.button_pressed = bool(options.get("split", false))
	for i in base_option.item_count:
		if base_option.get_item_text(i) == String(config.get("base", Importer.DEFAULT_BASE)):
			base_option.select(i)
	map = {}
	frame_times = {}
	_analyze()
	if rects.is_empty():
		return
	var normalized := Importer.normalize_map(config.get("map", {}), rects.size(), duplicates)
	for key in normalized["poses"]:
		map[key] = Array(normalized["poses"][key])
	var times: Variant = normalized["settings"].get("frame_time", {})
	if times is Dictionary:
		for key in times:
			frame_times[key] = float(times[key])
	_refresh()
	_select_pose("idle")
	_log("Cargada la importación de \"%s\": %d poses." % [id, map.size()], C_OK)
	for w in normalized["warnings"]:
		_log(w, C_WARN, false)


func _apply() -> void:
	var id := _id()
	if rects.is_empty():
		_log("Primero analiza una hoja.", C_WARN)
		return
	var normalized := Importer.normalize_map(_map_json(), rects.size(), duplicates)
	var base := base_option.get_item_text(base_option.selected)
	var result := Importer.apply(id, analysis, normalized, {"write": true, "base": base,
		"name": name_edit.text.strip_edges()})
	if not result["ok"]:
		_log("No se ha aplicado:", C_ERR)
		for e in result["errors"]:
			_log("· " + e, C_ERR, false)
		return
	Importer.save_config(id, _config())
	var poses_path := "%s/%s_poses.png" % [Importer.OUT_DIR, id]
	Importer.poses_sheet(result["built"], normalized).save_png(ProjectSettings.globalize_path(poses_path))
	_log("¡Hecho!", C_OK)
	for m in result["messages"]:
		_log("· " + m, C_TEXT, false)
	for w in normalized["warnings"]:
		_log("· " + w, C_WARN, false)
	for w in Importer.review_map(normalized, rects, info):
		_log("· Revisa: " + w, C_WARN, false)
	_log("· Poses para revisar: " + poses_path, C_TEXT, false)
	_log("Cierra esta ventana, deja que Godot importe la hoja nueva y pulsa F5.", C_OK, false)


# --- Vista de la hoja ----------------------------------------------------------------

class SheetView extends Control:
	signal frame_clicked(index: int, button: int, whole_group: bool)
	signal zoom_requested(step: float)

	var texture: Texture2D
	var rects: Array[Rect2i] = []
	var duplicates := {}
	var kinds: Array = []
	var group_of := {}
	var selected: Array = []
	var used := {}
	var zoom := 2.0
	var hover := -1

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_STOP

	func setup(image: Image, frame_rects: Array[Rect2i], dups: Dictionary) -> void:
		texture = ImageTexture.create_from_image(image)
		rects = frame_rects
		duplicates = dups
		set_zoom(zoom)

	func set_zoom(value: float) -> void:
		zoom = value
		if texture != null:
			custom_minimum_size = Vector2(texture.get_size()) * zoom
		queue_redraw()

	func _index_at(pos: Vector2) -> int:
		var p := Vector2i(pos / zoom)
		var best := -1
		for i in rects.size():
			# Con cuadros solapados gana el más pequeño (el que se ve "encima").
			if rects[i].grow(1).has_point(p) and (best < 0 or rects[i].get_area() < rects[best].get_area()):
				best = i
		return best

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var index := _index_at(event.position)
			if index != hover:
				hover = index
				tooltip_text = "" if index < 0 else "Cuadro %d (%dx%d)%s%s%s" % [index, rects[index].size.x, rects[index].size.y,
					"" if not duplicates.has(index) else ("  ·  reflejo del %d" if duplicates[index]["mirror"] else "  ·  copia del %d") % duplicates[index]["of"],
					("  ·  animación G%d (Mayús + clic: entera)" % (group_of[index] + 1)) if group_of.has(index) else "",
					("  ·  parece " + String(kinds[index])) if index < kinds.size() and kinds[index] != "personaje" else ""]
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed:
			if event.ctrl_pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				zoom_requested.emit(0.5 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.5)
				accept_event()
			elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				var index := _index_at(event.position)
				if index >= 0:
					frame_clicked.emit(index, event.button_index, event.shift_pressed)
					accept_event()

	func _draw() -> void:
		if texture == null:
			draw_string(ThemeDB.fallback_font, Vector2(20, 40), "Aquí saldrá la hoja con los cuadros numerados.",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.64, 0.72))
			return
		var full := Rect2(Vector2.ZERO, Vector2(texture.get_size()) * zoom)
		draw_rect(full, Color(0.16, 0.17, 0.22))
		# Cuadros de ajedrez suaves para distinguir lo transparente.
		var check := 16.0
		for y in int(full.size.y / check) + 1:
			for x in int(full.size.x / check) + 1:
				if (x + y) % 2 == 0:
					draw_rect(Rect2(Vector2(x, y) * check, Vector2(check, check)).intersection(full), Color(0.19, 0.2, 0.26))
		draw_texture_rect(texture, full, false)
		var font := ThemeDB.fallback_font
		for i in rects.size():
			var r := Rect2(Vector2(rects[i].position) * zoom, Vector2(rects[i].size) * zoom)
			var color := Color(1, 0.3, 0.35, 0.8)
			if i < kinds.size() and kinds[i] != "personaje":
				# Efectos, textos, ilustraciones: atenuados para que no distraigan.
				draw_rect(r, Color(0.08, 0.09, 0.12, 0.6))
				color = Color(0.45, 0.45, 0.5, 0.35)
			if duplicates.has(i):
				color = Color(0.5, 0.52, 0.6, 0.6)
			if used.has(i):
				color = Color(0.4, 0.7, 1.0, 0.9)
			var order := selected.find(i)
			if order >= 0:
				color = Color(0.4, 1.0, 0.5)
			if i == hover:
				color = Color.WHITE
				draw_rect(r, Color(1, 1, 1, 0.08))
			draw_rect(r, color, false, 2.0 if order >= 0 or i == hover else 1.0)
			var label := str(i)
			var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_rect(Rect2(r.position, size + Vector2(4, 1)), Color(0, 0, 0, 0.75))
			draw_string(font, r.position + Vector2(2, size.y - 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.75, 0.75, 0.8) if duplicates.has(i) else Color.YELLOW)
			if order >= 0:
				# Orden dentro de la pose (puede salir varias veces).
				var marks := PackedStringArray()
				for k in selected.size():
					if selected[k] == i:
						marks.append(str(k + 1))
				var text := "#" + ",".join(marks)
				var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
				var at := Vector2(r.end.x - tsize.x - 4, r.end.y - 3)
				draw_rect(Rect2(at - Vector2(2, tsize.y - 2), tsize + Vector2(4, 2)), Color(0, 0.25, 0.05, 0.85))
				draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 1, 0.6))


# --- Animación de la pose ------------------------------------------------------------

class AnimPreview extends Control:
	var image: Image
	var rects: Array[Rect2i] = []
	var pose := ""
	var frames: Array = []
	var frame_time := 0.1
	var time := 0.0
	var _cache := {}

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func setup(sheet: Image, frame_rects: Array[Rect2i]) -> void:
		image = sheet
		rects = frame_rects
		_cache.clear()
		queue_redraw()

	func play(pose_name: String, pose_frames: Array, seconds: float) -> void:
		pose = pose_name
		frames = pose_frames.duplicate()
		frame_time = seconds
		time = 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		if frames.size() > 1:
			time += delta
			queue_redraw()

	func _texture(index: int) -> Texture2D:
		if not _cache.has(index):
			_cache[index] = ImageTexture.create_from_image(image.get_region(rects[index]))
		return _cache[index]

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.13, 0.17))
		var ground := size.y - 26.0
		draw_line(Vector2(10, ground), Vector2(size.x - 10, ground), Color(0.35, 0.4, 0.5), 1.0)
		if image == null or frames.is_empty():
			draw_string(font, Vector2(12, 22), "%s: sin cuadros" % pose if pose != "" else "Sin hoja",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.64, 0.72))
			return
		# Misma escala para todos los cuadros de la pose (como en el juego).
		var tallest := 1
		var widest := 1
		for i: int in frames:
			tallest = maxi(tallest, rects[i].size.y)
			widest = maxi(widest, rects[i].size.x)
		var scale := minf((ground - 30.0) / tallest, (size.x - 20.0) / widest)
		scale = maxf(1.0, floorf(scale)) if scale >= 1.0 else scale
		var k := int(floorf(time / maxf(frame_time, 0.016))) % frames.size()
		var index: int = frames[k]
		var feet := SpriteSheet.feet_point(image, rects[index])
		var tex := _texture(index)
		var pos := Vector2(size.x / 2.0 - feet.x * scale, ground - feet.y * scale)
		draw_texture_rect(tex, Rect2(pos, Vector2(tex.get_size()) * scale), false)
		draw_circle(Vector2(size.x / 2.0, ground), 2.5, Color(1, 0.4, 0.4))
		draw_string(font, Vector2(12, 20), "%s · cuadro %d (%d/%d)" % [pose, index, k + 1, frames.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.88, 0.9, 0.95))
		draw_string(font, Vector2(12, size.y - 8), "punto rojo = pies (así se apoyará en el suelo)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.64, 0.72))
