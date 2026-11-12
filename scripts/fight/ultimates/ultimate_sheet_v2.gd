extends RefCounted
## Plan de la hoja v2 del definitivo de Madara Edo (≈30 s, atlas + manifiesto de
## tools/slice_definitivo_v2.gd, fondo negro). Cada fase va a una capa:
##   madara    sprite sólido con sus pies (sin el aura pintada): preparación, final
##   aura      el aura de esos cuadros, en modo luz detrás de Madara
##   susanoo   modo luz (aditivo) detrás de Madara: manifestación, perfecto, ataque, desvanecimiento
##   plano     plano de cine (franja): la carcajada (primeros planos) y el Rinnegan con sangre
## Los tiempos siguen los de la hoja del usuario.

const MANIFIESTO := "res://assets/fighters/madara_edo/definitivo_v2/madara_edo_definitivo_v2.json"
const DURACION := 30.0

## [capa, fase, inicio, fin]
const PLAN := [
	["madara", "preparacion", 0.0, 3.0],
	["madara", "quieto:preparacion:-1", 3.0, 28.5],
	["susanoo", "manifestacion", 3.0, 8.0],
	["susanoo", "perfecto", 8.0, 10.5],
	["susanoo", "ataque", 10.5, 13.5],
	["susanoo", "desvanecimiento", 13.5, 15.0],
	["plano", "risa", 15.0, 17.0],
	["plano", "rinnegan", 17.0, 18.4],
	["plano", "invocacion", 18.4, 19.5],
	["madara", "final", 28.5, 30.0],
]
## Los meteoritos, impactos y onda usan el meteorito de lava, la explosión, el humo y los
## escombros sueltos de la hoja anterior (efectos/), que lucen mejor a ese tamaño:
## [aparecen, cae el primero, cae el segundo].
const CAIDA := [19.5, 24.0, 24.8]
## Golpes (CombatSim.ultimate_hit): el tajo del Susanoo y la caída de cada meteorito.
const GOLPES := {"susanoo": 12.6, "meteoro1": 24.0, "meteoro2": 24.8}
## La segunda roca cae un poco después (y su impacto también).
const RETRASO_SEGUNDO := 0.8


static func leer_manifiesto() -> Dictionary:
	if not FileAccess.file_exists(MANIFIESTO):
		return {}
	var datos: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFIESTO))
	if not (datos is Dictionary):
		return {}
	var m: Dictionary = datos
	if not m.has("fases") or not ResourceLoader.exists(String(m.get("atlas", ""))):
		return {}
	return m


static func _id(fases: Dictionary, fase: String, i: int) -> int:
	var lista: Array = fases.get(fase, [])
	if lista.is_empty():
		return -1
	if i < 0:
		i += lista.size()
	return int(lista[clampi(i, 0, lista.size() - 1)])


## Cuadro de una capa en el segundo t (-1 si la capa no se ve). desfase retrasa la capa
## (la segunda roca usa las mismas fases un poco más tarde).
static func cuadro(fases: Dictionary, capa: String, t: float, desfase := 0.0) -> int:
	var tt := t - desfase
	for paso in PLAN:
		if String(paso[0]) != capa:
			continue
		var a := float(paso[2])
		var b := float(paso[3])
		if tt < a or tt >= b:
			continue
		var fase := String(paso[1])
		if fase.begins_with("quieto:"):
			var partes := fase.split(":")
			return _id(fases, partes[1], int(partes[2]))
		var n := (fases.get(fase, []) as Array).size()
		return _id(fases, fase, int(clampf((tt - a) / (b - a), 0.0, 0.9999) * n))
	return -1


## Avance (0-1) dentro de la fase de una capa, o -1 si no está activa.
static func avance(capa: String, t: float, desfase := 0.0) -> float:
	var tt := t - desfase
	for paso in PLAN:
		if String(paso[0]) == capa and tt >= float(paso[2]) and tt < float(paso[3]):
			return (tt - float(paso[2])) / (float(paso[3]) - float(paso[2]))
	return -1.0


static func fase_de(capa: String, t: float) -> String:
	for paso in PLAN:
		if String(paso[0]) == capa and t >= float(paso[2]) and t < float(paso[3]):
			return String(paso[1])
	return ""
