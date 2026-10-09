shader_type canvas_item;

// 瞬移强度（0 = 无效果，1 = 完全分离）
uniform float intensity : hint_range(0.0, 1.0) = 0.5;
// 瞬移方向（角度）
uniform float direction : hint_range(0.0, 360.0) = 0.0;
// 残影数量（视觉上的分段数量）
uniform int streaks : hint_range(1, 8) = 4;
// 色彩偏移强度
uniform float color_shift : hint_range(0.0, 1.0) = 0.3;
// 是否让瞬移边缘发光
uniform bool glow_edge = true;

void fragment() {
	// 原始UV坐标
	vec2 uv = UV;

	// 将角度转换为弧度并计算方向向量
	float rad = radians(direction);
	vec2 dir_vec = vec2(cos(rad), sin(rad));

	// 计算偏移强度（随intensity线性变化）
	float offset_scale = intensity * 0.15; // 最大偏移0.15个UV单位
	vec2 base_offset = dir_vec * offset_scale;

	// 最终颜色累加器
	vec4 final_color = vec4(0.0);
	float total_weight = 0.0;

	// 生成多个“瞬移片段”（残影感）
	for (int i = 0; i < streaks; i++) {
		// 计算当前片段的偏移比例
		float t = float(i) / float(max(streaks - 1, 1));
		// 非线性偏移让残影更自然
		float offset_factor = pow(t, 1.5) * intensity;
		vec2 offset = base_offset * offset_factor;

		// 当前片段UV
		vec2 sample_uv = uv - offset;

		// 边界裁剪，避免采样外部
		if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
			vec4 sample_color = texture(TEXTURE, sample_uv);

			// 片段权重 - 越靠近原始位置权重越高
			float weight = (1.0 - t) * (1.0 - intensity * 0.7);

			// 色彩偏移效果：偏移量越大，色调越偏向蓝/红
			if (color_shift > 0.0) {
			float shift_amount = t * color_shift;
			// 将色彩向青色/品红色偏移
			vec3 shifted = sample_color.rgb;
			shifted.r += shift_amount * 0.5;
			shifted.b -= shift_amount * 0.3;
			sample_color.rgb = shifted;
			}

			// 边缘发光：提高高亮部分
			if (glow_edge && t > 0.6) {
			float brightness = dot(sample_color.rgb, vec3(0.299, 0.587, 0.114));
			sample_color.rgb += vec3(0.5) * brightness * (t - 0.6) * intensity;
			}

			final_color += sample_color * weight;
			total_weight += weight;
		}
	}

	// 确保原始位置权重最高
	if (total_weight > 0.0) {
		final_color /= total_weight;
	} else {
		final_color = texture(TEXTURE, uv);
	}

	// 增加整体对比度，让瞬移更“利落”
	final_color.rgb = pow(final_color.rgb, vec3(1.0 / (1.0 - intensity * 0.3)));

	COLOR = final_color;
}