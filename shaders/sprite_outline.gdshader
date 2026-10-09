shader_type canvas_item;

uniform float outline_width = 1.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float flash_opacity : hint_range(0.0, 1.0, 0.1) = 0.0;

void fragment() {
	vec2 uv = UV;

	vec2 uv_up = uv + vec2(0.0, TEXTURE_PIXEL_SIZE.y) * outline_width;
	vec2 uv_down = uv + vec2(0.0, -TEXTURE_PIXEL_SIZE.y) * outline_width;
	vec2 uv_left = uv + vec2(TEXTURE_PIXEL_SIZE.x, 0.0) * outline_width;
	vec2 uv_right = uv + vec2(-TEXTURE_PIXEL_SIZE.x, 0.0) * outline_width;

	vec4 color_up = texture(TEXTURE, uv_up);
	vec4 color_down = texture(TEXTURE, uv_down);
	vec4 color_left = texture(TEXTURE, uv_left);
	vec4 color_right = texture(TEXTURE, uv_right);

	vec4 outline = color_up + color_down + color_left + color_right;

	outline.rgb = outline_color.rgb;

	outline.a = min(outline.a, 1.0);

	vec4 orginal_color = texture(TEXTURE, UV);
	orginal_color.rgb = mix(orginal_color.rgb, outline_color.rgb, flash_opacity);

	COLOR = mix(outline, orginal_color, orginal_color.a);
}
