shader_type canvas_item;

uniform float outline_width = 1.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float flash_opacity : hint_range(0.0, 1.0, 0.1) = 0.0;
uniform vec4 corruption_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float corruption_amount : hint_range(0.0, 1.0, 0.01) = 0.0;

// 策反「信号故障」：衰减完全在 shader 内按 glitch_clock 计算；GDScript 只在命中时写 glitch_start/seed。
// 未使用者默认 glitch_start 在过去 → amount = 0，输出与旧版逐像素一致。
global uniform float glitch_clock;
uniform float glitch_start = -1000.0;
uniform float glitch_duration = 0.30;
uniform float glitch_strength = 1.0;
uniform float glitch_seed = 0.0;
// 水平撕裂开关（Sprite2D 堆叠切片为 0）
uniform float glitch_tear = 1.0;
// 故障位移用的单像素 UV 尺寸；描边不用它（固定 TEXTURE_PIXEL_SIZE）。
uniform vec2 glitch_pixel = vec2(0.0, 0.0);
// Sprite2D(hframes/region) 的帧 UV 矩形；其余情况为整张 (0,0,1,1)。
uniform vec4 glitch_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

// 可调参数（默认值 = 原硬编码值）
uniform float glitch_row_gate : hint_range(0.0, 1.0, 0.01) = 0.66;
uniform float glitch_row_shift = 3.0;
uniform float glitch_block_size = 8.0;
uniform float glitch_block_shift = 6.0;
uniform float glitch_rgb_split = 1.0;
uniform float glitch_scanline : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float glitch_junk_gate : hint_range(0.0, 1.0, 0.001) = 0.972;

float glitch_hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453123);
}

void fragment() {
	float elapsed = max(glitch_clock - glitch_start, 0.0);
	float amount = clamp(1.0 - elapsed / max(glitch_duration, 0.001), 0.0, 1.0) * glitch_strength;
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec2 px = glitch_pixel.x > 0.0 ? glitch_pixel : texel;
	// 兜底：CanvasGroup / 空纹理可能给出 (1,1) 之类的假像素尺寸，会采到图集其它帧
	if (px.x <= 0.0 || px.x > 0.1) { px = vec2(1.0 / 128.0, 1.0 / 128.0); }
	vec2 uv = UV;
	bool full_rect = glitch_uv_rect.z >= 0.999 && glitch_uv_rect.w >= 0.999;
	if (amount > 0.001) {
		float tick = floor(TIME * 24.0);
		// 行撕裂：部分整行水平错位
		float row = floor(uv.y / max(px.y, 1e-6));
		float h_row = glitch_hash(row * 1.37 + glitch_seed + tick * 2.7);
		if (h_row > glitch_row_gate) {
			uv.x += (h_row - (glitch_row_gate + 0.17)) * glitch_row_shift * amount * glitch_tear;
		}
		// 粗块错位：按 glitch_block_size 像素见方的块整体平移
		float block = floor(uv.x / max(px.x * glitch_block_size, 1e-6));
		float h_block = glitch_hash(block * 7.31 + glitch_seed * 1.7 + tick);
		if (h_block > 0.90) {
			uv.x += (h_block - 0.95) * glitch_block_shift * amount * glitch_tear;
		}
		if (!full_rect) {
			uv = clamp(uv, glitch_uv_rect.xy + px * 0.5, glitch_uv_rect.xy + glitch_uv_rect.zw - px * 0.5);
		}
	}
	vec2 uv_min = full_rect ? vec2(0.0) : glitch_uv_rect.xy + px * 0.5;
	vec2 uv_max = full_rect ? vec2(1.0) : glitch_uv_rect.xy + glitch_uv_rect.zw - px * 0.5;
	// 描边用原始 UV + texel，不参与故障位移/夹取，避免边缘被拉成条带
	vec2 uv_up = UV + vec2(0.0, texel.y) * outline_width;
	vec2 uv_down = UV + vec2(0.0, -texel.y) * outline_width;
	vec2 uv_left = UV + vec2(texel.x, 0.0) * outline_width;
	vec2 uv_right = UV + vec2(-texel.x, 0.0) * outline_width;

	vec4 color_up = texture(TEXTURE, uv_up);
	vec4 color_down = texture(TEXTURE, uv_down);
	vec4 color_left = texture(TEXTURE, uv_left);
	vec4 color_right = texture(TEXTURE, uv_right);

	vec4 orginal_color = texture(TEXTURE, uv);
	if (amount > 0.001) {
		// RGB 分离：红向右、青向左
		vec2 split = vec2(px.x * glitch_rgb_split * (1.0 + 2.0 * amount), 0.0);
		float r = texture(TEXTURE, clamp(uv + split, uv_min, uv_max)).r;
		float b = texture(TEXTURE, clamp(uv - split, uv_min, uv_max)).b;
		orginal_color.r = mix(orginal_color.r, r, 0.9);
		orginal_color.b = mix(orginal_color.b, b, 0.9);
		// 隔行压暗（扫描线）
		float scan_row = floor(uv.y / max(px.y, 1e-6));
		if (mod(scan_row, 2.0) < 1.0) {
			orginal_color.rgb *= 1.0 - glitch_scanline * amount;
		}
		// 偶发坏点：粗块闪成亮青白
		float h_junk = glitch_hash(scan_row * 3.7 + floor(uv.x / max(px.x * 5.0, 1e-6)) + glitch_seed * 2.3 + floor(TIME * 18.0));
		orginal_color.rgb = mix(orginal_color.rgb, vec3(0.8, 1.0, 1.0), step(glitch_junk_gate, h_junk) * amount);
	}
	orginal_color.rgb = mix(orginal_color.rgb, outline_color.rgb, flash_opacity);

	vec4 outline = color_up + color_down + color_left + color_right;
	outline.rgb = outline_color.rgb;
	outline.a = min(outline.a, 1.0);

	COLOR = mix(outline, orginal_color, orginal_color.a);
	COLOR.rgb = mix(COLOR.rgb, corruption_tint.rgb, corruption_amount);
}
