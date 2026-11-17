shader_type canvas_item;

// Kotama 全息影像：从下往上显影 + 水平扫描线 + 少量 RGB 分离/坏行闪烁。
// 由 KotamaHologram 在 intro 时把 reveal 从 0 拉到 1；常驻靠 TIME 做扫描线/flicker。
uniform vec4 tint : source_color = vec4(0.55, 0.90, 1.0, 0.85);
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float scan_speed : hint_range(0.0, 8.0) = 2.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.18;
uniform float split : hint_range(0.0, 4.0) = 1.0;
uniform float white_scan : hint_range(0.0, 1.0) = 0.70;
uniform float white_scan_speed = 0.55;
uniform float white_scan_width : hint_range(0.0, 0.1) = 0.020;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV;
	vec4 base = texture(TEXTURE, uv);
	// 从下往上显影：reveal=0 全隐，reveal=1 全显。
	float reveal_mask = step(1.0 - reveal, uv.y);
	float scan = 0.5 + 0.5 * sin((uv.y + TIME * scan_speed) * 180.0);
	float row = floor(uv.y * 48.0);
	float glitch = step(1.0 - flicker * 0.35, hash(row + floor(TIME * 10.0)));
	vec2 off = vec2(split * 0.0018, 0.0);
	vec3 col = vec3(texture(TEXTURE, uv + off).r, base.g, texture(TEXTURE, uv - off).b);
	float alpha = base.a * tint.a * reveal_mask * (0.62 + 0.38 * scan);
	if (glitch > 0.5) {
		alpha *= 0.35;
		col += vec3(0.12, 0.18, 0.25);
	}

	// 白色水平扫描带：只画在角色轮廓内，箱子不挂此材质。
	float body_mask = smoothstep(0.02, 0.25, base.a);
	float band_center = 0.5 + 0.5 * sin(TIME * white_scan_speed * TAU);
	float white_band = (1.0 - smoothstep(0.0, white_scan_width, abs(uv.y - band_center))) * body_mask;
	vec3 lit = col * tint.rgb;
	lit = mix(lit, vec3(1.0), white_band * white_scan * reveal_mask);
	alpha = max(alpha, white_band * tint.a * reveal_mask * 0.9);
	COLOR = vec4(lit, alpha);
}
