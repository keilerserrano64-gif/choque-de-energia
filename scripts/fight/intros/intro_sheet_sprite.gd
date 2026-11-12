extends Node2D
## Dibuja un cuadro de la hoja de la intro de Madara Edo (atlas + manifiesto que genera
## tools/slice_intro_sheet.gd) dentro de la arena, con los pies en `position`.
## La escala la pone el controlador para que el personaje mida lo mismo que su sprite
## de combate; `mira` (+1/-1) voltea la imagen según hacia dónde mira el luchador.

const MANIFIESTO := "res://assets/fighters/madara_edo/intro/madara_edo_intro_frames.json"
## Difumina los bordes de cada cuadro: el aura de chakra de la hoja llega al borde de su
## celda y, sin esto, se vería cortada en línea recta.
const SHADER_BORDES := """
shader_type canvas_item;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0); // x, y, ancho, alto en UV del atlas
uniform vec2 borde = vec2(0.2, 0.16);           // fracción de la celda que se funde
uniform float ovalo = 0.0;                      // 1 = el dibujo acaba en óvalo (humo pintado)
uniform vec4 contenido = vec4(0.0, 0.0, 1.0, 1.0); // parte visible del cuadro (para el óvalo)
uniform float quitar_aura = 0.0;                // 1 = borra el aura morada/azul (se dibuja aparte como luz)
uniform float lados = 0.0;                      // 1 = funde los lados del dibujo (restos de fondo pintado)
void fragment() {
	vec2 p = (UV - region.xy) / region.zw;
	vec2 q = (UV - contenido.xy) / contenido.zw;
	float fx = smoothstep(0.0, borde.x, p.x) * smoothstep(0.0, borde.x, 1.0 - p.x);
	float fy = smoothstep(0.0, borde.y, p.y) * smoothstep(0.0, borde.y * 0.35, 1.0 - p.y);
	float d = length((q - vec2(0.5, 0.6)) / vec2(0.52, 0.6));
	float o = mix(1.0, 1.0 - smoothstep(0.55, 0.98, d), ovalo);
	vec4 tc = texture(TEXTURE, UV);
	float aura = (tc.b - tc.r * 0.6) * smoothstep(0.35, 0.6, max(tc.b, tc.r));
	float l = mix(1.0, smoothstep(0.0, 0.2, q.x) * smoothstep(0.0, 0.2, 1.0 - q.x), lados);
	COLOR.a *= fx * fy * o * l * (1.0 - quitar_aura * smoothstep(0.22, 0.45, aura));
}
"""
## Modo luz (Susanoo de chakra): mezcla aditiva que borra lo oscuro del dibujo (el fondo
## pintado de la celda) y deja brillar lo claro; los bordes de la celda se difuminan.
const SHADER_LUZ := """
shader_type canvas_item;
render_mode blend_add;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 contenido = vec4(0.0, 0.0, 1.0, 1.0);
uniform float ganancia = 1.5;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 p = (UV - contenido.xy) / contenido.zw;
	// Máscara ovalada en vez del recorte rectangular de la celda: el resplandor acaba suave.
	float d = length((p - vec2(0.5, 0.56)) / vec2(0.5, 0.5));
	float ovalo = 1.0 - smoothstep(0.62, 1.0, d);
	float ovalo_relleno = 1.0 - smoothstep(0.35, 0.85, d);
	// Las líneas de chakra (lo más brillante) se ven enteras; el relleno azul, tenue.
	float brillo = max(c.r, max(c.g, c.b));
	float lineas = smoothstep(0.68, 0.92, brillo) * step(c.r * 0.45 + 0.05, c.b);
	float chakra = smoothstep(0.12, 0.42, c.b - c.r * 0.45 - 0.1);
	float k = max(lineas * ovalo, chakra * 0.45 * ovalo_relleno);
	COLOR = vec4(c.rgb * ganancia, c.a * k * COLOR.a);
}
"""

var luz := false        ## true = modo luz (ponerlo antes de preparar)
var ovalo := 0.0        ## 1 = recorte ovalado (cuadros con humo pintado hasta el borde)
var contenidos: Array = []  ## rect del contenido visible de cada cuadro (mismo índice que cuadros)
var quitar_aura := 0.0      ## 1 = el aura pintada no se dibuja (otra capa la pone como luz)
var lados := 0.0            ## 1 = funde los lados del dibujo
var manifiesto: Dictionary = {}
var atlas: Texture2D
var cuadro := -1      ## índice en manifiesto.cuadros (-1 = nada)
var alfa := 1.0
var escala := 1.0
var mira := 1.0       ## hacia dónde mira el luchador en el juego
var _mira_hoja := 1.0 ## hacia dónde mira el dibujo en la hoja


## Lee el manifiesto. Devuelve {} si falta algo (la intro usará entonces los cuadros de siempre).
static func leer_manifiesto() -> Dictionary:
	if not FileAccess.file_exists(MANIFIESTO):
		return {}
	var datos: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFIESTO))
	if not (datos is Dictionary):
		return {}
	var m: Dictionary = datos
	if not m.has("cuadros") or not m.has("fases") or not ResourceLoader.exists(String(m.get("atlas", ""))):
		return {}
	return m


func preparar(m: Dictionary) -> bool:
	manifiesto = m
	atlas = load(String(m.get("atlas", ""))) as Texture2D
	_mira_hoja = -1.0 if String(m.get("mira", "derecha")) == "izquierda" else 1.0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sh := Shader.new()
	sh.code = SHADER_LUZ if luz else SHADER_BORDES
	var mat := ShaderMaterial.new()
	mat.shader = sh
	material = mat
	return atlas != null


## Índice global del cuadro i de una fase (o -1).
func indice(fase: String, i: int) -> int:
	var lista: Array = (manifiesto.get("fases", {}) as Dictionary).get(fase, [])
	if lista.is_empty():
		return -1
	return int(lista[clampi(i, 0, lista.size() - 1)])


func cuantos(fase: String) -> int:
	return ((manifiesto.get("fases", {}) as Dictionary).get(fase, []) as Array).size()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if atlas == null or cuadro < 0 or alfa <= 0.0:
		return
	var cuadros: Array = manifiesto["cuadros"]
	if cuadro >= cuadros.size():
		return
	var r: Array = (cuadros[cuadro] as Dictionary)["rect"]
	var celda := Vector2(float(r[2]), float(r[3]))
	var ancla_v: Array = manifiesto.get("ancla", [celda.x * 0.5, celda.y])
	var ancla := Vector2(float(ancla_v[0]), float(ancla_v[1]))
	var tam := atlas.get_size()
	(material as ShaderMaterial).set_shader_parameter("region",
		Vector4(float(r[0]) / tam.x, float(r[1]) / tam.y, celda.x / tam.x, celda.y / tam.y))
	var c: Array = r
	if cuadro < contenidos.size():
		c = (contenidos[cuadro] as Dictionary)["rect"]
	(material as ShaderMaterial).set_shader_parameter("contenido",
		Vector4(float(c[0]) / tam.x, float(c[1]) / tam.y, float(c[2]) / tam.x, float(c[3]) / tam.y))
	if not luz:
		(material as ShaderMaterial).set_shader_parameter("ovalo", ovalo)
		(material as ShaderMaterial).set_shader_parameter("quitar_aura", quitar_aura)
		(material as ShaderMaterial).set_shader_parameter("lados", lados)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(escala * mira * _mira_hoja, escala))
	draw_texture_rect_region(atlas, Rect2(-ancla, celda), Rect2(float(r[0]), float(r[1]), celda.x, celda.y), Color(1, 1, 1, alfa))
	draw_set_transform(Vector2.ZERO)
