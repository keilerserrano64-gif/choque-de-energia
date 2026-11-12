extends RefCounted
## Plan de la hoja del definitivo de Madara Edo (atlas + manifiesto de
## tools/slice_ultimate_sheet.gd y los efectos sueltos de tools/slice_ultimate_effects.gd).
## Tres capas:
##   - Madara en el escenario (sprite sólido con sus pies): preparación, carcajada,
##     invocación y final; mientras está el Susanoo, un cuadro quieto de la preparación.
##   - Susanoo en el escenario en «modo luz» (mezcla aditiva detrás de Madara): sus cuadros
##     traen el fondo de la celda pintado y así no se ve el recuadro.
##   - Planos de cine en una franja: solo los paneles de escena (meteoritos e impactos).
## Sin manifiesto, madara_ultimate.gd usa el Susanoo y los meteoritos dibujados con código.

const MANIFIESTO := "res://assets/fighters/madara_edo/definitivo/madara_edo_definitivo.json"
const EFECTOS := "res://assets/fighters/madara_edo/definitivo/efectos/efectos.json"

## Madara sólido: [fase, inicio, fin]. "quieto:<fase>:<i>" = un cuadro fijo.
const PLAN_MUNDO := [
	["preparacion", 0.0, 2.0], ["quieto:preparacion:0", 2.0, 10.0], ["risa", 10.0, 13.0],
	["invocacion", 13.0, 16.0], ["quieto:invocacion:-1", 16.0, 24.45], ["final", 24.45, 26.6],
]
## Susanoo en modo luz: [fase, inicio, fin]. El tajo tiene su propio reparto.
const PLAN_LUZ := [["susanoo", 2.0, 6.0], ["tajo", 6.0, 11.6]]
## El Susanoo se desvanece detrás de Madara mientras se ríe.
const LUZ_FUNDIDO := [10.0, 11.6]
## Planos de cine: [fase, atlas, inicio, fin].
const PLAN_PLANOS := [
	["meteoro1", "escenas", 16.0, 19.0], ["meteoro2", "escenas", 19.0, 21.0], ["impactos", "escenas", 23.0, 24.45],
]
## En el tajo: cuadros de alzar y bajar hasta el arco (7,9 s), el arco hasta 8,6 s y
## después la espada abajo.
const TAJO_ARCO := [7.9, 8.6]
## La fila de la carcajada está dibujada más de cerca que la de la preparación.
const ESCALA_FASE := {"risa": 0.72}


static func leer_manifiesto() -> Dictionary:
	if not FileAccess.file_exists(MANIFIESTO):
		return {}
	var datos: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFIESTO))
	if not (datos is Dictionary):
		return {}
	var m: Dictionary = datos
	var p: Variant = m.get("personaje")
	if not (p is Dictionary) or not ResourceLoader.exists(String((p as Dictionary).get("atlas", ""))):
		return {}
	return m


## Texturas de los efectos sueltos: {nombre: {tex, ancla}} (vacío si no están).
static func leer_efectos() -> Dictionary:
	if not FileAccess.file_exists(EFECTOS):
		return {}
	var datos: Variant = JSON.parse_string(FileAccess.get_file_as_string(EFECTOS))
	if not (datos is Dictionary):
		return {}
	var salida := {}
	for nombre in (datos as Dictionary):
		var e: Variant = datos[nombre]
		if e is Dictionary and ResourceLoader.exists(String((e as Dictionary).get("png", ""))):
			var tex := load(String(e["png"])) as Texture2D
			if tex:
				var anc: Array = (e as Dictionary).get("ancla", [tex.get_width() * 0.5, tex.get_height() * 0.5])
				salida[String(nombre)] = {"tex": tex, "ancla": Vector2(float(anc[0]), float(anc[1]))}
	return salida


static func _id(fases: Dictionary, fase: String, i: int) -> int:
	var lista: Array = fases.get(fase, [])
	if lista.is_empty():
		return -1
	if i < 0:
		i = lista.size() + i
	return int(lista[clampi(i, 0, lista.size() - 1)])


static func _paso(fases: Dictionary, fase: String, a: float, b: float, t: float) -> int:
	if fase.begins_with("quieto:"):
		var partes := fase.split(":")
		return _id(fases, partes[1], int(partes[2]))
	var n := (fases.get(fase, []) as Array).size()
	if n <= 0:
		return -1
	if fase == "tajo":
		if t >= float(TAJO_ARCO[1]):
			return _id(fases, fase, maxi(n - 2, 0))
		if t >= float(TAJO_ARCO[0]):
			return _id(fases, fase, n - 1)
		var k := clampf((t - a) / (float(TAJO_ARCO[0]) - a), 0.0, 0.9999)
		return _id(fases, fase, int(k * maxf(n - 1, 1)))
	return _id(fases, fase, int(clampf((t - a) / (b - a), 0.0, 0.9999) * n))


static func _en_plan(plan: Array, fases: Dictionary, t: float) -> int:
	for paso in plan:
		if t >= float(paso[1]) and t < float(paso[2]):
			return _paso(fases, String(paso[0]), float(paso[1]), float(paso[2]), t)
	return -1


## Cuadro de Madara (sólido) en el escenario en el segundo t, o -1.
static func cuadro_personaje(fases: Dictionary, t: float) -> int:
	return _en_plan(PLAN_MUNDO, fases, t)


## Cuadro del Susanoo (modo luz) en el segundo t, o -1.
static func cuadro_luz(fases: Dictionary, t: float) -> int:
	return _en_plan(PLAN_LUZ, fases, t)


## Alfa del Susanoo: aparece de golpe y se desvanece durante la carcajada.
static func alfa_luz(t: float) -> float:
	return 1.0 - clampf((t - float(LUZ_FUNDIDO[0])) / (float(LUZ_FUNDIDO[1]) - float(LUZ_FUNDIDO[0])), 0.0, 1.0)


static func fase_mundo(t: float) -> String:
	for paso in PLAN_MUNDO:
		if t >= float(paso[1]) and t < float(paso[2]):
			return String(paso[0])
	return ""


## Plano de cine del segundo t: [atlas ("escenas" | ""), índice, alfa].
static func plano(manifiesto: Dictionary, t: float) -> Array:
	for paso in PLAN_PLANOS:
		var a := float(paso[2])
		var b := float(paso[3])
		if t < a or t >= b:
			continue
		var tipo := String(paso[1])
		var fases: Dictionary = (manifiesto.get(tipo, {}) as Dictionary).get("fases", {})
		var i := _paso(fases, String(paso[0]), a, b, t)
		if i < 0:
			continue
		var alfa := clampf(minf((t - a) / 0.06, (b - t) / 0.1), 0.0, 1.0)
		return [tipo, i, alfa]
	return ["", -1, 0.0]


## Recuadro del contenido visible de cada cuadro (para los planos de cine).
static func recortar_a_contenido(atlas: Texture2D, cuadros: Array) -> Array:
	var img := atlas.get_image() if atlas else null
	if img == null:
		return cuadros
	if img.is_compressed():
		img.decompress()
	var salida: Array = []
	for c in cuadros:
		var r: Array = (c as Dictionary)["rect"]
		var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		var usado := img.get_region(rect).get_used_rect()
		var nuevo := (c as Dictionary).duplicate()
		if usado.size.x > 0 and usado.size.y > 0:
			nuevo["rect"] = [rect.position.x + usado.position.x, rect.position.y + usado.position.y, usado.size.x, usado.size.y]
		salida.append(nuevo)
	return salida
