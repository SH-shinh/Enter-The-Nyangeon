shader_type canvas_item;
render_mode blend_add;
#include "funcs.gdshaderinc"
uniform vec3 color: source_color;
uniform float num_cells: hint_range(2.0, 50.0, 1.0) = 10.0;
uniform float speed: hint_range(0.1, 10.0, 0.01) = 1.0;
uniform float smoothness: hint_range(0.5, 2.0, 0.01) = 0.5;
uniform float angle: hint_range(0.0, 360.0) = 45.0;
uniform float size;

void fragment() {

	vec2 igrd = floor( UV * num_cells ) / num_cells;

	igrd = rotation(igrd, vec2(0.5), angle * PI / 180.0);
	igrd.x += 2.0 - mod(TIME * speed, 4.0);

	vec2 fgrid = fract( UV * num_cells );

	float rect_mask = rectanglef(igrd, 0.001, 2.0, smoothness);

	float grid_mask = 1.0 - rectangle(fgrid, rect_mask, rect_mask);

	float emission_mask = 1.0 - rectangle(fgrid, rect_mask + size, rect_mask + size) - grid_mask;

	vec4 c = texture(TEXTURE, UV);

	float gray = dot(c.rgb, vec3(0.299,0.587,0.114));
	float bw = step(0.05, gray);

	vec3 tex = texture(TEXTURE, UV).rgb;

	COLOR = vec4(tex, emission_mask * bw);


}
