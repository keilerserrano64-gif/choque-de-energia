extends Node2D
## Susanoo Perfecto de Madara, dibujado con código (coordenadas de la arena 480x270).
## El origen es la base del Susanoo en el suelo; +x mira hacia el rival (la escala x del
## nodo pone el lado). Va dentro de un CanvasGroup para que su transparencia sea uniforme.
## Lo controla el definitivo con: aparicion (0-1), alzar (0-1), tajo (0-1), objetivo
## (distancia al rival en el eje x local) y brillo.

const ALTO := 168.0
const AZUL := Color(0.27, 0.48, 1.0)
const CLARO := Color(0.62, 0.82, 1.0)
const OSCURO := Color(0.1, 0.2, 0.62)
const BORDE := Color(0.86, 0.95, 1.0)
const MORADO := Color(0.55, 0.3, 1.0)

var aparicion := 0.0
var alzar := 0.0
var tajo := 0.0
var objetivo := 200.0
var brillo := 0.0
var tiempo := 0.0
var _rastro: Array = []  ## ángulos y largos de la espada en los últimos cuadros (estela)


func _process(delta: float) -> void:
	tiempo += delta
	var e := espada()
	_rastro.push_front(e)
	if _rastro.size() > 6:
		_rastro.pop_back()
	queue_redraw()


## Hombro del brazo de la espada.
func hombro() -> Vector2:
	return Vector2(40, -116)


## Mano y ángulo/largo de la espada según alzar y tajo: {mano, angulo, largo}.
func espada() -> Dictionary:
	var h := hombro()
	var mano_reposo := h + Vector2(30, 26)
	var mano_alta := h + Vector2(-4, -58)
	var mano_tajo := h + Vector2(46, 32)
	var mano := mano_reposo.lerp(mano_alta, alzar).lerp(mano_tajo, tajo)
	# Al final del tajo la punta toca el suelo junto al rival.
	var dx := maxf(objetivo - mano_tajo.x, 60.0)
	var ang_tajo := atan2(-mano_tajo.y, dx)
	var largo_tajo := clampf(Vector2(dx, -mano_tajo.y).length() + 6.0, 140.0, 300.0)
	var ang := lerp_angle(lerp_angle(-0.35, -2.05, alzar), ang_tajo, tajo)
	var largo := lerpf(lerpf(170.0, 185.0, alzar), largo_tajo, tajo)
	return {"mano": mano, "angulo": ang, "largo": largo}


func punta() -> Vector2:
	var e := espada()
	return (e["mano"] as Vector2) + Vector2.from_angle(float(e["angulo"])) * float(e["largo"])


func _draw() -> void:
	if aparicion <= 0.0:
		return
	var s1 := clampf(aparicion * 3.0, 0.0, 1.0)        # esqueleto
	var s2 := clampf(aparicion * 3.0 - 1.0, 0.0, 1.0)  # cuerpo de chakra
	var s3 := clampf(aparicion * 3.0 - 2.0, 0.0, 1.0)  # armadura, ojos y espada
	var t := tiempo
	_llamas_base(s1, t)
	_brazo_trasero(s2, s3)
	_cuerpo(s2, s3, t)
	_esqueleto(s1 * (1.0 - s2 * 0.7))
	_cabeza(s1, s2, s3, t)
	_estela(s3)
	_brazo_espada(s2, s3, t)


func _poli(puntos: Array, color: Color) -> void:
	if color.a <= 0.0:
		return
	var p := PackedVector2Array()
	for q in puntos:
		p.append((q as Vector2).round())
	draw_colored_polygon(p, color)


func _contorno(puntos: Array, color: Color, ancho := 1.0) -> void:
	if color.a <= 0.0:
		return
	var p := PackedVector2Array()
	for q in puntos:
		p.append((q as Vector2).round())
	p.append((puntos[0] as Vector2).round())
	draw_polyline(p, color, ancho)


## Base de llamas de chakra: el Susanoo surge de la cintura para arriba.
func _llamas_base(a: float, t: float) -> void:
	for i in range(22):
		var fase := fmod(t * (1.1 + (i % 4) * 0.25) + i * 0.137, 1.0)
		var x := -58.0 + i * 5.6 + sin(t * 3.0 + i) * 2.0
		var alto := (26.0 + (i % 5) * 7.0) * (1.0 - fase * 0.6)
		var y := -fase * 22.0
		var col := (AZUL if i % 3 else MORADO)
		col.a = a * 0.75 * (1.0 - fase * 0.7)
		_poli([Vector2(x - 4, y), Vector2(x + 4, y), Vector2(x + 1, y - alto), Vector2(x - 1, y - alto)], col)
	_poli([Vector2(-62, 0), Vector2(62, 0), Vector2(54, -14), Vector2(-54, -14)], Color(CLARO, a * 0.35))


func _esqueleto(a: float) -> void:
	if a <= 0.0:
		return
	var col := Color(BORDE, a)
	# Columna.
	draw_line(Vector2(0, -30), Vector2(2, -130), col, 2.0)
	# Costillas curvas.
	for i in range(6):
		var y := -60.0 - i * 11.0
		var ancho := 30.0 + sin(float(i) / 5.0 * PI) * 16.0
		var pts := PackedVector2Array()
		for k in range(9):
			var u := float(k) / 8.0
			pts.append(Vector2(lerpf(-ancho, ancho, u), y + sin(u * PI) * 6.0).round())
		draw_polyline(pts, col, 1.0)
	# Clavículas y pelvis.
	draw_line(Vector2(-46, -122), Vector2(46, -120), col, 2.0)
	_contorno([Vector2(-26, -34), Vector2(26, -34), Vector2(16, -44), Vector2(-16, -44)], col)


func _cuerpo(s2: float, s3: float, t: float) -> void:
	if s2 <= 0.0:
		return
	var pulso := 0.5 + 0.5 * sin(t * 4.0)
	# Torso de chakra.
	var torso := [Vector2(-30, -20), Vector2(30, -20), Vector2(46, -78), Vector2(50, -118), Vector2(-50, -120), Vector2(-46, -78)]
	_poli(torso, Color(AZUL, s2 * 0.85))
	_poli([Vector2(-22, -24), Vector2(22, -24), Vector2(32, -76), Vector2(-32, -76)], Color(OSCURO, s2 * 0.35))
	_contorno(torso, Color(BORDE, s2 * (0.6 + 0.3 * pulso)))
	if s3 <= 0.0:
		return
	# Coraza: placas del pecho, faldones y hombreras.
	var placa := Color(CLARO, s3 * 0.9)
	_poli([Vector2(-38, -82), Vector2(38, -82), Vector2(44, -114), Vector2(-44, -116)], Color(AZUL.darkened(0.15), s3))
	_contorno([Vector2(-38, -82), Vector2(38, -82), Vector2(44, -114), Vector2(-44, -116)], placa, 2.0)
	for i in range(3):
		var y := -88.0 - i * 9.0
		draw_line(Vector2(-34 + i * 2, y).round(), Vector2(34 - i * 2, y).round(), Color(BORDE, s3 * 0.55), 1.0)
	for i in range(4):
		var x := -30.0 + i * 16.0
		_poli([Vector2(x, -22), Vector2(x + 14, -22), Vector2(x + 12, -46), Vector2(x + 2, -46)], Color(AZUL.darkened(0.25), s3))
		_contorno([Vector2(x, -22), Vector2(x + 14, -22), Vector2(x + 12, -46), Vector2(x + 2, -46)], Color(CLARO, s3 * 0.7))
	for lado in [-1.0, 1.0]:
		var c := Vector2(50.0 * lado, -118.0)
		draw_circle(c.round(), 22.0, Color(AZUL.darkened(0.1), s3))
		draw_arc(c.round(), 22.0, PI, TAU, 18, Color(BORDE, s3), 2.0)
		draw_arc(c.round(), 15.0, PI, TAU, 14, Color(CLARO, s3 * 0.7), 1.0)
		# Placas en escalón bajo la hombrera.
		for k in range(3):
			draw_line((c + Vector2(-16, 6 + k * 6)).round(), (c + Vector2(16, 6 + k * 6)).round(), Color(CLARO, s3 * 0.6), 2.0)


func _cabeza(s1: float, s2: float, s3: float, t: float) -> void:
	var c := Vector2(6, -146)
	if s1 > 0.0 and s2 < 1.0:
		# Cráneo del esqueleto.
		draw_circle(c, 13.0, Color(BORDE, s1 * 0.25 * (1.0 - s2)))
		draw_arc(c, 13.0, 0.0, TAU, 20, Color(BORDE, s1 * (1.0 - s2)), 1.0)
	if s2 <= 0.0:
		return
	# Cabeza con yelmo tengu: cresta, cuernos y máscara con mandíbula.
	var yelmo := [c + Vector2(-16, 8), c + Vector2(-17, -8), c + Vector2(-8, -18), c + Vector2(10, -18), c + Vector2(20, -6), c + Vector2(22, 6), c + Vector2(14, 14), c + Vector2(-8, 14)]
	_poli(yelmo, Color(AZUL, s2))
	_contorno(yelmo, Color(BORDE, s2 * 0.8))
	if s3 > 0.0:
		var cresta := Color(CLARO, s3)
		_poli([c + Vector2(-6, -18), c + Vector2(2, -18), c + Vector2(-14, -40), c + Vector2(-16, -36)], cresta)
		_poli([c + Vector2(4, -18), c + Vector2(12, -16), c + Vector2(30, -34), c + Vector2(26, -36)], cresta)
		_poli([c + Vector2(-17, -6), c + Vector2(-10, -12), c + Vector2(-34, -20), c + Vector2(-32, -14)], Color(CLARO, s3 * 0.8))
		# Máscara: nariz larga y mandíbula.
		_poli([c + Vector2(14, -2), c + Vector2(30, 4), c + Vector2(16, 8)], Color(CLARO, s3))
		_poli([c + Vector2(-6, 10), c + Vector2(18, 10), c + Vector2(12, 18), c + Vector2(-2, 18)], Color(AZUL.darkened(0.3), s3))
		for k in range(4):
			draw_line((c + Vector2(-2 + k * 5, 11)).round(), (c + Vector2(-2 + k * 5, 17)).round(), Color(BORDE, s3 * 0.7), 1.0)
	# Ojos brillantes.
	var ojo := 0.6 + 0.4 * sin(t * 9.0)
	var a := maxf(s2 * 0.6, s3) * ojo
	_poli([c + Vector2(4, -4), c + Vector2(16, -6), c + Vector2(15, -2), c + Vector2(5, -1)], Color(1.0, 0.95, 0.75, a))
	_poli([c + Vector2(-10, -3), c + Vector2(0, -5), c + Vector2(0, -1), c + Vector2(-9, 0)], Color(1.0, 0.95, 0.75, a * 0.8))
	draw_circle((c + Vector2(10, -4)).round(), 5.0 + brillo * 3.0, Color(1.0, 0.95, 0.7, a * 0.25))


func _brazo_trasero(s2: float, s3: float) -> void:
	if s2 <= 0.0:
		return
	var h := Vector2(-44, -114)
	var codo := h + Vector2(-10, 36)
	var mano := codo + Vector2(12, 30)
	draw_line(h, codo, Color(AZUL.darkened(0.2), s2), 14.0)
	draw_line(codo, mano, Color(AZUL.darkened(0.2), s2), 12.0)
	if s3 > 0.0:
		draw_line(codo, mano, Color(CLARO, s3 * 0.5), 2.0)


func _brazo_espada(s2: float, s3: float, t: float) -> void:
	if s2 <= 0.0:
		return
	var e := espada()
	var h := hombro()
	var mano: Vector2 = e["mano"]
	var medio := (h + mano) * 0.5
	var normal := (mano - h).orthogonal().normalized()
	var codo := medio + normal * 12.0 * (1.0 - alzar * 0.5)
	draw_line(h.round(), codo.round(), Color(AZUL, s2), 15.0)
	draw_line(codo.round(), mano.round(), Color(AZUL, s2), 13.0)
	if s3 > 0.0:
		# Brazal de armadura y puño.
		draw_line(codo.lerp(mano, 0.2).round(), codo.lerp(mano, 0.85).round(), Color(CLARO, s3 * 0.8), 5.0)
		draw_circle(mano.round(), 8.0, Color(AZUL.darkened(0.1), s3))
		draw_arc(mano.round(), 8.0, 0.0, TAU, 12, Color(BORDE, s3), 1.0)
		_hoja(mano, float(e["angulo"]), float(e["largo"]), s3, t)


## Espada gigante de chakra: empuñadura, guarda y hoja que se afina con núcleo blanco.
func _hoja(mano: Vector2, ang: float, largo: float, a: float, t: float) -> void:
	var d := Vector2.from_angle(ang)
	var n := d.orthogonal()
	var base := mano - d * 14.0
	draw_line(base.round(), (mano + d * 6.0).round(), Color(OSCURO, a), 6.0)  # empuñadura
	_poli([mano + d * 6.0 + n * 12.0, mano + d * 10.0 + n * 12.0, mano + d * 10.0 - n * 12.0, mano + d * 6.0 - n * 12.0], Color(CLARO, a))
	var raiz := mano + d * 10.0
	var punta_p := mano + d * largo
	var ancho := 9.0 + brillo * 2.0
	var hoja := [raiz + n * ancho, punta_p - d * 20.0 + n * ancho * 0.7, punta_p, punta_p - d * 20.0 - n * ancho * 0.7, raiz - n * ancho]
	draw_colored_polygon(PackedVector2Array(hoja), Color(AZUL.lightened(0.15), a * 0.9))
	var parpadeo := 0.8 + 0.2 * sin(t * 30.0)
	_poli([raiz + n * 3.0, punta_p - d * 14.0 + n * 2.0, punta_p - d * 4.0, punta_p - d * 14.0 - n * 2.0, raiz - n * 3.0], Color(1, 1, 1, a * parpadeo))
	_contorno(hoja, Color(BORDE, a), 1.0)
	# Halo de la hoja.
	draw_line(raiz.round(), punta_p.round(), Color(CLARO, a * 0.2), ancho * 3.0)


## Estela de chakra del tajo: abanico entre las posiciones recientes de la hoja.
func _estela(a: float) -> void:
	if a <= 0.0 or _rastro.size() < 2 or tajo <= 0.02 or tajo >= 0.999:
		return
	for i in range(_rastro.size() - 1):
		var e0: Dictionary = _rastro[i]
		var e1: Dictionary = _rastro[i + 1]
		var m0: Vector2 = e0["mano"]
		var m1: Vector2 = e1["mano"]
		var p0 := m0 + Vector2.from_angle(float(e0["angulo"])) * float(e0["largo"])
		var p1 := m1 + Vector2.from_angle(float(e1["angulo"])) * float(e1["largo"])
		var k := 1.0 - float(i) / _rastro.size()
		# Dos triángulos en vez de un cuadrilátero: si la mano cruza la estela el cuadrilátero
		# se retuerce y Godot no puede triangularlo («Invalid polygon data»).
		_triangulo(m0, p0, p1, Color(CLARO, a * 0.45 * k))
		_triangulo(m0, p1, m1, Color(CLARO, a * 0.45 * k))
		draw_line(p0, p1, Color(1, 1, 1, a * 0.8 * k), 3.0)


func _triangulo(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	if absf((b - a).cross(c - a)) < 0.5:
		return  # sin área: nada que dibujar
	draw_colored_polygon(PackedVector2Array([a, b, c]), color)
