@tool
extends RefCounted
## Funciones compartidas por los generadores de AutoAnim.


## Interpola suavemente entre puntos [[tiempo, valor], ...] (tiempo de 0 a 1).
static func curva(p: float, pts: Array) -> float:
	var primero: Array = pts[0]
	if p <= float(primero[0]):
		return float(primero[1])
	for j in range(1, pts.size()):
		var b: Array = pts[j]
		if p <= float(b[0]):
			var a: Array = pts[j - 1]
			var t: float = (p - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, t))
	var ultimo: Array = pts[pts.size() - 1]
	return float(ultimo[1])


## Como curva(), pero entre colores: [[tiempo, Color], ...].
static func color_curva(p: float, pts: Array) -> Color:
	var primero: Array = pts[0]
	if p <= float(primero[0]):
		return primero[1]
	for j in range(1, pts.size()):
		var b: Array = pts[j]
		if p <= float(b[0]):
			var a: Array = pts[j - 1]
			var t: float = (p - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			return (a[1] as Color).lerp(b[1], smoothstep(0.0, 1.0, t))
	var ultimo: Array = pts[pts.size() - 1]
	return ultimo[1]


## Busca un AnimationPlayer hijo con ese nombre (que pertenezca a la escena).
## Si no existe, lo crea.
static func buscar_o_crear_player(padre: Node, nombre: String) -> AnimationPlayer:
	var escena := EditorInterface.get_edited_scene_root()
	for n in padre.get_children():
		if n is AnimationPlayer and n.owner == escena and String(n.name) == nombre:
			return n as AnimationPlayer
	var p := AnimationPlayer.new()
	p.name = nombre
	padre.add_child(p)
	p.owner = escena
	return p


## Guarda (o reemplaza) una animación en una librería del AnimationPlayer.
static func guardar(player: AnimationPlayer, libreria: String, nombre: String, anim: Animation) -> void:
	if not player.has_animation_library(libreria):
		player.add_animation_library(libreria, AnimationLibrary.new())
	var lib := player.get_animation_library(libreria)
	if lib.has_animation(nombre):
		lib.remove_animation(nombre)
	lib.add_animation(nombre, anim)
