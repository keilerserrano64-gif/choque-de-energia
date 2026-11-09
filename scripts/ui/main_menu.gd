extends Control
## Menú principal: Arcade, VS, VS CPU, Entrenamiento, Opciones, Tienda y Salir.

const ITEMS := [
	{"id": "arcade", "label": "ARCADE", "description": "Siete rivales seguidos. La dificultad sube combate a combate."},
	{"id": "versus", "label": "VS", "description": "Dos jugadores en el mismo teclado o con dos mandos."},
	{"id": "cpu", "label": "VS CPU", "description": "Un combate libre: eliges rival, escenario y dificultad."},
	{"id": "training", "label": "ENTRENAMIENTO", "description": "Practica contra un muñeco: la vida se recarga y ves las cajas de golpe."},
	{"id": "options", "label": "OPCIONES", "description": "Música, efectos, pantalla y controles."},
	{"id": "store", "label": "TIENDA DE DESPERTARES", "description": "Desbloquea el despertar de cada luchador por %d monedas." % Catalog.FORM_COST},
	{"id": "quit", "label": "SALIR", "description": "Cerrar el juego."},
]

@onready var backdrop: StagePreview = %Backdrop
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


func _ready() -> void:
	Sfx.play_music("menu")
	UiKit.style_label(tagline, 14, UiKit.ACCENT)
	UiKit.style_label(title_label, 76, UiKit.TEXT, 14, Color("#0b0e18"))
	UiKit.style_label(subtitle_label, 38, UiKit.GOLD, 10, Color("#0b0e18"))
	UiKit.style_label(description, 16, UiKit.MUTED)
	UiKit.style_label(coins_label, 20, UiKit.GOLD, 6)
	UiKit.style_label(hero_name, 40, UiKit.TEXT, 12, Color("#0b0e18"))
	UiKit.style_label(hero_role, 14, UiKit.ACCENT, 6)
	UiKit.style_label(footer, 13, UiKit.MUTED)
	_build_menu()
	options_panel.closed.connect(_on_panel_closed)
	store_panel.closed.connect(_on_panel_closed)
	SaveData.changed.connect(_update_coins)
	_update_coins()
	_hero_index = randi() % Catalog.FIGHTERS.size()
	_show_hero(_hero_index)
	_play_intro()


func _build_menu() -> void:
	for item in ITEMS:
		if item["id"] == "quit" and (OS.has_feature("web") or OS.has_feature("mobile")):
			continue
		var button := UiKit.make_button(String(item["label"]), UiKit.ACCENT, 20)
		button.custom_minimum_size = Vector2(340, 36)
		# Botones más bajos para que los siete quepan entre el título y la descripción.
		for state in ["normal", "hover", "focus", "pressed", "disabled"]:
			var style := button.get_theme_stylebox(state) as StyleBoxFlat
			style.content_margin_top = 5
			style.content_margin_bottom = 5
		var item_id := String(item["id"])
		var text := String(item["description"])
		button.pressed.connect(func() -> void: _choose(item_id))
		button.focus_entered.connect(func() -> void: _on_focus(button, text))
		button.mouse_entered.connect(button.grab_focus)
		menu_list.add_child(button)
		_buttons.append(button)


func _play_intro() -> void:
	title_box.modulate.a = 0.0
	title_box.position.x -= 40.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(title_box, "modulate:a", 1.0, 0.5)
	tween.tween_property(title_box, "position:x", title_box.position.x + 40.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in range(_buttons.size()):
		var b := _buttons[i]
		b.modulate.a = 0.0
		tween.tween_property(b, "modulate:a", 1.0, 0.3).set_delay(0.15 + i * 0.05)
	_buttons[0].grab_focus()


func _process(delta: float) -> void:
	_hero_timer += delta
	if _hero_timer > 4.5 and not options_panel.visible and not store_panel.visible:
		_hero_timer = 0.0
		_hero_index = (_hero_index + 1) % Catalog.FIGHTERS.size()
		_show_hero(_hero_index)


func _show_hero(index: int) -> void:
	var fighter: Dictionary = Catalog.FIGHTERS[index]
	hero.fighter_id = String(fighter["id"])
	hero.animation = "victory" if index % 2 == 0 else "intro"
	hero_name.text = String(fighter["name"]).to_upper()
	hero_role.text = String(fighter["role"])
	backdrop.stage_id = String(Catalog.STAGES[index % Catalog.STAGES.size()]["id"])
	hero.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(hero, "modulate:a", 1.0, 0.35)


func _on_focus(button: Button, text: String) -> void:
	if _last_focus != null and _last_focus != button:
		Sfx.play("cursor")
	_last_focus = button
	description.text = text


func _update_coins() -> void:
	coins_label.text = "%d MONEDAS" % SaveData.coins


func _choose(item_id: String) -> void:
	Sfx.play("confirm")
	match item_id:
		"arcade", "versus", "cpu", "training":
			Router.begin(item_id)
			Router.goto("select")
		"options":
			options_panel.open()
		"store":
			store_panel.open()
		"quit":
			get_tree().quit()


func _on_panel_closed() -> void:
	_update_coins()
	if _last_focus:
		_last_focus.grab_focus()
	else:
		_buttons[0].grab_focus()
