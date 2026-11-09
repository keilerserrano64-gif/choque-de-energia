class_name VsSplash
extends Control
## Presentación «VS» antes del primer asalto: fondo partido en diagonal con los
## colores de cada luchador, líneas de velocidad, retratos que entran desde los
## lados, nombres, el «VS» que golpea en el centro y el nombre del escenario.

var _left_color := Color.BLACK
var _right_color := Color.BLACK
var _left_accent := Color.WHITE
var _right_accent := Color.WHITE
var _time := 0.0
var _split := 0.0  ## 0 → 1: la franja diagonal se abre
var _p1: FighterPortrait
var _p2: FighterPortrait
var _vs: Label
var _labels: Array[Control] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()


## Muestra la presentación y espera a que termine.
func play(sim: CombatSim, short: bool) -> void:
	var p1 := sim.player.definition
	var p2 := sim.enemy.definition
	_left_color = Catalog.color(String(p1["color"])).darkened(0.55)
	_right_color = Catalog.color(String(p2["color"])).darkened(0.55)
	_left_accent = Catalog.color(String(p1["accent"]))
	_right_accent = Catalog.color(String(p2["accent"]))
	_time = 0.0
	_split = 0.0
	visible = true
	modulate.a = 1.0

	_p1 = _portrait(String(p1["id"]), 1)
	_p2 = _portrait(String(p2["id"]), -1)
	_p1.position = Vector2(-420, 70)
	_p2.position = Vector2(960, 70)
	var name1 := _name_label(String(p1["name"]).to_upper(), String(p1["role"]), _left_accent, HORIZONTAL_ALIGNMENT_LEFT)
	name1.position = Vector2(-500, 420)
	var name2 := _name_label(String(p2["name"]).to_upper(), String(p2["role"]), _right_accent, HORIZONTAL_ALIGNMENT_RIGHT)
	name2.position = Vector2(960, 420)
	_vs = UiKit.label("VS", 120, UiKit.GOLD, 18, Color("#2a0a00"))
	_vs.size = Vector2(300, 150)
	_vs.position = Vector2(330, 170)
	_vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs.pivot_offset = Vector2(150, 75)
	_vs.scale = Vector2(4, 4)
	_vs.modulate.a = 0.0
	add_child(_vs)
	_labels.append(_vs)
	var stage := UiKit.label(String(sim.stage()["name"]).to_upper(), 18, UiKit.TEXT, 6)
	stage.size = Vector2(960, 30)
	stage.position = Vector2(0, 500)
	stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.modulate.a = 0.0
	add_child(stage)
	_labels.append(stage)

	var speed := 0.55 if short else 1.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "_split", 1.0, 0.3 * speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_p1, "position:x", 20.0, 0.35 * speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_p2, "position:x", 560.0, 0.35 * speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(name1, "position:x", 40.0, 0.4 * speed).set_delay(0.1 * speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(name2, "position:x", 520.0, 0.4 * speed).set_delay(0.1 * speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_vs, "scale", Vector2.ONE, 0.22 * speed).set_delay(0.35 * speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_vs, "modulate:a", 1.0, 0.1 * speed).set_delay(0.35 * speed)
	tween.tween_property(stage, "modulate:a", 1.0, 0.3 * speed).set_delay(0.5 * speed)
	tween.tween_callback(func() -> void: Sfx.play("heavy_hit")).set_delay(0.4 * speed)
	await tween.finished
	await get_tree().create_timer(1.1 * speed).timeout
	var out := create_tween()
	out.tween_property(self, "modulate:a", 0.0, 0.25 * speed)
	await out.finished
	visible = false
	for child in get_children():
		child.queue_free()
	_labels.clear()


func _portrait(id: String, facing: int) -> FighterPortrait:
	var portrait := FighterPortrait.new()
	portrait.fighter_id = id
	portrait.facing = facing
	portrait.animation = "intro"
	portrait.size = Vector2(380, 400)
	add_child(portrait)
	return portrait


func _name_label(title: String, role: String, color: Color, align: HorizontalAlignment) -> Control:
	var box := VBoxContainer.new()
	box.size = Vector2(400, 80)
	box.add_theme_constant_override("separation", 0)
	var title_label := UiKit.label(title, 46, Color.WHITE, 12, Color("#0b0e18"))
	title_label.horizontal_alignment = align
	box.add_child(title_label)
	var sub := UiKit.label(role, 16, color, 6)
	sub.horizontal_alignment = align
	box.add_child(sub)
	add_child(box)
	_labels.append(box)
	return box


func _draw() -> void:
	var w := maxf(size.x, 960.0)
	var h := maxf(size.y, 540.0)
	var cut := w / 2.0
	var slant := 90.0
	var open := 1.0 - _split
	# Mitades de color que entran desde los lados.
	draw_colored_polygon(PackedVector2Array([Vector2(-w * open, 0), Vector2(cut + slant - w * open, 0),
		Vector2(cut - slant - w * open, h), Vector2(-w * open, h)]), _left_color)
	draw_colored_polygon(PackedVector2Array([Vector2(cut + slant + w * open, 0), Vector2(w + w * open, 0),
		Vector2(w + w * open, h), Vector2(cut - slant + w * open, h)]), _right_color)
	# Líneas de velocidad pixeladas.
	for i in range(22):
		var y := float((i * 47) % int(h))
		var length := 60.0 + float((i * 31) % 120)
		var speed := 600.0 + (i % 5) * 180.0
		if i % 2 == 0:
			var x := fmod(_time * speed + i * 97.0, cut + 200.0) - 200.0
			draw_rect(Rect2(x - w * open, y, length, 2), Color(_left_accent, 0.35))
		else:
			var x2 := w - fmod(_time * speed + i * 97.0, cut + 200.0)
			draw_rect(Rect2(x2 + w * open, y, length, 2), Color(_right_accent, 0.35))
	# Franja central de energía con chispas.
	if _split > 0.9:
		var glow := 0.6 + 0.4 * sin(_time * 20.0)
		draw_line(Vector2(cut + slant, 0), Vector2(cut - slant, h), Color(1, 1, 1, glow), 6.0)
		draw_line(Vector2(cut + slant + 6, 0), Vector2(cut - slant + 6, h), Color(UiKit.GOLD, glow * 0.6), 3.0)
		for i in range(8):
			var t := fmod(_time * 1.5 + i * 0.125, 1.0)
			var px := lerpf(cut + slant, cut - slant, t) + sin(_time * 30.0 + i) * 8.0
			draw_rect(Rect2(px - 2, t * h - 2, 4, 4), UiKit.GOLD)
