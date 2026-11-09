class_name ResultPanel
extends Control
## Pantalla de resultado: título, detalle, monedas y botones de la siguiente acción.

var _title: Label
var _subtitle: Label
var _details: Label
var _buttons_box: VBoxContainer
var _portrait: FighterPortrait
var _fx: ResultFx


## Rayos de luz que giran detrás del ganador y confeti pixelado que cae.
class ResultFx extends Control:
	var color := Color.WHITE
	var center := Vector2(740, 300)
	var time := 0.0

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			time += delta
			queue_redraw()

	func _draw() -> void:
		for i in range(12):
			var a0 := time * 0.25 + i * TAU / 12.0
			var a1 := a0 + 0.12
			var r := 520.0
			draw_colored_polygon(PackedVector2Array([center, center + Vector2(cos(a0), sin(a0)) * r,
				center + Vector2(cos(a1), sin(a1)) * r]), Color(color, 0.1 if i % 2 == 0 else 0.05))
		for i in range(46):
			var x := fmod(float(i * 83) + sin(time * 1.3 + i) * 20.0, 960.0)
			var y := fmod(time * (60.0 + (i % 5) * 25.0) + i * 41.0, 580.0) - 20.0
			var tone := color if i % 3 == 0 else (UiKit.GOLD if i % 3 == 1 else Color.WHITE)
			var flip := 4.0 if int(time * 8.0 + i) % 2 == 0 else 2.0
			draw_rect(Rect2(roundf(x), roundf(y), 4, flip), tone)


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_fx = ResultFx.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	_portrait = FighterPortrait.new()
	_portrait.animation = "victory"
	_portrait.position = Vector2(560, 60)
	_portrait.size = Vector2(360, 440)
	add_child(_portrait)
	_title = UiKit.label("", 64, UiKit.GOLD, 16, Color("#2a0a00"))
	_title.position = Vector2(60, 90)
	_title.size = Vector2(600, 90)
	add_child(_title)
	_subtitle = UiKit.label("", 22, Color.WHITE, 6)
	_subtitle.position = Vector2(64, 176)
	_subtitle.size = Vector2(560, 30)
	add_child(_subtitle)
	_details = UiKit.label("", 16, UiKit.MUTED)
	_details.position = Vector2(64, 214)
	_details.size = Vector2(520, 80)
	add_child(_details)
	_buttons_box = VBoxContainer.new()
	_buttons_box.position = Vector2(64, 300)
	_buttons_box.add_theme_constant_override("separation", 8)
	add_child(_buttons_box)


## actions: Array de [texto, Callable].
func show_result(title: String, subtitle: String, details: String, winner_id: String, actions: Array) -> void:
	for child in _buttons_box.get_children():
		child.queue_free()
	_title.text = title
	_subtitle.text = subtitle
	_details.text = details
	_portrait.visible = winner_id != ""
	_fx.visible = winner_id != ""
	if winner_id != "":
		_portrait.fighter_id = winner_id
		_fx.color = Catalog.color(String(Catalog.fighter(winner_id)["accent"]))
	var first: Button = null
	for entry in actions:
		var button := UiKit.make_button(String(entry[0]), UiKit.GOLD, 20)
		button.custom_minimum_size = Vector2(320, 44)
		var callback: Callable = entry[1]
		button.pressed.connect(_on_action.bind(callback))
		button.mouse_entered.connect(button.grab_focus)
		_buttons_box.add_child(button)
		if first == null:
			first = button
	visible = true
	modulate.a = 0.0
	_title.scale = Vector2(1.4, 1.4)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.25)
	tween.tween_property(_title, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if first:
		first.grab_focus()


func _on_action(callback: Callable) -> void:
	Sfx.play("confirm")
	callback.call()
