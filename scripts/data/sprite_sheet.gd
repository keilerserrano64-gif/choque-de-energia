class_name SpriteSheet
extends RefCounted
## Recorta cuadros de una hoja de sprites (un PNG con todos los cuadros juntos).
##
## En el catálogo, un cuadro se escribe como "ruta#x,y,ancho,alto", por ejemplo
##   "idle": "res://assets/fighters/volt/volt_sheet.png#0,0,96,128"
## y una animación en bucle como una lista de esos textos. FighterPainter los
## reconoce y pide la textura recortada a esta clase.
##
## La parte de análisis (fondo, detección de cuadros, celdas iguales) la usa
## tools/slice_sheet.gd para preparar la hoja; en el juego solo se recorta.

const SEPARATOR := "#"

static var _images: Dictionary = {}  ## ruta de la hoja -> Image
static var _frames: Dictionary = {}  ## referencia completa -> Texture2D


# --- Referencias "ruta#x,y,ancho,alto" ---------------------------------------

static func is_ref(path: String) -> bool:
	return path.contains(SEPARATOR)


static func make_ref(sheet_path: String, rect: Rect2i) -> String:
	return "%s%s%d,%d,%d,%d" % [sheet_path, SEPARATOR, rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## Devuelve [ruta de la hoja, Rect2i]. El rectángulo es vacío si el texto está mal escrito.
static func parse_ref(ref: String) -> Array:
	var cut := ref.rfind(SEPARATOR)
	if cut < 0:
		return [ref, Rect2i()]
	var parts := ref.substr(cut + 1).split(",")
	if parts.size() != 4:
		return [ref.substr(0, cut), Rect2i()]
	var rect := Rect2i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int(), parts[3].to_int())
	return [ref.substr(0, cut), rect]


## Referencia de la celda número `index` de una hoja en rejilla (se cuenta por filas
## desde arriba a la izquierda, empezando en 0).
static func cell_ref(sheet_path: String, cell: Vector2i, columns: int, index: int,
		offset := Vector2i.ZERO, separation := Vector2i.ZERO) -> String:
	return make_ref(sheet_path, grid_rect(cell, columns, index, offset, separation))


static func grid_rect(cell: Vector2i, columns: int, index: int,
		offset := Vector2i.ZERO, separation := Vector2i.ZERO) -> Rect2i:
	var col := index % columns
	var row := index / columns
	var pos := offset + Vector2i(col * (cell.x + separation.x), row * (cell.y + separation.y))
	return Rect2i(pos, cell)


# --- Uso en el juego ----------------------------------------------------------

## Textura del cuadro. null si la hoja no existe o el rectángulo se sale de ella.
static func frame_texture(ref: String) -> Texture2D:
	if _frames.has(ref):
		return _frames[ref]
	var parsed := parse_ref(ref)
	var rect: Rect2i = parsed[1]
	var image := load_image(String(parsed[0]))
	var tex: Texture2D = null
	if image != null and rect.has_area() and Rect2i(Vector2i.ZERO, image.get_size()).encloses(rect):
		tex = ImageTexture.create_from_image(image.get_region(rect))
	elif image != null:
		push_error("SpriteSheet: el cuadro %s se sale de la hoja (%dx%d)." % [ref, image.get_width(), image.get_height()])
	_frames[ref] = tex
	return tex


## Imagen RGBA8 de la hoja, guardada en caché. Sirve con hojas importadas (res://)
## y con archivos sueltos del disco (lo que usa la herramienta).
static func load_image(path: String) -> Image:
	if _images.has(path):
		return _images[path]
	var image: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			image = tex.get_image()
	if image == null:
		image = Image.load_from_file(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	if image != null:
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
	_images[path] = image
	return image


static func clear_cache() -> void:
	_images.clear()
	_frames.clear()


# --- Análisis de la hoja (herramienta) -----------------------------------------

## Color del fondo: el de la esquina superior izquierda si es opaco; si no, transparente.
static func guess_background(image: Image) -> Color:
	var corner := image.get_pixel(0, 0)
	return corner if corner.a > 0.5 else Color(0, 0, 0, 0)


static func _same_color(data: PackedByteArray, i: int, c: Color, tolerance: float) -> bool:
	var t := int(tolerance * 255.0)
	return absi(data[i] - c.r8) <= t and absi(data[i + 1] - c.g8) <= t and absi(data[i + 2] - c.b8) <= t


## Pone transparentes los píxeles de uno o varios colores (tolerancia de 0 a 1).
## La imagen tiene que estar en RGBA8.
static func remove_colors(image: Image, colors: Array, tolerance := 0.04) -> void:
	var solid: Array[Color] = []
	for c: Color in colors:
		if c.a > 0.5:
			solid.append(c)
	if solid.is_empty():
		return
	var data := image.get_data()
	for i in range(0, data.size(), 4):
		for c in solid:
			if _same_color(data, i, c, tolerance):
				data[i] = 0
				data[i + 1] = 0
				data[i + 2] = 0
				data[i + 3] = 0
				break
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


static func remove_background(image: Image, background: Color, tolerance := 0.04) -> void:
	remove_colors(image, [background], tolerance)


## Los dos colores que más se repiten (muestrea uno de cada `step` píxeles).
static func dominant_colors(image: Image, step := 3) -> Array[Color]:
	var data := image.get_data()
	var counts := {}
	for i in range(0, data.size(), 4 * step):
		if data[i + 3] < 128:
			continue
		var key := (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
		counts[key] = counts.get(key, 0) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a, b) -> bool: return counts[a] > counts[b])
	var out: Array[Color] = []
	for key in keys.slice(0, 2):
		out.append(Color8((key >> 16) & 255, (key >> 8) & 255, key & 255))
	return out


## Hojas con celdas: cada cuadro va en un rectángulo de color de relleno (p. ej. fucsia)
## separado de los demás por líneas o huecos de otro color (p. ej. gris). Devuelve
## [color de relleno, color separador] adivinados: los dos más repetidos; el de relleno
## es el más saturado (los separadores suelen ser gris, blanco o negro).
static func guess_cell_colors(image: Image) -> Array[Color]:
	var top := dominant_colors(image)
	if top.size() < 2:
		return [top[0] if top.size() > 0 else Color.MAGENTA, Color(0, 0, 0, 0)]
	if top[1].s > top[0].s:
		return [top[1], top[0]]
	return [top[0], top[1]]


## Busca las celdas: zonas conectadas de píxeles que NO son del color separador.
## Devuelve sus rectángulos en orden de lectura (las menores de `min_size` se descartan).
static func detect_cells(image: Image, separator: Color, tolerance := 0.04, min_size := 8) -> Array[Rect2i]:
	var data := image.get_data()
	var mask := PackedByteArray()
	mask.resize(image.get_width() * image.get_height())
	for p in mask.size():
		var i := p * 4
		if data[i + 3] >= 128 and not _same_color(data, i, separator, tolerance):
			mask[p] = 1
	return _filter_sort(_components(mask, image.get_width(), image.get_height()), min_size)


## Rectángulo de los píxeles opacos dentro de `rect` (vacío si no hay nada dibujado).
static func trim(image: Image, rect: Rect2i) -> Rect2i:
	var used := image.get_region(rect).get_used_rect()
	return Rect2i(used.position + rect.position, used.size) if used.has_area() else Rect2i()


## Recorta cada celda a lo dibujado y se queda con las que tienen algo.
static func trim_all(image: Image, rects: Array[Rect2i]) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for rect in rects:
		var t := trim(image, rect)
		if t.has_area():
			out.append(t)
	return out


## Busca los cuadros de una hoja sin rejilla: cada grupo de píxeles opacos conectados
## es una pieza; las piezas a `merge_gap` píxeles o menos se juntan (pelo, chispas,
## armas sueltas). Descarta lo que mida menos de `min_size` de ancho o alto (textos,
## motas). Devuelve los rectángulos ordenados por filas, de izquierda a derecha.
## Si todo sale en uno o dos bloques enormes, la hoja tiene celdas: usa detect_cells.
static func detect_frames(image: Image, min_size := 8, merge_gap := 2) -> Array[Rect2i]:
	var data := image.get_data()
	var mask := PackedByteArray()
	mask.resize(image.get_width() * image.get_height())
	for p in mask.size():
		if data[p * 4 + 3] > 0:
			mask[p] = 1
	var boxes := _components(mask, image.get_width(), image.get_height())
	return _filter_sort(_merge_close(boxes, merge_gap), min_size)


static func _filter_sort(boxes: Array[Rect2i], min_size: int) -> Array[Rect2i]:
	var kept: Array[Rect2i] = []
	for box in boxes:
		if box.size.x >= min_size and box.size.y >= min_size:
			kept.append(box)
	return sort_reading_order(kept)


## Rectángulos de los grupos de casillas a 1 de la máscara (vecindad de 8).
static func _components(mask: PackedByteArray, w: int, h: int) -> Array[Rect2i]:
	var boxes: Array[Rect2i] = []
	var stack := PackedInt32Array()
	for start in mask.size():
		if mask[start] != 1:
			continue
		mask[start] = 2
		var min_x := w
		var min_y := h
		var max_x := -1
		var max_y := -1
		stack.append(start)
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var px := i % w
			var py := i / w
			min_x = mini(min_x, px)
			max_x = maxi(max_x, px)
			min_y = mini(min_y, py)
			max_y = maxi(max_y, py)
			for dy in [-1, 0, 1]:
				var ny: int = py + dy
				if ny < 0 or ny >= h:
					continue
				for dx in [-1, 0, 1]:
					var nx: int = px + dx
					if nx < 0 or nx >= w:
						continue
					var n := ny * w + nx
					if mask[n] == 1:
						mask[n] = 2
						stack.append(n)
		boxes.append(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
	return boxes


static func _merge_close(boxes: Array[Rect2i], gap: int) -> Array[Rect2i]:
	var merged := true
	while merged:
		merged = false
		for a in boxes.size():
			for b in range(a + 1, boxes.size()):
				# +1: Rect2i no cuenta como choque dos rectángulos que solo se tocan.
				if boxes[a].grow(gap + 1).intersects(boxes[b]):
					boxes[a] = boxes[a].merge(boxes[b])
					boxes.remove_at(b)
					merged = true
					break
			if merged:
				break
	return boxes


## Ordena como se lee: por filas de arriba abajo y, dentro de cada fila, de izquierda
## a derecha. Dos cuadros están en la misma fila si se solapan en vertical.
static func sort_reading_order(boxes: Array[Rect2i]) -> Array[Rect2i]:
	var pending := boxes.duplicate()
	pending.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position.y < b.position.y)
	var result: Array[Rect2i] = []
	while not pending.is_empty():
		var first: Rect2i = pending.pop_front()
		var row: Array[Rect2i] = [first]
		var rest: Array[Rect2i] = []
		for box: Rect2i in pending:
			# Misma fila si empieza antes de la mitad del primer cuadro de la fila.
			if box.position.y < first.position.y + first.size.y / 2:
				row.append(box)
			else:
				rest.append(box)
		row.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position.x < b.position.x)
		result.append_array(row)
		pending = rest
	return result


## Punto de los pies dentro del cuadro: centro de los píxeles opacos de las filas
## más bajas (`band` filas). Devuelve coordenadas relativas al rectángulo.
static func feet_point(image: Image, rect: Rect2i, band := 4) -> Vector2:
	var bottom := -1
	for y in range(rect.end.y - 1, rect.position.y - 1, -1):
		for x in range(rect.position.x, rect.end.x):
			if image.get_pixel(x, y).a > 0.0:
				bottom = y
				break
		if bottom >= 0:
			break
	if bottom < 0:
		return Vector2(rect.size.x / 2.0, rect.size.y)
	var sum := 0.0
	var count := 0
	for y in range(maxi(rect.position.y, bottom - band + 1), bottom + 1):
		for x in range(rect.position.x, rect.end.x):
			if image.get_pixel(x, y).a > 0.0:
				sum += x
				count += 1
	# +0.5: centro del píxel, no su esquina.
	return Vector2(sum / count + 0.5 - rect.position.x, bottom + 1 - rect.position.y)


## Rehace la hoja con todos los cuadros en celdas del mismo tamaño, con los pies en el
## centro del borde inferior de cada celda. Así todas las imágenes del luchador tienen
## la misma escala y basta un solo "sprite_anchor": Vector2(celda.x / 2, celda.y).
## Devuelve {"image": Image, "cell": Vector2i, "columns": int}.
static func pack_uniform(image: Image, rects: Array[Rect2i], columns := 8, padding := 2) -> Dictionary:
	var left := 0.0
	var right := 0.0
	var height := 0
	var feet: Array[Vector2] = []
	for rect in rects:
		var foot := feet_point(image, rect)
		feet.append(foot)
		left = maxf(left, foot.x)
		right = maxf(right, rect.size.x - foot.x)
		height = maxi(height, rect.size.y)
	var half := int(ceilf(maxf(left, right))) + padding
	var cell := Vector2i(half * 2, height + padding)
	columns = clampi(columns, 1, maxi(1, rects.size()))
	var rows := int(ceil(float(rects.size()) / columns))
	var out := Image.create_empty(cell.x * columns, cell.y * maxi(rows, 1), false, Image.FORMAT_RGBA8)
	for i in rects.size():
		var target := grid_rect(cell, columns, i)
		var dest := target.position + Vector2i(half - int(roundf(feet[i].x)), cell.y - int(feet[i].y))
		out.blend_rect(image, rects[i], dest)
	return {"image": out, "cell": cell, "columns": columns}
