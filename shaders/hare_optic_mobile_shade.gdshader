// Hare 目镜移动端安全版（压暗层）：不读取屏幕纹理，避免 hint_screen_texture 机型风险。
// 只做边缘扫描线与暗角压暗；中央 edge=0 保持原画。
shader_type canvas_item;
render_mode blend_mix;

uniform vec2 resolution = vec2(640.0, 360.0);
uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.6;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.8;
uniform float edge_inner = 0.0;
uniform float edge_outer = 0.78;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 snapped = (floor(uv * resolution) + 0.5) / resolution;
	vec2 c = (snapped - 0.5) * vec2(1.0, 0.62);
	float d = length(c);
	float edge = smoothstep(edge_inner, edge_outer, d);
	float reveal = smoothstep(0.0, 0.45, open);
	// 每 2 逻辑像素一条暗线；只作用在边缘区域。
	float line = step(0.5, fract(snapped.y * resolution.y * 0.5));
	float dark = edge * (scanline_strength * 0.7 * line + vignette_strength * 0.45 * edge);
	COLOR = vec4(0.0, 0.0, 0.0, clamp(dark * reveal, 0.0, 0.7));
}
