shader_type canvas_item;

uniform float outline_width = 1.0;

uniform float speed : hint_range(0.1, 10.0) = 1.0; // 缩放速度
uniform float amplitude : hint_range(0.1, 100.0) = 1.0; // 缩放幅度
uniform float scroll_speed : hint_range( 0, 2) = 0.05;
uniform float angle_degrees : hint_range( 0, 360, 1) = 45.0;
uniform float repeat_x : hint_range( 1, 100, 1) = 1;
uniform float repeat_y : hint_range( 1, 100, 1) = 1;
uniform float num_uv : hint_range( 0.1, 10) = 1;
uniform vec4 tint : source_color = vec4( 1.0 );

uniform float scale = 2.0; // 缩放比例
uniform vec2 center = vec2(0.5, 0.5); // 缩放中心（UV 空间中的比例）


void fragment() {
	vec2 centered_uv = UV - center;
	centered_uv *= scale ; // 应用缩放
    centered_uv += center; // 将中心移回原来的位置
	float angle_rad = radians(angle_degrees);
	vec2 direction = vec2(cos(angle_rad), sin(angle_rad) );
	vec2 offset_uv = UV - ( TIME * scroll_speed * direction );
	//offset_uv *= UV * speed + center;
	offset_uv += center;
	//offset_uv.x += 1.0;
	//offset_uv.y += 0.1;
	vec2 uv = UV;

	vec2 uv_up = uv + vec2(0, TEXTURE_PIXEL_SIZE.y) * outline_width;
	vec2 uv_down = uv + vec2(0, -TEXTURE_PIXEL_SIZE.y) * outline_width;
	vec2 uv_left = uv + vec2(TEXTURE_PIXEL_SIZE.x, 0) * outline_width;
	vec2 uv_right = uv + vec2(-TEXTURE_PIXEL_SIZE.x, 0) * outline_width;
     // 将中心移动到UV坐标的0,0

	//offset_uv *= centered_uv;
    vec4 color = texture(TEXTURE, centered_uv); // 使用修改后的UV坐标采样纹理
    //COLOR = color;
	// tile
	float time = TIME * speed; // 使用全局时间变量TIME和速度参数
	float scale_factor = amplitude * (sin(time) + 1.0) * 0.5; // 使用正弦函数生成循环缩放
	vec2 scaled_uv = vec2(fract(offset_uv.x * repeat_x ),fract(offset_uv.y * repeat_y) );
	float uv_denom = max(UV.x * UV.y, 1e-4) * max(UV.x * UV.y, 1e-4) * num_uv;
	scaled_uv /= uv_denom;

	//scaled_uv *= uv_up + uv_down + uv_right + uv_left ;

	//scaled_uv.x = mod(scaled_uv.x / (TIME + speed), 1.0);
	//scaled_uv.y = mod(scaled_uv.y / (TIME + speed), 1.0);
	vec2 texelSize = vec2( 1.0 ) / vec2(textureSize( TEXTURE, 0) );
	vec2 snappedUV = round(scaled_uv / texelSize ) * texelSize;
	//snappedUV *= UV  * speed + center;
	//snappedUV += center;

	COLOR = texture(TEXTURE, snappedUV) * tint;


}
