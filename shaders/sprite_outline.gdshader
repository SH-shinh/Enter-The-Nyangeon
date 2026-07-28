shader_type canvas_item;
render_mode unshaded;

// Keep these legacy uniforms unchanged so existing scene parameters and
// animation tracks continue to work.
uniform float outline_width = 1.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float flash_opacity : hint_range(0.0, 1.0, 0.01) = 0.0;

// Caps the HDR energy reconstructed from legacy colors such as (22, 20, 28).
uniform float outline_glow_strength : hint_range(0.0, 40.0, 0.1) = 20.0;
uniform float outline_glow_pulse : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
	vec2 uv = UV;
	vec4 original_color = texture(TEXTURE, uv);

	float max_channel = max(
		max(outline_color.r, outline_color.g),
		outline_color.b
	);
	float uses_legacy_hdr_color = step(1.0001, max_channel);
	float safe_max_channel = max(max_channel, 0.0001);

	// Preserve the old parameter input, but use only its RGB ratio as the glow
	// hue. The original magnitude is never sent to Godot 4.7's HDR buffer.
	vec3 normalized_glow_color = clamp(
		outline_color.rgb / safe_max_channel,
		vec3(0.0),
		vec3(1.0)
	);
	vec3 regular_outline_color = clamp(
		outline_color.rgb,
		vec3(0.0),
		vec3(1.0)
	);

	// A white base recreates the old clipped outline. The capped colored HDR
	// excess is carried by the same pixels so WorldEnvironment Glow can bloom
	// it without adding a second, thicker outline mask.
	vec3 legacy_outline_color = vec3(1.0) +
		normalized_glow_color * outline_glow_strength * outline_glow_pulse;
	vec3 display_outline_color = mix(
		regular_outline_color,
		legacy_outline_color,
		uses_legacy_hdr_color
	);
	vec3 flash_color = mix(
		regular_outline_color,
		vec3(1.0),
		uses_legacy_hdr_color
	);

	vec2 pixel_step = TEXTURE_PIXEL_SIZE * outline_width;
	float outline_alpha = (
		texture(TEXTURE, uv + vec2(0.0, pixel_step.y)).a +
		texture(TEXTURE, uv + vec2(0.0, -pixel_step.y)).a +
		texture(TEXTURE, uv + vec2(pixel_step.x, 0.0)).a +
		texture(TEXTURE, uv + vec2(-pixel_step.x, 0.0)).a
	);
	outline_alpha = clamp(outline_alpha, 0.0, 1.0) * outline_color.a;

	vec4 outline = vec4(display_outline_color, outline_alpha);
	original_color.rgb = mix(
		original_color.rgb,
		flash_color,
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
