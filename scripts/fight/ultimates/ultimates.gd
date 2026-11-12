extends RefCounted
## Registro de técnicas definitivas cinemáticas: valor de "ultimate" en el catálogo -> escena.
## La escena tiene play(contexto) y las señales ultimate_started / ultimate_finished.

const ULTIMATES := {
	"juicio-dios-guerra": "res://scenes/ultimates/madara_edo_ultimate.tscn",
}


static func scene_for(definition: Dictionary) -> String:
	var path := String(ULTIMATES.get(String(definition.get("ultimate", "")), ""))
	return path if path != "" and ResourceLoader.exists(path) else ""
