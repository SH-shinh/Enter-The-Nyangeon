shader_type canvas_item;

// 单色颜料：贴图只提供 alpha mask（纯白），颜色完全由 MultiMesh 实例色决定。
// 像素化出现/消失：实例色 alpha 编码相对时间（>0 = 出生时间；<0 = -死亡时间），
// PaintGround 每帧把 now_sec 传进来，按 4px 块随机阈值逐块出现 / 反向消散。
uniform sampler2D paint_tex : source_color, filter_nearest;
uniform float now_sec = 0.0;
uniform float appear_time = 0.22;
uniform float disappear_time = 0.16;
uniform float cell_count = 32.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 tex = texture(paint_tex, UV);
	float t = COLOR.a;
	float mask = 1.0;
	float block = hash21(floor(UV * cell_count));
	if (t > 0.0) {
		float k = clamp((now_sec - t) / appear_time, 0.0, 1.0);
		mask = step(block, k);
	} else if (t < 0.0) {
		float k = clamp(1.0 - (now_sec + t) / disappear_time, 0.0, 1.0);
		mask = step(block, k);
	}
	// COLOR.rgb 是实例色（三色单色），alpha 由 mask 决定；时间码不再作为透明度输出。
	COLOR = vec4(COLOR.rgb, tex.a * mask);
}
