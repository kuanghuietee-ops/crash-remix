shader_type spatial;

// Breathing waterline for surf_foam_edge. Tier B2 of the environment review.
//
// The foam strip is the beach's focal contrast -- the brightest thing in the
// frame and the line that separates land from sea -- so it is the one piece
// where a static edge reads worst. It pulses rather than scrolls, for the same
// two-cell reason as sea_surface.gdshader: build_beach_env_kit.py paints this
// piece from the foam cell (u < 0.45 * wobble) and water_shallow beyond it, so
// no single UV rect bounds a scroll across both.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

uniform float bob_amplitude_m = 0.04;
uniform float bob_speed = 1.15;
// Foam is already the brightest surface on the beach, so this stays small; a
// strong pulse would blow the focal point around and fight the crate language.
uniform float pulse_strength : hint_range(0.0, 0.5) = 0.12;
uniform float pulse_speed = 1.6;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Runs along the shoreline so the whole waterline breathes as one body of
	// water rather than each strip bobbing independently.
	VERTEX.y += sin(world_position.z * 0.5 + TIME * bob_speed) * bob_amplitude_m;
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;

	float pulse = sin(world_position.z * 0.35 + TIME * pulse_speed) * 0.5 + 0.5;

	ALBEDO = base * (1.0 + (pulse - 0.5) * 2.0 * pulse_strength);
	ROUGHNESS = roughness_value;
}
