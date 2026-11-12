extends SceneTree
## Recorta la hoja v2 del definitivo de Madara Edo (fuentes/madara_edo_definitivo_v2.png,
## fondo negro, 13 filas x 40 cuadros) según fuentes/mapa_madara_edo_definitivo_v2.json.
## Ejecutar: godot --headless --path . -s res://tools/slice_definitivo_v2.gd
##
## Modos por fila:
##   solido  Madara: se quita el fondo negro (relleno desde los bordes, borde suave) y se
##           alinean los pies de todos los cuadros.
##   luz     Susanoo, aparición de meteoritos, onda: se guardan tal cual; el juego los dibuja
##           con mezcla aditiva y el negro desaparece solo.
##   escena  Descenso e impactos: se quita el negro conectado al borde (quedan rocas y fuego).
##   ojo     Rinnegan en primer plano: opaco, tal cual.
## Salida: assets/fighters/madara_edo/definitivo_v2/ (atlas, manifiesto, retrato, logo) y
## una vista previa en tools/out/madara_edo_definitivo_v2_preview.png.

const MAPA := "res://fuentes/mapa_madara_edo_definitivo_v2.json"
const OUT := "res://assets/fighters/madara_edo/definitivo_v2/"
const NEGRO := 0.07       ## por debajo: fondo seguro
const SUAVE := 0.16       ## hasta aquí, si toca el fondo: transparente a medias
const TITULO_X := 345     ## el título de cada fila ocupa la parte izquierda de arriba
const COLUMNAS := 20
const ANCHO_VENTANA := 1.7  ## la ventana de recorte es más ancha que el paso (las auras se solapan)


func _initialize() -> void:
	var mapa: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAPA))
	var hoja := Image.load_from_file(ProjectSettings.globalize_path(String(mapa["fuente"])))
	hoja.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# 1) Recortar y limpiar cada cuadro; medir los pies de Madara.
	var cuadros: Array = []   # {fase, i, modo, img, pies: Vector2i}
	for fila in mapa["filas"]:
		var modo := String(fila["modo"])
		var celdas: Array = fila["celdas"]
		var pies_y: Array = []
		var lote: Array = []
		for i in celdas.size():
			var r: Array = celdas[i]
			var paso := float(r[2])
			# Centro real del dibujo: cerca del número, donde está el cuerpo de Madara
			# (armadura roja) o, en las filas sin él, lo más brillante.
			var cx := _centrar(hoja, int(r[0]) + int(r[2]) / 2, int(r[1]), int(r[3]), modo)
			var ancho := int(paso * ANCHO_VENTANA)
			var rect := Rect2i(cx - ancho / 2, int(r[1]), ancho, int(r[3]))
			# Las primeras celdas tocan el título y la descripción de la fila.
			if rect.position.x < TITULO_X:
				var recorte := 14 if String(fila["fase"]) != "preparacion" else 20
				rect = Rect2i(rect.position.x, rect.position.y + recorte, rect.size.x, rect.size.y - recorte)
			var img := hoja.get_region(rect)
			if modo == "solido" or modo == "escena":
				_quitar_fondo(img)
			if modo != "ojo":
				_solo_el_centro(img, modo)
			var pies := _pies(img) if modo in ["solido", "luz"] else Vector2i(img.get_width() / 2, img.get_height() - 1)
			# El recorte de arriba desplaza el cuadro: los pies se miden en coordenadas de la fila.
			pies.y += rect.position.y - int(r[1])
			pies_y.append(pies.y)
			lote.append({"fase": String(fila["fase"]), "i": i, "modo": modo, "img": img,
				"pies": pies, "desfase": rect.position.y - int(r[1])})
		# Suela común por fila (mediana): evita saltos de uno o dos píxeles.
		pies_y.sort()
		var suela: int = pies_y[pies_y.size() / 2]
		for c in lote:
			c["pies"] = Vector2i((c["pies"] as Vector2i).x, suela)
			cuadros.append(c)

	# 2) Celda común: todos los cuadros con sus pies en el mismo punto (ancla).
	var izq := 0
	var der := 0
	var arriba := 0
	var abajo := 0
	for c in cuadros:
		var img: Image = c["img"]
		var p: Vector2i = c["pies"]
		var desfase: int = c["desfase"]
		izq = maxi(izq, p.x)
		der = maxi(der, img.get_width() - p.x)
		arriba = maxi(arriba, p.y - desfase)
		abajo = maxi(abajo, img.get_height() + desfase - p.y)
	var celda := Vector2i(izq + der + 2, arriba + abajo + 2)
	var ancla := Vector2i(izq + 1, arriba + 1)
	var filas_atlas := int(ceil(cuadros.size() / float(COLUMNAS)))
	var atlas := Image.create(celda.x * COLUMNAS, celda.y * filas_atlas, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var lista: Array = []
	var fases := {}
	var modos := {}
	for n in cuadros.size():
		var c: Dictionary = cuadros[n]
		var img: Image = c["img"]
		var origen := Vector2i((n % COLUMNAS) * celda.x, (n / COLUMNAS) * celda.y)
		var p: Vector2i = c["pies"]
		var desfase: int = c["desfase"]
		var destino := origen + ancla - Vector2i(p.x, p.y - desfase)
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), destino)
		lista.append({"fase": c["fase"], "i": c["i"], "rect": [origen.x, origen.y, celda.x, celda.y]})
		if not fases.has(c["fase"]):
			fases[c["fase"]] = []
		fases[c["fase"]].append(n)
		modos[c["fase"]] = c["modo"]
	atlas.save_png(ProjectSettings.globalize_path(OUT + "madara_edo_definitivo_v2.png"))

	# 3) Retrato y logo (opacos).
	for clave in ["retrato", "logo"]:
		var r2: Array = mapa[clave]
		hoja.get_region(Rect2i(int(r2[0]), int(r2[1]), int(r2[2]), int(r2[3]))).save_png(ProjectSettings.globalize_path(OUT + clave + ".png"))

	# 4) Altura de Madara de pie (preparación) y manifiesto.
	var alturas: Array = []
	for c in cuadros:
		if c["fase"] == "preparacion":
			var usado := (c["img"] as Image).get_used_rect()
			alturas.append((c["pies"] as Vector2i).y - int(c["desfase"]) - usado.position.y)
	alturas.sort()
	var manifiesto := {
		"atlas": OUT + "madara_edo_definitivo_v2.png", "celda": [celda.x, celda.y], "columnas": COLUMNAS,
		"ancla": [ancla.x, ancla.y], "alto_figura": alturas[alturas.size() / 2], "mira": "derecha",
		"fases": fases, "modos": modos, "cuadros": lista,
		"retrato": OUT + "retrato.png", "logo": OUT + "logo.png",
	}
	var f := FileAccess.open(OUT + "madara_edo_definitivo_v2.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifiesto, "\t"))
	f.close()
	_vista_previa(atlas, celda, ancla, cuadros.size())
	print("cuadros=%d celda=%s ancla=%s alto_figura=%s" % [cuadros.size(), celda, ancla, manifiesto["alto_figura"]])
	quit()


## Centro del dibujo cerca de x0 (±12 px): centroide de la armadura roja de Madara o,
## si no hay, de los píxeles brillantes.
func _centrar(hoja: Image, x0: int, y0: int, alto: int, modo: String) -> int:
	if modo == "ojo":
		return x0
	var suma := 0.0
	var peso := 0.0
	var rojo := modo in ["solido", "luz"]
	for pasada in range(2):
		for x in range(x0 - 12, x0 + 13):
			for y in range(y0, y0 + alto):
				var c := hoja.get_pixel(clampi(x, 0, hoja.get_width() - 1), y)
				var w := 0.0
				if rojo and pasada == 0:
					w = 1.0 if (c.r > 0.45 and c.g < 0.3 and c.b < 0.35 and c.r > c.b * 1.4) else 0.0
				elif pasada == 1:
					w = maxf(c.v - 0.35, 0.0)
				suma += x * w
				peso += w
		if peso > 3.0:
			return int(round(suma / peso))
		suma = 0.0
		peso = 0.0
	return x0


## Deja solo lo conectado a la franja central (borra trozos de los cuadros vecinos).
func _solo_el_centro(img: Image, modo: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var luz := modo == "luz"
	var lleno := func(c: Color) -> bool: return (c.v > 0.09) if luz else (c.a > 0.05)
	var marca := PackedByteArray()
	marca.resize(w * h)
	var pila: Array[Vector2i] = []
	for y in h:
		for x in range(w / 2 - 3, w / 2 + 4):
			pila.append(Vector2i(x, y))
	while not pila.is_empty():
		var p: Vector2i = pila.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var k := p.y * w + p.x
		if marca[k] == 1:
			continue
		if not lleno.call(img.get_pixelv(p)):
			continue
		marca[k] = 1
		pila.append(p + Vector2i.RIGHT)
		pila.append(p + Vector2i.LEFT)
		pila.append(p + Vector2i.DOWN)
		pila.append(p + Vector2i.UP)
	for y in h:
		for x in w:
			if marca[y * w + x] == 0:
				img.set_pixel(x, y, Color(0, 0, 0, 0) if not luz else Color(0, 0, 0, 1))


## Fondo negro fuera: relleno desde los bordes sobre los píxeles oscuros; los que tocan el
## fondo pero tienen algo de luz (halo del aura, humo) quedan medio transparentes.
func _quitar_fondo(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var visto := PackedByteArray()
	visto.resize(w * h)
	var pila: Array[Vector2i] = []
	for x in w:
		pila.append(Vector2i(x, 0))
		pila.append(Vector2i(x, h - 1))
	for y in h:
		pila.append(Vector2i(0, y))
		pila.append(Vector2i(w - 1, y))
	while not pila.is_empty():
		var p: Vector2i = pila.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var k := p.y * w + p.x
		if visto[k] == 1:
			continue
		var c := img.get_pixelv(p)
		if c.v >= SUAVE:
			continue
		visto[k] = 1
		var a := clampf((c.v - NEGRO) / (SUAVE - NEGRO), 0.0, 1.0)
		img.set_pixelv(p, Color(c.r, c.g, c.b, a * a))
		pila.append(p + Vector2i.RIGHT)
		pila.append(p + Vector2i.LEFT)
		pila.append(p + Vector2i.DOWN)
		pila.append(p + Vector2i.UP)


## Pies de Madara: x = mediana de la armadura roja; y = fila más baja con píxeles del
## cuerpo cerca de ese centro (ni negro ni aura muy saturada de morado/azul).
func _pies(img: Image) -> Vector2i:
	var xs: Array = []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.45 and c.g < 0.3 and c.b < 0.35 and c.r > c.b * 1.4:
				xs.append(x)
	var cx := img.get_width() / 2
	if not xs.is_empty():
		xs.sort()
		cx = int(xs[xs.size() / 2])
	var suela := img.get_height() - 1
	for y in range(img.get_height() - 1, -1, -1):
		var cuerpo := 0
		for x in range(maxi(cx - 8, 0), mini(cx + 9, img.get_width())):
			var c := img.get_pixel(x, y)
			if c.a > 0.6 and c.v > 0.1 and not (c.b > c.r * 1.3 and c.v > 0.5):
				cuerpo += 1
		if cuerpo >= 3:
			suela = y
			break
	return Vector2i(cx, suela)


func _vista_previa(atlas: Image, celda: Vector2i, ancla: Vector2i, total: int) -> void:
	var prev := Image.create(atlas.get_width(), atlas.get_height(), false, Image.FORMAT_RGBA8)
	prev.fill(Color(0.42, 0.42, 0.44))
	prev.blend_rect(atlas, Rect2i(Vector2i.ZERO, atlas.get_size()), Vector2i.ZERO)
	for n in total:
		var o := Vector2i((n % COLUMNAS) * celda.x, (n / COLUMNAS) * celda.y) + ancla
		for d in range(-2, 3):
			prev.set_pixelv(o + Vector2i(d, 0), Color.GREEN)
			prev.set_pixelv(o + Vector2i(0, d), Color.GREEN)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/out"))
	prev.save_png(ProjectSettings.globalize_path("res://tools/out/madara_edo_definitivo_v2_preview.png"))
