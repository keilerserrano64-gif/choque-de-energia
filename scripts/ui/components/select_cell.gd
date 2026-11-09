class_name SelectCell
extends Control
## Casilla de la cuadrícula de selección: retrato del luchador, "?" para
## aleatorio o emblema decorativo. Dibuja los cursores de J1 (azul) y J2 (rojo).

const RANDOM := -1
const EMBLEM := -2

var fighter_index := 0
var page_color := UiKit.BLUE_PAGE
var p1_here := false
var p2_here := false
var p1_locked := false
var p2_locked := false
var p2_label := "J2"
var _portrait: FighterPortrait
var _caption: Label
var _time := 0.0


func setup(index: int, color: Color) -> void:
	fighter_index = index
	page_color = color
	custom_minimum_size = Vector2(84, 84)
	size = Vector2(84, 84)
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	if index >= 0:
		var fighter: Dictionary = Catalog.FIGHTERS[index]
		_portrait = FighterPortrait.new()
		_portrait.fighter_id = String(fighter["id"])
		_portrait.crop = FighterPortrait.Crop.BUST
		_portrait.animation = "idle"
		_portrait.animate = false
		_portrait.position = Vector2(4, 4)
		_portrait.size = Vector2(76, 76)
		add_child(_portrait)
		_caption = UiKit.label(String(fighter["name"]).to_upper(), 11, UiKit.TEXT, 4)
	elif index == RANDOM:
		_caption = UiKit.label("ALEATORIO", 10, UiKit.GOLD, 4)
		var mark := UiKit.label("?", 46, UiKit.GOLD, 8)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.position = Vector2(0, 6)
		mark.size = Vector2(84, 60)
		add_child(mark)
	else:
		_caption = UiKit.label("", 10)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.position = Vector2(0, 66)
	_caption.size = Vector2(84, 16)
	add_child(_caption)


func is_selectable() -> bool:
	return fighter_index != EMBLEM


func _process(delta: float) -> void:
	_time += delta
	var hovered := p1_here or p2_here
	var target := 1.1 if hovered else 1.0
	scale = scale.lerp(Vector2(target, target), minf(1.0, delta * 14.0))
	if _portrait:
		_portrait.animate = hovered
	z_index = 2 if hovered else 0
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var bg := page_color.darkened(0.55)
	if fighter_index == EMBLEM:
		bg = page_color.darkened(0.35)
	draw_rect(rect, bg)
	draw_rect(Rect2(2, 2, size.x - 4, size.y * 0.45), Color(1, 1, 1, 0.05))
	draw_rect(rect, Color("#090b12"), false, 3.0)
	if fighter_index == EMBLEM:
		var c := size / 2.0
		var star := PackedVector2Array([c + Vector2(0, -22), c + Vector2(6, -6), c + Vector2(22, 0), c + Vector2(6, 6),
			c + Vector2(0, 22), c + Vector2(-6, 6), c + Vector2(-22, 0), c + Vector2(-6, -6)])
		draw_colored_polygon(star, Color(1, 1, 1, 0.18))
	var blink := fmod(_time, 0.5) < 0.25
	if p1_here and p2_here:
		draw_rect(rect.grow(1), UiKit.P1_COLOR, false, 4.0)
		draw_rect(rect.grow(-3), UiKit.P2_COLOR, false, 3.0)
	elif p1_here:
		var c1 := UiKit.GOLD if (blink and not p1_locked) else UiKit.P1_COLOR
		draw_rect(rect.grow(1), c1, false, 4.0)
	elif p2_here:
		var c2 := UiKit.GOLD if (blink and not p2_locked) else UiKit.P2_COLOR
		draw_rect(rect.grow(1), c2, false, 4.0)
	var font := ThemeDB.fallback_font
	if p1_here:
		draw_rect(Rect2(-4, -10, 26, 16), UiKit.P1_COLOR)
		draw_string(font, Vector2(-1, 3), "J1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	if p2_here:
		var w := 38.0 if p2_label.length() > 2 else 26.0
		draw_rect(Rect2(size.x - w + 4, -10, w, 16), UiKit.P2_COLOR)
		draw_string(font, Vector2(size.x - w + 7, 3), p2_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
