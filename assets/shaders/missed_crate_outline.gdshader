shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;

uniform vec4 missed_crate_outline_color : source_color = vec4(1.0, 0.82, 0.08, 1.0);
uniform float missed_crate_outline_opacity : hint_range(0.0, 1.0) = 0.95;
uniform float missed_crate_outline_edge_width_uv : hint_range(0.0, 0.5) = 0.12;
uniform float missed_crate_outline_padding_m : hint_range(0.0, 0.5) = 0.04;

void vertex() {
	VERTEX += normalize(VERTEX) * missed_crate_outline_padding_m;
}

void fragment() {
	vec2 nearest_edge = min(UV, vec2(1.0) - UV);
	float edge_distance = min(nearest_edge.x, nearest_edge.y);
	float antialias_width = max(fwidth(edge_distance), 0.001);
	float edge_mask = 1.0 - smoothstep(
		missed_crate_outline_edge_width_uv - antialias_width,
		missed_crate_outline_edge_width_uv + antialias_width,
		edge_distance
	);
	ALBEDO = missed_crate_outline_color.rgb;
	EMISSION = missed_crate_outline_color.rgb;
	ALPHA = (
		missed_crate_outline_color.a
		* missed_crate_outline_opacity
		* edge_mask
	);
}
