extends Control
## Menú principal: Arcade, VS, VS CPU, Entrenamiento, Opciones, Tienda y Salir.
##  - K / Esc / botón B: cierra el panel abierto (lo hacen los propios paneles) o vuelve al título.
##  - Sin tocar nada durante IDLE_TIME segundos vuelve al título (no cuenta con un panel abierto).
##  - Recuerda la última opción elegida (SaveData.last_menu_item).
## A la derecha, el luchador destacado cambia solo, con una franja de su color detrás.

const ITEMS := [
	{"id": "arcade", "label": "ARCADE", "description": "Supera a todos los rivales en dificultad Normal."},
	{"id": "versus", "label": "VS", "description": "Dos jugadores en el mismo teclado o con dos mandos."},
	{"id": "cpu", "label": "VS CPU", "description": "Un combate libre: eliges rival, escenario y dificultad."},
	{"id": "training", "label": "ENTRENAMIENTO", "description": "Practica contra un muñeco: la vida se recarga y ves las cajas de golpe."},
	{"id": "options", "label": "OPCIONES", "description": "Música, efectos, pantalla y controles."},
	{"id": "store", "label": "TIENDA DE DESPERTARES", "description": "Desbloquea el despertar de cada luchador por %d monedas." % Catalog.FORM_COST},
	{"id": "quit", "label": "SALIR", "description": "Cerrar el juego."},
]
const IDLE_TIME := 60.0     ## segundos sin tocar nada para volver al título
const STICK_DEADZONE := 0.5 ## el stick por debajo de esto no cuenta como actividad
const HERO_TIME := 4.5

@onready var backdrop: StagePreview = %Backdrop
@onready var stripe: Control = %Stripe
@onready var title_box: Control = %TitleBox
@onready var title_label: Label = %Title
@onready var subtitle_label: Label = %Subtitle
@onready var tagline: Label = %Tagline
@onready var menu_list: VBoxContainer = %MenuList
@onready var description: Label = %Description
@onready var coins_label: Label = %Coins
@onready var hero: FighterPortrait = %Hero
@onready var hero_name: Label = %HeroName
@onready var hero_role: Label = %HeroRole
@onready var footer: Label = %Footer
@onready var options_panel: OptionsPanel = %OptionsPanel
@onready var store_panel: StorePanel = %StorePanel

var _buttons: Array[Button] = []
var _hero_index := 0
var _hero_timer := 0.0
var _last_focus: Button
var _idle := 0.0
var _leaving := false
var _time := 0.0
## Franja y puntero de energía (se dibujan en %Stripe).
var _accent := UiKit.ACCENT
var _pointer_y := -100.0
var _pointer_alpha := 0.0
var _hero_x := 0.0


func _ready() -> void:
	Sfx.play_music("menu")
	UiKit.style_label(tagline, 12, UiKit.ACCENT, 4, Color("#0b0e18"))
	UiKit.style_label(title_label, 52, UiKit.TEXT, 12, Color("#0b0e18"))
	UiKit.style_label(subtitle_label, 26, UiKit.GOLD, 8, Color("#0b0e18"))
	UiKit.style_label(description, 15, UiKit.MUTED, 4, Color("#0b0e18"))
	UiKit.style_label(coins_label, 20, UiKit.GOLD, 6)
	UiKit.style_label(hero_name, 38, UiKit.TEXT, 12, Color("#0b0e18"))
	UiKit.style_label(hero_role, 14, UiKit.ACCENT, 6)
	UiKit.style_label(footer, 12, UiKit.MUTED)
	stripe.draw.connect(_draw_stripe)
	_build_menu()
	options_panel.closed.connect(_on_panel_closed)
	store_panel.closed.connect(_on_panel_closed)
	options_panel.visibility_changed.connect(_sync_menu_enabled)
	store_panel.visibility_changed.connect(_sync_menu_enabled)
	SaveData.changed.connect(_update_coins)
	_update_coins()
	_hero_x = hero.position.x
	_hero_index = randi() % Catalog.FIGHTERS.size()
	_show_hero(_hero_index)
	_play_intro()


func _build_menu() -> void:
	for item in ITEMS:
		if item["id"] == "quit" and (OS.has_feature("web") or OS.has_feature("mobile")):
			continue
		var button := UiKit.make_button(String(item["label"]), UiKit.ACCENT, 20)
		button.custom_minimum_size = Vector2(340, 38)
		for state in ["normal", "hover", "focus", "pressed", "disabled"]:
			var style := button.get_theme_stylebox(state) as StyleBoxFlat
			style.content_margin_top = 5
			style.content_margin_bottom = 5
		var item_id := String(item["id"])
		var text := String(item["description"])
		button.set_meta("item_id", item_id)
		button.pressed.connect(func() -> void: _choose(item_id))
		button.focus_entered.connect(func() -> void: _on_focus(button, text))
		button.mouse_entered.connect(button.grab_focus)
		menu_list.add_child(button)
		_buttons.append(button)


## Botón que debe tener el foco al entrar: la última opción elegida, si existe.
func _initial_button() -> Button:
	var last := ""
	if "last_menu_item" in SaveData:
		last = String(SaveData.get("last_menu_item"))
	for b in _buttons:
		if String(b.get_meta("item_id")) == last:
			return b
	return _buttons[0]


func _play_intro() -> void:
	title_box.modulate.a = 0.0
	hero.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(title_box, "modulate:a", 1.0, 0.4)
	for i in range(_buttons.size()):
		var b := _buttons[i]
		b.modulate.a = 0.0
		tween.tween_property(b, "modulate:a", 1.0, 0.25).set_delay(0.1 + i * 0.045)
	_initial_button().grab_focus()


func _process(delta: float) -> void:
	_time += delta
	var panel_open := options_panel.visible or store_panel.visible
	if not panel_open and not _leaving:
		_hero_timer += delta
		if _hero_timer > HERO_TIME:
			_hero_timer = 0.0
			_hero_index = (_hero_index + 1) % Catalog.FIGHTERS.size()
			_show_hero(_hero_index)
		_idle += delta
		if _idle >= IDLE_TIME:
			_go_title()
	if _last_focus != null:
		var target := _last_focus.global_position.y + _last_focus.size.y * 0.5
		_pointer_y = target if _pointer_y < 0.0 else lerpf(_pointer_y, target, clampf(delta * 18.0, 0.0, 1.0))
	_pointer_alpha = move_toward(_pointer_alpha, 0.0 if panel_open else 1.0, delta * 6.0)
	stripe.queue_redraw()


## Cualquier tecla, botón, clic o movimiento real cuenta como actividad.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= STICK_DEADZONE:
			_idle = 0.0
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventMouseMotion:
		_idle = 0.0


func _unhandled_input(event: InputEvent) -> void:
	# Con un panel abierto, el panel se encarga de cancelar (recibe la tecla antes).
	if options_panel.visible or store_panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_title()


func _go_title() -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("cursor")
	Router.goto("title")


func _show_hero(index: int) -> void:
	var fighter: Dictionary = Catalog.FIGHTERS[index]
	hero.fighter_id = String(fighter["id"])
	hero.animation = "victory" if index % 2 == 0 else "intro"
	hero_name.text = String(fighter["name"]).to_upper()
	hero_role.text = String(fighter["role"])
	_accent = Catalog.color(String(fighter.get("accent", "#66d9ff")))
	hero_role.add_theme_color_override("font_color", _accent.lightened(0.2))
	backdrop.stage_id = String(Catalog.STAGES[index % Catalog.STAGES.size()]["id"])
	var x := _hero_x
	hero.modulate.a = 0.0
	hero.position.x = x + 30.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(hero, "modulate:a", 1.0, 0.35)
	tween.tween_property(hero, "position:x", x, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hero.flash = 0.2


func _draw_stripe() -> void:
	# Franja diagonal del color del luchador detrás de él.
	var pulse := 0.85 + 0.15 * sin(_time * 2.0)
	var poly := PackedVector2Array([Vector2(600, 0), Vector2(800, 0), Vector2(700, 540), Vector2(500, 540)])
	stripe.draw_colored_polygon(poly, Color(_accent, 0.16 * pulse))
	var line := PackedVector2Array([Vector2(805, 0), Vector2(705, 540)])
	stripe.draw_polyline(line, Color(_accent, 0.5 * pulse), 3.0)
	# Panel oscuro detrás del menú para que se lea sobre cualquier escenario.
	stripe.draw_rect(Rect2(0, 0, 470, 540), Color(0.02, 0.025, 0.05, 0.45))
	# Puntero de energía junto al botón con foco.
	if _pointer_alpha > 0.01 and _pointer_y > 0.0:
		var y := _pointer_y
		var a := _pointer_alpha
		var x := 22.0 + sin(_time * 8.0) * 2.0
		stripe.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 8), Vector2(x + 10, y), Vector2(x, y + 8)]), Color(UiKit.ACCENT, a))
		stripe.draw_circle(Vector2(x + 3, y), 9.0, Color(UiKit.ACCENT, 0.18 * a))


func _on_focus(button: Button, text: String) -> void:
	if _last_focus != null and _last_focus != button:
		Sfx.play("cursor")
	_last_focus = button
	description.text = text


func _update_coins() -> void:
	coins_label.text = "%d MONEDAS" % SaveData.coins


func _choose(item_id: String) -> void:
	if _leaving or options_panel.visible or store_panel.visible:
		return
	Sfx.play("confirm")
	if SaveData.has_method("remember_menu_item"):
		SaveData.call("remember_menu_item", item_id)
	match item_id:
		"arcade", "versus", "cpu", "training":
			_leaving = true
			Router.begin(item_id)
			Router.goto("select")
		"options":
			options_panel.open()
		"store":
			store_panel.open()
		"quit":
			get_tree().quit()


## Los paneles conservan el foco: el menú del fondo no puede recibir acciones.
func _sync_menu_enabled() -> void:
	var available := not (options_panel.visible or store_panel.visible)
	for button in _buttons:
		button.disabled = not available
		button.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE


func _on_panel_closed() -> void:
	_update_coins()
	_idle = 0.0
	if _last_focus:
		_last_focus.grab_focus()
	else:
		_buttons[0].grab_focus()
