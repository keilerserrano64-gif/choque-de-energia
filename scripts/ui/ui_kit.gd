class_name UiKit
extends RefCounted
## Colores y estilos compartidos por todas las pantallas.

const BG := Color("#0c0f17")
const PANEL := Color("#141a29")
const PANEL_LIGHT := Color("#1d2538")
const LINE := Color("#2c3650")
const TEXT := Color("#eef2ff")
const MUTED := Color("#8e9ab8")
const ACCENT := Color("#66d9ff")
const GOLD := Color("#ffd36e")
const P1_COLOR := Color("#3f8cff")
const P2_COLOR := Color("#ff4d5a")
const BLUE_PAGE := Color("#1d3f8f")
const RED_PAGE := Color("#8f1d2c")


static func panel(bg: Color = PANEL, border: Color = LINE, border_width: int = 2, radius: int = 6, skew_x: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.skew = Vector2(skew_x, 0.0)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.anti_aliasing = false
	return style


static func label(text: String, size: int = 16, color: Color = TEXT, outline: int = 0, outline_color: Color = Color(0, 0, 0, 0.85)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	return l


static func style_label(l: Label, size: int, color: Color = TEXT, outline: int = 0, outline_color: Color = Color(0, 0, 0, 0.85)) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)


## Botón de menú con estado de foco muy visible (para jugar con teclado o mando).
static func style_button(b: Button, accent: Color = ACCENT, size: int = 20, skew_x: float = -0.18) -> void:
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", BG)
	b.add_theme_color_override("font_focus_color", BG)
	b.add_theme_color_override("font_pressed_color", BG)
	b.add_theme_color_override("font_disabled_color", Color(MUTED, 0.5))
	b.add_theme_stylebox_override("normal", panel(Color(PANEL, 0.88), LINE, 2, 3, skew_x))
	b.add_theme_stylebox_override("hover", panel(accent, accent.lightened(0.35), 2, 3, skew_x))
	b.add_theme_stylebox_override("focus", panel(accent, Color.WHITE, 3, 3, skew_x))
	b.add_theme_stylebox_override("pressed", panel(accent.lightened(0.25), Color.WHITE, 3, 3, skew_x))
	b.add_theme_stylebox_override("disabled", panel(Color(PANEL, 0.5), Color(LINE, 0.5), 2, 3, skew_x))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL


static func make_button(text: String, accent: Color = ACCENT, size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, accent, size)
	return b


static func style_slider(s: Range) -> void:
	s.add_theme_stylebox_override("slider", panel(LINE, LINE, 0, 3))
	s.add_theme_stylebox_override("grabber_area", panel(ACCENT, ACCENT, 0, 3))
	s.add_theme_stylebox_override("grabber_area_highlight", panel(GOLD, GOLD, 0, 3))
