shader_type canvas_item;

uniform float scroll_speed : hint_range( 0, 2) = 0.05;
uniform float angle_degrees : hint_range( 0, 360, 1) = 45.0;
uniform float repeat_x : hint_range( 1, 20, 1) = 1;
uniform float repeat_y : hint_range( 1, 20, 1) = 1;
uniform vec4 tint : source_color = vec4( 1.0 );


void fragment() {

	float angle_rad = radians(angle_degrees);
	vec2 direction = vec2(cos(angle_rad), sin(angle_rad) );
	vec2 offset_uv = UV - ( TIME * scroll_speed * direction );

	// tile
	vec2 scaled_uv = vec2(fract(offset_uv.x * repeat_x ),fract(offset_uv.y * repeat_y) );
	vec2 texelSize = vec2( 1.0 ) / vec2(textureSize( TEXTURE, 0) );
	vec2 snappedUV = round(scaled_uv / texelSize ) * texelSize;

	COLOR = texture(TEXTURE, snappedUV) * tint;


}
