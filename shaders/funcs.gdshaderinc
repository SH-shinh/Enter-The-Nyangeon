float circle(vec2 uv, float radius, float feather)
{
	return smoothstep(radius, radius + feather, length(uv - vec2(0.5)));
}

float rectangle (vec2 uv, float width, float height){
	vec2 uv_cartesian = uv * 2.0 - 1.0;
	vec2 uv_reflected = abs(uv_cartesian);
	float dfx = step(width,uv_reflected.x);
	float dfy = step(height, uv_reflected.y);
	return max(dfx,dfy);
}
float rectanglef (vec2 uv, float width, float height, float feather){
	vec2 uv_cartesian = uv * 2.0 - 1.0;
	vec2 uv_reflected = abs(uv_cartesian);
	float dfx = smoothstep(width,width+feather,uv_reflected.x);
	float dfy = smoothstep(height,height+feather,uv_reflected.y);
	return max(dfx,dfy);
}

float polygon(vec2 uv, float width, int sides)
{
	uv = uv * 2.0 - 1.0;
	float angle = atan(uv.x, uv.y);
	float radius = TAU / float(sides);
	float dist = cos(floor(0.5 + angle / radius) * radius - angle)* length(uv) ;
	float poly = step(width, dist);
	return poly;
}
vec2 polar_coordinates(vec2 uv, vec2 center)
{
	vec2 dir = uv - center;
	float radius = length(dir) * 2.0;
	float angle = atan(dir.y, dir.x) / TAU;
	return (vec2(radius, angle));
}
vec2 rotation ( vec2 uv, vec2 center, float angle){
	mat2 rotation = mat2(
					vec2(cos(angle), -sin(angle)),
					vec2(sin(angle), cos(angle))
					);
	uv -= center;
	uv *= rotation;
	uv += center;
	return uv;
}
vec2 scale(vec2 uv, float x, float y)
{
	mat2 scale = mat2(
				vec2(x, 0.0),
				vec2(0.0, y)
				);

	uv -= 0.5;
	uv = uv * scale;
	uv += 0.5;
	return uv;
}
float angleVectors(vec3 v1, vec3 v2){
	return acos(dot(normalize(v1),normalize(v2)));
}

float random (vec2 st) {
    return fract(sin(dot(st.xy,
                      vec2(12.9898,78.233))) * 43758.5453123);
}
float random1D(float x){
	return fract(sin(x) * 100000.0);
}
