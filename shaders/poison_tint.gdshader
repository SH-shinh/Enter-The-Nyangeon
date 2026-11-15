shader_type canvas_item;

// 毒池气泡的配色置换：把腐化池那套紫色气泡按亮度重映射成毒的绿色，
// 保留原有的鼓起/破裂/高光层次与 alpha（暗部→深绿，亮部→浅绿）。
uniform vec4 dark_color : source_color = vec4(0.03, 0.14, 0.08, 1.0);
uniform vec4 light_color : source_color = vec4(0.45, 1.0, 0.55, 1.0);
uniform float luma_gain : hint_range(0.5, 3.0) = 1.6;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float l = clamp(dot(c.rgb, vec3(0.299, 0.587, 0.114)) * luma_gain, 0.0, 1.0);
	COLOR = vec4(mix(dark_color.rgb, light_color.rgb, l), c.a);
}
