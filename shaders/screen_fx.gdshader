// Efectos de pantalla para las animaciones pesadas: onda expansiva del impacto,
// aberración cromática, "impact frame" de alto contraste y K.O. desaturado.
// Lenguaje de shaders de Godot (basado en GLSL ES 3.0). Lo controla ScreenFx
// (scripts/render/screen_fx.gd), que oculta el nodo cuando no hay ningún efecto.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// Onda expansiva (coordenadas UV de pantalla).
uniform vec2 shock_center = vec2(0.5, 0.5);
uniform float shock_radius = 0.0;
uniform float shock_strength = 0.0;
uniform float shock_width = 0.07;
uniform float aspect = 1.7777;

// Aberración cromática: separa rojo y azul desde el centro.
uniform float aberration = 0.0;

// Impact frame: la imagen se reduce a dos tonos durante unos cuadros.
uniform float impact = 0.0;
uniform vec4 impact_color : source_color = vec4(0.5, 0.9, 1.0, 1.0);

// K.O.: desaturación, viñeta y tinte.
uniform float desaturate = 0.0;
uniform float vignette = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Onda: los píxeles cercanos al anillo se empujan hacia fuera del centro.
	vec2 delta = uv - shock_center;
	delta.x *= aspect;
	float dist = length(delta);
	float ring = 1.0 - smoothstep(0.0, shock_width, abs(dist - shock_radius));
	vec2 dir = dist > 0.0001 ? delta / dist : vec2(0.0);
	dir.x /= aspect;
	uv -= dir * ring * shock_strength * 0.035;

	vec2 split = (uv - 0.5) * aberration;
	vec3 col;
	col.r = texture(screen_tex, uv + split).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - split).b;

	// El borde de la onda brilla un poco.
	col += ring * shock_strength * 0.18;

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), desaturate);
	col = mix(col, col * tint.rgb, tint_amount);

	if (impact > 0.0) {
		// Dos tonos: sombras casi negras y luces del color de la energía.
		vec3 two_tone = lum > 0.42 ? mix(impact_color.rgb, vec3(1.0), 0.45) : vec3(0.03, 0.03, 0.06);
		col = mix(col, two_tone, impact);
	}

	vec2 v = SCREEN_UV - 0.5;
	col *= 1.0 - vignette * dot(v, v) * 2.4;

	COLOR = vec4(col, 1.0);
}
