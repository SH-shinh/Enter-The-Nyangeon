shader_type canvas_item;
render_mode unshaded;

// outline_width 的单位是“设计像素”(640x360)，1.0 即 1 个设计像素。
// 偏移量直接用设计分辨率换算，因此与窗口/设备实际分辨率无关，
// 不需要再靠 GDScript 轮询窗口尺寸来补偿。
uniform float outline_width = 1.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float flash_opacity : hint_range(0.0, 1.0, 0.1) = 0.0;
uniform vec2 design_size = vec2(640.0, 360.0);

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec2 uv = SCREEN_UV;

	vec2 step_uv = outline_width / design_size;
	vec2 uv_up = uv + vec2(0.0, step_uv.y);
	vec2 uv_down = uv - vec2(0.0, step_uv.y);
	vec2 uv_left = uv - vec2(step_uv.x, 0.0);
	vec2 uv_right = uv + vec2(step_uv.x, 0.0);

	vec4 color_up = texture(screen_texture, uv_up);
	vec4 color_down = texture(screen_texture, uv_down);
	vec4 color_left = texture(screen_texture, uv_left);
	vec4 color_right = texture(screen_texture, uv_right);

	vec4 outline = color_up + color_down + color_left + color_right;

	outline.rgb = outline_color.rgb;

	outline.a = min(outline.a, 1.0);

	vec4 orginal_color = texture(screen_texture, SCREEN_UV);
	orginal_color.rgb = mix(orginal_color.rgb, outline_color.rgb, flash_opacity);

	COLOR = mix(outline, orginal_color, orginal_color.a);
}
