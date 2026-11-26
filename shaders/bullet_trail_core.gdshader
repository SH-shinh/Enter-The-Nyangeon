shader_type canvas_item;

// 单线双色拖尾：外线保留 Line2D 的长度渐变（顶点色 COLOR），中心叠一条胶囊内芯。
// 内芯不是按 UV.y 画的——Line2D 的圆头 cap 里 UV 映射的是圆弧，按宽度着色会得到平头；
// 这里用「局部坐标到拖尾弦的距离」做圆头胶囊：身体是直条，两端是半径 core_half 的半圆。
// tail_pos/head_pos/core_half_* 由 scenes/line.gd 每采样写入（每条线独立材质）。
uniform vec4 core_color : source_color = vec4(1.0);
// 边界羽化（px）；像素风默认 0 = 硬边。
uniform float core_softness : hint_range(0.0, 4.0) = 0.0;
uniform vec2 tail_pos = vec2(0.0);
uniform vec2 head_pos = vec2(1.0);
// 内芯半宽（px）：尾部/头部，用旧内线的 width_curve（0.527→0.670）还原收尖。
uniform float core_half_tail = 1.84;
uniform float core_half_head = 2.35;

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 seg = head_pos - tail_pos;
	float len2 = dot(seg, seg);
	float t = len2 > 0.0001 ? clamp(dot(v_local - tail_pos, seg) / len2, 0.0, 1.0) : 0.0;
	float hw = mix(core_half_tail, core_half_head, t);
	float d = distance(v_local, tail_pos + seg * t);
	float core;
	if (core_softness > 0.001) {
		core = 1.0 - smoothstep(hw - core_softness, hw + core_softness, d);
	} else {
		core = step(d, hw);
	}
	COLOR.rgb = mix(COLOR.rgb, core_color.rgb, core);
	COLOR.a = max(COLOR.a, core * core_color.a);
}
