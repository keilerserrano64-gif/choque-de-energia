@tool
extends Resource
## Animaciones AutoAnim 2D de un luchador (assets/fighters/<id>/<id>_autoanim.tres).
## Lo escribe el panel AutoAnim del editor; lo lee AutoAnim2D.config().

## accion -> {"estilo": String, "duracion": float, "intensidad": float}
@export var acciones: Dictionary = {}
