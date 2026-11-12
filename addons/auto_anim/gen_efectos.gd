@tool
extends RefCounted
## Genera EFECTOS 2D para cualquier Node2D, Sprite2D o Control de una escena:
## posición, rotación, escala y color (modulate) a partir de los estilos de AutoAnim2D.
## Se guardan en un AnimationPlayer "AnimEfectos" (librería "efectos").

const AutoAnim2D := preload("res://scripts/data/auto_anim_2d.gd")

## Muestras por segundo de cada pista (las claves se interpolan en línea recta).
const MUESTRAS_POR_SEGUNDO := 30.0

var error := ""


static func es_valido(nodo: Node) -> bool:
	return nodo is Node2D or nodo is Control


## mira_izquierda: el nodo mira hacia -X, así que "hacia delante" se invierte.
func generar(nodo: Node, estilo: String, duracion: float, intensidad: float, mira_izquierda: bool) -> Animation:
	error = ""
	if not es_valido(nodo):
		error = "%s no es un nodo 2D ni de interfaz" % nodo.name
		return null
	var clip := AutoAnim2D.generar(estilo, duracion, intensidad)
	if clip.is_empty():
		error = "Estilo desconocido: " + estilo
		return null
	var lado := -1.0 if mira_izquierda else 1.0
	var item := nodo as CanvasItem
	var pos: Vector2 = nodo.get("position")
	var rot: float = float(nodo.get("rotation"))
	var esc: Vector2 = nodo.get("scale")
	var mod: Color = item.modulate

	var anim := Animation.new()
	anim.length = float(clip["duracion"])
	anim.loop_mode = Animation.LOOP_LINEAR if bool(clip["loop"]) else Animation.LOOP_NONE
	var n := maxi(8, int(ceilf(anim.length * MUESTRAS_POR_SEGUNDO)))
	var muestras: Array = []
	for k in n + 1:
		muestras.append(AutoAnim2D.muestrear(clip, anim.length * float(k) / n))

	_pista_si_cambia(anim, "position", muestras, n, func(m: Dictionary) -> Variant:
		var d: Vector2 = m["desp"]
		return pos + Vector2(d.x * lado, d.y) * esc.abs())
	_pista_si_cambia(anim, "rotation", muestras, n, func(m: Dictionary) -> Variant:
		return rot + deg_to_rad(float(m["rot"])) * lado)
	_pista_si_cambia(anim, "scale", muestras, n, func(m: Dictionary) -> Variant:
		return esc * (m["escala"] as Vector2))
	_pista_si_cambia(anim, "modulate", muestras, n, func(m: Dictionary) -> Variant:
		return mod * (m["color"] as Color))
	return anim


## Añade la pista solo si el estilo cambia esa propiedad (neutro = valor sin cambio).
func _pista_si_cambia(anim: Animation, prop: String, muestras: Array, n: int, valor: Callable) -> void:
	var clave := {"position": "desp", "rotation": "rot", "scale": "escala", "modulate": "color"}[prop] as String
	var usada := false
	for m in muestras:
		if (m as Dictionary)[clave] != AutoAnim2D.NEUTRO[clave]:
			usada = true
			break
	if not usada:
		return
	var pista := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pista, NodePath(".:" + prop))
	anim.track_set_interpolation_type(pista, Animation.INTERPOLATION_LINEAR)
	for k in n + 1:
		anim.track_insert_key(pista, anim.length * float(k) / n, valor.call(muestras[k]))
