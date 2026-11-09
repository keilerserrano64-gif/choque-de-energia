class_name FighterState
extends RefCounted
## Estado de un luchador durante el combate (posición, temporizadores, combos…).
## Es solo datos: la lógica vive en CombatSim y el dibujo en FighterPainter.

var definition: Dictionary
var id: String
var index := 0  ## 0 = jugador 1 (izquierda), 1 = rival / jugador 2
var x := 0.0
var y := 0.0  ## altura sobre el suelo (negativo = en el aire)
var velocity_y := 0.0
var health := 100
var facing := 1
var grounded := true
var attack_cooldown := 0.0
var special_cooldown := 0.0
var hit_flash := 0.0
var white_flash := 0.0
var hurt_time := 0.0
var hit_direction := 0
var knockback_velocity := 0.0
var attack_pose := 0.0
var attack_animation := ""
var attack_windup := 0.0
var has_pending_attack := false
var pending_hit_index := 0
var pending_combo_length := 0
var pending_heavy := false  ## el golpe pendiente es un golpe fuerte (tecla I)
var pending_branch: Dictionary = {}  ## rama de combo del golpe pendiente (ComboData.BRANCHES)
var buffered_input := ""  ## "attack" o "heavy" pulsado durante otro golpe (sale al poder cancelar)
var buffer_time := 0.0  ## segundos que se guarda esa pulsación
var attack_index := 0
var chain_kind := "punch"  ## "punch" (J) o "kick" (K): tipo de la cadena abierta
var pending_strike := ""  ## golpe de cadena pendiente (ComboData.STRIKES), "" si no lo es
var combo_hits := 0  ## golpes seguidos que han entrado sin que el rival se recupere
var combo_damage := 0  ## daño total del combo actual
var combo_display := 0.0  ## segundos que el contador sigue visible
var juggle_count := 0  ## golpes recibidos en el aire en este malabar
var voice_cooldown := 0.0  ## evita que grite en cada golpe
var air_attack_used := false  ## un solo ataque aéreo por salto
var bounced := false  ## ya rebotó contra el suelo en este derribo
var special_back := false  ## técnica pulsada manteniendo atrás (Volt: esquiva hacia atrás)
var ai_plan: Array = []  ## combo que la CPU tiene pensado ("attack", "kick", "heavy")
var guard_time := 0.0
var decoy_time := 0.0
var special_charge := 0.0
var pending_special := ""
var special_pose_time := 0.0
var armor_time := 0.0
var step_timer := 0.0
var knocked_down := false
var knockdown_time := 0.0
var getup_time := 0.0
var running := false
var walking := false
var blocking := false
var awakening_time := 0.0
var awakening_available := false
var phase_time := 0.0
var meter := 0.0
var difficulty := 1.0
var combo := 0
var combo_timer := 0.0
var max_combo := 0
var damage_multiplier := 1.0
var speed_multiplier := 1.0
var reaction_multiplier := 1.0
var ai_decision := 0.5
var ai_jump_timer := 1.4


func _init(fighter_id: String = "brasa", start_x: float = 120.0, start_facing: int = 1, difficulty_level: float = 1.0) -> void:
	definition = Catalog.fighter(fighter_id)
	id = definition["id"]
	x = start_x
	facing = start_facing
	difficulty = difficulty_level
	damage_multiplier = difficulty_level


func stat(key: String, fallback: Variant = 0.0) -> Variant:
	return definition.get(key, fallback)


func display_name() -> String:
	return String(definition["name"])
