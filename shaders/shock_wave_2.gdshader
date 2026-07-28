shader_type canvas_item;

uniform vec2 center;
uniform float size;
uniform float thickness;

void fragment() {

	float ratio = TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y;
	vec2 scaledUV = ( UV - vec2(0.5, 0.0) ) / vec2(ratio, 1.0) + vec2(0.5, 0.0) ;
	float mask = (1.0 - smoothstep(size - thickness, size,length(scaledUV - center) )) *
	smoothstep(size - thickness * 2.0, size - thickness,length(scaledUV - center) );

	COLOR = vec4(COLOR.rgb, mask);
}
