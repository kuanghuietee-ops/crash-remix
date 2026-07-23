shader_type spatial;
render_mode unshaded, depth_draw_never, cull_front, blend_mix;

uniform float ghost_opacity : hint_range(0.0, 1.0) = 0.3;
uniform float ghost_outline_width_m : hint_range(0.0, 0.1) = 0.02;

void vertex() {
	vec3 view_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 shell_direction = normalize(view_position - view_center);
	view_position += shell_direction * ghost_outline_width_m;
	POSITION = PROJECTION_MATRIX * vec4(view_position, 1.0);
}

void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = ghost_opacity;
}
