extends Node2D
## Efectos del definitivo de Madara dentro de la arena (coordenadas lógicas 480x270),
## en pixel art. Dos copias:
##   delante = false: tras el escenario (cielo, nubes, meteoritos, rocas, cráteres, explosión trasera)
##   delante = true:  sobre los luchadores (polvo que cae, chispas, escombros, explosión delantera, ojos)
## El estado vive en el controlador (ctrl); aquí solo se dibuja.

var ctrl: Object
var delante := false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if ctrl == null:
		return
	var t := float(ctrl.get("tiempo"))
	if not delante:
		_cielo(float(ctrl.get("oscuridad")), float(ctrl.get("rojo")))
		_luz_chakra(ctrl.get("centro"), float(ctrl.get("chakra")), t)
		_nubes(float(ctrl.get("nubes")), t)
		for m in ctrl.get("meteoritos"):
			if bool(m["visible"]):
				_meteoro(m, t)
		_rocas(ctrl.get("rocas"), t)
		_crateres(ctrl.get("crateres"), t)
		for e in ctrl.get("explosiones"):
			_explosion(e, t, false)
		_ondas(ctrl.get("ondas"), t)
	else:
		for e in ctrl.get("explosiones"):
			_explosion(e, t, true)
	_sprites(t)
	_particulas(ctrl.get("particulas"))
	if delante:
		_ojos(ctrl.get("ojo"), float(ctrl.get("brillo_ojos")), float(ctrl.get("mira")), t)


func _box(x: float, y: float, w: float, h: float, color: Color) -> void:
	if color.a > 0.0:
		draw_rect(Rect2(roundf(x), roundf(y), roundf(w), roundf(h)).abs(), color)


## Oscuridad y cielo que se vuelve rojo/naranja por bandas (degradado pixelado).
func _cielo(oscuridad: float, rojo: float) -> void:
	if oscuridad <= 0.0 and rojo <= 0.0:
		return
	for i in range(14):
		var y := -60.0 + i * 24.0
		var k := float(i) / 13.0
		var col := Color(0.02, 0.01, 0.04).lerp(Color(0.32, 0.07, 0.03).lerp(Color(0.55, 0.2, 0.05), k), rojo)
		col.a = clampf(oscuridad * (0.55 + 0.35 * (1.0 - k)) + rojo * 0.25 * k, 0.0, 0.92)
		_box(-60, y, 600, 25, col)


func _luz_chakra(c: Vector2, a: float, t: float) -> void:
	if a <= 0.0:
		return
	var latido := 0.85 + 0.15 * sin(t * 7.0)
	for i in range(5):
		draw_set_transform(c + Vector2(0, -40), 0.0, Vector2(1.0, 1.3))
		draw_circle(Vector2.ZERO, 80.0 - i * 13.0, Color(0.35, 0.3, 1.0, a * 0.07 * latido))
	draw_set_transform(Vector2.ZERO)


## Nubes gigantes que bajan del cielo, iluminadas por debajo de naranja.
func _nubes(a: float, t: float) -> void:
	if a <= 0.0:
		return
	var bajada := lerpf(-90.0, 0.0, a)
	for capa in range(3):
		var y := 6.0 + capa * 22.0 + bajada
		var vel := 4.0 + capa * 3.0
		for i in range(10):
			var x := fmod(i * 61.0 + t * vel * (1.0 if capa % 2 == 0 else -1.0) + capa * 37.0, 620.0) - 70.0
			var r := 26.0 + ((i * 7 + capa * 3) % 5) * 6.0
			var base := Color(0.1, 0.06, 0.09).lerp(Color(0.2, 0.1, 0.08), capa / 2.0)
			draw_circle(Vector2(x, y).round(), r, Color(base, a * 0.92))
			draw_circle(Vector2(x + r * 0.3, y + r * 0.45).round(), r * 0.7, Color(0.55, 0.18, 0.06, a * 0.35 * float(ctrl.get("rojo"))))
	_box(-60, -60, 600, 70 + bajada, Color(0.06, 0.03, 0.05, a * 0.95))


## Meteorito gigante: humo detrás, fuego por delante, roca con cráteres y grietas de lava.
func _meteoro(m: Dictionary, t: float) -> void:
	var c: Vector2 = m["pos"]
	var r := float(m["radio"])
	var dir: Vector2 = (m["dir"] as Vector2).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(m["semilla"])
	var atras := -dir
	# Estela de humo.
	for i in range(12):
		var k := float(i) / 11.0
		var p := c + atras * r * (0.6 + k * 3.2) + Vector2(sin(t * 2.0 + i) * 4.0, cos(t * 1.7 + i) * 4.0)
		draw_circle(p.round(), r * (0.75 - k * 0.3), Color(0.16, 0.12, 0.12, 0.55 * (1.0 - k)))
	# Resplandor y llamas que barren hacia atrás.
	draw_circle(c.round(), r * 1.35, Color(1.0, 0.45, 0.1, 0.18))
	draw_circle(c.round(), r * 1.16, Color(1.0, 0.55, 0.15, 0.3))
	for i in range(18):
		var ang := atras.angle() + (float(i) / 17.0 - 0.5) * PI * 1.25
		var fase := fmod(t * 2.5 + i * 0.37, 1.0)
		var largo := r * (0.5 + 0.9 * (1.0 - absf(float(i) / 17.0 - 0.5) * 1.6)) * (0.7 + 0.3 * sin(t * 13.0 + i))
		var raiz := c + Vector2.from_angle(ang + PI) * r * 0.2 + Vector2.from_angle(ang) * r * 0.85
		var punta := raiz + Vector2.from_angle(ang) * largo * (0.6 + fase * 0.4)
		var lado := Vector2.from_angle(ang).orthogonal() * r * 0.12
		draw_colored_polygon(PackedVector2Array([raiz + lado, punta, raiz - lado]), Color(1.0, 0.5 + 0.3 * fase, 0.12, 0.8))
	# Roca: el meteorito de lava de la hoja (si está importado), girando despacio.
	var efx: Dictionary = ctrl.get("efx")
	if efx.has("meteoro_3"):
		var e: Dictionary = efx["meteoro_3"]
		var tex: Texture2D = e["tex"]
		var lado := maxf(tex.get_width(), tex.get_height())
		var esc := (r * 2.3) / lado
		draw_set_transform(c, t * 0.35 + float(m["semilla"]), Vector2(esc, esc))
		draw_texture(tex, -(e["ancla"] as Vector2))
		draw_set_transform(Vector2.ZERO)
		# Brillo de la cara que cae.
		draw_circle((c + dir * r * 0.55).round(), r * 0.35, Color(1.0, 0.6, 0.2, 0.25))
		return
	# Roca irregular.
	var roca := Color(0.2, 0.14, 0.13)
	draw_circle(c.round(), r, roca)
	for i in range(9):
		var ang2 := rng.randf() * TAU
		draw_circle((c + Vector2.from_angle(ang2) * r * 0.82).round(), r * rng.randf_range(0.22, 0.34), roca)
	# Cara iluminada por el fuego (del lado hacia donde cae) y sombra del otro.
	draw_circle((c + dir * r * 0.18).round(), r * 0.8, Color(0.42, 0.22, 0.14))
	draw_circle((c + dir * r * 0.3).round(), r * 0.55, Color(0.58, 0.3, 0.16))
	draw_circle((c + atras * r * 0.35).round(), r * 0.55, Color(0.12, 0.08, 0.08, 0.7))
	# Cráteres.
	for i in range(7):
		var p2 := c + Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.1, 0.7)
		var rr := r * rng.randf_range(0.07, 0.15)
		draw_circle(p2.round(), rr, Color(0.1, 0.06, 0.06, 0.85))
		draw_arc(p2.round(), rr, PI * 0.9, PI * 1.9, 8, Color(0.7, 0.42, 0.25, 0.7), 1.0)
	# Grietas de lava que laten.
	var latido := 0.7 + 0.3 * sin(t * 6.0 + float(m["semilla"]))
	for i in range(6):
		var p3 := c + Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.0, 0.5)
		var pts := PackedVector2Array([p3.round()])
		var ang3 := rng.randf() * TAU
		for k in range(5):
			ang3 += rng.randf_range(-0.9, 0.9)
			p3 += Vector2.from_angle(ang3) * r * rng.randf_range(0.1, 0.2)
			if p3.distance_to(c) > r * 0.92:
				break
			pts.append(p3.round())
		if pts.size() > 1:
			draw_polyline(pts, Color(1.0, 0.38, 0.06, 0.9 * latido), 3.0)
			draw_polyline(pts, Color(1.0, 0.85, 0.4, latido), 1.0)


func _rocas(lista: Array, t: float) -> void:
	var efx: Dictionary = ctrl.get("efx")
	var cuenta := 0
	for roca in lista:
		cuenta += 1
		var nombre := "roca_%d" % (1 + cuenta % 6)
		if efx.has(nombre):
			var e: Dictionary = efx[nombre]
			var tam := float(roca["tam"])
			draw_set_transform(roca["pos"], t * float(roca["giro"]), Vector2.ONE * (tam / 4.0) * 0.5)
			draw_texture(e["tex"], -(e["ancla"] as Vector2), Color(1, 1, 1, float(roca.get("alfa", 1.0))))
			draw_set_transform(Vector2.ZERO)
			continue
		var p: Vector2 = roca["pos"]
		var s := float(roca["tam"])
		var a := float(roca.get("alfa", 1.0))
		var giro := t * float(roca["giro"])
		var pts := PackedVector2Array()
		for k in range(5):
			pts.append((p + Vector2.from_angle(giro + k * TAU / 5.0) * s * (0.8 + 0.25 * ((k * 3) % 2))).round())
		draw_colored_polygon(pts, Color(0.32, 0.25, 0.22, a))
		_box(p.x - s * 0.4, p.y - s * 0.5, s * 0.6, 1, Color(0.75, 0.45, 0.3, a * 0.8))


func _crateres(lista: Array, t: float) -> void:
	for c in lista:
		var x := float(c["x"])
		var w := float(c["ancho"])
		var y := CombatSim.FLOOR + 1.0
		draw_set_transform(Vector2(x, y), 0.0, Vector2(1.0, 0.18))
		draw_circle(Vector2.ZERO, w, Color(0.06, 0.03, 0.03, 0.9))
		draw_arc(Vector2.ZERO, w, 0.0, TAU, 32, Color(1.0, 0.45, 0.1, 0.7 + 0.2 * sin(t * 5.0)), 6.0)
		draw_set_transform(Vector2.ZERO)
		# Fuegos sueltos en el borde.
		for i in range(6):
			var fx := x + (float(i) / 5.0 - 0.5) * w * 1.6
			var alto := 4.0 + 3.0 * sin(t * 11.0 + i * 1.7)
			_box(fx - 1, y - alto - 1, 3, alto, Color(1.0, 0.55, 0.15, 0.85))
			_box(fx, y - alto * 0.6 - 1, 1, alto * 0.6, Color(1.0, 0.9, 0.5, 0.9))


## Explosión: destello, bola de fuego con bultos, humo que sube y paredes de polvo.
func _explosion(e: Dictionary, t: float, frente: bool) -> void:
	var edad := t - float(e["t"])
	if edad < 0.0 or edad > 4.0:
		return
	var c: Vector2 = e["pos"]
	var esc := float(e["escala"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e["semilla"])
	if not frente:
		# Polvo bajo y ancho que se expande por el suelo.
		var ancho := (40.0 + edad * 150.0) * esc
		for i in range(10):
			var px := c.x + (float(i) / 9.0 - 0.5) * ancho * 2.0
			var r := (12.0 + rng.randf() * 10.0) * esc * minf(1.0, edad * 2.0 + 0.3)
			draw_circle(Vector2(px, CombatSim.FLOOR - r * 0.5).round(), r, Color(0.3, 0.24, 0.22, 0.8 * clampf(1.6 - edad * 0.45, 0.0, 1.0)))
		# Columna de humo oscuro.
		if edad > 0.3:
			var sube := minf(edad - 0.3, 2.5)
			for i in range(8):
				var k := float(i) / 7.0
				var p := c + Vector2(sin(i * 1.3 + t) * 10.0 * esc, -sube * 50.0 * k * esc)
				draw_circle(p.round(), (22.0 + k * 18.0) * esc, Color(0.12, 0.09, 0.09, 0.75 * clampf(2.8 - edad * 0.7, 0.0, 1.0)))
	# Bola de fuego.
	var f := clampf(1.0 - (edad - 0.15) / 1.1, 0.0, 1.0)
	if f > 0.0:
		var radio := (30.0 + minf(edad, 0.5) * 120.0) * esc * (0.6 if frente else 1.0)
		var capas := [[Color(0.75, 0.1, 0.04), 1.0], [Color(1.0, 0.42, 0.08), 0.78], [Color(1.0, 0.78, 0.3), 0.52], [Color(1.0, 0.97, 0.85), 0.28]]
		for capa in capas:
			var col: Color = capa[0]
			col.a = f * (0.6 if frente else 0.9)
			var rr := radio * float(capa[1])
			draw_circle((c + Vector2(0, -rr * 0.35)).round(), rr, col)
			for k in range(5):
				var ang := rng.randf() * TAU
				draw_circle((c + Vector2(0, -rr * 0.35) + Vector2.from_angle(ang) * rr * 0.8).round(), rr * 0.4, col)
	# Destello inicial.
	if edad < 0.18 and not frente:
		draw_circle(c.round(), 120.0 * esc * (1.0 - edad / 0.18), Color(1, 1, 0.9, 0.8 * (1.0 - edad / 0.18)))


func _ondas(lista: Array, t: float) -> void:
	for o in lista:
		var p := clampf((t - float(o["t"])) / float(o.get("dur", 1.0)), 0.0, 1.0)
		if p >= 1.0:
			continue
		var c: Vector2 = o["pos"]
		var col: Color = o["color"]
		col.a = (1.0 - p) * 0.9
		var r := 12.0 + p * float(o.get("radio", 220.0))
		FighterPainter.alpha = 1.0
		FighterPainter.ellipse(self, c, r, r * 0.2, col, 3.0)
		FighterPainter.ellipse(self, c, r * 0.85, r * 0.17, Color(1, 1, 1, col.a * 0.5), 1.0)


func _particulas(lista: Array) -> void:
	for p in lista:
		if bool(p["delante"]) != delante:
			continue
		var k := float(p["vida"]) / float(p["max"])
		var col: Color = p["color"]
		var pos: Vector2 = p["pos"]
		match String(p["tipo"]):
			"humo":
				col.a *= (1.0 - k) * minf(1.0, k * 6.0 + 0.3)
				var rr := roundf(float(p["r"]))
				_box(pos.x - rr, pos.y - rr * 0.6, rr * 2.0, rr * 1.2, col)
				_box(pos.x - rr * 0.6, pos.y - rr, rr * 1.2, rr * 2.0, col)
			"roca":
				col.a *= minf(1.0, (1.0 - k) * 3.0)
				var s := float(p["r"])
				_box(pos.x - s * 0.5, pos.y - s * 0.5, s, s, col)
				_box(pos.x - s * 0.5, pos.y - s * 0.5, s, 1, Color(0.8, 0.5, 0.3, col.a))
			"polvo":
				col.a *= minf(1.0, (1.0 - k) * 3.0)
				_box(pos.x, pos.y, 1, 2, col)
			_:
				col.a *= 1.0 - k
				_box(pos.x, pos.y, 2 if float(p["r"]) > 1.5 else 1, 2, col)


## Rinnegan: brillo morado en los ojos.
func _ojos(o: Vector2, a: float, mira: float, t: float) -> void:
	if a <= 0.0:
		return
	var latido := 0.8 + 0.2 * sin(t * 14.0)
	var largo := roundf(2.0 + a * 4.0 * latido)
	_box(o.x - largo, o.y, largo * 2.0 + 1.0, 1, Color(0.75, 0.45, 1.0, a * 0.5))
	draw_circle(o + Vector2(0.5, 0.5), 2.0, Color(0.7, 0.4, 1.0, a * 0.35))
	_box(o.x, o.y, 1, 1, Color(0.85, 0.7, 1.0, a))
	_box(o.x - mira * 3.0, o.y, 1, 1, Color(0.85, 0.7, 1.0, a * 0.85))


## Sprites de efectos de la hoja (tajo, explosión, humo, escombros) con fundido y crecimiento.
func _sprites(t: float) -> void:
	var efx: Dictionary = ctrl.get("efx")
	for f in ctrl.get("sprites_fx"):
		if bool(f["delante"]) != delante or not efx.has(String(f["nombre"])):
			continue
		var e: Dictionary = efx[String(f["nombre"])]
		var edad := t - float(f["t"])
		var k := clampf(edad / float(f["dur"]), 0.0, 1.0)
		var dur := float(f["dur"])
		var alfa := clampf(edad / 0.08, 0.0, 1.0) * (1.0 if dur > 50.0 else clampf((1.0 - k) * 2.5, 0.0, 1.0))
		var esc := float(f["escala"]) * (1.0 + float(f["crece"]) * k)
		var pos: Vector2 = (f["pos"] as Vector2) + (f["deriva"] as Vector2) * edad
		draw_set_transform(pos, float(f["rot"]), Vector2(esc, esc))
		draw_texture(e["tex"], -(e["ancla"] as Vector2), Color(1, 1, 1, alfa))
	draw_set_transform(Vector2.ZERO)
