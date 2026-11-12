extends SceneTree
## Godot --headless --path . -s res://tools/slice_ultimate_sheet.gd
## El mapa permanece intacto; fuente_rect documenta cada ventana afinada.

const OUT := "res://assets/fighters/madara_edo/definitivo/"
const MAP := "res://fuentes/mapa_madara_edo_definitivo.json"


func median(a: Array) -> int:
	a.sort()
	return int(a[a.size() / 2])


func rect(a: Array) -> Rect2i:
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


func array_rect(r: Rect2i) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func separator(sheet: Image, x: int, r: Rect2i) -> int:
	# Un separador es una discontinuidad vertical persistente, no el filo
	# brillante de un efecto (que solamente ocupa unas pocas filas).
	var best := x
	var score := -1.0
	for xx in range(maxi(5, x - 25), mini(1385, x + 26)):
		var total := 0.0
		for y in range(r.position.y + 5, r.end.y - 5):
			var c := sheet.get_pixel(xx, y)
			total += 1.0 - c.v * c.a
		total /= maxi(1, r.size.y - 10)
		total -= absf(xx - x) * 0.001
		if total > score:
			score = total
			best = xx
	return best


func background(c: Color) -> bool:
	# El fondo contiene tanto transparencia como morado oscuro casi opaco.
	# El núcleo de armadura/pelo/energía se protege antes del flood fill.
	return c.a < 0.94 or (c.v < 0.27 and c.s < 0.70) or dark_purple(c)


func dark_purple(c: Color) -> bool:
	# El cielo morado del panel conserva alfa 247-252; distinguirlo del
	# pelo azul (con más verde) y de la armadura roja evita fondos cuadrados.
	return c.v < 0.46 and c.b > c.r * 1.15 and c.g < c.r * 0.68


func protected_interior(im: Image) -> PackedByteArray:
	# Un alfa de 249/255 también aparece en el fondo: no sirve por sí solo
	# para proteger un píxel. Partir de armadura, pelo, piel y energía evita
	# cerrar y conservar rectángulos enteros de fondo alrededor de Madara.
	var w := im.get_width()
	var h := im.get_height()
	var wall := PackedByteArray()
	wall.resize(w * h)
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var c := im.get_pixel(x, y)
			var armor := c.r > 0.22 and c.r > c.g * 1.5 and c.r > c.b * 1.15
			var blue := c.b > c.r * 1.45 and c.b > c.g * 1.15 and c.g >= c.r * 0.8 and c.v > 0.18
			var skin := c.r > 0.4 and c.r > c.g * 1.1 and c.g > c.b * 0.85
			if c.a > 0.96 and (armor or blue or skin or (c.v > 0.5 and c.s < 0.3)):
				for dy in range(-2, 3):
					for dx in range(-2, 3):
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
			var q := Vector2i(p % w, p / w) + Vector2i(d)
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				continue
			var n := q.y * w + q.x
			if exterior[n] == 0 and wall[n] == 0:
				exterior[n] = 1
				queue.append(n)
	wall.fill(0)
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var inside := true
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if exterior[(y + dy) * w + x + dx] != 0:
						inside = false
			wall[y * w + x] = 1 if inside else 0
	return wall


func clean(im: Image, connected: bool = true) -> void:
	var w := im.get_width()
	var h := im.get_height()
	var protected := protected_interior(im)
	var visited := PackedByteArray()
	visited.resize(w * h)
	var queue := PackedInt32Array()
	for y in range(h):
		for x in range(w):
			if (x == 0 or y == 0 or x == w - 1 or y == h - 1) and protected[y * w + x] == 0 and background(im.get_pixel(x, y)):
				visited[y * w + x] = 1
				queue.append(y * w + x)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var q := Vector2i(p % w, p / w) + Vector2i(d)
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				continue
			var n := q.y * w + q.x
			if visited[n] == 0 and protected[n] == 0 and background(im.get_pixelv(q)):
				visited[n] = 1
				queue.append(n)
	for p in queue:
		im.set_pixel(p % w, p / w, Color.TRANSPARENT)
	# Los huecos entre las costillas del Susanoo tienen el mismo alfa de
	# fondo que el exterior; el pelo opaco queda protegido por su alfa.
	for y in range(h):
		for x in range(w):
			var c := im.get_pixel(x, y)
			if c.a < 0.80 or (protected[y * w + x] == 0 and dark_purple(c)):
				im.set_pixel(x, y, Color.TRANSPARENT)
	if not connected:
		return
	# Pelo, manos y rayos pueden quedar separados por uno o dos píxeles
	# transparentes de la fuente. Conservar solo la mayor armadura borraba
	# cabezas completas: retener componentes de piel, armadura o azul de
	# pelo/Susanoo; los rótulos y separadores morados quedan excluidos.
	visited.fill(0)
	var retained := PackedByteArray()
	retained.resize(w * h)
	for y in range(h):
		for x in range(w):
			var start := y * w + x
			if visited[start] != 0 or im.get_pixel(x, y).a == 0:
				continue
			queue = PackedInt32Array([start])
			visited[start] = 1
			head = 0
			var foreground := false
			while head < queue.size():
				var p := queue[head]
				head += 1
				var c := im.get_pixel(p % w, p / w)
				foreground = foreground or (c.r > 0.22 and c.r > c.g * 1.5 and c.r > c.b * 1.15) \
					or (c.b > c.r * 1.4 and c.g >= c.r * 0.75 and c.v > 0.2) \
					or (c.r > 0.4 and c.r > c.g * 1.1 and c.g > c.b * 0.85)
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var q := Vector2i(p % w, p / w) + Vector2i(d)
					if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
						continue
					var n := q.y * w + q.x
					if visited[n] == 0 and im.get_pixelv(q).a > 0:
						visited[n] = 1
						queue.append(n)
			if foreground and queue.size() > 3:
				for p in queue:
					retained[p] = 1
	for y in range(h):
		for x in range(w):
			if retained[y * w + x] == 0:
				im.set_pixel(x, y, Color.TRANSPARENT)


func body_anchor(im: Image) -> Vector2i:
	var xs: Array = []
	for y in range(im.get_height()):
		for x in range(im.get_width()):
			var c := im.get_pixel(x, y)
			if c.a > 0.9 and c.r > 0.22 and c.r > c.g * 1.5 and c.r > c.b * 1.15:
				xs.append(x)
	var cx := median(xs) if not xs.is_empty() else im.get_width() / 2
	for y in range(im.get_height() - 1, -1, -1):
		var count := 0
		for x in range(maxi(0, cx - 13), mini(im.get_width(), cx + 14)):
			var c := im.get_pixel(x, y)
			if c.a > 0.9 and c.v < 0.46 and c.b < 0.42:
				count += 1
		if count >= 2:
			return Vector2i(cx, y)
	return Vector2i(cx, im.get_used_rect().end.y - 1)


func _initialize() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(map.fuente))
	assert(sheet != null)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/out"))
	var groups := {"personaje": [], "escenas": []}
	var heights: Array = []
	var scene_heights: Array = []
	for phase in map.fases:
		var rr := rect(phase.celdas[0])
		var runs: Array = []
		var active := -1
		var previous := -100
		for x in range(10, 1380):
			var red := 0
			for y in range(rr.position.y + 4, rr.end.y - 5):
				var c := sheet.get_pixel(x, y)
				if c.a > 0.9 and c.r > 0.22 and c.r > c.g * 1.5 and c.r > c.b * 1.15:
					red += 1
			if red >= 3:
				if x - previous > 12:
					if active >= 0:
						runs.append([active, previous])
					active = x
				previous = x
		if active >= 0:
			runs.append([active, previous])
		var centers: Array = []
		for run in runs:
			if int(run[1]) - int(run[0]) >= 12:
				centers.append((int(run[0]) + int(run[1])) / 2)
		if phase.nombre == "final":
			centers = [55, 148, 235, 320, 405, 490, 585, 680, 780, 878, 978, 1074, 1170, 1265, 1350]
		var boundaries: Array = []
		for c in phase.celdas:
			var r := rect(c)
			boundaries.append(separator(sheet, r.position.x, r))
		var last := rect(phase.celdas.back())
		boundaries.append(separator(sheet, last.end.x, last))
		# Evitar que dos búsquedas independientes elijan el mismo borde o
		# una línea interior del meteoro; volver al límite medido en ese caso.
		for j in range(1, boundaries.size() - 1):
			if int(boundaries[j]) - int(boundaries[j - 1]) < 55 or int(boundaries[j + 1]) - int(boundaries[j]) < 55:
				boundaries[j] = int(phase.celdas[j][0])
		print(phase.nombre, " bordes=", boundaries)
		for i in range(phase.celdas.size()):
			var original := rect(phase.celdas[i])
			var r := Rect2i(int(boundaries[i]) + 2, original.position.y + 2, maxi(8, int(boundaries[i + 1]) - int(boundaries[i]) - 3), original.size.y - 4)
			var refined := r
			var pose := -1
			if phase.tipo == "escena":
				var top := 590 if phase.nombre != "impactos" else 692
				var bottom := 646 if phase.nombre != "impactos" else 743
				r.position.y = top
				r.size.y = bottom - top
				refined = r
			if phase.tipo == "personaje" and not centers.is_empty():
				var expected := original.get_center().x
				var distance := 10000
				for j in range(centers.size()):
					if absi(int(centers[j]) - expected) < distance:
						distance = absi(int(centers[j]) - expected)
						pose = j
				var left := (int(centers[pose - 1]) + int(centers[pose])) / 2 if pose > 0 else 8
				var right := (int(centers[pose + 1]) + int(centers[pose])) / 2 if pose < centers.size() - 1 else mini(1381, int(centers[pose]) + 54)
				var top := original.position.y + 2
				if phase.nombre == "preparacion":
					top = 27 if centers[pose] < 400 else 7
				elif phase.nombre == "susanoo":
					top = 138 if centers[pose] < 534 else 119
				elif phase.nombre == "tajo":
					top = 260 if centers[pose] < 435 else 249
				elif phase.nombre == "risa":
					top = 369
				elif phase.nombre == "invocacion":
					top = 482 if centers[pose] < 500 else 463
				elif phase.nombre == "final":
					top = 790 if pose < 4 else 776
				r = Rect2i(left + 1, top, right - left - 2, original.end.y - 2 - top)
			var im := sheet.get_region(r)
			im.convert(Image.FORMAT_RGBA8)
			if phase.nombre == "risa":
				# Seguir el borde inclinado del título sin cortar la quinta coronilla.
				for y in range(maxi(0, 368 - r.position.y), mini(im.get_height(), 386 - r.position.y)):
					var title_right := mini(480, ceili(468 + (385 - r.position.y - y) * 0.6))
					for x in range(maxi(0, mini(im.get_width(), title_right - r.position.x))):
						im.set_pixel(x, y, Color.TRANSPARENT)
			var anchor := Vector2i.ZERO
			if phase.tipo == "personaje":
				clean(im)
				anchor = body_anchor(im)
				if phase.nombre == "preparacion":
					var top := anchor.y
					for y in range(anchor.y):
						for x in range(maxi(0, anchor.x - 16), mini(im.get_width(), anchor.x + 17)):
							var c := im.get_pixel(x, y)
							if c.a > 0.9 and c.v < 0.45:
								top = mini(top, y)
					heights.append(anchor.y - top + 1)
			else:
				# Los planos cinematográficos son opacos; conservar RGB original.
				im.convert(Image.FORMAT_RGB8)
				im.convert(Image.FORMAT_RGBA8)
				scene_heights.append(im.get_height())
			var key := "personaje" if phase.tipo == "personaje" else "escenas"
			groups[key].append({"im": im, "anchor": anchor, "fase": phase.nombre, "i": i, "fuente_rect": array_rect(r), "mapa_rect": array_rect(original), "panel_rect": array_rect(refined), "pose_fuente": pose})
	var manifest := {"revision_visual": "Ventanas verticales ajustadas a los rotulos de la fuente; fondo oscuro eliminado desde el exterior protegiendo armadura, pelo y energia. La risa es un busto en la hoja original. pose_fuente y repetido_de documentan las repeticiones conservadoras del mapa; fuente_rect conserva el recorte exacto utilizado."}
	var atlases := {}
	for key in groups:
		var frames: Array = groups[key]
		var common := Vector2i.ZERO
		var size := Vector2i.ZERO
		var right := 0
		var below := 0
		for f in frames:
			var im: Image = f.im
			if key == "escenas":
				var hh := median(scene_heights)
				im.resize(roundi(float(im.get_width()) * hh / im.get_height()), hh, Image.INTERPOLATE_NEAREST)
				size = size.max(im.get_size())
			else:
				common = common.max(f.anchor)
				right = maxi(right, im.get_width() - f.anchor.x)
				below = maxi(below, im.get_height() - f.anchor.y)
		if key == "personaje":
			size = common + Vector2i(right, below) + Vector2i(8, 8)
			common += Vector2i(4, 4)
		size += Vector2i(size.x % 2, size.y % 2)
		var atlas := Image.create(size.x * 8, size.y * ceili(frames.size() / 8.0), false, Image.FORMAT_RGBA8)
		atlas.fill(Color.TRANSPARENT)
		var data := {"atlas": OUT + "madara_edo_definitivo_" + key + ".png", "celda": [size.x, size.y], "columnas": 8, "fases": {}, "cuadros": []}
		var source_poses := {}
		if key == "personaje":
			data.merge({"ancla": [common.x, common.y], "alto_figura": median(heights), "mira": "derecha"})
		for n in range(frames.size()):
			var f: Dictionary = frames[n]
			var im: Image = f.im
			var origin := Vector2i(n % 8, n / 8) * size
			var offset: Vector2i = common - f.anchor if key == "personaje" else (size - im.get_size()) / 2
			atlas.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), origin + offset)
			if not data.fases.has(f.fase):
				data.fases[f.fase] = []
			data.fases[f.fase].append(n)
			var entry := {"fase": f.fase, "i": f.i, "rect": array_rect(Rect2i(origin, size)), "fuente_rect": f.fuente_rect, "mapa_rect": f.mapa_rect, "panel_rect": f.panel_rect, "pose_fuente": f.pose_fuente}
			var pose_key := "%s:%s" % [f.fase, f.pose_fuente]
			if key == "personaje" and source_poses.has(pose_key):
				entry["repetido_de"] = source_poses[pose_key]
			elif key == "personaje":
				source_poses[pose_key] = n
			data.cuadros.append(entry)
		assert(atlas.save_png(ProjectSettings.globalize_path(data.atlas)) == OK)
		manifest[key] = data
		atlases[key] = atlas
		print(key, " celda=", size, " ancla=", common)
	for key in ["retrato", "logo", "efectos"]:
		var im := sheet.get_region(rect(map[key].rect))
		im.convert(Image.FORMAT_RGBA8)
		if key == "logo":
			clean(im, false)
		elif key == "retrato":
			im.convert(Image.FORMAT_RGB8)
		manifest[key] = OUT + key + ".png"
		assert(im.save_png(ProjectSettings.globalize_path(manifest[key])) == OK)
	var file := FileAccess.open(OUT + "madara_edo_definitivo.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	var chars: Image = atlases.personaje
	var scenes: Image = atlases.escenas
	var preview := Image.create(maxi(chars.get_width(), scenes.get_width()), chars.get_height() + scenes.get_height() + 8, false, Image.FORMAT_RGBA8)
	preview.fill(Color(0.45, 0.45, 0.45))
	preview.blend_rect(chars, Rect2i(Vector2i.ZERO, chars.get_size()), Vector2i.ZERO)
	preview.blend_rect(scenes, Rect2i(Vector2i.ZERO, scenes.get_size()), Vector2i(0, chars.get_height() + 8))
	for f in manifest.personaje.cuadros:
		var p := Vector2i(int(f.rect[0]) + int(manifest.personaje.ancla[0]), int(f.rect[1]) + int(manifest.personaje.ancla[1]))
		for d in range(-3, 4):
			preview.set_pixel(p.x + d, p.y, Color.GREEN)
			preview.set_pixel(p.x, p.y + d, Color.GREEN)
	assert(preview.save_png(ProjectSettings.globalize_path("res://tools/out/madara_edo_definitivo_preview.png")) == OK)
	print("alto_figura=", manifest.personaje.alto_figura)
	quit()
