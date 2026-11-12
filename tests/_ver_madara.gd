extends Node
## TEMPORAL (Claude): abre una pelea Madara Edo vs Kakashi con la intro y la barra llena
## para probar el definitivo (H = despertar, H otra vez = definitivo). Se borra después.

func _ready() -> void:
	SaveData.skip_intro = false
	Router.mode = "versus"
	Router.p1_id = "madara_edo"
	Router.p2_id = "kakashi"
	_iniciar.call_deferred()


func _iniciar() -> void:
	# Este nodo se queda en la raíz para seguir llenando la barra aunque cambie la escena.
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/fight.tscn")
	while true:
		await get_tree().process_frame
		var fight := get_tree().current_scene
		if fight and fight.get("_running") == true and fight.get("sim") != null:
			var sim = fight.get("sim")
			sim.player.awakening_available = true
			if sim.player.awakening_time <= 0.0 and not sim.ultimate_active:
				sim.player.meter = 100.0
