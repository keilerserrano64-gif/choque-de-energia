extends SceneTree
## Pule las hojas de sprites de los luchadores ya importados (lo mismo que hace ahora el
## importador al final): quita el polvo de borde casi transparente, hace opaco lo casi opaco
## y rellena el color bajo lo transparente para que no salgan halos al filtrar o girar.
## Copia antes cada hoja en ../respaldo_hojas_pulido/<id>/.
## Ejecutar: godot --headless --path . -s res://tools/pulir_hojas.gd
const Importer := preload("res://scripts/tools/fighter_importer.gd")


func _initialize() -> void:
	var raiz := ProjectSettings.globalize_path("res://assets/fighters")
	var respaldo := ProjectSettings.globalize_path("res://").path_join("../respaldo_hojas_pulido").simplify_path()
	for id in DirAccess.get_directories_at(raiz):
		var ruta := raiz.path_join(id).path_join(id + "_sheet.png")
		if not FileAccess.file_exists(ruta):
			continue
		DirAccess.make_dir_recursive_absolute(respaldo.path_join(id))
		var copia := respaldo.path_join(id).path_join(id + "_sheet.png")
		if not FileAccess.file_exists(copia):
			DirAccess.copy_absolute(ruta, copia)
		var img := Image.load_from_file(ruta)
		var antes := _sucios(img)
		Importer.pulir_hoja(img)
		img.save_png(ruta)
		print("%s: %d píxeles de borde sucio limpiados (%dx%d)" % [id, antes, img.get_width(), img.get_height()])
	quit()


func _sucios(img: Image) -> int:
	var n := 0
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if (a > 0.0 and a < 0.12) or (a > 0.88 and a < 1.0):
				n += 1
	return n
