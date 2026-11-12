shader_type canvas_item;

// 地面颜料：所有颜料块共用一个 MultiMesh（单 draw call），
// 实例色（MultiMesh.use_colors）乘到顶点色 COLOR，再乘共享的喷溅贴图。
// 每个实例的变换只负责位置 / 旋转 / 缩放 / 翻转，UV 由 QuadMesh 提供。

uniform sampler2D paint_tex : source_color, filter_nearest;

void fragment() {
	vec4 tex = texture(paint_tex, UV);
	// COLOR = 顶点色（含 MultiMesh 实例色与 CanvasItem modulate）
	COLOR = vec4(tex.rgb * COLOR.rgb, tex.a * COLOR.a);
}
