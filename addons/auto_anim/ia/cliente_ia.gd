@tool
extends Node
## Cliente de IA de AutoAnim: manda la descripción a un "cerebro" y devuelve el texto JSON.
## Proveedores:
##   claude -> Claude Code por línea de comandos (claude -p), usa tu sesión, sin clave de API.
##   codex  -> Codex por línea de comandos (codex exec), razonamiento bajo para gastar poco.
##   ollama -> modelo local de Ollama por HTTP (http://localhost:11434), gratis y sin internet.
##   local  -> sin IA: entiende palabras clave en español (salto, giro, rebote...). Instantáneo.
## Los CLI corren en un hilo para no congelar el editor.

signal terminado(ok: bool, texto: String, error: String)

const PROVEEDORES := ["claude", "codex", "ollama", "local"]
const NOMBRES := {
	"claude": "Claude (Claude Code)",
	"codex": "Codex",
	"ollama": "Ollama (local)",
	"local": "Local sin IA (palabras clave)",
}
const MODELO_POR_DEFECTO := {"claude": "haiku", "codex": "", "ollama": "llama3.2", "local": ""}
const URL_OLLAMA := "http://localhost:11434"
const TIEMPO_LIMITE := 180.0

const PROMPT_SISTEMA := """Eres un generador de animaciones 2D para Godot 4.
Responde UNICAMENTE con un objeto JSON valido, sin texto antes ni despues y sin markdown.
Formato exacto:
{"duracion": <segundos>, "loop": <true|false>, "pistas": [{"propiedad": "<position|rotation|scale|color>", "claves": [{"tiempo": <segundos>, "valor": <valor>}]}]}
Reglas:
- position: [x, y] en pixeles RELATIVOS al reposo ([0, 0] = donde esta el nodo). y negativo es ARRIBA.
- rotation: grados RELATIVOS y acumulados (360 = una vuelta completa, 720 = dos). Positivo = horario.
- scale: [x, y] multiplicador ([1, 1] = tamano normal). Para aplastar al caer usa p. ej. [1.25, 0.8].
- color: [r, g, b, a] que multiplica el color ([1, 1, 1, 1] = sin cambio; a = 0 invisible). Para brillar o
  destellar puedes subir r, g, b hasta 3 (p. ej. [2, 0.6, 0.6, 1] = destello rojo).
- Usa la duracion pedida. Los tiempos van de 0 a duracion. La primera clave de cada pista en 0 con el valor de reposo
  y, si no es un bucle, la ultima vuelve al reposo salvo que la descripcion pida terminar en otro sitio.
- Solo incluye las pistas que la descripcion necesita. Entre 3 y 12 claves por pista; anticipacion y rebote dan vida.
- loop = true solo si la descripcion habla de repetir, bucle, flotar, latir o similar."""

var _hilo: Thread
var _http: HTTPRequest
var _ocupado := false
var _inicio := 0.0
var proveedor_actual := ""

## Ruta de los ejecutables (se pueden cambiar desde el panel).
var ruta_claude := "claude"
var ruta_codex := "codex"
var url_ollama := URL_OLLAMA


func esta_ocupado() -> bool:
	return _ocupado


func segundos() -> float:
	return (Time.get_ticks_msec() / 1000.0) - _inicio if _ocupado else 0.0


static func prompt_usuario(descripcion: String, duracion: float) -> String:
	return "Descripcion de la animacion: %s\nDuracion: %.2f segundos." % [descripcion.strip_edges(), duracion]


static func prompt_completo(descripcion: String, duracion: float) -> String:
	return PROMPT_SISTEMA + "\n\n" + prompt_usuario(descripcion, duracion)


## Carpeta de trabajo de los CLI (fuera del proyecto, sin espacios en Windows).
static func carpeta_trabajo() -> String:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = OS.get_environment("TMPDIR")
	if base.is_empty():
		base = OS.get_user_data_dir()
	return base.path_join("autoanim_ia").replace("\\", "/")


## Línea de comandos que ejecuta el proveedor leyendo prompt.txt y dejando la respuesta en salida.txt.
static func comando(proveedor: String, modelo: String, ejecutable: String) -> String:
	var exe := ejecutable if not ejecutable.is_empty() else proveedor
	if exe.contains(" "):
		exe = "\"%s\"" % exe
	match proveedor:
		"claude":
			var m := (" --model " + modelo) if not modelo.is_empty() else ""
			return "%s -p%s --output-format text --tools \"\" --no-session-persistence --strict-mcp-config < prompt.txt > salida.txt 2> error.txt" % [exe, m]
		"codex":
			var m2 := (" -m " + modelo) if not modelo.is_empty() else ""
			return "%s exec --skip-git-repo-check --sandbox read-only --ephemeral -c model_reasoning_effort=low%s -o salida.txt - < prompt.txt > registro.txt 2> error.txt" % [exe, m2]
	return ""


## Cuerpo de la petición a Ollama (/api/chat).
static func peticion_ollama(modelo: String, descripcion: String, duracion: float) -> Dictionary:
	return {
		"model": modelo if not modelo.is_empty() else MODELO_POR_DEFECTO["ollama"],
		"stream": false,
		"format": "json",
		"options": {"temperature": 0.4},
		"messages": [
			{"role": "system", "content": PROMPT_SISTEMA},
			{"role": "user", "content": prompt_usuario(descripcion, duracion)},
		],
	}


static func extraer_ollama(respuesta: Variant) -> String:
	if respuesta is Dictionary:
		var msg: Variant = (respuesta as Dictionary).get("message")
		if msg is Dictionary:
			return String((msg as Dictionary).get("content", ""))
	return ""


# ================================================================ Pedir

func pedir(proveedor: String, modelo: String, descripcion: String, duracion: float) -> void:
	if _ocupado:
		terminado.emit(false, "", "Ya hay una petición en marcha.")
		return
	if descripcion.strip_edges().is_empty():
		terminado.emit(false, "", "Escribe una descripción.")
		return
	proveedor_actual = proveedor
	match proveedor:
		"local":
			terminado.emit(true, receta_local(descripcion, duracion), "")
		"ollama":
			_pedir_ollama(modelo, descripcion, duracion)
		"claude", "codex":
			_pedir_cli(proveedor, modelo, descripcion, duracion)
		_:
			terminado.emit(false, "", "Proveedor desconocido: " + proveedor)


func _pedir_cli(proveedor: String, modelo: String, descripcion: String, duracion: float) -> void:
	var carpeta := carpeta_trabajo()
	DirAccess.make_dir_recursive_absolute(carpeta)
	for f in ["salida.txt", "error.txt", "registro.txt"]:
		if FileAccess.file_exists(carpeta.path_join(f)):
			DirAccess.remove_absolute(carpeta.path_join(f))
	var fp := FileAccess.open(carpeta.path_join("prompt.txt"), FileAccess.WRITE)
	if fp == null:
		terminado.emit(false, "", "No pude escribir en " + carpeta)
		return
	fp.store_string(prompt_completo(descripcion, duracion))
	fp.close()

	var linea := comando(proveedor, modelo, ruta_claude if proveedor == "claude" else ruta_codex)
	var args: PackedStringArray
	var exe: String
	if OS.get_name() == "Windows":
		var bat := carpeta.path_join("pedir.bat")
		var fb := FileAccess.open(bat, FileAccess.WRITE)
		fb.store_string("@echo off\r\nchcp 65001 >nul\r\ncd /d \"%~dp0\"\r\n" + linea + "\r\n")
		fb.close()
		exe = "cmd.exe"
		args = ["/c", bat.replace("/", "\\")]
	else:
		exe = "/bin/sh"
		args = ["-c", "cd '%s' && %s" % [carpeta, linea]]

	_ocupado = true
	_inicio = Time.get_ticks_msec() / 1000.0
	_hilo = Thread.new()
	_hilo.start(_correr.bind(exe, args, carpeta, proveedor))


func _correr(exe: String, args: PackedStringArray, carpeta: String, proveedor: String) -> void:
	var salida: Array = []
	var codigo := OS.execute(exe, args, salida, true)
	var texto := _leer(carpeta.path_join("salida.txt"))
	var err := _leer(carpeta.path_join("error.txt")).strip_edges()
	call_deferred("_fin_cli", codigo, texto, err, proveedor)


func _fin_cli(codigo: int, texto: String, err: String, proveedor: String) -> void:
	if _hilo:
		_hilo.wait_to_finish()
		_hilo = null
	_ocupado = false
	if texto.strip_edges().is_empty():
		var motivo := err if not err.is_empty() else "código de salida %d" % codigo
		if codigo == 9009 or err.contains("no se reconoce") or err.contains("not recognized"):
			motivo = "No encuentro el programa '%s'. Pon su ruta en Ajustes." % proveedor
		terminado.emit(false, "", "%s no respondió: %s" % [NOMBRES.get(proveedor, proveedor), motivo.left(400)])
		return
	terminado.emit(true, texto, "")


static func _leer(ruta: String) -> String:
	if not FileAccess.file_exists(ruta):
		return ""
	return FileAccess.get_file_as_string(ruta)


func _pedir_ollama(modelo: String, descripcion: String, duracion: float) -> void:
	if _http == null:
		_http = get_node_or_null("Http") as HTTPRequest
		if _http == null:
			_http = HTTPRequest.new()
			_http.name = "Http"
			_http.timeout = TIEMPO_LIMITE
			add_child(_http)
		_http.request_completed.connect(_fin_ollama)
	var cuerpo := JSON.stringify(peticion_ollama(modelo, descripcion, duracion))
	var url := url_ollama.trim_suffix("/") + "/api/chat"
	var e := _http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, cuerpo)
	if e != OK:
		terminado.emit(false, "", "No pude conectar con Ollama (%s)." % error_string(e))
		return
	_ocupado = true
	_inicio = Time.get_ticks_msec() / 1000.0


func _fin_ollama(resultado: int, codigo: int, _cabeceras: PackedStringArray, cuerpo: PackedByteArray) -> void:
	_ocupado = false
	if resultado != HTTPRequest.RESULT_SUCCESS:
		terminado.emit(false, "", "Ollama no responde en %s. ¿Está abierto? (ollama serve)" % url_ollama)
		return
	var texto := cuerpo.get_string_from_utf8()
	if codigo != 200:
		terminado.emit(false, "", "Ollama devolvió %d: %s" % [codigo, texto.left(300)])
		return
	var contenido := extraer_ollama(JSON.parse_string(texto))
	if contenido.is_empty():
		terminado.emit(false, "", "Ollama respondió vacío.")
		return
	terminado.emit(true, contenido, "")


func _exit_tree() -> void:
	if _hilo and _hilo.is_started():
		_hilo.wait_to_finish()


# ================================================================ Local sin IA

## Entiende frases como "salto alto con giro de 360 grados y caída suave", "latido rojo en bucle",
## "temblor fuerte", "entra desde la izquierda", "rebota 3 veces", "desaparece".
## Devuelve el texto JSON de una receta (pasa por el mismo traductor que la IA).
static func receta_local(descripcion: String, duracion: float) -> String:
	var d := descripcion.to_lower()
	var dur := clampf(duracion, 0.1, 30.0)
	var fuerza := 1.0
	if _tiene(d, ["muy alto", "enorme", "gigante", "muy fuerte", "brutal"]):
		fuerza = 1.8
	elif _tiene(d, ["alto", "fuerte", "grande"]):
		fuerza = 1.4
	elif _tiene(d, ["pequeño", "pequeno", "leve", "suave", "bajito"]):
		fuerza = 0.7
	var loop := _tiene(d, ["bucle", "loop", "repite", "repetir", "siempre", "flota", "late", "latido", "infinito"])
	var pos: Array = []
	var rot: Array = []
	var esc: Array = []
	var col: Array = []

	if _tiene(d, ["salt", "brinc"]):
		var h := -90.0 * fuerza
		pos = [[0.0, [0, 0]], [0.12, [0, 8]], [0.45, [0, h]], [0.55, [0, h * 0.97]], [0.9, [0, 0]], [1.0, [0, 0]]]
		esc = [[0.0, [1, 1]], [0.12, [1.2, 0.8]], [0.25, [0.88, 1.15]], [0.5, [1, 1]], [0.9, [1.25, 0.78]], [1.0, [1, 1]]]
		if _tiene(d, ["caída suave", "caida suave", "aterriza suave", "suave"]):
			esc[4] = [0.92, [1.1, 0.9]]
	if _tiene(d, ["rebot"]):
		var veces := clampi(int(_numero(d, ["rebota", "rebotes", "veces"], 3.0)), 1, 8)
		pos = [[0.0, [0, 0]]]
		esc = [[0.0, [1, 1]]]
		var h2 := -70.0 * fuerza
		for i in veces:
			var a := float(i) / veces
			var b := float(i + 1) / veces
			var alto := h2 * pow(0.6, i)
			pos.append([lerpf(a, b, 0.5), [0, alto]])
			pos.append([b, [0, 0]])
			esc.append([b - 0.001, [1.0 + 0.2 * pow(0.6, i), 1.0 - 0.2 * pow(0.6, i)]])
		esc.append([1.0, [1, 1]])
	if _tiene(d, ["gir", "vuelta", "rota", "360", "grados"]):
		var grados := _numero(d, ["grados", "°"], 0.0)
		if grados == 0.0:
			grados = 360.0 * _numero(d, ["vueltas", "vuelta"], 1.0)
		if _tiene(d, ["izquierda", "antihorario", "al revés", "al reves"]):
			grados = -grados
		# Con salto: gira en el aire. Sin salto: pequeña anticipación y giro.
		var t0 := 0.15 if not pos.is_empty() else 0.1
		var t1 := 0.8 if not pos.is_empty() else 0.85
		rot = [[0.0, 0.0], [t0, -8.0 * signf(grados)], [t1, grados], [1.0, grados]]
		if loop and pos.is_empty():
			rot = [[0.0, 0.0], [1.0, grados]]
	if _tiene(d, ["tembl", "sacud", "vibr", "agit"]):
		var a2 := 6.0 * fuerza
		pos = [[0.0, [0, 0]]]
		for i in 10:
			var s := 1.0 if i % 2 == 0 else -1.0
			pos.append([0.05 + 0.09 * i, [a2 * s * (1.0 - i / 10.0), a2 * 0.4 * -s]])
		pos.append([1.0, [0, 0]])
	if _tiene(d, ["late", "latido", "pulso", "palpit", "respira", "crece"]):
		var k := 0.15 * fuerza
		esc = [[0.0, [1, 1]], [0.15, [1 + k, 1 + k]], [0.3, [1, 1]], [0.45, [1 + k * 0.6, 1 + k * 0.6]], [0.65, [1, 1]], [1.0, [1, 1]]]
	if _tiene(d, ["flot", "levit"]):
		pos = [[0.0, [0, 0]], [0.5, [0, -14.0 * fuerza]], [1.0, [0, 0]]]
		loop = true
	if _tiene(d, ["entra", "aparece desde", "llega"]):
		var lado := -1.0 if _tiene(d, ["izquierda"]) else 1.0
		pos = [[0.0, [300.0 * lado, 0]], [0.7, [-12.0 * lado, 0]], [1.0, [0, 0]]]
	elif _tiene(d, ["derecha", "izquierda", "avanza", "embest", "carga"]) and pos.is_empty():
		var lado2 := -1.0 if _tiene(d, ["izquierda", "retrocede"]) else 1.0
		pos = [[0.0, [0, 0]], [0.2, [-15.0 * lado2, 0]], [0.45, [120.0 * fuerza * lado2, 0]], [1.0, [0, 0]]]

	var color := _color(d)
	if _tiene(d, ["desaparec", "se desvanece", "fade out", "se apaga"]):
		col = [[0.0, [1, 1, 1, 1]], [1.0, [1, 1, 1, 0]]]
	elif _tiene(d, ["aparece", "fade in"]) and not _tiene(d, ["aparece desde"]):
		col = [[0.0, [1, 1, 1, 0]], [1.0, [1, 1, 1, 1]]]
	elif _tiene(d, ["parpade", "intermit"]):
		col = [[0.0, [1, 1, 1, 1]], [0.25, [1, 1, 1, 0.1]], [0.5, [1, 1, 1, 1]], [0.75, [1, 1, 1, 0.1]], [1.0, [1, 1, 1, 1]]]
	elif color.size() > 0 or _tiene(d, ["brill", "destell"]):
		var c: Array = color if color.size() > 0 else [1.6, 1.6, 1.6, 1]
		col = [[0.0, [1, 1, 1, 1]], [0.25, c], [1.0, [1, 1, 1, 1]]]

	if pos.is_empty() and rot.is_empty() and esc.is_empty() and col.is_empty():
		# Nada reconocido: un pequeño rebote de "estoy vivo".
		esc = [[0.0, [1, 1]], [0.3, [1.12, 0.9]], [0.6, [0.95, 1.06]], [1.0, [1, 1]]]

	var pistas: Array = []
	for par in [["position", pos], ["rotation", rot], ["scale", esc], ["color", col]]:
		var claves: Array = []
		for k in par[1]:
			claves.append({"tiempo": snappedf(float(k[0]) * dur, 0.001), "valor": k[1]})
		if not claves.is_empty():
			pistas.append({"propiedad": par[0], "claves": claves})
	return JSON.stringify({"duracion": dur, "loop": loop, "pistas": pistas})


static func _tiene(texto: String, palabras: Array) -> bool:
	for p in palabras:
		if texto.contains(String(p)):
			return true
	return false


## Número escrito justo antes de alguna de las palabras ("360 grados", "2 vueltas", "rebota 3 veces").
static func _numero(texto: String, palabras: Array, defecto: float) -> float:
	var re := RegEx.new()
	re.compile("(-?\\d+(?:[.,]\\d+)?)\\s*(?:°|º)?\\s*([a-záéíóúñ]+)?")
	for m in re.search_all(texto):
		var pal := m.get_string(2)
		for p in palabras:
			if pal.begins_with(String(p)) or (String(p) == "°" and texto.substr(m.get_end(1), 1) == "°"):
				return float(m.get_string(1).replace(",", "."))
	# "rebota 3 veces": número después de la palabra.
	for p in palabras:
		var i := texto.find(String(p))
		if i >= 0:
			var re2 := RegEx.new()
			re2.compile("^\\s*(\\d+)")
			var m2 := re2.search(texto.substr(i + String(p).length()))
			if m2:
				return float(m2.get_string(1))
	return defecto


static func _color(texto: String) -> Array:
	var colores := {
		"rojo": [1.6, 0.5, 0.5, 1], "roja": [1.6, 0.5, 0.5, 1], "azul": [0.6, 0.8, 1.7, 1],
		"verde": [0.6, 1.6, 0.6, 1], "amarill": [1.6, 1.5, 0.5, 1], "dorad": [1.6, 1.3, 0.6, 1],
		"morad": [1.3, 0.6, 1.6, 1], "blanco": [2.0, 2.0, 2.0, 1], "negro": [0.2, 0.2, 0.2, 1],
	}
	for c in colores.keys():
		if texto.contains(c):
			return colores[c]
	return []
