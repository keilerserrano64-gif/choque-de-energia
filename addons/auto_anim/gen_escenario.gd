@tool
extends RefCounted
## Genera animaciones de ESCENARIO 2D: objetos que flotan o se balancean, luces 2D,
## plataformas, puertas, temblor de cámara y ciclo de día/noche.
## Cada objeto recibe su propio AnimationPlayer ("AnimEscenario").
## Las animaciones en bucle se ponen en autoplay: arrancan solas al jugar.
##
## Sirve con Node2D, Sprite2D, Control, PointLight2D/DirectionalLight2D (energía),
## CanvasModulate (día/noche) y Camera2D (el temblor mueve su offset).

const U = preload("util.gd")

const DURACIONES := {
	"flotar": 3.0,
	"girar": 4.0,
	"cristal": 3.0,
	"balancear": 3.0,
	"parpadeo_luz": 1.5,
	"pulso_luz": 2.0,
	"plataforma": 4.0,
	"puerta": 1.0,
	"temblor": 0.5,
	"dia_noche": 60.0,
	"aparecer": 0.6,
}
const UNA_VEZ := ["puerta", "temblor", "aparecer"]
const AYUDA := {
	"flotar": "Sube y baja suave (nubes, cristales, islas).",
	"girar": "Da vueltas sin parar (aspas, engranajes, monedas).",
	"cristal": "Flota y brilla (objetos mágicos).",
	"balancear": "Se mece (árboles, banderas, lámparas colgantes).",
	"parpadeo_luz": "Luz que tiembla: antorchas o fuego. Mejor en una Light2D.",
	"pulso_luz": "Brillo que sube y baja suave. Mejor en una Light2D.",
	"plataforma": "Va y vuelve en horizontal.",
	"puerta": "Se abre deslizándose hacia arriba con un rebote.",
	"temblor": "Sacudida que se apaga. En una Camera2D mueve la cámara.",
	"dia_noche": "Ciclo de día, atardecer y noche. Úsalo en un CanvasModulate.",
	"aparecer": "Crece desde cero con un pequeño rebote.",
}

var error := ""


func es_loop(tipo: String) -> bool:
	return not (tipo in UNA_VEZ)


static func es_valido(nodo: Node) -> bool:
	return nodo is CanvasItem or nodo is CanvasModulate


func generar(nodo: Node, tipo: String, duracion: float, i: float) -> Animation:
	error = ""
	if not es_valido(nodo):
		error = "%s no es un nodo 2D" % nodo.name
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(nodo.get_path() if nodo.is_inside_tree() else NodePath(nodo.name)) + tipo)
	var loop := es_loop(tipo)
	# Variar un poco la duración para que varios objetos no se muevan sincronizados.
	if loop and tipo != "dia_noche":
		duracion *= rng.randf_range(0.85, 1.15)

	var anim := Animation.new()
	anim.length = duracion
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE

	var tiene_pos := nodo is Node2D or nodo is Control
	var pos: Vector2 = nodo.get("position") if tiene_pos else Vector2.ZERO
	var rot: float = float(nodo.get("rotation")) if tiene_pos else 0.0
	var esc: Vector2 = nodo.get("scale") if tiene_pos else Vector2.ONE
	var luz := nodo as Light2D
	var item := nodo as CanvasItem
	var camara := nodo as Camera2D

	match tipo:
		"flotar":
			if not _requiere_pos(nodo, tiene_pos): return null
			_pista(anim, "position", 16, func(p): return pos + Vector2.UP * sin(TAU * p) * 6.0 * i)

		"girar":
			if not _requiere_pos(nodo, tiene_pos): return null
			_pista(anim, "rotation", 4, func(p): return rot + TAU * p)

		"cristal":  # flotar + brillo
			if not _requiere_pos(nodo, tiene_pos): return null
			_pista(anim, "position", 16, func(p): return pos + Vector2.UP * sin(TAU * p) * 6.0 * i)
			if item != null:
				var m := item.modulate
				_pista(anim, "modulate", 16, func(p): return m * _brillo(0.35 * i * (0.5 + 0.5 * sin(TAU * p))))

		"balancear":  # árboles, banderas, lámparas colgantes
			if not _requiere_pos(nodo, tiene_pos): return null
			var a := deg_to_rad(4.0 * i)
			_pista(anim, "rotation", 16, func(p): return rot + sin(TAU * p) * a)

		"parpadeo_luz":  # antorchas, fuego, luces fallando
			var vals: Array[float] = []
			for k in 12:
				vals.append(rng.randf_range(1.0 - 0.5 * minf(i, 1.8), 1.0 + 0.2 * i))
			vals.append(vals[0])
			if luz != null:
				var e := luz.energy
				_pista(anim, "energy", 12, func(p): return maxf(0.0, e * vals[roundi(p * 12)]))
			elif item != null:
				var m := item.modulate
				_pista(anim, "modulate", 12, func(p): return m * _brillo(vals[roundi(p * 12)] - 1.0))
			else:
				error = "%s no tiene luz ni color que animar" % nodo.name
				return null

		"pulso_luz":  # brillo que sube y baja suave (cristales mágicos)
			if luz != null:
				var e := luz.energy
				_pista(anim, "energy", 16, func(p): return maxf(0.0, e * (1.0 + 0.4 * i * sin(TAU * p))))
			elif item != null:
				var m := item.modulate
				_pista(anim, "modulate", 16, func(p): return m * _brillo(0.3 * i * sin(TAU * p)))
			else:
				error = "%s no tiene luz ni color que animar" % nodo.name
				return null

		"plataforma":  # va y vuelve en horizontal
			if not _requiere_pos(nodo, tiene_pos): return null
			var dist := 64.0 * i
			_pista(anim, "position", 24, func(p): return pos + Vector2.RIGHT * dist * smoothstep(0.0, 1.0, 1.0 - absf(2.0 * p - 1.0)))

		"puerta":  # se desliza hacia arriba con un pequeño rebote
			if not _requiere_pos(nodo, tiene_pos): return null
			var alto := 48.0 * i
			_pista(anim, "position", 20, func(p): return pos + Vector2.UP * alto * U.curva(p, [[0.0, 0.0], [0.7, 1.05], [0.85, 0.97], [1.0, 1.0]]))

		"temblor":  # en una Camera2D mueve el offset; en otro nodo, la posición
			var offs: Array[Vector2] = []
			for k in 21:
				offs.append(Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
			if camara != null:
				var o := camara.offset
				_pista(anim, "offset", 20, func(p): return o + offs[roundi(p * 20)] * 6.0 * i * (1.0 - p))
			else:
				if not _requiere_pos(nodo, tiene_pos): return null
				_pista(anim, "position", 20, func(p): return pos + offs[roundi(p * 20)] * 4.0 * i * (1.0 - p))
				_pista(anim, "rotation", 20, func(p): return rot + offs[20 - roundi(p * 20)].x * deg_to_rad(2.0 * i) * (1.0 - p))

		"dia_noche":  # mejor en un CanvasModulate (tiñe toda la escena)
			var dia := Color.WHITE
			var tarde := Color(1.0, 0.72, 0.55)
			var noche := Color(0.35, 0.42, 0.7)
			var ciclo := func(p: float) -> Color:
				return U.color_curva(p, [[0.0, dia], [0.4, dia], [0.5, tarde], [0.6, noche], [0.9, noche], [1.0, dia]])
			if nodo is CanvasModulate:
				_pista(anim, "color", 48, ciclo)
			elif luz != null:
				var e := luz.energy
				_pista(anim, "energy", 48, func(p): return e * clampf(1.2 - 0.9 * (1.0 - (ciclo.call(p) as Color).b), 0.1, 1.2))
			elif item != null:
				var m := item.modulate
				_pista(anim, "modulate", 48, func(p): return m * (ciclo.call(p) as Color))

		"aparecer":
			if not _requiere_pos(nodo, tiene_pos): return null
			_pista(anim, "scale", 20, func(p): return esc * maxf(0.01, U.curva(p, [[0.0, 0.01], [0.6, 1.0 + 0.2 * i], [0.8, 0.95], [1.0, 1.0]])))

		_:
			error = "Tipo desconocido: " + tipo
			return null

	return anim


func _requiere_pos(nodo: Node, tiene_pos: bool) -> bool:
	if not tiene_pos:
		error = "%s no se puede mover (usa un Node2D, Sprite2D o Control)" % nodo.name
	return tiene_pos


static func _brillo(b: float) -> Color:
	return Color(1.0 + b, 1.0 + b, 1.0 + b)


## Crea una pista muestreando la función f(p) con p de 0 a 1.
func _pista(anim: Animation, prop: String, n: int, f: Callable) -> void:
	var t := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t, NodePath(".:" + prop))
	anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
	for k in n + 1:
		var p := float(k) / n
		anim.track_insert_key(t, p * anim.length, f.call(p))
