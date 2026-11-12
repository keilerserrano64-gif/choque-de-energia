class_name FighterAnimations
extends RefCounted
## Datos de animación por cuadros (60 cuadros = 1 segundo) y cajas de golpe.
## Equivale a src/animations.js. Cada cuadro es un Dictionary con:
##   duration (cuadros), pose (String) y detalles opcionales: bob, sway, arm, leg,
##   lean, smear, aura, hair, style, hitbox {x, y, w, h}.

## "like": id de otro luchador cuyos tiempos de animación se copian (lo pone el importador).
const ANIMATION_STYLES := {
	"kakashi": {"attack": "drive", "finisher": "sonic-kick", "special": "afterimage", "like": "volt"},
	"naruto": {"attack": "drive", "finisher": "sonic-kick", "special": "afterimage"},
	"ban": {"attack": "drive", "finisher": "sonic-kick", "special": "afterimage", "like": "naruto"},
	"todo": {"attack": "drive", "finisher": "sonic-kick", "special": "afterimage", "like": "naruto"},
	"adam": {"attack": "drive", "finisher": "sonic-kick", "special": "afterimage", "like": "naruto"},
	"madara": {"attack": "drive", "finisher": "sonic-kick", "special": "afterimage", "like": "naruto"},
	"madara_edo": {"attack": "drive", "finisher": "sonic-kick", "special": "afterimage", "like": "naruto"},
	"itachi": {"attack": "drive", "finisher": "sonic-kick", "special": "afterimage", "like": "naruto"},
}

static var _cache: Dictionary = {}


static func _f(duration: int, pose: String, details: Dictionary = {}) -> Dictionary:
	var frame := details.duplicate()
	frame["duration"] = duration
	frame["pose"] = pose
	return frame


static func _anim(loop: bool, frames: Array) -> Dictionary:
	return {"loop": loop, "frames": frames}


## Devuelve todas las animaciones de un luchador (idle, walk, run, jump, block,
## ataques, charge, special, hurt, fall, getup, victory, intro).
static func for_fighter(id: String) -> Dictionary:
	if not _cache.has(id):
		var set_: Dictionary = _brasa() if like(id) == "brasa" else _generic(id)
		set_.merge(_strikes(id), true)
		_cache[id] = set_
	return _cache[id]


static func get_animation(id: String, anim_name: String) -> Dictionary:
	var set_ := for_fighter(id)
	if set_.has(anim_name):
		return set_[anim_name]
	return set_["idle"]


static func duration(animation: Dictionary) -> int:
	var total := 0
	for frame in animation["frames"]:
		total += int(frame["duration"])
	return total


static func first_hitbox_frame(animation: Dictionary) -> int:
	var elapsed := 0
	for frame in animation["frames"]:
		if frame.has("hitbox"):
			return elapsed
		elapsed += int(frame["duration"])
	push_error("La animación de ataque no contiene una hitbox.")
	return 0


static func frame_at(animation: Dictionary, elapsed_frames: float) -> Dictionary:
	var total := duration(animation)
	var frame_time := int(floorf(elapsed_frames + 0.00000001))
	var time := 0
	if animation["loop"]:
		time = posmod(frame_time, total)
	else:
		time = clampi(frame_time, 0, total - 1)
	var remaining := time
	var frames: Array = animation["frames"]
	for index in range(frames.size()):
		var current: Dictionary = frames[index]
		if remaining < int(current["duration"]):
			var result := current.duplicate()
			result["index"] = index
			return result
		remaining -= int(current["duration"])
	var last: Dictionary = frames[frames.size() - 1].duplicate()
	last["index"] = frames.size() - 1
	return last


static func _brasa() -> Dictionary:
	var weak_box := {"x": 8, "y": 15, "w": 22, "h": 14}
	var strong_box := {"x": 10, "y": 17, "w": 29, "h": 14}
	var kick_box := {"x": 7, "y": 12, "w": 34, "h": 13}
	return {
		"idle": _anim(true, [
			_f(8, "idle", {"bob": 0, "hair": 0}), _f(8, "idle", {"bob": 1, "hair": 1}),
			_f(8, "idle", {"bob": 2, "hair": 1}), _f(8, "idle", {"bob": 1, "hair": 0}),
			_f(8, "idle", {"bob": 0, "hair": -1}), _f(8, "idle", {"bob": -1, "hair": 0}),
		]),
		"walk": _anim(true, [
			_f(4, "walk", {"arm": -1, "leg": 1}), _f(4, "walk", {"arm": -1, "leg": 0}),
			_f(4, "walk", {"arm": 0, "leg": -1}), _f(4, "walk", {"arm": 1, "leg": -1}),
			_f(4, "walk", {"arm": 1, "leg": 0}), _f(4, "walk", {"arm": 0, "leg": 1}),
		]),
		"run": _anim(true, [
			_f(3, "run", {"arm": -1, "leg": 1, "lean": 0.1, "smear": true}),
			_f(3, "run", {"arm": 0, "leg": 0, "lean": 0.14}),
			_f(3, "run", {"arm": 1, "leg": -1, "lean": 0.1, "smear": true}),
			_f(3, "run", {"arm": 0, "leg": 0, "lean": 0.14}),
		]),
		"jump": _anim(false, [
			_f(4, "jump", {"leg": 1, "arm": 1}), _f(4, "jump", {"leg": 0, "arm": 0}),
			_f(4, "jump", {"leg": -1, "arm": -1}),
		]),
		"block": _anim(true, [_f(5, "block", {"arms": 0}), _f(4, "block", {"arms": 1})]),
		"weak": _anim(false, [
			_f(3, "anticipate"),
			_f(2, "impact", {"arm": 2, "smear": true, "hitbox": weak_box}),
			_f(2, "impact", {"arm": 2, "hitbox": weak_box}),
			_f(7, "recover"),
		]),
		"strong": _anim(false, [
			_f(6, "anticipate", {"lean": -0.08}),
			_f(3, "punch", {"arm": 1, "lean": 0.06}),
			_f(2, "smear", {"arm": 2, "lean": 0.12, "smear": true, "hitbox": strong_box}),
			_f(8, "impact", {"arm": 2, "lean": 0.08, "hitbox": strong_box}),
			_f(5, "recover", {"arm": 1}),
			_f(4, "recover"),
		]),
		"kick": _anim(false, [
			_f(5, "anticipate", {"leg": -1}),
			_f(3, "kick", {"leg": 1}),
			_f(4, "smear", {"leg": 2, "smear": true, "hitbox": kick_box}),
			_f(6, "impact", {"leg": 2, "hitbox": kick_box}),
			_f(5, "recover"),
		]),
		"charge": _anim(true, [
			_f(4, "charge", {"aura": 1}), _f(4, "charge", {"aura": 2}),
			_f(4, "charge", {"aura": 3}), _f(4, "charge", {"aura": 2}),
		]),
		"special": _anim(false, [
			_f(5, "special-anticipate", {"arm": -1}),
			_f(3, "special-launch", {"arm": 1}),
			_f(3, "special-launch", {"arm": 2, "smear": true}),
			_f(6, "special-impact", {"arm": 2}),
			_f(5, "special-recover", {"arm": 1}),
			_f(4, "special-recover"),
		]),
		"hurt": _anim(false, [
			_f(3, "hurt", {"lean": -0.12}), _f(6, "hurt", {"lean": -0.22}), _f(4, "recover", {"lean": -0.08}),
		]),
		"fall": _anim(false, [
			_f(3, "fall", {"lean": -0.25}), _f(3, "fall", {"lean": -0.65}), _f(6, "fall", {"lean": -1.15}),
			_f(5, "down"), _f(5, "down"),
		]),
		"getup": _anim(false, [_f(4, "down"), _f(3, "getup", {"lean": -0.3}), _f(5, "idle")]),
		"victory": _anim(true, [
			_f(8, "victory", {"arm": 0, "hair": 0}), _f(5, "victory", {"arm": 1, "hair": 1}),
			_f(6, "victory", {"arm": 2, "hair": 2}), _f(8, "victory", {"arm": 2, "hair": 1}),
			_f(5, "victory", {"arm": 1, "hair": 0}), _f(6, "victory", {"arm": 0, "hair": -1}),
		]),
		"intro": _anim(true, [
			_f(6, "intro", {"arm": -1}), _f(8, "intro", {"arm": 0}), _f(6, "intro", {"arm": 1}),
			_f(8, "idle", {"arm": 1}), _f(6, "idle"), _f(8, "idle", {"hair": 1}),
		]),
	}


## Luchador cuyos tiempos de animación copia `id` (clave "like" de su estilo; los
## luchadores creados con el importador copian los de su base). Si no, él mismo.
static func like(id: String) -> String:
	return String((ANIMATION_STYLES.get(id, {}) as Dictionary).get("like", id))


static func _generic(fighter_id: String) -> Dictionary:
	var id := like(fighter_id)
	if not ANIMATION_STYLES.has(fighter_id):
		push_error("Estilo de animación desconocido: %s" % fighter_id)
		return _brasa()
	var style: Dictionary = ANIMATION_STYLES[fighter_id]
	var attack_style: String = style["attack"]
	var finisher_style: String = style["finisher"]
	var special_style: String = style["special"]
	var idle_bob := 0 if (id == "pedernal" or id == "onix") else 1
	var strike: Array = [2, 2, 2, 8, 4] if id == "volt" else [3, 2, 3, 7, 4]
	var finisher_x := 7 if (id == "pedernal" or id == "onix") else 9
	var base_box := {"x": 8, "y": 14, "w": 23, "h": 14}
	var strong_box := {"x": 9, "y": 15, "w": 28, "h": 15}
	var finisher_box := {"x": finisher_x, "y": 11, "w": 34 if id == "volt" else 31, "h": 18}
	return {
		"idle": _anim(true, [
			_f(8, "idle", {"bob": 0, "sway": 0}), _f(8, "idle", {"bob": idle_bob, "sway": 1}),
			_f(8, "idle", {"bob": idle_bob * 2, "sway": 0}), _f(8, "idle", {"bob": idle_bob, "sway": -1}),
			_f(8, "idle", {"bob": 0, "sway": 0}), _f(8, "idle", {"bob": -idle_bob, "sway": 1}),
		]),
		"walk": _anim(true, [
			_f(4, "walk", {"arm": -1, "leg": 1}), _f(4, "walk", {"arm": 0, "leg": 0}),
			_f(4, "walk", {"arm": 1, "leg": -1}), _f(4, "walk", {"arm": 1, "leg": -1}),
			_f(4, "walk", {"arm": 0, "leg": 0}), _f(4, "walk", {"arm": -1, "leg": 1}),
		]),
		"run": _anim(true, [
			_f(3, "run", {"arm": -1, "leg": 1, "lean": 0.1, "smear": true}),
			_f(3, "run", {"arm": 0, "leg": 0, "lean": 0.16}),
			_f(3, "run", {"arm": 1, "leg": -1, "lean": 0.1, "smear": true}),
			_f(3, "run", {"arm": 0, "leg": 0, "lean": 0.16}),
		]),
		"jump": _anim(false, [
			_f(4, "jump", {"arm": 1, "leg": 1}), _f(4, "jump", {"arm": 0, "leg": 0}),
			_f(4, "jump", {"arm": -1, "leg": -1}),
		]),
		"block": _anim(true, [_f(5, "block", {"arms": 0}), _f(4, "block", {"arms": 1})]),
		"light": _anim(false, [
			_f(strike[0], "anticipate", {"lean": -0.05, "style": attack_style}),
			_f(strike[1], "punch", {"arm": 1, "style": attack_style}),
			_f(strike[2], "impact", {"arm": 2, "smear": true, "hitbox": base_box, "style": attack_style}),
			_f(strike[3], "impact", {"arm": 2, "hitbox": base_box, "style": attack_style}),
			_f(strike[4], "recover", {"style": attack_style}),
		]),
		"heavy": _anim(false, [
			_f(6, "anticipate", {"lean": -0.1, "style": attack_style}),
			_f(3, "punch", {"arm": 1, "lean": 0.05, "style": attack_style}),
			_f(2, "smear", {"arm": 2, "lean": 0.12, "smear": true, "hitbox": strong_box, "style": attack_style}),
			_f(8, "impact", {"arm": 2, "lean": 0.08, "hitbox": strong_box, "style": attack_style}),
			_f(5, "recover", {"arm": 1, "style": attack_style}),
			_f(4, "recover", {"style": attack_style}),
		]),
		"finisher": _anim(false, [
			_f(6, "anticipate", {"lean": -0.12, "leg": -1, "style": finisher_style}),
			_f(3, "punch", {"arm": 1, "leg": 0, "style": finisher_style}),
			_f(3, "smear", {"arm": 2, "leg": 2, "smear": true, "hitbox": finisher_box, "style": finisher_style}),
			_f(7, "impact", {"arm": 2, "leg": 2, "hitbox": finisher_box, "style": finisher_style}),
			_f(5, "recover", {"arm": 1, "style": finisher_style}),
			_f(4, "recover", {"style": finisher_style}),
		]),
		"charge": _anim(true, [
			_f(4, "charge", {"aura": 1, "style": special_style}), _f(4, "charge", {"aura": 2, "style": special_style}),
			_f(4, "charge", {"aura": 3, "style": special_style}), _f(4, "charge", {"aura": 2, "style": special_style}),
		]),
		"special": _anim(false, [
			_f(5, "special-anticipate", {"arm": -1, "style": special_style}),
			_f(3, "special-launch", {"arm": 1, "style": special_style}),
			_f(3, "special-launch", {"arm": 2, "smear": true, "style": special_style}),
			_f(6, "special-impact", {"arm": 2, "style": special_style}),
			_f(5, "special-recover", {"arm": 1, "style": special_style}),
			_f(4, "special-recover", {"style": special_style}),
		]),
		"hurt": _anim(false, [
			_f(3, "hurt", {"lean": -0.12}), _f(6, "hurt", {"lean": -0.22}), _f(4, "recover", {"lean": -0.08}),
		]),
		"fall": _anim(false, [
			_f(3, "fall", {"lean": -0.25}), _f(3, "fall", {"lean": -0.65}), _f(6, "fall", {"lean": -1.15}),
			_f(5, "down"), _f(5, "down"),
		]),
		"getup": _anim(false, [_f(4, "down"), _f(3, "getup", {"lean": -0.3}), _f(5, "idle")]),
		"victory": _anim(true, [
			_f(8, "victory", {"arm": 0, "style": finisher_style}), _f(5, "victory", {"arm": 1, "style": finisher_style}),
			_f(6, "victory", {"arm": 2, "style": finisher_style}), _f(8, "victory", {"arm": 2, "style": finisher_style}),
			_f(5, "victory", {"arm": 1, "style": finisher_style}), _f(6, "victory", {"arm": 0, "style": finisher_style}),
		]),
		"intro": _anim(true, [
			_f(6, "intro", {"arm": -1, "style": finisher_style}), _f(8, "intro", {"arm": 0, "style": finisher_style}),
			_f(6, "intro", {"arm": 1, "style": finisher_style}), _f(8, "idle", {"arm": 1}),
			_f(6, "idle"), _f(8, "idle", {"arm": 0}),
		]),
	}


## Golpes de las cadenas de puños (J) y patadas (K), iguales para todos los
## luchadores salvo la velocidad: los pesados tardan un cuadro más en preparar y
## Volt uno menos. Claves extra que lee FighterPainter:
##   punch: "jab" | "cross" | "hook" | "upper"   (forma del puñetazo)
##   kick:  "low" | "mid" | "high" | "spin"      (altura de la patada)
##   turn:  true = cuadro de espaldas (giro de la patada giratoria)
static func _strikes(fighter_id: String) -> Dictionary:
	var id := like(fighter_id)
	var slow := 1 if (id == "pedernal" or id == "onix") else 0
	var fast := 1 if id == "volt" else 0
	var w := func(frames: int) -> int: return maxi(2, frames + slow - fast)
	var jab_box := {"x": 8, "y": 15, "w": 25, "h": 13}
	var cross_box := {"x": 9, "y": 15, "w": 28, "h": 14}
	var hook_box := {"x": 8, "y": 16, "w": 25, "h": 17}
	var upper_box := {"x": 6, "y": 18, "w": 30, "h": 28}
	var low_box := {"x": 6, "y": 0, "w": 30, "h": 13}
	var mid_box := {"x": 7, "y": 9, "w": 33, "h": 15}
	var high_box := {"x": 8, "y": 20, "w": 32, "h": 18}
	var spin_box := {"x": 5, "y": 10, "w": 38, "h": 24}
	var sweep_box := {"x": 4, "y": -2, "w": 36, "h": 12}
	var air_punch_box := {"x": 4, "y": -12, "w": 30, "h": 30}
	var air_kick_box := {"x": 2, "y": -14, "w": 34, "h": 30}
	var throw_box := {"x": 2, "y": 14, "w": 26, "h": 22}
	return {
		"sweep": _anim(false, [
			_f(w.call(4), "kick", {"leg": 1, "squash": 0.3, "kick": "low"}),
			_f(3, "smear", {"leg": 2, "smear": true, "squash": 0.38, "lean": -0.05, "hitbox": sweep_box, "kick": "low"}),
			_f(7, "impact", {"leg": 2, "squash": 0.38, "lean": -0.05, "hitbox": sweep_box, "kick": "low"}),
			_f(8, "recover", {"squash": 0.2, "kick": "low"}),
		]),
		"air_punch": _anim(false, [
			_f(w.call(3), "anticipate", {"lean": 0.1, "punch": "jab"}),
			_f(3, "impact", {"arm": 2, "smear": true, "lean": 0.3, "hitbox": air_punch_box, "punch": "jab"}),
			_f(9, "impact", {"arm": 2, "lean": 0.3, "hitbox": air_punch_box, "punch": "jab"}),
			_f(6, "recover", {"arm": 1, "punch": "jab"}),
		]),
		"air_kick": _anim(false, [
			_f(w.call(3), "kick", {"leg": 1, "lean": 0.1, "kick": "mid"}),
			_f(3, "smear", {"leg": 2, "smear": true, "lean": 0.35, "hitbox": air_kick_box, "kick": "mid"}),
			_f(12, "impact", {"leg": 2, "lean": 0.35, "hitbox": air_kick_box, "kick": "mid"}),
			_f(4, "recover", {"kick": "mid"}),
		]),
		"throw": _anim(false, [
			_f(w.call(3), "anticipate", {"lean": 0.08, "punch": "jab"}),
			_f(4, "punch", {"arm": 1, "lean": 0.12, "hitbox": throw_box, "punch": "jab"}),
			_f(6, "impact", {"arm": 2, "lean": -0.15, "punch": "upper", "smear": true}),
			_f(6, "impact", {"arm": 2, "lean": -0.2, "punch": "upper"}),
			_f(8, "recover", {"arm": 1}),
		]),
		"jab": _anim(false, [
			_f(w.call(2), "anticipate", {"lean": -0.03, "punch": "jab"}),
			_f(2, "impact", {"arm": 2, "smear": true, "hitbox": jab_box, "punch": "jab", "lean": 0.04}),
			_f(3, "impact", {"arm": 2, "hitbox": jab_box, "punch": "jab"}),
			_f(5, "recover", {"arm": 1, "punch": "jab"}),
		]),
		"cross": _anim(false, [
			_f(w.call(4), "anticipate", {"lean": -0.08, "punch": "cross"}),
			_f(2, "punch", {"arm": 1, "lean": 0.06, "punch": "cross"}),
			_f(2, "smear", {"arm": 2, "lean": 0.14, "smear": true, "hitbox": cross_box, "punch": "cross"}),
			_f(5, "impact", {"arm": 2, "lean": 0.1, "hitbox": cross_box, "punch": "cross"}),
			_f(5, "recover", {"arm": 1, "punch": "cross"}),
		]),
		"hook": _anim(false, [
			_f(w.call(4), "anticipate", {"lean": -0.12, "punch": "hook"}),
			_f(2, "punch", {"arm": 1, "lean": 0.02, "punch": "hook"}),
			_f(3, "smear", {"arm": 2, "lean": 0.1, "smear": true, "hitbox": hook_box, "punch": "hook"}),
			_f(5, "impact", {"arm": 2, "lean": 0.08, "hitbox": hook_box, "punch": "hook"}),
			_f(6, "recover", {"arm": 1, "punch": "hook"}),
		]),
		"uppercut": _anim(false, [
			_f(w.call(6), "anticipate", {"lean": 0.1, "bob": 2, "punch": "upper"}),
			_f(2, "punch", {"arm": 1, "lean": 0.0, "punch": "upper"}),
			_f(3, "smear", {"arm": 2, "lean": -0.12, "smear": true, "hitbox": upper_box, "punch": "upper"}),
			_f(7, "impact", {"arm": 2, "lean": -0.1, "hitbox": upper_box, "punch": "upper"}),
			_f(5, "recover", {"arm": 1, "punch": "upper"}),
			_f(4, "recover", {"punch": "upper"}),
		]),
		"kick_low": _anim(false, [
			_f(w.call(3), "kick", {"leg": 1, "lean": -0.04, "kick": "low"}),
			_f(2, "smear", {"leg": 2, "smear": true, "hitbox": low_box, "kick": "low", "lean": -0.06}),
			_f(4, "impact", {"leg": 2, "hitbox": low_box, "kick": "low", "lean": -0.06}),
			_f(6, "recover", {"kick": "low"}),
		]),
		"kick_mid": _anim(false, [
			_f(w.call(4), "kick", {"leg": 1, "lean": -0.08, "kick": "mid"}),
			_f(3, "smear", {"leg": 2, "smear": true, "hitbox": mid_box, "kick": "mid", "lean": -0.1}),
			_f(5, "impact", {"leg": 2, "hitbox": mid_box, "kick": "mid", "lean": -0.1}),
			_f(6, "recover", {"kick": "mid"}),
		]),
		"kick_high": _anim(false, [
			_f(w.call(5), "kick", {"leg": 1, "lean": -0.12, "kick": "high"}),
			_f(3, "smear", {"leg": 2, "smear": true, "hitbox": high_box, "kick": "high", "lean": -0.2}),
			_f(5, "impact", {"leg": 2, "hitbox": high_box, "kick": "high", "lean": -0.2}),
			_f(7, "recover", {"kick": "high"}),
		]),
		"kick_spin": _anim(false, [
			_f(w.call(4), "kick", {"leg": 1, "lean": -0.06, "kick": "spin"}),
			_f(3, "kick", {"leg": 1, "turn": true, "kick": "spin", "lean": 0.05}),
			_f(3, "smear", {"leg": 2, "smear": true, "hitbox": spin_box, "kick": "spin", "lean": -0.18}),
			_f(6, "impact", {"leg": 2, "hitbox": spin_box, "kick": "spin", "lean": -0.18}),
			_f(5, "recover", {"kick": "spin"}),
			_f(4, "recover"),
		]),
	}
