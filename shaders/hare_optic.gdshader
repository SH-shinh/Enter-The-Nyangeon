// Hare 锁定态战术目镜：黄绿夜视 + 扫描线/扫描带 + 像素暗角 + 边缘数字雨。
// 中心不覆盖：edge_mask 从中心 0 平滑过渡到边缘 1，数字雨只出现在最外圈。
// 全程线性色（项目 viewport/hdr_2d），不做 sRGB 转换；逻辑像素吸附避免模糊。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

uniform vec2 resolution = vec2(640.0, 360.0);
uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint = vec3(0.72, 1.0, 0.30);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.35;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.22;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float aberration : hint_range(0.0, 4.0) = 1.0;
uniform float sweep_speed = 0.35;

// 边缘遮罩：中心干净、边缘最强
uniform float edge_inner = 0.30;
uniform float edge_outer = 0.78;

// 数字雨
uniform float rain_strength : hint_range(0.0, 1.0) = 0.7;
uniform float rain_speed = 0.5;
uniform float rain_density = 0.55;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = vec2(1.0) / resolution;
	vec2 snapped = (floor(uv * resolution) + 0.5) / resolution;
	vec2 c = (snapped - 0.5) * vec2(1.0, 0.62);
	float d = length(c);
	float edge = smoothstep(edge_inner, edge_outer, d);
	float rain_mask = smoothstep(0.48, 0.92, d);
	float reveal = smoothstep(0.0, 0.45, open);

	vec3 orig = texture(screen_tex, snapped).rgb;

	// 轻微色差
	vec3 chr = orig;
	chr.r = texture(screen_tex, snapped + vec2(aberration * px.x, 0.0)).r;
	chr.b = texture(screen_tex, snapped - vec2(aberration * px.x, 0.0)).b;

	// 黄绿 tint + 提亮
	vec3 filt = mix(chr, chr * tint, tint_strength) * 1.08;

	// 扫描线：每 2 逻辑像素一条暗线
	float line = step(0.5, fract(snapped.y * resolution.y * 0.5));
	filt *= 1.0 - scanline_strength * line;

	// 缓慢下移的扫描带
	float band_y = fract(TIME * sweep_speed);
	float band = 1.0 - smoothstep(0.0, 0.06, abs(fract(snapped.y - band_y + 0.5) - 0.5));
	filt += tint * 0.10 * band;

	// 像素化暗角
	filt *= 1.0 - vignette_strength * smoothstep(edge_inner, edge_outer, d);

	// 开启光环：从中心向外扫一次（只在边缘区域叠加）
	float ring = 1.0 - smoothstep(0.0, 0.06, abs(d - open * 0.9));
	filt += tint * 0.18 * ring * edge;

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
	filt += tint * rain * rain_strength * rain_mask * 0.80;

	// 中心保持原画，边缘平滑过渡到滤镜
	float mix_k = clamp(edge * reveal + ring * 0.25 * edge, 0.0, 1.0);
	COLOR = vec4(mix(orig, filt, mix_k), 1.0);
}
