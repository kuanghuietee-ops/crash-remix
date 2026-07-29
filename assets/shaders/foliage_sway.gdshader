shader_type spatial;

// Vertex-only sway for the kit's plant family (palms, ferns, bushes, grass,
// canopy arches). Tier B2 of the 2026-07-29 environment review.
//
// This is the cheapest "alive vs dead" tell available: the island currently
// reads as a diorama because nothing in it moves. Cost is a handful of ALU per
// vertex and no extra passes, no extra draw calls, and no transparency.
//
// Deliberately vertex-only. The palette lives in the UVs -- each face points at
// one 256px cell of the shared atlas -- so touching UV here would slide faces
// into a neighbouring cell and repaint the piece. Motion comes from geometry.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

// Amplitude scales with height above the instance origin, so trunks and stems
// stay planted in the ground while fronds and tips carry the movement. A plant
// that slides at its base reads as sliding scenery, not wind.
uniform float sway_amplitude_m = 0.055;
uniform float sway_speed = 1.1;

void vertex() {
	// Per-instance phase from the instance's world origin, so a stand of ferns
	// does not sway in lockstep like one rigid object.
	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	float phase = fract(
		sin(dot(instance_origin.xz, vec2(12.9898, 78.233))) * 43758.5453
	) * 6.2831853;

	float height = max(VERTEX.y, 0.0);
	float t = TIME * sway_speed + phase;
	VERTEX.x += sin(t) * sway_amplitude_m * height;
	VERTEX.z += cos(t * 0.85) * sway_amplitude_m * 0.6 * height;
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	ROUGHNESS = roughness_value;
}
