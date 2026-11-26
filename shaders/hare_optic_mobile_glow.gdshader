// Hare 目镜移动端安全版（加色层）：不读取屏幕纹理。
// 边缘绿黄 tint、下移扫描带、开启环、最外圈数字雨；中央 edge=0 零贡献。
shader_type canvas_item;
render_mode blend_add;

uniform vec2 resolution = vec2(640.0, 360.0);
uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint = vec3(0.72, 1.0, 0.30);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.8;
uniform float sweep_speed = 0.35;
uniform float edge_inner = 0.0;
uniform float edge_outer = 0.78;
uniform float rain_strength : hint_range(0.0, 1.0) = 1.0;
uniform float rain_speed = 0.5;
uniform float rain_density = 0.55;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 snapped = (floor(uv * resolution) + 0.5) / resolution;
	vec2 c = (snapped - 0.5) * vec2(1.0, 0.62);
	float d = length(c);
	float edge = smoothstep(edge_inner, edge_outer, d);
	float rain_mask = smoothstep(0.48, 0.92, d);
	float reveal = smoothstep(0.0, 0.45, open);

	// 下移扫描带
	float band_y = fract(TIME * sweep_speed);
	float band = 1.0 - smoothstep(0.0, 0.06, abs(fract(snapped.y - band_y + 0.5) - 0.5));

	// 开启环：从中心向外扫一次（只在边缘区域叠加）
	float ring = 1.0 - smoothstep(0.0, 0.06, abs(d - open * 0.9));

	// 数字雨：32 列 × 60 行，随机速度/相位，只在最外圈
	float cols = 32.0;
	float rows = 60.0;
	float col = floor(uv.x * cols);
	float col_seed = hash21(vec2(col, 7.0));
	float speed = 0.45 + col_seed * 0.9;
	float y = fract(uv.y + TIME * speed * rain_speed + col_seed * 11.0);
	float row = floor(y * rows);
	vec2 cell = vec2(fract(uv.x * cols), fract(y * rows));
	vec2 g = floor(cell * vec2(3.0, 5.0));
	float bits = step(0.5, hash21(vec2(g.x + col * 3.0, g.y + row * 5.0)));
	float glyph_on = step(rain_density, hash21(vec2(col, row)));
	float head = 1.0 - smoothstep(0.0, 0.25, y);
	float rain = bits * glyph_on * (0.45 + 0.55 * head);

	float glow = edge * (0.18 + tint_strength * 0.35);
	glow += edge * band * 0.22;
	glow += edge * ring * 0.55;
	glow += rain * rain_strength * 0.85 * rain_mask;
	COLOR = vec4(tint * glow * reveal, 1.0);
}
