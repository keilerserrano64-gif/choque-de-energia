extends SceneTree
## Sube la calidad de los luchadores (hoja HD + estabilización): ver scripts/tools/calidad_luchador.gd.
## Ejecutar:
##   godot --headless --path . -s res://tools/subir_calidad.gd -- [--fighter ID] [--factor 2|4] [--sin-hd] [--sin-estabilizar]
## Sin --fighter procesa todos los luchadores con hoja en assets/fighters/.

const CatalogScript := preload("res://scripts/data/catalog.gd")
const Calidad := preload("res://scripts/tools/calidad_luchador.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var solo := _arg(args, "--fighter", "")
	var factor := int(_arg(args, "--factor", "4"))
	for def in CatalogScript.FIGHTERS:
		var d: Dictionary = def
		var id := String(d["id"])
		if solo != "" and id != solo:
			continue
		var hoja := "res://assets/fighters/%s/%s_sheet.png" % [id, id]
		if not FileAccess.file_exists(hoja):
			continue
		var t0 := Time.get_ticks_msec()
		var informe := PackedStringArray([id + ":"])
		if not args.has("--sin-hd"):
			informe.append(Calidad.hoja_hd(hoja, factor))
		if not args.has("--sin-estabilizar"):
			informe.append(Calidad.estabilizar(d, hoja))
		informe.append("(%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
		print(" ".join(informe))
	quit()


func _arg(args: PackedStringArray, nombre: String, defecto: String) -> String:
	var i := args.find(nombre)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else defecto
