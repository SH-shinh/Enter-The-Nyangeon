shader_type canvas_item;
render_mode unshaded;

uniform float outline_width = 1.0;
uniform vec4 outline_color : source_color = vec4(0, 0, 0, 1);
uniform float flash_opacity: hint_range(0.0, 1.0, 0.1) = 0.0;
uniform float outline_glow_strength: hint_range(0.0, 20.0, 0.1) = 8.0;
uniform float hard_outline_opacity: hint_range(0.0, 1.0, 0.05) = 0.65;
uniform float soft_glow_width: hint_range(0.0, 16.0, 0.5) = 7.0;
uniform float soft_glow_opacity: hint_range(0.0, 1.0, 0.05) = 0.55;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

vec3 get_outline_color(vec3 color) {
	float max_channel = max(max(color.r, color.g), color.b);
	float uses_legacy_hdr_color = step(1.0001, max_channel);
	float safe_max_channel = max(max_channel, 0.0001);
	vec3 normalized_glow_color = clamp(
		color / safe_max_channel,
		vec3(0.0),
		vec3(1.0)
	);
	vec3 regular_outline_color = clamp(
		color,
		vec3(0.0),
		vec3(1.0)
	);

	// Match sprite_outline.gdshader exactly: legacy HDR values keep their
	// channel ratio, use a white clipped base, and reconstruct fixed glow.
	// outline_glow_strength stays declared only for scene compatibility.
	vec3 legacy_outline_color = vec3(1.0) +
		normalized_glow_color * 1.0;
	return mix(
		regular_outline_color,
		legacy_outline_color,
		uses_legacy_hdr_color
	);
}

vec3 get_flash_color(vec3 color) {
	float max_channel = max(max(color.r, color.g), color.b);
	float uses_legacy_hdr_color = step(1.0001, max_channel);
	vec3 regular_outline_color = clamp(
		color,
		vec3(0.0),
		vec3(1.0)
	);
	return mix(
		regular_outline_color,
		vec3(1.0),
		uses_legacy_hdr_color
	);
}

void fragment() {

	vec2 uv = SCREEN_UV;

	vec2 uv_up = uv + vec2(0, SCREEN_PIXEL_SIZE.y) * outline_width;
	vec2 uv_down = uv + vec2(0, -SCREEN_PIXEL_SIZE.y) * outline_width;
	vec2 uv_left = uv + vec2(SCREEN_PIXEL_SIZE.x, 0) * outline_width;
	vec2 uv_right = uv + vec2(-SCREEN_PIXEL_SIZE.x, 0) * outline_width;

	float outline_alpha = (
		texture(screen_texture, uv_up).a +
		texture(screen_texture, uv_down).a +
		texture(screen_texture, uv_left).a +
		texture(screen_texture, uv_right).a
	);
	vec3 display_outline_color = get_outline_color(outline_color.rgb);
	float soft_glow = 0.0;

	if (soft_glow_width > 0.0 && soft_glow_opacity > 0.0) {
		vec2 glow_step_1 = SCREEN_PIXEL_SIZE * (outline_width + soft_glow_width * 0.20);
		vec2 glow_step_2 = SCREEN_PIXEL_SIZE * (outline_width + soft_glow_width * 0.45);
		vec2 glow_step_3 = SCREEN_PIXEL_SIZE * (outline_width + soft_glow_width * 0.75);
		vec2 glow_step_4 = SCREEN_PIXEL_SIZE * (outline_width + soft_glow_width);
		vec2 diagonal_1 = glow_step_1 * 0.70710678;
		vec2 diagonal_2 = glow_step_2 * 0.70710678;
		vec2 diagonal_3 = glow_step_3 * 0.70710678;
		vec2 diagonal_4 = glow_step_4 * 0.70710678;

		float glow_ring_1 = (
			texture(screen_texture, uv + vec2(0.0, glow_step_1.y)).a +
			texture(screen_texture, uv + vec2(0.0, -glow_step_1.y)).a +
			texture(screen_texture, uv + vec2(glow_step_1.x, 0.0)).a +
			texture(screen_texture, uv + vec2(-glow_step_1.x, 0.0)).a +
			texture(screen_texture, uv + vec2(diagonal_1.x, diagonal_1.y)).a +
			texture(screen_texture, uv + vec2(-diagonal_1.x, diagonal_1.y)).a +
			texture(screen_texture, uv + vec2(diagonal_1.x, -diagonal_1.y)).a +
			texture(screen_texture, uv + vec2(-diagonal_1.x, -diagonal_1.y)).a
		) * 0.125;

		float glow_ring_2 = (
			texture(screen_texture, uv + vec2(0.0, glow_step_2.y)).a +
			texture(screen_texture, uv + vec2(0.0, -glow_step_2.y)).a +
			texture(screen_texture, uv + vec2(glow_step_2.x, 0.0)).a +
			texture(screen_texture, uv + vec2(-glow_step_2.x, 0.0)).a +
			texture(screen_texture, uv + vec2(diagonal_2.x, diagonal_2.y)).a +
			texture(screen_texture, uv + vec2(-diagonal_2.x, diagonal_2.y)).a +
			texture(screen_texture, uv + vec2(diagonal_2.x, -diagonal_2.y)).a +
			texture(screen_texture, uv + vec2(-diagonal_2.x, -diagonal_2.y)).a
		) * 0.125;

		float glow_ring_3 = (
			texture(screen_texture, uv + vec2(0.0, glow_step_3.y)).a +
			texture(screen_texture, uv + vec2(0.0, -glow_step_3.y)).a +
			texture(screen_texture, uv + vec2(glow_step_3.x, 0.0)).a +
			texture(screen_texture, uv + vec2(-glow_step_3.x, 0.0)).a +
			texture(screen_texture, uv + vec2(diagonal_3.x, diagonal_3.y)).a +
			texture(screen_texture, uv + vec2(-diagonal_3.x, diagonal_3.y)).a +
			texture(screen_texture, uv + vec2(diagonal_3.x, -diagonal_3.y)).a +
			texture(screen_texture, uv + vec2(-diagonal_3.x, -diagonal_3.y)).a
		) * 0.125;

		float glow_ring_4 = (
			texture(screen_texture, uv + vec2(0.0, glow_step_4.y)).a +
			texture(screen_texture, uv + vec2(0.0, -glow_step_4.y)).a +
			texture(screen_texture, uv + vec2(glow_step_4.x, 0.0)).a +
			texture(screen_texture, uv + vec2(-glow_step_4.x, 0.0)).a +
			texture(screen_texture, uv + vec2(diagonal_4.x, diagonal_4.y)).a +
			texture(screen_texture, uv + vec2(-diagonal_4.x, diagonal_4.y)).a +
			texture(screen_texture, uv + vec2(diagonal_4.x, -diagonal_4.y)).a +
			texture(screen_texture, uv + vec2(-diagonal_4.x, -diagonal_4.y)).a
		) * 0.125;

		soft_glow = glow_ring_1 * 0.40 + glow_ring_2 * 0.30 + glow_ring_3 * 0.20 + glow_ring_4 * 0.10;
	}

	outline_alpha = max(
		clamp(outline_alpha, 0.0, 1.0) * hard_outline_opacity,
		soft_glow * soft_glow_opacity
	) * outline_color.a;
	vec4 outline = vec4(display_outline_color, outline_alpha);

	vec4 original_color = texture(screen_texture, SCREEN_UV);
	original_color.rgb = mix(
		original_color.rgb,
		get_flash_color(outline_color.rgb),
		flash_opacity
	);

	float output_alpha = original_color.a +
		outline.a * (1.0 - original_color.a);
	vec3 output_rgb = mix(
		outline.rgb,
		original_color.rgb,
		original_color.a
	);
	COLOR = vec4(output_rgb, output_alpha);

}
