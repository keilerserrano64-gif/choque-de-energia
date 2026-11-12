extends SceneTree
## Ejecutar: godot --headless --path . -s res://tools/slice_intro_sheet.gd
## Lee directamente fuentes/ porque su .gdignore impide usar ResourceLoader.

const OUT := "res://assets/fighters/madara_edo/intro/"
const BLACK := 0.06
const SOFT := 0.16
const SATURATION := 0.32
const PHASES := ["aparicion", "materializacion", "sello", "chakra", "presentacion"]


func median(values: Array) -> int:
	values.sort()
	return int(values[values.size() / 2])


func source_rect(values: Array) -> Rect2i:
	return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))


func background(c: Color) -> bool:
	return c.v < BLACK or (c.v < SOFT and (c.s < SATURATION or c.s > 0.65))


func reading_rect(cell: Dictionary) -> Rect2i:
	# El mapa da las columnas, pero algunas ventanas verticales cortan pelo
	# o zapatos. Extendemos hasta el espacio anterior a números y separadores.
	var r := source_rect(cell.rect)
	var top := r.position.y
	var bottom := r.end.y
	match cell.fase:
		"aparicion":
			top = 27 if cell.i < 2 else 6
			bottom = 126
		"materializacion":
			top = 166 if cell.i < 2 else 148
			bottom = 267
		"sello":
			top = 310 if cell.i < 3 else 300
			bottom = 409
		"chakra":
			top = 454 if cell.i < 4 else 434
			bottom = 552
		"presentacion":
			top = 601 if cell.i < 5 else 580
			bottom = 698
	return Rect2i(r.position.x, top, r.size.x, bottom - top)


func enclosed_mask(im: Image) -> PackedByteArray:
	# Cerrar huecos de 1-2 px del contorno antes del flood evita que este
	# entre en las siluetas negras iniciales. No pintamos la dilatación:
	# solamente protegemos los interiores encerrados por ese contorno.
	var w := im.get_width()
	var h := im.get_height()
	var wall := PackedByteArray()
	wall.resize(w * h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if im.get_pixel(x, y).v >= BLACK:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						wall[(y + dy) * w + x + dx] = 1
	var exterior := PackedByteArray()
	exterior.resize(w * h)
	var queue := PackedInt32Array()
	for y in range(h):
		for x in range(w):
			if (x == 0 or y == 0 or x == w - 1 or y == h - 1) and wall[y * w + x] == 0:
				exterior[y * w + x] = 1
				queue.append(y * w + x)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var q: Vector2i = Vector2i(p % w, p / w) + d
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				continue
			var n := q.y * w + q.x
			if exterior[n] == 0 and wall[n] == 0:
				exterior[n] = 1
				queue.append(n)
	wall.fill(0)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var inside := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if exterior[(y + dy) * w + x + dx] != 0:
						inside = false
			wall[y * w + x] = 1 if inside else 0
	return wall


func remove_background(im: Image) -> void:
	# Flood fill de cuatro vecinos: nunca se aplica una clave global al pelo/ropa.
	# Gris oscuro alcanzable: S < .32, V entre .06 y .16. También suavizamos
	# el brillo exterior muy saturado (S > .65) en ese rango, conservando
	# opaco el azul marino del cuerpo protegido. Desmultiplicamos el negro
	# original para que humo y brillo semitransparentes no tengan halo oscuro.
	var w := im.get_width()
	var h := im.get_height()
	var protected := enclosed_mask(im)
	var visited := PackedByteArray()
	visited.resize(w * h)
	var queue := PackedInt32Array()
	for y in range(h):
		for x in range(w):
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				if protected[y * w + x] == 0 and background(im.get_pixel(x, y)):
					visited[y * w + x] = 1
					queue.append(y * w + x)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		var x := p % w
		var y := p / w
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var q: Vector2i = Vector2i(x, y) + d
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				continue
			var n := q.y * w + q.x
			if visited[n] == 0 and protected[n] == 0 and background(im.get_pixelv(q)):
				visited[n] = 1
				queue.append(n)
	for p in queue:
		var x := p % w
		var y := p / w
		var c := im.get_pixel(x, y)
		var alpha := clampf((c.v - BLACK) / (SOFT - BLACK), 0.0, 1.0)
		if alpha <= 0.0:
			im.set_pixel(x, y, Color.TRANSPARENT)
		else:
			im.set_pixel(x, y, Color(c.r / alpha, c.g / alpha, c.b / alpha, alpha))


func feet(im: Image) -> Vector2i:
	# La mediana de la armadura roja ignora humo y aura. En las siluetas sin
	# rojo usamos el centro del recorte, que coincide con el cuerpo.
	var reds: Array = []
	for y in range(im.get_height()):
		for x in range(im.get_width()):
			var c := im.get_pixel(x, y)
			if c.a > 0.95 and c.r > 0.20 and c.r > c.g * 1.8 and c.r > c.b * 1.4:
				reds.append(x)
	var cx := median(reds) if reds.size() >= 24 else im.get_width() / 2
	# Calzado: oscuro, opaco, sin gris claro ni azul luminoso. Exigimos al
	# menos dos píxeles por fila para descartar chispas aisladas.
	for y in range(im.get_height() - 1, -1, -1):
		var count := 0
		for x in range(maxi(0, cx - 20), mini(im.get_width(), cx + 21)):
			var c := im.get_pixel(x, y)
			if c.a > 0.95 and c.v < 0.48 and not (c.b > 0.25 and c.b > c.r * 1.4):
				count += 1
		if count >= 2:
			return Vector2i(cx, y)
	return Vector2i(cx, im.get_height() - 3)


func _initialize() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fuentes/mapa_madara_edo_intro.json"))
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(map.fuente))
	if sheet == null or map.celdas.size() != 48:
		push_error("Hoja o mapa de intro inválidos")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/out"))
	var frames: Array[Image] = []
	var anchors: Array[Vector2i] = []
	var crop_tops: Array[int] = []
	var phase_y := {}
	for cell in map.celdas:
		var crop := reading_rect(cell)
		crop_tops.append(crop.position.y)
		var im := sheet.get_region(crop)
		im.convert(Image.FORMAT_RGBA8)
		remove_background(im)
		frames.append(im)
		var anchor := feet(im)
		anchors.append(anchor)
		if not phase_y.has(cell.fase):
			phase_y[cell.fase] = []
		phase_y[cell.fase].append(anchor.y + crop.position.y)
	# Saltos de más de cuatro píxeles en la suela dentro de una fase suelen
	# ser humo/chispas. Sustituimos solo esos valores por la mediana de fase.
	var left := 0
	var right := 0
	var above := 0
	var below := 0
	for n in range(frames.size()):
		var my := median(phase_y[map.celdas[n].fase])
		if absi(anchors[n].y + crop_tops[n] - my) > 4:
			anchors[n].y = clampi(my - crop_tops[n], 0, frames[n].get_height() - 1)
		left = maxi(left, anchors[n].x)
		right = maxi(right, frames[n].get_width() - anchors[n].x)
		above = maxi(above, anchors[n].y)
		below = maxi(below, frames[n].get_height() - anchors[n].y)
	var common := Vector2i(left + 4, above + 4)
	var size := Vector2i(left + right + 8, above + below + 8)
	size += Vector2i(size.x % 2, size.y % 2)
	var atlas := Image.create(size.x * 8, size.y * 6, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var manifest := {"atlas": OUT + "madara_edo_intro_frames.png", "celda": [size.x, size.y], "columnas": 8, "ancla": [common.x, common.y], "alto_figura": 0, "mira": "derecha", "fases": {}, "cuadros": [], "ojos": {"atlas": OUT + "ojos.png"}, "retrato": OUT + "retrato.png"}
	for phase in PHASES:
		manifest.fases[phase] = []
	var heights: Array = []
	for n in range(frames.size()):
		var origin := Vector2i(n % 8, n / 8) * size
		atlas.blit_rect(frames[n], Rect2i(Vector2i.ZERO, frames[n].get_size()), origin + common - anchors[n])
		var cell: Dictionary = map.celdas[n]
		manifest.fases[cell.fase].append(n)
		manifest.cuadros.append({"fase": cell.fase, "i": cell.i, "rect": [origin.x, origin.y, size.x, size.y]})
		if cell.fase == "presentacion":
			# Coronilla cerca del cuerpo: ignorar aura brillante y humo. El pelo
			# es azul marino (oscuro y saturado); el rostro también cuenta.
			var top := anchors[n].y
			for y in range(anchors[n].y):
				for x in range(maxi(0, anchors[n].x - 22), mini(frames[n].get_width(), anchors[n].x + 23)):
					var c := frames[n].get_pixel(x, y)
					if c.a > 0.95 and c.s > 0.25 and c.v < 0.48:
						top = mini(top, y)
			heights.append(anchors[n].y - top + 1)
		print("%s %s pies=%s" % [cell.fase, cell.i, anchors[n]])
	manifest.alto_figura = median(heights)
	assert(atlas.save_png(ProjectSettings.globalize_path(manifest.atlas)) == OK)
	var eyes_width := 0
	var eyes_height := 0
	for eye in map.ojos:
		eyes_width += int(eye.rect[2])
		eyes_height = maxi(eyes_height, int(eye.rect[3]))
	var eyes := Image.create(eyes_width, eyes_height, false, Image.FORMAT_RGB8)
	var eye_x := 0
	for eye in map.ojos:
		var rect := source_rect(eye.rect)
		eyes.blit_rect(sheet, rect, Vector2i(eye_x, 0))
		manifest.ojos[String(eye.nombre).trim_prefix("ojo_")] = [eye_x, 0, rect.size.x, rect.size.y]
		eye_x += rect.size.x
	assert(eyes.save_png(ProjectSettings.globalize_path(OUT + "ojos.png")) == OK)
	assert(sheet.get_region(source_rect(map.retrato.rect)).save_png(ProjectSettings.globalize_path(OUT + "retrato.png")) == OK)
	var file := FileAccess.open(OUT + "madara_edo_intro_frames.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	var preview := Image.create(atlas.get_width(), atlas.get_height(), false, Image.FORMAT_RGBA8)
	preview.fill(Color(0.45, 0.45, 0.45))
	preview.blend_rect(atlas, Rect2i(Vector2i.ZERO, atlas.get_size()), Vector2i.ZERO)
	for n in range(frames.size()):
		var p := Vector2i(n % 8, n / 8) * size + common
		for d in range(-3, 4):
			preview.set_pixel(p.x + d, p.y, Color.GREEN)
			preview.set_pixel(p.x, p.y + d, Color.GREEN)
	assert(preview.save_png(ProjectSettings.globalize_path("res://tools/out/madara_edo_intro_preview.png")) == OK)
	print("Intro: celda=%s ancla=%s alto_figura=%d mira=derecha" % [size, common, manifest.alto_figura])
	quit()
