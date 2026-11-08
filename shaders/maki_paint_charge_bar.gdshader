shader_type canvas_item;
render_mode unshaded;

// Maki 颜料充能条：普通方框容器 + 从底部上涨的液面 + 正弦波动 + 颜色周期变化。
// 仿 frenzy_effect.tscn 的 BurnBar 用法：ColorRect + ShaderMaterial，progress/fill 由脚本写 uniform。

uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform vec2 size_px = vec2(16.0, 24.0);
uniform float border_px : hint_range(0.0, 4.0) = 1.0;
uniform vec4 frame_color : source_color = vec4(0.95, 0.95, 1.0, 0.9);
uniform vec4 inner_color : source_color = vec4(0.05, 0.05, 0.08, 0.75);
uniform vec3 paint_a : source_color = vec3(1.0, 0.612, 0.753);
uniform vec3 paint_b : source_color = vec3(0.482, 0.851, 0.902);
uniform vec3 paint_c : source_color = vec3(0.902, 0.780, 0.302);
uniform float cycle_period : hint_range(1.0, 30.0) = 6.0;
uniform float wave_amp : hint_range(0.0, 0.3) = 0.05;
uniform float wave_freq : hint_range(0.0, 20.0) = 2.0;
uniform float wave_speed : hint_range(0.0, 10.0) = 2.5;
uniform vec4 crest_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);

vec3 paint_cycle(float t) {
	float u = fract(t / cycle_period) * 3.0;
	if (u < 1.0) {
		return mix(paint_a, paint_b, u);
	}
	if (u < 2.0) {
		return mix(paint_b, paint_c, u - 1.0);
	}
	return mix(paint_c, paint_a, u - 2.0);
}

void fragment() {
	vec2 size = max(size_px, vec2(1.0));
	vec2 px = UV * size;
	float b = clamp(border_px, 0.0, min(size.x, size.y) * 0.5);
	float inside = step(b, px.x) * step(px.x, size.x - b) * step(b, px.y) * step(px.y, size.y - b);
	float frame = 1.0 - inside;

	float f = clamp(fill, 0.0, 1.0);
	float surface = mix(size.y - b, b, f);
	float wave = sin(px.x / size.x * wave_freq * TAU + TIME * wave_speed) * wave_amp * size.y;
	float surface_y = surface + wave;
	float has_liquid = step(0.001, f);
	float liquid = inside * smoothstep(surface_y - 0.5, surface_y + 0.5, px.y) * has_liquid;
	float crest = (1.0 - smoothstep(0.0, 0.9, abs(px.y - surface_y))) * inside * has_liquid;

	vec3 liquid_rgb = paint_cycle(TIME);
	float depth = clamp((px.y - surface_y) / max(size.y - 2.0 * b, 1.0), 0.0, 1.0);
	liquid_rgb *= mix(1.08, 0.82, depth);

	vec3 col = inner_color.rgb;
	float alpha = inner_color.a * inside;
	col = mix(col, liquid_rgb, liquid);
	alpha = max(alpha, liquid);
	col = mix(col, crest_color.rgb, crest * crest_color.a);
	alpha = max(alpha, crest * crest_color.a);
	col = mix(col, frame_color.rgb, frame);
	alpha = max(alpha, frame * frame_color.a);

	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
