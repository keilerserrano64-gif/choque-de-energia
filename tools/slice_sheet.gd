extends SceneTree
## Importa un luchador desde una hoja de sprites (versión de terminal del importador).
##
## La forma fácil, desde la carpeta del proyecto (encuentra Godot sola):
##   tools\importar.bat --sheet hoja.png --fighter id              1) recorta y numera
##   tools\importar.bat --sheet hoja.png --fighter id --draft      2) borrador del mapa
##   tools\importar.bat --sheet hoja.png --fighter id --map mapa.json --apply
##   tools\importar.bat --fighter id --apply                       repetir con lo guardado
##
## O con Godot directamente:
##   godot --headless --path . -s res://tools/slice_sheet.gd -- --sheet hoja.png --fighter id ...
##
## Lo que hace:
##  - Quita el fondo y encuentra los cuadros (detecta solo si la hoja tiene celdas de color).
##  - tools/out/<id>_preview.png: la hoja con cada cuadro numerado. Los repetidos salen en
##    gris ("=N" copia, "<N" reflejo de N); los que usa el mapa, en verde.
##  - Valida el mapa: traduce nombres (kick -> finisher, salto -> jump...) y avisa de
##    números que no existen.
##  - tools/out/<id>_poses.png: cada pose con sus cuadros, para revisarla antes de jugar.
##  - Con --apply: guarda la hoja (solo los cuadros usados), escribe el luchador en
##    catalog.gd (lo crea si es nuevo), su estilo de animación y
##    assets/fighters/<id>/<id>_import.json para repetir la importación.

## Se carga con preload para que funcione aunque el editor no haya registrado la clase.
const Importer := preload("res://scripts/tools/fighter_importer.gd")

const OPTIONS := {
	"sheet": "hoja de sprites (PNG, JPG o WEBP)",
	"fighter": "id del luchador: minúsculas, números y _",
	"name": "nombre que se ve en el juego (luchador nuevo o para cambiarlo)",
	"base": "luchador del que copiar estadísticas si es nuevo (kakashi por defecto)",
	"map": "JSON con los cuadros de cada pose",
	"mode": "auto | cells | plain | grid (auto por defecto)",
	"cells": "auto | #rrggbb: hoja con celdas de ese color (equivale a --mode cells)",
	"separator": "#rrggbb: color de las líneas entre celdas",
	"bg": "auto | none | #rrggbb: fondo a quitar",
	"tolerance": "margen de color, de 0 a 1 (0.04)",
	"crop": "N o izq,arriba,der,abajo: píxeles a quitar de los bordes (capturas de pantalla)",
	"lines": "N: borra líneas rectas de N px o más (subrayados que unen cuadros)",
	"connect": "8 | 4: con 4, los píxeles que solo se tocan en diagonal no unen cuadros",
	"scale": "0.5: reduce la hoja antes de analizarla (hojas enormes)",
	"alpha": "N (0-255): borra los píxeles casi transparentes",
	"detector": "v2 (rápido, cuadros a tamaño completo; el de las importaciones nuevas) | legacy",
	"min": "tamaño mínimo de un cuadro en píxeles (8)",
	"gap": "junta piezas separadas por este hueco o menos (2); -1 = no juntar (hojas apretadas)",
	"grid": "ANCHOxALTO: rejilla fija",
	"grid-cols": "columnas de la rejilla",
	"grid-rows": "filas de la rejilla",
	"offset": "X,Y: margen antes de la primera celda",
	"spacing": "X,Y: hueco entre celdas",
	"columns": "columnas de la hoja que se genera (8)",
	"zoom": "aumento de la vista previa (2)",
	"calidad": "2 o 4: hoja HD que se genera al aplicar (4; ver scripts/tools/calidad_luchador.gd)",
}
const FLAGS := {
	"apply": "escribe el luchador en el juego (sin esto solo enseña el bloque)",
	"sin-calidad": "no genera la hoja HD ni estabiliza los cuadros al aplicar",
	"draft": "crea tools/out/<id>_mapa.json con las filas de la hoja para rellenar",
	"flip": "gira la hoja: para personajes que miran a la izquierda",
	"no-auto": "no hace ajustes automáticos (reducir, neblina, sprites apretados o pegados)",
	"split": "parte los cuadros mucho más anchos que los demás (sprites pegados)",
	"all-frames": "guarda todos los cuadros en la hoja, no solo los usados",
	"list": "lista cada cuadro con su posición en la hoja original",
	"help": "esta ayuda",
}


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.is_empty() or args.has("help") or not args.has("fighter"):
		_usage()
		return 0 if args.has("help") else 1
	var id := String(args["fighter"]).strip_edges().to_lower()
	if not Importer.is_valid_id(id):
		printerr("El id \"%s\" no vale: usa minúsculas, números y _, empezando por una letra." % id)
		return 1

	# Lo guardado en la importación anterior sirve de valor por defecto.
	var config := Importer.load_config(id)
	if not config.is_empty():
		print("Usando lo guardado en %s (lo que pongas en la línea de órdenes manda)." % Importer.config_path(id))
	var sheet_arg := String(args.get("sheet", config.get("sheet", "")))
	if sheet_arg == "":
		printerr("Falta --sheet hoja.png (y no hay importación guardada de \"%s\")." % id)
		return 1
	var sheet_file := Importer.resolve_path(sheet_arg)
	var source := Image.load_from_file(sheet_file)
	if source == null:
		printerr("No se pudo abrir la hoja: " + sheet_file)
		return 1

	var options: Dictionary = (config.get("options", {}) as Dictionary).duplicate() if config.get("options", {}) is Dictionary else {}
	for key in ["mode", "separator", "bg", "tolerance", "min", "gap", "grid", "offset", "spacing", "crop", "lines", "connect", "scale", "alpha", "detector"]:
		if args.has(key):
			options[key] = args[key]
	if args.has("cells"):
		options["mode"] = "cells"
		options["fill"] = args["cells"]
	if args.has("grid-cols"):
		options["grid_cols"] = args["grid-cols"]
	if args.has("grid-rows"):
		options["grid_rows"] = args["grid-rows"]
	if (args.has("grid") or args.has("grid-cols") or args.has("grid-rows")) and not args.has("mode"):
		options["mode"] = "grid"
	if args.has("split"):
		options["split"] = true
	if args.has("no-auto"):
		options["auto"] = false
	options["jpeg"] = sheet_file.get_extension().to_lower() in ["jpg", "jpeg"]
	# Las importaciones nuevas usan el detector v2; las guardadas siguen con el suyo para
	# que los números de sus cuadros (y su mapa) no cambien.
	if not options.has("detector") and config.is_empty():
		options["detector"] = "v2"
	var flip := args.has("flip") or bool(config.get("flip", false))

	var analysis := Importer.analyze(source, options)
	if String(analysis["error"]) != "":
		printerr(analysis["error"])
		return 1
	var image: Image = analysis["image"]
	var rects: Array[Rect2i] = analysis["rects"]
	if flip:
		rects = Importer.flip_sheet(image, rects)
		analysis["rects"] = rects
		analysis["flipped"] = true
		print("Hoja girada en horizontal (--flip).")
	var duplicates := Importer.find_duplicates(image, rects)
	print("%s. %d cuadros (%d repetidos o reflejados)." % [analysis["info"], rects.size(), duplicates.size()])
	var info := Importer.classify(image, rects, duplicates)
	var counts: Dictionary = info["counts"]
	var kinds_text := PackedStringArray()
	for kind in ["personaje", "variante", "efecto", "texto", "arte", "pieza", "marco"]:
		if counts.has(kind):
			kinds_text.append("%d %s" % [counts[kind], Importer.KIND_NAMES[kind]])
	print("Piezas: %s." % ", ".join(kinds_text))
	var groups: Array = info["groups"]
	print("Animaciones del personaje (grupos):")
	for g in groups.size():
		var marks := PackedStringArray()
		for i: int in groups[g]:
			marks.append(str(i) + ("*" if duplicates.has(i) else ""))
		var hint := Importer.group_hint(rects, groups[g], info)
		print("  G%-3d %s%s" % [g + 1, " ".join(marks), ("   <- " + hint) if hint != "" else ""])
	if not duplicates.is_empty():
		print("  (* = repetido o reflejo de otro cuadro; no hace falta usarlo)")
	if args.has("list"):
		for i in rects.size():
			print("  %3d  %s" % [i, rects[i]])

	# Mapa: el de --map, si no el guardado.
	var map: Dictionary = {}
	var map_source := ""
	if args.has("map"):
		var map_file := Importer.resolve_path(String(args["map"]))
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(map_file)) if FileAccess.file_exists(map_file) else null
		if not (parsed is Dictionary):
			printerr("El mapa no existe o no es un JSON válido: " + map_file)
			printerr("Ejemplo: {\"idle\": [0, 1, 2], \"walk\": [5, 6, 7], \"jab\": 9, \"finisher\": 12}")
			return 1
		map = parsed
		map_source = String(args["map"])
	elif config.get("map", null) is Dictionary:
		map = config["map"]
		map_source = "importación guardada"

	var normalized := {}
	var used: Array[int] = []
	if not map.is_empty():
		normalized = Importer.normalize_map(map, rects.size(), duplicates)
		used = Importer.used_frames(normalized["poses"])
		if normalized.get("settings", {}).get("flip", false) and not flip:
			print("AVISO: el mapa pide _flip; usa --flip para girar la hoja.")

	var zoom := int(args.get("zoom", "2"))
	var preview_path := "%s/%s_preview.png" % [Importer.OUT_DIR, id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Importer.OUT_DIR))
	Importer.preview(image, rects, duplicates, used, zoom).save_png(ProjectSettings.globalize_path(preview_path))
	print("Vista previa numerada: %s" % preview_path)
	var groups_path := "%s/%s_grupos.png" % [Importer.OUT_DIR, id]
	Importer.groups_sheet(image, rects, info).save_png(ProjectSettings.globalize_path(groups_path))
	print("Animaciones del personaje, ordenadas: %s  (la más fácil de leer)" % groups_path)

	if args.has("draft"):
		var draft_path := "%s/%s_mapa.json" % [Importer.OUT_DIR, id]
		var draft := Importer.draft_map_groups(rects, info, duplicates)
		var file := FileAccess.open(ProjectSettings.globalize_path(draft_path), FileAccess.WRITE)
		file.store_string(JSON.stringify(Importer.whole_numbers(draft), "  ", false) + "\n")
		file.close()
		print("Borrador del mapa: %s  (cambia cada grupo_N por su pose y úsalo con --map)" % draft_path)

	if map.is_empty():
		print("\nSiguiente paso: mira la vista previa, escribe el mapa (o usa --draft) y lanza con --map mapa.json --apply.")
		return 0

	print("\nMapa (%s): %d poses, %d cuadros distintos." % [map_source, (normalized["poses"] as Dictionary).size(), used.size()])
	for w in normalized["warnings"]:
		print("  AVISO: " + w)
	for w in Importer.review_map(normalized, rects, info):
		print("  REVISA: " + w)
	for e in normalized["errors"]:
		printerr("  ERROR: " + e)
	if not (normalized["errors"] as PackedStringArray).is_empty():
		return 1

	var write := args.has("apply")
	var base := String(args.get("base", config.get("base", Importer.DEFAULT_BASE)))
	var display_name := String(args.get("name", ""))
	var result := Importer.apply(id, analysis, normalized, {
		"write": write, "base": base, "name": display_name,
		"columns": int(args.get("columns", "8")), "pack_all": args.has("all-frames"), "calidad": 0 if args.has("sin-calidad") else int(args.get("calidad", "4")),
	})
	for e in result["errors"]:
		printerr("ERROR: " + e)
	if not result["ok"]:
		return 1
	for m in result["messages"]:
		print(m)
	var poses_path := "%s/%s_poses.png" % [Importer.OUT_DIR, id]
	Importer.poses_sheet(result["built"], normalized).save_png(ProjectSettings.globalize_path(poses_path))
	print("Poses para revisar: %s" % poses_path)

	if not write:
		print("\n# Bloque para catalog.gd (o vuelve a lanzar con --apply y se escribe solo):")
		print(result["block"])
		return 0

	var saved_options := options.duplicate()
	Importer.save_config(id, {
		"sheet": sheet_arg, "options": saved_options, "map": map, "base": base, "flip": flip,
		"name": display_name if display_name != "" else String(config.get("name", "")),
	})
	print("Importación guardada en %s: la próxima vez basta con --fighter %s --apply." % [Importer.config_path(id), id])
	print("\nListo. Abre Godot (deja que importe la hoja nueva) y pulsa F5.")
	return 0


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < raw.size():
		var key := raw[i]
		if not key.begins_with("--"):
			printerr("AVISO: no entiendo \"%s\" (las opciones empiezan por --)." % key)
			i += 1
			continue
		var name := key.substr(2)
		if FLAGS.has(name):
			out[name] = true
			i += 1
			continue
		if not OPTIONS.has(name):
			printerr("AVISO: la opción --%s no existe y se ignora (--help para verlas)." % name)
		if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
			out[name] = raw[i + 1]
			i += 2
		else:
			printerr("AVISO: falta el valor de --%s." % name)
			i += 1
	return out


func _usage() -> void:
	print("Importador de luchadores de Choque de Energía\n")
	print("  tools\\importar.bat --sheet hoja.png --fighter id [opciones]\n")
	print("Opciones con valor:")
	for key in OPTIONS:
		print("  --%-11s %s" % [key, OPTIONS[key]])
	print("Interruptores:")
	for key in FLAGS:
		print("  --%-11s %s" % [key, FLAGS[key]])
	print("\nPoses del mapa:")
	for key in Importer.POSES:
		print("  %-16s %s" % [key, Importer.POSES[key]])
	print("  <golpe>_<fase>   imagen de una fase de un golpe, p. ej. jab_anticipate, cross_impact")
	print("  Ajustes: \"_frame_time\": {\"walk\": 0.08}, \"_height\": 65 (tamaño en el juego)")
	print("           \"_offset\": {\"105\": [dx, dy]} mueve un cuadro mal colocado, \"_out_scale\": 0.5 tamaño de la hoja final")
