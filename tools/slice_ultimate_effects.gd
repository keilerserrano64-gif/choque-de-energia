extends SceneTree
## Ventanas de separación; componentes conectados y unión de fragmentos próximos.
## Vista previa: índices en el orden de inserción del manifiesto.

const OUT := "res://assets/fighters/madara_edo/definitivo/efectos/"
const DIGITS := ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001", "111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111"]


func extract(source: Image, window: Rect2i, energy: bool = false, blue: bool = false) -> Image:
	var im := source.get_region(window)
	im.convert(Image.FORMAT_RGBA8)
	for y in range(im.get_height()):
		for x in range(im.get_width()):
			var c := im.get_pixel(x, y)
			# El fondo tiene alfa bajo; reconstruir cobertura sin mezclar RGB.
			c.a = smoothstep(0.70, 0.94, c.a)
			if energy:
				c.a *= smoothstep(0.36, 0.62, c.v)
			# El extremo del tajo vecino invade la ventana azul por abajo.
			if blue and c.r > c.g * 1.2:
				c.a = 0.0
			im.set_pixel(x, y, c if c.a > 0.02 else Color.TRANSPARENT)
	var w := im.get_width()
	var h := im.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var components: Array = []
	for y in range(h):
		for x in range(w):
			var start := y * w + x
			if seen[start] or im.get_pixel(x, y).a == 0.0:
				continue
			var pixels := PackedInt32Array([start])
			seen[start] = 1
			var bounds := Rect2i(x, y, 1, 1)
			var head := 0
			while head < pixels.size():
				var p := Vector2i(pixels[head] % w, pixels[head] / w)
				head += 1
				bounds = bounds.expand(p)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var q := p + Vector2i(dx, dy)
						if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
							continue
						var n := q.y * w + q.x
						if not seen[n] and im.get_pixelv(q).a > 0:
							seen[n] = 1
							pixels.append(n)
			components.append({"pixels": pixels, "rect": bounds})
	assert(not components.is_empty(), "Ventana sin efecto: %s" % window)
	components.sort_custom(func(a, b): return a.pixels.size() > b.pixels.size())
	var accepted: Array = [components.pop_front()]
	var changed := true
	while changed:
		changed = false
		for i in range(components.size() - 1, -1, -1):
			var part: Dictionary = components[i]
			if part.pixels.size() < (12 if energy else 2):
				continue
			for other in accepted:
				if other.rect.grow(7).intersects(part.rect):
					accepted.append(part)
					components.remove_at(i)
					changed = true
					break
	var clean := Image.create(w, h, false, Image.FORMAT_RGBA8)
	clean.fill(Color.TRANSPARENT)
	for part in accepted:
		for p in part.pixels:
			clean.set_pixel(p % w, p / w, im.get_pixel(p % w, p / w))
	var used := clean.get_used_rect()
	# Un píxel de margen protege el filtrado y las esquinas.
	var cropped := Image.create(used.size.x + 2, used.size.y + 2, false, Image.FORMAT_RGBA8)
	cropped.fill(Color.TRANSPARENT)
	cropped.blit_rect(clean, used, Vector2i.ONE)
	return cropped


func label(im: Image, index: int, origin: Vector2i) -> void:
	var s := str(index)
	for n in range(s.length()):
		var glyph: String = DIGITS[int(s[n])]
		for y in range(5):
			for x in range(3):
				if glyph[y * 3 + x] == "1":
					im.fill_rect(Rect2i(origin + Vector2i(n * 10 + x * 2, y * 2), Vector2i(2, 2)), Color.WHITE)


func _initialize() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path("res://assets/fighters/madara_edo/definitivo/efectos.png"))
	assert(source != null and source.get_size() == Vector2i(362, 170))
	var pieces: Array = []
	var names := ["tajo_azul", "tajo_morado_1", "tajo_morado_2", "anillo_1", "anillo_2", "aura_morada"]
	var edges := [5, 76, 125, 187, 246, 292, 354]
	for i in range(names.size()):
		pieces.append([names[i], Rect2i(edges[i], 1, edges[i + 1] - edges[i], 33 if i == 5 else 42)])
	edges = [6, 28, 54, 78, 106, 135, 165]
	for i in range(6):
		pieces.append(["roca_%d" % (i + 1), Rect2i(edges[i], 48, edges[i + 1] - edges[i], 34)])
	edges = [165, 206, 273, 355]
	for i in range(3):
		pieces.append(["meteoro_%d" % (i + 1), Rect2i(edges[i], 36, edges[i + 1] - edges[i], 52)])
	pieces.append(["explosion", Rect2i(5, 82, 100, 47)])
	edges = [110, 199, 284, 355]
	for i in range(3):
		pieces.append(["humo_%d" % (i + 1), Rect2i(edges[i], 89, edges[i + 1] - edges[i], 40)])
	edges = [5, 110, 179, 273, 354]
	for i in range(4):
		pieces.append(["escombros_%d" % (i + 1), Rect2i(edges[i], 131, edges[i + 1] - edges[i], 33)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/out"))
	var preview := Image.create(1320, 560, false, Image.FORMAT_RGBA8)
	preview.fill(Color(0.45, 0.45, 0.45))
	var manifest := {}
	for i in range(pieces.size()):
		var name: String = pieces[i][0]
		var im := extract(source, pieces[i][1], i < 6, i == 0)
		var size := im.get_size()
		var bottom := name == "explosion" or name == "aura_morada" or name.begins_with("escombros_")
		manifest[name] = {"png": OUT + name + ".png", "tam": [size.x, size.y], "ancla": [size.x / 2.0, float(size.y) if bottom else size.y / 2.0]}
		assert(im.save_png(ProjectSettings.globalize_path(OUT + name + ".png")) == OK)
		print(name, " ", size)
		var origin := Vector2i(i % 6 * 220, i / 6 * 140)
		label(preview, i + 1, origin + Vector2i(8, 6))
		im.resize(size.x * 2, size.y * 2, Image.INTERPOLATE_NEAREST)
		preview.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), origin + Vector2i((220 - im.get_width()) / 2, 26))
	var file := FileAccess.open(OUT + "efectos.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t", false) + "\n")
	file.close()
	assert(preview.save_png(ProjectSettings.globalize_path("res://tools/out/madara_edo_efectos_preview.png")) == OK)
	quit()
