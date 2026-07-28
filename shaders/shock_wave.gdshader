shader_type canvas_item;

uniform vec2 center;
uniform float force;
uniform float size;
uniform float thickness;
uniform float strength = 1.0;
uniform float color_add;
uniform sampler2D offset_image : hint_default_white;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;


void fragment() {

	float ratio = SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y;
	vec2 scaledUV = ( SCREEN_UV - vec2(0.5, 0.0) ) / vec2(ratio, 1.0) + vec2(0.5, 0.0) ;
	float mask = (1.0 - smoothstep(size - thickness, size,length(scaledUV - center) )) *
	smoothstep(size - thickness * 2.0, size - thickness,length(scaledUV - center) );
	vec2 disp = normalize(scaledUV - center) * force * mask;

	vec2 offsetUV = SCREEN_UV - disp;

	vec4 output = texture(screen_texture , offsetUV);

	float shift = strength * texture(offset_image, offsetUV).r / 100.0;
	output.r = texture(screen_texture, vec2(offsetUV.x + shift * mask, offsetUV.y)).r + color_add * mask;
	output.g = texture(screen_texture, offsetUV).g + color_add * mask;
	output.b = texture(screen_texture, vec2(offsetUV.x - shift * mask, offsetUV.y)).b + color_add * mask;

	COLOR = output;

}
