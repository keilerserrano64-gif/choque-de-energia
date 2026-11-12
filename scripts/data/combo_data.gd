class_name ComboData
extends RefCounted
## Árbol de combos, buffer de entrada y aturdimiento de guardia.
## Mecánicas portadas del sistema Combat/Combo/Attack y de los estados
## StateBlockingOnFloor/StateKnockedDown de un proyecto de lucha en Unity,
## reescritas para CombatSim. No usa nada de su arte ni de sus personajes.
##
## Cómo funciona el árbol:
##   I abre una cadena de puños; J abre una cadena de patadas.
##   (combo_length golpes, el último es su remate).
##   L, en mitad de una cadena y antes de su remate, la cierra con una rama:
##     I → L        LANZADOR: lanza al rival para seguir golpeándolo en el aire.
##     I → I (→…) → L  REMATE CRUZADO: remate más fuerte que el normal.
##   L sin cadena abierta es el puño fuerte; ↓+L es una patada fuerte independiente.
##
## Cada luchador puede tener sus propias ramas con "combo_branches" en catalog.gd
## (misma forma que BRANCHES). Se usa la rama con el "after" más alto que no
## supere el número de golpes ya dados en la cadena.

const BRANCHES := [
	{
		"after": 1, "name": "LANZADOR", "text": "¡LANZADOR!",
		"damage": 0.9, "knockback": 60.0, "launch": -320.0, "hit_stop": 8.0,
	},
	{
		"after": 2, "name": "REMATE CRUZADO", "text": "¡REMATE CRUZADO!",
		"damage": 1.15, "knockback_bonus": 24.0,
	},
]

## --- Cadenas de puños (I) y de patadas (J) ---------------------------------
## Pulsar I varias veces lanza SOLO puños; pulsar J varias veces, SOLO patadas.
## Cada luchador tiene la longitud de sus cadenas en catalog.gd ("punch_combo",
## "kick_combo"). El último golpe de cada cadena es su remate.
## Cambiar de botón a mitad de cadena no la rompe: el combo sigue contando y el
## siguiente golpe sale del otro tipo (I, I, J = jab, directo, patada…).
const PUNCH_SEQUENCES := {
	2: ["jab", "uppercut"],
	3: ["jab", "cross", "uppercut"],
	4: ["jab", "cross", "hook", "uppercut"],
	5: ["jab", "jab", "cross", "hook", "uppercut"],
}
const KICK_SEQUENCES := {
	2: ["kick_mid", "kick_spin"],
	3: ["kick_low", "kick_mid", "kick_spin"],
	4: ["kick_low", "kick_mid", "kick_high", "kick_spin"],
	5: ["kick_low", "kick_mid", "kick_mid", "kick_high", "kick_spin"],
}
## Propiedades de cada golpe de las cadenas:
##   damage    multiplicador del daño base del luchador
##   knockback empuje (px/s) · hit_stop cuadros de pausa · hitstun segundos de aturdimiento
##   launch    impulso vertical (negativo = lanza hacia arriba para malabares)
##   lunge     paso adelante del atacante al golpear (px/s) para que la cadena no se escape
##   finisher  true = usa además finisher_damage/finisher_knockback del luchador
const STRIKES := {
	"jab": {"kind": "punch", "damage": 0.72, "knockback": 38.0, "hit_stop": 3.0, "hitstun": 0.3, "lunge": 70.0, "text": "¡JAB!"},
	"cross": {"kind": "punch", "damage": 0.95, "knockback": 52.0, "hit_stop": 4.0, "hitstun": 0.32, "lunge": 80.0, "text": "¡DIRECTO!"},
	"hook": {"kind": "punch", "damage": 1.05, "knockback": 58.0, "hit_stop": 5.0, "hitstun": 0.34, "lunge": 80.0, "text": "¡GANCHO!"},
	"uppercut": {"kind": "punch", "damage": 1.0, "knockback": 70.0, "hit_stop": 8.0, "hitstun": 0.4, "launch": -280.0, "lunge": 60.0,
		"finisher": true, "text": "¡GANCHO ASCENDENTE!"},
	"kick_low": {"kind": "kick", "damage": 0.85, "knockback": 40.0, "hit_stop": 3.0, "hitstun": 0.32, "lunge": 60.0, "text": "¡PATADA BAJA!"},
	"kick_mid": {"kind": "kick", "damage": 1.05, "knockback": 60.0, "hit_stop": 4.0, "hitstun": 0.34, "lunge": 70.0, "text": "¡PATADA MEDIA!"},
	"kick_high": {"kind": "kick", "damage": 1.15, "knockback": 66.0, "hit_stop": 5.0, "hitstun": 0.36, "lunge": 70.0, "text": "¡PATADA ALTA!"},
	"kick_spin": {"kind": "kick", "damage": 1.0, "knockback_bonus": 30.0, "hit_stop": 9.0, "hitstun": 0.42, "lunge": 50.0,
		"finisher": true, "text": "¡PATADA GIRATORIA!"},
}

## Golpes de comando (no forman parte de las cadenas):
##   ↓ + I uppercut antiaéreo · ↓ + J barrida · I / J en el aire: puño / patada aérea
##   → + L cerca del rival: agarre · ↓ + L patada fuerte (tiene prioridad sobre el agarre)
const COMMAND_STRIKES := {
	"sweep": {"kind": "kick", "damage": 1.0, "knockback": 46.0, "hit_stop": 6.0, "hitstun": 0.5, "launch": -95.0,
		"lunge": 60.0, "text": "¡BARRIDA!"},
	"air_punch": {"kind": "punch", "damage": 0.9, "knockback": 40.0, "hit_stop": 4.0, "hitstun": 0.46, "text": "¡PUÑO AÉREO!"},
	"air_kick": {"kind": "kick", "damage": 1.1, "knockback": 58.0, "hit_stop": 5.0, "hitstun": 0.5, "text": "¡PATADA VOLADORA!"},
	"throw": {"kind": "punch", "damage": 1.35, "knockback": 210.0, "hit_stop": 9.0, "hitstun": 0.5, "launch": -190.0, "text": "¡AGARRE!"},
}
## Distancia extra (además de la mínima entre cuerpos) a la que alcanza el agarre.
const THROW_RANGE := 18.0
## Contraataque: golpear al rival mientras prepara su propio golpe.
const COUNTER_DAMAGE := 1.25
const COUNTER_HITSTUN := 0.12

## Daño global de los golpes de cadena y de comando: como ahora los combos son
## reales (no se escapan), cada golpe pega algo menos que los antiguos.
const CHAIN_DAMAGE_SCALE := 0.85

## --- Contador de combo y reducción de daño ----------------------------------
## Cada golpe que entra mientras el rival sigue aturdido suma al combo.
## A partir del golpe PRORATION_START, cada golpe hace un PRORATION_STEP menos
## de daño (hasta PRORATION_MIN), como en los juegos de lucha modernos.
const PRORATION_START := 4
const PRORATION_STEP := 0.08
const PRORATION_MIN := 0.45
## Golpes en el aire seguidos (malabares) antes de que el rival caiga sin remedio.
const MAX_JUGGLE := 4
## Segundos que el contador de combo sigue visible tras el último golpe.
const COMBO_DISPLAY_TIME := 1.1

## Segundos que se guarda una pulsación hecha durante otro golpe (buffer de entrada).
const BUFFER_TIME := 0.3
## Aturdimiento del atacante cuando le bloquean un golpe cuerpo a cuerpo (segundos).
const GUARD_STUN_LIGHT := 0.2
const GUARD_STUN_HEAVY := 0.32
## Empuje hacia atrás del atacante bloqueado.
const GUARD_PUSHBACK := 60.0


## Rama de combo para cerrar con L una cadena que lleva `chain_step` golpes.
## Devuelve {} si no hay ninguna.
static func branch_for(definition: Dictionary, chain_step: int) -> Dictionary:
	var branches: Array = definition.get("combo_branches", BRANCHES)
	var best: Dictionary = {}
	for entry in branches:
		var branch: Dictionary = entry
		var after := int(branch.get("after", 1))
		if after <= chain_step and (best.is_empty() or after > int(best.get("after", 0))):
			best = branch
	return best


## Golpe número `step` (1, 2, 3…) de una cadena de puños ("punch") o patadas ("kick").
static func strike_for(kind: String, length: int, step: int) -> String:
	var table: Dictionary = KICK_SEQUENCES if kind == "kick" else PUNCH_SEQUENCES
	var sequence: Array = table.get(clampi(length, 2, 5), table[3])
	return String(sequence[clampi(step, 1, sequence.size()) - 1])


## Longitud de la cadena de puños o patadas de un luchador.
static func chain_length(definition: Dictionary, kind: String) -> int:
	var key := "kick_combo" if kind == "kick" else "punch_combo"
	return clampi(int(definition.get(key, definition.get("combo_length", 3))), 2, 5)


## Multiplicador de daño del golpe número `hits` de un combo.
static func proration(hits: int) -> float:
	if hits < PRORATION_START:
		return 1.0
	return maxf(PRORATION_MIN, 1.0 - PRORATION_STEP * (hits - PRORATION_START + 1))


static func is_strike(anim_name: String) -> bool:
	return STRIKES.has(anim_name) or COMMAND_STRIKES.has(anim_name)


## Datos de un golpe de cadena o de comando ({} si no lo es).
static func strike_data(anim_name: String) -> Dictionary:
	if STRIKES.has(anim_name):
		return STRIKES[anim_name]
	return COMMAND_STRIKES.get(anim_name, {})
