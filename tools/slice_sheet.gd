extends SceneTree
## Prepara una hoja de sprites para un luchador.
##
##   godot --headless --path . -s res://tools/slice_sheet.gd -- --sheet RUTA.png --fighter ID [opciones]
##
## 1. Quita el color de fondo (el de la esquina superior izquierda, o el que digas).
## 2. Encuentra los cuadros de una de estas tres formas:
##    - automática: cada grupo de píxeles conectados es un cuadro (fondo liso);
##    - --cells: la hoja tiene celdas de un color (p. ej. fucsia) separadas por líneas
##      o huecos de otro (p. ej. gris); cada celda es un cuadro;
##    - --grid / --grid-cols + --grid-rows: rejilla fija.
## 3. Guarda tools/out/ID_preview.png: la hoja original con cada cuadro enmarcado y numerado.
## 4. Guarda assets/fighters/ID/ID_sheet.png: los cuadros en celdas iguales, pies abajo al centro.
## 5. Con --map, escribe el bloque "sprites" listo para pegar en scripts/data/catalog.gd.
##
## Opciones:
##   --bg auto|none|#rrggbb   color de fondo a quitar (auto por defecto)
##   --tolerance 0.04         margen de color para el fondo (0 a 1)
##   --min 8                  tamaño mínimo de un cuadro, en píxeles
##   --gap 2                  junta piezas separadas por este hueco o menos
##   --cells auto|#rrggbb     hoja con celdas: color de relleno de las celdas
##   --separator #rrggbb      con --cells: color de las líneas entre celdas (auto por defecto)
##   --grid ANCHOxALTO        rejilla fija de celdas de ese tamaño (p. ej. 64x64)
##   --grid-cols C --grid-rows F   rejilla fija de C columnas y F filas (calcula el tamaño)
##   --offset X,Y             con rejilla: margen antes de la primera celda
##   --spacing X,Y            con rejilla: hueco entre celdas
##   --columns 8              columnas de la hoja de salida
##   --map RUTA.json          qué cuadros forman cada pose, p. ej.
##                            {"idle": [0, 1, 2, 3], "jab": 5, "block": [10, 11]}

const OPTIONS := ["sheet", "fighter", "bg", "tolerance", "min", "gap", "cells", "separator",
	"grid", "grid-cols", "grid-rows", "offset", "spacing", "columns", "map"]

const DIGITS := [  # tipografía de 3x5 para numerar la vista previa
	"111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111",
]


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if not args.has("sheet") or not args.has("fighter"):
		printerr("Uso: godot --headless --path . -s res://tools/slice_sheet.gd -- --sheet hoja.png --fighter id [--map mapa.json]")
		quit(1)
		return
	var id := String(args["fighter"])
	var image := Image.load_from_file(String(args["sheet"]))
	if image == null:
		printerr("No se pudo abrir la hoja: " + String(args["sheet"]))
		quit(1)
		return
	image.convert(Image.FORMAT_RGBA8)

	var tolerance := float(args.get("tolerance", "0.04"))
	var min_size := int(args.get("min", "8"))
	var removed: Array = []  # colores quitados, para el informe
	var rects: Array[Rect2i] = []
	if args.has("cells"):
		# Primero las celdas (con el separador aún visible) y luego se vacían.
		var guess := SpriteSheet.guess_cell_colors(image)
		var fill: Color = guess[0] if String(args["cells"]) == "auto" else Color.html(String(args["cells"]))
		var separator: Color = Color.html(String(args["separator"])) if args.has("separator") else guess[1]
		if separator.is_equal_approx(fill):
			separator = guess[0] if not guess[0].is_equal_approx(fill) else guess[1]
		var cells := SpriteSheet.detect_cells(image, separator, tolerance, min_size)
		removed = [fill, separator]
		if args.has("bg") and String(args["bg"]) not in ["auto", "none"]:
			removed.append(Color.html(String(args["bg"])))
		SpriteSheet.remove_colors(image, removed, tolerance)
		rects = SpriteSheet.trim_all(image, cells)
		print("%d celdas encontradas (relleno %s, separador %s)" % [cells.size(), fill.to_html(false), separator.to_html(false)])
	else:
		var bg_arg := String(args.get("bg", "auto"))
		if bg_arg == "auto":
			removed = [SpriteSheet.guess_background(image)]
		elif bg_arg != "none":
			removed = [Color.html(bg_arg)]
		SpriteSheet.remove_colors(image, removed, tolerance)
		if args.has("grid") or args.has("grid-cols") or args.has("grid-rows"):
			var grid := _grid_cells(image, args)
			if grid.is_empty():
				quit(1)
				return
			rects = SpriteSheet.trim_all(image, grid)
		else:
			rects = SpriteSheet.detect_frames(image, min_size, int(args.get("gap", "2")))
			if rects.size() <= 2 and rects.size() > 0 and rects[0].get_area() > image.get_width() * image.get_height() / 4:
				print("AVISO: casi toda la hoja ha salido como un solo bloque. Si los cuadros están en")
				print("celdas de color separadas por líneas, usa --cells auto (o --grid-cols/--grid-rows).")
	if rects.is_empty():
		printerr("No se ha encontrado ningún cuadro. Prueba con --cells auto, --bg #rrggbb o --tolerance mayor.")
		quit(1)
		return

	var preview_path := "res://tools/out/%s_preview.png" % id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/out"))
	_preview(image, rects).save_png(ProjectSettings.globalize_path(preview_path))

	var packed := SpriteSheet.pack_uniform(image, rects, int(args.get("columns", "8")))
	var sheet_path := "res://assets/fighters/%s/%s_sheet.png" % [id, id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sheet_path.get_base_dir()))
	(packed["image"] as Image).save_png(ProjectSettings.globalize_path(sheet_path))

	var cell: Vector2i = packed["cell"]
	var columns: int = packed["columns"]
	var names := PackedStringArray()
	for c: Color in removed:
		if c.a > 0.5:
			names.append("#" + c.to_html(false))
	print("Colores quitados: %s" % (", ".join(names) if not names.is_empty() else "ninguno"))
	print("%d cuadros. Vista previa numerada: %s" % [rects.size(), preview_path])
	print("Hoja limpia: %s (celdas de %dx%d, %d columnas)" % [sheet_path, cell.x, cell.y, columns])
	for i in rects.size():
		print("  %3d  original %s  ->  %s" % [i, rects[i], SpriteSheet.cell_ref(sheet_path, cell, columns, i)])

	if args.has("map"):
		var map: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(args["map"])))
		if not (map is Dictionary):
			printerr("El mapa no es un JSON válido: " + String(args["map"]))
			quit(1)
			return
		print("\n# Pega esto en la entrada del luchador en scripts/data/catalog.gd:")
		print(_catalog_block(map, sheet_path, cell, columns, rects))
	else:
		print("\nMira la vista previa, apunta qué números forman cada pose y vuelve a lanzar con --map.")
	quit(0)


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
		if name not in OPTIONS:
			printerr("AVISO: la opción --%s no existe y se ignora. Opciones: --%s" % [name, ", --".join(OPTIONS)])
		if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
			out[name] = raw[i + 1]
			i += 2
		else:
			printerr("AVISO: falta el valor de --%s." % name)
			i += 1
	return out


func _pair(text: String, sep: String) -> Vector2i:
	var parts := text.split(sep)
	return Vector2i(parts[0].to_int(), parts[1].to_int() if parts.size() > 1 else parts[0].to_int())


## Celdas de una rejilla fija: por tamaño (--grid 64x64) o por número de columnas y filas
## (--grid-cols 8 --grid-rows 4), con margen (--offset) y hueco entre celdas (--spacing).
func _grid_cells(image: Image, args: Dictionary) -> Array[Rect2i]:
	var offset := _pair(String(args.get("offset", "0,0")), ",")
	var spacing := _pair(String(args.get("spacing", "0,0")), ",")
	var area := image.get_size() - offset
	var cols := int(args.get("grid-cols", "0"))
	var rows := int(args.get("grid-rows", "0"))
	var cell := Vector2i.ZERO
	if args.has("grid"):
		cell = _pair(String(args["grid"]), "x")
	if cols > 0:
		cell.x = (area.x - spacing.x * (cols - 1)) / cols
	if rows > 0:
		cell.y = (area.y - spacing.y * (rows - 1)) / rows
	if cell.x <= 0 or cell.y <= 0:
		printerr("Rejilla incompleta: usa --grid ANCHOxALTO, o --grid-cols y --grid-rows.")
		return []
	if cols <= 0:
		cols = (area.x + spacing.x) / (cell.x + spacing.x)
	if rows <= 0:
		rows = (area.y + spacing.y) / (cell.y + spacing.y)
	print("Rejilla: %d columnas x %d filas, celdas de %dx%d" % [cols, rows, cell.x, cell.y])
	var rects: Array[Rect2i] = []
	for i in cols * rows:
		var rect := SpriteSheet.grid_rect(cell, cols, i, offset, spacing)
		rects.append(rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())))
	return rects


func _preview(image: Image, rects: Array[Rect2i]) -> Image:
	var out := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.16, 0.16, 0.2))
	out.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	for i in rects.size():
		var r := rects[i].grow(1).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var red := Color(1, 0.25, 0.3)
		out.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 1), red)
		out.fill_rect(Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), red)
		out.fill_rect(Rect2i(r.position.x, r.position.y, 1, r.size.y), red)
		out.fill_rect(Rect2i(r.end.x - 1, r.position.y, 1, r.size.y), red)
		_number(out, str(i), r.position + Vector2i(2, 2))
	return out


func _number(img: Image, text: String, at: Vector2i) -> void:
	var box := Rect2i(at - Vector2i.ONE, Vector2i(text.length() * 4 + 1, 7))
	img.fill_rect(box.intersection(Rect2i(Vector2i.ZERO, img.get_size())), Color.BLACK)
	for c in text.length():
		var bits: String = DIGITS[text.unicode_at(c) - 48]
		for b in 15:
			var p := at + Vector2i(c * 4 + b % 3, b / 3)
			if bits[b] == "1" and Rect2i(Vector2i.ZERO, img.get_size()).has_point(p):
				img.set_pixelv(p, Color.YELLOW)


func _catalog_block(map: Dictionary, sheet_path: String, cell: Vector2i, columns: int, rects: Array[Rect2i]) -> String:
	var lines := PackedStringArray(['"sprites": {'])
	for key in map:
		var value: Variant = map[key]
		var indices: Array = value if value is Array else [value]
		var refs := PackedStringArray()
		for index in indices:
			if int(index) < 0 or int(index) >= rects.size():
				printerr("El cuadro %s de \"%s\" no existe (hay %d)." % [index, key, rects.size()])
				continue
			refs.append('"%s"' % SpriteSheet.cell_ref(sheet_path, cell, columns, int(index)))
		if refs.is_empty():
			continue
		if value is Array:
			lines.append('\t"%s": [%s],' % [key, ", ".join(refs)])
		else:
			lines.append('\t"%s": %s,' % [key, refs[0]])
	lines.append("},")
	# Todas las celdas tienen los pies en el mismo sitio.
	lines.append('"sprite_anchor": Vector2(%d, %d),' % [cell.x / 2, cell.y])
	# Que la pose de reposo mida unas 58 unidades, como el resto del reparto.
	var idle_height := float(cell.y)
	if map.has("idle"):
		var first: Variant = map["idle"][0] if map["idle"] is Array else map["idle"]
		if int(first) >= 0 and int(first) < rects.size():
			idle_height = rects[int(first)].size.y
	lines.append('"sprite_height": %.1f,  # ajústalo si se ve grande o pequeño' % (58.0 * cell.y / idle_height))
	return "\n".join(lines)
