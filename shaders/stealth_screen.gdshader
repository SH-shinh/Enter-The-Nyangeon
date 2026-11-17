// Stealth screen edge: subtle screen-space refraction + chromatic separation + cyan scanline/vignette.
// Inspired by the Distortion/Shockwave Shader on Godot Shaders (CC0):
// https://godotshaders.com/shader/distortion/
// This ENN variant keeps the center clear and only affects the outer screen edge.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 resolution = vec2(1280.0, 720.0);

uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform float strength : hint_range(0.0, 0.05, 0.001) = 0.008;
uniform float radius : hint_range(0.0, 1.5, 0.001) = 0.5;
uniform float width : hint_range(0.0, 1.0, 0.001) = 0.5;
uniform float feather : hint_range(0.0, 1.0, 0.001) = 0.16;
uniform float aberration : hint_range(0.0, 1.0, 0.001) = 0.2;
uniform vec3 tint = vec3(0.36, 0.78, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.14;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.2;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / resolution;
	vec2 snapped = (floor(uv * resolution) + 0.5) / resolution;
	vec2 centered = (snapped - 0.5) * vec2(1.0, resolution.y / resolution.x);
	float d = length(centered);
	float edge = smoothstep(radius - width, radius, d);
	edge = clamp(edge + smoothstep(radius - width - feather, radius - width, d) * 0.25, 0.0, 1.0);

	vec2 dir = d > 0.0001 ? centered / d : vec2(0.0);
	float wave = sin(d * 22.0 - TIME * 1.7) * 0.55 + sin(d * 9.0 + TIME * 0.9) * 0.45;
	vec2 offset = dir * strength * edge * (0.7 + 0.3 * wave);
	vec2 sample_uv = uv + offset;
	vec2 ab = dir * aberration * px.x * edge;

	vec3 original = texture(screen_tex, snapped).rgb;
	vec3 refracted = vec3(
		texture(screen_tex, sample_uv + ab).r,
		texture(screen_tex, sample_uv).g,
		texture(screen_tex, sample_uv - ab).b
	);

	float pulse = 0.85 + 0.15 * sin(TIME * 2.0);
	refracted = mix(refracted, refracted * tint, tint_strength * edge * pulse);
	float line = step(0.5, fract(snapped.y * resolution.y * 0.5));
	refracted *= 1.0 - scanline_strength * line * edge;
	refracted *= 1.0 - vignette_strength * edge;

	COLOR = vec4(mix(original, refracted, edge * open), 1.0);
}
