class_name FighterImporter
extends RefCounted
## Importa luchadores desde hojas de sprites. Lo usan la herramienta de terminal
## (tools/slice_sheet.gd) y la ventana del importador (tools/importador/importador.tscn).
##
## Pasos: analyze() limpia la hoja y encuentra los cuadros, find_duplicates() marca los
## repetidos y los girados, normalize_map() valida el mapa de poses, apply() empaqueta
## los cuadros usados y escribe el luchador en el catálogo, el estilo de animación y
## La configuración queda en assets/fighters/<id>/<id>_import.json
## para repetir la importación con solo el id.

const CATALOG_PATH := "res://scripts/data/catalog.gd"
const ANIMATIONS_PATH := "res://scripts/data/fighter_animations.gd"
const FIGHTERS_DIR := "res://assets/fighters"
const OUT_DIR := "res://tools/out"
## Altura de la pose de reposo del reparto, en unidades del sprite.
const GAME_HEIGHT := 58.0
const DEFAULT_BASE := "kakashi"
## Más píxeles que esto (tras el recorte) y la hoja se reduce a la mitad para analizarla.
const AUTO_SCALE_PIXELS := 16000000
## Detector v2: hojas con más píxeles que esto se analizan reducidas (los cuadros se
## recortan después de la hoja original, a tamaño completo).
const FAST_DETECT_PIXELS := 8000000
## Altura máxima de la pose de pie en la hoja final (más alto se reduce con buen filtro;
## en pantalla completa un luchador mide unos 165 píxeles).
const OUT_MAX_HEIGHT := 200
## Poses de pie que sirven para medir la altura del luchador.
const STANDING_POSES := ["idle", "stance", "block", "intro", "victory"]
## Campos del catálogo que escribe el importador (se sustituyen al reimportar).
const SPRITE_FIELDS := ["sprites", "sprite_anchor", "sprite_frame_time", "sprite_height", "sprite_head", "sprite_fist"]

## Poses que entiende FighterPainter y para qué sirven, en el orden del importador.
const POSES := {
	"idle": "Reposo (obligatoria). Con varios cuadros se repite en bucle.",
	"stance": "Guardia: se ve al preparar y al terminar cada golpe.",
	"walk": "Andar (bucle).",
	"run": "Correr, primer cuadro (si falta, usa walk).",
	"run_alt": "Correr, segundo cuadro.",
	"jump": "En el aire.",
	"block": "Bloquear.",
	"jab": "Jab (I).",
	"light": "Puñetazos ligeros sin imagen propia: gancho, puñetazo aéreo.",
	"heavy": "Golpe fuerte (L); también cross, uppercut y agarre sin imagen propia.",
	"heavy_impact": "Golpe fuerte en el momento del impacto.",
	"finisher": "Patadas (J) y patada fuerte (↓+L): preparación. Lo usan todas las patadas sin imagen propia.",
	"finisher_impact": "Patadas: impacto.",
	"cross": "Cross (segundo puñetazo de la cadena).",
	"hook": "Gancho.",
	"uppercut": "Uppercut (↓ + I antiaéreo).",
	"kick_chamber": "Patada recogida.",
	"kick_low": "Patada baja.",
	"kick_mid": "Patada media.",
	"kick_high": "Patada alta.",
	"kick_spin": "Patada giratoria.",
	"sweep": "Barrida (↓ + J).",
	"air_punch": "Puñetazo en el aire.",
	"air_kick": "Patada en el aire.",
	"throw": "Agarre (→ + L).",
	"attack": "Cualquier golpe que no tenga otra imagen.",
	"charge": "Cargar energía.",
	"special": "Técnica especial (K).",
	"hurt": "Recibir un golpe.",
	"fall": "Salir despedido y levantarse.",
	"down": "Tumbado en el suelo.",
	"intro": "Entrada al combate.",
	"victory": "Celebración de victoria.",
}
## Golpes que admiten imagen por fase: <golpe>_<fase>, p. ej. jab_anticipate.
const ATTACKS := ["jab", "cross", "hook", "uppercut", "kick_low", "kick_mid", "kick_high", "kick_spin",
	"sweep", "air_punch", "air_kick", "throw", "light", "heavy", "finisher"]
const PHASES := ["anticipate", "punch", "smear", "impact", "recover", "kick"]
## Animaciones que admiten una secuencia completa de cuadros: seq_<animación>, p. ej.
## "seq_jab": [10, 11, 12, 13]. Los cuadros se reparten a lo largo de la animación y
## mandan sobre las poses sueltas (jab, jab_anticipate...).
const SEQUENCE_ANIMS := ["run", "jump", "block", "jab", "cross", "hook", "uppercut", "kick_low", "kick_mid",
	"kick_high", "kick_spin", "sweep", "air_punch", "air_kick", "throw", "light", "heavy", "finisher",
	"charge", "special", "hurt", "intro", "victory"]
## Nombres habituales que se traducen a la pose que usa el juego.
const ALIASES := {
	"reposo": "idle", "quieto": "idle", "parado": "idle", "guardia": "stance",
	"andar": "walk", "caminar": "walk", "correr": "run", "carrera": "run", "dash": "run",
	"salto": "jump", "saltar": "jump", "aire": "jump",
	"bloqueo": "block", "bloquear": "block", "defensa": "block", "guard": "block",
	"punch": "light", "puno": "light", "puño": "light", "golpe": "light", "punetazo": "light", "puñetazo": "light",
	"golpe_fuerte": "heavy", "fuerte": "heavy", "strong": "heavy",
	"kick": "finisher", "patada": "finisher", "kick_impact": "finisher_impact", "patada_impacto": "finisher_impact",
	"gancho": "uppercut", "barrida": "sweep", "agarre": "throw", "grab": "throw", "agarrar": "throw",
	"dano": "hurt", "daño": "hurt", "herido": "hurt", "hit": "hurt", "golpeado": "hurt",
	"caida": "fall", "caída": "fall", "knockdown": "fall", "suelo": "down", "tumbado": "down", "ko": "down",
	"victoria": "victory", "win": "victory", "ganar": "victory", "entrada": "intro",
	"especial": "special", "tecnica": "special", "técnica": "special", "carga": "charge", "cargar": "charge",
}
## Segundos por cuadro de las animaciones en lista, si el mapa no dice otra cosa.
const DEFAULT_FRAME_TIME := {"idle": 0.2, "walk": 0.09, "run": 0.08, "hurt": 0.12, "victory": 0.4,
	"intro": 0.15, "block": 0.12, "charge": 0.1, "special": 0.08}

## Tipografía de 3x5 para escribir en las vistas previas.
const FONT := {
	"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
	"4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
	"8": "111101111101111", "9": "111101111001111",
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
	"E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
	"I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
	"Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
	"U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111", "_": "000000000000111", "-": "000000111000000",
	".": "000000000000010", ":": "000010000010000", "(": "010100100100010", ")": "010001001001010",
	"=": "000111000111000", "<": "001010100010001", ">": "100010001010100", "/": "001001010100100",
	" ": "000000000000000",
}


# --- Análisis de la hoja --------------------------------------------------------

## Limpia la hoja y encuentra sus cuadros. Opciones (todas opcionales):
##   mode: "auto" (por defecto) | "cells" | "plain" | "grid"
##   bg: "auto" | "none" | "#rrggbb"          fondo a quitar (modo plain)
##   fill / separator: "auto" | "#rrggbb"     colores de celda y de línea (modo cells)
##   tolerance (0.04), min (8), gap (2)
##   crop: "N" o "izq,arriba,der,abajo"   píxeles que se quitan de los bordes (capturas)
##   lines: N   borra líneas rectas de N px o más (subrayados entre cuadros)
##   connect: 8 (por defecto) | 4   con 4, lo que solo se toca en diagonal no se une
##   split: true   parte los cuadros mucho más anchos que los demás (sprites pegados)
##   scale: 0.5   reduce la hoja antes de analizarla (hojas enormes con sprites grandes)
##   alpha: N   borra los píxeles con transparencia menor que N (0-255; neblina casi invisible)
##   grid: "64x64", grid_cols, grid_rows, offset: "x,y", spacing: "x,y"  (modo grid)
## Devuelve {"image": Image limpia, "rects": Array[Rect2i], "removed": Array[Color],
##   "mode": modo usado, "info": texto, "error": texto ("" si todo fue bien)}.
static func analyze(source: Image, options: Dictionary = {}) -> Dictionary:
	var notes := PackedStringArray()
	var prepared := _prepare(source, options, notes)
	if prepared.has("error"):
		return prepared
	var result := _detect(prepared["image"], prepared["options"], notes)
	result["detector"] = String(options.get("detector", "legacy"))
	result["scale"] = prepared["scale"]
	result["full"] = prepared["full"]
	result["alpha_min"] = prepared["alpha_min"]
	if not result.has("tolerance"):
		result["tolerance"] = float(options.get("tolerance", 0.04))
	if not notes.is_empty():
		result["info"] = String(result["info"]) + " · Ajustes automáticos: " + ", ".join(notes)
	result["auto"] = notes
	return result


## Recorte, reducción y limpieza de transparencia. Con "auto" (por defecto) decide solo
## lo que no se haya indicado: reduce las hojas enormes y borra la neblina transparente.
static func _prepare(source: Image, options: Dictionary, notes: PackedStringArray) -> Dictionary:
	var auto := not options.has("auto") or _flag(options["auto"])
	var image := source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var crop := parse_crop(String(options.get("crop", "")))
	if crop != Rect2i():
		var inner := Rect2i(crop.position, image.get_size() - crop.position - crop.size)
		if inner.size.x <= 0 or inner.size.y <= 0:
			return {"image": image, "rects": [] as Array[Rect2i], "removed": [], "mode": "", "info": "",
				"error": "El recorte de bordes (--crop) es más grande que la hoja."}
		image = image.get_region(inner)
	var v2 := String(options.get("detector", "legacy")) == "v2"
	var full: Image = null
	var scale := float(options.get("scale", 0.0))
	if scale <= 0.0:
		scale = 1.0
		var pixels_count := image.get_width() * image.get_height()
		if auto and v2 and pixels_count > FAST_DETECT_PIXELS:
			scale = snappedf(sqrt(float(FAST_DETECT_PIXELS) / pixels_count), 0.01)
			notes.append("hoja enorme analizada al %d %% (los cuadros salen a tamaño completo)" % roundi(scale * 100))
		elif auto and not v2 and pixels_count > AUTO_SCALE_PIXELS:
			scale = 0.5
			notes.append("hoja enorme reducida a la mitad (--scale 0.5)")
	if v2 and not is_equal_approx(scale, 1.0):
		full = image.duplicate() as Image
	if not is_equal_approx(scale, 1.0):
		image.resize(maxi(1, int(image.get_width() * scale)), maxi(1, int(image.get_height() * scale)), Image.INTERPOLATE_NEAREST)
	var alpha_min := int(options.get("alpha", -1))
	if alpha_min < 0:
		alpha_min = 0
		if auto and _has_haze(image):
			alpha_min = 128
			notes.append("neblina transparente borrada (--alpha 128)")
	if alpha_min > 0:
		var pixels := image.get_data()
		for i in range(3, pixels.size(), 4):
			if pixels[i] < alpha_min:
				pixels[i] = 0
		image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, pixels)
	var rest := options.duplicate()
	for key in ["crop", "scale", "alpha"]:
		rest.erase(key)
	rest["auto"] = auto
	return {"image": image, "options": rest, "full": full, "scale": scale, "alpha_min": alpha_min}


## true si hay muchos píxeles casi transparentes (0 < alfa < 128): restos de un borrado
## de fondo que unen los sprites entre sí aunque no se vean.
static func _has_haze(image: Image) -> bool:
	var data := image.get_data()
	var step := 4 * maxi(1, data.size() / 4 / 400000)
	var haze := 0
	var solid := 0
	for i in range(3, data.size(), step):
		var a := data[i]
		if a >= 128:
			solid += 1
		elif a > 0:
			haze += 1
	return haze > 50 and haze > solid / 50


## Encuentra los cuadros en una hoja ya preparada.
static func _detect(image: Image, options: Dictionary, notes: PackedStringArray) -> Dictionary:
	var source := image
	image = image.duplicate() as Image
	var auto := _flag(options.get("auto", true))
	var mode := String(options.get("mode", "auto"))
	var tolerance := float(options.get("tolerance", 0.04))
	var min_size := int(options.get("min", 8))
	var result := {"image": image, "rects": [] as Array[Rect2i], "removed": [], "mode": mode, "info": "", "error": ""}
	if mode == "auto":
		# Fondo liso primero (sin arreglos automáticos, solo para decidir); si todo sale
		# en un bloque enorme, la hoja tiene celdas de color.
		var probe := _detect(source, _with(_with(options, "mode", "plain"), "_probe", true), PackedStringArray())
		var rects: Array[Rect2i] = probe["rects"]
		var area := image.get_width() * image.get_height()
		if rects.is_empty() or (rects.size() <= 2 and rects[0].get_area() > area / 4):
			var cells := _detect(source, _with(options, "mode", "cells"), notes)
			if not (cells["rects"] as Array).is_empty():
				return cells
		return _detect(source, _with(options, "mode", "plain"), notes)
	if mode == "cells":
		var guess := SpriteSheet.guess_cell_colors(image)
		var fill_arg := String(options.get("fill", "auto"))
		var fill: Color = guess[0] if fill_arg == "auto" else Color.html(fill_arg)
		var sep_arg := String(options.get("separator", "auto"))
		var separator: Color = guess[1] if sep_arg == "auto" else Color.html(sep_arg)
		if separator.is_equal_approx(fill):
			separator = guess[0] if not guess[0].is_equal_approx(fill) else guess[1]
		var cells := SpriteSheet.detect_cells(image, separator, tolerance, min_size)
		# El separador solo se quita fuera de las celdas: dentro puede ser parte del
		# dibujo (pelo gris, ropa blanca...).
		SpriteSheet.clear_outside(image, cells)
		for cell_rect in cells:
			# Piezas sueltas sobre el separador (efectos sin celda): ahí sí es fondo.
			var piece := image.get_region(cell_rect)
			var without_fill := piece.duplicate() as Image
			SpriteSheet.remove_colors(without_fill, [fill], tolerance)
			if without_fill.get_data() == piece.get_data():
				SpriteSheet.remove_colors(piece, [separator], tolerance)
				image.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), cell_rect.position)
		var removed: Array = [fill]
		var bg := String(options.get("bg", "auto"))
		if bg not in ["auto", "none"]:
			removed.append(Color.html(bg))
		SpriteSheet.remove_colors(image, removed, tolerance)
		result["clean_colors"] = removed.duplicate()
		removed.append(separator)
		result["removed"] = removed
		result["rects"] = SpriteSheet.trim_all(image, cells)
		result["info"] = "Celdas: relleno #%s, separador #%s" % [fill.to_html(false), separator.to_html(false)]
	else:
		var bg := String(options.get("bg", "auto"))
		var removed: Array = []
		var v2_bg := String(options.get("detector", "legacy")) == "v2"
		if bg == "auto" and v2_bg:
			var guess := guess_backgrounds(image)
			removed = guess["colors"]
			if not options.has("tolerance"):
				tolerance = float(guess["tolerance"])
			if guess["kind"] == "damero":
				notes.append("fondo de damero (2 colores) quitado")
			if tolerance > 0.045 and not options.has("tolerance") and not removed.is_empty():
				notes.append("fondo con ruido: tolerancia %.2f" % tolerance)
			# JPG: el ruido rodea los bordes del dibujo y no se borra con el fondo.
			if _flag(options.get("jpeg", false)) and not removed.is_empty() and not options.has("tolerance"):
				tolerance = maxf(tolerance, 0.09)
				notes.append("hoja JPG: tolerancia %.2f y bordes limpiados" % tolerance)
			result["tolerance"] = tolerance
			result["defringe"] = not removed.is_empty()
		elif bg == "auto":
			removed = [SpriteSheet.guess_background(image)]
		elif bg != "none":
			removed = [Color.html(bg)]
			result["defringe"] = v2_bg
		SpriteSheet.remove_colors(image, removed, tolerance)
		if v2_bg and _flag(options.get("jpeg", false)) and not removed.is_empty():
			defringe(image, removed, tolerance, 2)
		result["removed"] = removed
		if mode == "grid":
			var grid := grid_cells(image.get_size(), options)
			if grid.is_empty():
				result["error"] = "Rejilla incompleta: indica el tamaño (64x64) o las columnas y filas."
				return result
			result["rects"] = SpriteSheet.trim_all(image, grid)
			result["info"] = "Rejilla de %d celdas" % grid.size()
		else:
			if int(options.get("lines", 0)) > 0:
				SpriteSheet.remove_lines(image, int(options["lines"]))
			var v2 := String(options.get("detector", "legacy")) == "v2"
			# v2 junta por cercanía real de píxeles: 1 px basta para pelo y estelas sueltas.
			var gap := int(options.get("gap", 1 if v2 else 2))
			var diagonal := int(options.get("connect", 8)) != 4
			var rects: Array[Rect2i] = detect_fast(image, min_size, gap) if v2 				else SpriteSheet.detect_frames(image, min_size, gap, diagonal)
			# Hojas apretadas: los rectángulos se solapan y la unión de piezas encadena
			# paneles enteros en un solo cuadro gigante. Se repite sin unir.
			var probing := options.has("_probe")
			if auto and not probing and not options.has("gap") and _has_giant(rects, image.get_size()):
				var retry: Array[Rect2i] = detect_fast(image, maxi(min_size, 16), 0) if v2 					else SpriteSheet.detect_frames(image, maxi(min_size, 16), -1, false)
				if retry.size() > rects.size():
					rects = retry
					notes.append("sprites apretados: sin unir piezas (--gap -1 --connect 4)")
			if _flag(options.get("split", false)):
				rects = split_wide(image, rects)
			elif auto and not probing and not options.has("split") and _has_pairs(rects):
				# No se parte solo: un golpe con arma extendida también es ancho. Se avisa.
				notes.append("hay cuadros muy anchos: si son dos sprites pegados, usa --split")
			result["rects"] = rects
			var bg_text := "ninguno"
			if not removed.is_empty() and (removed[0] as Color).a > 0.5:
				bg_text = "#" + (removed[0] as Color).to_html(false)
			result["info"] = "Fondo liso: %s" % bg_text
	result["mode"] = mode
	if (result["rects"] as Array).is_empty():
		result["error"] = "No se ha encontrado ningún cuadro. Prueba otro modo, otro color de fondo o más tolerancia."
	return result


static func _flag(value: Variant) -> bool:
	return value is bool and value or (value is String and String(value).to_lower() in ["true", "1", "si", "sí"]) 		or ((value is int or value is float) and value != 0)


## Parte los cuadros mucho más anchos que la mediana (dos sprites que se tocan por un
## pelo o una cinta) por la columna con menos dibujo, si esa columna casi está vacía.
static func split_wide(image: Image, rects: Array[Rect2i], factor := 1.5) -> Array[Rect2i]:
	if rects.size() < 3:
		return rects
	var widths: Array = rects.map(func(r: Rect2i) -> int: return r.size.x)
	widths.sort()
	var median: int = widths[widths.size() / 2]
	var out: Array[Rect2i] = []
	var pending: Array[Rect2i] = rects.duplicate()
	while not pending.is_empty():
		var r: Rect2i = pending.pop_front()
		if r.size.x <= median * factor:
			out.append(r)
			continue
		var counts := PackedInt32Array()
		counts.resize(r.size.x)
		var tallest := 1
		for x in r.size.x:
			var n := 0
			for y in r.size.y:
				if image.get_pixel(r.position.x + x, r.position.y + y).a > 0.0:
					n += 1
			counts[x] = n
			tallest = maxi(tallest, n)
		var margin := int(median * 0.6)
		var best := -1
		for x in range(margin, r.size.x - margin):
			if best < 0 or counts[x] < counts[best] or (counts[x] == counts[best] 					and absi(x - r.size.x / 2) < absi(best - r.size.x / 2)):
				best = x
		if best < 0 or counts[best] > maxi(3, tallest / 8):
			out.append(r)
			continue
		var left := SpriteSheet.trim(image, Rect2i(r.position, Vector2i(best, r.size.y)))
		var right := SpriteSheet.trim(image, Rect2i(r.position.x + best, r.position.y, r.size.x - best, r.size.y))
		for part in [left, right]:
			if part.has_area():
				pending.append(part)
	return SpriteSheet.sort_reading_order(out)


## "2" -> 2 px por cada lado; "1,0,2,2" -> izquierda, arriba, derecha, abajo.
## Devuelve Rect2i(izq, arriba, der, abajo) (vacío si no hay recorte).
static func parse_crop(text: String) -> Rect2i:
	text = text.strip_edges()
	if text == "" or text == "0":
		return Rect2i()
	var parts := text.split(",")
	if parts.size() == 1:
		var n := maxi(0, parts[0].to_int())
		return Rect2i(n, n, n, n)
	var v := [0, 0, 0, 0]
	for i in mini(4, parts.size()):
		v[i] = maxi(0, parts[i].to_int())
	return Rect2i(v[0], v[1], v[2], v[3])


static func _with(options: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy := options.duplicate()
	copy[key] = value
	return copy


static func _pair(text: String, sep: String) -> Vector2i:
	var parts := text.split(sep)
	return Vector2i(parts[0].to_int(), parts[1].to_int() if parts.size() > 1 else parts[0].to_int())


## Detector v2: islas de píxeles opacos con BitMap (código nativo, ~50 veces más rápido
## que recorrer la hoja en GDScript). gap > 0 junta piezas a esa distancia o menos por
## cercanía real de píxeles (no por rectángulos que se solapan).
static func detect_fast(image: Image, min_size := 8, gap := 2) -> Array[Rect2i]:
	var bm := BitMap.new()
	bm.create_from_image_alpha(image, 0.004)
	var bounds := Rect2i(Vector2i.ZERO, bm.get_size())
	var grow := maxi(gap, 0)
	if grow > 0:
		bm.grow_mask(grow, bounds)
	var boxes: Array[Rect2i] = []
	for poly: PackedVector2Array in bm.opaque_to_polygons(bounds, 1.0):
		if poly.is_empty():
			continue
		var r := Rect2(poly[0], Vector2.ZERO)
		for point in poly:
			r = r.expand(point)
		boxes.append(Rect2i(r.position.floor(), (r.size + Vector2.ONE).ceil()))
	# BitMap no devuelve los huecos: cada isla sale una vez, también las que están dentro
	# de un marco dibujado en la hoja.
	var out: Array[Rect2i] = []
	for box in boxes:
		# El contorno simplificado puede quedarse 1 px corto; la dilatación sobra.
		var area := box.grow(1 - grow).intersection(bounds) if grow > 0 else box.grow(1).intersection(bounds)
		var trimmed := SpriteSheet.trim(image, area)
		if trimmed.size.x >= min_size and trimmed.size.y >= min_size:
			out.append(trimmed)
	return SpriteSheet.sort_reading_order(out)


## Imagen limpia de cada cuadro `indices`, recortada a lo dibujado. Con el detector v2
## y una hoja analizada reducida se recorta de la hoja original (tamaño completo).
static func frame_images(analysis: Dictionary, indices: Array[int]) -> Dictionary:
	var rects: Array[Rect2i] = analysis["rects"]
	var image: Image = analysis["image"]
	var full: Variant = analysis.get("full", null)
	var scale := float(analysis.get("scale", 1.0))
	var flipped := bool(analysis.get("flipped", false))
	var out := {}
	for index in indices:
		var r: Rect2i = rects[index]
		var region: Image
		if full is Image and scale < 0.999:
			var src: Image = full
			if flipped:
				r = Rect2i(image.get_width() - r.end.x, r.position.y, r.size.x, r.size.y)
			var margin := int(ceilf(2.0 / scale))
			var pos := Vector2i((Vector2(r.position) / scale).floor()) - Vector2i(margin, margin)
			var size := Vector2i((Vector2(r.size) / scale).ceil()) + Vector2i(margin, margin) * 2
			region = src.get_region(Rect2i(pos, size).intersection(Rect2i(Vector2i.ZERO, src.get_size())))
			_clean_region(region, analysis)
			if flipped:
				region.flip_x()
		else:
			region = image.get_region(r)
		if bool(analysis.get("defringe", false)):
			defringe(region, analysis.get("removed", []), float(analysis.get("tolerance", 0.04)))
		var used := region.get_used_rect()
		out[index] = region.get_region(used) if used.has_area() else region
	return out


## Aplica a un trozo de la hoja original la misma limpieza que a la hoja analizada.
static func _clean_region(region: Image, analysis: Dictionary) -> void:
	var alpha_min := int(analysis.get("alpha_min", 0))
	if alpha_min > 0:
		var pixels := region.get_data()
		for i in range(3, pixels.size(), 4):
			if pixels[i] < alpha_min:
				pixels[i] = 0
		region.set_data(region.get_width(), region.get_height(), false, Image.FORMAT_RGBA8, pixels)
	var colors: Array = analysis.get("clean_colors", analysis.get("removed", []))
	if not colors.is_empty():
		SpriteSheet.remove_colors(region, colors, float(analysis.get("tolerance", 0.04)))


## true si algún cuadro ocupa una parte enorme de la hoja (varios sprites unidos).
static func _has_giant(rects: Array[Rect2i], size: Vector2i) -> bool:
	if rects.size() < 2:
		return not rects.is_empty() and rects[0].get_area() > size.x * size.y / 4
	for r in rects:
		if r.get_area() > size.x * size.y / 16:
			return true
	return false


## true si hay cuadros más del doble de anchos que la mediana (dos sprites pegados).
static func _has_pairs(rects: Array[Rect2i]) -> bool:
	if rects.size() < 6:
		return false
	var widths: Array = rects.map(func(r: Rect2i) -> int: return r.size.x)
	widths.sort()
	var median: int = widths[widths.size() / 2]
	for r in rects:
		if r.size.x > median * 2.2 and r.size.y < median * 3:
			return true
	return false


## Celdas de una rejilla fija: por tamaño (grid "64x64") o por columnas y filas.
static func grid_cells(size: Vector2i, options: Dictionary) -> Array[Rect2i]:
	var offset := _pair(String(options.get("offset", "0,0")), ",")
	var spacing := _pair(String(options.get("spacing", "0,0")), ",")
	var area := size - offset
	var cols := int(options.get("grid_cols", 0))
	var rows := int(options.get("grid_rows", 0))
	var cell := Vector2i.ZERO
	if String(options.get("grid", "")) != "":
		cell = _pair(String(options["grid"]), "x")
	if cols > 0:
		cell.x = (area.x - spacing.x * (cols - 1)) / cols
	if rows > 0:
		cell.y = (area.y - spacing.y * (rows - 1)) / rows
	if cell.x <= 0 or cell.y <= 0:
		return []
	if cols <= 0:
		cols = (area.x + spacing.x) / (cell.x + spacing.x)
	if rows <= 0:
		rows = (area.y + spacing.y) / (cell.y + spacing.y)
	var rects: Array[Rect2i] = []
	for i in cols * rows:
		var rect := SpriteSheet.grid_rect(cell, cols, i, offset, spacing)
		rects.append(rect.intersection(Rect2i(Vector2i.ZERO, size)))
	return rects


## Fondo inteligente (detector v2): mira los bordes de la hoja y devuelve los colores de
## fondo (1 en un fondo liso, 2 en el damero gris y blanco que imita la transparencia) y
## una tolerancia a medida (las hojas en JPG tienen ruido y el fondo no es de un solo color).
## {"colors": Array[Color], "tolerance": float, "kind": "liso" | "damero" | "transparente" | "ninguno"}
static func guess_backgrounds(image: Image) -> Dictionary:
	var w := image.get_width()
	var h := image.get_height()
	var samples: Array[Color] = []
	var step := maxi(1, (w + h) * 2 / 4000)
	for x in range(0, w, step):
		for y in [0, 1, h - 2, h - 1]:
			samples.append(image.get_pixel(x, clampi(y, 0, h - 1)))
	for y in range(0, h, step):
		for x in [0, 1, w - 2, w - 1]:
			samples.append(image.get_pixel(clampi(x, 0, w - 1), y))
	var transparent := 0
	var counts := {}
	for c in samples:
		if c.a < 0.5:
			transparent += 1
			continue
		var key := ((c.r8 >> 3) << 10) | ((c.g8 >> 3) << 5) | (c.b8 >> 3)
		counts[key] = counts.get(key, 0) + 1
	if transparent > samples.size() / 2:
		return {"colors": [], "tolerance": 0.04, "kind": "transparente"}
	var keys := counts.keys()
	keys.sort_custom(func(a: int, b: int) -> bool: return counts[a] > counts[b])
	# Colores de fondo: los que más se repiten en el borde (cada uno al menos el 12 %).
	var colors: Array[Color] = []
	var covered := 0
	var opaque := samples.size() - transparent
	for key: int in keys:
		if colors.size() >= 2 or counts[key] < opaque * 0.12:
			break
		var near := false
		for c in colors:
			if absi(c.r8 - ((key >> 10) << 3)) <= 24 and absi(c.g8 - (((key >> 5) & 31) << 3)) <= 24 \
					and absi(c.b8 - ((key & 31) << 3)) <= 24:
				near = true
		if near:
			continue
		# Color medio real de las muestras de esa casilla (no el redondeado).
		var sum := Vector3.ZERO
		var n := 0
		for c in samples:
			if c.a >= 0.5 and (((c.r8 >> 3) << 10) | ((c.g8 >> 3) << 5) | (c.b8 >> 3)) == key:
				sum += Vector3(c.r, c.g, c.b)
				n += 1
		sum /= maxi(1, n)
		colors.append(Color(sum.x, sum.y, sum.z))
		covered += counts[key]
	if colors.is_empty() or covered < opaque * 0.5:
		return {"colors": [], "tolerance": 0.04, "kind": "ninguno"}
	# Tolerancia: distancia del 90 % de las muestras de fondo a su color (ruido del JPG).
	var dists: Array[float] = []
	for c in samples:
		if c.a < 0.5:
			continue
		var best := 1.0
		for bg in colors:
			best = minf(best, maxf(absf(c.r - bg.r), maxf(absf(c.g - bg.g), absf(c.b - bg.b))))
		if best < 0.25:
			dists.append(best)
	dists.sort()
	var spread: float = dists[int(dists.size() * 0.9)] if not dists.is_empty() else 0.0
	var tolerance := clampf(spread + 0.025, 0.04, 0.2)
	return {"colors": colors, "tolerance": tolerance, "kind": "damero" if colors.size() == 2 else "liso"}


## Quita el halo del color de fondo que queda en el borde de un sprite: los píxeles
## opacos pegados a lo transparente que se parecen mucho al fondo.
static func defringe(region: Image, colors: Array, tolerance: float, passes := 2) -> void:
	if colors.is_empty():
		return
	var w := region.get_width()
	var h := region.get_height()
	var limit := tolerance * 2.5
	for p in passes:
		var data := region.get_data()
		var clear := PackedInt32Array()
		for y in h:
			for x in w:
				var i := (y * w + x) * 4
				if data[i + 3] == 0:
					continue
				var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1 \
					or data[i - 4 + 3] == 0 or data[i + 4 + 3] == 0 \
					or data[i - w * 4 + 3] == 0 or data[i + w * 4 + 3] == 0
				if not edge:
					continue
				for c: Color in colors:
					if absf(data[i] / 255.0 - c.r) <= limit and absf(data[i + 1] / 255.0 - c.g) <= limit \
							and absf(data[i + 2] / 255.0 - c.b) <= limit:
						clear.append(i)
						break
		if clear.is_empty():
			return
		for i in clear:
			data[i + 3] = 0
		region.set_data(w, h, false, Image.FORMAT_RGBA8, data)


## Cuadros repetidos: {índice: {"of": índice del original, "mirror": bool}}.
## "mirror" = es el mismo dibujo girado en horizontal (hojas con las dos direcciones).
static func find_duplicates(image: Image, rects: Array[Rect2i]) -> Dictionary:
	var seen := {}
	var coarse := {}  ## casilla de tamaño -> cuadros únicos con ese tamaño aproximado
	var masks := {}
	var hists := {}
	var out := {}
	for i in rects.size():
		var region := image.get_region(rects[i])
		var key := "%s:%d" % [rects[i].size, hash(region.get_data())]
		if seen.has(key):
			out[i] = {"of": seen[key], "mirror": false}
			continue
		var flipped := region.duplicate() as Image
		flipped.flip_x()
		var flipped_key := "%s:%d" % [rects[i].size, hash(flipped.get_data())]
		if seen.has(flipped_key):
			out[i] = {"of": seen[flipped_key], "mirror": true}
			continue
		# Misma silueta con otros colores: variante de color (hojas con varias paletas).
		var mask_key := "m%s:%d" % [rects[i].size, hash(_alpha_mask(region))]
		if seen.has(mask_key):
			out[i] = {"of": seen[mask_key], "mirror": false, "recolor": true}
			continue
		# Con ruido (JPG) la silueta no es idéntica: se compara una versión de 16x16 y se
		# exige que los colores sean claramente distintos (si no, son cuadros de una
		# animación que se parecen, como la respiración del reposo).
		var small := _coarse_mask(region)
		var hist := color_histogram(image, rects[i], 1500)
		var bucket := Vector2i(rects[i].size.x / 6, rects[i].size.y / 6)
		var found := -1
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				for j: int in coarse.get(bucket + Vector2i(dx, dy), []):
					var other: Rect2i = rects[j]
					if absi(other.size.x - rects[i].size.x) > 3 or absi(other.size.y - rects[i].size.y) > 3:
						continue
					if _mask_difference(small, masks[j]) <= 10 and _intersection(hist, hists[j]) < 0.5:
						found = j
						break
				if found >= 0:
					break
			if found >= 0:
				break
		if found >= 0:
			out[i] = {"of": found, "mirror": false, "recolor": true}
			continue
		if not coarse.has(bucket):
			coarse[bucket] = []
		coarse[bucket].append(i)
		masks[i] = small
		hists[i] = hist
		seen[key] = i
		seen[mask_key] = i
	return out


## Casillas distintas entre dos siluetas reducidas.
static func _mask_difference(a: PackedByteArray, b: PackedByteArray) -> int:
	var diff := 0
	for k in mini(a.size(), b.size()):
		if a[k] != b[k]:
			diff += 1
	return diff


## Silueta reducida a 16x16 (cada casilla: más de la mitad opaca o no).
static func _coarse_mask(region: Image) -> PackedByteArray:
	var small := region.duplicate() as Image
	small.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	var data := small.get_data()
	var mask := PackedByteArray()
	mask.resize(256)
	for p in 256:
		mask[p] = 1 if data[p * 4 + 3] >= 128 else 0
	return mask


## Silueta del cuadro (1 byte por píxel: opaco o no), para comparar formas.
static func _alpha_mask(region: Image) -> PackedByteArray:
	var data := region.get_data()
	var mask := PackedByteArray()
	mask.resize(data.size() / 4)
	for p in mask.size():
		mask[p] = 1 if data[p * 4 + 3] >= 128 else 0
	return mask


## Texto para un repetido: "una copia", "el reflejo" o "otra paleta de color".
static func duplicate_text(dup: Dictionary) -> String:
	if dup.get("recolor", false):
		return "otra paleta de color"
	return "el reflejo" if dup.get("mirror", false) else "una copia"


## Agrupa los cuadros (ya en orden de lectura) por filas de la hoja.
static func rows(rects: Array[Rect2i]) -> Array:
	var out: Array = []
	var current: Array = []
	var first := Rect2i()
	for i in rects.size():
		var r := rects[i]
		var same_row := not current.is_empty() and r.position.y < first.position.y + first.size.y / 2 \
				and r.position.x > rects[i - 1].position.x
		if not same_row:
			if not current.is_empty():
				out.append(current)
			current = []
			first = r
		current.append(i)
	if not current.is_empty():
		out.append(current)
	return out


## Mapa de partida para rellenar: cada fila de la hoja (sin repetidos) con un nombre
## provisional, y "idle" con el primer cuadro.
static func draft_map(rects: Array[Rect2i], duplicates: Dictionary) -> Dictionary:
	var map := {"_ayuda": "Cambia cada \"fila_N\" por una pose (idle, walk, jab, finisher, hurt...) y borra las que no uses. Las claves que empiezan por _ se ignoran."}
	var n := 1
	for row: Array in rows(rects):
		var unique: Array = []
		for i: int in row:
			if not duplicates.has(i):
				unique.append(i)
		if unique.is_empty():
			continue
		map["fila_%d" % n] = unique
		n += 1
	if not rects.is_empty():
		map["idle"] = [0]
	return map


# --- Clasificación de piezas y grupos de animación ---------------------------------

const KIND_NAMES := {"personaje": "personaje", "efecto": "efecto", "texto": "texto", "arte": "ilustración", "pieza": "pieza suelta", "marco": "marco o línea", "variante": "variante de color"}
## Poses en las que es normal mezclar cuadros de alturas distintas.
const MIXED_OK := ["jump", "fall", "down", "special", "charge", "hurt", "intro", "victory", "walk", "run", "run_alt"]


## Histograma de colores (4 bits por canal) normalizado de los píxeles opacos de `rect`.
static func color_histogram(image: Image, rect: Rect2i, samples := 2500) -> Dictionary:
	var data := image.get_region(rect).get_data()
	var count := data.size() / 4
	var step := maxi(1, count / samples)
	var hist := {}
	var total := 0
	for p in range(0, count, step):
		var i := p * 4
		if data[i + 3] < 128:
			continue
		var key := ((data[i] >> 4) << 8) | ((data[i + 1] >> 4) << 4) | (data[i + 2] >> 4)
		hist[key] = hist.get(key, 0) + 1
		total += 1
	if total > 0:
		for key in hist:
			hist[key] = float(hist[key]) / total
	return hist


## Parte del rectángulo que está pintada (0 a 1), por muestreo.
static func _fill_ratio(image: Image, rect: Rect2i, samples := 2500) -> float:
	var data := image.get_region(rect).get_data()
	var count := data.size() / 4
	var step := maxi(1, count / samples)
	var solid := 0
	var seen := 0
	for p in range(0, count, step):
		seen += 1
		if data[p * 4 + 3] >= 128:
			solid += 1
	return float(solid) / maxi(1, seen)


static func _intersection(a: Dictionary, b: Dictionary) -> float:
	var s := 0.0
	for key in a:
		if b.has(key):
			s += minf(a[key], b[key])
	return s


## Colores (casillas del histograma) que cubren el 90 % de la pieza.
static func _main_colors(hist: Dictionary) -> int:
	var values: Array = hist.values()
	values.sort()
	values.reverse()
	var acc := 0.0
	var n := 0
	for v: float in values:
		acc += v
		n += 1
		if acc >= 0.9:
			break
	return n


## Clasifica cada cuadro y agrupa los del personaje en animaciones.
## Devuelve {"kinds": Array[String], "similarity": Array[float], "groups": Array (de Array[int]),
##   "group_of": {índice: grupo}, "median_h": int, "median_w": int, "counts": {tipo: n}}.
## El personaje es lo que comparte paleta con la mayoría (ponderada por tamaño): los
## efectos (rayos, fuego, energía), los letreros y las ilustraciones tienen otros colores.
static func classify(image: Image, rects: Array[Rect2i], duplicates: Dictionary = {}) -> Dictionary:
	var n := rects.size()
	var hists: Array = []
	var weights: Array[float] = []
	for r in rects:
		hists.append(color_histogram(image, r))
		weights.append(sqrt(float(r.get_area())))
	var sims: Array[float] = []
	sims.resize(n)
	var chosen: Array = range(n)
	for round_index in 3:
		var reference := {}
		var total_w := 0.0
		for i: int in chosen:
			total_w += weights[i]
			var h: Dictionary = hists[i]
			for key in h:
				reference[key] = reference.get(key, 0.0) + h[key] * weights[i]
		if total_w <= 0.0:
			break
		for key in reference:
			reference[key] /= total_w
		for i in n:
			sims[i] = _intersection(hists[i], reference)
		# Siguiente vuelta: solo la mitad más parecida (se queda con el personaje).
		var order: Array = range(n)
		order.sort_custom(func(a: int, b: int) -> bool: return sims[a] > sims[b])
		chosen = order.slice(0, maxi(1, n / 2))
	var top: Array[float] = []
	for i: int in chosen:
		top.append(sims[i])
	top.sort()
	var cut := 0.5 * (top[top.size() / 2] if not top.is_empty() else 0.0)
	var kinds: Array[String] = []
	kinds.resize(n)
	var heights: Array[int] = []
	var widths: Array[int] = []
	for i in n:
		kinds[i] = "personaje" if sims[i] >= cut else "efecto"
		if kinds[i] == "personaje":
			heights.append(rects[i].size.y)
			widths.append(rects[i].size.x)
	heights.sort()
	widths.sort()
	var median_h: int = heights[heights.size() / 2] if not heights.is_empty() else 1
	var median_w: int = widths[widths.size() / 2] if not widths.is_empty() else 1
	for i in n:
		var r := rects[i]
		var colors := _main_colors(hists[i])
		if r.get_area() > median_h * median_w * 2 and _fill_ratio(image, r) < 0.08:
			kinds[i] = "marco"
		elif r.get_area() > median_h * median_w * 5 and colors > 12:
			kinds[i] = "arte"
		elif r.size.y < median_h * 0.6 and colors <= 4:
			kinds[i] = "texto"
		elif kinds[i] == "personaje" and r.size.y < median_h * 0.35 and r.size.x < median_w * 0.6:
			kinds[i] = "pieza"
		if duplicates.get(i, {}).get("recolor", false):
			kinds[i] = "variante"
	# Grupos: cuadros del personaje seguidos en una fila, sin un hueco grande entre ellos.
	var groups: Array = []
	var group_of := {}
	for row: Array in rows(rects):
		var current: Array[int] = []
		var last_end := -1
		for i: int in row:
			if kinds[i] != "personaje":
				continue
			if not current.is_empty() and rects[i].position.x - last_end > maxf(median_w * 1.6, median_h * 0.8):
				groups.append(current)
				current = []
			current.append(i)
			last_end = rects[i].end.x
		if not current.is_empty():
			groups.append(current)
	for g in groups.size():
		for i: int in groups[g]:
			group_of[i] = g
	var counts := {}
	for k in kinds:
		counts[k] = counts.get(k, 0) + 1
	return {"kinds": kinds, "similarity": sims, "groups": groups, "group_of": group_of,
		"median_h": median_h, "median_w": median_w, "counts": counts}


## Pista de lo que parece un grupo, por la forma de sus cuadros.
static func group_hint(rects: Array[Rect2i], group: Array, info: Dictionary) -> String:
	var mh := float(info["median_h"])
	var mw := float(info["median_w"])
	var avg_h := 0.0
	var avg_w := 0.0
	var min_h := 1 << 30
	var max_h := 0
	for i: int in group:
		avg_h += rects[i].size.y
		avg_w += rects[i].size.x
		min_h = mini(min_h, rects[i].size.y)
		max_h = maxi(max_h, rects[i].size.y)
	avg_h /= group.size()
	avg_w /= group.size()
	if avg_h < mh * 0.6 and avg_w > avg_h * 1.4:
		return "tumbado: down / fall"
	if avg_w > mw * 1.6:
		return "golpe con alcance: heavy / finisher_impact / special"
	if group.size() >= 4 and max_h - min_h <= mh * 0.12 and absf(avg_w - mw) < mw * 0.35:
		return "de pie y quieto: idle / victory / intro"
	if group.size() >= 5 and avg_w > mw * 1.1:
		return "desplazamiento: walk / run"
	if avg_h < mh * 0.85 and avg_w < mw * 1.2:
		return "agachado o en el aire: jump / block / hurt"
	return ""


## Hoja de grupos: solo el personaje, un grupo por fila, todos a la misma escala.
static func groups_sheet(image: Image, rects: Array[Rect2i], info: Dictionary, target_h := 72) -> Image:
	var groups: Array = info["groups"]
	var scale := float(target_h) / maxf(1.0, float(info["median_h"]))
	var label_w := 90
	var max_w := 1800
	var lines: Array = []  # [grupo, [índices]], partidos si no caben
	for g in groups.size():
		var line: Array = []
		var x := label_w
		for i: int in groups[g]:
			var w := int(rects[i].size.x * scale) + 6
			if not line.is_empty() and x + w > max_w:
				lines.append([g, line])
				line = []
				x = label_w
			line.append(i)
			x += w
		lines.append([g, line])
	var row_h: Array[int] = []
	var total_h := 0
	for entry: Array in lines:
		var h := 0
		for i: int in entry[1]:
			h = maxi(h, int(rects[i].size.y * scale))
		h = maxi(h, 30) + 16
		row_h.append(h)
		total_h += h
	var out := Image.create_empty(max_w, maxi(total_h, 1), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.12, 0.13, 0.17))
	var y := 0
	var last_group := -1
	for li in lines.size():
		var g: int = lines[li][0]
		if g % 2 == 1:
			out.fill_rect(Rect2i(0, y, max_w, row_h[li]), Color(0.15, 0.16, 0.21))
		if g != last_group:
			draw_text(out, "G%d" % (g + 1), Vector2i(4, y + 4), Color(1, 0.85, 0.3), 2, Color(0, 0, 0, 0))
			draw_text(out, "%d CUADROS" % (groups[g] as Array).size(), Vector2i(4, y + 20), Color(0.6, 0.65, 0.75), 1, Color(0, 0, 0, 0))
			var hint := group_hint(rects, groups[g], info)
			if hint != "":
				draw_text(out, hint.get_slice(":", 0), Vector2i(4, y + 30), Color(0.5, 0.85, 1.0), 1, Color(0, 0, 0, 0))
			last_group = g
		var x := label_w
		var base := y + row_h[li] - 4
		for i: int in lines[li][1]:
			var sub := image.get_region(rects[i])
			var w := maxi(1, int(rects[i].size.x * scale))
			var h := maxi(1, int(rects[i].size.y * scale))
			sub.resize(w, h, Image.INTERPOLATE_BILINEAR if scale < 1.0 else Image.INTERPOLATE_NEAREST)
			out.blend_rect(sub, Rect2i(Vector2i.ZERO, sub.get_size()), Vector2i(x, base - h))
			draw_text(out, str(i), Vector2i(x, y + 3), Color.YELLOW, 1, Color(0, 0, 0, 0.7))
			x += w + 6
		out.fill_rect(Rect2i(label_w, base, max_w - label_w, 1), Color(0.3, 0.34, 0.44))
		y += row_h[li]
	return out


## Borrador del mapa por grupos: el primer grupo de pie como idle, los demás con su pista.
static func draft_map_groups(rects: Array[Rect2i], info: Dictionary, duplicates: Dictionary) -> Dictionary:
	var map := {"_ayuda": "Cada grupo_N es una animación de la hoja (mira tools/out/<id>_grupos.png). Cambia su nombre por la pose (idle, walk, jab, finisher, hurt...) y borra los que no uses. _pistas dice lo que parece cada uno."}
	var hints := {}
	var idle_done := false
	var groups: Array = info["groups"]
	for g in groups.size():
		var frames: Array = []
		for i: int in groups[g]:
			if not duplicates.has(i):
				frames.append(i)
		if frames.is_empty():
			continue
		var hint := group_hint(rects, groups[g], info)
		var key := "grupo_%d" % (g + 1)
		if not idle_done and hint.begins_with("de pie"):
			key = "idle"
			idle_done = true
		map[key] = frames
		if hint != "" and key != "idle":
			hints[key] = hint
	if not idle_done and groups.size() > 0:
		map["idle"] = [groups[0][0]]
	_propose_poses(map, hints)
	if not hints.is_empty():
		map["_pistas"] = hints
	return map


## Pone nombre de pose a los grupos más claros (en el orden habitual de las hojas:
## reposo, andar, correr, salto, ..., daño, caída, ..., victoria). Lo dudoso queda como grupo_N.
static func _propose_poses(map: Dictionary, hints: Dictionary) -> void:
	var by_hint := {}
	var order: Array = []
	for key in map:
		if String(key).begins_with("grupo_"):
			order.append(key)
	order.sort_custom(func(a: String, b: String) -> bool: return a.substr(6).to_int() < b.substr(6).to_int())
	for key in order:
		var hint := String(hints.get(key, "")).get_slice(":", 0)
		if not by_hint.has(hint):
			by_hint[hint] = []
		by_hint[hint].append(key)
	var renames := {}
	var moving: Array = by_hint.get("desplazamiento", [])
	for key in moving:
		if (map[key] as Array).size() >= 4:
			renames[key] = "walk"
			break
	var standing: Array = by_hint.get("de pie y quieto", [])
	if standing.size() >= 1:
		renames[standing[standing.size() - 1]] = "victory"
	if standing.size() >= 2:
		renames[standing[0]] = "intro"
	var lying: Array = by_hint.get("tumbado", [])
	if lying.size() >= 1:
		var frames: Array = map[lying[0]]
		if frames.size() >= 2:
			renames[lying[0]] = "fall"
		if lying.size() >= 2:
			renames[lying[1]] = "down"
		elif frames.size() == 1:
			renames[lying[0]] = "down"
	for old in renames:
		var pose: String = renames[old]
		if map.has(pose):
			continue
		map[pose] = map[old]
		map.erase(old)
		hints[pose] = "propuesto (%s): revísalo en las poses" % old
		hints.erase(old)


## Revisión del mapa: avisa de cuadros que no parecen del personaje y de poses que mezclan
## tamaños muy distintos (casi siempre un número equivocado).
static func review_map(normalized: Dictionary, rects: Array[Rect2i], info: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var kinds: Array = info.get("kinds", [])
	var poses: Dictionary = normalized["poses"]
	for key in poses:
		var frames: Array = poses[key]
		for i: int in frames:
			if i < kinds.size() and kinds[i] != "personaje":
				out.append("\"%s\" usa el cuadro %d, que parece %s (no el personaje)." % [key, i, KIND_NAMES.get(kinds[i], kinds[i])])
		if frames.size() > 1 and not MIXED_OK.has(key):
			var lo := 1 << 30
			var hi := 0
			for i: int in frames:
				lo = mini(lo, rects[i].size.y)
				hi = maxi(hi, rects[i].size.y)
			if hi > lo * 1.4:
				out.append("\"%s\" mezcla cuadros de alturas muy distintas (%d y %d px): ¿algún número equivocado?" % [key, lo, hi])
	if poses.has("idle"):
		var first: int = poses["idle"][0]
		var r := rects[first]
		if r.size.x > r.size.y * 1.3:
			out.append("El reposo (idle, cuadro %d) es más ancho que alto: ¿está tumbado o es un golpe?" % first)
	return out


# --- Mapa de poses ----------------------------------------------------------------

static func is_valid_pose(key: String) -> bool:
	if POSES.has(key):
		return true
	if key.begins_with("seq_") and SEQUENCE_ANIMS.has(key.substr(4)):
		return true
	var cut := key.rfind("_")
	while cut > 0:
		if ATTACKS.has(key.substr(0, cut)) and PHASES.has(key.substr(cut + 1)):
			return true
		cut = key.rfind("_", cut - 1)
	return false


## Valida el mapa {pose: número | [números]} contra los cuadros que hay.
## Traduce nombres habituales (kick -> finisher, salto -> jump...), quita números que
## no existen y avisa de los cuadros repetidos. Las claves que empiezan por "_" son
## ajustes: _frame_time {pose: segundos}, _height (altura), _flip (bool).
## Devuelve {"poses": {pose: Array[int]}, "single": {pose: true si era un número},
##   "settings": {...}, "warnings": PackedStringArray, "errors": PackedStringArray}.
static func normalize_map(map: Dictionary, frame_count: int, duplicates: Dictionary = {}) -> Dictionary:
	var poses := {}
	var single := {}
	var settings := {}
	var warnings := PackedStringArray()
	var errors := PackedStringArray()
	for raw_key in map:
		var key := String(raw_key).strip_edges()
		if key.begins_with("_"):
			settings[key.substr(1)] = map[raw_key]
			continue
		var lower := key.to_lower()
		if not is_valid_pose(lower) and ALIASES.has(lower):
			warnings.append("\"%s\" no es una pose del juego: se usa como \"%s\"." % [key, ALIASES[lower]])
			lower = ALIASES[lower]
		if not is_valid_pose(lower):
			errors.append("\"%s\" no es una pose que el juego entienda. Poses: %s" % [key, ", ".join(PackedStringArray(POSES.keys()))])
			continue
		if poses.has(lower):
			warnings.append("La pose \"%s\" aparece dos veces; se queda la última." % lower)
		var value: Variant = map[raw_key]
		var list: Array = value if value is Array else [value]
		var frames: Array[int] = []
		for item in list:
			if not (item is int or item is float or (item is String and String(item).is_valid_int())):
				errors.append("En \"%s\", \"%s\" no es un número de cuadro." % [key, item])
				continue
			var index := int(item)
			if index < 0 or index >= frame_count:
				errors.append("El cuadro %d de \"%s\" no existe (hay %d, del 0 al %d)." % [index, key, frame_count, frame_count - 1])
				continue
			if duplicates.has(index):
				var dup: Dictionary = duplicates[index]
				warnings.append("El cuadro %d de \"%s\" es %s del %d (vale, pero sobra uno de los dos)." % [
					index, key, duplicate_text(dup), dup["of"]])
			frames.append(index)
		if frames.is_empty():
			continue
		poses[lower] = frames
		single[lower] = not (value is Array)
	if not poses.has("idle"):
		errors.append("Falta la pose \"idle\" (reposo): es la única obligatoria.")
	return {"poses": poses, "single": single, "settings": settings, "warnings": warnings, "errors": errors}


# --- Empaquetado y bloque del catálogo ---------------------------------------------

## Cuadros que usan las poses, sin repetir, en el orden en que aparecen.
static func used_frames(poses: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for key in poses:
		for index: int in poses[key]:
			if not out.has(index):
				out.append(index)
	return out


## Gira en horizontal la hoja limpia y los rectángulos (luchadores que miran a la izquierda).
static func flip_sheet(image: Image, rects: Array[Rect2i]) -> Array[Rect2i]:
	image.flip_x()
	var out: Array[Rect2i] = []
	for r in rects:
		out.append(Rect2i(image.get_width() - r.end.x, r.position.y, r.size.x, r.size.y))
	return out


## Empaqueta los cuadros `indices` en celdas iguales con los pies abajo al centro.
## Devuelve lo mismo que SpriteSheet.pack_uniform más "slot": {índice original: celda}.
static func pack(image: Image, rects: Array[Rect2i], indices: Array[int], columns := 8) -> Dictionary:
	var subset: Array[Rect2i] = []
	var slot := {}
	for index in indices:
		slot[index] = subset.size()
		subset.append(rects[index])
	var packed := SpriteSheet.pack_uniform(image, subset, columns)
	packed["slot"] = slot
	return packed


## Centro de la cara en la imagen de una celda: bajo las puntas más altas del dibujo.
## Usa la mediana de las columnas de arriba (no la media) para que cintas, coletas o
## armas que salen de la cabeza no la desplacen.
static func head_point(image: Image, rect: Rect2i) -> Vector2i:
	var used := image.get_region(rect).get_used_rect()
	if not used.has_area():
		return rect.size / 2
	var top := used.position.y
	var band := maxi(2, int(used.size.y * 0.1))
	var columns: Array[int] = []
	for y in range(top, mini(top + band, used.end.y)):
		for x in range(used.position.x, used.end.x):
			if image.get_pixel(rect.position.x + x, rect.position.y + y).a > 0.0:
				columns.append(x)
	columns.sort()
	var cx: int = columns[columns.size() / 2] if not columns.is_empty() else used.get_center().x
	return Vector2i(cx, top + int(used.size.y * 0.14))


## Escribe la hoja empaquetada y devuelve los campos del catálogo como texto GDScript
## (con dos tabuladores de sangría) y algunos datos para el informe.
static func build(image: Image, rects: Array[Rect2i], normalized: Dictionary, sheet_path: String,
		columns := 8, pack_all := false, analysis := {}) -> Dictionary:
	var poses: Dictionary = normalized["poses"]
	var settings: Dictionary = normalized["settings"]
	var indices: Array[int] = []
	if pack_all:
		for i in rects.size():
			indices.append(i)
	else:
		indices = used_frames(poses)
	var packed: Dictionary
	var heights := {}  ## índice -> alto del cuadro en la hoja final
	if String(analysis.get("detector", "legacy")) == "v2":
		packed = _pack_v2(analysis, poses, settings, indices, columns, heights)
	else:
		packed = pack(image, rects, indices, columns)
		for index in indices:
			heights[index] = rects[index].size.y
	var sheet: Image = packed["image"]
	pulir_hoja(sheet, bool(settings.get("alpha_suave", false)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sheet_path.get_base_dir()))
	var err := sheet.save_png(ProjectSettings.globalize_path(sheet_path))
	var cell: Vector2i = packed["cell"]
	var cols: int = packed["columns"]
	var slot: Dictionary = packed["slot"]
	var refs := {}
	for key in poses:
		var list: Array = []
		for index: int in poses[key]:
			list.append(SpriteSheet.cell_ref(sheet_path, cell, cols, slot[index]))
		refs[key] = list
	var idle_first: int = poses["idle"][0]
	# Altura de referencia: la pose de pie más alta (si el reposo es una guardia agachada,
	# medir solo el reposo haría al luchador mucho más grande que los demás).
	var standing := 1
	for key in STANDING_POSES:
		for index: int in poses.get(key, []):
			standing = maxi(standing, int(heights[index]))
	var height := float(settings.get("height", GAME_HEIGHT * cell.y / float(standing)))
	var head := head_point(sheet, SpriteSheet.grid_rect(cell, cols, slot[idle_first]))
	var frame_times := {}
	var custom_times: Dictionary = settings.get("frame_time", {}) if settings.get("frame_time", {}) is Dictionary else {}
	for key in poses:
		if (poses[key] as Array).size() > 1:
			frame_times[key] = float(custom_times.get(key, DEFAULT_FRAME_TIME.get(key, 0.1)))
	var lines := PackedStringArray(['\t\t"sprites": {'])
	for key in poses:
		var list: Array = refs[key]
		if normalized["single"].get(key, false) and list.size() == 1:
			lines.append('\t\t\t"%s": "%s",' % [key, list[0]])
		else:
			lines.append('\t\t\t"%s": [' % key)
			for ref in list:
				lines.append('\t\t\t\t"%s",' % ref)
			lines.append("\t\t\t],")
	lines.append("\t\t},")
	lines.append('\t\t"sprite_anchor": Vector2(%d, %d),' % [cell.x / 2, cell.y])
	if not frame_times.is_empty():
		var parts := PackedStringArray()
		for key in frame_times:
			parts.append('"%s": %s' % [key, _num(frame_times[key])])
		lines.append('\t\t"sprite_frame_time": {%s},' % ", ".join(parts))
	lines.append('\t\t"sprite_height": %s,' % _num(snappedf(height, 0.1)))
	lines.append('\t\t"sprite_head": Vector2(%d, %d),' % [head.x, head.y])
	return {"block": "\n".join(lines), "sheet": sheet, "cell": cell, "columns": cols, "slot": slot, "refs": refs,
		"frames": indices.size(), "height": height, "save_error": err,
		"out_scale": packed.get("out_scale", 1.0)}


## Hoja final del detector v2: cuadros a tamaño completo, reducidos con buen filtro si
## la pose de pie pasa de OUT_MAX_HEIGHT (o a "_out_scale" del mapa), pies robustos.
static func _pack_v2(analysis: Dictionary, poses: Dictionary, settings: Dictionary, indices: Array[int],
		columns: int, heights: Dictionary) -> Dictionary:
	var images := frame_images(analysis, indices)
	var standing_raw := 1
	for key in STANDING_POSES:
		for index: int in poses.get(key, []):
			standing_raw = maxi(standing_raw, (images[index] as Image).get_height())
	var out_scale := float(settings.get("out_scale", 0.0))
	if out_scale <= 0.0:
		out_scale = minf(1.0, float(OUT_MAX_HEIGHT) / standing_raw)
	if out_scale < 0.999:
		for index in images:
			reducir_limpio(images[index], out_scale)
	# Atlas provisional en estantes (una sola fila superaría el ancho máximo de Godot).
	var shelf_width := 8192
	var x := 0
	var y := 0
	var row_height := 0
	var spots := {}
	var total := Vector2i.ONE
	for index in indices:
		var size := (images[index] as Image).get_size()
		if x > 0 and x + size.x > shelf_width:
			x = 0
			y += row_height + 4
			row_height = 0
		spots[index] = Vector2i(x, y)
		x += size.x + 4
		row_height = maxi(row_height, size.y)
		total = Vector2i(maxi(total.x, x), maxi(total.y, y + row_height))
	var atlas := Image.create_empty(total.x, total.y, false, Image.FORMAT_RGBA8)
	var atlas_rects: Array[Rect2i] = []
	var slot := {}
	for index in indices:
		var im: Image = images[index]
		atlas.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), spots[index])
		slot[index] = atlas_rects.size()
		atlas_rects.append(Rect2i(spots[index], im.get_size()))
		heights[index] = im.get_height()
	# "_offset": {"105": [dx, dy]} en el mapa mueve ese cuadro (en píxeles de la hoja final).
	var shifts := {}
	var offsets: Variant = settings.get("offset", {})
	if offsets is Dictionary:
		for key in offsets:
			var index := int(key)
			var value: Variant = offsets[key]
			if slot.has(index) and value is Array and (value as Array).size() >= 2:
				shifts[slot[index]] = Vector2i(int(value[0]), int(value[1]))
	var packed := SpriteSheet.pack_uniform(atlas, atlas_rects, columns, 2, true, shifts)
	packed["slot"] = slot
	packed["out_scale"] = out_scale
	return packed


## Reduce un cuadro sin ensuciarlo: promedia el color de cada zona (mipmaps + trilineal,
## como un filtro de área) en vez de Lanczos, que deja halos y aplana los detalles, y luego
## afina un poco los bordes interiores. El color bajo lo transparente se rellena antes para
## que el promedio no oscurezca el contorno.
static func reducir_limpio(im: Image, escala: float) -> void:
	if escala >= 0.999:
		return
	im.convert(Image.FORMAT_RGBA8)
	im.fix_alpha_edges()
	var w := maxi(1, roundi(im.get_width() * escala))
	var h := maxi(1, roundi(im.get_height() * escala))
	im.generate_mipmaps()
	im.resize(w, h, Image.INTERPOLATE_TRILINEAR)
	im.clear_mipmaps()
	afinar(im, 0.35)


## Máscara de enfoque suave (3x3) solo en el color: recupera el detalle que pierde la reducción.
static func afinar(im: Image, cantidad: float) -> void:
	var w := im.get_width()
	var h := im.get_height()
	if w < 3 or h < 3 or cantidad <= 0.0:
		return
	var copia := im.duplicate() as Image
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := copia.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var media := Color(0, 0, 0, 0)
			var n := 0.0
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var v := copia.get_pixel(x + d.x, y + d.y)
				if v.a >= 0.5:
					media += v
					n += 1.0
			if n < 1.0:
				continue
			media /= n
			im.set_pixel(x, y, Color(clampf(c.r + (c.r - media.r) * cantidad, 0.0, 1.0),
				clampf(c.g + (c.g - media.g) * cantidad, 0.0, 1.0),
				clampf(c.b + (c.b - media.b) * cantidad, 0.0, 1.0), c.a))


## Pulido final de una hoja de sprites:
##  - fuera las medias transparencias casi invisibles (polvo de borde que ensucia el contorno)
##    y lo casi opaco pasa a opaco (salvo alpha_suave, para hojas con humo o resplandores);
##  - el color bajo lo transparente se rellena con el de al lado (fix_alpha_edges): con filtro
##    lineal o al girar/estirar al luchador, el borde ya no saca halos oscuros.
static func pulir_hoja(sheet: Image, alpha_suave := false) -> void:
	sheet.convert(Image.FORMAT_RGBA8)
	if not alpha_suave:
		for y in sheet.get_height():
			for x in sheet.get_width():
				var c := sheet.get_pixel(x, y)
				if c.a > 0.0 and c.a < 0.12:
					sheet.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
				elif c.a > 0.88 and c.a < 1.0:
					sheet.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	sheet.fix_alpha_edges()


static func _num(value: float) -> String:
	var text := "%.3f" % value
	while text.ends_with("0") and not text.ends_with(".0"):
		text = text.substr(0, text.length() - 1)
	return text


# --- Escritura en catalog.gd ------------------------------------------------------

## Posición de la llave o corchete que cierra el que abre en `open_pos`, saltando
## textos entre comillas y comentarios. -1 si no se cierra.
static func match_close(text: String, open_pos: int) -> int:
	var depth := 0
	var i := open_pos
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == '"':
			i += 1
			while i < n and text[i] != '"':
				if text[i] == "\\":
					i += 1
				i += 1
		elif c == "#":
			while i < n and text[i] != "\n":
				i += 1
		elif c == "{" or c == "[" or c == "(":
			depth += 1
		elif c == "}" or c == "]" or c == ")":
			depth -= 1
			if depth == 0:
				return i
		i += 1
	return -1


## [inicio, fin] de la entrada del luchador (la "{" y su "}") en el texto de catalog.gd.
static func find_entry(text: String, id: String) -> Vector2i:
	var at := text.find('"id": "%s"' % id)
	if at < 0:
		return Vector2i(-1, -1)
	var open := text.rfind("\n\t{", at)
	if open < 0:
		return Vector2i(-1, -1)
	open += 2
	var close := match_close(text, open)
	return Vector2i(open, close) if close > at else Vector2i(-1, -1)


## Quita de la entrada (texto entre sus llaves) los campos de primer nivel `keys`,
## con su línea completa (comentario final incluido).
static func remove_fields(body: String, keys: Array) -> String:
	var i := 0
	var n := body.length()
	var cuts: Array[Vector2i] = []
	var depth := 0
	while i < n:
		var c := body[i]
		if c == "#":
			while i < n and body[i] != "\n":
				i += 1
			continue
		if c == '"':
			var end := body.find('"', i + 1)
			if end < 0:
				break
			var word := body.substr(i + 1, end - i - 1)
			var after := end + 1
			while after < n and body[after] == " ":
				after += 1
			if depth == 0 and after < n and body[after] == ":" and keys.has(word):
				var value_end := _value_end(body, after + 1)
				var line_start := body.rfind("\n", i) + 1
				var line_end := body.find("\n", value_end)
				line_end = n if line_end < 0 else line_end + 1
				# Solo se borra la línea entera si en ella no hay más campos.
				var rest := body.substr(value_end + 1, maxi(0, line_end - value_end - 1)).strip_edges()
				var before := body.substr(line_start, i - line_start).strip_edges()
				if before == "" and (rest == "" or rest.begins_with("#")):
					cuts.append(Vector2i(line_start, line_end))
				else:
					cuts.append(Vector2i(i, mini(value_end + 1, n)))
				i = value_end + 1
				continue
			i = end + 1
			continue
		if c == "{" or c == "[" or c == "(":
			depth += 1
		elif c == "}" or c == "]" or c == ")":
			depth -= 1
		i += 1
	for k in range(cuts.size() - 1, -1, -1):
		body = body.substr(0, cuts[k].x) + body.substr(cuts[k].y)
	return body


## Posición de la coma que termina el valor que empieza en `from` (o del final).
static func _value_end(text: String, from: int) -> int:
	var i := from
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == '"':
			var end := text.find('"', i + 1)
			i = (end if end >= 0 else n - 1) + 1
			continue
		if c == "{" or c == "[" or c == "(":
			var close := match_close(text, i)
			i = (close if close >= 0 else n - 1) + 1
			continue
		if c == "," or c == "\n":
			# Un valor sin coma al final termina en el salto de línea.
			if c == "\n" and text.substr(from, i - from).strip_edges() == "":
				i += 1
				continue
			return i if c == "," else i - 1
		if c == "#":
			return i - 1
		i += 1
	return n - 1


## Mete el bloque de sprites en la entrada del luchador `id` (sustituye el anterior).
## Si el luchador no existe, lo crea copiando las estadísticas de `base`.
## Devuelve {"text": nuevo texto, "created": bool, "error": ""}.
static func catalog_with_sprites(text: String, id: String, block: String, display_name := "",
		base := DEFAULT_BASE) -> Dictionary:
	var entry := find_entry(text, id)
	var created := false
	if entry.x < 0:
		var base_entry := find_entry(text, base)
		if base_entry.x < 0:
			# La base no existe (p. ej. se borró): se usa el primer luchador del catálogo.
			var first := text.find('"id": "', text.find("const FIGHTERS := ["))
			if first >= 0:
				base = text.substr(first + 7, text.find('"', first + 7) - first - 7)
				base_entry = find_entry(text, base)
		if base_entry.x < 0:
			return {"text": text, "created": false, "error": "No existe el luchador base \"%s\"." % base}
		var body := text.substr(base_entry.x + 1, base_entry.y - base_entry.x - 1)
		body = remove_fields(body, SPRITE_FIELDS)
		body = _drop_sprite_comments(body)
		body = body.replace('"id": "%s"' % base, '"id": "%s"' % id)
		var name_text := display_name if display_name != "" else id.capitalize()
		var name_at := body.find('"name": "')
		if name_at >= 0:
			var name_end := body.find('"', name_at + 9)
			body = body.substr(0, name_at + 9) + name_text + body.substr(name_end)
		var comment := "\n\t\t# Creado con el importador a partir de \"%s\": ajusta sus estadísticas a gusto." % base
		var new_entry := "\t{" + comment + body.rstrip("\t") + "\t},\n"
		var list_at := text.find("const FIGHTERS := [")
		var list_end := match_close(text, text.find("[", list_at))
		var line_start := text.rfind("\n", list_end) + 1
		text = text.substr(0, line_start) + new_entry + text.substr(line_start)
		entry = find_entry(text, id)
		created = true
	var inner := text.substr(entry.x + 1, entry.y - entry.x - 1)
	inner = remove_fields(inner, SPRITE_FIELDS)
	inner = inner.rstrip(" \t\n")
	if not inner.ends_with(",") and not inner.ends_with("{"):
		inner = _add_trailing_comma(inner)
	inner += "\n" + block + "\n\t"
	text = text.substr(0, entry.x + 1) + inner + text.substr(entry.y)
	if display_name != "" and not created:
		var at := text.find('"id": "%s", "name": "' % id)
		if at >= 0:
			var start := at + ('"id": "%s", "name": "' % id).length()
			var end := text.find('"', start)
			text = text.substr(0, start) + display_name + text.substr(end)
	return {"text": text, "created": created, "error": ""}


## Comentarios de la base que hablan de sus imágenes (no sirven al luchador nuevo).
static func _drop_sprite_comments(body: String) -> String:
	var out := PackedStringArray()
	for line in body.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("#") and (t.contains("sprites generados") or t.contains("imágenes") \
				or t.contains("Claves posibles") or t.contains("<ataque>") or t.contains("Las que falten") \
				or t.contains("de cuadros que se repite") or t.contains("run_alt") or t.contains("Píxel de cada imagen")):
			continue
		out.append(line)
	return "\n".join(out)


## Se asegura de que el último valor (saltando líneas de comentario) termina en coma.
static func _add_trailing_comma(inner: String) -> String:
	var lines := inner.split("\n")
	for n in range(lines.size() - 1, -1, -1):
		var line := lines[n]
		var code := line
		var comment := ""
		var in_string := false
		for k in line.length():
			if line[k] == '"':
				in_string = not in_string
			elif line[k] == "#" and not in_string:
				code = line.substr(0, k)
				comment = line.substr(k)
				break
		var stripped := code.strip_edges()
		if stripped == "":
			continue
		if not stripped.ends_with(",") and not stripped.ends_with("{"):
			lines[n] = code.rstrip(" \t") + "," + ((" " + comment) if comment != "" else "")
		break
	return "\n".join(lines)


## Añade el estilo de animación del luchador (copia el de la base) si no lo tiene.
static func animations_with_style(text: String, id: String, base := DEFAULT_BASE) -> String:
	var start := text.find("const ANIMATION_STYLES := {")
	if start < 0 or text.find('\t"%s": {' % id, start) >= 0:
		return text
	var close := match_close(text, text.find("{", start))
	var source := base if text.find('\t"%s": {' % base, start) >= 0 else DEFAULT_BASE
	var at := text.find('\t"%s": {' % source, start)
	if at < 0 or at > close:
		# Ni la base ni la de por defecto tienen estilo: se copia el primero que haya.
		at = text.find('\t"', text.find("{", start))
		if at >= 0 and at < close:
			source = text.substr(at + 2, text.find('"', at + 2) - at - 2)
	if at < 0 or at > close:
		return text
	var line_end := text.find("\n", at)
	var line := text.substr(at, line_end - at).replace('"%s":' % source, '"%s":' % id)
	# "like": copia también los tiempos de animación de la base (FighterAnimations.like).
	var close_at := line.rfind("}")
	if close_at > 0 and not line.contains('"like"'):
		line = line.substr(0, close_at) + ', "like": "%s"' % base + line.substr(close_at)
	var line_start := text.rfind("\n", close) + 1
	return text.substr(0, line_start) + line + "\n" + text.substr(line_start)


# --- Configuración guardada ---------------------------------------------------------

static func config_path(id: String) -> String:
	return "%s/%s/%s_import.json" % [FIGHTERS_DIR, id, id]


static func load_config(id: String) -> Dictionary:
	var path := ProjectSettings.globalize_path(config_path(id))
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func save_config(id: String, config: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(config_path(id))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(whole_numbers(config), "  ", false) + "\n")


## JSON lee todos los números como decimales: 3.0 -> 3 para que el archivo se lea bien.
static func whole_numbers(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)) and absf(value) < 1e9:
		return int(value)
	if value is Array:
		var list: Array = []
		for item in value:
			list.append(whole_numbers(item))
		return list
	if value is Dictionary:
		var dict := {}
		for key in value:
			dict[key] = whole_numbers(value[key])
		return dict
	return value


## Ruta absoluta de una hoja: tal cual si es absoluta, si no, relativa al proyecto.
static func resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)


static func is_valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 24:
		return false
	for c in id:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return id[0] >= "a" and id[0] <= "z"


# --- Importación completa ------------------------------------------------------------

## Hace todo: empaqueta, escribe catálogo, estilo de animación y configuración.
## `analysis` es lo que devuelve analyze() (con la hoja ya girada si hacía falta).
## Opciones: name, base, columns, pack_all, write (false = solo enseñar el bloque).
## Devuelve {"ok", "block", "messages": PackedStringArray, "errors": PackedStringArray, ...}.
static func apply(id: String, analysis: Dictionary, normalized: Dictionary, options: Dictionary = {}) -> Dictionary:
	var messages := PackedStringArray()
	var errors := PackedStringArray(normalized["errors"])
	if not is_valid_id(id):
		errors.append("El id \"%s\" no vale: usa minúsculas, números y _, empezando por una letra." % id)
	if not errors.is_empty():
		return {"ok": false, "messages": messages, "errors": errors, "block": ""}
	var sheet_path := "%s/%s/%s_sheet.png" % [FIGHTERS_DIR, id, id]
	var built := build(analysis["image"], analysis["rects"], normalized, sheet_path,
		int(options.get("columns", 8)), bool(options.get("pack_all", false)), analysis)
	if int(built["save_error"]) != OK:
		errors.append("No se pudo guardar la hoja %s." % sheet_path)
		return {"ok": false, "messages": messages, "errors": errors, "block": built["block"]}
	var cell: Vector2i = built["cell"]
	messages.append("Hoja: %s (%d cuadros en celdas de %dx%d)" % [sheet_path, built["frames"], cell.x, cell.y])
	if float(built.get("out_scale", 1.0)) < 0.999:
		messages.append("Cuadros reducidos al %d %% promediando el color y afinados (altura de pie máxima %d px)" % [roundi(float(built["out_scale"]) * 100), OUT_MAX_HEIGHT])
	# Calidad: hoja HD (x4 si cabe) y estabilización de los pies (scripts/tools/calidad_luchador.gd).
	# Con "calidad": 0 en las opciones (o --sin-calidad en la CLI) no se hace.
	if int(options.get("calidad", 4)) > 0:
		var calidad: Script = load("res://scripts/tools/calidad_luchador.gd")
		messages.append("Calidad: " + String(calidad.call("hoja_hd", sheet_path, int(options.get("calidad", 4)))) + ", "
			+ String(calidad.call("estabilizar", {"sprites": built["refs"]}, sheet_path)))
	var result := {"ok": true, "messages": messages, "errors": errors, "block": built["block"], "built": built,
		"created": false}
	if not bool(options.get("write", true)):
		return result
	var base := String(options.get("base", DEFAULT_BASE))
	var catalog_file := ProjectSettings.globalize_path(CATALOG_PATH)
	var catalog_text := FileAccess.get_file_as_string(catalog_file)
	_backup(catalog_file, catalog_text)
	var cat := catalog_with_sprites(catalog_text, id, built["block"], String(options.get("name", "")), base)
	if String(cat["error"]) != "":
		errors.append(cat["error"])
		result["ok"] = false
		return result
	_write(catalog_file, cat["text"])
	result["created"] = cat["created"]
	if cat["created"]:
		messages.append("Luchador nuevo \"%s\" creado en catalog.gd (estadísticas de %s)" % [id, base])
	else:
		messages.append("Sprites de \"%s\" sustituidos en catalog.gd" % id)
	var anim_file := ProjectSettings.globalize_path(ANIMATIONS_PATH)
	var anim_text := FileAccess.get_file_as_string(anim_file)
	var anim_new := animations_with_style(anim_text, id, base)
	if anim_new != anim_text:
		_write(anim_file, anim_new)
		messages.append("Estilo de animación añadido en fighter_animations.gd")
	return result


static func _backup(path: String, text: String) -> void:
	var dir := ProjectSettings.globalize_path(OUT_DIR).path_join("respaldo")
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file := FileAccess.open(dir.path_join("%s.%s.bak" % [path.get_file(), stamp]), FileAccess.WRITE)
	if file != null:
		file.store_string(text)


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)


# --- Vistas previas -----------------------------------------------------------------

static func draw_text(img: Image, text: String, at: Vector2i, color: Color, scale := 1, back := Color.BLACK) -> void:
	text = text.to_upper()
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	if back.a > 0.0:
		var box := Rect2i(at - Vector2i(scale, scale), Vector2i((text.length() * 4 + 1) * scale, 7 * scale))
		img.fill_rect(box.intersection(bounds), back)
	for c in text.length():
		var bits: String = FONT.get(text[c], FONT[" "])
		for b in 15:
			if bits[b] != "1":
				continue
			var p := at + Vector2i((c * 4 + b % 3) * scale, (b / 3) * scale)
			var r := Rect2i(p, Vector2i(scale, scale)).intersection(bounds)
			if r.has_area():
				img.fill_rect(r, color)


## Hoja original limpia con cada cuadro enmarcado y numerado. Los repetidos salen en
## gris con "=N" (copia) o "<N" (reflejo de N); los usados por el mapa, en verde.
static func preview(image: Image, rects: Array[Rect2i], duplicates: Dictionary = {}, used: Array[int] = [],
		zoom := 2) -> Image:
	var out := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.16, 0.16, 0.2))
	out.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	out.resize(image.get_width() * zoom, image.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	for i in rects.size():
		var r := Rect2i(rects[i].position * zoom, rects[i].size * zoom).grow(1).intersection(Rect2i(Vector2i.ZERO, out.get_size()))
		var color := Color(1, 0.25, 0.3)
		var label := str(i)
		if used.has(i):
			color = Color(0.3, 1, 0.4)
		elif duplicates.has(i):
			color = Color(0.5, 0.5, 0.6)
			label += ("~" if duplicates[i].get("recolor", false) else ("<" if duplicates[i]["mirror"] else "=")) + str(duplicates[i]["of"])
		_frame(out, r, color)
		draw_text(out, label, r.position + Vector2i(2, 2), Color.YELLOW if not duplicates.has(i) else Color(0.8, 0.8, 0.85))
	return out


static func _frame(img: Image, r: Rect2i, color: Color) -> void:
	img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 1), color)
	img.fill_rect(Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), color)
	img.fill_rect(Rect2i(r.position.x, r.position.y, 1, r.size.y), color)
	img.fill_rect(Rect2i(r.end.x - 1, r.position.y, 1, r.size.y), color)


## Una fila por pose: su nombre y sus cuadros tal como quedan en la hoja empaquetada,
## con la línea del suelo, para comprobar que todo encaja antes de abrir el juego.
static func poses_sheet(built: Dictionary, normalized: Dictionary, zoom := 2) -> Image:
	var poses: Dictionary = normalized["poses"]
	var sheet: Image = built["sheet"]
	var cell: Vector2i = built["cell"]
	var cols: int = built["columns"]
	var slot: Dictionary = built["slot"]
	var label_w := 80
	var most := 1
	for key in poses:
		most = maxi(most, (poses[key] as Array).size())
	var size := Vector2i(label_w + most * cell.x * zoom, poses.size() * (cell.y * zoom + 6))
	var out := Image.create_empty(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.13, 0.14, 0.19))
	var row := 0
	for key in poses:
		var y := row * (cell.y * zoom + 6)
		if row % 2 == 1:
			out.fill_rect(Rect2i(0, y, size.x, cell.y * zoom + 6), Color(0.16, 0.17, 0.23))
		draw_text(out, key, Vector2i(4, y + 6), Color(1, 0.85, 0.3), 1, Color(0, 0, 0, 0))
		var frames: Array = poses[key]
		draw_text(out, "%d CUADRO%s" % [frames.size(), "S" if frames.size() != 1 else ""], Vector2i(4, y + 16),
			Color(0.6, 0.65, 0.75), 1, Color(0, 0, 0, 0))
		for k in frames.size():
			var src := SpriteSheet.grid_rect(cell, cols, slot[frames[k]])
			var sub := sheet.get_region(src)
			sub.resize(cell.x * zoom, cell.y * zoom, Image.INTERPOLATE_NEAREST)
			var pos := Vector2i(label_w + k * cell.x * zoom, y + 3)
			out.fill_rect(Rect2i(pos.x, pos.y + cell.y * zoom - 1, cell.x * zoom, 1), Color(0.35, 0.4, 0.5))
			out.blend_rect(sub, Rect2i(Vector2i.ZERO, sub.get_size()), pos)
			draw_text(out, str(frames[k]), pos + Vector2i(2, 2), Color(0.7, 0.75, 0.85), 1, Color(0, 0, 0, 0))
		row += 1
	return out
