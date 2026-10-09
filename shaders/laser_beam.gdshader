shader_type canvas_item;

uniform float jitter_amount : hint_range(0.0, 1.0) = 0.35;
uniform float jitter_freq : hint_range(1.0, 80.0) = 36.0;
uniform float jitter_speed : hint_range(0.0, 20.0) = 12.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float n = noise(vec2(UV.x * jitter_freq, TIME * jitter_speed));
	float edge = abs(UV.y - 0.5) * 2.0;
	float fade = 1.0 - jitter_amount * edge * (0.5 + 0.5 * n);
	c.a *= clamp(fade, 0.0, 1.0);
	COLOR = c;
}
