// Efectos del luchador durante las animaciones pesadas (despertar, cargas, remates).
// Lenguaje de shaders de Godot (basado en GLSL ES 3.0); Godot lo traduce a GLSL.
// Se aplica a la capa de dibujo de cada luchador en ArenaView. Con glow = 0 y
// surge = 0 el luchador se ve exactamente igual que sin shader.
shader_type canvas_item;

// 0..1: venas de energía que recorren el cuerpo y contorno eléctrico.
uniform float glow : hint_range(0.0, 1.0) = 0.0;
// 0..1: destello en el instante del golpe pesado o del lanzamiento de la técnica.
uniform float surge : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(0.5, 0.9, 1.0, 1.0);
// Grosor del contorno en píxeles de la imagen.
uniform float outline_px = 1.5;
// Pixel art nítido: con la capa en filtro lineal, cada píxel de la imagen se ve del mismo
// tamaño a cualquier escala (no entera), giro o zoom, con el borde apenas suavizado. Sin
// esto, el filtro «vecino más cercano» a escala 1,84 o 2,46 duplica unas filas y otras no,
// y al girar o estirar al luchador los bordes hacen escalones que tiemblan.
uniform bool pixel_nitido = true;

varying vec4 color_vertice;

void vertex() {
	color_vertice = COLOR;
}

vec2 uv_nitido(vec2 uv, vec2 tam) {
	vec2 px = uv * tam;
	vec2 centro = floor(px + 0.5);
	vec2 ancho = max(fwidth(px), vec2(1e-4));
	px = centro + clamp((px - centro) / ancho, -0.5, 0.5);
	return px / tam;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	// En Godot 4, COLOR ya llega multiplicado por la textura: volver a multiplicar por
	// texture(TEXTURE, UV) elevaba cada color al cuadrado y oscurecía a los luchadores.
	vec4 base = COLOR;
	// textureGrad con las derivadas de UV originales: el nivel de mipmap correcto aunque
	// uv_nitido «escalone» la coordenada (hojas HD dibujadas más pequeñas que su tamaño).
	vec4 muestra = pixel_nitido
		? textureGrad(TEXTURE, uv_nitido(UV, 1.0 / TEXTURE_PIXEL_SIZE), dFdx(UV), dFdy(UV))
		: texture(TEXTURE, UV);
	if (pixel_nitido) {
		base = color_vertice * muestra;
	}
	// Silueta de color (estelas y rastros de golpe): FighterPainter.silueta() la marca con
	// un color negativo. Se pinta la forma del sprite de ese color, sin su textura.
	if (color_vertice.r < -0.5) {
		base = vec4(-color_vertice.rgb - 1.0, muestra.a * color_vertice.a);
	}
	vec4 result = base;

	if (glow > 0.0) {
		// Venas: una franja estrecha de ruido que se desplaza, en coordenadas de
		// pantalla para que funcione igual en imágenes y en luchadores de rectángulos.
		vec2 p = FRAGCOORD.xy / 14.0;
		float n = value_noise(p + vec2(0.0, -TIME * 4.0)) * 0.7
			+ value_noise(p * 1.7 + vec2(TIME * 3.0, 0.0)) * 0.3;
		float vein = smoothstep(0.60, 0.62, n) * (1.0 - smoothstep(0.63, 0.66, n));
		result.rgb = mix(result.rgb, glow_color.rgb * 1.4, vein * glow * 0.6 * base.a);

		// Contorno eléctrico alrededor de la silueta. Solo aparece en imágenes: en los
		// rectángulos la textura es lisa y no hay bordes transparentes que detectar.
		float neighbour = 0.0;
		vec2 px = TEXTURE_PIXEL_SIZE * outline_px;
		for (int i = 0; i < 8; i++) {
			float angle = float(i) * 0.785398;
			neighbour = max(neighbour, texture(TEXTURE, UV + vec2(cos(angle), sin(angle)) * px).a);
		}
		float edge = clamp(neighbour - texture(TEXTURE, UV).a, 0.0, 1.0);
		float flicker = 0.55 + 0.45 * sin(TIME * 28.0 + FRAGCOORD.y * 0.35);
		float edge_alpha = edge * glow * flicker * COLOR.a;
		result.rgb = mix(result.rgb, glow_color.rgb * 1.3, edge_alpha);
		result.a = max(result.a, edge_alpha);
	}

	if (surge > 0.0) {
		// Destello: el cuerpo se aclara hacia blanco con un toque del color de energía.
		vec3 hot = mix(vec3(1.0), glow_color.rgb, 0.35);
		result.rgb = mix(result.rgb, hot, surge * base.a);
	}

	COLOR = result;
}
