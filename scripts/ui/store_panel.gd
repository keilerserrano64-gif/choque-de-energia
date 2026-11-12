class_name StorePanel
extends Control
## Tienda de despertares: cada luchador puede desbloquear su forma despertada.

signal closed

var _grid: GridContainer
var _coins: Label
var _cards: Array[Button] = []


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.PANEL, UiKit.GOLD, 2, 8))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UiKit.label("TIENDA", 13, UiKit.GOLD))
	titles.add_child(UiKit.label("Despertares", 30, UiKit.TEXT, 6))
	header.add_child(titles)
	_coins = UiKit.label("", 22, UiKit.GOLD, 6)
	header.add_child(_coins)
	box.add_child(header)
	box.add_child(UiKit.label("Llena la barra de energía y pulsa H para despertar. Cada forma cuesta %d monedas." % Catalog.FORM_COST, 14, UiKit.MUTED))

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	box.add_child(_grid)
	for fighter in Catalog.FIGHTERS:
		_grid.add_child(_make_card(fighter))

	var back := UiKit.make_button("VOLVER", UiKit.ACCENT, 18)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.pressed.connect(close)
	box.add_child(back)


func _make_card(fighter: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(170, 150)
	card.focus_mode = Control.FOCUS_ALL
	var accent := Catalog.color(String(fighter["accent"]))
	card.add_theme_stylebox_override("normal", UiKit.panel(UiKit.PANEL_LIGHT, UiKit.LINE, 2, 6))
	card.add_theme_stylebox_override("hover", UiKit.panel(UiKit.PANEL_LIGHT, accent, 3, 6))
	card.add_theme_stylebox_override("focus", UiKit.panel(UiKit.PANEL_LIGHT, UiKit.GOLD, 3, 6))
	card.add_theme_stylebox_override("pressed", UiKit.panel(UiKit.PANEL, UiKit.GOLD, 3, 6))
	var portrait := FighterPortrait.new()
	portrait.fighter_id = String(fighter["id"])
	portrait.crop = FighterPortrait.Crop.BUST
	portrait.animation = "idle"
	portrait.position = Vector2(10, 8)
	portrait.size = Vector2(70, 70)
	card.add_child(portrait)
	var name_label := UiKit.label(String(fighter["name"]).to_upper(), 14, UiKit.TEXT, 4)
	name_label.name = "FighterName"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.position = Vector2(84, 8)
	name_label.size = Vector2(80, 36)
	card.add_child(name_label)
	var form := UiKit.label(String(fighter["awakening"]), 12, accent)
	form.name = "AwakeningName"
	form.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.position = Vector2(84, 48)
	form.size = Vector2(80, 56)
	card.add_child(form)
	var status := UiKit.label("", 14, UiKit.GOLD, 4)
	status.name = "Status"
	status.position = Vector2(10, 112)
	card.add_child(status)
	var fighter_id := String(fighter["id"])
	card.set_meta("fighter_id", fighter_id)
	card.pressed.connect(func() -> void: _buy(card, fighter_id))
	card.mouse_entered.connect(card.grab_focus)
	_cards.append(card)
	return card


func _refresh() -> void:
	_coins.text = "%d MONEDAS" % SaveData.coins
	for card in _cards:
		var fighter_id := String(card.get_meta("fighter_id"))
		var status: Label = card.get_node("Status")
		if SaveData.is_unlocked(fighter_id):
			status.text = "DESBLOQUEADO"
			status.add_theme_color_override("font_color", Color("#8cf0a8"))
		else:
			status.text = "DESBLOQUEAR · %d" % Catalog.FORM_COST
			status.add_theme_color_override("font_color", UiKit.GOLD if SaveData.coins >= Catalog.FORM_COST else UiKit.MUTED)


func _buy(card: Button, fighter_id: String) -> void:
	if SaveData.is_unlocked(fighter_id):
		Sfx.play("cursor")
		return
	if SaveData.unlock(fighter_id):
		Sfx.play("awaken")
		var tween := create_tween()
		card.pivot_offset = card.size / 2.0
		tween.tween_property(card, "scale", Vector2(1.08, 1.08), 0.08)
		tween.tween_property(card, "scale", Vector2.ONE, 0.15)
	else:
		Sfx.play("block")
	_refresh()


func open() -> void:
	_refresh()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_cards[0].grab_focus()


func close() -> void:
	Sfx.play("confirm")
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
