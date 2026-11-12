extends RefCounted
## Registro de intros cinemáticas por luchador. fight.gd pregunta aquí si alguno de los
## dos tiene una intro antes del primer asalto. Para añadir otra: una escena cuyo nodo raíz
## tenga play(contexto) y las señales intro_started / intro_finished, y su línea aquí.

const INTROS := {
	"madara_edo": "res://scenes/intros/madara_edo_intro.tscn",
}


## Devuelve {"index": índice del luchador, "scene": ruta} o {} si nadie tiene intro.
## Si los dos la tienen (espejo), se presenta al rival: es a quien te enfrentas.
static func pick(player_id: String, enemy_id: String, player_index: int, enemy_index: int) -> Dictionary:
	for pair in [[enemy_id, enemy_index], [player_id, player_index]]:
		var path := String(INTROS.get(String(pair[0]), ""))
		if path != "" and ResourceLoader.exists(path):
			return {"index": int(pair[1]), "scene": path}
	return {}
