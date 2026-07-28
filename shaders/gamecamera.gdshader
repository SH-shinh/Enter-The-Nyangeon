shader_type canvas_item;

uniform float cutoff: hint_range(0.0, 1.0, 0.1);
uniform float smooth_size: hint_range(0.0, 1.0, 0.1);
uniform sampler2D mask;

void fragment() {
	float value = texture(mask, UV).r;
	float alpha = smoothstep(cutoff, cutoff + smooth_size, value + smooth_size);
	COLOR = vec4(COLOR.rgb, alpha);
}
