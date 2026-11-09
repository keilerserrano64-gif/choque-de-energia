extends Control
## Selección de escenario: carrusel con las cuatro arenas y ALEATORIO.
## Contra la CPU también se elige la dificultad (arriba / abajo).

const CARD_SIZE := Vector2(420, 236)

@onready var backdrop: SelectBackdrop = %Backdrop
@onready var stage_layer: Control = %Cards
@onready var stage_name: Label = %StageName
@onready var difficulty_label: Label = %Difficulty
@onready var hint: Label = %Hint
@onready var title: Label = %Title
@onready var matchup: Label = %Matchup

var _cards: Array[Control] = []
var _selected := 0
var _difficulty := 1
var _done := false
var _random_cycle := 0.0
var _random_preview: StagePreview


func _ready() -> void:
	Sfx.play_music("menu")
	UiKit.style_label(title, 28, Color.WHITE, 8, Color("#4a0610"))
	UiKit.style_label(stage_name, 34, Color.WHITE, 10, Color("#0b0e18"))
	UiKit.style_label(difficulty_label, 20, UiKit.GOLD, 6)
	UiKit.style_label(hint, 13, UiKit.MUTED)
	UiKit.style_label(matchup, 16, UiKit.ACCENT, 4)
	matchup.text = "%s  VS  %s  ·  %s" % [
		String(Catalog.fighter(Router.p1_id)["name"]).to_upper(),
		String(Catalog.fighter(Router.p2_id)["name"]).to_upper(),
		Router.mode_label(),
	]
	_difficulty = maxi(0, Catalog.DIFFICULTY_ORDER.find(Router.difficulty_id))
	_selected = maxi(0, _stage_index(Router.stage_id))
	for i in range(Catalog.STAGES.size() + 1):
		_cards.append(_make_card(i))
	difficulty_label.visible = Router.mode == "cpu"
	hint.text = "IZQ/DER  ESCENARIO     %sJ / ENTER  LUCHAR     L / ESC  VOLVER" % ("ARRIBA/ABAJO  DIFICULTAD     " if difficulty_label.visible else "")
	_layout(true)
	_refresh()


func _stage_index(id: String) -> int:
	for i in range(Catalog.STAGES.size()):
		if Catalog.STAGES[i]["id"] == id:
			return i
	return 0


func _make_card(index: int) -> Control:
	var card := Panel.new()
	card.size = CARD_SIZE
	card.pivot_offset = CARD_SIZE / 2.0
	card.clip_contents = true
	card.add_theme_stylebox_override("panel", UiKit.panel(UiKit.BG, UiKit.LINE, 4, 4))
	var preview := StagePreview.new()
	preview.position = Vector2(4, 4)
	preview.size = CARD_SIZE - Vector2(8, 8)
	card.add_child(preview)
	if index < Catalog.STAGES.size():
		preview.stage_id = String(Catalog.STAGES[index]["id"])
	else:
		preview.stage_id = String(Catalog.STAGES[0]["id"])
		preview.modulate = Color(0.35, 0.35, 0.45)
		_random_preview = preview
		var mark := UiKit.label("?", 120, UiKit.GOLD, 16)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.size = CARD_SIZE
		card.add_child(mark)
	card.gui_input.connect(func(event: InputEvent) -> void: _on_card_input(event, index))
	stage_layer.add_child(card)
	return card


func _layout(instant: bool = false) -> void:
	var center := Vector2(480, 250) - CARD_SIZE / 2.0
	for i in range(_cards.size()):
		var card := _cards[i]
		var offset := i - _selected
		var target_pos := center + Vector2(offset * 300.0, absf(offset) * 22.0)
		var s := 1.0 if offset == 0 else 0.62
		var tint := Color.WHITE if offset == 0 else Color(0.5, 0.5, 0.6, 0.85)
		var rot := clampf(offset * 0.07, -0.14, 0.14)
		card.z_index = 10 - absi(offset)
		var style := UiKit.panel(UiKit.BG, UiKit.GOLD if offset == 0 else UiKit.LINE, 4, 4)
		card.add_theme_stylebox_override("panel", style)
		if instant:
			card.position = target_pos
			card.scale = Vector2(s, s)
			card.modulate = tint
			card.rotation = rot
		else:
			var tween := create_tween().set_parallel(true)
			tween.tween_property(card, "position", target_pos, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(card, "scale", Vector2(s, s), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(card, "modulate", tint, 0.22)
			tween.tween_property(card, "rotation", rot, 0.22)


func _refresh() -> void:
	if _selected < Catalog.STAGES.size():
		stage_name.text = String(Catalog.STAGES[_selected]["name"]).to_upper()
	else:
		stage_name.text = "ALEATORIO"
	var level := Catalog.difficulty(Catalog.DIFFICULTY_ORDER[_difficulty])
	difficulty_label.text = "DIFICULTAD   <  %s  >" % String(level["name"]).to_upper()


func _process(delta: float) -> void:
	backdrop.parallax = Vector2((_selected - 2) * -12.0, 0)
	_random_cycle += delta
	if _random_preview and _random_cycle > 0.6:
		_random_cycle = 0.0
		var next := (_stage_index(_random_preview.stage_id) + 1) % Catalog.STAGES.size()
		_random_preview.stage_id = String(Catalog.STAGES[next]["id"])
	if _done:
		return
	if _pressed("left"):
		_move(-1)
	elif _pressed("right"):
		_move(1)
	elif difficulty_label.visible and _pressed("jump"):
		_change_difficulty(1)
	elif difficulty_label.visible and _pressed("down"):
		_change_difficulty(-1)
	elif _pressed("attack"):
		_confirm()
	elif _pressed("special") or Input.is_action_just_pressed("pause"):
		Sfx.play("cursor")
		Router.goto("select")


func _pressed(action: String) -> bool:
	var ui := {"left": "ui_left", "right": "ui_right", "jump": "ui_up", "down": "ui_down", "attack": "ui_accept", "special": "ui_cancel"}
	return Input.is_action_just_pressed("p1_" + action) or Input.is_action_just_pressed("p2_" + action) \
		or (ui.has(action) and Input.is_action_just_pressed(ui[action]))


func _move(step: int) -> void:
	_selected = posmod(_selected + step, _cards.size())
	Sfx.play("cursor")
	_layout()
	_refresh()


func _change_difficulty(step: int) -> void:
	_difficulty = clampi(_difficulty + step, 0, Catalog.DIFFICULTY_ORDER.size() - 1)
	Sfx.play("cursor")
	_refresh()


func _on_card_input(event: InputEvent, index: int) -> void:
	var tapped := false
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		tapped = mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		tapped = touch.pressed
	if not tapped or _done:
		return
	if index == _selected:
		_confirm()
	else:
		_selected = index
		Sfx.play("cursor")
		_layout()
		_refresh()


func _confirm() -> void:
	_done = true
	Sfx.play("confirm")
	var index := _selected
	if index >= Catalog.STAGES.size():
		index = randi() % Catalog.STAGES.size()
	Router.stage_id = String(Catalog.STAGES[index]["id"])
	if difficulty_label.visible:
		Router.difficulty_id = String(Catalog.DIFFICULTY_ORDER[_difficulty])
	var card := _cards[_selected]
	var tween := create_tween()
	tween.tween_property(card, "scale", Vector2(1.12, 1.12), 0.12)
	tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.12)
	await tween.finished
	Router.goto("fight")
