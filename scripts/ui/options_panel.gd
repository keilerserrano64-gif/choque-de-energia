class_name OptionsPanel
extends Control
## Panel de opciones (audio, pantalla y lista de controles). Se usa en el menú
## principal y en la pausa del combate.

signal closed

var _music: HSlider
var _effects: HSlider
var _voices: HSlider
var _announcer: CheckButton
var _skip_intro: CheckButton
var _fullscreen: CheckButton
var _hitboxes: CheckButton
var _screen_fx: CheckButton
var _done: Button


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.PANEL, UiKit.ACCENT, 2, 8))
	panel.custom_minimum_size = Vector2(620, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiKit.label("A TU MANERA", 13, UiKit.ACCENT))
	box.add_child(UiKit.label("Opciones", 32, UiKit.TEXT, 6))

	_music = _add_slider(box, "MÚSICA")
	_effects = _add_slider(box, "EFECTOS")
	_voices = _add_slider(box, "VOCES")
	_announcer = _add_check(box, "ANUNCIOS DE COMBATE")
	_skip_intro = _add_check(box, "OMITIR PRESENTACIÓN DE RONDA")
	_hitboxes = _add_check(box, "CAJAS DE GOLPE EN ENTRENAMIENTO")
	_screen_fx = _add_check(box, "EFECTOS DE PANTALLA (ONDAS Y DESTELLOS)")
	_fullscreen = _add_check(box, "PANTALLA COMPLETA")
	_fullscreen.visible = not (OS.has_feature("web") or OS.has_feature("mobile"))

	var controls := UiKit.label(
		"J1  WASD mover y saltar · Mayús correr · E cubrirse (mantener)\n" +
		"      J golpe · I golpe fuerte · K técnica · H despertar\n" +
		"J2  flechas · Num0 o Ñ correr · Num5 cubrirse\n" +
		"      Num1 golpe · Num4 golpe fuerte · Num2 técnica · Num3 despertar\n" +
		"Esc o P pausa", 13, UiKit.MUTED)
	box.add_child(controls)

	_done = UiKit.make_button("LISTO", UiKit.GOLD, 20)
	_done.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_done.pressed.connect(close)
	box.add_child(_done)

	_music.value_changed.connect(_on_music_changed)
	_effects.value_changed.connect(_on_effects_changed)
	_voices.value_changed.connect(_on_voices_changed)
	_announcer.toggled.connect(_on_announcer_toggled)
	_skip_intro.toggled.connect(_on_skip_intro_toggled)
	_hitboxes.toggled.connect(_on_hitboxes_toggled)
	_screen_fx.toggled.connect(func(on: bool) -> void: SaveData.screen_effects = on)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)


func _on_music_changed(value: float) -> void:
	SaveData.music_volume = int(value)
	Sfx.apply_volumes()


func _on_effects_changed(value: float) -> void:
	SaveData.effects_volume = int(value)
	Sfx.apply_volumes()
	Sfx.play("cursor")


func _on_voices_changed(value: float) -> void:
	SaveData.voice_volume = int(value)
	Sfx.apply_volumes()
	Sfx.play_voice(0, "brasa", "punch")


func _on_announcer_toggled(on: bool) -> void:
	SaveData.announcer = on


func _on_skip_intro_toggled(on: bool) -> void:
	SaveData.skip_intro = on


func _on_hitboxes_toggled(on: bool) -> void:
	SaveData.show_hitboxes = on


func _on_fullscreen_toggled(on: bool) -> void:
	SaveData.fullscreen = on
	SaveData.apply_display()


func _add_slider(parent: Control, text: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiKit.label(text, 16, UiKit.TEXT)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size = Vector2(320, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	UiKit.style_slider(slider)
	row.add_child(slider)
	parent.add_child(row)
	return slider


func _add_check(parent: Control, text: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.add_theme_font_size_override("font_size", 16)
	check.add_theme_color_override("font_focus_color", UiKit.GOLD)
	check.focus_mode = Control.FOCUS_ALL
	parent.add_child(check)
	return check


func open() -> void:
	_music.set_value_no_signal(SaveData.music_volume)
	_effects.set_value_no_signal(SaveData.effects_volume)
	_voices.set_value_no_signal(SaveData.voice_volume)
	_announcer.set_pressed_no_signal(SaveData.announcer)
	_skip_intro.set_pressed_no_signal(SaveData.skip_intro)
	_hitboxes.set_pressed_no_signal(SaveData.show_hitboxes)
	_screen_fx.set_pressed_no_signal(SaveData.screen_effects)
	_fullscreen.set_pressed_no_signal(SaveData.fullscreen)
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_music.grab_focus()


func close() -> void:
	SaveData.save()
	Sfx.play("confirm")
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()
