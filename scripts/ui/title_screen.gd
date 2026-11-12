extends Control
## Pantalla de título: lo primero que se ve al abrir el juego.
##  - Dos luchadores al azar se enfrentan y sus energías chocan en el centro.
##  - El logo entra de golpe con destello y temblor; cada pocos segundos cambia la pareja.
##  - Enter / J / botón A (o clic) pasa al menú principal con la transición pixelada.
## Todo se construye en código con anclas para que quepa siempre en 960x540.

const CAMBIO_PAREJA := 6.0   ## segundos entre parejas de luchadores

var _leaving := false
var _time := 0.0
var _pareja_t := 0.0
var _intro_hecha := false
var _ids: Array[String] = []
var _par := [0, 1]

var _fondo: StagePreview
var _choque: Choque
var _izq: FighterPortrait
var _der: FighterPortrait
var _nombre_izq: Label
var _nombre_der: Label
var _logo: Control
var _pulsa: Label
var _destello: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Sfx.play_music("menu")
	for f in Catalog.FIGHTERS:
		_ids.append(String(f["id"]))
	_construir()
	_elegir_pareja(true)
	_intro()


func _construir() -> void:
	_fondo = StagePreview.new()
	_fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fondo.modulate = Color(0.5, 0.52, 0.66)
	add_child(_fondo)

	var sombra := ColorRect.new()
	sombra.set_anchors_preset(Control.PRESET_FULL_RECT)
	sombra.color = Color(0.02, 0.025, 0.05, 0.45)
	sombra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sombra)

	_choque = Choque.new()
	_choque.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_choque)

	_izq = _retrato(1)
	_izq.position = Vector2(40, 175)
	_der = _retrato(-1)
	_der.position = Vector2(960 - 40 - 320, 175)
	_nombre_izq = _nombre(Vector2(40, 492), HORIZONTAL_ALIGNMENT_LEFT)
	_nombre_der = _nombre(Vector2(960 - 40 - 320, 492), HORIZONTAL_ALIGNMENT_RIGHT)

	_logo = VBoxContainer.new()
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.add_theme_constant_override("separation", -14)
	_logo.size = Vector2(760, 200)
	_logo.position = Vector2((960 - 760) / 2.0, 22)
	_logo.pivot_offset = _logo.size / 2.0
	add_child(_logo)
	var lema := UiKit.label("UNA ARENA · TODOS LOS ESTILOS", 15, UiKit.ACCENT, 6, Color("#0b0e18"))
	var titulo := UiKit.label("CHOQUE", 96, UiKit.TEXT, 18, Color("#0b0e18"))
	var sub := UiKit.label("DE ENERGÍA", 46, UiKit.GOLD, 12, Color("#0b0e18"))
	for l in [lema, titulo, sub]:
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_logo.add_child(l)

	_pulsa = UiKit.label("PULSA ENTER", 26, UiKit.TEXT, 8, Color("#0b0e18"))
	_pulsa.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pulsa.size = Vector2(400, 40)
	_pulsa.position = Vector2(280, 452)
	add_child(_pulsa)

	var version := UiKit.label("v" + String(ProjectSettings.get_setting("application/config/version", "1.0")), 12, UiKit.MUTED)
	version.name = "Version"
	version.position = Vector2(12, 516)
	add_child(version)
	var ayuda := UiKit.label("ENTER / J / Ⓐ  EMPEZAR", 12, UiKit.MUTED)
	ayuda.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ayuda.size = Vector2(300, 18)
	ayuda.position = Vector2(960 - 12 - 300, 516)
	add_child(ayuda)

	_destello = ColorRect.new()
	_destello.set_anchors_preset(Control.PRESET_FULL_RECT)
	_destello.color = Color(1, 1, 1, 0)
	_destello.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_destello)


func _retrato(mira: int) -> FighterPortrait:
	var r := FighterPortrait.new()
	r.size = Vector2(320, 330)
	r.facing = mira
	r.animation = "intro"
	add_child(r)
	return r


func _nombre(pos: Vector2, alineado: HorizontalAlignment) -> Label:
	var l := UiKit.label("", 22, UiKit.TEXT, 8, Color("#0b0e18"))
	l.horizontal_alignment = alineado
	l.size = Vector2(320, 30)
	l.position = pos
	add_child(l)
	return l


## Elige dos luchadores distintos (si hay) y un escenario al azar.
func _elegir_pareja(primera := false) -> void:
	if _ids.is_empty():
		return
	var a := randi() % _ids.size()
	var b := a
	if _ids.size() > 1:
		while b == a:
			b = randi() % _ids.size()
	_par = [a, b]
	var da := Catalog.fighter(_ids[a])
	var db := Catalog.fighter(_ids[b])
	_izq.fighter_id = _ids[a]
	_der.fighter_id = _ids[b]
	_izq.animation = "intro" if primera else "victory"
	_der.animation = "intro"
	_nombre_izq.text = String(da["name"]).to_upper()
	_nombre_der.text = String(db["name"]).to_upper()
	_nombre_izq.add_theme_color_override("font_color", Catalog.color(String(da["accent"])).lightened(0.35))
	_nombre_der.add_theme_color_override("font_color", Catalog.color(String(db["accent"])).lightened(0.35))
	_choque.color_izq = Catalog.color(String(da["accent"]))
	_choque.color_der = Catalog.color(String(db["accent"]))
	_fondo.stage_id = String(Catalog.STAGES[randi() % Catalog.STAGES.size()]["id"])
	if not primera:
		_destellar(0.5)
		_izq.flash = 0.25
		_der.flash = 0.25


func _intro() -> void:
	var x_izq := _izq.position.x
	var x_der := _der.position.x
	_izq.position.x = -340.0
	_der.position.x = 980.0
	_logo.modulate.a = 0.0
	_logo.scale = Vector2(2.4, 2.4)
	_pulsa.modulate.a = 0.0
	_choque.fuerza = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(_izq, "position:x", x_izq, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_der, "position:x", x_der, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_choque, "fuerza", 1.0, 0.5).set_delay(0.45)
	t.tween_property(_logo, "modulate:a", 1.0, 0.18).set_delay(0.55)
	t.tween_property(_logo, "scale", Vector2.ONE, 0.35).set_delay(0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		_destellar(0.75)
		_temblor(10.0)
		Sfx.play("heavy_hit")).set_delay(0.85)
	t.tween_property(_pulsa, "modulate:a", 1.0, 0.3).set_delay(1.2)
	t.chain().tween_callback(func() -> void: _intro_hecha = true)


func _destellar(fuerza: float) -> void:
	_destello.color.a = fuerza
	create_tween().tween_property(_destello, "color:a", 0.0, 0.35)


var _sacudida := 0.0


func _temblor(fuerza: float) -> void:
	_sacudida = fuerza


func _process(delta: float) -> void:
	_time += delta
	if _intro_hecha and not _leaving:
		_pareja_t += delta
		_pulsa.modulate.a = 0.55 + 0.45 * absf(sin(_time * 3.2))
		if _pareja_t >= CAMBIO_PAREJA:
			_pareja_t = 0.0
			_elegir_pareja()
	if _sacudida > 0.0:
		_sacudida = maxf(0.0, _sacudida - delta * 40.0)
		_logo.position = Vector2((960 - 760) / 2.0, 22) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _sacudida
	elif _intro_hecha:
		# El logo flota muy poco para que la pantalla no se sienta congelada.
		_logo.position = Vector2((960 - 760) / 2.0, 22 + sin(_time * 1.4) * 3.0)


## El Control raíz recibe el clic antes de que llegue a _unhandled_input.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		start()


func _unhandled_input(event: InputEvent) -> void:
	var pulsado: bool = event.is_action_pressed("ui_accept") \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not pulsado:
		return
	get_viewport().set_input_as_handled()
	start()


## Pasa al menú principal (una sola vez, aunque se pulse varias veces).
func start() -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("confirm")
	_pulsa.modulate.a = 1.0
	_choque.estallar()
	_destellar(0.9)
	Router.goto("menu")


## Las dos energías que chocan entre los luchadores.
class Choque extends Control:
	var color_izq := Color("#7fe8ff")
	var color_der := Color("#ff3b3b")
	var fuerza := 1.0      ## 0 = apagado, 1 = choque normal
	var _t := 0.0
	var _estallido := 0.0
	var _chispas: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func estallar() -> void:
		_estallido = 1.0

	func _process(delta: float) -> void:
		_t += delta
		_estallido = maxf(0.0, _estallido - delta * 2.0)
		if fuerza > 0.0 and randf() < 0.6:
			var lado := -1.0 if randf() < 0.5 else 1.0
			_chispas.append({"p": _centro(), "v": Vector2(lado * randf_range(60, 220), randf_range(-160, 120)),
				"vida": randf_range(0.25, 0.6), "c": color_izq if lado < 0 else color_der})
		var vivas: Array = []
		for c in _chispas:
			c["vida"] -= delta
			c["p"] += c["v"] * delta
			c["v"].y += 300.0 * delta
			if c["vida"] > 0.0:
				vivas.append(c)
		_chispas = vivas
		queue_redraw()

	func _centro() -> Vector2:
		return Vector2(480.0 + sin(_t * 1.7) * 26.0 + sin(_t * 4.3) * 6.0, 330.0)

	func _draw() -> void:
		if fuerza <= 0.0:
			return
		var c := _centro()
		var ancho := (10.0 + sin(_t * 18.0) * 2.0) * fuerza * (1.0 + _estallido * 2.5)
		_rayo(Vector2(250, 330), c, color_izq, ancho)
		_rayo(Vector2(710, 330), c, color_der, ancho)
		var r := (26.0 + sin(_t * 11.0) * 4.0) * fuerza * (1.0 + _estallido * 6.0)
		draw_circle(c, r * 1.9, Color(color_izq.lerp(color_der, 0.5), 0.16 * fuerza))
		draw_circle(c, r, Color(1, 1, 1, 0.85 * fuerza))
		draw_circle(c, r * 0.55, Color.WHITE)
		for ch in _chispas:
			var p: Vector2 = ch["p"]
			draw_rect(Rect2(p.round(), Vector2(3, 3)), Color(ch["c"], clampf(ch["vida"] * 3.0, 0.0, 1.0)))

	func _rayo(desde: Vector2, hasta: Vector2, color: Color, ancho: float) -> void:
		var ondas := PackedVector2Array()
		var pasos := 14
		for n in pasos + 1:
			var k := float(n) / pasos
			var p := desde.lerp(hasta, k)
			p.y += sin(_t * 24.0 + k * 9.0) * 4.0 * (1.0 - absf(k - 0.5) * 2.0)
			ondas.append(p)
		draw_polyline(ondas, Color(color, 0.25), ancho * 2.4)
		draw_polyline(ondas, Color(color, 0.85), ancho)
		draw_polyline(ondas, Color(1, 1, 1, 0.9), maxf(ancho * 0.35, 1.0))
