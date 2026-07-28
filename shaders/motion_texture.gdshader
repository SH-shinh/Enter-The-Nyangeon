shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float f : hint_range(0.0, 5.0);
uniform float v : hint_range(0.0, 100.0);
uniform bool grayscale ;

void fragment(){

	COLOR.rgb = texture(TEXTURE,UV,f).rgb;
	if (grayscale == true) {
		float a = (COLOR.r + COLOR.g + COLOR.b) / 3.0;
		float b = a * v * a;
		COLOR.rgb = vec3(b);
		}
}
