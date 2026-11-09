class_name StagePainter
extends RefCounted
## Dibuja los cuatro escenarios (fondo y suelo) en pixel art a 480 px de ancho.
## Se usa en el combate y en las miniaturas de la selección de escenario.
##
## Cada escenario tiene capas: cielo con degradado tramado (dithering), astro,
## fondo lejano, capa media con detalle, primer plano animado y un suelo propio
## (tablones, losas, hierba y roca, roca agrietada con lava).

const WIDTH := 480.0
const FLOOR := 204.0


static func c(hex: String) -> Color:
	return Catalog.color(hex)


static func box(ci: CanvasItem, x: float, y: float, w: float, h: float, color: Color) -> void:
	FighterPainter.box(ci, x, y, w, h, color)


static func _with_alpha(color: Color, a: float) -> Color:
	var result := color
	result.a = a
	return result


# --- Ayudas de pixel art -----------------------------------------------------

## Degradado vertical en bandas con una fila tramada entre bandas (estilo 16 bits).
static func _sky(ci: CanvasItem, top: Color, bottom: Color, y0: float, y1: float, bands: int = 9) -> void:
	var band_h := (y1 - y0) / bands
	for i in range(bands):
		var color := top.lerp(bottom, float(i) / float(bands - 1))
		box(ci, 0, y0 + i * band_h, WIDTH, band_h + 1, color)
		if i < bands - 1:
			var next := top.lerp(bottom, float(i + 1) / float(bands - 1))
			var dy := y0 + (i + 1) * band_h - 2
			for x in range(0, int(WIDTH), 4):
				box(ci, x + (2 if (i % 2 == 0) else 0), dy, 2, 1, next)


## Disco pixelado (luna, sol) con halo.
static func _orb(ci: CanvasItem, cx: float, cy: float, r: float, color: Color, halo: Color) -> void:
	for ring in range(3, 0, -1):
		var hr := r + ring * 5.0
		var hc := halo
		hc.a = halo.a / ring
		_disc(ci, cx, cy, hr, hc)
	_disc(ci, cx, cy, r, color)


static func _disc(ci: CanvasItem, cx: float, cy: float, r: float, color: Color) -> void:
	var y := -r
	while y <= r:
		var half := floorf(sqrt(maxf(0.0, r * r - y * y)))
		box(ci, cx - half, cy + y, half * 2.0, 2, color)
		y += 2.0


static func _stars(ci: CanvasItem, color: Color, time: float, count: int, max_y: float) -> void:
	for i in range(count):
		var x := float((i * 73 + 11) % int(WIDTH))
		var y := 8.0 + float((i * 29) % int(max_y))
		var twinkle := 1.0 if (i + int(time * 2.0)) % 7 != 0 else 0.25
		var size := 2.0 if i % 5 == 0 else 1.0
		box(ci, x, y, size, size, _with_alpha(color, (0.35 + 0.5 * twinkle) * (0.6 if i % 3 == 0 else 1.0)))


## Silueta de montañas/colinas con dientes de sierra pixelados.
static func _ridge(ci: CanvasItem, base_y: float, amplitude: float, step: float, seed_value: int, color: Color, bottom: float = 205.0) -> void:
	var x := 0.0
	var i := 0
	while x < WIDTH:
		var h := amplitude * (0.45 + 0.55 * absf(sin((i + seed_value) * 1.37) * cos((i + seed_value) * 0.61)))
		box(ci, x, base_y - h, step, bottom - (base_y - h), color)
		x += step
		i += 1


static func _cloud(ci: CanvasItem, x: float, y: float, w: float, color: Color) -> void:
	box(ci, x, y, w, 5, color)
	box(ci, x + w * 0.15, y - 4, w * 0.45, 4, color)
	box(ci, x + w * 0.45, y - 7, w * 0.3, 7, color)
	box(ci, x + 3, y + 5, w - 6, 2, _with_alpha(color.darkened(0.15), color.a))


# --- Fondo -------------------------------------------------------------------

## `time` anima elementos sutiles (olas, banderas, público, brasas); 0 = imagen fija.
static func draw_background(ci: CanvasItem, stage: Dictionary, height: float = 270.0, time: float = 0.0) -> void:
	box(ci, 0, 0, WIDTH, height, c(String(stage["sky"])))
	match String(stage["decor"]):
		"harbor":
			_draw_harbor(ci, stage, time)
		"arena":
			_draw_courtyard(ci, stage, time)
		"cliffs":
			_draw_cliffs(ci, stage, time)
		_:
			_draw_warzone(ci, stage, time)


## Puerto Brumaria: noche de luna llena, faro, barcos que se mecen y muelle de madera.
static func _draw_harbor(ci: CanvasItem, stage: Dictionary, time: float) -> void:
	var sky := c(String(stage["sky"]))
	var far := c(String(stage["far"]))
	var near := c(String(stage["near"]))
	var trim := c(String(stage["trim"]))
	_sky(ci, sky.darkened(0.45), sky.lightened(0.12), 0, 150)
	_stars(ci, c("#e3eef2"), time, 34, 90)
	_orb(ci, 120, 48, 15, c("#f4ecd0"), Color(0.95, 0.9, 0.75, 0.12))
	box(ci, 112, 42, 5, 4, c("#ddd2b2"))
	box(ci, 124, 52, 4, 3, c("#ddd2b2"))
	# Nubes finas que cruzan la luna.
	for i in range(3):
		var cx := fmod(time * (4.0 + i * 2.0) + i * 170.0, WIDTH + 120.0) - 80.0
		_cloud(ci, cx, 40.0 + i * 18.0, 70.0 - i * 10.0, Color(0.75, 0.82, 0.9, 0.12))
	# Ciudad lejana con ventanas que se encienden y apagan.
	_ridge(ci, 128, 22, 16, 3, far.darkened(0.35), 150)
	for i in range(12):
		var bx := i * 42.0 - 6.0
		var bh := 30.0 + float((i * 23) % 34)
		var tone := far if i % 2 == 0 else far.darkened(0.15)
		box(ci, bx, 146 - bh, 30, bh, tone)
		box(ci, bx, 146 - bh, 30, 2, tone.lightened(0.2))
		if i % 3 == 0:
			box(ci, bx + 12, 140 - bh, 4, 6, tone)
		for wy in range(int(bh / 9.0)):
			for wx in range(3):
				var lit := (i * 7 + wy * 3 + wx + int(time * 0.5)) % 5 != 0
				if lit:
					box(ci, bx + 4 + wx * 9, 150 - bh + wy * 9, 3, 4, _with_alpha(c("#f6c86f"), 0.75))
	# Faro con haz giratorio.
	var lx := 430.0
	box(ci, lx - 7, 70, 14, 78, near.darkened(0.2))
	for s in range(4):
		box(ci, lx - 7, 80 + s * 18, 14, 6, c("#c9413a"))
	box(ci, lx - 9, 62, 18, 9, c("#2b2f3d"))
	box(ci, lx - 5, 64, 10, 5, c("#ffeaa0"))
	box(ci, lx - 10, 58, 20, 4, c("#2b2f3d"))
	var beam := sin(time * 0.9)
	var beam_color := Color(1.0, 0.95, 0.7, 0.04 + 0.04 * absf(beam))
	var tip_x := lx + beam * 220.0
	if ci.has_method("draw_colored_polygon"):
		var tinted := beam_color
		tinted.a *= FighterPainter.alpha
		ci.draw_colored_polygon(PackedVector2Array([Vector2(lx, 64), Vector2(tip_x, 40), Vector2(tip_x, 82)]), tinted)
	# Agua con reflejo de la luna.
	_sky(ci, c("#1f3a52"), c("#14263a"), 146, 196, 5)
	for i in range(14):
		var wobble := roundf(sin(time * 2.0 + i * 0.9) * 3.0)
		var w := 18.0 - absf(i - 7.0) * 1.5
		box(ci, 120 - w / 2.0 + wobble, 148 + i * 3.4, w, 1, Color(0.97, 0.93, 0.78, 0.35 - i * 0.018))
	for i in range(28):
		var drift := fmod(time * (5.0 + i % 3 * 2.0), WIDTH)
		var wx := fmod(float((i * 47) % int(WIDTH)) + drift, WIDTH)
		box(ci, wx, 152 + (i * 11) % 40, 10 + (i % 3) * 5, 1, Color(0.72, 0.88, 0.87, 0.22))
	# Barcos que se mecen.
	for b in range(2):
		var sx := 250.0 + b * 120.0
		var bob := roundf(sin(time * 1.6 + b * 2.1) * 1.5)
		var sy := 168.0 + b * 8.0 + bob
		box(ci, sx, sy, 46, 6, c("#3a2a2a"))
		box(ci, sx + 4, sy + 6, 38, 3, c("#2a1e22"))
		box(ci, sx, sy, 46, 1, c("#8a6a4a"))
		box(ci, sx + 21, sy - 40, 2, 40, c("#4a3a32"))
		var sail := Color(0.92, 0.88, 0.78, 0.92)
		sail.a *= FighterPainter.alpha
		ci.draw_colored_polygon(PackedVector2Array([Vector2(sx + 23, sy - 38), Vector2(sx + 41, sy - 6), Vector2(sx + 23, sy - 6)]), sail)
		var sail2 := Color(0.8, 0.75, 0.66, 0.92)
		sail2.a *= FighterPainter.alpha
		ci.draw_colored_polygon(PackedVector2Array([Vector2(sx + 20, sy - 30), Vector2(sx + 6, sy - 6), Vector2(sx + 20, sy - 6)]), sail2)
		box(ci, sx + 22, sy - 44, 6, 3, trim)
	# Gaviotas.
	for g in range(3):
		var gx := fmod(time * (18.0 + g * 6.0) + g * 150.0, WIDTH + 40.0) - 20.0
		var gy := 70.0 + g * 14.0 + roundf(sin(time * 3.0 + g) * 3.0)
		var flap := 1.0 if sin(time * 10.0 + g) > 0.0 else 0.0
		box(ci, gx - 4, gy - flap, 4, 1, c("#e8eef0"))
		box(ci, gx, gy, 1, 1, c("#e8eef0"))
		box(ci, gx + 1, gy - flap, 4, 1, c("#e8eef0"))
	# Muelle: barandilla, postes, cajas y farolillos.
	box(ci, 0, 188, WIDTH, 16, near.darkened(0.25))
	box(ci, 0, 186, WIDTH, 3, c("#6b4b36"))
	for i in range(10):
		var px := i * 52.0 + 6.0
		box(ci, px, 176, 5, 28, c("#4a3326"))
		box(ci, px, 176, 5, 2, c("#8a6448"))
	box(ci, 0, 178, WIDTH, 2, c("#5b3f2e"))
	for k in range(2):
		var kx := 30.0 + k * 380.0
		box(ci, kx, 172, 18, 16, c("#6b4a30"))
		box(ci, kx, 172, 18, 2, c("#9a7048"))
		box(ci, kx + 8, 172, 2, 16, c("#4a3220"))
		box(ci, kx + 20, 178, 12, 10, c("#5c3f28"))
	for l in range(3):
		var lxp := 100.0 + l * 140.0
		var flicker := 0.75 + 0.25 * sin(time * 8.0 + l * 2.0)
		box(ci, lxp, 164, 2, 14, c("#2b2f3d"))
		box(ci, lxp - 3, 160, 8, 6, c("#2b2f3d"))
		box(ci, lxp - 2, 161, 6, 4, _with_alpha(c("#ffd27a"), flicker))
		_disc(ci, lxp + 1, 163, 9, Color(1.0, 0.82, 0.45, 0.08 * flicker))


## Patio del Bastión: atardecer, murallas con almenas, antorchas, estandartes y público.
static func _draw_courtyard(ci: CanvasItem, stage: Dictionary, time: float) -> void:
	var sky := c(String(stage["sky"]))
	var far := c(String(stage["far"]))
	var near := c(String(stage["near"]))
	var trim := c(String(stage["trim"]))
	_sky(ci, c("#3b2c45"), c("#f0a35e"), 0, 140)
	_orb(ci, 300, 108, 24, c("#ffd98a"), Color(1.0, 0.75, 0.4, 0.18))
	for i in range(4):
		var cx := fmod(time * (3.0 + i) + i * 130.0, WIDTH + 100.0) - 60.0
		_cloud(ci, cx, 30.0 + i * 16.0, 80.0 - i * 8.0, Color(1.0, 0.78, 0.6, 0.22))
	_ridge(ci, 132, 26, 12, 7, c("#6c4a52"), 160)
	_ridge(ci, 142, 16, 10, 2, c("#5a3d47"), 160)
	# Torres con tejado cónico.
	for t in range(2):
		var tx := 40.0 + t * 370.0
		box(ci, tx, 70, 34, 100, far.darkened(0.1))
		box(ci, tx + 26, 70, 8, 100, far.darkened(0.3))
		box(ci, tx, 70, 34, 2, far.lightened(0.2))
		var roof := c("#7a3138")
		roof.a *= FighterPainter.alpha
		ci.draw_colored_polygon(PackedVector2Array([Vector2(tx - 4, 72), Vector2(tx + 17, 40), Vector2(tx + 38, 72)]), roof)
		box(ci, tx + 16, 30, 2, 12, c("#3a2a2a"))
		var flag_wave := roundf(sin(time * 4.0 + t) * 1.5)
		box(ci, tx + 18, 31 + flag_wave, 10, 5, trim)
		box(ci, tx + 12, 96, 10, 14, c("#2a1e26"))
		box(ci, tx + 13, 97, 8, 12, _with_alpha(c("#ffb84d"), 0.55 + 0.2 * sin(time * 5.0 + t)))
	# Muralla con almenas.
	box(ci, 0, 112, WIDTH, 58, far)
	box(ci, 0, 112, WIDTH, 2, far.lightened(0.25))
	for i in range(24):
		box(ci, i * 20.0 + 2, 104, 12, 9, far)
		box(ci, i * 20.0 + 2, 104, 12, 2, far.lightened(0.25))
	for row in range(5):
		for col in range(16):
			var off := 15.0 if row % 2 == 0 else 0.0
			box(ci, col * 30.0 + off, 118 + row * 10, 1, 9, far.darkened(0.18))
		box(ci, 0, 127 + row * 10, WIDTH, 1, far.darkened(0.18))
	# Arcos oscuros con estandartes que ondean.
	for i in range(4):
		var ax := 90.0 + i * 92.0
		box(ci, ax, 128, 30, 42, c("#2f2230"))
		box(ci, ax + 4, 124, 22, 4, c("#2f2230"))
		box(ci, ax + 8, 121, 14, 3, c("#2f2230"))
		# Estandarte rojo con emblema dorado colgado sobre el arco.
		box(ci, ax + 8, 114, 14, 2, c("#3a2a24"))
		for seg in range(5):
			var wave := roundf(sin(time * 3.0 + i + seg * 0.6) * (seg * 0.35))
			box(ci, ax + 10 + wave, 116 + seg * 5, 10, 5, c("#8e2f36") if seg % 2 == 0 else c("#7a2830"))
			box(ci, ax + 10 + wave, 116 + seg * 5, 1, 5, trim)
			box(ci, ax + 19 + wave, 116 + seg * 5, 1, 5, trim)
		var tip := roundf(sin(time * 3.0 + i + 3.0) * 1.6)
		box(ci, ax + 13 + tip, 122, 4, 4, trim)
		box(ci, ax + 12 + tip, 141, 6, 2, c("#7a2830"))
	# Antorchas con llama animada.
	for i in range(5):
		var fx := 66.0 + i * 92.0
		box(ci, fx, 136, 3, 10, c("#3a2a24"))
		var h := 5.0 + roundf(absf(sin(time * 9.0 + i * 1.3)) * 3.0)
		box(ci, fx - 2, 136 - h, 7, h, c("#ff8a3a"))
		box(ci, fx, 136 - h + 2, 3, h - 2, c("#ffe08a"))
		_disc(ci, fx + 1, 131, 11, Color(1.0, 0.6, 0.25, 0.07))
	# Público tras la barandilla de piedra (salta más en los golpes).
	var crowd_colors := ["#b85c4a", "#4f6c8a", "#d6a84f", "#6b8a4f", "#8a4f7a", "#c9c0a8"]
	for i in range(40):
		var px := i * 12.0 + float(i % 3)
		var jump := roundf(absf(sin(time * (3.0 + (i % 4)) + i * 0.7)) * 2.0)
		var color := c(String(crowd_colors[i % crowd_colors.size()])).darkened(0.25)
		box(ci, px, 168 - jump, 9, 12, color)
		box(ci, px + 2, 162 - jump, 6, 6, c("#c49a7a").darkened(0.3))
		if (i + int(time * 2.0)) % 9 == 0:
			box(ci, px + 7, 156 - jump, 2, 7, color)
	box(ci, 0, 176, WIDTH, 26, near)
	box(ci, 0, 176, WIDTH, 3, near.lightened(0.2))
	for i in range(20):
		box(ci, i * 24.0, 182, 18, 2, near.darkened(0.25))
		box(ci, i * 24.0 + 21, 179, 3, 23, near.darkened(0.3))


## Rocas Gemelas: montañas nevadas, cascada entre dos agujas de roca, pinos y niebla.
static func _draw_cliffs(ci: CanvasItem, stage: Dictionary, time: float) -> void:
	var sky := c(String(stage["sky"]))
	var far := c(String(stage["far"]))
	var near := c(String(stage["near"]))
	_sky(ci, c("#2f5878"), c("#c4dfe4"), 0, 160)
	_orb(ci, 380, 40, 12, c("#fff6d8"), Color(1.0, 0.95, 0.7, 0.12))
	for i in range(5):
		var cx := fmod(time * (5.0 + i * 1.5) + i * 110.0, WIDTH + 120.0) - 80.0
		_cloud(ci, cx, 26.0 + (i % 3) * 20.0, 60.0 + (i % 2) * 30.0, Color(1, 1, 1, 0.28))
	# Cordillera lejana con nieve.
	for i in range(7):
		var mx := i * 80.0 - 30.0
		var peak := 58.0 + float((i * 37) % 30)
		var mcol := far.lightened(0.15)
		mcol.a *= FighterPainter.alpha
		ci.draw_colored_polygon(PackedVector2Array([Vector2(mx, 160), Vector2(mx + 50, peak), Vector2(mx + 100, 160)]), mcol)
		var snow := Color(0.94, 0.97, 1.0, 0.85 * FighterPainter.alpha)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(mx + 38, peak + 14), Vector2(mx + 50, peak), Vector2(mx + 62, peak + 14), Vector2(mx + 55, peak + 11), Vector2(mx + 50, peak + 16), Vector2(mx + 44, peak + 11)]), snow)
	_ridge(ci, 150, 20, 10, 5, far.darkened(0.1), 200)
	# Las dos agujas de roca con la cascada en medio.
	for r in range(2):
		var rx := 150.0 + r * 140.0
		box(ci, rx, 60, 40, 130, near)
		box(ci, rx + 4, 52, 30, 10, near)
		box(ci, rx + 10, 46, 16, 8, near)
		box(ci, rx, 60, 8, 130, near.lightened(0.15))
		box(ci, rx + 32, 60, 8, 130, near.darkened(0.25))
		for k in range(6):
			box(ci, rx + 10 + (k % 2) * 12, 70 + k * 19, 10, 2, near.darkened(0.3))
		box(ci, rx + 10, 46, 16, 2, c("#e8f0f2"))
	for i in range(8):
		var flow := fmod(time * 60.0 + i * 13.0, 130.0)
		box(ci, 210 + (i % 4) * 5, 62 + flow, 3, 10, Color(0.85, 0.95, 1.0, 0.7))
	box(ci, 205, 62, 20, 128, Color(0.6, 0.8, 0.95, 0.35))
	_disc(ci, 215, 186, 16, Color(1, 1, 1, 0.18 + 0.06 * sin(time * 6.0)))
	# Pinos.
	for p in range(9):
		var tx := float((p * 57 + 8) % int(WIDTH))
		if tx > 140.0 and tx < 340.0:
			continue
		var th := 22.0 + float((p * 13) % 14)
		var tree := c("#244034") if p % 2 == 0 else c("#2c4c3c")
		for layer in range(4):
			var lw := 4.0 + layer * 4.0
			box(ci, tx - lw / 2.0, 186 - th + layer * (th / 4.0), lw, th / 4.0 + 1, tree)
		box(ci, tx - 1, 186, 3, 6, c("#3a2a22"))
	# Pájaros y niebla lenta.
	for b in range(4):
		var bx := fmod(time * (14.0 + b * 4.0) + b * 120.0, WIDTH + 30.0) - 15.0
		var by := 50.0 + b * 11.0
		var flap := 1.0 if sin(time * 9.0 + b) > 0.0 else 0.0
		box(ci, bx - 3, by - flap, 3, 1, c("#2a3440"))
		box(ci, bx, by, 1, 1, c("#2a3440"))
		box(ci, bx + 1, by - flap, 3, 1, c("#2a3440"))
	for i in range(5):
		var fx := fmod(time * 9.0 + i * 120.0, WIDTH + 120.0) - 60.0
		box(ci, fx, 160 + i * 6, 110, 4, Color(1, 1, 1, 0.07))
	box(ci, 0, 188, WIDTH, 16, near.darkened(0.2))


## Falla Carmesí: luna roja, columnas de humo, ruinas en llamas y una grieta de lava.
static func _draw_warzone(ci: CanvasItem, stage: Dictionary, time: float) -> void:
	var sky := c(String(stage["sky"]))
	var far := c(String(stage["far"]))
	var near := c(String(stage["near"]))
	_sky(ci, c("#1e1020"), c("#b2463c"), 0, 160)
	_stars(ci, c("#ffb8a0"), time, 18, 60)
	_orb(ci, 140, 56, 22, c("#e8503f"), Color(1.0, 0.3, 0.2, 0.16))
	box(ci, 130, 48, 6, 5, c("#c43c32"))
	box(ci, 146, 62, 5, 4, c("#c43c32"))
	# Columnas de humo que suben.
	for s in range(3):
		var sx := 70.0 + s * 160.0
		for k in range(8):
			var rise := fmod(time * 10.0 + k * 14.0, 112.0)
			var r := 6.0 + rise * 0.12
			_disc(ci, sx + sin(time * 0.7 + k) * 6.0 + rise * 0.15, 150 - rise, r, Color(0.12, 0.08, 0.1, 0.35 - rise * 0.0028))
	_ridge(ci, 140, 24, 14, 9, c("#4a2430"), 170)
	# Ruinas con ventanas que arden.
	for i in range(9):
		var bx := i * 56.0 - 8.0
		var bh := 46.0 + float((i * 29) % 40)
		var tone := far.darkened(0.45) if i % 2 == 0 else c("#3a2230")
		box(ci, bx, 172 - bh, 38, bh, tone)
		# borde roto
		box(ci, bx + 6, 166 - bh, 8, 6, tone)
		box(ci, bx + 22, 169 - bh, 10, 3, tone)
		for wy in range(int(bh / 12.0)):
			for wx in range(2):
				var glow := 0.5 + 0.5 * sin(time * 6.0 + i + wy * 1.7 + wx)
				if (i + wy + wx) % 3 != 0:
					box(ci, bx + 7 + wx * 16, 178 - bh + wy * 12, 6, 6, _with_alpha(c("#ff8a4a"), 0.35 + 0.45 * glow))
				else:
					box(ci, bx + 7 + wx * 16, 178 - bh + wy * 12, 6, 6, c("#1a0e14"))
	# Fuegos en las ruinas.
	for i in range(6):
		var fx := float((i * 83 + 20) % int(WIDTH))
		var h := 6.0 + roundf(absf(sin(time * 8.0 + i * 1.9)) * 5.0)
		box(ci, fx - 4, 170 - h, 10, h, c("#ff6a2a"))
		box(ci, fx - 1, 172 - h, 5, h - 2, c("#ffd06a"))
		_disc(ci, fx + 1, 166, 13, Color(1.0, 0.45, 0.2, 0.08))
	# Grieta de lava al fondo de la arena.
	box(ci, 0, 172, WIDTH, 32, near)
	var pulse := 0.6 + 0.4 * sin(time * 2.5)
	for i in range(24):
		var lx := i * 20.0
		var ly := 182.0 + roundf(sin(i * 1.3) * 3.0)
		box(ci, lx, ly, 20, 3, _with_alpha(c("#ff6a2a"), 0.55 * pulse))
		box(ci, lx + 4, ly + 1, 10, 1, _with_alpha(c("#ffe08a"), 0.7 * pulse))
	_disc(ci, 240, 184, 40, Color(1.0, 0.4, 0.15, 0.05 * pulse))
	# Brasas que suben.
	for i in range(18):
		var ex := float((i * 41 + 13) % int(WIDTH))
		var ey := 205.0 - fmod(time * (14.0 + i % 4 * 5.0) + i * 23.0, 150.0)
		box(ci, ex + sin(time + i) * 4.0, ey, 2, 2, c("#ff9659") if i % 3 != 0 else c("#ffe08a"))


# --- Suelo -------------------------------------------------------------------

static func draw_ground(ci: CanvasItem, stage: Dictionary, height: float = 270.0, time: float = 0.0) -> void:
	var ground := c(String(stage["ground"]))
	var trim := c(String(stage["trim"]))
	box(ci, 0, FLOOR, WIDTH, height - FLOOR, ground)
	match String(stage["decor"]):
		"harbor":
			# Tablones de madera con juntas y clavos.
			for row in range(6):
				var y := FLOOR + 3 + row * 11.0
				var plank := ground.lightened(0.06 if row % 2 == 0 else 0.0)
				box(ci, 0, y, WIDTH, 10, plank)
				box(ci, 0, y + 9, WIDTH, 1, ground.darkened(0.35))
				box(ci, 0, y, WIDTH, 1, ground.lightened(0.18))
				for k in range(9):
					var jx := float((k * 61 + row * 29) % int(WIDTH))
					box(ci, jx, y, 1, 9, ground.darkened(0.35))
					box(ci, jx + 3, y + 4, 1, 1, c("#9aa0a8"))
		"arena":
			# Losas de piedra desplazadas.
			for row in range(6):
				var y := FLOOR + 3 + row * 11.0
				var off := 0.0 if row % 2 == 0 else 20.0
				box(ci, 0, y + 10, WIDTH, 1, ground.darkened(0.3))
				for k in range(13):
					var tx := k * 40.0 - off
					box(ci, tx, y, 1, 10, ground.darkened(0.3))
					box(ci, tx + 1, y, 38, 1, ground.lightened(0.12))
					if (k + row) % 5 == 0:
						box(ci, tx + 10, y + 4, 6, 1, ground.darkened(0.2))
		"cliffs":
			# Hierba con matas y roca con piedras.
			box(ci, 0, FLOOR + 3, WIDTH, 7, c("#3f6a48"))
			box(ci, 0, FLOOR + 3, WIDTH, 2, c("#5f9a5e"))
			for k in range(40):
				var gx := float((k * 37) % int(WIDTH))
				var sway := roundf(sin(time * 2.0 + k) * 1.0)
				box(ci, gx + sway, FLOOR - 1, 1, 4, c("#6fb06a"))
				box(ci, gx + 2, FLOOR, 1, 3, c("#4f8a50"))
			for k in range(22):
				var px := float((k * 53 + 17) % int(WIDTH))
				var py := FLOOR + 16 + float((k * 13) % 44)
				box(ci, px, py, 6, 3, ground.lightened(0.15))
				box(ci, px, py + 3, 6, 1, ground.darkened(0.3))
		_:
			# Roca agrietada con lava que late.
			var pulse := 0.55 + 0.45 * sin(time * 2.5)
			for k in range(14):
				var cx := float((k * 67 + 11) % int(WIDTH))
				var cy := FLOOR + 8 + float((k * 17) % 40)
				var seg := 0
				while seg < 4:
					box(ci, cx + seg * 5, cy + (seg % 2) * 2, 6, 1, _with_alpha(c("#ff6a2a"), 0.65 * pulse))
					seg += 1
				box(ci, cx + 6, cy + 1, 4, 1, _with_alpha(c("#ffe08a"), 0.8 * pulse))
			for k in range(20):
				var px := float((k * 43 + 5) % int(WIDTH))
				var py := FLOOR + 12 + float((k * 19) % 50)
				box(ci, px, py, 5, 2, ground.lightened(0.1))
	# Borde superior del suelo y degradado hacia abajo (profundidad).
	box(ci, 0, FLOOR, WIDTH, 3, trim)
	box(ci, 0, FLOOR + 3, WIDTH, 1, trim.darkened(0.4))
	for i in range(4):
		box(ci, 0, height - 16 + i * 4, WIDTH, 4, Color(0, 0, 0, 0.08 + i * 0.05))
