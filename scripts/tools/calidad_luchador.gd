extends RefCounted
## Calidad de los luchadores con imágenes (lo usan tools/subir_calidad.gd, el importador y
## FighterPainter):
##   hoja_hd()     <id>_sheet_hd.png ampliada x2 o x4 con un escalador de pixel art (Scale2x
##                 con tolerancia: redondea las escaleras de las diagonales sin emborronar).
##                 FighterPainter la dibuja en el mismo sitio y tamaño que la normal.
##   estabilizar() <id>_sheet_ajustes.json: desplazamiento por cuadro para que los pies no
##                 «bailen» en reposo, caminar, guardia, carga, intro y victoria.
## Para volver atrás basta con borrar los archivos _hd.png / _hd.json / _ajustes.json.

const Importer := preload("res://scripts/tools/fighter_importer.gd")
## Animaciones en las que los pies deben quedarse quietos de un cuadro a otro.
const ESTABLES := ["idle", "stance", "walk", "block", "charge", "victory", "intro"]
## Diferencia máxima (suma RGBA, 0-1020) para considerar dos píxeles «del mismo color».
const TOLERANCIA := 60
## Lado máximo de la hoja HD.
const LADO_MAXIMO := 8192


## Hoja HD y estabilización de un luchador. Devuelve un resumen.
static func subir(d: Dictionary, factor := 4) -> String:
	var id := String(d.get("id", ""))
	var hoja := "res://assets/fighters/%s/%s_sheet.png" % [id, id]
	if not FileAccess.file_exists(hoja):
		return id + ": sin hoja"
	return "%s: %s, %s" % [id, hoja_hd(hoja, factor), estabilizar(d, hoja)]


# ================================================================ Hoja HD

static func hoja_hd(hoja: String, factor_pedido := 4) -> String:
	var img := Image.load_from_file(ProjectSettings.globalize_path(hoja))
	img.convert(Image.FORMAT_RGBA8)
	var factor := 4 if factor_pedido >= 4 else 2
	while factor > 2 and maxi(img.get_width(), img.get_height()) * factor > LADO_MAXIMO:
		factor /= 2
	var hd := escalar_2x(img)
	if factor == 4:
		hd = escalar_2x(hd)
	Importer.pulir_hoja(hd, true)
	var base := hoja.get_basename()
	hd.save_png(ProjectSettings.globalize_path(base + "_hd.png"))
	var f := FileAccess.open(base + "_hd.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"factor": factor, "origen": hoja.get_file()}, "\t"))
	f.close()
	return "HD x%d (%dx%d)" % [factor, hd.get_width(), hd.get_height()]


static func _igual(d: PackedByteArray, i: int, j: int) -> bool:
	return absi(d[i] - d[j]) + absi(d[i + 1] - d[j + 1]) + absi(d[i + 2] - d[j + 2]) + absi(d[i + 3] - d[j + 3]) <= TOLERANCIA


## Scale2x / EPX con tolerancia: cada píxel se parte en cuatro y cada cuarto toma el color
## del vecino solo si dos vecinos contiguos coinciden (una diagonal): las escaleras se
## redondean y los bordes rectos y los detalles de un píxel se respetan.
static func escalar_2x(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var o := PackedByteArray()
	o.resize(w * h * 16)
	var w2 := w * 2
	for y in h:
		for x in w:
			var p := (y * w + x) * 4
			var a := (maxi(y - 1, 0) * w + x) * 4     # arriba
			var b := (y * w + mini(x + 1, w - 1)) * 4  # derecha
			var c := (y * w + maxi(x - 1, 0)) * 4     # izquierda
			var dd := (mini(y + 1, h - 1) * w + x) * 4 # abajo
			var e0 := p
			var e1 := p
			var e2 := p
			var e3 := p
			var ca := _igual(d, c, a)
			var ab := _igual(d, a, b)
			var dc := _igual(d, dd, c)
			var bd := _igual(d, b, dd)
			if ca and not dc and not ab:
				e0 = a
			if ab and not ca and not bd:
				e1 = b
			if dc and not bd and not ca:
				e2 = c
			if bd and not ab and not dc:
				e3 = dd
			var q := ((y * 2) * w2 + x * 2) * 4
			for k in 4:
				o[q + k] = d[e0 + k]
				o[q + 4 + k] = d[e1 + k]
				o[q + w2 * 4 + k] = d[e2 + k]
				o[q + w2 * 4 + 4 + k] = d[e3 + k]
	return Image.create_from_data(w2, h * 2, false, Image.FORMAT_RGBA8, o)


# ================================================================ Estabilización

static func estabilizar(d: Dictionary, hoja: String) -> String:
	var img := Image.load_from_file(ProjectSettings.globalize_path(hoja))
	img.convert(Image.FORMAT_RGBA8)
	var sprites: Dictionary = d.get("sprites", {})
	var desfases := {}
	var movidos := 0
	for clave in ESTABLES:
		var v: Variant = sprites.get(clave)
		var lista: Array = v if v is Array else ([v] if v is String else [])
		if lista.size() < 2:
			continue
		var pies := {}
		for ref in lista:
			var r := _rect(String(ref), hoja)
			if r.has_area():
				pies[String(ref)] = _pies(img, r)
		if pies.size() < 2:
			continue
		# Referencia: la mediana de la animación (no se mueve el conjunto, solo los saltos).
		var xs: Array = []
		var ys: Array = []
		for ref in pies:
			xs.append((pies[ref] as Vector2).x)
			ys.append((pies[ref] as Vector2).y)
		xs.sort()
		ys.sort()
		var mx: float = xs[xs.size() / 2]
		var my: float = ys[ys.size() / 2]
		for ref in pies:
			var p: Vector2 = pies[ref]
			var dx := roundf(mx - p.x)
			var dy := roundf(my - p.y)
			# Solo saltos pequeños: uno grande suele ser parte del movimiento, no un error.
			if absf(dx) > 6.0:
				dx = 0.0
			if absf(dy) > 4.0:
				dy = 0.0
			if dx != 0.0 or dy != 0.0:
				var celda := String(ref).get_slice("#", 1)
				desfases[celda] = [dx, dy]
				movidos += 1
	var base := hoja.get_basename()
	var f := FileAccess.open(base + "_ajustes.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"desfases": desfases}, "\t"))
	f.close()
	return "estabilizados %d cuadros" % movidos


static func _rect(ref: String, hoja: String) -> Rect2i:
	if not ref.begins_with(hoja + "#"):
		return Rect2i()
	var p := ref.get_slice("#", 1).split(",")
	return Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])) if p.size() == 4 else Rect2i()


## Pies: x = centro de los píxeles opacos de las filas más bajas; y = fila más baja opaca.
static func _pies(img: Image, r: Rect2i) -> Vector2:
	var abajo := -1
	for y in range(r.end.y - 1, r.position.y - 1, -1):
		for x in range(r.position.x, r.end.x):
			if img.get_pixel(x, y).a > 0.5:
				abajo = y
				break
		if abajo >= 0:
			break
	if abajo < 0:
		return Vector2(r.size.x * 0.5, r.size.y)
	var suma := 0.0
	var n := 0
	for y in range(maxi(abajo - 5, r.position.y), abajo + 1):
		for x in range(r.position.x, r.end.x):
			if img.get_pixel(x, y).a > 0.5:
				suma += x
				n += 1
	return Vector2((suma / maxi(n, 1)) - r.position.x, abajo - r.position.y)
