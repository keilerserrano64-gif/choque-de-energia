@tool
extends RefCounted
## AutoAnim 2D: animaciones automáticas para sprites 2D (versión 2D del addon AutoAnim).
##
## Una animación es una lista de claves {t, desp, escala, rot, color}:
##   t      momento de 0 a 1 dentro de la duración
##   desp   desplazamiento en píxeles de la imagen; +X = hacia delante, -Y = arriba
##   escala multiplicador (1, 1 = tamaño normal)
##   rot    grados; positivo = inclinarse hacia delante
##   color  tinte que multiplica al sprite (blanco = sin cambio; > 1 = destello)
##   curva  cómo se llega a esta clave desde la anterior (ver CURVAS; "suave" por defecto)
##
## Lo guardado por acción (ver config): {estilo, duracion, intensidad} y, opcionales,
##   variacion  0..1: cada vez sale un poco distinta (intensidad ±35 %, duración ±15 %)
##   capa       {estilo, intensidad}: segundo estilo que se suma encima (p. ej. golpe_seco + sacudida)
##
## La usan:
##   - AnimadorProcedural (en el juego): si un luchador tiene animaciones AutoAnim
##     guardadas en assets/fighters/<id>/<id>_autoanim.tres, las usa en vez de sus
##     movimientos fijos para esa acción.
##   - El panel del editor (addons/auto_anim): pestañas Personaje, Efectos y Escenario.
##
## Sin class_name a propósito: se carga con preload para que funcione aunque el editor
## todavía no haya registrado la clase (pasa al lanzar Godot solo con la terminal).

const ConfigScript := preload("res://scripts/data/auto_anim_config.gd")

## Acciones del luchador que se pueden animar (evento de CombatSim -> nombre visible).
const ACCIONES := {
	"golpe": "Puñetazo",
	"patada": "Patada",
	"golpe_recibido": "Recibir golpe",
	"bloqueo": "Bloquear",
	"salto": "Saltar (despegue)",
	"aterrizaje": "Aterrizar",
	"dash": "Dash / teletransporte",
	"especial": "Técnica (K)",
	"victoria": "Victoria",
	"barrida": "Barrida (↓+J)",
	"antiaereo": "Antiaéreo (↓+I)",
	"aereo": "Ataque aéreo",
	"agarre": "Agarre (→+L)",
	"derribo": "Derribado",
}

## Si una acción no tiene animación propia, prueba con esta otra antes de usar el
## movimiento fijo del juego (así una barrida usa la patada que ya configuraste).
const RESPALDO := {
	"barrida": "patada",
	"antiaereo": "golpe",
	"aereo": "patada",
	"agarre": "golpe",
	"derribo": "golpe_recibido",
}

## Estilos y su duración recomendada en segundos.
const DURACIONES := {
	"golpe_seco": 0.32,
	"golpe_pesado": 0.42,
	"patada_alta": 0.38,
	"embestida": 0.4,
	"retroceso": 0.36,
	"sacudida": 0.3,
	"guardia": 0.3,
	"inclinarse": 0.4,
	"salto_elastico": 0.34,
	"aterrizaje_pesado": 0.28,
	"brinco": 0.6,
	"giro": 0.45,
	"remolino": 0.8,
	"aparecer": 0.4,
	"desaparecer": 0.4,
	"destello": 0.4,
	"cargar_energia": 0.5,
	"victoria_salto": 0.6,
	"victoria_giro": 0.8,
	"flotar": 2.0,
	"rebote": 0.8,
	"vibrar": 0.4,
	"barrida_baja": 0.42,
	"gancho_arriba": 0.4,
	"picada_aerea": 0.36,
	"tiron": 0.5,
	"caida": 0.6,
	"latigazo": 0.34,
}

## Curvas de llegada a cada clave. "sobrepaso" y "elastico" se pasan del valor y vuelven.
const CURVAS := ["suave", "lineal", "entrada", "salida", "sobrepaso", "elastico", "escalon"]
## Estilos pensados para repetirse en bucle (en el juego se reproducen una vez).
const LOOPS := ["flotar", "rebote", "vibrar"]

## Lo que pone "Generar TODAS": estilo recomendado para cada acción.
const RECOMENDADOS := {
	"golpe": "golpe_seco",
	"patada": "patada_alta",
	"golpe_recibido": "retroceso",
	"bloqueo": "guardia",
	"salto": "salto_elastico",
	"aterrizaje": "aterrizaje_pesado",
	"dash": "embestida",
	"especial": "destello",
	"victoria": "victoria_salto",
	"barrida": "barrida_baja",
	"antiaereo": "gancho_arriba",
	"aereo": "picada_aerea",
	"agarre": "tiron",
	"derribo": "caida",
}

## Juegos completos con personalidad: estilo por acción + multiplicadores.
## Los estilos que no aparecen salen de RECOMENDADOS.
const PRESETS := {
	"equilibrado": {"nombre": "Equilibrado", "intensidad": 1.0, "duracion": 1.0, "variacion": 0.2, "estilos": {}},
	"ligero": {"nombre": "Ligero y rápido", "intensidad": 0.7, "duracion": 0.85, "variacion": 0.3,
		"estilos": {"golpe": "latigazo", "patada": "latigazo", "dash": "embestida", "victoria": "victoria_giro"}},
	"pesado": {"nombre": "Pesado y contundente", "intensidad": 1.3, "duracion": 1.15, "variacion": 0.15,
		"estilos": {"golpe": "golpe_pesado", "patada": "golpe_pesado", "especial": "cargar_energia"},
		"capas": {"golpe_recibido": {"estilo": "sacudida", "intensidad": 0.6}, "aterrizaje": {"estilo": "sacudida", "intensidad": 0.4}}},
	"elastico": {"nombre": "Elástico (cartoon)", "intensidad": 1.2, "duracion": 1.0, "variacion": 0.25,
		"estilos": {"aterrizaje": "aterrizaje_pesado", "victoria": "brinco", "bloqueo": "guardia"},
		"capas": {"salto": {"estilo": "rebote", "intensidad": 0.5}}},
	"sutil": {"nombre": "Sutil (solo matices)", "intensidad": 0.45, "duracion": 1.0, "variacion": 0.1, "estilos": {}},
}

const NEUTRO := {"desp": Vector2.ZERO, "escala": Vector2.ONE, "rot": 0.0, "color": Color.WHITE}

static var _configs: Dictionary = {}


# --- Generar --------------------------------------------------------------------

## Animación lista para muestrear: {estilo, duracion, intensidad, loop, claves}.
## Devuelve {} si el estilo no existe.
static func generar(estilo: String, duracion: float = -1.0, intensidad: float = 1.0) -> Dictionary:
	var claves := _claves(estilo, intensidad)
	if claves.is_empty():
		return {}
	if duracion <= 0.0:
		duracion = float(DURACIONES.get(estilo, 0.4))
	return {
		"estilo": estilo, "duracion": maxf(duracion, 0.05), "intensidad": intensidad,
		"loop": LOOPS.has(estilo), "claves": claves,
	}


## Animación a partir de lo guardado para una acción ({estilo, duracion, intensidad,
## variacion?, capa?}). `fuerza` multiplica la intensidad; `semilla` < 0 = al azar.
static func generar_desde(datos: Dictionary, fuerza: float = 1.0, semilla: int = -1) -> Dictionary:
	var estilo := String(datos.get("estilo", ""))
	var inten := float(datos.get("intensidad", 1.0)) * fuerza
	var dur := float(datos.get("duracion", -1.0))
	if dur <= 0.0:
		dur = float(DURACIONES.get(estilo, 0.4))
	var variacion := clampf(float(datos.get("variacion", 0.0)), 0.0, 1.0)
	if variacion > 0.0:
		var rng := RandomNumberGenerator.new()
		if semilla >= 0:
			rng.seed = semilla
		else:
			rng.randomize()
		inten *= rng.randf_range(1.0 - 0.35 * variacion, 1.0 + 0.35 * variacion)
		dur *= rng.randf_range(1.0 - 0.15 * variacion, 1.0 + 0.15 * variacion)
	var anim := generar(estilo, dur, inten)
	if anim.is_empty():
		return {}
	var capa: Variant = datos.get("capa", null)
	if capa is Dictionary and DURACIONES.has(String(capa.get("estilo", ""))):
		# La capa dura lo mismo que la acción (se estira o encoge) y se apaga al final
		# (ver muestrear), así nunca deja al luchador desplazado cuando el juego corta el clip.
		var c := generar(String(capa["estilo"]), float(anim["duracion"]),
			float(capa.get("intensidad", 1.0)) * fuerza)
		c["loop"] = false
		anim["capa"] = c
	return anim


## Valores en el segundo `tiempo`: {desp, escala, rot, color}. Entre claves se
## interpola con la curva de la clave de llegada (smoothstep si no dice nada).
## Si la animación trae "capa", se suma encima (desp y rot se suman; escala y color se multiplican).
static func muestrear(anim: Dictionary, tiempo: float) -> Dictionary:
	if anim.is_empty():
		return NEUTRO.duplicate()
	var s := _muestrear_claves(anim, tiempo)
	var capa: Dictionary = anim.get("capa", {})
	if not capa.is_empty():
		var c := _muestrear_claves(capa, tiempo)
		# Se apaga en el último 20 % (algunos estilos, como rebote o vibrar, no acaban en reposo).
		var peso := 1.0 - smoothstep(0.8, 1.0, clampf(tiempo / float(capa["duracion"]), 0.0, 1.0))
		s["desp"] = (s["desp"] as Vector2) + (c["desp"] as Vector2) * peso
		s["escala"] = (s["escala"] as Vector2) * Vector2.ONE.lerp(c["escala"], peso)
		s["rot"] = float(s["rot"]) + float(c["rot"]) * peso
		s["color"] = (s["color"] as Color) * Color.WHITE.lerp(c["color"], peso)
	return s


static func _muestrear_claves(anim: Dictionary, tiempo: float) -> Dictionary:
	var p := tiempo / float(anim["duracion"])
	p = fposmod(p, 1.0) if bool(anim.get("loop", false)) else clampf(p, 0.0, 1.0)
	var claves: Array = anim["claves"]
	var a: Dictionary = claves[0]
	if p <= float(a["t"]):
		return _copia(a)
	for j in range(1, claves.size()):
		var b: Dictionary = claves[j]
		if p <= float(b["t"]):
			var tramo := maxf(float(b["t"]) - float(a["t"]), 0.0001)
			var k := aplicar_curva(_curva_de(b), (p - float(a["t"])) / tramo)
			return {
				"desp": (a["desp"] as Vector2).lerp(b["desp"], k),
				"escala": (a["escala"] as Vector2).lerp(b["escala"], k),
				"rot": lerpf(float(a["rot"]), float(b["rot"]), k),
				"color": (a["color"] as Color).lerp(b["color"], k),
			}
		a = b
	return _copia(claves[claves.size() - 1])


static func _curva_de(clave: Dictionary) -> String:
	if clave.has("curva"):
		return String(clave["curva"])
	return "suave" if bool(clave.get("suave", true)) else "lineal"


## Avance 0..1 de un tramo según la curva. "sobrepaso" y "elastico" pasan de 1 y vuelven.
static func aplicar_curva(curva: String, k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	match curva:
		"lineal":
			return k
		"entrada":
			return k * k * k
		"salida":
			return 1.0 - pow(1.0 - k, 3.0)
		"sobrepaso":  # easeOutBack
			var c1 := 1.70158
			return 1.0 + (c1 + 1.0) * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)
		"elastico":  # easeOutElastic
			if k <= 0.0 or k >= 1.0:
				return k
			return pow(2.0, -10.0 * k) * sin((k * 10.0 - 0.75) * TAU / 3.0) + 1.0
		"escalon":
			return 0.0 if k < 1.0 else 1.0
	return smoothstep(0.0, 1.0, k)


## Juego completo de acciones de un preset (ver PRESETS), listo para guardar_config.
static func preset(nombre: String) -> Dictionary:
	var p: Dictionary = PRESETS.get(nombre, PRESETS["equilibrado"])
	var estilos: Dictionary = p.get("estilos", {})
	var capas: Dictionary = p.get("capas", {})
	var acciones := {}
	for accion in ACCIONES:
		var e := String(estilos.get(accion, RECOMENDADOS.get(accion, "golpe_seco")))
		var datos := {
			"estilo": e,
			"duracion": snappedf(float(DURACIONES[e]) * float(p.get("duracion", 1.0)), 0.01),
			"intensidad": snappedf(float(p.get("intensidad", 1.0)), 0.05),
			"variacion": float(p.get("variacion", 0.0)),
		}
		if capas.has(accion):
			datos["capa"] = (capas[accion] as Dictionary).duplicate()
		acciones[accion] = datos
	return acciones


static func es_loop(estilo: String) -> bool:
	return LOOPS.has(estilo)


static func estilos() -> Array:
	return DURACIONES.keys()


# --- Guardar y cargar las animaciones de cada luchador ---------------------------

static func ruta_config(id: String) -> String:
	return "res://assets/fighters/%s/%s_autoanim.tres" % [id, id]


## Acciones guardadas de un luchador: {accion: {estilo, duracion, intensidad}}.
static func config(id: String) -> Dictionary:
	if _configs.has(id):
		return _configs[id]
	var acciones := {}
	var ruta := ruta_config(id)
	if ResourceLoader.exists(ruta):
		var res: Resource = load(ruta)
		if res != null and res.get("acciones") is Dictionary:
			for accion in res.get("acciones"):
				var datos: Variant = res.get("acciones")[accion]
				if ACCIONES.has(accion) and datos is Dictionary and DURACIONES.has(String(datos.get("estilo", ""))):
					acciones[accion] = datos
	_configs[id] = acciones
	return acciones


## Guarda las acciones de un luchador (las vacías borran el archivo). Devuelve un error de Godot.
static func guardar_config(id: String, acciones: Dictionary) -> int:
	_configs.erase(id)
	var ruta := ruta_config(id)
	if acciones.is_empty():
		if FileAccess.file_exists(ruta):
			return DirAccess.remove_absolute(ProjectSettings.globalize_path(ruta))
		return OK
	var res: Resource = ConfigScript.new()
	res.set("acciones", acciones.duplicate(true))
	return ResourceSaver.save(res, ruta)


static func olvidar_cache() -> void:
	_configs.clear()


## Animación de una acción del luchador, o {} si no tiene (ni ella ni su RESPALDO).
## opciones (todas opcionales):
##   "fuerza": float   multiplica la intensidad (p. ej. 1.5 en un golpe fuerte recibido)
##   "semilla": int    para la variación aleatoria; misma semilla = misma animación
##   "sin_respaldo": bool  no probar la acción de RESPALDO
static func para_accion(id: String, accion: String, opciones: Dictionary = {}) -> Dictionary:
	var datos: Dictionary = config(id).get(accion, {})
	if datos.is_empty():
		if bool(opciones.get("sin_respaldo", false)) or not RESPALDO.has(accion):
			return {}
		datos = config(id).get(String(RESPALDO[accion]), {})
		if datos.is_empty():
			return {}
	return generar_desde(datos, float(opciones.get("fuerza", 1.0)), int(opciones.get("semilla", -1)))


# --- Estilos -----------------------------------------------------------------------

static func _copia(k: Dictionary) -> Dictionary:
	return {"desp": k["desp"], "escala": k["escala"], "rot": k["rot"], "color": k["color"]}


static func _k(t: float, desp := Vector2.ZERO, escala := Vector2.ONE, rot := 0.0, color := Color.WHITE, suave := true) -> Dictionary:
	return {"t": t, "desp": desp, "escala": escala, "rot": rot, "color": color, "suave": suave}


## Igual que _k pero diciendo la curva de llegada (ver CURVAS).
static func _kc(curva: String, t: float, desp := Vector2.ZERO, escala := Vector2.ONE, rot := 0.0, color := Color.WHITE) -> Dictionary:
	var k := _k(t, desp, escala, rot, color)
	k["curva"] = curva
	return k


## Aplastar (a > 0) o estirar (a < 0) conservando más o menos el volumen.
static func _apl(a: float) -> Vector2:
	return Vector2(1.0 + a, 1.0 - a)


static func _brillo(b: float) -> Color:
	return Color(1.0 + b, 1.0 + b, 1.0 + b)


static func _claves(estilo: String, i: float) -> Array:
	var Z := Vector2.ZERO
	var U := Vector2.ONE
	match estilo:
		"golpe_seco":  # cargar atrás, impacto rápido, mantener y volver
			return [_k(0.0), _k(0.25, Vector2(-6, 0) * i, _apl(-0.04 * i), -4 * i),
				_k(0.42, Vector2(14, 0) * i, _apl(0.07 * i), 6 * i, Color.WHITE, false),
				_k(0.62, Vector2(13, 0) * i, _apl(0.05 * i), 5 * i), _k(1.0)]
		"golpe_pesado":
			return [_k(0.0), _k(0.32, Vector2(-10, 2) * i, _apl(-0.07 * i), -8 * i),
				_k(0.48, Vector2(20, 0) * i, _apl(0.11 * i), 10 * i, _brillo(0.5 * i), false),
				_k(0.72, Vector2(18, 0) * i, _apl(0.06 * i), 6 * i), _k(1.0)]
		"patada_alta":  # se echa atrás para equilibrar y empuja
			return [_k(0.0), _k(0.28, Vector2(-5, 0) * i, _apl(-0.03 * i), -10 * i),
				_k(0.46, Vector2(12, -3) * i, _apl(0.06 * i), -8 * i, Color.WHITE, false),
				_k(0.72, Vector2(10, -2) * i, U, -6 * i), _k(1.0)]
		"embestida":
			return [_k(0.0), _k(0.3, Vector2(-6, 0) * i, _apl(0.05 * i), -10 * i),
				_k(0.45, Vector2(20, 0) * i, _apl(-0.08 * i), 15 * i),
				_k(0.7, Vector2(16, 0) * i, U, 8 * i), _k(1.0)]
		"retroceso":  # recibir un golpe: destello, salir hacia atrás y oscilar
			return [_k(0.0, Z, U, 0.0, _brillo(1.5 * i)),
				_k(0.1, Vector2(-12, -1) * i, _apl(0.1 * i), -12 * i, _brillo(1.0 * i), false),
				_k(0.25, Vector2(-8, 0) * i, U, -6 * i, Color.WHITE, false),
				_k(0.4, Vector2(-4, 0) * i, U, -2 * i, Color.WHITE, false),
				_k(0.6, Vector2(-1, 0) * i, U, 0.0, Color.WHITE, false), _k(1.0)]
		"sacudida":  # temblor que se apaga
			var claves := [_k(0.0, Z, U, 0.0, _brillo(1.2 * i))]
			for n in range(1, 8):
				var lado := 1.0 if n % 2 == 1 else -1.0
				var fuerza := (1.0 - n / 8.0) * 4.0 * i
				claves.append(_k(n / 8.0, Vector2(lado * fuerza, 0), U, lado * fuerza * 0.5, Color.WHITE, false))
			claves.append(_k(1.0))
			return claves
		"guardia":  # se encoge con destello cian
			return [_k(0.0, Z, U, 0.0, Color(0.7, 1.6, 2.0)),
				_k(0.25, Vector2(-4, 0) * i, _apl(0.04 * i), -3 * i, Color(0.85, 1.3, 1.5)),
				_k(0.6, Vector2(-3, 0) * i, _apl(0.03 * i), -2 * i), _k(1.0)]
		"inclinarse":
			return [_k(0.0), _k(0.4, Z, U, 15 * i), _k(1.0)]
		"salto_elastico":  # agacharse y estirarse al despegar
			return [_k(0.0), _k(0.2, Z, _apl(0.12 * i)), _k(0.5, Z, _apl(-0.09 * i)), _k(1.0)]
		"aterrizaje_pesado":
			return [_k(0.0, Z, _apl(0.17 * i)), _k(0.35, Z, _apl(-0.05 * i)), _k(0.65, Z, _apl(0.03 * i)), _k(1.0)]
		"brinco":
			return [_k(0.0), _k(0.15, Z, _apl(0.15 * i)), _k(0.5, Vector2(0, -32) * i, _apl(-0.12 * i)),
				_k(0.85, Z, _apl(0.15 * i)), _k(1.0)]
		"giro":
			var vueltas := maxf(1.0, roundf(i))
			return [_k(0.0), _k(1.0, Z, U, 360.0 * vueltas, Color.WHITE, false)]
		"remolino":  # elevarse girando y caer con fuerza
			return [_k(0.0), _k(0.3, Vector2(0, 3) * i, _apl(0.15 * i), 5 * i),
				_k(0.5, Vector2(0, -24) * i, _apl(-0.15 * i), 180.0),
				_k(0.75, Vector2(0, -24) * i, U * (1.0 + 0.15 * i), 360.0),
				_k(0.9, Z, _apl(0.12 * i), 360.0), _k(1.0, Z, U, 360.0)]
		"aparecer":
			return [_k(0.0, Z, U * 0.05, 0.0, Color(1.5, 1.5, 1.5, 0.0)),
				_k(0.6, Z, U * (1.0 + 0.2 * i), 0.0, _brillo(0.6)),
				_k(0.8, Z, U * (1.0 - 0.05 * i)), _k(1.0)]
		"desaparecer":
			return [_k(0.0), _k(0.3, Z, U * (1.0 + 0.15 * i), 0.0, _brillo(0.5)),
				_k(0.95, Vector2(0, -12) * i, U * 0.05, 0.0, Color(1.5, 1.5, 1.5, 0.0)),
				_k(1.0)]
		"destello":  # brillo y pulso de tamaño (técnicas)
			return [_k(0.0), _k(0.2, Vector2(-3, 0) * i, _apl(-0.05 * i), -3 * i, _brillo(0.8 * i)),
				_k(0.45, Vector2(6, 0) * i, U * (1.0 + 0.06 * i), 4 * i, _brillo(1.2 * i)),
				_k(1.0)]
		"cargar_energia":
			var claves := [_k(0.0)]
			for n in range(1, 10):
				var lado := 1.0 if n % 2 == 1 else -1.0
				claves.append(_k(n / 10.0, Vector2(lado * 1.5 * i, 0), U * (1.0 + 0.04 * i), 0.0,
					Color(1.0 + 0.4 * i, 1.0 + 0.3 * i, 1.0 + 0.6 * i), false))
			claves.append(_k(1.0))
			return claves
		"victoria_salto":
			return [_k(0.0, Z, U, 0.0, _brillo(0.8)), _k(0.15, Z, _apl(0.1 * i)),
				_k(0.45, Vector2(0, -16) * i, _apl(-0.1 * i)), _k(0.7, Z, _apl(0.12 * i)), _k(1.0)]
		"victoria_giro":
			return [_k(0.0, Z, U, 0.0, _brillo(0.6)), _k(0.2, Z, _apl(0.1 * i)),
				_k(0.6, Vector2(0, -20) * i, _apl(-0.08 * i), 360.0), _k(0.8, Z, _apl(0.1 * i), 360.0),
				_k(1.0, Z, U, 360.0)]
		"flotar":
			return [_k(0.0), _k(0.5, Vector2(0, -6) * i), _k(1.0)]
		"rebote":
			return [_k(0.0, Z, _apl(0.08 * i)), _k(0.5, Vector2(0, -10) * i, _apl(-0.06 * i)), _k(1.0, Z, _apl(0.08 * i))]
		"vibrar":
			return [_k(0.0, Z, U * (1.0 + 0.03 * i)),
				_k(0.25, Vector2(1.5, 0) * i, U * (1.0 + 0.06 * i), 0.0, Color.WHITE, false),
				_k(0.5, Vector2(-1.5, 1) * i, U * (1.0 + 0.03 * i), 0.0, Color.WHITE, false),
				_k(0.75, Vector2(0, -1) * i, U * (1.0 + 0.06 * i), 0.0, Color.WHITE, false),
				_k(1.0, Z, U * (1.0 + 0.03 * i))]
		"barrida_baja":  # agacharse mucho y barrer hacia delante pegado al suelo
			return [_k(0.0), _kc("salida", 0.22, Vector2(-4, 6) * i, _apl(0.14 * i), -6 * i),
				_kc("salida", 0.42, Vector2(18, 8) * i, _apl(0.2 * i), 8 * i),
				_k(0.7, Vector2(14, 6) * i, _apl(0.12 * i), 4 * i), _kc("sobrepaso", 1.0)]
		"gancho_arriba":  # se encoge y sale disparado hacia arriba estirándose
			return [_k(0.0), _kc("entrada", 0.25, Vector2(-2, 5) * i, _apl(0.14 * i), -6 * i),
				_kc("salida", 0.45, Vector2(6, -14) * i, _apl(-0.16 * i), -10 * i, _brillo(0.4 * i)),
				_k(0.7, Vector2(4, -10) * i, _apl(-0.06 * i), -6 * i), _kc("sobrepaso", 1.0)]
		"picada_aerea":  # se inclina y cae sobre el rival
			return [_k(0.0), _k(0.2, Vector2(-3, -4) * i, _apl(-0.05 * i), -12 * i),
				_kc("entrada", 0.5, Vector2(12, 6) * i, _apl(0.06 * i), 18 * i),
				_k(0.75, Vector2(10, 4) * i, U, 10 * i), _k(1.0)]
		"tiron":  # agarre: se lanza, sujeta y tira hacia atrás
			return [_k(0.0), _kc("salida", 0.2, Vector2(12, 0) * i, _apl(-0.06 * i), 10 * i),
				_k(0.4, Vector2(10, 0) * i, _apl(0.05 * i), 6 * i),
				_kc("entrada", 0.65, Vector2(-10, -2) * i, _apl(-0.05 * i), -14 * i),
				_kc("sobrepaso", 1.0)]
		"caida":  # derribo: sale despedido, golpea el suelo y rebota un poco
			return [_k(0.0, Z, U, 0.0, _brillo(1.2 * i)),
				_kc("salida", 0.25, Vector2(-14, -10) * i, _apl(-0.08 * i), -25 * i),
				_kc("entrada", 0.5, Vector2(-18, 0) * i, _apl(0.22 * i), -8 * i),
				_kc("elastico", 1.0)]
		"latigazo":  # golpe muy rápido con rebote elástico al volver
			return [_k(0.0), _k(0.15, Vector2(-3, 0) * i, _apl(-0.03 * i), -3 * i),
				_kc("salida", 0.32, Vector2(12, 0) * i, _apl(0.06 * i), 5 * i),
				_kc("elastico", 1.0)]
	return []
