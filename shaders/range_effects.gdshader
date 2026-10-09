shader_type canvas_item;

uniform float ring_radius : hint_range(0.1, 0.5, 0.01) = 0.4;
uniform float thickness_scalar : hint_range(0.0, 0.99, 0.01) = 0.7;
uniform float oscillation_scalar : hint_range(0.0, 0.25, 0.005) = 0.025;
uniform float speed : hint_range(0.0, 50.0, 0.1) = 1.0;
uniform vec4 main_color : source_color = vec4(1.0,1.0,1.0,1.0);
uniform vec4 lerp_color : source_color = vec4(1.0,1.0,1.0,1.0);
uniform float transparency : hint_range(0.0, 1.0, 0.01) = 1.0;

float range_lerp(float value, float min1, float min2, float max1, float max2){
	return min2 + (max2 - min2) * ((value - min1) / (max1 - min1));
}

void fragment() {
	// Calculate the distance between the current pixel and the center of the unit
	float dist = distance(UV, vec2(0.5, 0.5));

	// Add a slight oscillation to the size of the ring
	float o = cos(TIME * speed);
	float ring_size = ring_radius + oscillation_scalar;

	// Solve for ring alpha channel
	float alpha = step(dist, ring_size) * smoothstep(ring_size * (1.0 - thickness_scalar), ring_size, dist);

	// Solve w mix amount for optional color lerping
	float w = range_lerp(o, -1.0, 1.0, 1.0, 0.0);

	// Output the final color
	COLOR = vec4(mix(main_color.rgb, lerp_color.rgb, w), alpha * transparency );
}