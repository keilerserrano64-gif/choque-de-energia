extends Node2D
## Efectos de la intro dibujados dentro de la arena (coordenadas lógicas 480x270, la
## arena los escala x2), en pixel art como el resto del juego. Hay dos copias:
##   delante = false: justo después del escenario (oscuridad, luz, aura trasera, ondas, humo de fondo)
##   delante = true:  encima de los luchadores (humo delantero, polvo, chispas, rayos, ojos)
## Todo el estado vive en el controlador de la intro (ctrl); este nodo solo dibuja.

var ctrl: Object
var delante := false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if ctrl == null:
		return
	var t := float(ctrl.get("tiempo"))
	var c: Vector2 = ctrl.get("centro")
	if not delante:
		_oscuridad(float(ctrl.get("oscuridad")))
		_luz(c, float(ctrl.get("luz")), t)
		_anillos(c, ctrl.get("anillos"), t)
		_aura(c, float(ctrl.get("aura")), t, false)
	else:
		_aura(c, float(ctrl.get("aura")) * 0.6, t, true)
	_particulas(ctrl.get("particulas"))
	if delante:
		_rayos(c, float(ctrl.get("rayos")), t)
		_ojos(ctrl.get("ojo"), float(ctrl.get("brillo_ojos")), float(ctrl.get("mira")), t)


func _box(x: float, y: float, w: float, h: float, color: Color) -> void:
	draw_rect(Rect2(roundf(x), roundf(y), roundf(w), roundf(h)).abs(), color)


func _oscuridad(a: float) -> void:
	if a <= 0.0:
		return
	_box(-40, -40, 560, 350, Color(0.02, 0.01, 0.04, a))


## Charco de luz roja y morada detrás de Madara (anillos concéntricos en escalones).
func _luz(c: Vector2, a: float, t: float) -> void:
	if a <= 0.0:
		return
	var latido := 0.85 + 0.15 * sin(t * 6.0)
	for i in range(6):
		var r := 70.0 - i * 10.0
		var col := Color(0.55, 0.08, 0.12).lerp(Color(0.5, 0.25, 0.95), clampf(float(ctrl.get("aura")), 0.0, 1.0))
		col.a = a * 0.09 * latido
		draw_set_transform(c + Vector2(0, -34), 0.0, Vector2(1.0, 1.25))
		draw_circle(Vector2.ZERO, r, col)
	draw_set_transform(Vector2.ZERO)
	# Suelo iluminado.
	_box(c.x - 46, c.y - 2, 92, 4, Color(0.8, 0.25, 0.3, a * 0.25))


## Ondas de energía que se abren por el suelo.
func _anillos(c: Vector2, anillos: Array, t: float) -> void:
	for a in anillos:
		var p := clampf(t - float(a["t"]), 0.0, 1.0)
		var col: Color = a["color"]
		col.a = (1.0 - p) * 0.9
		var r := 10.0 + p * 150.0
		FighterPainter.alpha = 1.0
		FighterPainter.ellipse(self, c + Vector2(0, -1), r, r * 0.22, col, 2.0)
		FighterPainter.ellipse(self, c + Vector2(0, -1), r * 0.8, r * 0.18, Color(1, 1, 1, col.a * 0.5), 1.0)
		# Anillo vertical que sube alrededor del cuerpo.
		if p < 0.5:
			var k := p / 0.5
			FighterPainter.ellipse(self, c + Vector2(0, -34), 24.0 + k * 40.0, 44.0 + k * 50.0, Color(col, (1.0 - k) * 0.6), 1.0)


## Aura de chakra: lenguas de fuego azules y moradas que suben (como las del despertar).
func _aura(c: Vector2, a: float, t: float, frente: bool) -> void:
	if a <= 0.0:
		return
	var alto := 74.0
	var n := 26 if not frente else 12
	for i in range(n):
		var lado := -1.0 if i % 2 == 0 else 1.0
		var fase := fmod(t * (1.3 + (i % 4) * 0.3) + i * 0.173, 1.0)
		var ancho := 15.0 + (i % 5) * 3.0
		if frente:
			ancho *= 0.6
		var lx := c.x + lado * (ancho - fase * 9.0) + sin(t * 7.0 + i) * 1.5
		var ly := c.y - fase * alto * (1.05 + a * 0.25)
		var tam := roundf((5.0 * (1.0 - fase) + 2.0) * (0.7 + a * 0.4))
		var col := Color(0.32, 0.55, 1.0) if i % 3 != 0 else Color(0.58, 0.25, 0.95)
		col.a = a * 0.8 * (1.0 - fase * 0.75)
		# Lengua de fuego afilada: base ancha, punta fina.
		var ancho_l := maxf(1.0, roundf(tam * 0.5))
		_box(lx - ancho_l / 2.0, ly - tam * 1.2, ancho_l, tam * 1.6, col)
		_box(lx - 0.5, ly - tam * 2.2, 1, tam, Color(col, col.a * 0.8))
		_box(lx - 0.5, ly - tam * 0.8, 1, tam * 0.8, Color(0.85, 0.95, 1.0, col.a))
	if not frente:
		# Columna de energía detrás del cuerpo y base brillante.
		var pulso := 0.5 + 0.5 * sin(t * 12.0)
		_box(c.x - 12, c.y - alto - 6, 24, alto + 6, Color(0.4, 0.45, 1.0, a * 0.18))
		_box(c.x - 24, c.y - 3, 48, 3, Color(0.45, 0.55, 1.0, a * (0.45 + 0.25 * pulso)))
		_box(c.x - 14, c.y - 5, 28, 2, Color(0.85, 0.9, 1.0, a * 0.6))


func _particulas(lista: Array) -> void:
	for p in lista:
		if bool(p["delante"]) != delante:
			continue
		var k := float(p["vida"]) / float(p["max"])
		var col: Color = p["color"]
		var pos: Vector2 = p["pos"]
		match String(p["tipo"]):
			"humo":
				var r := float(p["r"])
				col.a *= (1.0 - k) * minf(1.0, k * 6.0 + 0.3)
				# Bocanada en escalones (pixel): cuerpo oscuro y un borde algo más claro arriba.
				var rr := roundf(r)
				_box(pos.x - rr, pos.y - rr * 0.6, rr * 2.0, rr * 1.2, col)
				_box(pos.x - rr * 0.6, pos.y - rr, rr * 1.2, rr * 2.0, col)
				_box(pos.x - rr * 0.6, pos.y - rr, rr * 1.2, 1, Color(col.lightened(0.15), col.a * 0.8))
			"polvo":
				col.a *= minf(1.0, (1.0 - k) * 3.0)
				_box(pos.x, pos.y, 2 if int(pos.x) % 3 == 0 else 1, 1, col)
			_:
				col.a *= 1.0 - k
				_box(pos.x, pos.y, 1, 2, col)


## Rayos morados que saltan del cuerpo durante el estallido de chakra.
func _rayos(c: Vector2, a: float, t: float) -> void:
	if a <= 0.0:
		return
	var semilla := int(t * 14.0)
	for i in range(3):
		var rng := RandomNumberGenerator.new()
		rng.seed = semilla * 7 + i * 131
		if rng.randf() > 0.75:
			continue
		var p := c + Vector2(rng.randf_range(-10, 10), rng.randf_range(-60, -10))
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var pts := PackedVector2Array([p])
		for s in range(5):
			p += dir * rng.randf_range(5, 9) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			pts.append(p.round())
		draw_polyline(pts, Color(0.75, 0.55, 1.0, a * 0.9), 1.0)
		draw_polyline(pts, Color(1, 1, 1, a * 0.5), 1.0)


## Brillo rojo de los ojos (Sharingan): punto, halo y destello en cruz.
func _ojos(o: Vector2, a: float, mira: float, t: float) -> void:
	if a <= 0.0:
		return
	var latido := 0.8 + 0.2 * sin(t * 18.0)
	var largo := roundf(2.0 + a * 4.0 * latido)
	_box(o.x - largo, o.y, largo * 2.0 + 1.0, 1, Color(1.0, 0.2, 0.15, a * 0.45))
	_box(o.x, o.y - 1, 1, 3, Color(1.0, 0.2, 0.15, a * 0.35))
	draw_circle(o + Vector2(0.5, 0.5), 1.8, Color(1.0, 0.1, 0.1, a * 0.3))
	_box(o.x, o.y, 1, 1, Color(1.0, 0.25, 0.2, a))
	# Segundo ojo, un poco más atrás.
	_box(o.x - mira * 3.0, o.y, 1, 1, Color(1.0, 0.25, 0.2, a * 0.85))
