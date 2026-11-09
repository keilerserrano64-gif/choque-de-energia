class_name FighterPainter
extends RefCounted
## Dibuja los sprites pixel art de los luchadores con rectángulos, igual que
## drawBrasaSprite() y drawSprite() de src/renderer.js. Se usa desde ArenaView
## (combate) y desde FighterPortrait (menús), así que todo el arte vive aquí.
##
## Las coordenadas son las del sprite original: (0, 0) son los pies y el eje Y
## crece hacia abajo; un luchador mide unos 43–58 px antes de escalarlo.

const OUTLINE := "#171925"
const ATTACK_POSES := ["punch", "smear", "impact", "special-launch", "special-impact"]
const CHARGE_ARM_FIGHTERS := ["cobalto", "luma", "marea", "pedernal", "volt", "espejo"]

## Transparencia global para los siguientes rectángulos (equivale a globalAlpha).
static var alpha := 1.0

## Centro aproximado de la cara de los luchadores dibujados con rectángulos
## (unidades del sprite, pies en 0,0). Sirve para encuadrar los retratos.
const GENERIC_HEAD := Vector2(0.5, -39.5)
const SPRITE_ATTACK_POSES := ["anticipate", "punch", "smear", "impact", "recover", "kick"]
## Imagen que usan los golpes de cadena si el luchador no tiene una propia
## (p. ej. Volt usa su puñetazo "light" para el jab y su patada "finisher" para todas las patadas).
## Volt tiene pocas imágenes: cuando un golpe usa la imagen de otro (p. ej. la patada media
## para la patada baja), se gira alrededor de la cadera o del hombro para que se lea como el
## golpe real. rot en radianes (+ = hacia delante y abajo), pivot = altura del eje en fracción
## de sprite_height, sy = aplastado vertical (agachado). Los luchadores con imagen propia no lo usan.
const SPRITE_MOVE_POSE := {
	"kick_low": {"rot": 0.3, "pivot": 0.45},
	"kick_high": {"rot": -0.42, "pivot": 0.45},
	"kick_spin": {"rot": -0.28, "pivot": 0.45},
	"sweep": {"rot": 0.5, "pivot": 0.42, "sy": 0.84},
	"air_kick": {"rot": 0.55, "pivot": 0.5},
	"air_punch": {"rot": 0.4, "pivot": 0.62},
	"uppercut": {"rot": -0.62, "pivot": 0.64},
	"hook": {"rot": -0.12, "pivot": 0.64},
}
const SPRITE_STRIKE_ALIAS := {
	"jab": "light", "cross": "heavy", "hook": "light", "uppercut": "heavy",
	"kick_low": "finisher", "kick_mid": "finisher", "kick_high": "finisher", "kick_spin": "finisher",
	"sweep": "finisher", "air_kick": "finisher", "air_punch": "light", "throw": "heavy",
}
const SPRITE_SPECIAL_POSES := ["charge", "special-anticipate", "special-launch", "special-impact", "special-recover"]

static var _textures: Dictionary = {}

## Salida de AnimadorProcedural para el luchador que se está dibujando:
## {desp: Vector2 (px de la imagen), escala: Vector2, rot: grados, color: Color, ko: bool}.
## ArenaView la pone antes de draw_body() y la vacía después. Vacío = sin animador.
static var procedural: Dictionary = {}


static func c(hex: String) -> Color:
	return Catalog.color(hex)


static func box(ci: CanvasItem, x: float, y: float, w: float, h: float, color: Color) -> void:
	var tinted := color
	tinted.a *= alpha
	ci.draw_rect(Rect2(roundf(x), roundf(y), roundf(w), roundf(h)).abs(), tinted)


static func ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float, color: Color, width: float = 1.0) -> void:
	var points := PackedVector2Array()
	var steps := 40
	for i in range(steps + 1):
		var angle := TAU * i / steps
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	var tinted := color
	tinted.a *= alpha
	ci.draw_polyline(points, tinted, width)


static func set_transform(ci: CanvasItem, base: Transform2D, pos: Vector2, scale: Vector2, rotation: float = 0.0) -> void:
	var xf := base * Transform2D(0.0, pos) * Transform2D(0.0, scale, 0.0, Vector2.ZERO) * Transform2D(rotation, Vector2.ZERO)
	ci.draw_set_transform_matrix(xf)


static func _num(frame: Dictionary, key: String, fallback: float = 0.0) -> float:
	return float(frame.get(key, fallback))


## Dibuja el cuerpo del luchador con los pies en (x, foot).
## `frame` es el cuadro de animación (incluye "name" y "pose").
static func draw_body(ci: CanvasItem, base: Transform2D, x: float, foot: float, f: FighterState,
		body_color: Color, frame: Dictionary, elapsed: float, victorious: bool = false) -> void:
	if has_sprites(f.definition):
		_draw_sprite(ci, base, x, foot, f, frame, elapsed, victorious)
	elif f.id == "brasa":
		_draw_brasa(ci, base, x, foot, f, body_color, frame, elapsed)
	else:
		_draw_generic(ci, base, x, foot, f, body_color, frame, elapsed, victorious)
	ci.draw_set_transform_matrix(base)


static func _draw_brasa(ci: CanvasItem, base: Transform2D, x: float, foot: float, f: FighterState,
		flash_color: Color, frame: Dictionary, elapsed: float) -> void:
	var outline := c("#391e2a")
	var outline_shade := c("#612936")
	var red_shadow := c("#a93632")
	var red := flash_color
	var red_light := c("#ff8b59")
	var red_dark := c("#732d39")
	var gold := c("#ffc34d")
	var gold_light := c("#fff0a1")
	var gold_shadow := c("#c46a37")
	var skin := c("#ff7770") if f.hit_flash > 0.0 else c("#f4c39c")
	var skin_shadow := c("#b97369")
	var boot := c("#482536")
	var trim := c("#ffe5a0")
	var scale := float(f.definition["sprite_scale"])
	var bob := _num(frame, "bob")
	var pose := String(frame.get("pose", "idle"))
	var turn := -1.0 if frame.get("turn", false) else 1.0
	var squash := 1.0 - _num(frame, "squash")  # agachado (barrida)
	# Las piernas se dibujan sin el "bob" (los pies no se hunden); el torso respira después.
	set_transform(ci, base, Vector2(x + _num(frame, "dx"), foot), Vector2(f.facing * scale * turn, scale * squash), _num(frame, "lean"))

	if pose == "down":
		box(ci, -19, -5, 37, 5, outline)
		box(ci, -16, -8, 29, 4, red)
		box(ci, 10, -11, 12, 8, gold)
		box(ci, 17, -10, 4, 2, skin)
		return

	var arm := int(_num(frame, "arm"))
	var leg := int(_num(frame, "leg"))
	var kick_type := String(frame.get("kick", ""))
	var punch_type := String(frame.get("punch", ""))
	var attacking := ATTACK_POSES.has(pose) and kick_type == ""
	var kicking := pose == "kick" or ((pose == "smear" or pose == "impact") and leg == 2)

	if pose == "run" and frame.get("smear", false):
		var saved := alpha
		alpha = saved * 0.45
		box(ci, -23, -29, 11, 4, gold_shadow)
		box(ci, -29, -23, 16, 3, gold)
		alpha = saved
	if frame.has("aura"):
		var saved_aura := alpha
		alpha = saved_aura * (0.2 + _num(frame, "aura") * 0.08)
		box(ci, -15, -34, 30, 30, c("#ffb53d"))
		alpha = saved_aura

	if kicking:
		var kick_reach := 21 if leg == 2 else 11
		var kick_y := -21 if leg == 2 else -17
		if leg == 2:
			match kick_type:
				"low":
					kick_y = -9
					kick_reach = 20
				"mid":
					kick_y = -17
				"high":
					kick_y = -30
					kick_reach = 19
				"spin":
					kick_y = -25
					kick_reach = 25
		var diagonal := leg == 2 and (kick_type == "high" or kick_type == "spin")
		box(ci, -8, -14, 8, 13, outline)
		box(ci, -7, -13, 6, 11, red_shadow)
		if diagonal:
			# Pierna en diagonal desde la cadera hasta el pie.
			var steps: Array = [Vector2(-1, -15), Vector2(5, -21), Vector2(11, -27)] if kick_type == "high" 				else [Vector2(-1, -15), Vector2(6, -19), Vector2(13, -23)]
			for st in steps:
				box(ci, st.x, st.y, 9, 8, outline)
			for st in steps:
				box(ci, st.x + 1, st.y + 1, 7, 6, red)
			var tip: Vector2 = steps[steps.size() - 1] + Vector2(7, -2)
			kick_reach = int(tip.x) + 4
			kick_y = int(tip.y) + 1
			box(ci, tip.x, tip.y, 9, 8, boot)
			box(ci, tip.x + 2, tip.y + 1, 6, 3, trim)
		else:
			box(ci, 0, kick_y, kick_reach, 7, outline)
			box(ci, 2, kick_y + 1, kick_reach - 2, 5, red)
			box(ci, kick_reach - 4, kick_y - 1, 9, 8, boot)
			box(ci, kick_reach - 2, kick_y, 6, 3, trim)
		if frame.get("smear", false) and kick_type != "":
			var saved_kick := alpha
			alpha = saved_kick * 0.6
			box(ci, kick_reach - 14, kick_y - 4, 12, 2, gold_light)
			box(ci, kick_reach - 22, kick_y + 7, 10, 2, gold)
			alpha = saved_kick
		box(ci, -9, -5, 11, 5, outline)
		box(ci, -7, -4, 8, 3, gold_shadow)
	else:
		var stride := leg if (pose == "walk" or pose == "run") else 0
		box(ci, -9 + stride * 2, -15, 8, 14, outline)
		box(ci, -8 + stride * 2, -14, 6, 12, red_shadow if stride != 0 else red)
		box(ci, 1 - stride * 2, -15, 8, 14, outline)
		box(ci, 2 - stride * 2, -14, 6, 12, red if stride != 0 else red_shadow)
		box(ci, -10 + stride * 2, -3, 10, 4, boot)
		box(ci, 0 - stride * 2, -3, 11, 4, boot)
		box(ci, -9 + stride * 2, -3, 6, 1, trim)
		box(ci, 1 - stride * 2, -3, 6, 1, gold_shadow)

	set_transform(ci, base, Vector2(x + _num(frame, "dx"), foot + bob * scale * 0.6), Vector2(f.facing * scale * turn, scale * squash), _num(frame, "lean"))
	box(ci, -11, -27, 22, 17, outline)
	box(ci, -9, -26, 18, 14, red_dark)
	box(ci, -8, -25, 16, 12, red)
	box(ci, -8, -22, 5, 8, red_light)
	box(ci, -8, -12, 16, 3, gold_shadow)
	box(ci, -7, -12, 13, 2, trim)
	box(ci, -2, -14, 4, 3, gold)
	box(ci, -13, -27, 4, 12, outline)
	box(ci, -12, -26, 2, 9, red_shadow)

	if pose == "block":
		box(ci, -1, -28, 8, 9, outline)
		box(ci, 0, -27, 6, 7, red_light)
		box(ci, 4, -26, 8, 8, outline)
		box(ci, 5, -25, 6, 6, skin)
		box(ci, -9, -28, 8, 9, outline)
		box(ci, -8, -27, 6, 7, red)
	elif attacking or pose == "special-anticipate" or pose == "victory" or pose == "intro":
		var reach := 0
		if arm == 2:
			reach = 18
		elif arm == 1:
			reach = 12
		elif arm == -1:
			reach = 3
		var arm_y := -27
		if pose == "victory":
			arm_y = -37
		elif pose.begins_with("special"):
			arm_y = -34
		elif punch_type == "hook":
			arm_y = -30
		elif punch_type == "cross":
			reach += 3
		if pose == "victory":
			# Puño en alto envuelto en llamas.
			var top_v := -40 - arm * 3
			box(ci, 5, top_v, 8, -20 - top_v, outline)
			box(ci, 6, top_v + 1, 6, -22 - top_v, red_light)
			box(ci, 4, top_v - 7, 10, 8, skin_shadow)
			box(ci, 5, top_v - 6, 8, 6, skin)
			var flick := 1.0 if sin(elapsed * 30.0) > 0.0 else 0.0
			box(ci, 5, top_v - 12 - flick, 3, 5 + flick, gold)
			box(ci, 8, top_v - 14 + flick, 3, 7 - flick, c("#ff8b38"))
			box(ci, 11, top_v - 11, 2, 4, gold_light)
			reach = -1
		elif punch_type == "upper" and attacking:
			# Uppercut: el puño sube en vertical por delante de la cara.
			var top := -36 - (6 if arm >= 2 else 2)
			box(ci, 6, top, 8, -20 - top, outline)
			box(ci, 7, top + 1, 6, -22 - top, red_light)
			box(ci, 5, top - 6, 10, 8, skin_shadow)
			box(ci, 6, top - 5, 8, 6, skin)
			if frame.get("smear", false):
				var saved_up := alpha
				alpha = saved_up * 0.75
				box(ci, 7, top - 12, 6, 6, gold_light)
				box(ci, 8, top - 16, 4, 4, c("#fff8d3"))
				alpha = saved_up
			reach = -1
		if reach >= 0:
			box(ci, 5, arm_y - 1, 8 + reach, 8, outline)
			box(ci, 7, arm_y, 6 + reach, 5, red_light)
			box(ci, 12 + reach, arm_y - 1, 7, 7, skin_shadow)
			box(ci, 14 + reach, arm_y, 6, 5, skin)
		if reach >= 0 and frame.get("smear", false):
			var saved_smear := alpha
			alpha = saved_smear * 0.75
			box(ci, 18 + reach, arm_y, 14, 4, gold_light)
			box(ci, 26 + reach, arm_y + 1, 13, 2, c("#fff8d3"))
			alpha = saved_smear
	else:
		var arm_offset := arm * 3 if (pose == "walk" or pose == "run") else 0
		box(ci, 6, -26 + arm_offset, 8, 13, outline)
		box(ci, 8, -25 + arm_offset, 5, 10, red_light)
		box(ci, 8, -16 + arm_offset, 7, 5, skin)

	box(ci, -8, -35, 16, 13, outline)
	box(ci, -6, -34, 13, 10, skin_shadow)
	box(ci, -5, -34, 11, 8, skin)
	box(ci, 2, -31, 4, 2, outline_shade)
	box(ci, 4, -31, 2, 1, gold_light)
	box(ci, -8, -36, 17, 6, outline)
	box(ci, -7, -36, 15, 4, gold_shadow)
	box(ci, -6, -37, 13, 3, gold)
	var hair_motion := roundf(_num(frame, "hair")) if frame.has("hair") else roundf(sin((elapsed * 60.0 - 1.0) * 0.45))
	box(ci, -7, -41 - hair_motion, 7, 6, outline)
	box(ci, -5, -40 - hair_motion, 8, 5, gold_shadow)
	box(ci, -3, -42 - hair_motion, 7, 7, gold)
	box(ci, 1, -41 - hair_motion, 8, 6, gold_light)
	box(ci, 6, -39, 7, 5, gold_shadow)
	box(ci, 2, -40, 4, 3, c("#fff7cf"))

	if pose == "hurt":
		box(ci, 3, -34, 5, 2, outline)
		box(ci, 3, -31, 5, 2, skin_shadow)


static func _draw_generic(ci: CanvasItem, base: Transform2D, x: float, foot: float, f: FighterState,
		body_color: Color, frame: Dictionary, elapsed: float, victorious_match: bool) -> void:
	var definition := f.definition
	var pose := String(frame.get("pose", "idle"))
	var anim_name := String(frame.get("name", ""))
	var style := String(frame.get("style", ""))
	var victorious := pose == "victory" or victorious_match
	var scale := float(definition["sprite_scale"])
	var turn := -1.0 if frame.get("turn", false) else 1.0
	var xf := base * Transform2D(0.0, Vector2(x, foot)) \
		* Transform2D(0.0, Vector2(f.facing * scale * turn, scale * (1.0 - _num(frame, "squash"))), 0.0, Vector2.ZERO)
	if frame.has("lean") and _num(frame, "lean") != 0.0:
		xf = xf * Transform2D(_num(frame, "lean"), Vector2.ZERO)
	elif f.hurt_time > 0.0:
		xf = xf * Transform2D(-f.hit_direction * f.facing * 0.2, Vector2.ZERO)
	if f.id == "onix":
		xf = xf * Transform2D(0.0, Vector2(1.0, 1.0 + sin(elapsed * 1.8) * 0.012), 0.0, Vector2.ZERO)
	ci.draw_set_transform_matrix(xf)

	var outline := c(OUTLINE)
	var trim := c(String(definition["trim"]))
	var accent := c(String(definition["accent"]))
	var hair := c(String(definition["hair"]))
	var skin := c("#f1c39b")
	if f.white_flash > 0.0:
		skin = Color.WHITE
	elif f.hit_flash > 0.0:
		skin = c("#f2e7d2")
	var body := accent if f.awakening_time > 0.0 else body_color
	var blocking := pose == "block"
	var smear_or_impact := pose == "smear" or pose == "impact"
	var kick_type := String(frame.get("kick", ""))
	var punch_type := String(frame.get("punch", ""))
	var chain_kick := kick_type != "" and (pose == "kick" or smear_or_impact)
	var attacking := ATTACK_POSES.has(pose) and kick_type == ""
	var kick_pose := pose == "kick" or (anim_name == "finisher" and style == "sonic-kick" and smear_or_impact)
	var stomp_pose := style == "stomp" and smear_or_impact
	var arm := int(_num(frame, "arm"))
	var arm_reach := 0
	if attacking:
		arm_reach = 18 if arm == 2 else (12 if arm == 1 else 0)
	var stride := int(_num(frame, "leg")) if (pose == "walk" or pose == "run" or pose == "jump") else 0
	var sway := _num(frame, "sway")

	# Paleta con volumen: luz por delante, sombra por detrás (pixel art con 3 tonos).
	var body_dark := body.darkened(0.32)
	var body_light := body.lightened(0.28)
	var pants := body.darkened(0.55)
	var pants_light := body.darkened(0.35)
	var boot := c("#262838")
	var boot_light := c("#3d4156")
	var skin_shadow := skin.darkened(0.22)
	var glove := trim.darkened(0.08)
	var smear: bool = frame.get("smear", false)

	if pose == "down":
		# Tumbado boca arriba.
		box(ci, -21, -9, 42, 9, outline)
		box(ci, -19, -8, 14, 6, pants)
		box(ci, -6, -8, 16, 6, body)
		box(ci, -6, -8, 16, 2, body_light)
		box(ci, -8, -4, 5, 2, trim)
		box(ci, 10, -13, 12, 12, outline)
		box(ci, 11, -12, 10, 10, skin)
		box(ci, 11, -12, 10, 3, hair)
		box(ci, -21, -6, 4, 5, boot)
		return

	var jumping := pose == "jump"
	var moving := pose == "walk" or pose == "run"
	var stride_px := 3 if pose == "run" else 2
	var lift_back := (3 if pose == "run" else 2) if moving and stride > 0 else 0
	var lift_front := (3 if pose == "run" else 2) if moving and stride < 0 else 0
	# --- Pierna trasera (detrás del cuerpo) ---
	var back_x := -7 + stride * stride_px
	if jumping:
		box(ci, back_x - 1, -19, 8, 11, outline)
		box(ci, back_x, -18, 6, 9, pants)
		box(ci, back_x - 3, -10, 8, 6, outline)
		box(ci, back_x - 2, -9, 6, 4, boot)
	else:
		box(ci, back_x - 1, -19, 8, 16 - lift_back, outline)
		box(ci, back_x, -18, 6, 14 - lift_back, pants)
		box(ci, back_x, -11 - lift_back, 6, 2, pants_light)
		box(ci, back_x - 2, -5 - lift_back, 10, 5, outline)
		box(ci, back_x - 1, -4 - lift_back, 8, 3, boot)
	# --- Pierna delantera ---
	if chain_kick:
		_draw_chain_kick(ci, kick_type, pose, outline, trim, accent, smear)
	elif kick_pose:
		box(ci, 0, -20, 9, 8, outline)
		box(ci, 1, -19, 7, 6, pants)
		box(ci, 6, -22, 14, 7, outline)
		box(ci, 7, -21, 12, 5, pants_light)
		box(ci, 18, -23, 7, 8, outline)
		box(ci, 19, -22, 5, 5, accent)
	elif stomp_pose:
		box(ci, 1, -19, 9, 12, outline)
		box(ci, 2, -18, 7, 10, pants)
		box(ci, 2, -9, 12, 7, outline)
		box(ci, 3, -8, 10, 5, boot)
		box(ci, 3, -8, 10, 1, accent)
	else:
		var front_x := 1 - stride * stride_px
		if jumping:
			box(ci, front_x - 1, -19, 8, 9, outline)
			box(ci, front_x, -18, 6, 7, pants_light)
			box(ci, front_x + 2, -12, 8, 7, outline)
			box(ci, front_x + 3, -11, 6, 5, boot)
			box(ci, front_x + 3, -11, 6, 1, boot_light)
		else:
			box(ci, front_x - 1, -19, 8, 16 - lift_front, outline)
			box(ci, front_x, -18, 6, 14 - lift_front, pants_light)
			box(ci, front_x + 4, -18, 2, 14 - lift_front, pants)
			box(ci, front_x - 1, -5 - lift_front, 10, 5, outline)
			box(ci, front_x, -4 - lift_front, 9, 3, boot)
			box(ci, front_x, -4 - lift_front, 9, 1, boot_light)
	# De la cintura hacia arriba respira (idle) y rebota al andar; las piernas no se mueven.
	var upper_bob := _num(frame, "bob")
	if moving:
		upper_bob += absf(stride) * (1.0 if pose == "run" else 0.5)
	ci.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(0.0, upper_bob)))
	# --- Brazo trasero ---
	if not blocking and not (victorious and VICTORY_TWO_ARMS.has(f.id)):
		var back_arm_y := -31 + (arm * 2 if (pose == "walk" or pose == "run") else 0)
		box(ci, -12, back_arm_y, 6, 13, outline)
		box(ci, -11, back_arm_y + 1, 4, 10, body_dark)
		box(ci, -12, back_arm_y + 10, 6, 5, outline)
		box(ci, -11, back_arm_y + 11, 4, 3, glove.darkened(0.25))
	# --- Cadera y cinturón ---
	box(ci, -9, -21, 18, 5, outline)
	box(ci, -8, -20, 16, 3, trim)
	box(ci, -1, -20, 3, 3, accent)
	# --- Torso con volumen ---
	box(ci, -9, -35, 18, 16, outline)
	box(ci, -8, -34, 16, 14, body)
	box(ci, 3, -34, 4, 13, body_light)
	box(ci, -8, -34, 3, 14, body_dark)
	box(ci, -5, -26, 10, 1, body_dark)
	box(ci, 0, -31, 3, 3, accent)
	box(ci, 1, -30, 1, 1, c("#ffffff"))
	# Hombrera trasera
	box(ci, -12, -36, 7, 6, outline)
	box(ci, -11, -35, 5, 4, body_dark)
	box(ci, -11, -35, 5, 1, trim)
	# --- Cuello y cabeza ---
	box(ci, -2, -37, 5, 3, skin_shadow)
	var hx := sway
	box(ci, -6 + hx, -48, 13, 13, outline)
	box(ci, -5 + hx, -47, 11, 11, skin)
	box(ci, -5 + hx, -47, 3, 11, skin_shadow)
	# Ojo, ceja y boca mirando al frente
	var eye_y := -43
	if pose == "hurt":
		box(ci, 2 + hx, eye_y, 3, 1, outline)
		box(ci, 3 + hx, eye_y + 4, 2, 1, outline)
	else:
		box(ci, 2 + hx, eye_y - 1, 4, 1, hair.darkened(0.2))
		box(ci, 3 + hx, eye_y, 2, 2, outline)
		box(ci, 4 + hx, eye_y, 1, 1, accent.lightened(0.4))
		box(ci, 3 + hx, eye_y + 4, 2, 1, skin_shadow.darkened(0.2))
	# Pelo base (gorra de pelo y nuca)
	box(ci, -6 + hx, -50, 13, 5, outline)
	box(ci, -5 + hx, -49, 11, 4, hair)
	box(ci, -1 + hx, -49, 5, 1, hair.lightened(0.25))
	box(ci, -7 + hx, -47, 4, 8, outline)
	box(ci, -6 + hx, -46, 3, 6, hair)

	# --- Brazo delantero según la pose ---
	if blocking:
		box(ci, 1, -45, 8, 15, outline)
		box(ci, 2, -44, 6, 12, body)
		box(ci, 2, -44, 6, 2, body_light)
		box(ci, 1, -48, 9, 6, outline)
		box(ci, 2, -47, 7, 4, glove)
		box(ci, 6, -40, 8, 12, outline)
		box(ci, 7, -39, 6, 9, body_light)
		box(ci, 6, -43, 9, 6, outline)
		box(ci, 7, -42, 7, 4, glove)
		var shine := 0.5 + 0.5 * sin(elapsed * 12.0)
		var guard_glow := accent
		guard_glow.a = 0.25 + shine * 0.2
		box(ci, 15, -48, 2, 22, guard_glow)
	elif f.special_charge > 0.0 and f.id == "onix":
		box(ci, 6, -40, 7, 22, outline)
		box(ci, 7, -39, 5, 19, body)
		box(ci, 3, -45, 13, 7, outline)
		box(ci, 4, -44, 11, 5, skin)
	elif f.special_charge > 0.0 and CHARGE_ARM_FIGHTERS.has(f.id):
		var ped := f.id == "pedernal"
		box(ci, 6, -30 if ped else -42, 7, 12 if ped else 22, outline)
		box(ci, 7, -29 if ped else -41, 5, 10 if ped else 19, body)
		box(ci, 5, -35 if ped else -47, 10, 7, outline)
		box(ci, 6, -34 if ped else -46, 8, 5, glove)
		var pulse := accent
		pulse.a = 0.35 + 0.25 * sin(elapsed * 30.0)
		box(ci, 3, (-39 if ped else -51), 14, 3, pulse)
	elif victorious and VICTORY_POSES.has(f.id):
		_draw_victory_arms(ci, f.id, arm, elapsed, outline, body, body_light, glove, accent)
	elif victorious or pose == "intro":
		var raised := 25 if arm == 2 else (17 if arm == 1 else 0)
		box(ci, 6, -36 - raised, 8, 22 + raised, outline)
		box(ci, 7, -35 - raised, 6, 19 + raised, body)
		box(ci, 11, -35 - raised, 2, 19 + raised, body_light)
		box(ci, 5, -42 - raised, 10, 8, outline)
		box(ci, 6, -41 - raised, 8, 6, glove)
	elif attacking and not kick_pose:
		var arm_y := -32
		match style:
			"rising-wave":
				arm_y = -42
			"stomp":
				arm_y = -28
			"light-palm":
				arm_y = -35
			"lance":
				arm_y = -34
		var meteor := style == "meteor-fist" and punch_type == ""
		var fist_reach := arm_reach + 5 if meteor else arm_reach
		if punch_type == "hook":
			arm_y = -36
			fist_reach -= 2
		elif punch_type == "cross":
			fist_reach += 3
		elif punch_type == "jab":
			arm_y = -32
		if punch_type == "upper":
			var top := -44 - (5 if arm >= 2 else 1)
			box(ci, 5, top, 8, -26 - top, outline)
			box(ci, 6, top + 1, 6, -28 - top, body)
			box(ci, 10, top + 1, 2, -28 - top, body_light)
			box(ci, 3, top - 7, 11, 9, outline)
			box(ci, 4, top - 6, 9, 7, glove)
			box(ci, 4, top - 6, 9, 2, glove.lightened(0.3))
			if smear:
				var saved_up := alpha
				alpha = saved_up * 0.7
				box(ci, 6, top - 14, 5, 7, accent)
				box(ci, 7, top - 19, 3, 5, trim)
				alpha = saved_up
		else:
			# Hombrera delantera + brazo completo hasta el guante.
			box(ci, 3, arm_y - 3, 8, 7, outline)
			box(ci, 4, arm_y - 2, 6, 5, body_light)
			box(ci, 7, arm_y - 1, fist_reach + 9, 7, outline)
			box(ci, 8, arm_y, fist_reach + 7, 5, body)
			box(ci, 8, arm_y, fist_reach + 7, 1, body_light)
			var fist_w := 10 if meteor else 8
			box(ci, 14 + fist_reach, arm_y - 2, fist_w + 1, 9 if meteor else 8, outline)
			box(ci, 15 + fist_reach, arm_y - 1, fist_w - 1, 7 if meteor else 6, skin if style == "light-palm" else glove)
			box(ci, 15 + fist_reach, arm_y - 1, fist_w - 1, 2, (skin if style == "light-palm" else glove).lightened(0.3))
			if smear:
				var saved := alpha
				alpha = saved * 0.7
				box(ci, 22 + fist_reach, arm_y, 16 if meteor else 11, 4, accent)
				box(ci, 24 + fist_reach, arm_y + 1, 8, 2, c("#ffffff"))
				if punch_type == "hook":
					box(ci, 12 + fist_reach, arm_y - 6, 8, 3, accent)
				alpha = saved
			elif pose == "impact":
				var spark := c("#ffffff")
				spark.a = 0.8
				box(ci, 23 + fist_reach, arm_y - 3, 2, 2, spark)
				box(ci, 25 + fist_reach, arm_y + 4, 2, 2, accent)
	else:
		# Guardia: puño delantero a la altura de la barbilla, se balancea al andar.
		var swing := 0
		if pose == "walk" or pose == "run":
			swing = arm * 2
		var guard_y := -40 + swing
		if jumping:
			guard_y = -44
		box(ci, 3, -36, 8, 7, outline)
		box(ci, 4, -35, 6, 5, body_light)
		box(ci, 6, guard_y + 3, 7, -30 - guard_y, outline)
		box(ci, 7, guard_y + 4, 5, -32 - guard_y, body)
		box(ci, 7, guard_y - 1, 9, 7, outline)
		box(ci, 8, guard_y, 7, 5, glove)
		box(ci, 8, guard_y, 7, 1, glove.lightened(0.3))

	match String(definition["look"]):
		"crest":
			var flame := 1.0 if sin(elapsed * 33.0) > 0.0 else 0.0
			box(ci, -7, -55, 4, 7, hair)
			box(ci, -3, -56 - flame, 4, 9 + flame, hair)
			box(ci, 2, -56 - flame, 5, 9 + flame, accent)
			box(ci, 7, -54, 4, 6, hair)
			box(ci, 3, -54 - flame, 2, 5, c("#fff4bd"))
		"spikes":
			box(ci, -6, -54, 4, 6, hair)
			box(ci, -1, -57, 4, 9, hair)
			box(ci, 4, -54, 4, 6, hair)
		"hood":
			# Capucha de la guardiana: tela sobre la cabeza y caída por la espalda.
			box(ci, -8 + hx, -52, 16, 6, outline)
			box(ci, -7 + hx, -51, 14, 4, accent)
			box(ci, -7 + hx, -51, 14, 1, accent.lightened(0.3))
			box(ci, -10, -48, 5, 22, outline)
			box(ci, -9, -47, 3, 20, c(String(definition["color"])).darkened(0.2))
			box(ci, -6 + hx, -36, 12, 3, accent)
		"mantle":
			# Manto del artillero: capa larga a ambos lados.
			box(ci, -13, -36, 5, 24, outline)
			box(ci, -12, -35, 3, 22, accent.darkened(0.15))
			box(ci, -12, -35, 1, 22, accent)
			box(ci, -4 + hx, -54, 9, 5, hair)
			box(ci, -9, -37, 18, 3, accent)
		"mask":
			# Antifaz y mechón del ilusionista.
			box(ci, -5 + hx, -45, 12, 4, outline)
			box(ci, -4 + hx, -44, 10, 2, accent)
			box(ci, 3 + hx, -44, 2, 1, c("#ffffff"))
			box(ci, -5 + hx, -54, 10, 5, hair)
			box(ci, 4 + hx, -52, 5, 7, hair.lightened(0.15))
		"shoulders":
			# Hombreras de roca del titán.
			box(ci, -15, -39, 9, 9, outline)
			box(ci, -14, -38, 7, 7, accent.darkened(0.25))
			box(ci, -14, -38, 7, 2, accent)
			box(ci, 5, -39, 9, 9, outline)
			box(ci, 6, -38, 7, 7, accent.darkened(0.1))
			box(ci, 6, -38, 7, 2, accent.lightened(0.2))
			box(ci, -7 + hx, -54, 15, 6, hair)
		"ribbon":
			# Cinta que ondea detrás de la cabeza.
			var flutter := roundf(sin(elapsed * 6.0) * 2.0)
			box(ci, -12, -46 + flutter, 7, 3, accent)
			box(ci, -16, -44 + flutter, 5, 3, accent.darkened(0.15))
			box(ci, -5 + hx, -53, 10, 4, hair)
			box(ci, -6 + hx, -47, 12, 2, accent)
		"crown":
			box(ci, -7, -55, 15, 4, outline)
			box(ci, -6, -54, 13, 2, accent.darkened(0.2))
			box(ci, -6, -58, 4, 6, accent)
			box(ci, -1, -61, 4, 9, accent)
			box(ci, 4, -58, 4, 6, accent)
			box(ci, 0, -59, 2, 2, c("#fff2b0"))
	if victorious:
		box(ci, -7, -62, 4, 5, accent)
		box(ci, 0, -66, 4, 5, c("#fff4bc"))
		box(ci, 6, -62, 4, 5, accent)


## Luchadores con pose de victoria propia (los demás levantan el puño).
const VICTORY_POSES := ["marea", "cobalto", "espejo", "pedernal", "luma"]
## Poses que dibujan los dos brazos (se omite el brazo trasero normal).
const VICTORY_TWO_ARMS := ["marea", "pedernal", "luma"]


static func _draw_victory_arms(ci: CanvasItem, id: String, arm: int, elapsed: float, outline: Color, body: Color,
		body_light: Color, glove: Color, accent: Color) -> void:
	match id:
		"marea":
			# Brazos cruzados, tranquila; la capucha ondea.
			box(ci, -9, -32, 18, 6, outline)
			box(ci, -8, -31, 16, 4, body_light)
			box(ci, -10, -28, 20, 6, outline)
			box(ci, -9, -27, 18, 4, body)
			box(ci, 7, -33, 5, 5, glove)
			box(ci, -11, -28, 5, 5, glove)
		"cobalto":
			# Señala al frente como si apuntara su lanza.
			box(ci, 3, -36, 8, 7, outline)
			box(ci, 4, -35, 6, 5, body_light)
			box(ci, 8, -34, 16, 6, outline)
			box(ci, 9, -33, 14, 4, body)
			box(ci, 22, -35, 7, 7, outline)
			box(ci, 23, -34, 5, 5, glove)
			box(ci, 28, -33, 4, 2, glove)
			if fmod(elapsed, 1.2) < 0.25:
				box(ci, 33, -36, 2, 8, accent)
				box(ci, 30, -33, 8, 2, accent)
		"espejo":
			# Saluda con la mano en alto, moviéndola de lado a lado.
			var wave := roundf(sin(elapsed * 8.0) * 2.0)
			box(ci, 3, -36, 8, 7, outline)
			box(ci, 4, -35, 6, 5, body_light)
			box(ci, 7 + wave, -50, 6, 16, outline)
			box(ci, 8 + wave, -49, 4, 14, body)
			box(ci, 6 + wave, -56, 8, 7, outline)
			box(ci, 7 + wave, -55, 6, 5, glove)
		"pedernal":
			# Doble bíceps: los dos puños arriba.
			var flex := 1 if arm >= 1 else 0
			for side: float in [-1.0, 1.0]:
				var sx := 8.0 if side > 0 else -17.0
				box(ci, sx - 1, -37, 10, 7, outline)
				box(ci, sx, -36, 8, 5, body_light if side > 0 else body)
				var fx := sx + (6.0 if side > 0 else -3.0)
				box(ci, fx - 1, -48 - flex, 7, 13, outline)
				box(ci, fx, -47 - flex, 5, 11, body)
				box(ci, fx - 2, -53 - flex, 9, 7, outline)
				box(ci, fx - 1, -52 - flex, 7, 5, glove)
		"luma":
			# Manos juntas delante del pecho con destellos de luz.
			box(ci, -1, -34, 14, 8, outline)
			box(ci, 0, -33, 12, 6, body)
			box(ci, 9, -38, 7, 9, outline)
			box(ci, 10, -37, 5, 7, glove)
			for i in range(4):
				var ang := elapsed * 3.0 + i * TAU / 4.0
				var px := 12.0 + cos(ang) * 9.0
				var py := -34.0 + sin(ang) * 9.0
				box(ci, px, py, 2, 2, accent if i % 2 == 0 else c("#ffffff"))


## Pierna delantera de las patadas de cadena (luchadores de rectángulos).
## kick: "low" | "mid" | "high" | "spin"; en la pose "kick" la rodilla sube preparando.
static func _draw_chain_kick(ci: CanvasItem, kick_type: String, pose: String, outline: Color, trim: Color,
		accent: Color, smear: bool) -> void:
	if pose == "kick":
		box(ci, 1, -16, 10, 9, outline)
		box(ci, 2, -15, 8, 7, trim)
		box(ci, 6, -9, 6, 6, outline)
		box(ci, 7, -8, 4, 4, accent)
		return
	var y := -18
	var reach := 22
	match kick_type:
		"low":
			y = -9
			reach = 20
		"high":
			y = -31
			reach = 18
		"spin":
			y = -27
			reach = 24
	if kick_type == "high" or kick_type == "spin":
		# Pierna en diagonal desde la cadera hasta el pie.
		var steps: Array = [Vector2(0, -13), Vector2(6, -20), Vector2(12, -27)] if kick_type == "high" 			else [Vector2(0, -12), Vector2(7, -17), Vector2(14, -22)]
		for st in steps:
			box(ci, st.x, st.y, 10, 8, outline)
		for st in steps:
			box(ci, st.x + 1, st.y + 1, 8, 6, trim)
		var tip: Vector2 = steps[steps.size() - 1] + Vector2(9, -2)
		box(ci, tip.x, tip.y, 9, 8, outline)
		box(ci, tip.x + 1, tip.y + 1, 7, 5, accent)
		if smear:
			var saved_arc := alpha
			alpha = saved_arc * 0.6
			box(ci, tip.x - 10, tip.y - 6, 14, 3, accent)
			box(ci, tip.x - 18, tip.y - 1, 8, 3, trim)
			if kick_type == "spin":
				box(ci, tip.x - 26, tip.y + 6, 10, 3, accent)
			alpha = saved_arc
		return
	box(ci, 1, y, reach, 7, outline)
	box(ci, 2, y + 1, reach - 2, 5, trim)
	box(ci, reach - 1, y - 1, 8, 8, outline)
	box(ci, reach, y, 6, 5, accent)
	if smear:
		var saved := alpha
		alpha = saved * 0.6
		if kick_type == "high" or kick_type == "spin":
			box(ci, reach - 12, y - 6, 14, 3, accent)
			box(ci, reach - 20, y - 2, 8, 3, trim)
		else:
			box(ci, reach - 18, y + 7, 16, 2, accent)
		alpha = saved


# --- Luchadores dibujados con imágenes --------------------------------------
# Un luchador usa imágenes si su entrada del catálogo tiene "sprites". Con solo dos
# imágenes (idle y stance) el movimiento se hace en código: embestidas, inclinaciones,
# estiramientos, estelas y rayos. Si más adelante añades imágenes para otras poses
# (attack, block, jump, hurt…), se usan automáticamente.

static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		if SpriteSheet.is_ref(path):
			# Cuadro de una hoja de sprites: "ruta.png#x,y,ancho,alto".
			_textures[path] = SpriteSheet.frame_texture(path)
		else:
			_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


## true si el luchador usa imágenes y su imagen "idle" se puede cargar.
static func has_sprites(definition: Dictionary) -> bool:
	if not definition.has("sprites"):
		return false
	return _sprite_available(definition["sprites"], "idle")


## Una clave de "sprites" puede ser una ruta o una lista de rutas (animación en bucle).
static func _sprite_available(sprites: Dictionary, key: String) -> bool:
	if not sprites.has(key):
		return false
	var value: Variant = sprites[key]
	if value is Array:
		return not value.is_empty() and _texture(String(value[0])) != null
	return _texture(String(value)) != null


## Ruta de la imagen que toca ahora. En las listas avanza un cuadro cada
## "sprite_frame_time" segundos (0.1 s si no se indica) y vuelve a empezar.
static func _sprite_path(definition: Dictionary, key: String, elapsed: float) -> String:
	var value: Variant = definition["sprites"][key]
	if not (value is Array):
		return String(value)
	var frames: Array = value
	var frame_times: Dictionary = definition.get("sprite_frame_time", {})
	var frame_time := maxf(0.016, float(frame_times.get(key, 0.1)))
	var index := posmod(int(floorf(elapsed / frame_time)), frames.size())
	return String(frames[index])


## Elige la imagen de la pose. Si no existe una específica, prueba la siguiente de la lista.
static func _sprite_key(sprites: Dictionary, pose: String, anim_name: String, frame: Dictionary, elapsed: float) -> String:
	var candidates: Array = ["idle"]
	if anim_name == "hurt":
		candidates = ["hurt", "idle"]
	elif pose == "anticipate" or pose == "recover":
		# Preparación y recuperación del golpe: postura de guardia.
		candidates = [anim_name + "_" + pose, "stance", "idle"]
	elif SPRITE_ATTACK_POSES.has(pose):
		candidates = [anim_name + "_" + pose, anim_name]
		if SPRITE_STRIKE_ALIAS.has(anim_name):
			var alias := String(SPRITE_STRIKE_ALIAS[anim_name])
			# La patada en preparación (pose "kick") usa el primer cuadro; el impacto, el segundo.
			if pose == "smear" or pose == "impact":
				candidates.append(alias + "_impact")
			candidates.append(alias)
		candidates.append_array(["attack", "stance", "idle"])
	elif pose == "charge" or pose == "special-anticipate":
		candidates = ["charge", "stance", "idle"]
	elif SPRITE_SPECIAL_POSES.has(pose):
		candidates = ["special", "stance", "idle"]
	else:
		match pose:
			"block":
				candidates = ["block", "stance", "idle"]
			"walk":
				candidates = ["walk", "idle"]
			"run":
				# Ciclo de carrera de dos imágenes (cada una dura medio ciclo).
				candidates = ["run", "walk", "idle"]
				if int(frame.get("index", 0)) >= 2:
					candidates.push_front("run_alt")
			"jump":
				candidates = ["jump", "idle"]
			"hurt":
				candidates = ["hurt", "idle"]
			"fall", "getup":
				candidates = ["fall", "hurt", "idle"]
			"down":
				candidates = ["down", "fall", "hurt", "idle"]
			"victory":
				candidates = ["victory", "idle"]
			"intro":
				candidates = ["intro", "idle"]
	for key in candidates:
		if _sprite_available(sprites, key):
			return key
	return "idle"


## Devuelve [punto de anclaje en píxeles, unidades del sprite por píxel] de una imagen.
## "sprite_anchor" puede ser un Vector2 para todas o un Dictionary por clave de imagen.
static func _sprite_metrics(definition: Dictionary, tex: Texture2D, key: String = "idle") -> Array:
	var anchor := Vector2(tex.get_width() / 2.0, tex.get_height())
	var anchor_data: Variant = definition.get("sprite_anchor", null)
	if anchor_data is Dictionary:
		anchor_data = anchor_data.get(key, anchor_data.get("idle", null))
	if anchor_data is Vector2:
		anchor = anchor_data
	var units_per_pixel := float(definition.get("sprite_height", 60.0)) / float(tex.get_height())
	return [anchor, units_per_pixel]


## Desplazamiento de la cara respecto a los luchadores de rectángulos, en unidades
## del sprite. FighterPortrait lo usa para centrar la cabeza en los retratos.
static func portrait_head_offset(definition: Dictionary) -> Vector2:
	if not has_sprites(definition) or not definition.has("sprite_head"):
		return Vector2.ZERO
	var sprites: Dictionary = definition["sprites"]
	var metrics := _sprite_metrics(definition, _texture(String(sprites["idle"])))
	var head: Vector2 = definition["sprite_head"]
	var anchor: Vector2 = metrics[0]
	return (head - anchor) * float(metrics[1]) - GENERIC_HEAD


static func _draw_sprite(ci: CanvasItem, base: Transform2D, x: float, foot: float, f: FighterState,
		frame: Dictionary, elapsed: float, victorious_match: bool) -> void:
	var definition := f.definition
	var sprites: Dictionary = definition["sprites"]
	var pose := String(frame.get("pose", "idle"))
	var anim_name := String(frame.get("name", ""))
	# AnimadorProcedural (si lo hay) se encarga del movimiento; aquí solo se aplica.
	var proc := procedural
	var animated := not proc.is_empty()
	var knockdown_pose := pose == "fall" or pose == "down" or pose == "getup"
	var key := _sprite_key(sprites, pose, anim_name, frame, elapsed)
	if animated and bool(proc.get("ko", false)) and knockdown_pose:
		# K.O.: el animador tumba al luchador desde la imagen de pie (su función ko()).
		pose = "ko"
		key = "idle"
		knockdown_pose = false
	var tex := _texture(_sprite_path(definition, key, elapsed))
	var metrics := _sprite_metrics(definition, tex, key)
	# Si la imagen ya muestra el movimiento (puñetazo, patada, carrera…), el código
	# solo lo acompaña un poco en vez de simularlo entero.
	var dedicated := key != "idle" and key != "stance"
	var anchor: Vector2 = metrics[0]
	var upp: float = metrics[1]
	var size := Vector2(tex.get_width(), tex.get_height()) * upp
	var rect := Rect2(-anchor * upp, size)
	var scale := float(definition["sprite_scale"])
	var arm := int(_num(frame, "arm"))
	var leg := int(_num(frame, "leg"))
	var bob := _num(frame, "bob")
	var style := String(frame.get("style", ""))
	var smear: bool = frame.get("smear", false)
	var kick_pose := pose == "kick" or (anim_name == "finisher" and style == "sonic-kick" and (pose == "smear" or pose == "impact")) \
		or (frame.has("kick") and (pose == "smear" or pose == "impact"))
	var lean := _num(frame, "lean")
	if lean == 0.0 and f.hurt_time > 0.0:
		lean = -f.hit_direction * f.facing * 0.2

	# Movimiento hecho en código: embestida (dx), estiramiento (sx, sy) e inclinación.
	var dx := 0.0
	var sx := 1.0
	var sy := 1.0
	match pose:
		"idle":
			sy = 1.0 - bob * 0.008
			sx = 1.0 + bob * 0.004
		"walk":
			sy = 1.0 - absf(leg) * 0.018
			lean += leg * 0.025
		"run":
			sy = 1.0 - absf(leg) * 0.025
		"jump":
			if leg > 0:
				sx = 0.95
				sy = 1.06
			elif leg < 0:
				sx = 1.03
				sy = 0.97
		"anticipate", "special-anticipate":
			dx = -2.0
			sx = 1.02
			sy = 0.97
		"punch":
			dx = 3.0
		"smear", "impact", "special-impact":
			dx = 9.0 if kick_pose else (7.0 if arm >= 2 else 4.0)
			sx = 1.04
		"special-launch":
			dx = 4.0 * arm
		"recover", "special-recover":
			dx = 2.0 if arm >= 1 else 0.0
		"block":
			dx = -2.0
			lean -= 0.05
		"charge":
			dx = roundf(sin(elapsed * 70.0)) * 0.7
			sy = 0.98
		"victory":
			sy = 1.0 + arm * 0.015
		"intro":
			dx = arm * 1.0
	if frame.has("squash") and not dedicated:
		sy *= 1.0 - _num(frame, "squash") * 0.7
		sx *= 1.0 + _num(frame, "squash") * 0.15
	if dedicated:
		dx *= 0.35
		if pose == "run" or pose == "jump" or SPRITE_ATTACK_POSES.has(pose):
			lean *= 0.3
	var anim_xf := Transform2D.IDENTITY
	if animated:
		# Con animador, su movimiento sustituye al de aquí (salvo los derribos, que
		# siguen la física de la simulación). Sus distancias están en píxeles de la imagen.
		if not knockdown_pose:
			dx = 0.0
			sx = 1.0
			sy = 1.0
			lean = 0.0
		var desp: Vector2 = proc["desp"]
		var esc: Vector2 = proc["escala"]
		anim_xf = Transform2D(0.0, desp * upp) * Transform2D(deg_to_rad(float(proc["rot"])), Vector2.ZERO) \
			* Transform2D(0.0, esc, 0.0, Vector2.ZERO)

	# Cuadro de giro (patada giratoria): la imagen se voltea un instante.
	var turn := -1.0 if frame.get("turn", false) else 1.0
	var root := base * Transform2D(0.0, Vector2(x, foot)) \
		* Transform2D(0.0, Vector2(f.facing * scale * turn, scale), 0.0, Vector2.ZERO)
	var xf: Transform2D
	if pose == "down":
		# Tumbado boca arriba: se gira 90° hacia atrás y se aplana para que no quede tan alto.
		var flat := 0.55
		xf = root * Transform2D(0.0, Vector2(size.y * 0.5, -anchor.x * upp * flat)) \
			* Transform2D(-PI / 2.0, Vector2.ZERO) * Transform2D(0.0, Vector2(flat, 1.0), 0.0, Vector2.ZERO)
	else:
		# Al inclinarse se eleva un poco para que los pies no atraviesen el suelo.
		var lift := 0.0
		if lean < 0.0:
			lift = (anchor.x - 10.0) * upp * sin(-lean)
		elif lean > 0.0:
			lift = (tex.get_width() - 20.0 - anchor.x) * upp * sin(lean)
		xf = root * Transform2D(0.0, Vector2(dx, -lift)) * Transform2D(lean, Vector2.ZERO) \
			* Transform2D(0.0, Vector2(sx, sy), 0.0, Vector2.ZERO) * anim_xf
		var tweak := _move_tweak(anim_name, key)
		if not tweak.is_empty():
			var ph := float(tweak.get("pivot", 0.45)) * float(definition.get("sprite_height", 60.0))
			xf = xf * Transform2D(0.0, Vector2(0.0, -ph)) * Transform2D(float(tweak.get("rot", 0.0)), Vector2.ZERO) \
				* Transform2D(0.0, Vector2(0.0, ph)) * Transform2D(0.0, Vector2(1.0, float(tweak.get("sy", 1.0))), 0.0, Vector2.ZERO)

	var accent := c(String(definition["accent"]))
	var tint := Color(1.0, 1.0, 1.0, alpha)
	if f.white_flash > 0.0:
		tint = Color(3.0, 3.0, 3.0, alpha)
	elif f.hit_flash > 0.0:
		tint = Color(1.8, 1.55, 1.55, alpha)
	elif f.awakening_time > 0.0:
		tint = Color(0.85, 1.12, 1.35, alpha)
	if animated:
		var proc_color: Color = proc["color"]
		if proc_color != Color.WHITE:
			tint = Color(proc_color.r, proc_color.g, proc_color.b, proc_color.a * alpha)

	# Estela eléctrica detrás al correr y al golpear.
	if smear and (pose == "run" or pose == "smear" or pose == "impact" or pose == "special-launch"):
		ci.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(-8.0, 0.0)))
		ci.draw_texture_rect(tex, rect, false, Color(accent.r, accent.g, accent.b, 0.35 * alpha))
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture_rect(tex, rect, false, tint)

	if pose == "down" or pose == "ko":
		return
	var fists: Dictionary = definition.get("sprite_fist", {})
	# Solo idle y stance tienen puño marcado: las demás imágenes ya traen sus propios rayos.
	var fist_px: Vector2 = fists.get(key, Vector2(-1.0, -1.0))
	if fist_px.x >= 0.0:
		_draw_sprite_sparks(ci, (fist_px - anchor) * upp, pose, arm, smear, elapsed, accent)
	if pose == "victory" or victorious_match:
		var white := c("#efffff")
		var step := floorf(elapsed * 12.0)
		for i in range(4):
			var angle := step * 0.9 + i * TAU / 4.0
			box(ci, cos(angle) * 26.0, -32.0 + sin(angle) * 30.0, 2, 5, accent if i % 2 == 0 else white)


## Ajuste de pose (SPRITE_MOVE_POSE) si el golpe se dibuja con la imagen de otro golpe.
static func _move_tweak(anim_name: String, key: String) -> Dictionary:
	if not SPRITE_MOVE_POSE.has(anim_name) or not SPRITE_STRIKE_ALIAS.has(anim_name):
		return {}
	var alias := String(SPRITE_STRIKE_ALIAS[anim_name])
	if key != alias and key != alias + "_impact":
		return {}
	return SPRITE_MOVE_POSE[anim_name]


## Rayos alrededor del puño: chispazos sueltos, carga y descarga al golpear.
static func _draw_sprite_sparks(ci: CanvasItem, fist: Vector2, pose: String, arm: int, smear: bool,
		elapsed: float, accent: Color) -> void:
	var white := c("#efffff")
	if smear and (SPRITE_ATTACK_POSES.has(pose) or pose == "special-launch"):
		var length := 20.0 if arm >= 2 else 12.0
		_draw_bolt(ci, fist + Vector2(2.0, 0.0), length, elapsed, accent, 3.0)
		_draw_bolt(ci, fist + Vector2(2.0, 0.0), length, elapsed + 0.5, white, 1.0)
	elif pose == "impact" or pose == "special-impact":
		var saved := alpha
		alpha = saved * 0.8
		box(ci, fist.x - 3.0, fist.y - 3.0, 7, 7, accent)
		box(ci, fist.x - 1.0, fist.y - 1.0, 3, 3, white)
		alpha = saved
	if pose == "charge" or fmod(elapsed, 0.55) < 0.14:
		var step := floorf(elapsed * 20.0)
		for i in range(3 if pose == "charge" else 2):
			var angle := step * 1.7 + i * 2.1
			var p := fist + Vector2(cos(angle), sin(angle)) * (4.0 + i * 2.0)
			box(ci, p.x, p.y, 2, 2, white if i % 2 == 0 else accent)


## Rayo horizontal en zigzag hacia delante.
static func _draw_bolt(ci: CanvasItem, from: Vector2, length: float, seed_value: float, color: Color, thickness: float) -> void:
	var steps := maxi(2, int(length / 4.0))
	var p := from
	for i in range(steps):
		var jitter := roundf(sin(seed_value * 13.0 + i * 2.7) * 2.0)
		box(ci, p.x, p.y + jitter - thickness / 2.0, 4, thickness, color)
		p.x += 4.0


## Armadura espectral de Volt durante su despertar (drawVoltArmor).
static func draw_volt_armor(ci: CanvasItem, x: float, foot: float, elapsed: float) -> void:
	var pulse := sin(elapsed * 18.0)
	var offset := roundf(pulse * 2.0)
	var saved := alpha
	alpha = saved * (0.3 + absf(pulse) * 0.1)
	ellipse(ci, Vector2(x, foot - 58), 34 + roundf((pulse + 1.0) * 2.0), 61, c("#d6fff5"), 3.0)
	var shape := PackedVector2Array([
		Vector2(x - 14, foot - 111 - offset), Vector2(x - 19, foot - 101), Vector2(x - 31, foot - 94),
		Vector2(x - 37, foot - 78), Vector2(x - 29, foot - 73), Vector2(x - 23, foot - 52),
		Vector2(x - 17, foot - 27), Vector2(x - 10, foot - 10), Vector2(x + 11, foot - 10),
		Vector2(x + 18, foot - 28), Vector2(x + 25, foot - 53), Vector2(x + 32, foot - 73),
		Vector2(x + 39, foot - 79), Vector2(x + 32, foot - 94), Vector2(x + 19, foot - 101),
		Vector2(x + 13, foot - 111 - offset), Vector2(x + 6, foot - 100), Vector2(x - 6, foot - 100),
	])
	var fill := c("#153b57")
	fill.a *= alpha
	ci.draw_colored_polygon(shape, fill)
	var closed := shape.duplicate()
	closed.append(shape[0])
	var stroke := c("#66f1df")
	stroke.a *= alpha
	ci.draw_polyline(closed, stroke, 3.0)
	var blue := c("#2755a3")
	box(ci, x - 30, foot - 91, 13, 14, blue)
	box(ci, x + 17, foot - 91, 13, 14, blue)
	box(ci, x - 18, foot - 76, 36, 27, blue)
	box(ci, x - 13, foot - 45, 10, 22, blue)
	box(ci, x + 4, foot - 45, 10, 22, blue)
	box(ci, x - 10, foot - 105 - offset, 20, 15, c("#1b293e"))
	box(ci, x - 8, foot - 99 - offset, 16, 3, c("#d6fff5"))
	box(ci, x - 14, foot - 115 - offset, 7, 12, c("#66f1df"))
	box(ci, x + 7, foot - 115 - offset, 7, 12, c("#66f1df"))
	box(ci, x - 5, foot - 73, 10, 14, c("#d6fff5"))
	box(ci, x - 3, foot - 70, 6, 8, c("#ffcf70"))
	box(ci, x - 34, foot - 81, 5, 8, c("#d6fff5"))
	box(ci, x + 30, foot - 81, 5, 8, c("#d6fff5"))
	alpha = saved
