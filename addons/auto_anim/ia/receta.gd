@tool
extends RefCounted
## Traduce la respuesta de texto de una IA a una receta de animacion normalizada.

const PROPIEDADES := ["position", "rotation", "scale", "modulate"]


static func limpiar(texto: String) -> String:
	var limpio := texto.strip_edges()
	var inicio := limpio.find("{")
	var fin := limpio.rfind("}")
	if inicio < 0 or fin < inicio:
		return ""
	return limpio.substr(inicio, fin - inicio + 1)


static func _es_numero(valor: Variant) -> bool:
	return (valor is int or valor is float) and is_finite(float(valor))


static func convertir(propiedad: String, valor: Variant) -> Variant:
	match propiedad:
		"position", "scale":
			if propiedad == "scale" and _es_numero(valor):
				return Vector2(float(valor), float(valor))
			if valor is Array and valor.size() == 2:
				if _es_numero(valor[0]) and _es_numero(valor[1]):
					return Vector2(float(valor[0]), float(valor[1]))
			if valor is Dictionary and _es_numero(valor.get("x")) and _es_numero(valor.get("y")):
				return Vector2(float(valor["x"]), float(valor["y"]))
		"rotation":
			if _es_numero(valor):
				return deg_to_rad(float(valor))
		"modulate":
			if valor is Array and valor.size() in [3, 4]:
				var divisor := 1.0
				for componente in valor:
					if not _es_numero(componente):
						return null
					# Hasta 4.0 es un brillo (modulate puede pasar de 1); mas alto es escala 0..255.
					if float(componente) > 4.0:
						divisor = 255.0
				var alfa := float(valor[3]) / divisor if valor.size() == 4 else 1.0
				return Color(float(valor[0]) / divisor, float(valor[1]) / divisor, float(valor[2]) / divisor, alfa)
			if valor is String:
				if valor.begins_with("#"):
					if valor.length() in [7, 9] and Color.html_is_valid(valor):
						return Color.html(valor)
					return null
				var respaldo := Color(-1.0, -1.0, -1.0, -1.0)
				var color := Color.from_string(valor, respaldo)
				if color != respaldo:
					return color
	return null


static func _fallo(error: String) -> Dictionary:
	return {"ok": false, "error": error, "receta": {}}


static func parsear(texto: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(limpiar(texto)) != OK:
		return _fallo("Error JSON en la linea %d: %s" % [json.get_error_line(), json.get_error_message()])
	var datos: Variant = json.data
	if not datos is Dictionary:
		return _fallo("La respuesta JSON debe ser un objeto")
	var duracion_entrada: Variant = datos.get("duracion", datos.get("duration", 1.0))
	var duracion := clampf(float(duracion_entrada), 0.05, 30.0) if _es_numero(duracion_entrada) else 1.0
	var loop_entrada: Variant = datos.get("loop", false)
	var receta := {"duracion": duracion, "loop": loop_entrada if loop_entrada is bool else false, "pistas": []}
	var pistas: Variant = datos.get("pistas", datos.get("tracks", []))
	var fusionadas := {}
	var alias := {"color": "modulate", "rotation_degrees": "rotation", "pos": "position",
		"posicion": "position", "escala": "scale", "rotacion": "rotation"}
	if pistas is Array:
		for pista in pistas:
			if not pista is Dictionary:
				continue
			var propiedad: Variant = pista.get("propiedad", pista.get("property"))
			if not propiedad is String:
				continue
			propiedad = alias.get(propiedad, propiedad)
			if propiedad not in PROPIEDADES:
				continue
			var claves: Variant = pista.get("claves", pista.get("keys", []))
			if not claves is Array:
				continue
			for clave in claves:
				if not clave is Dictionary:
					continue
				var tiempo: Variant = clave.get("tiempo", clave.get("time"))
				if not _es_numero(tiempo):
					continue
				var valor: Variant = convertir(propiedad, clave.get("valor", clave.get("value")))
				if valor == null:
					continue
				if not fusionadas.has(propiedad):
					fusionadas[propiedad] = {}
				fusionadas[propiedad][clampf(float(tiempo), 0.0, duracion)] = valor
	for propiedad in fusionadas:
		var tiempos: Array = fusionadas[propiedad].keys()
		tiempos.sort()
		var claves := []
		for tiempo in tiempos:
			claves.append({"tiempo": float(tiempo), "valor": fusionadas[propiedad][tiempo]})
		receta["pistas"].append({"propiedad": propiedad, "claves": claves})
	if receta["pistas"].is_empty():
		return _fallo("La IA no devolvio pistas validas")
	return {"ok": true, "error": "", "receta": receta}
